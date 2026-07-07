import Foundation

public struct AppshotPromptContext: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String
    public var windowTitle: String?
    public var axTree: String
    public var imageName: String?
    public var imagePath: String?
    public var imageDataURL: String?

    public init(
        appName: String,
        bundleIdentifier: String,
        windowTitle: String?,
        axTree: String,
        imageName: String?,
        imagePath: String? = nil,
        imageDataURL: String? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.axTree = axTree
        self.imageName = imageName
        self.imagePath = imagePath
        self.imageDataURL = imageDataURL
    }
}

public enum AppshotPromptCodec {
    public static func render(_ context: AppshotContext) -> String {
        var attributes = [
            #"app="\#(xmlEscaped(context.appName))""#,
            #"bundle-identifier="\#(xmlEscaped(context.bundleIdentifier))""#,
        ]

        if let windowTitle = context.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           windowTitle.isEmpty == false {
            attributes.append(#"window-title="\#(xmlEscaped(windowTitle))""#)
        }

        if let imageName = context.imageName ?? context.imagePath {
            attributes.append(#"image="\#(xmlEscaped(imageName))""#)
        }

        return """
        <appshot \(attributes.joined(separator: " "))>
        \(bodyEscaped(context.axTree))
        </appshot>
        """
    }

    public static func parseAppshots(in text: String) -> [AppshotPromptContext] {
        let nsText = text as NSString
        return appshotRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let attributes = attributeMap(
                from: string(in: nsText, match: match, index: 1)
                    ?? string(in: nsText, match: match, index: 3)
                    ?? ""
            )
            guard let appName = attributes["app"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  appName.isEmpty == false,
                  let bundleIdentifier = attributes["bundle-identifier"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  bundleIdentifier.isEmpty == false
            else {
                return nil
            }

            let axTree = bodyUnescaped(
                (string(in: nsText, match: match, index: 2) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard axTree.isEmpty == false else {
                return nil
            }

            let image = attributes["image"]
            return AppshotPromptContext(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: attributes["window-title"],
                axTree: axTree,
                imageName: image,
                imagePath: image
            )
        }
    }

    public static func stripAppshots(from text: String) -> String {
        appshotRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func pairAppshots(
        in text: String,
        imageSources: [String],
        commentImageCount: Int = 0
    ) -> (nonAppshotImageSources: [String], appshotContexts: [AppshotPromptContext]) {
        let contexts = parseAppshots(in: text)
        guard contexts.isEmpty == false, imageSources.isEmpty == false else {
            return (imageSources, contexts)
        }

        // Trailing comment images are never appshot screenshots: cap the
        // pairable pool at the sources remaining once they're excluded, or a
        // shortfall of appshot images would pair a comment image instead.
        let pairCount = min(contexts.count, max(imageSources.count - commentImageCount, 0))
        let leadingImageCount = max(imageSources.count - commentImageCount - pairCount, 0)
        let pairedSources = Array(imageSources.dropFirst(leadingImageCount).prefix(pairCount))
        let pairedContexts = contexts.enumerated().map { index, context in
            guard pairedSources.indices.contains(index) else {
                return context
            }

            var paired = context
            let source = pairedSources[index]
            if source.range(of: #"^data:image/"#, options: .regularExpression) != nil {
                paired.imageDataURL = source
            } else {
                paired.imagePath = source
            }
            return paired
        }

        return (
            Array(imageSources.prefix(leadingImageCount)) + Array(imageSources.dropFirst(leadingImageCount + pairCount)),
            pairedContexts
        )
    }

    private static let appshotRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"<appshot\b([^>]*)>([\s\S]*?)</appshot>|<appshot\b([^>]*)>"#,
            options: []
        )
    }()

    private static let attributeRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"([A-Za-z][A-Za-z0-9-]*)="([^"]*)""#,
            options: []
        )
    }()

    private static func attributeMap(from text: String) -> [String: String] {
        let nsText = text as NSString
        var result: [String: String] = [:]
        for match in attributeRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let key = string(in: nsText, match: match, index: 1),
                  let value = string(in: nsText, match: match, index: 2)
            else {
                continue
            }
            result[key] = attributeUnescaped(value)
        }
        return result
    }

    private static func string(in text: NSString, match: NSTextCheckingResult, index: Int) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return text.substring(with: range)
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func bodyEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func attributeUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func bodyUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

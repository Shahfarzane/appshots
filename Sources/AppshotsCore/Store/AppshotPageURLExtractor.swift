import Foundation

extension AppshotStore {
    func extractPageURL(
        appName: String,
        bundleID: String,
        appStateText: String,
        structuredState: CapturedAppState?
    ) -> String? {
        // Structured-state extraction keys off address-bar / web-area URLs, so
        // it is reliable for any URL-bearing app — browsers plus Electron and
        // web-view apps (Figma, Slack, Notion, VS Code).
        if let structuredURL = structuredState.flatMap(extractPageURLFromStructuredState) {
            return structuredURL
        }

        // The text fallback is a fuzzy regex over formatted output, so it stays
        // gated to browsers where a URL value is reliably present.
        guard isBrowser(appName: appName, bundleID: bundleID) else {
            return nil
        }
        return extractPageURLFromText(appStateText)
    }

    private func isBrowser(appName: String, bundleID: String) -> Bool {
        let haystack = "\(appName) \(bundleID)".lowercased()
        return haystack.contains("safari") ||
            haystack.contains("chrome") ||
            haystack.contains("chromium") ||
            haystack.contains("arc") ||
            haystack.contains("firefox") ||
            haystack.contains("browser")
    }

    private func extractPageURLFromStructuredState(_ state: CapturedAppState) -> String? {
        let addressSignals = ["address", "search", "location", "url", "omnibox", "web_browser_address"]

        for node in state.nodes {
            let descriptor = [
                node.role,
                node.title,
                node.description,
                node.help,
                node.identifier,
            ].joined(separator: " ").lowercased()

            guard addressSignals.contains(where: { descriptor.contains($0) }) else {
                continue
            }

            for candidate in [node.value, node.url, node.title, node.description] {
                if let url = normalizedPageURL(candidate) {
                    return url
                }
            }
        }

        for node in state.nodes {
            if let url = normalizedPageURL(node.url) {
                return url
            }
        }

        return nil
    }

    private func extractPageURLFromText(_ text: String) -> String? {
        let patterns = [
            #"HTML content URL:\s*([^,\n]+)"#,
            #"Value:\s*(https?://[^,\n ]+)"#,
            #"Value:\s*([A-Za-z0-9.-]+\.[A-Za-z]{2,}[^,\n ]*)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let matchRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }
            if let url = normalizedPageURL(String(text[matchRange])) {
                return url
            }
        }

        return nil
    }

    private func normalizedPageURL(_ candidate: String?) -> String? {
        guard var candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              candidate.isEmpty == false
        else {
            return nil
        }

        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>.,"))
        if candidate.contains("://"),
           candidate.hasPrefix("http://") == false,
           candidate.hasPrefix("https://") == false {
            return nil
        }
        if candidate.hasPrefix("http://") == false,
           candidate.hasPrefix("https://") == false {
            guard candidate.contains("."),
                  candidate.contains(" ") == false
            else {
                return nil
            }
            candidate = "https://\(candidate)"
        }

        guard let components = URLComponents(string: candidate),
              components.scheme?.hasPrefix("http") == true,
              components.host?.isEmpty == false
        else {
            return nil
        }

        return candidate
    }
}

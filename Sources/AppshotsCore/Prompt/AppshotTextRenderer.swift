import Foundation

extension AppshotStore {
    func codexStyleAppshotText(record: AppshotRecord, appStateText: String) -> String {
        let imageName = record.screenshotURL?.lastPathComponent ?? ""
        return """
        # Applications mentioned by the user:

        <appshot app="\(xmlEscaped(record.appName))" bundle-identifier="\(xmlEscaped(record.bundleID))" window-title="\(xmlEscaped(record.windowTitle))" image="\(xmlEscaped(imageName))" screenshot-path="\(xmlEscaped(record.screenshotPath ?? ""))" content-path="\(xmlEscaped(record.axTextPath))" json-path="\(xmlEscaped(record.axJSONPath ?? ""))" diagnostics-path="\(xmlEscaped(record.captureDiagnosticsPath ?? ""))" metadata-path="\(xmlEscaped(record.metadataPath))">
        Window: "\(record.windowTitle)", App: \(record.appName).
        Bundle identifier: \(record.bundleID)
        Process ID: \(record.pid)
        Window ID: \(record.windowID)
        Window frame: x=\(Int(record.windowFrame.origin.x)) y=\(Int(record.windowFrame.origin.y)) width=\(Int(record.windowFrame.size.width)) height=\(Int(record.windowFrame.size.height))
        \(screenshotSizeLine(record.screenshotSize))
        \(pageURLLine(record.pageURL))
        \(captureDiagnosticsLine(record.captureDiagnosticsPath))
        Capture directory: \(record.directoryPath)

        \(trimAppStateForAppshot(appStateText))
        </appshot>
        """
    }

    func modelFacingAppshotText(record: AppshotRecord, appStateText: String) -> String {
        let axTree = [
            record.pageURL.map { "Page URL: \($0)" },
            trimAppStateForAppshot(appStateText),
        ].compactMap { $0 }
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .joined(separator: "\n\n")
        let context = AppshotContext(
            appName: record.appName,
            bundleIdentifier: record.bundleID,
            windowTitle: record.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : record.windowTitle,
            axTree: axTree,
            imageName: record.screenshotURL?.lastPathComponent,
            imagePath: record.screenshotPath,
            imageDataURL: nil,
            metadata: record
        )
        return """
        # Applications mentioned by the user:

        \(AppshotPromptCodec.render(context))
        """
    }

    private func screenshotSizeLine(_ size: CGSize?) -> String {
        guard let size else {
            return "Screenshot: not captured"
        }
        return "Screenshot size: \(Int(size.width))x\(Int(size.height))"
    }

    private func pageURLLine(_ pageURL: String?) -> String {
        guard let pageURL else {
            return "Page URL: not captured"
        }
        return "Page URL: \(pageURL)"
    }

    private func captureDiagnosticsLine(_ path: String?) -> String {
        guard let path else {
            return "Capture diagnostics: not captured"
        }
        return "Capture diagnostics: \(path)"
    }

    func trimAppStateForAppshot(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("<app_state") == false &&
                    trimmed != "</app_state>" &&
                    trimmed.hasPrefix("Screenshot: ") == false &&
                    trimmed.hasPrefix("ScreenshotSize: ") == false
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

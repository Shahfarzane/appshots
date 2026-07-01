@testable import AppshotsCore
import CoreGraphics
import Foundation
import Testing

struct AppshotStoreTests {
    @Test func `Save writes agent artifacts and latest pointers`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        let output = CaptureOutput(
            text: """
            <app_state surface="window">
            Window: "Example Window", App: Safari.
            text field Description: smart search field, Value: https://example.com/docs
            button Open
            </app_state>
            """,
            metadata: metadata()
        )

        let record = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: output
        )

        #expect(FileManager.default.fileExists(atPath: record.axTextPath))
        #expect(FileManager.default.fileExists(atPath: record.appshotTextPath))
        #expect(FileManager.default.fileExists(atPath: record.metadataPath))
        #expect(record.pageURL == "https://example.com/docs")
        #expect(FileManager.default.fileExists(atPath: record.pageURLPath ?? ""))
        #expect(try String(contentsOf: store.latestTextURL, encoding: .utf8) == record.directoryPath)
        let latestPrompt = try String(contentsOf: store.latestPromptURL, encoding: .utf8)
        #expect(latestPrompt.contains("<appshot app=\"Safari\""))
        #expect(!latestPrompt.contains("screenshot-path="))
        #expect(FileManager.default.fileExists(atPath: record.debugTextPath ?? ""))
        #expect(FileManager.default.fileExists(atPath: record.directoryURL.appendingPathComponent("context.json").path))
        let modelPrompt = try store.modelPrompt(for: record)
        #expect(modelPrompt.contains("<appshot app=\"Safari\" bundle-identifier=\"com.apple.Safari\" window-title=\"Example Window\">"))
        #expect(!modelPrompt.contains("screenshot-path="))
        #expect(!modelPrompt.contains("content-path="))
        #expect(!modelPrompt.contains("metadata-path="))
        let context = try store.appshotContext(for: record)
        #expect(context.type == "appshot")
        #expect(context.appName == "Safari")
        #expect(context.bundleIdentifier == "com.apple.Safari")
        #expect(context.windowTitle == "Example Window")
        #expect(context.axTree.contains("button Open"))
        #expect(!context.axTree.contains("<app_state"))
        let payload = try store.payload(for: record)
        #expect(payload.context == context)
        #expect(payload.text == modelPrompt)
        #expect(store.latestCapture()?.id == record.id)
        #expect(store.searchCaptures(query: "example.com").first?.id == record.id)
    }

    @Test func `Save persists metrics when recorder is supplied`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        let recorder = AppshotCaptureMetricsRecorder(requestID: "metrics-test", coldStart: false)
        recorder.mark("hotkey received")
        let record = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: Metrics", metadata: metadata()),
            metricsRecorder: recorder
        )

        let metrics = try store.captureMetrics(for: record)
        #expect(record.captureMetricsPath?.hasSuffix("capture_metrics.json") == true)
        #expect(metrics.requestID == "metrics-test")
        #expect(metrics.phases.contains { $0.name == "hotkey received" })
        #expect(metrics.phases.contains { $0.name == "final artifact write" })
    }

    @Test func `Text only status surface is persisted without screenshot`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let statusState = CapturedAppState(
            metadata: metadata(title: "Status Items"),
            surface: "status",
            focusedElementIndex: nil,
            selectedText: nil,
            nodes: [
                node(0, parent: nil, depth: 0, role: "AXMenuBarItem", title: "Appshots"),
            ]
        )
        let store = AppshotStore(rootURL: rootURL)
        let record = try store.save(
            target: FrontmostAppTarget(name: "Appshots", bundleID: "ceo.nerd.appshots", pid: 42),
            output: CaptureOutput(text: "fallback", metadata: metadata(title: "Status Items")),
            structuredState: statusState
        )

        #expect(record.surface == .status)
        #expect(record.screenshotPath == nil)
        #expect(try store.modelPrompt(for: record).contains("Surface: status"))
    }

    @Test func `Open menu surface is persisted as text only appshot`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let menuState = CapturedAppState(
            metadata: metadata(title: "Example Window"),
            surface: "menu",
            focusedElementIndex: nil,
            selectedText: nil,
            nodes: [
                node(0, parent: nil, depth: 0, role: "AXMenu", title: "File"),
                node(1, parent: 0, depth: 1, role: "AXMenuItem", title: "Export Appshot"),
            ]
        )
        let store = AppshotStore(rootURL: rootURL)
        let record = try store.save(
            target: FrontmostAppTarget(name: "Appshots", bundleID: "ceo.nerd.appshots", pid: 42),
            output: CaptureOutput(text: "fallback", metadata: metadata(title: "Example Window")),
            structuredState: menuState
        )

        #expect(record.surface == .menu)
        #expect(record.screenshotPath == nil)
        #expect(try store.modelPrompt(for: record).contains("Surface: menu"))
        #expect(try store.modelPrompt(for: record).contains("Export Appshot"))
    }

    @Test func `Cursor like webview and file explorer fixture renders`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = CapturedAppState(
            metadata: metadata(title: "main.swift - Appshots"),
            focusedElementIndex: 4,
            selectedText: "func captureFrontmostApp()",
            nodes: [
                node(0, parent: nil, depth: 0, role: "AXWindow", subrole: "AXStandardWindow", title: "main.swift - Appshots"),
                node(1, parent: 0, depth: 1, role: "AXGroup", description: "Explorer"),
                node(2, parent: 1, depth: 2, role: "AXStaticText", value: "Sources/Appshots/AppshotsModel.swift"),
                node(3, parent: 0, depth: 1, role: "AXWebArea", title: "Editor", url: "vscode-file://main.swift"),
                node(4, parent: 3, depth: 2, role: "AXTextArea", value: "func captureFrontmostApp()", focused: true, isValueSettable: true),
            ]
        )
        let store = AppshotStore(rootURL: rootURL)
        let record = try store.save(
            target: FrontmostAppTarget(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", pid: 42),
            output: CaptureOutput(text: "fallback", metadata: metadata(title: "main.swift - Appshots")),
            structuredState: state
        )

        let prompt = try store.modelPrompt(for: record)
        #expect(prompt.contains("Sources/Appshots/AppshotsModel.swift"))
        #expect(prompt.contains("HTML content Editor"))
        #expect(prompt.contains("Selected text"))
    }

    @Test func `Prompt codec parses, strips, and pairs appshots with images`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        let record = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(
                text: "Window: \"A < B\", App: Safari.\nbutton Continue & Save",
                metadata: metadata(title: "A < B")
            )
        )
        let prompt = try store.modelPrompt(for: record) + "\n\n## My request for Codex:\nRead this."
        let parsed = AppshotPromptCodec.parseAppshots(in: prompt)

        #expect(parsed.count == 1)
        #expect(parsed[0].appName == "Safari")
        #expect(parsed[0].bundleIdentifier == "com.apple.Safari")
        #expect(parsed[0].windowTitle == "A < B")
        #expect(parsed[0].axTree.contains("Continue & Save"))
        #expect(AppshotPromptCodec.stripAppshots(from: prompt) == "# Applications mentioned by the user:\n\n\n\n## My request for Codex:\nRead this.")

        let paired = AppshotPromptCodec.pairAppshots(
            in: prompt,
            imageSources: ["regular.png", "data:image/png;base64,abc"]
        )
        #expect(paired.nonAppshotImageSources == ["regular.png"])
        #expect(paired.appshotContexts.first?.imageDataURL == "data:image/png;base64,abc")
    }

    @Test func `Payload can inline screenshot data URL`() throws {
        let rootURL = temporaryRootURL()
        let sourceScreenshotURL = rootURL.appendingPathComponent("source.png")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try tinyPNGData().write(to: sourceScreenshotURL)

        let store = AppshotStore(rootURL: rootURL)
        var snapshotMetadata = metadata()
        snapshotMetadata.screenshotPath = sourceScreenshotURL.path
        let record = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: Screenshot", metadata: snapshotMetadata)
        )

        let payload = try store.payload(for: record)
        #expect(payload.context.imageName == "screenshot.png")
        #expect(payload.context.imagePath == record.screenshotPath)
        #expect(payload.imageDataURL?.hasPrefix("data:image/png;base64,") == true)
        #expect(payload.imageDataURL == payload.context.imageDataURL)
        #expect(record.transitionSnapshotPath != nil)
        #expect(FileManager.default.fileExists(
            atPath: record.directoryURL.appendingPathComponent("transition-snapshot.png").path
        ))
        #expect(payload.context.transitionSnapshotDataURL?.hasPrefix("data:image/png;base64,") == true)
        #expect(payload.context.transitionSnapshotDataURL != payload.imageDataURL)
        #expect(payload.context.transitionSpringResponse == AppshotStore.transitionSpringResponse)
        #expect(payload.context.transitionSpringDampingFraction == AppshotStore.transitionSpringDampingFraction)
        #expect(payload.context.transitionSnapshotHeight != nil)
    }

    @Test func `Save keeps staged cache screenshot readable after final copy`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try SnapshotCacheStore.ensureRootDirectory()
        let sourceScreenshotURL = SnapshotCacheStore.screenshotURL(for: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: sourceScreenshotURL) }
        try tinyPNGData().write(to: sourceScreenshotURL)

        let store = AppshotStore(rootURL: rootURL)
        var snapshotMetadata = metadata()
        snapshotMetadata.screenshotPath = sourceScreenshotURL.path
        let record = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: Screenshot", metadata: snapshotMetadata)
        )

        #expect(FileManager.default.fileExists(atPath: sourceScreenshotURL.path))
        #expect(FileManager.default.fileExists(atPath: record.screenshotPath ?? ""))
        #expect(sourceScreenshotURL.path != record.screenshotPath)
    }

    @Test func `Same window AX cache fails closed to full recapture`() {
        #expect(AccessibilityCaptureEngine.sameWindowAXReuseRequiresFullRecapture)
    }

    @Test func `Shared AX render policy normalizes URLs and truncates consistently`() {
        let longValue = String(repeating: "x", count: AXRenderPolicy.detailValueLimit + 10)
        let line = AXRenderPolicy.format(
            node: node(
                0,
                parent: nil,
                depth: 0,
                role: "AXWebArea",
                title: "Docs",
                value: longValue,
                url: "https://www.example.com/path"
            ),
            displayDepth: 0,
            includeElementIndexes: false,
            preserveTextAreaNewlines: false
        )

        #expect(line.contains("URL: example.com/path"))
        #expect(line.contains("[truncated 10 chars]"))
    }

    @Test func `Appshot compression preserves Mail sized stored screenshots`() {
        let foregroundSize = ScreenshotCompression.foregroundDefault.scaledPixelSize(
            width: 1591,
            height: 1190
        )
        let appshotSize = ScreenshotCompression.appshotStored.scaledPixelSize(
            width: 1591,
            height: 1190
        )

        #expect(Int(foregroundSize.width) == 917)
        #expect(Int(foregroundSize.height) == 686)
        #expect(Int(appshotSize.width) == 1591)
        #expect(Int(appshotSize.height) == 1190)
    }

    @Test func `Save copies capture diagnostics next to final appshot artifacts`() throws {
        let rootURL = temporaryRootURL()
        let sourceScreenshotURL = rootURL.appendingPathComponent("source.png")
        let sourceDiagnosticsURL = sourceScreenshotURL.appendingPathExtension("diagnostics.json")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try tinyPNGData().write(to: sourceScreenshotURL)
        try #"{"backend":"CoreGraphics.CGWindowListCreateImage"}"#.write(
            to: sourceDiagnosticsURL,
            atomically: true,
            encoding: .utf8
        )

        let store = AppshotStore(rootURL: rootURL)
        var snapshotMetadata = metadata()
        snapshotMetadata.screenshotPath = sourceScreenshotURL.path
        let record = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: Screenshot", metadata: snapshotMetadata)
        )

        #expect(record.captureDiagnosticsPath?.hasSuffix("capture_diagnostics.json") == true)
        #expect(FileManager.default.fileExists(atPath: record.captureDiagnosticsPath ?? ""))
        #expect(try String(contentsOfFile: record.captureDiagnosticsPath ?? "").contains("CoreGraphics.CGWindowListCreateImage"))
    }

    @Test func `Structured state drives prompt text when richer than formatted output`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        let richState = figmaLikeState()
        let record = try store.save(
            target: FrontmostAppTarget(name: "Figma", bundleID: "com.figma.Desktop", pid: 7178),
            output: CaptureOutput(
                text: """
                <app_state surface="window">
                Window: "Recents", App: Figma.
                web area Figma URL: file:///Applications/Figma.app/Contents/Resources/app.asar/shell.html
                </app_state>
                """,
                metadata: figmaMetadata()
            ),
            structuredState: richState
        )

        let axText = try String(contentsOf: record.axTextURL, encoding: .utf8)
        let appshotText = try String(contentsOf: record.appshotTextURL, encoding: .utf8)
        let modelPrompt = try store.modelPrompt(for: record)
        let context = try store.appshotContext(for: record)

        #expect(record.nodeCount == richState.nodes.count)
        #expect(record.pageURL == "https://www.figma.com/files/team/123/recents-and-sharing")
        #expect(axText.contains("HTML content Recents - Figma, URL: figma.com/files/team/123/recents-and-sharing"))
        #expect(axText.contains("pop up button Account dropdown for Shahin Farzane"))
        #expect(axText.contains("text Gumroad"))
        #expect(!axText.contains("outer-only"))
        #expect(appshotText.contains("Page URL: https://www.figma.com/files/team/123/recents-and-sharing"))
        #expect(modelPrompt.contains("HTML content Recents - Figma, URL: figma.com/files/team/123/recents-and-sharing"))
        #expect(context.axTree.contains("text Gumroad"))
        #expect(FileManager.default.fileExists(atPath: record.axJSONPath ?? ""))
    }

    @Test func `Structured appshot text matches Codex-style noise policy`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let longSummary = String(repeating: "Visible Mail summary content ", count: 40)
        let state = CapturedAppState(
            metadata: metadata(title: "Inbox"),
            focusedElementIndex: 2,
            selectedText: nil,
            nodes: [
                node(0, parent: nil, depth: 0, role: "AXWindow", subrole: "AXStandardWindow", title: "Inbox", actions: ["AXRaise"]),
                node(1, parent: 0, depth: 1, role: "AXTable", title: "messages", identifier: "Mail.messageList", actions: ["AXShowMenu"]),
                node(2, parent: 1, depth: 2, role: "AXRow", selected: true, actions: ["AXShowMenu", "AXShowAlternateUI"]),
                node(3, parent: 2, depth: 3, role: "AXCell", selected: true, actions: ["AXShowMenu"]),
                node(4, parent: 3, depth: 4, role: "AXUnknown", title: "Mail.messageList.cell.view"),
                node(5, parent: 4, depth: 5, role: "AXStaticText", value: longSummary, identifier: "Mail.messageList.cell.view.summaryLabel"),
                node(6, parent: 0, depth: 1, role: "AXMenuBar", actions: ["AXCancel"]),
                node(7, parent: 6, depth: 2, role: "AXMenuBarItem", title: "File", identifier: "Mail.menuBar.fileMenu", actions: ["AXCancel", "AXPress"]),
            ]
        )

        let store = AppshotStore(rootURL: rootURL)
        let record = try store.save(
            target: FrontmostAppTarget(name: "Mail", bundleID: "com.apple.mail", pid: 42),
            output: CaptureOutput(text: "fallback", metadata: metadata(title: "Inbox")),
            structuredState: state
        )

        let axText = try String(contentsOf: record.axTextURL, encoding: .utf8)
        #expect(!axText.contains("Secondary Actions"))
        #expect(!axText.contains("menu bar"))
        #expect(!axText.contains("Mail.menuBar.fileMenu"))
        #expect(axText.contains("Mail.messageList.cell.view"))
        #expect(!axText.contains("unknown Mail.messageList.cell.view"))
        #expect(axText.contains("Selected:\n\trow (selected)"))
        #expect(axText.contains("Note: Pay special attention to the content selected by the user."))
        #expect(axText.contains(longSummary.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(!axText.contains("[truncated"))
    }

    @Test func `Delete capture updates index and latest pointers`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        let first = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: First", metadata: metadata(id: "first", title: "First"))
        )
        let second = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: Second", metadata: metadata(id: "second", title: "Second"))
        )

        #expect(try store.deleteCapture(id: second.id))
        #expect(!FileManager.default.fileExists(atPath: second.directoryPath))
        #expect(store.latestCapture()?.id == first.id)
        #expect(try String(contentsOf: store.latestTextURL, encoding: .utf8) == first.directoryPath)
    }

    @Test func `Delete captures removes matching IDs and returns count`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        let first = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: First", metadata: metadata(id: "first", title: "First"))
        )
        let second = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: Second", metadata: metadata(id: "second", title: "Second"))
        )

        let deleted = try store.deleteCaptures(ids: [second.id, "does-not-exist"])

        #expect(deleted == 1)
        #expect(!FileManager.default.fileExists(atPath: second.directoryPath))
        #expect(store.allCaptures().map(\.id) == [first.id])
        #expect(store.latestCapture()?.id == first.id)
    }

    @Test func `Clear all removes everything and leaves empty store`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        let first = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: First", metadata: metadata(id: "first", title: "First"))
        )
        let second = try store.save(
            target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
            output: CaptureOutput(text: "Window: Second", metadata: metadata(id: "second", title: "Second"))
        )

        try store.clearAll()

        #expect(store.allCaptures() == [])
        #expect(store.latestCapture() == nil)
        #expect(!FileManager.default.fileExists(atPath: store.indexURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.latestTextURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.latestPromptURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.latestMetadataURL.path))
        #expect(!FileManager.default.fileExists(atPath: first.directoryPath))
        #expect(!FileManager.default.fileExists(atPath: second.directoryPath))
    }

    @Test func `Clear all on empty store does not throw`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotStore(rootURL: rootURL)
        try store.ensureRootDirectory()
        #expect(throws: Never.self) { try store.clearAll() }
        #expect(store.allCaptures() == [])
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("appshots-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func metadata(id: String = "snapshot", title: String = "Example Window") -> CaptureMetadata {
        CaptureMetadata(
            id: id,
            createdAt: Date(timeIntervalSince1970: id == "second" ? 2 : 1),
            appName: "Safari",
            bundleID: "com.apple.Safari",
            pid: 42,
            windowTitle: title,
            windowID: 100,
            windowFrame: CGRectCodable(CGRect(x: 10, y: 20, width: 800, height: 600)),
            screenshotPath: nil,
            screenshotSize: CGSizeCodable(width: 800, height: 600),
            fingerprint: "fingerprint-\(id)",
            nodeSignatures: [
                CachedNodeSignature(
                    depth: 0,
                    role: "AXWindow",
                    subrole: "",
                    title: title,
                    description: nil,
                    identifier: "",
                    childIndexAmongSameRole: 0
                ),
            ]
        )
    }

    private func figmaMetadata() -> CaptureMetadata {
        CaptureMetadata(
            id: "figma",
            createdAt: Date(timeIntervalSince1970: 3),
            appName: "Figma",
            bundleID: "com.figma.Desktop",
            pid: 7178,
            windowTitle: "Recents",
            windowID: 1963,
            windowFrame: CGRectCodable(CGRect(x: 0, y: 39, width: 2056, height: 1193)),
            screenshotPath: nil,
            screenshotSize: CGSizeCodable(width: 1041, height: 604),
            fingerprint: "figma-fingerprint",
            nodeSignatures: []
        )
    }

    private func figmaLikeState() -> CapturedAppState {
        CapturedAppState(
            metadata: figmaMetadata(),
            focusedElementIndex: 3,
            selectedText: nil,
            nodes: [
                node(0, parent: nil, depth: 0, role: "AXWindow", subrole: "AXStandardWindow", title: "Recents"),
                node(1, parent: 0, depth: 1, role: "AXGroup", title: "Recents"),
                node(2, parent: 1, depth: 2, role: "AXWebArea", title: "Figma", url: "file:///Applications/Figma.app/Contents/Resources/app.asar/shell.html"),
                node(3, parent: 1, depth: 2, role: "AXWebArea", title: "Recents - Figma", url: "https://www.figma.com/files/team/123/recents-and-sharing", focused: true),
                node(4, parent: 3, depth: 3, role: "AXGroup", subrole: "AXLandmarkNavigation", description: "Sidebar"),
                node(5, parent: 4, depth: 4, role: "AXPopUpButton", description: "Account dropdown for Shahin Farzane"),
                node(6, parent: 5, depth: 5, role: "AXStaticText", value: "Shahin Farzane"),
                node(7, parent: 4, depth: 4, role: "AXButton", title: "Recents"),
                node(8, parent: 4, depth: 4, role: "AXButton", title: "Community"),
                node(9, parent: 4, depth: 4, role: "AXButton", title: "Gumroad"),
                node(10, parent: 9, depth: 5, role: "AXStaticText", value: "Gumroad"),
            ]
        )
    }

    private func node(
        _ index: Int,
        parent: Int?,
        depth: Int,
        role: String,
        subrole: String = "",
        title: String = "",
        description: String = "",
        value: String? = nil,
        url: String? = nil,
        focused: Bool? = nil,
        selected: Bool? = nil,
        expanded: Bool? = nil,
        identifier: String = "",
        help: String = "",
        actions: [String] = [],
        isValueSettable: Bool = false,
        valueTypeDescription: String? = nil
    ) -> AXNode {
        AXNode(
            index: index,
            parentIndex: parent,
            depth: depth,
            role: role,
            subrole: subrole,
            title: title,
            description: description,
            value: value,
            help: help,
            identifier: identifier,
            url: url,
            enabled: true,
            selected: selected,
            expanded: expanded,
            focused: focused,
            frame: nil,
            actions: actions,
            isValueSettable: isValueSettable,
            valueTypeDescription: valueTypeDescription
        )
    }

    private func tinyPNGData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    }
}

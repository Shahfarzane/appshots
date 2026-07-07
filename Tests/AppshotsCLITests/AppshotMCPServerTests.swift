@testable import AppshotsCLI
@testable import AppshotsCore
import CoreGraphics
import Foundation
import Testing

/// Focused MCP contract tests (AGENTS.md: the catalog, prompt shapes, and
/// content structures are wire contract). They drive the server's JSON-RPC
/// dispatch directly against a temporary store.
struct AppshotMCPServerTests {
    @Test func `Prompt catalog exposes latest-appshot and appshot with expected shapes`() {
        let prompts = MCPToolCatalog.prompts
        let names = prompts.compactMap { $0["name"] as? String }
        #expect(names == ["latest-appshot", "appshot"])

        let latest = prompts[0]
        #expect(latest["arguments"] == nil)
        #expect((latest["description"] as? String)?.isEmpty == false)

        let appshot = prompts[1]
        let arguments = appshot["arguments"] as? [[String: Any]]
        #expect(arguments?.count == 1)
        #expect(arguments?.first?["name"] as? String == "app")
        #expect(arguments?.first?["required"] as? Bool == false)
    }

    @Test func `Tool catalog defaults take_appshot and get_latest_appshot to codex`() {
        for name in ["take_appshot", "get_latest_appshot"] {
            let tool = MCPToolCatalog.tools.first { $0["name"] as? String == name }
            let schema = tool?["inputSchema"] as? [String: Any]
            let properties = schema?["properties"] as? [String: Any]
            let format = properties?["format"] as? [String: Any]
            #expect(format?["default"] as? String == "codex", "\(name) should default to codex")
        }
    }

    @Test func `initialize advertises the prompts capability`() throws {
        let (server, cleanup) = try makeServer()
        defer { cleanup() }

        let result = try server.handle(method: "initialize", params: [:])
        let capabilities = result["capabilities"] as? [String: Any]
        #expect(capabilities?.keys.sorted() == ["prompts", "tools"])
    }

    @Test func `prompts list matches the catalog`() throws {
        let (server, cleanup) = try makeServer()
        defer { cleanup() }

        let result = try server.handle(method: "prompts/list", params: [:])
        let names = (result["prompts"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(names == ["latest-appshot", "appshot"])
    }

    @Test func `latest-appshot prompt returns text and image user messages`() throws {
        let (server, cleanup) = try makeServer(seedCapture: true, withScreenshot: true)
        defer { cleanup() }

        let result = try server.handle(
            method: "prompts/get",
            params: ["name": "latest-appshot"]
        )
        #expect((result["description"] as? String)?.contains("Safari") == true)

        let messages = try #require(result["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0["role"] as? String == "user" })

        let text = messages[0]["content"] as? [String: Any]
        #expect(text?["type"] as? String == "text")
        #expect((text?["text"] as? String)?.contains("<appshot") == true)

        let image = messages[1]["content"] as? [String: Any]
        #expect(image?["type"] as? String == "image")
        #expect(image?["mimeType"] as? String == "image/png")
        #expect((image?["data"] as? String)?.isEmpty == false)
    }

    @Test func `latest-appshot prompt omits the image message for text-only captures`() throws {
        let (server, cleanup) = try makeServer(seedCapture: true, withScreenshot: false)
        defer { cleanup() }

        let result = try server.handle(
            method: "prompts/get",
            params: ["name": "latest-appshot"]
        )
        let messages = try #require(result["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect((messages[0]["content"] as? [String: Any])?["type"] as? String == "text")
    }

    @Test func `latest-appshot prompt errors on an empty store`() throws {
        let (server, cleanup) = try makeServer()
        defer { cleanup() }

        #expect(throws: (any Error).self) {
            try server.handle(method: "prompts/get", params: ["name": "latest-appshot"])
        }
    }

    @Test func `Unknown prompt name errors`() throws {
        let (server, cleanup) = try makeServer()
        defer { cleanup() }

        #expect(throws: (any Error).self) {
            try server.handle(method: "prompts/get", params: ["name": "nope"])
        }
    }

    @Test func `get_latest_appshot tool defaults to codex text plus image content`() throws {
        let (server, cleanup) = try makeServer(seedCapture: true, withScreenshot: true)
        defer { cleanup() }

        let result = try server.handle(
            method: "tools/call",
            params: ["name": "get_latest_appshot", "arguments": [String: Any]()]
        )
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["text", "image"])

        // An explicit format keeps the previous text-only behavior.
        let explicit = try server.handle(
            method: "tools/call",
            params: ["name": "get_latest_appshot", "arguments": ["format": "prompt"]]
        )
        let explicitContent = try #require(explicit["content"] as? [[String: Any]])
        #expect(explicitContent.map { $0["type"] as? String } == ["text"])
    }

    // MARK: - Fixtures

    /// Builds a server over a fresh temporary store, optionally seeded with one
    /// capture. Returns the server and a cleanup closure removing the store.
    private func makeServer(
        seedCapture: Bool = false,
        withScreenshot: Bool = false
    ) throws -> (AppshotMCPServer, () -> Void) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appshots-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        let store = AppshotStore(rootURL: rootURL)
        let cleanup = { try? FileManager.default.removeItem(at: rootURL); return }

        if seedCapture {
            var screenshotPath: String?
            if withScreenshot {
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                let screenshotURL = rootURL.appendingPathComponent("source.png")
                try tinyPNGData().write(to: screenshotURL)
                screenshotPath = screenshotURL.path
            }
            let metadata = CaptureMetadata(
                id: "snapshot",
                createdAt: Date(timeIntervalSince1970: 1),
                appName: "Safari",
                bundleID: "com.apple.Safari",
                pid: 42,
                windowTitle: "Example Window",
                windowID: 100,
                windowFrame: CGRectCodable(CGRect(x: 10, y: 20, width: 800, height: 600)),
                screenshotPath: screenshotPath,
                screenshotSize: CGSizeCodable(width: 1, height: 1),
                fingerprint: "fingerprint",
                nodeSignatures: []
            )
            _ = try store.save(
                target: FrontmostAppTarget(name: "Safari", bundleID: "com.apple.Safari", pid: 42),
                output: CaptureOutput(text: "Window: \"Example Window\", App: Safari.\nbutton Open", metadata: metadata)
            )
        }

        return (AppshotMCPServer(store: store), cleanup)
    }

    /// A 1x1 transparent PNG.
    private func tinyPNGData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    }
}

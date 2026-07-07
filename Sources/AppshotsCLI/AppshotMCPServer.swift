import AppshotsCore
import Foundation

/// A native Swift stdio MCP (Model Context Protocol) server for Appshots.
///
/// Implements a blocking, line-delimited JSON-RPC 2.0 loop over stdin/stdout.
/// Each inbound line is a single JSON-RPC request; each response is written as
/// a single compact JSON line followed by a newline. Notifications (requests
/// without an `id`) never produce a response. The loop exits cleanly on EOF.
final class AppshotMCPServer {
    private static let serverVersion = "0.1.0"
    private static let protocolVersion = "2024-11-05"

    private let store: AppshotStore

    init(store: AppshotStore) {
        self.store = store
    }

    func run() throws {
        AppLog.mcp.notice("MCP server started version=\(Self.serverVersion, privacy: .public) protocol=\(Self.protocolVersion, privacy: .public)")
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }

            let request: [String: Any]
            do {
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    AppLog.mcp.error("parse error: request was not a JSON object")
                    write(errorResponse(id: NSNull(), code: -32700, message: "Parse error: request was not a JSON object."))
                    continue
                }
                request = object
            } catch {
                AppLog.mcp.error("parse error: \(error.localizedDescription, privacy: .public)")
                write(errorResponse(id: NSNull(), code: -32700, message: "Parse error: \(error.localizedDescription)"))
                continue
            }

            if let response = process(request) {
                write(response)
            }
        }
    }

    // MARK: - Dispatch

    private func process(_ request: [String: Any]) -> [String: Any]? {
        let id = request["id"]
        let hasID = id != nil && (id is NSNull) == false

        guard let method = request["method"] as? String else {
            return hasID ? errorResponse(id: id, code: -32600, message: "Invalid Request: missing method.") : nil
        }

        if method.hasPrefix("notifications/") {
            AppLog.mcp.debug("notification \(method, privacy: .public)")
            return nil
        }

        AppLog.mcp.debug("request method=\(method, privacy: .public) hasID=\(hasID, privacy: .public)")
        do {
            let result = try handle(method: method, params: request["params"] as? [String: Any] ?? [:])
            guard hasID else { return nil }
            return ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        } catch let error as MCPMethodError {
            AppLog.mcp.error("method \(method, privacy: .public) failed code=\(error.code, privacy: .public) message=\(error.message, privacy: .public)")
            guard hasID else { return nil }
            return errorResponse(id: id, code: error.code, message: error.message)
        } catch {
            AppLog.mcp.error("method \(method, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            guard hasID else { return nil }
            return errorResponse(id: id, code: -32603, message: error.localizedDescription)
        }
    }

    /// Internal (not private) so the MCP contract tests can drive the JSON-RPC
    /// dispatch path directly without a stdio round-trip.
    func handle(method: String, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            return [
                "protocolVersion": Self.protocolVersion,
                "capabilities": [
                    "tools": [String: Any](),
                    "prompts": [String: Any](),
                ],
                "serverInfo": ["name": "appshots", "version": Self.serverVersion],
            ]
        case "tools/list":
            return ["tools": MCPToolCatalog.tools]
        case "prompts/list":
            return ["prompts": MCPToolCatalog.prompts]
        case "prompts/get":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            AppLog.mcp.notice("prompt get name=\(name, privacy: .public)")
            return try promptResult(name: name, arguments: arguments)
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            AppLog.mcp.notice("tool call name=\(name, privacy: .public)")
            do {
                let content = try callTool(name: name, arguments: arguments)
                return ["content": content]
            } catch {
                AppLog.mcp.error("tool \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return [
                    "content": [textItem(error.localizedDescription)],
                    "isError": true,
                ]
            }
        default:
            throw MCPMethodError(code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Tools

    private func callTool(name: String, arguments: [String: Any]) throws -> [[String: Any]] {
        switch name {
        case "take_appshot":
            let format = arguments["format"] as? String ?? "codex"
            let record = try AppshotCaptureService.captureFrontmostApplication()
            return try content(for: record, format: format)
        case "get_latest_appshot":
            let format = arguments["format"] as? String ?? "codex"
            guard let record = store.latestCapture() else {
                throw MCPToolError("No appshots captured yet.")
            }
            return try content(for: record, format: format)
        case "get_appshot_image":
            guard let record = store.latestCapture() else {
                throw MCPToolError("No appshots captured yet.")
            }
            guard let path = record.screenshotPath else {
                throw MCPToolError("Latest appshot has no screenshot.")
            }
            return [try imageItem(path: path)]
        case "list_appshots":
            let limit = clampedLimit(intArgument(arguments["limit"]))
            return [textItem(try AppshotJSON.string(Array(store.allCaptures().prefix(limit))))]
        case "search_appshots":
            guard let query = arguments["query"] as? String, query.isEmpty == false else {
                throw MCPToolError("search_appshots requires a non-empty query.")
            }
            let limit = clampedLimit(intArgument(arguments["limit"]))
            return [textItem(try AppshotJSON.string(store.searchCaptures(query: query, limit: limit)))]
        case "delete_appshot":
            guard let id = arguments["id"] as? String, id.isEmpty == false else {
                throw MCPToolError("delete_appshot requires an id.")
            }
            guard try store.deleteCapture(id: id) else {
                throw MCPToolError("Capture not found: \(id)")
            }
            return [textItem("Deleted \(id)")]
        case "doctor_appshots":
            return [textItem(try AppshotJSON.string(AppshotDoctor.run(store: store)))]
        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Prompts

    /// Builds a `prompts/get` result: the appshot delivered as user-role
    /// messages (the `<appshot>` text with the AX tree, then the screenshot as
    /// image content), so invoking the prompt attaches the capture directly to
    /// the user's message.
    private func promptResult(name: String, arguments: [String: Any]) throws -> [String: Any] {
        switch name {
        case "latest-appshot":
            guard let record = store.latestCapture() else {
                throw MCPMethodError(
                    code: -32602,
                    message: "No appshots captured yet. Press the capture hot key or run `appshotsctl capture`, then try again."
                )
            }
            return [
                "description": "Latest appshot: \(record.appName)",
                "messages": try promptMessages(for: record),
            ]
        case "appshot":
            let record: AppshotRecord
            if let app = arguments["app"] as? String,
               app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                let target = try AppshotCaptureService.resolveTarget(matching: app)
                record = try AppshotCaptureService.capture(target: target)
            } else {
                record = try AppshotCaptureService.captureFrontmostApplication()
            }
            return [
                "description": "Appshot of \(record.appName)",
                "messages": try promptMessages(for: record),
            ]
        default:
            throw MCPMethodError(code: -32602, message: "Unknown prompt: \(name)")
        }
    }

    /// The appshot rendered as MCP prompt messages: one text message (the
    /// model-facing `<appshot>` block including the AX tree) plus, when the
    /// capture has a screenshot, one image message.
    private func promptMessages(for record: AppshotRecord) throws -> [[String: Any]] {
        let payload = try store.payload(for: record, includeImageData: false)
        var messages: [[String: Any]] = [
            ["role": "user", "content": textItem(payload.text)],
        ]
        if let path = payload.imagePath {
            messages.append(["role": "user", "content": try imageItem(path: path)])
        }
        return messages
    }

    private func content(for record: AppshotRecord, format: String) throws -> [[String: Any]] {
        if format == "codex" {
            let payload = try store.payload(for: record, includeImageData: false)
            guard let path = payload.imagePath else {
                return [textItem(payload.text)]
            }
            return [textItem(payload.text), try imageItem(path: path)]
        }
        guard let outputFormat = Self.outputFormat(for: format) else {
            throw MCPToolError("Unsupported format: \(format)")
        }
        return [textItem(try store.render(record, as: outputFormat))]
    }

    /// Maps an MCP `format` argument string to its shared `AppshotOutputFormat`.
    /// `codex` is intentionally absent — it returns image content and stays
    /// special-cased in `content(for:format:)`.
    private static func outputFormat(for format: String) -> AppshotOutputFormat? {
        switch format {
        case "prompt": return .prompt
        case "model_prompt": return .modelPrompt
        case "json": return .json
        case "payload": return .payload
        case "context": return .context
        case "events": return .events
        case "image_path": return .imagePath
        case "directory": return .directory
        default: return nil
        }
    }

    // MARK: - Content helpers

    private func textItem(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    private func imageItem(path: String) throws -> [String: Any] {
        ["type": "image", "data": try store.inlinePNG(at: path), "mimeType": "image/png"]
    }

    private func intArgument(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    /// Clamps a client-supplied limit into a safe, non-negative range so a
    /// hostile or buggy caller can never trap `prefix(_:)` and crash the loop.
    private func clampedLimit(_ value: Int?, default defaultValue: Int = 20, max maxValue: Int = 100) -> Int {
        min(max(0, value ?? defaultValue), maxValue)
    }

    // MARK: - Output

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return }
        let handle = FileHandle.standardOutput
        handle.write(data)
        handle.write(Data([0x0A]))
    }
}

private struct MCPMethodError: Error {
    var code: Int
    var message: String
}

private struct MCPToolError: LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

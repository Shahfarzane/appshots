import Foundation

/// The static MCP tool catalog returned by the `tools/list` handler. The tool
/// names, descriptions, `inputSchema` shapes, and `format` enum values are the
/// wire contract — keep them identical to what clients depend on.
enum MCPToolCatalog {
    static let formatEnum: [String] = [
        "codex", "prompt", "model_prompt", "json", "payload", "context", "events", "image_path", "directory",
    ]

    static var tools: [[String: Any]] {
        [
        [
            "name": "take_appshot",
            "description": "Capture the frontmost macOS app and return Codex-style appshot text plus the screenshot image.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "format": [
                        "type": "string",
                        "enum": formatEnum,
                        "default": "codex",
                    ],
                ],
            ],
        ],
        [
            "name": "get_latest_appshot",
            "description": "Return the latest appshot as Codex-style appshot text plus the screenshot image (or another format via `format`).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "format": [
                        "type": "string",
                        "enum": formatEnum,
                        "default": "codex",
                    ],
                ],
            ],
        ],
        [
            "name": "get_appshot_image",
            "description": "Return the latest appshot screenshot as PNG image content.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "list_appshots",
            "description": "List recent appshots as JSON.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "default": 20, "minimum": 1, "maximum": 100],
                ],
            ],
        ],
        [
            "name": "search_appshots",
            "description": "Search indexed appshots by app, title, URL, or captured text.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string"],
                    "limit": ["type": "integer", "default": 20, "minimum": 1, "maximum": 100],
                ],
                "required": ["query"],
            ],
        ],
        [
            "name": "delete_appshot",
            "description": "Delete an appshot by capture id.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"],
            ],
        ],
        [
            "name": "doctor_appshots",
            "description": "Check Appshots storage and latest capture health.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        ]
    }

    /// The static MCP prompt catalog returned by the `prompts/list` handler.
    /// Prompts surface as user-invocable slash commands / attach-menu entries in
    /// MCP clients (Claude Code, Claude Desktop), so the appshot lands *in the
    /// user's message* instead of requiring the agent to decide on a tool call.
    /// Names, descriptions, and argument shapes are wire contract.
    static var prompts: [[String: Any]] {
        [
        [
            "name": "latest-appshot",
            "description": "Attach the most recent appshot (screenshot + accessibility tree) captured with the hot key or `appshotsctl capture`.",
        ],
        [
            "name": "appshot",
            "description": "Capture an app right now and attach the appshot (screenshot + accessibility tree). Pass `app` to capture a specific running app by name or bundle id; without it the frontmost app is captured, which from a chat client is usually the chat window itself, so prefer naming the app or use latest-appshot after pressing the hot key.",
            "arguments": [
                [
                    "name": "app",
                    "description": "Bundle id or name of a running app to capture (e.g. Safari or com.apple.Safari).",
                    "required": false,
                ],
            ],
        ],
        ]
    }
}

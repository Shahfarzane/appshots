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
            "description": "Return the latest appshot prompt or metadata.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "format": [
                        "type": "string",
                        "enum": formatEnum,
                        "default": "prompt",
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
}

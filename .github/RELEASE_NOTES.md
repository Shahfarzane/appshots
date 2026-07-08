Appshots is a macOS 15+ menu-bar app that gives coding agents visual + accessibility context. On a hot key it captures the frontmost window (a screenshot plus the app's accessibility tree), renders a Codex-style `<appshot>` prompt, and copies it to the clipboard. Every capture is saved under `~/.appshots/` so CLI and MCP agents can read it back.

### Install

- **App:** download `Appshots.dmg` (Developer ID signed + notarized), open it, and drag Appshots to Applications.
- **CLI only:** the attached `appshotsctl-*-arm64.zip` for the standalone CLI + MCP stdio server.

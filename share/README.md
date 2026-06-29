# ~/.ai-shared

Shared, source-of-truth support files for the `ai` session router.

## Model

| Axis        | Decides                       | Mechanism                                  |
|-------------|-------------------------------|--------------------------------------------|
| workspace   | files + logs                  | `cd`; logs under `<ws>/.ai-logs/`          |
| account     | auth / billing / session      | `CLAUDE_CONFIG_DIR` / `CODEX_HOME`         |
| browser     | GUI chat identity             | Edge (personal) / Chrome profile (company) |
| Tailscale   | remote entry only             | `ai remote doctor`                         |

Shared dev base (unchanged by the router): ssh, secret managers, git, editor.

## Logs

`<workspace>/.ai-logs/<tool>/<account>-account/session-<timestamp>.log`.
Workspace owns logs; account owns auth.

- Codex internal logs may remain under `$CODEX_HOME/log` (follow the account).
- Claude has no general log-dir flag (only `--debug-file`).
- The wrapper captures a terminal transcript into the workspace log dir.

## MCP (optional extension point)

`mcp/mcp.common.json` (Claude, JSON) and `mcp/mcp.common.toml` (Codex, TOML) are
placeholders only. Claude and Codex do not share an MCP format, so nothing is
symlinked. Per-account tokens/auth/env stay under each account's config root.

See the router repo `docs/` for full architecture, commands, and portability notes.

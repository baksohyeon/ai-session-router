# Command reference

```
ai gui     <personal|company> [--browser] [--dry-run]      # native Claude app, isolated per account (macOS)
ai shell   <personal|company>                              # subshell cd'd into workspace
ai claude  <personal|company> [--account p|c] [-- args]    # launch Claude Code
ai codex   <personal|company> [--account p|c] [-- args]    # launch Codex
ai tmux    <personal|company>                              # attach/create ai-<ws> session
ai doctor                                                  # local diagnostic
ai remote doctor                                           # tailscale / sshd / tmux / host
ai logs                                                    # list captured transcripts
ai resolve <claude|codex> <ws> [--account p|c]             # DRY-RUN preview (no launch)
```

## Rules

- **`ai gui`** launches the native Claude desktop app with a per-account
  `--user-data-dir` (`~/.claude-app-<account>`), so personal and company stay logged in
  separately and simultaneously. If `Claude.app` is absent (or on non-macOS), it falls
  back to the browser identity path. `--browser` forces that fallback; `--dry-run`
  prints the exact `open` command without launching. App data dirs are separate from the
  CLI roots (`~/.claude-<account>`). Native isolation is Electron-only; ChatGPT (native
  AppKit) is not isolatable this way and stays on the browser path.
- **Default account** follows the workspace: `personal`→personal, `company`→company.
- **Override** with `--account personal|company`.
- **`--` passthrough**: everything after `--` is forwarded verbatim to the tool.
  Example: `ai codex company --account personal -- doctor` runs `codex doctor`
  non-interactively through the real wrapper path (handy for testing).

## Examples

| Command | workspace | account env | logs |
|---------|-----------|-------------|------|
| `ai claude personal` | `~/dev/personal` | `CLAUDE_CONFIG_DIR=~/.claude-personal` | `~/dev/personal/.ai-logs/claude/personal-account/` |
| `ai codex company` | `~/dev/work` | `CODEX_HOME=~/.codex-company` | `~/dev/work/.ai-logs/codex/company-account/` |
| `ai codex company --account personal` | `~/dev/work` | `CODEX_HOME=~/.codex-personal` | `~/dev/work/.ai-logs/codex/personal-account/` |

## Diagnostics

- `ai doctor` — OS, shell, PATH, tool availability, browsers, workspace paths, config
  roots (exists/missing), example log resolution, config file in use.
- `ai remote doctor` — hostname, user, Tailscale status/IP, sshd listening check,
  tmux sessions. **Never configures Tailscale.**
- `ai resolve …` — prints exactly what a launch would do (env var, cwd, logs) **without
  launching**. Use this whenever unsure.

## Exit codes

`2` = usage/validation error · `127` = tool not on PATH · `1` = unknown command / cd
failure · otherwise the wrapped tool's own exit code.

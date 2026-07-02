# Command reference

```
ai gui     <personal|company> [--browser] [--dry-run]      # native Claude app, isolated per account (macOS)
ai shell   <personal|company>                              # subshell cd'd into workspace
ai claude  <personal|company> [--account p|c] [-- args]    # launch Claude Code
ai codex   <personal|company> [--account p|c] [-- args]    # launch Codex
ai tmux    <personal|company>                              # attach/create ai-<ws> session
ai keychain <list|prune> [--force] [--keep DIR]            # audit/clean orphaned Claude keychain creds (macOS)
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

## Keychain hygiene (macOS)

Claude Code on macOS stores each `CLAUDE_CONFIG_DIR`'s OAuth under a Keychain service
`Claude Code-credentials-<sha256(dir)[:8]>` (the default `~/.claude` uses the bare,
unsuffixed name). Every config dir ever logged into leaves an entry that is never
cleaned up, so they accumulate.

- **`ai keychain list`** classifies every `Claude Code-credentials*` entry as
  *default* (bare `~/.claude`), *active* (hash matches an existing config dir), or
  *orphan* (matches no existing dir). Presence/labels only — **never reads the secret**.
- **`ai keychain prune`** is **dry-run by default**: it prints the orphans it *would*
  delete and preserves everything. Add **`--force`** to actually delete — and even then
  it only ever removes *orphan* entries, never the bare entry or an active account's.
- **`--keep DIR`** (repeatable) whitelists a config dir whose entry should be treated as
  active — use it for devcontainer/worktree roots that live outside `~/.claude*`, since
  those would otherwise look like orphans.

Recommended flow: run `ai keychain list`, eyeball the orphans, then `ai keychain prune`
(dry-run) to confirm, and only then `ai keychain prune --force`.

## Diagnostics

- `ai doctor` — OS, shell, PATH, tool availability, browsers, workspace paths, config
  roots (exists/missing), per-account auth isolation (verified Keychain entry on macOS),
  a keychain-scheme version guard, example log resolution, config file in use.
- `ai remote doctor` — hostname, user, Tailscale status/IP, sshd listening check,
  tmux sessions. **Never configures Tailscale.**
- `ai resolve …` — prints exactly what a launch would do (env var, cwd, logs) **without
  launching**. Use this whenever unsure.

## Exit codes

`2` = usage/validation error · `127` = tool not on PATH · `1` = unknown command / cd
failure · otherwise the wrapped tool's own exit code.

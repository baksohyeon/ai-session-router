# Command reference

**Language:** English · [한국어](../ko/COMMANDS.md)

```
ai gui     <personal|company> [--browser] [--dry-run]      # native Claude app, else isolated browser instance
ai gui     setup [--print]                                 # detect browsers, map identities → router.env
ai shell   <personal|company>                              # subshell cd'd into workspace
ai claude  <personal|company> [--account p|c] [-- args]    # launch Claude Code
ai codex   <personal|company> [--account p|c] [-- args]    # launch Codex
ai tmux    <personal|company>                              # attach/create ai-<ws> session
ai zellij  <personal|company>                              # Zellij session (layout-as-code); tmux = fallback
ai keychain <list|prune> [--force] [--keep DIR]            # audit/clean orphaned Claude keychain creds (macOS)
ai doctor                                                  # local diagnostic
ai remote doctor                                           # tailscale / sshd / tmux / host
ai logs                                                    # list captured transcripts
ai profiles [list | show <ws>]                             # account inventory (redacted; presence only)
ai resolve <claude|codex> <ws> [--account p|c]             # DRY-RUN preview (no launch)
```

## Rules

- **`ai gui <personal|company>`** launches the native Claude desktop app with a
  per-account `--user-data-dir` (`~/.claude-app-<account>`), so personal and company stay
  logged in separately and simultaneously. If `Claude.app` is absent (or on non-macOS),
  it falls back to the **browser identity path**. `--browser` forces that fallback;
  `--dry-run` prints the exact launch command without launching. App data dirs are
  separate from the CLI roots (`~/.claude-<account>`). Native isolation is Electron-only;
  ChatGPT (native AppKit) is not isolatable this way and stays on the browser path.
- **Browser identity path (generic).** One identity = one isolated browser instance,
  launched with the same `--user-data-dir` mechanism the desktop app uses. No specific
  browser and no pre-existing profile are required; the isolated data-dir is
  auto-created. Two mechanisms:
  - **Isolated data-dir** (default): `--user-data-dir=${AI_BROWSER_DATA_PREFIX}<id>`;
    zero setup, clean slate. Signing into the browser account inside it triggers Chromium
    sync, so bookmarks/extensions/passwords populate after a one-time login.
  - **Existing profile** (opt-in per identity): set `AI_GUI_PROFILE_<id>` to reuse an
    existing profile's logins/bookmarks via `--profile-directory=<name>`.

  Your everyday browser (opened by clicking its icon = the default data-dir) is never
  touched; `ai gui` launches a separate isolated instance. If no browser resolves,
  it falls back to the OS default browser opening the URLs and hints to run `ai gui setup`.
- **`ai gui setup [--print]`** is a one-time helper: it detects installed Chromium
  browsers (Edge, Chrome, Brave, Arc, Chromium), lists their existing profiles, prompts
  you to map each identity → (browser, isolated | profile, URLs), and writes only the
  relevant `AI_*` lines into `router.env` (never clobbering unrelated lines). `--print`
  shows what it would write without changing anything. Setup is convenience, not a gate.
  If you never run it, defaults still work (isolated data-dir with the auto-detected
  browser). Runtime `ai gui` launches are always non-interactive. Config vars:
  `AI_BROWSER`, `AI_BROWSER_DATA_PREFIX`, `AI_GUI_BROWSER_<id>`, `AI_GUI_URLS_<id>`,
  `AI_GUI_PROFILE_<id>`. Legacy `AI_CHROME_COMPANY_PROFILE` / `AI_COMPANY_*_URL` are still
  honored as fallbacks, so existing configs keep working; migration is not forced.
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
  *orphan* (matches no existing dir). Presence/labels only, **never reads the secret**.
- **`ai keychain prune`** is **dry-run by default**: it prints the orphans it *would*
  delete and preserves everything. Add **`--force`** to actually delete, and even then
  it only ever removes *orphan* entries, never the bare entry or an active account's.
- **`--keep DIR`** (repeatable) whitelists a config dir whose entry should be treated as
  active. Use it for devcontainer/worktree roots that live outside `~/.claude*`, since
  those would otherwise look like orphans.

Recommended flow: run `ai keychain list`, eyeball the orphans, then `ai keychain prune`
(dry-run) to confirm, and only then `ai keychain prune --force`.

## Diagnostics

- `ai doctor`: OS, shell, PATH, tool availability, browsers, workspace paths, config
  roots (exists/missing), per-account auth isolation (verified Keychain entry on macOS),
  a keychain-scheme version guard, example log resolution, config file in use. For the
  GUI it also reports the resolved browser per identity, the mechanism (data-dir vs
  profile), and the resolved data-dir / profile with exists/missing status.
- `ai remote doctor`: hostname, user, Tailscale status/IP, sshd listening check,
  tmux sessions, plus read-only control-plane exposure checks (T5): TCP listeners
  bound off-loopback, agent control planes flagged as WARNINGs, and a HIGH-RISK
  warning when Tailscale Funnel is active. Prints process name + bind address +
  port only, never args or secrets. **Never configures Tailscale.**
- `ai resolve …`: prints exactly what a launch would do (env var, cwd, logs) **without
  launching**. Use this whenever unsure.

## Exit codes

`2` = usage/validation error · `127` = tool not on PATH · `1` = unknown command / cd
failure · otherwise the wrapped tool's own exit code.

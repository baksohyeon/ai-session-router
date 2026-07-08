# Architecture

**Language:** English · [한국어](../ko/ARCHITECTURE.md)

> **[Archived]** This project is deprecated; session routing moved to Orca. See [TEARDOWN.md](TEARDOWN.md) to revert. Kept for reference.

## 1. Problem

One machine, one user, two AI identities (personal accounts/projects vs work
accounts/repos). CLI AI tools default to a single global state dir, which cross-contaminates
everything: wrong billing, mixed chat history, wrong MCP tokens, logs in the
wrong tree. `ai` makes the identity choice explicit and repeatable.

## 2. Core idea: orthogonal axes

A "session" breaks into independent axes that combine freely:

| Axis          | Decides                       | Mechanism                                   |
|---------------|-------------------------------|---------------------------------------------|
| **workspace** | files + log location          | `cd`; logs under `<ws>/.ai-logs/`           |
| **account**   | auth / billing / session      | `CLAUDE_CONFIG_DIR` · `CODEX_HOME`          |
| **browser**   | GUI chat identity             | isolated browser instance (`--user-data-dir`) |
| **Tailscale** | remote entry (report only)    | `ai remote doctor`                          |

Changing one axis never affects the others. `ai codex company --account personal` =
"personal account, company workspace, company-located logs." One line here, a footgun
elsewhere.

## 3. The mechanism

CLI AI tools resolve all state from one root dir via an env var. So the router comes down to
three lines:

```zsh
export CODEX_HOME="$HOME/.codex-$account"   # account = which folder
cd "$workspace"                              # workspace = where you work
codex "$@"                                    # everything else inherits both
```

Everything else (arg parsing, default rules, warnings, logging, gui/tmux/doctor) is
ergonomics and guardrails.

### Config roots

| Tool   | personal              | company              | env var             |
|--------|-----------------------|----------------------|---------------------|
| Claude | `~/.claude-personal`  | `~/.claude-company`  | `CLAUDE_CONFIG_DIR` |
| Codex  | `~/.codex-personal`   | `~/.codex-company`   | `CODEX_HOME`        |

(Prefixes are configurable via `router.env`.) Originals `~/.claude`/`~/.codex` are
never moved; seed new roots by cloning or by a fresh login.

### Workspaces & logs

`<workspace>/.ai-logs/<tool>/<account>-account/session-<timestamp>.log`.
**Workspace owns logs; account owns auth.** A terminal transcript is captured via
`script(1)` (TTY-preserving, so the interactive TUI still works).

### Browser isolation (`ai gui`)

The GUI path reuses the isolation trick the Claude desktop app already relies on.
Chromium-based apps and browsers accept `--user-data-dir=<path>`, which spins up an
**isolated instance with its own storage and auto-creates the directory**, no
pre-existing profile required. The desktop app passes `--user-data-dir=~/.claude-app-<account>`;
the browser path generalizes the same idea to any Chromium browser (Edge, Chrome,
Brave, Arc, Chromium):

> One identity = one isolated browser instance. Nothing is forced: no required browser,
> no pre-created profile, no interactive prompt on every launch.

Two mechanisms, resolved per identity:

| Mechanism | Flag | Setup | Use |
|-----------|------|-------|-----|
| **Isolated data-dir** (default) | `--user-data-dir=${AI_BROWSER_DATA_PREFIX}<id>` | none, auto-created | zero-setup clean isolation |
| **Existing profile** (opt-in) | `--profile-directory=<name>` | profile must exist | reuse an existing profile's logins/bookmarks |

The default forces nothing. Signing into the browser account inside a fresh data-dir
triggers **Chromium sync**, so bookmarks/extensions/passwords/history populate after a
one-time login, matching a profile without pre-creating one. The user's everyday
browser (launched by clicking its icon → the *default* data-dir) is never touched.

Resolution per identity `<id>`: browser = `AI_GUI_BROWSER_<id>` → `AI_BROWSER` → first
detected Chromium browser → OS default (open URLs only + warn). URLs = `AI_GUI_URLS_<id>`.
If `AI_GUI_PROFILE_<id>` is set, launch with `--profile-directory`; else `--user-data-dir`.
Legacy `AI_CHROME_COMPANY_PROFILE` / `AI_COMPANY_*_URL` are honored as fallbacks, so old
configs keep working (migration is documented, not forced). `ai gui setup` is a one-time
helper that detects browsers/profiles and writes these per-identity mappings; runtime
launches stay non-interactive.

## 4. Guardrails

- personal workspace + company account → warn
- cwd outside the selected workspace → warn
- secret-looking filenames near workspace root → warn **by name only** (never reads
  contents)
- nothing hard-blocks unless an action would overwrite/destroy

## 5. Known limitations

- **Codex internal logs** can't be redirected by CLI flag; they live under
  `$CODEX_HOME/log/` (follow the account). The workspace transcript compensates.
- **Claude** has no general log-dir flag (only `--debug-file`). Same compensation.
- **Claude auth on macOS** lives in the Keychain, not under `CLAUDE_CONFIG_DIR`. It
  *is* isolated per account, but via an **undocumented, version-dependent** service
  name `Claude Code-credentials-<sha256(config-dir)[:8]>` (verified on Claude Code
  v2.1.198; the public docs still describe a single shared entry). So `ai doctor`
  **verifies** the entry exists (presence only, never the secret) rather
  than assuming, and flags it as re-verify-after-upgrade. Two "fixes" are macOS
  dead-ends and left alone on purpose: forcing file-based `.credentials.json`
  (no supported switch) and per-account `CLAUDE_CODE_OAUTH_TOKEN` (triggers issue
  \#37512, which deletes the shared Keychain entry on exit). Codex avoids this:
  `auth.json` is a plain file under `CODEX_HOME`.
- **Version drift**: tools auto-update; the wrapper hardcodes no versions. The macOS
  Keychain hash above is the one place this can bite, which is why the doctor verifies it.

## 6. MCP: deliberately out of scope (v1)

Claude (JSON) and Codex (TOML) use different MCP config formats, and per-account tokens
must live in each config root anyway. So MCP is **not** a core feature. The
`share/mcp/` placeholders exist only as an optional, documented extension point. Wire
MCP into each account's config root by hand.

## 7. Data flow

```
$ ai codex company --account personal -- doctor
        │        │              │          └── passthrough → `codex doctor`
        │        │              └── account override → CODEX_HOME=~/.codex-personal
        │        └── workspace → cd ~/dev/work ; logs under ~/dev/work/.ai-logs
        └── tool → codex
   ↓
   warnings (mismatch / cwd / secrets) → stderr
   ↓
   export CODEX_HOME ; cd workspace ; script -q <transcript> codex doctor
```

See also [PORTABILITY.md](PORTABILITY.md) and [COMMANDS.md](COMMANDS.md).

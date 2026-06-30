# Design — GUI desktop app isolation (`ai gui`)

- **Date:** 2026-06-30
- **Sub-project:** A of the multi-session / multi-device / multi-agent roadmap
- **Status:** Approved (design)
- **Scope this iteration:** Claude desktop app only. ChatGPT (and any Codex GUI) are
  deferred to a follow-up; the code is structured so adding them is a one-line change.

## 1. Problem

`ai gui <personal|company>` today only opens a **browser**: personal launches Microsoft
Edge; company launches a Chrome "Work" profile pointed at chat URLs. The user also wants
the **native Claude desktop app** logged into the *right account* per identity, with
personal and company running **simultaneously without their logins fighting**.

The native app stores its login/session under one data directory, so two accounts
normally clobber each other. We isolate them.

## 2. Mechanism (verified)

macOS Electron apps accept `--user-data-dir`, and `open -n` bypasses the single-instance
lock so two instances run side by side:

```zsh
open -n -a "$AI_CLAUDE_APP" --args --user-data-dir="<per-account data dir>"
```

- `-n` → force a new instance regardless of one already running.
- `--user-data-dir` → redirect all app state (login, tokens, session) to that folder.
- No `.app` bundle copying (rejected: wastes disk, breaks on every app update).

## 3. Behavior

`ai gui <personal|company> [--browser] [--dry-run]`:

1. **macOS + Claude.app present** → launch Claude.app with the account's isolated
   `--user-data-dir`.
2. **Claude.app absent** → warn, fall back to the existing browser behavior.
3. **Non-macOS (Linux)** → browser fallback (native app not available there).
4. **`--browser`** → force the old browser path (escape hatch).
5. **`--dry-run`** → print the exact `open` command + data dir, run nothing. Mirrors the
   existing `ai resolve` dry-run philosophy and is the script's testable surface.

The current `personal → Edge` special-case is absorbed into the **browser fallback**
path, so personal and company become symmetric (different data dir; on fallback,
different Chrome profile / browser).

## 4. App registry (extensibility)

Apps are described in a small data structure rather than hardcoded inline, so tomorrow's
ChatGPT addition is one entry:

```zsh
# conceptual shape — name, bundle var, data-dir prefix var
gui_apps=(
  "claude:$AI_CLAUDE_APP:$AI_CLAUDE_APP_DATA_PREFIX"
  # tomorrow: "chatgpt:$AI_CHATGPT_APP:$AI_CHATGPT_APP_DATA_PREFIX"
)
```

`cmd_gui` iterates the registry: for each app, if its bundle exists launch it isolated,
else fall back. This keeps the Claude-only scope now while making the multi-app future
trivial.

## 5. Data directories — separate from the CLI roots (important)

Desktop-app data is **distinct** from the CLI's `CLAUDE_CONFIG_DIR`. They must not be
conflated. We only reuse the `<prefix><account>` naming pattern:

| Concern            | personal               | company               |
|--------------------|------------------------|-----------------------|
| CLI root (existing)| `~/.claude-personal`   | `~/.claude-company`   |
| **App data (new)** | `~/.claude-app-personal` | `~/.claude-app-company` |

Login happens once per app-data dir.

## 6. Config — new `router.env` keys (all have defaults)

```zsh
AI_CLAUDE_APP="/Applications/Claude.app"
AI_CLAUDE_APP_DATA_PREFIX="$HOME/.claude-app-"   # + <account>
# Reserved for the follow-up iteration:
# AI_CHATGPT_APP="/Applications/ChatGPT.app"
# AI_CHATGPT_APP_DATA_PREFIX="$HOME/.chatgpt-app-"
```

## 7. Error handling

- App bundle missing → `warn` + browser fallback for that app.
- `mkdir -p` the data dir before launch.
- Invalid identity (not personal/company) → usage error (unchanged validation; axis
  generalization is sub-project B, out of scope here).

## 8. `ai doctor` augmentation

Under the existing config-roots section, also report:

- Claude.app present? (bundle path)
- App data dirs and whether they exist.

## 9. Testing

zsh launcher → follow repo convention (no heavyweight unit harness):

- `ai gui <id> --dry-run` output assertions: bundle path, data dir, exact `open` string.
- `ai doctor` reflects app detection.
- Manual: run `ai gui personal` and `ai gui company` together; confirm each keeps a
  distinct login.

## 10. Known risks

- ChatGPT.app's respect for `--user-data-dir` is unverified (app not in scope yet);
  validate when that iteration starts.
- If a future macOS / Claude.app update changes single-instance handling, `open -n`
  behavior must be re-checked.

## 11. Docs to update

- `docs/COMMANDS.md` — `ai gui` entry (native app + flags).
- `examples/router.env.example` — new keys.
- `README.md` — the `ai gui` line if its description changes.

## 12. Out of scope (explicit)

- ChatGPT / Codex GUI (next iteration).
- Identity axis generalization beyond personal|company (sub-project B).
- Any orchestration / multi-agent logic (sub-projects C/D).

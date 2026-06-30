# GUI Desktop App Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ai gui <personal|company>` launch the native Claude desktop app isolated per account (own login/session) on macOS, falling back to the existing browser behavior when the app is absent.

**Architecture:** Extend the single zsh router `bin/ai`. Add config defaults + an app-name→bundle/data-dir registry, two OS-isolated launch helpers, and rewrite `cmd_gui` to: parse `--browser`/`--dry-run`, launch configured apps via `open -n -a <bundle> --args --user-data-dir=<dir>` on macOS, and fall back to the legacy browser path otherwise. Augment `ai doctor` and the docs.

**Tech Stack:** zsh (macOS-first; Linux falls back to browser). No test framework — the repo's convention is smoke checks (`zsh -n bin/ai`, `ai resolve`, `ai doctor`, and here `ai gui … --dry-run`).

## Global Constraints

- **No secrets, ever.** Never read token/credential file *contents*. (CONTRIBUTING.md)
- **No machine-specific hardcoding.** Every new tunable goes through `router.env` / `AI_*` env vars with a default in `bin/ai`, never a literal in logic. (CONTRIBUTING.md)
- **Isolate OS-specific code** in platform helpers (`_open_url`, `_has_browser`, `_launch_*`). Native-app launch is macOS-only; other OSes use the browser fallback. (CONTRIBUTING.md)
- **Non-destructive by default.** Prefer warnings over hard blocks; never move originals. (CONTRIBUTING.md)
- **Scope:** Claude desktop app only this iteration. ChatGPT/Codex GUI deferred; the registry must let them be added by extending one default value. (spec §0, §4, §12)
- **App data dirs are separate from CLI roots:** app uses `~/.claude-app-<account>`, distinct from the CLI's `~/.claude-<account>`. Do not conflate. (spec §5)
- **Commit style:** Conventional commits (`feat:`, `docs:`, …). (CONTRIBUTING.md)
- **Pre-PR checks:** `zsh -n bin/ai` and `sh -n install.sh` must pass; update `docs/COMMANDS.md` and `CHANGELOG.md` on behavior change. (CONTRIBUTING.md)

## File Structure

- `bin/ai` — the only logic file. Adds:
  - config defaults: `AI_CLAUDE_APP`, `AI_CLAUDE_APP_DATA_PREFIX`, `AI_GUI_APPS`
  - registry fns: `gui_app_bundle`, `gui_app_dataprefix`
  - helpers: `_has_app_bundle`, `_launch_app_isolated`
  - `_gui_browser` (legacy `cmd_gui` body, renamed) + rewritten `cmd_gui`
  - `cmd_doctor` gui-apps section
  - `usage` line update
- `examples/router.env.example` — document the new keys.
- `install.sh` — emit the new keys into the generated `router.env`.
- `docs/COMMANDS.md`, `README.md`, `CHANGELOG.md` — doc updates.

---

### Task 1: Native isolated `ai gui` (config, registry, helpers, cmd_gui)

**Files:**
- Modify: `bin/ai` — config block (~28-35), maps block (~41-66), platform helpers (~101-113), `cmd_gui` (245-258)

**Interfaces:**
- Produces:
  - `gui_app_bundle <app>` → prints bundle path (e.g. `/Applications/Claude.app`); nonzero on unknown app.
  - `gui_app_dataprefix <app>` → prints data-dir prefix (e.g. `$HOME/.claude-app-`).
  - `_has_app_bundle <bundle>` → true iff macOS and `<bundle>` is a directory.
  - `_launch_app_isolated <bundle> <data-dir>` → `mkdir -p <data-dir>; open -n -a <bundle> --args --user-data-dir=<data-dir>`.
  - `cmd_gui <personal|company> [--browser] [--dry-run]` → native launch / browser fallback / dry-run report.
- Consumes: existing `valid_ws`, `warn`, `_has_browser`, `_launch_edge`, `_launch_chrome_profile`, `_open_url`, `AI_OS`.

- [ ] **Step 1: Write the failing smoke test (dry-run resolution)**

Run this now (before implementing) to confirm it FAILS:

```bash
cd ~/dev/personal/ai-session-router
./bin/ai gui company --dry-run 2>&1 | grep -E 'Claude\.app .*--user-data-dir.*\.claude-app-company'
```

Expected before implementation: **no match / nonzero exit** (current `cmd_gui` rejects `--dry-run` with a usage error).

- [ ] **Step 2: Add config defaults**

In `bin/ai`, in the user-overridable config block (right after the `AI_SHARED` line, before `_cfg=`), add:

```zsh
: "${AI_CLAUDE_APP:=/Applications/Claude.app}"
: "${AI_CLAUDE_APP_DATA_PREFIX:=$HOME/.claude-app-}"   # + <account>
: "${AI_GUI_APPS:=claude}"                              # space-separated; later: "claude chatgpt"
```

- [ ] **Step 3: Add registry map functions**

After the `cfg_env_name` function (around line 62), add:

```zsh
gui_app_bundle() {  # $1 app name -> bundle path
  case "$1" in
    claude)  print -r -- "$AI_CLAUDE_APP" ;;
    chatgpt) print -r -- "${AI_CHATGPT_APP:-/Applications/ChatGPT.app}" ;;
    *) return 1 ;;
  esac
}

gui_app_dataprefix() {  # $1 app name -> data-dir prefix (account appended by caller)
  case "$1" in
    claude)  print -r -- "$AI_CLAUDE_APP_DATA_PREFIX" ;;
    chatgpt) print -r -- "${AI_CHATGPT_APP_DATA_PREFIX:-$HOME/.chatgpt-app-}" ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Add launch helpers**

After `_launch_chrome_profile` (around line 113), add:

```zsh
_has_app_bundle() {  # $1 = /Applications/Foo.app — macOS .app bundles are directories
  [[ "$AI_OS" == macos && -d "$1" ]]
}

_launch_app_isolated() {  # $1 bundle, $2 data-dir — new isolated instance (macOS)
  mkdir -p "$2"
  open -n -a "$1" --args --user-data-dir="$2"
}
```

- [ ] **Step 5: Rename the legacy `cmd_gui` body to `_gui_browser`**

Replace the existing `cmd_gui() { … }` (lines 245-258) with `_gui_browser`, keeping its body verbatim (it is the fallback path):

```zsh
_gui_browser() {  # personal|company — legacy browser identity path (also the fallback)
  case "$1" in
    personal)
      if _has_browser edge; then print -r -- "→ gui personal: Microsoft Edge"; _launch_edge
      else warn "Microsoft Edge not found; opening default browser."; _open_url "$AI_COMPANY_CLAUDE_URL"; fi ;;
    company)
      if _has_browser chrome; then
        print -r -- "→ gui company: Chrome profile \"$AI_CHROME_COMPANY_PROFILE\" + company chat URLs"
        _launch_chrome_profile "$AI_CHROME_COMPANY_PROFILE" "$AI_COMPANY_CHATGPT_URL" "$AI_COMPANY_CLAUDE_URL" \
          || { warn "could not launch Chrome with a dedicated profile."; return 1; }
      else warn "Google Chrome not found; cannot open dedicated company profile."; return 1; fi ;;
    *) print -r -- "usage: ai gui <personal|company>" >&2; return 2 ;;
  esac
}
```

- [ ] **Step 6: Add the new `cmd_gui`**

Immediately after `_gui_browser`, add:

```zsh
cmd_gui() {  # <personal|company> [--browser] [--dry-run]
  local id="" browser=0 dry=0
  while (( $# )); do
    case "$1" in
      --browser) browser=1; shift ;;
      --dry-run) dry=1; shift ;;
      personal|company) id="$1"; shift ;;
      *) print -r -- "usage: ai gui <personal|company> [--browser] [--dry-run]" >&2; return 2 ;;
    esac
  done
  valid_ws "$id" || { print -r -- "usage: ai gui <personal|company> [--browser] [--dry-run]" >&2; return 2; }

  # Forced browser, or no native GUI on this OS -> legacy browser identity path.
  if (( browser )) || [[ "$AI_OS" != macos ]]; then
    if (( dry )); then
      print -r -- "gui (browser) id=$id"
      print -r -- "  would run the browser identity path (Edge / Chrome profile + URLs)"
      return 0
    fi
    _gui_browser "$id"; return
  fi

  # Native mode: launch each configured app, isolated by account.
  local app bundle datadir missing=0
  for app in ${=AI_GUI_APPS}; do
    bundle="$(gui_app_bundle "$app")" || { warn "unknown gui app: $app"; continue; }
    datadir="$(gui_app_dataprefix "$app")$id"
    if (( dry )); then
      print -r -- "gui (native, macOS) app=$app id=$id"
      if [[ -d "$bundle" ]]; then print -r -- "  bundle:   $bundle (exists)"
      else print -r -- "  bundle:   $bundle (MISSING -> real run uses browser fallback)"; fi
      print -r -- "  data-dir: $datadir"
      print -r -- "  command:  open -n -a \"$bundle\" --args --user-data-dir=\"$datadir\""
      continue
    fi
    if _has_app_bundle "$bundle"; then
      print -r -- "→ gui $id: $app app (isolated)  data-dir=$datadir"
      _launch_app_isolated "$bundle" "$datadir"
    else
      warn "$app app not found at $bundle; using browser fallback."
      missing=1
    fi
  done
  (( missing )) && _gui_browser "$id"
  return 0
}
```

- [ ] **Step 7: Update the `usage` heredoc**

In `usage()` change the `ai gui` line to:

```
  ai gui     <personal|company> [--browser] [--dry-run]
```

- [ ] **Step 8: Verify syntax**

Run: `zsh -n bin/ai`
Expected: no output, exit 0.

- [ ] **Step 9: Run the dry-run smoke tests (now PASS)**

```bash
./bin/ai gui company --dry-run 2>&1 | grep -E 'Claude\.app" --args --user-data-dir=".*\.claude-app-company"'
./bin/ai gui personal --dry-run 2>&1 | grep -E '\.claude-app-personal'
./bin/ai gui company --browser --dry-run 2>&1 | grep -F 'gui (browser)'
./bin/ai gui bogus 2>&1 | grep -F 'usage: ai gui'
```
Expected: each `grep` matches (exit 0). The first two prove native command + per-account data dir; the third proves the `--browser` escape hatch; the fourth proves validation.

- [ ] **Step 10: Commit**

```bash
git add bin/ai
git commit -m "feat: ai gui launches native Claude app isolated per account"
```

---

### Task 2: `ai doctor` reports gui apps

**Files:**
- Modify: `bin/ai` — `cmd_doctor` (after the config-roots loop, ~307)

**Interfaces:**
- Consumes: `AI_GUI_APPS`, `gui_app_bundle`, `gui_app_dataprefix` (Task 1).

- [ ] **Step 1: Write the failing smoke test**

```bash
./bin/ai doctor 2>&1 | grep -F 'gui desktop apps:'
```
Expected before implementation: no match (nonzero).

- [ ] **Step 2: Add the gui-apps section to `cmd_doctor`**

In `cmd_doctor`, immediately after the `for a in personal company; do … done` config-roots loop (just before `print -r -- "log resolution (examples):"`), insert:

```zsh
  print -r -- "gui desktop apps:"
  local gapp gbundle gd
  for gapp in ${=AI_GUI_APPS}; do
    gbundle="$(gui_app_bundle "$gapp")"
    [[ -d "$gbundle" ]] && print -r -- "  $gapp app: $gbundle (present)" \
                        || print -r -- "  $gapp app: $gbundle (NOT FOUND)"
    for a in personal company; do
      gd="$(gui_app_dataprefix "$gapp")$a"
      [[ -d "$gd" ]] && print -r -- "    data/$a: $gd (exists)" \
                     || print -r -- "    data/$a: $gd (missing)"
    done
  done
```

Note: `a` is already declared `local` earlier in `cmd_doctor`; `gapp gbundle gd` are added here.

- [ ] **Step 3: Verify syntax**

Run: `zsh -n bin/ai`
Expected: exit 0.

- [ ] **Step 4: Run the smoke test (now PASS)**

```bash
./bin/ai doctor 2>&1 | grep -E 'gui desktop apps:|claude app:'
```
Expected: matches (exit 0).

- [ ] **Step 5: Commit**

```bash
git add bin/ai
git commit -m "feat: ai doctor reports gui desktop apps and data dirs"
```

---

### Task 3: Config surface + docs

**Files:**
- Modify: `examples/router.env.example`
- Modify: `install.sh` (generated `router.env` heredoc)
- Modify: `docs/COMMANDS.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:** none (documentation / config text).

- [ ] **Step 1: Extend `examples/router.env.example`**

After the `# Browser identity (company GUI)` block, add:

```zsh

# Native desktop GUI apps (macOS). `ai gui` launches these isolated per account
# via `open -n -a <bundle> --args --user-data-dir=<prefix><account>`.
# Data dirs are SEPARATE from the CLI roots above.
AI_CLAUDE_APP="/Applications/Claude.app"
AI_CLAUDE_APP_DATA_PREFIX="$HOME/.claude-app-"
AI_GUI_APPS="claude"   # space-separated; e.g. "claude chatgpt" once ChatGPT is added
```

- [ ] **Step 2: Extend the `install.sh` config heredoc**

In `install.sh`, in the heredoc that writes the default `router.env` (the block ending with the `EOF` after `AI_COMPANY_CLAUDE_URL=...`), add these lines before `EOF`:

```sh
AI_CLAUDE_APP="/Applications/Claude.app"
AI_CLAUDE_APP_DATA_PREFIX="\$HOME/.claude-app-"
AI_GUI_APPS="claude"
```

(Note the escaped `\$HOME` to match the surrounding lines.)

- [ ] **Step 3: Verify install.sh syntax**

Run: `sh -n install.sh`
Expected: exit 0.

- [ ] **Step 4: Update `docs/COMMANDS.md`**

Replace the `ai gui` line in the top code block with:

```
ai gui     <personal|company> [--browser] [--dry-run]      # native Claude app, isolated per account (macOS)
```

Then add this bullet under `## Rules`:

```markdown
- **`ai gui`** launches the native Claude desktop app with a per-account
  `--user-data-dir` (`~/.claude-app-<account>`), so personal and company stay logged
  in separately and simultaneously. If `Claude.app` is absent (or on non-macOS), it
  falls back to the browser identity path. `--browser` forces that fallback;
  `--dry-run` prints the exact `open` command without launching. App data dirs are
  separate from the CLI roots (`~/.claude-<account>`).
```

- [ ] **Step 5: Update `README.md`**

In the opening example block, change the `ai gui company` comment to reflect native-app behavior:

```sh
ai gui    company              # open the company Claude desktop app (isolated profile)
```

- [ ] **Step 6: Update `CHANGELOG.md`**

Add an entry at the top under an Unreleased/most-recent heading (match the file's existing style):

```markdown
- `ai gui` now launches the native Claude desktop app isolated per account
  (`--user-data-dir=~/.claude-app-<account>`) on macOS, with browser fallback,
  plus `--browser` and `--dry-run` flags. `ai doctor` reports gui apps.
```

- [ ] **Step 7: Final verification**

```bash
zsh -n bin/ai && sh -n install.sh && ./bin/ai gui company --dry-run && ./bin/ai doctor | grep -F 'gui desktop apps:'
```
Expected: all succeed (exit 0), dry-run prints the native command, doctor shows the gui section.

- [ ] **Step 8: Commit**

```bash
git add examples/router.env.example install.sh docs/COMMANDS.md README.md CHANGELOG.md
git commit -m "docs: document ai gui native desktop app isolation"
```

---

## Self-Review

**Spec coverage:**
- §2 mechanism (`open -n -a --user-data-dir`) → Task 1 Steps 4, 6. ✓
- §3 behavior (native / fallback / non-macOS / `--browser` / `--dry-run`) → Task 1 Step 6. ✓
- §4 app registry (one-line extension) → Task 1 Step 3 (`gui_app_bundle`/`gui_app_dataprefix` + `AI_GUI_APPS`). ✓
- §5 separate data dirs → `AI_CLAUDE_APP_DATA_PREFIX` distinct from CLI prefix; Task 3 Step 1 note. ✓
- §6 router.env keys → Task 1 Step 2 defaults + Task 3 Steps 1-2. ✓
- §7 error handling (missing bundle → warn+fallback; mkdir -p; invalid id) → Task 1 Steps 4, 6. ✓
- §8 doctor augmentation → Task 2. ✓
- §9 testing (dry-run, doctor, manual) → Task 1 Step 9, Task 2 Step 4; manual noted below. ✓
- §11 docs → Task 3. ✓
- §12 out of scope respected (Claude only; no axis generalization; chatgpt/codex commented as future). ✓

**Placeholder scan:** none — all steps contain concrete code/commands.

**Type/name consistency:** `gui_app_bundle`, `gui_app_dataprefix`, `_has_app_bundle`, `_launch_app_isolated`, `_gui_browser`, `cmd_gui`, `AI_GUI_APPS`, `AI_CLAUDE_APP`, `AI_CLAUDE_APP_DATA_PREFIX` — used identically across Tasks 1-3. ✓

**Manual check (not automatable here):** after Task 1, run `./bin/ai gui personal` and `./bin/ai gui company` on a Mac with `Claude.app` installed; confirm two Claude windows each stay logged into a different account across restarts.

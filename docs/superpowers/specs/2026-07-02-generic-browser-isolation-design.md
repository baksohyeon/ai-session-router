# Generic browser isolation for `ai gui`

**Date:** 2026-07-02
**Status:** Approved (design)
**Branch:** `feat/generic-browser-isolation`

## Problem

The `ai gui` browser path is hardcoded and forces conventions on the user:

- `personal` → Microsoft Edge (fixed)
- `company` → Google Chrome + profile `Work` + company URLs (fixed)
- Only two identities exist, and the *company* path requires the user to have
  pre-created a named Chrome profile.

Everyone's default browser, profiles, and accounts differ. Requiring a specific
browser (Edge/Chrome) or a pre-existing profile is a hidden mandate that breaks
for anyone whose setup doesn't match.

## Insight

The desktop-app path already solved isolation the right way: Chromium-based apps
accept `--user-data-dir=<path>`, which **creates an isolated instance with its own
storage, auto-creating the directory** — no pre-existing profile required. The
Claude desktop app uses exactly this (`bin/ai:139-142`).

Browsers (Edge/Chrome/Brave/Arc/Chromium) are all Chromium and accept the same
flag. So the browser path can use the identical mechanism as the desktop app.

**Signing into the browser account inside an isolated data-dir triggers Chromium
sync** — bookmarks, extensions, passwords, history all populate. So the "clean
slate" cost is paid exactly once per identity, then sync fills it in. The result
is equivalent to a profile, without requiring the user to pre-create one.

## Design

### Principle

One identity = one isolated browser instance, launched via `--user-data-dir`.
Nothing is forced: no required browser, no required profile, no interactive
prompt on every launch.

### Two mechanisms (default + opt-in)

| Mechanism | Flag | Requires setup? | Use |
|-----------|------|-----------------|-----|
| **Isolated data-dir** (default) | `--user-data-dir=<prefix><id>` | No — auto-created | Zero-setup clean isolation, mirrors desktop-app path |
| **Existing profile** (opt-in) | `--profile-directory=<name>` | Yes — profile must exist | Reuse an existing browser profile's logins/bookmarks |

Default is the data-dir mechanism because it forces nothing. A user who already
has profiles they like (and wants existing logins/extensions immediately) opts
into the profile mechanism per identity via config.

### Config contract (`router.env`)

New generic vars. Per-identity vars use a `_<id>` suffix, resolved in zsh via
indirect expansion (`${(P)var}`).

```sh
# Default browser for isolated GUI launches (macOS app name / linux binary).
# Empty → auto-detect first available Chromium browser; else OS default browser.
AI_BROWSER="Microsoft Edge"

# Prefix for per-identity isolated user-data dirs; router appends <id>.
# e.g. AI_BROWSER_DATA_PREFIX="$HOME/.ai-browser-" → ~/.ai-browser-company
AI_BROWSER_DATA_PREFIX="$HOME/.ai-browser-"

# Optional per-identity overrides (all optional; unset → fall back to defaults):
AI_GUI_BROWSER_personal=""              # override AI_BROWSER for this identity
AI_GUI_BROWSER_company=""
AI_GUI_URLS_personal=""                 # space-separated URLs to open on launch
AI_GUI_URLS_company="https://chatgpt.com/ https://claude.ai/"
AI_GUI_PROFILE_personal=""              # set → opt into --profile-directory instead of data-dir
AI_GUI_PROFILE_company=""
```

**Backward compatibility:** the old `AI_CHROME_COMPANY_PROFILE`,
`AI_COMPANY_CHATGPT_URL`, `AI_COMPANY_CLAUDE_URL` are honored as fallbacks when
the new vars are unset, so existing configs keep working. Migration is documented
but not forced.

### Resolution logic (`_gui_browser <id>`)

1. `browser = AI_GUI_BROWSER_<id>` → else `AI_BROWSER` → else first detected
   Chromium browser → else OS default (open URLs only, warn, hint `ai gui setup`).
2. `urls = AI_GUI_URLS_<id>` (else legacy company URL fallback).
3. `profile = AI_GUI_PROFILE_<id>`.
4. If `profile` non-empty → launch `browser --profile-directory="$profile" $urls`.
   Else → launch `browser --user-data-dir="${AI_BROWSER_DATA_PREFIX}<id>" $urls`.
5. Never hard-block: an unresolved browser falls back to the OS default browser
   opening the URLs, plus a hint to run `ai gui setup`.

### `ai gui setup` subcommand

A one-time, opt-in helper — detection at setup, config at runtime:

- Detect installed Chromium browsers (Edge, Chrome, Brave, Arc, Chromium) per OS.
- For each, read `Local State` and list existing profiles by display name (for the
  opt-in profile mechanism).
- Prompt the user to map each identity → (browser, isolated | profile, URLs).
- Write/update only the relevant `AI_*` lines in `router.env`; never clobber
  unrelated lines; support `--print` (dry-run) to show what it would write.

If the user never runs `setup`, defaults still work (isolated data-dir with the
default/auto-detected browser). `setup` is convenience, not a gate.

### Cross-platform

- **macOS**: `open -na "<browser app>" --args <flags> <urls>`
- **Linux**: resolve a browser binary (`microsoft-edge`, `google-chrome`,
  `chromium`, …) and run `<bin> <flags> <urls> &`.
- Non-Chromium / unknown → OS default browser opens URLs, warn.

### `ai doctor` additions

- Show resolved browser per identity, the mechanism (data-dir vs profile), and
  the resolved data-dir / profile, with exists/missing status.
- Keep the desktop-app section unchanged.

## What stays the same

- Desktop-app isolation (`--user-data-dir` for `Claude.app`) — untouched.
- Native mode still runs first on macOS; the (now generic) browser path remains
  the fallback and the `--browser` forced path.
- The user's everyday browser (launched by clicking its icon → default data-dir)
  is never touched.

## Non-goals (YAGNI)

- No profile *creation* automation beyond what `--user-data-dir` gives for free.
- No sync configuration — that is the browser's own account feature.
- No GUI; `ai gui setup` is a terminal prompt flow.

## File-level work breakdown (disjoint, parallelizable)

- **A — core (`bin/ai`)**: generic `_gui_browser`, indirect per-id resolution,
  new launch helper, `ai gui setup`, arg parsing, doctor updates, legacy fallbacks.
- **B — config (`examples/router.env.example`, `install.sh`)**: new default
  config block + comments; keep never-clobber behavior.
- **C — docs (`README.md`, `docs/ARCHITECTURE.md`, `docs/COMMANDS.md`)**: describe
  the generic model, the two mechanisms, `ai gui setup`, and migration notes.

The var names and command surface above are the fixed contract all three follow.

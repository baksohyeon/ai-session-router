# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.2.0] - 2026-07-04

### Added

- `ai pick`: an interactive picker (bare `ai` on a TTY does the same) that walks
  tool → identity → account with numbered prompts and enter-for-default, then
  dispatches to the exact same code paths as the explicit commands. Pure zsh, no
  dependencies; bare `ai` in scripts/CI (non-TTY) still prints usage.
- `ai remote doctor` upgrades: detects the macOS GUI-app Tailscale (whose CLI
  hides inside the app bundle and refuses symlinks), falls back to a plain TCP
  probe for the sshd check (unprivileged `lsof` can't see root's listener), and
  lists herdr sessions alongside tmux/zellij.
- `docs/en/FAQ.md` + `docs/ko/FAQ.md`: Raspberry Pi limits, what syncs between
  machines and what can't, the honest three-case answer on working around a
  corporate network, and the identity-layer map (machine/account/workspace/
  browser) with ASCII diagrams. Claims verified against the official Claude
  Code / Codex / Chromium docs; linked from both READMEs.
- `ai doctor` and `ai profiles` now report per-account content (skills count,
  plugin marketplaces, config presence, never secrets) and `ai doctor` warns when
  an account is logged in but unpopulated (0 skills). This surfaces the hollow-shell
  failure mode (auth present, empty content) that otherwise stays hidden until an
  account starts with no skills or config.

### Changed

- `docs/*/REMOTE-ACCESS.md` restructured Tailscale-first (EN+KO): the mesh-VPN
  path is now §1, networking theory and the pre-Tailscale toolbox moved to an
  appendix TL;DR, a tmux/zellij/Herdr/mosh trade-off table was added, and the
  field-tested gotchas (node key expiry, GUI-app CLI alias, Remote Login on the
  wrong Mac, stale auth URLs, Pi power-supply reboot loops) are folded in. The
  Korea-specific appendix is now present in both languages.
- `AI_BROWSER` defaults to empty (auto-detect: edge → chrome → brave → arc →
  chromium, else the OS default browser) instead of hardcoding Microsoft Edge;
  `install.sh` no longer seeds Edge into fresh configs. Explicit configs keep
  working; machines with Edge resolve to Edge via auto-detect as before.
- `install.sh` warns when zsh is missing and targets `~/.bashrc` in the PATH
  hint for bash users.
- `ai gui` no longer launches the Codex desktop app. Codex resolves its account,
  config, plugins, and skills from `CODEX_HOME`, not from an Electron
  `--user-data-dir`, so isolating the Electron shell did nothing for the account
  (and only cluttered the dock). Codex is now CLI-first via `ai codex <account>`,
  which sets `CODEX_HOME` for real isolation. `AI_GUI_APPS` defaults to `claude`.

### Fixed

- `ai remote doctor`'s Funnel/Serve checks invoked bare `tailscale` instead of
  the resolved binary path, so they failed on GUI-app installs.
- On a stock macOS without the Command Line Tools, `ai gui setup` could trigger
  the `/usr/bin/python3` stub's GUI "install developer tools?" dialog; the stub
  is now detected and skipped (profile listing degrades to the isolated
  data-dir default, as documented).

### Removed

- `AI_CODEX_APP` and `AI_CODEX_APP_DATA_PREFIX` config vars (no longer read;
  Codex desktop is not gui-isolated). See the note above.

## [0.1.1] - 2026-07-03

### Added
- Korean README (`README.ko.md`) with a language toggle in both READMEs, plus release
  and license badges and a releases link on the README.

## [0.1.0] - 2026-07-03

### Added
- `ai zellij <personal|company>`: attach or create a Zellij session `ai-<workspace>`
  using a layout-as-code file (`AI_ZELLIJ_LAYOUT`, default `share/zellij/ai.kdl`). `ai tmux`
  stays as the ubiquitous remote fallback. `ai doctor` reports zellij availability and
  `ai remote doctor` lists zellij sessions.
- Config-driven named profiles via `AI_PROFILES` (space-separated; defaults to
  `personal company`). Every command now accepts any configured name (e.g.
  `ai claude client1`, `ai resolve codex client1`), and `ai doctor` / `ai logs` /
  `ai profiles list` / keychain keep-set enumerate the full set. Each extra profile
  `<name>` gets config roots `${AI_CLAUDE_ROOT_PREFIX}<name>` / `${AI_CODEX_ROOT_PREFIX}<name>`
  and a workspace from `AI_WS_<name>` (fallback `$HOME/dev/<name>`). Fully
  backward-compatible: with `AI_PROFILES` unset, personal/company behave exactly as before.
- `ai remote doctor` now surfaces exposed local control-plane risk (T5): read-only
  detection of TCP listeners bound off-loopback (`lsof` on macOS, `ss` on linux),
  flagging agent-runtime processes (codex/claude/mcp/node) and common control-plane
  ports as WARNINGs; a HIGH-RISK warning when Tailscale Funnel (public internet) is
  active; Tailscale Serve reported as informational. Prints process name + bind
  address + port only, never command-line args or secrets, and changes nothing.
- `scripts/smoke.sh`: a safe, read-only/dry-run smoke battery (runs under zsh or bash)
  covering `ai resolve`, `profiles`, `doctor`/`remote doctor`/`logs`, `gui --dry-run`,
  `gui setup --print`, and `keychain list`, plus a secret-leak scan. It never launches an
  interactive session, opens a browser/app, or prunes; exits non-zero on any failure.
- Docs: `WSL-LINUX.md` (EN + KO): exact WSL and Linux setup, how to run the smoke
  battery, and an explicit verified-vs-not table (macOS verified; Linux static-audited
  with script; Windows/WSL static + script, not live-tested here). Linked from SUPPORT.md.
- `ai gui` now launches the native Claude desktop app isolated per account
  (`--user-data-dir=~/.claude-app-<account>`) on macOS, with browser fallback, plus
  `--browser` and `--dry-run` flags. `ai doctor` reports gui apps and their data dirs.
  Native isolation is Electron-only; ChatGPT (native AppKit) stays on the browser path.
- `ai gui` also isolates the native Codex desktop app (Electron, verified via `app.asar`)
  per account (`--user-data-dir=~/.codex-app-<account>`); `AI_GUI_APPS` defaults to
  `claude codex`, so one command opens both isolated.
- Generic browser isolation for `ai gui`: `AI_BROWSER` plus per-identity overrides,
  isolated `--user-data-dir` by default, and `ai gui setup` to auto-detect browsers.
- `ai keychain list|prune` to audit and clean orphaned Claude Keychain credentials on
  macOS (dry-run by default; `--force` is fail-closed and confirm-gated).
- `ai doctor` per-account auth-isolation checks (Claude Keychain-hash verification, Codex
  auth mode / permission / clone detection) plus `CLAUDE_CODE_OAUTH_TOKEN` /
  `ANTHROPIC_API_KEY` environment warnings.
- `ai profiles [list | show <account>]`: account-centric inventory of each profile's
  workspace, config roots, and redacted auth status (presence and file mode only, never
  token contents).
- Docs: `THREAT-MODEL.md` (assets, trust boundaries, 7 threats + residual risk) and
  `SURFACES.md` (per-surface isolation for every OpenAI/Anthropic surface, credentials by
  OS, Tailscale) with official vendor doc links.
- Bilingual docs under `docs/en` and `docs/ko` with a Language switcher; new `SUPPORT.md`
  (tool/surface/OS support matrix, mechanisms, official doc links) and `HOW-IT-WORKS.md`.
- Initial extraction into a standalone, OS-generic project.
- `bin/ai` router with platform abstraction (macOS + Linux paths).
- `install.sh` idempotent bootstrap with `router.env` config.
- Config override layer: `${XDG_CONFIG_HOME:-~/.config}/ai-session-router/router.env`.
- Docs: ARCHITECTURE, COMMANDS, PORTABILITY; CONTRIBUTING; examples.
- `.gitignore` that excludes all account roots and logs.

### Changed
- `ai claude` / `ai codex` keep the current directory when it is already inside the
  selected workspace, and only relocate to the workspace root (with a warning) when
  launched from outside it. Previously they always moved to the workspace root.

### Notes
- macOS fully tested. Linux paths provided and smoke-tested, not yet verified on a
  real Linux desktop (browser GUI especially).
- MCP intentionally kept out of the core; `share/mcp/` are optional placeholders.

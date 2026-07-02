# Support status: tools, surfaces, and platforms

**Language:** English · [한국어](../ko/SUPPORT.md)

What the router isolates, on which surface, and on which OS. This is the "does my
combination work?" page. For the command syntax see [COMMANDS.md](COMMANDS.md); for
install and first run see the [Quick start](../../README.md#quick-start).

## Introduction

`ai` runs Claude Code, Codex, and their chat GUIs so that a personal identity and a work
identity never mix. You pick a tool, an account, and a surface (terminal, desktop app, or
browser); the router points that tool at a per-account location before launching it. What
that "location" is depends on the tool and the surface, which is why some combinations
isolate cleanly and one or two cannot. This page lists every combination and why.

## Quick start

```sh
git clone <this-repo> ~/dev/personal/ai-session-router
cd ~/dev/personal/ai-session-router
./install.sh                 # creates dirs + config, symlinks ~/.local/bin/ai
ai doctor                    # verify the whole setup
ai codex company -- login    # log in once per account
ai gui setup                 # detect browsers, write per-identity mappings
```

## Commands (summary)

```
ai claude|codex  <personal|company> [--account personal|company] [-- tool-args...]
ai gui           <personal|company> [--browser] [--dry-run]
ai gui setup     [--print]
ai shell|tmux    <personal|company>
ai resolve <claude|codex> <personal|company> [--account ...]    # dry-run preview
ai profiles      [list | show <personal|company>]              # account inventory (redacted)
ai doctor | ai remote doctor | ai logs
```

Full reference: [COMMANDS.md](COMMANDS.md).

## Support status, by tool and surface

| Tool / surface | Isolated? | Mechanism | Notes |
|---|---|---|---|
| **Claude Code (CLI)** | yes | `CLAUDE_CONFIG_DIR` | config, sessions, plugins, skills per account |
| **Claude desktop app** | yes | `--user-data-dir` (Electron) | `ai gui`. The app embeds Claude Code, so the desktop GUI and the CLI run the same engine |
| **Claude in a browser** | yes | dedicated profile or isolated user-data dir | `ai gui --browser` |
| **Codex (CLI)** | yes | `CODEX_HOME` | login is a plaintext `auth.json` in that dir, so isolation is fully reliable |
| **Codex desktop app (Electron)** | yes | `--user-data-dir` (Electron) | verified Electron (ships `app.asar`); `ai gui` opens it isolated alongside Claude |
| **ChatGPT desktop app** | no | none available | a native macOS (AppKit) app ignores `--user-data-dir`; use a browser profile instead |
| **ChatGPT in a browser** | yes | dedicated profile | `ai gui company` opens chatgpt.com in the company profile |

## Support status, by OS

| | macOS | Linux | Windows |
|---|---|---|---|
| CLI (`claude` / `codex`) | yes | yes | yes, inside WSL only |
| Desktop-app isolation | yes (`open -n -a --user-data-dir`) | not applicable | no: the router does not drive Windows apps |
| Browser isolation | yes (Edge / Chrome) | yes (chrome / chromium) | needs a WSL to Windows browser bridge |
| Shell | zsh (system default) | install zsh | **WSL + zsh (never PowerShell)** |
| Status | fully tested | provided, smoke-tested | reviewed statically, not live-tested here |

## Windows: use WSL, not PowerShell

`bin/ai` is a zsh script (`#!/usr/bin/env zsh`). PowerShell and CMD cannot run it at all.
On Windows:

1. Install WSL and a Linux distro.
2. Install zsh inside WSL and run `ai` from the **WSL terminal** (not PowerShell, not CMD).
3. CLI sessions (`ai claude`, `ai codex`) work there.
4. GUI isolation does not carry over: the router launches macOS or Linux apps, not Windows
   `.exe` apps, so open the Windows Claude app on its own.

## Why each mechanism works

Every tool resolves its account state from one place, and the router points that place at a
per-account folder. The lever differs per tool. (Vendor docs move; verify flags at the
version you run.)

- **Claude Code, `CLAUDE_CONFIG_DIR`.** Claude Code reads all of its state from one config
  directory. On macOS the OAuth token sits in the Keychain under a service name derived from
  that directory's path, so each config dir gets its own Keychain entry. Docs:
  [authentication](https://code.claude.com/docs/en/authentication),
  [CLI reference](https://code.claude.com/docs/en/cli-reference).
- **Codex, `CODEX_HOME`.** Codex resolves config, `auth.json`, history, and sessions from
  `CODEX_HOME`. The login is a plaintext file inside it, so two homes never share a login
  (and you must never copy `auth.json` between them, since refresh tokens are single-use).
  Docs: [Codex auth](https://developers.openai.com/codex/auth),
  [config](https://developers.openai.com/codex/config-advanced).
- **Electron desktop apps, `--user-data-dir`.** Electron embeds Chromium, which stores all
  profile data under `--user-data-dir`. Passing a per-account dir gives each launch its own
  login. That is why the Claude desktop app isolates, and the Codex desktop app too (it is Electron).
  Reference: [Chromium command-line switches](https://peter.sh/experiments/chromium-command-line-switches/).
- **Native AppKit apps (ChatGPT.app), no lever.** A native macOS app ignores Chromium flags,
  so `--user-data-dir` does nothing. ChatGPT's own web account switching stays in the browser
  and does not reach Codex. Docs:
  [ChatGPT account switching](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching).
- **Browsers, `--profile-directory` / `--user-data-dir`.** Chrome and Edge keep separate
  logins per profile or per user-data dir, so one identity per profile stays clean.

## Known gaps and behavior notes

- **Codex desktop app**: isolated (it is Electron). `ai gui` opens Claude.app and Codex.app
  together, each pinned to the account's own `--user-data-dir`. Set `AI_GUI_APPS` to one
  name to open just one.
- **ChatGPT desktop app**: cannot be isolated (AppKit). Use `ai gui --browser`.
- **Windows GUI**: out of scope. The router handles the WSL CLI, not Windows-native apps.
- **Windows and Linux**: reviewed by reading the code, not live-tested from the macOS host.
- **Starting directory**: `ai claude` and `ai codex` keep you where you are when the current
  directory is already inside the selected workspace; only when you launch from outside the
  workspace do they move you to its root (with a warning). `ai gui` ignores your location.

See also [ARCHITECTURE.md](ARCHITECTURE.md), [PORTABILITY.md](PORTABILITY.md),
[CODEX-AUTH.md](CODEX-AUTH.md), [SURFACES.md](SURFACES.md), and [THREAT-MODEL.md](THREAT-MODEL.md).

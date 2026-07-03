# WSL and Linux setup

**Language:** English · [한국어](../ko/WSL-LINUX.md)

How to run the router on Linux, and on Windows through WSL. This page covers exact
setup, how to run the read-only smoke battery, and an honest statement of what is
verified versus only statically reviewed. For the OS support matrix by tool and
surface see [SUPPORT.md](SUPPORT.md); for the platform abstraction points inside
`bin/ai` see [PORTABILITY.md](PORTABILITY.md).

## What is verified where

The router is developed and run on macOS. Linux paths are branched in the code and
covered by the smoke script, but the maintainer's host is macOS, so Linux and WSL are
not exercised on real hardware here. Be aware of the distinction before you rely on it.

| Platform | Status | What that means |
|---|---|---|
| macOS | verified | developed and run daily; every command exercised live |
| Linux | static-audited + script provided | every Linux branch reviewed in code; `scripts/smoke.sh` provided to self-verify on a real box; not run on Linux from this host |
| Windows via WSL | static + script, not live-tested here | same Linux code path inside WSL; setup documented; not booted on Windows from this host |

If you run the router on Linux or WSL, running `scripts/smoke.sh` (below) is the way
to confirm the platform branches behave on your machine.

## Linux setup

1. Install `zsh`. The router is a zsh script (`#!/usr/bin/env zsh`).

   ```sh
   sudo apt install zsh      # Debian / Ubuntu
   sudo dnf install zsh      # Fedora
   sudo pacman -S zsh        # Arch
   ```

2. Install the CLIs you use (`claude`, `codex`) per their own instructions, and make
   sure they are on `PATH`.

3. Clone and install the router:

   ```sh
   git clone <this-repo> ~/dev/personal/ai-session-router
   cd ~/dev/personal/ai-session-router
   ./install.sh
   ```

4. Verify:

   ```sh
   ai doctor
   ```

   On Linux, `doctor` reports the distro via `/etc/os-release`, checks for `zsh`,
   `claude`, `codex`, `tmux`, and `tailscale`, and lists your config roots. Credentials
   on Linux live in a file (`~/.claude-<account>/.credentials.json` for Claude,
   `~/.codex-<account>/auth.json` for Codex), so isolation is by `CLAUDE_CONFIG_DIR` and
   `CODEX_HOME` directly. There is no Keychain on Linux, so the `ai keychain` command
   reports that it is not applicable and does nothing.

5. Browser GUI (optional): install a Chromium-family browser (Chrome, Chromium, Edge,
   Brave) and run `ai gui setup`. The router launches the Linux binary
   (`google-chrome`, `chromium`, `microsoft-edge`, and so on) with an isolated
   `--user-data-dir` per identity. If no Chromium browser is found, `ai gui` opens the
   URLs in the default browser via `xdg-open` and warns.

## Windows via WSL: use WSL, never PowerShell

`bin/ai` is a zsh script. PowerShell and CMD cannot run it at all. On Windows you run
it inside WSL, where it presents as Linux.

1. Install WSL and a Linux distro from an elevated PowerShell, then reboot if prompted:

   ```powershell
   wsl --install
   ```

   This installs WSL 2 and Ubuntu by default. This is the only step you do in
   PowerShell; everything after this happens inside the WSL terminal.

2. Open the **WSL terminal** (the Ubuntu app, or `wsl` from a normal terminal). Do the
   rest here, never in PowerShell or CMD.

3. Install `zsh` inside WSL:

   ```sh
   sudo apt update && sudo apt install zsh
   ```

4. Install the CLIs (`claude`, `codex`) inside WSL and confirm they are on `PATH`.

5. Clone and install the router, exactly as on Linux:

   ```sh
   git clone <this-repo> ~/dev/personal/ai-session-router
   cd ~/dev/personal/ai-session-router
   ./install.sh
   ai doctor
   ```

6. Log in once per account from the WSL terminal:

   ```sh
   ai codex company -- login
   ai claude company            # then /login inside the session
   ```

### What works and what does not, under WSL

- **CLI sessions** (`ai claude`, `ai codex`) work inside WSL. They isolate by
  `CLAUDE_CONFIG_DIR` / `CODEX_HOME` the same way they do on Linux.
- **Credentials** live in files under the per-account config roots, isolated by the env
  vars. There is no Windows Credential Manager involvement.
- **GUI isolation does not carry over.** The router launches macOS or Linux apps, not
  Windows `.exe` apps. `ai gui` inside WSL targets Linux browser binaries, which usually
  are not installed in a default WSL image. Open the Windows Claude app on its own, or
  install a Linux browser in WSL if you want the isolated browser path.
- **Always run `ai` from the WSL terminal.** Running it from PowerShell or CMD will not
  work.

## Running the smoke battery

`scripts/smoke.sh` is a safe, read-only and dry-run battery. It runs under zsh or bash
and exercises every non-destructive surface of the router:

- `ai resolve` for each tool and account
- `ai profiles list` and `ai profiles show`
- `ai doctor`, `ai remote doctor`, `ai logs`
- `ai gui <id> --dry-run` and `ai gui setup --print` (these launch nothing)
- `ai keychain list` (attributes only; it never prunes)
- a secret-leak scan that asserts no token-shaped string appears in any output

It never launches an interactive session, never opens a browser or app, and never runs
`keychain prune`. It exits non-zero if any check fails or if a secret pattern is found.

```sh
cd ~/dev/personal/ai-session-router
zsh scripts/smoke.sh       # or: bash scripts/smoke.sh
echo $?                     # 0 means every check passed
```

The script finds `bin/ai` relative to its own location, so it tests the checkout it
lives in regardless of what `ai` resolves to on `PATH`.

A clean run ends with a line like `summary: 21 passed, 0 failed` and exit code 0. On
Linux and WSL the counts differ from macOS (there is no Keychain, and the GUI path
resolves to Linux browsers), but every check that applies should still pass.

## See also

[SUPPORT.md](SUPPORT.md), [PORTABILITY.md](PORTABILITY.md),
[ARCHITECTURE.md](ARCHITECTURE.md), [REMOTE-ACCESS.md](REMOTE-ACCESS.md).

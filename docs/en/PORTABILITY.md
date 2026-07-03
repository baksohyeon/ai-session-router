# Portability & OS support

**Language:** English · [한국어](../ko/PORTABILITY.md)

The router runs regardless of environment. The **core** (env-var
redirection, workspace selection, logging, doctor/resolve) is OS-agnostic. A few
surfaces are platform-specific; helper functions isolate those, so adding an OS is a
one-spot change.

## Support matrix

| Capability             | macOS (tested)            | Linux (provided, smoke-tested) | Notes |
|------------------------|---------------------------|--------------------------------|-------|
| account/workspace/logs | ✅                         | ✅                              | pure env + fs |
| `ai resolve` / `doctor`| ✅                         | ✅                              | OS label via `sw_vers` / `/etc/os-release` |
| transcript (`script`)  | ✅ BSD `script -q F cmd`   | ✅ util-linux `script -q -c "cmd" F` | branched by `$AI_OS` |
| `ai gui personal`      | ✅ `open -a "Microsoft Edge"` | ⚠️ `microsoft-edge[-stable]` | falls back to default browser |
| `ai gui company`       | ✅ Chrome `--profile-directory` | ⚠️ `google-chrome`/`chromium --profile-directory` | needs the binary on PATH |
| sshd check             | ✅ `lsof`                  | ✅ `lsof` or `ss`               | best-effort, no privileges |
| `ai tmux`              | ✅                         | ✅                              | tmux required |

Legend: ✅ implemented & verified · ⚠️ implemented, depends on the browser being
installed; not verified on a real Linux desktop yet.

## Platform abstraction points (in `bin/ai`)

All OS branching lives in a handful of helpers near the top of the script:

- `AI_OS`: set once from `uname -s` (`macos` / `linux` / `other`).
- `_open_url`: `open` (macOS) vs `xdg-open` (Linux).
- `_has_browser` / `_launch_edge` / `_launch_chrome_profile`: app detection + launch.
- `_os_label`: `sw_vers` vs `/etc/os-release` vs `uname`.
- `_sshd_listening`: `lsof` then `ss` fallback.
- `_run_with_transcript`: BSD vs util-linux `script(1)` syntax.

To add a new OS (e.g. WSL, BSD), extend these helpers only.

## Dependencies

- **Required**: `zsh` (the script uses arrays, `setopt`, `${x:t}`), coreutils
  (`date`, `find`, `sed`).
- **Optional**: `tmux` (for `ai tmux`), `script` (for transcripts; degrades to direct
  exec), `tailscale` (for `ai remote doctor`), a Chromium/Edge browser (for `ai gui`).

## Configuration override

Machine-specific values are **not** hardcoded. They come from
`${XDG_CONFIG_HOME:-~/.config}/ai-session-router/router.env` (or env vars), so the same
script works on any machine by shipping a different config:

```sh
AI_PERSONAL_WS="$HOME/dev/personal"
AI_COMPANY_WS="$HOME/work/acme"
AI_CODEX_ROOT_PREFIX="$HOME/.codex-"
AI_CHROME_COMPANY_PROFILE="Acme Work"
AI_PROFILES="personal company client1"   # add arbitrary named profiles
AI_WS_client1="$HOME/dev/clients/acme"   # per-profile workspace (fallback $HOME/dev/client1)
```

`AI_PROFILES` is space-separated and defaults to `personal company`, so leaving it
unset keeps the built-in behavior. Each extra name `<name>` gets config roots
`${AI_CLAUDE_ROOT_PREFIX}<name>` and `${AI_CODEX_ROOT_PREFIX}<name>`, and its workspace
resolves from `AI_WS_<name>` (fallback `$HOME/dev/<name>`). Every command then accepts
the new name, e.g. `ai claude client1` or `ai resolve codex client1`.

## Not yet portable

- The **browser GUI** is desktop-OS-specific; headless/server hosts warn and
  no-op for `ai gui`. That's expected.
- Windows is out of scope (use WSL, which presents as Linux).

## Testing portability

```sh
zsh -n bin/ai                      # syntax (any OS with zsh)
shellcheck -s bash bin/ai || true  # heuristic lint (zsh not fully supported)
./bin/ai resolve codex company --account personal   # pure-logic, OS-agnostic
./bin/ai doctor                    # exercises OS label + browser detection
```

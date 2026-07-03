# Backlog

Non-urgent candidates for the router. Nothing here is committed work; pull an item
into a release when it is ready and record the result in [CHANGELOG.md](CHANGELOG.md).
See [RELEASE.md](RELEASE.md) for how items graduate into a version.

## Candidates

- **Zellij fleet layout.** An opt-in layout where panes preload `ai claude <ws>` /
  `ai codex <ws>` (a per-workspace agent cockpit), alongside the default
  `share/zellij/ai.kdl`. Select via `AI_ZELLIJ_LAYOUT` or a `--fleet` flag.
- **Live-test on Linux and WSL.** Run `zsh scripts/smoke.sh` on a real Linux box and
  under WSL. So far it is static-audited and macOS-run only. Windows must use WSL with
  zsh, never PowerShell.
- **Deepen codex-remote / app-server safety checks.** `ai remote doctor` already flags
  off-loopback listeners and Tailscale Funnel; add probes specific to Codex `app-server`
  (experimental WebSocket) and Claude Code Remote Control exposure.
- **iTerm2 integration.** Local multi-pane is native in iTerm2, so a multiplexer is only
  needed for remote persistence (Tailscale reconnect), which lives host-side. Candidate:
  add `tmux -CC` control-mode support to `ai tmux` (a `--cc` flag) so tmux persistence
  renders as native iTerm2 panes; and document Claude Code `--teammate-mode=iterm2` for
  agent teams.

# Contributing

## Layout

```
bin/ai                 # the router (single self-contained zsh script)
install.sh             # idempotent bootstrap
docs/                  # ARCHITECTURE / COMMANDS / PORTABILITY
share/                 # ~/.ai-shared model + optional MCP placeholders
examples/router.env.example
```

## Ground rules

- **No secrets, ever.** Account roots (`.claude-*`, `.codex-*`) and `.ai-logs/` are
  gitignored. Don't add anything that reads token/credential file *contents*.
- **No machine-specific hardcoding.** New tunables go through `router.env` /
  `AI_*` env vars, not literals in `bin/ai`.
- **Isolate OS-specific code** in the platform helpers (`_open_url`, `_has_browser`,
  `_launch_*`, `_os_label`, `_sshd_listening`, `_run_with_transcript`). Adding an OS
  should touch only those.
- **Non-destructive by default.** Prefer warnings over hard blocks; back up before
  editing user files (`<file>.bak.<timestamp>`); never move originals.

## Checks before a PR

```sh
zsh -n bin/ai                         # must pass
sh  -n install.sh                     # must pass
./bin/ai resolve codex company --account personal   # logic smoke
./bin/ai doctor                       # OS detection smoke
```

If you change behavior, update `docs/COMMANDS.md` and `CHANGELOG.md`.

## Commit style

Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.

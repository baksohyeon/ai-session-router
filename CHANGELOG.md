# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Initial extraction into a standalone, OS-generic project.
- `bin/ai` router with platform abstraction (macOS + Linux paths).
- `install.sh` idempotent bootstrap with `router.env` config.
- Config override layer: `${XDG_CONFIG_HOME:-~/.config}/ai-session-router/router.env`.
- Docs: ARCHITECTURE, COMMANDS, PORTABILITY; CONTRIBUTING; examples.
- `.gitignore` that excludes all account roots and logs.

### Notes
- macOS fully tested. Linux paths provided and smoke-tested, not yet verified on a
  real Linux desktop (browser GUI especially).
- MCP intentionally kept out of the core; `share/mcp/` are optional placeholders.

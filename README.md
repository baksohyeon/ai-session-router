# ai — AI session router

One command to launch **Claude Code** or **Codex** with the right **account**, in the
right **workspace**, with the right **browser identity** — so your personal and work AI
usage never bleed into each other.

```sh
ai claude company              # company account, company workspace
ai codex  personal             # personal account, personal workspace
ai codex  company --account personal   # company workspace, personal account (mix freely)
ai gui    company              # open Chrome on the dedicated work profile
ai doctor                      # diagnose the whole setup
```

## Why

If you use AI CLIs for both personal and work, everything wants to share one global
state dir: the same account, the same billing, the same chat history, the same logs.
`ai` keeps them cleanly separated by treating a "session" as a combination of
**independent axes** you choose explicitly.

| Axis          | Decides                       | Mechanism                                   |
|---------------|-------------------------------|---------------------------------------------|
| **workspace** | files + where logs go         | `cd` into it; logs under `<ws>/.ai-logs/`   |
| **account**   | auth / billing / session      | `CLAUDE_CONFIG_DIR` · `CODEX_HOME`          |
| **browser**   | GUI chat identity             | Edge (personal) / Chrome profile (company)  |
| **Tailscale** | remote entry (reported only)  | `ai remote doctor`                          |

Shared dev tools (`ssh`, git, your editor, secret managers) stay global and untouched.

## How it works (one paragraph)

Claude Code and Codex resolve **all** their state — tokens, sessions, config, agents —
from a single directory pointed to by an env var (`CLAUDE_CONFIG_DIR` / `CODEX_HOME`).
"Switching accounts" is just pointing that var at a different folder before launching.
`ai` wraps that with default rules, guardrails, logging, and per-OS browser/tmux
helpers. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick start

```sh
git clone <this-repo> ~/dev/personal/ai-session-router
cd ~/dev/personal/ai-session-router
./install.sh           # creates dirs, config, and symlinks ~/.local/bin/ai
ai doctor              # verify
```

Then log in once per account, e.g. `ai codex company` → Codex login flow.

## Configuration

`install.sh` writes a config you can edit any time:

```
${XDG_CONFIG_HOME:-~/.config}/ai-session-router/router.env
```

See [examples/router.env.example](examples/router.env.example) for every override
(workspace paths, config-root prefixes, Chrome profile name, company URLs).

## Commands

Full reference: [docs/COMMANDS.md](docs/COMMANDS.md). Summary:

```
ai gui|shell|tmux   <personal|company>
ai claude|codex     <personal|company> [--account personal|company] [-- tool-args...]
ai resolve <claude|codex> <personal|company> [--account ...]   # dry-run preview
ai doctor | ai remote doctor | ai logs
```

## Platform support

zsh required. macOS is fully tested. Linux paths (xdg-open, util-linux `script`,
`ss`-based checks) are provided and smoke-tested. See
[docs/PORTABILITY.md](docs/PORTABILITY.md) for the support matrix.

## Remote access

Running `ai` on one machine and attaching from your phone, another laptop, or anywhere
else — without losing the session when the network drops or the lid closes — is
covered in [docs/REMOTE-ACCESS.md](docs/REMOTE-ACCESS.md)
([한국어](docs/REMOTE-ACCESS-ko.md)). Network fundamentals through Tailscale, SSH,
tmux, sleep control, mobile clients, and end-to-end workflows.

## Security

This repo ships **no secrets**. Account config roots (`~/.claude-*`, `~/.codex-*`) and
logs are never tracked — see [.gitignore](.gitignore). Tokens stay under each account's
own config root. The router only ever reads filenames (never contents) when warning
about secret-looking files near a workspace.

## License

MIT — see [LICENSE](LICENSE).

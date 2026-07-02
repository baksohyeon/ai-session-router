# ai — AI session router

One command to launch **Claude Code** or **Codex** with the right **account**, in the
right **workspace**, with the right **browser identity** — so your personal and work AI
usage never bleed into each other.

```sh
ai claude company              # company account, company workspace
ai codex  personal             # personal account, personal workspace
ai codex  company --account personal   # company workspace, personal account (mix freely)
ai gui    company              # open company GUI in an isolated browser/app instance
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
| **browser**   | GUI chat identity             | one isolated browser instance per identity (`--user-data-dir`) |
| **Tailscale** | remote entry (reported only)  | `ai remote doctor`                          |

Shared dev tools (`ssh`, git, your editor, secret managers) stay global and untouched.

## How it works (one paragraph)

Claude Code and Codex resolve **all** their state — tokens, sessions, config, agents —
from a single directory pointed to by an env var (`CLAUDE_CONFIG_DIR` / `CODEX_HOME`).
"Switching accounts" is just pointing that var at a different folder before launching.
`ai` wraps that with default rules, guardrails, logging, and per-OS browser/tmux
helpers. See [docs/en/ARCHITECTURE.md](docs/en/ARCHITECTURE.md).

## Quick start

```sh
git clone <this-repo> ~/dev/personal/ai-session-router
cd ~/dev/personal/ai-session-router
./install.sh           # creates dirs, config, and symlinks ~/.local/bin/ai
ai doctor              # verify
```

Then log in once per account, e.g. `ai codex company -- login` → Codex login flow.
For OpenAI/Codex specifics — auth modes, API-key profiles, and why ChatGPT web account
switching is **not** Codex account switching — see [docs/en/CODEX-AUTH.md](docs/en/CODEX-AUTH.md).

## Configuration

`install.sh` writes a config you can edit any time:

```
${XDG_CONFIG_HOME:-~/.config}/ai-session-router/router.env
```

See [examples/router.env.example](examples/router.env.example) for every override
(workspace paths, config-root prefixes, per-identity browser/URLs/profile). Or run
`ai gui setup` once to auto-detect installed browsers and write the per-identity
mappings for you.

## Commands

Full reference: [docs/en/COMMANDS.md](docs/en/COMMANDS.md). Summary:

```
ai gui|shell|tmux   <personal|company>
ai gui setup [--print]                                         # detect browsers, write per-identity mappings
ai claude|codex     <personal|company> [--account personal|company] [-- tool-args...]
ai resolve <claude|codex> <personal|company> [--account ...]   # dry-run preview
ai doctor | ai remote doctor | ai logs
```

## Platform support

zsh required. macOS is fully tested. Linux paths (xdg-open, util-linux `script`,
`ss`-based checks) are provided and smoke-tested. See
[docs/en/PORTABILITY.md](docs/en/PORTABILITY.md) for the support matrix.

## Remote access

Running `ai` on one machine and attaching from your phone, another laptop, or anywhere
else — without losing the session when the network drops or the lid closes — is
covered in [docs/en/REMOTE-ACCESS.md](docs/en/REMOTE-ACCESS.md)
([한국어](docs/ko/REMOTE-ACCESS.md)). Network fundamentals through Tailscale, SSH,
tmux, sleep control, mobile clients, and end-to-end workflows.

## Security

This repo ships **no secrets**. Account config roots (`~/.claude-*`, `~/.codex-*`) and
logs are never tracked — see [.gitignore](.gitignore). Tokens stay under each account's
own config root. The router only ever reads filenames (never contents) when warning
about secret-looking files near a workspace. `ai doctor` inspects Codex `auth.json` only
by *presence*, file *mode*, and a non-reversible *fingerprint* — never its contents — and
warns on loose permissions or a cloned (stale-token) copy. Codex auth details:
[docs/en/CODEX-AUTH.md](docs/en/CODEX-AUTH.md).

## License

MIT — see [LICENSE](LICENSE).

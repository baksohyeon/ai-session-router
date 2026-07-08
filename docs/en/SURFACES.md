# Surfaces: what isolates, and how

**Language:** English · [한국어](../ko/SURFACES.md)

> **[Archived]** This project is deprecated; session routing moved to Orca. See [TEARDOWN.md](TEARDOWN.md) to revert. Kept for reference.

Each product has several surfaces: terminal, desktop app, browser, mobile, remote control.
The router isolates local surfaces by pointing them at a per-account state root. It cannot
isolate server-side surfaces (web and mobile account state); for those the separation lives
in the vendor account, and at best a dedicated browser profile. This page lists every surface,
whether the router can isolate it, and the mechanism. Facts are current as of 2026-07-02;
vendor behavior changes, so verify at your version.

## OpenAI / ChatGPT / Codex

| Surface | Router isolates? | How |
|---|---|---|
| ChatGPT web | partial | server-side account; ChatGPT's own switcher holds up to 2 accounts, or use a dedicated browser profile per identity |
| ChatGPT mobile | no | native app, one account at a time; no router reach |
| Codex CLI | yes | `CODEX_HOME` per account (`auth.json` plaintext in-dir) |
| Codex desktop app | no (CLI-first) | reads `CODEX_HOME`, not `--user-data-dir`; use `ai codex <account>` |
| Codex Remote (phone drives host) | no, host-pinned | host must be signed into the same ChatGPT account and workspace |
| Codex `app-server` | transport, not isolated | powers rich clients; WebSocket mode experimental, never expose unauthenticated |

- ChatGPT web account switching keeps chats, memory, billing, files, and workspaces separate, but OpenAI states it is not yet supported in Codex desktop or native ChatGPT mobile: [account switching](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching).
- ChatGPT **Projects** give project-only memory that isolates context to conversations inside the project: [Projects](https://help.openai.com/en/articles/10169521-projects-in-chatgpt).
- ChatGPT **Tasks** (scheduled) can be created from web or mobile: [Tasks](https://help.openai.com/en/articles/10291617-tasks-in-chatgpt).
- ChatGPT **Apps/connectors** use MCP-backed tools; workspace admins control access: [Connectors](https://help.openai.com/en/articles/11487775-connectors-in-chatgpt).
- ChatGPT **Agent** acts with your signed-in sessions, so treat agent, browser, and app use as high-risk: [Agent](https://help.openai.com/en/articles/11752874-chatgpt-agent).
- ChatGPT macOS **Work with Apps** can read content from coding apps: [Work with Apps](https://help.openai.com/en/articles/10119604-work-with-apps-on-macos).
- Codex docs: [auth](https://developers.openai.com/codex/auth), [config](https://developers.openai.com/codex/config-advanced), [CLI reference](https://developers.openai.com/codex/cli/reference), [Remote](https://developers.openai.com/codex/remote-connections), [app-server](https://developers.openai.com/codex/app-server).

## Anthropic / Claude / Claude Code

| Surface | Router isolates? | How |
|---|---|---|
| Claude web | partial | server-side account; personal and org can coexist under one email and switch in the account menu, or use a browser profile |
| Claude mobile | no | native app; cannot start data export or log-out-all-sessions |
| Claude desktop app | partial | uses OAuth, not CLI env vars; isolate the embedded Claude Code via `ai gui`, otherwise switch account in-app |
| Claude Code CLI | yes | `CLAUDE_CONFIG_DIR` per account; macOS login isolated by a per-config-dir Keychain hash (verified, version-dependent) |
| Claude Code desktop app | yes | the Claude desktop app embeds Claude Code; `ai gui` isolates it with `--user-data-dir` |
| Claude Code Remote Control | no, session-pinned | web or mobile drives one local session over outbound HTTPS, no inbound port; Claude.ai login only, no API keys; needs v2.1.51+ |

- Claude runs on web, desktop, and mobile: [getting started](https://support.anthropic.com/en/articles/8114491-getting-started-with-claude).
- Personal and org accounts under one email switch from the account menu; conversations and projects stay separate: [profiles](https://support.anthropic.com/en/articles/9267400-can-i-migrate-or-merge-two-profiles-that-use-claude-ai).
- Data export: web and desktop can, mobile cannot ([export](https://support.anthropic.com/en/articles/9450526-how-can-i-export-my-claude-ai-data)). Log out of all sessions: web only ([log out all](https://support.anthropic.com/en/articles/10310342-how-do-i-log-out-of-all-active-sessions)).
- **Projects**: self-contained workspaces with their own history and knowledge; Team/Enterprise add visibility controls: [projects](https://support.anthropic.com/en/articles/9517075-what-are-projects), [visibility](https://support.anthropic.com/en/articles/9519189-manage-project-visibility-and-sharing).
- **Artifacts**: standalone content in a dedicated window, versioned, downloadable, shareable; Cowork live artifacts persist across tasks on paid plans. They live server-side, so export from the UI: [artifacts](https://support.anthropic.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them), [publish/remix](https://support.anthropic.com/en/articles/9547008-publishing-and-remixing-artifacts), [live artifacts](https://support.anthropic.com/en/articles/14729249-use-live-artifacts-in-claude-cowork).
- Mobile file create/edit and iOS App Intents/Shortcuts/widgets: [files](https://support.anthropic.com/en/articles/12111783-create-and-edit-files-with-claude), [iOS intents](https://support.anthropic.com/en/articles/10263469-using-claude-app-intents-shortcuts-and-widgets-on-ios).
- Connectors: web connectors on Claude, Cowork, Desktop, and Mobile; desktop extensions on Desktop: [connectors](https://support.anthropic.com/en/articles/11176164-pre-built-web-connectors-using-remote-mcp).
- Claude Code runs in terminal, IDE, desktop, and browser; Pro/Max share one subscription across surfaces: [overview](https://docs.anthropic.com/en/docs/claude-code/overview), [Pro/Max](https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan).
- Auth storage and precedence (IAM): macOS Keychain; `apiKeyHelper`/`ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN` apply to CLI surfaces only, while Desktop and cloud sessions use OAuth: [IAM](https://docs.anthropic.com/en/docs/claude-code/iam).
- Settings, memory, transcripts, devcontainer, remote control, gateway: [settings](https://docs.anthropic.com/en/docs/claude-code/settings), [memory](https://docs.anthropic.com/en/docs/claude-code/memory), [data usage](https://docs.anthropic.com/en/docs/claude-code/data-usage), [devcontainer](https://docs.anthropic.com/en/docs/claude-code/devcontainer), [remote control](https://docs.anthropic.com/en/docs/claude-code/remote-control), [LLM gateway](https://docs.anthropic.com/en/docs/claude-code/llm-gateway).

## Claude Code credentials, by OS

- macOS: Keychain. The service name derives from the config-dir path, so each `CLAUDE_CONFIG_DIR` gets its own entry (verified per-dir isolation, undocumented and version-dependent).
- Linux: `~/.claude/.credentials.json`, mode 0600, or under `CLAUDE_CONFIG_DIR` when set.
- Windows: `%USERPROFILE%\.claude\.credentials.json`, or under `CLAUDE_CONFIG_DIR` when set. Run the router through WSL with zsh, never PowerShell.

## Tailscale (remote reach)

- Serve: private inside the tailnet, ACLs apply. Prefer this or SSH: [Serve](https://tailscale.com/docs/features/tailscale-serve).
- Funnel: public internet. Opt-in only and high-risk; never expose an unauthenticated agent control plane through it: [Funnel](https://tailscale.com/docs/features/tailscale-funnel).
- Auth keys, OAuth clients, and tags provision and gate non-user devices: [auth keys](https://tailscale.com/docs/features/access-control/auth-keys), [OAuth clients](https://tailscale.com/docs/features/oauth-clients), [tags](https://tailscale.com/docs/features/tags).

See [THREAT-MODEL.md](THREAT-MODEL.md) and [SUPPORT.md](SUPPORT.md).

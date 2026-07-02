# Threat model

**Language:** English · [한국어](../ko/THREAT-MODEL.md)

What the router protects, what it does not, and the risks that remain. The router's job is to
keep the active account, tool, state root, and network exposure visible and separate. It does
not add security the vendors do not provide. Read this before trusting it with a work account.

## Assets

- Credentials: Codex `auth.json`, Claude Keychain entries, API keys, OAuth tokens.
- Local state: config, chat history, session transcripts, project memory, plugins.
- Code and data: the repos and files in each workspace.
- Identity: which account (personal or company) is active on each surface.
- Network reach: any local control plane (Codex `app-server`, Claude Code Remote Control, an MCP server, a local web UI) that a remote client can drive.

## Trust boundaries

- Per-account state roots (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`) separate personal from company on disk.
- The macOS Keychain separates Claude logins per config dir (verified on this machine, version-dependent).
- The tailnet is a private boundary; Tailscale Funnel punches through it to the public internet.
- The vendor server holds web and mobile account state the router cannot reach.

## Threats and mitigations

### T1. Credential leakage
Tokens or keys end up in logs, transcripts, git, or terminal output.
- Mitigation: the router never prints or copies `auth.json`, `.credentials.json`, tokens, keys, or Keychain secrets. `ai doctor` and `ai keychain` read presence, file mode, and a non-reversible fingerprint only. `.gitignore` excludes every account root and log.
- Residual: your own commands can still leak (do not `cat auth.json`). Codex `auth.json` is plaintext at mode 600, so anyone with disk read access sees it.

### T2. Wrong-account use
You run a work task under the personal account, or send company code to a personal account.
- Mitigation: `ai <tool> <workspace>` defaults the account to the workspace; `--account` mixes deliberately, and a personal-workspace-with-company-account mismatch warns. `ai resolve` previews the exact account and env before launch.
- Residual: the warning does not block. `ai doctor` shows which Keychain entry exists, not which account is live; confirm with `/status` in-session.

### T3. Cross-contamination of memory and history
Claude Code memory or Codex history from one account bleeds into another.
- Mitigation: separate state roots keep `history.jsonl`, transcripts, and memory per account.
- Residual: Claude Code auto-memory is keyed per git repo, so two accounts working the SAME repo share that repo's memory. Split it with `autoMemoryDirectory` or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. Never copy `auth.json` between roots; Codex refresh tokens are single-use and the copy goes stale.

### T4. Accidental personal/work mixing
You are in a personal repo but launch the company account, or the reverse.
- Mitigation: the workspace axis pins files and logs. Launching from inside a workspace keeps you there; launching from outside warns and moves you to the workspace root. Logs land under the workspace, so a session's provenance is on disk.
- Residual: nothing stops a wrong workspace-to-path mapping in `router.env`.

### T5. Exposing a local agent control plane
Codex `app-server`, Claude Code Remote Control, an MCP server, or a local web UI becomes reachable from the network.
- Mitigation: the router never opens inbound ports. Remote access is documented as Tailscale Serve (private, ACL-gated) or SSH. Funnel (public internet) is opt-in and flagged high-risk. Codex `app-server` WebSocket mode is experimental; do not expose it unauthenticated.
- Residual: Claude Code Remote Control uses outbound HTTPS with no inbound port (lower risk), but anyone with your Claude.ai login can drive that session. Funnel, once enabled, is the public internet.

### T6. Artifact and session provenance loss
You cannot tell which account or workspace produced an artifact, transcript, or patch.
- Mitigation: transcripts are written under `<workspace>/.ai-logs/<tool>/<account>-account/`, so the path records tool, account, and workspace. `ai logs` lists them.
- Residual: web and mobile artifacts (ChatGPT canvases, Claude Artifacts) live server-side and the router does not capture them. Export them from the vendor UI.

### T7. Mobile remote-control ambiguity
You drive a local session from a phone and cannot tell which local account or host it controls.
- Mitigation: Codex Remote requires the host to be signed into the same ChatGPT account and workspace; Claude Code Remote Control drives one specific local session. `ai doctor` and `ai remote doctor` report host state.
- Residual: the vendor apps, not the router, decide which session a phone attaches to. Sign out to cut remote control.

## What the router does NOT protect against

- Vendor server-side account state (web and mobile logins, Projects, Artifacts).
- Malware or another local user reading your disk or Keychain.
- A wrong `router.env` mapping.
- Anything you paste or pipe yourself.

See [SURFACES.md](SURFACES.md) for per-surface isolation and [SUPPORT.md](SUPPORT.md) for the support matrix.

# Orchestration Plan — multi-machine · multi-account · multi-agent (draft)

**Language:** English · [한국어](../ko/ORCHESTRATION-PLAN.md)

> Status: **draft for review** (2026-07-02, committed on `main`). Extends [ARCHITECTURE.md](ARCHITECTURE.md).
> Research basis: primary sources (Claude Code / Codex CLI docs, GitHub) surveyed mid-2026.
> Treat exact flags/model IDs as *verify-at-invocation* — both CLIs auto-update.

## 0. What you're actually asking for

"멀티 머신 멀티 계정 멀티 에이전트 멀티 서브에이전트 … 리모트·로컬 다, 가능하면 Codex↔Claude Code 오케스트레이션." Decomposed into independent axes (same philosophy as the v1 router):

| Axis | Values | v1 status | This plan |
|------|--------|-----------|-----------|
| **machine** | this Mac, other Macs, remote box | entry only (`ai remote doctor` + Tailscale) | promote to a routing dimension |
| **account** | personal · company | ✅ `CLAUDE_CONFIG_DIR` / `CODEX_HOME` | **harden Claude/macOS auth** (see §4) |
| **tool** | claude · codex | ✅ launches either | let one **drive** the other (§3) |
| **workspace** | personal · company tree | ✅ `cd` + logs | unchanged; add worktrees |
| **agents** | 1 → N parallel (+ subagents) | none | native fleet + orchestrator (§2, §5) |

The router's v1 thesis (a session = orthogonal axes, each pinned by an env var) is **validated by primary sources**. This plan adds three axes — *fleet*, *cross-tool*, *machine-as-target* — without changing that core.

## 1. What changed since v1 was written (the leverage)

1. **Claude Code now ships a native fleet surface.** `claude agents [--json]` (monitor/dispatch parallel background sessions), `claude --bg/--background` + `attach/logs/stop/respawn/rm <id>`, `claude daemon status|stop` (supervisor), `--worktree/-w` + `--tmux`, **agent teams** (`--teammate-mode {in-process|auto|tmux|iterm2}`, shared task-list), and **Remote Control** (`claude remote-control` — drive a local session from claude.ai / mobile). → *Don't rebuild a fleet manager; route around the native one.*
2. **Cross-orchestration Codex↔Claude is real, and MCP is the glue.** Both run headless with structured JSON, both are MCP clients, and **both can be exposed AS an MCP server**. So ARCHITECTURE §6 ("MCP out of scope") is now the thing to revisit.
3. **The one macOS detail worth pinning down in the current design:** ARCHITECTURE §3 says "account = which folder" via `CLAUDE_CONFIG_DIR`. On macOS, Claude Code stores OAuth in the **Keychain**, not in the config dir (`~/.claude-*/.credentials.json` don't exist; Keychain holds `Claude Code-credentials[-<hash>]`). Isolation per `CLAUDE_CONFIG_DIR` **does work** — the service name is `Claude Code-credentials-<hash>` where hash = `sha256(absolute config-dir path)[:8]` (no trailing slash), and the default `~/.claude` uses the bare unsuffixed name. Verified on Claude Code v2.1.198: `~/.claude-personal` → `0414a328`, `~/.claude-company` → `98bf7d2c`, both present as distinct entries. Caveat: this mechanism is **undocumented and version-dependent** — re-verify after upgrades; it is not a contract. Codex is clean (`auth.json` is a plaintext file under `CODEX_HOME`). → §4 verifies this.

## 2. Codex ↔ Claude Code cross-orchestration (concrete)

Both directions work today:

- **Claude drives Codex:** register `codex mcp-server` (Codex over stdio, exposes `codex()` / `codex-reply()` tools, stateful via `threadId`) in Claude's `--mcp-config`.
- **Codex drives Claude:** `codex mcp add` the community wrapper `steipete/claude-code-mcp` (exposes a single `claude_code` tool with a `permissionMode` arg). No first-party "Claude as MCP server" flag yet.

Headless building blocks:
- **Codex:** `codex exec "task" --json -o out.txt --output-schema s.json`, `--sandbox {read-only|workspace-write|danger-full-access}`, `-a {untrusted|on-request|never}`, `codex exec resume`.
- **Claude:** `claude -p --output-format stream-json --json-schema '…'`, `--allowedTools`, `--permission-mode`, `--mcp-config`, `--bare` (skip auto-discovery for reproducible scripted calls — note `--bare` ignores `CLAUDE_CODE_OAUTH_TOKEN`, use `ANTHROPIC_API_KEY`).
- **Claude Agent SDK** (renamed from "Claude Code SDK"): TS `@anthropic-ai/claude-agent-sdk`, Py `claude-agent-sdk`.
- Reference: OpenAI Cookbook "Building Consistent Workflows with Codex CLI & Agents SDK" (orchestrator calls `codex mcp-server` concurrently, each with its own cwd/profile — the same isolation the router already does).

**Router fit:** the per-account isolation you already enforce is exactly what makes *"personal-account orchestrator drives company-account worker"* safe. This becomes a new verb (§5).

## 3. Multi-machine (remote + local)

Standard, verified stack — already half-documented in [REMOTE-ACCESS.md](REMOTE-ACCESS.md):
- **Tailscale** (mesh + Tailscale SSH, no public SSH) + **tmux/zellij** (survives disconnect) + laptop/phone client.
- Coordination substrate options: **shared task file/queue** (Claude agent teams' live list), **lock-based** (`claude_code_agent_farm`), **git branch-per-agent + PR/checkpoint merge** (uzi / claude-squad / crystal).
- **git worktrees** = dominant isolation primitive (now native: `claude -w`). Caveat: worktrees isolate *files, not runtime* (shared ports/DBs/caches; disk blows up fast) — `dagger/container-use` (fresh container per agent/branch) closes that gap when needed.

OSS orchestrators worth studying before building (all repo-verified): `smtg-ai/claude-squad`, `devflowinc/uzi`, `Dicklesworthstone/claude_code_agent_farm`, `dagger/container-use`, `stravu/crystal`, `mco-org/mco` (multi-CLI). Discovery: `andyrewlee/awesome-agent-orchestrators`.

## 4. Harden the account axis (do this regardless of fleet plans)

The router's most-used guarantee — account isolation — holds on macOS, but the mechanism is undocumented, so the hardening is to **verify** it rather than assume it.

- **Claude (macOS): isolation is verified-working.** Each `CLAUDE_CONFIG_DIR` gets its own Keychain entry named `Claude Code-credentials-<hash>`, hash = `sha256(absolute config-dir path)[:8]` (no trailing slash); the default `~/.claude` uses the bare unsuffixed name. Verified on v2.1.198 (`~/.claude-personal` → `0414a328`, `~/.claude-company` → `98bf7d2c`, both present as distinct entries). This is **undocumented and version-dependent** — treat it as re-verify-after-upgrade, not a contract.
- **The two "robust fixes" previously floated here are both macOS dead-ends — do NOT pursue either:**
  1. **Force file-based `.credentials.json` per root** — there is *no supported macOS switch* for this (the feature request is still open). Only Linux/Windows write creds to a file; on macOS the store is always the Keychain.
  2. **Per-account `CLAUDE_CODE_OAUTH_TOKEN`** — triggers issue #37512: a token-env launch silently *deletes* the shared `Claude Code-credentials` Keychain entry on process exit, breaking the VS Code extension and other sessions. Separately, `ANTHROPIC_API_KEY` **outranks** subscription OAuth in Claude Code's auth-precedence chain, so exporting a key can silently bill the API account instead of the subscription plan.
- **Codex:** already fully isolated by `CODEX_HOME`. One rule to encode: **never clone `auth.json` between roots** (refresh tokens are single-use; the copy goes stale). `ai doctor` should warn if two roots share an `auth.json` fingerprint.
- **What shipped — `ai doctor` verification (not assumption):** for each Claude account it computes `sha256(config-dir)[:8]`, runs `security find-generic-password -s "Claude Code-credentials-<hash>"` for **presence only** (never reads the secret), and reports `isolated ✓` or `not logged in`, flagging the mechanism as version-dependent. It also **warns** when `CLAUDE_CODE_OAUTH_TOKEN` (#37512) or `ANTHROPIC_API_KEY` (billing precedence) are set in the environment, and warns on a cloned Codex `auth.json`. This directly prevents a repeat of the "which account is even active?" confusion.

## 5. Target architecture — phased

### Phase A — Router-as-launcher + native fleet (recommended near-term, thinnest)
Keep `ai` as the env-var/guardrail launcher. Add verbs that shell into Claude Code's native fleet, one pane per account×workspace:
- `ai fleet <ws> [--account X] [-n N]` → `claude agents` / `--bg` + tmuxp layout.
- `ai worktree <ws> <branch>` → `claude -w` in an isolated worktree.
- Remote stays Tailscale SSH + tmux (documented). No new daemon.
- Cross-orchestration opt-in: `ai claude … --mcp-config <codex-mcp-server.json>`.

### Phase B — MCP mesh control plane (medium)
Each machine runs a per-account runtime (Claude Agent SDK / Codex-via-Agents-SDK) that both consumes and exposes MCP (`codex mcp-server`, `claude-code-mcp`). A thin broker (SQLite queue / NATS / Redis over the tailnet) routes task envelopes to `machine × tool × account`. `ai` becomes the **bootstrapper** that launches each node with the right `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / token. You own retries/dedup.

### Phase C — Durable control plane (heaviest; only if reliability demands it)
Same node runtimes as B, but **Temporal** underneath for crash-proof, resumable long-running remote jobs (worker-per-machine maps onto remote+local topology). Adopt only when "the job survived my laptop sleeping" is a hard requirement.

**Recommendation:** ship **A** now (low risk, immediate value, reuses native primitives), spike **B** as a `ai orchestrate` prototype driving one Codex worker from one Claude orchestrator across two accounts, defer **C** until a real durability need appears.

## 6. Concrete next steps

1. **✅ (shipped)** Harden §4 in `ai doctor` — presence-only Keychain isolation check per account + `CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY`/cloned-`auth.json` warnings. Pure diagnostics, no behavior change.
2. **(small)** Revise ARCHITECTURE §3 (macOS auth caveat) and §6 (MCP now in-scope as an axis).
3. **(Phase A)** Add `ai worktree` and `ai fleet` verbs wrapping native Claude flags; add tmuxp layout templates per account×workspace.
4. **(Phase A)** Add an optional `share/mcp/codex-mcp-server.json` and `ai claude … --orchestrate-codex` sugar to wire `codex mcp-server` into a Claude session.
5. **(Phase B spike)** `ai orchestrate` PoC: Claude(personal, orchestrator) → Codex(company, worker) via MCP, one task, structured-JSON round-trip, logged to the workspace transcript.

## 7. Open decisions (need your call before building)
- **Auth hardening: resolved (§4).** Both former candidates (file-based creds, env-token wrapper) are macOS dead-ends; native `CLAUDE_CONFIG_DIR` isolation is verified-working and `ai doctor` now verifies it. No decision needed here. (Headless/remote unattended runs remain an open question for §5 — but not via a per-account OAuth token, given #37512.)
- **Fleet coordination substrate:** git-branch-per-agent (simplest, PR-review-friendly) vs shared-task-file (tighter, Claude-native) vs container-per-agent (heaviest, true runtime isolation).
- **Cross-orchestration default identity:** which account is the orchestrator vs the worker (billing/rate-limit implications).
- **Scope of "multi-machine" for v1:** just this Mac + one remote box, or a genuine N-node tailnet fleet?

## 8. Flagged / verify-before-relying
- `Claude Code-credentials-<sha256(config-dir)[:8]>` hash-suffix: verified-working (v2.1.198) but **undocumented and version-dependent** — re-verify after upgrades; not a contract. `ai doctor` checks presence per account.
- `codex mcp-server` reads as newer/experimental — pin a Codex version.
- Conductor / Nimbalyst are products, not confirmed OSS repos; `vibe-kanban` is sunsetting; `parruda/claude-swarm` URL is dead.
- Exact model IDs and repo star counts are point-in-time.

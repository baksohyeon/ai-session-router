# Guard, observability, and modularization for `ai`

**Date:** 2026-07-07
**Status:** Phase 1 implemented (guard + `ai status` + prompt segment; print-only installers). Phases 2–3 pending.
**Branch (suggested):** `feat/guard-observability`

## Phase 1 — as-built (2026-07-07)

- Installers are **print-only** (decided): `ai guard install` / `ai prompt install`
  print the exact `source` line to paste into `~/.zshrc`; they never edit any rc.
- All shell output is ASCII English (no emoji), per host preference / encoding.
- New: `share/shell/guard.zsh`, `share/shell/prompt.zsh`; `bin/ai` gains
  `_profile_from_root`, `cmd_status` (`status`/`where`), `cmd_guard`, `cmd_prompt`,
  and a top-level `AI_ROOT` (repo root must be resolved outside a function — zsh
  `FUNCTION_ARGZERO` makes `$0` the function name inside `cmd_*`).
- Coverage: `scripts/smoke.sh` extended (+6 checks → 27 passing).

## Problem

Three distinct anxieties, surfaced while auditing the router on this host:

1. **Bare tools escape routing silently.** `~/.local/bin/claude` and
   `~/.local/bin/codex` point straight at the tool binaries. The router's whole
   isolation contract is a single env var (`CLAUDE_CONFIG_DIR` / `CODEX_HOME`)
   exported *before* exec. There is **no global export** in `~/.zshrc`. So in a
   fresh terminal that was not launched through `ai`, typing `claude` falls back
   to the default `~/.claude` — neither `personal` nor `company`, a third
   unrouted identity — with no warning. The maintainer cannot trust their own
   muscle memory. (Verified 2026-07-07: `~/.claude/skills` is a real copy, not a
   shared symlink, so it is genuinely a separate account, not a mirror.)

2. **Global state is invisible.** At any moment there is no cheap way to answer
   "which account am I on right now, and does my cwd match it?" The information
   exists (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, cwd vs workspace) but is never
   surfaced. This is what makes sessions feel like they might be "tangled."

3. **The router is a 1,475-line monolith.** `bin/ai` is one self-contained zsh
   file. It is well-sectioned but large enough that reasoning about any one
   concern requires scrolling past nine others. This raises the perceived risk
   of every change.

## Insight

These are **three orthogonal axes**, and conflating them leads to the wrong tool:

| Anxiety | Correct axis | Wrong fix |
|---------|--------------|-----------|
| Bare tool escapes routing | **Guard** (safety) | — |
| "Which account am I on?" | **Observability** (status + prompt) | splitting files |
| 1,475-line file | **Modularization** (readability) | a Makefile |

Splitting the file does **not** make runtime state visible — that needs a status
command and a prompt segment. And a `Makefile` **cannot** replace the router:
`make` runs recipes in child processes, so an `export CLAUDE_CONFIG_DIR=…` never
propagates back to the interactive shell. The router must run *in* the shell and
`exec` into it; that is intrinsically a shell-function/script job, not a build
target. A Makefile is still valuable — but only as a **task runner for repo dev
tasks** (install/test/lint/release), never as the dispatch mechanism.

## Design

### Axis 1 — Guard (refuse mode)

Ship an **interactive-shell-only** guard that intercepts bare `claude`/`codex`
and refuses when routing is absent. Chosen behavior (decided 2026-07-07):
**refuse**, with an explicit escape hatch.

Mechanism: a zsh function sourced from `~/.zshrc`, e.g. `share/shell/guard.zsh`:

```sh
# sourced only by interactive shells (~/.zshrc); NOT seen by the router script,
# which runs non-interactively and never sources ~/.zshrc — so router-internal
# `claude`/`codex` calls are unaffected.
_ai_guard() {  # $1 = tool, $2 = env var name
  [[ -n "${AI_GUARD_OFF:-}" ]] && return 0          # explicit opt-out
  [[ -n "${(P)2:-}" ]] && return 0                  # routed → allow
  print -ru2 -- "ai-guard: '$1' was run without routing."
  print -ru2 -- "  → ai $1 personal   (personal)"
  print -ru2 -- "  → ai $1 company    (company)"
  print -ru2 -- "  really want bare ~/.$1: AI_GUARD_OFF=1 $1"
  return 1
}
claude() { _ai_guard claude CLAUDE_CONFIG_DIR || return 1; command claude "$@"; }
codex()  { _ai_guard codex  CODEX_HOME        || return 1; command codex  "$@"; }
```

Why this shape:

- **Interactive-only.** Functions live in `~/.zshrc`, which scripts do not
  source. The router (`bin/ai`) calls `command claude` / the binary directly, so
  its own launches never hit the guard. Zero blast radius on routing.
- **Refuse, not reroute.** Matches the decision: no silent default-to-personal
  that could bill company work to personal.
- **Escape hatch.** `AI_GUARD_OFF=1 claude` for the rare deliberate bare run.
- **Reversible.** Remove one `source` line to disable.

Installer: `ai guard install` appends a single guarded `source` line to
`~/.zshrc` (idempotent, marked with a `# >>> ai-guard >>>` fence like other
tools do), and `ai guard uninstall` removes the fence. `ai guard status` reports
whether the fence is present and whether the current shell has it active.

### Axis 2 — Observability

**`ai status`** (alias `ai where`) — one command, answers "where am I":

```
$ ai status
profile:   personal            (derived from CLAUDE_CONFIG_DIR)
claude:    CLAUDE_CONFIG_DIR=~/.claude-personal   auth ✓   skills 256
codex:     CODEX_HOME=(unset)  → bare codex would use ~/.codex
cwd:       ~/dev/personal/ai-session-router
workspace: ~/dev/personal      ✓ cwd is inside the personal workspace
guard:     installed ✓   active in this shell ✓
```

Derivation rule: map the active `CLAUDE_CONFIG_DIR` / `CODEX_HOME` back to a
profile name by reversing `cfg_root` (strip the `AI_CLAUDE_ROOT_PREFIX` /
`AI_CODEX_ROOT_PREFIX`). Unset → report "unrouted (bare would use default)".
This reuses the existing `cfg_root` / `ws_path` / profile-enumeration helpers;
much of the print logic already exists near `bin/ai:1405-1420` and can be
lifted into `lib/status.zsh`.

**Prompt segment** (opt-in, `share/shell/prompt.zsh`) — the always-on "never
lose track" fix. Adds a right-prompt token when routed:

```
~/dev/personal/ai-session-router                          [claude:personal]
```

- Reads `CLAUDE_CONFIG_DIR` / `CODEX_HOME` from the live env (no subprocess, no
  per-prompt cost beyond a parameter read).
- Colorized by profile so `personal` vs `company` are visually distinct.
- Installed/removed via `ai prompt install` / `ai prompt uninstall`, same fenced
  `~/.zshrc` approach as the guard.

### Axis 3 — Modularization

Thin entrypoint + sourced library modules. Proposed layout:

```
bin/ai            # entry: platform detect, resolve real dir (readlink the
                  #   symlink → repo), source lib/*.zsh, dispatch subcommands
lib/config.zsh    # defaults, router.env load, cfg_root, ws_path, profile validation
lib/resolve.zsh   # cmd_resolve — the core env-inject + cd + exec
lib/browser.zsh   # browser isolation / launch
lib/doctor.zsh    # ai doctor
lib/status.zsh    # ai status / ai where          (new, Axis 2)
lib/guard.zsh     # ai guard install|uninstall|status  (new, Axis 1)
lib/prompt.zsh    # ai prompt install|uninstall   (new, Axis 2)
lib/gui.zsh       # ai gui
lib/remote.zsh    # ai remote / tailscale reporting
```

Self-location contract (the one new failure mode to get right):

```sh
# bin/ai must find its lib/ even when invoked via the ~/.local/bin/ai symlink.
0_real=${0:A}                       # zsh: resolve symlinks + absolutize
AI_LIB=${0_real:h:h}/lib            # <repo>/bin/ai → <repo>/lib
[[ -d $AI_LIB ]] || { print -ru2 -- "ai: cannot locate lib/ ($AI_LIB)"; exit 1 }
for m in config resolve browser doctor status guard prompt gui remote; do
  source "$AI_LIB/$m.zsh"
done
```

**Honest tradeoff.** Today's single file = one symlink, zero path resolution,
perfect portability. Splitting adds the "find my lib" step and a new way to
break (moved repo, partial checkout). Mitigation: `${0:A}` resolution + explicit
fail-fast, and the module split is done **last**, behind the smoke test, one
module at a time.

### Rejected alternative — Makefile as router

Documented so it is not re-proposed: `make ai-personal` would `export` inside a
recipe subshell that dies before the interactive shell sees it. Make cannot
`exec` the user into a routed session. Rejected. Make is adopted **only** as a
dev-task runner (below).

### Makefile (dev tasks only)

```make
make install    # wrap install.sh
make test       # scripts/smoke.sh
make lint       # zsh -n bin/ai lib/*.zsh  (syntax check)
make guard      # ai guard install
make prompt     # ai prompt install
make release    # RELEASE.md procedure
```

## Sequencing

Deliberately staged so trust lands first and the risky refactor comes last
behind a safety net.

- **Phase 1 — safe slice (low risk, high relief).** Add `lib/`-free versions of:
  guard (refuse) + `ai status` + prompt segment, wired into the existing
  monolith as new subcommands / shipped shell snippets. No restructuring of
  existing code. This alone closes anxieties #1 and #2.
- **Phase 2 — test coverage.** Extend `scripts/smoke.sh` to assert: routed
  launch sets the right env; `ai status` reports the right profile; guard
  refuses when unset and allows when set / when `AI_GUARD_OFF=1`.
- **Phase 3 — modularization.** With smoke green, extract `lib/*.zsh` one module
  at a time, running `make test` after each extraction. Add the Makefile.

Each phase is independently shippable and independently revertible.

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Guard breaks router-internal `claude` calls | Guard is interactive-only; scripts don't source `~/.zshrc`; router uses `command claude` / binary path. Smoke test asserts a routed launch still works. |
| Guard blocks a legitimate bare run | `AI_GUARD_OFF=1` escape hatch, documented in the refuse message itself. |
| Module split can't find `lib/` | `${0:A}` symlink resolution + fail-fast error; split done last, behind smoke test, one module per commit. |
| Prompt segment slows the shell | Pure parameter read, no subprocess per prompt. |
| `~/.zshrc` edits corrupt shell config | Idempotent fenced blocks (`# >>> ai-guard >>>`), `uninstall` removes cleanly, back up `~/.zshrc` before first write. |

## Open questions

- `ai status` output: human table (above) only, or also a `--porcelain`
  machine-readable form for scripts/prompt reuse?
- Prompt segment: right-prompt (`RPROMPT`) vs left-prompt injection — default to
  `RPROMPT` to avoid fighting an existing theme (Powerlevel10k etc.)?
- Should `ai guard install` also offer to install the prompt segment in the same
  step (bundle), or keep them independent subcommands?
```

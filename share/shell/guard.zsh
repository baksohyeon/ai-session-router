# ai-guard: refuse bare `claude` / `codex` when the session is not routed by `ai`.
#
# Sourced ONLY by interactive shells (add the `source` line to ~/.zshrc yourself;
# see `ai guard install`). The router (bin/ai) runs non-interactively and never
# sources ~/.zshrc, so its own tool launches are unaffected by these functions.
#
# Behavior: refuse mode. If the routing env var is unset, print how to route and
# return non-zero without launching the tool.
# Escape hatch for one deliberate bare run: `AI_GUARD_OFF=1 claude ...`
#
# Disable entirely: remove the `source .../guard.zsh` line from ~/.zshrc.

_ai_guard() {  # $1 = tool name, $2 = routing env var name
  [[ -n "${AI_GUARD_OFF:-}" ]] && return 0        # explicit opt-out for this run
  [[ -n "${(P)2:-}" ]] && return 0                # already routed -> allow
  print -ru2 -- "ai-guard: '$1' was run without routing ($2 is unset)."
  print -ru2 -- "  ->  ai $1 personal    (personal account)"
  print -ru2 -- "  ->  ai $1 company     (company account)"
  print -ru2 -- "  bare ~/.$1 on purpose:  AI_GUARD_OFF=1 $1 ..."
  return 1
}

claude() { _ai_guard claude CLAUDE_CONFIG_DIR || return 1; command claude "$@"; }
codex()  { _ai_guard codex  CODEX_HOME        || return 1; command codex  "$@"; }

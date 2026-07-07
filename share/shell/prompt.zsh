# ai-prompt: show the active routed AI profile in the right prompt (RPROMPT),
# e.g.  [claude:personal]  or  [claude:company codex:company].
#
# Sourced ONLY by interactive shells (add the `source` line to ~/.zshrc yourself;
# see `ai prompt install`). Pure parameter reads, no subprocess per prompt.
#
# The label strips the default config-dir prefixes (~/.claude- / ~/.codex-).
# With a custom AI_*_ROOT_PREFIX the label falls back to the directory tail.
#
# Theme note: if you use Powerlevel10k / Starship / another prompt framework,
# it may manage RPROMPT via precmd hooks and override this. Source this AFTER
# your theme, or add the segment through the theme instead.

_ai_prompt_segment() {
  local seg=""
  [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && seg+="claude:${${CLAUDE_CONFIG_DIR:t}#.claude-} "
  [[ -n "${CODEX_HOME:-}" ]]        && seg+="codex:${${CODEX_HOME:t}#.codex-} "
  [[ -n "$seg" ]] && print -rn -- "%F{cyan}[${seg% }]%f"
}

setopt prompt_subst
# Append to any existing RPROMPT rather than clobbering it.
RPROMPT="${RPROMPT}"'$(_ai_prompt_segment)'

# lib/observability.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

# match; rc 1 if the dir is empty or matches no configured profile.
_profile_from_root() {  # $1 = tool, $2 = dir
  local tool="$1" dir="$2" p
  [[ -n "$dir" ]] || return 1
  for p in ${=AI_PROFILES}; do
    [[ "$(cfg_root "$tool" "$p")" == "$dir" ]] && { print -r -- "$p"; return 0; }
  done
  return 1
}

cmd_status() {  # status | where: routing state of THIS shell (env vars only)
  local ccd="${CLAUDE_CONFIG_DIR:-}" cxh="${CODEX_HOME:-}" cp cx
  cp="$(_profile_from_root claude "$ccd")" || cp=""
  cx="$(_profile_from_root codex "$cxh")" || cx=""

  print -r -- "== ai status =="
  if [[ -n "$ccd" ]]; then
    print -r -- "claude:  routed -> ${cp:-<unknown>}   CLAUDE_CONFIG_DIR=$ccd"
  else
    print -r -- "claude:  UNROUTED   bare 'claude' would use ~/.claude (default)"
  fi
  if [[ -n "$cxh" ]]; then
    print -r -- "codex:   routed -> ${cx:-<unknown>}   CODEX_HOME=$cxh"
  else
    print -r -- "codex:   UNROUTED   bare 'codex' would use ~/.codex (default)"
  fi

  print -r -- "cwd:     $PWD"
  local prof="${cp:-$cx}" wp=""
  if [[ -n "$prof" ]]; then
    wp="$(ws_path "$prof" 2>/dev/null)"
    if [[ -n "$wp" ]]; then
      case "$PWD/" in
        "$wp/"*) print -r -- "ws:      $wp   (cwd is inside the $prof workspace)" ;;
        *)       print -r -- "ws:      $wp   WARNING: cwd is OUTSIDE the $prof workspace" ;;
      esac
    fi
  fi

  local rc found="no"
  for rc in "$HOME/.zshrc" "$HOME/.zprofile"; do
    [[ -f "$rc" ]] && grep -q 'share/shell/guard.zsh' "$rc" 2>/dev/null && found="yes"
  done
  print -r -- "guard:   referenced in shell rc: $found"
  print -r -- "note: 'routed' reflects env vars only; confirm the live Claude account with /status in-session."
}

# Print-only installers: they NEVER edit your shell rc. They print the exact
# `source` line for you to paste into ~/.zshrc yourself (manual, auditable).
cmd_guard() {  # install | status
  local sub="${1:-install}"; (( $# )) && shift
  local snippet="$AI_ROOT/share/shell/guard.zsh"
  case "$sub" in
    install|show|line)
      [[ -f "$snippet" ]] || { print -ru2 -- "ai guard: snippet not found: $snippet"; return 1; }
      print -r -- "# ai-guard (refuse mode): add the line below to ~/.zshrc, then restart your shell."
      print -r -- "# It refuses bare 'claude'/'codex' when the session is not routed by 'ai'."
      print -r -- "# Deliberate bare run:  AI_GUARD_OFF=1 claude ..."
      print -r --
      print -r -- "source \"$snippet\""
      ;;
    status)
      [[ -f "$snippet" ]] && print -r -- "ai guard: snippet: $snippet (present)" \
                          || print -r -- "ai guard: snippet: $snippet (MISSING)"
      local rc found="no"
      for rc in "$HOME/.zshrc" "$HOME/.zprofile"; do
        [[ -f "$rc" ]] && grep -q 'share/shell/guard.zsh' "$rc" 2>/dev/null && found="yes ($rc)"
      done
      print -r -- "ai guard: referenced in shell rc: $found"
      ;;
    *) print -ru2 -- "usage: ai guard <install|status>"; return 2 ;;
  esac
}

cmd_prompt() {  # install | status
  local sub="${1:-install}"; (( $# )) && shift
  local snippet="$AI_ROOT/share/shell/prompt.zsh"
  case "$sub" in
    install|show|line)
      [[ -f "$snippet" ]] || { print -ru2 -- "ai prompt: snippet not found: $snippet"; return 1; }
      print -r -- "# ai-prompt: add the line below to ~/.zshrc, then restart your shell."
      print -r -- "# It shows the active routed profile in the right prompt, e.g. [claude:personal]."
      print -r -- "# Source it AFTER any prompt theme (Powerlevel10k / Starship), which may override RPROMPT."
      print -r --
      print -r -- "source \"$snippet\""
      ;;
    status)
      [[ -f "$snippet" ]] && print -r -- "ai prompt: snippet: $snippet (present)" \
                          || print -r -- "ai prompt: snippet: $snippet (MISSING)"
      local rc found="no"
      for rc in "$HOME/.zshrc" "$HOME/.zprofile"; do
        [[ -f "$rc" ]] && grep -q 'share/shell/prompt.zsh' "$rc" 2>/dev/null && found="yes ($rc)"
      done
      print -r -- "ai prompt: referenced in shell rc: $found"
      ;;
    *) print -ru2 -- "usage: ai prompt <install|status>"; return 2 ;;
  esac
}


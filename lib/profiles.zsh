# lib/profiles.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

_dirmark() { [[ -d "$1" ]] && print -- "(exists)" || print -- "(missing)"; }

# Auth-presence predicates (presence only; NEVER token contents). rc 0 = present.
_claude_auth_present() {  # $1 = claude config root
  local croot="$1" khash ksvc
  [[ -f "$croot/.credentials.json" ]] && return 0
  if [[ "$AI_OS" == macos ]]; then
    khash="$(claude_keychain_hash "$croot")"; ksvc="Claude Code-credentials-$khash"
    [[ -n "$khash" ]] && keychain_service_present "$ksvc" && return 0
  fi
  return 1
}
_codex_auth_present() {  # $1 = codex config root
  local cxroot="$1"
  [[ -f "$cxroot/auth.json" ]] && return 0
  [[ "$(codex_store_pref "$cxroot")" == keyring ]] && return 0
  return 1
}

# Content inventory for a config root (counts only; follows symlinks like the shared store).
# Prints a compact "skills=N ..." summary. rc 0 = has skills, rc 1 = looks unpopulated.
# An account with auth but 0 skills is a hollow shell (the codex-company failure mode).
_content_counts() {  # $1 = tool, $2 = config root
  local tool="$1" root="$2" nskills=0 detail=""
  [[ -d "$root/skills" ]] && nskills=$(ls -1 "$root/skills" 2>/dev/null | wc -l | tr -d ' ')
  case "$tool" in
    claude)
      local nmkt=0
      [[ -d "$root/plugins/marketplaces" ]] && nmkt=$(ls -1 "$root/plugins/marketplaces" 2>/dev/null | wc -l | tr -d ' ')
      detail="skills=$nskills plugins-marketplaces=$nmkt" ;;
    codex)
      local cfgl=0
      [[ -f "$root/config.toml" ]] && cfgl=$(wc -l < "$root/config.toml" 2>/dev/null | tr -d ' ')
      detail="skills=$nskills config.toml=${cfgl}L" ;;
  esac
  print -r -- "$detail"
  [[ "${nskills:-0}" -gt 0 ]]
}

# Redacted auth status for a profile (presence/mode only; NEVER token contents).
_profile_claude_auth() {  # $1 = claude config root
  local croot="$1" khash ksvc
  if [[ -f "$croot/.credentials.json" ]]; then print -r -- "file creds (.credentials.json)"; return; fi
  if [[ "$AI_OS" == macos ]]; then
    khash="$(claude_keychain_hash "$croot")"; ksvc="Claude Code-credentials-$khash"
    if [[ -n "$khash" ]] && keychain_service_present "$ksvc"; then print -r -- "keychain entry present"
    else print -r -- "not logged in (no keychain entry)"; fi
  else
    print -r -- "no creds file"
  fi
}
_profile_codex_auth() {  # $1 = codex config root
  local cxroot="$1" authf="$1/auth.json" store mode
  store="$(codex_store_pref "$cxroot")"
  if [[ -f "$authf" ]]; then mode="$(file_mode "$authf")"; print -r -- "file (auth.json mode ${mode:-?})"
  elif [[ "$store" == keyring ]]; then print -r -- "keyring"
  else print -r -- "not logged in"; fi
}

cmd_profiles() {  # list | show <account> (account-centric inventory). Never prints secrets.
  local sub="${1:-list}"; (( $# )) && shift
  case "$sub" in
    list)
      print -r -- "== ai profiles =="
      local a wp ccr cxr
      for a in ${=AI_PROFILES}; do
        wp="$(ws_path "$a")"
        ccr="$(cfg_root claude "$a")"; cxr="$(cfg_root codex "$a")"
        print -r -- "[$a]  workspace: $wp $(_dirmark "$wp")"
        print -r -- "  claude  $ccr   auth: $(_profile_claude_auth "$ccr")   $(_content_counts claude "$ccr")"
        print -r -- "  codex   $cxr    auth: $(_profile_codex_auth "$cxr")   $(_content_counts codex "$cxr")"
      done
      print -r -- "note: auth = presence only, never token contents. Confirm the live Claude account with /status in-session."
      ;;
    show)
      local a="${1:-}"
      valid_account "$a" || { print -r -- "usage: ai profiles show <personal|company>" >&2; return 2; }
      local wp cr gapp gd
      wp="$(ws_path "$a")"
      print -r -- "== ai profiles: $a =="
      print -r -- "workspace:   $wp $(_dirmark "$wp")"
      cr="$(cfg_root claude "$a")"; print -r -- "claude root: $cr $(_dirmark "$cr")  auth: $(_profile_claude_auth "$cr")  content: $(_content_counts claude "$cr")"
      cr="$(cfg_root codex "$a")";  print -r -- "codex root:  $cr $(_dirmark "$cr")  auth: $(_profile_codex_auth "$cr")  content: $(_content_counts codex "$cr")"
      for gapp in ${=AI_GUI_APPS}; do
        gd="$(gui_app_dataprefix "$gapp" 2>/dev/null)" || continue
        [[ -n "$gd" ]] && { gd="$gd$a"; print -r -- "gui $gapp:    $gd $(_dirmark "$gd")"; }
      done
      print -r -- "logs:        $wp/.ai-logs"
      print -r -- "note: auth = presence only, never token contents."
      ;;
    *) print -r -- "usage: ai profiles <list|show [personal|company]>" >&2; return 2 ;;
  esac
}

# Reverse-map an active config dir back to a profile name. Prints name, rc 0 on

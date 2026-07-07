# lib/doctor.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

cmd_doctor() {
  print -r -- "== ai doctor =="
  print -r -- "OS:      $(_os_label)"
  print -r -- "shell:   ${SHELL:-?}"
  print -r -- "whoami:  $(whoami)"
  print -r -- "HOME:    $HOME"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) print -r -- "PATH:    ~/.local/bin present" ;;
    *) print -r -- "PATH:    ~/.local/bin MISSING" ;;
  esac
  print -r -- ""
  print -r -- "tools:"
  local t p
  for t in claude codex tmux zellij tailscale; do p="$(command -v "$t" 2>/dev/null)"; print -r -- "  $t: ${p:-NOT FOUND}"; done
  command -v zellij >/dev/null 2>&1 || _zellij_install_hint
  _has_browser edge   && print -r -- "  Microsoft Edge: present" || print -r -- "  Microsoft Edge: NOT FOUND"
  _has_browser chrome && print -r -- "  Google Chrome: present"  || print -r -- "  Google Chrome: NOT FOUND"
  print -r -- ""
  print -r -- "workspaces:"
  local ws
  for ws in ${=AI_PROFILES}; do
    print -r -- "  $ws: $(ws_path "$ws")"
  done
  print -r -- "config roots:"
  local a r
  for a in ${=AI_PROFILES}; do
    for t in claude codex; do
      r="$(cfg_root "$t" "$a")"
      [[ -d "$r" ]] && print -r -- "  $t/$a: $r (exists)" || print -r -- "  $t/$a: $r (missing)"
    done
  done
  print -r -- "auth isolation:"
  local acct croot khash ksvc
  for acct in ${=AI_PROFILES}; do
    croot="$(cfg_root claude "$acct")"
    if [[ -f "$croot/.credentials.json" ]]; then
      # Linux/Windows (or a macOS build that ever writes a file): creds live in-dir.
      print -r -- "  claude/$acct: file creds in config root (.credentials.json), isolated by CLAUDE_CONFIG_DIR [ok]"
    elif [[ "$AI_OS" == macos ]]; then
      khash="$(claude_keychain_hash "$croot")"; ksvc="Claude Code-credentials-$khash"
      if [[ -n "$khash" ]] && keychain_service_present "$ksvc"; then
        print -r -- "  claude/$acct: Keychain entry '$ksvc' present: CLAUDE_CONFIG_DIR isolates auth on this Claude Code version (per-dir keychain hash) [ok]"
        print -r -- "               (undocumented + version-dependent; confirms an isolated store exists, not which account; use /status. Re-verify after Claude upgrades.)"
      else
        print -r -- "  claude/$acct: no isolated Keychain entry for this root yet. log in: ai claude $acct  (then /login)."
        print -r -- "               If a future Claude version drops per-dir keychain hashing, this stays empty even when logged in; confirm the active account via /status in-session."
      fi
    else
      print -r -- "  claude/$acct: no creds file yet (login: ai claude $acct then /login)"
    fi
  done
  # Upgrade guard: compare installed Claude Code version to the keychain-verified one.
  if command -v claude >/dev/null 2>&1; then
    local cver; cver="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    if [[ -n "$cver" ]]; then
      if [[ "$cver" == "$AI_CLAUDE_KC_VERIFIED_VER" ]]; then
        print -r -- "  keychain hash scheme: verified for Claude Code $cver [ok]"
      else
        print -r -- "  note: Claude Code $cver differs from keychain-scheme-verified $AI_CLAUDE_KC_VERIFIED_VER: if any account above shows 'no isolated keychain entry' despite being logged in, the per-dir hash scheme may have changed; re-verify with: ai keychain list"
      fi
    fi
  fi
  # Codex auth mode per account: presence + declared store, never token contents.
  local ca cxroot store authf mode
  for ca in ${=AI_PROFILES}; do
    cxroot="$(cfg_root codex "$ca")"; authf="$cxroot/auth.json"; store="$(codex_store_pref "$cxroot")"
    if [[ -f "$authf" ]]; then
      print -r -- "  codex/$ca: file-backed creds present (auth.json), isolated by CODEX_HOME [ok]"
      mode="$(file_mode "$authf")"
      [[ -n "$mode" && "$mode" != 600 && "$mode" != 400 ]] && \
        warn "codex/$ca auth.json mode $mode: treat like a password; run: chmod 600 \"$authf\""
    elif [[ "$store" == keyring ]]; then
      print -r -- "  codex/$ca: keyring-backed (cli_auth_credentials_store=keyring): CODEX_HOME isolates config/history, but the OS keyring entry may be shared; confirm with: ai codex $ca -- login status"
    else
      print -r -- "  codex/$ca: not logged in (store=$store). log in with: ai codex $ca -- login"
    fi
  done
  # Cloned auth.json is a footgun: refresh tokens are single-use and go stale.
  local cx_p cx_c h_p h_c
  cx_p="$(cfg_root codex personal)/auth.json"; cx_c="$(cfg_root codex company)/auth.json"
  if [[ -f "$cx_p" && -f "$cx_c" ]] && command -v shasum >/dev/null 2>&1; then
    h_p="$(shasum -a 256 "$cx_p" 2>/dev/null | awk '{print $1}')"
    h_c="$(shasum -a 256 "$cx_c" 2>/dev/null | awk '{print $1}')"
    if [[ -n "$h_p" && "$h_p" == "$h_c" ]]; then
      print -r -- "  codex: personal & company auth.json IDENTICAL [!] (cloned; re-login one account separately)"
    else
      print -r -- "  codex: personal/company auth.json distinct (isolated [ok])"
    fi
  fi
  print -r -- "  note: ChatGPT web account switching (max 2 accounts) does NOT apply to Codex: each Codex account needs its own CODEX_HOME + login, which is exactly what the router pins."
  # Account content: an account can be logged in yet be a hollow shell (0 skills, near-empty
  # config) so it starts with nothing. auth-present + skills=0 is the codex-company failure mode.
  print -r -- "account content (skills/plugins/config presence, not secrets):"
  local pt pa proot pcounts pok
  for pt in claude codex; do
    for pa in ${=AI_PROFILES}; do
      proot="$(cfg_root "$pt" "$pa")"
      if [[ ! -d "$proot" ]]; then
        print -r -- "  $pt/$pa: config root missing ($proot); create it with: ai $pt $pa"
        continue
      fi
      pcounts="$(_content_counts "$pt" "$proot")"; pok=$?   # plain assignment: $? is _content_counts's rc
      if (( pok == 0 )); then
        print -r -- "  $pt/$pa: $pcounts [ok]"
      else
        if { [[ "$pt" == claude ]] && _claude_auth_present "$proot"; } || \
           { [[ "$pt" == codex  ]] && _codex_auth_present  "$proot"; }; then
          print -r -- "  $pt/$pa: $pcounts"
          warn "$pt/$pa is logged in but unpopulated (0 skills): it will start empty. Copy content from another account, e.g. cp -Rp \"$(cfg_root "$pt" personal)/skills\" \"$proot/skills\" (never copy auth.json)."
        else
          print -r -- "  $pt/$pa: $pcounts (not logged in; set up with: ai $pt $pa)"
        fi
      fi
    done
  done
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    print -r -- "  [!] CLAUDE_CODE_OAUTH_TOKEN set in env: a token-based Claude launch can delete the shared macOS Keychain entry on exit (issue #37512); unset for subscription-OAuth sessions."
  fi
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    print -r -- "  [!] ANTHROPIC_API_KEY set in env: it OUTRANKS subscription OAuth in Claude Code's auth precedence; a claude launch may silently bill the API key instead of your plan. unset it for subscription sessions."
  fi
  print -r -- "gui desktop apps:"
  local gapp gbundle gd
  for gapp in ${=AI_GUI_APPS}; do
    gbundle="$(gui_app_bundle "$gapp")"
    [[ -d "$gbundle" ]] && print -r -- "  $gapp app: $gbundle (present)" \
                        || print -r -- "  $gapp app: $gbundle (NOT FOUND)"
    for a in ${=AI_PROFILES}; do
      gd="$(gui_app_dataprefix "$gapp")$a"
      [[ -d "$gd" ]] && print -r -- "    data/$a: $gd (exists)" \
                     || print -r -- "    data/$a: $gd (missing)"
    done
  done
  print -r -- "gui browser identities:"
  print -r -- "  AI_BROWSER: ${AI_BROWSER:-(unset -> auto-detect)}"
  local bid bpref btarget bprofile bdatadir
  for bid in ${=AI_PROFILES}; do
    bpref="$(_gui_resolve_browser_pref "$bid")"
    if [[ -n "$bpref" ]] && btarget="$(_browser_launch_target "$bpref")"; then :
    elif btarget="$(_browser_first_detected)"; then :
    else btarget=""; fi
    if [[ -z "$btarget" ]]; then
      print -r -- "  $bid: no Chromium browser resolved -> OS default (run 'ai gui setup')"
      continue
    fi
    bprofile="$(_gui_resolve_profile "$bid")"
    if [[ -n "$bprofile" ]]; then
      print -r -- "  $bid: $btarget  mechanism=profile  profile=\"$bprofile\""
    else
      bdatadir="${AI_BROWSER_DATA_PREFIX}${bid}"
      [[ -d "$bdatadir" ]] \
        && print -r -- "  $bid: $btarget  mechanism=data-dir  $bdatadir (exists)" \
        || print -r -- "  $bid: $btarget  mechanism=data-dir  $bdatadir (missing)"
    fi
  done
  print -r -- "log resolution (examples):"
  print -r -- "  company/claude/personal -> $(log_dir company claude personal)"
  print -r -- "config: ${_cfg} $([[ -f "$_cfg" ]] && print -- '(loaded)' || print -- '(defaults)')"
  [[ -x "$HOME/.local/bin/ai" ]] && print -r -- "  ~/.local/bin/ai: present (executable)" || print -r -- "  ~/.local/bin/ai: MISSING"
  command -v ai >/dev/null 2>&1 && print -r -- "  ai on PATH: yes ($(command -v ai))" || print -r -- "  ai on PATH: no"
}


# lib/gui.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

# ---------- generic browser-identity resolution ----------
# Resolve the configured browser name for an identity (before existence check):
#   AI_GUI_BROWSER_<id> -> AI_BROWSER -> (empty; caller auto-detects).
_gui_resolve_browser_pref() {  # $1 = id -> configured browser (may be empty)
  local id="$1"
  local v="AI_GUI_BROWSER_$id"
  local pref="${(P)v:-}"
  [[ -n "$pref" ]] && { print -r -- "$pref"; return 0; }
  # Legacy fallback: a pre-generic config that only set AI_CHROME_COMPANY_PROFILE
  # meant "company -> Google Chrome, that profile". Preserve the browser too so an
  # upgrading config does not silently switch company to Edge.
  if [[ "$id" == company ]]; then
    local pv="AI_GUI_PROFILE_company"
    [[ -z "${(P)pv:-}" && -n "${AI_CHROME_COMPANY_PROFILE:-}" ]] && { print -r -- "Google Chrome"; return 0; }
  fi
  [[ -n "${AI_BROWSER:-}" ]] && { print -r -- "$AI_BROWSER"; return 0; }
  return 0
}

# Resolve URLs for an identity: AI_GUI_URLS_<id> -> legacy company URL fallback.
_gui_resolve_urls() {  # $1 = id -> space-separated URLs (may be empty)
  local id="$1"
  local v="AI_GUI_URLS_$id"
  local urls="${(P)v:-}"
  if [[ -n "$urls" ]]; then print -r -- "$urls"; return 0; fi
  [[ "$id" == company ]] && print -r -- "$AI_COMPANY_CHATGPT_URL $AI_COMPANY_CLAUDE_URL"
  return 0
}

# Resolve opt-in profile for an identity: AI_GUI_PROFILE_<id> -> legacy company profile.
_gui_resolve_profile() {  # $1 = id -> profile name (may be empty)
  local id="$1"
  local v="AI_GUI_PROFILE_$id"
  local profile="${(P)v:-}"
  # Legacy fallback: pre-generic configs set AI_CHROME_COMPANY_PROFILE for company.
  [[ -z "$profile" && "$id" == company ]] && profile="${AI_CHROME_COMPANY_PROFILE:-}"
  print -r -- "$profile"
}

# Generic browser identity path (also the native fallback). Resolution order per spec:
#   browser = AI_GUI_BROWSER_<id> -> AI_BROWSER -> first detected Chromium -> OS default.
#   Never hard-blocks: an unresolved browser opens URLs in the OS default + a hint.
_gui_browser() {  # <id> [--dry-run]
  local id="" dry=0
  while (( $# )); do
    case "$1" in
      --dry-run) dry=1; shift ;;
      *) id="$1"; shift ;;
    esac
  done
  [[ -n "$id" ]] || { print -r -- "usage: ai gui <personal|company>" >&2; return 2; }

  local pref urls profile target datadir source
  pref="$(_gui_resolve_browser_pref "$id")"
  urls="$(_gui_resolve_urls "$id")"
  profile="$(_gui_resolve_profile "$id")"
  local -a urlv=(); [[ -n "$urls" ]] && urlv=(${=urls})

  # Resolve a launchable target: configured pref -> first detected Chromium.
  target=""; source=""
  if [[ -n "$pref" ]]; then
    if target="$(_browser_launch_target "$pref")"; then source="configured"
    else warn "configured browser not found: $pref"; target=""; fi
  fi
  if [[ -z "$target" ]]; then
    if target="$(_browser_first_detected)"; then source="auto-detected"; fi
  fi

  # No Chromium browser resolvable -> OS default opens URLs (never hard-block).
  if [[ -z "$target" ]]; then
    if (( dry )); then
      print -r -- "gui (browser) id=$id"
      print -r -- "  browser:   (none resolved) -> OS default browser"
      print -r -- "  urls:      ${urls:-(none)}"
      print -r -- "  hint:      run 'ai gui setup' to configure a Chromium browser"
      return 0
    fi
    warn "no Chromium browser resolved for '$id'; opening URLs in the OS default browser."
    warn "hint: run 'ai gui setup' to configure a browser for isolated identities."
    (( ${#urlv} )) && _open_url "${urlv[@]}"
    return 0
  fi

  if [[ -n "$profile" ]]; then
    # Opt-in: reuse an existing browser profile.
    if (( dry )); then
      print -r -- "gui (browser) id=$id"
      print -r -- "  browser:   $target ($source)"
      print -r -- "  mechanism: profile (--profile-directory)"
      print -r -- "  profile:   $profile"
      print -r -- "  urls:      ${urls:-(none)}"
      return 0
    fi
    print -r -- "-> gui $id: $target profile \"$profile\"${urls:+ + urls}"
    _launch_browser_profile "$target" "$profile" "${urlv[@]}" \
      || { warn "could not launch $target with profile \"$profile\"."; return 1; }
    return 0
  fi

  # Default: isolated user-data-dir (auto-created, mirrors the desktop-app path).
  datadir="${AI_BROWSER_DATA_PREFIX}${id}"
  if (( dry )); then
    print -r -- "gui (browser) id=$id"
    print -r -- "  browser:   $target ($source)"
    print -r -- "  mechanism: isolated data-dir (--user-data-dir)"
    print -r -- "  data-dir:  $datadir"
    print -r -- "  urls:      ${urls:-(none)}"
    return 0
  fi
  print -r -- "-> gui $id: $target (isolated)  data-dir=$datadir${urls:+ + urls}"
  _launch_browser_isolated "$target" "$datadir" "${urlv[@]}" \
    || { warn "could not launch $target isolated."; return 1; }
  return 0
}

# ---------- ai gui setup helpers ----------
# List existing profile display names from a browser's "Local State" JSON.
# Output: one line per profile, "<dir>\t<display name>". Degrades to nothing if the
# file is unreadable or cannot be parsed (caller falls back to isolated data-dir).
_setup_profiles_for() {  # $1 = browser key
  local dir ls
  dir="$(_browser_localstate_dir "$1")" || return 1
  ls="$dir/Local State"
  [[ -r "$ls" ]] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$ls" <<'PY' 2>/dev/null || return 1
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    info = (data.get("profile") or {}).get("info_cache") or {}
    for d, meta in info.items():
        name = (meta or {}).get("name") or d
        print("%s\t%s" % (d, name))
except Exception:
    sys.exit(1)
PY
  else
    # jq-free, python-free degrade: emit nothing so caller uses isolated data-dir.
    return 1
  fi
}

# Write/update a single `KEY="VALUE"` line in the config file without clobbering
# unrelated lines. Creates the file (and its dir) if missing. Immutable-style:
# builds a new file via a temp then atomically moves it into place.
_cfg_set_var() {  # $1 key, $2 value
  local key="$1" val="$2" target dir tmp found=0 mode=""
  # Follow a symlinked config (dotfiles setups) so we update the real file
  # instead of replacing the symlink with a plain file.
  target="$_cfg"
  if [[ -L "$target" ]]; then
    local link; link="$(readlink "$target")"
    case "$link" in
      /*) target="$link" ;;
      *)  target="${_cfg:h}/$link" ;;
    esac
  fi
  dir="${target:h}"
  mkdir -p "$dir"
  [[ -f "$target" ]] || : > "$target"
  # Same-directory temp so the final mv is an atomic same-filesystem rename.
  tmp="$(mktemp "${dir}/router.env.XXXXXX")" || return 1
  # Preserve the original file's mode (best-effort; macOS then linux stat).
  mode="$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null || true)"
  [[ -n "$mode" ]] && chmod "$mode" "$tmp" 2>/dev/null
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$key="* ]]; then
      # ${(qq)} quotes the value so a sourced router.env can never execute
      # embedded $(...)/backticks and always round-trips exactly.
      print -r -- "$key=${(qq)val}" >> "$tmp"; found=1
    else
      print -r -- "$line" >> "$tmp"
    fi
  done < "$target"
  (( found )) || print -r -- "$key=${(qq)val}" >> "$tmp"
  mv "$tmp" "$target"
}

# Detect installed Chromium browsers; echo "<key>\t<launch-target>" per line.
_setup_detect_browsers() {
  local k target label
  for k in "${_CHROMIUM_KEYS[@]}"; do
    case "$AI_OS" in
      macos) label="$(_browser_macos_app "$k")" ;;
      linux) local bins; bins="$(_browser_linux_bins "$k")"; label="${${=bins}[1]}" ;;
      *) return 0 ;;
    esac
    if target="$(_browser_launch_target "$label")"; then
      printf '%s\t%s\n' "$k" "$target"
    fi
  done
}

# `ai gui setup`: interactive one-time config helper. --print = dry-run (show the
# lines that would be written; touch nothing). Defensive: unreadable Local State
# degrades to isolated data-dir mode for that identity.
cmd_gui_setup() {  # [--print]
  local dry=0
  while (( $# )); do
    case "$1" in
      --print) dry=1; shift ;;
      *) print -r -- "usage: ai gui setup [--print]" >&2; return 2 ;;
    esac
  done

  print -r -- "== ai gui setup =="
  print -r -- "config: $_cfg"
  print -r -- ""

  # Detect installed browsers.
  local -a detected_keys=() detected_targets=()
  local line k t
  while IFS=$'\t' read -r k t; do
    [[ -n "$k" ]] || continue
    detected_keys+=("$k"); detected_targets+=("$t")
  done < <(_setup_detect_browsers)

  if (( ${#detected_keys} == 0 )); then
    print -r -- "No Chromium browsers detected. Identities will use the OS default browser."
    print -r -- "You can still set AI_GUI_URLS_<id> manually in $_cfg."
    return 0
  fi

  print -r -- "Detected Chromium browsers:"
  local i
  for i in {1..${#detected_keys}}; do
    print -r -- "  $i) ${detected_targets[$i]}  [${detected_keys[$i]}]"
  done
  print -r -- ""

  # Collect the config lines to write (immutable accumulation).
  # All locals declared once up front; re-running `local` inside the loop would
  # re-print name=value under some zsh configs, so declare here.
  local -a out_keys=() out_vals=() profs=() profnames=()
  local id choice target key pdir pname use_profile urls default_urls j
  setopt local_options extended_glob
  for id in personal company; do
    print -r -- "--- identity: $id ---"
    # Choose a browser.
    if (( dry )); then
      choice=1  # non-interactive dry-run: assume first detected browser
    else
      print -r -- "Choose browser for '$id' [1-${#detected_keys}] (Enter = 1, s = skip):"
      read -r choice
      [[ "$choice" == s ]] && { print -r -- "  (skipped)"; print -r -- ""; continue; }
      [[ -n "$choice" ]] || choice=1
    fi
    [[ "$choice" == <-> && "$choice" -ge 1 && "$choice" -le ${#detected_keys} ]] || choice=1
    key="${detected_keys[$choice]}"; target="${detected_targets[$choice]}"
    out_keys+=("AI_GUI_BROWSER_$id"); out_vals+=("$target")

    # Mechanism: isolated (default) or an existing profile.
    profs=(); profnames=()
    while IFS=$'\t' read -r pdir pname; do
      [[ -n "$pdir" ]] || continue
      profs+=("$pdir"); profnames+=("$pname")
    done < <(_setup_profiles_for "$key")

    use_profile=""
    if (( ${#profs} )) && (( ! dry )); then
      print -r -- "  Existing profiles in $target:"
      for j in {1..${#profs}}; do
        print -r -- "    $j) ${profnames[$j]}  [${profs[$j]}]"
      done
      print -r -- "  Use an existing profile? Enter number, or Enter for isolated data-dir:"
      read -r use_profile
    elif (( ${#profs} == 0 )); then
      (( dry )) || print -r -- "  (no readable profiles; using isolated data-dir)"
    fi

    if [[ -n "$use_profile" && "$use_profile" == <-> && "$use_profile" -ge 1 && "$use_profile" -le ${#profs} ]]; then
      out_keys+=("AI_GUI_PROFILE_$id"); out_vals+=("${profs[$use_profile]}")
    else
      # Isolated data-dir: clear any stale profile override.
      out_keys+=("AI_GUI_PROFILE_$id"); out_vals+=("")
    fi

    # URLs.
    default_urls="$(_gui_resolve_urls "$id")"
    if (( dry )); then
      urls="$default_urls"
    else
      print -r -- "  URLs to open for '$id' (space-separated, Enter = ${default_urls:-none}):"
      read -r urls
      [[ -n "$urls" ]] || urls="$default_urls"
    fi
    out_keys+=("AI_GUI_URLS_$id"); out_vals+=("$urls")
    print -r -- ""
  done

  # Write or preview.
  if (( dry )); then
    print -r -- "Would write to $_cfg:"
    local n
    for (( n = 1; n <= ${#out_keys}; n++ )); do
      print -r -- "  ${out_keys[$n]}=${(qq)out_vals[$n]}"
    done
    return 0
  fi

  local n
  for (( n = 1; n <= ${#out_keys}; n++ )); do
    _cfg_set_var "${out_keys[$n]}" "${out_vals[$n]}"
  done
  print -r -- "Wrote ${#out_keys} setting(s) to $_cfg"
  return 0
}

cmd_gui() {  # <personal|company|setup> [--browser] [--dry-run] [--print]
  # Subcommand: `ai gui setup` (interactive config helper; --print for dry-run).
  if [[ "${1:-}" == setup ]]; then
    shift
    cmd_gui_setup "$@"; return
  fi

  local id="" browser=0 dry=0
  while (( $# )); do
    case "$1" in
      --browser) browser=1; shift ;;
      --dry-run) dry=1; shift ;;
      --*) print -r -- "usage: ai gui <personal|company> [--browser] [--dry-run]" >&2; return 2 ;;
      *) id="$1"; shift ;;
    esac
  done
  valid_ws "$id" || { print -r -- "usage: ai gui <personal|company|setup> [--browser] [--dry-run]" >&2; return 2; }

  # Forced browser, or no native GUI on this OS -> generic browser identity path.
  if (( browser )) || [[ "$AI_OS" != macos ]]; then
    if (( dry )); then _gui_browser "$id" --dry-run; return; fi
    _gui_browser "$id"; return
  fi

  # Native mode: launch each configured app, isolated by account.
  local app bundle datadir missing=0
  for app in ${=AI_GUI_APPS}; do
    bundle="$(gui_app_bundle "$app")" || { warn "unknown gui app: $app"; continue; }
    datadir="$(gui_app_dataprefix "$app")$id"
    if (( dry )); then
      print -r -- "gui (native, macOS) app=$app id=$id"
      if [[ -d "$bundle" ]]; then print -r -- "  bundle:   $bundle (exists)"
      else print -r -- "  bundle:   $bundle (MISSING -> real run uses browser fallback)"; fi
      print -r -- "  data-dir: $datadir"
      print -r -- "  command:  open -n -a \"$bundle\" --args --user-data-dir=\"$datadir\""
      continue
    fi
    if _has_app_bundle "$bundle"; then
      print -r -- "-> gui $id: $app app (isolated)  data-dir=$datadir"
      _launch_app_isolated "$bundle" "$datadir"
    else
      warn "$app app not found at $bundle; using browser fallback."
      missing=1
    fi
  done
  (( missing )) && _gui_browser "$id"
  return 0
}

cmd_shell() {  # personal|company
  local ws="${1:-}"
  valid_ws "$ws" || { print -r -- "usage: ai shell <personal|company>" >&2; return 2; }
  local wp; wp="$(ws_path "$ws")"; mkdir -p "$wp"
  check_cwd "$wp"; check_secrets "$wp"
  cd "$wp" || return 1
  print -r -- "-> shell in $ws workspace: $wp"
  exec "${SHELL:-/bin/zsh}"
}

cmd_tmux() {  # personal|company
  local ws="${1:-}"
  valid_ws "$ws" || { print -r -- "usage: ai tmux <personal|company>" >&2; return 2; }
  command -v tmux >/dev/null 2>&1 || { print -r -- "tmux not found" >&2; return 1; }
  local wp sess; wp="$(ws_path "$ws")"; sess="ai-$ws"; mkdir -p "$wp"
  if tmux has-session -t "$sess" 2>/dev/null; then print -r -- "attaching tmux session: $sess"
  else print -r -- "creating tmux session: $sess (cwd $wp)"; tmux new-session -d -s "$sess" -c "$wp"; fi
  if [[ -n "${TMUX:-}" ]]; then tmux switch-client -t "$sess"; else tmux attach-session -t "$sess"; fi
}

# Optional-tool install guidance for Zellij (a modern, tmux-like multiplexer).
_zellij_install_hint() {
  print -r -- "  install (optional):  brew install zellij   |   cargo install --locked zellij"
  print -r -- "  docs:                https://zellij.dev/documentation/installation"
}

cmd_zellij() {  # personal|company: Zellij session (layout-as-code). tmux stays the remote fallback.
  local ws="${1:-}"
  valid_ws "$ws" || { print -r -- "usage: ai zellij <personal|company>" >&2; return 2; }
  command -v zellij >/dev/null 2>&1 || {
    print -r -- "zellij not found (optional). Install it, or use 'ai tmux $ws' now:" >&2
    _zellij_install_hint >&2
    return 1
  }
  [[ -n "${ZELLIJ:-}" ]] && { warn "already inside a zellij session; open a new terminal to attach 'ai-$ws'."; return 1; }
  local wp sess; wp="$(ws_path "$ws")"; sess="ai-$ws"; mkdir -p "$wp"
  cd "$wp" || { print -r -- "cannot cd to $wp" >&2; return 1; }
  if zellij list-sessions 2>/dev/null | grep -q -- "$sess"; then
    print -r -- "attaching zellij session: $sess"
    zellij attach "$sess"
  else
    print -r -- "creating zellij session: $sess (cwd $wp)"
    if [[ -f "$AI_ZELLIJ_LAYOUT" ]]; then
      print -r -- "  layout: $AI_ZELLIJ_LAYOUT"
      zellij --session "$sess" --layout "$AI_ZELLIJ_LAYOUT"
    else
      warn "layout not found ($AI_ZELLIJ_LAYOUT); starting a default zellij session."
      zellij --session "$sess"
    fi
  fi
}


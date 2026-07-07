# lib/maps.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md


# ---------- maps ----------
ws_path() {
  case "$1" in
    personal) print -r -- "$AI_PERSONAL_WS" ;;
    company)  print -r -- "$AI_COMPANY_WS" ;;
    *)
      # Generic profile: honor a per-profile AI_WS_<name> override, else $HOME/dev/<name>.
      valid_ws "$1" || return 1
      local _wsvar="AI_WS_$1"
      print -r -- "${(P)_wsvar:-$HOME/dev/$1}"
      ;;
  esac
}

cfg_root() {  # $1 tool, $2 account
  case "$1" in
    claude) print -r -- "${AI_CLAUDE_ROOT_PREFIX}$2" ;;
    codex)  print -r -- "${AI_CODEX_ROOT_PREFIX}$2" ;;
    *) return 1 ;;
  esac
}

cfg_env_name() {
  case "$1" in
    claude) print -r -- "CLAUDE_CONFIG_DIR" ;;
    codex)  print -r -- "CODEX_HOME" ;;
  esac
}

# Native-isolation registry: Claude.app only. --user-data-dir isolates a Chromium/Electron
# shell, which works for Claude.app (it embeds Claude Code and reads its state from that dir).
# Codex.app is Electron too, but reads config/plugins/skills/account from CODEX_HOME, so
# --user-data-dir does NOT isolate the Codex account; Codex stays CLI-first (`ai codex`).
# Native AppKit apps like ChatGPT.app ignore the flag entirely. Isolate non-Claude via browser.
gui_app_bundle() {  # $1 app name -> bundle path
  case "$1" in
    claude)  print -r -- "$AI_CLAUDE_APP" ;;
    *) return 1 ;;
  esac
}

gui_app_dataprefix() {  # $1 app name -> data-dir prefix (account appended by caller)
  case "$1" in
    claude)  print -r -- "$AI_CLAUDE_APP_DATA_PREFIX" ;;
    *) return 1 ;;
  esac
}

log_dir() {  # $1 workspace, $2 tool, $3 account
  print -r -- "$(ws_path "$1")/.ai-logs/$2/$3-account"
}

# Codex auth-store preference. Reads ONLY the config KEY value (file|keyring|auto)
# from config.toml, never auth.json, never token contents. $1 = codex config root.
codex_store_pref() {
  local cfg="$1/config.toml" v=""
  if [[ -f "$cfg" ]]; then
    v="$(grep -aE '^[[:space:]]*cli_auth_credentials_store[[:space:]]*=' "$cfg" 2>/dev/null \
          | head -n1 | sed -E 's/.*=[[:space:]]*"?([A-Za-z]+)"?.*/\1/')"
  fi
  print -r -- "${v:-auto}"
}

# File mode ("600", "644"…) without reading contents. $1 = path. Empty if unknown.
file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || print -r -- ""
}

# Claude Code (macOS) derives a per-CLAUDE_CONFIG_DIR Keychain service name by
# suffixing "Claude Code-credentials-" with sha256(abs config-dir path)[:8].
# UNDOCUMENTED and version-dependent (verified on Claude Code 2.1.198), so the
# router VERIFIES the entry rather than assuming it. $1 = config dir. Empty if
# shasum is unavailable. (Default ~/.claude uses the bare, unsuffixed name.)
claude_keychain_hash() {  # $1 config dir
  command -v shasum >/dev/null 2>&1 || { print -r -- ""; return; }
  printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -c1-8
}

# True iff a Keychain generic-password service exists. Reads ONLY item presence
# (no -w): the secret is never fetched. $1 = service name. macOS only.
keychain_service_present() {  # $1 service
  [[ "$AI_OS" == macos ]] || return 1
  command -v security >/dev/null 2>&1 || return 1
  security find-generic-password -s "$1" >/dev/null 2>&1
}


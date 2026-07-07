# lib/remote.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

# ---------- exposed control-plane detection (read-only) ----------
# T5 in docs/en/THREAT-MODEL.md: surface any locally-listening socket that is
# reachable off-host, and flag ones that look like an agent control plane.
# STRICTLY read-only: we print process name + bind address + port ONLY. We never
# read command-line args or env (they can carry tokens/secrets), never touch
# config, and never open or close a port.

# A bind address is "off-host" (reachable from the network) if it is NOT a
# loopback address. Loopback = 127.0.0.0/8 or ::1 (and the bracketed [::1] form).
_bind_is_loopback() {  # $1 = bind address (no port)
  case "$1" in
    127.*|::1|'[::1]'|localhost) return 0 ;;
    *) return 1 ;;
  esac
}

# Does this process/port look like an agent control plane worth warning about?
# Matches common agent runtimes/tools by process name, plus ports frequently used
# by local agent servers / dev control planes.
_looks_like_control_plane() {  # $1 = process/command name (lowercased ok), $2 = port
  local name="${1:l}" port="$2"
  case "$name" in
    *codex*|*claude*|*mcp*|node|node.js|*npm*|*npx*|*deno*|*bun*|*ollama*) return 0 ;;
  esac
  case "$port" in
    # Ports commonly used by local agent control planes / dev servers.
    1455|1456|3000|3001|4111|5173|8000|8080|8090|8787|11434|1234) return 0 ;;
  esac
  return 1
}

# Print the exposed-listener report for macOS (lsof) or linux (ss). Read-only.
_report_exposed_listeners() {
  print -r -- "-- exposed listeners (bound off-loopback) --"
  local any=0 flagged=0
  local -A _seen=()   # dedupe identical proc+addr:port (IPv4/IPv6 dual-bind, etc.)
  if [[ "$AI_OS" == macos ]]; then
    if ! command -v lsof >/dev/null 2>&1; then
      print -r -- "  (lsof unavailable; cannot enumerate listeners)"; return 0
    fi
    # -nP: no name/port resolution. -Fpcn: parse-friendly output: p=pid, c=command,
    # n=name (addr:port). We deliberately request ONLY these fields; args are never emitted.
    local proc="" line f val addr port
    # lsof -F emits records; a new "p" line starts a new process block.
    while IFS= read -r line; do
      f="${line[1]}"; val="${line[2,-1]}"
      case "$f" in
        c) proc="$val" ;;
        n)
          # val looks like: 127.0.0.1:8080  or  *:22  or  [::1]:631  or  [2001:db8::1]:443
          addr="${val%:*}"; port="${val##*:}"
          [[ "$addr" == '*' ]] && addr='0.0.0.0'
          _bind_is_loopback "$addr" && continue   # loopback = not off-host
          local key="${proc}|${addr}|${port}"
          [[ -n "${_seen[$key]:-}" ]] && continue; _seen[$key]=1
          any=1
          if _looks_like_control_plane "$proc" "$port"; then
            flagged=1
            print -r -- "  ⚠️  WARNING  ${proc}  ${addr}:${port}  (looks like an agent control plane)"
          else
            print -r -- "  info      ${proc}  ${addr}:${port}"
          fi
          ;;
      esac
    done < <(lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null)
  elif [[ "$AI_OS" == linux ]]; then
    if ! command -v ss >/dev/null 2>&1; then
      print -r -- "  (ss unavailable; cannot enumerate listeners)"; return 0
    fi
    # -ltnH: listening, tcp, numeric, no header. Local-address is field 4 (addr:port),
    # process info (field 6) carries only the program name we extract, no args.
    local laddr proc addr port pinfo
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      laddr="${${(z)line}[4]}"
      pinfo="${${(z)line}[6]:-}"
      addr="${laddr%:*}"; port="${laddr##*:}"
      addr="${addr#\[}"; addr="${addr%\]}"   # strip [] from IPv6
      [[ "$addr" == '*' ]] && addr='0.0.0.0'
      _bind_is_loopback "$addr" && continue
      # pinfo: users:(("node",pid=123,fd=20)) -> extract the quoted program name only.
      proc="${pinfo#*\"}"; proc="${proc%%\"*}"; proc="${proc:-?}"
      local key="${proc}|${addr}|${port}"
      [[ -n "${_seen[$key]:-}" ]] && continue; _seen[$key]=1
      any=1
      if _looks_like_control_plane "$proc" "$port"; then
        flagged=1
        print -r -- "  ⚠️  WARNING  ${proc}  ${addr}:${port}  (looks like an agent control plane)"
      else
        print -r -- "  info      ${proc}  ${addr}:${port}"
      fi
    done < <(ss -ltnH 2>/dev/null)
  else
    print -r -- "  (listener enumeration not supported on this OS)"; return 0
  fi
  (( any )) || print -r -- "  none (no off-loopback TCP listeners detected) ✓"
  if (( flagged )); then
    print -r -- "  → An agent control plane reachable off-loopback is high-risk. Bind it to"
    print -r -- "    127.0.0.1 and reach it over Tailscale/SSH, or require authentication."
  fi
  return 0
}

# Tailscale Funnel = public internet exposure. Serve = private inside the tailnet.
_report_tailscale_exposure() {  # $1 = tailscale path (may be empty)
  local tp="$1"
  print -r -- "-- tailscale funnel (public internet) --"
  if [[ -z "$tp" ]]; then
    print -r -- "  (tailscale not installed; cannot check Funnel)"
  else
    local funnel; funnel="$(tailscale funnel status 2>/dev/null)"
    if [[ -z "$funnel" || "$funnel" == *"No serve config"* || "$funnel" == *"Funnel is not"* ]]; then
      print -r -- "  Funnel not active ✓"
    else
      print -r -- "  ⚠️  HIGH RISK: Tailscale Funnel is ACTIVE: whatever is behind it is on the"
      print -r -- "     PUBLIC INTERNET. Never expose an unauthenticated agent control plane"
      print -r -- "     (Codex app-server, MCP server, local web UI) through Funnel."
      print -r -- "$funnel" | sed 's/^/     /'
    fi
  fi
  print -r -- "-- tailscale serve (private, inside tailnet) --"
  if [[ -z "$tp" ]]; then
    print -r -- "  (tailscale not installed; cannot check Serve)"
  else
    local serve; serve="$(tailscale serve status 2>/dev/null)"
    if [[ -z "$serve" || "$serve" == *"No serve config"* ]]; then
      print -r -- "  Serve not active."
    else
      print -r -- "  Serve active (reachable inside your tailnet only, ACL-gated):"
      print -r -- "$serve" | sed 's/^/    /'
    fi
  fi
  return 0
}

cmd_remote_doctor() {
  print -r -- "== ai remote doctor =="
  print -r -- "hostname: $(hostname)"
  print -r -- "whoami:   $(whoami)"
  local tp; tp="$(command -v tailscale 2>/dev/null)"
  print -r -- "tailscale: ${tp:-NOT FOUND}"
  if [[ -n "$tp" ]]; then
    print -r -- "-- tailscale status (summary) --"; tailscale status 2>/dev/null | head -n 10 || print -r -- "  (status unavailable)"
    print -r -- "-- tailscale ip --"; tailscale ip 2>/dev/null || print -r -- "  (ip unavailable)"
  fi
  print -r -- "-- sshd listening on :22? --"; print -r -- "  $(_sshd_listening)"
  print -r -- "-- tmux sessions --"; tmux ls 2>/dev/null || print -r -- "  (none)"
  print -r -- "-- zellij sessions --"
  if command -v zellij >/dev/null 2>&1; then zellij list-sessions 2>/dev/null || print -r -- "  (none)"; else print -r -- "  (zellij not installed)"; fi
  _report_exposed_listeners
  _report_tailscale_exposure "$tp"
  print -r -- "-- control-plane exposure notes --"
  print -r -- "  • Codex 'app-server' WebSocket mode is EXPERIMENTAL; do not expose it"
  print -r -- "    unauthenticated. Keep it on loopback and reach it via Tailscale/SSH."
  print -r -- "  • Claude Code Remote Control uses OUTBOUND HTTPS with no inbound port and"
  print -r -- "    Claude.ai login only. Nothing to expose here, but anyone with that login"
  print -r -- "    can drive the session."
}

cmd_logs() {
  print -r -- "== ai logs =="
  local ws base files
  for ws in ${=AI_PROFILES}; do
    base="$(ws_path "$ws")/.ai-logs"
    print -r -- "[$ws] $base"
    if [[ -d "$base" ]]; then
      files="$(find "$base" -type f 2>/dev/null | sort)"
      [[ -n "$files" ]] && print -r -- "$files" | sed 's/^/  /' || print -r -- "  (empty)"
    else print -r -- "  (not created yet)"; fi
  done
}

# Build the "keep set": hashes of config dirs that must NEVER be pruned. Maps
# hash -> dir for existing dirs so list can name an active entry's owner. The bare
# ~/.claude entry is kept unconditionally (handled by caller, not hashed here).
# $@ = extra --keep dirs to whitelist. Populates the assoc array named _keep_map.

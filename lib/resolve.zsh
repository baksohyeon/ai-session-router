# lib/resolve.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

# ---------- commands ----------
cmd_resolve() {  # <tool> <workspace> [--account X]
  local tool="${1:-}" ws="${2:-}"
  [[ -n "$tool" && -n "$ws" ]] || { print -r -- "usage: ai resolve <claude|codex> <personal|company> [--account personal|company]" >&2; return 2; }
  shift 2
  valid_ws "$ws" || { print -r -- "invalid workspace: $ws" >&2; return 2; }
  local account="$ws"
  while (( $# )); do
    case "$1" in
      --account) account="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  valid_account "$account" || { print -r -- "invalid account: $account" >&2; return 2; }
  print -r -- "tool:       $tool"
  print -r -- "workspace:  $ws -> $(ws_path "$ws")"
  print -r -- "account:    $account"
  print -r -- "$(cfg_env_name "$tool")=$(cfg_root "$tool" "$account")"
  print -r -- "logs:       $(log_dir "$ws" "$tool" "$account")"
  check_mismatch "$ws" "$account"
}

run_tool() {  # <tool> <workspace> [--account X] [-- passthrough...]
  local tool="${1:-}" ws="${2:-}"
  [[ -n "$tool" && -n "$ws" ]] || { print -r -- "usage: ai $tool <personal|company> [--account personal|company] [-- args...]" >&2; return 2; }
  shift 2
  valid_ws "$ws" || { print -r -- "invalid workspace: $ws" >&2; return 2; }
  local account="$ws"; local -a passthru=()
  while (( $# )); do
    case "$1" in
      --account) account="${2:-}"; shift 2 ;;
      --) shift; passthru+=("$@"); break ;;
      *) passthru+=("$1"); shift ;;
    esac
  done
  valid_account "$account" || { print -r -- "invalid account: $account" >&2; return 2; }
  command -v "$tool" >/dev/null 2>&1 || { print -r -- "$tool not found on PATH" >&2; return 127; }

  local wp cr ld
  wp="$(ws_path "$ws")"; cr="$(cfg_root "$tool" "$account")"; ld="$(log_dir "$ws" "$tool" "$account")"
  mkdir -p "$ld" "$wp"
  check_mismatch "$ws" "$account"
  check_secrets "$wp"
  # Stay in the current dir if it is already inside the workspace; otherwise start at the
  # workspace root (and say so). Keeps you in-project when you launch from a subdirectory.
  local launch_dir="$wp"
  case "$PWD/" in
    "$wp/"*) launch_dir="$PWD" ;;
    *) warn "current dir is outside $ws workspace; starting at workspace root:
      cwd: $PWD
      ws:  $wp" ;;
  esac
  cd "$launch_dir" || { print -r -- "cannot cd to $launch_dir" >&2; return 1; }

  local ts transcript; ts="$(date +%Y%m%d-%H%M%S)"; transcript="$ld/session-$ts.log"
  case "$tool" in
    claude)
      export CLAUDE_CONFIG_DIR="$cr"
      print -r -- "→ claude  CLAUDE_CONFIG_DIR=$cr  cwd=$PWD"
      print -r -- "  transcript: $transcript"
      _run_with_transcript "$transcript" claude "${passthru[@]}" ;;
    codex)
      export CODEX_HOME="$cr"
      print -r -- "→ codex   CODEX_HOME=$cr  cwd=$PWD"
      print -r -- "  transcript: $transcript"
      print -r -- "  note: Codex internal logs may remain under \$CODEX_HOME/log (follows account, not workspace)."
      _run_with_transcript "$transcript" codex "${passthru[@]}" ;;
    *) print -r -- "unknown tool: $tool" >&2; return 2 ;;
  esac
}


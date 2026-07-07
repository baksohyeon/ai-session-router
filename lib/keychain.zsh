# lib/keychain.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

_keychain_build_keep() {  # $@ extra keep dirs -> fills the caller-scoped _keep_map assoc array
  setopt local_options null_glob
  local -a candidates=("$HOME/.claude" "${AI_CLAUDE_ROOT_PREFIX}"*(N) "$@")
  local _p
  for _p in ${=AI_PROFILES}; do candidates+=("$(cfg_root claude "$_p")"); done
  local dir h
  for dir in "${candidates[@]}"; do
    [[ -n "$dir" && -d "$dir" ]] || continue           # only dirs that actually exist
    [[ "$dir" == "$HOME/.claude" ]] && continue         # bare entry: kept, not hashed
    h="$(claude_keychain_hash "$dir")"
    [[ -n "$h" ]] && _keep_map[$h]="$dir"
  done
}

cmd_keychain() {  # <list|prune> [--force] [--keep DIR ...]
  setopt local_options extended_glob   # needed for the (#b) backreference match below
  local sub="" force=0 assume_yes=0; local -a keep_dirs=()
  local _u="usage: ai keychain <list|prune> [--force] [--yes] [--keep DIR ...]"
  while (( $# )); do
    case "$1" in
      --force) force=1; shift ;;
      --yes|-y) assume_yes=1; shift ;;
      --keep)
        (( $# >= 2 )) || { print -r -- "ai keychain: --keep requires a DIR argument" >&2; return 2; }
        [[ -d "$2" ]] || warn "--keep path does not exist; it will protect nothing: $2"
        keep_dirs+=("$2"); shift 2 ;;
      list|prune) [[ -z "$sub" ]] && sub="$1" || { print -r -- "$_u" >&2; return 2; }; shift ;;
      *) print -r -- "$_u" >&2; return 2 ;;
    esac
  done
  [[ -n "$sub" ]] || { print -r -- "$_u" >&2; return 2; }

  # macOS-only; both actions no-op cleanly elsewhere.
  if [[ "$AI_OS" != macos ]]; then
    print -r -- "ai keychain: not applicable on this OS (macOS Keychain only)."; return 0
  fi
  command -v security >/dev/null 2>&1 || { print -r -- "ai keychain: 'security' tool unavailable; nothing to do."; return 0; }
  command -v shasum   >/dev/null 2>&1 || { print -r -- "ai keychain: 'shasum' unavailable; cannot classify entries."; return 0; }

  # Keep set: hash -> owning dir. Bare ~/.claude is always kept separately.
  local -A _keep_map=()
  _keychain_build_keep "${keep_dirs[@]}"

  # Enumerate matching services from ATTRIBUTES ONLY (never -w / secret values).
  # Anchor to the "svce" attribute line so a stray label/comment/account field that
  # merely contains the pattern can't be swept in and (under --force) deleted.
  local -a services=()
  services=("${(@f)$(security dump-keychain 2>/dev/null \
    | grep -aoE '"svce"<blob>="Claude Code-credentials(-[0-9a-f]+)?"' \
    | sed -E 's/^"svce"<blob>="(.*)"$/\1/' | sort -u)}")

  local svc suffix nactive=0 norphan=0 nbare=0
  local -a orphans=()
  for svc in "${services[@]}"; do
    [[ -n "$svc" ]] || continue
    if [[ "$svc" == "Claude Code-credentials" ]]; then
      (( nbare++ ))
      [[ "$sub" == list ]] && print -r -- "  $svc  ->  default (~/.claude)"
    elif [[ "$svc" == (#b)"Claude Code-credentials-"([0-9a-f]##) ]]; then
      suffix="$match[1]"
      if [[ -n "${_keep_map[$suffix]:-}" ]]; then
        (( nactive++ ))
        [[ "$sub" == list ]] && print -r -- "  $svc  ->  active: ${_keep_map[$suffix]}"
      else
        (( norphan++ )); orphans+=("$svc")
        [[ "$sub" == list ]] && print -r -- "  $svc  ->  orphan (no matching config dir)"
      fi
    fi
    # Anything not matching the exact patterns above is ignored, never touched.
  done

  if [[ "$sub" == list ]]; then
    print -r -- "summary: $nactive active, $norphan orphan, $nbare default"
    return 0
  fi

  # prune: dry-run unless --force. Only ORPHAN entries are ever eligible.
  local kept=$(( nactive + nbare ))
  if (( norphan == 0 )); then
    print -r -- "no orphaned Claude keychain entries found [ok]"
    print -r -- "kept $kept entries ($nactive active + $nbare default)."
    return 0
  fi
  # Fail CLOSED: 0 active entries almost always means the keep-set failed to resolve
  # (bad HOME, devcontainer, moved/renamed dirs), in which case EVERY live entry looks
  # orphaned. Refuse to delete rather than wipe real credentials. (#security-F1)
  if (( force && nactive == 0 )); then
    print -r -- "ai keychain: refusing to prune: 0 active entries detected but $norphan candidate(s) found." >&2
    print -r -- "  This usually means HOME / AI_CLAUDE_ROOT_PREFIX don't resolve here (devcontainer, moved dirs)," >&2
    print -r -- "  not that $norphan accounts are genuinely stale. Inspect with 'ai keychain list', or pass" >&2
    print -r -- "  --keep DIR for each live account, then retry." >&2
    return 1
  fi
  local o
  if (( force )); then
    # Magnitude confirmation (skip with --yes for automation). With no TTY, read -q
    # returns non-zero -> treated as "no" -> nothing is deleted. (#security-F2)
    if (( ! assume_yes )); then
      print -r -- "about to DELETE $norphan orphaned keychain entry(s); keeping $kept ($nactive active + $nbare default)."
      if ! read -q "?proceed? [y/N] "; then print -r -- ""; print -r -- "aborted, no changes."; return 1; fi
      print -r -- ""
    fi
    for o in "${orphans[@]}"; do
      print -r -- "deleting: $o"
      if security delete-generic-password -s "$o" >/dev/null 2>&1; then
        print -r -- "  ok"
      else
        warn "failed to delete: $o"
      fi
    done
  else
    for o in "${orphans[@]}"; do
      print -r -- "would delete: $o"
    done
    print -r -- "re-run with --force to delete $norphan orphaned entries"
  fi
  print -r -- "kept $kept entries ($nactive active + $nbare default)."
  return 0
}


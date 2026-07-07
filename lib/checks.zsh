# lib/checks.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

# ---------- warnings (non-blocking) ----------
warn() { print -r -- "[!] $*" >&2; }

# Valid iff the name appears in the configured AI_PROFILES set.
valid_ws() {
  local p
  for p in ${=AI_PROFILES}; do [[ "$1" == "$p" ]] && return 0; done
  return 1
}
valid_account() { valid_ws "$1"; }

check_mismatch() {  # workspace account
  [[ "$1" == personal && "$2" == company ]] && \
    warn "personal workspace paired with COMPANY account ($1 ws + $2 acct)."
  return 0
}

check_cwd() {  # workspace path
  case "$PWD/" in
    "$1/"*) ;;
    *) warn "current dir is outside selected workspace:
      cwd: $PWD
      ws:  $1" ;;
  esac
}

check_secrets() {  # workspace path (names only, contents NEVER read)
  setopt local_options null_glob
  local f
  for f in "$1"/.env "$1"/.env.* "$1"/*.pem "$1"/*.key "$1"/*.p12 \
           "$1"/id_rsa "$1"/id_dsa "$1"/id_ecdsa "$1"/id_ed25519 \
           "$1"/*secret* "$1"/*credential*; do
    [[ -e "$f" ]] && warn "secret-looking file near workspace root: ${f:t} (contents not read)"
  done
  return 0
}


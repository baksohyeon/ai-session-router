#!/usr/bin/env sh
# smoke.sh: safe, read-only/dry-run smoke battery for the ai session router.
#
# Runs under zsh or bash (POSIX-ish; no arrays, no bashisms). Exercises every
# non-destructive surface of bin/ai and asserts a clean result:
#
#   - ai resolve <tool> <account>   (pure logic, every tool x account)
#   - ai profiles list              (redacted inventory)
#   - ai doctor                     (environment + isolation report)
#   - ai gui <id> --dry-run         (launch preview, launches nothing)
#   - ai keychain list              (attributes only; NEVER prune)
#   - secret-leak grep              (asserts 0 secret-looking tokens in output)
#
# SAFETY: this script NEVER launches an interactive session, NEVER opens a
# browser or app, and NEVER runs `keychain prune` (with or without --force).
# Every ai invocation here is a resolve/list/dry-run/doctor read.
#
# Exit code: 0 if all checks pass; non-zero on the first failure or if any
# secret pattern is found in captured output.

set -u

# ---------- locate bin/ai relative to this script ----------
# Resolve the script's own directory so the smoke test works from any CWD and
# targets THIS checkout's bin/ai (not whatever `ai` happens to be on PATH).
script_path="$0"
# Follow one level of symlink if present (best-effort; POSIX has no realpath).
if [ -L "$script_path" ]; then
  link=$(readlink "$script_path")
  case "$link" in
    /*) script_path="$link" ;;
    *)  script_path="$(dirname "$script_path")/$link" ;;
  esac
fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$script_path")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
AI="$repo_root/bin/ai"

if [ ! -f "$AI" ]; then
  printf '%s\n' "smoke: cannot find router at $AI" >&2
  exit 2
fi

# Prefer zsh to run the (zsh) router; fall back to executing it directly.
if command -v zsh >/dev/null 2>&1; then
  RUN_AI="zsh $AI"
else
  RUN_AI="$AI"
fi

# ---------- reporting ----------
pass_count=0
fail_count=0
tmpout=$(mktemp "${TMPDIR:-/tmp}/ai-smoke.XXXXXX") || exit 2
# Accumulates ALL captured output for a single end-of-run secret scan.
allout=$(mktemp "${TMPDIR:-/tmp}/ai-smoke-all.XXXXXX") || exit 2
cleanup() { rm -f "$tmpout" "$allout"; }
trap cleanup EXIT INT TERM

ok()   { pass_count=$((pass_count + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail_count=$((fail_count + 1)); printf '  FAIL %s\n' "$1" >&2; }

# run_check <label> <command...>
# Runs the command, captures output, appends to the global scan buffer, and
# asserts a zero exit status.
run_check() {
  label="$1"; shift
  if "$@" >"$tmpout" 2>&1; then
    cat "$tmpout" >>"$allout"
    ok "$label"
  else
    status=$?
    cat "$tmpout" >>"$allout"
    bad "$label (exit $status)"
    sed 's/^/       | /' "$tmpout" >&2
  fi
}

# run_check_sh <label> <shell-string>
# Same as run_check but for a command that needs word-splitting ($RUN_AI).
run_check_sh() {
  label="$1"; shift
  if sh -c "$*" >"$tmpout" 2>&1; then
    cat "$tmpout" >>"$allout"
    ok "$label"
  else
    status=$?
    cat "$tmpout" >>"$allout"
    bad "$label (exit $status)"
    sed 's/^/       | /' "$tmpout" >&2
  fi
}

printf '== ai smoke (read-only / dry-run) ==\n'
printf 'router: %s\n' "$AI"
printf 'runner: %s\n\n' "$RUN_AI"

# ---------- 1. resolve: every tool x account (pure logic) ----------
printf 'resolve:\n'
for tool in claude codex; do
  for acct in personal company; do
    run_check_sh "resolve $tool $acct" "$RUN_AI resolve $tool $acct"
    run_check_sh "resolve $tool $acct --account $acct" \
      "$RUN_AI resolve $tool $acct --account $acct"
  done
done

# ---------- 2. profiles inventory (redacted) ----------
printf 'profiles:\n'
run_check_sh "profiles list" "$RUN_AI profiles list"
run_check_sh "profiles show personal" "$RUN_AI profiles show personal"
run_check_sh "profiles show company" "$RUN_AI profiles show company"

# ---------- 3. doctor (environment + isolation report) ----------
printf 'doctor:\n'
run_check_sh "doctor" "$RUN_AI doctor"
run_check_sh "remote doctor" "$RUN_AI remote doctor"
run_check_sh "logs" "$RUN_AI logs"

# ---------- 4. gui dry-run (launches nothing) ----------
printf 'gui (dry-run, launches nothing):\n'
for id in personal company; do
  run_check_sh "gui $id --dry-run" "$RUN_AI gui $id --dry-run"
  run_check_sh "gui $id --browser --dry-run" "$RUN_AI gui $id --browser --dry-run"
done
run_check_sh "gui setup --print" "$RUN_AI gui setup --print"

# ---------- 5. keychain list (attributes only; NEVER prune) ----------
printf 'keychain (list only; never prune):\n'
run_check_sh "keychain list" "$RUN_AI keychain list"

# ---------- 6. secret-leak scan over ALL captured output ----------
# The router promises to print presence/mode only, never token contents. Assert
# that nothing token-shaped leaked into any command's output. Patterns cover the
# common credential shapes (OAuth/JWT/API keys) plus explicit token JSON keys.
printf 'secret scan:\n'
# Extended-regex alternation. Kept deliberately broad; a hit is a hard failure.
secret_re='sk-[A-Za-z0-9]{16,}'
secret_re="$secret_re"'|sk-ant-[A-Za-z0-9_-]{16,}'
secret_re="$secret_re"'|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'   # JWT
secret_re="$secret_re"'|ghp_[A-Za-z0-9]{20,}'
secret_re="$secret_re"'|"access_token"[[:space:]]*:[[:space:]]*"[^"]'
secret_re="$secret_re"'|"refresh_token"[[:space:]]*:[[:space:]]*"[^"]'
secret_re="$secret_re"'|"id_token"[[:space:]]*:[[:space:]]*"[^"]'
secret_re="$secret_re"'|-----BEGIN [A-Z ]*PRIVATE KEY-----'

if grep -aEn "$secret_re" "$allout" >"$tmpout" 2>/dev/null; then
  bad "secret pattern found in router output"
  printf '     leaked lines (redacted markers):\n' >&2
  # Show only line numbers + a truncated prefix so the log itself does not leak.
  cut -c1-24 "$tmpout" | sed 's/^/       | /' >&2
else
  ok "no secret patterns in any command output"
fi

# ---------- summary ----------
printf '\nsummary: %d passed, %d failed\n' "$pass_count" "$fail_count"
if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
exit 0

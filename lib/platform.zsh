# lib/platform.zsh -- part of the ai session router.
# Sourced by bin/ai after the config preamble; not meant to be run directly.
# See docs/superpowers/specs/2026-07-07-guard-observability-modularization-design.md

# ---------- platform helpers ----------
_open_url() {  # open one or more URLs in the default browser
  case "$AI_OS" in
    macos) open "$@" ;;
    linux) command -v xdg-open >/dev/null 2>&1 && { local u; for u in "$@"; do xdg-open "$u" >/dev/null 2>&1; done; } || warn "no xdg-open; cannot open: $*" ;;
    *) warn "unsupported OS for opening URLs: $*" ;;
  esac
}

# ---------- Chromium browser registry ----------
# Known Chromium-family browsers. Each entry maps a canonical key to its macOS app
# name, candidate linux binaries, and the "Local State" JSON dir (relative to $HOME,
# used by `ai gui setup` to enumerate existing profiles).
_CHROMIUM_KEYS=(edge chrome brave arc chromium)

_browser_macos_app() {  # $1 key -> macOS app name
  case "$1" in
    edge)     print -r -- "Microsoft Edge" ;;
    chrome)   print -r -- "Google Chrome" ;;
    brave)    print -r -- "Brave Browser" ;;
    arc)      print -r -- "Arc" ;;
    chromium) print -r -- "Chromium" ;;
    *) return 1 ;;
  esac
}

_browser_linux_bins() {  # $1 key -> space-separated candidate linux binaries
  case "$1" in
    edge)     print -r -- "microsoft-edge microsoft-edge-stable" ;;
    chrome)   print -r -- "google-chrome google-chrome-stable" ;;
    brave)    print -r -- "brave-browser brave" ;;
    arc)      print -r -- "arc" ;;
    chromium) print -r -- "chromium chromium-browser" ;;
    *) return 1 ;;
  esac
}

_browser_localstate_dir() {  # $1 key -> dir containing "Local State" (per OS)
  local app
  case "$AI_OS" in
    macos)
      case "$1" in
        edge)     print -r -- "$HOME/Library/Application Support/Microsoft Edge" ;;
        chrome)   print -r -- "$HOME/Library/Application Support/Google/Chrome" ;;
        brave)    print -r -- "$HOME/Library/Application Support/BraveSoftware/Brave-Browser" ;;
        arc)      print -r -- "$HOME/Library/Application Support/Arc/User Data" ;;
        chromium) print -r -- "$HOME/Library/Application Support/Chromium" ;;
        *) return 1 ;;
      esac ;;
    linux)
      case "$1" in
        edge)     print -r -- "$HOME/.config/microsoft-edge" ;;
        chrome)   print -r -- "$HOME/.config/google-chrome" ;;
        brave)    print -r -- "$HOME/.config/BraveSoftware/Brave-Browser" ;;
        arc)      print -r -- "$HOME/.config/arc" ;;
        chromium) print -r -- "$HOME/.config/chromium" ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

# Map an app name / binary (as stored in AI_BROWSER or AI_GUI_BROWSER_<id>) to a
# canonical key, so we can look up its Local State dir etc. Accepts either macOS app
# names ("Microsoft Edge") or linux binaries ("google-chrome-stable").
_browser_key_for() {  # $1 = app-name-or-bin -> canonical key (or empty)
  local want="$1" k app bins b
  for k in "${_CHROMIUM_KEYS[@]}"; do
    app="$(_browser_macos_app "$k")"
    [[ "$want" == "$app" ]] && { print -r -- "$k"; return 0; }
    bins="$(_browser_linux_bins "$k")"
    for b in ${=bins}; do
      [[ "$want" == "$b" ]] && { print -r -- "$k"; return 0; }
    done
  done
  return 1
}

# Resolve a launchable target for an app-name-or-bin on the current OS.
#   macOS: echoes the app name if the .app bundle exists.
#   linux: echoes the first candidate binary found on PATH.
# Also accepts a raw app name / binary not in the registry (best effort).
_browser_launch_target() {  # $1 = app-name-or-bin -> launch target (or fail)
  local want="$1" key bins b
  key="$(_browser_key_for "$want")" || key=""
  case "$AI_OS" in
    macos)
      if [[ -n "$key" ]]; then
        local app; app="$(_browser_macos_app "$key")"
        [[ -d "/Applications/$app.app" ]] && { print -r -- "$app"; return 0; }
        return 1
      fi
      # Unknown: treat $want as an app name, accept if bundle exists.
      [[ -d "/Applications/$want.app" ]] && { print -r -- "$want"; return 0; }
      return 1 ;;
    linux)
      if [[ -n "$key" ]]; then
        bins="$(_browser_linux_bins "$key")"
        for b in ${=bins}; do
          command -v "$b" >/dev/null 2>&1 && { print -r -- "$b"; return 0; }
        done
        return 1
      fi
      command -v "$want" >/dev/null 2>&1 && { print -r -- "$want"; return 0; }
      return 1 ;;
    *) return 1 ;;
  esac
}

# First detected Chromium browser on this OS (echoes app-name/bin), else fail.
_browser_first_detected() {
  local k target
  for k in "${_CHROMIUM_KEYS[@]}"; do
    case "$AI_OS" in
      macos)   target="$(_browser_macos_app "$k")" ;;
      linux)   local bins; bins="$(_browser_linux_bins "$k")"; target="${${=bins}[1]}" ;;
      *) return 1 ;;
    esac
    _browser_launch_target "$target" >/dev/null 2>&1 && { print -r -- "$target"; return 0; }
  done
  return 1
}

_has_browser() {  # $1 = edge|chrome|brave|arc|chromium (back-compat predicate)
  local app
  case "$1" in
    edge)     app="$(_browser_macos_app edge)" ;;
    chrome)   app="$(_browser_macos_app chrome)" ;;
    brave)    app="$(_browser_macos_app brave)" ;;
    arc)      app="$(_browser_macos_app arc)" ;;
    chromium) app="$(_browser_macos_app chromium)" ;;
    *) return 1 ;;
  esac
  _browser_launch_target "$app" >/dev/null 2>&1
}

# Launch a Chromium browser with an arbitrary set of flags + URLs.
#   $1 = launch target (macOS app name / linux binary), rest = flags and URLs.
_launch_browser() {  # $1 target, rest = flags+urls
  local target="$1"; shift
  case "$AI_OS" in
    macos) open -na "$target" --args "$@" ;;
    linux) ("$target" "$@" >/dev/null 2>&1 &); return 0 ;;
    *) return 1 ;;
  esac
}

# Isolated launch mirroring _launch_app_isolated: creates the data-dir, launches the
# browser bound to it, then opens the URLs in that instance.
#   $1 = launch target, $2 = data-dir, rest = URLs.
_launch_browser_isolated() {  # $1 target, $2 data-dir, rest = urls
  local target="$1" datadir="$2"; shift 2
  mkdir -p "$datadir"
  _launch_browser "$target" --user-data-dir="$datadir" "$@"
}

# Profile launch (opt-in): reuse an existing browser profile.
#   $1 = launch target, $2 = profile directory name, rest = URLs.
_launch_browser_profile() {  # $1 target, $2 profile, rest = urls
  local target="$1" profile="$2"; shift 2
  _launch_browser "$target" --profile-directory="$profile" "$@"
}

_has_app_bundle() {  # $1 = /Applications/Foo.app (macOS .app bundles are directories)
  [[ "$AI_OS" == macos && -d "$1" ]]
}

_launch_app_isolated() {  # $1 bundle, $2 data-dir (new isolated instance, macOS)
  mkdir -p "$2"
  open -n -a "$1" --args --user-data-dir="$2"
}

_os_label() {
  case "$AI_OS" in
    macos) print -r -- "macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))" ;;
    linux)
      if [[ -r /etc/os-release ]]; then
        local n; n="$(. /etc/os-release 2>/dev/null; print -r -- "$PRETTY_NAME")"
        print -r -- "${n:-Linux} ($(uname -m))"
      else print -r -- "Linux ($(uname -m))"; fi ;;
    *) print -r -- "$(uname -s) ($(uname -m))" ;;
  esac
}

_sshd_listening() {  # echoes a human string
  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:22 -sTCP:LISTEN >/dev/null 2>&1; then
    print -r -- "yes (listener detected on tcp/22)"
  elif command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -qE '[:.]22 '; then
    print -r -- "yes (ss: listener on tcp/22)"
  else
    print -r -- "not detected (may require privileges / remote login off)"
  fi
}

_run_with_transcript() {  # <transcript> <cmd> [args...] (preserve TTY via script(1))
  local transcript="$1"; shift
  if command -v script >/dev/null 2>&1; then
    case "$AI_OS" in
      macos) script -q "$transcript" "$@" ;;                # BSD: script [-q] file cmd...
      linux) script -q -c "${(j: :)${(@q)@}}" "$transcript" ;; # util-linux: script -c "cmd" file
      *)     "$@" ;;
    esac
  else
    "$@"
  fi
}


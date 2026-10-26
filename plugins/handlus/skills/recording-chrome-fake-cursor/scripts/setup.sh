#!/bin/zsh
# setup.sh — check (and install) what a Chrome window recording needs (recording-chrome-fake-cursor skill)
#
#   setup.sh            check only. One line per item: "ok  …" or "MISSING  …  → fix". Last line READY or NOT READY. Exit 0 = ready, 2 = not
#   setup.sh install    install what can be installed from here (ffmpeg via Homebrew, the recorder), start the steps
#                       only the user can finish (Command Line Tools dialog, Screen Recording switch), then check again
#
# Only the user can: click Install in the Command Line Tools dialog · install Homebrew (asks for their Mac password)
#                    · turn on Screen Recording for the terminal app and reopen that app.
set -u
HERE=${0:A:h}
BIN=$HERE/bin/screcord
MODE=${1:-check}
missing=0

ok()   { print -r -- "ok       $1"; }
miss() { print -r -- "MISSING  $1  → $2"; missing=$((missing + 1)); }

# Homebrew and its tools are often not on an agent's PATH
for d in /opt/homebrew/bin /usr/local/bin; do [[ -d $d && :$PATH: != *:$d:* ]] && PATH=$PATH:$d; done
export PATH

# The app that owns this terminal — macOS asks it, not the shell, for Screen Recording
term_app() {
  case ${__CFBundleIdentifier:-${TERM_PROGRAM:-}} in
    com.googlecode.iterm2|iTerm.app) print iTerm ;;
    com.apple.Terminal|Apple_Terminal) print Terminal ;;
    com.microsoft.VSCode|vscode) print 'Visual Studio Code' ;;
    com.todesktop.230313mzl4w4u92|cursor) print Cursor ;;
    dev.warp.Warp-Stable|WarpTerminal) print Warp ;;
    com.mitchellh.ghostty|ghostty) print Ghostty ;;
    *) print 'the terminal app running this agent' ;;
  esac
}
APP=$(term_app)
[[ -n ${TMUX:-} ]] && APP="$APP (under tmux: the app that started the tmux server)"
SR_PANE='x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'

have_clt() { xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; }
have_brew() { command -v brew >/dev/null 2>&1; }
have_ffmpeg() { command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; }

# Runs `screcord list` (asks ScreenCaptureKit for windows) with a 20 s limit. 0 = allowed
probe_screen_recording() {
  local err=${TMPDIR:-/tmp}/screcord-probe.$$ pid i
  $BIN list >/dev/null 2>$err &
  pid=$!
  for i in {1..40}; do kill -0 $pid 2>/dev/null || break; sleep 0.5; done
  if kill -0 $pid 2>/dev/null; then kill $pid 2>/dev/null; rm -f $err; return 2; fi
  wait $pid; local rc=$?
  PROBE_ERR=$(head -c 300 $err 2>/dev/null); rm -f $err
  return $rc
}

if [[ $MODE == install ]]; then
  print "== install"
  if [[ $(uname) != Darwin ]]; then print "Recording works on macOS only."; exit 2; fi
  if ! have_clt; then
    print "Opening the Command Line Tools installer. The user clicks Install (a few minutes), then run setup.sh install again."
    xcode-select --install 2>&1 | head -3
    exit 2
  fi
  if ! have_ffmpeg; then
    if have_brew; then
      print "Installing ffmpeg with Homebrew…"
      brew install ffmpeg || print "brew install ffmpeg failed — show the user the output above"
    else
      print "Homebrew is not installed. The user runs this in their own terminal (it asks for their Mac password):"
      print '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      print "then: brew install ffmpeg"
    fi
  fi
  if [[ ! -x $BIN ]]; then print "Building the recorder…"; zsh $HERE/build.sh || print "build failed"; fi
  if [[ -x $BIN ]] && ! probe_screen_recording; then
    print "Opening System Settings → Privacy & Security → Screen & System Audio Recording."
    print "The user turns on: $APP — then quits and reopens that app (macOS applies it only after a restart) and starts the agent again."
    open "$SR_PANE" 2>/dev/null
  fi
  print
fi

print "== check"
if [[ $(uname) != Darwin ]]; then
  miss "macOS" "recording uses ScreenCaptureKit and works on macOS 13+ only"
else
  v=$(sw_vers -productVersion); if (( ${v%%.*} >= 13 )); then ok "macOS $v"; else miss "macOS $v" "macOS 13 or later is needed"; fi

  if have_clt; then ok "Command Line Tools (swiftc)"; else miss "Command Line Tools" "run: xcode-select --install  (the user clicks Install)"; fi

  if have_clt && command -v python3 >/dev/null 2>&1; then ok "python3 $(python3 -c 'import platform;print(platform.python_version())' 2>/dev/null)"
  elif ! have_clt; then miss "python3" "comes with Command Line Tools"
  else miss "python3" "brew install python"; fi

  if have_ffmpeg; then ok "ffmpeg · ffprobe ($(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}'))"
  elif have_brew; then miss "ffmpeg · ffprobe" "brew install ffmpeg"
  else miss "ffmpeg · ffprobe" "install Homebrew first (https://brew.sh — the user runs it, it asks for their password), then brew install ffmpeg"; fi

  if [[ -d "/Applications/Google Chrome.app" || -d "$HOME/Applications/Google Chrome.app" ]]; then ok "Google Chrome"; else miss "Google Chrome" "install Chrome from https://www.google.com/chrome/"; fi

  if [[ ! -x $BIN ]] && have_clt; then zsh $HERE/build.sh >/dev/null 2>&1; fi
  if [[ -x $BIN ]]; then
    ok "recorder (bin/screcord)"
    probe_screen_recording; rc=$?
    if (( rc == 0 )); then ok "Screen Recording permission ($APP)"
    elif (( rc == 2 )); then miss "Screen Recording permission" "no answer in 20 s — a macOS permission prompt may be waiting; the user answers it, or turns on $APP in System Settings → Privacy & Security → Screen & System Audio Recording, then reopens the app"
    else miss "Screen Recording permission" "the user turns on $APP in System Settings → Privacy & Security → Screen & System Audio Recording (open \"$SR_PANE\"), then quits and reopens it. Error: ${PROBE_ERR:-exit $rc}"; fi
  else
    miss "recorder (bin/screcord)" "needs Command Line Tools; then zsh $HERE/build.sh"
  fi
fi

print -r -- "-- Also needed (check from the agent, not the shell): the Handlus MCP connected, and chrome_demo_cursor in the tool list (Handlus extension 0.3.1+)."
if (( missing )); then print "NOT READY ($missing missing)"; exit 2; fi
print "READY"

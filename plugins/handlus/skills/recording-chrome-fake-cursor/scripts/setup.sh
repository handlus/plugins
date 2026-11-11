#!/bin/zsh
# setup.sh — check (and install) what a browser window recording needs on a Mac (recording-chrome-fake-cursor skill)
#
#   setup.sh            check only. One line per item: "ok  …", "MISSING  …  → fix" or "optional  …". Last line READY or NOT READY.
#                       Exit 0 = ready, 2 = not
#   setup.sh install    if the Handlus app is missing or too old to record: download it, put it in /Applications and open it.
#                       If it is there but not running: open it. Then check again
#
# On a Mac the Handlus app (1.5.0 or later) records the window, with the Screen Recording permission it gets on its own
# setup screen. The terminal running the agent needs no permission, and nothing is built here (no Command Line Tools).
# ffmpeg and python3 with Pillow are optional: only to trim the video or make a preview sheet (sheet.py · evidence.py).
#
# Only the user can: connect this computer to their Handlus account (a page in the browser) · turn on Allow, Accessibility
#                    and Screen Recording on the app's setup screen.
set -u
HERE=${0:A:h}
MODE=${1:-check}
MIN=1.5.0                                            # first Handlus app with desktop_record
MANIFEST=https://handlus.com/downloads/app.json      # latest app: version · files.darwin-dmg.url · sha256
PAGE=https://handlus.com/download
missing=0

ok()   { print -r -- "ok       $1"; }
miss() { print -r -- "MISSING  $1  → $2"; missing=$((missing + 1)); }
opt()  { print -r -- "optional $1  → $2"; }

# Homebrew and its tools are often not on an agent's PATH
for d in /opt/homebrew/bin /usr/local/bin; do [[ -d $d && :$PATH: != *:$d:* ]] && PATH=$PATH:$d; done
export PATH

# Not a Mac: Windows (Git Bash, WSL) has its own setup.ps1; Linux is not supported
not_mac() {
  local here_win
  if grep -qi microsoft /proc/version 2>/dev/null; then
    here_win=$(wslpath -w "$HERE" 2>/dev/null || print "$HERE")
    print "This is WSL. Recording runs on the Windows side: run the skill from Claude Code or Codex on Windows itself (not inside WSL),"
    print "or check from here with:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$here_win\\setup.ps1'"
  elif [[ $(uname -s) == MINGW* || $(uname -s) == MSYS* || $(uname -s) == CYGWIN* || ${OS:-} == Windows_NT ]]; then
    print "This is Windows. Use setup.ps1 instead:  powershell -NoProfile -ExecutionPolicy Bypass -File \"\$(cygpath -w '$HERE')\\setup.ps1\""
  else
    print "Recording works on macOS and Windows only."
  fi
}

# Where the app can be. The app installs itself into Application Support and runs from there; /Applications holds the
# copy from the download. HANDLUS_APP=<path to a Handlus.app> checks that one instead.
INSTALLED="$HOME/Library/Application Support/Handlus/App/Handlus.app"
APPS=("$INSTALLED" "/Applications/Handlus.app" "$HOME/Applications/Handlus.app")
[[ -n ${HANDLUS_APP:-} ]] && APPS=("$HANDLUS_APP")

find_app() { local a; for a in "${APPS[@]}"; do [[ -x "$a/Contents/MacOS/handlus-app" ]] && { print -r -- "$a"; return 0; }; done; return 1; }

# ver_ge A B: A >= B (numbers only, 1.10.0 > 1.9.9)
ver_ge() {
  local -a a b; local i x y
  a=(${(s:.:)1}); b=(${(s:.:)2})
  for i in 1 2 3; do
    x=${a[i]:-0}; y=${b[i]:-0}; x=${x%%[^0-9]*}; y=${y%%[^0-9]*}
    (( ${x:-0} > ${y:-0} )) && return 0
    (( ${x:-0} < ${y:-0} )) && return 1
  done
  return 0
}

# APP_VERSION · APP_CONNECTED · APP_RUNNING from the app's own `status` (English, 10 s limit). 1 = no answer
read_status() {
  local out=${TMPDIR:-/tmp}/handlus-status.$$ pid i
  APP_VERSION=''; APP_CONNECTED=''; APP_RUNNING=''
  HANDLUS_UPDATER_LANG=en "$1/Contents/MacOS/handlus-app" status >$out 2>/dev/null &
  pid=$!
  for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 0.5; done
  if kill -0 $pid 2>/dev/null; then kill $pid 2>/dev/null; rm -f $out; return 1; fi
  wait $pid
  local line
  while IFS= read -r line; do
    case $line in
      Version:*)   APP_VERSION=${${line#Version:}// /} ;;
      Connected:*) APP_CONNECTED=${${line#Connected:}// /} ;;
      Running:*)   APP_RUNNING=${${line#Running:}// /} ;;
    esac
  done <$out
  rm -f $out
  [[ -n $APP_VERSION ]]
}

have_ffmpeg() { command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; }
# /usr/bin/python3 without Command Line Tools is a stub that opens their installer: do not run it then
have_python() {
  local p; p=$(command -v python3 2>/dev/null) || return 1
  [[ $p != /usr/bin/python3 ]] || xcode-select -p >/dev/null 2>&1
}
have_pillow() { have_python && python3 -c 'import PIL' >/dev/null 2>&1; }

# Download the latest app (checked against its sha256), put it in /Applications (or ~/Applications) and open it
TMP_DIR=''
cleanup() {
  [[ -n $TMP_DIR ]] || return 0
  [[ -d $TMP_DIR/mnt/Handlus.app ]] && hdiutil detach "$TMP_DIR/mnt" -quiet -force >/dev/null 2>&1
  rm -rf "$TMP_DIR"
}
install_app() {
  local tmp url sum ver dest mnt got
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/handlus-app.XXXXXX") || return 1
  TMP_DIR=$tmp; mnt=$tmp/mnt
  trap cleanup EXIT
  url=''; sum=''; ver=''
  if curl -fsSL --max-time 30 "$MANIFEST" -o "$tmp/app.json" 2>/dev/null; then
    url=$(plutil -extract files.darwin-dmg.url raw -o - "$tmp/app.json" 2>/dev/null)
    sum=$(plutil -extract files.darwin-dmg.sha256 raw -o - "$tmp/app.json" 2>/dev/null)
    ver=$(plutil -extract version raw -o - "$tmp/app.json" 2>/dev/null)
  fi
  if [[ -z $url ]]; then print "Could not read $MANIFEST. Send the user to $PAGE to download the Handlus app."; return 1; fi
  if [[ -n $ver ]] && ! ver_ge "$ver" $MIN; then
    print "The latest Handlus app is $ver; recording needs $MIN or later, which is not out yet. Nothing was installed."; return 1
  fi
  print "Downloading the Handlus app ${ver:+$ver }…"
  if ! curl -fL --max-time 600 --progress-bar "$url" -o "$tmp/Handlus.dmg"; then print "Download failed. Send the user to $PAGE."; return 1; fi
  if [[ -n $sum ]]; then
    got=$(shasum -a 256 "$tmp/Handlus.dmg" | awk '{print $1}')
    if [[ $got != $sum ]]; then print "The download does not match its checksum. Nothing was installed. Send the user to $PAGE."; return 1; fi
  fi
  mkdir -p "$mnt"
  # macOS 26+ calls these hdiutil flags deprecated (diskutil image is not on macOS 13); they still work, so hide only that warning
  if ! hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$tmp/Handlus.dmg" >/dev/null 2>"$tmp/err"; then
    grep -v deprecated "$tmp/err" >&2; print "Could not open the downloaded disk image. Send the user to $PAGE."; return 1
  fi
  dest=/Applications
  [[ -w $dest ]] || { dest=$HOME/Applications; mkdir -p "$dest"; }
  rm -rf "$dest/Handlus.app.new"
  if ! ditto "$mnt/Handlus.app" "$dest/Handlus.app.new"; then print "Could not copy Handlus.app to $dest. Send the user to $PAGE."; return 1; fi
  rm -rf "$dest/Handlus.app" && mv "$dest/Handlus.app.new" "$dest/Handlus.app"
  hdiutil detach "$mnt" -quiet >/dev/null 2>&1
  print "Opening $dest/Handlus.app"
  open "$dest/Handlus.app"
}

next_steps() {
  print "Next, the user does these in order (only a person can), and you wait until they say they are done:"
  print "  1. Connect this computer: if a Handlus page opened in the browser, they sign in and connect this computer (first time only)."
  print "  2. On the Handlus app window's setup screen: Allow, Accessibility, then Screen Recording. If macOS asks to quit and"
  print "     reopen Handlus, they choose that: it restarts only the Handlus app, not you or the terminal."
  print "Then run setup.sh again, and call desktop_list: this Mac should show [on]."
}

if [[ $MODE == install ]]; then
  print "== install"
  if [[ $(uname) != Darwin ]]; then not_mac; exit 2; fi
  if app=$(find_app) && read_status "$app" && ver_ge "$APP_VERSION" $MIN; then
    if [[ $APP_RUNNING == yes && $APP_CONNECTED == yes ]]; then print "The Handlus app $APP_VERSION is installed, connected and running."
    else print "Opening $app"; open "$app"; next_steps; fi
  else
    install_app || exit 2
    next_steps
  fi
  print
fi

print "== check"
print -r -- "-- On a Mac the Handlus app records: the terminal needs no Screen Recording permission, and Command Line Tools and Homebrew are not needed."
if [[ $(uname) != Darwin ]]; then
  miss "macOS" "$(not_mac)"
else
  v=$(sw_vers -productVersion); if (( ${v%%.*} >= 13 )); then ok "macOS $v"; else miss "macOS $v" "macOS 13 or later is needed"; fi

  if ! app=$(find_app); then
    miss "Handlus app" "zsh $HERE/setup.sh install (downloads it from handlus.com and opens it), or the user installs it from $PAGE"
  elif ! read_status "$app"; then
    miss "Handlus app ($app)" "it did not answer its status command; open it (open \"$app\"), or reinstall from $PAGE"
  else
    if ver_ge "$APP_VERSION" $MIN; then ok "Handlus app $APP_VERSION"
    else miss "Handlus app $MIN or later (this is $APP_VERSION)" "open the app: when it is connected it updates itself within a minute. Or zsh $HERE/setup.sh install"; fi
    if [[ $APP_CONNECTED == yes ]]; then ok "connected to a Handlus account"
    else miss "connected" "open the app (open \"$app\"): it opens a page in the browser where the user connects this computer"; fi
    if [[ $APP_RUNNING == yes ]]; then ok "running"
    else miss "running" "open \"$app\""; fi
  fi

  b=''
  for n in "Google Chrome" "Microsoft Edge" "Whale"; do
    [[ -d "/Applications/$n.app" || -d "$HOME/Applications/$n.app" ]] && { b=$n; break; }
  done
  if [[ -n $b ]]; then ok "browser ($b)"; else miss "browser" "install Google Chrome from https://www.google.com/chrome/"; fi

  if have_ffmpeg; then ok "ffmpeg · ffprobe ($(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}'), optional)"
  else opt "ffmpeg · ffprobe" "only to trim the video or make a preview sheet: brew install ffmpeg"; fi
  if have_pillow; then ok "python3 · Pillow (optional)"
  elif have_python; then opt "Pillow (python3)" "only for the preview sheet: python3 -m pip install --user pillow"
  else opt "python3 · Pillow" "only for the preview sheet and evidence file: Command Line Tools (xcode-select --install), then python3 -m pip install --user pillow"; fi
fi

print -r -- "-- Check from your tools too: desktop_list shows this Mac [on]. [screen_off] means Screen Recording is off for Handlus: the user turns it on in the Handlus app window's setup screen. chrome_demo_cursor and desktop_record must be in your tool list."
if (( missing )); then print "NOT READY ($missing missing)"; exit 2; fi
print "READY"

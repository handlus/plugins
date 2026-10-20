#!/bin/zsh
# rec.sh — the shell side of a Chrome window recording (recording-chrome-fake-cursor skill)
#
#   rec.sh screens                      pick the recording display → prints X/Y/SCALE/MONITOR
#   rec.sh place <title-marker>         move the Chrome window whose title starts with the marker to the recording slot (W×H) and raise it
#   rec.sh record <T0ms> <sec> <out.mp4>  wait until T0−1.5s, then record that window only (prints rec_started)
#
# Browser steps (open window, title marker, cursor) are done by the agent through MCP — see ../SKILL.md
#
# REC_MONITOR   unset = main display (top-left at 0,0) · <name prefix> = a display from `screcord screens`
# REC_W · REC_H window size (default 1920×1200). Lower REC_H on displays shorter than 1200
set -euo pipefail
HERE=${0:A:h}
BIN=$HERE/bin/screcord
[[ -x $BIN ]] || zsh $HERE/build.sh >/dev/null
W=${REC_W:-1920}; H=${REC_H:-1200}

pick() {   # prints: X Y SCALE MONITOR…  (window top-left = W×H centred on the display; the name goes last because it may contain spaces)
  local line name ax ay mw mh sc
  local want=${REC_MONITOR:-main}
  while IFS= read -r line; do
    name=${line%%  at:*}
    [[ $line =~ 'at:(-?[0-9]+),(-?[0-9]+)  ([0-9]+)x([0-9]+)  scale=([0-9.]+)' ]] || continue
    ax=$match[1]; ay=$match[2]; mw=$match[3]; mh=$match[4]; sc=$match[5]
    if [[ $want == main && $ax == 0 && $ay == 0 ]] || [[ $want != main && $name == ${want}* ]]; then
      echo "$(( ax + (mw - W) / 2 )) $(( ay + (mh - H) / 2 )) $sc $name"; return 0
    fi
  done < <($BIN screens)
  return 1
}

case ${1:-} in
  screens)
    $BIN screens >&2
    if r=$(pick); then
      set -- ${=r}
      echo "X=$1 Y=$2 SCALE=$3 MONITOR='${@:4}'"
      if [[ $3 == 2* ]]; then echo "# scale 2 — the video is $((W*2))x$((H*2)); multiply crop coordinates by 2" >&2; fi
    else
      echo "⛔ no display named ${REC_MONITOR:-main} — check rec.sh screens" >&2
      exit 3
    fi ;;
  place)
    mark=${2:?title marker (__rec_…)}
    r=$(pick) || { echo "⛔ no recording display — run rec.sh screens" >&2; exit 3; }
    set -- ${=r}; X=$1; Y=$2
    # Stop if another window already occupies the slot (another agent recording) — covering it freezes their recording
    if busy=$($BIN list 2>/dev/null | grep -F "at:$X,$Y  ${W}x${H}" | grep -vF " $mark"); then
      if [[ -n $busy ]]; then
        echo "⛔ another window already sits in the recording slot — another agent may be recording. Wait, or use another display with REC_MONITOR:" >&2
        echo "$busy" >&2
        exit 4
      fi
    fi
    # Use System Events + the Chrome PID that owns the marked window (AppleScript "tell application Google Chrome" can grab an automation Chrome)
    CANDS=($(for p in $(pgrep -x "Google Chrome"); do ps -o command= -p $p | grep -q -- "--disable-field-trial-config" || echo $p; done))
    [[ ${#CANDS[@]} -gt 0 ]] || { echo "⛔ no Chrome process" >&2; exit 2; }
    PID=${CANDS[1]}
    for p in "${CANDS[@]}"; do
      n=$(osascript -e "tell application \"System Events\" to count (windows of (first process whose unix id is $p) whose name starts with \"$mark\")" 2>/dev/null || echo 0)
      [[ $n == 1 ]] && { PID=$p; break; }
    done
    osascript -e "tell application \"System Events\"
set p to first process whose unix id is $PID
set ws to (windows of p whose name starts with \"$mark\")
if (count of ws) is not 1 then return \"found \" & (count of ws)
set w to item 1 of ws
set position of w to {$X, $Y}
set size of w to {$W, $H}
perform action \"AXRaise\" of w
set frontmost of p to true
return \"ok \" & (position of w as string) & \" \" & (size of w as string)
end tell" | tee /dev/stderr | grep -q '^ok' || { echo "⛔ expected exactly one window with that title marker" >&2; exit 2; } ;;
  record)
    T0=${2:?T0 in ms}; SEC=${3:?seconds}; OUT=${4:?out.mp4}
    r=$(pick) || { echo "⛔ no recording display" >&2; exit 3; }
    set -- ${=r}; X=$1; Y=$2
    mkdir -p ${OUT:h}
    now=$(python3 -c 'import time;print(int(time.time()*1000))')
    wait=$(python3 -c "print(max(0,($T0-$now-1500)/1000))")
    sleep $wait
    $BIN at:$X,$Y $SEC $OUT ;;
  *)
    sed -n 2,16p $0; exit 1 ;;
esac

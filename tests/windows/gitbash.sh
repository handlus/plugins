#!/usr/bin/env bash
# gitbash.sh - the commands windows.md gives for Claude Code (Git Bash), run as written there.
# Expects e2e.ps1 to have run in the same job (ffmpeg / Python / Pillow installed, Chrome with the test page open).
set -u
cd "$(dirname "$0")/../.."
K="$(cygpath -w "$PWD/plugins/handlus/skills/recording-chrome-fake-cursor/scripts")"
OUT="$(cygpath -w "$PWD/out")"
fail=0
check() { if [ "$1" = 0 ]; then echo "PASS  $2"; else echo "FAIL  $2"; fail=1; fi; }

echo "### git bash: $(bash --version | head -1)"
echo "K=$K"

powershell -NoProfile -ExecutionPolicy Bypass -File "$K\setup.ps1" > "$OUT\gb-setup.txt" 2>&1; rc=$?
cat "$OUT\gb-setup.txt"
check $([ $rc = 0 ] && grep -q '^READY' "$OUT\gb-setup.txt"; echo $?) 'Git Bash: setup.ps1 READY'

PY="$(sed -n "s/.*run the skill's .py scripts with: \(.*\))\$/\1/p" "$OUT\gb-setup.txt" | tr -d '\r')"
echo "python command: $PY"
pyrun() { eval "$PY" '"$@"'; }   # the command exactly as setup.ps1 printed it (py -3, or a quoted path)
DRIVE="$(cygpath -w "$PWD/tests/windows/drive.py")"

slot="$(powershell -NoProfile -ExecutionPolicy Bypass -File "$K\rec.ps1" screens 2>/dev/null | tr -d '\r')"
echo "$slot"
check $([[ "$slot" == X=* ]]; echo $?) 'Git Bash: rec.ps1 screens prints the slot'

pyrun "$DRIVE" title __rec_gb > /dev/null
pl="$(powershell -NoProfile -ExecutionPolicy Bypass -File "$K\rec.ps1" place __rec_gb 2>&1)"; rc=$?; pl="${pl//$'\r'/}"
echo "$pl"
check $([ $rc = 0 ] && [[ "$pl" == ok* ]]; echo $?) 'Git Bash: rec.ps1 place'

T0=$(( $(date +%s%3N) + 8000 ))
pyrun "$DRIVE" play $T0 basic
powershell -NoProfile -ExecutionPolicy Bypass -File "$K\rec.ps1" record $T0 8 "$OUT\gb.mp4"; rc=$?
check $rc 'Git Bash: rec.ps1 record'
sleep 1
pyrun "$DRIVE" fclog "$OUT\gb.fclog.json" > /dev/null
MON="$(sed -n "s/.*MONITOR='\([^']*\)'.*/\1/p" <<< "$slot")"
SC="$(sed -n 's/.*SCALE=\([0-9.]*\).*/\1/p' <<< "$slot")"
# the command line windows.md gives for step 8, with the Python command setup.ps1 printed
pyrun "$K\evidence.py" write "$OUT\gb.mp4" --monitor "$MON" --scale "$SC" --profile ci --url test --fclog "$OUT\gb.fclog.json" --action gitbash; rc=$?
check $rc 'Git Bash: evidence.py write passes'

exit $fail

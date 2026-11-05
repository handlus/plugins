# Windows: commands for the same steps

Use these commands in place of the macOS ones in SKILL.md when you run on Windows. The rules, shot list, cursor
(`chrome_demo_cursor` or `scripts/cursor.js`), evidence and traps in SKILL.md stay the same.

Recording uses **Windows.Graphics.Capture** (built into Windows, the API the Snipping Tool uses) through `scripts/win32.cs`,
which `rec.ps1` compiles on the fly: only the Chrome window is recorded, windows partly over it do not show up, and the
real mouse pointer is not drawn. It works with or without a graphics card. ffmpeg only encodes the frames (H.264, 60 per
second). There is no permission to turn on.

## How to call the scripts

Claude Code on Windows runs commands in Git Bash; Codex runs them in PowerShell. Both call the same PowerShell scripts.
Shell variables do not carry over between your commands, so write the full line each time.

**Git Bash** (convert the folder once per command with `cygpath -w`):
```bash
K="$(cygpath -w "${CLAUDE_SKILL_DIR}/scripts")"      # or the scripts folder beside this file
powershell -NoProfile -ExecutionPolicy Bypass -File "$K\setup.ps1"
```

**PowerShell**:
```powershell
$K = '<skill folder>\scripts'
powershell -NoProfile -ExecutionPolicy Bypass -File "$K\setup.ps1"
```

Below, `REC <cmd>` means `powershell -NoProfile -ExecutionPolicy Bypass -File "$K\rec.ps1" <cmd>` and `SETUP` the same with
`setup.ps1`. `PY` is the Python command `setup.ps1` prints on its Python line (usually `py -3`). Do not use `python3`:
on Windows it is often the Microsoft Store placeholder, which does nothing.

`-ExecutionPolicy Bypass` applies to that one process only and changes no setting. If it still says scripts are disabled,
a company policy blocks PowerShell scripts: tell the user; do not try to change the policy.

## 0. Setup (every time)

```bash
SETUP              # one line per item, last line READY or NOT READY (exit 0 / 2)
```
It checks Windows 10 2004+ / 11, ffmpeg with an H.264 encoder, Python 3 and Pillow, Google Chrome, and records one open
Chrome window for 1 s (skipped if no Chrome window is open).

If it prints `NOT READY`: tell the user what is missing and what installing it means, ask once, then
```bash
SETUP install      # ffmpeg into scripts\bin\ffmpeg (from github.com/BtbN/FFmpeg-Builds), Python (winget or python.org,
                   # for this user only) and Pillow (pip --user). No administrator rights, then it checks again
```
Nothing needs a restart. Hand over only what a person must do: an administrator prompt if one appears, updating Windows,
or a company policy. Record only after `READY`.

Then check Handlus from your tools as in SKILL.md section 0.

## Steps (numbers as in SKILL.md)

**3. Display** — `REC screens` → `X=… Y=… W=… H=… SCALE=… LW=… LH=… MONITOR='DISPLAY1'`. It also lists every display on stderr.
- Default is the primary display; `REC_MONITOR=DISPLAY2` picks another (Git Bash: put it before the command,
  `REC_MONITOR=DISPLAY2 powershell …`; PowerShell: `$env:REC_MONITOR='DISPLAY2'` first).
- The window is 1920×1200 *logical* pixels, or the first of 1600×1000, 1440×900, 1280×800, 1024×640 that fits the display
  (taskbar excluded); that logical size is `LW`×`LH`. Force a size with `REC_W` / `REC_H`.
- `W`×`H` is the size on screen **and of the video**: logical size × `SCALE` (Windows display scale 1, 1.25, 1.5, 1.75…).
  Crop coordinates in the video are page coordinates × `SCALE` plus Chrome's tab strip and toolbar.

**4. Window**
- `chrome_navigate … newWindow:true width:<LW> height:<LH>` with the unique `?rec=<name>` query, then
  `chrome_demo_cursor action:"title" title:"__rec_<name>"` — as in SKILL.md
- `REC place __rec_<name>` → must print `ok X,Y WxH fg=yes`. It restores a minimized or maximized window, moves and sizes it
  so that its visible frame fills the slot, and brings it to the front
  - **Exit 4**: another Chrome window already sits in the slot (another agent may be recording). Wait, or use another display
  - `fg=no`: Windows did not let the script bring the window to the front (foreground lock). Call `chrome_switch_tab` on its
    tab, and make sure nothing covers it

**5. Cursor** — exactly as SKILL.md 5-A (`chrome_demo_cursor`) or 5-B (`cursor.js`).

**6. Record** — `REC record <T0> <action length + 3> <out>\REC.mp4` → prints `window …`, `size …`, `rec_started <ms>`,
`saved <path>`. It waits until T0 − 1.5 s, records only that window (found at the slot position) and stops by itself.

**7. Clean up** — as SKILL.md. Save the `log` from `chrome_demo_cursor action:"status"` as `fclog.json` with your file tool.

**8. Evidence, trim, sign** — the same scripts through `PY`:
```bash
PY "$K\evidence.py" write REC.mp4 --monitor "<MONITOR>" --scale <SCALE> --profile <profile> --url "<url>" --fclog fclog.json --action "<what happened>"
PY "$K\sheet.py" REC.mp4 --from <a> --to <b> --step 0.25 [--crop x,y,w,h] --out sheet.jpg
PY "$K\sheet.py" REC.mp4 --preview --segments 'a-b' --crop x,y,w,h --out preview.jpg
PY "$K\evidence.py" sign REC.mp4 --sheet preview.jpg --note "removed: …"
PY "$K\evidence.py" check REC.mp4
```
`patch_lights.py` is for macOS window buttons only; Windows does not need it.

## Windows traps

| Symptom | Cause | Fix |
|---|---|---|
| Frozen picture in part of the video | The recording window was **fully** covered or minimized, so Chrome stopped painting it (Windows tells Chrome the window is hidden) | Keep the window uncovered and not minimized; `evidence.py write` fails such a take |
| `place` prints `fg=no` | Foreground lock: Windows lets only the app you are using change the front window | `chrome_switch_tab` on the tab, then check nothing covers it |
| `STOP: a …x… window does not fit` | Display scale is high (150%: a 1920×1080 screen is 1280×720 logical) | Let it choose (unset `REC_W`/`REC_H`) or use another display |
| `ffmpeg not found` / `has no H.264 encoder` | No ffmpeg, or a build without libx264 and h264_mf | `SETUP install` (it puts one in `scripts\bin\ffmpeg`); or set `HANDLUS_FFMPEG` to another ffmpeg.exe |
| `rec_slow: … frames were written late` | The computer could not encode 60 frames a second (the take would stutter) | Close heavy apps, `HANDLUS_X264=ultrafast`, or a smaller window (`REC_W` / `REC_H`); record again |
| `STOP: window capture: …` | Windows refused to capture that window (minimized, closed, or Windows older than 10 2004) | Restore the window, check `SETUP`; the message names the failing step |
| `python` opens the Microsoft Store or does nothing (exit 9009) | Store placeholder | Use the command `setup.ps1` printed (`py -3`) |
| `running scripts is disabled on this system` even with `-ExecutionPolicy Bypass` | Company group policy | Tell the user; do not change policy |
| Yellow frame around the window while recording (Windows 10) | Windows' capture indicator | On screen only, not in the video |
| Codex: `Access is denied`, no displays, or `found 0` for a window you can see | The Codex sandbox may not reach other apps' windows | Run `rec.ps1` outside the sandbox (approve the escalation) |
| Running inside WSL | WSL cannot see or record Windows windows | Run Claude Code or Codex on Windows itself |
| "…started debugging this browser" bar | Same as macOS | Same as macOS: no debugger-based calls from any agent during the take |

## Quick reference

```bash
SETUP [install]                       # what is missing (and install it)
REC screens                           # displays and the recording slot
REC list                              # Chrome windows (hwnd · visible frame · title)
REC place <marker>                    # put the marked window in the slot
REC record <T0ms> <sec> <out.mp4>     # record that window
REC ffmpeg                            # which ffmpeg, and whether it can capture a window
REC probe                             # 1 s test recording of an open Chrome window
```

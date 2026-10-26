---
name: recording-chrome-fake-cursor
description: Record a real Chrome window on macOS while an AI agent drives it, with a visible fake mouse cursor that glides, clicks with an orange ripple and types one letter at a time — without moving the real mouse, so you can keep working. Use for product demos, tutorials, reels, shorts and lecture clips of Chrome being operated through Handlus (or another Chrome MCP). Also when a recording froze, showed Chrome's "started debugging this browser" bar, captured a covered window, or failed with a screen-recording permission (TCC) error, and to set up or check recording on a Mac ("set up recording", "is recording ready", installing ffmpeg or the Screen Recording permission). 크롬 화면 녹화 · 가짜 커서 · 마우스가 움직이는 영상 · 클릭할 때 주황 원 · 한 글자씩 입력되는 화면 · 핸들러스로 조작하며 찍기 · 녹화 준비해 줘 · 녹화 설치 · 화면 기록 권한.
---

# Fake-cursor Chrome window recording (macOS)

The agent drives Chrome through **Handlus** and draws a **fake cursor** in the page; a ScreenCaptureKit recorder captures **that one Chrome window**.
The cursor moves in a slight arc, shrinks and spreads an orange ring when it clicks, and types character by character, then really clicks and types on the page.
The real mouse never moves, so the user can keep working on another screen. Because it is a window recording, other windows partly overlapping it do not show up.

Scripts live next to this file: `K="${CLAUDE_SKILL_DIR}/scripts"` (in Codex, or if that variable is not substituted, use the `scripts/` folder beside this SKILL.md).

## 0. Setup — run this first, every time

```bash
zsh $K/setup.sh            # check only: one line per item, last line READY or NOT READY (exit 0 / 2)
```

It checks macOS 13+, Xcode Command Line Tools (`swiftc`), `python3`, `ffmpeg` and `ffprobe`, Google Chrome, builds the recorder `bin/screcord`, and asks ScreenCaptureKit for windows to test the **Screen Recording permission** of the terminal app running you.

If it prints `NOT READY`:
1. Tell the user, in their language, what is missing and what installing it means (ffmpeg comes from Homebrew; the permission is a switch in System Settings). Ask once, then run
   ```bash
   zsh $K/setup.sh install    # installs ffmpeg (brew), builds the recorder, opens the dialogs, then checks again
   ```
2. Hand over only the steps a person has to do, one at a time, and wait for them:
   - **Command Line Tools**: a macOS dialog opens; they click Install and wait a few minutes. Then run `setup.sh install` again
   - **Homebrew** (only if missing): they paste the command `setup.sh install` printed into their own terminal; it asks for their Mac password. Do not run it yourself
   - **Screen Recording**: System Settings opens on Privacy & Security → Screen & System Audio Recording. They turn on the app `setup.sh` names (the terminal or editor running you; under tmux, the app that started tmux), then **quit and reopen that app** — macOS applies it only after a restart, so this session ends there. Tell them to start you again and say "record" when it is back
3. Run `zsh $K/setup.sh` again. Record only after `READY`.

Then check Handlus from your tools: `chrome_list_browsers` must answer (if the Handlus tools are missing, give the user `claude mcp add --transport http --scope user handlus https://api.handlus.com/mcp` or `codex mcp add handlus --url https://api.handlus.com/mcp` and the extension link https://handlus.com), and `chrome_demo_cursor` must be in your tool list (Handlus extension 0.3.1+, which draws the cursor **without Chrome's debugger**). Without it, update the extension, or use `scripts/cursor.js` (section 5-B).

Do not reset or edit macOS privacy settings yourself (no `tccutil`), and do not click permission prompts for the user.

## Rules

1. Drive Chrome only through MCP (open windows, cursor, schedule). The shell only runs `setup.sh`, `rec.sh`, `evidence.py` and `sheet.py`
2. **Never press buttons that leave a trace outside the page** — publish, send, pay, connect, delete. Hover the cursor over them for the shot and cancel afterwards
3. Close only the windows and tabs you opened. Do not launch a new Chrome process
4. Do not record sites whose terms forbid automation, and keep personal data (names, emails, other accounts) out of the frame
5. Do not use `chrome_gif_recorder` or whole-screen recording — they stutter and capture covering windows

## Steps

**1. Shot list** — for each scene: Chrome profile, URL, actions (move, click, type, wait), expected screen, and what must stay out of frame.

**2. Dry run (no recording)** — run the same steps once with `chrome_demo_cursor action:"play"` and no `startAt`. Fix any step that logs `error`, and anything that shows personal data.

**3. Display** — `zsh $K/rec.sh screens` → `X=… Y=… SCALE=… MONITOR=…`. Default is the main display; `REC_MONITOR=<name prefix>` picks another. On a scale-2 (Retina) display the video is 2× (3840×2400) and crop coordinates double. If the display is shorter than 1200 px, set `REC_H=1000`.

**4. Window**
- `chrome_navigate browser:<profile> url:"<url>?rec=<name>" newWindow:true width:1920 height:1200` — the unique `?rec=` query prevents reusing an existing tab
- `chrome_demo_cursor action:"title" title:"__rec_<name>"` (temporary title marker)
- `zsh $K/rec.sh place __rec_<name>` → must print `ok …`. **Exit 4** means another window already sits in the recording slot (another agent may be recording) — wait, or use another display

**5-A. Cursor and schedule — Handlus `chrome_demo_cursor`**
```text
chrome_demo_cursor action:"play" startAt:<T0 epoch ms> start:[1500, 760] scrollTop:true steps:[
  {op:"wait", ms:600},
  {op:"click", to:"nav a[href='#features']", label:"features"},
  {op:"type",  target:"input[name=q]", text:"hello", msPer:70},
  {op:"scroll", by:500},
  {op:"mark",  label:"end-scene"}
]
```
- Steps: `move` · `click` · `type` (input, textarea, contenteditable) · `key` · `scroll` (`by` or `to`) · `wait` · `mark`. `to`/`target` = CSS selector, `[x, y]` or `{x, y}`
- One second before `startAt` it clears selection and focus and puts the cursor at `start`. Pick `T0` about 15 s ahead so the recorder is running first
- Rhythm that looks human: move 0.4–1 s (automatic) · pause 0.16 s · press 0.26 s · typing 45–90 ms per character

**5-B. Cursor and schedule — other Chrome MCPs (or Handlus ≤ 0.3.0)** — inject `scripts/cursor.js` with the MCP's JavaScript tool (pass the whole file as the code), then in a second call `window.__fc.runAt(T0, {start, prep, script: async (F, log) => { … }})` with `F.clickEl`, `F.typeInto`, `F.typeCE`, `F.moveTo`, `F.scrollBy`. These JavaScript tools use Chrome's debugger, so finish them **at least 20 s before T0**. Read the log afterwards with `JSON.stringify(window.__fcLog)` (it stays in the page; a page-changing click must be the last step, preceded by `log('nav: …')`).

**6. Record** — `zsh $K/rec.sh record <T0> <action length + 3> <out>/REC.mp4` (note the `rec_started` line). Keep the recording only 3 s longer than the action; a long static tail lowers the frame rate.

**7. Clean up** — `chrome_demo_cursor action:"status"` → save `log` as `fclog.json` (format `[[ms from T0, label, document.hidden], …]`; it survives a page-changing click) → `action:"title" title:""` → `action:"hide"` → close the tab you opened.

**8. Evidence, trim, sign**
```bash
python3 $K/evidence.py write REC.mp4 --monitor "<display>" --scale <scale> --profile <profile> --url "<url>" --fclog fclog.json --action "<what happened>"
python3 $K/sheet.py REC.mp4 --from <a> --to <b> --step 0.25 [--crop x,y,w,h] --out sheet.jpg   # choose the segment
python3 $K/sheet.py REC.mp4 --preview --segments 'a-b' --crop x,y,w,h --out preview.jpg        # look at it, then:
python3 $K/evidence.py sign REC.mp4 --sheet preview.jpg --note "removed: …"
python3 $K/evidence.py check REC.mp4     # must pass before you hand the video over
```
`write` fails the take (record again) if any log line was `hidden`, fps < 40, or `start`/`end` is missing.

## Traps (all observed)

| Symptom | Cause | Fix |
|---|---|---|
| Frozen screen in the video | The window was **fully** covered, so Chrome stopped painting (`document.hidden`) | Keep the recording window uncovered; `evidence.py` catches it |
| Page pushed down 56 px by a "…started debugging this browser" bar | Any extension using Chrome's debugger. The bar is **browser-wide — every window of every profile** — so another agent's debugger-based tool call anywhere shows it in your take | Use `chrome_demo_cursor` (no debugger). No debugger-based calls (JavaScript, screenshot, `chrome_computer`) from **any** agent from T0 − 20 s until the end — tell other running agents first |
| `screcord`: `-3801 … TCC` | The terminal app has no Screen Recording permission. Under tmux the permission of the app that started tmux applies, and long-running tmux servers can keep the old answer | Grant the permission and restart the terminal; or run the recorder from a terminal window that has it (e.g. `osascript -e 'tell application "iTerm" to create window with default profile command "/bin/zsh -c \'<cmd> > out.txt 2>&1; touch out.txt.done\'"'` and wait for `out.txt.done`) |
| `record`: `expected exactly 1 window, got 2` | Another window sits exactly in the recording slot | `rec.sh place` now stops with exit 4 first; wait or use another display |
| `newWindow` brought the user's window forward | A tab with the same URL already existed | Unique `?rec=` query |
| Blue selected text in the first frame | Leftover selection | `play` clears it one second before T0 |
| "Recent downloads" bubble in the corner | A screenshot with `savePng` created a download | Do not save screenshots in the recording window; press Escape on the bubble |
| Clicks on a cross-origin iframe do nothing | The fake cursor clicks the iframe element, not its contents | Show the cursor moving there, and do the real action another way |
| Recording starts on the wrong page | A previous take's schedule navigated away | Check the URL and first screen before scheduling |

## Quick reference

```bash
zsh $K/setup.sh [install]             # what is missing (and install it)
zsh $K/build.sh                       # rebuild bin/screcord
$K/bin/screcord screens               # displays (name · top-left · size · scale)
$K/bin/screcord list                  # Chrome windows (id · position · title)
$K/bin/screcord at:<x>,<y> <sec> <out.mp4>   # record the window at that top-left (what rec.sh record uses)
```
Report back: the video path, the `evidence.py check` result, and anything the dry run left in the user's accounts.

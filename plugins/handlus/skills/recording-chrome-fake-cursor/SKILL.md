---
name: recording-chrome-fake-cursor
description: Record a real Chrome window on macOS or Windows while an AI agent drives it, with a visible fake mouse cursor that glides, clicks with an orange ripple and types one letter at a time, without moving the real mouse, so you can keep working. On a Mac the Handlus app records the window (desktop_record); on Windows a PowerShell recorder does. Use for product demos, tutorials, reels, shorts and lecture clips of Chrome being operated through Handlus. Also when a recording froze, showed Chrome's "started debugging this browser" bar, captured a covered window, or failed with a Screen Recording permission error, and to set up or check recording on a Mac or a Windows PC ("set up recording", "is recording ready", the Handlus app and its Screen Recording switch on macOS, PowerShell setup on Windows). 크롬 화면 녹화 · 가짜 커서 · 마우스가 움직이는 영상 · 클릭할 때 주황 원 · 한 글자씩 입력되는 화면 · 핸들러스로 조작하며 찍기 · 녹화 준비해 줘 · 녹화 설치 · 화면 기록 권한 · 윈도우에서 녹화.
---

# Fake-cursor Chrome window recording (macOS · Windows)

The agent drives Chrome through **Handlus** and draws a **fake cursor** in the page, and **that one browser window** is recorded: on macOS by the **Handlus app** (`desktop_record`, app 1.5.0 or later), on Windows by `rec.ps1` (Windows.Graphics.Capture).
The cursor moves in a slight arc, shrinks and spreads an orange ring when it clicks, and types character by character, then really clicks and types on the page.
The real mouse never moves, so the user can keep working on another screen. Because it is a window recording, other windows partly overlapping it do not show up.

Scripts live next to this file: `K="${CLAUDE_SKILL_DIR}/scripts"` (in Codex, or if that variable is not substituted, use the `scripts/` folder beside this SKILL.md).

**On Windows, read [windows.md](windows.md) now and use its commands** (`setup.ps1` · `rec.ps1` · the Python command `setup.ps1` prints) in place of the macOS ones here (`setup.sh` · `desktop_record` · `python3`). Everything else (rules, shot list, cursor, evidence, traps) is the same. Inside WSL, stop and tell the user to run you from Windows itself. Other systems are not supported.

## 0. Setup: check this first, every time (macOS; Windows: windows.md)

On a Mac the **Handlus app** records the window. It uses its own Screen Recording permission, which the user turns on once on the app's setup screen. The terminal running you needs no permission, and nothing has to be built or installed for the recording itself.

Check from your tools:
1. `desktop_list`: this Mac shows `[on]`. Note its name and pass it as `computer` to `desktop_record`.
   - `[screen_off]`: Screen Recording is off for Handlus. Tell the user to turn it on in the Handlus app window's setup screen. If macOS asks to quit and reopen Handlus, that restarts only the app, not you. `desktop_record start` also opens that screen by itself
   - `[not_allowed]`: the user clicks Allow in the app window. `[needs_permission]`: Accessibility is off (the app uses it to bring the window to the front)
   - `[update_required]`, or `desktop_record` says the app is older than 1.5.0: a connected app updates itself within a minute; or run `setup.sh install`
   - This Mac is not listed, or there are no `desktop_*` tools: the Handlus app is missing or not connected. Check with `setup.sh` below
2. `desktop_record` and `chrome_demo_cursor` are in your tool list.

```bash
zsh $K/setup.sh            # the Handlus app: installed, 1.5.0+, connected, running. Last line READY or NOT READY (exit 0 / 2)
zsh $K/setup.sh install    # with the user's OK: downloads the app from handlus.com, puts it in /Applications and opens it
```
In Codex, run `setup.sh install` outside the sandbox (it needs the network). After it, only the user can do the rest, one at a time, and you wait for them: connect this computer on the Handlus page that opens in the browser (first time only), then Allow, Accessibility and Screen Recording on the app's setup screen. Then check again. `setup.sh` also lists ffmpeg and python3 with Pillow as optional: they are needed only to trim the video or make a preview sheet (step 8).

On both systems, check Handlus from your tools: `chrome_list_browsers` must answer (if the Handlus tools are missing, give the user `claude mcp add --transport http --scope user handlus https://api.handlus.com/mcp` or `codex mcp add handlus --url https://api.handlus.com/mcp` and the link https://handlus.com), and `chrome_demo_cursor` must be in your tool list (Handlus extension 0.3.1+, which draws the cursor **without Chrome's debugger**). Without it, update the extension, or use `scripts/cursor.js` (section 5-B).

Do not reset or edit macOS privacy settings yourself (no `tccutil`), and do not click permission prompts for the user.

## Rules

1. Drive Chrome only through MCP (open windows, cursor, schedule). On a Mac the recording is a tool call too (`desktop_record`). The shell only runs `setup.sh`, and if you want them `evidence.py` and `sheet.py`
2. **Never press buttons that leave a trace outside the page** — publish, send, pay, connect, delete. Hover the cursor over them for the shot and cancel afterwards
3. Close only the windows and tabs you opened. Do not launch a new Chrome process
4. Do not record sites whose terms forbid automation, and keep personal data (names, emails, other accounts) out of the frame
5. Do not use `chrome_gif_recorder` or whole-screen recording — they stutter and capture covering windows

## Steps

**1. Shot list** — for each scene: Chrome profile, URL, actions (move, click, type, wait), expected screen, and what must stay out of frame.

**2. Dry run (no recording)** — run the same steps once with `chrome_demo_cursor action:"play"` and no `startAt`. Fix any step that logs `error`, and anything that shows personal data.

**3. Display** (macOS): nothing to pick. The window is recorded where it is, on whichever display it is, and is never moved. The video is the window size × that display's scale: a 1280×800 window on a Retina (scale 2) display gives 2560×1600, and crop coordinates double. `desktop_record start` returns `width` and `height`.

**4. Window**
- `chrome_navigate browser:<profile> url:"<url>?rec=<name>" newWindow:true width:1280 height:800`. The unique `?rec=` query prevents reusing an existing tab. `<name>` uses only letters, digits, `_` and `-`. A larger window (1440×900, 1920×1200) suits a larger display; Chrome keeps the window on the screen, so read the real size from `desktop_record start` (`window`, `width`, `height`)
- `chrome_demo_cursor action:"title" title:"__rec_<name>"` (temporary title marker; exactly one window may contain it)
- macOS: do not move or resize the window after this (windows.md has its own `place` step). Ask the user not to put another window fully over it, and not to minimize it, until the take ends

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
- One second before `startAt` it clears selection and focus and puts the cursor at `start`. Pick `T0` about 25 s ahead so the recorder is running first
- **On a Mac, call `desktop_record start` (step 6) before `play`**, with the same T0
- Rhythm that looks human: move 0.4–1 s (automatic) · pause 0.16 s · press 0.26 s · typing 45–90 ms per character

**5-B. Cursor and schedule — other Chrome MCPs (or Handlus ≤ 0.3.0)** — inject `scripts/cursor.js` with the MCP's JavaScript tool (pass the whole file as the code), then in a second call `window.__fc.runAt(T0, {start, prep, script: async (F, log) => { … }})` with `F.clickEl`, `F.typeInto`, `F.typeCE`, `F.moveTo`, `F.scrollBy`. These JavaScript tools use Chrome's debugger, so finish them **at least 20 s before T0**. Read the log afterwards with `JSON.stringify(window.__fcLog)` (it stays in the page; a page-changing click must be the last step, preceded by `log('nav: …')`).

**6. Record** (macOS), in this order with one T0 (epoch ms, about 25 s ahead, at most 60 s):
1. `desktop_record action:"start" marker:"__rec_<name>" seconds:<action length + 3> start_at:<T0> computer:"<this Mac>"` → `{"id":"rec-…","state":"waiting","file":"…/Movies/Handlus/rec-….mp4","width":…,"height":…,"covered_pct":…,"raised":true,…}`. The app brings the window to the front, checks that it is not covered, and records only that window from 1.5 s before T0. An error answer names the problem and the next step (Traps)
2. `chrome_demo_cursor action:"status"`: if `hidden` is `true`, the window is still covered or minimized. Do not play: `desktop_record action:"stop" id:<id>`, have it uncovered, and start again with a new T0
3. `chrome_demo_cursor action:"play" startAt:<T0> …` (5-A). Its answer has `hidden` too; if it is `true`, stop and record again. If T0 is less than 3 s away by now, stop and start again with a new T0
4. `desktop_record action:"status" id:<id> wait_ms:45000`, repeated until `state` is `done` (or `failed`). The done answer has `file`, `width`, `height`, `video_seconds`, `fps`, `frames` and `dropped`

Keep the recording only 3 s longer than the action; a long static tail lowers the frame rate. One recording at a time per computer, up to 600 s. `stop` ends early and keeps the file.

**7. Clean up**: `chrome_demo_cursor action:"status"` → keep its `log` (format `[[ms from T0, label, document.hidden], …]`; it survives a page-changing click), and save it as `fclog.json` with your file tool if you write the evidence file → `action:"title" title:""` → `action:"hide"` → close the tab you opened. On a Mac the video is in `~/Movies/Handlus/`; move it to where the user wants it.

**8. Check, trim, evidence**

On a Mac, with no extra tools, the take passes when all of these hold; otherwise record again:
- the done `desktop_record` status: `state` is `done`, `fps` ≥ 40, and `video_seconds` is about the `seconds` you asked for
- the cursor `log`: it has `start` and `end` (or a `nav: …` label before a page-changing click), no label starting with `error`, and no line whose third value (`document.hidden`) is `true`

With python3 (and ffmpeg and Pillow for the sheets; `setup.sh` shows which are there) also write the evidence file and look at the frames. On Windows this is the check (windows.md 8):
```bash
python3 $K/evidence.py write REC.mp4 --app status.json --profile <profile> --url "<url>" --fclog fclog.json --action "<what happened>"   # macOS: status.json = the done status answer
python3 $K/sheet.py REC.mp4 --from <a> --to <b> --step 0.25 [--crop x,y,w,h] --out sheet.jpg   # choose the segment
python3 $K/sheet.py REC.mp4 --preview --segments 'a-b' --crop x,y,w,h --out preview.jpg        # look at it, then:
python3 $K/evidence.py sign REC.mp4 --sheet preview.jpg --note "removed: …"
python3 $K/evidence.py check REC.mp4     # must pass before you hand the video over
```
`write` fails the take (record again) if any log line was `hidden`, fps < 40, `start`/`end` is missing, or the app's `state` is not `done`. Without `--app` it reads the video with ffprobe and needs `--monitor` and `--scale`.

## Traps

| Symptom | Cause | Fix |
|---|---|---|
| Frozen screen in the video | The window was **fully** covered or minimized, so Chrome stopped painting (`document.hidden`) | Keep the recording window uncovered. On a Mac the app brings it to the front first and refuses with `window_hidden` if it is still covered; also check `hidden` before `play` and in the log |
| Page pushed down 56 px by a "…started debugging this browser" bar | Any extension using Chrome's debugger. The bar is **browser-wide, every window of every profile**, so another agent's debugger-based tool call anywhere shows it in your take | Use `chrome_demo_cursor` (no debugger). No debugger-based calls (JavaScript, screenshot, `chrome_computer`) from **any** agent from T0 − 20 s until the end: tell other running agents first |
| `desktop_record`: `window_hidden` | Even after being brought to the front the window is 95 % covered or more, minimized, or on another desktop (Space) or in full screen | Have it unminimized, on the current desktop and uncovered (ask the user), then start again |
| `desktop_record`: `window_not_found` | No browser window has the marker in its title (title not set, or the page changed its title) | `chrome_demo_cursor action:"title"` again on that window's tab, then start again |
| `desktop_record`: `window_not_unique` | Two windows contain the marker (an earlier take's window is still open) | Close the old window, or use a new `<name>` |
| `desktop_record`: `recording_busy` | Another recording is running on this Mac (yours or another agent's) | `status` with the id it returns, or wait |
| `desktop_record`: Screen Recording is off (`[screen_off]` in `desktop_list`) | The Handlus app has no Screen Recording permission. It is the app's permission, not the terminal's | The app opens its setup screen; the user turns Screen Recording on there (and reopens Handlus if macOS asks), then start again |
| `desktop_record`: update the app to 1.5.0 | The Handlus app on that Mac is older | A connected app updates itself within a minute; or `setup.sh install` |
| `newWindow` brought the user's window forward | A tab with the same URL already existed | Unique `?rec=` query |
| Blue selected text in the first frame | Leftover selection | `play` clears it one second before T0 |
| "Recent downloads" bubble in the corner | A screenshot with `savePng` created a download | Do not save screenshots in the recording window; press Escape on the bubble |
| Clicks on a cross-origin iframe do nothing | The fake cursor clicks the iframe element, not its contents | Show the cursor moving there, and do the real action another way |
| Recording starts on the wrong page | A previous take's schedule navigated away | Check the URL and first screen before scheduling |

## Quick reference (macOS; Windows: windows.md)

```text
zsh $K/setup.sh [install]          # the Handlus app: installed · 1.5.0+ · connected · running (and install it)
desktop_list                       # this Mac [on]; [screen_off] = Screen Recording is off for Handlus
desktop_record action:"start"  marker:"__rec_<name>" seconds:<s> start_at:<T0> computer:"<Mac>"   # → id, file
desktop_record action:"status" id:"rec-…" wait_ms:45000                                          # until done or failed
desktop_record action:"stop"   id:"rec-…"                                                        # end early, keep the file
```
Report back: the video path, the step 8 check (the status numbers and the log, or the `evidence.py check` result), and anything the dry run left in the user's accounts.

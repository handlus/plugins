# Windows recording tests

Run on GitHub's Windows runners by `.github/workflows/windows-recording.yml` (windows-2022 and windows-2025, no GPU).
The runner has a desktop session; the tests set it to 1920x1080 first.

| File | What it does |
|---|---|
| `e2e.ps1` | The skill as an agent uses it: `setup.ps1` (NOT READY) -> `setup.ps1 install` -> READY, then a take: `screens`, `place`, the fake cursor (`cursor.js` through CDP), `record`, `evidence.py write`, `sheet.py`, `sign`, `check`. Checks that a window over half of Chrome is not in the video, that a fully covered take fails when Chrome stopped painting, and display scale 125 % / 150 % (slot size, video size). Exit 0 = all passed |
| `gitbash.sh` | The same take with the Git Bash commands from `windows.md` (Claude Code's shell on Windows), after `e2e.ps1` |
| `spike.ps1` | Measurements behind the design: occlusion without capture, half / full cover, still page, minimize, encoder speed. Run it with the workflow input `scripts: ["spike.ps1"]` |
| `drive.py` | CDP driver: page title, schedule the cursor scene, read the cursor log and the page's paint log |
| `page.html` | Test page: magenta background, a box that always moves, a form for the cursor scene |
| `cover.ps1` | A lime topmost window used to cover Chrome |
| `res.cs` | Changes the runner's resolution and display scale (tests only) |

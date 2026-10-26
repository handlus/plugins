# Handlus plugins

Skills for AI agents that use your own Chrome through [Handlus](https://handlus.com), packaged for **Claude Code** and **Codex**.

| Skill | What it does |
|---|---|
| `handlus-browser` | When a task needs a step on a website (getting an API key from a service's dashboard, changing a console setting) and no connected tool covers it, the agent does it in your signed-in Chrome instead of installing a CLI or handing it back to you. Payments, passwords, 2-step codes and deletions stay with you; keys go straight into the file you want, not into chat. |
| `recording-chrome-fake-cursor` | Records one Chrome window on macOS while the agent drives it, with a visible fake cursor that glides, clicks with an orange ripple and types letter by letter. Your real mouse never moves. |

## Install

**Claude Code**

```text
/plugin marketplace add handlus/plugins
/plugin install handlus@handlus
```

Then ask: *"Record a demo of handlus.com with the fake cursor."* The skill is `/handlus:recording-chrome-fake-cursor`.

**Codex**

```bash
codex plugin marketplace add handlus/plugins
codex plugin add handlus@handlus
```

To add only the skill, copy `plugins/handlus/skills/recording-chrome-fake-cursor` into `~/.codex/skills/`.

## Connect Handlus (once)

The skill drives Chrome through the Handlus MCP server. Install the Handlus extension from [handlus.com](https://handlus.com), then:

```bash
claude mcp add --transport http --scope user handlus https://api.handlus.com/mcp   # Claude Code
codex mcp add handlus --url https://api.handlus.com/mcp                             # Codex
```

The fake cursor (`chrome_demo_cursor`) needs Handlus extension **0.3.1 or later**. With older versions or other Chrome MCPs the skill falls back to injecting `scripts/cursor.js`.

## Set up recording (macOS, once)

Ask your agent: *"Set up recording."* The skill runs `scripts/setup.sh`, tells you what is missing and installs what it can (`ffmpeg` through Homebrew, the recorder). You do the parts only a person can do:

- **Xcode Command Line Tools** — click Install in the dialog that opens
- **Homebrew** (only if you do not have it) — paste the command it gives you; it asks for your Mac password
- **Screen Recording permission** for the app running the agent (Terminal, iTerm, VS Code, Cursor…) — System Settings → Privacy & Security → Screen & System Audio Recording opens; turn the app on, then quit and reopen it

Requirements in short: macOS 13+, Xcode Command Line Tools, `ffmpeg`, `python3`, Google Chrome, Screen Recording permission. Check any time with `zsh <skill folder>/scripts/setup.sh`.

---

## 한국어

[Handlus](https://handlus.com)(내 크롬을 AI 에이전트가 쓰게 하는 크롬 MCP)용 스킬을 클로드코드 · 코덱스 플러그인으로 묶었습니다.

- **웹 일 스킬** `handlus-browser` — 대시보드에서 API 키 발급, 콘솔 설정 바꾸기처럼 웹에서 하는 일을, 맡을 도구가 연결돼 있지 않으면 CLI 를 깔거나 나에게 넘기지 않고 내 크롬에서 합니다. 결제 · 비밀번호 · 2단계 코드 · 삭제는 사용자 몫이고, 키는 대화에 적지 않고 원하는 파일에 바로 넣습니다.
- **녹화 스킬** `recording-chrome-fake-cursor` — 에이전트가 크롬을 조작하는 모습을 그 창만 녹화합니다. 가짜 커서가 움직이고, 누를 때 주황 원이 퍼지고, 글자가 한 자씩 쳐집니다. 진짜 마우스는 움직이지 않습니다(맥 전용).
- **클로드코드**: `/plugin marketplace add handlus/plugins` → `/plugin install handlus@handlus`
- **코덱스**: `codex plugin marketplace add handlus/plugins` → `codex plugin add handlus@handlus`. 스킬만 쓰려면 스킬 폴더를 `~/.codex/skills/` 에 복사
- Handlus 연결은 위 명령 한 줄. 가짜 커서 도구는 Handlus 확장 0.3.1 이상에서 됩니다.
- **녹화 준비(맥, 한 번)**: 에이전트에게 「녹화 준비해 줘」 라고 하면 스킬이 `scripts/setup.sh` 로 빠진 것을 찾아 알려 주고, 깔 수 있는 것(Homebrew 로 ffmpeg, 녹화기)은 설치합니다. 사람이 해야 하는 것만 남깁니다: 명령줄 도구 설치 창의 「설치」, Homebrew 가 없을 때 그 설치 명령(맥 비밀번호를 묻습니다), 에이전트를 돌리는 앱(터미널 · iTerm · VS Code · Cursor 등)의 「화면 기록」 권한 켜고 그 앱 다시 열기.

Copyright (c) 2026 Handlus. See [LICENSE](LICENSE).

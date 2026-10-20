# Handlus plugins

Skills for AI agents that use your own Chrome through [Handlus](https://handlus.com), packaged for **Claude Code** and **Codex**.

| Skill | What it does |
|---|---|
| `recording-chrome-fake-cursor` | Records one Chrome window on macOS while the agent drives it, with a visible fake cursor that glides, clicks with an orange ripple and types letter by letter. Your real mouse never moves. |

## Install

**Claude Code**

```text
/plugin marketplace add bambwc20/handlus-plugins
/plugin install handlus@handlus
```

Then ask: *"Record a demo of handlus.com with the fake cursor."* The skill is `/handlus:recording-chrome-fake-cursor`.

**Codex**

```bash
codex plugin marketplace add bambwc20/handlus-plugins
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

## Requirements (recording)

- macOS 13+, Xcode Command Line Tools (`xcode-select --install`), `ffmpeg` (`brew install ffmpeg`), `python3`
- Screen Recording permission for your terminal app (System Settings → Privacy & Security → Screen & System Audio Recording)

---

## 한국어

[Handlus](https://handlus.com)(내 크롬을 AI 에이전트가 쓰게 하는 크롬 MCP)용 스킬을 클로드코드 · 코덱스 플러그인으로 묶었습니다.

- **녹화 스킬** `recording-chrome-fake-cursor` — 에이전트가 크롬을 조작하는 모습을 그 창만 녹화합니다. 가짜 커서가 움직이고, 누를 때 주황 원이 퍼지고, 글자가 한 자씩 쳐집니다. 진짜 마우스는 움직이지 않습니다(맥 전용).
- **클로드코드**: `/plugin marketplace add bambwc20/handlus-plugins` → `/plugin install handlus@handlus`
- **코덱스**: `codex plugin marketplace add bambwc20/handlus-plugins` → `codex plugin add handlus@handlus`. 스킬만 쓰려면 스킬 폴더를 `~/.codex/skills/` 에 복사
- Handlus 연결은 위 명령 한 줄. 가짜 커서 도구는 Handlus 확장 0.3.1 이상에서 됩니다.

Copyright (c) 2026 Handlus. See [LICENSE](LICENSE).

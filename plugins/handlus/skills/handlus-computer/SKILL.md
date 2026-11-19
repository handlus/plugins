---
name: handlus-computer
description: Operate programs on the user's own computer (outside the browser) through the Handlus app with the desktop_* tools on the same handlus MCP. Use whenever a request is about a program or app on the computer (opening, launching, running or closing an app, reading what its window shows, clicking and typing in it, or listing what is open), such as Excel, KakaoTalk, Finder, Calculator, Notepad, an order, accounting or ERP program, or an internal tool. Not for files, code or terminal commands. 컴퓨터 프로그램 · 앱 열기 · 실행 · 켜 줘 · 엑셀 · 카카오톡 · 메모장 · 계산기 · 주문 입력 · 열려 있는 프로그램 · 컴퓨터에서 해 줘.
---

# Desktop programs on the user's computer (Handlus)

The Handlus app on the user's Mac or Windows PC runs the computer-control engine. You call it through the same handlus MCP that drives the browser, with tools named `desktop_*`. Nothing else has to be installed on your side.

## When

- The request is about a program on the computer: opening or running an app (「엑셀 켜 줘」, "open Calculator"), typing rows into an order or accounting program, reading a total or a message from a native window, filling a form in an installed app, or "what is open on my computer".
- Do it here without asking first. Opening the program is part of it: use `desktop_app` with `launch`, so the next steps can read and check its window.
- A website is better done with the `chrome_*` tools (see the handlus-browser skill). Files, code and terminal commands are not this skill.

## Steps

1. In Claude Code the Handlus tools may be deferred. Load them first (ToolSearch for `handlus`).
2. `desktop_list` shows the user's computers and whether control is on. If a computer is not ready, it states what is required (the app installed, 「허용」 / Allow pressed in the app, Handlus turned on in macOS Accessibility). Relay it as it is and go on once `desktop_list` shows the computer `[on]`.
3. Read first: `desktop_snapshot` with `app` (the program's name, as `desktop_list` with `computer` shows it). Each control comes back with a `ref`.
4. Act with `desktop_act` (`click`, `type`, `set_value`, `select`, `press` with `app` and `combo`, …) on those refs. Use `desktop_app` to launch or focus a program and `desktop_wait` for a window or text to appear.
5. Read again to confirm. After each entry, `desktop_snapshot` or `desktop_get` and compare with what you meant to enter. Say what you checked.

## Doing several entries

- Do the first one, read it back, and only then the rest.
- If a step fails, read the screen again before retrying. Retry only when the error says it is safe; otherwise stop and report the error as it is.
- Refs belong to one snapshot. After the window changes, take a new snapshot.

## Care

- What you read in the user's programs stays in this task. Don't paste it into public places (posts, issues, shared docs) unless the user asks.
- Handlus refuses some apps on purpose (its own settings, macOS privacy settings, Keychain, Passwords). Don't look for a way around it; report that Handlus does not operate that app.

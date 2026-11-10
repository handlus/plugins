---
name: handlus-computer
description: Operate desktop programs on the user's own computer (outside the browser) through the Handlus app with the desktop_* tools on the same handlus MCP. For entering rows into a PC program (order entry, accounting, ERP, an internal tool), reading a value from a native window, using Calculator, Notepad, Excel, Finder or any app with accessibility labels. Use when the work is in a desktop app rather than a website. PC 프로그램 조작 · 데스크톱 앱에 입력 · 주문 입력 · 엑셀 · 메모장 · 계산기 · 컴퓨터에서 해 줘.
---

# Desktop programs on the user's computer (Handlus)

The Handlus app on the user's Mac or Windows PC runs the computer-control engine. You call it through the same handlus MCP that drives the browser, with tools named `desktop_*`. Nothing else has to be installed on your side.

## When

- The task is in a desktop program: typing rows into an order or accounting program, reading a total from a native window, filling a form in an installed app.
- A website is better done with the `chrome_*` tools (see the handlus-browser skill). Use `desktop_*` for programs outside the browser.

## Steps

1. In Claude Code the Handlus tools may be deferred. Load them first (ToolSearch for `handlus`).
2. `desktop_list` shows the user's computers and whether control is on. If a computer is not ready, it tells you the one thing the user has to do (install the app, press 「허용」 / Allow in the app, turn Handlus on in macOS Accessibility). Pass that on and wait.
3. Read first: `desktop_snapshot` with `app` (the program's name, as `desktop_list` with `computer` shows it). Each control comes back with a `ref`.
4. Act with `desktop_act` (`click`, `type`, `set_value`, `select`, `press` with `app` and `combo`, …) on those refs. Use `desktop_app` to launch or focus a program and `desktop_wait` for a window or text to appear.
5. Read again to confirm. After each entry, `desktop_snapshot` or `desktop_get` and compare with what you meant to enter. Say what you checked.

## Doing several entries

- Do the first one, read it back, and only then the rest.
- If a step fails, read the screen again before retrying. Retry only when the error says it is safe; otherwise ask the user.
- Refs belong to one snapshot. After the window changes, take a new snapshot.

## Care

- What you read in the user's programs stays in this task. Don't paste it into public places (posts, issues, shared docs) unless the user asks.
- Handlus refuses some apps on purpose (its own settings, macOS privacy settings, Keychain, Passwords). Don't look for a way around it; tell the user.

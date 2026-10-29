---
name: handlus-browser
description: Do a step on a website in the user's own signed-in Chrome through Handlus when no connected tool covers it, instead of installing a CLI or handing the step back to the user. For getting or rotating an API key or token in a service's dashboard (Supabase, Vercel, Stripe, Google Cloud, Resend, OpenAI…), adding an environment variable, OAuth redirect URI or webhook in a web console, or checking a DNS record or a setting on an admin page. Use when a task needs a value or a change that lives behind a login on a website. API 키 발급 · 대시보드 설정 · 콘솔에서 바꾸기 · 관리자 페이지 확인 · 내 크롬에서 해 줘.
---

# Web steps in the user's own Chrome (Handlus)

The user's Chrome is already signed in to their services. Through Handlus you open the dashboard there, read the value and make the change, so nothing has to be installed and no new login is needed.

## When

- The task needs something that lives on a website behind the user's login: an API key, a token, a webhook secret, a project URL, a setting in a console.
- **Check the tools you already have first.** If a connected MCP server, or a CLI that is already installed and signed in, covers the step for that service (for example an MCP tool that returns the project's keys), use it. This skill is for when nothing connected covers it.
- Not for work that has nothing to do with a website (refactoring, tests, commits).

## Steps

1. In Claude Code the Handlus tools may be deferred. Load them first (ToolSearch for `handlus`).
2. With several Chromes: `chrome_list_browsers` (pass `hint` with the site and account), then `chrome_select_browser` for the one signed in to the account the task needs.
3. `chrome_navigate` to the page that holds the value. If you don't know the project yet, open the service's project list first and match it to the repo (project name, the URL in `.env.example`).
4. `chrome_get_web_content` or `chrome_read_page` to find the value or the control; `chrome_click_element` and `chrome_fill_or_select` to change a setting.
5. Write the value into the file the user wants (`.env.local` and the like) with your file tools. Say which variable you set, where, and which page it came from. Keep secrets out of commits and logs, and check that `.gitignore` covers that file.
6. Report in a sentence or two. If you created a key, say where it is managed so the user can revoke it.

## The right Chrome

- A sign-in page, or a different account than the task needs: don't sign in or guess. Ask the user which Chrome is signed in to it. If that Chrome is not connected, call `chrome_add_browser` and pass on its install steps.

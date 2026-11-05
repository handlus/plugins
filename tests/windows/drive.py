"""drive.py — stands in for the agent's MCP calls in the Windows CI take (tests/windows/e2e.ps1).

Talks to the test Chrome over its DevTools port (127.0.0.1:9222). Chrome's --remote-debugging-port does not show the
"started debugging this browser" bar (only extensions using chrome.debugger do), so the take stays clean.

  drive.py title <text>                      document.title = text   (the __rec_ marker)
  drive.py play <T0 ms> <basic|cover>        inject scripts/cursor.js and schedule a scene at T0 (like 5-B in SKILL.md)
  drive.py fclog <out.json>                  write window.__fcLog
  drive.py stats                             page.html visibility / paint log
"""
import json, os, sys, time, urllib.request

import websocket  # pip install websocket-client

HERE = os.path.dirname(os.path.abspath(__file__))
CURSOR = os.path.join(HERE, "..", "..", "plugins", "handlus", "skills", "recording-chrome-fake-cursor", "scripts", "cursor.js")

SCENES = {
    # ~5 s: click the input, type, click Go, then a short pause
    "basic": """async (F, log) => {
        await F.sleep(400);
        await F.clickEl('#q'); log('click-q');
        await F.typeInto('#q', 'hello from windows', 60); log('typed');
        await F.clickEl('#go'); log('click-go');
        await F.sleep(600);
    }""",
    # ~7 s with timer-only steps in the middle, so a log line lands while the window is covered (T0+2.5 s .. T0+4.5 s)
    "cover": """async (F, log) => {
        await F.clickEl('#q'); log('click-q');
        for (let i = 0; i < 10; i++) { await F.sleep(500); log('tick-' + i); }
        await F.typeInto('#q', 'after cover', 60); log('typed');
    }""",
}


def target():
    for t in json.load(urllib.request.urlopen("http://127.0.0.1:9222/json/list")):
        if t.get("type") == "page" and "page.html" in t.get("url", ""):
            return t
    raise SystemExit("no page.html tab")


def evaluate(expr, await_promise=False):
    ws = websocket.create_connection(target()["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
    ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                        "params": {"expression": expr, "returnByValue": True, "awaitPromise": await_promise}}))
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == 1:
            ws.close()
            r = m.get("result", {})
            if "exceptionDetails" in r:
                raise SystemExit("JS error: " + json.dumps(r["exceptionDetails"])[:500])
            return r.get("result", {}).get("value")


def main():
    cmd = sys.argv[1]
    if cmd == "title":
        print(evaluate(f"document.title = {json.dumps(sys.argv[2])}"))
    elif cmd == "play":
        t0, scene = int(sys.argv[2]), sys.argv[3]
        code = open(CURSOR, encoding="utf-8").read()
        print(json.dumps(evaluate("(async () => {\n" + code + "\n})()", await_promise=True)))
        print(evaluate(f"window.__fc.runAt({t0}, {{ start: [innerWidth * 0.6, innerHeight * 0.7], "
                       f"prep: () => window.scrollTo(0, 0), script: {SCENES[scene]} }})"))
        print(f"scheduled {scene} at {t0} (in {t0 - int(time.time() * 1000)} ms)")
    elif cmd == "fclog":
        log = evaluate("JSON.stringify(window.__fcLog || [])")
        open(sys.argv[2], "w", encoding="utf-8").write(log)
        print(log)
    elif cmd == "stats":
        print(evaluate("JSON.stringify(window.__stats())"))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()

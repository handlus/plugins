#!/usr/bin/env python3
"""evidence.py — 창 녹화본의 증거 파일 `{stem}.rec.json` (recording-chrome-fake-cursor).

  evidence.py write REC.mp4 --monitor "<display name>" --scale 1 --profile <chrome profile> --url <opened url> \
                            --fclog fclog.json [--action "타자 → 전송 → 답변 대기"]
      ffprobe(해상도·fps·길이) + `window.__fcLog`(cursor.js runAt 기록) → ok 판정
      ok = fcLog 에 start·end 가 있고 · error 없고 · hidden 이 **전부** false · fps ≥ 40
  evidence.py sign REC.mp4 --sheet preview.jpg --note "뺀 것: 사이드바·주소창 …"
      sheet.py --preview 시트를 Read 로 본 **뒤에** 서명한다. 시트 파일이 실제로 있어야 한다
  evidence.py check REC.mp4            → exit 0 통과 / 2 위반

왜 hidden 인가: 창이 **완전히** 가려지면 크롬이 그리기를 멈춘다(document.hidden=true) — 카운트다운이 멈춘 화면이 찍힌다.
  녹화본을 끝까지 다 보지 않고도 그걸 아는 유일한 기록이 fcLog 다.
왜 해시인가: 증거를 다른 녹화본 옆에 복사해 두면 통과한다. 증거는 **그 파일**의 것이어야 한다.
"""
import argparse, datetime, hashlib, json, os, shutil, subprocess, sys
from pathlib import Path

FPS_MIN = 40          # 실측: 배율 2 모니터 약 45fps · 배율 1 모니터 약 56fps
FFPROBE = shutil.which("ffprobe") or next((p for p in ("/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe") if os.path.exists(p)), "ffprobe")


def side(p: Path) -> Path:
    return p.with_suffix(".rec.json")


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def probe(p: Path) -> dict:
    out = subprocess.run([FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height,avg_frame_rate:format=duration", "-of", "json", str(p)],
                         capture_output=True, text=True, check=True).stdout
    j = json.loads(out); s = j["streams"][0]
    n, d = (s.get("avg_frame_rate") or "0/1").split("/")
    return {"width": s["width"], "height": s["height"],
            "fps": round(float(n) / float(d), 2) if float(d) else 0.0,
            "duration": round(float(j["format"]["duration"]), 3)}


def judge(fclog, fps) -> list[str]:
    why = []
    labels = [str(e[1]) for e in fclog] if isinstance(fclog, list) else []
    if not fclog:
        why.append("fcLog 가 비었다 — runAt 예약 없이 찍었거나 로그를 안 붙였다")
    else:
        # 마지막 클릭이 다른 페이지로 넘어가면 페이지 안의 로그가 같이 사라져 end 가 안 남는다.
        # 그 클릭 직전에 log('nav: …') 를 남기면 끝난 것으로 본다 (2026-10-13)
        ended = "end" in labels or any(l.startswith("nav:") for l in labels)
        if "start" not in labels or not ended:
            why.append("fcLog 에 start·end(또는 nav:) 가 없다 — 동작이 끝까지 돌았는지 모른다")
        errs = [l for l in labels if l.startswith("error") or "prep error" in l]
        if errs:
            why.append(f"fcLog 에 오류가 있다 — {errs[0]}")
        hid = [e for e in fclog if len(e) > 2 and e[2] is True]
        if hid:
            why.append(f"document.hidden=true 가 {len(hid)}번 — 창이 가려져 크롬이 그리기를 멈췄다(멈춘 화면이 찍힌다). 다시 찍는다")
    if fps < FPS_MIN:
        why.append(f"fps {fps} < {FPS_MIN} — 녹화가 버벅였다")
    return why


def write(a):
    p = Path(a.rec).resolve()
    fclog = json.loads(Path(a.fclog).read_text()) if os.path.exists(a.fclog) else json.loads(a.fclog)
    if isinstance(fclog, dict) and "log" in fclog:
        fclog = fclog["log"]
    pr = probe(p)
    why = judge(fclog, pr["fps"])
    ev = {"ok": not why, "why": why, "file": p.name, "sha256": sha256(p), **pr,
          "monitor": a.monitor, "scale": a.scale, "profile": a.profile, "url": a.url, "action": a.action,
          "fcLog": fclog, "written": datetime.datetime.now().isoformat(timespec="seconds"),
          "eyecheck": {"signed": False}}
    old = side(p)
    if old.exists():   # 서명은 같은 파일일 때만 이어 간다
        try:
            o = json.loads(old.read_text())
            if o.get("sha256") == ev["sha256"] and o.get("eyecheck", {}).get("signed"):
                ev["eyecheck"] = o["eyecheck"]
        except Exception:
            pass
    side(p).write_text(json.dumps(ev, ensure_ascii=False, indent=1) + "\n")
    print(f"{'✅' if ev['ok'] else '🚨'} {side(p).name} · {pr['width']}x{pr['height']} · {pr['fps']}fps · {pr['duration']}s"
          + ("" if ev["ok"] else "\n   " + "\n   ".join(why)))
    return 0 if ev["ok"] else 2


def sign(a):
    p = Path(a.rec).resolve()
    s = side(p)
    if not s.exists():
        print(f"🚨 {s.name} 없음 — evidence.py write 먼저"); return 2
    ev = json.loads(s.read_text())
    if ev.get("sha256") != sha256(p):
        print(f"🚨 {s.name} 가 이 녹화본의 증거가 아니다(해시 불일치) — write 를 다시"); return 2
    if not a.sheet or not os.path.isfile(a.sheet):
        print("🚨 --sheet 시트 파일이 없다 — sheet.py --preview 로 만들고 Read 로 본 뒤 서명한다"); return 2
    if not (a.note or "").strip():
        print("🚨 --note 가 비었다 — 무엇을 crop 으로 뺐는지(사이드바·주소창·핸들 …) 적는다"); return 2
    ev["eyecheck"] = {"signed": True, "sheet": os.path.abspath(a.sheet), "note": a.note.strip(),
                      "by": a.by, "at": datetime.datetime.now().isoformat(timespec="seconds")}
    s.write_text(json.dumps(ev, ensure_ascii=False, indent=1) + "\n")
    print(f"✅ {s.name} 눈 검사 서명 — {a.note.strip()[:60]}")
    return 0


def verify(path) -> list[str]:
    """check 가 쓴다(다른 스크립트가 import 해도 된다). 위반 사유 목록(빈 목록 = 통과)."""
    p = Path(path)
    s = side(p)
    if not s.exists():
        return [f"{p.name} 의 녹화 증거 {s.name} 가 없다 — evidence.py write (fcLog 붙여서) → sheet.py --preview 로 보고 → evidence.py sign"]
    try:
        ev = json.loads(s.read_text())
    except Exception as e:
        return [f"{s.name} 을 못 읽는다 — {e}"]
    out = []
    if ev.get("sha256") != sha256(p):
        out.append(f"{s.name} 가 이 녹화본의 증거가 아니다(해시 불일치) — 녹화를 바꿨으면 write 를 다시")
    if ev.get("ok") is not True:
        out.append(f"{p.name} 녹화 증거가 불합격 — " + "; ".join(ev.get("why") or ["ok 아님"]))
    if not (ev.get("eyecheck") or {}).get("signed"):
        out.append(f"{p.name} 는 crop 눈 검사 서명이 없다 — sheet.py --preview 시트를 보고 evidence.py sign")
    return out


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    w = sp.add_parser("write"); w.add_argument("rec")
    w.add_argument("--monitor", required=True); w.add_argument("--scale", type=float, required=True)
    w.add_argument("--profile", required=True); w.add_argument("--url", required=True)
    w.add_argument("--fclog", required=True, help="__fcLog JSON 파일 경로 또는 JSON 문자열")
    w.add_argument("--action", default="")
    s = sp.add_parser("sign"); s.add_argument("rec"); s.add_argument("--sheet", required=True)
    s.add_argument("--note", required=True); s.add_argument("--by", default="agent")
    c = sp.add_parser("check"); c.add_argument("rec")
    a = ap.parse_args()
    if a.cmd == "write":
        sys.exit(write(a))
    if a.cmd == "sign":
        sys.exit(sign(a))
    why = verify(a.rec)
    print("✅ 통과" if not why else "🚨 " + "\n🚨 ".join(why))
    sys.exit(0 if not why else 2)


if __name__ == "__main__":
    main()

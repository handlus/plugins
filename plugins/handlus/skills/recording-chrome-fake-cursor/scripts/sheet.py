#!/usr/bin/env python3
"""sheet.py — 녹화본에서 구간·crop 을 고르는 눈 도구 (recording-chrome-fake-cursor).

  sheet.py REC.mp4 --from 2.6 --to 6.2 --step 0.2 [--crop x,y,w,h] [--cols 6] [--width 390] --out sheet.jpg
      시각 라벨이 붙은 프레임 시트. 구간 양 끝은 0.1~0.25s 간격으로 본다(줌 전환·스피너·빨간 안내가 0.5s 안에 지나간다)
  sheet.py REC.mp4 --still 17 [--crop x,y,w,h] --out still.png
      원본 해상도 한 장 (crop 좌표를 재는 용도 — 메인 모니터 녹화는 3840×2400 이고 화면 좌표의 ×2)
  sheet.py REC.mp4 --preview --segments '2.85-4.5,10.45-11.1' --crop x,y,w,h [--crop2 x,y,w,h] [--preview-width 880] --out preview.jpg
      쓸 구간을 **실제로 쓰일 폭(기본 880)으로** 줄여 구간마다 처음·가운데·끝 3장 — 이 시트를 Read 로 보고
      `evidence.py sign --sheet preview.jpg` 로 서명한다 (글자가 읽히는지 · 핸들·주소창·사이드바가 빠졌는지)

왜: 0.25s 시트로는 0.1s 짜리 빨간 형식 안내를 놓쳤고, 줄인 미리보기 첫 칸이 잡았다.
    숫자로만 crop 을 고르면 제목이 반쯤 잘린 채 나간다 — 그래서 쓰일 폭 미리보기가 따로 있다.
"""
import argparse, os, shutil, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFont

FF = shutil.which("ffmpeg") or next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.path.exists(p)), "ffmpeg")


def font(sz):
    for f in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def grab(src, t, crop=None, width=None):
    vf = []
    if crop:
        x, y, w, h = crop
        vf.append(f"crop={w}:{h}:{x}:{y}")
    if width:
        vf.append(f"scale={width}:-2:flags=lanczos")
    fd, p = tempfile.mkstemp(suffix=".png"); os.close(fd)
    cmd = [FF, "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", src, "-frames:v", "1"] + (["-vf", ",".join(vf)] if vf else []) + [p]
    subprocess.run(cmd, check=True)
    im = Image.open(p).convert("RGB"); os.remove(p)
    return im


def label(im, txt):
    d = ImageDraw.Draw(im); f = font(max(16, im.width // 18))
    w = int(d.textlength(txt, font=f)) + 12
    d.rectangle([0, 0, w, f.size + 10], fill="black"); d.text((6, 4), txt, fill="yellow", font=f)
    return im


def tile(ims, cols, out):
    w = max(i.width for i in ims); h = max(i.height for i in ims)
    rows = (len(ims) + cols - 1) // cols
    sh = Image.new("RGB", (cols * w, rows * h), "white")
    for k, im in enumerate(ims):
        sh.paste(im, ((k % cols) * w, (k // cols) * h))
    sh.save(out, quality=88)
    print(f"{out}  ({len(ims)}장 · {sh.width}x{sh.height})")


def parse_crop(s):
    return [int(v) for v in s.split(",")] if s else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--out", required=True)
    ap.add_argument("--from", dest="t0", type=float)
    ap.add_argument("--to", dest="t1", type=float)
    ap.add_argument("--step", type=float, default=0.5)
    ap.add_argument("--crop")
    ap.add_argument("--crop2", help="--preview 에서 둘째 구간부터 쓰는 crop (화면이 바뀌는 녹화)")
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--width", type=int, default=390)
    ap.add_argument("--still", type=float)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--segments", help="'a-b,c-d' — 쓸 구간 순서대로")
    ap.add_argument("--preview-width", type=int, default=880, help="미리보기 폭 = 결과물에서 이 영상이 차지할 폭")
    a = ap.parse_args()
    crop = parse_crop(a.crop)
    if a.still is not None:
        im = grab(a.src, a.still, crop)
        im.save(a.out); print(f"{a.out}  ({im.width}x{im.height} @ {a.still}s)"); return
    if a.preview:
        if not (a.segments and crop):
            raise SystemExit("--preview 는 --segments 와 --crop 이 필요하다")
        segs = [tuple(float(x) for x in s.split("-")) for s in a.segments.split(",")]
        c2 = parse_crop(a.crop2) or crop
        ims = []
        for k, (s, e) in enumerate(segs):
            cr = crop if k == 0 else c2
            for t in (s + 0.05, (s + e) / 2, e - 0.05):
                ims.append(label(grab(a.src, t, cr, a.preview_width), f"seg{k + 1} {t:.2f}s"))
        tile(ims, 3, a.out); return
    if a.t0 is None or a.t1 is None:
        raise SystemExit("--from/--to 또는 --still 또는 --preview")
    ims, t = [], a.t0
    while t <= a.t1 + 1e-6:
        ims.append(label(grab(a.src, t, crop, a.width), f"{t:.2f}"))
        t += a.step
    tile(ims, a.cols, a.out)


if __name__ == "__main__":
    main()

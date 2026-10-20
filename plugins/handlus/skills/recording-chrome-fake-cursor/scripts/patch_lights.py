#!/usr/bin/env python3
"""창 녹화의 신호등 자리 녹화 표시를 덮는 패치 PNG 를 만든다.

사용: patch_lights.py <원본.mp4> <배율 1|2> <패치.png>
  → 출력 마지막 줄 = ffmpeg overlay 좌표 (예: 7:7)
제목줄 색은 크롬 프로필 테마마다 달라서 영상 첫 프레임에서 뽑는다.
"""
import os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw

src, scale, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
FF = shutil.which("ffmpeg") or next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.path.exists(p)), "ffmpeg")

with tempfile.TemporaryDirectory() as td:
    fr = os.path.join(td, 'f.png')
    subprocess.run([FF, '-hide_banner', '-loglevel', 'error', '-y', '-ss', '0.5', '-i', src,
                    '-frames:v', '1', fr], check=True)
    im = Image.open(fr).convert('RGB')
    # 녹화 표시(알약)와 탭 펼침 버튼 사이 틈 = 제목줄 맨바닥 색 (1배 좌표 85,20)
    bg = im.getpixel((85 * scale, 20 * scale))

S = 4                                   # 4배로 그려 줄여서 원 가장자리를 부드럽게
ox, oy, W, H = 7, 7, 72, 27             # 덮는 영역 (1배 좌표)
lights = [(20, (0xFF, 0x5F, 0x57), (0xE0, 0x44, 0x3E)),
          (43, (0xFE, 0xBC, 0x2E), (0xDE, 0xA1, 0x23)),
          (66, (0x28, 0xC8, 0x40), (0x1D, 0xAD, 0x2B))]
k = scale * S
pat = Image.new('RGBA', (W * k, H * k), bg + (255,))
d = ImageDraw.Draw(pat)
for cx, fill, edge in lights:
    x, y, r = (cx - ox) * k, (20.5 - oy) * k, 6.5 * k
    d.ellipse([x - r, y - r, x + r, y + r], fill=edge)
    r2 = r - 0.5 * k
    d.ellipse([x - r2, y - r2, x + r2, y + r2], fill=fill)
pat.resize((W * scale, H * scale), Image.LANCZOS).save(out)
print(f'bg=#{bg[0]:02x}{bg[1]:02x}{bg[2]:02x}')
print(f'{ox * scale}:{oy * scale}')

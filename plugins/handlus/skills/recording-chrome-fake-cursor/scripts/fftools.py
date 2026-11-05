"""fftools.py — shared helpers for evidence.py · sheet.py · patch_lights.py (macOS and Windows).

- find("ffmpeg") / find("ffprobe"): HANDLUS_FFMPEG (the exe or its folder) → PATH → Homebrew (macOS)
  → the copy setup.ps1 install puts in scripts\\bin\\ffmpeg (Windows) → winget (WinGet\\Links, then
  WinGet\\Packages\\…\\bin). Same order as rec.ps1. winget changes PATH only for new shells,
  so a just-installed ffmpeg is found here before the agent restarts.
- utf8_stdio(): Windows pipes default to the ANSI code page (cp949, cp1252 …) and printing ✅ would crash.
- read_text(path): UTF-8 with or without BOM, or UTF-16 (Windows PowerShell 5.1 `>` and Out-File write UTF-16).
"""
import glob, os, shutil, sys

EXE = ".exe" if os.name == "nt" else ""


def _candidates(name):
    env = os.environ.get("HANDLUS_FFMPEG", "").strip().strip('"')
    if env:
        yield os.path.join(env, name + EXE) if os.path.isdir(env) else os.path.join(os.path.dirname(env), name + EXE)
    w = shutil.which(name)
    if w:
        yield w
    for d in ("/opt/homebrew/bin", "/usr/local/bin"):
        yield os.path.join(d, name)
    yield os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "ffmpeg", "bin", name + EXE)
    la = os.environ.get("LOCALAPPDATA")
    if la:
        yield os.path.join(la, "Microsoft", "WinGet", "Links", name + EXE)
        hits = sorted(glob.glob(os.path.join(la, "Microsoft", "WinGet", "Packages", "*", "**", "bin", name + EXE), recursive=True))
        yield from reversed(hits)   # newest version folder last in sort order


def find(name):
    for p in _candidates(name):
        if p and os.path.isfile(p):
            return p
    return name


def utf8_stdio():
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def read_text(path):
    b = open(path, "rb").read()
    if b[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return b.decode("utf-16")
    return b.decode("utf-8-sig")


def font_paths():
    return ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc",
            os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", "arial.ttf"),
            os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", "segoeui.ttf"),
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")

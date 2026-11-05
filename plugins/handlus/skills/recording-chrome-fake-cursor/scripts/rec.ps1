# rec.ps1 - the Windows side of a Chrome window recording (recording-chrome-fake-cursor skill). Same commands as rec.sh.
#
#   rec.ps1 screens                        pick the recording slot -> prints X= Y= W= H= SCALE= LW= LH= MONITOR=
#   rec.ps1 list                           Chrome windows (hwnd, visible frame, title)
#   rec.ps1 place <title-marker>           move the Chrome window whose title starts with the marker to the slot and raise it
#   rec.ps1 record <T0ms> <sec> <out.mp4>  wait until T0-1.5s, then record that window only (prints rec_started)
#   rec.ps1 probe                          record one open Chrome window for 1 s (setup.ps1 uses it)
#   rec.ps1 ffmpeg                         print the ffmpeg this script uses to encode, and its H.264 encoder
#
# Recording itself is Windows.Graphics.Capture (win32.cs, HandlusWgc): only the window's own pixels, no real mouse
# pointer, and it also works without a GPU driver. ffmpeg (any recent version) only encodes the frames to H.264.
#
# Run it as:  powershell -NoProfile -ExecutionPolicy Bypass -File <skill folder>\scripts\rec.ps1 <command> ...
# Browser steps (open window, title marker, cursor) are done by the agent through MCP - see ../SKILL.md and ../windows.md
#
# REC_MONITOR   unset = primary display, or a display name prefix from `rec.ps1 screens` (DISPLAY2 ...)
# REC_W, REC_H  window size in logical pixels (default 1920x1200; without them the first of
#               1920x1200, 1600x1000, 1440x900, 1280x800, 1024x640 that fits the display's work area is used).
#               The window and the video are that size times the display scale (125% -> x1.25).
# HANDLUS_FFMPEG  ffmpeg.exe (or its folder) to use instead of the one found on PATH / winget / bin\ffmpeg
# HANDLUS_X264    x264 preset (default veryfast; ultrafast when the machine cannot keep up)
param(
  [Parameter(Position = 0)][string]$Cmd = '',
  [Parameter(Position = 1)][string]$A1 = '',
  [Parameter(Position = 2)][string]$A2 = '',
  [Parameter(Position = 3)][string]$A3 = ''
)
$ErrorActionPreference = 'Continue'   # 'Stop' turns any native stderr line into a terminating error in PowerShell 5.1
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$HERE = $PSScriptRoot
if (-not ('HandlusWgc' -as [type])) { Add-Type -Path (Join-Path $HERE 'win32.cs') }

function Err([string]$m) { [Console]::Error.WriteLine($m) }

# ---------- ffmpeg ----------
# Every ffmpeg.exe we can see, in order of preference
function Find-Ffmpegs {
  $c = @()
  if ($env:HANDLUS_FFMPEG) {
    $e = $env:HANDLUS_FFMPEG.Trim('"')
    if (Test-Path $e -PathType Container) { $c += (Join-Path $e 'ffmpeg.exe') } else { $c += $e }
  }
  $g = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g) { $c += $g.Source }
  $c += (Join-Path $HERE 'bin\ffmpeg\bin\ffmpeg.exe')
  if ($env:LOCALAPPDATA) {
    $c += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe')
    $pk = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $pk) {
      Get-ChildItem $pk -Directory -Filter '*FFmpeg*' -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.FullName -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object { $c += $_.FullName }
      }
    }
  }
  $seen = @{}
  foreach ($p in $c) { if ($p -and -not $seen.ContainsKey($p) -and (Test-Path $p -PathType Leaf)) { $seen[$p] = 1; $p } }
}

# The first ffmpeg that has an H.264 encoder, else the first one found (to report why it cannot), else $null
function Best-Ffmpeg {
  $first = $null
  foreach ($ff in @(Find-Ffmpegs)) {
    $i = Ffmpeg-Info $ff
    if ($i.enc) { return $i }
    if (-not $first) { $first = $i }
  }
  return $first
}

# Version and the H.264 encoder to use (libx264, else Media Foundation's h264_mf)
function Ffmpeg-Info([string]$ff) {
  $info = @{ exe = $ff; enc = $null; version = '' }
  $info.version = (& $ff -hide_banner -version 2>&1 | Select-Object -First 1) -replace '^ffmpeg version (\S+).*', '$1'
  $enc = (& $ff -hide_banner -encoders 2>&1 | Out-String)
  if ($enc -match '\blibx264\b') { $info.enc = 'libx264' } elseif ($enc -match '\bh264_mf\b') { $info.enc = 'h264_mf' }
  return $info
}

function Need-Ffmpeg {
  $i = Best-Ffmpeg
  if (-not $i) { Err 'STOP: ffmpeg not found - run setup.ps1 install'; exit 5 }
  if (-not $i.enc) { Err "STOP: $($i.exe) ($($i.version)) has no H.264 encoder (libx264 or h264_mf) - run setup.ps1 install"; exit 5 }
  return $i
}

# Encoder arguments after the raw frames ffmpeg reads from the recorder
function Encode-Args($i) {
  $preset = if ($env:HANDLUS_X264) { $env:HANDLUS_X264 } else { 'veryfast' }
  if ($i.enc -eq 'libx264') { return "-c:v libx264 -preset $preset -crf 18 -pix_fmt yuv420p -movflags +faststart" }
  return '-c:v h264_mf -b:v 16M -pix_fmt nv12 -movflags +faststart'
}

# ---------- displays and windows ----------
function Monitor-Line($m) {
  "{0}  at:{1},{2}  {3}x{4}  work:{5},{6},{7}x{8}  scale={9}{10}" -f $m.Name, $m.Bounds.L, $m.Bounds.T, ($m.Bounds.R - $m.Bounds.L), ($m.Bounds.B - $m.Bounds.T),
    $m.Work.L, $m.Work.T, ($m.Work.R - $m.Work.L), ($m.Work.B - $m.Work.T), $m.Scale.ToString([Globalization.CultureInfo]::InvariantCulture), $(if ($m.Primary) { '  (primary)' } else { '' })
}

# The slot: W x H logical, centred in the display's work area (taskbar excluded). Returns $null if no such display.
function Pick {
  $mons = @([HandlusRec]::Monitors())
  if ($env:REC_MONITOR) { $m = $mons | Where-Object { $_.Name -like "$($env:REC_MONITOR)*" } | Select-Object -First 1 }
  else { $m = $mons | Where-Object { $_.Primary } | Select-Object -First 1 }
  if (-not $m) { return $null }
  $ww = $m.Work.R - $m.Work.L; $wh = $m.Work.B - $m.Work.T
  if ($env:REC_W -or $env:REC_H) { $sizes = @(, @([int]$(if ($env:REC_W) { $env:REC_W } else { 1920 }), [int]$(if ($env:REC_H) { $env:REC_H } else { 1200 }))) }
  else { $sizes = @(@(1920, 1200), @(1600, 1000), @(1440, 900), @(1280, 800), @(1024, 640)) }
  $pick = $null
  foreach ($s in $sizes) {
    $pw = [int][math]::Round($s[0] * $m.Scale); $ph = [int][math]::Round($s[1] * $m.Scale)
    $pick = @{ LW = $s[0]; LH = $s[1]; W = $pw; H = $ph; Fits = ($pw -le $ww -and $ph -le $wh) }
    if ($pick.Fits) { break }
  }
  $pick.X = $m.Work.L + [int][math]::Floor(($ww - $pick.W) / 2)
  $pick.Y = $m.Work.T + [int][math]::Floor(($wh - $pick.H) / 2)
  if ($pick.X -lt $m.Work.L) { $pick.X = $m.Work.L }
  if ($pick.Y -lt $m.Work.T) { $pick.Y = $m.Work.T }
  $pick.Scale = $m.Scale; $pick.Monitor = $m.Name
  return $pick
}

# Visible Chrome browser windows (all profiles), front to back
function Chrome-Windows {
  $names = @{}
  foreach ($w in [HandlusRec]::Windows('Chrome_WidgetWin_1')) {
    if (-not $w.Visible -or $w.Cloaked -or -not $w.Title -or $w.W -lt 200 -or $w.H -lt 200) { continue }
    $key = [string]$w.Pid
    if (-not $names.ContainsKey($key)) {
      $p = Get-Process -Id $w.Pid -ErrorAction SilentlyContinue
      $names[$key] = $(if ($p) { $p.ProcessName } else { '' })
    }
    if ($names[$key] -eq 'chrome') { $w }
  }
}

function Win-Line($w) { "hwnd:{0}  at:{1},{2}  {3}x{4}  pid={5}{6}  {7}" -f $w.Hwnd, $w.X, $w.Y, $w.W, $w.H, $w.Pid, $(if ($w.Iconic) { '  minimized' } elseif ($w.Zoomed) { '  maximized' } else { '' }), $w.Title }

function In-Slot($w, $slot) { return ($w.X -eq $slot.X -and $w.Y -eq $slot.Y -and $w.W -eq $slot.W -and $w.H -eq $slot.H) }

function Now-Ms { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function Record-Window($i, $w, [double]$sec, [string]$out) {
  $dir = Split-Path -Parent $out
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  if (Test-Path $out) { Remove-Item $out -Force }
  $rc = [HandlusWgc]::Record($w.Hwnd, $sec, $i.exe, (Encode-Args $i), $out)
  if ($rc -ne 0 -or -not (Test-Path $out) -or (Get-Item $out).Length -eq 0) { Err "rec_failed exit $rc"; return $false }
  # frames written late = the machine could not encode 60 per second; such a take stutters
  if ([HandlusWgc]::Stats -match 'frames (\d+)\s+new \d+\s+late (\d+)') {
    $n = [int]$Matches[1]; $late = [int]$Matches[2]
    if ($n -gt 0 -and $late * 100 / $n -gt 10) {
      Err "rec_slow: $late of $n frames were written late - close other apps, set HANDLUS_X264=ultrafast, or lower REC_W / REC_H, then record again"
      return $false
    }
  }
  return $true
}

# ---------- commands ----------
switch ($Cmd) {
  'screens' {
    foreach ($m in [HandlusRec]::Monitors()) { Err (Monitor-Line $m) }
    $p = Pick
    if (-not $p) { Err "STOP: no display named $($env:REC_MONITOR) - check rec.ps1 screens"; exit 3 }
    $sc = $p.Scale.ToString([Globalization.CultureInfo]::InvariantCulture)
    "X=$($p.X) Y=$($p.Y) W=$($p.W) H=$($p.H) SCALE=$sc LW=$($p.LW) LH=$($p.LH) MONITOR='$($p.Monitor)'"
    Err "# window $($p.LW)x$($p.LH) logical = $($p.W)x$($p.H) on screen = the video size. Crop coordinates = page coordinates x $sc"
    if (-not $p.Fits) { Err "# WARNING: $($p.W)x$($p.H) does not fit the work area of $($p.Monitor) - lower REC_W / REC_H" }
  }
  'list' {
    foreach ($w in @(Chrome-Windows)) { Win-Line $w }
  }
  'place' {
    $mark = $A1
    if (-not $mark) { Err 'usage: rec.ps1 place <title marker (__rec_...)>'; exit 1 }
    $p = Pick
    if (-not $p) { Err 'STOP: no recording display - run rec.ps1 screens'; exit 3 }
    if (-not $p.Fits) { Err "STOP: a $($p.W)x$($p.H) window does not fit $($p.Monitor) - lower REC_W / REC_H"; exit 3 }
    $wins = @(Chrome-Windows)
    $mine = @($wins | Where-Object { $_.Title.StartsWith($mark) })
    if ($mine.Count -ne 1) {
      Err "STOP: expected exactly one Chrome window whose title starts with '$mark', found $($mine.Count)"
      $wins | ForEach-Object { Err ('  ' + (Win-Line $_)) }
      exit 2
    }
    $w = $mine[0]
    # Stop if another Chrome window already occupies the slot (another agent recording) - covering it freezes their recording
    $busy = @($wins | Where-Object { $_.Hwnd -ne $w.Hwnd -and (In-Slot $_ $p) })
    if ($busy.Count) {
      Err 'STOP: another window already sits in the recording slot - another agent may be recording. Wait, or use another display with REC_MONITOR:'
      $busy | ForEach-Object { Err ('  ' + (Win-Line $_)) }
      exit 4
    }
    $fg = [HandlusRec]::Place($w.Hwnd, $p.X, $p.Y, $p.W, $p.H)
    $now = [HandlusRec]::Describe($w.Hwnd)
    if (-not (In-Slot $now $p)) {
      Err "STOP: the window ended at $($now.X),$($now.Y) $($now.W)x$($now.H) instead of $($p.X),$($p.Y) $($p.W)x$($p.H)"
      exit 2
    }
    "ok $($now.X),$($now.Y) $($now.W)x$($now.H) $fg"
    if ($fg -eq 'fg=no') { Err '# Windows did not let this script bring the window to the front (foreground lock). Call chrome_switch_tab on its tab, then check nothing covers it.' }
  }
  'record' {
    if (-not $A1 -or -not $A2 -or -not $A3) { Err 'usage: rec.ps1 record <T0 epoch ms> <seconds> <out.mp4>'; exit 1 }
    $T0 = [long]$A1
    $sec = [double]::Parse($A2, [Globalization.CultureInfo]::InvariantCulture)
    $out = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($A3)) { $A3 } else { Join-Path (Get-Location).Path $A3 }))
    $i = Need-Ffmpeg
    $p = Pick
    if (-not $p) { Err 'STOP: no recording display'; exit 3 }
    $mine = @(Chrome-Windows | Where-Object { In-Slot $_ $p })
    if ($mine.Count -ne 1) {
      Err "STOP: expected exactly 1 Chrome window in the slot $($p.X),$($p.Y) $($p.W)x$($p.H), got $($mine.Count) - run rec.ps1 place first"
      exit 2
    }
    $w = $mine[0]
    "window hwnd:$($w.Hwnd) at:$($w.X),$($w.Y) $($w.W)x$($w.H) scale=$($p.Scale.ToString([Globalization.CultureInfo]::InvariantCulture))"
    $wait = $T0 - (Now-Ms) - 1500
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
    if (-not (Record-Window $i $w $sec $out)) { exit 2 }
    "saved $out"
  }
  'probe' {
    $i = Need-Ffmpeg
    $w = @(Chrome-Windows | Where-Object { -not $_.Iconic }) | Select-Object -First 1
    if (-not $w) { Err 'SKIP: no open Chrome window to test with'; exit 6 }
    $out = Join-Path ([IO.Path]::GetTempPath()) ("handlus-probe-{0}.mp4" -f $PID)
    $ok = Record-Window $i $w 1 $out
    if ($ok) { "ok probe $($w.W)x$($w.H) $((Get-Item $out).Length) bytes"; Remove-Item $out -Force; exit 0 }
    exit 2
  }
  'ffmpeg' {
    $i = Best-Ffmpeg
    if (-not $i) { 'ffmpeg: not found'; exit 5 }
    "ffmpeg: $($i.exe)"
    "version: $($i.version)  encoder: $($i.enc)"
    if (-not $i.enc) { exit 5 }
  }
  default {
    Get-Content $PSCommandPath -TotalCount 21 | Select-Object -Skip 1 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 1
  }
}
exit 0

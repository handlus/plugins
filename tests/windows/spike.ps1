# spike.ps1 - measurements on a GitHub Actions Windows runner for the Windows recorder (win32.cs HandlusWgc).
# The runner has no GPU, so this also checks the WARP (software) fallback.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # the PS 5.1 progress bar makes Invoke-WebRequest crawl
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$K = Join-Path $root 'plugins\handlus\skills\recording-chrome-fake-cursor\scripts'
$out = Join-Path $root 'out'; New-Item -ItemType Directory -Force $out | Out-Null
Start-Transcript -Path (Join-Path $out 'spike.txt') | Out-Null
function Log($m) { Write-Host ""; Write-Host "### $m" }

Add-Type -Path (Join-Path $K 'win32.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'res.cs')
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);'

Log 'system'
"$((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version)"
Get-CimInstance Win32_VideoController | ForEach-Object { "adapter: $($_.Name)" }
"set 1920x1080 -> " + [Res]::Set(1920, 1080); Start-Sleep 2
foreach ($m in [HandlusRec]::Monitors()) { "monitor $($m.Name) scale=$($m.Scale) bounds=$($m.Bounds.L),$($m.Bounds.T),$($m.Bounds.R),$($m.Bounds.B)" }

Log 'ffmpeg (BtbN release, encode only)'
$rel = Invoke-RestMethod 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest' -Headers @{ 'User-Agent' = 'handlus-ci' } -UseBasicParsing
$a = $rel.assets | Where-Object { $_.name -match '^ffmpeg-n\d+\.\d+-latest-win64-gpl-\d+\.\d+\.zip$' } | Sort-Object name -Descending | Select-Object -First 1
$z = Join-Path $env:TEMP 'ff.zip'; Invoke-WebRequest $a.browser_download_url -OutFile $z -UseBasicParsing
Expand-Archive $z (Join-Path $env:TEMP 'ff') -Force
$ff = (Get-ChildItem (Join-Path $env:TEMP 'ff') -Recurse -Filter ffmpeg.exe | Select-Object -First 1).FullName
$fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
"$($a.name) -> $ff"

Log 'chrome'
$chrome = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
$page = 'file:///' + ((Join-Path $PSScriptRoot 'page.html') -replace '\\', '/') + '?rec=spike'
Start-Process $chrome -ArgumentList "--user-data-dir=$env:TEMP\chr-spike", '--no-first-run', '--no-default-browser-check', '--disable-search-engine-choice-screen', '--remote-debugging-port=9222', '--window-position=100,100', '--window-size=1000,700', $page
$w = $null
for ($i = 0; $i -lt 60 -and -not $w; $i++) { Start-Sleep 1; $w = @([HandlusRec]::Windows('Chrome_WidgetWin_1') | Where-Object { $_.Visible -and $_.Title -like '__rec_ci*' })[0] }
if (-not $w) { Log 'NO CHROME WINDOW'; Stop-Transcript | Out-Null; exit 0 }
"window after $i s"
[HandlusRec]::Place($w.Hwnd, 100, 100, 1000, 700)
$w = [HandlusRec]::Describe($w.Hwnd)
"frame=$($w.Frame.L),$($w.Frame.T),$($w.Frame.R),$($w.Frame.B) rect=$($w.Rect.L),$($w.Rect.T),$($w.Rect.R),$($w.Rect.B)"

function Cdp([string]$expr) {
  try {
    $t = (Invoke-RestMethod 'http://127.0.0.1:9222/json/list') | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
    $msg = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $expr; returnByValue = $true } } | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $ws.SendAsync((New-Object ArraySegment[byte] -ArgumentList @(, $bytes)), 'Text', $true, [Threading.CancellationToken]::None).Wait()
    $buf = New-Object byte[] 65536; $seg = New-Object ArraySegment[byte] -ArgumentList @(, $buf)
    $r = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None); $r.Wait()
    return [Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)
  } catch { return "cdp eval failed: $_" }
}
function Cover($x, $y, $cw, $chh, $sec) { Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'cover.ps1'), '-X', $x, '-Y', $y, '-W', $cw, '-H', $chh, '-Sec', $sec -PassThru }
function Probe($mp4) { & $fp -v error -select_streams v:0 -count_frames -show_entries 'stream=width,height,avg_frame_rate,nb_read_frames:format=duration' -of compact $mp4 2>&1 | Out-String }
function Grab($mp4, $t, $png) { & $ff -hide_banner -loglevel error -y -ss $t -i $mp4 -frames:v 1 $png 2>&1 }
function Px($png, $x, $y) { $b = New-Object System.Drawing.Bitmap $png; $c = $b.GetPixel($x, $y); $b.Dispose(); return ('#{0:x2}{1:x2}{2:x2}' -f $c.R, $c.G, $c.B) }
# Still stretches (the page's box always moves, so a still picture means Chrome stopped painting or Windows sent nothing)
function Frozen($mp4) {
  $o = & $ff -hide_banner -nostats -i $mp4 -vf 'freezedetect=n=0.001:d=0.3' -an -f null - 2>&1 | Out-String
  $st = @([regex]::Matches($o, 'freeze_start: ([0-9.]+)') | ForEach-Object { $_.Groups[1].Value })
  $en = @([regex]::Matches($o, 'freeze_end: ([0-9.]+)') | ForEach-Object { $_.Groups[1].Value })
  $runs = for ($i = 0; $i -lt $st.Count; $i++) { "$($st[$i])-$(if ($i -lt $en.Count) { $en[$i] } else { 'end' })s" }
  "still stretches (>0.3 s): $(if ($runs) { $runs -join ' ' } else { 'none' })"
}
$enc = '-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p'

Log 'occlusion without capture: full cover 4 s, half cover 3 s, minimize 3 s'
Cdp 'window.__vis = []; 1' | Out-Null
(Cover 0 0 1920 1080 4).WaitForExit(); Start-Sleep 1
(Cover 50 300 500 300 3).WaitForExit(); Start-Sleep 1
"after covers: " + (Cdp 'JSON.stringify(window.__stats())')
Cdp 'window.__vis = []; 1' | Out-Null
[W.U]::ShowWindow([IntPtr]$w.Hwnd, 6) | Out-Null; Start-Sleep 3; [W.U]::ShowWindow([IntPtr]$w.Hwnd, 9) | Out-Null; Start-Sleep 1
"after minimize: " + (Cdp 'JSON.stringify(window.__stats())')
[HandlusRec]::Raise($w.Hwnd) | Out-Null; Start-Sleep 1

Log 'A: record 6 s, a window over the left half from 1 s to 5 s'
$mp4 = Join-Path $out 'A.mp4'
$c = Cover 50 300 500 300 4
$rc = [HandlusWgc]::Record($w.Hwnd, 6, $ff, $enc, $mp4)
"exit $rc  device=$([HandlusWgc]::Device)  $([HandlusWgc]::Stats)"
if ($rc -ne 0) { "ffmpeg: $([HandlusWgc]::FfmpegError)"; Stop-Transcript | Out-Null; exit 0 }
Probe $mp4
Grab $mp4 2.5 (Join-Path $out 'A.png')
# the cover sits at screen 50..550 x 300..600; the window frame starts at 100,100 -> window 0..450 x 200..500
"covered (window 200,350): $(Px (Join-Path $out 'A.png') 200 350)   uncovered (800,600): $(Px (Join-Path $out 'A.png') 800 600)   top-left 2,2: $(Px (Join-Path $out 'A.png') 2 2)"
Frozen $mp4

Log 'B: record 8 s, fully covered from 2 s to 5 s'
Cdp 'window.__vis = []; 1' | Out-Null
$mp4 = Join-Path $out 'B.mp4'
$job = Start-Job -ScriptBlock { param($p) Start-Sleep 2; Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $p, '-X', '0', '-Y', '0', '-W', '1920', '-H', '1080', '-Sec', '3' -Wait } -ArgumentList (Join-Path $PSScriptRoot 'cover.ps1')
$rc = [HandlusWgc]::Record($w.Hwnd, 8, $ff, $enc, $mp4)
"exit $rc  $([HandlusWgc]::Stats)"
Receive-Job $job -Wait | Out-Null
Probe $mp4; Frozen $mp4
"page: " + (Cdp 'JSON.stringify(window.__stats())')

Log 'C: still page 4 s'
Cdp 'window.__still = true' | Out-Null; Start-Sleep 1
$mp4 = Join-Path $out 'C.mp4'
$rc = [HandlusWgc]::Record($w.Hwnd, 4, $ff, $enc, $mp4)
"exit $rc  $([HandlusWgc]::Stats)"
Probe $mp4
Cdp 'window.__still = false' | Out-Null

Log 'D: minimized from 2 s to 4 s'
$mp4 = Join-Path $out 'D.mp4'
$job = Start-Job -ScriptBlock { param($h)
  Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);'
  Start-Sleep 2; [W.U]::ShowWindow([IntPtr]$h, 6) | Out-Null; Start-Sleep 2; [W.U]::ShowWindow([IntPtr]$h, 9) | Out-Null } -ArgumentList $w.Hwnd
$rc = [HandlusWgc]::Record($w.Hwnd, 6, $ff, $enc, $mp4)
"exit $rc  $([HandlusWgc]::Stats)"
Receive-Job $job -Wait | Out-Null
Probe $mp4; Frozen $mp4

Log 'E: 1600x1000 window, ultrafast vs veryfast'
[HandlusRec]::Raise($w.Hwnd) | Out-Null
[HandlusRec]::Place($w.Hwnd, 0, 0, 1600, 1000) | Out-Null
foreach ($pr in 'veryfast', 'ultrafast') {
  $mp4 = Join-Path $out "E-$pr.mp4"
  $rc = [HandlusWgc]::Record($w.Hwnd, 5, $ff, "-c:v libx264 -preset $pr -crf 18 -pix_fmt yuv420p", $mp4)
  "$pr exit $rc  $([HandlusWgc]::Stats)  $((Get-Item $mp4).Length) bytes"
}

Log 'done'
Stop-Transcript | Out-Null

# spike.ps1 - T0 measurements on a GitHub Actions Windows runner (docs: recording on Windows)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # the PS 5.1 progress bar makes Invoke-WebRequest crawl
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $root 'out'; New-Item -ItemType Directory -Force $out | Out-Null
Start-Transcript -Path (Join-Path $out 'spike.txt') | Out-Null
function Log($m) { Write-Host ""; Write-Host "### $m" }

Add-Type -Path (Join-Path $root 'plugins\handlus\skills\recording-chrome-fake-cursor\scripts\win32.cs')
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Log 'system'
[Environment]::OSVersion.Version.ToString()
(Get-CimInstance Win32_OperatingSystem).Caption
"PS " + $PSVersionTable.PSVersion
"session " + [System.Diagnostics.Process]::GetCurrentProcess().SessionId
Get-Process explorer, dwm -ErrorAction SilentlyContinue | Format-Table Id, SessionId, ProcessName -AutoSize | Out-String
Get-Command winget, choco, python, py, ffmpeg, git, bash -ErrorAction SilentlyContinue | Format-Table Name, Source -AutoSize | Out-String
foreach ($m in [HandlusRec]::Monitors()) { "monitor $($m.Name) primary=$($m.Primary) scale=$($m.Scale) bounds=$($m.Bounds.L),$($m.Bounds.T),$($m.Bounds.R),$($m.Bounds.B) work=$($m.Work.L),$($m.Work.T),$($m.Work.R),$($m.Work.B)" }

Log 'resolution change to 1920x1080'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Res {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
  public static string Modes() { var sb = new System.Text.StringBuilder(); var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); for (int i = 0; EnumDisplaySettings(null, i, ref dm); i++) sb.Append(dm.dmPelsWidth + "x" + dm.dmPelsHeight + " "); return sb.ToString(); }
  public static int Set(int w, int h) { var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); EnumDisplaySettings(null, -1, ref dm); dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x80000 | 0x100000; return ChangeDisplaySettings(ref dm, 0); }
}
'@
"modes: " + ([Res]::Modes())
"set 1920x1080 -> " + [Res]::Set(1920, 1080)
Start-Sleep 2
foreach ($m in [HandlusRec]::Monitors()) { "monitor $($m.Name) scale=$($m.Scale) bounds=$($m.Bounds.L),$($m.Bounds.T),$($m.Bounds.R),$($m.Bounds.B) work=$($m.Work.L),$($m.Work.T),$($m.Work.R),$($m.Work.B)" }

Log 'ffmpeg builds'
$ffdir = Join-Path $env:TEMP 'ffs'; New-Item -ItemType Directory -Force $ffdir | Out-Null
$cands = @()
if (Get-Command winget -ErrorAction SilentlyContinue) {
  winget install -e --id Gyan.FFmpeg --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Select-Object -Last 3
  $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe'
  if (Test-Path $links) { $cands += @{ name = 'winget Gyan.FFmpeg'; exe = $links } }
  else { Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $cands += @{ name = 'winget Gyan.FFmpeg (pkg)'; exe = $_.FullName } } }
}
try {
  $rel = Invoke-RestMethod 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest' -Headers @{ 'User-Agent' = 'handlus-ci' }
  foreach ($a in $rel.assets) {
    "asset: $($a.name)"
    if ($a.name -match '^ffmpeg-n8\.\d+-latest-win64-gpl-8\.\d+\.zip$') {
      $z = Join-Path $ffdir $a.name; Invoke-WebRequest $a.browser_download_url -OutFile $z -UseBasicParsing
      $d = Join-Path $ffdir ($a.name -replace '\.zip$', ''); Expand-Archive $z $d -Force
      $e = Get-ChildItem $d -Recurse -Filter ffmpeg.exe | Select-Object -First 1
      if ($e) { $cands += @{ name = "BtbN $($a.name)"; exe = $e.FullName } }
    }
  }
} catch { "BtbN download failed: $_" }
try {
  $z = Join-Path $ffdir 'gyan-ess.zip'; Invoke-WebRequest 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile $z -UseBasicParsing
  $d = Join-Path $ffdir 'gyan-ess'; Expand-Archive $z $d -Force
  $e = Get-ChildItem $d -Recurse -Filter ffmpeg.exe | Select-Object -First 1
  if ($e) { $cands += @{ name = 'gyan release essentials'; exe = $e.FullName } }
} catch { "gyan download failed: $_" }

$ff = $null
foreach ($c in $cands) {
  Log "build: $($c.name)"
  & $c.exe -hide_banner -version 2>&1 | Select-Object -First 1
  $filters = & $c.exe -hide_banner -filters 2>&1 | Out-String
  $has = $filters -match 'gfxcapture'
  "gfxcapture: $has   ddagrab: $($filters -match 'ddagrab')"
  if ($has) { & $c.exe -hide_banner -h filter=gfxcapture 2>&1 | Out-String }
  $enc = & $c.exe -hide_banner -encoders 2>&1 | Out-String
  "libx264: $($enc -match 'libx264')   h264_mf: $($enc -match 'h264_mf')"
  if ($has -and -not $ff) { $ff = $c.exe }
}
if (-not $ff) { Log 'NO BUILD WITH gfxcapture'; Stop-Transcript; exit 0 }
$fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
"using $ff"

Log 'chrome'
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
"chrome: $chrome"
$page = 'file:///' + ((Join-Path $PSScriptRoot 'page.html') -replace '\\', '/') + '?rec=spike'
$prof = Join-Path $env:TEMP 'chr-spike'
Start-Process $chrome -ArgumentList "--user-data-dir=$prof", '--no-first-run', '--no-default-browser-check', '--disable-search-engine-choice-screen', '--remote-debugging-port=9222', '--window-position=100,100', '--window-size=1000,700', $page
$wins = $null
for ($i = 0; $i -lt 45 -and -not $wins; $i++) {
  Start-Sleep 1
  $wins = [HandlusRec]::Windows('Chrome_WidgetWin_1') | Where-Object { $_.Visible -and $_.Title -like '__rec_ci*' }
  if ($i % 5 -eq 4) {
    "t=$($i+1)s windows: $(([HandlusRec]::Windows('Chrome_WidgetWin_1') | ForEach-Object { "'$($_.Title)' vis=$($_.Visible)" }) -join ' | ')"
    try { (Invoke-RestMethod 'http://127.0.0.1:9222/json/list') | ForEach-Object { "  cdp $($_.type) '$($_.title)' $($_.url)" } } catch { "  cdp: $($_.Exception.Message)" }
  }
}
$wins | ForEach-Object { "win hwnd=$($_.Hwnd) title='$($_.Title)' rect=$($_.Rect.L),$($_.Rect.T),$($_.Rect.R),$($_.Rect.B) frame=$($_.Frame.L),$($_.Frame.T),$($_.Frame.R),$($_.Frame.B) cloaked=$($_.Cloaked)" }
$w = @($wins)[0]
if (-not $w) { Log 'NO CHROME WINDOW'; [HandlusRec]::Windows('Chrome_WidgetWin_1') | ForEach-Object { "  any: '$($_.Title)' vis=$($_.Visible)" }; Stop-Transcript; exit 0 }

Log 'place 100,100 1000x700 (visible frame)'
[HandlusRec]::Place($w.Hwnd, 100, 100, 1000, 700)
$w = [HandlusRec]::Describe($w.Hwnd)
"after: rect=$($w.Rect.L),$($w.Rect.T),$($w.Rect.R),$($w.Rect.B) frame=$($w.Frame.L),$($w.Frame.T),$($w.Frame.R),$($w.Frame.B)"

function Stats() {
  try {
    $t = (Invoke-RestMethod 'http://127.0.0.1:9222/json/list') | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    return $t.title
  } catch { return "cdp error $_" }
}

function Grab($mp4, $t, $png) { & $ff -hide_banner -loglevel error -y -ss $t -i $mp4 -frames:v 1 $png 2>&1 }
function Px($png, $x, $y) { $b = New-Object System.Drawing.Bitmap $png; $c = $b.GetPixel($x, $y); $b.Dispose(); return ('#{0:x2}{1:x2}{2:x2}' -f $c.R, $c.G, $c.B) }
function Probe($mp4) { & $fp -v error -select_streams v:0 -show_entries 'stream=width,height,avg_frame_rate,r_frame_rate,nb_frames:format=duration' -of compact $mp4 2>&1 }
function Desk($png) { $b = New-Object System.Drawing.Bitmap 1920, 1080; $g = [System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen(0, 0, 0, 0, $b.Size); $b.Save($png); $g.Dispose(); $b.Dispose() }

$vf = 'hwdownload,format=bgra,crop=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p'
Log 'video adapters'
Get-CimInstance Win32_VideoController | ForEach-Object { "adapter: $($_.Name) | $($_.AdapterCompatibility) | $($_.DriverVersion) | $($_.PNPDeviceID)" }

# gfxcapture makes its own D3D11 device with D3D_DRIVER_TYPE_HARDWARE; a GPU-less VM may need one handed in (WARP adapter)
$devs = @('', '-init_hw_device d3d11va=hw:0 -filter_hw_device hw', '-init_hw_device d3d11va=hw:1 -filter_hw_device hw', '-init_hw_device d3d11va=hw,vendor_id=0x1414 -filter_hw_device hw')
$dev = $null
foreach ($d in $devs) {
  $k = $devs.IndexOf($d)
  Log "record A (half covered) dev='$d'"
  $mp4 = Join-Path $out "A-$k.mp4"
  $fa = "-hide_banner -loglevel verbose -y -progress pipe:1 -stats_period 0.1 $d -filter_complex gfxcapture=hwnd=$($w.Hwnd):capture_cursor=0:display_border=0,$vf -t 6 -fps_mode passthrough -c:v libx264 -preset veryfast -crf 18 $mp4"
  $cover = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'cover.ps1'), '-X', '50', '-Y', '300', '-W', '500', '-H', '300', '-Sec', '4' -PassThru
  $rc = [HandlusRec]::RunFfmpeg($ff, $fa, 20000)
  "exit $rc"
  [HandlusRec]::LastError -split "`n" | Where-Object { $_ -match 'd3d|D3D|[Dd]evice|adapter|Client area|window rect|gfxcapture.*(size|Using|Capture)' } | Select-Object -First 25
  if ($rc -ne 0) { if ($cover -and -not $cover.HasExited) { $cover.WaitForExit(6000) | Out-Null }; continue }
  $dev = $d
  Probe $mp4
  $png = Join-Path $out "A-$k.png"; Grab $mp4 2.5 $png
  # cover occupies screen 50..550 x 300..600; window frame starts at 100,100 -> window-relative 0..450 x 200..500
  "pixel in covered area (window 200,350): $(Px $png 200 350)   uncovered (window 800,600): $(Px $png 800 600)   top-left 2,2: $(Px $png 2 2)"
  Desk (Join-Path $out "A-$k-desktop.png")
  break
}
if ($null -eq $dev) { Log 'NO DEVICE WORKED - window capture cannot run on this machine'; Stop-Transcript | Out-Null; exit 0 }
"device args that work: '$dev'"

Log 'record B (fully covered for 3 s)'
$before = Stats; "title before: $before"
$mp4 = Join-Path $out 'B.mp4'
$fa = "-hide_banner -y -progress pipe:1 -stats_period 0.1 $dev -filter_complex gfxcapture=hwnd=$($w.Hwnd):capture_cursor=0,$vf -t 8 -fps_mode passthrough -c:v libx264 -preset veryfast -crf 18 $mp4"
$job = Start-Job -ScriptBlock { param($p) Start-Sleep 2; Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $p, '-X', '0', '-Y', '0', '-W', '1920', '-H', '1080', '-Sec', '3' -Wait } -ArgumentList (Join-Path $PSScriptRoot 'cover.ps1')
$rc = [HandlusRec]::RunFfmpeg($ff, $fa, 25000)
"exit $rc"
Receive-Job $job -Wait | Out-Null
Probe $mp4
& $fp -v error -select_streams v:0 -show_entries frame=pts_time -of csv=p=0 $mp4 2>&1 | Out-File (Join-Path $out 'B-frames.txt')
$ts = Get-Content (Join-Path $out 'B-frames.txt') | Where-Object { $_ -match '^[0-9.]+' } | ForEach-Object { [double]($_ -replace ',.*', '') }
$gap = 0; for ($i = 1; $i -lt $ts.Count; $i++) { $g = $ts[$i] - $ts[$i - 1]; if ($g -gt $gap) { $gap = $g } }
"frames=$($ts.Count) max frame gap=$([math]::Round($gap, 3)) s"
Start-Sleep 1
"page log after: " + (Stats)

Log 'page vis log via CDP (Runtime.evaluate)'
try {
  $t = (Invoke-RestMethod 'http://127.0.0.1:9222/json/list') | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
  $msg = '{"id":1,"method":"Runtime.evaluate","params":{"expression":"JSON.stringify(window.__stats())","returnByValue":true}}'
  $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
  $ws.SendAsync((New-Object ArraySegment[byte] -ArgumentList @(, $bytes)), 'Text', $true, [Threading.CancellationToken]::None).Wait()
  $buf = New-Object byte[] 65536; $seg = New-Object ArraySegment[byte] -ArgumentList @(, $buf)
  $r = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None); $r.Wait()
  [Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)
} catch { "cdp eval failed: $_" }

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

# C: nothing moves on the page for 4 s -> how many frames does window capture deliver? (decides the fps check on Windows)
Log 'record C (still page, 4 s)'
Cdp 'window.__still = true'
Start-Sleep 1
foreach ($mode in 'passthrough', 'cfr') {
  $mp4 = Join-Path $out "C-$mode.mp4"
  $fm = if ($mode -eq 'cfr') { '-fps_mode cfr -r 60' } else { '-fps_mode passthrough' }
  $fa = "-hide_banner -y -progress pipe:1 -stats_period 0.1 $dev -filter_complex gfxcapture=hwnd=$($w.Hwnd):capture_cursor=0,$vf -t 4 $fm -c:v libx264 -preset veryfast -crf 18 $mp4"
  $rc = [HandlusRec]::RunFfmpeg($ff, $fa, 20000)
  "C $mode exit $rc"; Probe $mp4
  $n = (& $fp -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 $mp4 2>&1)
  "C $mode frames read: $n"
}
# D: still page, the cursor moves (a 40 px element following a timer at 60 Hz) -> frames?
Cdp "(() => { const d = document.createElement('div'); d.style.cssText = 'position:fixed;width:40px;height:40px;background:#000;left:0;top:300px'; document.body.appendChild(d); let x = 0; window.__mv = setInterval(() => { x = (x + 6) % 800; d.style.left = x + 'px'; }, 16); return 1; })()"
$mp4 = Join-Path $out 'D.mp4'
$fa = "-hide_banner -y -progress pipe:1 -stats_period 0.1 $dev -filter_complex gfxcapture=hwnd=$($w.Hwnd):capture_cursor=0,$vf -t 4 -fps_mode passthrough -c:v libx264 -preset veryfast -crf 18 $mp4"
$rc = [HandlusRec]::RunFfmpeg($ff, $fa, 20000)
"D exit $rc"; Probe $mp4
Cdp 'clearInterval(window.__mv); window.__still = false'

# E: window minimized during recording -> what does capture do (error, freeze, black)?
Log 'record E (minimized for 2 s)'
$mp4 = Join-Path $out 'E.mp4'
$fa = "-hide_banner -y -progress pipe:1 -stats_period 0.1 $dev -filter_complex gfxcapture=hwnd=$($w.Hwnd):capture_cursor=0,$vf -t 6 -fps_mode passthrough -c:v libx264 -preset veryfast -crf 18 $mp4"
$job = Start-Job -ScriptBlock { param($h)
  Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);'
  Start-Sleep 2; [W.U]::ShowWindow([IntPtr]$h, 6) | Out-Null; Start-Sleep 2; [W.U]::ShowWindow([IntPtr]$h, 9) | Out-Null } -ArgumentList $w.Hwnd
$rc = [HandlusRec]::RunFfmpeg($ff, $fa, 25000)
"E exit $rc"; if ($rc -ne 0) { [HandlusRec]::LastError | Select-Object -Last 8 }
Receive-Job $job -Wait | Out-Null
Probe $mp4
& $fp -v error -select_streams v:0 -show_entries frame=pts_time -of csv=p=0 $mp4 2>&1 | Out-File (Join-Path $out 'E-frames.txt')
"page log after E: " + (Cdp 'JSON.stringify(window.__stats())')

Log 'done'
Stop-Transcript | Out-Null

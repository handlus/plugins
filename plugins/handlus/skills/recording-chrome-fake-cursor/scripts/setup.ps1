# setup.ps1 - check (and install) what a Chrome window recording needs on Windows (recording-chrome-fake-cursor skill)
#
#   setup.ps1           check only. One line per item: "ok  ..." or "MISSING  ...  -> fix". Last line READY or NOT READY.
#                       Exit 0 = ready, 2 = not
#   setup.ps1 install   install what can be installed without administrator rights (ffmpeg, Python, Pillow), then
#                       check again
#
# The window is recorded with Windows.Graphics.Capture (built into Windows 10 2004+ / 11, see win32.cs); ffmpeg only
# encodes the frames, so any ffmpeg with libx264 or h264_mf works.
#
# Run it as:  powershell -NoProfile -ExecutionPolicy Bypass -File <skill folder>\scripts\setup.ps1 [install]
# Windows has no Screen Recording permission to turn on. Only the user can: approve an administrator (UAC) prompt if one
# appears, update a Windows older than 10 version 2004, or lift a company policy that blocks PowerShell scripts.
param([Parameter(Position = 0)][string]$Mode = 'check')
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$HERE = $PSScriptRoot
$REC = Join-Path $HERE 'rec.ps1'
$script:missing = 0

function Ok([string]$m) { "ok       $m" }
function Miss([string]$m, [string]$fix) { "MISSING  $m  -> $fix"; $script:missing++ }
function Info([string]$m) { "info     $m" }
function Arch { if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }

# The Python to use. The Microsoft Store placeholder "python.exe" prints nothing and exits 9009, so a candidate
# counts only if it really runs. Returns @{ show = 'py -3'; exe = ...; pre = @('-3') } or $null
function Find-Python {
  $cands = @()
  foreach ($n in 'py', 'python', 'python3') {
    $g = Get-Command "$n.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { $cands += @{ exe = $g.Source; pre = $(if ($n -eq 'py') { @('-3') } else { @() }); show = $(if ($n -eq 'py') { 'py -3' } else { $n }) } }
  }
  # Just installed (PATH of this shell is old)
  foreach ($p in @("$env:LOCALAPPDATA\Programs\Python\Launcher\py.exe", "$env:WINDIR\py.exe")) {
    if (Test-Path $p) { $cands += @{ exe = $p; pre = @('-3'); show = "`"$p`" -3" } }
  }
  Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
    $p = Join-Path $_.FullName 'python.exe'
    if (Test-Path $p) { $cands += @{ exe = $p; pre = @(); show = "`"$p`"" } }
  }
  foreach ($c in $cands) {
    $v = & $c.exe @($c.pre + @('-c', 'import sys;print(sys.version_info[0], sys.version.split()[0])')) 2>$null
    if ($LASTEXITCODE -eq 0 -and "$v" -match '^3 (\S+)') { $c.version = $Matches[1]; return $c }
  }
  return $null
}

function Has-Pillow($py) {
  if (-not $py) { return $false }
  & $py.exe @($py.pre + @('-c', 'import PIL')) 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Have-Winget { [bool](Get-Command winget.exe -ErrorAction SilentlyContinue) }

function Chrome-Path {
  foreach ($p in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}

# ffmpeg into scripts\bin\ffmpeg, from the BtbN builds on GitHub (a release build, GPL = with libx264)
function Install-Ffmpeg {
  $arch = if ((Arch) -eq 'ARM64') { 'winarm64' } else { 'win64' }
  $url = $null
  try {
    $rel = Invoke-RestMethod 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest' -Headers @{ 'User-Agent' = 'handlus-recording-setup' } -UseBasicParsing
    # Release builds are named ffmpeg-n<major>.<minor>-latest-<arch>-gpl-<major>.<minor>.zip; take the newest
    $a = $rel.assets | Where-Object { $_.name -match "^ffmpeg-n(\d+)\.(\d+)-latest-$arch-gpl-\d+\.\d+\.zip$" } |
      ForEach-Object { $null = $_.name -match '^ffmpeg-n(\d+)\.(\d+)'; [pscustomobject]@{ a = $_; v = [int]$Matches[1] * 100 + [int]$Matches[2] } } |
      Where-Object { $_.v -ge 801 } | Sort-Object v -Descending | Select-Object -First 1 | ForEach-Object { $_.a }
    if (-not $a) { $a = $rel.assets | Where-Object { $_.name -eq "ffmpeg-master-latest-$arch-gpl.zip" } | Select-Object -First 1 }
    if ($a) { $url = $a.browser_download_url }
  } catch { }
  if (-not $url) { $url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-$arch-gpl.zip" }
  $bin = Join-Path $HERE 'bin'
  $zip = Join-Path ([IO.Path]::GetTempPath()) 'handlus-ffmpeg.zip'
  $tmp = Join-Path ([IO.Path]::GetTempPath()) 'handlus-ffmpeg'
  "Downloading ffmpeg ($url)..."
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
    $ProgressPreference = $pp
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive $zip $tmp -Force
    $top = Get-ChildItem $tmp -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Force $bin | Out-Null
    $dst = Join-Path $bin 'ffmpeg'
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Move-Item $top.FullName $dst
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
    "ffmpeg installed in $dst"
  } catch { "ffmpeg download failed: $($_.Exception.Message) - show the user this line" }
}

function Install-Python {
  if (Have-Winget) {
    'Installing Python 3 with winget (for this user, no administrator rights)...'
    winget install -e --id Python.Python.3.13 --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Select-Object -Last 3
    return
  }
  $arch = if ((Arch) -eq 'ARM64') { 'arm64' } else { 'amd64' }
  $url = "https://www.python.org/ftp/python/3.13.3/python-3.13.3-$arch.exe"
  $exe = Join-Path ([IO.Path]::GetTempPath()) "python-3.13.3-$arch.exe"
  "Installing Python 3 from python.org (for this user, no administrator rights): $url"
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $url -OutFile $exe -UseBasicParsing
    $ProgressPreference = $pp
    $p = Start-Process $exe -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1', 'InstallLauncherAllUsers=0', 'Include_test=0' -Wait -PassThru
    "python installer exit $($p.ExitCode)"
  } catch { "python install failed: $($_.Exception.Message) - show the user this line" }
}

if ($Mode -eq 'install') {
  '== install'
  & $REC ffmpeg *> $null
  if ($LASTEXITCODE -ne 0) { Install-Ffmpeg }
  $py = Find-Python
  if (-not $py) { Install-Python; $py = Find-Python }
  if ($py -and -not (Has-Pillow $py)) {
    'Installing Pillow (Python imaging library, used by sheet.py)...'
    & $py.exe @($py.pre + @('-m', 'pip', 'install', '--user', '--quiet', '--disable-pip-version-check', 'pillow')) 2>&1 | Select-Object -Last 3
  }
  ''
}

'== check'
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$build = [Environment]::OSVersion.Version.Build
$name = if ($os) { $os.Caption } else { 'Windows' }
if ($build -ge 19041) {
  Ok "$name (build $build, $(Arch))"
  Info 'Windows may draw a yellow frame around the window while it is recorded (on screen only, not in the video)'
} else { Miss "$name (build $build)" 'window recording needs Windows 10 version 2004 (build 19041) or later - the user updates Windows' }

"ok       PowerShell $($PSVersionTable.PSVersion)"

$ffline = & $REC ffmpeg 2>&1 | Out-String
$ffrc = $LASTEXITCODE
if ($ffrc -eq 0) {
  $ver = if ($ffline -match 'version: (\S+)') { $Matches[1] } else { '?' }
  $enc = if ($ffline -match 'encoder: (\S+)') { $Matches[1] } else { '?' }
  Ok "ffmpeg $ver (encoder $enc)"
} elseif ($ffline -match 'not found') {
  Miss 'ffmpeg' 'setup.ps1 install downloads one into scripts\bin\ffmpeg'
} else {
  Miss 'ffmpeg with an H.264 encoder' "the ffmpeg found has neither libx264 nor h264_mf; setup.ps1 install puts one in scripts\bin\ffmpeg. Found: $(($ffline -split "`n" | Select-Object -First 2) -join ' / ')"
}

$py = Find-Python
if ($py) { Ok "Python $($py.version)  (run the skill's .py scripts with: $($py.show))" }
else { Miss 'Python 3' $(if (Have-Winget) { 'setup.ps1 install (winget, for this user)' } else { 'setup.ps1 install (python.org installer, for this user)' }) }

if (Has-Pillow $py) { Ok 'Pillow (Python)' }
elseif ($py) { Miss 'Pillow (Python)' "$($py.show) -m pip install --user pillow  (setup.ps1 install does it)" }
else { Miss 'Pillow (Python)' 'after Python: setup.ps1 install' }

$chrome = Chrome-Path
if ($chrome) { Ok "Google Chrome ($chrome)" } else { Miss 'Google Chrome' 'the user installs Chrome from https://www.google.com/chrome/' }

if ($ffrc -eq 0) {
  # In its own process: the recorder (C#) writes straight to the console, which a script call here cannot capture
  $pr = & powershell -NoProfile -ExecutionPolicy Bypass -File $REC probe 2>&1 | Out-String
  $prc = $LASTEXITCODE
  if ($prc -eq 0) { Ok "window recording test (1 s of an open Chrome window$(if ($pr -match 'device=(\S+)') { ', ' + $Matches[1] + ' graphics' }))" }
  elseif ($prc -eq 6) { Info 'window recording not tested: no Chrome window is open (open one and run setup.ps1 again to test)' }
  else { Miss 'window recording test' "recording an open Chrome window failed: $(($pr -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 4) -join ' / ')" }
}

'-- Also needed (check from the agent, not the shell): the Handlus MCP connected, and chrome_demo_cursor in the tool list (Handlus extension 0.3.1+).'
if ($script:missing) { "NOT READY ($script:missing missing)"; exit 2 }
'READY'
exit 0

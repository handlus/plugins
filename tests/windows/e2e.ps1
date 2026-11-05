# e2e.ps1 - Windows CI take for the recording skill: setup -> install -> place -> cursor -> record -> evidence.
# Runs on a GitHub Actions Windows runner (see .github/workflows/windows-recording.yml). Exit 0 = every check passed.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$K = Join-Path $root 'plugins\handlus\skills\recording-chrome-fake-cursor\scripts'
$out = Join-Path $root 'out'; New-Item -ItemType Directory -Force $out | Out-Null
Start-Transcript -Path (Join-Path $out 'e2e.txt') | Out-Null
$script:fails = @()
function Log($m) { Write-Host ''; Write-Host "### $m" }
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "PASS  $what" } else { Write-Host "FAIL  $what"; $script:fails += $what } }
function Rec { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $K 'rec.ps1') @args }
function Setup { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $K 'setup.ps1') @args }
function Now-Ms { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $K 'win32.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'res.cs')
"runner display 1920x1080 -> $([Res]::Set(1920, 1080))"; Start-Sleep 2

# ---------- 1. setup before anything is installed ----------
Log 'setup (check) before install'
$s1 = Setup 2>&1 | Out-String; $rc1 = $LASTEXITCODE; $s1
Check ($rc1 -eq 2 -and $s1 -match 'NOT READY') 'setup.ps1 reports NOT READY before install (exit 2)'

Log 'setup install'
$s2 = Setup install 2>&1 | Out-String; $rc2 = $LASTEXITCODE; $s2
Check ($s2 -match 'ok\s+ffmpeg') 'setup.ps1 install leaves an ffmpeg with an H.264 encoder'
Check ($s2 -match 'ok\s+Pillow') 'setup.ps1 install leaves Pillow'
$py = if ($s2 -match "run the skill's \.py scripts with: (.+)\)") { $Matches[1].Trim() } else { 'python' }
"python command: $py"
function Py { $a = @($args); if ($py -eq 'py -3') { & py -3 @a } else { & ($py.Trim('"')) @a } }

# ---------- 2. Chrome with the test page ----------
Log 'chrome'
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$page = 'file:///' + ((Join-Path $PSScriptRoot 'page.html') -replace '\\', '/') + '?rec=ci'
Start-Process $chrome -ArgumentList "--user-data-dir=$env:TEMP\chr-e2e", '--no-first-run', '--no-default-browser-check', '--disable-search-engine-choice-screen', '--disable-features=Translate', '--remote-debugging-port=9222', '--window-position=40,40', '--window-size=900,600', $page
# A cold Chrome on the runner takes more than 6 s to show its first window
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep 1
  if (@([HandlusRec]::Windows('Chrome_WidgetWin_1') | Where-Object { $_.Visible -and $_.Title -like '__rec_ci*' }).Count) { "chrome window after $($i + 1) s"; break }
}
Py -m pip install --user --quiet --disable-pip-version-check websocket-client 2>&1 | Select-Object -Last 2

Log 'setup (check) with a Chrome window open'
$s3 = Setup 2>&1 | Out-String; $rc3 = $LASTEXITCODE; $s3
Check ($rc3 -eq 0 -and $s3 -match '(?m)^READY') 'setup.ps1 READY after install, window capture test passes'

Log 'rec.ps1 ffmpeg / list'
Rec ffmpeg
Rec list

# ---------- 3. a take ----------
function Take([string]$name, [string]$scene, [scriptblock]$during) {
  Log "take $name ($scene)"
  Py (Join-Path $PSScriptRoot 'drive.py') title "__rec_$name" | Out-Null
  $scr = Rec screens 2>&1 | Out-String; $scr
  $slot = @{}
  if ($scr -match 'X=(-?\d+) Y=(-?\d+) W=(\d+) H=(\d+) SCALE=([0-9.]+) LW=\d+ LH=\d+ MONITOR=''([^'']*)''') {
    $slot = @{ X = [int]$Matches[1]; Y = [int]$Matches[2]; W = [int]$Matches[3]; H = [int]$Matches[4]; Scale = $Matches[5]; Mon = $Matches[6] }
  }
  $pl = Rec place "__rec_$name" 2>&1 | Out-String; $prc = $LASTEXITCODE; $pl
  Check ($prc -eq 0 -and $pl -match '(?m)^ok ') "[$name] place puts the window in the slot"
  $T0 = (Now-Ms) + 9000
  Py (Join-Path $PSScriptRoot 'drive.py') play $T0 $scene
  $job = $null
  if ($during) { $job = Start-Job -ScriptBlock $during -ArgumentList $T0, $slot, (Join-Path $PSScriptRoot 'cover.ps1') }
  $len = if ($scene -eq 'cover') { 10 } else { 8 }
  $mp4 = Join-Path $out "$name.mp4"
  $r = Rec record $T0 $len $mp4 2>&1 | Out-String; $rrc = $LASTEXITCODE; $r
  $recorded = ($rrc -eq 0 -and $r -match 'rec_started \d+' -and (Test-Path $mp4))
  Check $recorded "[$name] record saves the video"
  if ($job) { Receive-Job $job -Wait -AutoRemoveJob | Out-Null }
  Start-Sleep 1
  $fcl = Join-Path $out "$name.fclog.json"
  Py (Join-Path $PSScriptRoot 'drive.py') fclog $fcl | Out-Null
  "fclog: $(Get-Content $fcl -Raw)"
  "stats: $(Py (Join-Path $PSScriptRoot 'drive.py') stats)"
  $ev = Py (Join-Path $K 'evidence.py') write $mp4 --monitor $slot.Mon --scale $slot.Scale --profile ci --url $page --fclog $fcl --action $scene 2>&1 | Out-String
  $erc = $LASTEXITCODE; $ev
  return @{ slot = $slot; mp4 = $mp4; evidence = $erc; T0 = $T0; rec = $r; recorded = $recorded }
}

function Px($mp4, [double]$t, [int]$x, [int]$y) {
  if (-not (Test-Path $mp4)) { return [System.Drawing.Color]::Black }
  $png = "$mp4.$t.png"
  $ff = (Rec ffmpeg | Select-String '^ffmpeg: (.+)$').Matches[0].Groups[1].Value
  & $ff -hide_banner -loglevel error -y -ss $t -i $mp4 -frames:v 1 $png 2>&1 | Out-Null
  $b = New-Object System.Drawing.Bitmap $png; $c = $b.GetPixel($x, $y); $b.Dispose()
  return $c
}

# A: half covered by a lime window from T0+1 s to T0+5 s. The page is magenta; lime in the video means the cover was recorded.
$halfCover = { param($T0, $slot, $cover)
  $wait = $T0 + 1000 - [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cover, '-X', ($slot.X - 50), '-Y', ($slot.Y + 150), '-W', ([int]($slot.W / 2)), '-H', ([int]($slot.H / 2)), '-Sec', '4' -Wait }
$a = Take 'half' 'basic' $halfCover
Check ($a.evidence -eq 0) '[half] evidence.py write passes (fcLog start/end, no hidden, fps >= 40)'
# rec starts ~1.5 s before T0; the cover is up from about 2.5 s to 6.5 s in the video. Sample inside the covered part.
$c = Px $a.mp4 4.0 ([int]($a.slot.W / 8)) ([int]($a.slot.H * 0.6))
"covered-area pixel at 4.0 s: R=$($c.R) G=$($c.G) B=$($c.B)"
Check (-not ($c.G -gt 200 -and $c.R -lt 80 -and $c.B -lt 80)) '[half] the covering window is not in the video'
Check ($c.R -gt 200 -and $c.B -gt 200 -and $c.G -lt 80) '[half] the page shows where the cover was'

Log 'sheet + sign + check'
$prev = Join-Path $out 'half.preview.jpg'
Py (Join-Path $K 'sheet.py') $a.mp4 --preview --segments '2-6' --crop "0,0,$($a.slot.W - 2),$($a.slot.H - 2)" --out $prev
Py (Join-Path $K 'sheet.py') $a.mp4 --from 1 --to 3 --step 0.5 --out (Join-Path $out 'half.sheet.jpg')
Py (Join-Path $K 'evidence.py') sign $a.mp4 --sheet $prev --note 'ci: nothing cropped'
$ck = Py (Join-Path $K 'evidence.py') check $a.mp4 2>&1 | Out-String; $ckrc = $LASTEXITCODE; $ck
Check ($ckrc -eq 0) '[half] evidence.py check passes after sign'

# B: fully covered from T0+2.5 s to T0+4.5 s -> Chrome stops painting; the take must fail evidence
$fullCover = { param($T0, $slot, $cover)
  $wait = $T0 + 2500 - [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cover, '-X', ($slot.X - 20), '-Y', ($slot.Y - 20), '-W', ($slot.W + 40), '-H', ($slot.H + 40), '-Sec', '2' -Wait }
$b = Take 'full' 'cover' $fullCover
# What Windows did while the window was fully covered: Chrome either marks the page hidden (and stops painting),
# or does not notice the cover and keeps painting. The page's #box moves all the time, so a still stretch in the
# video means painting stopped. The take must fail exactly when it is broken (hidden, or a still stretch).
$fcl = Join-Path $out 'full.fclog.json'
$hid = (Test-Path $fcl) -and ((Get-Content $fcl -Raw) -match ',\s*true\s*\]')
$ff = (Rec ffmpeg | Select-String '^ffmpeg: (.+)$').Matches[0].Groups[1].Value
$fz = if (Test-Path $b.mp4) { & $ff -hide_banner -nostats -i $b.mp4 -vf 'freezedetect=n=0.001:d=0.4' -an -f null - 2>&1 | Out-String } else { '' }
$frozen = $fz -match 'freeze_start'
"full cover: page hidden=$hid  still stretch in the video=$frozen"
($fz -split "`n" | Where-Object { $_ -match 'freeze_' }) -join ' / '
if ($hid -or $frozen) {
  Check ($b.recorded -and $b.evidence -ne 0) '[full] evidence.py write FAILS the take (window hidden or picture stopped)'
} else {
  Check ($b.recorded -and $b.evidence -eq 0) '[full] Chrome kept painting under the cover, so the take passes'
}
Check (-not ($frozen -and -not $hid)) '[full] no still stretch without document.hidden (evidence would miss it)'

# ---------- 4. display scale 125 % and 150 % (size ladder on a smaller logical screen) ----------
$ffp = Join-Path (Split-Path ((Rec ffmpeg | Select-String '^ffmpeg: (.+)$').Matches[0].Groups[1].Value)) 'ffprobe.exe'
"display scale before: $([Res]::Scale())"
foreach ($pct in 125, 150) {
  Log "display scale $pct %"
  $r = [Res]::SetScale($pct); Start-Sleep 4
  "SetScale $pct -> $r  now: $([Res]::Scale())"
  if ($r -ne 0) { Check $false "[scale $pct] the runner lets the test change the display scale"; continue }
  Py (Join-Path $PSScriptRoot 'drive.py') title '__rec_scale' | Out-Null
  $scr = Rec screens 2>&1 | Out-String; $scr
  if ($scr -notmatch 'X=(-?\d+) Y=(-?\d+) W=(\d+) H=(\d+) SCALE=([0-9.]+) LW=(\d+) LH=(\d+)') { Check $false "[scale $pct] screens prints the slot"; continue }
  $W = [int]$Matches[3]; $H = [int]$Matches[4]; $sc = [double]$Matches[5]; $LW = [int]$Matches[6]; $LH = [int]$Matches[7]
  Check ([math]::Abs($sc - $pct / 100) -lt 0.01) "[scale $pct] screens reports SCALE=$($pct / 100) (got $sc)"
  Check ($W -eq [math]::Round($LW * $sc) -and $H -eq [math]::Round($LH * $sc)) "[scale $pct] W x H = logical size x scale ($LW x $LH -> $W x $H)"
  $pl = Rec place '__rec_scale' 2>&1 | Out-String; $prc = $LASTEXITCODE; $pl
  Check ($prc -eq 0 -and $pl -match "(?m)^ok -?\d+,-?\d+ ${W}x${H}") "[scale $pct] place puts the window at $W x $H"
  $mp4 = Join-Path $out "scale$pct.mp4"
  $rr = Rec record ((Now-Ms) + 2000) 3 $mp4 2>&1 | Out-String; $rrc = $LASTEXITCODE; $rr
  $vs = if (Test-Path $mp4) { (& $ffp -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $mp4 | Out-String).Trim() } else { 'none' }
  "video size: $vs"
  Check ($rrc -eq 0 -and $vs -eq "$($W - $W % 2),$($H - $H % 2)") "[scale $pct] the video is the window size ($W x $H)"
}
"back to 100 %: $([Res]::SetScale(100))"; Start-Sleep 3

Log 'result'
if ($script:fails.Count) { "FAILED: $($script:fails.Count)"; $script:fails | ForEach-Object { "  - $_" } } else { 'ALL PASSED' }
Stop-Transcript | Out-Null
if ($script:fails.Count) { exit 1 }
exit 0

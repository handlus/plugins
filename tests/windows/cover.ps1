# cover.ps1 - a plain lime window used by the tests to cover (part of) the recording window
param([int]$X, [int]$Y, [int]$W, [int]$H, [double]$Sec = 3)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class CoverDpi{[DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);}'
[CoverDpi]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
$f = New-Object System.Windows.Forms.Form
$f.Text = 'cover'; $f.BackColor = [System.Drawing.Color]::Lime; $f.TopMost = $true
$f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.ShowInTaskbar = $false
$f.Location = New-Object System.Drawing.Point($X, $Y); $f.Size = New-Object System.Drawing.Size($W, $H)
$t = New-Object System.Windows.Forms.Timer; $t.Interval = [int]($Sec * 1000); $t.add_Tick({ $f.Close() }); $t.Start()
$f.add_Shown({ $f.Location = New-Object System.Drawing.Point($X, $Y); $f.Size = New-Object System.Drawing.Size($W, $H) })
[System.Windows.Forms.Application]::Run($f)

# Finds the newest Godot 4 on this PC and prints "<version>|<path>".
# Used by Play_Dead_Protocol.bat and Open_In_Godot_Editor.bat.
param([string]$GameDir)
$roots = @($GameDir, (Join-Path $GameDir '..'), "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Documents", "$env:ProgramFiles", "$env:LOCALAPPDATA") +
    (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })
$found = @()
foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    $found += Get-ChildItem -Path $r -Filter 'Godot_v4*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*console*' }
    # Stop early once a good one (4.7 or newer) turned up
    if ($found | Where-Object { $_.Name -match 'Godot_v4\.(\d+)' -and [int]$Matches[1] -ge 7 }) { break }
}
if (-not $found) { exit 0 }
$best = $found | Sort-Object @{ Expression = {
        if ($_.Name -match 'Godot_v(\d+)\.(\d+)(?:\.(\d+))?') { [int]$Matches[1] * 10000 + [int]$Matches[2] * 100 + [int]("0" + $Matches[3]) } else { 0 }
    }; Descending = $true } | Select-Object -First 1
$ver = '0.0'
if ($best.Name -match 'Godot_v(\d+\.\d+(?:\.\d+)?)') { $ver = $Matches[1] }
"$ver|$($best.FullName)"

@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
rem Finds Godot 4 on this PC (any folder), so this works on every computer.
set "GODOT="
if exist "%~dp0godot_path.txt" set /p GODOT=<"%~dp0godot_path.txt"
if defined GODOT if not exist "!GODOT!" set "GODOT="
if not defined GODOT (
  echo Looking for Godot 4 on this PC, please wait...
  for /f "usebackq delims=" %%F in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$roots = @('%~dp0', '%~dp0..', \"$env:USERPROFILE\Desktop\", \"$env:USERPROFILE\Downloads\", \"$env:USERPROFILE\Documents\", \"$env:ProgramFiles\", \"$env:LOCALAPPDATA\") + (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root }); foreach ($r in $roots) { if (Test-Path $r) { $h = Get-ChildItem -Path $r -Filter 'Godot_v4*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*console*' } | Sort-Object { $_.Name -like '*mono*' } -Descending | Select-Object -First 1; if ($h) { $h.FullName; break } } }"`) do set "GODOT=%%F"
)
if not defined GODOT (
  echo.
  echo Could not find Godot 4 on this PC.
  echo Download Godot 4.7.1 .NET from https://godotengine.org/download/archive/
  echo Then drag the Godot .exe onto this window and press Enter:
  set /p GODOT=
  if defined GODOT set "GODOT=!GODOT:"=!"
)
if not defined GODOT goto nogodot
if not exist "!GODOT!" goto nogodot
> "%~dp0godot_path.txt" echo !GODOT!
echo Using Godot: !GODOT!
rem Godot must import the models, textures and sounds before the game can run.
rem A fresh download has none imported (that shows as a plain gray window).
if not exist "%~dp0.godot\imported" (
  echo.
  echo First launch: preparing game files. This takes a few minutes, please wait...
) else (
  echo Checking game files...
)
start "" /wait "!GODOT!" --headless --import --path .
start "" "!GODOT!" --path .
exit /b 0
:nogodot
echo Godot not found. Install Godot 4.7.1 .NET and run this again.
pause
exit /b 1

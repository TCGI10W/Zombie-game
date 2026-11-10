@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
rem Finds the newest Godot 4 on this PC (any folder), so this works on every computer.
rem The game needs Godot 4.7 or newer: an older Godot only shows a gray window.
set "GODOT="
set "GVER="
if exist "%~dp0godot_path.txt" set /p GODOT=<"%~dp0godot_path.txt"
if defined GODOT if not exist "!GODOT!" set "GODOT="
if defined GODOT call :version_of "!GODOT!"
if defined GODOT if "!GOOD!"=="0" set "GODOT="
if not defined GODOT (
  echo Looking for Godot 4 on this PC, please wait...
  for /f "usebackq tokens=1,* delims=|" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\find_godot.ps1" -GameDir "%~dp0."`) do (
    set "GVER=%%A"
    set "GODOT=%%B"
  )
  if defined GODOT call :version_of "!GODOT!"
)
if not defined GODOT (
  echo.
  echo Could not find Godot 4 on this PC.
  echo Download Godot 4.7.1 from https://godotengine.org/download/archive/4.7.1-stable/
  echo Then drag the Godot .exe onto this window and press Enter:
  set /p GODOT=
  if defined GODOT set "GODOT=!GODOT:"=!"
  if defined GODOT call :version_of "!GODOT!"
)
if not defined GODOT goto nogodot
if not exist "!GODOT!" goto nogodot
if "!GOOD!"=="0" goto oldgodot
> "%~dp0godot_path.txt" echo !GODOT!
echo Using Godot !GVER!: !GODOT!
start "" "!GODOT!" --editor --path .
exit /b 0
:version_of
rem Reads the version from the file name (Godot_v4.7.1-stable...) -> GVER, GOOD
set "GOOD=1"
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$n = [IO.Path]::GetFileName('%~1'); if ($n -match 'Godot_v(\d+)\.(\d+)(\.\d+)?') { $Matches[0].Substring(7) + '|' + ([int]([int]$Matches[1] -gt 4 -or [int]$Matches[2] -ge 7)) } else { 'unknown|1' }"`) do (
  for /f "tokens=1,2 delims=|" %%X in ("%%V") do (
    set "GVER=%%X"
    set "GOOD=%%Y"
  )
)
exit /b 0
:oldgodot
echo.
echo The Godot found on this PC is version !GVER!:
echo   !GODOT!
echo This game needs Godot 4.7.1 or newer. An older Godot only shows a gray window.
echo Download 4.7.1 from https://godotengine.org/download/archive/4.7.1-stable/
echo unzip it anywhere, then run this file again.
del "%~dp0godot_path.txt" 2>nul
pause
exit /b 1
:nogodot
echo Godot not found. Install Godot 4.7.1 and run this again.
pause
exit /b 1

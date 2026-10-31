@echo off
setlocal
set "GODOT=%GODOT4%"
if not defined GODOT if exist "F:\Godot_v4.7.2-stable_win64.exe" set "GODOT=F:\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT set "GODOT=D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Set GODOT4 to your Godot 4.7.2 executable, or open project.godot and press F5.
  pause
  exit /b 1
)
if not exist "%~dp0work\appdata" mkdir "%~dp0work\appdata"
set "APPDATA=%~dp0work\appdata"
start "" "%GODOT%" --path "%~dp0." --rendering-method gl_compatibility --log-file "%~dp0work\play.log"
endlocal

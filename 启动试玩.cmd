@echo off
setlocal
set "GODOT=F:\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot executable not found. Open project.godot in Godot 4 and press F5.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0." --rendering-method gl_compatibility --log-file "%~dp0output\play.log"
endlocal

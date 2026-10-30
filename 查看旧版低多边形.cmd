@echo off
setlocal
set "GODOT=F:\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" exit /b 1
start "" "%GODOT%" --path "%~dp0." --scene res://scenes/lowpoly.tscn --rendering-method gl_compatibility --log-file "%~dp0output\lowpoly-play.log"
endlocal

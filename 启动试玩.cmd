@echo off
setlocal
if defined GODOT4 set "GODOT=%GODOT4%"
if not defined GODOT for /f "delims=" %%G in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%G"
if not defined GODOT if exist "D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe" set "GODOT=D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT (
  echo Set GODOT4 to a Godot 4 executable, or open project.godot and press F5.
  pause
  exit /b 1
)
if not exist "%GODOT%" (
  echo Godot executable not found. Check GODOT4.
  pause
  exit /b 1
)
set "XIUXIAN_SAVE_DIR=%~dp0output"
if not exist "%XIUXIAN_SAVE_DIR%" mkdir "%XIUXIAN_SAVE_DIR%"
start "" "%GODOT%" --path "%~dp0." --rendering-method gl_compatibility --log-file "%~dp0output\play.log"
endlocal

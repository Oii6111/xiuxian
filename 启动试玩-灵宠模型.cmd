@echo off
setlocal
REM 启动灵宠聊天服务（DeepSeek deepseek-flash），再把游戏指向它。
set "GODOT=%GODOT4%"
if not defined GODOT if exist "F:\Godot_v4.7.2-stable_win64.exe" set "GODOT=F:\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT set "GODOT=D:\Projects\Codex\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Set GODOT4 to your Godot 4.7.2 executable, or open project.godot and press F5.
  pause
  exit /b 1
)
if not exist "%~dp0companion-service\.env" (
  echo 还没有 companion-service\.env
  echo 先执行: copy companion-service\.env.example companion-service\.env
  echo 再把 DeepSeek 密钥填进 LLM_API_KEY；不填也能启动（离线 stub 模式）。
)
start "灵宠聊天服务" /min cmd /c ""%~dp0companion-service\启动灵宠聊天服务.cmd""
timeout /t 3 >nul
set "XIUXIAN_COMPANION_API_URL=http://127.0.0.1:8031/api/v1/companion/chat"
set "XIUXIAN_COMPANION_AUTH_ORIGIN=http://127.0.0.1:8031"
if not exist "%~dp0work\appdata" mkdir "%~dp0work\appdata"
set "APPDATA=%~dp0work\appdata"
start "" "%GODOT%" --path "%~dp0." --rendering-method gl_compatibility --log-file "%~dp0work\play.log"
endlocal

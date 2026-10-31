@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
set "WECHAT_LINK_PYTHON=%XIUXIAN_ACCOUNT_PYTHON%"
if not defined WECHAT_LINK_PYTHON if exist "E:\anaconda3\python.exe" set "WECHAT_LINK_PYTHON=E:\anaconda3\python.exe"
if not defined WECHAT_LINK_PYTHON set "WECHAT_LINK_PYTHON=python"
"%WECHAT_LINK_PYTHON%" "%~dp0wechat_link_demo\run.py" --open-browser
if errorlevel 1 pause
endlocal

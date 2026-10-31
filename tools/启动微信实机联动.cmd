@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wechat_live\launch.ps1"
if errorlevel 1 pause

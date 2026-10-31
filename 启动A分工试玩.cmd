@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\play_combat_lifecycle.ps1"
if errorlevel 1 pause

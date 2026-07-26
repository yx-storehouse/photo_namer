@echo off
cd /d %~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\publish_app_update.ps1" -BuildOnly %*
pause

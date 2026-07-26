@echo off
cd /d %~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\publish_app_update.ps1" -BuildOnly %*
if errorlevel 1 goto end
node "%~dp0tool\publish_release_node.mjs" publish %*
:end
pause

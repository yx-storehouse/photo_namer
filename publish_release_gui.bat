@echo off
cd /d %~dp0
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0tool\publish_release_gui.ps1"

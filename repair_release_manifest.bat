@echo off
cd /d %~dp0
node "%~dp0tool\publish_release_node.mjs" repair %*
pause

@echo off
echo Restarting chat server...
taskkill /F /IM node.exe 2>nul
cd /d "%~dp0"
node server.js
pause

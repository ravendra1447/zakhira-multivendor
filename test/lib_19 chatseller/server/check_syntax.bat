@echo off
echo Checking chatHelpers.js syntax...
node -c routes\marketplace\chatHelpers.js
if %errorlevel% equ 0 (
    echo ✅ Syntax is correct!
) else (
    echo ❌ Syntax error found!
)
pause

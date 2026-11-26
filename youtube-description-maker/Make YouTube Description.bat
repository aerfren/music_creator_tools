@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Make YouTube Description.ps1" %*
echo.
echo Done. The description is saved in Documents\YouTube Descriptions and copied to the clipboard.
pause

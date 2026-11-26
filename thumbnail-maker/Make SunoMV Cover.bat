@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Make SunoMV Cover.ps1" %*
echo.
echo Done. The cover is saved next to your picture. Thumbnails go in your Music\thumbnails folder.
pause

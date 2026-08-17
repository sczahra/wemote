@echo off
setlocal
title WEMOTE Update
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_wemote.ps1"
echo.
pause

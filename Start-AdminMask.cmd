@echo off
setlocal
powershell.exe -NoProfile -File "%~dp0adminMask.ps1"
exit /b %errorlevel%

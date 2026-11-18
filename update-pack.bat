@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update-pack.ps1" %*
if not "%~1"=="-Yes" pause

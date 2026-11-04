@echo off
setlocal
cd /d "%~dp0"
title WoW Core-Pinning Background Watcher
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch_and_pin_wow.ps1"
endlocal

@echo off
setlocal
cd /d "%~dp0"

:: Check for administrative rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Run the universal network optimizer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply_WoW_Network_Optimizations.ps1"
if %errorlevel% equ 0 (
    echo.
    echo [OK] All network and latency optimizations applied successfully!
) else (
    echo.
    echo [!] An error occurred during optimization.
)
echo.
pause
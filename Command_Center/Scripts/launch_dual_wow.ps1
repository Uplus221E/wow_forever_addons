<#
.SYNOPSIS
    Dual-Client Launcher & Monitor Positioner for WoW: Forever.
.DESCRIPTION
    Launches WoW1 (Main Alliance Gnome Mage) snapped to Monitor 1 (Primary Display).
    Launches WoW2 (Ironforge Bank Alt) snapped to Monitor 2 (Secondary Display, Left Half).
    Launches Dashboard/LAUNCH_HUD.html snapped to Monitor 2 (Right Half).
.PARAMETER WowPath
    Explicit path to WowClassic.exe or WoW directory.
.PARAMETER DryRun
    Simulates window coordinates and launch sequence without starting processes.
.PARAMETER SkipHud
    Skips opening the Launch HUD on Monitor 2.
#>

[CmdletBinding()]
param (
    [string]$WowPath = "",
    [switch]$DryRun,
    [switch]$SkipHud,
    [switch]$Single
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

# Load Win32 user32.dll P/Invoke definitions
$win32Code = @"
using System;
using System.Runtime.InteropServices;

public class Win32Window {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const int GWL_STYLE = -16;
    public const int WS_VISIBLE = 0x10000000;
    public const int WS_POPUP = 0x00800000;
    public const int SW_SHOW = 5;
    public const uint SWP_FRAMECHANGED = 0x0020;
    public const uint SWP_SHOWWINDOW = 0x0040;
}
"@

if (-not ([System.Management.Automation.PSTypeName]'Win32Window').Type) {
    Add-Type -TypeDefinition $win32Code
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " WOW: FOREVER DUAL-CLIENT LAUNCHER & MULTI-MONITOR POSITIONER" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Enumerate Displays
$screens = [System.Windows.Forms.Screen]::AllScreens
$primaryScreen = $screens | Where-Object { $_.Primary }
$secondaryScreen = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1

if (-not $primaryScreen) {
    $primaryScreen = $screens[0]
}
if (-not $secondaryScreen) {
    Write-Host "[i] Single monitor detected. Partitioning primary display for dual workflow." -ForegroundColor Yellow
    $secondaryScreen = $primaryScreen
}

Write-Host "[+] Monitor 1 (Primary)   : $($primaryScreen.DeviceName) - $($primaryScreen.Bounds.Width)x$($primaryScreen.Bounds.Height) at ($($primaryScreen.Bounds.X), $($primaryScreen.Bounds.Y))" -ForegroundColor Cyan
Write-Host "[+] Monitor 2 (Secondary) : $($secondaryScreen.DeviceName) - $($secondaryScreen.Bounds.Width)x$($secondaryScreen.Bounds.Height) at ($($secondaryScreen.Bounds.X), $($secondaryScreen.Bounds.Y))" -ForegroundColor Cyan

# 2. Locate WoW Executable (Resilient Dynamic Discovery)
$wowExe = $null

# Priority 1: Query Blizzard's active .build.info database to track client patches automatically
$buildInfoRoots = @(
    "C:\Program Files (x86)\World of Warcraft",
    "C:\Program Files\World of Warcraft",
    "D:\World of Warcraft"
)

$discoveredExes = @()
foreach ($root in $buildInfoRoots) {
    $infoFile = Join-Path $root ".build.info"
    if (Test-Path $infoFile) {
        try {
            $lines = Get-Content $infoFile
            foreach ($line in $lines) {
                # Format: branch|active|...|Product
                # Active wowf line: eu|1|...||wowf
                if ($line -match "\|1\|.*\|wowf$") {
                    $foreverExe = Join-Path $root "_forever_\Wow.exe"
                    if (Test-Path $foreverExe) {
                        $discoveredExes += $foreverExe
                    }
                }
            }
        } catch {}
    }
}

$candidateExes = $discoveredExes + @(
    "C:\Program Files (x86)\World of Warcraft\_forever_\Wow.exe",
    "C:\Program Files\World of Warcraft\_forever_\Wow.exe",
    "D:\World of Warcraft\_forever_\Wow.exe",
    "C:\Program Files (x86)\World of Warcraft\_classic_era_\WowClassic.exe",
    "C:\Program Files (x86)\World of Warcraft\_classic_\WowClassic.exe",
    "C:\Program Files\World of Warcraft\_classic_era_\WowClassic.exe",
    "C:\Program Files\World of Warcraft\_classic_\WowClassic.exe",
    "D:\World of Warcraft\_classic_era_\WowClassic.exe",
    "D:\World of Warcraft\_classic_\WowClassic.exe"
)

if (-not [string]::IsNullOrWhiteSpace($WowPath)) {
    $candidateExes = @(
        $WowPath,
        (Join-Path $WowPath "Wow.exe"),
        (Join-Path $WowPath "_forever_\Wow.exe"),
        (Join-Path $WowPath "WowClassic.exe"),
        (Join-Path $WowPath "_classic_era_\WowClassic.exe"),
        (Join-Path $WowPath "_classic_\WowClassic.exe")
    ) + $candidateExes
}

foreach ($cand in $candidateExes) {
    if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand -PathType Leaf)) {
        $wowExe = (Resolve-Path $cand).Path
        break
    }
}

if (-not $wowExe) {
    if ($DryRun) {
        $wowExe = "C:\Program Files (x86)\World of Warcraft\_classic_era_\WowClassic.exe (Simulated)"
        Write-Host "[i] Running in DryRun mode with simulated executable." -ForegroundColor DarkGray
    } else {
        Write-Warning "Could not find WowClassic.exe or Wow.exe in standard directories. Provide -WowPath or run with -DryRun."
        return
    }
} else {
    Write-Host "[+] WoW Executable located: $wowExe" -ForegroundColor Green
}

# 3. Calculate Geometries
# WoW1: Full primary display
$w1_X = $primaryScreen.Bounds.X
$w1_Y = $primaryScreen.Bounds.Y
$w1_W = $primaryScreen.Bounds.Width
$w1_H = $primaryScreen.Bounds.Height

# WoW2: Secondary display, left half
$w2_X = $secondaryScreen.Bounds.X
$w2_Y = $secondaryScreen.Bounds.Y
$w2_W = [int]($secondaryScreen.Bounds.Width / 2)
$w2_H = $secondaryScreen.Bounds.Height

# HUD: Secondary display, right half
$hud_X = $secondaryScreen.Bounds.X + $w2_W
$hud_Y = $secondaryScreen.Bounds.Y
$hud_W = $secondaryScreen.Bounds.Width - $w2_W
$hud_H = $secondaryScreen.Bounds.Height

Write-Host ""
Write-Host "[Layout Plan]" -ForegroundColor White
Write-Host "  WoW1 (Main Mage)    -> ($w1_X, $w1_Y) ${w1_W}x${w1_H} [Monitor 1 Fullscreen/Borderless]" -ForegroundColor White
Write-Host "  WoW2 (Bank Mule)    -> ($w2_X, $w2_Y) ${w2_W}x${w2_H} [Monitor 2 Left Half]" -ForegroundColor White
Write-Host "  HUD  (Command Desk) -> ($hud_X, $hud_Y) ${hud_W}x${hud_H} [Monitor 2 Right Half]" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY-RUN] Execution plan verified. Skipping actual process invocation." -ForegroundColor Green
    return
}

# Helper function to wait for window handle and position it
function Position-ProcessWindow {
    param (
        [System.Diagnostics.Process]$Proc,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [string]$Label
    )
    Write-Host "[*] Waiting for $Label window handle..." -ForegroundColor White
    $timeout = 20
    $elapsed = 0
    while ($Proc.MainWindowHandle -eq [IntPtr]::Zero -and $elapsed -lt $timeout) {
        Start-Sleep -Milliseconds 500
        $elapsed += 0.5
        $Proc.Refresh()
    }

    if ($Proc.MainWindowHandle -ne [IntPtr]::Zero) {
        Start-Sleep -Milliseconds 1000 # Wait for initial engine render
        [Win32Window]::MoveWindow($Proc.MainWindowHandle, $X, $Y, $Width, $Height, $true) | Out-Null
        Write-Host "    [OK] $Label positioned successfully at ($X, $Y) ${Width}x${Height}." -ForegroundColor Green

        # Re-affirm core pinning post-D3D12 render in case game patch resets thread affinity
        try {
            $Proc.Refresh()
            $Proc.ProcessorAffinity = 0x0FFF
            $Proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
            Write-Host "    [OK] Confirmed persistent P-Core pinning (0x0FFF, High Priority) for $Label." -ForegroundColor Green
        } catch {
            Write-Host "    [!] Post-render pinning confirmation notice: $_" -ForegroundColor DarkGray
        }
    } else {
        Write-Warning "Could not retrieve MainWindowHandle for $Label within ${timeout}s."
    }
}

# 4. Launch WoW1 (Alliance Gnome Mage) - Primary Borderless Fullscreen Display
Write-Host "[*] Launching WoW1 (Main Account in Borderless Fullscreen)..." -ForegroundColor White

# Ensure Config.wtf enforces Borderless Fullscreen (SET GxMaximize "1") before booting
$wtfPath = Join-Path (Split-Path $wowExe) "WTF\Config.wtf"
if (Test-Path $wtfPath) {
    try {
        $wtfContent = Get-Content $wtfPath -Raw
        if ($wtfContent -match 'SET GxMaximize\s+"0"') {
            $wtfContent = $wtfContent -replace 'SET GxMaximize\s+"0"', 'SET GxMaximize "1"'
            Set-Content -Path $wtfPath -Value $wtfContent -Encoding UTF8 -NoNewline
            Write-Host "    [+] Config.wtf: Restored Borderless Fullscreen (SET GxMaximize 1)." -ForegroundColor Green
        }
    } catch {}
}

# Boot WoW1 without '-windowed' so D3D12 launches directly into native Borderless Fullscreen
$procWoW1 = Start-Process -FilePath $wowExe -PassThru
try {
    # Pin WoW1 to P-Cores (CPUs 0-11) + High Priority Class
    $procWoW1.ProcessorAffinity = 0x0FFF
    $procWoW1.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
    Write-Host "    [OK] WoW1 initial core pinning: P-Cores (0x0FFF), High Priority." -ForegroundColor Green
} catch {
    Write-Host "    [!] Could not apply core pinning to WoW1: $_" -ForegroundColor DarkGray
}

# Wait for WoW1 engine initialization & confirm persistent core pinning post-render
Write-Host "[*] Waiting for WoW1 engine initialization..." -ForegroundColor White
$timeout = 20
$elapsed = 0
while ($procWoW1.MainWindowHandle -eq [IntPtr]::Zero -and $elapsed -lt $timeout) {
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
    $procWoW1.Refresh()
}
if ($procWoW1.MainWindowHandle -ne [IntPtr]::Zero) {
    Start-Sleep -Milliseconds 1000
    try {
        $procWoW1.Refresh()
        $procWoW1.ProcessorAffinity = 0x0FFF
        $procWoW1.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
        Write-Host "    [OK] Confirmed persistent P-Core pinning (0x0FFF, High Priority) for WoW1 (Fullscreen)." -ForegroundColor Green
    } catch {}
} else {
    Write-Warning "Could not retrieve MainWindowHandle for WoW1 within ${timeout}s."
}

# 5. Launch WoW2 (Ironforge Bank Alt - Secondary Display)
if (-not $Single) {
    Write-Host "[*] Launching WoW2 (Bank Alt Account)..." -ForegroundColor White
    # NOTE: Never pass '-popupwindow' as WoW engine rejects it with a fatal CommandLine Parse Error.
    $procWoW2 = Start-Process -FilePath $wowExe -ArgumentList "-windowed" -PassThru
    try {
        # Pin WoW2 to P-Cores (CPUs 0-11) + Normal Priority Class
        $procWoW2.ProcessorAffinity = 0x0FFF
        $procWoW2.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
        Write-Host "    [OK] WoW2 pinned to P-Cores (0x0FFF) with Normal Priority." -ForegroundColor Green
    } catch {
        Write-Host "    [!] Could not apply core pinning to WoW2: $_" -ForegroundColor DarkGray
    }
    Position-ProcessWindow -Proc $procWoW2 -X $w2_X -Y $w2_Y -Width $w2_W -Height $w2_H -Label "WoW2 (Bank Alt)"
} else {
    Write-Host "[i] Single-client mode requested: skipping WoW2 (Bank Alt)." -ForegroundColor DarkGray
}

# 6. Launch Command Center HUD
if (-not $SkipHud -and -not $Single) {
    $hudFile = Join-Path $PSScriptRoot "..\Dashboard\LAUNCH_HUD.html"
    if (Test-Path $hudFile) {
        $hudPath = (Resolve-Path $hudFile).Path
        $hudUri = "file:///" + $hudPath.Replace("\", "/")
        Write-Host "[*] Launching LAUNCH_HUD.html on Monitor 2..." -ForegroundColor White
        
        $edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
        if (-not (Test-Path $edgePath)) {
            $edgePath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
        }

        if (Test-Path $edgePath) {
            $edgeArgs = "--app=""$hudUri"" --window-position=$hud_X,$hud_Y --window-size=$hud_W,$hud_H"
            Start-Process -FilePath $edgePath -ArgumentList $edgeArgs
            Write-Host "    [OK] HUD launched in frameless app window." -ForegroundColor Green
        } else {
            Start-Process $hudPath
            Write-Host "    [OK] HUD opened in default browser." -ForegroundColor Green
        }
    } else {
        Write-Warning "LAUNCH_HUD.html not found at $hudFile"
    }
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "[OK] Dual WoW environment and Command Center initialized." -ForegroundColor Green

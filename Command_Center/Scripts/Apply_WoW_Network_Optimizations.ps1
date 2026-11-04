<#
.SYNOPSIS
    Universal WoW & Windows Network Latency Optimizer for ZeroMaint.
.DESCRIPTION
    1. Detects all active physical Ethernet and Wi-Fi adapters.
    2. Disables Nagle's Algorithm (TcpAckFrequency = 1, TCPNoDelay = 1) to eliminate spell queue delay.
    3. Disables Windows NetworkThrottlingIndex (0xFFFFFFFF) and SystemResponsiveness (0).
    4. Enables Windows 11 Optimizations for Windowed Games (SwapEffectUpgradeEnable = 1).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " ZeroMaint - Universal WoW Network & Latency Optimizer" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Enumerate and optimize all active physical adapters
$nics = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
    $_.Status -eq "Up" -and 
    $_.InterfaceDescription -notmatch "Tailscale|Virtual|VPN|Loopback|TAP|Bluetooth" 
}

if (-not $nics) {
    Write-Warning "No active physical network adapters detected."
} else {
    foreach ($nic in $nics) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($nic.InterfaceGuid)"
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name "TcpAckFrequency" -Value 1 -Type DWord
            Set-ItemProperty -Path $path -Name "TCPNoDelay" -Value 1 -Type DWord
            Write-Host "  [OK] Applied TCP NoDelay & instant ACKs to: $($nic.Name) ($($nic.InterfaceDescription))" -ForegroundColor Green
        }
    }
}

# 2. System Profile Optimizations
try {
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord
    Write-Host "  [OK] Disabled Windows Network Throttling & 20% background CPU reservation" -ForegroundColor Green

    $taskGames = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if (Test-Path $taskGames) {
        Set-ItemProperty -Path $taskGames -Name "GPU Priority" -Value 8 -Type DWord
        Set-ItemProperty -Path $taskGames -Name "Priority" -Value 6 -Type DWord
        Set-ItemProperty -Path $taskGames -Name "Scheduling Category" -Value "High" -Type String
        Set-ItemProperty -Path $taskGames -Name "SFIO Priority" -Value "High" -Type String
        Write-Host "  [OK] Configured Games task priority (GPU 8, Priority 6, High Scheduling)" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not update SystemProfile (requires Administrator): $_"
}

# 3. User GPU Preferences (Windows 11 Windowed Game Optimizations)
try {
    $userGpu = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (-not (Test-Path $userGpu)) {
        New-Item -Path $userGpu -Force | Out-Null
    }
    Set-ItemProperty -Path $userGpu -Name "DirectXUserGlobalSettings" -Value "SwapEffectUpgradeEnable=1;"
    Write-Host "  [OK] Enabled Windows 11 Optimizations for Windowed Games" -ForegroundColor Green
} catch {
    Write-Warning "Could not update UserGpuPreferences: $_"
}

# 4. Disable Windows 11 DWM Transparency (Frees compositor GPU memory & reduces frame jitter)
try {
    $themePersonalize = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (Test-Path $themePersonalize) {
        Set-ItemProperty -Path $themePersonalize -Name "EnableTransparency" -Value 0 -Type DWord
        Write-Host "  [OK] Disabled Windows 11 DWM Transparency Effects" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not update Transparency settings: $_"
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] Network & Latency Optimization is Active!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
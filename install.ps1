<#
.SYNOPSIS
    1-Click Addon Installer for WoW: Forever.
.DESCRIPTION
    Installs the full curated addon suite directly into World of Warcraft: Forever
    (C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns).
.PARAMETER WowPath
    Explicit path to World of Warcraft installation root or Interface\AddOns folder.
#>

[CmdletBinding()]
param (
    [string]$WowPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " WOW: FOREVER ADDONS 1-CLICK DEPLOYER" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan

# Locate target directory
$targetAddonDir = $null
$candidatePaths = @(
    $WowPath,
    "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns",
    "C:\Program Files\World of Warcraft\_forever_\Interface\AddOns",
    "D:\World of Warcraft\_forever_\Interface\AddOns",
    "C:\Program Files (x86)\World of Warcraft\_classic_\Interface\AddOns",
    "C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns"
)

foreach ($candidate in $candidatePaths) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        try {
            $root = [System.IO.Path]::GetPathRoot($candidate)
            if (-not [string]::IsNullOrEmpty($root) -and -not [System.IO.Directory]::Exists($root)) { continue }
            if ($candidate -match "Interface\\AddOns$" -and (Test-Path $candidate)) {
                $targetAddonDir = $candidate
                break
            }
            $subForeverPath = [System.IO.Path]::Combine($candidate, "_forever_\Interface\AddOns")
            if (Test-Path $subForeverPath) {
                $targetAddonDir = $subForeverPath
                break
            }
        } catch { continue }
    }
}

if (-not $targetAddonDir) {
    Write-Error "Could not detect World of Warcraft _forever_ AddOns folder. Pass -WowPath explicitly."
    return
}

Write-Host "[+] Target Directory: $targetAddonDir" -ForegroundColor Green

$sourceAddons = Join-Path $PSScriptRoot "AddOns"
$addons = Get-ChildItem -Directory $sourceAddons

foreach ($addon in $addons) {
    $dest = Join-Path $targetAddonDir $addon.Name
    $isJunction = $false
    if (Test-Path $dest) {
        $item = Get-Item $dest
        if ($item.Attributes -match "ReparsePoint") { $isJunction = $true }
    }

    if ($isJunction) {
        Write-Host "  [*] $($addon.Name) is an active junction, preserving link." -ForegroundColor Yellow
    } else {
        Write-Host "  [*] Deploying $($addon.Name)..." -ForegroundColor White
        if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
        Copy-Item -Path "$($addon.FullName)\*" -Destination $dest -Recurse -Force
        Write-Host "      [OK] $($addon.Name) deployed." -ForegroundColor Green
    }
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "[OK] All WoW: Forever addons deployed successfully!" -ForegroundColor Green

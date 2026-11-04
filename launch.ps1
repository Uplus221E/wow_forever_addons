<#
.SYNOPSIS
    1-Click Dual WoW + Command Center Launcher.
#>

[CmdletBinding()]
param (
    [string]$WowPath = "",
    [switch]$DryRun,
    [switch]$SkipHud
)

$script = Join-Path $PSScriptRoot "Command_Center\Scripts\launch_dual_wow.ps1"
if (Test-Path $script) {
    & $script -WowPath $WowPath -DryRun:$DryRun -SkipHud:$SkipHud
} else {
    Write-Error "Could not find launch_dual_wow.ps1 at $script"
}

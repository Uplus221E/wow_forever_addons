<#
.SYNOPSIS
    Automated Background Core Pinner for World of Warcraft (Battle.net launches).
.DESCRIPTION
    Runs silently in the background with near-zero CPU overhead.
    Detects any 'Wow.exe' or 'WowClassic.exe' instance launched via Battle.net
    and instantly enforces Intel 12th Gen P-Core pinning (0x0FFF) and High Priority.
#>

$P_CORES = 0x0FFF  # CPUs 0-11 (All 6 Golden Cove P-cores with HT)
$targetProcesses = @("Wow", "WowClassic")

while ($true) {
    try {
        Get-Process -Name $targetProcesses -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.ProcessorAffinity -ne $P_CORES) {
                    $_.ProcessorAffinity = $P_CORES
                    $_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
                }
            } catch {
                # Ignore transient access errors during startup/termination
            }
        }
    } catch {
        # Defensive catch-all to prevent script termination
    }
    Start-Sleep -Seconds 2
}

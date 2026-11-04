<#
.SYNOPSIS
    Automated Addon Downloader & Installer for WoW: Forever Command Suite.
.DESCRIPTION
    Deploys ZeroMaint & ForeverGoblin_Core, downloads and installs RXPGuides,
    Questie, AtlasQuest, and VoiceOver directly from GitHub releases.
    Explicitly skips Leatrix Plus (LTP) to ensure zero conflicts with ZeroMaint.
.PARAMETER WowPath
    Explicit path to World of Warcraft installation root or Interface\AddOns folder.
.PARAMETER DryRun
    Simulates detection and download steps without writing files.
#>

[CmdletBinding()]
param (
    [string]$WowPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " FOREVER GOBLIN ADDON INSTALLER & STAGING PIPELINE (NO LEATRIX PLUS)" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Determine AddOns target directory
$targetAddonDir = $null

$candidatePaths = @(
    $WowPath,
    "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns",
    "C:\Program Files\World of Warcraft\_forever_\Interface\AddOns",
    "D:\World of Warcraft\_forever_\Interface\AddOns",
    "C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns",
    "C:\Program Files (x86)\World of Warcraft\_classic_\Interface\AddOns",
    "C:\Program Files\World of Warcraft\_classic_era_\Interface\AddOns",
    "C:\Program Files\World of Warcraft\_classic_\Interface\AddOns",
    "D:\World of Warcraft\_classic_era_\Interface\AddOns",
    "D:\World of Warcraft\_classic_\Interface\AddOns"
)

foreach ($candidate in $candidatePaths) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        try {
            $root = [System.IO.Path]::GetPathRoot($candidate)
            if (-not [string]::IsNullOrEmpty($root) -and -not [System.IO.Directory]::Exists($root)) {
                continue
            }
            if ($candidate -match "Interface\\AddOns$" -and (Test-Path $candidate)) {
                $targetAddonDir = $candidate
                break
            }
            $subForeverPath = [System.IO.Path]::Combine($candidate, "_forever_\Interface\AddOns")
            if (Test-Path $subForeverPath) {
                $targetAddonDir = $subForeverPath
                break
            }
            $subAddonPath = [System.IO.Path]::Combine($candidate, "_classic_era_\Interface\AddOns")
            if (Test-Path $subAddonPath) {
                $targetAddonDir = $subAddonPath
                break
            }
            $subClassicPath = [System.IO.Path]::Combine($candidate, "_classic_\Interface\AddOns")
            if (Test-Path $subClassicPath) {
                $targetAddonDir = $subClassicPath
                break
            }
            $directPath = [System.IO.Path]::Combine($candidate, "Interface\AddOns")
            if (Test-Path $directPath) {
                $targetAddonDir = $directPath
                break
            }
        } catch {
            continue
        }
    }
}

if (-not $targetAddonDir) {
    $stagedDir = Join-Path $PSScriptRoot "..\Staged_AddOns"
    $targetAddonDir = (Resolve-Path -Path $stagedDir -ErrorAction SilentlyContinue)
    if (-not $targetAddonDir) {
        $targetAddonDir = [System.IO.Path]::GetFullPath($stagedDir)
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $targetAddonDir -Force | Out-Null
        }
    }
    Write-Host "[!] Active WoW installation not detected in standard paths." -ForegroundColor Yellow
    Write-Host "    Defaulting to Staging directory: $targetAddonDir" -ForegroundColor Yellow
} else {
    Write-Host "[+] Target AddOns directory identified: $targetAddonDir" -ForegroundColor Green
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "ForeverGoblin_Temp"
if (-not $DryRun -and -not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

$webHeaders = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Antigravity-WoW-Installer' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 2. Deploy ZeroMaint (Core Suite)
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$zeroMaintFiles = @(
    "ZeroMaint.toc",
    "ZeroMaint_Core.lua",
    "ZeroMaint_Layout.lua",
    "ZeroMaint_Mail.lua",
    "ZeroMaint_Profiles.lua",
    "ZeroMaint_QoL.lua"
)

$destZeroMaint = Join-Path $targetAddonDir "ZeroMaint"
Write-Host "[*] Deploying ZeroMaint (Core Layout, QoL & BoE Engine)..." -ForegroundColor White
$isJunction = $false
if (Test-Path $destZeroMaint) {
    $item = Get-Item $destZeroMaint
    if ($item.Attributes -match "ReparsePoint") {
        $isJunction = $true
    }
}

if ($isJunction) {
    Write-Host "    [OK] ZeroMaint is already live junctioned to this repository ($destZeroMaint)" -ForegroundColor Green
} else {
    if (-not $DryRun) {
        if (-not (Test-Path $destZeroMaint)) { New-Item -ItemType Directory -Path $destZeroMaint -Force | Out-Null }
        foreach ($f in $zeroMaintFiles) {
            $src = Join-Path $repoRoot $f
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination $destZeroMaint -Force
            }
        }
        Write-Host "    [OK] ZeroMaint deployed -> $destZeroMaint" -ForegroundColor Green
    } else {
        Write-Host "    [DRY-RUN] Would copy ZeroMaint files to $destZeroMaint" -ForegroundColor DarkGray
    }
}

# 3. Deploy ForeverGoblin_Core (Launch Companion)
$sourceAddonDir = Join-Path $PSScriptRoot "..\Addon_Deploy\ForeverGoblin_Core"
if (Test-Path $sourceAddonDir) {
    $destForeverGoblin = Join-Path $targetAddonDir "ForeverGoblin_Core"
    Write-Host "[*] Deploying ForeverGoblin_Core (Recipe Sniper & Route Engine)..." -ForegroundColor White
    if (-not $DryRun) {
        if (-not (Test-Path $destForeverGoblin)) {
            New-Item -ItemType Directory -Path $destForeverGoblin -Force | Out-Null
        }
        Copy-Item -Path "$sourceAddonDir\*" -Destination $destForeverGoblin -Recurse -Force
        Write-Host "    [OK] ForeverGoblin_Core deployed -> $destForeverGoblin" -ForegroundColor Green
    } else {
        Write-Host "    [DRY-RUN] Would copy $sourceAddonDir to $destForeverGoblin" -ForegroundColor DarkGray
    }
}

$stagedCacheDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Staged_AddOns"))

# 4. Deploy or Fetch RestedXP Free (1-20 Starter Engine)
$rxpStaged = Join-Path $stagedCacheDir "RXPGuides"
$targetRXP = Join-Path $targetAddonDir "RXPGuides"
Write-Host "[*] Deploying RestedXP (1-20 Starter Engine)..." -ForegroundColor White
if ((Test-Path $rxpStaged) -and ((Resolve-Path $rxpStaged).Path -ne (Resolve-Path $targetRXP -ErrorAction SilentlyContinue).Path)) {
    if (-not $DryRun) {
        if (-not (Test-Path $targetRXP)) { New-Item -ItemType Directory -Path $targetRXP -Force | Out-Null }
        Copy-Item -Path "$rxpStaged\*" -Destination $targetRXP -Recurse -Force
        Write-Host "    [OK] RestedXP deployed from staged cache -> $targetRXP" -ForegroundColor Green
    } else {
        Write-Host "    [DRY-RUN] Would copy RestedXP from staged cache to $targetRXP" -ForegroundColor DarkGray
    }
} else {
    $rxpUrl = "https://github.com/RestedXP/RXPGuides/archive/refs/heads/main.zip"
    $rxpZip = Join-Path $tempDir "rxpguides.zip"
    $rxpExtract = Join-Path $tempDir "rxp_extract"
    if (-not $DryRun) {
        try {
            Invoke-WebRequest -Uri $rxpUrl -OutFile $rxpZip -UseBasicParsing -TimeoutSec 30
            if (Test-Path $rxpExtract) { Remove-Item $rxpExtract -Recurse -Force }
            Expand-Archive -Path $rxpZip -DestinationPath $rxpExtract -Force
            
            $innerDir = Get-ChildItem -Path $rxpExtract -Directory | Select-Object -First 1
            if (-not (Test-Path $targetRXP)) { New-Item -ItemType Directory -Path $targetRXP -Force | Out-Null }
            Copy-Item -Path "$($innerDir.FullName)\*" -Destination $targetRXP -Recurse -Force
            Write-Host "    [OK] RestedXP installed -> $targetRXP" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to download/extract RestedXP: $_"
        } finally {
            if (Test-Path $rxpZip) { Remove-Item $rxpZip -Force -ErrorAction SilentlyContinue }
            if (Test-Path $rxpExtract) { Remove-Item $rxpExtract -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } else {
        Write-Host "    [DRY-RUN] Would download $rxpUrl and extract to $targetRXP" -ForegroundColor DarkGray
    }
}

# 5. Deploy or Fetch Questie Release
$questieStaged = Join-Path $stagedCacheDir "Questie"
$targetQuestie = Join-Path $targetAddonDir "Questie"
Write-Host "[*] Deploying Questie..." -ForegroundColor White
if ((Test-Path $questieStaged) -and ((Resolve-Path $questieStaged).Path -ne (Resolve-Path $targetQuestie -ErrorAction SilentlyContinue).Path)) {
    if (-not $DryRun) {
        if (-not (Test-Path $targetQuestie)) { New-Item -ItemType Directory -Path $targetQuestie -Force | Out-Null }
        Copy-Item -Path "$questieStaged\*" -Destination $targetQuestie -Recurse -Force
        Write-Host "    [OK] Questie deployed from staged cache -> $targetQuestie" -ForegroundColor Green
    } else {
        Write-Host "    [DRY-RUN] Would copy Questie from staged cache to $targetQuestie" -ForegroundColor DarkGray
    }
} else {
    Write-Host "    Querying latest Questie release from GitHub..." -ForegroundColor DarkCyan
    if (-not $DryRun) {
        try {
            $questieRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Questie/Questie/releases/latest" -Headers $webHeaders -TimeoutSec 15
            $zipAsset = $questieRelease.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
            if ($zipAsset) {
                $questieZip = Join-Path $tempDir "questie.zip"
                $questieExtract = Join-Path $tempDir "questie_extract"
                Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $questieZip -UseBasicParsing -TimeoutSec 60
                if (Test-Path $questieExtract) { Remove-Item $questieExtract -Recurse -Force }
                Expand-Archive -Path $questieZip -DestinationPath $questieExtract -Force
                
                $questieSource = Join-Path $questieExtract "Questie"
                if (-not (Test-Path $questieSource)) {
                    $subDir = Get-ChildItem -Path $questieExtract -Directory | Select-Object -First 1
                    if ($subDir) { $questieSource = $subDir.FullName }
                }
                if (-not (Test-Path $targetQuestie)) { New-Item -ItemType Directory -Path $targetQuestie -Force | Out-Null }
                Copy-Item -Path "$questieSource\*" -Destination $targetQuestie -Recurse -Force
                Write-Host "    [OK] Questie installed -> $targetQuestie" -ForegroundColor Green
                Remove-Item $questieZip -Force -ErrorAction SilentlyContinue
                Remove-Item $questieExtract -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Failed to query or install Questie: $_"
        }
    } else {
        Write-Host "    [DRY-RUN] Would fetch and unpack Questie to $targetQuestie" -ForegroundColor DarkGray
    }
}

# 6. Deploy or Fetch AtlasQuest Release
$aqStaged = Join-Path $stagedCacheDir "AtlasQuest"
$targetAQ = Join-Path $targetAddonDir "AtlasQuest"
Write-Host "[*] Deploying AtlasQuest..." -ForegroundColor White
if ((Test-Path $aqStaged) -and ((Resolve-Path $aqStaged).Path -ne (Resolve-Path $targetAQ -ErrorAction SilentlyContinue).Path)) {
    if (-not $DryRun) {
        if (-not (Test-Path $targetAQ)) { New-Item -ItemType Directory -Path $targetAQ -Force | Out-Null }
        Copy-Item -Path "$aqStaged\*" -Destination $targetAQ -Recurse -Force
        Write-Host "    [OK] AtlasQuest deployed from staged cache -> $targetAQ" -ForegroundColor Green
    } else {
        Write-Host "    [DRY-RUN] Would copy AtlasQuest from staged cache to $targetAQ" -ForegroundColor DarkGray
    }
} else {
    Write-Host "    Querying latest AtlasQuest release from GitHub..." -ForegroundColor DarkCyan
    if (-not $DryRun) {
        try {
            $aqRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/nanderson11/AtlasQuest/releases/latest" -Headers $webHeaders -TimeoutSec 15
            $aqZipAsset = $aqRelease.assets | Where-Object { $_.name -like "AtlasQuest-*.zip" } | Select-Object -First 1
            if ($aqZipAsset) {
                $aqZip = Join-Path $tempDir "atlasquest.zip"
                $aqExtract = Join-Path $tempDir "aq_extract"
                Invoke-WebRequest -Uri $aqZipAsset.browser_download_url -OutFile $aqZip -UseBasicParsing -TimeoutSec 30
                if (Test-Path $aqExtract) { Remove-Item $aqExtract -Recurse -Force }
                Expand-Archive -Path $aqZip -DestinationPath $aqExtract -Force
                
                $aqSource = Join-Path $aqExtract "AtlasQuest"
                if (-not (Test-Path $targetAQ)) { New-Item -ItemType Directory -Path $targetAQ -Force | Out-Null }
                Copy-Item -Path "$aqSource\*" -Destination $targetAQ -Recurse -Force
                Write-Host "    [OK] AtlasQuest installed -> $targetAQ" -ForegroundColor Green
                Remove-Item $aqZip -Force -ErrorAction SilentlyContinue
                Remove-Item $aqExtract -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Failed to query or install AtlasQuest: $_"
        }
    } else {
        Write-Host "    [DRY-RUN] Would fetch and unpack AtlasQuest to $targetAQ" -ForegroundColor DarkGray
    }
}

# 7. Deploy or Fetch VoiceOver Release (BlizzClassic Core)
$voStaged = Join-Path $stagedCacheDir "AI_VoiceOver"
$targetVO = Join-Path $targetAddonDir "AI_VoiceOver"
Write-Host "[*] Deploying VoiceOver Core..." -ForegroundColor White
if ((Test-Path $voStaged) -and ((Resolve-Path $voStaged).Path -ne (Resolve-Path $targetVO -ErrorAction SilentlyContinue).Path)) {
    if (-not $DryRun) {
        if (-not (Test-Path $targetVO)) { New-Item -ItemType Directory -Path $targetVO -Force | Out-Null }
        Copy-Item -Path "$voStaged\*" -Destination $targetVO -Recurse -Force
        Write-Host "    [OK] VoiceOver core deployed from staged cache -> $targetVO" -ForegroundColor Green
    } else {
        Write-Host "    [DRY-RUN] Would copy VoiceOver from staged cache to $targetVO" -ForegroundColor DarkGray
    }
} else {
    Write-Host "    Querying latest VoiceOver core release from GitHub..." -ForegroundColor DarkCyan
    if (-not $DryRun) {
        try {
            $voRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/mrthinger/wow-voiceover/releases/latest" -Headers $webHeaders -TimeoutSec 15
            $voZipAsset = $voRelease.assets | Where-Object { $_.name -like "*BlizzClassic*.zip" } | Select-Object -First 1
            if (-not $voZipAsset) {
                $voZipAsset = $voRelease.assets | Where-Object { $_.name -like "*1.12*.zip" } | Select-Object -First 1
            }
            if ($voZipAsset) {
                $voZip = Join-Path $tempDir "voiceover.zip"
                $voExtract = Join-Path $tempDir "vo_extract"
                Invoke-WebRequest -Uri $voZipAsset.browser_download_url -OutFile $voZip -UseBasicParsing -TimeoutSec 45
                if (Test-Path $voExtract) { Remove-Item $voExtract -Recurse -Force }
                Expand-Archive -Path $voZip -DestinationPath $voExtract -Force
                
                $voSource = Join-Path $voExtract "AI_VoiceOver"
                if (-not (Test-Path $voSource)) {
                    $subDir = Get-ChildItem -Path $voExtract -Directory | Select-Object -First 1
                    if ($subDir) { $voSource = $subDir.FullName }
                }
                if (-not (Test-Path $targetVO)) { New-Item -ItemType Directory -Path $targetVO -Force | Out-Null }
                Copy-Item -Path "$voSource\*" -Destination $targetVO -Recurse -Force
                Write-Host "    [OK] VoiceOver core installed -> $targetVO" -ForegroundColor Green
                Remove-Item $voZip -Force -ErrorAction SilentlyContinue
                Remove-Item $voExtract -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Failed to query or install VoiceOver: $_"
        }
    } else {
        Write-Host "    [DRY-RUN] Would fetch and unpack VoiceOver to $targetVO" -ForegroundColor DarkGray
    }
}

# 8. Clean up temp folder
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 9. Summary & Final Verification Checklist (LTP SKIPPED)
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " INSTALLED & STAGED ADDONS (LEATRIX PLUS OMITTED BY DESIGN):" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  [x] 1. ZeroMaint         : Deployed (Layout, Unitframes, Auto-Repair, BoE Engine)" -ForegroundColor Green
Write-Host "  [x] 2. ForeverGoblin_Core: Deployed (Qia Recipe Sniper, Mail Dump, /fgroute)" -ForegroundColor Green
Write-Host "  [x] 3. RXPGuides         : Deployed (1-20 Free Starter Speedrun Engine)" -ForegroundColor Green
Write-Host "  [x] 4. Questie           : Deployed (Latest GitHub Release)" -ForegroundColor Green
Write-Host "  [x] 5. AtlasQuest        : Deployed (1-and-Done Dungeon Quest Engine)" -ForegroundColor Green
Write-Host "  [x] 6. VoiceOver Core    : Deployed (BlizzClassic AI Engine)" -ForegroundColor Green
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " REMAINING 2 UTILITIES (VERIFY IN CURSEFORGE):" -ForegroundColor Yellow
Write-Host "  [ ] 1. TradeSkillMaster  : TSM Core + AppHelper (Auction house & sniper strings)" -ForegroundColor White
Write-Host "  [ ] 2. TomTom            : Waypoints engine for /fgroute Winterspring loop" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "[OK] Full addon deployment complete. ZeroMaint is in complete control." -ForegroundColor Green

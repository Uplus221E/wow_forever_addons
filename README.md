# _forever_addons

Automated, high-performance addon suite and dual-client launch command center curated for **World of Warcraft: Forever** (`_forever_`, non-beta).

Built specifically for high-efficiency dual-account gameplay (**WoW1 Main Alliance Gnome Mage** + **WoW2 Ironforge Bank Mule**) on super ultra-wide displays (32:9 Samsung Odyssey G95C) with secondary monitoring.

---

## 📦 Curated Addon Stack

| Addon | Role | Key Functionality |
| :--- | :--- | :--- |
| **`ZeroMaint`** | **Core UI & QoL Engine** | 16:9 safe-zone UI containment for 32:9 displays, clean round minimap, auto-repair with guild bank support, throttled auto-vendor grays, vacuum auto-looting, and native 12-slot BoE auto-mailer (`/sendboe`, `/z mail`). |
| **`ForeverGoblin_Core`** | **Launch Speedrun Automation** | First-tick limited recipe sniper (Qia *Runecloth Bag/Gloves*, *Transmute: Arcanite*, *Runed Arcanite Rod*, *GFPP*), 1-click bulk scarce mat bankalt mail dump (`/fgmail`), 12-point Winterspring Outer Rim TomTom route loader (`/fgroute`), and bedtime FCT downshift (`/fgnight`, `/fgday`). |
| **`RXPGuides`** | **1–20 Speedrun Engine** | Free RestedXP Dun Morogh $\rightarrow$ Loch Modan $\rightarrow$ Darkshore navigation arrow and quest optimization. |
| **`Questie`** | **Quest Database** | World map and minimap quest objective tracker for Classic Era/Forever. |
| **`AtlasQuest`** | **Dungeon Quest Engine** | In-instance dungeon quest logs and reward tracking for 1-and-done custom Forever dungeons. |
| **`AI_VoiceOver`** | **AI Narration Core** | Immersive voice narration for quest text while managing bank alt logistics. |

> **Note on Leatrix Plus (LTP):** Omitted by design. `ZeroMaint` natively implements all layout containment, vendor auto-repair, junk selling, fast auto-looting, and CVar enforcement without framework bloat or race conditions.

---

## 🚀 Quick Start (1-Click Deployment)

### 1. Deploy All Addons
Run PowerShell as Administrator or regular user:
```powershell
.\install.ps1
```
*Automatically detects `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` and deploys all 6 addons.*

### 2. Launch Dual Clients & Second-Monitor HUD
```powershell
.\launch.ps1
```
- **Monitor 1 (5120x1440 Super Ultra-Wide):** Snaps `WoW1` (Main Mage) borderless fullscreen.
- **Monitor 2 (Secondary 1920x1080 / Laptop Display):** 
  - Left Half: Snaps `WoW2` (Ironforge Bank Mule).
  - Right Half: Opens the interactive `LAUNCH_HUD.html` Command Center.

---

## 🎛️ Command Center Features

Located inside `Command_Center/`:

- **Interactive Second-Monitor HUD (`Dashboard/LAUNCH_HUD.html`):**
  - **Live Umeå Bio-Clock:** Highlights active biological phases (04:00 Fasted APM, 14:00 Slurry, 17:00 Solid plate, pulsing red 18:00 Hard Fluid Cutoff, 19:30 Ceasefire).
  - **1900K Amber Eye-Safe Mode:** One-click toggle (and auto-after 19:30) shifting the HUD to zero-blue-light warm amber.
  - **Golden Asset Sticky Note:** Direct tracking of scarce mining/herbalism procs (*Pyrite, Bauxite, Frilled Lichen, Rosecap*), raid bottlenecks, and twink BoE blues.
  - **1–60 Leveling Corridor:** Checkable wand power spikes (Lesser/Greater Magic Wand, Gravestone Scepter, Icefury Wand) and 9 custom Forever dungeons.
  - **1-Click Clipboard Bank:** Instant copy buttons for TSM vendor arbitrage strings, fresh server snipers, GM COD pitches, and Trade Chat barks.

- **OBS Content & Thumbnail Watcher (`Media_Pipeline/clip_watcher.py`):**
  - Monitors `C:/WoWClips` for OBS Replay Buffer captures (triggered via Logitech G600 hotkey).
  - Extracts 4K action frames via `ffmpeg` and generates high-CTR 1280x720 YouTube thumbnails with golden headers and dynamic rotating hooks using `Pillow`.
  - Generates ready-to-upload metadata JSON.

- **Pre-Built Macro Caches (`Config_Templates/`):**
  - `macros-cache-main.txt`: Reticle `@cursor` Blizzard & Flamestrike, dual-gathering tracker (`/castsequence !Find Herbs, !Find Minerals`), panic stopcast Ice Block, and disengage Polymorph.
  - `macros-cache-bankalt.txt`: Trade Chat COD buyer barks, speedrunner `/who` radar, and instant dungeon reset macros.
  - `TSM_And_G600_Config.txt`: Logitech G600 G-HUB mapping and TSM shopping/sniper strings.

---

## 📜 In-Game Slash Commands

| Command | Addon | Action |
| :--- | :--- | :--- |
| `/fgbank <Name>` | ForeverGoblin | Lock in target bank alt (automatically syncs with `ZeroMaint`). |
| `/fgmail` | ForeverGoblin | 1-Click Mail Dump: Attaches up to 12 scarce/green+ items to bank alt and sends mail. |
| `/sendboe` (or `/z mail`) | ZeroMaint | 1-Click BoE Mailer: Dispatches unbound BoE gear to bank alt. |
| `/fgroute` | ForeverGoblin | Loads all 12 Winterspring Outer Rim dual-gathering waypoints into TomTom. |
| `/fgnight` | ForeverGoblin | Bedtime downshift: Disables floating combat text before 20:30 sleep. |
| `/fgday` | ForeverGoblin | Restores floating combat text for 04:00 AM fasted APM window. |
| `/z` | ZeroMaint | Access ZeroMaint configuration menu and layout controls. |

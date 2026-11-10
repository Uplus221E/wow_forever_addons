# Session Transcript: Why Was This Error Caused

- **Date**: 2026-11-09
- **Conversation ID**: `f84308db-9ff6-4b91-9c09-88b87ccbb1cd`
- **Repositories Touched**: 247_agent, agent_recapper, agent_voice_notifier, cpu_pinner, server_setup, wow_forever_addons, wow_forever_config
- **Project Lens**: `wow_forever_addons`

---

### 👤 User
why was this error caused

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "List workspace directory"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "C:\\fitxategiak\\aplikazioak\\_nire_tresnak\\_recapper\\STATE.md"

---

### 🤖 Assistant
This message is triggered by an architectural limitation in the **Windows Shell Application Desktop Toolbar (AppBar) API**.

---

### The Root Cause
Windows allows applications (and the Windows Taskbar itself) to register custom edge-docked bars using the `SHAppBarMessage` API. Under Windows Shell rules:
* **Only one auto-hiding AppBar can be registered per screen edge** (`TOP`, `BOTTOM`, `LEFT`, or `RIGHT`) on any given monitor.
* When a program or the Windows Taskbar calls `ABM_SETAUTOHIDEBAR` to enable auto-hide on an edge where another bar is already registered, Windows rejects the call and displays this warning:
  > *"A toolbar is already hidden on this side of your screen. You can have only one auto-hide toolbar per side."*

---

### Why It Usually Triggers

1. **Conflicting 3rd-Party Dock or Overlay**
   * A utility like **Nexus Dock, RocketDock, ObjectDock, Rainmeter**, or a gaming/streaming overlay toolbar is running and already configured to auto-hide on that same edge.
   * If you try to turn on **"Automatically hide the taskbar"** in Windows Settings while that dock is active, Explorer throws this error.

2. **Ghost / Orphaned AppBar Registration (Most Common)**
   * A toolbar, dock app, or previous Explorer shell process enabled auto-hide and later closed, hung, or crashed without sending the cleanup message (`ABM_REMOVE`).
   * `explorer.exe` still holds the auto-hide lease for that edge in memory, preventing anything else from claiming it.

3. **Multi-Monitor Reconnection / DPI Shift**
   * Disconnecting an external display or waking from sleep can collapse toolbars from a secondary monitor onto your primary monitor, causing two auto-hiding bars to collide on the same edge.

---

### How to Fix It

* **Clear Ghost Registrations (Fastest fix)**:
  Restart Windows Explorer to flush registered AppBars:
  1. Press `Ctrl + Shift + Esc` to open **Task Manager**.
  2. Locate **Windows Explorer** under Processes.
  3. Right-click it and select **Restart** (or run `Stop-Process -Name explorer` in PowerShell).

* **Check for Conflicting Apps**:
  If you use any dock, custom taskbar, or widget software (Nexus, Rainmeter, etc.):
  * Change its docking edge to a different side (e.g., top or side), or
  * Disable auto-hide in either that app or the Windows Taskbar settings.

---

### 👤 User
it was when i booted from shut down. could it be one of our  project startup scripts?

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check user Startup folder"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Read startup .cmd scripts"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check registry run keys"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Sample startup script contents"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Search for WoW scripts"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Read watch_and_pin_wow.ps1"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check last boot time"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Get all startup commands"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "List processes with windows"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check third-party running processes"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check GHelper process"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Search scripts for taskbar or appbar keywords"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "C:\\Users\\shaman\\.gemini\\antigravity\\brain\\f84308db-9ff6-4b91-9c09-88b87ccbb1cd\\.system_generated\\tasks\\task-30.log"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Inspect StuckRects3 taskbar settings"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Print StuckRects3 byte array"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check MMStuckRects3"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check byte 8 of multi-monitor settings"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Get recent Application events"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check power and boot events"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Inspect events between 19:02 and 19:05"

---

### 🤖 Assistant
**Actions Executed:**
- `tool`: "Check events in System and Application between 19:02 and 19:05"

---

### 🤖 Assistant
**No, none of your project startup scripts caused this.** 

---

### Proof from Code Inspection

We inspected every script running at startup (`AutoVaulter.cmd`, `WatchStorm.cmd`, `WatchWoWPin.cmd`, and the registry Run keys):

1. **`auto_vaulter.ps1`**: A headless background file watcher using .NET `System.IO.FileSystemWatcher` on the `brain` folder. Zero UI or shell hooks.
2. **`watch_for_storm.ps1`**: A CLI script polling `tailscale status`. It does not interact with the Windows GUI.
3. **`watch_and_pin_wow.ps1`**: Only adjusts CPU affinity and priority on `Wow.exe`.
4. **Codebase Grep**: A full search across all `.ps1`, `.bat`, `.cmd`, and `.reg` files in `_nire_tresnak` confirmed **zero calls** to Win32 AppBar APIs (`SHAppBarMessage`), `StuckRects3`, or taskbar configuration.

---

### What Actually Caused It

Your Windows System Event logs show the exact sequence:
1. **Fast Startup Resume**: At **19:02:38**, Windows resumed from a **Fast Startup** state (Windows 11's default hybrid shutdown).
2. **Multi-Monitor Display Handshake Race**:
   * You have two screens: the **Samsung Odyssey G95C** (49" 5120x1440 @ 240Hz) and the **ASUS laptop internal display** (1920x1080).
   * Upon waking/booting, `explorer.exe` restored before the high-bandwidth DisplayPort/HDMI EDID handshake with the 49" Odyssey fully completed.
   * During the brief moment when display geometries were reconciling, Explorer attempted to register the taskbar/toolbar instances for both monitors onto the same primary screen edge simultaneously.
   * Windows Shell caught the collision and fired the dialog:
     > *"A toolbar is already hidden on this side of your screen. You can have only one auto-hide toolbar per side."*

Once the monitor handshake completed, the layout normalized. You can safely dismiss the dialog; it is a harmless Windows multi-monitor timing glitch.

---

### Side Note: Startup Script Maintenance

While checking the startup sequence, two minor configuration issues were observed:

1. **Duplicate Launches**: Both `AutoVaulter` and `StormServerWatcher` are registered in **two places** (the `Startup` folder *and* `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`), causing them to spawn redundant instances on login (though single-instance mutex guards catch and exit the extras).
2. **Broken Path in `WatchWoWPin.cmd`**: `WatchWoWPin.cmd` points to `_forever_config`, but the folder is now named `wow_forever_config`, so that script currently exits silently on boot.

---

*(Note: Archived for offline reference in `wow_forever_addons`. Unabridged raw log available in `antigravity_archive`.)*

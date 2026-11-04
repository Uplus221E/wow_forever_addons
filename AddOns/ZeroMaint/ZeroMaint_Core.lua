--[[
    ZeroMaint - Core Architecture & Universal Compatibility Foundation
    File: ZeroMaint_Core.lua
    
    Responsibilities:
      1. Initializes shared addon namespace (addonName, ns) across all pillars.
      2. Fault-isolated event dispatcher using protected xpcall execution.
      3. Recursive deep-merge database schema initialization (ZeroMaintDB).
      4. Universal cross-client polyfills (Vanilla 1.12.1 -> Retail 11.0+).
      5. Shared mathematical & coordinate utilities (16:9 safe zone, scale normalizer).
      6. Table-driven slash command router (/z, /zerores).
]]

local addonName, ns = ...
ns = ns or {}
_G["ZeroMaint_NS"] = ns
ns.name = addonName or "ZeroMaint"

-- Pillar Sub-Namespaces
ns.Layout = ns.Layout or {}
ns.QoL = ns.QoL or {}
ns.Profiles = ns.Profiles or {}
ns.Mail = ns.Mail or {}

--------------------------------------------------------------------------------
-- 1. UNIVERSAL COMPATIBILITY POLYFILL ENGINE (Vanilla 1.12.1 -> Retail 11.0+)
--------------------------------------------------------------------------------

-- 1.1 'print()' Polyfill (Added in WoW 3.0.2 WotLK; absent in Vanilla 1.12 & TBC 2.4.3)
if not print then
    print = function(...)
        local msg = ""
        local n = (arg and arg.n) or (select and select("#", ...)) or 0
        if n == 0 and ... ~= nil then
            msg = tostring(...)
        else
            for i = 1, n do
                local val = (arg and arg[i]) or (select and select(i, ...))
                msg = msg .. (i > 1 and " " or "") .. tostring(val)
            end
        end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    end
end
ns.print = print

-- 1.2 'InCombatLockdown()' Polyfill (Added in WoW 2.0 TBC; absent in Vanilla 1.12)
if not InCombatLockdown then
    InCombatLockdown = function()
        return (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    end
end
ns.InCombatLockdown = InCombatLockdown

-- 1.3 'hooksecurefunc()' Polyfill (Added in WoW 2.0 TBC; absent in Vanilla 1.12)
if not hooksecurefunc then
    hooksecurefunc = function(arg1, arg2, arg3)
        if type(arg1) == "string" then
            local orig = _G[arg1]
            if orig then
                _G[arg1] = function(...)
                    orig(...)
                    return arg2(...)
                end
            end
        elseif type(arg1) == "table" and type(arg2) == "string" and type(arg3) == "function" then
            local orig = arg1[arg2]
            if orig then
                arg1[arg2] = function(...)
                    orig(...)
                    return arg3(...)
                end
            end
        end
    end
end
ns.hooksecurefunc = hooksecurefunc

-- 1.4 'string.match()' Polyfill (Lua 5.1 feature; absent in Vanilla 1.12 Lua 5.0)
if not string.match then
    string.match = function(str, pattern, init)
        local s, e, c1, c2, c3, c4 = string.find(str, pattern, init)
        if not s then return nil end
        if c1 then return c1, c2, c3, c4 end
        return string.sub(str, s, e)
    end
end

-- 1.5 'C_Timer.After()' Polyfill (Added in WoW 6.0 WoD; absent in 1.12 -> 5.4 MoP)
if not C_Timer then C_Timer = {} end
if not C_Timer.After then
    local timerFrame = CreateFrame("Frame")
    local timers = {}
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        local i = 1
        while i <= #timers do
            local t = timers[i]
            t.delay = t.delay - elapsed
            if t.delay <= 0 then
                table.remove(timers, i)
                pcall(t.func)
            else
                i = i + 1
            end
        end
        if #timers == 0 then
            timerFrame:Hide()
        end
    end)
    timerFrame:Hide()
    C_Timer.After = function(delay, func)
        if type(func) ~= "function" then return end
        table.insert(timers, { delay = tonumber(delay) or 0, func = func })
        timerFrame:Show()
    end
end

-- 1.6 Solid Color Texture Setter (Safe alternative to Texture metatable injection)
local function SetSolidColor(tex, r, g, b, a)
    if not tex then return end
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a or 1)
    else
        tex:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        if r and g and b then
            tex:SetVertexColor(r, g, b, a or 1)
        end
    end
end
ns.SetSolidColor = SetSolidColor

-- 1.7 Universal Item Info Safe Wrapper (Cross-client C_Item vs GetItemInfo)
local function SafeGetItemInfo(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    elseif GetItemInfo then
        return GetItemInfo(item)
    end
    return nil
end
ns.SafeGetItemInfo = SafeGetItemInfo

-- 1.8 CVar Safe Setter Wrapper (Cross-client C_CVar vs SetCVar)
local function SafeSetCVar(cvar, value)
    if C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, cvar, tostring(value))
    elseif SetCVar then
        pcall(SetCVar, cvar, tostring(value))
    end
end
ns.SafeSetCVar = SafeSetCVar

-- 1.9 Currency Formatter (Copper -> Gold, Silver, Copper)
local function FormatMoney(amount)
    if not amount or amount <= 0 then return "0c" end
    if GetCoinTextureString then
        return GetCoinTextureString(amount)
    end
    local g = math.floor(amount / 10000)
    local s = math.floor((amount % 10000) / 100)
    local c = amount % 100
    if g > 0 then
        return string.format("%dg %ds %dc", g, s, c)
    elseif s > 0 then
        return string.format("%ds %dc", s, c)
    else
        return string.format("%dc", c)
    end
end
ns.FormatMoney = FormatMoney

-- 1.10 Universal Container Wrappers (Supports Vanilla 1.12 -> Dragonflight/Retail C_Container)
local function GetNumBagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end
ns.GetNumBagSlots = GetNumBagSlots

local function GetBagItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            local q = info.quality
            local l = info.hyperlink or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot))
            if (not q or q == -1) and l then
                local _, _, itemQuality = SafeGetItemInfo(l)
                q = itemQuality
            end
            return q, l, info.hasNoValue, info.isLocked, info.stackCount
        end
        return nil
    elseif GetContainerItemInfo then
        local texture, count, locked, quality, readable, lootable, link, isFiltered, noValue = GetContainerItemInfo(bag, slot)
        if texture then
            if not link and GetContainerItemLink then
                link = GetContainerItemLink(bag, slot)
            end
            if (not quality or quality == -1) and link then
                local _, _, itemQuality = SafeGetItemInfo(link)
                quality = itemQuality
            end
            return quality, link, noValue, locked, count
        end
    end
    return nil
end
ns.GetBagItemInfo = GetBagItemInfo

local function UseBagItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    elseif UseContainerItem then
        UseContainerItem(bag, slot)
    end
end
ns.UseBagItem = UseBagItem

-- 1.11 Scale Normalization Helper
local function GetEffectiveOffset(frame, offset)
    local fScale = (frame and frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if fScale <= 0 then fScale = 1 end
    local pScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    return offset * (pScale / fScale)
end
ns.GetEffectiveOffset = GetEffectiveOffset

-- 1.12 Metrics Calculation (Zero-Allocation Cached Metrics)
local cachedMetrics = {
    parentWidth  = 1920,
    parentHeight = 1080,
    aspect       = 16 / 9,
    safeWidth    = 1920,
    safeHeight   = 1080,
    hOffset      = 0,
}

local function GetMetrics()
    local parentWidth = (UIParent and UIParent:GetWidth()) or 1920
    local parentHeight = (UIParent and UIParent:GetHeight()) or 1080
    local aspect = parentWidth / parentHeight

    local safeWidth = parentWidth
    local safeHeight = parentHeight
    local hOffset = 0

    local config = ns.db or ns.defaults
    local targetAspect = (config and config.targetAspect) or (16 / 9)
    local clamp = (config and (config.clampAllTo16x9 or config.enableSafeZone)) ~= false

    if clamp and aspect > targetAspect then
        safeWidth = parentHeight * targetAspect
        safeHeight = parentHeight
        hOffset = (parentWidth - safeWidth) / 2
    end

    cachedMetrics.parentWidth  = parentWidth
    cachedMetrics.parentHeight = parentHeight
    cachedMetrics.aspect       = aspect
    cachedMetrics.safeWidth    = safeWidth
    cachedMetrics.safeHeight   = safeHeight
    cachedMetrics.hOffset      = hOffset

    return cachedMetrics
end
ns.GetMetrics = GetMetrics

--------------------------------------------------------------------------------
-- 2. DEFAULT CONFIGURATION SCHEMA (Merged from Monolith)
--------------------------------------------------------------------------------

local defaults = {
    -- Pillar 1: Streamer Safe Zone & Layout
    clampAllTo16x9         = true,     -- Strictly contain ALL UI in 16:9 safe zone for streaming
    enableSafeZone         = true,     -- Alias for safe zone containment
    targetAspect           = 16 / 9,   -- 1.77777777778
    minimapPosition        = "bottom", -- "bottom" (bottom-right safe zone) or "top" (top-right safe zone)
    showBorder             = false,    -- Restore border overlay across reloads

    -- Pillar 2: Native QoL Automations (Leatrix Plus replacement)
    autoRepair             = true,     -- Automatically repair equipment at vendors
    autoRepairGuild        = true,     -- Use guild bank funds for repair if permitted
    useGuildRepair         = true,     -- Alias for guild repair
    autoSellGrays          = true,     -- Automatically sell gray/poor quality junk items
    autoVendor             = true,     -- Alias for auto-selling junk
    fasterLoot             = true,     -- Instant auto-looting without Blizzard UI delay
    hideLootFrame          = true,     -- Suppress loot window during auto-loot (SpeedyAutoLoot vacuum mode)
    enforceCVars           = true,     -- Enforce maximum camera, instant quest text, auto-loot, etc.
    maxCameraZoom          = true,     -- Enforce max camera zoom factor
    silenceUIErrors        = true,     -- Silence red "Spell is not ready yet" center combat text

    -- Core HUD Offsets relative to UIParent CENTER
    player   = { x = -240, y = -160 },
    target   = { x =  240, y = -160 },
    focus    = { x = -450, y =  -80 },
    tot      = { x =  410, y = -160 },
    pet      = { x = -240, y = -240 },
    castBar  = { x =    0, y = -210 },

    -- Peripherals & Safe-Zone Elements (Offsets relative to their Safe-Zone Docking Anchors)
    bags     = { x = -15, y = 305 }, -- Relative to safe-zone BOTTOMRIGHT (clears round minimap)
    minimap  = { x = -15, y =  35 }, -- Relative to safe-zone corner (BOTTOMRIGHT or TOPRIGHT)
    chat     = { x =  35, y =  45 }, -- Relative to safe-zone BOTTOMLEFT
    tracker  = { x = -20, y = -220 }, -- Relative to safe-zone TOPRIGHT (clears top buffs & debuffs)
    tooltip  = { x = -20, y = 310 }, -- Relative to safe-zone BOTTOMRIGHT
    buffs    = { x = -15, y = -13 }, -- Relative to safe-zone TOPRIGHT (or left of top-docked minimap)
    party    = { x =  20, y = -160 }, -- Relative to safe-zone TOPLEFT (PartyFrame / PartyMemberFrame1)
    raid     = { x =   0, y = -140 }, -- Relative to safe-zone TOPLEFT (CompactRaidFrameManager)
    boss     = { x = -40, y = -260 }, -- Relative to safe-zone TOPRIGHT
    arena    = { x = -40, y =    0 }, -- Relative to safe-zone RIGHT

    -- Pillar 3: Saved Action Bar, Keybind & Macro Profiles
    profiles = {},

    -- Pillar 4: Native Mail Automation & Bank Alt Pipeline (Postal replacement)
    bankAlt                = "",       -- Configured bank alt recipient name
    mailMinQuality         = 2,        -- Minimum item quality: 2=Uncommon (Green), 3=Rare (Blue), 4=Epic (Purple)
    mailAutoSend           = false,    -- Auto-send mail immediately or leave open for 1-click confirmation
}
ns.defaults = defaults
ns.DefaultConfig = defaults
ns.db = defaults
ns.Config = defaults

--------------------------------------------------------------------------------
-- 3. RECURSIVE DEEP-MERGE FOR SAVEDVARIABLES
--------------------------------------------------------------------------------

local function MergeDefaults(src, dst)
    if type(src) ~= "table" then return {} end
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = MergeDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.MergeDefaults = MergeDefaults

--------------------------------------------------------------------------------
-- 4. FAULT-TOLERANT EVENT DISPATCHER
--------------------------------------------------------------------------------

ns.eventFrame = CreateFrame("Frame", "ZeroMaint_EventFrame")
ns.events = {}

local function ErrorHandler(err)
    print("|cffff3333[ZeroMaint Error]|r Module failed but was isolated:\n", err)
end
ns.ErrorHandler = ErrorHandler

ns.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = ns.events[event]
    if not handlers then return end
    local count = #handlers
    if count == 1 then
        xpcall(handlers[1], ErrorHandler, event, ...)
    elseif count > 1 then
        local list = {}
        for i = 1, count do
            list[i] = handlers[i]
        end
        for i = 1, count do
            if list[i] then
                xpcall(list[i], ErrorHandler, event, ...)
            end
        end
    end
end)

function ns.RegisterEvent(event, handler)
    if not ns.events[event] then
        ns.events[event] = {}
        ns.eventFrame:RegisterEvent(event)
    end
    table.insert(ns.events[event], handler)
end

function ns.UnregisterEvent(event, handler)
    local handlers = ns.events[event]
    if not handlers then return end
    for i = #handlers, 1, -1 do
        if handlers[i] == handler then
            table.remove(handlers, i)
        end
    end
    if #handlers == 0 then
        ns.events[event] = nil
        ns.eventFrame:UnregisterEvent(event)
    end
end

--------------------------------------------------------------------------------
-- 5. DATABASE INITIALIZATION & MODULE LIFECYCLE
--------------------------------------------------------------------------------

local function OnAddonLoaded(arg1, arg2)
    local loadedAddon = (arg1 == "ADDON_LOADED") and arg2 or arg1
    if loadedAddon ~= (ns.name or addonName) then return end
    ZeroMaintDB = MergeDefaults(defaults, ZeroMaintDB)
    if ZeroMaintDB.enableSafeZone ~= nil then ZeroMaintDB.clampAllTo16x9 = ZeroMaintDB.enableSafeZone end
    if ZeroMaintDB.useGuildRepair ~= nil then ZeroMaintDB.autoRepairGuild = ZeroMaintDB.useGuildRepair end
    if ZeroMaintDB.autoVendor ~= nil then ZeroMaintDB.autoSellGrays = ZeroMaintDB.autoVendor end
    if ZeroMaintDB.maxCameraZoom ~= nil then ZeroMaintDB.enforceCVars = ZeroMaintDB.maxCameraZoom end
    ns.db = ZeroMaintDB
    ns.Config = ZeroMaintDB
    ns.UnregisterEvent("ADDON_LOADED", OnAddonLoaded)

    if ns.OnInitialize then
        for _, initFunc in ipairs(ns.OnInitialize) do
            xpcall(initFunc, ErrorHandler)
        end
    end
end
ns.RegisterEvent("ADDON_LOADED", OnAddonLoaded)

function ns.RegisterInit(func)
    ns.OnInitialize = ns.OnInitialize or {}
    table.insert(ns.OnInitialize, func)
end

--------------------------------------------------------------------------------
-- 6. TABLE-DRIVEN SLASH COMMAND ROUTER (/z, /zerores)
--------------------------------------------------------------------------------

ns.commands = {}

-- 6.1 Pillar 3: Profile Commands
ns.commands["save"] = function(arg1, arg2, arg3)
    if ns.Profiles.SnapshotProfile then
        ns.Profiles.SnapshotProfile((arg1 ~= "" and arg1) or nil)
    end
end

ns.commands["load"] = function(arg1, arg2, arg3)
    if ns.Profiles.RestoreProfile then
        ns.Profiles.RestoreProfile((arg1 ~= "" and arg1) or nil)
    end
end
ns.commands["restore"] = ns.commands["load"]

ns.commands["list"] = function(arg1, arg2, arg3)
    if ns.Profiles.ListProfiles then
        ns.Profiles.ListProfiles()
    end
end
ns.commands["profiles"] = ns.commands["list"]

ns.commands["delete"] = function(arg1, arg2, arg3)
    if ns.Profiles.DeleteProfile then
        ns.Profiles.DeleteProfile((arg1 ~= "" and arg1) or nil)
    end
end
ns.commands["del"] = ns.commands["delete"]
ns.commands["remove"] = ns.commands["delete"]

-- 6.2 Pillar 1: Layout & Safe-Zone Commands
ns.commands["border"] = function(arg1, arg2, arg3)
    if ns.Layout.ToggleBorder then
        ns.Layout.ToggleBorder()
    end
end

ns.commands["minimap"] = function(arg1, arg2, arg3)
    if ns.Layout.SetMinimapPosition then
        ns.Layout.SetMinimapPosition(arg1)
    end
end

ns.commands["move"] = function(arg1, arg2, arg3)
    if ns.Layout.HandleMoveCommand then
        ns.Layout.HandleMoveCommand(arg1, arg2, arg3)
    end
end
ns.commands["pos"] = ns.commands["move"]
ns.commands["hud"] = ns.commands["move"]
ns.commands["set"] = ns.commands["move"]

ns.commands["toggle"] = function(arg1, arg2, arg3)
    if ns.Layout.ToggleSafeZone then
        ns.Layout.ToggleSafeZone()
    end
end

-- 6.3 Pillar 2: QoL Automation Commands
ns.commands["repair"] = function(arg1, arg2, arg3)
    if ns.QoL.ToggleAutoRepair then
        ns.QoL.ToggleAutoRepair()
    end
end

ns.commands["sell"] = function(arg1, arg2, arg3)
    if ns.QoL.ToggleAutoSell then
        ns.QoL.ToggleAutoSell()
    end
end

ns.commands["fastloot"] = function(arg1, arg2, arg3)
    if ns.QoL.ToggleFastLoot then
        ns.QoL.ToggleFastLoot()
    end
end
ns.commands["loot"] = ns.commands["fastloot"]

ns.commands["hideloot"] = function(arg1, arg2, arg3)
    if ns.QoL.ToggleHideLootFrame then
        ns.QoL.ToggleHideLootFrame()
    end
end

ns.commands["cvars"] = function(arg1, arg2, arg3)
    if ns.QoL.ToggleCVars then
        ns.QoL.ToggleCVars()
    end
end

ns.commands["speedrun"] = function(arg1, arg2, arg3)
    if ns.QoL and ns.QoL.ApplyCVars then
        ns.QoL.ApplyCVars()
        print("|cff00ccff[ZeroMaint]|r Speedrun & Graphics CVars: |cff00ff00EXECUTED & ENFORCED|r")
    end
end
ns.commands["graphics"] = ns.commands["speedrun"]

ns.commands["errors"] = function(arg1, arg2, arg3)
    if ns.QoL.ToggleUIErrors then
        ns.QoL.ToggleUIErrors()
    end
end

-- 6.4 Pillar 4: Mail & Bank Alt Commands
ns.commands["mail"] = function(arg1, arg2, arg3)
    if ns.Mail and ns.Mail.HandleCommand then
        ns.Mail.HandleCommand(arg1, arg2, arg3)
    end
end

ns.commands["sendboe"] = function(arg1, arg2, arg3)
    if ns.Mail and ns.Mail.SendBoE then
        ns.Mail.SendBoE((arg1 ~= "" and arg1) or nil)
    end
end
ns.commands["boe"] = ns.commands["sendboe"]

ns.commands["setalt"] = function(arg1, arg2, arg3)
    if ns.Mail and ns.Mail.SetBankAlt then
        ns.Mail.SetBankAlt(arg1)
    end
end
ns.commands["bankalt"] = ns.commands["setalt"]
ns.commands["mailalt"] = ns.commands["setalt"]

ns.commands["mailquality"] = function(arg1, arg2, arg3)
    if ns.Mail and ns.Mail.SetMinQuality then
        ns.Mail.SetMinQuality(arg1)
    end
end

ns.commands["mailautosend"] = function(arg1, arg2, arg3)
    if ns.Mail and ns.Mail.ToggleAutoSend then
        ns.Mail.ToggleAutoSend()
    end
end

ns.commands["mailstatus"] = function(arg1, arg2, arg3)
    if ns.Mail and ns.Mail.PrintStatus then
        ns.Mail.PrintStatus()
    end
end

ns.commands["mailscan"] = function(arg1, arg2, arg3)
    if ns.Mail and ns.Mail.PreviewBoE then
        ns.Mail.PreviewBoE()
    end
end

-- 6.5 System & Utility Commands
ns.commands["reset"] = function(arg1, arg2, arg3)
    local savedProfiles = ZeroMaintDB and ZeroMaintDB.profiles
    ZeroMaintDB = {}
    ZeroMaintDB = MergeDefaults(defaults, ZeroMaintDB)
    if savedProfiles then
        ZeroMaintDB.profiles = savedProfiles
    end
    ns.db = ZeroMaintDB
    ns.Config = ZeroMaintDB
    if ns.Layout and ns.Layout.Reset then
        ns.Layout.Reset()
    end
    if ns.QoL and ns.QoL.Reset then
        ns.QoL.Reset()
    end
    if ns.Mail and ns.Mail.Reset then
        ns.Mail.Reset()
    end
    print("|cff00ccff[ZeroMaint]|r Configuration reset to factory defaults (profiles preserved).")
end

ns.commands["debug"] = function(arg1, arg2, arg3)
    if ns.Layout and ns.Layout.RealignAllUI then
        ns.Layout.RealignAllUI()
    end
    local m = GetMetrics()
    local db = ns.db or defaults
    print(string.format("|cff00ccff[ZeroMaint Debug]|r Display: %.0fx%.0f | Safe-Zone: %.0fx%.0f | Offset: %.0f | Minimap Pos: %s",
        m.parentWidth, m.parentHeight, m.safeWidth, m.safeHeight, m.hOffset, db.minimapPosition))
    if ns.Layout and ns.Layout.PrintDebug then
        ns.Layout.PrintDebug()
    end
    if ns.QoL and ns.QoL.PrintDebug then
        ns.QoL.PrintDebug()
    end
    if ns.Mail and ns.Mail.PrintDebug then
        ns.Mail.PrintDebug()
    end
    print(string.format("EditMode: SystemMixin=%s, Manager=%s | SavedDB: %s", 
        tostring(EditModeSystemMixin ~= nil), tostring(EditModeManagerFrame ~= nil), tostring(ZeroMaintDB ~= nil)))
end

ns.commands["help"] = function(arg1, arg2, arg3)
    local m = GetMetrics()
    local db = ns.db or defaults
    print(string.format("|cff00ccff[ZeroMaint]|r UIParent: %.0fx%.0f (Aspect: %.2f:1) | Margin: %.0f units | Minimap: %s-right", 
        m.parentWidth, m.parentHeight, m.aspect, m.hOffset, db.minimapPosition))
    if ns.Layout and ns.Layout.RealignAllUI then
        ns.Layout.RealignAllUI()
    end
    print("|cff00ccff[ZeroMaint]|r Commands:")
    print("  |cffffd100/z save <profile>|r - Snapshot action bars, keybinds & macros to WTF")
    print("  |cffffd100/z load <profile>|r - Restore action bars, keybinds & macros from WTF")
    print("  |cffffd100/z list|r           - List all saved profiles")
    print("  |cffffd100/z delete <profile>|r - Delete saved profile from WTF")
    print("  |cffffd100/z move [player|target|focus|tot|pet|castbar] <X> <Y>|r - Reposition HUD frame (auto-saved to WTF)")
    print("  |cffffd100/z minimap [top|bottom]|r - Toggle or set minimap position (auto-saved to WTF)")
    print("  |cffffd100/z border|r   - Toggle cyan 16:9 OBS crop boundary (auto-saved to WTF)")
    print("  |cffffd100/z fastloot|r - Toggle instant faster auto-looting ON/OFF (auto-saved to WTF)")
    print("  |cffffd100/z hideloot|r - Toggle suppressing loot window ON/OFF (auto-saved to WTF)")
    print("  |cffffd100/z repair|r   - Toggle vendor auto-repair ON/OFF (auto-saved to WTF)")
    print("  |cffffd100/z sell|r     - Toggle vendor auto-sell grays ON/OFF (auto-saved to WTF)")
    print("  |cffffd100/z cvars|r    - Toggle or re-apply native CVar enforcements (auto-saved to WTF)")
    print("  |cffffd100/z errors|r   - Toggle silencing red combat error text (auto-saved to WTF)")
    print("  |cffffd100/sendboe [alt]|r   - Auto-attach and mail BoEs to bank alt")
    print("  |cffffd100/z setalt <name>|r - Set default bank alt for auto-mailing (auto-saved to WTF)")
    print("  |cffffd100/z mail [scan|status|autosend|quality]|r - Mail pipeline controls")
    print("  |cffffd100/z toggle|r   - Toggle safe zone clamping ON/OFF (auto-saved to WTF)")
    print("  |cffffd100/z reset|r    - Reset all settings back to factory defaults")
    print("  |cffffd100/z debug|r    - Print live frame coordinates and status")
end

-- 6.6 Slash Registration & Dispatcher
SLASH_ZERORES1 = "/z"
SLASH_ZERORES2 = "/zerores"
SLASH_ZERORES3 = "/zeromaint"
SlashCmdList["ZERORES"] = function(msg)
    local rawCmd, rawArg1, rawArg2, rawArg3 = (msg or ""):match("^%s*(%S+)%s*(%S*)%s*(%S*)%s*(%S*)")
    local cmd = (rawCmd or ""):lower()
    local handler = ns.commands[cmd]
    if handler then
        xpcall(function()
            handler(rawArg1 or "", rawArg2 or "", rawArg3 or "", msg)
        end, ErrorHandler)
    else
        xpcall(function()
            ns.commands["help"](rawArg1 or "", rawArg2 or "", rawArg3 or "", msg)
        end, ErrorHandler)
    end
end

-- Dedicated /sendboe Slash Shortcut
SLASH_SENDBOE1 = "/sendboe"
SlashCmdList["SENDBOE"] = function(msg)
    local target = (msg or ""):match("^%s*(%S*)")
    if target:lower() == "help" or target == "?" then
        if ns.Mail and ns.Mail.HandleCommand then
            ns.Mail.HandleCommand("help")
        end
        return
    end
    if ns.Mail and ns.Mail.SendBoE then
        xpcall(function()
            ns.Mail.SendBoE((target ~= "" and target) or nil)
        end, ErrorHandler)
    else
        print("|cff00ccff[ZeroMaint]|r Mail module is not loaded.")
    end
end

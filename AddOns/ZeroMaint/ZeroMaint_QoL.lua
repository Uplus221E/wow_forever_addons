--[[
    ZeroMaint - Native QoL Automations & Ergonomics (Pillar 2)
    File: ZeroMaint_QoL.lua
    
    Responsibilities:
      1. Vendor auto-repair (personal gold and guild bank support).
      2. Vendor auto-sell junk (C_MerchantFrame.SellAllJunkItems with throttled fallback).
      3. Instant faster auto-looting with optional loot window suppression (vacuum mode).
      4. Native CVar enforcement (camera distance, auto-loot, instant quest text, graphics glow).
      5. Red combat error text suppression (UIErrorsFrame).
]]

local addonName, ns = ...
local QoL = ns.QoL or {}
ns.QoL = QoL

--------------------------------------------------------------------------------
-- 1. NATIVE CVAR ENFORCEMENTS & COMBAT ERROR SUPPRESSION
--------------------------------------------------------------------------------

local function ApplyCVars()
    local db = ns.db or ns.defaults

    -- Silence Red UI Combat Error Messages ("Spell is not ready yet", "Out of range")
    if UIErrorsFrame then
        if db.silenceUIErrors then
            UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        else
            UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        end
    end

    if not (db.enforceCVars or db.maxCameraZoom) then return end

    -- Instant Looting & Cursor Ergonomics
    ns.SafeSetCVar("autoLootDefault", "1")
    ns.SafeSetCVar("lootUnderMouse", "1")

    -- Instant Quest Text Display (Suppresses typewriter effect)
    ns.SafeSetCVar("instantQuestText", "1")

    -- Maximum Situational Camera Distance
    -- Modern WoW (Retail / Classic Era / Beta 1.60)
    ns.SafeSetCVar("cameraDistanceMaxZoomFactor", "2.6")
    -- Legacy WoW (1.12.1 through 3.3.5a)
    ns.SafeSetCVar("cameraDistanceMaxFactor", "4")
    ns.SafeSetCVar("cameraDistanceMax", "50")

    -- Graphics Post-Processing (Remove eye-strain blur and grayscale death screen)
    ns.SafeSetCVar("ffxGlow", "0")
    ns.SafeSetCVar("ffxDeath", "0")
    ns.SafeSetCVar("ffxNether", "0")
    ns.SafeSetCVar("ffxAntiAliasingMode", "0")

    -- Zero-Grass & Ground Clutter Culling (Maximum Ground Item Visibility)
    ns.SafeSetCVar("groundEffectDist", "1")
    ns.SafeSetCVar("groundEffectDensity", "0")
    ns.SafeSetCVar("groundEffectFade", "0")
    ns.SafeSetCVar("graphicsGroundClutter", "1")
    ns.SafeSetCVar("graphicsEnvironmentDetail", "1")

    -- High Contrast, Sharpness & Atmospheric Clarity Preset
    ns.SafeSetCVar("Contrast", "65")
    ns.SafeSetCVar("Brightness", "50")
    ns.SafeSetCVar("Gamma", "1.0")
    ns.SafeSetCVar("ResampleAlwaysSharpen", "1")
    ns.SafeSetCVar("waterDetail", "0")
    ns.SafeSetCVar("weatherDensity", "0")
    ns.SafeSetCVar("volumeFog", "0")
    ns.SafeSetCVar("volumeFogLevel", "0")
    ns.SafeSetCVar("sunShafts", "0")
    ns.SafeSetCVar("shadowMode", "0")
    ns.SafeSetCVar("SSAO", "0")

    -- Silhouette Outlines & Projected Textures Guard
    ns.SafeSetCVar("graphicsOutlineMode", "2")
    ns.SafeSetCVar("OutlineEngineMode", "2")
    ns.SafeSetCVar("outlineModeShowLootEffectWhenDisabled", "1")
    ns.SafeSetCVar("graphicsProjectedTextures", "1")
    ns.SafeSetCVar("projectedTextures", "1")

    -- Speedrun Engine: Loading Preload, Latency, Camera & Physics
    ns.SafeSetCVar("worldPreloadNonCritical", "0")
    ns.SafeSetCVar("GxLowLatencyMode", "2")
    ns.SafeSetCVar("physicsLevel", "0")
    ns.SafeSetCVar("cameraWaterCollision", "0")
    ns.SafeSetCVar("cameraSmoothStyle", "0")
    ns.SafeSetCVar("cameraPivot", "0")
    ns.SafeSetCVar("spellVisualDensityFilterSetting", "0")
    ns.SafeSetCVar("spellClutter", "0")

    -- Soft-Targeting & Interact Key Engine
    ns.SafeSetCVar("SoftTargetInteract", "3")
    ns.SafeSetCVar("SoftTargetInteractArc", "2")
    ns.SafeSetCVar("SoftTargetInteractRange", "30")
    ns.SafeSetCVar("SoftTargetIconInteract", "1")
    ns.SafeSetCVar("TargetNearestUseNew", "1")

    -- Nameplate Bounds & Swarm Clarity
    ns.SafeSetCVar("nameplateTargetRadialPosition", "1")
    ns.SafeSetCVar("nameplateMotion", "1")
    ns.SafeSetCVar("nameplateShowEnemies", "1")
    ns.SafeSetCVar("nameplateShowEnemyMinus", "1")

    -- Suppress Lua Error Popups
    ns.SafeSetCVar("scriptErrors", "0")
end
QoL.ApplyCVars = ApplyCVars

--------------------------------------------------------------------------------
-- 2. VENDOR AUTOMATION: AUTO-REPAIR & AUTO-SELL
--------------------------------------------------------------------------------

local function OnMerchantShow()
    local db = ns.db or ns.defaults
    if not db then return end

    -- 2.1 Auto-Repair Equipment
    if db.autoRepair and CanMerchantRepair and CanMerchantRepair() then
        local cost, canRepair = GetRepairAllCost()
        if canRepair and cost and cost > 0 then
            local repaired = false
            local useGuild = (db.useGuildRepair or db.autoRepairGuild)
            if useGuild and CanGuildBankRepair and CanGuildBankRepair() and IsInGuild and IsInGuild() then
                local guildMoney = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or 0
                local guildTotal = (GetGuildBankMoney and GetGuildBankMoney()) or 0
                if (guildMoney == -1 or guildMoney >= cost) and guildTotal >= cost then
                    RepairAllItems(true)
                    repaired = true
                    local moneyStr = (GetMoneyString and GetMoneyString(cost, true)) or ns.FormatMoney(cost)
                    print(string.format("|cff00ff00[ZeroMaint]|r Guild repaired for %s", moneyStr))
                end
            end
            if not repaired and GetMoney and GetMoney() >= cost then
                RepairAllItems(false)
                local moneyStr = (GetMoneyString and GetMoneyString(cost, true)) or ns.FormatMoney(cost)
                print(string.format("|cff00ff00[ZeroMaint]|r Repaired for %s", moneyStr))
            elseif not repaired then
                local playerMoney = (GetMoney and GetMoney()) or 0
                print(string.format("|cff00ccff[ZeroMaint]|r Insufficient funds to repair (Cost: %s, Current: %s).", ns.FormatMoney(cost), ns.FormatMoney(playerMoney)))
            end
        end
    end

    -- 2.2 Auto-Sell Gray / Junk Items
    if db.autoVendor or db.autoSellGrays then
        -- 1. Try native Retail/Modern C_MerchantFrame batch API first
        if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
            local numJunk = (C_MerchantFrame.GetNumJunkItems and C_MerchantFrame.GetNumJunkItems()) or 1
            if numJunk > 0 then
                C_MerchantFrame.SellAllJunkItems()
                return
            end
        end

        -- 2. Universal throttled bag loop fallback (supports Retail, Classic, Vanilla)
        local maxBags = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
        local poorQuality = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
        local totalSold = 0
        local totalGain = 0
        local itemsToSell = {}

        for bag = 0, maxBags do
            local numSlots = ns.GetNumBagSlots(bag)
            for slot = 1, numSlots do
                local quality, link, noValue, isLocked, count = ns.GetBagItemInfo(bag, slot)
                local isPoor = (quality == poorQuality) or (link and string.find(link, "ff9d9d9d"))
                if isPoor and not isLocked and not noValue then
                    local sellPrice = 0
                    if link then
                        sellPrice = select(11, ns.SafeGetItemInfo(link)) or 0
                    end
                    -- Guard against sellPrice == 0 to prevent accidentally equipping/consuming 0-value soulbound items
                    if sellPrice > 0 then
                        totalGain = totalGain + (sellPrice * (count or 1))
                        totalSold = totalSold + 1
                        table.insert(itemsToSell, { bag = bag, slot = slot })
                    end
                end
            end
        end

        if totalSold > 0 then
            local idx = 1
            local function SellNextItem()
                if MerchantFrame and MerchantFrame:IsShown() and idx <= #itemsToSell then
                    local item = itemsToSell[idx]
                    idx = idx + 1
                    ns.UseBagItem(item.bag, item.slot)
                    if idx <= #itemsToSell then
                        C_Timer.After(0.05, SellNextItem)
                    end
                end
            end
            C_Timer.After(0.05, SellNextItem)

            if totalGain > 0 then
                print(string.format("|cff00ccff[ZeroMaint]|r Sold %d junk items for %s.", totalSold, ns.FormatMoney(totalGain)))
            else
                print(string.format("|cff00ccff[ZeroMaint]|r Sold %d junk items.", totalSold))
            end
        end
    end
end
ns.RegisterEvent("MERCHANT_SHOW", OnMerchantShow)

--------------------------------------------------------------------------------
-- 3. FASTER AUTO-LOOT & WINDOW SUPPRESSION (Vacuum Mode)
--------------------------------------------------------------------------------

local isLootingSession = false
local lastLootCount = 0

local function IsAutoLootActive()
    local autoLoot = false
    if GetCVarBool then
        autoLoot = GetCVarBool("autoLootDefault")
    elseif GetCVar then
        autoLoot = (GetCVar("autoLootDefault") == "1")
    end
    local isModified = false
    if IsModifiedClick then
        isModified = IsModifiedClick("AUTOLOOTTOGGLE")
    end
    -- XOR: true if autoLoot is on and modifier is NOT held, OR autoLoot is off and modifier IS held
    return (autoLoot and not isModified) or (not autoLoot and isModified)
end

local function UpdateLootFrameRegistration()
    if not LootFrame then return end
    local db = ns.db or ns.defaults
    if db.fasterLoot and db.hideLootFrame then
        LootFrame:UnregisterEvent("LOOT_OPENED")
        if LootFrame.UnregisterEvent then
            pcall(LootFrame.UnregisterEvent, LootFrame, "LOOT_READY")
        end
        LootFrame:Hide()
    else
        LootFrame:RegisterEvent("LOOT_OPENED")
        if LootFrame.RegisterEvent then
            pcall(LootFrame.RegisterEvent, LootFrame, "LOOT_READY")
        end
    end
end
QoL.UpdateLootFrameRegistration = UpdateLootFrameRegistration

local function ShowManualLootFrame()
    if not LootFrame then return end
    local onEvent = LootFrame.GetScript and LootFrame:GetScript("OnEvent")
    if onEvent then
        pcall(onEvent, LootFrame, "LOOT_OPENED")
    elseif LootFrame_OnEvent then
        pcall(LootFrame_OnEvent, LootFrame, "LOOT_OPENED")
    else
        LootFrame:Show()
    end
end

local function HandleFastLoot()
    local db = ns.db or ns.defaults
    if not db.fasterLoot then return end

    local isAuto = IsAutoLootActive()
    if not isAuto then
        -- User explicitly wants to inspect loot manually (holding modifier key)
        ShowManualLootFrame()
        return
    end

    local numItems = (GetNumLootItems and GetNumLootItems()) or 0
    -- If items are not yet populated (LOOT_OPENED before server payload), wait for LOOT_READY!
    if numItems <= 0 then
        return
    end

    -- Allow re-entry if numItems > lastLootCount so multi-wave AoE loot drops are not locked out
    if isLootingSession and numItems <= lastLootCount then
        return
    end
    isLootingSession = true
    lastLootCount = numItems

    -- Vacuum all items in reverse order immediately (0ms delay), guarding locked slots
    for i = numItems, 1, -1 do
        local locked = false
        if GetLootSlotInfo then
            local n = select("#", GetLootSlotInfo(i))
            if n >= 6 then
                locked = select(6, GetLootSlotInfo(i))
            elseif n >= 5 then
                locked = select(5, GetLootSlotInfo(i))
            end
        end
        if not locked and LootSlot then
            LootSlot(i)
        end
    end

    -- Safety Fallback: Only open the window if after 0.5s items still remain (e.g. inventory full or BoP confirmation)
    if db.hideLootFrame and LootFrame then
        C_Timer.After(0.5, function()
            if isLootingSession and (GetNumLootItems and GetNumLootItems() or 0) > 0 then
                ShowManualLootFrame()
            end
        end)
    end
end

local function HandleLootClosed()
    isLootingSession = false
    lastLootCount = 0
end

ns.RegisterEvent("LOOT_OPENED", HandleFastLoot)
pcall(ns.RegisterEvent, "LOOT_READY", HandleFastLoot)
ns.RegisterEvent("LOOT_CLOSED", HandleLootClosed)

--------------------------------------------------------------------------------
-- 4. LIFECYCLE & EVENT REGISTRATIONS
--------------------------------------------------------------------------------

ns.RegisterEvent("PLAYER_LOGIN", function()
    ApplyCVars()
    UpdateLootFrameRegistration()
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ApplyCVars()
    UpdateLootFrameRegistration()
end)

ns.RegisterInit(function()
    ApplyCVars()
    UpdateLootFrameRegistration()
end)

--------------------------------------------------------------------------------
-- 5. QoL API EXPORTS (For Command Dispatcher)
--------------------------------------------------------------------------------

function QoL.ToggleAutoRepair()
    local db = ns.db or ns.defaults
    db.autoRepair = not db.autoRepair
    print("|cff00ccff[ZeroMaint]|r Vendor Auto-Repair: " .. (db.autoRepair and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r") .. " (Saved to WTF)")
end

function QoL.ToggleAutoSell()
    local db = ns.db or ns.defaults
    db.autoSellGrays = not db.autoSellGrays
    db.autoVendor = db.autoSellGrays
    print("|cff00ccff[ZeroMaint]|r Vendor Auto-Sell Grays: " .. (db.autoSellGrays and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r") .. " (Saved to WTF)")
end

function QoL.ToggleFastLoot()
    local db = ns.db or ns.defaults
    db.fasterLoot = not db.fasterLoot
    print("|cff00ccff[ZeroMaint]|r Faster Auto-Loot: " .. (db.fasterLoot and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r") .. " (Saved to WTF)")
end

function QoL.ToggleHideLootFrame()
    local db = ns.db or ns.defaults
    db.hideLootFrame = not db.hideLootFrame
    UpdateLootFrameRegistration()
    print("|cff00ccff[ZeroMaint]|r Suppress Loot Window: " .. (db.hideLootFrame and "|cff00ff00ENABLED (Vacuum Mode)|r" or "|cffff0000DISABLED (Visible)|r") .. " (Saved to WTF)")
end

function QoL.ToggleCVars()
    local db = ns.db or ns.defaults
    db.enforceCVars = not db.enforceCVars
    db.maxCameraZoom = db.enforceCVars
    if db.enforceCVars then
        ApplyCVars()
        print("|cff00ccff[ZeroMaint]|r Native CVar Enforcements: |cff00ff00ENABLED & APPLIED|r (Saved to WTF)")
    else
        print("|cff00ccff[ZeroMaint]|r Native CVar Enforcements: |cffff0000DISABLED|r (Saved to WTF)")
    end
end

function QoL.ToggleUIErrors()
    local db = ns.db or ns.defaults
    db.silenceUIErrors = not db.silenceUIErrors
    if UIErrorsFrame then
        if db.silenceUIErrors then
            UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
            print("|cff00ccff[ZeroMaint]|r Red Combat Error Text: |cffff0000SILENCED|r (Saved to WTF)")
        else
            UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
            print("|cff00ccff[ZeroMaint]|r Red Combat Error Text: |cff00ff00VISIBLE|r (Saved to WTF)")
        end
    end
end

function QoL.Reset()
    ApplyCVars()
    UpdateLootFrameRegistration()
end

function QoL.PrintDebug()
    local db = ns.db or ns.defaults
    print(string.format("QoL Automations: FastLoot=%s (HideWindow=%s) | AutoRepair=%s (Guild=%s) | AutoSell=%s | CVars=%s | SilenceErrors=%s",
        tostring(db.fasterLoot), tostring(db.hideLootFrame), tostring(db.autoRepair), tostring(db.useGuildRepair or db.autoRepairGuild),
        tostring(db.autoVendor or db.autoSellGrays), tostring(db.enforceCVars), tostring(db.silenceUIErrors)))
end

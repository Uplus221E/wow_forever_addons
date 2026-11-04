--[[
    ForeverGoblin_Core.lua
    Part of the Vanguard WoW: Forever Command Suite.
    Autonomous Launch Automation: Auto-Vendor, Recipe Snipe, Bank Mailer, Route Loader.
]]--

local ADDON_NAME = "ForeverGoblin_Core"
local FG_TAG = "|cff00ff00[ForeverGoblin]|r "

-- Initialize DB
ForeverGoblinDB = ForeverGoblinDB or {
    bankAltName = "Bankalt"
}

--------------------------------------------------------------------------------
-- API Compatibility Layer (Classic 1.15 C_Container vs 1.12 Legacy)
--------------------------------------------------------------------------------
local function GetNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bag)
    end
    return 0
end

local function GetItemDetails(bag, slot)
    local link, quality, isLocked, stackCount, itemID
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            link = info.hyperlink
            quality = info.quality
            isLocked = info.isLocked
            stackCount = info.stackCount
            itemID = info.itemID
        end
    elseif GetContainerItemInfo then
        local texture, count, locked, qual, readable, lootable, itemLink = GetContainerItemInfo(bag, slot)
        link = itemLink
        quality = qual
        isLocked = locked
        stackCount = count
    end
    return link, quality, isLocked, stackCount, itemID
end

local function UseItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    elseif UseContainerItem then
        UseContainerItem(bag, slot)
    end
end

local function PickupItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    elseif PickupContainerItem then
        PickupContainerItem(bag, slot)
    end
end

--------------------------------------------------------------------------------
-- Hidden Tooltip for Soulbound Scanning
--------------------------------------------------------------------------------
local scanTooltip = CreateFrame("GameTooltip", "ForeverGoblinScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function IsItemSoulbound(bag, slot)
    scanTooltip:ClearLines()
    if C_Container and C_Container.GetContainerItemInfo and scanTooltip.SetBagItem then
        scanTooltip:SetBagItem(bag, slot)
    elseif scanTooltip.SetBagItem then
        scanTooltip:SetBagItem(bag, slot)
    else
        return false
    end

    local soulboundPatterns = {
        ITEM_SOULBOUND or "Soulbound",
        "Soulbound",
        "Quest Item"
    }

    for i = 1, scanTooltip:NumLines() do
        local line = _G["ForeverGoblinScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                for _, pattern in ipairs(soulboundPatterns) do
                    if string.find(text, pattern) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Snipe Watchlist & Scarce Keywords
--------------------------------------------------------------------------------
local SNIPE_PATTERNS = {
    "runecloth bag",
    "runecloth gloves",
    "transmute.*arcanite",
    "runed arcanite rod",
    "greater fire protection"
}

local SCARCE_KEYWORDS = {
    "cloth",
    "pyrite",
    "bauxite",
    "pitchblende",
    "lichen",
    "rosecap",
    "stranglevine",
    "seed",
    "elemental earth",
    "elemental fire",
    "arcane crystal",
    "thorium",
    "black lotus",
    "silversage",
    "plaguebloom",
    "dreamfoil",
    "recipe:",
    "pattern:",
    "formula:",
    "plans:",
    "blueprint"
}

local function MatchesScarceKeyword(name)
    if not name then return false end
    local lower = string.lower(name)
    for _, kw in ipairs(SCARCE_KEYWORDS) do
        if string.find(lower, kw, 1, true) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- ZeroMaint Addon Detection & Cooperative Integration
--------------------------------------------------------------------------------
local function IsZeroMaintActive()
    return (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ZeroMaint"))
        or (IsAddOnLoaded and IsAddOnLoaded("ZeroMaint"))
        or (ZeroMaintDB ~= nil)
end

local function SyncBankAlt()
    if ZeroMaintDB and ZeroMaintDB.bankAlt and ZeroMaintDB.bankAlt ~= "" then
        if not ForeverGoblinDB.bankAltName or ForeverGoblinDB.bankAltName == "Bankalt" then
            ForeverGoblinDB.bankAltName = ZeroMaintDB.bankAlt
        end
    end
end

--------------------------------------------------------------------------------
-- Merchant Automation: Repair, Vendor Grays, Recipe Snipe
--------------------------------------------------------------------------------
local function OnMerchantShow()
    local zmActive = IsZeroMaintActive()
    local zmHandlesVendoring = zmActive and ZeroMaintDB and (ZeroMaintDB.autoVendor or ZeroMaintDB.autoSellGrays or ZeroMaintDB.autoRepair)

    -- 1. Auto-Repair (Delegates to ZeroMaint if active to avoid duplicate calls/prints)
    if not zmHandlesVendoring and CanMerchantRepair and CanMerchantRepair() then
        local repairCost, canRepair = GetRepairAllCost()
        if canRepair and repairCost > 0 and GetMoney() >= repairCost then
            RepairAllItems()
            local formattedCost = GetCoinTextureString and GetCoinTextureString(repairCost) or (tostring(repairCost) .. " copper")
            DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "Auto-repaired all items for " .. formattedCost .. ".")
        end
    end

    -- 2. Auto-Vendor Grays (Quality == 0) (Delegates to ZeroMaint throttled seller to prevent 'Item is locked' errors)
    if not zmHandlesVendoring then
        local soldCount = 0
        for bag = 0, 4 do
            local numSlots = GetNumSlots(bag)
            for slot = 1, numSlots do
                local link, quality, isLocked = GetItemDetails(bag, slot)
                if link and quality == 0 and not isLocked then
                    UseItem(bag, slot)
                    soldCount = soldCount + 1
                end
            end
        end
        if soldCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "Auto-sold " .. soldCount .. " gray junk items.")
        end
    end

    -- 3. Instant Qia / Limited Recipe Snipe (Always runs regardless of other addons!)
    local numMerchantItems = GetMerchantNumItems()
    for i = 1, numMerchantItems do
        local name, texture, price, quantity, numAvailable, isPurchasable = GetMerchantItemInfo(i)
        if name and numAvailable and numAvailable > 0 then
            local lowerName = string.lower(name)
            local matched = false
            for _, pattern in ipairs(SNIPE_PATTERNS) do
                if string.find(lowerName, pattern) then
                    matched = true
                    break
                end
            end

            if matched then
                if GetMoney() >= price then
                    BuyMerchantItem(i, 1)
                    DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "|cff00ff00>>> SNIPED LIMITED ITEM: " .. name .. "! <<<|r")
                else
                    DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "|cffff2020>>> MISSED SNIPE (Not enough gold): " .. name .. "! <<<|r")
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- 1-Click Bank Alt Mail Dump (/fgmail)
--------------------------------------------------------------------------------
local function FGMailDump()
    if not (MailFrame and MailFrame:IsShown()) then
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "|cffff2020Mailbox is not open! Open mailbox first.|r")
        return
    end

    local recipient = ForeverGoblinDB.bankAltName
    if not recipient or recipient == "" or recipient == "Bankalt" then
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "|cffffaa00Target bank alt not set or default 'Bankalt'. Use: /fgbank <Name>|r")
    end

    -- Switch to Send Mail tab
    if MailFrameTab2 and MailFrameTab2:IsShown() then
        MailFrameTab2:Click()
    end

    if SendMailNameEditBox then
        SendMailNameEditBox:SetText(recipient)
    end
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText("Dump")
    end

    local maxAttach = ATTACHMENTS_MAX_SEND or 12
    local attachedCount = 0

    for bag = 0, 4 do
        local numSlots = GetNumSlots(bag)
        for slot = 1, numSlots do
            if attachedCount >= maxAttach then
                break
            end

            local link, quality, isLocked = GetItemDetails(bag, slot)
            if link and not isLocked then
                local isSoulbound = IsItemSoulbound(bag, slot)
                if not isSoulbound then
                    local itemName = GetItemInfo(link) or ""
                    local shouldMail = (quality and quality >= 2) or MatchesScarceKeyword(itemName)
                    if shouldMail then
                        PickupItem(bag, slot)
                        if ClickSendMailItemButton then
                            ClickSendMailItemButton(attachedCount + 1)
                        else
                            UseItem(bag, slot)
                        end
                        attachedCount = attachedCount + 1
                    end
                end
            end
        end
        if attachedCount >= maxAttach then
            break
        end
    end

    if attachedCount > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "Attached " .. attachedCount .. " items for " .. recipient .. ". Sending mail...")
        if SendMailMailButton and SendMailMailButton:IsEnabled() then
            SendMailMailButton:Click()
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "No eligible unbound scarce/green+ items found to mail.")
    end
end

--------------------------------------------------------------------------------
-- Winterspring Outer Rim TomTom Loader (/fgroute)
--------------------------------------------------------------------------------
local WINTERSPRING_WAYPOINTS = {
    {x = 68.4, y = 36.2, desc = "Sector 1: Ice Thistle North"},
    {x = 69.1, y = 42.8, desc = "Sector 1: Ice Thistle South"},
    {x = 65.8, y = 61.2, desc = "Sector 2: Owl Wing Incline"},
    {x = 64.2, y = 72.0, desc = "Sector 2: Owl Wing Ridge"},
    {x = 60.5, y = 75.8, desc = "Sector 3: Gorge Archway - Do Not Enter Deep"},
    {x = 57.2, y = 65.4, desc = "Sector 4: Mazthoril Cliff"},
    {x = 55.0, y = 53.2, desc = "Sector 4: Mazthoril Path"},
    {x = 48.8, y = 42.5, desc = "Sector 5: Frostfire Pools"},
    {x = 52.0, y = 36.5, desc = "Sector 6: Kel'Theril Bluffs"},
    {x = 50.5, y = 27.2, desc = "Sector 7: Starfall Ridge"},
    {x = 58.4, y = 22.1, desc = "Sector 7: North Wall"},
    {x = 61.0, y = 38.9, desc = "Reset: Everlook Outdoor Mailbox"}
}

local function LoadWinterspringRoute()
    local count = 0
    local tomtomCmd = SlashCmdList["TOMTOM_WAY"] or SlashCmdList["WAY"]

    for _, wp in ipairs(WINTERSPRING_WAYPOINTS) do
        if TomTom and TomTom.AddWaypoint then
            -- Support TomTom API directly (Winterspring UiMapID = 1452)
            TomTom:AddWaypoint(1452, wp.x / 100, wp.y / 100, {
                title = wp.desc,
                persistent = false,
                minimap = true,
                world = true
            })
            count = count + 1
        elseif tomtomCmd then
            tomtomCmd(string.format("Winterspring %.1f %.1f %s", wp.x, wp.y, wp.desc))
            count = count + 1
        end
    end

    if count > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "Successfully loaded " .. count .. " Winterspring Outer Rim waypoints into TomTom!")
    else
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "|cffffaa00TomTom addon not detected. Install TomTom to view active waypoints.|r")
        for i, wp in ipairs(WINTERSPRING_WAYPOINTS) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%d] Winterspring %.1f, %.1f - %s", i, wp.x, wp.y, wp.desc))
        end
    end
end

--------------------------------------------------------------------------------
-- Bedtime Downshift & Day Modes (/fgnight, /fgday)
--------------------------------------------------------------------------------
local function FGNightMode()
    SetCVar("enableFloatingCombatText", "0")
    SetCVar("floatingCombatTextCombatDamage", "0")
    DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "|cffffaa00Night Mode Engaged: Floating Combat Text disabled. Prepare for downshift & sleep.|r")
end

local function FGDayMode()
    SetCVar("enableFloatingCombatText", "1")
    SetCVar("floatingCombatTextCombatDamage", "1")
    DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "|cff00ff00Day Mode Engaged: Floating Combat Text restored. Fasted APM window active!|r")
end

--------------------------------------------------------------------------------
-- Slash Commands Registration
--------------------------------------------------------------------------------
SLASH_FGBANK1 = "/fgbank"
SlashCmdList["FGBANK"] = function(msg)
    local name = msg and string.match(msg, "^%s*(%S+)%s*$")
    if name and name ~= "" then
        ForeverGoblinDB.bankAltName = name
        if ZeroMaintDB then
            ZeroMaintDB.bankAlt = name
        end
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "Bank Alt locked to: |cff00ff00" .. name .. "|r" .. (IsZeroMaintActive() and " (Synced with ZeroMaint)" or ""))
    else
        SyncBankAlt()
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "Current Bank Alt: |cff00ff00" .. (ForeverGoblinDB.bankAltName or "Not Set") .. "|r. Usage: /fgbank <CharacterName>")
    end
end

SLASH_FGMAIL1 = "/fgmail"
SlashCmdList["FGMAIL"] = function()
    SyncBankAlt()
    FGMailDump()
end

SLASH_FGROUTE1 = "/fgroute"
SlashCmdList["FGROUTE"] = function()
    LoadWinterspringRoute()
end

SLASH_FGNIGHT1 = "/fgnight"
SlashCmdList["FGNIGHT"] = function()
    FGNightMode()
end

SLASH_FGDAY1 = "/fgday"
SlashCmdList["FGDAY"] = function()
    FGDayMode()
end

--------------------------------------------------------------------------------
-- Main Event Listener Frame
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "ForeverGoblinEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("MERCHANT_SHOW")

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ForeverGoblinDB = ForeverGoblinDB or {}
        ForeverGoblinDB.bankAltName = ForeverGoblinDB.bankAltName or "Bankalt"
    elseif event == "PLAYER_LOGIN" then
        SyncBankAlt()
        local zmStatus = IsZeroMaintActive() and " |cff38bdf8[ZeroMaint Active]|r" or ""
        DEFAULT_CHAT_FRAME:AddMessage(FG_TAG .. "Loaded. Bank Alt: |cff00ff00" .. (ForeverGoblinDB.bankAltName or "Bankalt") .. "|r" .. zmStatus .. ". Commands: /fgbank, /fgmail, /fgroute, /fgnight, /fgday")
    elseif event == "MERCHANT_SHOW" then
        OnMerchantShow()
    end
end)

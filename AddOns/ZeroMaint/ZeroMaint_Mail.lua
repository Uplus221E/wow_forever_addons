--[[
    ZeroMaint - Native Mail Automation & Bank Alt Pipeline (Pillar 4)
    File: ZeroMaint_Mail.lua
    
    Responsibilities:
      1. Bank alt recipient management and persistence in ZeroMaintDB.
      2. Mailbox interaction verification (MailFrame state).
      3. Cross-client container and item polyfill engine (1.12 -> 11.0+).
      4. Soulbound and Bind-on-Equip (BoE) detection without memory leaks.
      5. 12-slot mail attachment automation and 1-click dispatch.
      6. Error handling, combat isolation, and mailbox event synchronization.
]]

local addonName, ns = ...
local Mail = ns.Mail or {}
ns.Mail = Mail

--------------------------------------------------------------------------------
-- 1. CONFIGURATION GETTERS & SETTERS
--------------------------------------------------------------------------------

function Mail.GetBankAlt()
    local db = ns.db or ns.defaults
    return (db and db.bankAlt) or ""
end

function Mail.SetBankAlt(name)
    local db = ns.db or ns.defaults
    if not db then return end

    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        print("|cff00ccff[ZeroMaint Mail]|r Usage: /z setalt <CharacterName>")
        return
    end

    db.bankAlt = name
    print(string.format("|cff00ccff[ZeroMaint Mail]|r Default bank alt set to: |cffffd100%s|r", name))
end

function Mail.GetMinQuality()
    local db = ns.db or ns.defaults
    return (db and db.mailMinQuality) or 2
end

function Mail.SetMinQuality(val)
    local db = ns.db or ns.defaults
    if not db then return end

    local q = tonumber(val)
    if not q or q < 1 or q > 4 then
        print("|cff00ccff[ZeroMaint Mail]|r Usage: /z mail quality <2|3|4> (2=Uncommon, 3=Rare, 4=Epic)")
        return
    end

    db.mailMinQuality = q
    local names = { [1] = "Common (White+)", [2] = "Uncommon (Green+)", [3] = "Rare (Blue+)", [4] = "Epic (Purple)" }
    print(string.format("|cff00ccff[ZeroMaint Mail]|r Minimum mail quality set to: |cffffd100%s|r", names[q] or tostring(q)))
end

function Mail.ToggleAutoSend()
    local db = ns.db or ns.defaults
    if not db then return end

    db.mailAutoSend = not db.mailAutoSend
    print(string.format("|cff00ccff[ZeroMaint Mail]|r Auto-Send mode: %s",
        db.mailAutoSend and "|cff00ff00ENABLED (immediate dispatch)|r" or "|cffff4444DISABLED (1-click confirmation)|r"))
end

function Mail.PrintStatus()
    local db = ns.db or ns.defaults
    local bankAlt = Mail.GetBankAlt()
    local altDisplay = (bankAlt ~= "" and ("|cffffd100" .. bankAlt .. "|r")) or "|cffff4444[None Configured]|r"
    local qualityNames = { [1] = "White+", [2] = "Green+ (Uncommon)", [3] = "Blue+ (Rare)", [4] = "Epic" }
    local q = Mail.GetMinQuality()
    local isOpen = Mail.IsMailboxOpen()

    print("|cff00ccff[ZeroMaint Mail Status]|r")
    print(string.format("  Bank Alt: %s", altDisplay))
    print(string.format("  Quality Threshold: |cffffd100%s|r", qualityNames[q] or tostring(q)))
    print(string.format("  Auto-Send: %s", (db and db.mailAutoSend) and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
    print(string.format("  Mailbox Open: %s", isOpen and "|cff00ff00YES|r" or "|cffff4444NO|r"))
end

--------------------------------------------------------------------------------
-- 2. UNIVERSAL CONTAINER & ITEM POLYFILL ENGINE (Vanilla 1.12 -> Retail 11.0+)
--------------------------------------------------------------------------------

-- 2.1 Container Slot Count Polyfill
local function GetContainerNumSlotsPolyfill(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID) or 0
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bagID) or 0
    end
    return 0
end
Mail.GetContainerNumSlots = GetContainerNumSlotsPolyfill

-- 2.2 Container Item Info Polyfill
-- Returns normalized table: { itemID, hyperlink, stackCount, quality, isLocked, isBound } or nil
local function GetContainerItemInfoPolyfill(bagID, slotIndex)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotIndex)
        if not info then return nil end
        return {
            itemID     = info.itemID,
            hyperlink  = info.hyperlink,
            stackCount = info.stackCount or 1,
            quality    = info.quality or 0,
            isLocked   = info.isLocked or false,
            isBound    = info.isBound,
        }
    elseif GetContainerItemInfo then
        local texture, count, locked, quality, readable, lootable, link, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(bagID, slotIndex)
        if not texture and not link and not itemID then return nil end
        return {
            itemID     = itemID,
            hyperlink  = link,
            stackCount = count or 1,
            quality    = quality or 0,
            isLocked   = locked or false,
            isBound    = isBound,
        }
    end
    return nil
end
Mail.GetContainerItemInfo = GetContainerItemInfoPolyfill

-- 2.3 Container Pickup Polyfill
local function PickupContainerItemPolyfill(bagID, slotIndex)
    if C_Container and C_Container.PickupContainerItem then
        return C_Container.PickupContainerItem(bagID, slotIndex)
    elseif PickupContainerItem then
        return PickupContainerItem(bagID, slotIndex)
    end
end
Mail.PickupContainerItem = PickupContainerItemPolyfill

-- 2.4 Container Item Link Polyfill
local function GetContainerItemLinkPolyfill(bagID, slotIndex)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bagID, slotIndex)
    elseif GetContainerItemLink then
        return GetContainerItemLink(bagID, slotIndex)
    end
    return nil
end
Mail.GetContainerItemLink = GetContainerItemLinkPolyfill

--------------------------------------------------------------------------------
-- 3. ITEM BINDING & BOE INSPECTION ENGINE
--------------------------------------------------------------------------------

-- Hidden singleton scanning tooltip for legacy or deep binding verification
local scanTooltip
local function GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "ZeroMaint_MailScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTooltip
end
Mail.GetScanTooltip = GetScanTooltip

-- Known binding strings from Blizzard FrameXML globals
local BOUND_PATTERNS = {
    ITEM_SOULBOUND or "Soulbound",
    ITEM_BIND_ON_PICKUP or "Binds when picked up",
    ITEM_ACCOUNTBOUND or "Account Bound",
    ITEM_BIND_TO_ACCOUNT or "Binds to account",
    ITEM_BIND_TO_BNETACCOUNT or "Binds to Battle.net account",
    ITEM_BNETACCOUNTBOUND or "Blizzard Account Bound",
}

-- Checks if an item in (bagID, slotIndex) is soulbound / accountbound
function Mail.IsItemBound(bagID, slotIndex, itemInfo)
    -- 1. Modern direct boolean check from container info
    if itemInfo and itemInfo.isBound ~= nil then
        return itemInfo.isBound == true
    end

    -- 2. Modern C_Item.IsBound with ItemLocation
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local loc = ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
        if loc and loc:IsValid() then
            local isBound = C_Item.IsBound(loc)
            if isBound ~= nil then return isBound end
        end
    end

    -- 3. Fallback: Hidden Tooltip Scanner
    local tt = GetScanTooltip()
    tt:ClearLines()
    local ok = pcall(tt.SetBagItem, tt, bagID, slotIndex)
    if not ok then return false end

    for i = 1, (tt:NumLines() or 0) do
        local line = _G["ZeroMaint_MailScanTooltipTextLeft" .. i]
        if line and line.GetText then
            local text = line:GetText()
            if text and text ~= "" then
                for _, pattern in ipairs(BOUND_PATTERNS) do
                    if text:find(pattern, 1, true) then
                        tt:Hide()
                        return true
                    end
                end
            end
        end
    end

    tt:Hide()
    return false
end

-- Checks if an item in (bagID, slotIndex) is equipable BoE
function Mail.IsItemBoE(bagID, slotIndex, itemInfo)
    if not itemInfo then
        itemInfo = Mail.GetContainerItemInfo(bagID, slotIndex)
    end
    if not itemInfo then return false end

    -- Locked items (in transit, pending transaction) are skipped
    if itemInfo.isLocked then return false end

    -- Check quality threshold
    local minQuality = Mail.GetMinQuality()
    if (itemInfo.quality or 0) < minQuality then
        return false
    end

    -- If already bound, it cannot be mailed as BoE
    if Mail.IsItemBound(bagID, slotIndex, itemInfo) then
        return false
    end

    -- Query item info for equipability and bindType
    local link = itemInfo.hyperlink or Mail.GetContainerItemLink(bagID, slotIndex)
    local itemID = itemInfo.itemID
    local queryTarget = link or itemID
    if not queryTarget then return false end

    local itemName, _, itemQuality, _, _, _, _, _, itemEquipLoc, _, _, _, _, bindType = GetItemInfo(queryTarget)

    -- If GetItemInfo returns nil (uncached item), fall back to tooltip inspection
    if not itemName then
        local tt = GetScanTooltip()
        tt:ClearLines()
        local ok = pcall(tt.SetBagItem, tt, bagID, slotIndex)
        if not ok then return false end

        local isBoE = false
        local boeString = ITEM_BIND_ON_EQUIP or "Binds when equipped"
        for i = 1, (tt:NumLines() or 0) do
            local line = _G["ZeroMaint_MailScanTooltipTextLeft" .. i]
            if line and line.GetText then
                local text = line:GetText()
                if text and text:find(boeString, 1, true) then
                    isBoE = true
                    break
                end
            end
        end
        tt:Hide()
        return isBoE
    end

    -- Must be equipable gear (weapons, armor, accessories)
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP" then
        return false
    end

    -- bindType == 2 corresponds to LE_ITEM_BIND_ON_EQUIP (or LE_ITEM_BIND_EQUIP)
    if bindType and bindType == 2 then
        return true
    end

    -- If bindType wasn't 2 or was omitted (legacy clients), check tooltip for "Binds when equipped"
    local tt = GetScanTooltip()
    tt:ClearLines()
    local ok = pcall(tt.SetBagItem, tt, bagID, slotIndex)
    if ok then
        local boeString = ITEM_BIND_ON_EQUIP or "Binds when equipped"
        for i = 1, (tt:NumLines() or 0) do
            local line = _G["ZeroMaint_MailScanTooltipTextLeft" .. i]
            if line and line.GetText then
                local text = line:GetText()
                if text and text:find(boeString, 1, true) then
                    tt:Hide()
                    return true
                end
            end
        end
    end

    tt:Hide()
    return false
end

-- Inspects a specific bag slot and returns a structured descriptor
function Mail.InspectSlot(bagID, slotIndex)
    local info = Mail.GetContainerItemInfo(bagID, slotIndex)
    if not info then return nil end

    local link = info.hyperlink or Mail.GetContainerItemLink(bagID, slotIndex)
    local bound = Mail.IsItemBound(bagID, slotIndex, info)
    local boe = Mail.IsItemBoE(bagID, slotIndex, info)

    local name, itemQuality, equipLoc, sellPrice, bindType
    if link or info.itemID then
        name, _, itemQuality, _, _, _, _, _, equipLoc, _, sellPrice, _, _, bindType = GetItemInfo(link or info.itemID)
    end

    return {
        bag       = bagID,
        slot      = slotIndex,
        itemID    = info.itemID,
        link      = link,
        name      = name,
        quality   = info.quality or itemQuality or 0,
        count     = info.stackCount or 1,
        isLocked  = info.isLocked or false,
        isBound   = bound,
        isBoE     = boe,
        equipLoc  = equipLoc,
        bindType  = bindType,
        sellPrice = sellPrice or 0,
    }
end

--------------------------------------------------------------------------------
-- 4. MAILBOX ENVIRONMENT CHECKS & TAB NAVIGATION
--------------------------------------------------------------------------------

function Mail.IsMailboxOpen()
    return (MailFrame and MailFrame:IsShown()) and true or false
end

function Mail.OpenSendMailTab()
    if MailFrameTab2 and MailFrameTab2.Click then
        MailFrameTab2:Click()
    elseif SetSendMailShowing then
        SetSendMailShowing(true)
    end
end

--------------------------------------------------------------------------------
-- 5. BAG SCANNING & 12-SLOT ATTACHMENT PIPELINE (PILLAR 4)
--------------------------------------------------------------------------------

-- Scans player bags 0 to 4 for unbound BoE items matching criteria
function Mail.ScanBagsForBoE(maxCount)
    local items = {}
    local numBags = NUM_BAG_SLOTS or 4

    for bagID = 0, numBags do
        local numSlots = Mail.GetContainerNumSlots(bagID)
        for slotIndex = 1, numSlots do
            local desc = Mail.InspectSlot(bagID, slotIndex)
            if desc and desc.isBoE and not desc.isLocked then
                table.insert(items, desc)
                if maxCount and #items >= maxCount then
                    return items
                end
            end
        end
    end

    return items
end

-- Previews BoE items found in player bags without sending
function Mail.PreviewBoE()
    local q = Mail.GetMinQuality()
    local qualityNames = { [1] = "White+", [2] = "Green+ (Uncommon)", [3] = "Blue+ (Rare)", [4] = "Epic" }
    local items = Mail.ScanBagsForBoE(nil)

    print(string.format("|cff00ccff[ZeroMaint BoE Scanner]|r Quality: |cffffd100%s|r", qualityNames[q] or tostring(q)))
    if #items == 0 then
        print("  |cffff4444No unbound BoE items found in bags.|r")
        return
    end

    print(string.format("  Found |cffffd100%d|r BoE item(s):", #items))
    for i = 1, math.min(#items, 12) do
        local item = items[i]
        local nameOrLink = item.link or item.name or ("Item #" .. tostring(item.itemID))
        print(string.format("    %d. [Bag %d, Slot %d] %s", i, item.bag, item.slot, nameOrLink))
    end
    if #items > 12 then
        print(string.format("    ... and %d more (mail sends max 12 per letter).", #items - 12))
    end
end

-- Clears current send mail attachment slots
function Mail.ClearSendMailAttachments()
    ClearCursor()
    local maxAttachments = ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxAttachments do
        if HasSendMailItem and HasSendMailItem(i) then
            if ClickSendMailItemButton then
                ClickSendMailItemButton(i, true)
            elseif ClickSendMailPackageButton then
                ClickSendMailPackageButton(true)
            end
        end
    end
    ClearCursor()
end

-- Prepares the send mail form, attaches items, and dispatches or confirms
function Mail.AttachAndPrepare(recipient, items)
    if not items or #items == 0 then return 0 end

    -- 1. Ensure Send Mail tab is active
    Mail.OpenSendMailTab()

    -- 2. Clear previous attachments if any
    Mail.ClearSendMailAttachments()

    -- 3. Attach items sequentially into SendMail slots
    local maxAttachments = ATTACHMENTS_MAX_SEND or 12
    local attachLimit = math.min(#items, maxAttachments)
    local attachedCount = 0

    for i = 1, attachLimit do
        local item = items[i]
        ClearCursor()
        Mail.PickupContainerItem(item.bag, item.slot)

        local hasCursorItem = (CursorHasItem and CursorHasItem()) or (GetCursorInfo and GetCursorInfo() ~= nil)
        if hasCursorItem then
            if ClickSendMailItemButton then
                ClickSendMailItemButton(i)
            elseif ClickSendMailPackageButton then
                ClickSendMailPackageButton()
            end
            attachedCount = attachedCount + 1
        end
    end
    ClearCursor()

    if attachedCount == 0 then
        print("|cff00ccff[ZeroMaint Mail]|r |cffff4444Failed to attach items into mail slots.|r")
        return 0
    end

    -- 4. Fill Recipient
    if SendMailNameEditBox then
        SendMailNameEditBox:SetText(recipient)
        if SendMailNameEditBox.HighlightText then
            SendMailNameEditBox:HighlightText(0, 0)
        end
    elseif SendMailFrame and SendMailFrame.SendMailNameEditBox then
        SendMailFrame.SendMailNameEditBox:SetText(recipient)
    end

    -- 5. Fill Subject
    local subject = string.format("BoE Dump (%d item%s)", attachedCount, attachedCount == 1 and "" or "s")
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText(subject)
    elseif SendMailFrame and SendMailFrame.SendMailSubjectEditBox then
        SendMailFrame.SendMailSubjectEditBox:SetText(subject)
    end

    -- 6. Postage Check
    local cost = (GetSendMailPrice and GetSendMailPrice()) or 0
    local playerMoney = (GetMoney and GetMoney()) or 0
    if cost > 0 and playerMoney < cost then
        print(string.format("|cff00ccff[ZeroMaint Mail]|r Attached |cffffd100%d|r item(s), but insufficient copper for postage (%d copper required).",
            attachedCount, cost))
        return attachedCount
    end

    -- 7. Auto-Send vs Confirmation
    local db = ns.db or ns.defaults
    if db and db.mailAutoSend then
        if SendMail then
            SendMail(recipient, subject, "")
            print(string.format("|cff00ccff[ZeroMaint Mail]|r Dispatched |cffffd100%d|r BoE item(s) to |cffffd100%s|r.", attachedCount, recipient))
        elseif SendMailMailButton and SendMailMailButton.Click then
            SendMailMailButton:Click()
            print(string.format("|cff00ccff[ZeroMaint Mail]|r Dispatched |cffffd100%d|r BoE item(s) to |cffffd100%s|r.", attachedCount, recipient))
        end
    else
        print(string.format("|cff00ccff[ZeroMaint Mail]|r Attached |cffffd100%d|r BoE item(s) to |cffffd100%s|r. Click |cffffd100'Send'|r to dispatch (or enable |cffffd100/z mail autosend|r).",
            attachedCount, recipient))
    end

    return attachedCount
end

--------------------------------------------------------------------------------
-- 6. COMMAND DISPATCHER & EVENT HANDLERS
--------------------------------------------------------------------------------

function Mail.SendBoE(targetAlt)
    if InCombatLockdown and InCombatLockdown() then
        print("|cff00ccff[ZeroMaint Mail]|r Cannot automate mail during combat lockdown.")
        return false
    end

    if not Mail.IsMailboxOpen() then
        print("|cff00ccff[ZeroMaint Mail]|r |cffff4444You must be at an open Mailbox to send items.|r")
        return false
    end

    local recipient = targetAlt or Mail.GetBankAlt()
    recipient = (recipient or ""):match("^%s*(.-)%s*$")
    if recipient == "" then
        print("|cff00ccff[ZeroMaint Mail]|r |cffff4444No bank alt configured.|r Use |cffffd100/z setalt <Name>|r or |cffffd100/sendboe <Name>|r.")
        return false
    end

    local maxAttachments = ATTACHMENTS_MAX_SEND or 12
    local boeItems = Mail.ScanBagsForBoE(maxAttachments)
    if #boeItems == 0 then
        local q = Mail.GetMinQuality()
        local qualityNames = { [1] = "White+", [2] = "Green+ (Uncommon)", [3] = "Blue+ (Rare)", [4] = "Epic" }
        print(string.format("|cff00ccff[ZeroMaint Mail]|r No unbound BoE items found in bags matching quality threshold |cffffd100%s|r.",
            qualityNames[q] or tostring(q)))
        return false
    end

    local count = Mail.AttachAndPrepare(recipient, boeItems)
    return count > 0
end

function Mail.HandleCommand(arg1, arg2, arg3)
    local sub = (arg1 or ""):lower()
    if sub == "alt" or sub == "setalt" then
        Mail.SetBankAlt(arg2)
    elseif sub == "quality" or sub == "minquality" then
        Mail.SetMinQuality(arg2)
    elseif sub == "autosend" or sub == "toggleauto" then
        Mail.ToggleAutoSend()
    elseif sub == "scan" or sub == "preview" then
        Mail.PreviewBoE()
    elseif sub == "status" then
        Mail.PrintStatus()
    elseif sub == "help" or sub == "?" then
        print("|cff00ccff[ZeroMaint Mail Commands]|r")
        print("  |cffffd100/sendboe [AltName]|r       - Attach & mail BoEs to bank alt")
        print("  |cffffd100/z setalt <Name>|r         - Set default recipient character")
        print("  |cffffd100/z mail scan|r             - Preview BoE items in bags without sending")
        print("  |cffffd100/z mail quality <2|3|4>|r  - Set quality threshold (2=Green, 3=Blue, 4=Purple)")
        print("  |cffffd100/z mail autosend|r         - Toggle auto-dispatch vs 1-click confirmation")
        print("  |cffffd100/z mail status|r           - Print current mail configuration")
    else
        Mail.SendBoE((arg1 ~= "" and arg1) or nil)
    end
end

function Mail.PrintDebug()
    local bankAlt = Mail.GetBankAlt()
    local isOpen = Mail.IsMailboxOpen()
    local containerApi = (C_Container and C_Container.GetContainerItemInfo) and "C_Container" or "Legacy"
    local boeCount = #(Mail.ScanBagsForBoE(nil) or {})
    print(string.format("|cff00ccff[ZeroMaint Mail Debug]|r MailboxOpen: %s | TargetAlt: '%s' | ContainerAPI: %s | BoEsInBags: %d | SendMailFrame: %s",
        tostring(isOpen), bankAlt, containerApi, boeCount, tostring(SendMailFrame ~= nil)))
end

function Mail.Reset()
    local db = ns.db or ns.defaults
    if db then
        db.bankAlt = ""
        db.mailMinQuality = 2
        db.mailAutoSend = false
    end
end

-- Mailbox Event Lifecycle: Clear cursor when mailbox closes to ensure zero dangling items
if ns.RegisterEvent then
    ns.RegisterEvent("MAIL_CLOSED", function()
        ClearCursor()
    end)
end

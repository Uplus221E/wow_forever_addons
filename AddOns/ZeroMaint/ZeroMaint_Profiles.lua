--[[
    ZeroMaint - Action Bars, Keybinds & Macros Engine (Pillar 3)
    File: ZeroMaint_Profiles.lua
    
    Responsibilities:
      1. Action Bar snapshotting and restoration across all 180 action slots.
      2. Native macro engine: snapshots, creates, and edits account and character macros.
      3. Keybinding synchronization with BINDING_HEADER_ header filtering.
      4. Support for Spells, Macros, Items, Mounts, Companions, Equipment Sets, and Flyouts.
      5. Strict InCombatLockdown guards preventing ADDON_ACTION_BLOCKED taint.
]]

local addonName, ns = ...
local Profiles = ns.Profiles or {}
ns.Profiles = Profiles

--------------------------------------------------------------------------------
-- 1. SAFE SPELL RESOLUTION HELPER
--------------------------------------------------------------------------------

local function SafePickupSpell(spellIdentifier)
    if not spellIdentifier then return false end

    -- 1. If string in Retail 11.0+, try resolving to numeric spellID first
    if type(spellIdentifier) == "string" and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local resolvedID = C_Spell.GetSpellIDForSpellIdentifier(spellIdentifier)
        if resolvedID then spellIdentifier = resolvedID end
    end

    -- 2. Modern Retail Pickup
    if C_Spell and C_Spell.PickupSpell then
        pcall(C_Spell.PickupSpell, spellIdentifier)
        if GetCursorInfo and GetCursorInfo() ~= nil then return true end
    end

    -- 3. Classic / Legacy Pickup
    if PickupSpell then
        pcall(PickupSpell, spellIdentifier)
        if GetCursorInfo and GetCursorInfo() ~= nil then return true end
    end

    -- 4. Fallback to PickupSpellBookItem
    if type(spellIdentifier) == "string" and PickupSpellBookItem then
        pcall(PickupSpellBookItem, spellIdentifier)
        if GetCursorInfo and GetCursorInfo() ~= nil then return true end
    end

    return false
end
Profiles.SafePickupSpell = SafePickupSpell
ns.SafePickupSpell = SafePickupSpell

--------------------------------------------------------------------------------
-- 2. PROFILE SNAPSHOT ENGINE
--------------------------------------------------------------------------------

local function ForEachBoundKey(callback)
    local numBindings = (GetNumBindings and GetNumBindings()) or 0
    for i = 1, numBindings do
        local command = select(1, GetBinding(i))
        if command and not string.find(command, "^BINDING_HEADER_") and not string.find(command, "^HEADER") then
            if GetBindingKey then
                for k = 1, select("#", GetBindingKey(command)) do
                    local key = select(k, GetBindingKey(command))
                    if key and key ~= "" and not string.find(key, "^BINDING_HEADER_") then
                        callback(key, command)
                    end
                end
            else
                for k = 2, select("#", GetBinding(i)) do
                    local key = select(k, GetBinding(i))
                    if key and key ~= "" and not string.find(key, "^BINDING_HEADER_") then
                        callback(key, command)
                    end
                end
            end
        end
    end
end

local function SnapshotProfile(name)
    if not name or name == "" then
        print("|cff00ccff[ZeroMaint]|r Usage: |cffffd100/z save <profile>|r")
        return false
    end

    if InCombatLockdown() then
        print("|cff00ccff[ZeroMaint]|r |cffff0000Cannot save profile in combat!|r")
        return false
    end

    local db = ns.db or ZeroMaintDB
    if not db then
        db = {}
        ZeroMaintDB = db
        ns.db = db
    end
    if not db.profiles then
        db.profiles = {}
    end

    local playerClass = (UnitClass and select(2, UnitClass("player"))) or "Universal"
    local timestamp = (date and date("%Y-%m-%d %H:%M:%S")) or "unknown"

    local profile = {
        name = name,
        created = timestamp,
        class = playerClass,
        actions = {},
        bindings = {},
        macros = {},
        maxSlots = 180,
    }

    -- 1. Snapshot Action Bars (Slots 1 to 180)
    for slot = 1, 180 do
        local actionType, id, subType = GetActionInfo(slot)
        if actionType then
            local entry = {
                type = actionType,
                id = id,
                subType = subType,
            }
            if actionType == "spell" then
                local spellName
                if C_Spell and C_Spell.GetSpellInfo then
                    local info = C_Spell.GetSpellInfo(id)
                    if info then spellName = info.name end
                elseif GetSpellInfo then
                    spellName = GetSpellInfo(id)
                end
                entry.name = spellName
            elseif actionType == "macro" then
                local mName, mIcon, mBody = GetMacroInfo(id)
                entry.name = mName
                entry.icon = mIcon
                entry.body = mBody
            elseif actionType == "item" then
                local iName
                if C_Item and C_Item.GetItemNameByID then
                    iName = C_Item.GetItemNameByID(id)
                else
                    iName = ns.SafeGetItemInfo(id)
                end
                entry.name = iName
            end
            profile.actions[slot] = entry
        end
    end

    -- 2. Snapshot Keybindings (Filter out BINDING_HEADER_ categories)
    ForEachBoundKey(function(key, command)
        profile.bindings[key] = command
    end)

    -- 3. Snapshot Macros
    local numAccount, numChar = 0, 0
    if GetNumMacros then
        numAccount, numChar = GetNumMacros()
    end
    for i = 1, (numAccount or 0) do
        local mName, mIcon, mBody = GetMacroInfo(i)
        if mName then
            table.insert(profile.macros, {
                name = mName,
                icon = mIcon,
                body = mBody,
                isChar = false,
            })
        end
    end
    local maxAccount = MAX_ACCOUNT_MACROS or 120
    for i = 1, (numChar or 0) do
        local mName, mIcon, mBody = GetMacroInfo(maxAccount + i)
        if mName then
            table.insert(profile.macros, {
                name = mName,
                icon = mIcon,
                body = mBody,
                isChar = true,
            })
        end
    end

    db.profiles[name] = profile

    local actionCount = 0
    for _ in pairs(profile.actions) do actionCount = actionCount + 1 end
    local bindCount = 0
    for _ in pairs(profile.bindings) do bindCount = bindCount + 1 end

    print(string.format("|cff00ccff[ZeroMaint]|r Profile '|cffffd100%s|r' saved: %d actions, %d binds, %d macros. (Saved to WTF)",
        name, actionCount, bindCount, #profile.macros))
    return true
end
Profiles.SnapshotProfile = SnapshotProfile
ns.SnapshotProfile = SnapshotProfile

--------------------------------------------------------------------------------
-- 3. PROFILE RESTORATION ENGINE
--------------------------------------------------------------------------------

local function RestoreProfile(name)
    if not name or name == "" then
        print("|cff00ccff[ZeroMaint]|r Usage: |cffffd100/z load <profile>|r")
        return false
    end

    if InCombatLockdown() then
        print("|cff00ccff[ZeroMaint]|r |cffff0000Cannot restore profile in combat!|r")
        return false
    end

    local db = ns.db or ZeroMaintDB
    if not db or not db.profiles then
        print(string.format("|cff00ccff[ZeroMaint]|r Profile '|cffff0000%s|r' not found. Type |cffffd100/z list|r to see saved profiles.", name))
        return false
    end

    local profile = db.profiles[name]
    if not profile then
        for k, v in pairs(db.profiles) do
            if k:lower() == name:lower() then
                profile = v
                name = k
                break
            end
        end
    end

    if not profile then
        print(string.format("|cff00ccff[ZeroMaint]|r Profile '|cffff0000%s|r' not found. Type |cffffd100/z list|r to see saved profiles.", name))
        return false
    end

    -- 1. Restore Macros (Created/Updated before action bar assignments)
    if profile.macros and CreateMacro then
        for _, m in ipairs(profile.macros) do
            local existing = nil
            if GetMacroIndexByName then
                local idx = GetMacroIndexByName(m.name)
                if idx and idx > 0 then existing = idx end
            end
            if not existing and GetMacroInfo then
                local test = GetMacroInfo(m.name)
                if test then existing = m.name end
            end

            if existing then
                if EditMacro then
                    pcall(EditMacro, existing, m.name, m.icon or "INV_MISC_QUESTIONMARK", m.body)
                end
            else
                local numAccount, numChar = 0, 0
                if GetNumMacros then numAccount, numChar = GetNumMacros() end
                local maxAccount = MAX_ACCOUNT_MACROS or 120
                local maxChar = MAX_CHARACTER_MACROS or 18
                local canCreateChar = m.isChar and (numChar < maxChar)
                local canCreateAccount = (numAccount < maxAccount)

                if canCreateChar then
                    pcall(CreateMacro, m.name, m.icon or "INV_MISC_QUESTIONMARK", m.body, true)
                elseif canCreateAccount then
                    pcall(CreateMacro, m.name, m.icon or "INV_MISC_QUESTIONMARK", m.body, false)
                end
            end
        end
    end

    -- 2. Restore Action Bars
    ClearCursor()
    local maxSlots = profile.maxSlots or 180
    for slot = 1, maxSlots do
        local action = profile.actions and profile.actions[slot]
        if action then
            ClearCursor()

            if action.type == "spell" then
                if action.id then
                    SafePickupSpell(action.id)
                end
                if (GetCursorInfo and GetCursorInfo() == nil) and action.name then
                    SafePickupSpell(action.name)
                end

            elseif action.type == "macro" then
                local idx = (GetMacroIndexByName and action.name and GetMacroIndexByName(action.name)) or 0
                if (not idx or idx == 0) and action.id and action.name and GetMacroInfo then
                    local testName = GetMacroInfo(action.id)
                    if testName == action.name then
                        idx = action.id
                    end
                end
                if idx and type(idx) == "number" and idx > 0 and PickupMacro then
                    pcall(PickupMacro, idx)
                end

            elseif action.type == "item" then
                local pickupItemFn = (C_Item and C_Item.PickupItem) or PickupItem
                if action.id and pickupItemFn then
                    pcall(pickupItemFn, action.id)
                end
                if (GetCursorInfo and GetCursorInfo() == nil) and action.name and pickupItemFn then
                    pcall(pickupItemFn, action.name)
                end

            elseif action.type == "mount" or action.type == "summonmount" then
                if action.id == 268435455 or action.id == 0 then
                    if C_MountJournal and C_MountJournal.Pickup then
                        pcall(C_MountJournal.Pickup, 0)
                    end
                elseif action.id then
                    if C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local spellID = select(2, C_MountJournal.GetMountInfoByID(action.id))
                        if spellID then
                            SafePickupSpell(spellID)
                        end
                    end
                    if (GetCursorInfo and GetCursorInfo() == nil) and C_MountJournal and C_MountJournal.Pickup then
                        pcall(C_MountJournal.Pickup, action.id)
                    end
                    if (GetCursorInfo and GetCursorInfo() == nil) and PickupCompanion then
                        pcall(PickupCompanion, "MOUNT", action.id)
                    end
                end

            elseif action.type == "companion" then
                if PickupCompanion and action.id then
                    pcall(PickupCompanion, action.subType or "CRITTER", action.id)
                end

            elseif action.type == "equipmentset" then
                if action.id then
                    local setID = action.id
                    if type(setID) == "string" and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID then
                        setID = C_EquipmentSet.GetEquipmentSetID(action.id) or setID
                    end
                    if C_EquipmentSet and C_EquipmentSet.PickupEquipmentSet then
                        pcall(C_EquipmentSet.PickupEquipmentSet, setID)
                    elseif PickupEquipmentSetByName then
                        pcall(PickupEquipmentSetByName, action.id)
                    end
                end

            elseif action.type == "flyout" then
                if action.id then
                    if PickupFlyout then
                        pcall(PickupFlyout, action.id)
                    else
                        SafePickupSpell(action.id)
                    end
                end
            end

            if GetCursorInfo and GetCursorInfo() ~= nil then
                PlaceAction(slot)
                ClearCursor()
            end
        else
            -- Slot was empty in snapshot; clear if currently occupied
            if GetActionInfo(slot) ~= nil then
                PickupAction(slot)
                ClearCursor()
            end
        end
    end
    ClearCursor()

    -- 3. Restore Keybindings (Filter out BINDING_HEADER_ categories)
    if profile.bindings and SetBinding then
        ForEachBoundKey(function(key, command)
            if profile.bindings[key] ~= command then
                SetBinding(key, nil)
            end
        end)

        for key, command in pairs(profile.bindings) do
            if key and not string.find(key, "^BINDING_HEADER_") and command and not string.find(command, "^BINDING_HEADER_") then
                SetBinding(key, command)
            end
        end

        local bindSet = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
        if SaveBindings then
            pcall(SaveBindings, bindSet)
        end
    end

    print(string.format("|cff00ccff[ZeroMaint]|r Profile '|cffffd100%s|r' loaded and applied!", name))
    return true
end
Profiles.RestoreProfile = RestoreProfile
ns.RestoreProfile = RestoreProfile

--------------------------------------------------------------------------------
-- 4. PROFILE LISTING & DELETION
--------------------------------------------------------------------------------

local function ListProfiles()
    local db = ns.db or ZeroMaintDB
    if not db or not db.profiles or next(db.profiles) == nil then
        print("|cff00ccff[ZeroMaint]|r No profiles saved yet. Use |cffffd100/z save <profile>|r to create one.")
        return
    end

    print("|cff00ccff[ZeroMaint]|r Saved Profiles:")
    for name, p in pairs(db.profiles) do
        local numActions = 0
        if p.actions then
            for _ in pairs(p.actions) do numActions = numActions + 1 end
        end
        local numBinds = 0
        if p.bindings then
            for _ in pairs(p.bindings) do numBinds = numBinds + 1 end
        end
        local numMacros = (p.macros and #p.macros) or 0
        print(string.format("  - |cffffd100%s|r (%s) | %d actions, %d binds, %d macros | Created: %s",
            name, p.class or "Universal", numActions, numBinds, numMacros, p.created or "N/A"))
    end
end
Profiles.ListProfiles = ListProfiles
ns.ListProfiles = ListProfiles

local function DeleteProfile(name)
    if not name or name == "" then
        print("|cff00ccff[ZeroMaint]|r Usage: |cffffd100/z delete <profile>|r")
        return false
    end

    if InCombatLockdown() then
        print("|cff00ccff[ZeroMaint]|r |cffff0000Cannot delete profile in combat!|r")
        return false
    end

    local db = ns.db or ZeroMaintDB
    if not db or not db.profiles then
        print(string.format("|cff00ccff[ZeroMaint]|r Profile '|cffff0000%s|r' not found.", name))
        return false
    end

    local resolvedKey = nil
    if db.profiles[name] then
        resolvedKey = name
    else
        for k in pairs(db.profiles) do
            if k:lower() == name:lower() then
                resolvedKey = k
                break
            end
        end
    end

    if resolvedKey then
        db.profiles[resolvedKey] = nil
        print(string.format("|cff00ccff[ZeroMaint]|r Profile '|cffffd100%s|r' deleted.", resolvedKey))
        return true
    else
        print(string.format("|cff00ccff[ZeroMaint]|r Profile '|cffff0000%s|r' not found.", name))
        return false
    end
end
Profiles.DeleteProfile = DeleteProfile
ns.DeleteProfile = DeleteProfile

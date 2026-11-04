--[[
    ZeroMaint - Streamer Safe-Zone Engine & Frame Clamping (Pillar 1)
    File: ZeroMaint_Layout.lua
    
    Responsibilities:
      1. Virtual 16:9 safe-zone container and streamer alignment border.
      2. Synchronous zero-flicker UI panel clamping (Quest, Character, Gossip, Bank, etc.).
      3. Combat HUD crosshair positioning (Player, Target, Focus, ToT, Pet, Castbar).
      4. Peripheral element clamping (Minimap, Quest Tracker, Chat, Bags, Durability, Side Bars).
      5. Persistent SetPoint hooks preventing Blizzard edge-docking overrides.
      6. Protected layout updates guarded against in-combat execution taint.
]]

local addonName, ns = ...
local Layout = ns.Layout or {}
ns.Layout = Layout

local pendingUpdate = false
local isRealigningPanels = false
local isMoving = {}
local activeTimers = {}

local function Defer(key, delay, fn)
    if activeTimers[key] or not (C_Timer and C_Timer.After) then return end
    activeTimers[key] = true
    C_Timer.After(delay, function()
        activeTimers[key] = false
        if not InCombatLockdown() then fn() else pendingUpdate = true end
    end)
end

--------------------------------------------------------------------------------
-- 1. VIRTUAL SAFE ZONE & OBS CALIBRATION BORDER
--------------------------------------------------------------------------------

local VirtualSafeZone = CreateFrame("Frame", "ZeroMaint_SafeZone", UIParent)
VirtualSafeZone:SetFrameStrata("BACKGROUND")
VirtualSafeZone:SetFrameLevel(0)
ns.VirtualSafeZone = VirtualSafeZone

local BorderOverlay = CreateFrame("Frame", "ZeroMaint_BorderOverlay", VirtualSafeZone)
BorderOverlay:SetAllPoints(VirtualSafeZone)
BorderOverlay:SetFrameStrata("TOOLTIP")
BorderOverlay:Hide()
ns.BorderOverlay = BorderOverlay

local function CreateBorderLines(f)
    local col = { r = 0, g = 0.8, b = 1, a = 0.85 } -- Cyan stream border
    local thickness = 3

    local t = f:CreateTexture(nil, "OVERLAY")
    ns.SetSolidColor(t, col.r, col.g, col.b, col.a)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    t:SetHeight(thickness)

    local b = f:CreateTexture(nil, "OVERLAY")
    ns.SetSolidColor(b, col.r, col.g, col.b, col.a)
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(thickness)

    local l = f:CreateTexture(nil, "OVERLAY")
    ns.SetSolidColor(l, col.r, col.g, col.b, col.a)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    l:SetWidth(thickness)

    local r = f:CreateTexture(nil, "OVERLAY")
    ns.SetSolidColor(r, col.r, col.g, col.b, col.a)
    r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    r:SetWidth(thickness)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    label:SetPoint("TOP", f, "TOP", 0, -15)
    label:SetText("|cff00ccff[ZeroMaint]|r 16:9 Stream Safe Zone Boundary (OBS Crop Area)")
end
CreateBorderLines(BorderOverlay)

local function UpdateVirtualSafeZone(m)
    VirtualSafeZone:ClearAllPoints()
    VirtualSafeZone:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    VirtualSafeZone:SetSize(m.safeWidth, m.safeHeight)
end

--------------------------------------------------------------------------------
-- 2. BLIZZARD EDGE OVERRIDE SUPPRESSION & PANEL CLAMPING
--------------------------------------------------------------------------------

local function GetObjectiveTrackerFrame()
    return WatchFrame or ObjectiveTrackerFrame or QuestWatchFrame
end

local function DisableBlizzardEdgeOverrides()
    if UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS["ChatFrame1"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["MinimapCluster"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["WatchFrame"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["ObjectiveTrackerFrame"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["QuestWatchFrame"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["DurabilityFrame"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["PartyMemberFrame1"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["CompactRaidFrameManager"] = nil
        -- Note: BuffFrame is intentionally excluded to prevent UI taint in Blizzard aura timers
    end

    local tracker = GetObjectiveTrackerFrame()
    if tracker then
        tracker.ignoreFramePositionManager = true
        if tracker.BreakFromFrameManager then
            pcall(tracker.BreakFromFrameManager, tracker)
        end
    end
    local rightContainer = GetRightManagedFrameContainer and GetRightManagedFrameContainer()
    if rightContainer and rightContainer.RemoveManagedFrame and tracker then
        pcall(rightContainer.RemoveManagedFrame, rightContainer, tracker)
    end
end

local MANAGED_PANEL_NAMES = {
    -- Core Character & Progression
    "CharacterFrame",
    "SpellBookFrame",
    "PlayerSpellsFrame",
    "TalentFrame",
    "ClassTalentFrame",
    "GenericTraitFrame",
    "MajorFactionRenownFrame",
    "AchievementFrame",
    "ReputationFrame",
    "TokenFrame",

    -- Questing & Lore
    "QuestFrame",
    "GossipFrame",
    "QuestLogFrame",
    "QuestLogPopupDetailFrame",
    "EncounterJournal",

    -- Commerce, Bags & NPCs
    "MerchantFrame",
    "MailFrame",
    "BankFrame",
    "GuildBankFrame",
    "AuctionFrame",
    "AuctionHouseFrame",
    "TradeFrame",
    "DressUpFrame",
    "WardrobeFrame",
    "ItemUpgradeFrame",
    "VoidStorageFrame",
    "TransmogrifyFrame",

    -- Professions & Crafting
    "TradeSkillFrame",
    "CraftFrame",
    "ProfessionsFrame",
    "ProfessionsCustomerOrdersFrame",

    -- Social & Grouping
    "FriendsFrame",
    "GuildFrame",
    "CommunitiesFrame",
    "LFGParentFrame",
    "LFDParentFrame",
    "PVEFrame",
    "PVPUIFrame",
    "ChallengesUI",
    "WeeklyRewardsFrame",

    -- Collections
    "CollectionsJournal",

    -- World & Travel
    "TaxiFrame",
    "TabardFrame",
    "GuildRegistrarFrame",
    "PetitionFrame",
    "ItemTextFrame",
    "AlliedRacesFrame",

    -- Utility & Configuration
    "HelpFrame",
    "MacroFrame",
    "SettingsPanel",
    "KeyBindingFrame",
    "ChannelFrame",
    "DelvesDashboardFrame",
    "DelvesCompanionAbilityListFrame",
}

local function RealignActiveUIPanels()
    if isRealigningPanels or InCombatLockdown() then
        if InCombatLockdown() then pendingUpdate = true end
        return
    end
    local m = ns.GetMetrics()
    if not m or m.hOffset <= 0 then return end

    isRealigningPanels = true

    pcall(function()
        local currentX = m.hOffset
        local handledFrames = {}

        -- 1. Standard Blizzard GetUIPanel Slots (doublewide, left, center, right)
        local double = GetUIPanel and GetUIPanel("doublewide")
        local left   = GetUIPanel and GetUIPanel("left")
        local center = GetUIPanel and GetUIPanel("center")
        local right  = GetUIPanel and GetUIPanel("right")

        local function AlignSlot(f, defaultWidth, advanceX)
            if not (f and f:IsShown()) then return false end
            handledFrames[f] = true
            local _, _, _, x, y = f:GetPoint(1)
            if not x or math.abs(x - currentX) > 2 then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", currentX, y or -104)
            end
            if advanceX then
                local w = (f:GetWidth() and f:GetWidth() > 0) and f:GetWidth() or defaultWidth
                currentX = currentX + w
            end
            return true
        end

        if not AlignSlot(double, 768, true) then AlignSlot(left, 384, true) end
        AlignSlot(center, 384, true)
        AlignSlot(right, 384, false)

        -- 2. Comprehensive Check for Standalone and LOD Panels
        for _, name in ipairs(MANAGED_PANEL_NAMES) do
            local f = _G[name]
            if f and f:IsShown() and not handledFrames[f] then
                handledFrames[f] = true
                local numPoints = f:GetNumPoints()
                if numPoints and numPoints > 0 then
                    local point, rel, relPoint, x, y = f:GetPoint(1)
                    local leftCoord = f:GetLeft()
                    if (point == "TOPLEFT" or point == "TOP" or not point) and (rel == UIParent or rel == nil or rel == "UIParent") then
                        if ((x or 0) < (m.hOffset - 1)) or ((leftCoord or 0) < (m.hOffset - 1)) then
                            local targetPanelX = (currentX > m.hOffset) and currentX or m.hOffset
                            f:ClearAllPoints()
                            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", targetPanelX, y or -104)
                            local w = (f:GetWidth() and f:GetWidth() > 0) and f:GetWidth() or 384
                            currentX = currentX + w
                        end
                    end
                end
            end
        end
    end)

    isRealigningPanels = false
end

--------------------------------------------------------------------------------
-- 3. COMBAT HUD REPOSITIONING (Screen Center Crosshair)
--------------------------------------------------------------------------------

local function RepositionCombatHUD()
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end

    local db = ns.db or ns.defaults
    local unitFrames = {
        { frame = PlayerFrame,    pos = db.player },
        { frame = TargetFrame,    pos = db.target },
        { frame = FocusFrame,     pos = db.focus  },
        { frame = TargetFrameToT, pos = db.tot    },
        { frame = PetFrame,       pos = db.pet    },
    }

    for _, data in ipairs(unitFrames) do
        local f = data.frame
        if f and data.pos then
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", data.pos.x, data.pos.y)
            if f.SetMovable then pcall(f.SetMovable, f, true) end
        end
    end

    local castBar = PlayerCastingBarFrame or CastingBarFrame
    if castBar and db.castBar then
        castBar:ClearAllPoints()
        castBar:SetPoint("CENTER", UIParent, "CENTER", db.castBar.x, db.castBar.y)
        if castBar.SetMovable then pcall(castBar.SetMovable, castBar, true) end
        if castBar.SetUserPlaced then pcall(castBar.SetUserPlaced, castBar, true) end
    end
end

--------------------------------------------------------------------------------
-- 4. BAGS & PERIPHERALS REPOSITIONING
--------------------------------------------------------------------------------

local function RepositionBags(m)
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not m then return end

    local db = ns.db or ns.defaults
    local defaultBagY = (db.minimapPosition == "bottom") and 305 or 40
    local bagOffsetX = (db.bags and db.bags.x) or -15
    local bagOffsetY = (db.bags and db.bags.y) or defaultBagY

    local targetX = -m.hOffset + bagOffsetX
    local targetY = bagOffsetY

    -- 1. Modern Container Frame Wrapper (Retail 10.2.5+ / Dragonflight)
    if ContainerFrameContainer then
        pcall(function()
            ContainerFrameContainer:ClearAllPoints()
            ContainerFrameContainer:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", targetX, targetY)
        end)
    end

    -- 2. Modern Combined Bags (Dragonflight 10.0+ / The War Within / Beta 1.60)
    if ContainerFrameCombinedBags then
        local parent = ContainerFrameCombinedBags:GetParent()
        if parent == UIParent or parent == nil or not ContainerFrameContainer then
            pcall(function()
                ContainerFrameCombinedBags:ClearAllPoints()
                ContainerFrameCombinedBags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", targetX, targetY)
            end)
        end
    end

    -- 3. Classic Individual Backpack (Vanilla 1.12 -> Wrath / Classic Era)
    if ContainerFrame1 and not ContainerFrameContainer then
        local parent = ContainerFrame1:GetParent()
        if parent == UIParent or parent == nil then
            pcall(function()
                ContainerFrame1:ClearAllPoints()
                ContainerFrame1:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", targetX, targetY)
            end)
        end
    end
end

local function RepositionBuffs(m)
    if InCombatLockdown() or isMoving.buffs then
        if InCombatLockdown() then pendingUpdate = true end
        return
    end
    if not m then return end

    local bf = BuffFrame or _G["BuffFrame"]
    if not bf then return end

    -- Never mark BuffFrame or DebuffFrame user-placed to prevent layout-local.txt taint
    if bf.SetUserPlaced and bf.IsUserPlaced and bf:IsUserPlaced() then
        pcall(bf.SetUserPlaced, bf, false)
    end

    local db = ns.db or ns.defaults
    local buffOffsetX = (db.buffs and db.buffs.x) or -15
    local buffOffsetY = (db.buffs and db.buffs.y) or -13

    -- If minimap is docked at the top right, shift buffs left so they do not overlap the minimap
    local isTopMinimap = (db.minimapPosition == "top")
    local mmWidth = (isTopMinimap and MinimapCluster and MinimapCluster:GetWidth()) or 200
    local mmExtraOffset = isTopMinimap and (mmWidth + 15) or 0

    local targetX = ns.GetEffectiveOffset(bf, -m.hOffset - mmExtraOffset + buffOffsetX)
    local targetY = ns.GetEffectiveOffset(bf, buffOffsetY)

    -- Guard: Strictly idempotent SetPoint only if coordinates drifted by > 2px
    local point, relTo, relPoint, curX, curY = bf:GetPoint(1)
    if point ~= "TOPRIGHT" or relTo ~= UIParent or not curX or math.abs(curX - targetX) > 2 or not curY or math.abs(curY - targetY) > 2 then
        isMoving.buffs = true
        pcall(function()
            bf:ClearAllPoints()
            bf:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", targetX, targetY)
        end)
        isMoving.buffs = false
    end

    local df = DebuffFrame or _G["DebuffFrame"]
    if df then
        if df.SetUserPlaced and df.IsUserPlaced and df:IsUserPlaced() then
            pcall(df.SetUserPlaced, df, false)
        end
        local dPoint, dRelTo, dRelPoint, dCurX, dCurY = df:GetPoint(1)
        -- In Modern/EditMode, DebuffFrame anchors to UIParent independently. If so, clamp into safe zone.
        -- If anchored to BuffFrame natively (Classic FrameXML), it follows BuffFrame automatically.
        if dRelTo == UIParent or dRelTo == nil then
            local targetDfX = ns.GetEffectiveOffset(df, -m.hOffset - mmExtraOffset + buffOffsetX)
            local targetDfY = dCurY or -155
            if not dCurX or math.abs(dCurX - targetDfX) > 2 then
                isMoving.buffs = true
                pcall(function()
                    df:ClearAllPoints()
                    df:SetPoint(dPoint or "TOPRIGHT", UIParent, dRelPoint or "TOPRIGHT", targetDfX, targetDfY)
                end)
                isMoving.buffs = false
            end
        end
    end
end

local function UpdateRaidManagerAppearance()
    local manager = CompactRaidFrameManager or _G["CompactRaidFrameManager"]
    if not manager then return end
    local isCollapsed = manager.collapsed

    pcall(function()
        local alpha = isCollapsed and 0 or 1
        if manager.SetBackdropColor then manager:SetBackdropColor(0.05, 0.05, 0.05, isCollapsed and 0 or 0.85) end
        if manager.SetBackdropBorderColor then manager:SetBackdropBorderColor(0.6, 0.6, 0.6, alpha) end
        if manager.NineSlice then manager.NineSlice:SetAlpha(alpha) end
        for i = 1, select("#", manager:GetRegions()) do
            local region = select(i, manager:GetRegions())
            if region and region:IsObjectType("Texture") then region:SetAlpha(alpha) end
        end

        -- Keep all toggle arrow button variants 100% visible and interactive at the safe-zone line
        local toggleBtns = { manager.toggleButton, manager.toggleButtonForward, manager.toggleButtonBack }
        for _, btn in ipairs(toggleBtns) do
            if btn then
                btn:SetAlpha(1)
                if btn.GetNormalTexture and btn:GetNormalTexture() then
                    btn:GetNormalTexture():SetAlpha(1)
                end
            end
        end
    end)
end

local function RepositionRaidFrames(m)
    if InCombatLockdown() or isMoving.raid then
        if InCombatLockdown() then pendingUpdate = true end
        return
    end
    if not m then return end
    local manager = CompactRaidFrameManager or _G["CompactRaidFrameManager"]
    if not manager then return end

    isMoving.raid = true
    pcall(function()
        local db = ns.db or ns.defaults
        local raidOffsetX = (db.raid and db.raid.x) or 0
        local raidOffsetY = (db.raid and db.raid.y) or -140

        local isCollapsed = manager.collapsed
        if isCollapsed == nil and manager.displayFrame then
            isCollapsed = not manager.displayFrame:IsShown()
        end
        if CompactRaidFrameManager_GetSetting and CompactRaidFrameManager_GetSetting("IsShown") == "0" then
            isCollapsed = true
        end

        local baseX = -7
        if isCollapsed then
            baseX = (manager.toggleButtonForward and -200) or -182
        end

        local targetX = ns.GetEffectiveOffset(manager, m.hOffset + baseX + raidOffsetX)
        local targetY = ns.GetEffectiveOffset(manager, raidOffsetY)

        manager:SetMovable(true)
        manager:SetClampedToScreen(false)
        manager:ClearAllPoints()
        manager:SetPoint("TOPLEFT", UIParent, "TOPLEFT", targetX, targetY)

        UpdateRaidManagerAppearance()

        -- Only manage CompactRaidFrameContainer directly if it is detached and parented to UIParent (Retail EditMode).
        -- In Classic FrameXML, container is a child of manager/containerResizeFrame and moves with it automatically.
        local container = CompactRaidFrameContainer or _G["CompactRaidFrameContainer"]
        if container and container:GetParent() == UIParent then
            local left = container:GetLeft()
            if not left or left < (m.hOffset + 8) then
                if container.SetMovable then pcall(container.SetMovable, container, true) end
                if container.SetClampedToScreen then pcall(container.SetClampedToScreen, container, false) end
                local pHeight = (UIParent and UIParent:GetHeight()) or 1080
                local top = container:GetTop()
                local targetContY = top and (top - pHeight) or -140
                local targetContX = ns.GetEffectiveOffset(container, m.hOffset + 10)
                container:ClearAllPoints()
                container:SetPoint("TOPLEFT", UIParent, "TOPLEFT", targetContX, targetContY)
                if container.SetUserPlaced and container.IsUserPlaced and container:IsUserPlaced() then
                    pcall(container.SetUserPlaced, container, false)
                end
            end
        end
    end)
    isMoving.raid = false
end

local function RepositionPartyFrames(m)
    if InCombatLockdown() or isMoving.party then
        if InCombatLockdown() then pendingUpdate = true end
        return
    end
    if not m then return end

    local db = ns.db or ns.defaults
    local partyOffsetX = (db.party and db.party.x) or 20
    local partyOffsetY = (db.party and db.party.y) or -160

    isMoving.party = true
    pcall(function()
        -- 1. Classic PartyMemberFrame1 (chains PartyMemberFrame2..4)
        local p1 = PartyMemberFrame1 or _G["PartyMemberFrame1"]
        if p1 and p1.GetParent and (p1:GetParent() == UIParent or p1:GetParent() == nil) then
            local targetX = ns.GetEffectiveOffset(p1, m.hOffset + partyOffsetX)
            local targetY = ns.GetEffectiveOffset(p1, partyOffsetY)
            p1:SetMovable(true)
            p1:SetClampedToScreen(false)
            p1:ClearAllPoints()
            p1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", targetX, targetY)
            if p1.SetUserPlaced then p1:SetUserPlaced(true) end
        end

        -- 2. Modern Retail / EditMode PartyFrame container
        local partyFrame = PartyFrame or _G["PartyFrame"]
        if partyFrame and partyFrame.GetParent and (partyFrame:GetParent() == UIParent or partyFrame:GetParent() == nil) then
            local targetX = ns.GetEffectiveOffset(partyFrame, m.hOffset + partyOffsetX)
            local targetY = ns.GetEffectiveOffset(partyFrame, partyOffsetY)
            partyFrame:ClearAllPoints()
            partyFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", targetX, targetY)
        end
    end)
    isMoving.party = false
end

local function RepositionBossAndArenaFrames(m)
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not m then return end

    local db = ns.db or ns.defaults
    local bossOffsetX = (db.boss and db.boss.x) or -40
    local bossOffsetY = (db.boss and db.boss.y) or -260
    local arenaOffsetX = (db.arena and db.arena.x) or -40
    local arenaOffsetY = (db.arena and db.arena.y) or 0

    -- 1. Boss Target Frames
    local boss = BossTargetFrameContainer or Boss1TargetFrame or _G["BossTargetFrameContainer"] or _G["Boss1TargetFrame"]
    if boss and boss.GetParent and (boss:GetParent() == UIParent or boss:GetParent() == nil) then
        pcall(function()
            boss:ClearAllPoints()
            local targetX = ns.GetEffectiveOffset(boss, -m.hOffset + bossOffsetX)
            local targetY = ns.GetEffectiveOffset(boss, bossOffsetY)
            boss:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", targetX, targetY)
        end)
    end

    -- 2. Arena Enemy Frames
    local arena = ArenaEnemyFrames or CompactArenaFrame or ArenaEnemyFrame1 or _G["ArenaEnemyFrames"] or _G["CompactArenaFrame"]
    if arena and arena.GetParent and (arena:GetParent() == UIParent or arena:GetParent() == nil) then
        pcall(function()
            arena:ClearAllPoints()
            local targetX = ns.GetEffectiveOffset(arena, -m.hOffset + arenaOffsetX)
            local targetY = ns.GetEffectiveOffset(arena, arenaOffsetY)
            arena:SetPoint("RIGHT", UIParent, "RIGHT", targetX, targetY)
        end)
    end

    -- 3. Battleground / Delve / Minimap Objective Widget
    local bgWidget = UIWidgetBelowMinimapContainerFrame or _G["UIWidgetBelowMinimapContainerFrame"]
    if bgWidget then
        pcall(function()
            bgWidget:ClearAllPoints()
            if db.minimapPosition == "bottom" then
                local tracker = GetObjectiveTrackerFrame()
                if tracker and tracker:IsShown() then
                    bgWidget:SetPoint("TOP", tracker, "BOTTOM", 0, -15)
                else
                    bgWidget:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -m.hOffset - 20, -220)
                end
            else
                if MinimapCluster and MinimapCluster:IsShown() then
                    bgWidget:SetPoint("TOP", MinimapCluster, "BOTTOM", 0, -15)
                else
                    bgWidget:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -m.hOffset - 20, -220)
                end
            end
        end)
    end
end

local function RepositionObjectiveTracker(m)
    if InCombatLockdown() or isMoving.tracker then
        if InCombatLockdown() then pendingUpdate = true end
        return
    end
    if not m then return end

    local tracker = GetObjectiveTrackerFrame()
    if not tracker then return end

    isMoving.tracker = true
    pcall(function()
        local db = ns.db or ns.defaults

        -- Break tracker from right managed frame container in Retail Edit Mode so Blizzard stops forcing it to the screen edge
        if tracker.BreakFromFrameManager then
            pcall(tracker.BreakFromFrameManager, tracker)
        end
        tracker.ignoreFramePositionManager = true

        local rightContainer = GetRightManagedFrameContainer and GetRightManagedFrameContainer()
        if rightContainer and rightContainer.RemoveManagedFrame then
            pcall(rightContainer.RemoveManagedFrame, rightContainer, tracker)
        end

        if tracker.SetMovable then pcall(tracker.SetMovable, tracker, true) end
        if tracker.SetClampedToScreen then pcall(tracker.SetClampedToScreen, tracker, false) end
        tracker:ClearAllPoints()

        local trkOffsetX = (db.tracker and db.tracker.x) or -20
        local defaultTrk_Y = (db.minimapPosition == "bottom") and -220 or -260
        local trkOffsetY = (db.tracker and db.tracker.y) or defaultTrk_Y
        local targetTrk_X = ns.GetEffectiveOffset(tracker, -m.hOffset + trkOffsetX)
        local targetTrk_Y = ns.GetEffectiveOffset(tracker, trkOffsetY)
        tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", targetTrk_X, targetTrk_Y)
        if tracker.SetUserPlaced then pcall(tracker.SetUserPlaced, tracker, true) end
    end)
    isMoving.tracker = false
end

local function RepositionPeripherals(m)
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not m then return end
    DisableBlizzardEdgeOverrides()

    local db = ns.db or ns.defaults

    -- 1. Chat Frame (Lock to 16:9 bottom-left)
    if ChatFrame1 and not isMoving.chat then
        isMoving.chat = true
        ChatFrame1:ClearAllPoints()
        local chatX = (db.chat and db.chat.x) or 35
        local chatY = (db.chat and db.chat.y) or 45
        local targetChatX = ns.GetEffectiveOffset(ChatFrame1, m.hOffset + chatX)
        local targetChatY = ns.GetEffectiveOffset(ChatFrame1, chatY)
        ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", targetChatX, targetChatY)
        ChatFrame1:SetUserPlaced(true)
        if FCF_SavePositionAndDimensions and m.hOffset > 0 then
            pcall(FCF_SavePositionAndDimensions, ChatFrame1)
        end
        isMoving.chat = false
    end

    -- 2. Minimap (Bottom-Right or Top-Right of Safe Zone)
    local mm = MinimapCluster
    if mm and not isMoving.minimap then
        isMoving.minimap = true
        mm:SetMovable(true)
        mm:SetClampedToScreen(false)
        mm:ClearAllPoints()
        local mmOffsetX = (db.minimap and db.minimap.x) or -15
        local defaultMM_Y = (db.minimapPosition == "bottom") and 35 or -15
        local mmOffsetY = (db.minimap and db.minimap.y) or defaultMM_Y
        local mmPoint = (db.minimapPosition == "bottom") and "BOTTOMRIGHT" or "TOPRIGHT"
        local targetMM_X = ns.GetEffectiveOffset(mm, -m.hOffset + mmOffsetX)
        local targetMM_Y = ns.GetEffectiveOffset(mm, mmOffsetY)
        mm:SetPoint(mmPoint, UIParent, mmPoint, targetMM_X, targetMM_Y)
        mm:SetUserPlaced(true)
        isMoving.minimap = false
    end

    -- 3. Objective Tracker / WatchFrame
    RepositionObjectiveTracker(m)

    -- 4. Bags Docking
    RepositionBags(m)

    -- 5. Side Action Bars (MultiBarRight, MultiBarLeft)
    if MultiBarRight and not (EditModeManagerFrame and MultiBarRight.systemIndex) then
        MultiBarRight:ClearAllPoints()
        local barX = ns.GetEffectiveOffset(MultiBarRight, -m.hOffset - 5)
        MultiBarRight:SetPoint("RIGHT", UIParent, "RIGHT", barX, 0)
        if MultiBarRight.IsMovable and MultiBarRight:IsMovable() and MultiBarRight.SetUserPlaced then
            pcall(MultiBarRight.SetUserPlaced, MultiBarRight, true)
        end
    end
    if MultiBarLeft and MultiBarRight and not (EditModeManagerFrame and MultiBarLeft.systemIndex) then
        MultiBarLeft:ClearAllPoints()
        MultiBarLeft:SetPoint("TOPRIGHT", MultiBarRight, "TOPLEFT", -5, 0)
        if MultiBarLeft.IsMovable and MultiBarLeft:IsMovable() and MultiBarLeft.SetUserPlaced then
            pcall(MultiBarLeft.SetUserPlaced, MultiBarLeft, true)
        end
    end

    -- 6. Durability Frame (Armor Doll)
    if DurabilityFrame then
        DurabilityFrame:ClearAllPoints()
        if db.minimapPosition == "bottom" then
            DurabilityFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -(m.hOffset + 215), 40)
        else
            DurabilityFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -(m.hOffset + 215), -15)
        end
    end

    -- 7. Buff & Debuff Frames
    RepositionBuffs(m)

    -- 8. Raid Manager & Container
    RepositionRaidFrames(m)

    -- 9. Classic Party Frames / Modern PartyFrame
    RepositionPartyFrames(m)

    -- 10. Boss & Arena / Battleground Widget Frames
    RepositionBossAndArenaFrames(m)
end

--------------------------------------------------------------------------------
-- 5. HOOKS & SYSTEM INTEGRATIONS
--------------------------------------------------------------------------------

local function InstallChatHook()
    if ChatFrame1 and not ChatFrame1._ZeroMaintChatHooked then
        ChatFrame1._ZeroMaintChatHooked = true
        hooksecurefunc(ChatFrame1, "SetPoint", function(self, point, relativeTo, relativePoint, x, y)
            if isMoving.chat or InCombatLockdown() then
                if InCombatLockdown() then pendingUpdate = true end
                return
            end
            local m = ns.GetMetrics()
            if m.hOffset <= 0 then return end

            local db = ns.db or ns.defaults
            if point == "BOTTOMLEFT" and (relativeTo == UIParent or relativeTo == nil or relativeTo == "UIParent") then
                local chatX = (db.chat and db.chat.x) or 35
                local chatY = (db.chat and db.chat.y) or 45
                local targetX = ns.GetEffectiveOffset(self, m.hOffset + chatX)
                local targetY = ns.GetEffectiveOffset(self, chatY)
                if math.abs((x or 0) - targetX) > 2 or math.abs((y or 0) - targetY) > 2 then
                    isMoving.chat = true
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", targetX, targetY)
                    self:SetUserPlaced(true)
                    if FCF_SavePositionAndDimensions then
                        pcall(FCF_SavePositionAndDimensions, self)
                    end
                    isMoving.chat = false
                end
            end
        end)
    end
end

local function InstallMinimapHook()
    local mm = MinimapCluster
    if mm and not mm._ZeroMaintMinimapHooked then
        mm._ZeroMaintMinimapHooked = true
        mm:SetMovable(true)
        mm:SetClampedToScreen(false)
        hooksecurefunc(mm, "SetPoint", function(self, point, relativeTo, relativePoint, x, y)
            if isMoving.minimap or InCombatLockdown() then
                if InCombatLockdown() then pendingUpdate = true end
                return
            end
            local m = ns.GetMetrics()
            if m.hOffset <= 0 then return end

            local db = ns.db or ns.defaults
            local targetPoint = (db.minimapPosition == "bottom") and "BOTTOMRIGHT" or "TOPRIGHT"
            local mmOffsetX = (db.minimap and db.minimap.x) or -15
            local defaultMM_Y = (db.minimapPosition == "bottom") and 35 or -15
            local mmOffsetY = (db.minimap and db.minimap.y) or defaultMM_Y
            local targetX = ns.GetEffectiveOffset(self, -m.hOffset + mmOffsetX)
            local targetY = ns.GetEffectiveOffset(self, mmOffsetY)

            if point ~= targetPoint or math.abs((x or 0) - targetX) > 2 or math.abs((y or 0) - targetY) > 2 then
                isMoving.minimap = true
                self:ClearAllPoints()
                self:SetPoint(targetPoint, UIParent, targetPoint, targetX, targetY)
                self:SetUserPlaced(true)
                isMoving.minimap = false
            end
        end)
    end
end

local function DeferredRepositionTracker()
    if InCombatLockdown() then pendingUpdate = true; return end
    local m = ns.GetMetrics()
    if m.hOffset <= 0 then return end
    RepositionObjectiveTracker(m)
    RepositionBossAndArenaFrames(m)
    Defer("tracker", 0.05, function()
        local curM = ns.GetMetrics()
        if curM.hOffset > 0 then
            RepositionObjectiveTracker(curM)
            RepositionBossAndArenaFrames(curM)
        end
    end)
end

local function InstallTrackerHook()
    -- 1. Persistent SetPoint and lifecycle hooks on all tracker frame variants
    local trackerFrames = { WatchFrame, ObjectiveTrackerFrame, QuestWatchFrame }
    for _, tracker in ipairs(trackerFrames) do
        if tracker and not tracker._ZeroMaintTrackerHooked then
            tracker._ZeroMaintTrackerHooked = true
            if tracker.SetMovable then pcall(tracker.SetMovable, tracker, true) end
            if tracker.SetClampedToScreen then pcall(tracker.SetClampedToScreen, tracker, false) end
            hooksecurefunc(tracker, "SetPoint", function(self, point, relativeTo, relativePoint, x, y)
                if isMoving.tracker or InCombatLockdown() then
                    if InCombatLockdown() then pendingUpdate = true end
                    return
                end
                local m = ns.GetMetrics()
                if m.hOffset <= 0 then return end

                local db = ns.db or ns.defaults
                local targetPoint = "TOPRIGHT"
                local trkOffsetX = (db.tracker and db.tracker.x) or -20
                local defaultTrk_Y = (db.minimapPosition == "bottom") and -220 or -260
                local trkOffsetY = (db.tracker and db.tracker.y) or defaultTrk_Y
                local targetX = ns.GetEffectiveOffset(self, -m.hOffset + trkOffsetX)
                local targetY = ns.GetEffectiveOffset(self, trkOffsetY)

                local isUIParent = (relativeTo == UIParent or relativeTo == nil or relativeTo == "UIParent")
                if point ~= targetPoint or not isUIParent or math.abs((x or 0) - targetX) > 2 or math.abs((y or 0) - targetY) > 2 then
                    isMoving.tracker = true
                    pcall(function()
                        self:ClearAllPoints()
                        self:SetPoint(targetPoint, UIParent, targetPoint, targetX, targetY)
                        if self.SetUserPlaced then pcall(self.SetUserPlaced, self, true) end
                    end)
                    isMoving.tracker = false
                end
            end)

            if tracker.HookScript and not tracker._ZeroMaintOnSizeHooked then
                tracker._ZeroMaintOnSizeHooked = true
                pcall(tracker.HookScript, tracker, "OnSizeChanged", function()
                    if isMoving.tracker or InCombatLockdown() then
                        if InCombatLockdown() then pendingUpdate = true end
                        return
                    end
                    local m = ns.GetMetrics()
                    if m.hOffset <= 0 then return end
                    local trkRight = tracker:GetRight()
                    local pWidth = (UIParent and UIParent:GetWidth()) or m.parentWidth
                    if trkRight and pWidth then
                        local displayTrk_X = trkRight - pWidth
                        local db = ns.db or ns.defaults
                        local trkOffsetX = (db.tracker and db.tracker.x) or -20
                        local targetTrk_X = -(m.hOffset + math.abs(trkOffsetX))
                        if math.abs(displayTrk_X - targetTrk_X) > 10 then
                            DeferredRepositionTracker()
                        end
                    end
                end)
            end

            if tracker.HookScript and not tracker._ZeroMaintOnShowHooked then
                tracker._ZeroMaintOnShowHooked = true
                pcall(tracker.HookScript, tracker, "OnShow", function()
                    if not InCombatLockdown() then
                        DeferredRepositionTracker()
                    else
                        pendingUpdate = true
                    end
                end)
            end
        end
    end

    -- 2. Global Blizzard Collapse/Expand/Toggle Functions
    for _, fnName in ipairs({"ObjectiveTracker_Collapse", "ObjectiveTracker_Expand", "ObjectiveTracker_Toggle", "WatchFrame_Collapse", "WatchFrame_Expand"}) do
        if type(_G[fnName]) == "function" and not ns["_hook_" .. fnName] then
            ns["_hook_" .. fnName] = true
            hooksecurefunc(fnName, DeferredRepositionTracker)
        end
    end

    -- 3. Frame & Manager Object-Level Methods (Retail Dragonflight / TWW / Midnight)
    local objTrackers = { ObjectiveTrackerFrame, WatchFrame }
    for _, trk in ipairs(objTrackers) do
        if trk then
            for _, method in ipairs({"SetCollapsed", "ToggleCollapsed"}) do
                if type(trk[method]) == "function" and not trk["_ZeroMaint" .. method .. "Hooked"] then
                    trk["_ZeroMaint" .. method .. "Hooked"] = true
                    hooksecurefunc(trk, method, DeferredRepositionTracker)
                end
            end
            if type(trk.Update) == "function" and not trk._ZeroMaintUpdateHooked then
                trk._ZeroMaintUpdateHooked = true
                hooksecurefunc(trk, "Update", function()
                    if not InCombatLockdown() then
                        local m = ns.GetMetrics()
                        if m.hOffset > 0 then
                            local trkRight = trk:GetRight()
                            local pWidth = (UIParent and UIParent:GetWidth()) or m.parentWidth
                            if trkRight and pWidth then
                                local displayTrk_X = trkRight - pWidth
                                local db = ns.db or ns.defaults
                                local trkOffsetX = (db.tracker and db.tracker.x) or -20
                                local targetTrk_X = -(m.hOffset + math.abs(trkOffsetX))
                                if math.abs(displayTrk_X - targetTrk_X) > 10 then
                                    DeferredRepositionTracker()
                                end
                            end
                        end
                    else
                        pendingUpdate = true
                    end
                end)
            end
        end
    end

    if ObjectiveTrackerManager then
        if type(ObjectiveTrackerManager.SetCollapsed) == "function" and not ObjectiveTrackerManager._ZeroMaintSetCollapsedHooked then
            ObjectiveTrackerManager._ZeroMaintSetCollapsedHooked = true
            hooksecurefunc(ObjectiveTrackerManager, "SetCollapsed", DeferredRepositionTracker)
        end
        if type(ObjectiveTrackerManager.UpdateAll) == "function" and not ObjectiveTrackerManager._ZeroMaintUpdateAllHooked then
            ObjectiveTrackerManager._ZeroMaintUpdateAllHooked = true
            hooksecurefunc(ObjectiveTrackerManager, "UpdateAll", DeferredRepositionTracker)
        end
    end

    -- 4. Header & Minimize Buttons across all client versions
    local minButtons = {
        ObjectiveTrackerFrame and ObjectiveTrackerFrame.Header and ObjectiveTrackerFrame.Header.MinimizeButton,
        ObjectiveTrackerFrame and ObjectiveTrackerFrame.HeaderMenu and ObjectiveTrackerFrame.HeaderMenu.MinimizeButton,
        WatchFrameCollapseExpandButton,
        WatchFrame and WatchFrame.Header and WatchFrame.Header.MinimizeButton,
    }
    for _, btn in ipairs(minButtons) do
        if btn and not btn._ZeroMaintBtnHooked then
            btn._ZeroMaintBtnHooked = true
            if btn.HookScript then
                pcall(btn.HookScript, btn, "OnClick", DeferredRepositionTracker)
            end
            if type(btn.SetCollapsed) == "function" then
                hooksecurefunc(btn, "SetCollapsed", DeferredRepositionTracker)
            end
        end
    end

    local headers = {
        ObjectiveTrackerFrame and ObjectiveTrackerFrame.Header,
        ObjectiveTrackerFrame and ObjectiveTrackerFrame.HeaderMenu,
    }
    for _, hdr in ipairs(headers) do
        if hdr and type(hdr.SetCollapsed) == "function" and not hdr._ZeroMaintHdrHooked then
            hdr._ZeroMaintHdrHooked = true
            hooksecurefunc(hdr, "SetCollapsed", DeferredRepositionTracker)
        end
    end
end

local function DeferredRepositionRaid()
    if InCombatLockdown() then pendingUpdate = true; return end
    local m = ns.GetMetrics()
    if m.hOffset <= 0 then return end
    RepositionRaidFrames(m)
    Defer("raid", 0.05, function()
        local curM = ns.GetMetrics()
        if curM.hOffset > 0 then
            RepositionRaidFrames(curM)
        end
    end)
end

local function InstallEditModeHooks()
    if EditModeManagerFrame and not EditModeManagerFrame._ZeroMaintManagerHooked then
        EditModeManagerFrame._ZeroMaintManagerHooked = true
        hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", function()
            if not InCombatLockdown() then ns.UpdateLayout() else pendingUpdate = true end
        end)
        hooksecurefunc(EditModeManagerFrame, "SelectLayout", function()
            if not InCombatLockdown() then ns.UpdateLayout() else pendingUpdate = true end
        end)
    end

    local peripheralFrames = { MinimapCluster, ChatFrame1, PartyFrame, BossTargetFrameContainer, ArenaEnemyFrames }
    for _, f in ipairs(peripheralFrames) do
        if f and f.ApplySystemAnchor and not f._ZeroMaintApplyAnchorHooked then
            f._ZeroMaintApplyAnchorHooked = true
            hooksecurefunc(f, "ApplySystemAnchor", function()
                if not InCombatLockdown() then
                    RepositionPeripherals(ns.GetMetrics())
                else
                    pendingUpdate = true
                end
            end)
        end
    end

    local specializedHooks = {
        { frame = ObjectiveTrackerFrame, fn = DeferredRepositionTracker },
        { frame = WatchFrame,            fn = DeferredRepositionTracker },
        { frame = CompactRaidFrameContainer or _G["CompactRaidFrameContainer"], fn = DeferredRepositionRaid },
    }
    for _, entry in ipairs(specializedHooks) do
        local f = entry.frame
        if f and f.ApplySystemAnchor and not f._ZeroMaintApplyAnchorHooked then
            f._ZeroMaintApplyAnchorHooked = true
            hooksecurefunc(f, "ApplySystemAnchor", function()
                if not InCombatLockdown() then
                    entry.fn()
                else
                    pendingUpdate = true
                end
            end)
        end
    end
end

local function InstallRaidHooks()
    local manager = CompactRaidFrameManager or _G["CompactRaidFrameManager"]
    if manager and not manager._ZeroMaintRaidHooked then
        manager._ZeroMaintRaidHooked = true
        hooksecurefunc(manager, "SetPoint", function(self, point, relTo, relPoint, x, y)
            if isMoving.raid or InCombatLockdown() then
                if InCombatLockdown() then pendingUpdate = true end
                return
            end
            local m = ns.GetMetrics()
            if m.hOffset <= 0 then return end
            -- Only trigger if Blizzard reset manager toward screen edge (< m.hOffset / 2)
            local currentX = x or 0
            if currentX < (m.hOffset / 2) then
                DeferredRepositionRaid()
            end
        end)

        for _, fnName in ipairs({"CompactRaidFrameManager_Toggle", "CompactRaidFrameManager_Expand", "CompactRaidFrameManager_Collapse", "CompactRaidFrameManager_UpdateShown"}) do
            if type(_G[fnName]) == "function" and not ns["_hook_" .. fnName] then
                ns["_hook_" .. fnName] = true
                hooksecurefunc(fnName, DeferredRepositionRaid)
            end
        end

        local raidToggleBtns = {
            manager.toggleButton,
            manager.toggleButtonForward,
            manager.toggleButtonBack
        }
        for _, btn in ipairs(raidToggleBtns) do
            if btn and not btn._ZeroMaintBtnHooked then
                btn._ZeroMaintBtnHooked = true
                if btn.HookScript then
                    pcall(btn.HookScript, btn, "OnClick", DeferredRepositionRaid)
                end
            end
        end

        if manager.HookScript then
            manager:HookScript("OnShow", function()
                UpdateRaidManagerAppearance()
                DeferredRepositionRaid()
            end)
        end
    end

    -- Only hook CompactRaidFrameContainer if parented to UIParent (Retail EditMode)
    local container = CompactRaidFrameContainer or _G["CompactRaidFrameContainer"]
    if container and container:GetParent() == UIParent and not container._ZeroMaintContainerHooked then
        container._ZeroMaintContainerHooked = true
        hooksecurefunc(container, "SetPoint", function(self, point, relTo, relPoint, x, y)
            if isMoving.raid or InCombatLockdown() then
                if InCombatLockdown() then pendingUpdate = true end
                return
            end
            local m = ns.GetMetrics()
            if m.hOffset <= 0 then return end
            local left = self:GetLeft()
            if left and left < (m.hOffset + 8) then
                DeferredRepositionRaid()
            end
        end)
    end
end

local function InstallPartyHook()
    local p1 = PartyMemberFrame1 or _G["PartyMemberFrame1"]
    if p1 and not p1._ZeroMaintPartyHooked then
        p1._ZeroMaintPartyHooked = true
        hooksecurefunc(p1, "SetPoint", function(self, point, relTo, relPoint, x, y)
            if isMoving.party or InCombatLockdown() then
                if InCombatLockdown() then pendingUpdate = true end
                return
            end
            local m = ns.GetMetrics()
            if m.hOffset <= 0 then return end
            RepositionPartyFrames(m)
        end)
    end
end

local function InstallBagHooks()
    if UpdateContainerFrameAnchors and not ns._ZeroMaintAnchorsHooked then
        ns._ZeroMaintAnchorsHooked = true
        hooksecurefunc("UpdateContainerFrameAnchors", function()
            if not InCombatLockdown() then
                RepositionBags(ns.GetMetrics())
            else
                pendingUpdate = true
            end
        end)
    end

    local bagFrames = { ContainerFrameCombinedBags, ContainerFrame1 }
    for _, f in ipairs(bagFrames) do
        if f and not f._ZeroMaintBagHooked then
            f._ZeroMaintBagHooked = true
            f:HookScript("OnShow", function()
                if not InCombatLockdown() then
                    RepositionBags(ns.GetMetrics())
                else
                    pendingUpdate = true
                end
            end)
        end
    end
end

local function HookPanelSynchronous(name)
    local f = _G[name]
    if f and not f._ZeroMaintSynchronousHooked then
        f._ZeroMaintSynchronousHooked = true
        f:HookScript("OnShow", function()
            if not InCombatLockdown() then
                RealignActiveUIPanels()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if not InCombatLockdown() then
                            RealignActiveUIPanels()
                        end
                    end)
                end
            else
                pendingUpdate = true
            end
        end)
    end
end

local function HookAllAvailablePanels()
    for _, name in ipairs(MANAGED_PANEL_NAMES) do
        HookPanelSynchronous(name)
    end
end

local function InstallAllHooks()
    InstallChatHook()
    InstallMinimapHook()
    InstallTrackerHook()
    InstallRaidHooks()
    InstallPartyHook()
    InstallEditModeHooks()
    InstallBagHooks()
    HookAllAvailablePanels()
end

-- Global Panel Hooks (Installed once)
if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", RealignActiveUIPanels) end
if SetUIPanel then hooksecurefunc("SetUIPanel", RealignActiveUIPanels) end
if ShowUIPanel then hooksecurefunc("ShowUIPanel", RealignActiveUIPanels) end
if HideUIPanel then hooksecurefunc("HideUIPanel", RealignActiveUIPanels) end
if MoveUIPanel then hooksecurefunc("MoveUIPanel", RealignActiveUIPanels) end
if RestoreUIPanelArea then hooksecurefunc("RestoreUIPanelArea", RealignActiveUIPanels) end
if MaximizeUIPanel then hooksecurefunc("MaximizeUIPanel", RealignActiveUIPanels) end


if GameTooltip_SetDefaultAnchor then
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not tooltip or (tooltip.GetAnchorType and tooltip:GetAnchorType() ~= "ANCHOR_NONE") then return end
        local m = ns.GetMetrics()
        if m.hOffset > 0 then
            tooltip:ClearAllPoints()
            local db = ns.db or ns.defaults
            local tipOffsetX = (db.tooltip and db.tooltip.x) or -20
            local defaultTipY = (db.minimapPosition == "bottom") and 310 or 80
            local tipOffsetY = (db.tooltip and db.tooltip.y) or defaultTipY
            local targetX = ns.GetEffectiveOffset(tooltip, -m.hOffset + tipOffsetX)
            local targetY = ns.GetEffectiveOffset(tooltip, tipOffsetY)
            tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", targetX, targetY)
        end
    end)
end

--------------------------------------------------------------------------------
-- 6. PROTECTED UPDATE LAYOUT ENGINE
--------------------------------------------------------------------------------

function ns.UpdateLayout()
    local db = ns.db or ns.defaults
    if not db then return end
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end

    local m = ns.GetMetrics()
    UpdateVirtualSafeZone(m)
    RepositionCombatHUD()
    RepositionPeripherals(m)
    RealignActiveUIPanels()

    pendingUpdate = false
end
Layout.RealignAllUI = ns.UpdateLayout

--------------------------------------------------------------------------------
-- 7. EVENT REGISTRATIONS & LIFECYCLE
--------------------------------------------------------------------------------

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingUpdate then
        pendingUpdate = false
        ns.UpdateLayout()
    else
        RealignActiveUIPanels()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if not InCombatLockdown() then
                if pendingUpdate then
                    pendingUpdate = false
                    ns.UpdateLayout()
                else
                    RealignActiveUIPanels()
                end
            end
        end)
    end
end)

ns.RegisterEvent("ADDON_LOADED", function(arg1, arg2)
    local loaded = (arg1 == "ADDON_LOADED") and arg2 or arg1
    if loaded ~= (ns.name or addonName) and loaded and loaded:find("^Blizzard_") then
        HookAllAvailablePanels()
        if not InCombatLockdown() then
            RealignActiveUIPanels()
        end
        if loaded == "Blizzard_EditMode" or loaded == "Blizzard_ObjectiveTracker"
           or loaded == "Blizzard_CompactRaidFrames" or loaded == "Blizzard_ArenaUI" then
            InstallAllHooks()
            ns.UpdateLayout()
        end
    end
end)

ns.RegisterEvent("PLAYER_ALIVE", function()
    if not InCombatLockdown() then
        ns.UpdateLayout()
        RealignActiveUIPanels()
    else
        pendingUpdate = true
    end
end)

ns.RegisterEvent("PLAYER_UNGHOST", function()
    if not InCombatLockdown() then
        ns.UpdateLayout()
        RealignActiveUIPanels()
    else
        pendingUpdate = true
    end
end)

ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if not InCombatLockdown() then
        local m = ns.GetMetrics()
        RepositionRaidFrames(m)
        RepositionPartyFrames(m)
        RepositionBossAndArenaFrames(m)
        DeferredRepositionRaid()
    else
        pendingUpdate = true
    end
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    DisableBlizzardEdgeOverrides()
    InstallAllHooks()
    ns.UpdateLayout()
    Defer("entering_world", 0.25, function()
        InstallAllHooks()
        ns.UpdateLayout()
    end)
end)

ns.RegisterEvent("UI_SCALE_CHANGED", ns.UpdateLayout)
ns.RegisterEvent("DISPLAY_SIZE_CHANGED", ns.UpdateLayout)

ns.RegisterInit(function()
    InstallAllHooks()
    local db = ns.db or ns.defaults
    if db.showBorder then
        UpdateVirtualSafeZone(ns.GetMetrics())
        BorderOverlay:Show()
    end
    -- If UIParent is already sized (e.g. during /reload), apply immediately
    local m = ns.GetMetrics()
    if m.hOffset > 0 then
        ns.UpdateLayout()
    end
end)

--------------------------------------------------------------------------------
-- 8. LAYOUT API EXPORTS (For Command Dispatcher)
--------------------------------------------------------------------------------

function Layout.ToggleBorder()
    local db = ns.db or ns.defaults
    if BorderOverlay:IsShown() then
        BorderOverlay:Hide()
        db.showBorder = false
        print("|cff00ccff[ZeroMaint]|r Stream alignment border: |cffff0000OFF|r (Saved to WTF)")
    else
        ns.UpdateLayout()
        BorderOverlay:Show()
        db.showBorder = true
        print("|cff00ccff[ZeroMaint]|r Stream alignment border: |cff00ff00ON|r (Saved to WTF)")
    end
end

function Layout.SetMinimapPosition(arg)
    local db = ns.db or ns.defaults
    if arg == "top" or arg == "bottom" then
        db.minimapPosition = arg
    else
        db.minimapPosition = (db.minimapPosition == "bottom") and "top" or "bottom"
    end
    if not db.bags then db.bags = { x = -15, y = 305 } end
    db.bags.y = (db.minimapPosition == "top") and 40 or 305

    if not db.tracker then db.tracker = { x = -20, y = -220 } end
    db.tracker.y = (db.minimapPosition == "top") and -260 or -220

    print(string.format("|cff00ccff[ZeroMaint]|r Minimap position saved: |cffffd100%s-right|r of safe zone (Bags at Y=%d, Tracker at Y=%d) (Saved to WTF)", db.minimapPosition:upper(), db.bags.y, db.tracker.y))
    InstallAllHooks()
    ns.UpdateLayout()
end

function Layout.ToggleSafeZone()
    local db = ns.db or ns.defaults
    local newState = not ((db.enableSafeZone or db.clampAllTo16x9) ~= false)
    db.enableSafeZone = newState
    db.clampAllTo16x9 = newState
    print("|cff00ccff[ZeroMaint]|r 16:9 Stream Safe-Zone Clamping: " .. (newState and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r") .. " (Saved to WTF)")
    ns.UpdateLayout()
end

function Layout.Reset()
    BorderOverlay:Hide()
    InstallAllHooks()
    ns.UpdateLayout()
end

local ELEMENT_ALIASES = {
    cast = "castBar", castbar = "castBar", targettarget = "tot",
    bag = "bags", backpack = "bags", mochila = "bags", bags = "bags",
    map = "minimap", mini = "minimap", minimap = "minimap",
    chat = "chat", chatframe = "chat",
    tracker = "tracker", objectives = "tracker", quest = "tracker", watch = "tracker",
    tooltip = "tooltip", tip = "tooltip",
    buff = "buffs", buffs = "buffs", auras = "buffs",
    party = "party", partymembers = "party",
    raid = "raid", raidmanager = "raid",
    boss = "boss", bosses = "boss",
    arena = "arena", pvp = "arena",
}

function Layout.HandleMoveCommand(rawElement, rawX, rawY)
    local db = ns.db or ns.defaults
    local element = (rawElement or ""):lower()
    element = ELEMENT_ALIASES[element] or element

    local x = tonumber(rawX)
    local y = tonumber(rawY)

    if db[element] and type(db[element]) == "table" and x and y then
        db[element].x = x
        db[element].y = y
        
        if element == "player" or element == "target" or element == "focus" or element == "tot" or element == "pet" or element == "castBar" then
            RepositionCombatHUD()
        else
            RepositionPeripherals(ns.GetMetrics())
        end
        print(string.format("|cff00ccff[ZeroMaint]|r |cffffd100%s|r repositioned to (|cffffd100X=%d, Y=%d|r). (Saved to WTF)", element, x, y))
    else
        print("|cff00ccff[ZeroMaint]|r Usage: |cffffd100/z move <element> <X> <Y>|r")
        print("  |cff00ccffCombat HUD (offsets from screen center):|r")
        for _, k in ipairs({"player", "target", "focus", "tot", "pet", "castBar"}) do
            if db[k] then
                print(string.format("    |cffffd100%s|r: X=%d, Y=%d", k, db[k].x, db[k].y))
            end
        end
        print("  |cff00ccffSafe-Zone & Group Anchors:|r")
        for _, k in ipairs({"bags", "minimap", "chat", "tracker", "tooltip", "buffs", "party", "raid", "boss", "arena"}) do
            if db[k] then
                print(string.format("    |cffffd100%s|r: X=%d, Y=%d", k, db[k].x, db[k].y))
            end
        end
        print("  |cffff8800Tip:|r If bags overlap the map, try: |cffffd100/z move bags -15 310|r")
    end
end

function Layout.PrintDebug()
    local m = ns.GetMetrics()
    local db = ns.db or ns.defaults
    local pWidth = (UIParent and UIParent:GetWidth()) or m.parentWidth
    local pHeight = (UIParent and UIParent:GetHeight()) or m.parentHeight

    local function PrintFrameDiag(label, frame, targetX, targetY)
        if not frame then return end
        local pt, rel, relPt, x, y = frame:GetPoint(1)
        local curX = frame:GetLeft() or x or 0
        local curY = frame:GetBottom() or y or 0
        if pt and pt:find("RIGHT") and frame:GetRight() then
            curX = frame:GetRight() - pWidth
        end
        if pt and pt:find("TOP") and frame:GetTop() then
            curY = frame:GetTop() - pHeight
        end
        local extra = ""
        if targetX and targetY then
            extra = string.format(" (Target X=%.0f, Y=%.0f)", targetX, targetY)
        elseif targetX then
            extra = string.format(" (Target X=%.0f)", targetX)
        end
        print(string.format("%s: Frame=%s, Screen X=%.0f, Y=%.0f%s | Anchor=%s", 
            label, frame:GetName() or tostring(frame), curX, curY, extra, tostring(pt)))
    end

    -- 1. ChatFrame1 true screen position vs target
    local targetChatX = m.hOffset + ((db.chat and db.chat.x) or 35)
    local targetChatY = (db.chat and db.chat.y) or 45
    PrintFrameDiag("ChatFrame1", ChatFrame1, targetChatX, targetChatY)

    -- 2. MinimapCluster true screen position vs target
    local mm = MinimapCluster
    local defaultMM_Y = (db.minimapPosition == "bottom") and 35 or -15
    local targetMM_Y = (db.minimap and db.minimap.y) or defaultMM_Y
    local targetMM_X = -(m.hOffset - ((db.minimap and db.minimap.x) or -15))
    PrintFrameDiag("Minimap", mm, targetMM_X, targetMM_Y)

    -- 3. ObjectiveTrackerFrame true screen position vs target
    local trk = GetObjectiveTrackerFrame()
    local trkOffsetX = (db.tracker and db.tracker.x) or -20
    local defaultTrk_Y = (db.minimapPosition == "bottom") and -220 or -260
    local targetTrk_Y = (db.tracker and db.tracker.y) or defaultTrk_Y
    local targetTrk_X = -(m.hOffset + math.abs(trkOffsetX))
    PrintFrameDiag("Tracker", trk, targetTrk_X, targetTrk_Y)

    -- 4. BuffFrame & DebuffFrame true screen position vs target
    local bf = BuffFrame or _G["BuffFrame"]
    if bf then
        local isTopMinimap = (db.minimapPosition == "top")
        local mmWidth = (isTopMinimap and MinimapCluster and MinimapCluster:GetWidth()) or 200
        local mmExtraOffset = isTopMinimap and (mmWidth + 15) or 0
        local targetBF_X = -m.hOffset - mmExtraOffset + ((db.buffs and db.buffs.x) or -15)
        local targetBF_Y = (db.buffs and db.buffs.y) or -13
        PrintFrameDiag("Buffs", bf, targetBF_X, targetBF_Y)
    end
    local df = DebuffFrame or _G["DebuffFrame"]
    if df then
        PrintFrameDiag("Debuffs", df)
    end

    -- 5. Raid Manager & Container true screen position
    local manager = CompactRaidFrameManager or _G["CompactRaidFrameManager"]
    if manager then
        local isCollapsed = manager.collapsed
        local baseX = isCollapsed and ((manager.toggleButtonForward and -200) or -182) or -7
        local targetMgrX = m.hOffset + baseX + ((db.raid and db.raid.x) or 0)
        local targetMgrY = (db.raid and db.raid.y) or -140
        PrintFrameDiag("RaidManager", manager, targetMgrX, targetMgrY)
    end
    local container = CompactRaidFrameContainer or _G["CompactRaidFrameContainer"]
    if container then
        PrintFrameDiag("RaidContainer", container, m.hOffset + 10, -140)
    end
    local p1 = PartyMemberFrame1 or _G["PartyMemberFrame1"] or PartyFrame
    if p1 then
        local targetP1X = m.hOffset + ((db.party and db.party.x) or 20)
        local targetP1Y = (db.party and db.party.y) or -160
        PrintFrameDiag("Party1", p1, targetP1X, targetP1Y)
    end
end

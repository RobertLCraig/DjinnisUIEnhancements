local ADDON_NAME, ns = ...

local Mod = {}
ns.modules.EditMode = Mod

local print = ns.print or function() end

-- ---------------------------------------------------------------------------
-- Offset save: derive shared anchor offset from controller frame vs its boss
-- ---------------------------------------------------------------------------

local function saveOffsetFromController()
    local BT = ns.modules.BossTarget
    if not BT or not ns.db then return end
    local controller = BT.GetFrame(1)
    local bossFrame = BT.GetBossFrame(1)
    if not controller or not bossFrame then return end

    local cfg = ns.db.bossTarget
    local fx, fy = controller:GetCenter()
    local bx, by = bossFrame:GetCenter()
    if not (fx and fy and bx and by) then return end

    cfg.anchor.x = math.floor((fx - bx) + 0.5)
    cfg.anchor.y = math.floor((fy - by) + 0.5)
end

-- ---------------------------------------------------------------------------
-- Path A: LibEQOLEditMode integration (preferred — matches EnhanceQoL UX)
-- ---------------------------------------------------------------------------

local lib

local function refreshLib()
    if lib and lib.internal and lib.internal.RefreshSettings then
        lib.internal:RefreshSettings()
    end
    if lib and lib.internal and lib.internal.RefreshSettingValues then
        lib.internal:RefreshSettingValues()
    end
end
Mod.RefreshLib = refreshLib

local function buildSettings()
    local SettingType = lib.SettingType
    if not SettingType then return nil end

    local BT = ns.modules.BossTarget
    local function refresh()
        if BT and BT.ApplyLayout then BT.ApplyLayout() end
    end

    local settings = {}

    settings[#settings + 1] = {
        name = "Scale",
        kind = SettingType.Slider,
        default = ns.DEFAULTS.bossTarget.scale,
        minValue = 0.5,
        maxValue = 2.0,
        valueStep = 0.05,
        get = function() return ns.db.bossTarget.scale end,
        set = function(_, v) ns.db.bossTarget.scale = v; refresh() end,
        formatter = function(v) return ("%.2f"):format(v or 1) end,
    }

    settings[#settings + 1] = {
        name = "Width",
        kind = SettingType.Slider,
        default = ns.DEFAULTS.bossTarget.width,
        minValue = 100,
        maxValue = 400,
        valueStep = 1,
        get = function() return ns.db.bossTarget.width end,
        set = function(_, v) ns.db.bossTarget.width = math.floor(v + 0.5); refresh() end,
        formatter = function(v) return tostring(math.floor((v or 0) + 0.5)) end,
    }

    settings[#settings + 1] = {
        name = "Height",
        kind = SettingType.Slider,
        default = ns.DEFAULTS.bossTarget.height,
        minValue = 20,
        maxValue = 80,
        valueStep = 1,
        get = function() return ns.db.bossTarget.height end,
        set = function(_, v) ns.db.bossTarget.height = math.floor(v + 0.5); refresh() end,
        formatter = function(v) return tostring(math.floor((v or 0) + 0.5)) end,
    }

    settings[#settings + 1] = {
        name = "Offset X (from each boss frame center)",
        kind = SettingType.Slider,
        default = ns.DEFAULTS.bossTarget.anchor.x,
        minValue = -500,
        maxValue = 500,
        valueStep = 1,
        get = function() return ns.db.bossTarget.anchor.x end,
        set = function(_, v) ns.db.bossTarget.anchor.x = math.floor(v + 0.5); refresh() end,
        formatter = function(v) return tostring(math.floor((v or 0) + 0.5)) end,
    }

    settings[#settings + 1] = {
        name = "Offset Y (from each boss frame center)",
        kind = SettingType.Slider,
        default = ns.DEFAULTS.bossTarget.anchor.y,
        minValue = -500,
        maxValue = 500,
        valueStep = 1,
        get = function() return ns.db.bossTarget.anchor.y end,
        set = function(_, v) ns.db.bossTarget.anchor.y = math.floor(v + 0.5); refresh() end,
        formatter = function(v) return tostring(math.floor((v or 0) + 0.5)) end,
    }

    settings[#settings + 1] = {
        name = "Enabled",
        kind = SettingType.Checkbox,
        get = function() return ns.db.bossTarget.enabled and true or false end,
        set = function(_, v)
            ns.db.bossTarget.enabled = v and true or false
            if BT then
                if v then BT.Show() else BT.Hide() end
            end
        end,
    }

    -- Color options ----------------------------------------------------------
    -- Color changes are picked up by the next OnUpdate tick (no layout reapply
    -- needed) so these checkboxes are cheap and safe to flip in combat.

    local function colorCheckbox(name, key)
        return {
            name = name,
            kind = SettingType.Checkbox,
            get  = function() return ns.db.bossTarget.color[key] and true or false end,
            set  = function(_, v) ns.db.bossTarget.color[key] = v and true or false end,
        }
    end

    if SettingType.Divider then
        settings[#settings + 1] = { name = "Colors", kind = SettingType.Divider }
    end
    settings[#settings + 1] = colorCheckbox("Class color (players)",  "classColorPlayers")
    settings[#settings + 1] = colorCheckbox("Reaction color (NPCs)",  "npcUseReaction")
    settings[#settings + 1] = colorCheckbox("Apply to name",          "applyToName")
    settings[#settings + 1] = colorCheckbox("Apply to health bar",    "applyToHealthBar")
    settings[#settings + 1] = colorCheckbox("Apply to border",        "applyToBorder")

    settings[#settings + 1] = {
        name = "Health bar brightness",
        kind = SettingType.Slider,
        default = ns.DEFAULTS.bossTarget.color.brightness,
        minValue = 0.4,
        maxValue = 1.0,
        valueStep = 0.05,
        get = function() return ns.db.bossTarget.color.brightness or 1.0 end,
        set = function(_, v) ns.db.bossTarget.color.brightness = v end,
        formatter = function(v) return ("%.2f"):format(v or 1.0) end,
    }

    return settings
end

local function tryRegisterWithLib()
    lib = LibStub and LibStub("LibEQOLEditMode-1.0", true)
    if not lib or not lib.AddFrame then return false end

    local BT = ns.modules.BossTarget
    local controller = BT.GetFrame(1)
    if not controller then return false end

    controller.editModeName = "Djinni's Boss Target (shared offset)"

    local cfg = ns.db.bossTarget
    local defaults = {
        enableOverlayToggle = true,
        allowDrag = true,
        managePosition = false, -- we own position (anchored to boss frame, not UIParent)
        showReset = true,
        showSettingsReset = false,
        settingsMaxHeight = 400,
        point = "CENTER",
        relativePoint = "CENTER",
        x = cfg.anchor.x,
        y = cfg.anchor.y,
    }

    -- Drag callback: derive new shared offset from where frame1 was dropped,
    -- then re-pin all 5 frames to their respective boss frames.
    local function onPositionChanged(frame)
        saveOffsetFromController()
        if BT.ApplyLayout then BT.ApplyLayout() end
    end

    lib:AddFrame(controller, onPositionChanged, defaults)

    local settings = buildSettings()
    if settings then
        lib:AddFrameSettings(controller, settings)
    end

    if lib.RegisterCallback then
        lib:RegisterCallback("enter", function()
            if BT.ShowPlaceholders then BT.ShowPlaceholders(true) end
        end)
        lib:RegisterCallback("exit", function()
            if BT.ShowPlaceholders then BT.ShowPlaceholders(false) end
            -- Re-pin to boss frames after the lib's drag detached the controller.
            if BT.ApplyLayout then BT.ApplyLayout() end
        end)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Path B: Native Blizzard Edit Mode fallback (no LibEQOLEditMode loaded)
-- ---------------------------------------------------------------------------

local nativeOverlay

local function setupNativeOverlay()
    if nativeOverlay or not _G.EditModeManagerFrame then return end
    local BT = ns.modules.BossTarget
    local controller = BT and BT.GetFrame(1)
    if not controller then return end

    -- Overlay drawn on top of frame 1 — labels it as the shared-offset controller.
    local overlay = controller:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0.2, 0.6, 1.0, 0.25)
    overlay:Hide()

    local border = CreateFrame("Frame", nil, controller, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    border:SetBackdropBorderColor(0.2, 0.6, 1.0, 1.0)
    border:Hide()

    local label = border:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    label:SetPoint("BOTTOM", border, "TOP", 0, 4)
    label:SetText("Drag to set Boss Target offset (applies to all 5)")
    label:Hide()

    nativeOverlay = { tex = overlay, border = border, label = label }

    controller:RegisterForDrag("LeftButton")
    controller:SetScript("OnDragStart", function(self)
        if self._djueDragEnabled and not InCombatLockdown() then self:StartMoving() end
    end)
    controller:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveOffsetFromController()
        if BT.ApplyLayout then BT.ApplyLayout() end
    end)

    local function enter()
        if InCombatLockdown() then return end
        overlay:Show(); border:Show(); label:Show()
        controller._djueDragEnabled = true
        controller:EnableMouse(true)
        controller:SetMovable(true)
        if BT.ShowPlaceholders then BT.ShowPlaceholders(true) end
    end

    local function exit()
        overlay:Hide(); border:Hide(); label:Hide()
        controller._djueDragEnabled = false
        controller:SetMovable(false)
        if BT.ShowPlaceholders then BT.ShowPlaceholders(false) end
        if BT.ApplyLayout then BT.ApplyLayout() end
    end

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", enter)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", exit)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Mod.Init()
    if not ns.modules.BossTarget then return end
    -- Delay so LibEQOLEditMode finishes initializing on first login.
    C_Timer.After(0.5, function()
        if tryRegisterWithLib() then return end
        setupNativeOverlay()
    end)
end

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
-- Plain frames: anchored to UIParent, position saved as point/x/y in ns.db.
-- Rule: anything this addon draws on screen is movable from Edit Mode.
-- Each module exposes GetFrame(), SetUnlocked(bool) and ApplyLayout().
--
-- No library: EnhanceQoL 13.x stopped publishing LibEQOLEditMode via LibStub.
-- Same pattern as Plumber (Modules/Shared/SharedEditMode.lua): Blizzard's
-- EditMode.Enter/Exit events, plus our own mouse-catching overlay. The overlay
-- sits in HIGH strata because the default spot (centre, y -200) is under
-- Blizzard's own Edit Mode selection boxes. That they took the clicks is the
-- best guess for why dragging the frame itself did nothing (2026-09-21).
--
-- Behaviour copied from Blizzard (Blizzard_EditMode) and EnhanceQoL's edit
-- mode lib, which does the same for addon frames:
--   * The box is Blizzard's EditModeSystemSelectionTemplate: blue when idle,
--     yellow when selected, hover glow, "Click to edit" label. Its OnMouseDown
--     and drag scripts are replaced, because the stock ones hand the frame to
--     EditModeManagerFrame:SelectSystem, which only knows Blizzard systems.
--   * ONE settings dialog, shared, at Blizzard's spot (bottom right), not
--     pinned to the frame. Where you drag it is kept for the session.
--   * Selecting ours clears Blizzard's selection; selecting a Blizzard system
--     clears ours. The dialog closes on its X, on another selection, or on
--     leaving Edit Mode, and on a click anywhere else (Plumber's rule;
--     Blizzard and EnhanceQoL leave it open).
-- ---------------------------------------------------------------------------

-- `options` rows:
--   { "slider", field, label, min, max, step }
--   { "choice", field, label, { { value, text }, ... } }
local ROW_H, DIALOG_W = 36, 380

-- What EditModeMagnetismManager and the snap preview call on a dragged frame.
-- Borrowed as-is from Blizzard's EditModeSystemMixin (EditModeSystemTemplates.lua)
-- instead of rewritten, which is what EnhanceQoL's ensureMagnetismAPI does.
-- They need only frame.Selection. The snapped-frame bookkeeping methods are
-- left out: nothing ever anchors to our frames.
local MAGNETISM_METHODS = {
    "HasValidSelectionRect", "IsToTheLeftOfFrame", "IsToTheRightOfFrame",
    "IsAboveFrame", "IsBelowFrame", "IsVerticallyAlignedWithFrame",
    "IsHorizontallyAlignedWithFrame", "GetScaledSelectionCenter", "GetScaledCenter",
    "GetScaledSelectionSides", "GetLeftOffset", "GetRightOffset", "GetTopOffset",
    "GetBottomOffset", "GetSelectionOffset", "GetCombinedSelectionOffset",
    "GetCombinedCenterOffset", "GetSnapOffsets", "SnapToFrame",
    "IsFrameAnchoredToMe", "GetFrameMagneticEligibility",
}

local dialog        -- the one shared settings dialog
local selections = {}

local function deselectAll()
    for _, s in ipairs(selections) do
        if s.isSelected then s:ShowHighlighted() end
    end
    if dialog then dialog:Hide() end
end

local function getDialog()
    if dialog then return dialog end
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -250, 250)
    d:SetWidth(DIALOG_W)
    d:Hide()
    d:SetScript("OnHide", deselectAll) -- the X button deselects, as Blizzard's does

    CreateFrame("Frame", nil, d, "DialogBorderTranslucentTemplate"):SetAllPoints()
    CreateFrame("Button", nil, d, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -2, -2)

    d.Title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    d.Title:SetPoint("TOP", 0, -18)

    -- Blizzard fires SelectSystem when one of its own frames is clicked.
    hooksecurefunc(EditModeManagerFrame, "SelectSystem", deselectAll)

    -- A click anywhere else closes it, as Plumber does. Rob chose this over
    -- Blizzard's stay-open (2026-09-21). An open dropdown list is its own
    -- frame outside the dialog, so a click on it must not count as outside.
    d:SetScript("OnEvent", function()
        if d:IsMouseOver() or Menu.GetManager():IsAnyMenuOpen() then return end
        for _, s in ipairs(selections) do
            if s:IsShown() and s:IsMouseOver() then return end
        end
        d:Hide()
    end)
    d:HookScript("OnShow", function() d:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    d:HookScript("OnHide", function() d:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)

    dialog = d
    return d
end

-- The rows for one frame, built once, shown inside the shared dialog.
local function buildContent(mod, cfgKey, options)
    local cfg = ns.db[cfgKey]
    local d = CreateFrame("Frame", nil, getDialog())
    d:SetPoint("TOPLEFT", 0, -44)
    d:SetWidth(DIALOG_W)
    d:Hide()

    -- Slash commands can change a value while the window is closed.
    local sliders = {}
    d:SetScript("OnShow", function()
        for s, field in pairs(sliders) do s:SetValue(cfg[field]) end
    end)

    local y = -8
    for _, o in ipairs(options) do
        local kind, field, text = o[1], o[2], o[3]
        local name = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("LEFT", d, "TOPLEFT", 24, y)
        name:SetText(text)

        if kind == "slider" then
            local min, max, step = o[4], o[5], o[6]
            local s = CreateFrame("Frame", nil, d, "MinimalSliderWithSteppersTemplate")
            s:SetSize(200, 20)
            s:SetPoint("LEFT", d, "TOPLEFT", 140, y)
            local fmt = step < 1 and "%.2f" or "%d"
            s:Init(cfg[field], min, max, math.floor((max - min) / step + 0.5), {
                [MinimalSliderWithSteppersMixin.Label.Right] = function(v) return fmt:format(v) end,
            })
            s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
                if step >= 1 then v = math.floor(v + 0.5) end
                cfg[field] = v
                mod.ApplyLayout()
            end, d)
            sliders[s] = field
        else -- "choice"
            local dd = CreateFrame("DropdownButton", nil, d, "WowStyle1DropdownTemplate")
            dd:SetWidth(200)
            dd:SetPoint("LEFT", d, "TOPLEFT", 140, y)
            dd:SetupMenu(function(_, root)
                for _, c in ipairs(o[4]) do
                    root:CreateRadio(c[2],
                        function(v) return cfg[field] == v end,
                        function(v)
                            cfg[field] = v
                            mod.ApplyLayout()
                            mod.SetUnlocked(true) -- redraw the preview in the new style
                        end,
                        c[1])
                end
            end)
        end
        y = y - ROW_H
    end

    local reset = CreateFrame("Button", nil, d, "EditModeSystemSettingsDialogButtonTemplate")
    reset:SetPoint("TOP", d, "TOP", 0, y - 4)
    reset:SetText(HUD_EDIT_MODE_RESET_POSITION)
    reset:SetScript("OnClick", function()
        local def = ns.DEFAULTS[cfgKey]
        cfg.point, cfg.relativePoint, cfg.x, cfg.y = def.point, def.relativePoint, def.x, def.y
        mod.ApplyLayout()
    end)

    d:SetHeight(-y + 40)
    return d
end

local function registerPlain(mod, cfgKey, label, options)
    local frame = mod and mod.GetFrame and mod.GetFrame()
    if not frame then return end -- module never built it (e.g. not a druid)

    local content

    local sel = CreateFrame("Frame", nil, frame, "EditModeSystemSelectionTemplate")
    sel:SetAllPoints()
    sel:SetFrameStrata("HIGH")
    sel.system = { GetSystemName = function() return label end } -- read by the template's label and tooltip
    sel:Hide()
    selections[#selections + 1] = sel

    frame.Selection = sel
    for _, k in ipairs(MAGNETISM_METHODS) do frame[k] = EditModeSystemMixin[k] end

    sel:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        frame:StartMoving()
        EditModeManagerFrame:SetSnapPreviewFrame(frame) -- Blizzard's live snap lines
    end)
    sel:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        EditModeManagerFrame:ClearSnapPreviewFrame()
        -- Blizzard's own snap: edges, centres, grid lines, screen centre and
        -- other Edit Mode frames, exactly as its frames snap. It may anchor us
        -- to one of them; savePosition turns that back into our CENTER form.
        if EditModeManagerFrame:IsSnapEnabled() then
            EditModeMagnetismManager:ApplyMagnetism(frame)
        end
        ns.savePosition(frame, ns.db[cfgKey])
        mod.ApplyLayout()
    end)
    sel:SetScript("OnMouseDown", function()
        if sel.isSelected then return end
        EditModeManagerFrame:ClearSelectedSystem() -- fires no SelectSystem, so ours survive
        deselectAll()
        content = content or buildContent(mod, cfgKey, options)
        local d = getDialog()
        for _, child in ipairs({ d:GetChildren() }) do
            if child.isContent then child:Hide() end
        end
        content.isContent = true
        content:Show()
        d.Title:SetText(label)
        d:SetHeight(44 + content:GetHeight() + 16)
        sel:ShowSelected()
        d:Show()
    end)

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        mod.SetUnlocked(true)
        sel:ShowHighlighted()
    end, sel)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        deselectAll()
        sel:Hide()
        mod.SetUnlocked(false)
    end, sel)
end

-- 0 is the round gems; 1..20 pin that frame of the claw swipe as a still claw
-- (ComboPoints.lua clawTexCoords). Picked by eye, so every frame is offered.
local function clawChoices()
    local list = { { 0, "Gems (default)" } }
    for i = 1, 20 do list[#list + 1] = { i, "Still claw, frame " .. i } end
    return list
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Mod.Init()
    -- Delay so LibEQOLEditMode finishes initializing on first login.
    C_Timer.After(0.5, function()
        if ns.modules.BossTarget and not tryRegisterWithLib() then
            setupNativeOverlay()
        end
        registerPlain(ns.modules.ComboPoints, "comboPoints", "Djinni's Combo Points", {
            -- No Scale row: Point size and Spacing cover it (Rob, 2026-09-21).
            { "slider", "size",    "Point size", 8,   80,  1 },
            { "slider", "spacing", "Spacing",    0,   40,  1 },
            { "choice", "visibility", "Show", {
                { "cat",    "In Cat Form" },
                { "points", "In Cat Form, with points" },
                { "always", "Always" },
            } },
            { "choice", "clawFrame", "Claw", clawChoices() },
        })
        registerPlain(ns.modules.EnergyBar, "energyBar", "Djinni's Energy Bar", {
            { "slider", "width",  "Width",  60, 600, 1 },
            { "slider", "height", "Height", 4,  60,  1 },
            { "choice", "visibility", "Show", {
                { "energy", "When energy is your power" },
                { "always", "Always" },
                { "never",  "Never" },
            } },
        })
        registerPlain(ns.modules.IronfurBar, "ironfurBar", "Djinni's Ironfur Bar", {
            { "slider", "scale",  "Scale",  0.5, 2.0, 0.05 },
            { "slider", "width",  "Width",  60,  600, 1 },
            { "slider", "height", "Height", 8,   60,  1 },
            { "choice", "visibility", "Show", {
                { "bear",           "In Bear Form, or with stacks" },
                { "onlyWithStacks", "Only with stacks" },
                { "always",         "Always" },
            } },
        })
    end)
end

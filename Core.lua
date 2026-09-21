local ADDON_NAME, ns = ...

ns.modules = {}

local DEFAULTS = {
    ironfurBar = {
        enabled = true,
        scale = 1.0,
        width = 240,
        height = 18,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -160,
        -- "bear" = show in Bear/Incarnation form OR whenever stacks are up
        -- "always" = always show while a Druid is logged in
        -- "onlyWithStacks" = only when there's at least 1 stack
        visibility = "bear",
        barColor = { 0.85, 0.55, 0.10 },
        markerColor = { 1.0, 1.0, 0.40 },
        markerWidth = 2,
    },
    comboPoints = {
        enabled = true,
        scale = 1.0,
        size = 26,      -- per point, in pixels
        spacing = 8,    -- gap between points
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -200,
        -- "cat"    = show whenever in Cat Form
        -- "always" = always show while a Druid is logged in
        -- "points" = only in Cat Form and only with at least 1 point
        visibility = "cat",
        -- Resting shape. 0 = Blizzard's round gems with the claw swiping on
        -- gain, which is the combination Rob accepted on 2026-09-08 and the
        -- reason this defaults to 0 rather than to the newer option. 1..20 pins
        -- that frame of the UF-DruidCP-Slash flipbook as a still claw instead.
        -- Which frame reads as a claw can only be judged on screen, so it is a
        -- dial rather than a constant, and `/djue cp claw 0` is the way back.
        clawFrame = 0,
    },
    bossTarget = {
        enabled = true,
        scale = 1.0,
        width = 180,
        height = 36,
        -- Each target frame is pinned CENTER-to-CENTER on its boss frame
        -- (EQOLUFBoss%dFrame if EnhanceQoL is loaded, else Boss%dTargetFrame).
        -- A single shared offset keeps all 5 visually identical.
        anchor = {
            x = 200, -- positive = right of boss frame
            y = 0,
        },
        color = {
            classColorPlayers = true, -- use class color when target is a player
            npcUseReaction    = true, -- use reaction (red/yellow/green) color for NPC targets
            applyToName       = true,
            applyToHealthBar  = true,
            applyToBorder     = false,
            brightness        = 1.0,  -- multiplier on health-bar tint (0.5 = dim, 1.0 = full)
        },
    },
}

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepCopy(v) end
    return out
end

local function mergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            mergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Position of a plain UIParent frame: its CENTER against UIParent's CENTER,
-- in UIParent units. SetPoint offsets are in the frame's own (scaled) units,
-- so they are divided by scale on the way in. That is what makes a scale
-- change grow the frame around its middle instead of sliding it away.
function ns.savePosition(frame, cfg)
    local s = frame:GetScale()
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    cfg.point, cfg.relativePoint = "CENTER", "CENTER"
    cfg.x = math.floor(cx * s - ux + 0.5)
    cfg.y = math.floor(cy * s - uy + 0.5)
end

function ns.applyPosition(frame, cfg)
    frame:SetScale(cfg.scale)
    frame:ClearAllPoints()
    if cfg.point ~= "CENTER" or cfg.relativePoint ~= "CENTER" then
        -- Saved before 2026-09-21 as a corner anchor in frame units. Place it
        -- the old way once and re-save it in the new form.
        frame:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
        ns.savePosition(frame, cfg)
        frame:ClearAllPoints()
    end
    frame:SetPoint("CENTER", UIParent, "CENTER", cfg.x / cfg.scale, cfg.y / cfg.scale)
end

ns.deepCopy = deepCopy
ns.DEFAULTS = DEFAULTS

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")

loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DjinnisUIEnhancementsDB = DjinnisUIEnhancementsDB or {}
        mergeDefaults(DjinnisUIEnhancementsDB, DEFAULTS)
        ns.db = DjinnisUIEnhancementsDB
        if ns.modules.BossTarget and ns.modules.BossTarget.OnDBReady then
            ns.modules.BossTarget.OnDBReady()
        end
        if ns.modules.IronfurBar and ns.modules.IronfurBar.OnDBReady then
            ns.modules.IronfurBar.OnDBReady()
        end
        if ns.modules.ComboPoints and ns.modules.ComboPoints.OnDBReady then
            ns.modules.ComboPoints.OnDBReady()
        end
    elseif event == "PLAYER_LOGIN" then
        if ns.modules.BossTarget and ns.modules.BossTarget.Init then
            ns.modules.BossTarget.Init()
        end
        if ns.modules.IronfurBar and ns.modules.IronfurBar.Init then
            ns.modules.IronfurBar.Init()
        end
        if ns.modules.ComboPoints and ns.modules.ComboPoints.Init then
            ns.modules.ComboPoints.Init()
        end
        if ns.modules.EditMode and ns.modules.EditMode.Init then
            ns.modules.EditMode.Init()
        end
        if ns.modules.PriceTrackerTSM and ns.modules.PriceTrackerTSM.Init then
            ns.modules.PriceTrackerTSM.Init()
        end
    end
end)

-- Slash command dispatch
SLASH_DJINNISUIE1 = "/djue"
SLASH_DJINNISUIE2 = "/djinnisuie"

local function print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[DjinniUIE]|r " .. tostring(msg))
end
ns.print = print

local helpLines = {
    "Commands:",
    "  /djue bt reset — reset to default offset/size",
    "  /djue bt scale <n> — set scale (e.g. 1.0)",
    "  /djue bt size <w> <h> — set frame width/height",
    "  /djue bt offset <x> <y> — offset relative to each boss frame center",
    "  /djue bt show | hide — toggle module",
    "  /djue bt status — show current settings",
    "  /djue ifb unlock | lock — drag the Ironfur bar to position",
    "  /djue ifb size <w> <h> | scale <n> — size/scale Ironfur bar",
    "  /djue ifb vis <always|bear|stacks> — when the Ironfur bar is shown",
    "  /djue ifb show | hide | reset | status",
    "  /djue cp unlock | lock — drag the combo points to position",
    "  /djue cp size <n> | gap <n> | scale <n> — size/spacing/scale",
    "  /djue cp vis <always|cat|points> — when the combo points are shown",
    "  /djue cp claw <0-20> — 0 = the default gems + swipe, 1-20 = still claw",
    "  /djue cp test — play the claw swipe on demand",
    "  /djue cp show | hide | reset | status | debug",
    "  (or use /editmode to configure visually)",
}

SlashCmdList.DJINNISUIE = function(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" or input == "help" then
        for _, line in ipairs(helpLines) do print(line) end
        return
    end

    local module, rest = input:match("^(%S+)%s*(.*)$")
    if module == "bt" or module == "bosstarget" then
        local mod = ns.modules.BossTarget
        if not mod or not mod.HandleCommand then
            print("BossTarget module not loaded.")
            return
        end
        mod.HandleCommand(rest)
    elseif module == "ifb" or module == "ironfur" or module == "ironfurbar" then
        local mod = ns.modules.IronfurBar
        if not mod or not mod.HandleCommand then
            print("IronfurBar module not loaded.")
            return
        end
        mod.HandleCommand(rest)
    elseif module == "cp" or module == "combo" or module == "combopoints" then
        local mod = ns.modules.ComboPoints
        if not mod or not mod.HandleCommand then
            print("ComboPoints module not loaded.")
            return
        end
        mod.HandleCommand(rest)
    else
        print("Unknown command. Try /djue help")
    end
end

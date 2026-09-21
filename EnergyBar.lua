local ADDON_NAME, ns = ...

local Mod = {}
ns.modules.EnergyBar = Mod

-- ---------------------------------------------------------------------------
-- Energy bar. Shown by default whenever energy is the player's displayed power
-- (Cat Form for a druid, always for a rogue or a brewmaster/windwalker monk).
--
-- 12.1 secrets: UnitPower carries SecretWhenUnitPowerRestricted, but
-- StatusBar:SetValue, StatusBar:SetMinMaxValues and FontString:SetText all
-- take secret arguments from addon code (SecretArguments = "AllowedWhenTainted"
-- in SimpleStatusBarAPIDocumentation.lua and SimpleFontStringAPIDocumentation.lua).
-- So the numbers go straight into the widgets and this file never compares,
-- formats or concatenates them. That needs no guard at all, and keeps working
-- if energy ever turns secret mid-fight, where ComboPoints.lua has to freeze.
-- ---------------------------------------------------------------------------

local print = ns.print or function() end

local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local SMOOTH = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local frame, bar, text

local function usesEnergy()
    return UnitPowerType("player") == ENERGY
end

local function shouldShow()
    -- Edit Mode wins over every rule, so the bar can be placed from anywhere.
    if frame._unlocked then return true end
    local mode = ns.db.energyBar.visibility
    if mode == "always" then return true end
    if mode == "never" then return false end
    return usesEnergy() -- "energy"
end

local function redraw()
    if not frame then return end
    if not shouldShow() then
        frame:Hide()
        return
    end
    frame:Show()
    local value = UnitPower("player", ENERGY)
    bar:SetMinMaxValues(0, UnitPowerMax("player", ENERGY))
    if SMOOTH then bar:SetValue(value, SMOOTH) else bar:SetValue(value) end
    text:SetText(value)
end
Mod.Redraw = redraw

local function buildFrame()
    frame =CreateFrame("Frame", "DjinnisEnergyBar", UIParent, "BackdropTemplate")
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.55)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    frame:Hide()

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetPoint("TOPLEFT", 3, -3)
    bar:SetPoint("BOTTOMRIGHT", -3, 3)
    -- Blizzard's own energy yellow (PowerBarColorUtil.lua).
    local c = PowerBarColor and PowerBarColor.ENERGY or { r = 1, g = 1, b = 0 }
    bar:SetStatusBarColor(c.r, c.g, c.b)

    text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
end

local function applyLayout()
    if not frame then return end
    local cfg = ns.db.energyBar
    frame:SetSize(cfg.width, cfg.height)
    ns.applyPosition(frame, cfg)
end
Mod.ApplyLayout = applyLayout

-- Registered one at a time, after SetScript, each checked with
-- IsEventRegistered: 12.1 can refuse silently (workspace docs/DECISIONS.md).
-- A refusal is reported once and never retried.
local function registerEvents()
    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", redraw)
    local refused = {}
    local function reg(event, unit)
        if unit then ev:RegisterUnitEvent(event, unit) else ev:RegisterEvent(event) end
        if not ev:IsEventRegistered(event) then refused[#refused + 1] = event end
    end
    reg("UNIT_POWER_FREQUENT", "player")
    reg("UNIT_MAXPOWER", "player")
    reg("UNIT_DISPLAYPOWER", "player") -- shifted into or out of Cat Form
    reg("PLAYER_ENTERING_WORLD")
    if #refused > 0 then
        print("Energy bar: the game refused these events: " .. table.concat(refused, ", ")
            .. ". The bar will not update. Nothing is retried.")
    end
end

function Mod.GetFrame() return frame end

function Mod.SetUnlocked(unlocked)
    if not frame then return end
    frame._unlocked = unlocked and true or false
    redraw()
end

function Mod.Init()
    buildFrame()
    applyLayout()
    registerEvents()
    redraw()
end

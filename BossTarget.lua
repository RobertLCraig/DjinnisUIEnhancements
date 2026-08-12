local ADDON_NAME, ns = ...

local MAX_BOSS_FRAMES = 5
local UPDATE_INTERVAL = 0.1

local Mod = {}
ns.modules.BossTarget = Mod

local frames = {}
local print = ns.print or function() end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Resolve the per-boss frame we should attach to.
-- EnhanceQoL's frame takes priority; falls back to Blizzard's default frame.
local function getBossFrame(i)
    return _G["EQOLUFBoss" .. i .. "Frame"] or _G["Boss" .. i .. "TargetFrame"]
end

local DEFAULT_NEUTRAL = { 0.7, 0.7, 0.7 }
local DEFAULT_BAR_GREEN = { 0.2, 0.8, 0.2 }
local DEFAULT_BORDER = { 0.3, 0.3, 0.3 }

-- Returns r, g, b based on color config + unit type.
-- isPlayer signals whether class color was actually used (caller may want to
-- distinguish player vs NPC styling).
local function getColor(unit, cfg)
    if not unit or not UnitExists(unit) then
        return DEFAULT_NEUTRAL[1], DEFAULT_NEUTRAL[2], DEFAULT_NEUTRAL[3], false
    end
    if cfg.classColorPlayers and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b, true end
    end
    if cfg.npcUseReaction then
        local r, g, b = UnitSelectionColor(unit, true)
        if r then return r, g, b, false end
    end
    return DEFAULT_NEUTRAL[1], DEFAULT_NEUTRAL[2], DEFAULT_NEUTRAL[3], false
end

local function shortNumber(n)
    if not n then return "" end
    if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
    if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
    return tostring(math.floor(n))
end

-- Compound unit tokens like boss1target can return "secret number" values
-- (Blizzard's Secret API) — arithmetic on them throws. Probe with pcall so we
-- can degrade gracefully instead of erroring 10x/second during fights.
local function safeNumber(v)
    if type(v) ~= "number" then return nil end
    local ok = pcall(function() return v + 0 end)
    if not ok then return nil end
    return v
end

local function safeString(v)
    if type(v) ~= "string" then return nil end
    -- A "secret string" exists too; concatenation triggers the error.
    local ok = pcall(function() return v .. "" end)
    if not ok then return nil end
    return v
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

local function createBossTargetFrame(index)
    local name = "DjinnisBossTargetFrame" .. index
    local unitToken = "boss" .. index .. "target"

    local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    f:SetAttribute("unit", unitToken)
    f:SetAttribute("type1", "target")
    f:SetAttribute("type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f.unit = unitToken
    f.bossUnit = "boss" .. index
    f.index = index

    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local hb = CreateFrame("StatusBar", nil, f)
    hb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    hb:SetPoint("TOPLEFT", 4, -4)
    hb:SetPoint("TOPRIGHT", -4, -4)
    hb:SetHeight(16)
    hb:SetMinMaxValues(0, 1)
    hb:SetStatusBarColor(0.2, 0.8, 0.2)
    f.healthBar = hb

    local hbBg = hb:CreateTexture(nil, "BACKGROUND")
    hbBg:SetAllPoints()
    hbBg:SetColorTexture(0, 0, 0, 0.5)

    local pb = CreateFrame("StatusBar", nil, f)
    pb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    pb:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, -2)
    pb:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", 0, -2)
    pb:SetHeight(6)
    pb:SetMinMaxValues(0, 1)
    pb:SetStatusBarColor(0.2, 0.4, 0.9)
    f.powerBar = pb

    local pbBg = pb:CreateTexture(nil, "BACKGROUND")
    pbBg:SetAllPoints()
    pbBg:SetColorTexture(0, 0, 0, 0.5)

    local nameText = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", 4, 0)
    nameText:SetPoint("RIGHT", -4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    f.nameText = nameText

    local hpText = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpText:SetPoint("RIGHT", -4, 0)
    hpText:SetJustifyH("RIGHT")
    f.hpText = hpText

    local idxText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    idxText:SetPoint("TOPRIGHT", -4, -2)
    idxText:SetText("B" .. index .. "→")
    idxText:SetTextColor(0.7, 0.7, 0.7)
    f.idxText = idxText

    f:SetScript("OnEnter", function(self)
        if UnitExists(self.unit) then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetUnit(self.unit)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Blizzard's secure visibility driver: shows when boss1target exists, hides
    -- when not. Required for SecureUnitButton frames — insecure :Hide()/:Show()
    -- is blocked by the protected-function guard.
    RegisterUnitWatch(f)
    return f
end

-- ---------------------------------------------------------------------------
-- Updates
-- ---------------------------------------------------------------------------

local function updateFrame(f)
    local unit = f.unit
    -- Visibility is handled by RegisterUnitWatch; skip content update when hidden.
    if not f:IsShown() then return end
    if not UnitExists(unit) then return end

    local colorCfg = ns.db.bossTarget.color
    local r, g, b = getColor(unit, colorCfg)

    local name = safeString(UnitName(unit))
    if name then
        f.nameText:SetText(name)
        if colorCfg.applyToName then
            f.nameText:SetTextColor(r, g, b)
        else
            f.nameText:SetTextColor(1, 1, 1)
        end
    else
        f.nameText:SetText("|cff888888?|r")
        f.nameText:SetTextColor(1, 1, 1)
    end

    if colorCfg.applyToBorder then
        f:SetBackdropBorderColor(r, g, b, 1)
    else
        f:SetBackdropBorderColor(DEFAULT_BORDER[1], DEFAULT_BORDER[2], DEFAULT_BORDER[3], 1)
    end

    local rawHp = UnitHealth(unit)
    local rawHpMax = UnitHealthMax(unit)
    local hp = safeNumber(rawHp)
    local hpMax = safeNumber(rawHpMax)
    if hp and hpMax and hpMax > 0 then
        f.healthBar:SetMinMaxValues(0, hpMax)
        f.healthBar:SetValue(hp)
        local pct = (hp / hpMax) * 100
        f.hpText:SetText(("%s  %.0f%%"):format(shortNumber(hp), pct))
        if colorCfg.applyToHealthBar then
            local k = colorCfg.brightness or 1.0
            f.healthBar:SetStatusBarColor(r * k, g * k, b * k)
        else
            f.healthBar:SetStatusBarColor(DEFAULT_BAR_GREEN[1], DEFAULT_BAR_GREEN[2], DEFAULT_BAR_GREEN[3])
        end
    elseif rawHp ~= nil or rawHpMax ~= nil then
        -- Values existed but were secret-restricted by the API. Show a striped
        -- "data unavailable" bar so the user knows the unit is alive but health
        -- can't be queried (common when the boss is targeting a non-party NPC).
        f.healthBar:SetMinMaxValues(0, 1)
        f.healthBar:SetValue(1)
        f.healthBar:SetStatusBarColor(0.3, 0.3, 0.35, 0.6)
        f.hpText:SetText("|cff888888secret|r")
    else
        f.healthBar:SetMinMaxValues(0, 1)
        f.healthBar:SetValue(0)
        f.healthBar:SetStatusBarColor(0.4, 0.4, 0.4)
        f.hpText:SetText("")
    end

    local pwr = safeNumber(UnitPower(unit))
    local pwrMax = safeNumber(UnitPowerMax(unit))
    if pwr and pwrMax and pwrMax > 0 then
        f.powerBar:Show()
        f.powerBar:SetMinMaxValues(0, pwrMax)
        f.powerBar:SetValue(pwr)
        local ptype = UnitPowerType(unit)
        local info = PowerBarColor and PowerBarColor[ptype]
        if info then
            f.powerBar:SetStatusBarColor(info.r, info.g, info.b)
        end
    else
        f.powerBar:Hide()
    end
end

local elapsedAccum = 0
local function onUpdate(self, elapsed)
    elapsedAccum = elapsedAccum + elapsed
    if elapsedAccum < UPDATE_INTERVAL then return end
    elapsedAccum = 0
    for i = 1, MAX_BOSS_FRAMES do
        local f = frames[i]
        if f then
            -- Defensive: any error in updateFrame (e.g. a secret value the
            -- safeNumber probe didn't catch) gets swallowed instead of
            -- spamming BugSack every tick. Frame just shows stale data
            -- for one tick.
            local ok, err = pcall(updateFrame, f)
            if not ok then
                f.healthBar:SetMinMaxValues(0, 1)
                f.healthBar:SetValue(0)
                f.hpText:SetText("")
                f.nameText:SetText("|cff888888?|r")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layout — each frame physically pinned to its corresponding boss frame
-- ---------------------------------------------------------------------------

local layoutPending = false
local combatWatcher
local updateDriver

local function applyLayout(opts)
    if not ns.db then return end
    if InCombatLockdown() then
        layoutPending = true
        return
    end

    local cfg = ns.db.bossTarget

    for i = 1, MAX_BOSS_FRAMES do
        local f = frames[i]
        if f then
            f:SetSize(cfg.width, cfg.height)
            f:SetScale(cfg.scale)
            f:ClearAllPoints()

            local bossFrame = getBossFrame(i)
            if bossFrame then
                -- CENTER-to-CENTER anchor with shared offset: identical relative
                -- positioning for every boss/target pair.
                f:SetPoint("CENTER", bossFrame, "CENTER", cfg.anchor.x, cfg.anchor.y)
            else
                -- Defensive fallback: park off-screen until a boss frame appears.
                f:SetPoint("CENTER", UIParent, "CENTER", 0, -300 + (i * 50))
            end
        end
    end
end
Mod.ApplyLayout = applyLayout

local function ensureCombatWatcher()
    if combatWatcher then return end
    combatWatcher = CreateFrame("Frame")
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatcher:SetScript("OnEvent", function()
        if layoutPending then
            layoutPending = false
            applyLayout()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local eventFrame

local function registerEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    for i = 1, MAX_BOSS_FRAMES do
        eventFrame:RegisterUnitEvent("UNIT_TARGET", "boss" .. i)
    end
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        -- Boss frame may have just appeared (EnhanceQoL lazy create);
        -- reapply layout so we re-resolve and pin to whichever frame is live.
        applyLayout()
        for i = 1, MAX_BOSS_FRAMES do
            local f = frames[i]
            if f then updateFrame(f) end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Init / API
-- ---------------------------------------------------------------------------

function Mod.OnDBReady()
end

-- Returns one of our boss-target frames (used by EditMode to register it
-- as the "controller" frame for the shared offset).
function Mod.GetFrame(i)
    return frames[i]
end

function Mod.GetBossFrame(i)
    return getBossFrame(i)
end

function Mod.GetMaxFrames()
    return MAX_BOSS_FRAMES
end

-- Secure visibility helper: avoids the protected :Show()/:Hide() restriction
-- on SecureUnitButton frames. RegisterUnitWatch and RegisterAttributeDriver
-- are insecure-callable but drive visibility through secure handlers.
local function setFrameVisibility(f, mode)
    UnregisterUnitWatch(f)
    UnregisterAttributeDriver(f, "state-visibility")
    if mode == "watch" then
        RegisterUnitWatch(f)
    elseif mode == "show" then
        RegisterAttributeDriver(f, "state-visibility", "show")
    elseif mode == "hide" then
        RegisterAttributeDriver(f, "state-visibility", "hide")
    end
end

function Mod.Show()
    for i = 1, MAX_BOSS_FRAMES do
        if frames[i] then setFrameVisibility(frames[i], "watch") end
    end
end

function Mod.Hide()
    for i = 1, MAX_BOSS_FRAMES do
        if frames[i] then setFrameVisibility(frames[i], "hide") end
    end
end

-- Force all 5 frames visible with placeholder content (used by EditMode preview).
function Mod.ShowPlaceholders(enable)
    for i = 1, MAX_BOSS_FRAMES do
        local f = frames[i]
        if not f then break end
        if enable then
            setFrameVisibility(f, "show")
            f.nameText:SetText("Boss " .. i .. " Target")
            f.nameText:SetTextColor(1, 1, 1)
            f.healthBar:SetMinMaxValues(0, 1)
            f.healthBar:SetValue(0.7)
            f.healthBar:SetStatusBarColor(0.4, 0.4, 0.4)
            f.hpText:SetText("70%")
            f.powerBar:Show()
            f.powerBar:SetMinMaxValues(0, 1)
            f.powerBar:SetValue(0.5)
            f.powerBar:SetStatusBarColor(0.3, 0.4, 0.8)
        else
            setFrameVisibility(f, "watch")
        end
    end
    if updateDriver then
        updateDriver:SetScript("OnUpdate", enable and nil or onUpdate)
    end
end

function Mod.Init()
    if not ns.db or not ns.db.bossTarget.enabled then return end

    for i = 1, MAX_BOSS_FRAMES do
        frames[i] = createBossTargetFrame(i)
    end

    -- A tiny invisible driver frame owns the OnUpdate ticker so we don't
    -- have to attach it to a secure frame.
    updateDriver = CreateFrame("Frame", "DjinnisBossTargetDriver", UIParent)
    updateDriver:SetSize(1, 1)
    updateDriver:SetScript("OnUpdate", onUpdate)

    applyLayout()
    registerEvents()
    ensureCombatWatcher()
end

-- ---------------------------------------------------------------------------
-- Slash command handler (called by Core.lua dispatcher)
-- ---------------------------------------------------------------------------

function Mod.HandleCommand(rest)
    local cmd, args = rest:match("^(%S*)%s*(.*)$")
    cmd = cmd or ""
    local cfg = ns.db and ns.db.bossTarget

    if cmd == "" or cmd == "status" then
        if not cfg then print("DB not ready.") return end
        print(("BossTarget: enabled=%s scale=%.2f size=%dx%d offset=(%.0f, %.0f)")
            :format(tostring(cfg.enabled), cfg.scale, cfg.width, cfg.height, cfg.anchor.x, cfg.anchor.y))
        for i = 1, MAX_BOSS_FRAMES do
            local bf = getBossFrame(i)
            print(("  boss%d frame: %s"):format(i, bf and bf:GetName() or "<none>"))
        end
    elseif cmd == "reset" then
        cfg.anchor.x = ns.DEFAULTS.bossTarget.anchor.x
        cfg.anchor.y = ns.DEFAULTS.bossTarget.anchor.y
        cfg.scale = ns.DEFAULTS.bossTarget.scale
        cfg.width = ns.DEFAULTS.bossTarget.width
        cfg.height = ns.DEFAULTS.bossTarget.height
        applyLayout()
        print("Boss target frames reset to defaults.")
    elseif cmd == "scale" then
        local n = tonumber(args)
        if n and n > 0.3 and n < 3 then
            cfg.scale = n
            applyLayout()
            print("Scale: " .. n)
        else
            print("Usage: /djue bt scale <0.3..3.0>")
        end
    elseif cmd == "size" then
        local w, h = args:match("(%d+)%s+(%d+)")
        w, h = tonumber(w), tonumber(h)
        if w and h then
            cfg.width, cfg.height = w, h
            applyLayout()
            print(("Size: %dx%d"):format(w, h))
        else
            print("Usage: /djue bt size <width> <height>")
        end
    elseif cmd == "offset" then
        local x, y = args:match("(%-?%d+)%s+(%-?%d+)")
        x, y = tonumber(x), tonumber(y)
        if x and y then
            cfg.anchor.x, cfg.anchor.y = x, y
            applyLayout()
            print(("Offset: (%d, %d)"):format(x, y))
        else
            print("Usage: /djue bt offset <x> <y>   (e.g. 200 0 for right, 0 -50 for below)")
        end
    elseif cmd == "show" then
        cfg.enabled = true
        if #frames == 0 then Mod.Init() else Mod.Show() end
        print("Boss target frames enabled.")
    elseif cmd == "hide" then
        cfg.enabled = false
        Mod.Hide()
        print("Boss target frames hidden.")
    else
        print("Unknown bt command. Try /djue help")
    end
end

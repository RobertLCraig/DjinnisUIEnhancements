local ADDON_NAME, ns = ...

local Mod = {}
ns.modules.ComboPoints = Mod

-- ---------------------------------------------------------------------------
-- Feral combo points, drawn with Blizzard's own druid claw art.
--
-- The art is the UF-DruidCP-* atlas set that Blizzard_UnitFrame's
-- DruidComboPointBar uses. Reusing it means no bundled textures and no art to
-- keep in step with a patch; if an atlas name ever disappears, setArt() falls
-- back to plain coloured squares rather than drawing nothing.
-- ---------------------------------------------------------------------------

local print = ns.print or function() end

local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local DEFAULT_MAX = 5

local container       -- parent Frame (positioned / dragged)
local points = {}     -- point frames, index 1..maxPoints
local maxPoints = DEFAULT_MAX
local lastCount = 0

-- ---------------------------------------------------------------------------
-- Secret-value guards
-- ---------------------------------------------------------------------------
--
-- UnitPower and UnitPowerMax carry SecretWhenUnitPowerRestricted in 12.1
-- (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua), which means the
-- number they return can be a secret value that must not be compared. Two
-- guards, because either one alone can be wrong:
--   * C_Secrets.ShouldUnitPowerBeSecret asks up front, before we read.
--   * issecretvalue checks what we actually got. type() cannot see a secret
--     (workspace docs/DECISIONS.md), so this is the only reliable test.
-- When the answer is secret we leave the display on its last known count
-- rather than guessing, which is the only honest option available.

local function isSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function powerWouldBeSecret()
    if C_Secrets and C_Secrets.ShouldUnitPowerBeSecret then
        return C_Secrets.ShouldUnitPowerBeSecret("player", COMBO)
    end
    return false
end

-- Returns the current combo point count, or nil if it cannot be read safely.
local function readCombo()
    if powerWouldBeSecret() then return nil end
    local n = UnitPower("player", COMBO)
    if isSecret(n) then return nil end
    return tonumber(n) or 0
end

-- Returns the max combo points, or nil if it cannot be read safely. Feral can
-- run 5 or 6 depending on talents, so this is read rather than assumed.
local function readComboMax()
    if C_Secrets and C_Secrets.ShouldUnitPowerMaxBeSecret
        and C_Secrets.ShouldUnitPowerMaxBeSecret("player", COMBO) then
        return nil
    end
    local n = UnitPowerMax("player", COMBO)
    if isSecret(n) then return nil end
    n = tonumber(n)
    if not n or n < 1 or n > 10 then return nil end
    return n
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function isDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

-- Cat form, without touching GetShapeshiftFormID. This is exactly what
-- DruidComboPointBarMixin:ShouldShowBar does: a druid whose displayed power is
-- Energy is in cat form. UnitPowerType carries no secret predicate, so it is
-- safe in combat where the power VALUE is not.
local function inCatForm()
    return UnitPowerType("player") == ENERGY
end

-- ---------------------------------------------------------------------------
-- Art
-- ---------------------------------------------------------------------------

local ATLAS = {
    shadow   = "UF-DruidCP-BG-Shadow",
    inactive = "UF-DruidCP-BG-Dis",
    active   = "UF-DruidCP-BG-Active",
    glow     = "UF-DruidCP-Ring-Glow",
    icon     = "UF-DruidCP-Icon",
    slash    = "UF-DruidCP-Slash",
}

-- The claw. UF-DruidCP-Slash is a flipbook sheet, 3 rows by 8 columns, 20 used
-- frames, played over one second when a point is gained. It is the only claw in
-- the druid set: the resting art is a round gem, so without this the display is
-- a row of circles. Numbers copied from DruidComboPointBar.xml's activateAnim.
local SLASH = { rows = 3, columns = 8, frames = 20, duration = 1 }

-- Blizzard sizes the slash 26x41 against a 20x20 point.
local SLASH_W, SLASH_H, SLASH_BASE = 26, 41, 20

-- Static claw shape, cut out of the same slash sheet.
--
-- The druid atlas set has no still claw in it: the resting art is a round gem
-- and the only claw is the swipe. So the shape comes from one frame of the
-- flipbook, pinned instead of played. AtlasInfo gives the sheet's own texcoords
-- inside the larger atlas file, and one cell is 1/8 of its width by 1/3 of its
-- height, so a frame can be cropped out with SetTexCoord against info.file.
--
-- Which frame looks like a claw and which looks like a smear cannot be decided
-- from source: nothing here can render the sheet. `cfg.clawFrame` is therefore
-- a dial, 0 for the round gems and 1 to 20 to pin that frame.
local function clawTexCoords(frameIndex)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS.slash)
    if not info or not info.file then return nil end
    local n = math.max(1, math.min(SLASH.frames, math.floor(frameIndex)))
    local col = (n - 1) % SLASH.columns
    local row = math.floor((n - 1) / SLASH.columns)
    local w = (info.rightTexCoord - info.leftTexCoord) / SLASH.columns
    local h = (info.bottomTexCoord - info.topTexCoord) / SLASH.rows
    local l = info.leftTexCoord + (col * w)
    local t = info.topTexCoord + (row * h)
    return info.file, l, l + w, t, t + h
end

-- Use the atlas if the client still has it, otherwise a flat colour. A missing
-- atlas draws nothing at all, and an invisible bar reads as a broken addon.
local function setArt(tex, atlas, r, g, b, a)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas, false)
    else
        tex:SetColorTexture(r, g, b, a or 1)
    end
end

-- One animation group per point: the claw flipbook, plus the ring glow pulsing
-- up and back down under it. The textures are shown for the duration and hidden
-- again on every exit path, including Stop(), so a point that goes out mid-swipe
-- does not leave a frozen claw behind.
local function buildGainAnim(f)
    if not f.CreateAnimationGroup then return nil end
    local ag = f:CreateAnimationGroup()
    ag:SetToFinalAlpha(true)

    -- No Blizzard Lua calls CreateAnimation("FlipBook"), only the XML tag, so
    -- the type string is inferred from the convention the other types follow.
    -- If it is wrong the call returns nil, and an unguarded method on nil would
    -- take the whole point frame down and leave nothing on screen. Degrade to
    -- the glow pulse instead, and let `/djue cp debug` say the claw is missing.
    local fb = ag:CreateAnimation("FlipBook")
    if fb and fb.SetFlipBookRows then
        fb:SetTarget(f.slash)
        fb:SetDuration(SLASH.duration)
        fb:SetFlipBookRows(SLASH.rows)
        fb:SetFlipBookColumns(SLASH.columns)
        fb:SetFlipBookFrames(SLASH.frames)
        f.hasClaw = true
    end

    local up = ag:CreateAnimation("Alpha")
    up:SetTarget(f.glow)
    up:SetFromAlpha(0)
    up:SetToAlpha(1)
    up:SetDuration(0.27)

    local down = ag:CreateAnimation("Alpha")
    down:SetTarget(f.glow)
    down:SetFromAlpha(1)
    down:SetToAlpha(0)
    down:SetStartDelay(0.27)
    down:SetDuration(0.47)

    -- Without the flipbook the sheet would sit there as one static frame, which
    -- looks like a graphical fault rather than a missing effect.
    local function begin()
        if f.hasClaw then f.slash:Show() end
        f.glow:Show()
    end
    local function finish() f.slash:Hide(); f.glow:Hide() end
    ag:SetScript("OnPlay", begin)
    ag:SetScript("OnStop", finish)
    ag:SetScript("OnFinished", finish)
    return ag
end

local function buildPoint(index)
    local f = CreateFrame("Frame", nil, container)

    f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    setArt(f.shadow, ATLAS.shadow, 0, 0, 0, 0.5)
    f.shadow:SetPoint("CENTER", 0, -2)

    f.inactive = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    setArt(f.inactive, ATLAS.inactive, 0.18, 0.18, 0.18, 1)
    f.inactive:SetAllPoints()

    f.active = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    setArt(f.active, ATLAS.active, 1.0, 0.45, 0.10, 1)
    f.active:SetAllPoints()

    f.glow = f:CreateTexture(nil, "ARTWORK")
    setArt(f.glow, ATLAS.glow, 1.0, 0.75, 0.30, 0.35)
    f.glow:SetPoint("CENTER")

    f.icon = f:CreateTexture(nil, "OVERLAY")
    setArt(f.icon, ATLAS.icon, 1, 1, 1, 0.9)
    f.icon:SetAllPoints()

    f.claw = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.claw:SetPoint("CENTER", 1, 3)
    f.claw:Hide()

    f.slash = f:CreateTexture(nil, "OVERLAY", nil, 2)
    setArt(f.slash, ATLAS.slash, 1, 1, 1, 0.9)
    f.slash:SetPoint("CENTER", 1, 3)
    f.slash:Hide()

    f.gainAnim = buildGainAnim(f)

    points[index] = f
    return f
end

-- Claw style swaps the whole resting shape: the gem, its shadow and its icon go
-- away and the pinned claw frame carries the state instead, bright when the
-- point is up and dark when it is not. Falls back to the gems on its own if the
-- crop failed, so a bad frame number cannot leave an empty row.
local function applyStyle(f)
    local wanted = (ns.db.comboPoints.clawFrame or 0) > 0
    local file, l, r, t, b
    if wanted then
        file, l, r, t, b = clawTexCoords(ns.db.comboPoints.clawFrame)
    end
    f._claw = file ~= nil
    if f._claw then
        f.claw:SetTexture(file)
        f.claw:SetTexCoord(l, r, t, b)
    end
    f.claw:SetShown(f._claw)
    f.shadow:SetShown(not f._claw)
    f.icon:SetShown(not f._claw)
end

-- The ring glow and the slash are effects, not state: both rest hidden and are
-- driven by gainAnim. Only the resting shape says how many points are up.
local function setPointActive(f, on)
    if f._claw then
        f.active:Hide()
        f.inactive:Hide()
        local shade = on and 1.0 or 0.22
        f.claw:SetVertexColor(shade, shade, shade)
        f.claw:SetAlpha(on and 1.0 or 0.55)
    else
        f.active:SetShown(on)
        f.inactive:SetShown(not on)
        f.icon:SetAlpha(on and 1.0 or 0.30)
    end
    if not on then
        if f.gainAnim then f.gainAnim:Stop() end
        f.glow:Hide()
        f.slash:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

local function buildFrame()
    if container then return end
    local cfg = ns.db.comboPoints

    container = CreateFrame("Frame", "DjinnisComboPoints", UIParent)
    container:SetMovable(true)
    container:EnableMouse(false) -- enabled only during unlocked mode

    -- Drag handlers, only live while the user has explicitly unlocked.
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        if self._unlocked and not InCombatLockdown() then self:StartMoving() end
    end)
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.savePosition(self, ns.db.comboPoints)
    end)

    container:Hide()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function applyLayout()
    if not container or not ns.db then return end
    local cfg = ns.db.comboPoints
    local size, gap = cfg.size, cfg.spacing

    container:SetSize((maxPoints * size) + ((maxPoints - 1) * gap), size)
    ns.applyPosition(container, cfg)

    for i = 1, maxPoints do
        local f = points[i] or buildPoint(i)
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("LEFT", container, "LEFT", (i - 1) * (size + gap), 0)
        f.shadow:SetSize(size * 1.10, size * 1.10)
        f.glow:SetSize(size * 1.60, size * 1.60)
        local sw, sh = SLASH_W * (size / SLASH_BASE), SLASH_H * (size / SLASH_BASE)
        f.slash:SetSize(sw, sh)
        f.claw:SetSize(sw, sh)
        applyStyle(f)
        f:Show()
    end

    -- Talents can lower the cap; hide any point frame past it rather than
    -- destroying it, so raising the cap again costs nothing.
    for i = maxPoints + 1, #points do
        points[i]:Hide()
    end
end
Mod.ApplyLayout = applyLayout

-- ---------------------------------------------------------------------------
-- Visibility policy
-- ---------------------------------------------------------------------------

local function shouldShow()
    if not ns.db or not ns.db.comboPoints.enabled then return false end
    -- Unlock wins over every rule, so the bar can be positioned from any
    -- character, in any form, at any time.
    if container and container._unlocked then return true end
    if not isDruid() then return false end

    local mode = ns.db.comboPoints.visibility
    if mode == "always" then
        return true
    elseif mode == "points" then
        return inCatForm() and lastCount > 0
    else -- "cat"
        return inCatForm()
    end
end

-- ---------------------------------------------------------------------------
-- Redraw
-- ---------------------------------------------------------------------------

local function redraw()
    if not container then return end

    local previous = lastCount
    local n = readCombo()
    if n then lastCount = n end -- nil means secret: keep the last known count

    if not shouldShow() then
        if container:IsShown() then container:Hide() end
        return
    end
    local wasHidden = not container:IsShown()
    if wasHidden then container:Show() end

    for i = 1, maxPoints do
        local f = points[i]
        if f then
            local on = i <= lastCount
            setPointActive(f, on)
            -- Swipe only the points that just lit. Replaying it on every redraw
            -- would fire the claw on a form change or a talent swap, and showing
            -- the bar already full is not a gain.
            if on and not wasHidden and i > previous and f.gainAnim then
                f.gainAnim:Restart()
            end
        end
    end
end
Mod.Redraw = redraw

local function refreshMax()
    local m = readComboMax()
    if m and m ~= maxPoints then
        maxPoints = m
        applyLayout()
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
--
-- Registered one at a time, AFTER SetScript, and each one verified with
-- IsEventRegistered. 12.1 can refuse a RegisterEvent silently: no Lua error is
-- raised and pcall sees nothing, so IsEventRegistered is the only thing that
-- tells the truth. See workspace docs/DECISIONS.md, 2026-08-21.

local eventFrame = CreateFrame("Frame")

local function onEvent(self, event)
    if event == "UNIT_MAXPOWER" then
        refreshMax()
    end
    redraw()
end

-- Refusals are reported once and never retried. Retrying a refused event on
-- every load is what produced 122 ADDON_ACTION_FORBIDDEN errors in BearWatch.
local function registerEvents()
    eventFrame:SetScript("OnEvent", onEvent)

    local refused = {}

    local function reg(event, unit)
        if unit then
            eventFrame:RegisterUnitEvent(event, unit)
        else
            eventFrame:RegisterEvent(event)
        end
        if not eventFrame:IsEventRegistered(event) then
            refused[#refused + 1] = event
        end
    end

    reg("UNIT_POWER_FREQUENT", "player") -- combo point gained or spent
    reg("UNIT_MAXPOWER", "player")       -- talent changed the cap
    reg("UNIT_DISPLAYPOWER", "player")   -- shifted into or out of cat
    reg("UPDATE_SHAPESHIFT_FORM")
    reg("PLAYER_ENTERING_WORLD")

    if #refused > 0 then
        print("Combo points: the game refused these events: " .. table.concat(refused, ", ")
            .. ". The display will not update. Nothing is retried.")
    end
end

-- ---------------------------------------------------------------------------
-- Init / public API
-- ---------------------------------------------------------------------------

function Mod.OnDBReady() end

function Mod.GetFrame() return container end

function Mod.Init()
    if not ns.db or not ns.db.comboPoints.enabled then return end
    if not isDruid() then return end

    buildFrame()
    maxPoints = readComboMax() or DEFAULT_MAX
    applyLayout()
    registerEvents()
    redraw()
end

-- ---------------------------------------------------------------------------
-- Unlock / preview
-- ---------------------------------------------------------------------------

local function setUnlocked(unlocked)
    if not container then return end
    container._unlocked = unlocked and true or false
    container:EnableMouse(container._unlocked)
    if container._unlocked then
        -- Light up three points so there is something to aim at while dragging.
        for i = 1, maxPoints do
            if points[i] then setPointActive(points[i], i <= 3) end
        end
        container:Show()
    else
        redraw()
    end
end
Mod.SetUnlocked = setUnlocked

-- ---------------------------------------------------------------------------
-- Slash command handler, dispatched from Core.lua as `/djue cp ...`
-- ---------------------------------------------------------------------------

function Mod.HandleCommand(rest)
    local cmd, args = rest:match("^(%S*)%s*(.*)$")
    cmd = cmd or ""
    local cfg = ns.db and ns.db.comboPoints
    if not cfg then print("DB not ready.") return end

    if cmd == "" or cmd == "status" then
        print(("ComboPoints: enabled=%s scale=%.2f size=%d gap=%d pos=(%s,%s,%d,%d) vis=%s claw=%d points=%d/%d")
            :format(tostring(cfg.enabled), cfg.scale, cfg.size, cfg.spacing,
                cfg.point, cfg.relativePoint, cfg.x, cfg.y, cfg.visibility,
                cfg.clawFrame or 0, lastCount, maxPoints))
    elseif cmd == "reset" then
        local d = ns.DEFAULTS.comboPoints
        cfg.size, cfg.spacing, cfg.scale = d.size, d.spacing, d.scale
        cfg.point, cfg.relativePoint = d.point, d.relativePoint
        cfg.x, cfg.y = d.x, d.y
        cfg.clawFrame = d.clawFrame
        applyLayout()
        print("Combo points reset.")
    elseif cmd == "size" then
        local n = tonumber(args)
        if n and n >= 8 and n <= 80 then
            cfg.size = math.floor(n + 0.5)
            applyLayout()
            print("Size: " .. cfg.size)
        else
            print("Usage: /djue cp size <8..80>")
        end
    elseif cmd == "gap" or cmd == "spacing" then
        local n = tonumber(args)
        if n and n >= 0 and n <= 40 then
            cfg.spacing = math.floor(n + 0.5)
            applyLayout()
            print("Spacing: " .. cfg.spacing)
        else
            print("Usage: /djue cp gap <0..40>")
        end
    elseif cmd == "scale" then
        local n = tonumber(args)
        if n and n > 0.3 and n < 3 then
            cfg.scale = n
            applyLayout()
            print("Scale: " .. n)
        else
            print("Usage: /djue cp scale <0.3..3.0>")
        end
    elseif cmd == "claw" then
        local n = tonumber(args)
        if n and n >= 0 and n <= SLASH.frames then
            cfg.clawFrame = math.floor(n)
            applyLayout()
            -- Light every point so the shape can actually be judged, then let
            -- the next power event put the real count back.
            for i = 1, maxPoints do
                if points[i] then setPointActive(points[i], true) end
            end
            if cfg.clawFrame == 0 then
                print("Claw 0: round gems, Blizzard's resting art.")
            else
                print(("Claw frame %d of %d. All points lit so you can judge it; next point gained or spent restores the real count. Try the neighbours: /djue cp claw %d")
                    :format(cfg.clawFrame, SLASH.frames, cfg.clawFrame + 1))
            end
        else
            print(("Usage: /djue cp claw <0..%d>. 0 is the round gems; 1 to %d pin that frame of the swipe as a still claw.")
                :format(SLASH.frames, SLASH.frames))
        end
    elseif cmd == "test" or cmd == "swipe" then
        -- The swipe lasts one second and only fires on a gain, so "I saw
        -- nothing" is ambiguous between a broken claw and a missed one. This
        -- plays it on demand, out of combat, with nothing else going on.
        if not container then print("Not built. /djue cp show first.") return end
        local played = 0
        for i = 1, maxPoints do
            local f = points[i]
            if f and f.gainAnim then
                setPointActive(f, true)
                f.gainAnim:Restart()
                played = played + 1
            end
        end
        print(("Swiped %d point(s). hasClaw=%s. Points return to their real state on the next update.")
            :format(played, tostring(points[1] and points[1].hasClaw or false)))
    elseif cmd == "unlock" then
        setUnlocked(true)
        print("Combo points unlocked (drag to move; /djue cp lock to save).")
    elseif cmd == "lock" then
        setUnlocked(false)
        print("Combo points locked.")
    elseif cmd == "show" then
        cfg.enabled = true
        if not container then Mod.Init() else redraw() end
        print("Combo points enabled.")
    elseif cmd == "hide" then
        cfg.enabled = false
        if container then container:Hide() end
        print("Combo points disabled.")
    elseif cmd == "vis" or cmd == "visibility" then
        if args == "always" or args == "cat" or args == "points" then
            cfg.visibility = args
            redraw()
            print("Visibility: " .. args)
        else
            print("Usage: /djue cp vis <always|cat|points>")
        end
    elseif cmd == "debug" then
        -- Every signal redraw() and shouldShow() depend on. Run this in and out
        -- of combat, in and out of cat form, at 0 and at 5 points. If the
        -- display is wrong, one of these lines is wrong, and it says which.
        local _, class = UnitClass("player")
        local raw      = readCombo()
        local rawMax   = readComboMax()
        print("---- ComboPoints debug ----")
        print(("class=%s isDruid=%s powerType=%s inCatForm=%s")
            :format(tostring(class), tostring(isDruid()),
                    tostring(UnitPowerType("player")), tostring(inCatForm())))
        print(("inCombat=%s lockdown=%s")
            :format(tostring(UnitAffectingCombat("player")), tostring(InCombatLockdown())))
        print(("powerWouldBeSecret=%s readCombo=%s readComboMax=%s")
            :format(tostring(powerWouldBeSecret()),
                    raw and tostring(raw) or "<secret/unreadable>",
                    rawMax and tostring(rawMax) or "<secret/unreadable>"))
        print(("lastCount=%d maxPoints=%d builtPointFrames=%d")
            :format(lastCount, maxPoints, #points))
        local regs = {}
        for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                             "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }) do
            regs[#regs + 1] = e .. "=" .. tostring(eventFrame:IsEventRegistered(e))
        end
        print("events: " .. table.concat(regs, " "))
        local function atlasOk(name)
            return C_Texture and C_Texture.GetAtlasInfo
                and C_Texture.GetAtlasInfo(name) ~= nil
        end
        print(("atlasPresent=%s slashAtlas=%s clawAnim=%s")
            :format(tostring(atlasOk(ATLAS.active)), tostring(atlasOk(ATLAS.slash)),
                    tostring(points[1] and points[1].hasClaw or false)))
        print("  (atlasPresent false = art fell back to plain squares;"
            .. " clawAnim false = gain pulses the glow only, no claw swipe)")
        print(("visibility=%s -> shouldShow=%s frameShown=%s _unlocked=%s")
            :format(cfg.visibility, tostring(shouldShow()),
                    tostring(container and container:IsShown()),
                    tostring(container and container._unlocked or false)))
    else
        print("cp commands: status | debug | test | claw <0..20> | reset | size <n> | gap <n> | scale <n> | unlock | lock | show | hide | vis <always|cat|points>")
    end
end

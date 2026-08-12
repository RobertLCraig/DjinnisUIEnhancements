local ADDON_NAME, ns = ...

local Mod = {}
ns.modules.IronfurBar = Mod

-- ---------------------------------------------------------------------------
-- Spell + form IDs
-- ---------------------------------------------------------------------------

local IRONFUR_SPELL_ID       = 192081

local UPDATE_INTERVAL = 0.05
local FALLBACK_DURATION = 7  -- baseline Ironfur duration; refined from live aura

-- ---------------------------------------------------------------------------
-- Local state
-- ---------------------------------------------------------------------------

local print = ns.print or function() end

-- Stack queue, oldest at index 1 → newest at #stacks. Each entry is the
-- GetTime()-relative expiration timestamp for that individual application.
local stacks = {}

local bar              -- main StatusBar (contains everything)
local barContainer     -- parent Frame (positioned/dragged)
local stackText
local timeText
local markerPool = {}  -- recycled vertical-pipe textures
local lastDuration = FALLBACK_DURATION
local elapsedAccum = 0

-- Last-known stack count from UNIT_AURA, used to compute deltas. Each delta
-- tells us how many new stacks were added (or fell off the front of the queue).
local lastSeenStacks = 0
local lastSeenInstanceID = nil

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function isDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

-- Bear Form detection. Primary: GetShapeshiftFormID() == 5 (Bear Form in
-- current retail; Incarnation: Guardian of Ursoc keeps the same form id since
-- it's still "bear, just empowered"). Aura-based detection was tried but
-- C_UnitAuras.GetPlayerAuraBySpellID(5487) returns nil in combat even when
-- the player is genuinely in Bear Form, so it's unreliable as a fallback.
local BEAR_FORM_ID = 5

local function inBearForm()
    return GetShapeshiftFormID and GetShapeshiftFormID() == BEAR_FORM_ID
end

-- Only safe to call OUT of combat. In combat, aura.spellId / applications /
-- expirationTime become "secret" values: GetPlayerAuraBySpellID returns nil
-- and iterating auras triggers "attempt to compare secret value" taint errors.
-- See SecretPredicatesDocumentation.lua → SecretWhenUnitAuraRestricted.
local function getLiveIronfurAura()
    if InCombatLockdown() then return nil end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(IRONFUR_SPELL_ID)
    end
    return nil
end

-- Single live aura on the player; .duration is the spell's nominal duration
-- (varies with Reinvigoration etc.). Cache it whenever we see it so we can
-- still create new stacks correctly between aura refreshes.
local function refreshDurationFromAura()
    local d = getLiveIronfurAura()
    if d and d.duration and d.duration > 0 then
        lastDuration = d.duration
    end
end

-- Drop already-expired stacks from the front of the queue.
local function pruneExpired(now)
    while stacks[1] and stacks[1] <= now do
        table.remove(stacks, 1)
    end
end

-- ---------------------------------------------------------------------------
-- Marker pool (vertical chapter-pipes on the bar)
-- ---------------------------------------------------------------------------

local function acquireMarker()
    for _, m in ipairs(markerPool) do
        if not m:IsShown() then
            m:Show()
            return m
        end
    end
    local tex = bar:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetSize(2, 1) -- height set per-draw to match bar
    table.insert(markerPool, tex)
    tex:Show()
    return tex
end

local function releaseAllMarkers()
    for _, m in ipairs(markerPool) do m:Hide() end
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

local function buildFrame()
    if barContainer then return end
    local cfg = ns.db.ironfurBar

    barContainer = CreateFrame("Frame", "DjinnisIronfurBar", UIParent, "BackdropTemplate")
    barContainer:SetSize(cfg.width, cfg.height)
    barContainer:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
    barContainer:SetScale(cfg.scale)
    barContainer:SetMovable(true)
    barContainer:EnableMouse(false) -- enabled only during unlocked mode

    barContainer:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    barContainer:SetBackdropColor(0, 0, 0, 0.55)
    barContainer:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    bar = CreateFrame("StatusBar", nil, barContainer)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetPoint("TOPLEFT", 3, -3)
    bar:SetPoint("BOTTOMRIGHT", -3, 3)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local c = cfg.barColor
    bar:SetStatusBarColor(c[1], c[2], c[3], 1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)

    stackText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    stackText:SetPoint("LEFT", 6, 0)
    stackText:SetTextColor(1, 1, 1, 1)
    stackText:SetText("")

    timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeText:SetPoint("RIGHT", -6, 0)
    timeText:SetTextColor(1, 1, 1, 1)
    timeText:SetText("")

    -- Drag handlers — only fire when the user explicitly unlocks via /djue ifb unlock
    barContainer:RegisterForDrag("LeftButton")
    barContainer:SetScript("OnDragStart", function(self)
        if self._unlocked and not InCombatLockdown() then self:StartMoving() end
    end)
    barContainer:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        local c = ns.db.ironfurBar
        c.point = point
        c.relativePoint = relativePoint
        c.x = math.floor(x + 0.5)
        c.y = math.floor(y + 0.5)
    end)

    barContainer:Hide()
end

-- ---------------------------------------------------------------------------
-- Visibility policy
-- ---------------------------------------------------------------------------

local function shouldShow()
    if not ns.db or not ns.db.ironfurBar.enabled then return false end
    -- Unlock mode wins over every other rule so the user can position the
    -- bar from any character at any time.
    if barContainer and barContainer._unlocked then return true end
    if not isDruid() then return false end

    local mode = ns.db.ironfurBar.visibility
    if mode == "always" then
        return true
    elseif mode == "bear" then
        if #stacks > 0 then return true end
        return inBearForm()
    else -- "onlyWithStacks"
        return #stacks > 0
    end
end

-- ---------------------------------------------------------------------------
-- Per-tick redraw
-- ---------------------------------------------------------------------------

local function redraw()
    if not barContainer then return end

    local now = GetTime()
    pruneExpired(now)

    if not shouldShow() then
        if barContainer:IsShown() then barContainer:Hide() end
        return
    end

    if not barContainer:IsShown() then barContainer:Show() end

    -- Unlock mode keeps the preview frozen so the user can drag/size against
    -- representative content; the next live tick after lock restores reality.
    if barContainer._unlocked and #stacks == 0 then
        return
    end

    local count = #stacks
    if count == 0 then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        stackText:SetText("")
        timeText:SetText("")
        releaseAllMarkers()
        return
    end

    -- Bar fills based on the NEWEST stack's remaining time.
    local newestExpire = stacks[count]
    local newestRemaining = math.max(0, newestExpire - now)
    local duration = lastDuration > 0 and lastDuration or FALLBACK_DURATION
    bar:SetMinMaxValues(0, duration)
    bar:SetValue(newestRemaining)

    stackText:SetText(tostring(count))
    timeText:SetText(("%.1f"):format(newestRemaining))

    -- Markers: one vertical pipe per OLDER stack (everything except newest),
    -- positioned proportionally along the bar at (remaining / duration).
    releaseAllMarkers()
    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    local cfgMarker = ns.db.ironfurBar.markerColor
    local markerW = ns.db.ironfurBar.markerWidth or 2

    for i = 1, count - 1 do
        local remaining = math.max(0, stacks[i] - now)
        local frac = remaining / duration
        if frac > 0 and frac <= 1 then
            local m = acquireMarker()
            m:SetSize(markerW, barHeight)
            m:SetColorTexture(cfgMarker[1], cfgMarker[2], cfgMarker[3], 1)
            m:ClearAllPoints()
            m:SetPoint("LEFT", bar, "LEFT", frac * barWidth - (markerW * 0.5), 0)
        end
    end
end

local function onUpdate(self, elapsed)
    elapsedAccum = elapsedAccum + elapsed
    if elapsedAccum < UPDATE_INTERVAL then return end
    elapsedAccum = 0
    local ok, err = pcall(redraw)
    if not ok then
        -- Swallow rather than spam the chat. If something's wrong we just
        -- show an empty bar for one tick.
    end
end

-- ---------------------------------------------------------------------------
-- Aura tracking
-- ---------------------------------------------------------------------------
--
-- We derive per-stack timers from UNIT_AURA stack-count deltas rather than
-- COMBAT_LOG_EVENT_UNFILTERED. Combat log has HasRestrictions/CallbackEvent
-- in modern WoW retail, so Frame:RegisterEvent() trips ADDON_ACTION_FORBIDDEN.
-- UNIT_AURA is unrestricted and gives us exactly what we need:
--   - aura's auraInstanceID identifies a fresh application chain
--   - aura's applications is the current stack count
--   - aura's expirationTime is the NEWEST stack's expiration (the latest cast)
-- Older stacks' individual expirations are NOT exposed, so we track them
-- ourselves: every stack we've ever appended keeps its original timestamp.

-- In-combat-safe path: UNIT_SPELLCAST_SUCCEEDED for the player gives us
-- spellID readable (player's own cast info is exempt from combat secrecy).
-- We don't get duration/expiration from that event — we use the lastDuration
-- cached from the most recent out-of-combat aura read (default 7s).
local function handleIronfurCast()
    table.insert(stacks, GetTime() + (lastDuration or FALLBACK_DURATION))
    lastSeenStacks = #stacks
    elapsedAccum = UPDATE_INTERVAL -- nudge a redraw
end

local function handleAuraChange()
    local d = getLiveIronfurAura()
    if not d then
        if #stacks > 0 then stacks = {} end
        lastSeenStacks = 0
        lastSeenInstanceID = nil
        return
    end

    refreshDurationFromAura()
    local count = d.applications or 1
    if count <= 0 then count = 1 end
    local exp = d.expirationTime

    -- Aura instance changed → fresh application chain. We don't know the
    -- individual expirations for any pre-existing stacks in this chain
    -- (e.g. addon loaded mid-combat), so seed everything at `exp`. They'll
    -- spread out correctly as new casts arrive.
    if d.auraInstanceID ~= lastSeenInstanceID then
        stacks = {}
        for i = 1, count do
            table.insert(stacks, exp)
        end
        lastSeenInstanceID = d.auraInstanceID
        lastSeenStacks = count
        return
    end

    if count > lastSeenStacks then
        -- N new stacks: append at the aura's current expirationTime (they
        -- are the newly-added "newest" stacks).
        for i = 1, count - lastSeenStacks do
            table.insert(stacks, exp)
        end
    elseif count < lastSeenStacks then
        -- N stacks fell off naturally: pop from the front (oldest first).
        for i = 1, lastSeenStacks - count do
            table.remove(stacks, 1)
        end
        if stacks[#stacks] then stacks[#stacks] = exp end
    else
        -- Same count but expirationTime advanced → at-cap refresh: only the
        -- newest stack's timer was reset; older ones keep their countdowns.
        if stacks[#stacks] and exp > (stacks[#stacks] or 0) then
            stacks[#stacks] = exp
        end
    end

    lastSeenStacks = count
end

-- Events are registered at FILE LOAD time.
--
-- Why this event set:
-- * COMBAT_LOG_EVENT_UNFILTERED — restricted (HasRestrictions/CallbackEvent),
--   Frame:RegisterEvent trips ADDON_ACTION_FORBIDDEN. NOT usable.
-- * UNIT_AURA — works, but the aura *fields* (spellId, applications,
--   expirationTime) become secret in combat, so it can only sync state
--   while out of combat.
-- * UNIT_SPELLCAST_SUCCEEDED — SecretWhenUnitSpellCastRestricted *exempts*
--   the player's own casts, so spellID is readable even in combat.
--   This is our only signal for "Ironfur was cast" during a fight.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- combat begin
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- combat end → resync
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- Bail out cleanly until Init has wired things up. Events that fire
    -- pre-PLAYER_LOGIN are harmlessly dropped.
    if not Mod._initialized then return end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if spellID == IRONFUR_SPELL_ID then
            handleIronfurCast()
        end
    elseif event == "UNIT_AURA" then
        -- Only safe out of combat — aura fields are secret in combat and
        -- reading them triggers "secret value comparison" taint errors.
        if not InCombatLockdown() then handleAuraChange() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat just ended → aura data is readable again; full resync.
        handleAuraChange()
        elapsedAccum = UPDATE_INTERVAL
    elseif event == "PLAYER_REGEN_DISABLED"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "PLAYER_ENTERING_WORLD"
    then
        if event == "PLAYER_ENTERING_WORLD" and not InCombatLockdown() then
            handleAuraChange()
        end
        elapsedAccum = UPDATE_INTERVAL
    end
end)

-- ---------------------------------------------------------------------------
-- Layout / lock helpers
-- ---------------------------------------------------------------------------

local function applyLayout()
    if not barContainer or not ns.db then return end
    local cfg = ns.db.ironfurBar
    barContainer:SetSize(cfg.width, cfg.height)
    barContainer:SetScale(cfg.scale)
    barContainer:ClearAllPoints()
    barContainer:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
    local c = cfg.barColor
    if bar then bar:SetStatusBarColor(c[1], c[2], c[3], 1) end
end
Mod.ApplyLayout = applyLayout

local function setUnlocked(unlocked)
    if not barContainer then return end
    barContainer._unlocked = unlocked and true or false
    barContainer:EnableMouse(unlocked and true or false)
    if unlocked then
        -- Preview content so the user can see what they're dragging when
        -- there are no real Ironfur stacks active.
        if #stacks == 0 then
            stackText:SetText("3")
            timeText:SetText("5.0")
            bar:SetMinMaxValues(0, lastDuration)
            bar:SetValue(lastDuration * 0.7)
            releaseAllMarkers()
            local barWidth = bar:GetWidth()
            local barHeight = bar:GetHeight()
            local cfgMarker = ns.db.ironfurBar.markerColor
            for i, frac in ipairs({ 0.2, 0.45 }) do
                local m = acquireMarker()
                m:SetSize(2, barHeight)
                m:SetColorTexture(cfgMarker[1], cfgMarker[2], cfgMarker[3], 1)
                m:ClearAllPoints()
                m:SetPoint("LEFT", bar, "LEFT", frac * barWidth - 1, 0)
            end
        end
        if not barContainer:IsShown() then barContainer:Show() end
        barContainer:SetBackdropBorderColor(0.2, 0.6, 1.0, 1.0)
    else
        barContainer:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
end

-- ---------------------------------------------------------------------------
-- Init / public API
-- ---------------------------------------------------------------------------

function Mod.OnDBReady() end

function Mod.GetFrame() return barContainer end

function Mod.Init()
    if not ns.db or not ns.db.ironfurBar.enabled then return end

    buildFrame()

    -- A tiny driver frame owns the ticker so we don't attach OnUpdate to a
    -- frame that may get parented elsewhere.
    local driver = CreateFrame("Frame", "DjinnisIronfurDriver", UIParent)
    driver:SetSize(1, 1)
    driver:SetScript("OnUpdate", onUpdate)

    -- Seed state from whatever aura is up at login (mid-combat reload).
    handleAuraChange()

    -- Flip last so the file-scope event handler starts processing real work.
    Mod._initialized = true
end

-- ---------------------------------------------------------------------------
-- Slash command handler — dispatched from Core.lua as `/djue ifb ...`
-- ---------------------------------------------------------------------------

function Mod.HandleCommand(rest)
    local cmd, args = rest:match("^(%S*)%s*(.*)$")
    cmd = cmd or ""
    local cfg = ns.db and ns.db.ironfurBar
    if not cfg then print("DB not ready.") return end

    if cmd == "" or cmd == "status" then
        print(("IronfurBar: enabled=%s scale=%.2f size=%dx%d pos=(%s,%s,%d,%d) vis=%s stacks=%d")
            :format(tostring(cfg.enabled), cfg.scale, cfg.width, cfg.height,
                cfg.point, cfg.relativePoint, cfg.x, cfg.y, cfg.visibility, #stacks))
    elseif cmd == "reset" then
        local d = ns.DEFAULTS.ironfurBar
        cfg.width, cfg.height = d.width, d.height
        cfg.point, cfg.relativePoint = d.point, d.relativePoint
        cfg.x, cfg.y = d.x, d.y
        cfg.scale = d.scale
        applyLayout()
        print("Ironfur bar reset.")
    elseif cmd == "size" then
        local w, h = args:match("(%d+)%s+(%d+)")
        w, h = tonumber(w), tonumber(h)
        if w and h then
            cfg.width, cfg.height = w, h
            applyLayout()
            print(("Size: %dx%d"):format(w, h))
        else
            print("Usage: /djue ifb size <width> <height>")
        end
    elseif cmd == "scale" then
        local n = tonumber(args)
        if n and n > 0.3 and n < 3 then
            cfg.scale = n
            applyLayout()
            print("Scale: " .. n)
        else
            print("Usage: /djue ifb scale <0.3..3.0>")
        end
    elseif cmd == "unlock" then
        setUnlocked(true)
        print("Ironfur bar unlocked (drag to move; /djue ifb lock to save).")
    elseif cmd == "lock" then
        setUnlocked(false)
        print("Ironfur bar locked.")
    elseif cmd == "show" then
        cfg.enabled = true
        if not barContainer then Mod.Init() end
        print("Ironfur bar enabled.")
    elseif cmd == "hide" then
        cfg.enabled = false
        if barContainer then barContainer:Hide() end
        print("Ironfur bar disabled.")
    elseif cmd == "vis" or cmd == "visibility" then
        if args == "always" or args == "bear" or args == "stacks" then
            cfg.visibility = (args == "stacks") and "onlyWithStacks" or args
            print("Visibility: " .. cfg.visibility)
        else
            print("Usage: /djue ifb vis <always|bear|stacks>")
        end
    elseif cmd == "debug" then
        -- Snapshot every signal shouldShow() depends on, plus a couple of
        -- live-state observables. Run /djue ifb debug in/out of combat,
        -- in/out of bear form, with/without Ironfur stacks to compare.
        --
        -- NOTE: we deliberately do NOT iterate auras here (AuraUtil.ForEachAura
        -- / GetAuraDataByIndex) — in combat their callbacks receive auras with
        -- secret spellId fields, and `aura.spellId == X` taints us. Direct
        -- GetPlayerAuraBySpellID is fine because the spellID argument we pass
        -- is a literal and the returned table is only inspected for nil-ness.
        local _, class = UnitClass("player")
        local formID    = GetShapeshiftFormID and GetShapeshiftFormID()
        local ironfur   = getLiveIronfurAura()
        local cf        = (UnitAffectingCombat and UnitAffectingCombat("player")) and "yes" or "no"
        local lockdown  = InCombatLockdown() and "yes" or "no"
        local visible   = (barContainer and barContainer:IsShown()) and "yes" or "no"
        local shown     = shouldShow() and "yes" or "no"

        print("---- IronfurBar debug ----")
        print(("class=%s isDruid=%s"):format(tostring(class), tostring(isDruid())))
        print(("inCombat=%s lockdown=%s"):format(cf, lockdown))
        print(("shapeshiftFormID=%s -> inBearForm=%s")
            :format(tostring(formID), tostring(inBearForm())))
        -- ironfur fields are only safe to read out of combat; in combat the
        -- table itself may be nil and reading fields would taint us.
        local apps, expLeft, instID = "-", "-", "-"
        if ironfur and not lockdown then
            apps    = tostring(ironfur.applications)
            expLeft = ("%.2fs left"):format((ironfur.expirationTime or GetTime()) - GetTime())
            instID  = tostring(ironfur.auraInstanceID)
        elseif lockdown then
            apps = "<combat: unreadable>"
        end
        print(("ironfurAura=%s applications=%s expirationTime=%s instanceID=%s")
            :format(ironfur and "yes" or "no", apps, expLeft, instID))
        print(("trackedStacks=%d lastSeenStacks=%d lastSeenInstanceID=%s lastDuration=%.1f")
            :format(#stacks, lastSeenStacks, tostring(lastSeenInstanceID), lastDuration))
        if #stacks > 0 then
            local now = GetTime()
            local parts = {}
            for i, exp in ipairs(stacks) do
                parts[#parts + 1] = ("[%d]=%.1fs"):format(i, exp - now)
            end
            print("  stack remaining: " .. table.concat(parts, " "))
        end
        print(("visibility=%s -> shouldShow=%s frameShown=%s _unlocked=%s")
            :format(cfg.visibility, shown, visible,
                    tostring(barContainer and barContainer._unlocked or false)))
    else
        print("ifb commands: status | debug | reset | size <w> <h> | scale <n> | unlock | lock | show | hide | vis <always|bear|stacks>")
    end
end

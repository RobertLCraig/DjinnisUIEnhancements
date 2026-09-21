-- Offline check for ComboPoints.lua. Run with plain Lua 5.1:
--
--     lua tests/test_combopoints.lua
--
-- No game client, no framework. It exists for the one thing that cannot be
-- checked in a live client: the secret-value path. Rob cannot force UnitPower
-- to return a secret on demand, so the guard would otherwise ship unproven.
--
-- The fake secret is a table whose comparison metamethods raise. If the module
-- ever compares a secret instead of testing it with issecretvalue first, this
-- file fails loudly with the exact error 12.1 would produce in the client.

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. (detail and ("  -- " .. detail) or ""))
    end
end

-- ---------------------------------------------------------------------------
-- The fake secret value
-- ---------------------------------------------------------------------------

local secretMT = {}
local function boom() error("attempt to compare secret value", 2) end
secretMT.__lt, secretMT.__le, secretMT.__eq = boom, boom, boom
secretMT.__concat, secretMT.__add = boom, boom
local SECRET = setmetatable({}, secretMT)

-- ---------------------------------------------------------------------------
-- Minimal WoW API stubs
-- ---------------------------------------------------------------------------

local function newTexture()
    local t = { shown = true, alpha = 1 }
    function t:SetAtlas() end
    function t:SetColorTexture() end
    function t:SetPoint() end
    function t:SetAllPoints() end
    function t:SetSize() end
    function t:SetTexture() end
    function t:SetTexCoord() end
    function t:SetVertexColor() end
    function t:SetShown(v) self.shown = v and true or false end
    function t:SetAlpha(v) self.alpha = v end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end

-- Animation stubs. The group counts its Restart calls, which is how the tests
-- tell "the claw swiped" from "the point is merely lit".
local function newAnimation()
    local a = {}
    function a:SetTarget() end
    function a:SetDuration() end
    function a:SetStartDelay() end
    function a:SetFromAlpha() end
    function a:SetToAlpha() end
    function a:SetFlipBookRows() end
    function a:SetFlipBookColumns() end
    function a:SetFlipBookFrames() end
    return a
end

local function newAnimGroup()
    local g = { restarts = 0, _scripts = {} }
    function g:SetToFinalAlpha() end
    function g:CreateAnimation() return newAnimation() end
    function g:SetScript(k, fn) self._scripts[k] = fn end
    function g:Restart()
        self.restarts = self.restarts + 1
        if self._scripts.OnPlay then self._scripts.OnPlay() end
    end
    function g:Stop()
        if self._scripts.OnStop then self._scripts.OnStop() end
    end
    return g
end

local function newFrame(_, _, parent)
    local f = { _shown = true, _children = {}, _events = {} }
    function f:CreateAnimationGroup() return newAnimGroup() end
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetScale() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:ClearAllPoints() end
    function f:RegisterForDrag() end
    function f:SetScript() end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:CreateTexture() return newTexture() end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:RegisterUnitEvent(e) self._events[e] = true end
    function f:IsEventRegistered(e) return self._events[e] or false end
    if parent and parent._children then
        parent._children[#parent._children + 1] = f
    end
    return f
end

-- Mutable world state the tests drive.
local world = {
    class = "DRUID",
    powerType = 3,      -- Energy, i.e. cat form
    combo = 0,
    comboMax = 5,
    secretPower = false,
}

local env = setmetatable({}, { __index = _G })
env.Enum = { PowerType = { ComboPoints = 4, Energy = 3 } }
env.UIParent = {}
env.CreateFrame = newFrame
env.UnitClass = function() return "Druid", world.class end
env.UnitPowerType = function() return world.powerType end
env.UnitPower = function() return world.secretPower and SECRET or world.combo end
env.UnitPowerMax = function() return world.secretPower and SECRET or world.comboMax end
env.UnitAffectingCombat = function() return false end
env.InCombatLockdown = function() return false end
env.issecretvalue = function(v) return v == SECRET end -- rawequal-style, no metamethod
env.C_Secrets = { ShouldUnitPowerBeSecret = function() return world.secretPower end,
                  ShouldUnitPowerMaxBeSecret = function() return world.secretPower end }
-- `atlasKnown = false` is a client that no longer has the UF-DruidCP-* names.
world.atlasKnown = true
env.C_Texture = {
    GetAtlasInfo = function()
        if not world.atlasKnown then return nil end
        return {
            width = 20, height = 20, file = 12345,
            leftTexCoord = 0.0, rightTexCoord = 0.5,
            topTexCoord = 0.0, bottomTexCoord = 0.25,
        }
    end,
}

-- issecretvalue must not itself trip the metamethods.
env.issecretvalue = function(v) return rawequal(v, SECRET) end

-- ---------------------------------------------------------------------------
-- Load the module under test
-- ---------------------------------------------------------------------------

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."

-- WoW runs Lua 5.1, but this harness runs on whatever `lua` is on PATH, so
-- load a file into `env` the way both versions allow.
local function load(file, ns)
    local chunk
    if setfenv then
        chunk = assert(loadfile(here .. "/../" .. file))
        setfenv(chunk, env)
    else
        chunk = assert(loadfile(here .. "/../" .. file, "t", env))
    end
    chunk("DjinnisUIEnhancements", ns)
end

-- Core.lua first, for the real ns.savePosition / ns.applyPosition.
env.SlashCmdList = {}
env.UIParent.GetCenter = function() return 960, 540 end
local ns = {}
load("Core.lua", ns)
ns.print = function() end
ns.DEFAULTS = {
    comboPoints = {
        enabled = true, scale = 1.0, size = 26, spacing = 8,
        point = "CENTER", relativePoint = "CENTER", x = 0, y = -200,
        visibility = "cat",
    },
}
ns.DEFAULTS.comboPoints.clawFrame = 0 -- gems, so litCount() reads the gem art
ns.db = { comboPoints = {} }
for k, v in pairs(ns.DEFAULTS.comboPoints) do ns.db.comboPoints[k] = v end

load("ComboPoints.lua", ns)

local Mod = ns.modules.ComboPoints
Mod.Init()

local container = Mod.GetFrame()
check("container was built", container ~= nil)

-- How many points are lit, read off the art itself.
local function litCount()
    local n = 0
    for _, child in ipairs(container._children) do
        if child.active and child.active.shown then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Ordinary counting
-- ---------------------------------------------------------------------------

for _, n in ipairs({ 0, 1, 3, 5 }) do
    world.combo = n
    Mod.Redraw()
    check("shows " .. n .. " points", litCount() == n, "got " .. litCount())
end

-- ---------------------------------------------------------------------------
-- The secret path: must not throw, and must hold the last known count
-- ---------------------------------------------------------------------------

world.combo = 4
Mod.Redraw()
check("baseline before secret", litCount() == 4, "got " .. litCount())

world.secretPower = true
local ok, err = pcall(Mod.Redraw)
check("redraw survives a secret power value", ok, tostring(err))
check("holds the last known count while secret", litCount() == 4, "got " .. litCount())

world.secretPower = false
world.combo = 2
Mod.Redraw()
check("recovers once the value is readable again", litCount() == 2, "got " .. litCount())

-- ---------------------------------------------------------------------------
-- The claw swipe fires on a gain, and only on a gain
-- ---------------------------------------------------------------------------

local function swipes()
    local n = 0
    for _, child in ipairs(container._children) do
        n = n + (child.gainAnim and child.gainAnim.restarts or 0)
    end
    return n
end

local function resetSwipes()
    for _, child in ipairs(container._children) do
        if child.gainAnim then child.gainAnim.restarts = 0 end
    end
end

world.combo = 0
Mod.Redraw()
resetSwipes()

world.combo = 2
Mod.Redraw()
check("two new points swipe twice", swipes() == 2, "got " .. swipes())

resetSwipes()
Mod.Redraw()
check("a redraw with no change does not swipe", swipes() == 0, "got " .. swipes())

resetSwipes()
world.combo = 1
Mod.Redraw()
check("spending a point does not swipe", swipes() == 0, "got " .. swipes())

resetSwipes()
world.combo = 3
Mod.Redraw()
check("only the newly lit points swipe", swipes() == 2, "got " .. swipes())

-- A point going out must not leave the claw or the glow frozen on screen.
world.combo = 0
Mod.Redraw()
local stuck = 0
for _, child in ipairs(container._children) do
    if (child.slash and child.slash.shown) or (child.glow and child.glow.shown) then
        stuck = stuck + 1
    end
end
check("no claw or glow left showing once points are spent", stuck == 0, stuck .. " stuck")

-- ---------------------------------------------------------------------------
-- Visibility policy
-- ---------------------------------------------------------------------------

world.combo = 3
world.powerType = 0 -- Mana: out of cat form
Mod.Redraw()
check("hidden out of cat form", not container:IsShown())

ns.db.comboPoints.visibility = "always"
Mod.Redraw()
check("vis=always shows out of cat form", container:IsShown())

ns.db.comboPoints.visibility = "points"
world.powerType = 3
world.combo = 0
Mod.Redraw()
check("vis=points hides at zero points", not container:IsShown())
world.combo = 1
Mod.Redraw()
check("vis=points shows at one point", container:IsShown())

ns.db.comboPoints.visibility = "cat"
world.class = "ROGUE"
Mod.Redraw()
check("hidden on a non-druid", not container:IsShown())
world.class = "DRUID"

-- ---------------------------------------------------------------------------
-- Events actually got registered
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Claw style: the shape swaps, and a failed crop falls back to the gems
-- ---------------------------------------------------------------------------

local function count(field)
    local n = 0
    for _, child in ipairs(container._children) do
        if child[field] and child[field].shown then n = n + 1 end
    end
    return n
end

ns.db.comboPoints.visibility = "cat"
world.powerType, world.class, world.combo = 3, "DRUID", 3

ns.db.comboPoints.clawFrame = 10
Mod.ApplyLayout()
Mod.Redraw()
check("claw frame shows the claw", count("claw") == 5, "got " .. count("claw"))
check("claw frame hides the gem icon", count("icon") == 0, "got " .. count("icon"))

ns.db.comboPoints.clawFrame = 0
Mod.ApplyLayout()
Mod.Redraw()
check("frame 0 goes back to gems", count("claw") == 0 and count("icon") == 5,
      ("claw=%d icon=%d"):format(count("claw"), count("icon")))
check("gems still count correctly after the round trip", litCount() == 3, "got " .. litCount())

-- A client that no longer knows the atlas must not leave an empty row.
world.atlasKnown = false
ns.db.comboPoints.clawFrame = 10
Mod.ApplyLayout()
Mod.Redraw()
check("unknown atlas falls back to gems rather than nothing",
      count("claw") == 0 and count("icon") == 5,
      ("claw=%d icon=%d"):format(count("claw"), count("icon")))
world.atlasKnown = true
ns.db.comboPoints.clawFrame = 0
Mod.ApplyLayout()

-- ---------------------------------------------------------------------------
-- Scale grows the frame around its centre (Rob, 2026-09-21: it used to slide)
-- ---------------------------------------------------------------------------
--
-- A frame anchored CENTER to UIParent CENTER with offset o, at scale s, has
-- its centre at uiCentre + o*s in UIParent units, and GetCenter() answers in
-- the frame's own units, which is that divided by s.

local function posFrame()
    local f = { s = 1, ox = 0, oy = 0 }
    function f:SetScale(s) self.s = s end
    function f:GetScale() return self.s end
    function f:ClearAllPoints() end
    function f:SetPoint(_, _, _, x, y) self.ox, self.oy = x, y end
    function f:GetCenter() return (960 + self.ox * self.s) / self.s, (540 + self.oy * self.s) / self.s end
    function f:uiCentre() return 960 + self.ox * self.s, 540 + self.oy * self.s end
    return f
end

local pf = posFrame()
local pc = { scale = 1, point = "CENTER", relativePoint = "CENTER", x = 40, y = -200 }
ns.applyPosition(pf, pc)
local x1, y1 = pf:uiCentre()
pc.scale = 1.7
ns.applyPosition(pf, pc)
local x2, y2 = pf:uiCentre()
check("scale change keeps the centre", math.abs(x1 - x2) < 0.01 and math.abs(y1 - y2) < 0.01,
    ("%.1f,%.1f -> %.1f,%.1f"):format(x1, y1, x2, y2))
ns.savePosition(pf, pc)
check("save after scale gives back the same offset", pc.x == 40 and pc.y == -200,
    ("got %s,%s"):format(pc.x, pc.y))

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

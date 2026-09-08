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
    function t:SetShown(v) self.shown = v and true or false end
    function t:SetAlpha(v) self.alpha = v end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end

local function newFrame(_, _, parent)
    local f = { _shown = true, _children = {}, _events = {} }
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
env.C_Texture = { GetAtlasInfo = function() return { width = 20, height = 20 } end }

-- issecretvalue must not itself trip the metamethods.
env.issecretvalue = function(v) return rawequal(v, SECRET) end

-- ---------------------------------------------------------------------------
-- Load the module under test
-- ---------------------------------------------------------------------------

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local ns = { modules = {}, print = function() end }
ns.DEFAULTS = {
    comboPoints = {
        enabled = true, scale = 1.0, size = 26, spacing = 8,
        point = "CENTER", relativePoint = "CENTER", x = 0, y = -200,
        visibility = "cat",
    },
}
ns.db = { comboPoints = {} }
for k, v in pairs(ns.DEFAULTS.comboPoints) do ns.db.comboPoints[k] = v end

-- WoW runs Lua 5.1, but this harness runs on whatever `lua` is on PATH, so
-- load the file into `env` the way both versions allow.
local path = here .. "/../ComboPoints.lua"
local chunk
if setfenv then
    chunk = assert(loadfile(path))
    setfenv(chunk, env)
else
    chunk = assert(loadfile(path, "t", env))
end
chunk("DjinnisUIEnhancements", ns)

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

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

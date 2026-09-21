-- Offline check for EnergyBar.lua. Run with plain Lua 5.1:
--
--     lua tests/test_energybar.lua
--
-- The claim EnergyBar.lua makes is that it never compares, formats or
-- concatenates the energy number, so a secret one passes straight into the
-- widgets. The fake secret raises on all of those, the way 12.1 does.

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. (detail and ("  -- " .. detail) or ""))
    end
end

local function boom() error("attempt to use a secret value", 2) end
local SECRET = setmetatable({}, {
    __lt = boom, __le = boom, __eq = boom, __concat = boom, __add = boom,
    __sub = boom, __tostring = boom,
})

local function newFrame()
    local f = { shown = false, events = {} }
    function f:SetMovable() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor() end
    function f:SetStatusBarTexture() end
    function f:SetStatusBarColor() end
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetScale() end
    function f:ClearAllPoints() end
    function f:SetScript(_, fn) self.onEvent = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:IsEventRegistered(e) return self.events[e] end
    function f:SetMinMaxValues(_, max) self.max = max end
    function f:SetValue(v) self.value = v end
    function f:SetText(v) self.text = v end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:CreateFontString() return newFrame() end
    return f
end

local world = { powerType = 3, power = 60, max = 100 }
local env = setmetatable({}, { __index = _G })
env.Enum = { PowerType = { Energy = 3 }, StatusBarInterpolation = { ExponentialEaseOut = 1 } }
env.UIParent = {}
env.CreateFrame = newFrame
env.UnitPowerType = function() return world.powerType end
env.UnitPower = function() return world.power end
env.UnitPowerMax = function() return world.max end

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local chunk = assert(loadfile(here .. "/../EnergyBar.lua"))
if setfenv then setfenv(chunk, env) else chunk = assert(loadfile(here .. "/../EnergyBar.lua", "t", env)) end

local ns = { modules = {}, print = function() end, applyPosition = function() end }
ns.db = { energyBar = { scale = 1, width = 200, height = 16, visibility = "energy",
                        point = "CENTER", relativePoint = "CENTER", x = 0, y = -230 } }
chunk("DjinnisUIEnhancements", ns)
local Mod = ns.modules.EnergyBar
Mod.Init()
local f = Mod.GetFrame()

check("shown when energy is the power", f.shown)

world.powerType = 1 -- rage: bear form
Mod.Redraw()
check("hidden in bear form", not f.shown)

Mod.SetUnlocked(true)
check("Edit Mode shows it anyway", f.shown)
Mod.SetUnlocked(false)
check("and hides it again after", not f.shown)

world.powerType = 3
world.power, world.max = SECRET, SECRET
local ok, err = pcall(Mod.Redraw)
check("a secret energy value draws without error", ok and f.shown, err)

ns.db.energyBar.visibility = "never"
world.power, world.max = 60, 100
Mod.Redraw()
check("visibility never hides it", not f.shown)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

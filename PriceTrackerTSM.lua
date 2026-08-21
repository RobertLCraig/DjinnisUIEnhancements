local ADDON_NAME, ns = ...

local Mod = {}
ns.modules.PriceTrackerTSM = Mod

-- ---------------------------------------------------------------------------
-- Why this exists
-- ---------------------------------------------------------------------------
-- On retail, TSM does not hide the Blizzard auction window when you pick its
-- tab. It scales that window to 0.001 and draws its own frame over the top
-- (TradeSkillMaster/Core/UI/AuctionUI/Core.lua, private.TSMTabOnClick).
--
-- Auctionator PriceTracker parents its window to UIParent, so the shrink never
-- reaches it and it keeps drawing at full size across the TSM UI. Mirror the
-- scale change onto PriceTracker's own frames instead.

-- Fields on the AuctionatorPriceTracker global, in its own naming.
local WIDGETS = { "frame", "dayDetailFrame", "ahButton", "toggleButton" }

local wasShown = {}
local isHidden = false
local hooked = false

local function TSMViewActive()
    local ah = _G.AuctionHouseFrame
    if not ah or not C_AddOns.IsAddOnLoaded("TradeSkillMaster") then return false end
    -- TSM uses 0.001; anything under half size is the TSM view, not a UI scaler.
    return ah:GetScale() < 0.5
end

local function Apply()
    local apt = _G.AuctionatorPriceTracker
    if not apt then return end

    local active = TSMViewActive()
    if active == isHidden then return end
    isHidden = active

    for _, key in ipairs(WIDGETS) do
        local widget = apt[key]
        if widget then
            if active then
                -- Remember PriceTracker's own state so its close button and
                -- /apt toggle still win when we put things back.
                wasShown[key] = widget:IsShown()
                widget:Hide()
            elseif wasShown[key] then
                widget:Show()
            end
        end
    end
end

local function OnEvent(_, event)
    if event == "AUCTION_HOUSE_CLOSED" then
        isHidden = false
        wipe(wasShown)
        return
    end

    if _G.AuctionHouseFrame and not hooked then
        hooked = true
        -- Fires both ways: the TSM tab, and TSM's "switch to Blizzard UI" button.
        hooksecurefunc(_G.AuctionHouseFrame, "SetScale", function()
            C_Timer.After(0, Apply)
        end)
    end

    -- Next frame, so PriceTracker's own AUCTION_HOUSE_SHOW handler runs first.
    C_Timer.After(0, Apply)
end

function Mod.Init()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("AUCTION_HOUSE_SHOW")
    watcher:RegisterEvent("AUCTION_HOUSE_CLOSED")
    watcher:SetScript("OnEvent", OnEvent)
end

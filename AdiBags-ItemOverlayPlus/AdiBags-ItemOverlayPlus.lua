local _, ns = ...

local addon = LibStub('AceAddon-3.0'):GetAddon('AdiBags')
local L = addon.L

LibCompat = LibStub:GetLibrary("LibCompat-1.0")

local mod = addon:NewModule("ItemOverlayPlus", 'AceEvent-3.0')
mod.uiName = L['Item Overlay Plus']
mod.uiDesc = L["Adds a red overlay to items that are unusable for you."]

local tooltipName = "AdibagsItemOverlayPlusScanningTooltip"
local tooltipFrame = _G[tooltipName] or CreateFrame("GameTooltip", tooltipName, nil, "GameTooltipTemplate")

local unusableItemsCache = {} -- Cache for scanned items

function mod:OnInitialize()
    self.db = addon.db:RegisterNamespace(self.moduleName, {
        profile = {
            EnableOverlay = true,
        },
    })

    -- Register the ITEM_UNLOCKED and MERCHANT_UPDATE event handlers
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ITEM_LOCK_UPDATE")
    frame:RegisterEvent("BAG_UPDATE")
    frame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ITEM_LOCK_UPDATE" or event == "CURRENT_SPELL_CAST_CHANGED" or event == "BAG_UPDATE" then
            if _G["AdiBagsContainer1"] and AdiBagsContainer1:IsVisible() then
                -- print(event)
                self:SendMessage('AdiBags_UpdateAllButtons')
            end
        end
    end)

    local frame2 = CreateFrame("Frame")
    frame2:RegisterEvent("ITEM_UNLOCKED")
    frame2:RegisterEvent("ITEM_LOCKED")
    frame2:SetScript("OnEvent", function(_, event, bag, slot)
        if event == "ITEM_UNLOCKED" or event == "ITEM_LOCKED" then
            if _G["AdiBagsContainer1"] and bag~=nil and slot~=nil then
                --print(bag, slot)
                unusableItemsCache[bag .. "," .. slot] = nil
                self:SendMessage('AdiBags_UpdateAllButtons')
            end
        end
    end)
end


function mod:GetOptions()
    EnableOverlay = self.db.profile.EnableOverlay
    return {
        EnableOverlay = {
            name = L["Enable Overlay"],
            desc = L["Check this if you want overlay shown"],
            type = "toggle",
            width = "double",
            order = 10,
            get = function() return EnableOverlay end,
            set = function(_, value)
                EnableOverlay = value
                self.db.profile.EnableOverlay = value
                self:SendMessage('AdiBags_UpdateAllButtons')
            end,
        },
    }, addon:GetOptionHandler(self)
end





-- -- Register a message to check if the bag is open whenever the AdiBags_BagOpened or AdiBags_BagClosed messages are received
-- mod:RegisterMessage('AdiBags_BagOpened', emptyfornow)



function mod:OnEnable()

    EnableOverlay = true
    self:RegisterMessage('AdiBags_UpdateButton', 'UpdateButton')

    self:RegisterMessage('AdiBags_BagSwapPanelClosed', 'ItemPositionChanged')
    self:RegisterMessage('AdiBags_NewItemReset', 'ItemPositionChanged')
    -- self:RegisterMessage('AdiBags_TidyBagsButtonClick', 'ItemPositionChanged')

    self:RegisterMessage('AdiBags_TidyBags', 'TidyBagsUpdateRed')
end

function mod:TidyBagsUpdateRed()
    wipe(unusableItemsCache)
    self:SendMessage('AdiBags_UpdateAllButtons')
    -- print('Tidy Bags: Redoing button scanning due to filters changed')
end


function mod:ItemPositionChanged()
    wipe(unusableItemsCache)
    self:SendMessage('AdiBags_UpdateAllButtons')
    -- print('Button Position: Redoing button scanning due to filters changed')
end



function mod:OnDisable()
    EnableOverlay = false
end

function mod:UpdateButton(event, button)
    if not EnableOverlay then
        return
    end
    if not GetContainerItemID(button.bag, button.slot) then
        return
    end


    -- Check if the item is visible on the screen
    if not button:IsVisible() then
        return
    end


    -- Check if the item has already been scanned
    local key = button.bag .. "," .. button.slot
    local isUnusable = unusableItemsCache[key]
    if isUnusable ~= nil then
        if isUnusable then
            button.IconTexture:SetVertexColor(1, 0.1, 0.1)
        elseif not isUnusable then
            button.IconTexture:SetVertexColor(1, 1, 1)
        end
        return
    end
    -- Mark the item as scanned so it doesn't get scanned again
    unusableItemsCache[key] = false

    -- Use the After function to delay the scan by 0.03 seconds
    LibCompat.After(0.03 * (button.slot - 1), function()
        -- Scan the tooltip for red text
        local isUnusable = mod:ScanTooltipOfBagItemForRedText(button.bag, button.slot)
        -- do not remove this next commented code, it's needed for testing: when the full scan fires.
        -- print("Scanned bag slot", button.bag, button.slot)
        unusableItemsCache[key] = isUnusable

        -- Update the button texture
        if isUnusable then
            button.IconTexture:SetVertexColor(1, 0.1, 0.1)
        elseif not isUnusable then
            button.IconTexture:SetVertexColor(1, 1, 1)
        end
    end)
end


local function roundRGB(r, g, b)
    return floor(r * 100 + 0.5) / 100, floor(g * 100 + 0.5) / 100, floor(b * 100 + 0.5) / 100
end

local function isTextColorRed(textTable)
    if not textTable then
        return false
    end

    local text = textTable:GetText()
    if not text or text == "" or string.find(text, "0 / %d+") then
        return false
    end

    -- local r, g, b = roundRGB(textTable:GetTextColor())
    local r, g, b = textTable:GetTextColor()
    -- return r > 1 and g == 0.13 and b == 0.13
    return r > 0.98 and g < 0.15 and b < 0.15
end

function mod:ScanTooltipOfBagItemForRedText(bag, slot)
    --local tooltip = _G[tooltipName]
    tooltipFrame:ClearLines()
    tooltipFrame:SetBagItem(bag, slot)
    if bag < 0 then
        tooltipFrame:SetInventoryItem('player', slot+39)
    end
    for i=1, tooltipFrame:NumLines() do
        if isTextColorRed(_G[tooltipName .. "TextLeft" .. i]) or isTextColorRed(_G[tooltipName .. "TextRight" .. i]) then
            -- print("Red text found on line:", i, "in bag:", bag, "slot:", slot)
            return true
        end
    end

    return false
end

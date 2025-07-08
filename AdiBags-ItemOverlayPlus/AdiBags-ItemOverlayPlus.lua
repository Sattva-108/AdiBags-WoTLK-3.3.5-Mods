local _, ns = ...

local addon = LibStub('AceAddon-3.0'):GetAddon('AdiBags')
local L = addon.L

LibCompat = LibStub:GetLibrary("LibCompat-1.0")

local mod = addon:NewModule("ItemOverlayPlus", 'AceEvent-3.0')
mod.uiName = L['Item Overlay Plus']
mod.uiDesc = L["Adds a red overlay to items that are unusable for you."]

local tooltipName = "AdibagsItemOverlayPlusScanningTooltip"
local tooltipFrame = _G[tooltipName] or CreateFrame("GameTooltip", tooltipName, nil, "GameTooltipTemplate")

local openBagCount = 0

-- Debounce mechanism for frequent events
local updateAllScheduled = false
local function RequestFullUpdate()
    if not mod.db.profile.EnableOverlay then return end -- Don't schedule if disabled
    if openBagCount == 0 then return end -- Don't schedule if bags are closed

    if updateAllScheduled then
        -- print("[IOP DEBUG] Full update already scheduled, skipping.")
        return
    end
    updateAllScheduled = true
    -- print("[IOP DEBUG] Scheduling full update.")
    LibCompat.After(0, function() -- Debounce delay (0.25 seconds)
        if openBagCount > 0 and mod.db.profile.EnableOverlay then -- Re-check state before sending
            -- print("[IOP DEBUG] Executing debounced AdiBags_UpdateAllButtons.")
            mod:SendMessage('AdiBags_UpdateAllButtons')
        else
            -- print("[IOP DEBUG] Debounced update cancelled (bags closed or mod disabled).")
        end
        updateAllScheduled = false
    end)
end


function mod:OnInitialize()
    self.db = addon.db:RegisterNamespace(self.moduleName, {
        profile = {
            EnableOverlay = true,
        },
    })

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ITEM_LOCK_UPDATE")
    --frame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED") Re-enable this if specific items need update on cast change
    frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    frame:SetScript("OnEvent", function(_, event) -- Removed bag, slot as ITEM_LOCK_UPDATE doesn't reliably provide them here
        if openBagCount == 0 or not self.db.profile.EnableOverlay then return end

        if event == "ITEM_LOCK_UPDATE" then
            -- print("[IOP Event] ITEM_LOCK_UPDATE")
            RequestFullUpdate()
        elseif event == "BAG_UPDATE_COOLDOWN" then
            -- print("[IOP Event] BAG_UPDATE_COOLDOWN")
            RequestFullUpdate()
        elseif event == "CURRENT_SPELL_CAST_CHANGED" then
            -- print("[IOP Event] CURRENT_SPELL_CAST_CHANGED - Currently ignored for full rescan to save FPS.")
            -- RequestFullUpdate() -- Re-enable this if specific items need update on cast change AND performance is acceptable
            -- A more targeted update would be better here if possible.
        end
    end)

    local frame2 = CreateFrame("Frame")
    frame2:RegisterEvent("ITEM_UNLOCKED")
    frame2:RegisterEvent("ITEM_LOCKED")
    -- Event payload for ITEM_UNLOCKED/LOCKED can be (itemID, bagIndex, slotIndex) or just (itemID)
    -- We'll just trigger a debounced full update for simplicity without relying on potentially misinterpreted bag/slot.
    frame2:SetScript("OnEvent", function(_, event)
        if openBagCount == 0 or not self.db.profile.EnableOverlay then return end
        if event == "ITEM_UNLOCKED" or event == "ITEM_LOCKED" then
            -- print("[IOP Event]", event)
            RequestFullUpdate()
        end
    end)

    local levelFrame = CreateFrame("Frame")
    levelFrame:RegisterEvent("PLAYER_LEVEL_UP")
    levelFrame:SetScript("OnEvent", function()
        if openBagCount > 0 and self.db.profile.EnableOverlay then
            -- print("[IOP Event] PLAYER_LEVEL_UP")
            self:SendMessage('AdiBags_UpdateAllButtons') -- Level up is infrequent, direct update is fine
        end
    end)
end

function mod:GetOptions()
    return {
        EnableOverlay = {
            name = L["Enable Overlay"],
            desc = L["Check this if you want overlay shown"],
            type = "toggle",
            width = "double",
            order = 10,
            get = function() return self.db.profile.EnableOverlay end,
            set = function(_, value)
                self.db.profile.EnableOverlay = value
                -- print("[IOP Option] EnableOverlay set to:", value)
                if openBagCount > 0 then -- Only update if bags are open
                    self:SendMessage('AdiBags_UpdateAllButtons')
                end
            end,
        },
    }, addon:GetOptionHandler(self)
end

function mod:OnEnable()
    self:RegisterMessage('AdiBags_BagSwapPanelClosed', 'ItemPositionChanged')
    self:RegisterMessage('AdiBags_NewItemReset', 'ItemPositionChanged')
    self:RegisterMessage('AdiBags_TidyBags', 'TidyBagsUpdateRed')
    self:RegisterMessage('AdiBags_BagOpened',  'OnBagOpened')
    self:RegisterMessage('AdiBags_BagClosed', 'OnBagClosed')
    -- print("[IOP] Module Enabled.")

    -- If bags are already open when addon is enabled (e.g. /reload),
    -- and OnBagOpened hasn't fired yet for them in this session for this module,
    -- we might need to manually check AdiBags' state or wait for first OnBagOpened.
    -- For now, relying on OnBagOpened for initial setup.
end

function mod:OnDisable()
    self:UnregisterMessage('AdiBags_UpdateButton')
    self:UnregisterMessage('AdiBags_BagSwapPanelClosed')
    self:UnregisterMessage('AdiBags_NewItemReset')
    self:UnregisterMessage('AdiBags_TidyBags')
    self:UnregisterMessage('AdiBags_BagOpened')
    self:UnregisterMessage('AdiBags_BagClosed')
    -- print("[IOP] Module Disabled.")
    -- If overlay was active, force a clear of all buttons if possible.
    -- AdiBags might do this itself if a data source changes.
    -- Or, if bags are open, send one last UpdateAllButtons (knowing EnableOverlay is now false in options).
    if openBagCount > 0 and addon.db.profile[self.moduleName] and addon.db.profile[self.moduleName].EnableOverlay == false then
        -- This assumes the option has already been set to false by the toggle leading to disable.
        -- Or, if the module is disabled externally, this might not run as expected.
        -- print("[IOP OnDisable] Requesting final clear.")
        -- self:SendMessage('AdiBags_UpdateAllButtons') -- This could be problematic if module is tearing down.
    end
end

function mod:OnBagOpened()
    openBagCount = openBagCount + 1
    -- print(string.format("[IOP] OnBagOpened. Count: %d", openBagCount))
    if openBagCount == 1 then
        self:RegisterMessage('AdiBags_UpdateButton', 'UpdateButton')
        -- print("[IOP] AdiBags_UpdateButton message registered.")
    end

    if self.db.profile.EnableOverlay then
        LibCompat.After(0, function() -- Delay to allow AdiBags to draw
            if openBagCount > 0 and self.db.profile.EnableOverlay then -- Re-check, bag might have closed quickly
                -- print("[IOP OnBagOpened] Sending AdiBags_UpdateAllButtons.")
                self:SendMessage('AdiBags_UpdateAllButtons')
            end
        end)
    end
end

function mod:OnBagClosed()
    openBagCount = openBagCount - 1
    -- print(string.format("[IOP] OnBagClosed. Count: %d", openBagCount))
    if openBagCount == 0 then
        self:UnregisterMessage('AdiBags_UpdateButton')
        -- print("[IOP] AdiBags_UpdateButton message unregistered.")
        updateAllScheduled = false -- Cancel any pending debounced updates
    end
    if openBagCount < 0 then openBagCount = 0 end -- Safety
end

function mod:TidyBagsUpdateRed()
    if not self.db.profile.EnableOverlay or openBagCount == 0 then return end
    -- print("[IOP] TidyBagsUpdateRed: Sending AdiBags_UpdateAllButtons.")
    self:SendMessage('AdiBags_UpdateAllButtons')
end

function mod:ItemPositionChanged()
    if not self.db.profile.EnableOverlay or openBagCount == 0 then return end
    -- print("[IOP] ItemPositionChanged: Sending AdiBags_UpdateAllButtons.")
    self:SendMessage('AdiBags_UpdateAllButtons')
end

-- Simplified ApplyOverlay without __overlayState to test coloring issues
local function ApplyOverlay(button, isActuallyUnusable)
    if not button or not button.IconTexture then return end -- Safety

    -- Check module and db existence, useful during reloads or if mod is disabled while apply is pending
    if not mod or not mod.db or not mod.db.profile then
        button.IconTexture:SetVertexColor(1, 1, 1)
        return
    end

    local shouldBeRed = mod.db.profile.EnableOverlay and isActuallyUnusable

    -- Get current color to avoid redundant SetVertexColor if possible,
    -- though without __overlayState, this is less critical but still good practice.
    local r, g, b = button.IconTexture:GetVertexColor()

    if shouldBeRed then
        if r ~= 1 or g ~= 0.1 or b ~= 0.1 then -- Check exact target color
            button.IconTexture:SetVertexColor(1, 0.1, 0.1)
            -- print(string.format("[IOP ApplyOverlay] Set RED for bag %s, slot %s", tostring(button.bag), tostring(button.slot)))
        end
    else
        if r ~= 1 or g ~= 1 or b ~= 1 then -- Check exact target color (white)
            button.IconTexture:SetVertexColor(1, 1, 1)
            -- print(string.format("[IOP ApplyOverlay] Set WHITE for bag %s, slot %s", tostring(button.bag), tostring(button.slot)))
        end
    end
end

local function QuickPreCheck(itemID)
    local _, _, _, _, minLevel = GetItemInfo(itemID)
    if not minLevel or minLevel == 0 then return nil end -- Info not cached or no level requirement

    local playerLevel = UnitLevel("player")
    if minLevel > playerLevel then
        return true -- Is Unusable (due to level)
    end
    return false -- Is Usable (by level, or other checks needed)
end

function mod:UpdateButton(_, button)
    -- print(string.format("[IOP UpdateButton] Called for bag %s, slot %s", tostring(button.bag), tostring(button.slot)))

    local itemID = GetContainerItemID(button.bag, button.slot)
    if not itemID then
        ApplyOverlay(button, false) -- No item, so not "unusable"
        return
    end

    -- If overlay is disabled globally, ensure item is white
    if not self.db.profile.EnableOverlay then
        ApplyOverlay(button, false)
        return
    end

    local isUnusable
    local preCheckUnusable = QuickPreCheck(itemID)

    if preCheckUnusable == true then -- Explicitly unusable by level
        isUnusable = true
    elseif preCheckUnusable == false then -- Explicitly usable by level (or inconclusive, needing tooltip scan)
        isUnusable = self:ScanTooltipOfBagItemForRedText(button.bag, button.slot)
    else -- preCheckUnusable is nil (e.g. GetItemInfo not ready), must scan
        isUnusable = self:ScanTooltipOfBagItemForRedText(button.bag, button.slot)
    end

    ApplyOverlay(button, isUnusable)
end

local function isTextColorRed(textTable)
    if not textTable then return false end
    local text = textTable:GetText()
    if not text or text == "" or string.find(text, "^0 / %d+$") then return false end
    local r, g, b = textTable:GetTextColor()
    return r > 0.95 and g < 0.2 and b < 0.2 -- Standard red check
end

function mod:ScanTooltipOfBagItemForRedText(bag, slot)
    tooltipFrame:ClearLines()
    tooltipFrame:SetBagItem(bag, slot)
    -- Removed: if bag < 0 then tooltipFrame:SetInventoryItem('player', slot+39) end

    for i = 1, tooltipFrame:NumLines() do
        if isTextColorRed(_G[tooltipName .. "TextLeft" .. i]) or isTextColorRed(_G[tooltipName .. "TextRight" .. i]) then
            -- print(string.format("[IOP ScanTooltip] Red text found for bag %s, slot %s", tostring(bag), tostring(slot)))
            return true -- Unusable
        end
    end
    -- print(string.format("[IOP ScanTooltip] No red text for bag %s, slot %s", tostring(bag), tostring(slot)))
    return false -- Usable
end
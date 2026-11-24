local addonName, ns = ...

-- The shopping list: the writs you ticked in the table, and what each one
-- needs (the writ itself and its requested items). At the Auction House it
-- sits beside the AH window: "Search all" sends one exact search for every
-- line still missing, and each line ticks itself off as you buy. Bought
-- items go to the mailbox on Forever, so a purchase counts at once (from the
-- server's "You won an auction" message, see Learn.lua) and stays counted
-- until it reaches your bags.

local WIDTH = 300
local LINE_HEIGHT = 16
local MAX_LINES = 24
local TOP = -30

local panel, lines, emptyText, moreText, searchButton, clearButton
local dismissed = false -- closed by hand: stays closed until opened again

-- Lines: { name, need, have, mail, entry, isWrit }, grouped per writ (the
-- writ, then its item). An item two writs ask for is one line.
function ns.ShoppingLines()
    local result, byName = {}, {}
    local function Add(name, need, entry, isWrit)
        local line = byName[name]
        if line then
            line.need = line.need + need
            return
        end
        line = { name = name, need = need, entry = entry, isWrit = isWrit }
        byName[name] = line
        result[#result + 1] = line
    end
    for _, entry in ipairs(ns.ListEntries()) do
        Add(ns.WritName(entry), 1, entry, true)
        Add(entry.item, ns.Count(entry) or 1, entry, false)
    end
    for _, line in ipairs(result) do
        line.mail = ns.OnWay(line.name)
        -- An accepted writ stays in the bags, so it already counts; noted in the tooltip.
        line.accepted = line.isWrit and ns.activeWrits[line.entry.item] == true
        line.have = (ns.owned[line.name] or 0) + line.mail
    end
    return result
end

local function Missing()
    local names = {}
    for _, line in ipairs(ns.ShoppingLines()) do
        if line.have < line.need then names[#names + 1] = line.name end
    end
    return names
end

-- Placement --------------------------------------------------------------------

local function AHWindow()
    local ah = _G.AuctionHouseFrame or _G.AuctionFrame
    if ah and ah:IsShown() then return ah end
end

local function Place()
    panel:ClearAllPoints()
    local ah = AHWindow()
    local main = _G.WritsLedgerFrame
    if ns.ahOpen and ah then
        panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
    elseif main and main:IsShown() then
        panel:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    end
end

-- Drawing ------------------------------------------------------------------------

local function LineTooltip(button)
    local line = button.line
    if not line then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(line.name, 1, 1, 1)
    GameTooltip:AddLine(("Needed: %d. In your bags: %d."):format(line.need, ns.owned[line.name] or 0), 0.8, 0.8, 0.8)
    if line.accepted then
        GameTooltip:AddLine("Accepted: this writ is in your quest log.", 0.4, 1, 0.4)
    end
    if line.mail > 0 then
        GameTooltip:AddLine(("Bought and on its way by mail: %d."):format(line.mail), 0.4, 0.8, 1, true)
    end
    GameTooltip:AddLine("Click: search for it on the Auction House.", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: take this writ off the list.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateLine(index)
    local button = CreateFrame("Button", nil, panel)
    button:SetSize(WIDTH - 20, LINE_HEIGHT)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, TOP - (index - 1) * LINE_HEIGHT)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.12)
    button.check = button:CreateTexture(nil, "ARTWORK")
    button.check:SetSize(14, 14)
    button.check:SetPoint("LEFT", 0, 0)
    button.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", 18, 0)
    button.label:SetWidth(WIDTH - 110)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)
    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.count:SetPoint("RIGHT", -2, 0)
    button.count:SetJustifyH("RIGHT")
    button:SetScript("OnClick", function(self, mouseButton)
        local line = self.line
        if not line then return end
        if mouseButton == "RightButton" then
            ns.SetInList(line.entry.item, false)
        else
            ns.Buy({ line.name })
        end
    end)
    button:SetScript("OnEnter", LineTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function Draw()
    local all = ns.ShoppingLines()
    local shown = math.min(#all, MAX_LINES)
    for index = 1, math.max(shown, #lines) do
        local button = lines[index]
        local line = all[index]
        if index <= shown then
            if not button then
                button = CreateLine(index)
                lines[index] = button
            end
            button.line = line
            local done = line.have >= line.need
            button.check:SetShown(done)
            if line.isWrit then
                local r, g, b = unpack(ns.TierColor(ns.Tier(line.entry)))
                local dim = done and 0.55 or 1
                button.label:SetText(line.entry.item .. " |cff808080(writ)|r")
                button.label:SetTextColor(r * dim, g * dim, b * dim)
            else
                button.label:SetText("    " .. line.name)
                local grey = done and 0.55 or 1
                button.label:SetTextColor(grey, grey, grey)
            end
            local have = math.min(line.have, line.need)
            local mail = line.mail > 0 and (" |cff66ccff(%d mail)|r"):format(line.mail) or ""
            local colour = done and "|cff20ff20" or "|cffffffff"
            button.count:SetText(("%s%s%d/%d|r"):format(mail, colour, have, line.need))
            button:Show()
        elseif button then
            button.line = nil
            button:Hide()
        end
    end

    emptyText:SetShown(#all == 0)
    moreText:SetShown(#all > MAX_LINES)
    if #all > MAX_LINES then moreText:SetText(("+%d more"):format(#all - MAX_LINES)) end

    local missing = #Missing()
    searchButton:SetText(missing > 0 and ("Search all (%d)"):format(missing) or "Search all")
    searchButton:SetEnabled(ns.ahOpen and missing > 0 and not ns.AuctionatorScanning())
    clearButton:SetEnabled(#all > 0)

    local rowsHeight = math.max(1, shown + (#all > MAX_LINES and 1 or 0)) * LINE_HEIGHT
    panel:SetHeight(-TOP + rowsHeight + 40)
end

-- Construction -------------------------------------------------------------------

local function CreatePanel()
    panel = CreateFrame("Frame", "WritsLedgerShoppingFrame", UIParent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.95)
    panel:SetWidth(WIDTH)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    lines = {}

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Writs shopping list")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        dismissed = true
        panel:Hide()
    end)

    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", 12, TOP - 2)
    emptyText:SetWidth(WIDTH - 24)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText("Empty. Tick the box at the start of a row in the writ table to add a writ.")

    moreText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    moreText:SetPoint("TOPLEFT", 28, TOP - MAX_LINES * LINE_HEIGHT - 2)

    searchButton = ns.CreateButton(panel, "Search all", 120, function()
        local names = Missing()
        if #names > 0 then ns.Buy(names) end
    end)
    searchButton:SetPoint("BOTTOMLEFT", 10, 10)
    searchButton:SetMotionScriptsWhileDisabled(true)
    ns.SetSimpleTooltip(searchButton, "Search all",
        "One exact search in Auctionator's Shopping tab for every line still missing. "
        .. "Click each listing there to buy it; the lines tick off as you buy.")

    clearButton = ns.CreateButton(panel, "Clear", 70, function() ns.ClearList() end)
    clearButton:SetPoint("BOTTOMRIGHT", -10, 10)
    ns.SetSimpleTooltip(clearButton, "Clear", "Empties the list.")
end

-- Shows the panel when it has something to show: at the Auction House, or
-- beside the writ table. Hidden by hand, it waits for the button again.
local function Wanted()
    if dismissed then return false end
    if #ns.ListEntries() == 0 then return false end
    return ns.ahOpen or ns.WindowShown()
end

function ns.RefreshShoppingList()
    if not panel then
        if not Wanted() then return end
        CreatePanel()
    end
    if not (ns.ahOpen or ns.WindowShown()) then
        panel:Hide()
    elseif Wanted() then
        Place()
        Draw()
        panel:Show()
    elseif panel:IsShown() then
        Place()
        Draw() -- opened by hand with an empty list
    end
end

function ns.ToggleShoppingList()
    if not panel then CreatePanel() end
    if panel:IsShown() then
        dismissed = true
        panel:Hide()
    else
        dismissed = false
        Place()
        Draw()
        panel:Show()
    end
end

-- Called when a writ goes on or off the list.
function ns.ShoppingListChanged(added)
    if added then dismissed = false end
    ns.RefreshWindow()
end

-- Opening or closing the Auction House moves the panel there and back.
local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
    -- A frame later: after Learn.lua has set ns.ahOpen and the AH window is laid out.
    C_Timer.After(0, function() ns.RefreshShoppingList() end)
end)

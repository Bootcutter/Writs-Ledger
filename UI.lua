local addonName, ns = ...

-- The writ table window. One row per writ:
--   [list] Writ (tier colour) | Profession | Count | Have | Turn-in | Writ price [Buy] | Item price [Buy] | Total [Both]
-- Prices come from Auctionator's saved prices, so the window works anywhere;
-- Buy and Scan need the Auction House open.

local ROW_HEIGHT = 20
local VISIBLE_ROWS = 20
local WIDTH = 1024 -- room for the scroll bar right of the Both buttons
local HEADER_Y = -88

-- Column layout: key, title, x, width, justify, sort key.
local COLUMNS = {
    { key = "name",   title = "Writ (requested item)", x = 30,  width = 212, justify = "LEFT",  sort = "name" },
    { key = "prof",   title = "Profession",             x = 246, width = 100, justify = "LEFT",  sort = "profession" },
    { key = "count",  title = "Count",                  x = 348, width = 40,  justify = "CENTER" },
    { key = "have",   title = "Have",                   x = 390, width = 56,  justify = "CENTER", sort = "have" },
    { key = "turnIn", title = "Turn-in",                x = 450, width = 190, justify = "LEFT",  sort = "turnIn" },
    { key = "writ",   title = "Writ",                   x = 644, width = 72,  justify = "RIGHT", sort = "writ" },
    { key = "item",   title = "Item",                   x = 760, width = 72,  justify = "RIGHT", sort = "item" },
    { key = "total",  title = "Total",                  x = 876, width = 66,  justify = "RIGHT", sort = "total" },
}
local BUY_WRIT_X, BUY_ITEM_X, BUY_BOTH_X = 718, 834, 944

local state = {
    sort = "tier",
    ascending = true,
    tiers = { Apprentice = true, Journeyman = true, Expert = true, Artisan = true, Unknown = true },
    profession = nil, -- nil = all
    zones = nil,      -- nil = all; else set of zone names ("Unknown" = turn-in not learned yet)
    ownedOnly = false,
    text = "",
    offset = 0,
}

local frame, rows, list, scrollBar, statusText, scanButton, lastScanText, professionButton, zoneButton, zonePopup, tierButtons
local listButton
local ahButton

function ns.WindowShown()
    return frame ~= nil and frame:IsShown()
end

-- Data -------------------------------------------------------------------------

local function Professions()
    local seen, result = {}, {}
    for _, entry in ipairs(ns.writs) do
        for _, profession in ipairs(ns.Professions(entry)) do
            if not seen[profession] then
                seen[profession] = true
                result[#result + 1] = profession
            end
        end
    end
    table.sort(result)
    return result
end

-- Zone of a writ's turn-in, or "Unknown" when it is not learned yet.
local function ZoneKey(entry)
    local turnIn = ns.TurnIn(entry)
    return turnIn and ns.ZoneName(turnIn) or "Unknown"
end

-- Turn-in zones grouped by continent, for the zone dropdown:
-- { { name = continent, zones = { { name = zone, count = writs }, ... } }, ... }
-- Kalimdor first, then Eastern Kingdoms, with a "Not learned yet" group
-- (zone "Unknown") last.
local function ZoneGroups()
    local groups, byName, counts = {}, {}, {}
    for _, entry in ipairs(ns.writs) do
        local zone = ZoneKey(entry)
        if not counts[zone] then
            counts[zone] = 0
            local continent = zone == "Unknown" and "~" or (ns.Continent(entry) or "Other")
            local group = byName[continent]
            if not group then
                group = { name = continent, zones = {} }
                byName[continent] = group
                groups[#groups + 1] = group
            end
            group.zones[#group.zones + 1] = { name = zone }
        end
        counts[zone] = counts[zone] + 1
    end
    -- Map order, west to east: Kalimdor, then Eastern Kingdoms, then any other
    -- continent by name, and "Not learned yet" ("~") last.
    local rank = {}
    for i, mapID in ipairs({ 1414, 1415 }) do -- Kalimdor, Eastern Kingdoms
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then rank[info.name] = i end
    end
    local function Rank(name) return name == "~" and 99 or rank[name] or 50 end
    table.sort(groups, function(a, b)
        local ra, rb = Rank(a.name), Rank(b.name)
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    for _, group in ipairs(groups) do
        if group.name == "~" then group.name = "Not learned yet" end
        table.sort(group.zones, function(a, b) return a.name < b.name end)
        for _, zone in ipairs(group.zones) do zone.count = counts[zone.name] end
    end
    return groups
end

local function OwnedCounts(entry)
    return ns.owned[ns.WritName(entry)] or 0, ns.owned[entry.item] or 0
end

local function Matches(entry)
    local tier = ns.Tier(entry) or "Unknown"
    if not state.tiers[tier] then return false end
    if state.profession then
        local found = false
        for _, profession in ipairs(ns.Professions(entry)) do
            if profession == state.profession then found = true end
        end
        if not found then return false end
    end
    if state.zones and not state.zones[ZoneKey(entry)] then return false end
    if state.ownedOnly then
        local writs, items = OwnedCounts(entry)
        if writs == 0 and items == 0 then return false end
    end
    if state.text ~= "" and not entry.item:lower():find(state.text, 1, true) then return false end
    return true
end

local function SortValue(entry, key)
    if key == "name" then return entry.item:lower() end
    if key == "profession" then return (ns.Profession(entry) or "~"):lower() end
    if key == "tier" then return ns.TIER_ORDER[ns.Tier(entry) or ""] or 99 end
    if key == "have" then
        local writs, items = OwnedCounts(entry)
        return -(writs * 1000 + items)
    end
    if key == "turnIn" then
        local turnIn = ns.TurnIn(entry)
        return turnIn and ns.ZoneName(turnIn):lower() or "~"
    end
    local writPrice, itemPrice, total = ns.Prices(entry)
    if key == "writ" then return writPrice end
    if key == "item" then return itemPrice end
    if key == "total" then return total end
end

local function BuildList()
    list = {}
    for _, entry in ipairs(ns.writs) do
        if Matches(entry) then list[#list + 1] = entry end
    end
    local key, ascending = state.sort, state.ascending
    local values = {}
    for _, entry in ipairs(list) do values[entry] = SortValue(entry, key) end
    table.sort(list, function(a, b)
        local va, vb = values[a], values[b]
        if va == vb then
            -- Ties: by tier, then name.
            local ta = ns.TIER_ORDER[ns.Tier(a) or ""] or 99
            local tb = ns.TIER_ORDER[ns.Tier(b) or ""] or 99
            if ta ~= tb then return ta < tb end
            return a.item < b.item
        end
        -- Unknown values (no price yet) always last.
        if va == nil then return false end
        if vb == nil then return true end
        if ascending then return va < vb end
        return va > vb
    end)
    local maxOffset = math.max(0, #list - VISIBLE_ROWS)
    state.offset = math.min(state.offset, maxOffset)
end

-- Drawing ----------------------------------------------------------------------

local function AgeText(age)
    if not age or age < 1 then return "" end
    return (" |cff808080%dd|r"):format(age)
end

local function PriceText(price, age)
    local text = ns.FormatMoney(price)
    if price and age and age >= 1 then
        -- Prices not from today's scan are greyed out (writ prices swing daily).
        text = "|cff9a9a9a" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
    end
    return text
end

local function DrawRow(row, entry)
    row.entry = entry
    if not entry then
        row:Hide()
        return
    end
    local tier = ns.Tier(entry)
    local r, g, b = unpack(ns.TierColor(tier))
    local done = ns.DoneToday(entry)
    local dim = done and 0.5 or 1 -- done today: name dimmed, check in Have
    row.cells.name:SetText(entry.item)
    row.cells.name:SetTextColor(r * dim, g * dim, b * dim)
    row.cells.prof:SetText(ns.Profession(entry) or "|cff808080?|r")

    local count, known = ns.Count(entry)
    row.cells.count:SetText(known and ("x" .. count) or "|cff808080x1?|r")

    local writs, items = OwnedCounts(entry)
    local have = {}
    if done then have[#have + 1] = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t" end
    if writs > 0 then have[#have + 1] = "|cffffd100W|r" end
    if items > 0 then have[#have + 1] = "|cff20ff20" .. items .. "|r" end
    row.cells.have:SetText(#have > 0 and table.concat(have, " ") or "")

    local turnIn, source = ns.TurnIn(entry)
    if turnIn then
        -- Confirmed in your own quest log: white; from the baseline data: pale.
        local colour = source == "confirmed" and "|cffffffff" or "|cffd8d0b0"
        row.cells.turnIn:SetText(("%s%s|r |cffb0b0b0%.0f, %.0f|r"):format(colour, ns.ZoneName(turnIn), turnIn.x * 100, turnIn.y * 100))
    else
        row.cells.turnIn:SetText("|cff808080accept once to learn|r")
    end

    local writPrice, itemPrice, total, writAge, itemAge = ns.Prices(entry)
    row.cells.writ:SetText(PriceText(writPrice, writAge) .. AgeText(writAge))
    row.cells.item:SetText(PriceText(itemPrice, itemAge) .. AgeText(itemAge))
    -- The total is only as fresh as its older part.
    row.cells.total:SetText(PriceText(total, total and math.max(writAge or 0, itemAge or 0) or nil))

    local canBuy = ns.ahOpen and not ns.AuctionatorScanning()
    for _, button in ipairs(row.buy) do button:SetEnabled(canBuy) end
    row.listCheck:SetChecked(ns.InList(entry.item))
    row:Show()
end

-- Defined before DrawRows, which calls it (a local is only visible below it).
local function LastScanText()
    local progress = ns.ScanProgress()
    if progress then
        return ("|cffffd100Auctionator scanning... %d%%|r"):format(math.floor(progress * 100 + 0.5))
    end
    local text
    local last = ns.LastScan()
    if not last then
        text = "Last scan: never"
    else
        local seconds = math.max(0, time() - last)
        if seconds < 60 then text = "Last scan: just now"
        elseif seconds < 3600 then text = ("Last scan: %d min ago"):format(seconds / 60)
        elseif seconds < 86400 then text = ("Last scan: %d h ago"):format(seconds / 3600)
        else text = ("Last scan: %d days ago"):format(seconds / 86400) end
    end
    -- Most prices older than today: say so (writ prices swing from day to day).
    local age = ns.TypicalPriceAge()
    if age and age >= 1 then
        text = ("|cffffd100Prices are %d day%s old: scan again.|r  %s"):format(age, age == 1 and "" or "s", text)
    end
    return text
end

local function ResetText()
    local seconds = ns.SecondsUntilReset()
    if not seconds then return "" end
    return ("  Daily reset in %s."):format(ns.FormatDuration(seconds))
end
ns.ResetText = ResetText

local function DrawRows()
    if not frame then return end
    for index, row in ipairs(rows) do
        DrawRow(row, list[state.offset + index])
    end
    local maxOffset = math.max(0, #list - VISIBLE_ROWS)
    scrollBar:SetMinMaxValues(0, maxOffset)
    scrollBar:SetValue(state.offset)
    scrollBar:SetShown(maxOffset > 0)

    local priced = 0
    for _, entry in ipairs(list) do
        local _, _, total = ns.Prices(entry)
        if total then priced = priced + 1 end
    end
    local where = ""
    if not ns.ahOpen then
        where = "  |cffff8080Open the Auction House to buy or scan.|r"
    elseif ns.AuctionatorScanning() then
        where = "  |cffffd100Buy is paused until Auctionator's scan finishes.|r"
    end
    statusText:SetText(("%d writs shown, %d with full prices.%s%s"):format(#list, priced, ResetText(), where))
    scanButton:SetEnabled(ns.ahOpen and not ns.AuctionatorScanning())
    lastScanText:SetText(LastScanText())
    listButton:SetText(("Shopping list (%d)"):format(#ns.ListEntries()))
end

local function RefreshTierButtons()
    for tier, button in pairs(tierButtons) do
        local r, g, b = unpack(ns.TierColor(tier ~= "Unknown" and tier or nil))
        local on = state.tiers[tier]
        button.label:SetTextColor(on and r or r * 0.35, on and g or g * 0.35, on and b or b * 0.35)
        button.check:SetShown(on)
    end
    professionButton:SetText("Profession: " .. (state.profession or "All"))
    local label = "All"
    if state.zones then
        local picked, count = nil, 0
        for zone in pairs(state.zones) do picked, count = zone, count + 1 end
        label = count == 0 and "None" or count == 1 and picked or (count .. " selected")
    end
    zoneButton:SetText("Zones: " .. label)
end

-- Only the scan text at the top (cheap; called on every scan progress step).
function ns.RefreshScanStatus()
    if ns.WindowShown() and lastScanText then lastScanText:SetText(LastScanText()) end
end

function ns.RefreshWindow()
    if ns.RefreshShoppingList then ns.RefreshShoppingList() end
    if not ns.WindowShown() then return end
    BuildList()
    DrawRows()
end

-- Row tooltip ----------------------------------------------------------------------

local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local tier = ns.Tier(entry)
    local r, g, b = unpack(ns.TierColor(tier))
    GameTooltip:SetText(ns.WritName(entry), r, g, b)
    local rep = ns.TIER_REP[tier or ""]
    GameTooltip:AddLine((tier and (tier .. " writ") or "Unknown tier") .. " - " .. (ns.Profession(entry) or "unknown profession"), 1, 1, 1)
    if rep then GameTooltip:AddLine(("%d reputation per turn-in"):format(rep), r, g, b) end
    local count, known = ns.Count(entry)
    GameTooltip:AddLine(known and ("Requests %d %s"):format(count, entry.item)
        or ("Requests %s (count not seen yet; right-click the writ to learn it)"):format(entry.item), 1, 1, 1, true)
    if ns.DoneToday(entry) then
        local seconds = ns.SecondsUntilReset()
        GameTooltip:AddLine("Already done today." .. (seconds and (" Daily reset in " .. ns.FormatDuration(seconds) .. ".") or ""),
            0.6, 0.6, 0.6)
    end
    if ns.InList(entry.item) then
        GameTooltip:AddLine("On your shopping list.", 0.4, 0.8, 1)
    end
    local turnIn, source = ns.TurnIn(entry)
    if turnIn then
        local continent = ns.Continent(entry)
        -- A confirmed point has no NPC name; the data's name still applies.
        local npc = turnIn.npc or (entry.turnIn and entry.turnIn.npc) or "the map marker"
        GameTooltip:AddLine(("Turn-in: %s, %s %.1f, %.1f"):format(npc, ns.ZoneName(turnIn),
            turnIn.x * 100, turnIn.y * 100), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(("%s%s. Click the row to pin it on the map."):format(
            continent and (continent .. ". ") or "",
            source == "confirmed" and "Confirmed from your quest log" or "From the addon's data, not confirmed by you yet"),
            0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine("Turn-in: not known yet. Accept this writ once and it is learned.", 0.6, 0.6, 0.6, true)
    end
    local writPrice, itemPrice, _, writAge, itemAge = ns.Prices(entry)
    local function AgeLine(age)
        if not age then return "" end
        if age < 1 then return " (today)" end
        return (" (%d day%s old)"):format(age, age == 1 and "" or "s")
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Writ", ns.FormatMoney(writPrice) .. AgeLine(writAge), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Item" .. (known and count > 1 and (" x" .. count) or ""),
        ns.FormatMoney(itemPrice) .. AgeLine(itemAge), 1, 1, 1, 1, 1, 1)
    if not ns.ItemID(ns.WritName(entry)) or not ns.ItemID(entry.item) then
        GameTooltip:AddLine("Missing prices fill in after the item has been seen once (Scan, or in your bags).", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

-- Construction -----------------------------------------------------------------------

local function CreateButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function SetSimpleTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
ns.CreateButton, ns.SetSimpleTooltip = CreateButton, SetSimpleTooltip

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 40, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, HEADER_Y - 18 - (index - 1) * ROW_HEIGHT)
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.12)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        local owner = row
        if column.key == "turnIn" then
            -- The turn-in is a link: click opens the map with a waypoint there.
            owner = CreateFrame("Button", nil, row)
            owner:SetSize(column.width, ROW_HEIGHT)
            owner:SetPoint("LEFT", row, "LEFT", column.x - 8, 0)
            local linkHighlight = owner:CreateTexture(nil, "HIGHLIGHT")
            linkHighlight:SetPoint("BOTTOMLEFT", 0, 2)
            linkHighlight:SetPoint("BOTTOMRIGHT", 0, 2)
            linkHighlight:SetHeight(1)
            linkHighlight:SetColorTexture(1, 0.82, 0, 0.8)
            owner:SetScript("OnClick", function()
                if row.entry then ns.ShowTurnInOnMap(row.entry) end
            end)
            owner:SetScript("OnEnter", function(self)
                local entry = row.entry
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                if entry and ns.TurnIn(entry) then
                    GameTooltip:SetText("Show on map")
                    if not ns.OpenMapOnClick() then
                        GameTooltip:AddLine("Sets a waypoint on the turn-in (\"Open map on turn-in click\" is off).", 1, 1, 1, true)
                    elseif ns.ahOpen then
                        GameTooltip:AddLine("Opens the world map with a waypoint on the turn-in. This closes the Auction House.", 1, 1, 1, true)
                    else
                        GameTooltip:AddLine("Opens the world map with a waypoint on the turn-in.", 1, 1, 1, true)
                    end
                else
                    GameTooltip:SetText("Turn-in not known yet")
                    GameTooltip:AddLine("Accept this writ once and its turn-in is learned.", 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.turnInButton = owner
        end
        local text = owner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if owner == row then
            text:SetPoint("LEFT", row, "LEFT", column.x - 8, 0)
        else
            text:SetPoint("LEFT", owner, "LEFT", 0, 0)
        end
        text:SetWidth(column.width)
        text:SetJustifyH(column.justify)
        text:SetWordWrap(false)
        row.cells[column.key] = text
    end

    -- Shopping list box, left of the name.
    local listCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    listCheck:SetSize(18, 18)
    listCheck:SetPoint("LEFT", row, "LEFT", 2, 0)
    listCheck:SetScript("OnClick", function(self)
        if row.entry then ns.SetInList(row.entry.item, self:GetChecked()) end -- redraws
    end)
    SetSimpleTooltip(listCheck, "Shopping list",
        "Adds this writ and its requested item to your shopping list. At the Auction House the list "
        .. "searches for everything at once and ticks items off as you buy them.")
    row.listCheck = listCheck

    row.buy = {}
    local function BuyButton(x, label, names)
        local button = CreateButton(row, label, label == "Both" and 46 or 40, function()
            if row.entry then ns.Buy(names(row.entry)) end
        end)
        button:SetHeight(18)
        button:SetPoint("LEFT", row, "LEFT", x - 8, 0)
        row.buy[#row.buy + 1] = button
        return button
    end
    SetSimpleTooltip(BuyButton(BUY_WRIT_X, "Buy", function(entry) return { ns.WritName(entry) } end),
        "Buy the writ", "Searches Auctionator's Shopping tab for this writ. Pick a listing there to buy it.")
    SetSimpleTooltip(BuyButton(BUY_ITEM_X, "Buy", function(entry) return { entry.item } end),
        "Buy the requested item", "Searches Auctionator's Shopping tab for the item this writ asks for.")
    SetSimpleTooltip(BuyButton(BUY_BOTH_X, "Both", function(entry) return { ns.WritName(entry), entry.item } end),
        "Buy writ and item", "Searches for both, so they are listed together in Auctionator's Shopping tab.")

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        local entry = self.entry
        if not entry then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") then
            local id = ns.ItemID(ns.WritName(entry))
            local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local link = id and getInfo and select(2, getInfo(id))
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
            return
        end
        ns.PinTurnIn(entry)
    end)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Scroll(delta)
    local maxOffset = math.max(0, #list - VISIBLE_ROWS)
    state.offset = math.max(0, math.min(maxOffset, state.offset - delta * 3))
    DrawRows()
end

-- Zone dropdown ------------------------------------------------------------------
-- A checkbox per turn-in zone, one column per continent (like the dungeon
-- finder's list). A continent's own checkbox toggles all its zones.

local ZONE_COLUMN_WIDTH, ZONE_ROW_HEIGHT = 190, 18

local function ZoneOn(zone)
    return not state.zones or state.zones[zone] == true
end

-- Sets zones on/off; collapses back to nil ("All") when everything is on.
local function SetZones(names, on)
    local groups = ZoneGroups()
    if not state.zones then
        state.zones = {}
        for _, group in ipairs(groups) do
            for _, zone in ipairs(group.zones) do state.zones[zone.name] = true end
        end
    end
    for _, name in ipairs(names) do state.zones[name] = on or nil end
    local all = true
    for _, group in ipairs(groups) do
        for _, zone in ipairs(group.zones) do
            if not state.zones[zone.name] then all = false end
        end
    end
    if all then state.zones = nil end
    state.offset = 0
    RefreshTierButtons()
    ns.RefreshWindow()
end

local function ZoneCheck(index)
    zonePopup.checks = zonePopup.checks or {}
    local check = zonePopup.checks[index]
    if not check then
        check = CreateFrame("CheckButton", nil, zonePopup, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        check.label:SetPoint("LEFT", check, "RIGHT", 1, 0)
        check.label:SetJustifyH("LEFT")
        check:SetHitRectInsets(0, -(ZONE_COLUMN_WIDTH - 40), 0, 0) -- the label clicks too
        zonePopup.checks[index] = check
    end
    return check
end

local function DrawZonePopup()
    for _, check in ipairs(zonePopup.checks or {}) do check:Hide() end
    local index, maxRows = 0, 0
    for column, group in ipairs(ZoneGroups()) do
        local x = 12 + (column - 1) * ZONE_COLUMN_WIDTH
        local names, allOn = {}, true
        for _, zone in ipairs(group.zones) do
            names[#names + 1] = zone.name
            if not ZoneOn(zone.name) then allOn = false end
        end

        index = index + 1
        local header = ZoneCheck(index)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", zonePopup, "TOPLEFT", x, -34)
        header.label:SetFontObject("GameFontNormal")
        header.label:SetText(group.name)
        header:SetChecked(allOn)
        header:SetScript("OnClick", function(self)
            SetZones(names, self:GetChecked())
            DrawZonePopup()
        end)
        header:Show()

        for row, zone in ipairs(group.zones) do
            index = index + 1
            local check = ZoneCheck(index)
            check:ClearAllPoints()
            check:SetPoint("TOPLEFT", zonePopup, "TOPLEFT", x + 14, -34 - row * ZONE_ROW_HEIGHT)
            check.label:SetFontObject("GameFontHighlightSmall")
            check.label:SetText(("%s |cff808080(%d)|r"):format(zone.name, zone.count))
            check:SetChecked(ZoneOn(zone.name))
            check:SetScript("OnClick", function(self)
                SetZones({ zone.name }, self:GetChecked())
                DrawZonePopup()
            end)
            check:Show()
        end
        maxRows = math.max(maxRows, #group.zones)
        zonePopup:SetWidth(math.max(260, 24 + column * ZONE_COLUMN_WIDTH))
    end
    zonePopup:SetHeight(48 + (maxRows + 1) * ZONE_ROW_HEIGHT)
end

local function CreateZonePopup()
    zonePopup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    zonePopup:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    zonePopup:SetBackdropColor(0, 0, 0, 0.95)
    zonePopup:SetPoint("TOPLEFT", zoneButton, "BOTTOMLEFT", 0, -2)
    zonePopup:SetFrameLevel(frame:GetFrameLevel() + 20)
    zonePopup:EnableMouse(true) -- clicks do not fall through to the rows
    zonePopup:Hide()

    local all = CreateButton(zonePopup, "All", 60, function()
        state.zones = nil
        SetZones({}, true)
        DrawZonePopup()
    end)
    all:SetPoint("TOPLEFT", 10, -8)
    local none = CreateButton(zonePopup, "None", 60, function()
        local names = {}
        for _, group in ipairs(ZoneGroups()) do
            for _, zone in ipairs(group.zones) do names[#names + 1] = zone.name end
        end
        SetZones(names, false)
        DrawZonePopup()
    end)
    none:SetPoint("LEFT", all, "RIGHT", 4, 0)
    local close = CreateButton(zonePopup, "Close", 60, function() zonePopup:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -8)
end

local function ToggleZonePopup()
    if not zonePopup then CreateZonePopup() end
    if zonePopup:IsShown() then
        zonePopup:Hide()
    else
        DrawZonePopup()
        zonePopup:Show()
    end
end

local function CreateWindow()
    local ok, created = pcall(CreateFrame, "Frame", "WritsLedgerFrame", UIParent, "BasicFrameTemplateWithInset")
    if ok and created then
        frame = created
    else
        frame = CreateFrame("Frame", "WritsLedgerFrame", UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    -- One even, near-black background: the template's tiled grey background
    -- and its inner inset frame are replaced.
    if frame.Bg and frame.Bg.SetColorTexture then pcall(frame.Bg.SetColorTexture, frame.Bg, 0, 0, 0, 0.95) end
    if frame.Inset then pcall(frame.Inset.Hide, frame.Inset) end
    if frame.InsetBg then pcall(frame.InsetBg.Hide, frame.InsetBg) end
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    background:SetPoint("TOPLEFT", 2, -2)
    background:SetPoint("BOTTOMRIGHT", -2, 2)
    background:SetColorTexture(0, 0, 0, 0.95)
    frame:SetSize(WIDTH, -HEADER_Y + 18 + VISIBLE_ROWS * ROW_HEIGHT + 34)
    frame:SetScale(ns.WindowScale())
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "WritsLedgerFrame") -- Escape closes it

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText("Craftsman's Writs")

    -- Filter bar ---------------------------------------------------------------
    local x = 14
    tierButtons = {}
    -- The tier boxes double as the colour legend: a writ's name colour is its
    -- tier, and the tier sets the reputation it gives.
    local tierLegend = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tierLegend:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -36)
    tierLegend:SetText("Writ tier (rep per turn-in):")
    x = x + tierLegend:GetStringWidth() + 8
    -- No Apprentice or Unknown box: no writ has those tiers, so they filtered
    -- nothing. Such writs still show (state.tiers keeps them on).
    for _, tier in ipairs({ "Journeyman", "Expert", "Artisan" }) do
        local button = CreateFrame("Button", nil, frame)
        button:SetHeight(20)
        button.check = button:CreateTexture(nil, "ARTWORK")
        button.check:SetSize(14, 14)
        button.check:SetPoint("LEFT", 0, 0)
        button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        local box = button:CreateTexture(nil, "BACKGROUND")
        box:SetSize(14, 14)
        box:SetPoint("LEFT", 0, 0)
        box:SetColorTexture(0, 0, 0, 0.5)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("LEFT", 18, 0)
        button.label:SetText(("%s (%d)"):format(tier, ns.TIER_REP[tier]))
        button:SetWidth(button.label:GetStringWidth() + 26)
        SetSimpleTooltip(button, tier .. " writs",
            ("Writs with names in this colour are %s writs. Each turn-in gives %d reputation "
                .. "(up to 10%% more with the Legacy perk Diplomat). Click to show or hide them.")
                :format(tier, ns.TIER_REP[tier]))
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -32)
        x = x + button:GetWidth() + 4
        button:SetScript("OnClick", function()
            state.tiers[tier] = not state.tiers[tier]
            state.offset = 0
            RefreshTierButtons()
            ns.RefreshWindow()
        end)
        tierButtons[tier] = button
    end

    -- Second filter row: cycle buttons. Left-click: next value; right-click:
    -- previous; the list wraps through "All".
    local function CycleButton(label, values, get, set)
        local button = CreateButton(frame, label .. ": All", 180, function(_, mouseButton)
            local options = values()
            local index = 0
            for i, value in ipairs(options) do
                if value == get() then index = i end
            end
            local step = mouseButton == "RightButton" and -1 or 1
            index = (index + step) % (#options + 1)
            set(options[index])
            state.offset = 0
            RefreshTierButtons()
            ns.RefreshWindow()
        end)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        return button
    end

    professionButton = CycleButton("Profession", Professions,
        function() return state.profession end, function(value) state.profession = value end)
    professionButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -56)
    SetSimpleTooltip(professionButton, "Profession", "Left-click: next profession. Right-click: previous.")

    zoneButton = CreateButton(frame, "Zones: All", 180, ToggleZonePopup)
    zoneButton:SetPoint("LEFT", professionButton, "RIGHT", 8, 0)
    SetSimpleTooltip(zoneButton, "Turn-in zones",
        "Pick the zones to show, grouped by continent; a continent's box ticks all its zones. "
        .. "Not learned yet: writs whose turn-in is unknown (accept that writ once).")

    local owned = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    owned:SetSize(22, 22)
    owned:SetPoint("LEFT", zoneButton, "RIGHT", 12, 0)
    local ownedLabel = owned:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ownedLabel:SetPoint("LEFT", owned, "RIGHT", 0, 0)
    ownedLabel:SetText("Only what I have")
    owned:SetScript("OnClick", function(self)
        state.ownedOnly = self:GetChecked() and true or false
        state.offset = 0
        ns.RefreshWindow()
    end)

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(150, 20)
    search:SetAutoFocus(false)
    search:SetPoint("LEFT", ownedLabel, "RIGHT", 16, 0)
    local searchHint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 2, 0)
    searchHint:SetText("Search")
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        -- Hint first, so it hides even if the redraw below fails.
        searchHint:SetShown(text == "")
        state.text = strtrim(text):lower()
        state.offset = 0
        ns.RefreshWindow()
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)

    scanButton = CreateButton(frame, "Full Scan", 80, function()
        ns.Scan()
    end)
    scanButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -32)
    scanButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Auctionator Full Scan")
        GameTooltip:AddLine("Runs Auctionator's full scan: every auction in one request, done in seconds. "
            .. "The server allows one every 15 minutes; Auctionator says in chat when the next is possible. "
            .. "The table updates when the scan finishes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scanButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scanButton:SetMotionScriptsWhileDisabled(true)

    lastScanText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lastScanText:SetPoint("RIGHT", scanButton, "LEFT", -8, 0)
    lastScanText:SetJustifyH("RIGHT")

    -- Column headers -------------------------------------------------------------
    for _, column in ipairs(COLUMNS) do
        local header = CreateFrame("Button", nil, frame)
        header:SetSize(column.width, 16)
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", column.x, HEADER_Y)
        local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetAllPoints()
        text:SetJustifyH(column.justify)
        text:SetText(column.title)
        if column.sort then
            header:SetScript("OnClick", function()
                if state.sort == column.sort then
                    state.ascending = not state.ascending
                else
                    state.sort, state.ascending = column.sort, true
                end
                ns.RefreshWindow()
            end)
            local highlight = header:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.08)
        end
    end
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, HEADER_Y - 16)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, HEADER_Y - 16)

    -- Rows ------------------------------------------------------------------------
    rows = {}
    for index = 1, VISIBLE_ROWS do rows[index] = CreateRow(frame, index) end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)

    scrollBar = CreateFrame("Slider", nil, frame)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetWidth(12)
    scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, HEADER_Y - 18)
    scrollBar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -8, HEADER_Y - 18 - VISIBLE_ROWS * ROW_HEIGHT)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.4)
    scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= state.offset then
            state.offset = value
            DrawRows()
        end
    end)

    local openMap = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    openMap:SetSize(22, 22)
    openMap:SetPoint("LEFT", search, "RIGHT", 16, 0)
    local openMapLabel = openMap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    openMapLabel:SetPoint("LEFT", openMap, "RIGHT", 0, 0)
    openMapLabel:SetText("Open map on turn-in click")
    openMap:SetScript("OnClick", function(self)
        ns.SetOpenMapOnClick(self:GetChecked())
    end)
    SetSimpleTooltip(openMap, "Open map on turn-in click",
        "On: clicking a turn-in opens the world map with a waypoint there (this closes the Auction House if it is open). "
        .. "Off: it only sets the waypoint.")

    listButton = CreateButton(frame, "Shopping list (0)", 130, function()
        if ns.ToggleShoppingList then ns.ToggleShoppingList() end
    end)
    listButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -56)
    SetSimpleTooltip(listButton, "Shopping list",
        "Shows or hides the shopping list. Tick the box at the start of a row to add a writ.")

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    statusText:SetJustifyH("LEFT")

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
    hint:SetText("Click a turn-in to open the map there; click a row to just pin it. Shift-click links the writ.")

    -- Prices change as Auctionator scans; refresh now and then while shown.
    local elapsedSinceRefresh = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRefresh = elapsedSinceRefresh + elapsed
        if elapsedSinceRefresh >= 2 then
            elapsedSinceRefresh = 0
            ns.RefreshWindow()
        end
    end)
    -- Size buttons, left of the close button: A- / A+.
    local function SizeButton(label, delta, anchorX, tooltip)
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(24, 16)
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", anchorX, -4)
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetAllPoints()
        text:SetText(label)
        button:SetScript("OnClick", function()
            ns.ApplyWindowScale(ns.WindowScale() + delta)
        end)
        button:SetScript("OnEnter", function(self)
            text:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltip)
            GameTooltip:AddLine(("Now %d%%. Also in Options > AddOns > Writs Ledger, or /wledger size 120.")
                :format(ns.WindowScale() * 100 + 0.5), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            text:SetTextColor(1, 0.82, 0)
            GameTooltip:Hide()
        end)
    end
    SizeButton("A+", ns.SCALE_STEP, -30, "Bigger text")
    SizeButton("A-", -ns.SCALE_STEP, -56, "Smaller text")

    frame:SetScript("OnShow", function()
        frame:SetScale(ns.WindowScale())
        openMap:SetChecked(ns.OpenMapOnClick())
        RefreshTierButtons()
        ns.RefreshWindow()
    end)
    -- The shopping list beside the table goes with it (it stays at the AH).
    frame:SetScript("OnHide", function()
        if ns.RefreshShoppingList then ns.RefreshShoppingList() end
    end)
end

function ns.ToggleWindow()
    if not frame then CreateWindow() end
    frame:SetShown(not frame:IsShown())
end

-- Window size ---------------------------------------------------------------------

local settingsSlider -- the slider in Options > AddOns, if the panel was registered

-- Saves a new size and applies it to the open window and the options slider.
function ns.ApplyWindowScale(value)
    local scale = ns.SetWindowScale(value)
    if frame then frame:SetScale(scale) end
    if settingsSlider and math.abs(settingsSlider:GetValue() - scale * 100) > 0.5 then
        settingsSlider:SetValue(scale * 100)
    end
    return scale
end

-- Options > AddOns > Writs Ledger: a panel with the size slider.
local function CreateSettingsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Writs Ledger"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Writs Ledger")

    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)

    local slider = CreateFrame("Slider", nil, panel)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(240, 16)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -12)
    slider:SetMinMaxValues(ns.SCALE_MIN * 100, ns.SCALE_MAX * 100)
    slider:SetValueStep(ns.SCALE_STEP * 100)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)
    track:SetColorTexture(0, 0, 0, 0.6)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local low = slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    low:SetText(("%d%%"):format(ns.SCALE_MIN * 100))
    local high = slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    high:SetText(("%d%%"):format(ns.SCALE_MAX * 100))

    local function ShowValue(percent)
        label:SetText(("Text and window size: %d%%"):format(percent + 0.5))
    end
    slider:SetScript("OnValueChanged", function(_, value)
        ShowValue(value)
        ns.ApplyWindowScale(value / 100)
    end)

    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -24)
    note:SetWidth(420)
    note:SetJustifyH("LEFT")
    note:SetText("Scales the whole writ table, so bigger text still fits its columns. "
        .. "Also: the A- / A+ buttons in the window's title bar, or /wledger size 80-150.")

    panel:SetScript("OnShow", function()
        local percent = ns.WindowScale() * 100
        ShowValue(percent)
        slider:SetValue(percent)
    end)
    settingsSlider = slider

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local okPanel = pcall(CreateSettingsPanel)
if not okPanel then settingsSlider = nil end

-- Turn-in map pin ---------------------------------------------------------------

-- Sets the turn-in as your map waypoint. Returns the turn-in (nil if unknown)
-- and whether the waypoint was set.
function ns.PinTurnIn(entry, quiet)
    local turnIn = ns.TurnIn(entry)
    if not turnIn then
        ns.Report(("the turn-in for %s is not known yet; accept that writ once to learn it."):format(entry.item))
        return nil, false
    end
    local pinned = false
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pinned = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(turnIn.mapID, turnIn.x, turnIn.y))
        if pinned and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
    -- A clickable map pin link in chat, where the client supports it.
    local link = ""
    if pinned and C_Map.GetUserWaypointHyperlink then
        local ok, value = pcall(C_Map.GetUserWaypointHyperlink)
        if ok and type(value) == "string" then link = " " .. value end
    end
    if not quiet or not pinned then
        ns.Report(("%s turn-in: %s%s %.1f, %.1f%s%s"):format(entry.item, turnIn.npc and (turnIn.npc .. ", ") or "",
            ns.ZoneName(turnIn), turnIn.x * 100, turnIn.y * 100,
            pinned and " (pinned on your map)" or "", link))
    end
    return turnIn, pinned
end

-- Sets the waypoint and opens the world map on the turn-in's zone.
function ns.ShowTurnInOnMap(entry)
    local turnIn, pinned = ns.PinTurnIn(entry)
    if not turnIn or not turnIn.mapID then return end
    if InCombatLockdown() then return end -- the map cannot always open in combat
    -- Setting off: waypoint only. (Opening the world map closes the Auction
    -- House if it is open; that is the player's choice via the checkbox.)
    if not ns.OpenMapOnClick() then
        if pinned then ns.Report("waypoint set; press M to see it.") end
        return
    end
    if OpenWorldMap then
        if pcall(OpenWorldMap, turnIn.mapID) then return end
    end
    local map = WorldMapFrame
    if not map then return end
    if not map:IsShown() then
        if ToggleWorldMap then pcall(ToggleWorldMap) elseif ShowUIPanel then pcall(ShowUIPanel, map) end
    end
    if map.SetMapID then pcall(map.SetMapID, map, turnIn.mapID) end
end

-- Auction House button ------------------------------------------------------------

-- Named so it does not shadow the global AuctionFrame (the legacy AH window):
-- inside "local function AuctionFrame", that name would be this function.
local function AHWindow()
    return _G.AuctionHouseFrame or _G.AuctionFrame
end

local WRIT_ICON_ITEM = 264019 -- any Craftsman's Writ: its scroll icon
local FALLBACK_ICON = "Interface\\Icons\\INV_Scroll_03"

local function WritIcon()
    local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if getIcon then
        local ok, icon = pcall(getIcon, WRIT_ICON_ITEM)
        if ok and icon then return icon end
    end
    return FALLBACK_ICON
end

local ICON_SIZE, ICON_GAP = 16, 4

-- A standard red button, same style and height as Auctionator's buttons.
-- (Not a tab: the Auction House tab templates add themselves to the
-- window's tab list, and Auctionator lines its tabs up after the last one.)
local function CreateAHButton()
    local ok, button = pcall(CreateFrame, "Button", nil, UIParent, "UIPanelDynamicResizeButtonTemplate")
    if not ok or not button then button = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate") end
    button:SetHeight(22)
    button:SetText("Writs Ledger")
    button:SetScript("OnClick", function() ns.ToggleWindow() end)

    local label = button:GetFontString()
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if label then
        label:ClearAllPoints()
        label:SetPoint("CENTER", button, "CENTER", (ICON_SIZE + ICON_GAP) / 2, 0)
        icon:SetPoint("RIGHT", label, "LEFT", -ICON_GAP, 0)
        button:SetWidth(math.ceil(label:GetStringWidth()) + ICON_SIZE + ICON_GAP + 28)
    else
        icon:SetPoint("LEFT", 8, 0)
        button:SetWidth(120)
    end
    button.icon = icon
    SetSimpleTooltip(button, "Writs Ledger", "Open the Craftsman's Writs table (also /wledger).")
    return button
end

-- Other addons also put buttons on top of the Auction House window. Find the
-- ones sitting in that strip (children of the AH window or of UIParent) as
-- horizontal spans in screen units, so ours can queue up beside them.
local SLOT_START, SLOT_GAP = 6, 4

local function CollectStripSpans(ahFrame, ahScale, ahTop, height, spans, ...)
    for index = 1, select("#", ...) do
        local frame = select(index, ...)
        if frame ~= ahButton and frame ~= ahFrame then
            pcall(function()
                if not frame:IsVisible() then return end
                local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
                if not (left and right and bottom and top) then return end
                local scale = frame:GetEffectiveScale()
                left, right, bottom, top = left * scale, right * scale, bottom * scale, top * scale
                -- Sits on the AH top edge (not inside the window) and is button-sized.
                if bottom >= ahTop - 4 * ahScale and bottom < ahTop + height
                    and top - bottom < 60 * ahScale and right - left < 400 * ahScale then
                    spans[#spans + 1] = { left = left, right = right }
                end
            end)
        end
    end
end

-- Distance (in AH units) from the AH's right edge to the right edge of the
-- first free slot, walking leftwards, that is wide enough for our button.
local function FreeSlotOffset(ahFrame)
    local ahScale = ahFrame:GetEffectiveScale()
    local ahLeft, ahRight, ahTop = ahFrame:GetLeft(), ahFrame:GetRight(), ahFrame:GetTop()
    if not (ahLeft and ahRight and ahTop) then return SLOT_START end
    ahLeft, ahRight, ahTop = ahLeft * ahScale, ahRight * ahScale, ahTop * ahScale
    local width = ahButton:GetWidth() * ahScale
    local gap = SLOT_GAP * ahScale

    local spans = {}
    local height = ahButton:GetHeight() * ahScale
    CollectStripSpans(ahFrame, ahScale, ahTop, height, spans, ahFrame:GetChildren())
    CollectStripSpans(ahFrame, ahScale, ahTop, height, spans, UIParent:GetChildren())
    table.sort(spans, function(a, b) return a.right > b.right end)

    local x = ahRight - SLOT_START * ahScale -- our right edge
    for _, span in ipairs(spans) do
        if span.left - gap < x and span.right + gap > x - width then
            x = span.left - gap
        end
    end
    if x - width < ahLeft then return SLOT_START end -- no room: keep the default spot
    return (ahRight - x) / ahScale
end

local function PlaceOnAuctionHouse(ahFrame)
    if not (ahButton and ahButton:IsShown() and ahFrame:IsShown()) then return end
    if ahButton:GetParent() ~= ahFrame then return end
    local ok, offset = pcall(FreeSlotOffset, ahFrame)
    ahButton:ClearAllPoints()
    ahButton:SetPoint("BOTTOMRIGHT", ahFrame, "TOPRIGHT", -(ok and offset or SLOT_START), 0)
end

function ns.ShowAHButton()
    local ahFrame = AHWindow()
    if not ahButton then ahButton = CreateAHButton() end
    ahButton.icon:SetTexture(WritIcon()) -- the item icon may only load later
    ahButton:ClearAllPoints()
    if ahFrame and ahFrame:IsShown() then
        -- On top of the Auction House window at its right edge, queued to the
        -- left of any other addon's button already there; it moves, scales
        -- and hides with the window.
        ahButton:SetParent(ahFrame)
        ahButton:SetFrameStrata(ahFrame:GetFrameStrata())
        ahButton:SetFrameLevel(ahFrame:GetFrameLevel() + 10)
        ahButton:SetPoint("BOTTOMRIGHT", ahFrame, "TOPRIGHT", -SLOT_START, 0)
        -- Other addons may add their buttons in the same frame or a moment
        -- later, so look for free space after they have had their turn.
        C_Timer.After(0, function() PlaceOnAuctionHouse(ahFrame) end)
        C_Timer.After(0.5, function() PlaceOnAuctionHouse(ahFrame) end)
    else
        -- Unknown Auction House frame on this client: top centre of the screen.
        ahButton:SetParent(UIParent)
        ahButton:SetFrameStrata("HIGH")
        ahButton:SetPoint("TOP", UIParent, "TOP", 0, -8)
    end
    ahButton:Show()
    ns.RefreshWindow()
end

function ns.HideAHButton()
    if ahButton then ahButton:Hide() end
    ns.RefreshWindow()
end

-- Slash command -------------------------------------------------------------------

SLASH_WRITSLEDGER1 = "/wledger"
SLASH_WRITSLEDGER2 = "/writsledger"
SLASH_WRITSLEDGER3 = "/awrits" -- name before 0.2.0
SlashCmdList.WRITSLEDGER = function(message)
    local command = strtrim(message or ""):lower()
    local size = command:match("^size%s*(%d+)")
    if command == "learn" then
        ns.LearnNow()
        ns.Report("re-read your bags and quest log.")
    elseif size then
        local scale = ns.ApplyWindowScale(tonumber(size) / 100)
        ns.Report(("window size %d%%."):format(scale * 100 + 0.5))
    elseif command == "size" then
        ns.Report(("window size is %d%%. Change it with /wledger size 80-150."):format(ns.WindowScale() * 100 + 0.5))
    else
        ns.ToggleWindow()
    end
end

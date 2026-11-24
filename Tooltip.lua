local _, ns = ...

-- Writs Ledger lines on every Craftsman's Writ tooltip (bags, Auction House,
-- chat links, mail): tier and reputation, the requested item and how many
-- you have, the turn-in, the item's cost and whether it is done today.

local IsSecret = ns.IsSecret

-- The writ entry for an item ID, or nil when the item is not a writ.
local function EntryForItemID(itemID)
    if type(itemID) ~= "number" or IsSecret(itemID) then return nil end
    local name
    if C_Item and C_Item.GetItemNameByID then
        local ok, value = pcall(C_Item.GetItemNameByID, itemID)
        if ok and not IsSecret(value) then name = value end
    end
    if type(name) == "string" then
        if name:sub(1, #ns.WRIT_PREFIX) ~= ns.WRIT_PREFIX then return nil end
        return ns.writsByItem[name:sub(#ns.WRIT_PREFIX + 1)]
    end
    -- Name not loaded yet: writ items are numbered 264000-264999; find it among
    -- the IDs learned or in the data.
    if itemID < 264000 or itemID > 264999 then return nil end
    for _, entry in ipairs(ns.writs) do
        if ns.ItemID(ns.WritName(entry)) == itemID then return entry end
    end
end

local function AddWritLines(tooltip, entry)
    local tier = ns.Tier(entry)
    local r, g, b = unpack(ns.TierColor(tier))
    tooltip:AddLine(" ")
    tooltip:AddLine("Writs Ledger", 0.2, 1, 0.6)
    local rep = ns.TIER_REP[tier or ""]
    tooltip:AddLine(("%s%s%s"):format(tier and (tier .. " writ") or "Writ",
        ns.Profession(entry) and (", " .. ns.Profession(entry)) or "",
        rep and (": %d reputation"):format(rep) or ""), r, g, b)

    local count, known = ns.Count(entry)
    local have = ns.owned[entry.item] or 0
    local mail = ns.OnWay(entry.item)
    local haveText = ("you have %d%s"):format(have, mail > 0 and (", %d in the mail"):format(mail) or "")
    if known then
        tooltip:AddLine(("Requests %d %s (%s)"):format(count, entry.item, haveText), 1, 1, 1, true)
    else
        tooltip:AddLine(("Requests %s (%s)"):format(entry.item, haveText), 1, 1, 1, true)
    end

    local turnIn = ns.TurnIn(entry)
    if turnIn then
        local npc = turnIn.npc or (entry.turnIn and entry.turnIn.npc)
        tooltip:AddLine(("Turn-in: %s%s %.0f, %.0f"):format(npc and (npc .. ", ") or "", ns.ZoneName(turnIn),
            turnIn.x * 100, turnIn.y * 100), 0.8, 0.8, 0.8, true)
    else
        tooltip:AddLine("Turn-in: not known yet (accept the writ once to learn it).", 0.6, 0.6, 0.6, true)
    end

    local _, itemPrice, total = ns.Prices(entry)
    if itemPrice then
        tooltip:AddDoubleLine(known and count > 1 and ("Item x%d"):format(count) or "Item", ns.FormatMoney(itemPrice),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    if total then
        tooltip:AddDoubleLine("Writ + item", ns.FormatMoney(total), 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if ns.DoneToday(entry) then
        local seconds = ns.SecondsUntilReset()
        tooltip:AddLine("Done today on this character." .. (seconds and (" Daily reset in "
            .. ns.FormatDuration(seconds) .. ".") or ""), 0.6, 0.6, 0.6, true)
    end
    if ns.InList(entry.item) then
        tooltip:AddLine("On your shopping list.", 0.4, 0.8, 1)
    end
end

local function Clear(tooltip) tooltip.writsLedgerShown = nil end

local function OnItemTooltip(tooltip, itemID)
    if not tooltip or tooltip.writsLedgerShown == itemID then return end
    local entry = EntryForItemID(itemID)
    if not entry then return end
    -- Once per tooltip, even if the hook fires twice; cleared with the tooltip.
    if not tooltip.writsLedgerHooked and tooltip.HookScript then
        tooltip.writsLedgerHooked = pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Clear)
    end
    if tooltip.writsLedgerHooked then tooltip.writsLedgerShown = itemID end
    local ok = pcall(AddWritLines, tooltip, entry)
    if ok and tooltip:IsShown() then tooltip:Show() end -- resize to the new lines
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if type(data) ~= "table" then return end
        OnItemTooltip(tooltip, data.id)
    end)
else
    -- Older tooltip API.
    local function Hook(tooltip)
        if not tooltip or not tooltip.HookScript then return end
        pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
            local _, link = self:GetItem()
            if type(link) == "string" and not IsSecret(link) then
                OnItemTooltip(self, tonumber(link:match("item:(%d+)")))
            end
        end)
    end
    Hook(GameTooltip)
    Hook(ItemRefTooltip)
end

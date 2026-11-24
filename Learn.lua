local addonName, ns = ...

-- Learns what the seed data does not have, from things you already do:
--   bags       -> item IDs of writs and requested items, what you own, writ tiers
--   AH results -> item IDs of writs and requested items seen in any search
--   quest window (right-clicking a writ) -> requested count
--   quest log (accepted writ) -> turn-in point from the map marker
-- Everything learned is saved account-wide in WritsLedgerDB.

local IsSecret = ns.IsSecret
local PREFIX = ns.WRIT_PREFIX

local function Plain(value)
    if IsSecret(value) then return nil end
    return value
end

local function NameFromLink(link)
    link = Plain(link)
    if type(link) ~= "string" then return nil end
    return link:match("|h%[(.-)%]|h")
end

local function IDFromLink(link)
    link = Plain(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Tooltip lines (left text) for an item ID.
local scanTooltip
local function TooltipLines(itemID)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                local text = Plain(line.leftText)
                if type(text) == "string" then lines[#lines + 1] = text end
            end
            return lines
        end
    end
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "WritsLedgerScanTooltip", UIParent, "GameTooltipTemplate")
    end
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:ClearLines()
    if not pcall(scanTooltip.SetHyperlink, scanTooltip, "item:" .. itemID) then return lines end
    for index = 1, scanTooltip:NumLines() do
        local region = _G["WritsLedgerScanTooltipTextLeft" .. index]
        local text = region and Plain(region:GetText())
        if type(text) == "string" then lines[#lines + 1] = text end
    end
    scanTooltip:Hide()
    return lines
end

-- The writ tooltip has the tier on its own line ("Expert").
local function LearnTier(item, writID)
    local learned = ns.Learned(item)
    if learned and learned.tier then return end
    for _, text in ipairs(TooltipLines(writID)) do
        if ns.TIER_ORDER[text] then
            ns.Learned(item, true).tier = text
            return
        end
    end
end

local changed = false

-- Records an item seen anywhere (bags, AH). Returns the writ's requested item
-- name if it is a writ.
local function Consider(name, itemID)
    if type(name) ~= "string" or type(itemID) ~= "number" then return end
    if name:sub(1, #PREFIX) == PREFIX then
        local item = name:sub(#PREFIX + 1)
        if not ns.writsByItem[item] then
            ns.AddWrit(item)
            ns.Learned(item, true)
            changed = true
        end
        ns.RememberID(name, itemID)
        LearnTier(item, itemID)
        return item
    elseif ns.writsByItem[name] then
        ns.RememberID(name, itemID)
    end
end

-- Names not cached yet: retried when the item data arrives.
local pendingIDs = {}

local function ItemNameByID(itemID)
    local name
    if C_Item and C_Item.GetItemNameByID then
        local ok, value = pcall(C_Item.GetItemNameByID, itemID)
        if ok then name = Plain(value) end
    end
    if not name then
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if getInfo then
            local ok, value = pcall(getInfo, itemID)
            if ok then name = Plain(value) end
        end
    end
    if not name then
        pendingIDs[itemID] = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    end
    return name
end

-- Writ items are numbered 264000-264999; anything else is only worth a name
-- lookup if it is a requested item we already know. This keeps an AH-wide
-- scan (thousands of results) from loading item data for every item.
local WRIT_ID_MIN, WRIT_ID_MAX = 264000, 264999
local knownIDs, knownCount = {}, -1

local function Interesting(itemID)
    if itemID >= WRIT_ID_MIN and itemID <= WRIT_ID_MAX then return true end
    if knownCount ~= #ns.writs then
        knownIDs, knownCount = {}, #ns.writs
        for _, entry in ipairs(ns.writs) do
            local id = entry.itemID or ns.ItemID(entry.item)
            if id then knownIDs[id] = true end
        end
    end
    return knownIDs[itemID] == true
end

local function ConsiderID(itemID)
    if type(itemID) ~= "number" or not Interesting(itemID) then return end
    Consider(ItemNameByID(itemID), itemID)
end

-- Bags -------------------------------------------------------------------------

local function ScanBags()
    if not C_Container or not C_Container.GetContainerNumSlots then return end
    local owned = {}
    local lastBag = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1)
    for bag = 0, lastBag do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local link = info.hyperlink
                local name = NameFromLink(link)
                local id = Plain(info.itemID) or IDFromLink(link)
                if name and id then
                    Consider(name, id)
                    local count = Plain(info.stackCount)
                    owned[name] = (owned[name] or 0) + (type(count) == "number" and count or 1)
                end
            end
        end
    end
    ns.owned = owned
    -- Bought items reaching the bags are no longer "in the mail". Not in the
    -- first seconds after login, while the bags may still be loading.
    if ns.bagsSettled then ns.UpdateOnWay() end
    changed = true -- the Have column follows the bags
end

-- Auction House purchases ------------------------------------------------------
-- On Forever, bought items go to the mailbox, so the bags do not show them
-- yet. The server says "You won an auction for [Item]x10 for 3g 20s" in chat
-- (ERR_AUCTION_WON_S, plus Forever's price); commodity buys also fire
-- COMMODITY_PURCHASE_SUCCEEDED. Either one counts the purchase, once.

local CHAT_GRACE = 30 -- seconds after closing the AH that a purchase line still counts
local DUPLICATE_WINDOW = 10
local ahClosedAt
local recentBuys = {} -- name -> { t, n, via }

-- Is this name a writ or a requested item?
local function Tracked(name)
    if type(name) ~= "string" then return false end
    if name:sub(1, #PREFIX) == PREFIX then return ns.writsByItem[name:sub(#PREFIX + 1)] ~= nil end
    return ns.writsByItem[name] ~= nil
end

local function RecordPurchase(name, count, via)
    if not Tracked(name) or type(count) ~= "number" or count < 1 then return end
    local now = GetTime()
    local recent = recentBuys[name]
    if recent and now - recent.t < DUPLICATE_WINDOW and recent.via ~= via then
        -- The same purchase reported the other way: count only what is new.
        local extra = count - recent.n
        recentBuys[name] = nil
        if extra <= 0 then return end
        count = extra
    else
        recentBuys[name] = { t = now, n = count, via = via }
    end
    ns.AddOnWay(name, count)
    changed = true
end

local function Listening()
    return ns.ahOpen or (ahClosedAt ~= nil and GetTime() - ahClosedAt < CHAT_GRACE)
end

-- Item name and count from a "You won an auction for ..." line, or nil.
local function ParseAuctionWon(message)
    message = Plain(message)
    if type(message) ~= "string" then return nil end
    local format = type(ERR_AUCTION_WON_S) == "string" and ERR_AUCTION_WON_S or "You won an auction for %s"
    local lead = format:match("^(.-)%%s")
    if not lead or lead == "" then return nil end
    message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local at = message:find(lead, 1, true)
    if not at then return nil end
    local what = message:sub(at + #lead)
    local name, rest = what:match("^|H.-|h%[(.-)%]|h(.*)$")
    if not name then name, rest = what:match("^%[(.-)%](.*)$") end
    if not name then name, rest = what:match("^(.-)%s*([xX]%d+.*)$") end
    if not name then name, rest = what:match("^(.-)%s+for%s.*$") or what:gsub("%.$", ""), "" end
    local count = tonumber((rest or ""):match("^%s*[xX]%s*(%d+)")) or 1
    return strtrim(name), count
end

local pendingCommodity
if hooksecurefunc and C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
        pendingCommodity = type(itemID) == "number" and { itemID = itemID, n = quantity or 1 } or nil
    end)
end

-- Auction House results --------------------------------------------------------

-- Legacy AH: list results carry links (name and ID).
local function ScanLegacyResults()
    if not GetNumAuctionItems or not GetAuctionItemLink then return end
    local count = GetNumAuctionItems("list") or 0
    for index = 1, count do
        local link = GetAuctionItemLink("list", index)
        Consider(NameFromLink(link), IDFromLink(link))
    end
end

-- Modern AH: browse results carry item keys (ID only). RESULTS_ADDED passes
-- just the new page, so a paged AH-wide scan is read once, not once per page.
local function ScanBrowseResults(added)
    local results = added
    if type(results) ~= "table" then
        if not C_AuctionHouse or not C_AuctionHouse.GetBrowseResults then return end
        local ok, all = pcall(C_AuctionHouse.GetBrowseResults)
        if not ok or type(all) ~= "table" then return end
        results = all
    end
    for _, result in ipairs(results) do
        ConsiderID(result.itemKey and result.itemKey.itemID)
    end
end

-- Quest window: count ------------------------------------------------------------

local function LearnFromQuestDetail()
    local title = GetTitleText and Plain(GetTitleText())
    if type(title) ~= "string" or title:sub(1, #PREFIX) ~= PREFIX then return end
    local item = title:sub(#PREFIX + 1)
    ns.AddWrit(item)
    local text = GetQuestText and Plain(GetQuestText())
    -- "...the note is requesting 1 Red Mageweave Pants, along with..."
    local count = type(text) == "string" and tonumber(text:match("requesting (%d+) "))
    if count then
        ns.Learned(item, true).count = count
        changed = true
    end
end

-- Quest log: turn-in point -------------------------------------------------------

local function ForEachQuest(callback)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local count = C_QuestLog.GetNumQuestLogEntries() or 0
        for index = 1, count do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader then callback(Plain(info.title), Plain(info.questID)) end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local count = GetNumQuestLogEntries() or 0
        for index = 1, count do
            local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if not isHeader then callback(Plain(title), Plain(questID)) end
        end
    end
end

local function RootMap()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetMapInfo then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local guard = 0
    while mapID and guard < 10 do
        local info = C_Map.GetMapInfo(mapID)
        if not info or not info.parentMapID or info.parentMapID == 0 then break end
        mapID = info.parentMapID
        guard = guard + 1
    end
    return mapID
end

-- The quest's marker on one map, or nil.
local function MarkerOnMap(questID, mapID)
    local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not ok or type(quests) ~= "table" then return end
    for _, quest in ipairs(quests) do
        if Plain(quest.questID) == questID then
            local x, y = Plain(quest.x), Plain(quest.y)
            if type(x) == "number" and type(y) == "number" then return x, y end
        end
    end
end

-- The turn-in is "the location marked on your map": find the quest's own map
-- marker. C_QuestLog.GetNextWaypoint is not used: it gives the next step of
-- the route there (a zone exit, a tram, a flight master), not the turn-in.
-- `expectedMapID` (the Data.lua turn-in map, if any) breaks ties.
local function FindQuestLocation(questID, expectedMapID)
    if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
    -- The map the game files the quest under, when the client says.
    if C_QuestLog.GetQuestUiMapID then
        local ok, questMap = pcall(C_QuestLog.GetQuestUiMapID, questID)
        questMap = ok and Plain(questMap)
        if type(questMap) == "number" and questMap > 0 then
            local x, y = MarkerOnMap(questID, questMap)
            if x then return questMap, x, y end
        end
    end
    if not C_Map or not C_Map.GetMapChildrenInfo then return end
    local root = RootMap()
    if not root then return end
    local ok, maps = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
    if not ok or type(maps) ~= "table" then return end
    -- The most detailed map that shows the marker (zone or city over continent);
    -- among equally detailed maps, the one Data.lua expects.
    local best
    for _, map in ipairs(maps) do
        local x, y = MarkerOnMap(questID, map.mapID)
        if x then
            local rank = (map.mapType or 0) * 2 + (map.mapID == expectedMapID and 1 or 0)
            if not best or rank > best.rank then
                best = { mapID = map.mapID, rank = rank, x = x, y = y }
            end
        end
    end
    if best then return best.mapID, best.x, best.y end
end

local function LearnTurnIns()
    ForEachQuest(function(title, questID)
        if type(title) ~= "string" or title:sub(1, #PREFIX) ~= PREFIX or type(questID) ~= "number" then return end
        local item = title:sub(#PREFIX + 1)
        ns.AddWrit(item)
        local learned = ns.Learned(item, true)
        local entry = ns.writsByItem[item]
        -- Remember the quest ID when Data.lua has none or a different one,
        -- so turn-ins and the daily check find this writ.
        if entry and entry.quest ~= questID and learned.quest ~= questID then
            learned.quest = questID
        end
        if learned.turnIn then return end
        local expected = entry and entry.turnIn and entry.turnIn.mapID
        local mapID, x, y = FindQuestLocation(questID, expected)
        if mapID and x and y then
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
            learned.turnIn = {
                mapID = mapID, x = x, y = y, zone = info and info.name or ("map " .. mapID),
                method = ns.TURN_IN_METHOD,
            }
            changed = true
            ns.Report(("confirmed the turn-in for %s: %s %.1f, %.1f"):format(item, learned.turnIn.zone, x * 100, y * 100))
        end
    end)
end

-- Events -------------------------------------------------------------------------

-- Redraws the window once, a moment after the last change, instead of once
-- per event (AH scans and item-data loads fire many events in a burst).
local flushQueued = false
local function Flush()
    if not changed or flushQueued then return end
    flushQueued = true
    C_Timer.After(0.3, function()
        flushQueued = false
        changed = false
        ns.RefreshWindow()
    end)
end

local questLogQueued = false
local function QueueQuestLogScan(delay)
    if questLogQueued then return end
    questLogQueued = true
    C_Timer.After(delay, function()
        questLogQueued = false
        LearnTurnIns()
        Flush()
    end)
end

local events = CreateFrame("Frame")
local function TryRegister(event)
    pcall(events.RegisterEvent, events, event)
end
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
TryRegister("BAG_UPDATE_DELAYED")
TryRegister("AUCTION_HOUSE_SHOW")
TryRegister("AUCTION_HOUSE_CLOSED")
TryRegister("AUCTION_ITEM_LIST_UPDATE")
TryRegister("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
TryRegister("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
TryRegister("ITEM_SEARCH_RESULTS_UPDATED")
TryRegister("COMMODITY_SEARCH_RESULTS_UPDATED")
TryRegister("GET_ITEM_INFO_RECEIVED")
TryRegister("QUEST_DETAIL")
TryRegister("QUEST_ACCEPTED")
TryRegister("QUEST_LOG_UPDATE")
TryRegister("QUEST_TURNED_IN")
TryRegister("CHAT_MSG_SYSTEM")
TryRegister("COMMODITY_PURCHASE_SUCCEEDED")
TryRegister("COMMODITY_PURCHASE_FAILED")

-- A writ was turned in: mark it done for today on this character.
local function OnQuestTurnedIn(questID)
    questID = Plain(questID)
    local entry = ns.EntryForQuest(questID)
    if not entry and type(questID) == "number" and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        title = ok and Plain(title)
        if type(title) == "string" and title:sub(1, #PREFIX) == PREFIX then
            entry = ns.writsByItem[title:sub(#PREFIX + 1)]
        end
    end
    if not entry then return end
    ns.MarkTurnedIn(entry.item)
    -- Done with this writ for today: off the shopping list.
    if ns.InList(entry.item) then ns.SetInList(entry.item, false) end
    changed = true
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then ns.InitializeDatabase() end
        return
    elseif event == "PLAYER_LOGIN" then
        ns.Report("loaded. Type /wledger to open the writ table.")
        ns.RegisterPriceUpdates()
        ScanBags()
        QueueQuestLogScan(3)
        C_Timer.After(10, function()
            ns.bagsSettled = true
            ScanBags()
            Flush()
        end)
    elseif event == "BAG_UPDATE_DELAYED" then
        ScanBags()
    elseif event == "AUCTION_HOUSE_SHOW" then
        ns.ahOpen = true
        ahClosedAt = nil
        changed = true -- enables Buy/Scan
        ns.ShowAHButton()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ns.ahOpen = false
        ahClosedAt = GetTime()
        pendingCommodity = nil
        changed = true
        ns.HideAHButton()
    elseif event == "CHAT_MSG_SYSTEM" then
        if not Listening() then return end
        local name, count = ParseAuctionWon(arg1)
        if not name then return end
        RecordPurchase(name, count, "chat")
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" or event == "COMMODITY_PURCHASE_FAILED" then
        local pending = pendingCommodity
        pendingCommodity = nil
        if not pending or event == "COMMODITY_PURCHASE_FAILED" then return end
        RecordPurchase(ItemNameByID(pending.itemID), pending.n, "commodity")
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        ScanLegacyResults()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        ScanBrowseResults(arg1)
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        ScanBrowseResults()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        ConsiderID(type(arg1) == "table" and arg1.itemID or nil)
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        ConsiderID(arg1)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if type(arg1) ~= "number" or not pendingIDs[arg1] then return end
        pendingIDs[arg1] = nil
        ConsiderID(arg1)
    elseif event == "QUEST_DETAIL" then
        LearnFromQuestDetail()
    elseif event == "QUEST_ACCEPTED" then
        QueueQuestLogScan(1)
        return
    elseif event == "QUEST_LOG_UPDATE" then
        QueueQuestLogScan(5)
        return
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn(arg1)
    end
    Flush()
end)

-- Re-reads the quest log on demand (/wledger learn).
function ns.LearnNow()
    ScanBags()
    LearnTurnIns()
    Flush()
end

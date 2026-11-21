local addonName, ns = ...

-- Shared model for the writ table: the writ list (seed data merged with what
-- was learned in-game), item IDs by name, prices from Auctionator, and buying
-- through Auctionator's Shopping tab.
--
-- Auctionator's public extension API (Auctionator.API.v1) is used, plus its
-- Scan button entry point for the full scan (no public call exists). Every
-- call is guarded, so an Auctionator update cannot break this addon's window.

local CALLER = addonName

ns.WRIT_PREFIX = "Craftsman's Writ: "
ns.WRIT_SEARCH = "Craftsman's Writ"

ns.TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan" }
ns.TIER_ORDER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }
ns.TIER_COLORS = {
    Apprentice = { 0.85, 0.85, 0.85 },
    Journeyman = { 0.12, 1.00, 0.00 },
    Expert     = { 0.00, 0.55, 1.00 },
    Artisan    = { 0.78, 0.40, 1.00 },
}
ns.UNKNOWN_COLOR = { 0.6, 0.6, 0.6 }

function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

-- Saved data -------------------------------------------------------------------

-- WritsLedgerDB (account-wide):
--   ids[name]   = itemID, for writs and requested items, learned from bags and AH
--   writs[item] = { tier, profession, count, turnIn = { mapID, x, y, zone } }
local db

ns.writs = {}        -- list of seed entries (see Data.lua), plus writs learned in-game
ns.writsByItem = {}  -- requested item name -> entry
ns.owned = {}        -- item name -> count in your bags (writs by writ name)
ns.ahOpen = false

local seedIDs = {}   -- name -> item ID, from the seed data

-- `seed` is a Data.lua entry, or just { item = name } for a writ learned in-game.
local function AddWrit(seed)
    if type(seed) == "string" then seed = { item = seed } end
    local existing = ns.writsByItem[seed.item]
    if existing then return existing end
    ns.writs[#ns.writs + 1] = seed
    ns.writsByItem[seed.item] = seed
    if seed.writID then seedIDs[ns.WRIT_PREFIX .. seed.item] = seed.writID end
    if seed.itemID then seedIDs[seed.item] = seed.itemID end
    return seed
end
ns.AddWrit = AddWrit

function ns.InitializeDatabase()
    WritsLedgerDB = type(WritsLedgerDB) == "table" and WritsLedgerDB or {}
    db = WritsLedgerDB
    db.ids = type(db.ids) == "table" and db.ids or {}
    db.writs = type(db.writs) == "table" and db.writs or {}
    if db.openMap == nil then db.openMap = true end -- click a turn-in: open the map
    for _, seed in ipairs(ns.SeedWrits or {}) do AddWrit(seed) end
    -- Writs learned in-game that the seed list does not have.
    for item in pairs(db.writs) do AddWrit(item) end
end

-- What was learned about one writ (created on first write).
function ns.Learned(item, create)
    if not db then return nil end
    local learned = db.writs[item]
    if not learned and create then
        learned = {}
        db.writs[item] = learned
    end
    return learned
end

function ns.WritName(entry) return ns.WRIT_PREFIX .. entry.item end

function ns.Tier(entry)
    local learned = ns.Learned(entry.item)
    return learned and learned.tier or entry.tier
end

-- List of professions (some writs accept either of two), or an empty list.
function ns.Professions(entry)
    return entry.professions or {}
end

-- "Alchemy" or "Alchemy / Engineering"; nil when unknown.
function ns.Profession(entry)
    local professions = ns.Professions(entry)
    if #professions == 0 then return nil end
    return table.concat(professions, " / ")
end

-- Requested count and whether it is known (seen in-game or in the data).
function ns.Count(entry)
    local learned = ns.Learned(entry.item)
    local count = learned and learned.count or entry.count
    return count, count ~= nil
end

-- Turn-in point and its source: "confirmed" (from your own quest log) or
-- "data" (baseline in Data.lua). nil when not known.
function ns.TurnIn(entry)
    local learned = ns.Learned(entry.item)
    if learned and learned.turnIn then return learned.turnIn, "confirmed" end
    if entry.turnIn then return entry.turnIn, "data" end
end

-- Zone name of a turn-in (saved, or from the map).
function ns.ZoneName(turnIn)
    if turnIn.zone then return turnIn.zone end
    local info = C_Map and C_Map.GetMapInfo and turnIn.mapID and C_Map.GetMapInfo(turnIn.mapID)
    return info and info.name or "?"
end

-- True when this writ's daily quest was already done today (nil if unknown).
function ns.DoneToday(entry)
    if not entry.quest then return nil end
    local check = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not check then return nil end
    local ok, done = pcall(check, entry.quest)
    if ok and type(done) == "boolean" then return done end
end

-- Continent of a map (Kalimdor, Eastern Kingdoms, ...): walk up the map
-- parents to the continent-type map. Cached per map.
local continentByMap = {}
local function ContinentOfMap(mapID)
    if continentByMap[mapID] ~= nil then return continentByMap[mapID] or nil end
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    local name = false
    local current, guard = mapID, 0
    while current and current ~= 0 and guard < 10 and C_Map and C_Map.GetMapInfo do
        local info = C_Map.GetMapInfo(current)
        if not info then break end
        if info.mapType == continentType then
            name = info.name
            break
        end
        current, guard = info.parentMapID, guard + 1
    end
    continentByMap[mapID] = name
    return name or nil
end

-- Continent of the writ's turn-in point; nil while the turn-in is unknown.
function ns.Continent(entry)
    local turnIn = ns.TurnIn(entry)
    if not turnIn or not turnIn.mapID then return nil end
    return ContinentOfMap(turnIn.mapID)
end

function ns.TierColor(tier)
    return ns.TIER_COLORS[tier or ""] or ns.UNKNOWN_COLOR
end

-- Item IDs ---------------------------------------------------------------------

function ns.RememberID(name, itemID)
    if not db or type(name) ~= "string" or type(itemID) ~= "number" then return end
    db.ids[name] = itemID
end

-- Item ID for an item name: saved, or from the item cache (works once the game
-- has seen the item, e.g. in bags or AH results).
function ns.ItemID(name)
    if not db or not name then return nil end
    local id = db.ids[name] or seedIDs[name]
    if id then return id end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local ok, _, link = pcall(getInfo, name)
        if ok and type(link) == "string" and not ns.IsSecret(link) then
            id = tonumber(link:match("item:(%d+)"))
            if id then db.ids[name] = id end
        end
    end
    return id
end

-- Prices (Auctionator's saved price database; no AH searches) --------------------

local function API()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- Returns price in copper (or nil) and its age in days (or nil).
function ns.Price(itemID)
    local api = API()
    if not api or not itemID then return nil end
    local price, age
    if api.GetAuctionPriceByItemID then
        local ok, value = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
        if ok and type(value) == "number" then price = value end
    end
    if price and api.GetAuctionAgeByItemID then
        local ok, value = pcall(api.GetAuctionAgeByItemID, CALLER, itemID)
        if ok and type(value) == "number" then age = value end
    end
    return price, age
end

-- Writ price, item price (for the requested count) and total. Missing parts
-- are nil; total is nil unless both are known.
function ns.Prices(entry)
    local writPrice, writAge = ns.Price(ns.ItemID(ns.WritName(entry)))
    local itemPrice, itemAge = ns.Price(ns.ItemID(entry.item))
    local count = ns.Count(entry) or 1
    if itemPrice then itemPrice = itemPrice * count end
    local total = writPrice and itemPrice and (writPrice + itemPrice) or nil
    return writPrice, itemPrice, total, writAge, itemAge
end

function ns.FormatMoney(copper)
    if not copper then return "|cff808080--|r" end
    copper = math.floor(copper + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100
    if gold > 0 then
        if silver > 0 then return ("%d|cffffd100g|r %d|cffc7c7cfs|r"):format(gold, silver) end
        return ("%d|cffffd100g|r"):format(gold)
    elseif silver > 0 then
        if rest > 0 then return ("%d|cffc7c7cfs|r %d|cffeda55fc|r"):format(silver, rest) end
        return ("%d|cffc7c7cfs|r"):format(silver)
    end
    return ("%d|cffeda55fc|r"):format(rest)
end

-- Buying and scanning (Auctionator's Shopping tab) -----------------------------

-- Clicking a turn-in opens the world map (true) or only sets a waypoint.
function ns.OpenMapOnClick()
    return not db or db.openMap ~= false
end

function ns.SetOpenMapOnClick(value)
    if db then db.openMap = value and true or false end
end

-- Time (from time()) Auctionator last finished a scan, or nil.
function ns.LastScan()
    return db and db.lastScan
end

local function Report(message)
    print("|cff33ff99Writs Ledger|r: " .. message)
end
ns.Report = Report

-- Opens Auctionator's Shopping tab with an exact search for each name. You
-- buy from the results with Auctionator as usual.
function ns.Buy(names)
    local api = API()
    if not ns.ahOpen then
        Report("open the Auction House to buy.")
        return
    end
    if not api or not api.MultiSearchExact then
        Report("this Auctionator version has no search API.")
        return
    end
    local ok, err = pcall(api.MultiSearchExact, CALLER, names)
    if not ok then Report("search failed: " .. tostring(err)) end
end

-- Starts Auctionator's own Full Scan (one bulk request for the whole Auction
-- House, then a 15 minute server cooldown). Auctionator's public API has no
-- call for this, so this uses the same entry point as Auctionator's Scan
-- button, guarded: if Auctionator changes it, we only print a message.
-- Auctionator reports progress and the cooldown in chat itself.
function ns.Scan()
    if not ns.ahOpen then
        Report("open the Auction House to scan.")
        return
    end
    local mixin = AuctionatorScanButtonMixin
    if type(mixin) == "table" and type(mixin.OnClick) == "function" then
        -- Honours Auctionator's own setting (full or incremental scan).
        if pcall(mixin.OnClick, mixin) then return end
    end
    local frame = Auctionator and Auctionator.State and Auctionator.State.FullScanFrameRef
    if frame and type(frame.InitiateScan) == "function" then
        local ok, err = pcall(frame.InitiateScan, frame)
        if not ok then Report("full scan failed: " .. tostring(err)) end
        return
    end
    Report("could not start Auctionator's full scan. Use the Scan button on Auctionator's tab.")
end

-- Records when Auctionator last finished a scan and redraws the window, so
-- new prices show without reopening it. Covers scans started from Auctionator.
function ns.RegisterPriceUpdates()
    local api = API()
    if not api or not api.RegisterForDBUpdate then return end
    pcall(api.RegisterForDBUpdate, CALLER, function()
        if db then db.lastScan = time() end
        if ns.RefreshWindow then ns.RefreshWindow() end
    end)
end

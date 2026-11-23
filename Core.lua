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
-- Base reputation per turn-in, before the Legacy perk Diplomat (+2% per rank,
-- up to +10%). Numbers from Craftman's Helper.
ns.TIER_REP = { Journeyman = 75, Expert = 125, Artisan = 200 }

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
    -- Before 0.2.5 one "last scan" time was shared by every realm and faction,
    -- and any AH search counted as a scan; now it is kept per price database.
    db.lastScan = nil
    for _, seed in ipairs(ns.SeedWrits or {}) do AddWrit(seed) end
    -- Writs learned in-game that the seed list does not have.
    for item in pairs(db.writs) do AddWrit(item) end
    ns.DropRouteTurnIns()
end

-- Turn-ins learned before 0.2.1 could be a step on the route (e.g. a point in
-- Dun Morogh for a Searing Gorge writ). Drop those that disagree with Data.lua;
-- they are learned again, correctly, the next time the writ is in your log.
ns.TURN_IN_METHOD = 2
function ns.DropRouteTurnIns()
    for item, learned in pairs(db.writs) do
        local turnIn = type(learned) == "table" and learned.turnIn
        if type(turnIn) == "table" and turnIn.method ~= ns.TURN_IN_METHOD then
            local seed = ns.writsByItem[item]
            local expected = seed and seed.turnIn and seed.turnIn.mapID
            if expected and turnIn.mapID ~= expected then
                learned.turnIn = nil
            end
        end
    end
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

-- Daily turn-ins ---------------------------------------------------------------

-- Keyed by the character's GUID: on Forever, UnitName/GetRealmName gave "Lil-"
-- for every "Lil-..." character, so alts shared one list.
local function CharacterKey()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and not ns.IsSecret(guid) and guid ~= "" then return guid end
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName() or ""
    return name and (name .. "-" .. realm) or nil
end

-- Time of the last daily reset, or nil when the client does not say.
local function LastDailyReset()
    local untilReset
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local ok, seconds = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok then untilReset = seconds end
    end
    if type(untilReset) ~= "number" and GetQuestResetTime then
        local ok, seconds = pcall(GetQuestResetTime)
        if ok then untilReset = seconds end
    end
    if type(untilReset) ~= "number" or untilReset <= 0 then return nil end
    return time() + untilReset - 86400
end

-- Remembers that this character turned in the writ for `item` just now.
function ns.MarkTurnedIn(item)
    local key = CharacterKey()
    if not db or not key or not item then return end
    db.turnedIn = type(db.turnedIn) == "table" and db.turnedIn or {}
    db.turnedIn[key] = type(db.turnedIn[key]) == "table" and db.turnedIn[key] or {}
    db.turnedIn[key][item] = time()
end

local function TurnedInToday(item)
    local key = CharacterKey()
    local byChar = db and type(db.turnedIn) == "table" and key and db.turnedIn[key]
    local at = type(byChar) == "table" and byChar[item]
    if type(at) ~= "number" then return false end
    local reset = LastDailyReset() or (time() - 86400)
    return at >= reset
end

local function QuestFlagged(questID)
    if type(questID) ~= "number" then return nil end
    local check = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not check then return nil end
    local ok, done = pcall(check, questID)
    if ok and type(done) == "boolean" then return done end
end

-- True when this character already turned in this writ today: the game's
-- daily completion flag, or a turn-in this addon saw since the daily reset.
function ns.DoneToday(entry)
    if TurnedInToday(entry.item) then return true end
    local learned = ns.Learned(entry.item)
    return QuestFlagged(entry.quest) or QuestFlagged(learned and learned.quest) or false
end

-- The writ entry whose quest has this ID, or nil.
function ns.EntryForQuest(questID)
    if type(questID) ~= "number" then return nil end
    for _, entry in ipairs(ns.writs) do
        local learned = ns.Learned(entry.item)
        if entry.quest == questID or (learned and learned.quest == questID) then return entry end
    end
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
-- Window size (text and all), 0.8-1.5; saved account-wide.
ns.SCALE_MIN, ns.SCALE_MAX, ns.SCALE_STEP = 0.8, 1.5, 0.05

function ns.WindowScale()
    local scale = db and tonumber(db.scale)
    if not scale then return 1 end
    return math.min(ns.SCALE_MAX, math.max(ns.SCALE_MIN, scale))
end

-- Stores the size (rounded to a step, clamped) and returns it.
function ns.SetWindowScale(value)
    value = tonumber(value) or 1
    value = math.floor(value / ns.SCALE_STEP + 0.5) * ns.SCALE_STEP
    value = math.min(ns.SCALE_MAX, math.max(ns.SCALE_MIN, value))
    if db then db.scale = value end
    return value
end

function ns.OpenMapOnClick()
    return not db or db.openMap ~= false
end

function ns.SetOpenMapOnClick(value)
    if db then db.openMap = value and true or false end
end

-- Auctionator keeps one price database per AH (on Forever: ruleset + faction,
-- e.g. "PvE Horde") and picks it for the character you log in with. Scan
-- times are kept under the same key, so a Horde scan never shows as recent on
-- an Alliance character.
local function PriceDatabaseKey()
    local state = Auctionator and Auctionator.State
    local key = state and state.CurrentRealm
    if type(key) == "string" and key ~= "" then return key end
    return (GetRealmName and GetRealmName() or "?") .. " " .. (UnitFactionGroup and UnitFactionGroup("player") or "?")
end

-- Time (from time()) Auctionator last finished a scan of this AH, or nil.
function ns.LastScan()
    if not db or type(db.lastScans) ~= "table" then return nil end
    return db.lastScans[PriceDatabaseKey()]
end

-- True while Auctionator's own scan is running. An AH search started then
-- (by the Buy buttons, or anyone) replaces the scan's results, and the scan
-- ends with "Finished processing 0 items".
function ns.AuctionatorScanning()
    local state = Auctionator and Auctionator.State
    if not state then return false end
    local summary, replicate = state.IncrementalScanFrameRef, state.FullScanFrameRef
    return (summary and summary.doingFullScan == true) or (replicate and replicate.inProgress == true) or false
end

-- Auctionator's scan progress, 0-1, while it scans; nil otherwise.
function ns.ScanProgress()
    if not ns.AuctionatorScanning() then
        ns.scanProgress = nil
        return nil
    end
    return ns.scanProgress or 0
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
    if ns.AuctionatorScanning() then
        Report("Auctionator is still scanning. Buy when it says \"Finished processing\"; a search now would cut the scan short.")
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

-- Redraws the window when Auctionator's prices change, so they show without
-- reopening it. Auctionator also records prices from every AH search (not
-- only scans), so its public update callback cannot tell a scan apart. Scan
-- state ("scanning 42%", "Last scan") instead comes from Auctionator's scan
-- events (internal, guarded: if they change, the window only loses the
-- progress text and the "Last scan" time; ns.AuctionatorScanning still
-- greys out the buttons during a scan).
function ns.RegisterPriceUpdates()
    local api = API()
    if api and api.RegisterForDBUpdate then
        pcall(api.RegisterForDBUpdate, CALLER, function()
            if ns.RefreshWindow then ns.RefreshWindow() end
        end)
    end

    local bus = Auctionator and Auctionator.EventBus
    if not bus or type(bus.Register) ~= "function" then return end
    local kinds, events = {}, {}
    for _, name in ipairs({ "IncrementalScan", "FullScan" }) do -- summary and replicate scans
        local group = Auctionator[name]
        local names = type(group) == "table" and type(group.Events) == "table" and group.Events
        if names then
            for _, kind in ipairs({ "ScanStart", "ScanProgress", "ScanComplete", "ScanFailed" }) do
                if type(names[kind]) == "string" then
                    kinds[names[kind]] = kind
                    events[#events + 1] = names[kind]
                end
            end
        end
    end
    if #events == 0 then return end
    pcall(bus.Register, bus, {
        ReceiveEvent = function(_, eventName, progress)
            local kind = kinds[eventName]
            if kind == "ScanStart" then
                ns.scanProgress = 0
            elseif kind == "ScanProgress" then
                ns.scanProgress = type(progress) == "number" and progress or ns.scanProgress or 0
            elseif kind == "ScanComplete" then
                ns.scanProgress = nil
                if db then
                    db.lastScans = type(db.lastScans) == "table" and db.lastScans or {}
                    db.lastScans[PriceDatabaseKey()] = time()
                end
            elseif kind == "ScanFailed" then
                ns.scanProgress = nil
            end
            -- Progress fires often during a scan: only redraw the percentage.
            if kind == "ScanProgress" then
                if ns.RefreshScanStatus then ns.RefreshScanStatus() end
            elseif ns.RefreshWindow then
                ns.RefreshWindow()
            end
        end,
    }, events)
end

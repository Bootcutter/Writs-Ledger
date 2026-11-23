# Changelog

## 0.2.5

- While Auctionator scans, the Buy and Full Scan buttons are greyed out and the window shows "Auctionator scanning... N%". A search during the scan cut it short ("Finished processing 0 items").
- "Last scan" now counts only finished Auctionator scans (not every Auction House search) and is kept per Auctionator price database, so each faction has its own.
- The Writs Ledger button on the Auction House moves left of another addon's button instead of covering it.
- Fixed: the turn-in NPCs "Plucky" Johnson and "Sea Wolf" MacKinley showed stray backslashes in the tooltip.
- Fixed a possible error on clients with the old-style Auction House window.

## 0.2.4

- The zone filter now lists Kalimdor on the left and Eastern Kingdoms on the right, as on the world map.
- The tier colours are explained: the tier boxes read "Writ tier (rep per turn-in): Journeyman (75), Expert (125), Artisan (200)", hovering one explains it, and each writ's tooltip shows its reputation.
- Fixed: characters whose names share a prefix (for example Lil-Bolty and Lil-Stormy) shared one "turned in today" list. Each character now has its own.

## 0.2.3

- Packaging: the addon's TOC file is now named WritsLedger.toc so CurseForge accepts the upload. No gameplay changes.

## 0.2.2

- Writs you turned in today get a green check in the Have column, and their name is dimmed. Turn-ins are also remembered per character until the daily reset, so the check shows even when the game's completion flag does not.
- Removed the Apprentice and Unknown filter boxes; no writ has those tiers, so they did nothing.
- The Auction House button now matches Auctionator's buttons: same style and height, a writ icon and a "Writs Ledger" label, attached to the top of the Auction House window.
- Even near-black window background (no more grey texture and inner frame).
- Text size setting (80-150%): Options > AddOns > Writs Ledger, the A- / A+ buttons in the title bar, or /wledger size 120. It scales the whole table so text never gets cut off.

## 0.2.1

- Fixed: a writ's turn-in could be learned as a point on the way there (for example Dun Morogh for Searing Gorge writs, or The Barrens for Feralas). Turn-ins are now read from the quest's own map marker, and wrongly learned ones are cleared and learned again the next time you have the writ.

## 0.2.0

First public release.

- Table of all 150 Craftsman's Writs with tier, profession, requested item and count, what you carry, and turn-in point.
- Auctionator prices for the writ, the item and both together; Buy / Buy / Both open Auctionator's Shopping tab with an exact search.
- Full Scan button and "last scan" time.
- Turn-in points for 111 writs, confirmed from your quest log as you accept writs; click to open the map with a waypoint.
- Filters by tier, profession, turn-in zone, "Only what I have" and name; sortable columns.
- Open with `/wledger` or the Writs button on the Auction House.

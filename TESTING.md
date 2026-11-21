# Writs Ledger: in-game test checklist

1. `/reload` with Auctionator enabled: no Lua errors. Disable Auctionator: Writs Ledger does not load (required dependency).
2. `/wledger`: the window opens with ~150 rows, names coloured by tier (Journeyman green, Expert blue, Artisan purple). Escape closes it; it can be dragged. Mouse wheel and the scroll bar scroll.
3. Toggle tier boxes, cycle profession, type in Search (the grey "Search" hint disappears as soon as you type and comes back when the box is empty), tick "Only what I have": the list and the "N writs shown" count follow. Click headers to sort.
3a. Click **Zones**: a panel opens below it with columns per continent (Eastern Kingdoms, Kalimdor, ..., Not learned yet). Tick only Feralas and Thousand Needles: the list shows just those writs and the button reads "Zones: 2 selected". Untick a continent box: all its zones clear. **All** restores everything ("Zones: All"); **None** empties the list. Clicking a zone's name also toggles it. Close hides the panel; closing the window hides it too.
4. Away from the AH: Buy and Scan buttons are disabled and the status line says to open the Auction House.
5. Open the AH: a **Writs** button sits above its top-right corner; Buy/Scan buttons enable.
6. Click **Full Scan**: Auctionator prints that the full scan started and finishes within seconds; the table fills with prices and "Last scan" says "just now" without reopening the window. Click again right away: Auctionator says how long until the next scan. A scan started from Auctionator's own tab also updates "Last scan".
7. Click **Buy** under Item on Red Mageweave Pants: the Shopping tab shows only that item. **Both**: writ and item are listed together. Buy one through Auctionator.
8. Counts show from the start (Crafted Solid Shot is x200). Right-click a writ in your bags (do not accept): if its count differs, the table updates.
9. About 111 writs show a pale turn-in zone and coordinates from the start; the tooltip names the NPC. The Zones panel lists their zones from the start. Accept a writ: within a few seconds chat says "confirmed the turn-in for ...", and its Turn-in turns white. Compare with the baseline; if they differ, the confirmed one is right. Click a row: a map pin is set (or the coordinates are printed if pins are not available).
10. Complete a writ: its Have column shows grey "done" for the rest of the day.
11. Carry a writ and its item: the Have column shows a gold **W** and the item count.
12. Report anything that does not fill in (prices, counts, turn-ins) together with whether the AH you use looks like the old (Classic) or new (Retail) Auction House.
13. Route fix (0.2.1): Solid Sharpening Stone, Fire Protection Potion and Nightscape Shoulders show Searing Gorge (pale) after updating. Accept one of them while in Ironforge: chat confirms Searing Gorge, not Dun Morogh. Catseye Ultra Goggles shows Feralas, Dusky Bracers Dustwallow Marsh.

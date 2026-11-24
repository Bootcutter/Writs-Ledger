# Writs Ledger

**Every Craftsman's Writ in one table, with Auctionator prices and one-click shopping.**

Made for **World of Warcraft: Forever**. Requires **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**.

Writs Ledger lists all 150 Craftsman's Writs. Each row shows the writ's tier, its profession, the item and count it asks for, what you already carry, where to turn it in, and what the writ, the item and both together cost on the Auction House. Buy buttons open Auctionator's Shopping tab with an exact search, so you can find the cheapest writ to fill without searching by hand.

## Features

- **All writs in one table.** Names are coloured by tier, and the tier sets the reputation a turn-in gives: Journeyman (green) 75, Expert (blue) 125, Artisan (purple) 200, before the Legacy perk Diplomat. The tier boxes above the table double as the legend.
- **Prices from Auctionator.** The table shows the price of the writ, of the requested item, and of both together. Prices come from Auctionator's saved data, so the table works anywhere, even away from the Auction House. Prices older than today are grey and show their age in days.
- **One-click shopping.** At the Auction House, **Buy** (writ), **Buy** (item) and **Both** open Auctionator's Shopping tab with an exact search. You still click to buy every item yourself.
- **Auctionator Full Scan button.** Starts Auctionator's own full scan from the table and shows its progress ("Auctionator scanning... 42%"). While any Auctionator scan runs, the Buy buttons are paused so a search can't cut the scan short. The table updates when the scan finishes.
- **Shopping list.** Tick the writs you want to do. At the Auction House the list sits beside the AH window with each writ and its requested item. **Search all** searches for everything still missing in one go, and each line ticks itself off as you buy. Forever sends purchases by mail; they count right away and show as "in the mail" until they reach your bags. Turned-in writs leave the list by themselves.
- **Writ tooltips.** Hover a Craftsman's Writ anywhere (bags, Auction House, chat links) to see its tier and reputation, the requested item and how many you have, the turn-in, and what the item costs. Items that a writ you carry (or have accepted or listed) asks for are marked **Writ item** in their tooltip, so you don't sell them by accident.
- **Daily reset timer** at the bottom of the table, and a yellow note when most prices are a day or more old.
- **Turn-in points.** Shows the zone and coordinates for 111 writs from the start. Click the zone to open the world map with a waypoint on the spot. Turn-in points for the rest are learned when you accept those writs.
- **Filters and sorting.** Filter by tier, profession, turn-in zone (grouped by continent), "Only what I have" and name search. Click a column header to sort.
- **Your progress.** Shows which writs and items are in your bags, and dims writs this character has already turned in today, with a green check.

## Getting started

1. Install **Auctionator** and **Writs Ledger**.
2. Go to an Auction House and click **Auctionator Full Scan** in the table, or run a scan from Auctionator. Prices appear once a scan has finished.
3. Type `/wledger`, or click the **Writs Ledger** button on top of the Auction House window.

## Commands and clicks

| Action | Result |
|---|---|
| `/wledger` | Opens or closes the table. `/writsledger` and the old `/awrits` work too. |
| `/wledger learn` | Reads your bags and quest log again. |
| `/wledger lastbuy` | Shows the last Auction House purchase line and how it was read (for bug reports). |
| `/wledger size 120` | Sets the text and window size, from 80 to 150%. Also in **Options > AddOns > Writs Ledger** and with the **A- / A+** buttons in the window's title bar. |
| Tick the box at the start of a row | Adds the writ to your shopping list. **Shopping list (N)** at the top right shows or hides the list. |
| Tick the box in the header row | Adds every writ shown (after your filters) to the list, or takes them all off. |
| Shopping list: click / right-click a line | Searches for that item / takes the writ off the list. |
| Click a column header | Sorts by that column. Click again to reverse it. Writs without a price always come last. |
| Click a turn-in zone | Opens the world map with a waypoint on the turn-in spot. This closes the Auction House if it is open. Untick **Open map on turn-in click** to set only the waypoint. |
| Click elsewhere on a row | Sets the waypoint only. |
| Shift-click a row | Links the writ in chat. |

## Good to know

- **Auctionator 349 or newer keeps separate prices for each faction on Forever.** After you update Auctionator, run a full scan before you trust the prices.
- The full scan has a **15-minute server cooldown**. Auctionator tells you in chat when the next scan is possible.
- In the Turn-in column, **white** means your own quest log confirmed the spot. **Pale** means the spot comes from the built-in data. The row's tooltip names the NPC.
- Writs that are not in the built-in data are added when you see them in your bags or in Auction House results.
- Writs Ledger reads prices through Auctionator's public API (plus its scan events, for the progress display), and never buys anything without your click.
- "Last scan" is kept separately for each Auctionator price database, so Horde and Alliance each show their own.
- If another addon already has a button at the top right of the Auction House window, the Writs Ledger button sits to its left.
- Settings and learned data are saved account-wide. The shopping list and "done today" are kept per character.
- The shopping list notices a purchase from the Auction House's "You won an auction" message. It never buys anything itself: every purchase is still your own click in Auctionator.

## Bugs and feedback

Please report problems in the comments on this project's page. Include the Lua error text if there is one (BugSack makes it easy to copy) and your Auctionator version.

## License and credits

Thanks to **emsw0rth**, author of [Craftman's Helper](https://github.com/emsw0rth/craftmanshelper). The built-in writ list and turn-in points (in Data.lua) are adapted from Craftman's Helper 1.10.3, Copyright (C) 2026 Emsworth, licensed under the GNU GPL v3.0. They have been reformatted for this addon. Craftman's Helper builds on:

- [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0): turn-in NPCs and coordinates.
- [Wowhead's Craftsman's Writs guide](https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards) and its quest and NPC pages: the list of writs and some Expert and Artisan turn-in NPCs.

For this reason, Writs Ledger is licensed under the **GNU GPL v3.0**; see LICENSE.md. If you share or change the addon, keep the license and these credits.

Writs Ledger is not made by or affiliated with the Auctionator authors.

# Writs Ledger

**Every Craftsman's Writ in one table, with Auctionator prices and one-click shopping.**

Made for **World of Warcraft: Forever**. Requires **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)**.

Writs Ledger lists all 150 Craftsman's Writs. Each row shows the writ's tier, its profession, the item and count it asks for, what you already carry, where to turn it in, and what the writ, the item and both together cost on the Auction House. Buy buttons open Auctionator's Shopping tab with an exact search, so you can find the cheapest writ to fill without searching by hand.

## Features

- **All writs in one table.** Names are coloured by tier: Apprentice, Journeyman, Expert and Artisan.
- **Prices from Auctionator.** The table shows the price of the writ, of the requested item, and of both together. Prices come from Auctionator's saved data, so the table works anywhere, even away from the Auction House. Prices older than today are grey and show their age in days.
- **One-click shopping.** At the Auction House, **Buy** (writ), **Buy** (item) and **Both** open Auctionator's Shopping tab with an exact search. You still click to buy every item yourself.
- **Full Scan button.** Starts Auctionator's own full scan from the table. The table updates when the scan finishes.
- **Turn-in points.** Shows the zone and coordinates for 111 writs from the start. Click the zone to open the world map with a waypoint on the spot. Turn-in points for the rest are learned when you accept those writs.
- **Filters and sorting.** Filter by tier, profession, turn-in zone (grouped by continent), "Only what I have" and name search. Click a column header to sort.
- **Your progress.** Shows which writs and items are in your bags, and puts a green check on writs this character has already turned in today.

## Getting started

1. Install **Auctionator** and **Writs Ledger**.
2. Go to an Auction House and click **Full Scan** in the table, or run a scan from Auctionator. Prices appear once a scan has finished.
3. Type `/wledger`, or click the **Writs Ledger** button on top of the Auction House window.

## Commands and clicks

| Action | Result |
|---|---|
| `/wledger` | Opens or closes the table. |
| `/wledger learn` | Reads your bags and quest log again. |
| `/wledger size 120` | Sets the text and window size, from 80 to 150%. Also in **Options > AddOns > Writs Ledger** and with the **A- / A+** buttons in the window's title bar. |
| Click a column header | Sorts by that column. Click again to reverse it. Writs without a price always come last. |
| Click a turn-in zone | Opens the world map with a waypoint on the turn-in spot. This closes the Auction House if it is open. Untick **Open map on turn-in click** to set only the waypoint. |
| Click elsewhere on a row | Sets the waypoint only. |
| Shift-click a row | Links the writ in chat. |

## Good to know

- **Auctionator 349 or newer keeps separate prices for each faction on Forever.** After you update Auctionator, run a full scan before you trust the prices.
- The full scan has a **15-minute server cooldown**. Auctionator tells you in chat when the next scan is possible.
- In the Turn-in column, **white** means your own quest log confirmed the spot. **Pale** means the spot comes from the built-in data. The row's tooltip names the NPC.
- Writs that are not in the built-in data are added when you see them in your bags or in Auction House results.
- Writs Ledger uses only Auctionator's public API, and never buys anything without your click.
- Settings and learned data are saved account-wide.

## Bugs and feedback

Please report problems in the comments on this project's page. Include the Lua error text if there is one (BugSack makes it easy to copy) and your Auctionator version.

## License and credits

Thanks to **emsw0rth**, author of [Craftman's Helper](https://github.com/emsw0rth/craftmanshelper). The built-in writ list and turn-in points (in Data.lua) are adapted from Craftman's Helper 1.10.3, Copyright (C) 2026 Emsworth, licensed under the GNU GPL v3.0. They have been reformatted for this addon. Craftman's Helper builds on:

- [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0): turn-in NPCs and coordinates.
- [Wowhead's Craftsman's Writs guide](https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards) and its quest and NPC pages: the list of writs and some Expert and Artisan turn-in NPCs.

For this reason, Writs Ledger is licensed under the **GNU GPL v3.0**; see LICENSE.md. If you share or change the addon, keep the license and these credits.

Writs Ledger is not made by or affiliated with the Auctionator authors.

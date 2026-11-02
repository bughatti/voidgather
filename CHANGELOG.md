# VoidGather Changelog

## 0.3.2

- **Gathering HUD.** Your minimap, big and see-through in front of you and turning with you: the game's own herb and ore dots (Find Herbs / Find Minerals) float around you, with VoidGather's spots (and VoidSweep's, if you have it) on top. Its buttons wait in a dark circle where the minimap normally sits, and turning it off puts everything back, zoom and rotation included. Set a key in Keybindings > AddOns > VoidGather, use `/vg hud`, or tick it in the settings window (size, how much of the map shows underneath, Move HUD to place it). It switches outside combat.
- **Void hub pop-up** opens next to the hub icon again when another addon moves or fades the minimap (a gathering HUD did both).

## 0.3.1

- **Players-here box.** A small box you can drag anywhere showing how many other VoidGather (and VoidSweep) players are in your zone, kept up to date as people come and go. Tick it in the settings window or use `/vg box`.

## 0.3.0

- **What your gathering is worth.** Herbs, ore, skins, lumber and fish are priced as they land in your bags (VoidAH, Auctionator or TSM if you have one, else the vendor price). Tick **Earnings box on screen** in the settings window, or `/vg earn`, for a small box you can drag anywhere: session total and gold per hour, with the split by profession and your best items on hover. Only time spent gathering counts toward the hourly rate.
- **Sell it or craft it?** Hover a herb, ore, leather or cooking ingredient to see its sell price and what each piece is worth crafted (potion, flask, mulch, ingot, armor kit, food), best three first, with "you can make it" when you know the recipe. The earnings box shows the crafted value of your loot in green and what the session would be worth crafted. Built from every Midnight recipe in the game's data and your own auction prices.
- **Best zones.** Each zone keeps a gold-per-hour record across sessions: `/vg earn zones`. `/vg earn history` lists recent sessions. A session ends 15 minutes after your last loot or with `/vg reset`, and carries over a /reload.
- **A real settings window.** The Void hub icon, the world map button and `/vg options` open a proper VoidGather window in the Void addons' style (drag the title bar, x or Esc to close) instead of a dropdown menu. The hub icon is new: VoidGather now shows up in it, and right-clicking it turns the earnings box on or off.
- **Waypoints across continents.** A pin in another zone or continent now sends you to the right portal first, then on to the spot after you arrive.

## 0.2.2

- **Smaller, see-through minimap pins.** The squares on your minimap were big enough to hide the terrain. They are now smaller and 70% opaque, with a thinner skill-color edge. The world map button has two new settings, **Minimap pin size** (Small / Medium / Large) and **Minimap pin opacity** (50% / 70% / 100%), and a pick shows on the minimap at once.

## 0.2.1

- **Who's here.** When you enter a zone, VoidGather tells you how many other VoidGather players are in it. It stays quiet when nobody else is there; `/vg here` asks anytime. Caves and city floors count as their zone, instances aren't counted, players with sharing turned off aren't counted, and players on an older VoidGather don't answer yet.

## 0.2.0

- **Skill-up colors.** Herb and ore pins get an outline in the profession window's colors: orange always gives a skill point, yellow usually, green rarely, grey never (grey pins fade). It reads your Midnight Herbalism and Mining skill and each node's skill thresholds from the game's own data, and turns off once you're maxed.
- **Where to go.** The world-map menu shows your skill, which nodes give points now, and a **Go:** button that sets a waypoint to the best known spot. `/vg best` does the same from chat.
- **"Only nodes that give skill"** in the map menu hides the grey ones.
- **Midnight ore is saved again.** Midnight's mining cast has its own name ("Midnight Mining"), so ore you mined there was never saved. Herbs were fine.
- Sharing sends its messages at a steady pace instead of in bursts. Spots named from your loot merge with the same node shared by others. Leaving a map in combat no longer leaves its pins over the next one, and the waypoint watcher stops when the waypoint isn't VoidGather's.

## 0.1.5

- **`/vg net` shows who else is out there.** Besides checking that sharing works, it now tells you how many other VoidGather players are online on your realm group right now, and how many messages you've received from other players this session.

## 0.1.4

- **Smooth minimap pins.** Gathering pins no longer jitter while you fly or ride; they now move with the minimap every frame.

## 0.1.3

- **Minimap pins now actually show.** A bug kept every gathering spot off the minimap (the world map was fine).

## 0.1.2

- World map pins are now small colored diamonds (blue mining, green herbs, white skinning, teal lumber) drawn underneath quest markers, flight points and entrances, so they no longer cover what you're questing on.
- New: "Only my professions" (on by default) hides spots for professions you don't have. Lumber always shows.
- New: "World map dots" switch in the map menu, to keep pins on the minimap only.
- Updated for WoW 12.1.5 — no longer shows as out of date.

## 0.1.1

- Fixed: the world-map button could sit on top of another addon's map button and hide it.
- The map button's gold ring is now centered, with a round icon.

## 0.1.0 — first release

- Saves every mining, herb, skinning and lumber spot you gather to your world map and minimap.
- Shares spots with other VoidGather players on your realm (live, plus catch-up when you enter a zone). `/vg share` turns it off.
- Click a pin for a waypoint.
- Session loot tally (`/vg stats`).
- Optional auto-switch of Find Minerals / Find Herbs (`/vg track`).
- World-map button with filters and options.
- Works in WoW Forever and WoW 12.1.

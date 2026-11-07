# VoidGather Changelog

## 0.4.6

- **Known spots come with VoidGather.** A new character no longer starts with an empty map: VoidGather now ships with the spots its players have gathered so far (WoW Forever: Durotar, The Barrens, Tirisfal Glades, Silverpine Forest and Stonetalon Mountains; retail: Midnight zones). They show faded like shared spots, with "comes with VoidGather" on hover, and become yours once you gather there. Only spots gathered by hand or confirmed by two players are included. This matters most where few players of your faction use VoidGather, because sharing never crosses factions.
- **Lighter sharing.** Spots everyone already has from VoidGather itself aren't sent again.

## 0.4.5

- **WoW Forever: the players box shows the right count.** VoidGather, VoidQuest and VoidSweep each read their own sharing channel's member list, but the game hands out only one list at a time, so they took it from each other. A count could stick, and VoidGather could lose its list of players to ask for spots. They now take turns.
- **Offline players stay off the count.** A player who logged off stays at 0 until a message to them goes through again. Before, they came back as "online" every 30 minutes.

## 0.4.4

- **Fixed: sharing errors during encounters.** While the game's chat lockdown is on (boss fights), system messages are hidden from addons; VoidGather read one and errored. It now skips them, and joining the sharing channel waits until combat or the lockdown is over, then tries again.

## 0.4.3

- **WoW Forever: offline players no longer counted or messaged.** Forever's sharing channel still lists players who have logged off. When one of them can't be reached, VoidGather now leaves them out for 30 minutes, so the players box shows who's really online and spots go to players who can get them.
- **The players box says "Players online" on WoW Forever** (it counts players online, not per zone, there), and it has room for VoidQuest's line too.

## 0.4.2

- **Spot sharing works again on WoW Forever.** Forever's live servers stopped carrying addon messages on the hidden sharing channel, so shared spots silently stopped arriving there. On Forever, VoidGather now sends them by hidden addon whisper to a few other VoidGather players online instead (they never show in chat). Retail is unchanged.
- **On Forever the players box counts VoidGather players online** (Forever can't count them by zone any more). `/vg here` says the same.
- **Auto-tracking no longer errors in battlegrounds** (your speed is hidden there), and stays off in instances, where there's nothing to gather.

## 0.4.1

- **Deposit for crafters covers everything your crafters use.** With VoidBags, the warband bank's "Materials for your crafters" list now has every material in your bags that one of your other characters' professions crafts with (dust and crystals for your enchanter, herbs your scribe mills, cooking ingredients for your cook), not only crafting goals. Goals still come first with their exact counts. What the character you're on crafts with stays in its bags, except disenchanting materials (dust, shards, Dawn Crystals), which always go to the warband bank for your enchanter. A character's professions count once it has logged in with VoidBags or opened its profession window.
- **Take my materials** (with VoidBags): the reverse, what in the warband bank the character you're on crafts with, back into its bags. A character with Enchanting takes the disenchanting materials too.
- **Only crafting materials move**, never potions, food or gear a recipe happens to take. A profession a character has never leveled (Cooking 1/100) doesn't count as one it crafts with.

## 0.4.0

- **Crafting goals in every profession.** The **Set a crafting goal** button (it was "Set a gather goal") now shows on every Midnight recipe, not just the ones made straight from herbs, ore, leather or cooking ingredients: Inscription's inks and Treatises, Enchanting's enchants, Jewelcrafting, Tailoring and Engineering recipes, crafted gear. Hovering an ink, dust or other crafted material shows which of your characters crafts with it.
- **Your characters' materials in VoidAH.** VoidAH's profession leveling plan uses VoidGather's count of every character's bags and bank, so it can use what your alts hold before telling you to buy.

## 0.3.5

- **Settings are per character.** Each character keeps its own VoidGather settings, and a new character starts with the settings of the one you played last, so nothing resets when you update. Right-click the Void hub icon by your minimap and pick **Copy settings from...** to take another character's settings for one Void addon or all of them. Window positions, your spots, earnings, recipes and crafting goals stay shared by all your characters.

## 0.3.4

- **Gathering for your other characters.** Open a profession window once on each character and VoidGather remembers its recipes. Hovering a herb or ore on any character then shows who of yours crafts what from it.
- **Crafting goals.** Click **Set a gather goal** in a recipe's profession window (or **Add a goal** in the settings window) and pick how many to craft. The earnings box lists the materials still missing on every character, the ones you gather first ("Azeroot 9/15"), says when everything's in, and counts the goal down as you craft. Counts include your bank, the warband bank and what your other characters held the last time you played them (right away with VoidBags).
- **Deposit for your crafters (with VoidBags).** At the bank, VoidBags' Warband tab lists the goal materials you're carrying that your crafter still needs, with one button to put them in the warband bank.

## 0.3.3

- **Compass on the HUD.** N, E, S and W sit on the HUD's rim and turn as you turn, with north in cyan and your heading (N, NE, E...) just above the ring, so you always know which way you're flying.
- **Void hub icons in rings.** Clicking the Void hub icon fans your Void addons out in rings around it (5, then 7, 9, 12), opening away from the minimap instead of one long column.

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

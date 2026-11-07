# VoidGather

**Remembers every mining, herb, skinning and lumber spot you gather, shares them with other players, and shows them all on your map.**

VoidGather builds your gathering routes as you play. Every vein, herb, skinnable spot and tree you chop is saved to your world map and minimap. Spots found by other VoidGather players arrive automatically, so you can find nodes in zones you've never farmed. It works in WoW Forever and in Midnight.

---

## Features

### Your spots, on your map
- **Saved automatically** — gather a node and its spot appears on the world map and minimap, named ("Copper Vein", "Peacebloom", "Thalassian Lumber")
- **Lumber too** — Midnight's housing lumber counts, no profession needed
- **Settles on the exact spot** — gathering the same node again refines its position instead of adding a duplicate
- **Stays out of your way** — small colored diamonds (blue mining, green herbs, white skinning, teal lumber) drawn underneath quest markers, flight points and entrances
- **Only your professions** — spots for professions you don't have stay hidden (lumber always shows); switch it off in the settings window
- **Click a pin for a waypoint** — Blizzard's waypoint and arrow, cleared when you arrive
- **Minimap pins** are small and see-through so the map shows through, and fade near the edge so close spots stand out. Pick their size and opacity from the world map button

### Skill-ups: where to level Herbalism and Mining
- **Pins show if they still give you skill**, in the profession window's colors: an **orange** outline always gives a point, **yellow** usually, **green** rarely, and **grey** never (grey pins fade). Black means no skill info, such as an older expansion's node
- **Uses your real Midnight skill** and the game's own skill thresholds for each node
- **Where to go**: the settings window shows your skill, what gives points right now, and a **Go:** button that sets a waypoint to the best known spot. `/vg best` does the same from chat
- **"Only nodes that give skill"** in the settings window hides the grey ones
- Turns itself off once you're maxed, so farming pins don't all go grey

### Shared with other players
- **Not an empty map on day one** — VoidGather comes with known spots for the zones its players have gathered in (WoW Forever and retail), faded like shared spots. They become yours once you gather there
- **Live sharing** — when another VoidGather player gathers a new spot on your realm, it shows up on your map
- **Zone catch-up** — entering a zone asks other players for the spots they know there
- **Easy to tell apart** — shared spots are smaller and faded, brighten once a second player confirms them, and become yours once you gather there
- **Hover a shared pin** to see who found it and when
- **Who's here** — entering a zone tells you how many other VoidGather players are in it (`/vg here` asks any time)
- **Players-here box** — a small box you can drag anywhere that keeps that count on screen, updated as people come and go (VoidSweep players too, if you have it). Tick it in the settings window or `/vg box`
- **Turn sharing off** any time with `/vg share` or the settings window

### What your gathering is worth
- **Gold per hour** — every herb, ore, skin, lumber and fish you loot is priced as it lands in your bags, and the session total and gold per hour add up as you go
- **A small box you can put anywhere** — tick "Earnings box on screen" in the settings window (or `/vg earn`), then drag it where you like. Hover it for the split by profession and your most valuable items; right-click to start a new session
- **Fair hourly rate** — only time spent gathering counts. A break of more than 5 minutes (flying back to town, a dungeon, AFK) is left out
- **Best zones** — every zone keeps a running gold-per-hour record across your sessions, so `/vg earn zones` shows where gathering pays best for you. `/vg earn history` lists your recent sessions
- **Prices** come from VoidAH's auction data, Auctionator or TSM if you have one, otherwise the vendor price. Soulbound loot has no price and isn't counted

### Sell it or craft it?
- **Hover a herb, ore, leather or cooking ingredient** and the tooltip shows its sell price and what each piece is worth turned into something else: a potion, flask, mulch, ingot, armor kit or food. The best three, with the profession that makes them, and "you can make it" when you know the recipe
- **The earnings box shows it too** — hover it and items worth more crafted show that value in green, plus what your whole session would be worth crafted
- **Every Midnight recipe** comes from the game's own data; values use your auction prices (VoidAH, Auctionator or TSM) and are left out when a price is missing, so you never see a guess. Crafting bonuses aren't counted, so real crafts can come out a bit better
- Turn the tooltip lines off in the settings window

### Gathering for your other characters
- **It knows what your alts craft** — open a profession window once on each character and VoidGather saves the recipes it has learned. From then on, hovering a herb or ore on any of your characters names who crafts what from it ("Vede: Harandar Celebration, 3 each")
- **Crafting goals, every profession** — in any recipe's profession window click **Set a crafting goal** (or **Add a goal** in the settings window) and pick how many to craft: food, potions, inks, enchants, gear. The earnings box then lists the materials still missing, on every character, the ones you gather first: "Azeroot 9/15"
- **The list clears itself** — a material leaves the box once you have enough, the goal says "all in, craft on Vede" when everything's there, and it counts down as you craft
- **Counts every character** — your bags, bank and warband bank, plus what your other characters held the last time you played them (with VoidBags installed, their bags count right away)
- **Moves materials to whoever crafts with them** (with VoidBags) — at the bank, the Warband tab's **Deposit for crafters** puts in every material your other characters craft with (their crafting goals first), keeping what the character you're on uses itself; **Take my materials** brings back what this character crafts with. Only real crafting materials move, never potions or food, and a profession a character has never leveled doesn't count

### Gathering HUD
- **Your minimap, big and see-through in front of you** and turning with you, so the game's own herb and ore dots (Find Herbs / Find Minerals) float around you while you fly, with VoidGather's spots on top
- **Click-through** while you play; **Move HUD** in the settings window to place it, three sizes, and how much of the map shows underneath
- **Nothing gets lost** — the minimap's buttons wait where it normally sits, and turning the HUD off puts everything back, zoom and rotation included
- **A compass** on its rim (N, E, S, W turning with you) and your heading above it
- **VoidSweep's rares and treasures** show on it too, if you have VoidSweep
- Key binding (Keybindings > AddOns > VoidGather), `/vg hud`, or the settings window. It switches outside combat

### Gathering helpers
- **Session loot tally** — what you've gathered this session, with an hourly rate
- **Auto-switch Find Minerals / Find Herbs** (optional) — for miner-herbalists where only one tracker can run at a time; it only flips while you're moving and out of combat

### Settings window
- **Open it from the Void hub icon by your minimap, the button on the world map, or `/vg options`.** Drag the title bar to move it; the x or Esc closes it. It has your skill-ups and where to go, show/hide filters for mining, herbs, skinning and lumber (with counts for the zone), "only nodes that give skill", "only my professions", world map dots, minimap pins (with size and opacity), auto-switch, sharing, the earnings and players-here boxes, item tooltips and the gathering HUD

---

## Slash Commands

| Command | What it does |
|---|---|
| `/vg` | Show all commands |
| `/vg options` | Open the settings window |
| `/vg best` | Waypoint to the best known spot for your Herbalism or Mining skill-ups |
| `/vg zone` | How many spots are known in this zone (yours and shared) |
| `/vg stats` | This session's gathered loot |
| `/vg reset` | Start a new session (loot tally and earnings) |
| `/vg earn` | Earnings box on or off |
| `/vg earn zones` | Best gold per hour by zone, from all your sessions |
| `/vg earn history` | Your recent sessions |
| `/vg mining` · `/vg herb` · `/vg skin` · `/vg lumber` | Show or hide that kind of pin |
| `/vg minimap` | Minimap pins on or off |
| `/vg track` | Auto-switch Find Minerals / Find Herbs on or off |
| `/vg share` | Share spots with other players on or off |
| `/vg here` | How many other VoidGather players are in your zone |
| `/vg box` | Players-here box on or off |
| `/vg hud` | Gathering HUD on or off · `/vg hud move` to place it |
| `/vg net` | Check that sharing works on your realm, and see how many other VoidGather players are online there |

---

## Getting Started

1. Install with the CurseForge app, or copy the `VoidGather` folder into your game's `Interface/AddOns/` folder.
2. Restart WoW or `/reload`.
3. Turn on **Find Minerals** or **Find Herbs** from the tracking button by your minimap, and gather your first node — VoidGather says so in chat and pins it on your map.

---

## Privacy & Data

- **What's shared:** the kind of spot (mining, herb, skinning or lumber), the zone, its map position and the node's name. Nothing about your character, bags or gold. Your earnings stay on your computer.
- Other players see the character name that shared a spot, the same as any addon message.
- Shared spots only come from players' own gathers, never passed along second-hand, so one bad report can't spread.
- With sharing off, VoidGather sends and receives nothing.

---

## Good to Know

- **Settings are per character.** Each character keeps its own VoidGather settings, and a new character starts with the settings of the one you played last, so nothing resets when you update. Right-click the Void hub icon by your minimap and pick **Copy settings from...** to take another character's settings for one Void addon or all of them. Window positions, your spots, earnings, recipes and crafting goals stay shared by all your characters.
- The yellow dots from Find Minerals and Find Herbs are drawn by the game, and addons can't read them. VoidGather learns a spot when someone gathers it. The gathering HUD shows those dots anyway, because it uses your real minimap.
- In some zones the minimap can show a dark square right after you turn the HUD off. It redraws round as soon as you move.
- Sharing reaches players on your realm group who are online and running VoidGather.
- Your spots are saved per account and kept between sessions.

---

## Compatibility

- **WoW Forever**
- **WoW 12.1.5** (Midnight Season 2)
- Standalone — nothing else to install

---

*Part of the Void addon family by Vede · MIT licensed · [Source & bug reports](https://github.com/bughatti/voidgather) · [All Void addons](https://www.curseforge.com/members/bughatti/projects) · free M+ & raid player lookups at [voidscout.io](https://voidscout.io) · more at [tinkerline.io](https://tinkerline.io) · [Discord](https://discord.gg/7ZHmx7zMDh)*

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
- **Only your professions** — spots for professions you don't have stay hidden (lumber always shows); switch it off in the map menu
- **Click a pin for a waypoint** — Blizzard's waypoint and arrow, cleared when you arrive
- **Minimap pins** fade near the edge of the minimap so close spots stand out

### Skill-ups: where to level Herbalism and Mining
- **Pins show if they still give you skill**, in the profession window's colors: an **orange** outline always gives a point, **yellow** usually, **green** rarely, and **grey** never (grey pins fade). Black means no skill info, such as an older expansion's node
- **Uses your real Midnight skill** and the game's own skill thresholds for each node
- **Where to go**: the map menu shows your skill, what gives points right now, and a **Go:** button that sets a waypoint to the best known spot. `/vg best` does the same from chat
- **"Only nodes that give skill"** in the map menu hides the grey ones
- Turns itself off once you're maxed, so farming pins don't all go grey

### Shared with other players
- **Live sharing** — when another VoidGather player gathers a new spot on your realm, it shows up on your map
- **Zone catch-up** — entering a zone asks other players for the spots they know there
- **Easy to tell apart** — shared spots are smaller and faded, brighten once a second player confirms them, and become yours once you gather there
- **Hover a shared pin** to see who found it and when
- **Who's here** — entering a zone tells you how many other VoidGather players are in it (`/vg here` asks any time)
- **Turn sharing off** any time with `/vg share` or the map menu

### Gathering helpers
- **Session loot tally** — what you've gathered this session, with an hourly rate
- **Auto-switch Find Minerals / Find Herbs** (optional) — for miner-herbalists where only one tracker can run at a time; it only flips while you're moving and out of combat

### Map menu
- **A button on the world map** with your skill-ups and where to go, show/hide filters for mining, herbs, skinning and lumber (with counts for the zone), "only nodes that give skill", "only my professions", world map dots, minimap pins, auto-switch and sharing

---

## Slash Commands

| Command | What it does |
|---|---|
| `/vg` | Show all commands |
| `/vg best` | Waypoint to the best known spot for your Herbalism or Mining skill-ups |
| `/vg zone` | How many spots are known in this zone (yours and shared) |
| `/vg stats` | This session's gathered loot |
| `/vg reset` | Reset the session tally |
| `/vg mining` · `/vg herb` · `/vg skin` · `/vg lumber` | Show or hide that kind of pin |
| `/vg minimap` | Minimap pins on or off |
| `/vg track` | Auto-switch Find Minerals / Find Herbs on or off |
| `/vg share` | Share spots with other players on or off |
| `/vg here` | How many other VoidGather players are in your zone |
| `/vg net` | Check that sharing works on your realm, and see how many other VoidGather players are online there |

---

## Getting Started

1. Install with the CurseForge app, or copy the `VoidGather` folder into your game's `Interface/AddOns/` folder.
2. Restart WoW or `/reload`.
3. Turn on **Find Minerals** or **Find Herbs** from the tracking button by your minimap, and gather your first node — VoidGather says so in chat and pins it on your map.

---

## Privacy & Data

- **What's shared:** the kind of spot (mining, herb, skinning or lumber), the zone, its map position and the node's name. Nothing about your character, bags or gold.
- Other players see the character name that shared a spot, the same as any addon message.
- Shared spots only come from players' own gathers, never passed along second-hand, so one bad report can't spread.
- With sharing off, VoidGather sends and receives nothing.

---

## Good to Know

- The yellow dots from Find Minerals and Find Herbs are drawn by the game, and addons can't read them. VoidGather learns a spot when someone gathers it.
- Sharing reaches players on your realm group who are online and running VoidGather.
- Your spots are saved per account and kept between sessions.

---

## Compatibility

- **WoW Forever**
- **WoW 12.1.5** (Midnight Season 2)
- Standalone — nothing else to install

---

*Part of the Void addon family by Vede · MIT licensed · free M+ & raid player lookups at [voidscout.io](https://voidscout.io) · more addons & apps at [tinkerline.io](https://tinkerline.io) · [Discord](https://discord.gg/7ZHmx7zMDh)*

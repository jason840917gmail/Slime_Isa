# Game Guidelines

> **Status: living draft.** This document records the agreed design direction.
> Task order and status live in the [Game Roadmap](./GAME_ROADMAP.md).
> Updated 2026-09-29: it absorbed the useful parts of the former
> `BETA_PLAN.md`, which was removed.

## The Game In One Line

Slime Isa is a top-down action-adventure with crafting: a small slime explores,
fights, gathers, and rebuilds Slimeshire, and grows stronger through the gear
it crafts, not through experience levels.

## Core Loop

Explore and gather resources. Fight enemies for drops and access to dangerous
areas. Rebuild Slimeshire's crafting buildings. Craft stronger tools and
weapons, then tackle tougher enemies to obtain rarer materials.

Chapter 1 ("The Clearing", in Slimeshire Meadow, map `level-1`) is the
playable version of this loop today: gather loose wood, craft and place a
workbench, craft stone tools, clear the worm camp with a spear, defeat Fatty
One Eye for the green key, and open the Verdant Gate into Gloop Forest. Quests
guide each step and teach the next recipe.

**Release 1** is Chapters 1 and 2 as a free web build; its scope and order are
in the [roadmap](./GAME_ROADMAP.md#release-1-v01--the-target).

## Progression: Gear, Not Levels

Decided 2026-09-29. There are no XP, levels, or perks (removed in roadmap
Milestone 5). Base stats are flat (`character.player.stats`). The player grows
through:

- **Crafted gear:** weapon and tool tiers (wood → stone → iron → later
  materials) are the main power curve.
- **Goo Hearts:** collectibles that permanently raise max HP
  (`character.player.gooHeart.maxHpBonus`, 10 each), hidden in secrets and
  dropped by bosses. Exploration pays off in strength. Each heart has a unique
  ID and can be taken once per run.
- **Story-unlocked abilities:** quests and bosses teach abilities (Jump, Squash
  Slam, Stretch Lash, Teleport, and later ones), the same way they teach
  recipes. The Stretch Lash is a hook, not a weapon: light things come to the
  slime, heavy things pull the slime to them. Chapter 1's Worm Trouble teaches Jump; a locked ability says on the
  ability bar how it is earned.
- **Gulp forms:** temporary forms that change how the slime plays (see below).

Enemies are worth fighting for their drops, which gate recipes, and for access
to places, never for XP. Each region's difficulty is tuned to the gear a player
can have there, so grinding is never required. After Release 1, **Goo charms**
(equippable trinkets crafted from enemy materials) may bring back effects the
old perks gave, such as crit, life steal, and speed, as gear.

## Signature Mechanic: Gulp

The slime eats a Gulp material and takes its form for a while. Each form has a
clear look and exactly one rule.

- **One key, Q, is the slime's mouth, and no menu ever opens to eat.**
  - Tap Q near a Gulp spot to eat from the world. Right-clicking the spot does
    the same.
  - Hold Q for a quick wheel of carried Gulp materials; the game keeps running.
  - In a form, tapping Q away from a Gulp spot burps the form away.
  - Anywhere else, a tap only says how to gulp.
  - It was W until the controls moved to WASD and the mouse (roadmap 4.10).
- **Gulp spots** (a mossy boulder, a silk cocoon) never run out and look
  different from walk-over piles. Every Gulp puzzle has its spot beside it, so
  a puzzle never depends on what the player carries. Carried materials are for
  freedom: using a form in a fight, for a secret, or anywhere else.
- A form lasts **1 minute** to start with (a tunable constant). Eating a
  different material switches straight to that form; eating the same one at a
  Gulp spot resets the timer.
- New forms are tried in the dev-only `playground` map and enter chapter
  content only after the user accepts them as fun.
- **Release 1 forms:** **Heavy** (stone): no knockback, holds pressure plates
  down, breaks cracked ground to open hidden caverns, moves slower. **Sticky**
  (silk): crosses spider webs that would catch a normal slime.
- **Later forms:** **Glow** (crystal shard) lights dark caves; **Bouncy**
  (berry); biome forms such as ice and lava for later regions.
- Forms open traversal puzzles and secrets. A fight requires a form only when
  that fight exists to teach it.

Gulp replaces the old "slime forms" idea: one system, many forms, each form
added as data plus art.

## Home And Slimeshire

- The player's home stays in Slimeshire (Level 1) and never moves. Other maps
  can have their own homes with their own interiors, linked door to door.
- Any bed the player sleeps in becomes the respawn point.
- Placed furniture (starting with the workbench) persists per map.
- Home is not automatically safe: map conditions and nearby enemies determine
  whether it is safe to use.

**Rebuild Slimeshire.** The crafting buildings are ruined buildings in town.
Restoring one (a quest and materials) turns it into a station the player uses
directly and unlocks its recipes; no NPC runs it. Upgrading a building unlocks
its next recipe tier. Slimeshire visibly grows as the story advances.

## Crafting And Buildings

Simple survival recipes may be portable. Weapons, advanced tools, building
pieces, and other progression recipes require the right station. Every station
uses one shared crafting popup and one recipe authority, filtered by station
and tier.

| Station | Crafts | Main inputs | When |
|---|---|---|---|
| **Placeable workbench** | Chapter 1 tier-1 tools and spears | Wood, stone | Today |
| **Workshop** | Everything the workbench does, plus weapons, tools, bombs, storage, building parts, and repairs | Wood, stone, metal bars, enemy materials | Release 1: restored in Chapter 1 (The Old Workshop, optional), tier 2 in Chapter 2 |
| **Forge** | Smelts ore into metal bars, later alloys; never outputs weapons | Ore and fuel | Release 1 (Chapter 2) |
| **Kitchen** | Food, healing and buff meals, potions, and antidotes | Forage, fish, crops, monster materials | After Release 1 |
| **Builder's table** | Furniture, storage, and defenses for homes | Building parts, bars | After Release 1 |

- Metal gear goes ore → Forge (bars) → Workshop.
- A station lists the recipes of the station that builds on it as locked ("At
  the Workshop"), so the player knows what restoring it would give.
- The workbench recipe itself, Slime Tonic, and Berry Basket stay portable so a
  fresh save can never softlock.
- The Alchemy table is retired: potions belong to the Kitchen and bombs to the
  Workshop. A loom or enchanting station are examples only, not committed
  direction.

## Coins

Coins are earned from quests and enemies and spent after Release 1 at a
Slimeshire shop and on equipment repairs. Restoring buildings costs materials,
not coins.

## Resource Progression

Tool-gated and enemy-gated progression work together. The player starts
unarmed, gathers loose wood and stone, and crafts basic harvesting tools; tree
and stone nodes need the matching stone tool. In Chapter 2, a Reinforced
Pickaxe made with an enemy-only material harvests iron, and the Forge turns
iron into bars for metal gear. Later regions add rarer materials.

Harvested trees and rock nodes grow back after a long timer
(`resources.respawnMs`, roadmap 5.5), checked when their map loads. Loose
starter piles and quest rewards keep the chain softlock-free.

## Recipe Discovery

- Chapter 1: quest rewards teach recipes (`learnedByQuest` recipes stay
  visible but locked until learned).
- From Chapter 2: restoring or upgrading a building unlocks its recipes.
  Quests may still teach special recipes.

## World

- Areas are authored maps joined by edge exits and doors. Production never
  generates worlds procedurally.
- Each chapter's region brings one new resource goal, at least one new enemy,
  and one boss.
- Region order: **Slimeshire Meadow** (Chapter 1), **Gloop Forest**
  (Chapter 2), **Crystal Caverns** (Chapter 3 candidate). Later biome ideas:
  Sticky Swamp (slow, poison, rain), Frostpeak (ice physics, snow), and Volcano
  Ridge (lava, burn, the finale). The authored but unconnected `icege`,
  `emberleef`, and `hot` maps are candidates for them.

## Enemies And Bosses

- A new enemy needs authored art, an animation set, behavior, and validation
  before it enters the roster. Archived concepts are in
  [Future Enemy Types](./task/ideas/open/future-enemy-types.md).
- **The boss model** is Fatty One Eye: a telegraphed signature attack, a boss
  bar, an arena leash, a guarded reward, persisted defeat, and a timed respawn.
  Telegraphs make the dodge a skill, not a stat.
- Ordinary enemies keep a territory: they notice the slime by sight (walls,
  houses and trees hide it) or when hit, chase within a leash that shrinks
  the farther they are from home, search for three seconds where they lost
  sight of the slime, then walk home and heal. Standing just outside a camp
  and poking its enemies never works.
- Fatty One Eye is the finished Chapter 1 boss; his fight does not change.
- Each boss should teach something: a weapon, a form, or a way to move.

## Game Feel

- Audio shapes perceived quality more than any single visual.
- Hit-stop, screen shake, and squash and stretch are most of a slime's feel.
  Every hit, landing, pickup, and Gulp gets feedback.
- The Goo Trail, a passive ability a later quest teaches, leaves fading goo
  that slows enemies crossing it.
- Accessibility from day one: every shake, flash, and strong motion respects
  the reduce-motion setting, and status colors must stay readable for
  colorblind players.

## Art Style

**Cozy storybook woodland, hand-painted miniatures**, defined from the NPC and
interior sprites. Every new asset follows the
[art style guide](./assets/visual-style-guide.md).

## Controls

The left hand stays on WASD and the right hand stays on the mouse (agreed
2026-09-30, roadmap 4.10;
[design](./superpowers/specs/2026-09-30-simple-controls-design.md)):

- **The mouse:** left click uses (attack, chop, mine); right click interacts
  with what the pointer is on.
- **Abilities:** the story teaches them, and they sit on Space (Jump) and the
  number keys (1 Dodge, 2–4 the rest). Those that aim, aim at the pointer.
- **Shift is only ever held** (sprint), and Ctrl and Alt are never used.
- **Key names:** every key name the player reads comes from one binding
  table, so content text never names a key.

## UI Style

On 2026-09-04 the in-world HUD direction was approved as **artwork-first**: the
world stays visible, and the HUD, minimap, and weapon hotbar use transparent
interiors with restrained outlines, text shadows, and state accents instead of
opaque dark boxes. Inventory and crafting are excluded and get their own
redesign; the ability bar's skin is deferred. Details:
[World HUD Artwork-First Presentation](./superpowers/specs/2026-09-04-world-hud-artwork-first-design.md),
refining the [Game UI Visual Skin System](./superpowers/specs/2026-09-03-game-ui-visual-skin-design.md).

## Scope Discipline

- New ideas go to the roadmap's
  [parking lot](./GAME_ROADMAP.md#after-release-1--idea-parking-lot), not into
  a Release 1 milestone.
- Scene Studio is feature-frozen until Release 1 ships: bug fixes and blockers
  only.
- The Android app in `MobileVersion/` is frozen until after Release 1.
- New art is added only with an authored-scene home; reuse existing atlases and
  generated scene sets first.

## Open Questions

- Does equipment wear out? Coin-paid repairs (below) need a durability rule.
- How long is the resource respawn time for trees, rocks, and ore? (Provisionally 10 minutes, `resources.respawnMs`.)
- What are the safety, recovery, and storage rules for homes?
- What is the Chapter 2 boss's final design?
- What are the material tiers after iron, and where does each appear?
- How many recipes should each station have, and how fast should progression
  advance?
- Where will Release 1 be published?

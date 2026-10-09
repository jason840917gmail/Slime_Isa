# Game Guidelines

> **Status: living draft.** This document records the agreed design direction.
> Task order and status live in the [Game Roadmap](GAME_ROADMAP.md).
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
in the [roadmap](GAME_ROADMAP.md#release-1-v01--the-target).

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
- **Story-unlocked abilities:** quests and bosses teach abilities (Squash Slam,
  Stretch Lash, Teleport, and later ones; the jump was removed on 2026-10-08),
  the same way they teach recipes. The Stretch Lash is a hook, not a weapon:
  light things come to the slime, heavy things pull the slime to them. Chapter
  1's The One-Eyed Guardian teaches Squash Slam (Fatty One Eye's Pearl will,
  once it exists); a locked ability says on the ability bar how it is earned.
  Learning an ability is a moment of its own, the ability ceremony (built
  2026-10-09, roadmap 4.13): the world dims around the slime, a goo bubble
  with the ability's icon rises out of it, a card says what the ability does
  and its key, and the slime gulps the bubble back down. Items get their
  ceremony later.
- **Gulp forms:** forms taken by swallowing essences, which are found and spent
  (see below).

Enemies are worth fighting for their drops, which gate recipes, and for access
to places, never for XP. Each region's difficulty is tuned to the gear a player
can have there, so grinding is never required. After Release 1, **Goo charms**
(equippable trinkets crafted from enemy materials) may bring back effects the
old perks gave, such as crit, life steal, and speed, as gear.

## Signature Mechanic: Gulp

**Redesigned 2026-10-08** (owner). This replaces the one-minute forms of
2026-09-29 and the armors of 2026-10-02. "The build today" below says what is
built (roadmap 7.5–7.7, 8.12 and 8.13).

The slime sucks things into its body, then throws them or swallows them.
Swallowing an **essence** turns the slime into that essence's form. Each form
has a clear look and exactly one rule.

- **Suck (hold Q).** At short range the slime pulls in an essence, or a light
  object made to be lifted: pots and 60-odd other light things for every kind
  of place, such as a crate in a kitchen, a rune urn in a dungeon, an ice
  block in the snow or a pumpkin in a garden. Pots are fine as long as they
  are the game's own, not copies of Zelda's (owner, 2026-10-09). It never
  sucks in a live enemy. A tap with nothing in reach is only a puff. Two
  upgrades later let it suck in heavy rocks, like Zelda's gloves, and each
  gets the full item ceremony.
- **Holding.** What was sucked in sits inside the slime, which swells up and
  waddles, at 70% of its speed (owner, 2026-10-09). While it holds something it
  cannot attack or use abilities; it can only throw or swallow.
- **Throw (Q).** It spits a light thing as a projectile, aimed at the pointer
  (where the slime faces in the keys-only scheme). The thing breaks where it
  lands, by what it is made of: a pot shatters into shards, a crate splinters,
  a kettle clangs, a pumpkin splats, each with its own sound. It hits for
  damage, harder for metal and stone. An essence is never thrown (owner,
  2026-10-09): Q spits it out whole a step ahead, where it stays, as a form
  released with Swallow does.
- **Swallow** (key 1). A learned ability:
  Tom teaches it in Chapter 2, with the full ceremony, and it takes the jump's
  old place on the HUD. Swallowing an essence gives its form. Only essences
  can be swallowed, not pots, rocks or other things.
- **Forms.** One at a time, with no timer and no energy cost: the essence is
  the cost. A form lasts until:
  - a hit pops it out as a blob the slime can suck back for a moment. The pop
    takes the hit's side effect, so the Matron's lash pops the silk instead of
    trapping the slime;
  - the slime swallows another essence (the old form pops out);
  - the slime presses Swallow with nothing held. The essence drops out whole,
    not thrown and not broken, and it stays on the ground until it is taken
    again.
  A form, and anything held, survives doors and saves. A new form gets no
  ceremony: the challenge is finding essences.
- **Essences** are consumable items.
  - Some beaten enemies drop one: by chance for common enemies, always for
    special ones. A dropped essence fades after about 30 s.
  - Some are placed in maps, and those come back when the map is entered again,
    so a puzzle can never be lost by wasting its essence. Today's Gulp spots
    become placed essences.
  - Walking over an essence never picks it up: Interact puts it in the bag,
    Suck puts it in the slime. From the bag, "Use" puts it back in the slime.
    Recipes can use essences.
- **Release 1 forms:** **Stone** (Heavy: no knockback, holds pressure plates
  down, moves slower; a Squash Slam in it breaks cracked ground), dropped by the
  **Clod Stomper**, a new enemy. **Silk** (Sticky: passes the spider webs that
  trap a normal slime), dropped by spiders.
- **Swim** crosses deep water. Its essence will drop from an aquatic monster
  (not designed yet) and can be placed by hand anywhere. The frog on its lily
  pad is decoration now.
- **Later forms:** **Glow** lights dark caves; **Bouncy**; biome essences such
  as ice and lava for later regions. New enemies are designed around the
  essence they drop.
- **The Roll replaces the Dodge** (key 2; built 2026-10-09, roadmap 7.7). It
  feels like Zelda's Pegasus Boots dash (owner, 2026-10-09). The slime curls
  into a ball and spins in place for about a quarter second, laying skid
  streaks and kicking dust like screeching tires; it does not move and is not
  yet safe from hits. Then it shoots off in a straight line toward the
  pointer (the held movement keys or the facing without one), fast at first
  and easing down, safe from hits for 0.4 s from the launch. It cannot turn
  or slide sideways. Holding 2 keeps it rolling for as long as the key is
  held and energy lasts; only this held part costs energy. Running into a
  wall, a rock or an enemy is a bonk: the screen shakes, things nearby
  wobble, an enemy there is hit, and the slime bounces back with a little
  hop. The slime learns all of it at once, with no later upgrade (owner,
  2026-10-09). The owner still judges the feel.
- **Keys (owner, 2026-10-09):** Q sucks and throws; 1 swallows; 2 rolls;
  Stretch Lash, Squash Slam and Teleport move to 3, 4 and 5; interact stays on
  right-click (W in the keys-only scheme).
- New forms are tried in the dev-only `playground` map and enter chapter
  content only after the user accepts them as fun.
- Forms open traversal puzzles and secrets. A fight requires a form only when
  that fight exists to teach it.

### The build today

Built 2026-10-09 as a playground prototype (roadmap 7.5): suck, hold, throw
and Swallow; essences on the ground, in the bag and from spider drops; the hit
pop and spitting out; 67 kinds of things to lift, from pots to pumpkins, each
breaking by its material with its own sound (the playground's liftable
gallery shows them all); the Stone, Silk and Swim forms. The old Gulp spots
are placed essences now, and the frog is decoration. The same day brought the
art, which the owner accepted: the slime's suck, spit and full-slime clips
(the held thing shows inside, on its belly), the Roll's ball, the first three
liftables and the essences (on the ground, in the mouth and in the bag). The
64 newer liftables wait for the owner. The suction lines are still
placeholder streaks. The new sounds (Sound Picker round 5) wait for the
owner's picks.

Also built 2026-10-09, waiting for the owner:

- **Tom** teaches Swallow in Chapter 2 (roadmap 8.13): Mossy's quest Tom in
  the Web sends the slime to cut him out of a web in the forest's south-west
  spider thicket, and he gives Swallow at the camp, with the ability
  ceremony. Beyond the Verdant Gate no longer teaches Swallow.
- **The ceremony** (roadmap 4.13) plays for every active ability the slime
  learns, the first time each weapon, tool and key comes into the bag, and for
  every Goo Heart: the game pauses, the thing rises out of the slime in a goo
  bubble with light rays and a fanfare, a card says what it is and how to use
  it, and any key lets the slime gulp it back. Bags, heart quarters and story
  items will end in it when they are built.
- **The Clod Stomper** (roadmap 8.12) crouches behind a ring telegraph, hops
  and slams, breaking cracked ground near its feet, and always drops a stone
  essence. It camps by the iron hollow and the cracked clearing in Gloop
  Forest, and in the playground's enemy pen.
- **The Roll** (roadmap 7.7), above.

Not built yet: the lift upgrades and the rest of the art (the roadmap's
Milestone 7 assets).

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
| **Placeable workbench** | Tools and spears in Chapters 1 and 2, including the Reinforced Pickaxe and iron gear | Wood, stone, iron bars, enemy materials | Today |
| **Workshop** | An upgrade of the workbench: everything it does, plus heavier weapons, bombs, storage, building parts, and repairs | Wood, stone, metal bars, enemy materials | After Chapter 2, once the Forge makes bars (moved 2026-09-30) |
| **Forge** | Smelts ore into metal bars, later alloys; never outputs weapons | Ore and fuel | Release 1 (Chapter 2) |
| **Kitchen** | Food, healing and buff meals, potions, and antidotes | Forage, fish, crops, monster materials | After Release 1 |
| **Builder's table** | Furniture, storage, and defenses for homes | Building parts, bars | After Release 1 |

- Metal gear goes ore → Forge (bars) → workbench in Chapter 2; the Workshop
  takes over the heavier gear after Chapter 2.
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
  [Future Enemy Types](task/ideas/open/future-enemy-types.md).
- **The boss model** is Fatty One Eye: a telegraphed signature attack, a boss
  bar, an arena leash, a guarded reward, persisted defeat, and a timed respawn.
  Telegraphs make the dodge a skill, not a stat. A boss left alone outside its
  arena for a minute heals to full (`arenaRecoveryMs`), so it cannot be worn
  down in visits. Every landed hit flashes and shows its damage, and a weapon
  a boss refuses says so.
- Ordinary enemies keep a territory: they notice the slime by sight (walls,
  houses and trees hide it) or when hit, chase within a leash that shrinks
  the farther they are from home, search for three seconds where they lost
  sight of the slime, then walk home and heal. Standing just outside a camp
  and poking its enemies never works.
- Fatty One Eye is the finished Chapter 1 boss. Since the 2026-10-01 playtest
  his eye (the only place he takes damage) follows the drawn eye in every
  animation, and every spear reaches it.
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
[art style guide](assets/visual-style-guide.md).

## Controls

The left hand stays on WASD and the right hand stays on the mouse (agreed
2026-09-30, roadmap 4.10;
[design](archive/phaser/superpowers/specs/2026-09-30-simple-controls-design.md)):

- **The mouse:** left click uses (attack, chop, mine); right click interacts
  with what the pointer is on. Tools never switch by themselves: the weapon in
  hand swings, and the four-slot belt switches with the mouse wheel or a click.
- **Abilities:** the story teaches them, and they sit on the number keys
  (since 2026-10-09: 1 Swallow, 2 the Roll, 3 Stretch Lash, 4 Squash Slam,
  5 Teleport); Q is the mouth (suck and throw). Space has been
  free since the jump was removed (2026-10-08). Those that aim, aim at the
  pointer.
- **Shift, Ctrl and Alt are not used.** Shift sprinted until 2026-10-08; the
  Roll on 2 took its place (roadmap 7.7).
- **Key names:** every key name the player reads comes from one binding
  table, so content text never names a key.

## UI Style

On 2026-09-04 the in-world HUD direction was approved as **artwork-first**: the
world stays visible, and the HUD, minimap, and weapon hotbar use transparent
interiors with restrained outlines, text shadows, and state accents instead of
opaque dark boxes. Inventory and crafting are excluded and get their own
redesign; the ability bar's skin is deferred. Details:
[World HUD Artwork-First Presentation](archive/phaser/superpowers/specs/2026-09-04-world-hud-artwork-first-design.md),
refining the [Game UI Visual Skin System](archive/phaser/superpowers/specs/2026-09-03-game-ui-visual-skin-design.md).

## Scope Discipline

- New ideas go to the roadmap's
  [parking lot](GAME_ROADMAP.md#after-release-1--idea-parking-lot), not into
  a Release 1 milestone.
- Levels and scenes are built in the Godot editor; no custom editor tooling until
  Release 1 ships (Scene Studio was retired with the Phaser app on 2026-10-05).
- The old Android prototype (`MobileVersion/`) was removed on 2026-10-04;
  Android becomes an export of the Godot project after Release 1
  ([GODOT_MIGRATION.md](GODOT_MIGRATION.md)).
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

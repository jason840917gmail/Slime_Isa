# Slime Isa — Roadmap to Beta

The long-range plan that takes the original tech demo (a single 54×54 meadow
with collectibles) to a **beta-state action-adventure**: a multi-biome world
with Zelda-style area transitions, combat, enemies, bosses, quests, leveling,
unlockable abilities and weapons, and full game feel.

**Ownership.** This file keeps the beta *target* and the content and feel
ideas behind it. Task status, ordering, and acceptance checks live in the
[Game Roadmap](./GAME_ROADMAP.md); design direction lives in the
[Game Guidelines](./GAME_GUIDELINES.md). When a phase below starts, add its
tasks to the roadmap instead of expanding them here.

**Architecture note.** The original phase plans named files such as
`src/game/data/*.json`, `AreaScene`, `terrainNoise.ts`, and procedural enemy
textures. The game instead moved to authored maps and universal scenes (see
[Architecture](./ARCHITECTURE.md)): content lives in `src/game/content/`,
every world, entity, UI, and audio surface is an authored scene edited in
Scene Studio (`?studio=scenes`), and production never generates worlds
procedurally. Build new phases on that structure.

## Status Summary (2026-09-29)

| Phase | State | What exists |
|---|---|---|
| 0. Architecture | Done, superseded | `EventBus`, `GameState`, `SaveSystem`, centralized input; the universal scene refactor replaced the planned systems split. `WorldScene` is still a large composition root |
| 1. Player core | Done | HP, XP and levels, energy, perks and the level-up modal, slot inventory, status effects (burn, poison, slow, sticky, bouncy, frenzy), respawn at the last bed |
| 2. Combat, abilities, weapons | First slice | Six-slot 1–6 weapon hotbar, combo/hitbox system, dodge, abilities (jump, teleport, Squash Slam, Stretch Lash), weapons listed below |
| 3. Enemies | First slice | Worm Brawler, Worm Swordsman, Worm Archer, Slime Spider; authored spawn and safe areas; drops, contact damage, knockback, telegraphs |
| 4. World | First slice | Authored maps joined by exits: Slimeshire Meadow (`level-1`) → Gloop Forest → Crystal Caverns, plus `slime-home` and `mushroom-home` interiors; area title cards, world map, minimap. `icege`, `emberleef`, and `hot` are authored but not reachable from Level 1 |
| 5. Quests | First slice | Chapter 1 — The Clearing: six NPC quests with dialogue, journal, tracker, markers, and quest-taught recipes |
| 6. Bosses | First slice | Fatty One Eye guards the green key in the Meadow: leap telegraph, boss bar, arena leash, guarded chest, timed respawn |
| 7. Dungeons, puzzles, crafting | Crafting only | Recipe crafting UI and the placeable workbench; crafting buildings are planned in the roadmap. No dungeon or puzzle yet |
| 8. Meta systems | Partial | Named saves, recovery autosave, save schema v9; audio in progress (roadmap milestone A). No day/night, weather, or VFX presets |
| 9. UI/UX shell | Partial | Escape closes the topmost surface; Esc opens sound settings. No title, pause, game-over, or onboarding screens |
| 10–12. Juice, content, hardening | Not started | Ideas and targets below |

## 1. Beta Definition (the target)

A beta build is **feature-complete** and **fun loop-complete**:

- **Loop:** explore → fight → collect → level up → unlock ability/weapon → tackle harder area → boss → progress quest → repeat.
- **Content:** ≥ 6 distinct biomes with Zelda-style edge transitions, ≥ 8 enemy types, ≥ 4 bosses, ≥ 12 quests, ≥ 8 abilities, ≥ 6 weapons, ≥ 1 dungeon.
- **Systems:** health/death, combat, XP/leveling, ability tree, weapon upgrade, inventory, quests/journal, save/load, audio, day/night, settings, pause, title screen, game-over/respawn.
- **Feel:** particles, screen shake, hit-stop, squash/stretch juice, tweened UI, floating damage/loot numbers, boss intro cinematics.
- **Polish:** balanced economy and difficulty curve, stable 60 fps on the target world size, no softlocks.

Today: 3 connected outdoor biomes, 4 enemy types, 1 boss, 6 quests,
4 abilities plus dodge, and 10 weapons and tools.

## Phase 2 — Combat, Abilities & Weapons

Remaining goals: charge attacks, an ability tree spent from level-up points,
weapon upgrade tiers, and the missing weapons and abilities.

### Weapons

Shipped (`src/game/content/weapons/`): Goo Gauntlet, basic sword and spear,
Wooden and Stone Spear, Slam Hammer, Wooden and Stone Axe, Pickaxe and Stone
Pickaxe. Fresh runs start unarmed; starter gear is crafted.

Still ideas:

1. **Bouncy Bow** (quest) — ranged, arrows bounce off walls.
2. **Sticky Whip** — pulls enemies in, applies sticky.
3. **Bubble Wand** (quest) — AoE bubbles, applies slow.

### Abilities (8 target)

Shipped: Jump, Teleport, **Squash Slam** (AoE shockwave), **Stretch Lash**
(long-range whip), and the dodge roll.

Still ideas: **Slime Split** (three seeking mini-slimes), **Bouncy Bubble**
(projectile-reflecting shield), **Fizzy Frenzy** (attack and move speed buff
that drains energy), **Sticky Trap** (rooting puddle), **Geyser Leap**
(vertical slam with AoE knockup).

## Phase 3 — Enemies & AI

Shipped roster: Worm Brawler, Worm Swordsman, Worm Archer, and Slime Spider.
Earlier procedural concepts (Blob, Spike Slime, Bouncer, Caster, Swarmer,
Armored Slime, Mimic, Sticky Spider-Slime, The Blobfather) are archived in
[Future Enemy Types](./task/ideas/open/future-enemy-types.md); each returns
only with authored art, a visual set, behavior, and validation.

Remaining goals: reach ≥ 8 types, population caps and off-screen despawn
where needed, respawn tied to a day cycle, and enemy-gated materials (roadmap
milestone 7).

## Phase 4 — World Expansion & Biomes

Areas are authored maps connected by edge exits, loaded through
`MapRepository` with a queued transition; walls are placed forest-tree and
crystal-cluster scenes.

### Biomes (6 minimum)

1. **Meadow** (Slimeshire Meadow) — town, NPCs, Chapter 1. *Authored.*
2. **Gloop Forest** — dense trees; first area past the Verdant Gate. *Authored.*
3. **Crystal Caverns** — crystal-cluster walls. *Authored.*
4. **Sticky Swamp** — slow movement, poison, spider-slimes, rain.
5. **Frostpeak** — ice physics, snow weather.
6. **Volcano Ridge** — lava damage, burn; gates a late boss.

Remaining ideas: several areas per biome, fast-travel shrines unlocked by
discovery, day/night effects on enemy density, and the shallow/deep water and
swimming tasks in the roadmap (E.3, E.4).

## Phase 5 — Quests, Missions & Journal

The quest engine supports collect, kill, talk, craft, place, boss, and
discover objectives with live producers; escort, activate-object, and
survival objectives have contracts but no gameplay producer yet. See the
[Quest authoring guide](./knowledge/quest-authoring-guide.md).

Quest types to reach ≥ 12 quests:

- **Hunt:** "Defeat 10 worms in Gloop Forest".
- **Fetch:** "Bring 5 sticky silk to the swamp hermit".
- **Escort:** "Walk an authored NPC safely across the caverns".
- **Boss-gate:** "Clear the Volcano Ridge camp" → unlocks a boss arena.
- **Collection:** "Discover all 6 shrines".
- **Crafting:** quests that teach building and weapon recipes.

A main line of about five steps per chapter gates boss progression; side
quests stay optional.

## Phase 6 — Bosses

Fatty One Eye is the shipped first boss and the model for the rest: a
telegraphed signature attack, a boss bar, an arena leash, a guarded reward,
and persisted defeat. Remaining boss ideas, one per major area:

1. **Crystal Colossus** (Caverns) — armored, weak to hammer; laser sweep and
   projectile fan; teaches weapon switching.
2. **Swamp Matriarch** (Swamp) — webs and poison, summons spider-slimes;
   teaches status effects and the bubble shield.
3. **Magma Monarch** (Volcano, finale) — lava waves, enrage at 30%,
   multi-phase; gates the beta's end.

Goals still open: HP-threshold phases, intro name cards and camera pans, a
victory sequence, and a unique weapon or ability drop per boss.

## Phase 7 — Dungeons, Puzzles & Crafting

Crafting buildings (Workshop, Forge, Kitchen, Builder's table) are planned in
the roadmap. Dungeons and puzzles (locked doors, keys, switches, push blocks,
a mini-boss) must be authored map content, never injected by `WorldScene`.
No Crystal Caverns dungeon expansion is planned.

## Phase 8 — Meta Systems: Save, Audio, Day/Night, Weather, VFX

- **Save:** done (named saves, per-map progress, and a recovery autosave
  written on map entry, after state changes, and on page hide).
- **Audio:** tracked as roadmap milestone A (music per area, ambience,
  ducking).
- **Day/night:** an 8-minute day with a tint overlay; enemies stronger at
  night; NPC schedules may react.
- **Weather:** rain (swamp), snow (frost), ash (volcano), with gameplay hooks
  such as rain extinguishing burn.
- **VFX presets:** pooled particles (hit spark, slime splash, roll dust, coin
  sparkle, level-up burst), shake presets, and hit-stop on heavy hits.

## Phase 9 — UI/UX: Title, Pause, Settings, Game Over, Onboarding

- Title screen: Play, Continue, Settings, Credits, version.
- Game over: retry from the last bed or save, with a short stats summary.
- Pause menu: Resume, Journal, Inventory, Map, Settings, Save & Quit.
- Settings beyond sound: screen shake, reduce motion, autosave, key rebinding.
- Item and ability tooltips, stacking notifications, and contextual control
  hints that fade after first use.

Milestone: boot → title → new game → play → die → retry → pause → settings →
quit → title → continue works end to end.

## Phase 10 — Game Feel & Juice

- **Squash and stretch** on land, jump, and hit, driven by events.
- **Hit-stop** and **screen shake** calibrated per event; respect reduce motion.
- **Particle bursts** on hit, crit, level-up, loot, and boss death.
- **Floating text** colored by damage type.
- **Camera feedback:** zoom out on boss entry, zoom in on level-up.
- **Slime forms** (signature mechanic): Ice, Lava, Sticky, and Bubble forms
  tied to biomes, each gated by a quest and opening traversal puzzles.
- **Mount:** a tameable creature to ride.
- **Combo meter** with small coin/XP multipliers.
- **Hidden secrets:** breakable-rock caves, heart containers, stamina fruits.
- **Photo mode** and authored joke writing in NPC dialogue.

## Phase 11 — Content Authoring Pass

Fill the systems with authored content: all biomes and their areas, 8+
enemies with variants, 6+ weapons with upgrade tiers, 8 abilities and their
tree, 12+ quests (about 5 main and 7 side), 4 bosses, about 12 recipes and 25
items, NPC dialogue, and one dungeon. Milestone: a title-to-final-boss
playthrough of 2–4 hours with no placeholder text.

## Phase 12 — Beta Hardening

- **Balance:** XP curve, coin economy, enemy damage per area, boss tuning,
  drop rates.
- **Performance:** pooling, culling, per-area enemy caps; 60 fps on a mid
  laptop.
- **Controls:** gamepad support, persisted rebinding, on-screen hints.
- **Accessibility:** reduce motion, colorblind-safe status colors, text size,
  hold-to-confirm on destructive actions.
- **Bug sweep:** no softlocks on death, no falling through area edges, no
  duplicate key items.

Milestone (beta): every phase green, balance done, 60 fps met, saves robust,
full menu loop, gamepad and accessibility options working, no known
softlocks. Tag `v0.9.0-beta`.

## Things You Might Miss

- **Audio shapes perception of quality** more than any single visual.
- **Hit-stop, screen shake, and squash/stretch** are most of the game feel for
  a slime.
- **Slime-form transformations** tie exploration, abilities, and puzzles into
  one signature mechanic.
- **Companions** must use authored NPC definitions and explicit placement.
- **A mimic** can be both a joke and an enemy.
- **Telegraphed boss attacks** make the dodge a skill, not a stat.
- **Reduce motion and accessibility** from day one — cheap now, expensive
  later.
- **Debug overlay and cheats** (spawn enemy, give XP, unlock area) for daily
  balancing.
- **Heart-container and stamina-fruit collectibles** make exploration
  self-rewarding.

## Risk Register

| Risk | Mitigation |
|---|---|
| World too big → perf | Pools, despawn, and per-area maps rather than one giant grid |
| Combat feels floaty | Hit-stop, shake, and squash on every event; telegraphs for fairness |
| Content authoring bottleneck | Authored scenes and JSON content in Scene Studio; debug shortcuts to any area or boss |
| Save corruption | Schema versioning, migrations, independent named saves, recovery autosave |
| Scope creep | Each roadmap milestone is a playable build |
| Art asset cost | Reuse atlases and generated scene sets (interiors, props, grounds); add art only with an authored-scene home |

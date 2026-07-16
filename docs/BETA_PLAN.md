# Slime Isa — Roadmap to Beta

A drastic, end-to-end upgrade plan that takes the current tech-demo (a single
54×54 meadow with wandering friends, a shop, and collectibles) to a **beta-state
action-adventure** with a large multi-biome world, Zelda-style area transitions,
combat, enemies, bosses, missions, leveling, unlockable abilities & weapons, and
full game feel.

The plan is ordered so each phase is independently shippable and testable. Every
phase lists **new files**, **changed files**, **concrete tasks**, and a
**milestone** you can play and verify.

## Implementation Progress

Last updated: 2026-06-23

Completed so far:
- Phase 0 foundation is functionally in place: `EventBus`, `GameState`, centralized input, save handoff, and extracted house/HUD-style systems exist, though `WorldScene` still needs later cleanup.
- Phase 1 player core is in place: HP, XP, levels, energy, perks, inventory, status effects, respawn, level-up modal, health bar, ability bar, and inventory actions.
- Phase 2 combat is in place: starter weapon, combo/hitbox system, target dummy, attack/dodge, gated abilities, reach/arc perks, and life-steal perk.
- Phase 3 enemies are in place: enemy AI, spawner, projectiles, drops, contact damage, knockback/stun, safe home zone, and biome spawn tables.
- Phase 4 world expansion first slice is in place: Meadow, Gloop Forest, Crystal Caverns, biome tiles, area transitions, world map, discovered areas, and death return-to-home behavior.
- Phase 5 quest first slice is in place: quest tracker, quest journal, starter quest, event-driven progress, rewards, and quest persistence.
- Phase 6 boss first slice is in place: The Blobfather, boss intro/banner, boss health bar, reward, and defeated persistence.
- Phase 7 crafting first slice is in place: recipe system, crafting UI, consumable brewing, keyboard/mouse controls, and inventory material use/delete flow.

Left off here:
- Phase 7 is active.
- Latest completed slice: Crystal Caverns switch trial. Two pressure switches unlock a persistent crystal chest that rewards coins, XP, Crystal Shards, and a Slime Tonic.
- Verified: `pnpm build` passes and the dev server serves the new Crystal Trial source.

Next recommended slice:
- Continue Phase 7 by expanding the Crystal Caverns trial into a fuller dungeon loop: add a second puzzle, a key/locked gate, and a mini-boss or mimic chest before the major treasure.

---

## 0. Current State Audit (what we are building on)

| Area | Status | Notes |
|---|---|---|
| World | 54×54 tiles @ 64px = 3456×3456px, one biome | `terrainNoise.ts:2`, `worldTiles.ts:30` |
| Tiles | grass-a / grass-b / water / rock-wall | `worldTiles.ts:30` |
| Player | walk/boost/jump/4 emote anims, no health, no combat | `WorldScene.ts:160` |
| Friends | 84 wandering NPCs, ears/face/color variants, chat | `Friend.ts` |
| Houses | enter/sleep/coin reward, player + friend homes | `House.ts`, `WorldScene.ts:760` |
| Shop | buy boost speed / spawn friend | `ShopUI.ts` |
| Collectibles | purple berry (+5c), grape chip (+12c) | `WorldScene.ts:412` |
| Animations | 9 clips from `slime_normalized.png` (8×8 sheet) | `slimeAnimations.ts:28` |
| UI | HUD (coins/friends), minimap, chat, controls panel | `HUD.ts`, `Minimap.ts`, `ChatUI.ts` |
| Missing | health, combat, enemies, XP, levels, abilities, weapons, quests, inventory, save, audio, particles, day/night, menu, pause, death, dungeons, bosses, fast-travel | — |
| Tech debt | `WorldScene.ts` is 979 lines (monolith) | flagged in `AGENTS.md:20` |

---

## 1. Beta Definition (the target)

A beta build is **feature-complete** and **fun loop-complete**:

- **Loop:** explore → fight → collect → level up → unlock ability/weapon → tackle harder area → boss → progress quest → repeat.
- **Content:** ≥ 6 distinct biomes with Zelda-style edge transitions, ≥ 8 enemy types, ≥ 4 bosses, ≥ 12 quests, ≥ 8 abilities, ≥ 6 weapons, ≥ 1 dungeon.
- **Systems:** health/death, combat, XP/leveling, ability tree, weapon upgrade, inventory, quests/journal, save/load, audio, day/night, settings, pause, title screen, game-over/respawn.
- **Feel:** particles, screen shake, hit-stop, squash/stretch juice, tweened UI, floating damage/loot numbers, boss intro cinematics.
- **Polish:** balanced economy & difficulty curve, stable 60 fps on the target world size, no softlocks.

---

## Phase 0 — Architecture Refactor (foundation for scale)

Goal: break the `WorldScene` monolith into data-driven systems so the rest of
the plan can be built without constantly editing a 1000-line file.

### New files
- `src/game/core/EventBus.ts` — typed Phaser event emitter (`game.events`) for cross-system decoupling (e.g. `player.hit`, `enemy.died`, `quest.updated`, `area.enter`).
- `src/game/core/GameState.ts` — single source of truth for persistent player state: hp, maxHp, level, xp, coins, abilities, weapons, inventory, flags, current area, discovered areas. Emits change events.
- `src/game/core/SaveSystem.ts` — localStorage serialize/load of `GameState` + per-area flags; schema-versioned.
- `src/game/core/Input.ts` — centralized input manager (replaces the ad-hoc `Controls` type in `WorldScene.ts:23`). Adds rebinding + gamepad support later.
- `src/game/core/SceneManager` helpers — typed area-transition controller (Phase 4).
- `src/game/data/` — JSON-driven content folders: `areas.json`, `enemies.json`, `weapons.json`, `abilities.json`, `quests.json`, `items.json`, `biomes.json`.
- `src/game/registry/Registry.ts` — typed access to the Phaser `registry` so systems read/write state through one facade instead of scene properties.

### Changed files
- `src/game/scenes/WorldScene.ts` — strip to orchestration only. Move build/update logic into systems (below). Target ≤ 250 lines.
- `src/game/config.ts` — add `BootScene → TitleScene → AreaScene` scene order; add `physics.arcade.debug` toggle from a global.

### Concrete tasks
1. Create `EventBus` as a singleton `Phaser.Events.EventEmitter` with a typed event map.
2. Extract `GameState` as a plain serializable object + a `PlayerState` view used in-scene.
3. Replace direct `this.coins`/`this.boostBonus` reads in `WorldScene` with `GameState` access; keep HUD/subsystems subscribed via `EventBus`.
4. Extract from `WorldScene`: `HouseUI` (`WorldScene.ts:777`), `EnterPrompt` (`WorldScene.ts:851`), `SleepController` (`WorldScene.ts:889`) into `src/game/systems/HouseSystem.ts` (AGENTS.md:20 already flags this).
5. Move world building (`buildWorld`, `createWorldTile`, `placeHouses`, `findSpawnPoint`) into `src/game/systems/WorldBuilder.ts`.
6. Move player + controls into `src/game/systems/PlayerController.ts`.
7. Add a `src/game/data` loader in `BootScene` that validates JSON against TS interfaces.

### Milestone 0
The game runs **identically** to today, but `WorldScene` is thin and all state
flows through `GameState`/`EventBus`. No new gameplay yet — this is the runway.

---

## Phase 1 — Player Core: Health, Stats, Inventory, Leveling

Goal: turn the slime into a real RPG character.

### New files
- `src/game/systems/PlayerStats.ts` — derived stats: `maxHp, attack, defense, speed, critChance, energy/maxEnergy`.
- `src/game/systems/HealthSystem.ts` — damage/heal, i-frames after hit, knockback, death event.
- `src/game/systems/Inventory.ts` — slot-based inventory (items, consumables, key items, materials).
- `src/game/systems/LevelSystem.ts` — XP curve `xpForLevel(n) = 80 * n^1.5`, level-up event → heal + skill point + unlock check.
- `src/game/systems/StatusEffects.ts` — burn, poison, slow, sticky (can't move), bouncy (knockback up), frenzy (atk speed). Slime-themed.
- `src/game/ui/HealthBar.ts` — world-space bar above player + screen-space bar in HUD.
- `src/game/ui/InventoryUI.ts` — grid overlay (Tab key), drag-free, item tooltips.
- `src/game/ui/LevelUpModal.ts` — picks 1 of 3 perks on level up (roguelike-style).

### Changed files
- `src/game/HUD.ts` — add HP bar, XP bar, level, energy, minimap-adjacent buff icons. Current `HUD.ts:7` only shows coins/friends.
- `src/game/scenes/WorldScene.ts` — wire `HealthSystem` into update, handle death → `GameOverScene`.
- `src/game/Friend.ts` — give friends HP too (so they can be allies in Phase 6).
- `src/game/scenes/BootScene.ts` — generate HP-potion, energy-potion, material textures.

### Concrete tasks
1. Define stat growth table (per level: +12 maxHp, +2 atk, +1 def, +8 speed cap).
2. Implement damage pipeline: `incoming → defense mitigation → status modifiers → apply → i-frames 600ms → knockback → flash → event`.
3. Add floating combat text (`src/game/ui/FloatingText.ts`) — rises + fades, crits bigger/yellow.
4. Inventory supports stacking, categories, use-from-slot (potions).
5. Level-up modal pauses the game (`scene.pause`-style flag, not real Phaser pause so UI still animates).

### Milestone 1
Slime has HP, can take damage from a debug key, dies → respawns at last bed,
gains XP from a debug spawner, levels up with a perk pick, and potions heal.
Playtest: survive 5 debug hits, level to 3, spend 2 perks.

---

## Phase 2 — Combat, Abilities & Weapons

Goal: a satisfying combat layer using the existing `slime-trick`/`slime-roll`
animations plus new attack anims.

### New files
- `src/game/combat/Weapon.ts` — abstract weapon: `attack(player, dir)`, cooldown, damage, hitbox spec, animation key, VFX.
- `src/game/combat/Hitbox.ts` — transient arcade overlap zone with damage/knockback/status; pooled.
- `src/game/combat/ComboSystem.ts` — chain window (e.g. 3-hit combo with rising damage).
- `src/game/abilities/Ability.ts` — interface: `cooldown, energyCost, activate(player)`, unlocked flag.
- `src/game/abilities/AbilityTree.ts` — node graph; points spent in `LevelUpModal` unlock nodes.
- `src/game/abilities/library/` — one file per ability (see list below).
- `src/game/weapons/library/` — one file per weapon.
- `src/game/ui/WeaponWheel.ts` — switch weapon (1–6 keys or wheel).
- `src/game/ui/AbilityBar.ts` — bottom HUD slots with cooldown overlays (Zelda-ish).
- `src/game/data/weapons.json`, `src/game/data/abilities.json`.

### Changed files
- `src/game/slimeAnimations.ts` — add `slime-attack-side`, `slime-attack-up`, `slime-attack-down`, `slime-charge`, `slime-cast`, `slime-hurt`, `slime-die`. These need **new frames** — either extend the existing sheet or add a second sheet `slime_combat.png` (add to `asset/` and load in `BootScene`).
- `src/game/scenes/BootScene.ts` — load new combat sheet; generate weapon icon textures (sword/spear/bow/wand/hammer/whip).
- `src/game/config.ts` — controls panel: add attack (J / Left-Click), ability 1-3 (1/2/3), weapon wheel (Tab-Hold), charge (hold attack), dash-dodge (Shift).

### Weapons (6, unlock by level/quest/material)
1. **Goo Gauntlet** (starter, melee short) — punch combo, knockback.
2. **Splat Spear** (level 3) — long reach, thrust, pierces.
3. **Bouncy Bow** (quest) — ranged, arrows bounce off walls (slime physics).
4. **Sticky Whip** (level 6) — pulls enemies in, applies sticky.
5. **Bubble Wand** (quest) — AoE bubbles, applies slow.
6. **Slam Hammer** (boss drop) — slow, big AoE, breaks armor & terrain.

### Abilities (8, unlock via tree)
1. **Dash-Dodge** (roll with i-frames — upgrade existing roll, `WorldScene.ts:650`).
2. **Slime Split** — split into 3 mini-slimes that seek enemies (cooldown).
3. **Squash Slam** — AoE shockwave using existing squash anim (`slimeAnimations.ts:54`).
4. **Stretch Lash** — long-range tongue/whip from stretch anim.
5. **Bouncy Bubble** — shield that reflects projectiles.
6. **Fizzy Frenzy** — atk speed + move speed buff (energy drain).
7. **Sticky Trap** — lay a sticky puddle, roots enemies.
8. **Geyser Leap** — vertical slam → AoE knockup (great vs bosses).

### Concrete tasks
1. Implement `Hitbox` pooling (reuse instead of creating per swing — perf for many enemies).
2. Combo system: 3-input window, last hit applies knockback + bonus damage.
3. Charge attacks: hold → `slime-charge` → release for bigger hitbox + status.
4. i-frame dodge: existing roll gains 400ms invuln + dust particles.
5. Ability cooldowns read from `AbilityBar`; energy gated by `PlayerStats.energy`.
6. Weapon switching swaps animation set + stat multipliers.

### Milestone 2
Fight a debug-spawned dummy: 3-hit combo, dodge-roll through a hit, switch
weapon, pop Dash + Squash Slam, see floating damage + screen shake. No real
enemies yet — dummies only.

---

## Phase 3 — Enemies & AI

Goal: populate the world with threats that make combat matter.

### New files
- `src/game/enemies/Enemy.ts` — base class extending `Phaser.Physics.Arcade.Sprite`: hp, state machine, damage, drop table, stun, knockback resistance, contact-damage.
- `src/game/enemies/EnemyAI.ts` — reusable behaviors as composable states: `Idle`, `Wander`, `Chase`, `Attack`, `Flee`, `Ranged`, `Summon`, `Dead`.
- `src/game/enemies/EnemySpawner.ts` — area-aware spawner with population caps, despawn when far from player, respawn on day cycle.
- `src/game/enemies/Projectile.ts` — pooled projectiles (enemy + player).
- `src/game/enemies/library/` — one file per enemy type.
- `src/game/data/enemies.json` — stats per type and per area.
- `src/game/ui/EnemyHealthBar.ts` — world-space bar that fades when not recently hit.

### Changed files
- `src/game/scenes/BootScene.ts` — generate enemy textures (procedural, slime-family aesthetic: blob, spike, flyer, caster, brute, swarmer, armored, mimic).
- `src/game/scenes/WorldScene.ts` — add enemy group + collider/overlap wiring.
- `src/game/worldTiles.ts` — mark spawn-point rules (no spawn on water/rock, density per biome).

### Enemy roster (8 base types + variants)
1. **Blob** — slow wanderer, contact damage, easy. (starter)
2. **Spike Slime** — contact damage + retaliates when hit from front (must flank).
3. **Bouncer** — fast, telegraphed leap attack, knockback-prone.
4. **Caster Slime** — ranged bubbles, keeps distance, low hp.
5. **Swarmer** — spawns in packs, low hp, fast.
6. **Armored Slime** — high defense front, weak to hammer / back hits.
7. **Mimic Treasure** — looks like a collectible until approached (great scare/joke).
8. **Sticky Spider-Slime** — webs apply slow/sticky, ranged root.

### Concrete tasks
1. State machine with debug overlay (toggle from `config.ts` debug flag).
2. Telegraphs: red flash + windup animation before heavy attacks (so dodge-roll is meaningful).
3. Knockback + stun with recovery; knockback resisted by heavier types.
4. Contact-damage + i-frames prevent multi-hit per touch.
5. Drop tables: coins, XP orbs (auto-collect within radius), materials, rare items.
6. Population cap per area; despawn off-screen beyond a margin; respawn on day cycle.
7. Status effects from Phase 1 apply (burn spreads, poison ticks, sticky roots, etc.).

### Milestone 3
Walk an area with 15 enemies of mixed types; aggro, kite, combo, dodge, kill,
collect XP orbs + coins. Simulate a 2-minute fight; no frame drops; corpses
clean up.

---

## Phase 4 — World Expansion & Biomes & Zelda-style Area Transitions

Goal: a **much larger** world built from connected areas, not one giant tile grid.

### Architecture decision
Replace the single 54×54 grid with a **map of named areas**, each its own
`AreaScene` (or one `AreaScene` parameterized by an area id). Edge zones trigger
a Zelda-style transition: **fade/wipe → load neighbor → place player at the
matching edge spawn**.

### New files
- `src/game/world/Area.ts` — area definition: id, biome, size in tiles, neighbor links (N/E/S/W → target area + entry point), spawn rules, props, palette, music track, ambient color.
- `src/game/world/AreaLoader.ts` — builds an area from `areas.json` + `biomes.json`; generates tiles via per-biome noise; caches generated layouts.
- `src/game/world/Biome.ts` — biome descriptor: tile set, noise params, decoration density, enemy pool, weather, ambient light, water color.
- `src/game/world/AreaTransition.ts` — handles edge-zone overlap → fade → swap scene/area → spawn at entry.
- `src/game/data/biomes.json`, `src/game/data/areas.json`.
- `src/game/ui/AreaTitleCard.ts` — “Forest of Goo” banner on entry (tween in/out).

### Biomes (6 minimum)
1. **Meadow** (starter, current art) — peaceful, slimes, friends, tutorial.
2. **Gloop Forest** — dense trees, spike slimes, casters; first combat area.
3. **Crystal Caverns** — underground, armored + swarmers; torch-light radius.
4. **Sticky Swamp** — slow movement, poison, spider-slime, weather: rain.
5. **Frostpeak** — ice physics (low friction), bouncers, snow weather.
6. **Volcano Ridge** — lava (instant damage), brutes, burn; gates the first boss.

### Changed files
- `src/game/terrainNoise.ts` — replace single `sample()` global with per-biome seeded noise functions (keep one shared `sample()` for back-compat per AGENTS.md:21, but add `biomeSample(biome, x, y)`).
- `src/game/worldTiles.ts` — add per-biome tile ids: `snow`, `ice`, `lava`, `sand`, `swamp-water`, `crystal`, `tree-canopy`, `torch`, `flower-blue`, etc.
- `src/game/scenes/WorldScene.ts` → rename/split into `AreaScene.ts` parameterized by `areaId`.
- `src/game/Minimap.ts` — render current area only, with a **world map** (press M) showing discovered areas + links + player location (Zelda overworld map).

### Concrete tasks
1. Define 6 biomes × 4+ areas each (≥ 24 area instances). World is now ~20–40× bigger.
2. Each area 48×48 to 64×64 tiles. Edge transition zones at N/E/S/W borders.
3. Transition VFX: pixelate/wipe + 350ms fade (match `WorldScene.ts:768` pan timing style).
4. Camera per-area bounds; `cameras.main.setBounds` driven by area size.
5. Streamline spawn rules per biome (enemy density, friend density, decorations).
6. Add **fast-travel shrines** unlocked by discovery (Zelda towers/bonfires).
7. Day/night affects enemy density & aggression per area (Phase 8).

### Milestone 4
Walk from the Meadow → Gloop Forest → Crystal Caverns via 3 edge transitions,
see area title cards, distinct tile art + enemies, minimap switches, world map
(M) shows discovered areas and your position.

---

## Phase 5 — Quests, Missions & Journal

Goal: give the player reasons to go everywhere and fight everything.

### New files
- `src/game/quests/Quest.ts` — quest model: id, title, giver, stages, rewards, prerequisites, flags.
- `src/game/quests/QuestTracker.ts` — tracks active/complete/failed, listens to `EventBus` (`enemy.died`, `item.collected`, `area.enter`, `npc.talked`).
- `src/game/quests/QuestGiver.ts` — NPC with a quest-offer dialogue + accept/decline.
- `src/game/ui/QuestJournal.ts` — Tab overlay: active, completed, available hints.
- `src/game/ui/DialogueBox.ts` — replaces the free-text `ChatUI` for scripted NPC dialogue (portrait, typewriter, choices). Keep `ChatUI` for casual friend chatter.
- `src/game/data/quests.json`.

### Quest types (≥ 12 total)
- **Tutorial:** “Talk to 3 friends”, “Buy a boost”, “Sleep at home”.
- **Hunt:** “Defeat 10 blobs in Gloop Forest”.
- **Fetch:** “Bring 5 sticky silk to the swamp hermit”.
- **Escort:** “Walk a friend safely across the caverns”.
- **Boss-gate:** “Clear the Volcano Ridge camp” → unlocks boss arena.
- **Mystery:** “Find the mimic in the caverns” (joke + scare).
- **Collection:** “Discover all 6 shrines”.
- **Crafting intro:** “Forge the Splat Spear” (ties to Phase 7).

### Concrete tasks
1. Quest stages are event-driven, not polled — subscribe to `EventBus`.
2. Rewards: coins, XP, items, ability points, weapon unlocks, area unlocks.
3. Quest-giver markers on minimap + world (! / ? icons, Zelda-style).
4. Journal sorted by area; completed quests collapse.
5. Main quest line of ~5 steps gates boss progression; side quests optional.

### Milestone 5
Pick up the tutorial quest line, complete 3 stages by doing real actions, see
journal update + reward granted + notification toast. Talk to a quest giver
with the new `DialogueBox`.

---

## Phase 6 — Bosses

Goal: memorable, multi-phase fights that cap each major area.

### New files
- `src/game/boss/Boss.ts` — extends `Enemy` with phases, health thresholds, attack queue, intro cinematic, enrage timer, death cutscene.
- `src/game/boss/BossArena.ts` — gated arena: walls rise on enter, gates open on victory.
- `src/game/boss/AttackPatterns.ts` — reusable patterns: `LeapSlam`, `ProjectileFan`, `ChargeRun`, `SummonAdds`, `GroundWave`, `LaserSweep`.
- `src/game/boss/library/` — one file per boss.
- `src/game/ui/BossHealthBar.ts` — bottom-screen bar with name + phase pips.

### Bosses (4, one per major area)
1. **The Blobfather** (Forest) — big slime, summon swarmers, leap-slam shockwaves; teaches dodge + AoE.
2. **Crystal Colossus** (Caverns) — armored, weak to hammer; laser-sweep + projectile fan; teaches weapon switching.
3. **Swamp Matriarch** (Swamp) — sticky-web + poison, summons spider-slimes; teaches status effects + bubble shield.
4. **Magma Monarch** (Volcano, finale) — lava waves, enrage at 30%, multi-phase; gates the beta’s end.

### Concrete tasks
1. Intro cinematic: camera pan + name card + roar (reuses `cameras.main.pan` style from `WorldScene.ts:768`).
2. Phase transitions on HP thresholds with short invuln + new attack queue.
3. Telegraph every heavy attack (red ground decal / windup anim).
4. i-frame dodge windows tuned so each pattern is fair.
5. Death sequence: slow-mo (`timeScale`), explosion particles, gate opens, reward chest.
6. Bosses drop a unique weapon or ability (ties to Phase 2/7).

### Milestone 6
Beat The Blobfather: enter arena → walls rise → cinematic → fight 3 phases →
victory → reward chest → gate opens. No softlocks on death (retry from arena
entrance).

---

## Phase 7 — Progression Content: Dungeons, Puzzles & Crafting

Goal: Zelda-style substance between combat encounters.

Status: **in progress**. Crafting is implemented, and the first Crystal Caverns
trial slice is implemented. The current stopping point is after the two-switch
trial chest; the next work should turn this into a fuller dungeon path.

### New files
- `src/game/dungeon/Dungeon.ts` — multi-room area with locked doors, keys, switches, a mini-boss, a treasure.
- `src/game/dungeon/Puzzle.ts` — base for switch/push-block/slime-puddle-redirect/order-puzzle.
- `src/game/crafting/Crafting.ts` — recipe-based: materials → weapon upgrades / consumables / ability tomes.
- `src/game/crafting/Forge.ts` — workstation object in the world (anvil/cauldron).
- `src/game/data/recipes.json`.
- `src/game/ui/CraftingUI.ts`.

### Concrete tasks
1. In progress: at least **1 full dungeon** (Crystal Caverns depth) with 6 rooms, 2 puzzles, 1 mini-boss, 1 treasure (Splat Spear upgrade or ability tome).
2. Started: puzzles reuse physics. Implemented first step-on switch trial in Crystal Caverns with 2 switches and a persistent reward chest.
3. Pending: crafting upgrades weapons (tier I→II→III) with material costs; gives collectibles long-term value.
4. Done first slice: cauldron-style recipe crafting brews potions from foraged materials.

### Implemented Phase 7 slices
- `src/game/crafting/Crafting.ts` and `src/game/ui/CraftingUI.ts`: recipe crafting UI, keyboard navigation, mouse click regions, and crafted-item feedback.
- Inventory flow supports item details, consumable use, and deleting one item at a time.
- Purple berries now enter inventory as crafting material.
- Crystal Caverns switch trial in `WorldScene`: two switches unlock a chest.
- Crystal trial reward: `+90 coins`, `+120 XP`, `+4 Crystal Shards`, `+1 Slime Tonic`.
- Crystal trial persistence key: `slime-isa:dungeon-completed`.
- New generated textures in `BootScene`: crystal switches and crystal chest open/closed states.

### Left off / next action
- Add the second dungeon puzzle after the Crystal Trial chest.
- Add a locked gate/key or a mimic/mini-boss encounter after puzzle 2.
- Decide whether the major treasure should be a Splat Spear unlock, weapon upgrade, or ability tome.

### Milestone 7
Clear the cavern dungeon: solve 2 puzzles, get the key, beat mini-boss, open
treasure, forge a weapon upgrade at the anvil, feel stronger in combat.

---

## Phase 8 — Meta Systems: Save, Audio, Day/Night, Weather, VFX

Goal: the connective tissue that makes it feel like a real game.

### New files
- `src/game/core/SaveSystem.ts` (from Phase 0) — finalize: autosave on area transition + every 60s + on sleep + on quit (`visibilitychange`).
- `src/game/audio/AudioManager.ts` — wraps Phaser sound; SFX bus + music bus; crossfade music per area; duck music on low HP.
- `src/game/audio/Sfx.ts` — named one-shots: hit, crit, coin, levelup, ability, bossroar, ui.
- `src/game/systems/DayNight.ts` — 8-min day; tint overlay + ambient light; enemies stronger at night; friends go home.
- `src/game/systems/Weather.ts` — per-biome: rain (swamp), snow (frost), ash (volcano); particles + gameplay (rain extinguishes burn, snow slows).
- `src/game/vfx/Particles.ts` — pooled emitters: hit spark, slime splash, dust on roll, coin sparkle, level-up burst.
- `src/game/vfx/ScreenShake.ts` — small/medium/large presets tied to events.
- `src/game/vfx/HitStop.ts` — freeze 40–80ms on heavy hits/boss hits (juice).

### Changed files
- `src/game/scenes/BootScene.ts` — generate audio is **not** procedural; add a small bundled sound set in `asset/audio/` (CC0) + load in preload. Keep textures procedural.
- `src/game/HUD.ts` — clock widget (sun/moon), weather icon, low-HP vignette.
- `src/game/Minimap.ts` — tint at night.

### Concrete tasks
1. Save schema v1: `GameState` + discovered areas + quest flags + boss flags + settings.
2. Audio: minimum 12 SFX + 5 music tracks (menu, meadow, forest, cavern, boss).
3. Day/night tint via a fullscreen colored rect with `blendMode MULTIPLY` + depth max; lerp colors at dawn/dusk.
4. Weather particles via `Phaser.GameObjects.Particles` with per-biome spawn region.
5. VFX presets callable from anywhere via `vfx.shake(scene, 'small')`.

### Milestone 8
Save mid-fight, reload the page, resume in the same area with the same HP/XP.
Hear distinct music per area + SFX on every hit. See a full day-night cycle
with night enemies. Watch rain fall in the swamp.

---

## Phase 9 — UI/UX: Title, Pause, Settings, Game Over, Onboarding

Goal: first-30-minutes polish that a beta reviewer expects.

### New files
- `src/game/scenes/TitleScene.ts` — title art (procedural slime logo), Play/Continue/Settings/Credits, version + build hash.
- `src/game/scenes/GameOverScene.ts` — death screen, retry from last save/shrine, stats summary.
- `src/game/ui/PauseMenu.ts` — Esc: Resume, Journal, Inventory, Map, Settings, Save & Quit.
- `src/game/ui/SettingsUI.ts` — master/music/sfx volume, screen shake, reduce-motion, autosave toggle, key rebinding, debug overlay.
- `src/game/ui/Tooltip.ts` — hover tooltips for items/abilities.
- `src/game/ui/Toast.ts` — quest/item/level-up notifications (stacking, auto-dismiss).
- `src/game/ui/IntroTutorial.ts` — contextual controls hints that fade after first performance (Zelda-esque, non-intrusive).

### Changed files
- `src/game/config.ts` — scene order: `Boot → Title → (Area) → GameOver → Title`; remove the static controls `<table>` from `config.ts:11` (move into an in-game pause/Journal “Controls” tab; keep a small persistent hint instead).
- `src/styles.css` — fonts, scrollbars, input styling for menus.

### Concrete tasks
1. Title → Continue loads save; New Game wipes and starts at Meadow.
2. Pause freezes simulation (flag, not Phaser pause, so UI animates).
3. Settings persist to `localStorage` separate from save.
4. Reduce-motion mode disables shake + heavy particles (accessibility).
5. Tutorial hints: show “Press Space to jump” until the player jumps once.

### Milestone 9
Boot → title → new game → play → die → game over → retry → pause → settings →
quit → title → continue. Full menu loop works end to end.

---

## Phase 10 — Game Feel & Juice (the “funnier/better” pass)

This is the layer that makes it *feel* good rather than just *work*.

- **Squash & stretch on every meaningful event** — land → squash, jump → stretch, hit → flinch. The slime sheet already supports these (`slimeAnimations.ts:54,62`) — drive them from events, not just key presses.
- **Hit-stop** on heavy hits/boss hits (Phase 8 `HitStop`).
- **Screen shake** calibrated per event; respect reduce-motion.
- **Particle bursts** on hit/crit/level/loot/boss-death.
- **Floating text** for damage (color by type: physical white, crit yellow, burn orange, poison green, heal green).
- **Camera feedback**: slight zoom-out on boss enter, zoom-in on level up, dolly on dialogue.
- **Slime-form transformations** (signature mechanic): the slime can take a *form* tied to biome — **Ice Form** (frostpeak, slide), **Lava Form** (volcano, burn aura), **Sticky Form** (swamp, wall cling), **Bubble Form** (water, float). Each gated by a quest and opening new traversal puzzles. This is the “thing you might miss” that ties exploration + abilities + puzzles together.
- **Companions**: recruit friends (existing `Friend.ts`) to follow and fight. Cap 2–3; they level with you. Reuses friend art/anim — high value, low cost.
- **Mounts**: a tameable Bouncer you can ride (faster travel + stomp attack). Fun + uses existing enemy art.
- **Combo meter** that builds style → small coin/xp multipliers; rewards aggressive play.
- **Boss intro / victory name cards** (Zelda memory).
- **Hidden secrets**: hidden caves behind breakable rock (hammer), heart-container upgrades (max HP up), stamina-fruits (max energy up) — classic Zelda collectibles that reward exploration.
- **Photo mode / idle camera** (small, cheap, delightful).
- **Joke writing**: mimic scare, friend dialogue, NPC puns. The chat system (`ChatUI.ts`) already has a voice — lean into it.

### Milestone 10
A 5-minute combat encounter feels like a finished game: hits have weight, the
slime squashes on land, a crit stops time for 60ms with a yellow number, a
level-up bursts particles, a companion slime helps you, and the combo meter
flashes.

---

## Phase 11 — Content Authoring Pass

Now that systems exist, fill them with content (data, not code).

- Author all 6 biomes × 4 areas = 24 `areas.json` entries.
- Author 8 enemies × variants (≈ 16 stat blocks) in `enemies.json`.
- Author 6 weapons with 3 upgrade tiers = 18 weapon records.
- Author 8 abilities + tree layout in `abilities.json`.
- Author 12+ quests (5 main + 7 side) in `quests.json`.
- Author 4 bosses with 3 phases each + attack queues.
- Author recipes (~12) and items (~25: consumables, materials, key items, collectibles).
- Author NPC dialogue trees for quest givers + flavor NPCs.
- Author 1 dungeon layout.

### Milestone 11
A full playthrough from title → final boss is possible in ~2–4 hours with all
content populated; no placeholder “TODO” text in shipped paths.

---

## Phase 12 — Beta Hardening

- **Balance pass:** XP curve, coin economy, enemy damage per area, boss phase tuning, drop rates. Use a `config.ts` debug overlay to tweak live.
- **Performance:** pooled hitboxes/projectiles/particles/enemies; cull off-screen; cap concurrent enemies per area (≈ 24); reuse the `EnemySpawner` despawn. Target 60 fps on a mid laptop with the 24-area world.
- **Save migration:** schema version + migration stub so future changes don’t wipe saves.
- **Controls:** full gamepad support via Phaser input, rebinding persisted, on-screen button hints when a pad is detected.
- **Accessibility:** reduce-motion, colorblind-safe status colors (shape + color, not color alone), configurable text size, hold-to-confirm on destructive actions.
- **Bug sweep:** no softlocks on death during cutscenes, no fall-through-world at area edges, no duplicate key items, retry-from-shrine guaranteed.
- **Telemetry/`AGENTS.md` update:** document new dev commands (debug overlay, save wipe, spawn-enemy cheat) and the data-driven content workflow.

### Milestone 12 (BETA)
All milestones 0–11 green, balance pass done, 60 fps target met, save/load
robust, full menu loop, gamepad works, accessibility options work, no known
softlocks. Ship a tagged `v0.9.0-beta` build.

---

## Implementation Order (recommended, with checkpoints)

1. Phase 0 → Milestone 0 *(refactor, no new gameplay)*
2. Phase 1 → M1 *(health/leveling)*
3. Phase 2 → M2 *(combat vs dummies)*
4. Phase 3 → M3 *(real enemies)*
5. Phase 4 → M4 *(big world + transitions)*
6. Phase 8 (subset: Save + Audio + Particles) *(unblock feel early)*
7. Phase 5 → M5 *(quests)*
8. Phase 6 → M6 *(first boss)*
9. Phase 7 → M7 *(dungeon + crafting)*
10. Phase 10 *(juice + companions + slime-forms)*
11. Phase 9 → M9 *(full menu loop)*
12. Phase 11 → M11 *(content)*
13. Phase 12 → M12 *(beta)*

> Pulling a subset of Phase 8 (save/audio/particles) forward is intentional:
> saving means you don’t lose progress while building the rest, audio + particles
> make every later milestone feel like a real game and surface tuning issues
> earlier.

---

## Things you might miss (explicit list, as requested)

- **Save early.** Without it, every playtest resets; you’ll under-test late game.
- **Audio shapes perception of quality** more than any single visual. Budget for a small CC0 pack.
- **Hit-stop + screen shake + squash/stretch** are 80% of “game feel” for a slime.
- **Slime-form transformations** tie exploration, abilities, and puzzles into one signature mechanic — the differentiator vs. generic top-down adventures.
- **Companions** reuse your existing `Friend` art/anim — huge fun-per-effort.
- **Mimic treasure** as both a joke and an enemy — the chat system already has personality; keep that voice.
- **Telegraphed boss attacks** so the existing dodge-roll (`WorldScene.ts:650`) becomes a skill, not a stat.
- **Reduce-motion / accessibility** from day one — cheap now, expensive later.
- **Data-driven content (JSON)** so Phase 11 is authoring, not coding — you’ll iterate balance 100× more than systems.
- **Debug overlay + cheats** (spawn enemy, give XP, unlock area) — you will need these every single day of balancing.
- **Schema-versioned saves** — add it before the first public build, not after.
- **Heart-container / stamina-fruit collectibles** — the classic Zelda hook that makes exploration self-rewarding.

---

## Risk register

| Risk | Mitigation |
|---|---|
| World too big → perf | Pools + despawn + per-area scenes, not one giant grid |
| Combat feels floaty | Hit-stop + shake + squash on every event; telegraphs for fairness |
| Content authoring bottleneck | JSON-driven; debug cheats to skip to any area/boss |
| Save corruption | Schema versioning + migration + autosave to separate slots |
| Scope creep | Phases are independently shippable; each milestone is a playable build |
| Art asset cost | Keep procedural textures; add only a combat sheet + small audio pack |

---

This plan is intentionally large because the gap between “wander a meadow” and
“beta action-adventure” is large. Each phase is sized so it can be a single
focused work session with a verifiable milestone at the end.

# Game Roadmap — Playable Task Checklist

> **Status: active living checklist.** Follow this in small vertical slices and
> update it as the game changes. The design direction lives in
> [Game Guidelines](./GAME_GUIDELINES.md); the larger beta reference remains
> [BETA_PLAN.md](./BETA_PLAN.md).

This roadmap is ordered for visible progress. A milestone is complete only when
the player can perform the loop in the running game and the authored map/editor
workflow supports the content it introduces.

Milestones 1 and 2 and the save/load foundation are verified in fresh-game
playtests. Between 2026-09-12 and 2026-09-26 the whole game moved onto the
Godot-inspired universal scene architecture: authored SceneTrees, ScriptNode
behavior, and one editor, **Scene Studio** (`?studio=scenes`). Every authoring
task below uses Scene Studio. The former Map, Character, Animation, Weapon, and
Projectile Studios and Field Cartographer are retired, and their URLs redirect
to Scene Studio. See [Universal Scene Architecture](#cross-cutting-engine--universal-scene-architecture).

## Locked UI Style Decisions

On 2026-09-04 the in-world gameplay HUD direction was approved as **Option C —
artwork-first**: the world background remains visible, and the HUD,
minimap, and weapon hotbar use transparent interiors with restrained outlines,
text shadows, and state accents instead of opaque dark boxes. Inventory and
crafting are explicitly excluded because they are being redesigned separately.
The ability bar is now mounted as an authored UI scene (commit `42ad451`), but
its artwork-first skin remains deferred.
The detailed implementation contract is in
[World HUD Artwork-First Presentation](./superpowers/specs/2026-09-04-world-hud-artwork-first-design.md),
which refines the broader
[Game UI Visual Skin System](./superpowers/specs/2026-09-03-game-ui-visual-skin-design.md).

## How To Use The Checklist

- `[ ]` not started, `[~]` in progress, `[x]` verified in the running game, `[—]` dropped.
- Finish one milestone before expanding its next tier.
- After each milestone, do a short playtest and record one screenshot or note
  describing what became possible.
- Keep unresolved design choices in the open-question tasks instead of silently
  inventing rules.

## Progress Board

| Milestone | Player-visible result | Status |
|---|---|---|
| 1. Wood gathering | Chop a visible tree and collect wood | `[x]` |
| 2. Stone and starter tools | Walk over loose materials, craft starter gear, defeat Fatty One Eye, loot the guarded chest, and unlock the next area | `[x]` |
| P. Save, load, and reset foundation | Create or overwrite named saves, load complete runs, or reset to authored defaults | `[x]` |
| S. Universal scene architecture | Every world, entity, effect, UI, and audio surface is an authored scene editable in Scene Studio | `[x]` |
| A. Audio and SFX | Combat, gathering, UI, and boss actions are audible; music and ambience follow the area | `[~]` |
| 3. Home exterior | Doors anywhere lead into interiors; the last bed slept in is home | `[~]` |
| 4. Home interior | Enter a real interior, move inside, and return outside | `[~]` |
| 5. Workshop | Craft weapons, tools, and items in the first crafting building | `[ ]` |
| 6. Iron region | Reach a tougher region and harvest iron with the right tool | `[ ]` |
| 7. Enemy materials | Fight enemies for special drops and access | `[ ]` |
| 8. Forge | Smelt iron and other ores into metal bars | `[ ]` |
| 9. Kitchen | Cook healing or buff food in the kitchen | `[ ]` |
| 10. Kitchen potions | Brew potions and antidotes from monster materials in the kitchen | `[ ]` |
| 11. Builder’s table | Upgrade and move the home while keeping its interior | `[ ]` |
| 12. Safety and persistence | Understand danger, recover, store items, and reload safely | `[ ]` |
| 13. Progression pass | Discover recipes and complete a balanced material path | `[ ]` |
| 14. Beta slice | Play a complete gather → fight → craft → upgrade loop | `[ ]` |

## Task Tile Format

Use this shape when adding a new task:

```md
### [ ] 1.1 — Short task name

- Build: the smallest implementation or content change.
- Player proof: what the player can see or do afterward.
- Done when: the concrete acceptance check passes.
```

## 1. Wood Gathering — First Complete Resource Loop

### [x] 1.0 — Add numeric resource damage modifiers

- Build: weapons now carry direct `{ targetTag, modifier }` entries; existing
  weapons use `resource: 0.1`, with normal damage as the fallback.
- Player proof: resource targets can be balanced independently from enemy damage.
- Done when: the weapon catalog and combat pipeline validate and apply numeric
  resource modifiers.

### [x] 1.1 — Add wood as a persistent material

- Build: define the stable wood item, stack rules, inventory display, and save data.
- Current: `wood` is registered, stackable, shown in the inventory, and included
  in saved inventory/world progress.
- Player proof: wood appears as a named resource instead of an anonymous pickup.
- Done when: collect, reload, and still have the same wood count.

### [x] 1.2 — Author harvestable tree objects

- Build: create tree object definitions with a harvest state, drop payload, and
  collision layer; place several instances in an authored map.
- Current: authored trees have colliders, health, wood drops, persistent state,
  and replace themselves with the catalog wood-pile visual.
- Player proof: trees are visible world objects that occupy space.
- Done when: the runtime and map validator accept the same tree IDs.

### [x] 1.3 — Add wood visuals and feedback

- Build: add the tree variants, hit/harvest feedback, wood pickup icon, and a
  small collection notification.
- Current: tree/pile art, wood inventory art, hit feedback, collection prompts,
  floating reward text, and the independent resource-impact effect are present.
- Player proof: chopping feels like an action, not an invisible counter change.
- Done when: the player can identify the tree, the hit, and the reward.

### [x] 1.4 — Add the starter gathering tool

- Build: add a starter axe or equivalent tool, equip/use flow, and the resource
  interaction that lets it harvest wood.
- Current: the Wooden Axe is a fifth starter hotbar item with directional art,
  wood `1.0` damage, non-wood resource `0.1` damage, enemy `0.2` damage, and a
  resource-only impact effect.
- Player proof: the tool visibly performs the action and produces wood.
- Done when: the player can harvest several trees without a debug shortcut.

### [x] 1.5 — Verify the first playtest loop

- Build: add any missing pickup, HUD, sound, or save feedback needed to make the
  loop readable.
- Player proof: explore → find tree → harvest → collect → see inventory.
- Current: user-verified in a fresh-game playtest; the complete loop works
  reliably.
- Done when: a five-minute fresh-game playtest completes the loop reliably.

**Milestone 1 complete:** the player can gather and keep wood through a normal
play session, verified in the running game.

## 2. Stone And Starter Tools

Implementation order, ownership, save migration, and acceptance checks are
defined in the
[Stone and Starter Tools implementation plan](./superpowers/plans/2026-08-23-stone-and-starter-tools-implementation-plan.md).

The resource/collectible taxonomy correction, walk-over pickup behavior, save
migration, and Map Studio attribute work are defined in the
[Walk-over Collectibles and Editor Attributes implementation plan](./superpowers/plans/2026-08-24-walk-over-collectibles-and-editor-attributes-implementation-plan.md).

Close-out evidence is in the
[Level 1 and Milestone 2 verification checklist](./task/ideas/completed/level-1-milestone-2-verification-checklist.md).
The user verified the milestone in a playtest on the refactored build on
2026-09-28.

### [x] 2.1 — Author stone resource nodes

- Build: add stone material, visible rock nodes, collision, map placement, deterministic three-pile drops, and reload-safe depletion state.
- Current: the implementation and validators are present: stone nodes use the
  intentional Level 1 visual variants, carry 80 health, and break into up to
  three adjacent small stone piles. Partial node health resets on reload while
  broken piles and their remaining amounts persist. Loose starter stone and its
  persistence path are implemented and verified in a fresh-save/reload pass.
- Player proof: wood and stone are distinct resources with distinct visuals.
- Done when: both resources can be collected and saved.

### [x] 2.2 — Add basic tool recipes

- Build: add portable recipes for Wooden Spear (`20 wood`), Stone Axe
  (`10 wood + 10 stone`), Stone Pickaxe (`10 wood + 10 stone`), and Stone
  Spear (`20 wood + 20 stone`). Add enough hand-collectible loose wood and stone
  to prevent a fresh-save softlock.
- Current: the four portable recipes, atomic inventory transaction, crafted
  weapon assignment, dedicated spear swing art, and a hand-collectible starter
  budget are implemented in the Level 1 map. Normal fresh runs now begin with
  no weapon, tool, attack, or production test potion; the legacy starter arsenal
  is available only through the explicit development grant. The complete flow
  passed its fresh-save playtest.
- Player proof: gathered materials turn into equipped tools and a first crafted weapon.
- Done when: a new save can craft and assign the starter gear without cheats or
  automatic production grants.

### [x] 2.3 — Enforce tool-gated harvesting

- Build: give resource nodes a required tool tier and show a clear feedback state
  when the tool is insufficient.
- Current: tree and stone archetypes declare explicit tier-one requirements;
  combat checks the equipped weapon's harvest capability before damage and
  displays Stone Axe or Stone Pickaxe guidance when the requirement is unmet.
  Verified in a fresh-save runtime pass.
- Player proof: the player understands why a harder node cannot be harvested yet.
- Done when: the gate works consistently in runtime and authored maps.

### [x] 2.4 — Build the shared animation library (superseded by Scene Studio)

- Build: originally, layered animation packages shared through a recursive
  catalog, edited in Weapon/Animation Studio and picked in Map Studio.
- Outcome: the universal scene refactor replaced this design. Weapons, trees,
  and objects now embed their clips in their own scene's `AnimationPlayer`
  library, and truly shared data lives in standalone `*.resource.json` files.
  The 34 package rows were retired. Scene Studio's animation dock is the only
  animation editor. Its timeline, viewport, and inspector keying, and a
  weapon script's `attackPlans` hitbox timing, are covered by scene and browser
  tests.
- Done: weapons keep their authored visuals, and object animation is authored
  once per scene and reused by every instance.

### [x] 2.5 — Add new object authoring (superseded by Scene Studio)

- Build: originally, a New Object dialog in Map Studio.
- Outcome: Scene Studio replaces it. A new object is an authored scene with a
  sprite, collision shapes, depth guide, and ScriptNode behavior. It is placed
  in a world scene as an instance with reversible local overrides, and
  undo/redo and hash-checked saves cover the whole flow (commits `4a41d93`,
  `f4fd578`).
- Done: objects can be created, placed, saved, and reloaded without editing
  JSON by hand. `scenes:check`, `objects:check`, `maps:check`, typecheck, and
  the build validate them.

### [x] 2.6 — Move loose materials to walk-over collectibles

- Build: replace resource-pile pickup data with a generic collectible payload;
  move loose wood and stone into Collectibles; collect all collectibles by
  player overlap without `F`; preserve partial quantities and existing save
  progress. Group Map Studio objects by behavior capability and expose editable
  shared gameplay defaults plus supported per-instance overrides, including
  collectible material/quantity and resource-node life/drop/tool attributes.
  Resource nodes choose their death drop from a catalog-backed collectible
  dropdown and specify how many collectible pieces spawn. Split the right
  inspector into **Visuals & collisions** and **Gameplay attributes** tabs with
  independent validation and save state.
- Player proof: walking over loose wood or stone collects it immediately, while
  trees and stone nodes remain tool-damaged resource targets.
- Creator proof: wood, stone, and berries appear under Collectibles; resource
  nodes appear under Resource Nodes; selecting either shows its resolved
  gameplay attributes and safe edit scope. A stone node can select the stone
  collectible and set, for example, 3 or 4 dropped pieces with a visible total
  material-yield preview, while visual/collision controls remain organized in
  their own inspector tab.
- Done when: no collectible uses the `F` pickup route, partial/full inventory
  behavior and save migration are verified, editor attribute edits survive
  save/reload, the two inspector tabs cannot overwrite each other's data, and
  the automated/manual matrix in the linked plan passes.
- Verification: focused persistence, collectible-runtime, and Map Studio state
  tests cover migration, partial/exact-once collection, deterministic overflow
  placement, draft preservation, grouping/search, per-instance validation, and
  granular override reset. The production build and all content validators pass;
  the running Map Studio confirms tab navigation, yield preview, dirty-state
  preservation, and reset behavior.

### [x] 2.7 — Complete the first guarded-key progression gate

- Build: keep the ordinary worm camp unchanged and add a separate authored boss
  camp for Fatty One Eye. Fatty is a round, mouthless, translucent slime whose
  exact-center eye can be damaged only by the Wooden or Stone Spear. He deals
  a collision-triggered 300 ms stationary contact hop with one 64 px landing
  hit, ignores knockback through the shared enemy-effect immunity field, and
  telegraphs a targeted one-second leap with three small
  hops, a shadow, landing marker, landing-area damage, and ground cracks. A true
  defeat starts the camp-authored three-minute wall-clock respawn timer; an
  eligible respawn waits for exit and re-entry.
- Build: add a reusable authored chest with closed/open sprites, Map Studio
  placement and editable item stacks, and an inventory-skinned loot panel.
  Left-click inspects an item; right-click transfers the maximum amount of its
  stack that fits and leaves any remainder. Fatty locks the chest while alive;
  partial contents persist and relock on respawn, while an emptied chest stays
  visibly open forever.
- Build: put exactly one persistent green key in the Level 1 chest and require
  it at the east exit. The key is consumed only on the first unlock and the
  permanent gate state survives reload. Save/load or player death during the
  fight resets Fatty to full health without starting the defeat timer.
- Current: Fatty is a ranked enemy scene with ScriptNode behavior. The chest
  and its UI, save-schema version 9 state, the authored Level 1 camp and chest,
  and the keyed Gloop Forest exit are all implemented. The encounter's shape-based
  area and shared arena leash, its boss links, and the landing splash are
  authored in Scene Studio (commits `a3aa9a2`, `8e34a88`). The encounter,
  three-minute respawn, chest, and key/gate round trip were verified by the user
  on 2026-09-28. See
  [Fatty One Eye guarded chest design](./superpowers/specs/2026-09-11-fatty-one-eye-guarded-chest-design.md).
- Player proof: collecting and crafting starter gear leads to a readable boss
  fight, deliberate spear-range eye strikes, selectable chest loot, and visible
  access to Gloop Forest.
- Done when: the Section E matrix passes in a fresh run, including partial
  inventory transfer, save/reload, boss respawn/relocking, exact-once key use,
  and the complete collect → craft → gather → fight → chest → key → exit loop.

**Milestone 2 complete (verified 2026-09-28):** wood and stone form a readable
starting economy, and crafted starter gear opens the first guarded progression
gate.

## A. Audio And SFX — Make The World Audible

Current focus. Milestone 3 starts once A.0–A.4 are done. The full cue list
(about 150 cues, ranked P1 combat feel, P2 living world, P3 polish), the hooks
for each cue, and the phase details are in the
[Audio & SFX implementation plan](./superpowers/plans/2026-09-28-audio-sfx-implementation-plan.md).

What already exists: `AudioStreamPlayer` and `AudioStreamPlayer2D` nodes, the
`effects` and `music` buses with volume and mute, audio unlock on first input,
2D falloff and pan, scene signal `connections`, and the mounted `audio.global`
scene. What is missing: sound files, audio loading, variation, polyphony, sounds
that outlive their node, the `gameEvents` bridge, and a volume UI.

**Sourcing:** each P1 cue ships in two flavours under the same cue ID: `synth`
(made by our deterministic `pnpm audio:bake`) and `library` (Kenney CC0 samples,
credited in `asset/audio/CREDITS.md`). A dev toggle, `?sfx=synth|library`,
switches between them. After an A/B listen, the losing flavour is deleted.

### [~] A.0 — Make audio loadable

- Build: add `source.kind: "audio"` entries to `asset/assets.json`, route them
  through `scene.load.audio` in `AssetLoader`, check the audio cache instead of
  textures, and load them in a boot-time `audio` bundle. `assets:check` must
  validate audio files and extensions. Asset IDs follow
  `audio.sfx.<flavour>.<category>.<cue>[.<n>]`, `audio.music.<id>`, and
  `audio.ambience.<id>`.
- Done when: an audio asset loads at boot, and `assets:check` and `pnpm check`
  pass.

### [~] A.1 — Upgrade the audio nodes

- Build: add built-in node handlers (for example `AudioStreamPlayer.play`) and
  an `AudioPlaybackController` that supports `variants`, `pitchRandomness`,
  `polyphony` (default 4), `minInterval`, and `detached` one-shots that outlive
  their node. Add an `ambience` bus.
- Current: node-type handler descriptors and signal/handler payload
  compatibility are being added in `propertyDescriptors.ts`.
- Done when: rapid hits overlap instead of cutting each other off, a pickup's
  sound survives the pickup being freed, and scene checks pass.

### [ ] A.2 — Create the P1 sounds

- Build: write the synth bake tool (`scripts/audio/sfx-bake.mjs` plus JSON
  recipes) that outputs deterministic 22.05 kHz WAV files. Add all P1 synth
  cues, then the Kenney P1 cues (after the user approves the download) and the
  flavour toggle.
- Done when: every P1 cue exists in both flavours, and `pnpm audio:bake`
  reproduces the synth files byte-for-byte.

### [ ] A.3 — Wire P1 sounds into scenes

- Build: author the sound nodes in the effect, weapon, player, enemy, Fatty,
  resource, projectile, and collectible scenes, connected to their existing
  signals. Add `features/audio/AudioEventBridge` for UI and `gameEvents` cues.
  It receives a context interface, never imports `WorldScene`, and cleans up
  through `DisposableBag`.
- Player proof: swings, hits, chops, the wrong-tool clank, pickups, crafting,
  level-up, and every Fatty phase can be heard.
- Done when: a browser preview playtest hears every P1 cue once per trigger,
  with no duplicates and no console audio errors.

### [ ] A.4 — Pick a flavour

- Build: the user compares synth and library sounds for each category. Delete
  the losing flavour and remove the toggle if it is no longer needed.
- Done when: each cue ID has one shipped flavour and `assets:check` finds no
  orphans.

### [ ] A.5 — Bring the world to life (P2)

- Build: add terrain-aware footsteps, status-effect cues, chest, gate, and NPC
  sounds, prop loops (campfire, cauldron, grindstone, anvil), biome ambience,
  and area music with stings.
- Player proof: each area sounds different and the camp props can be heard as
  you approach them.

### [ ] A.6 — Add audio settings and polish (P3)

- Build: add master, effects, music, and ambience volume sliders persisted
  through `SaveSystem`. Duck the music while paused, crossfade it on
  `area.enter`, and switch to boss music on `boss_spawn_requested`. Pass the
  crit flag through to hit sounds, and add the remaining P3 cues.
- Done when: volume settings survive a reload, and music transitions never
  stack or cut off abruptly.

**Audio milestone complete when:** P1 combat, gathering, UI, and boss cues are
wired in one final flavour, and the world has ambience, music, and persistent
volume settings.

## Crafting Buildings — Where Each Craft Happens

Crafting past the starter tier happens in **dedicated buildings**, not in a
portable menu. Each building is its own authored scene: an exterior in the
world, and a station you use at or inside it. It has its own recipe family and
its own upgrade tiers. The four starter recipes stay `portable` so a fresh save
can never softlock.

| Building | Crafts | Main inputs | Milestone |
|---|---|---|---|
| **Workshop** | Weapons, tools, and items (bombs, storage, building parts, repairs) | Wood, stone, metal bars, enemy materials | 5 (built at home), then new tiers in 6–8 |
| **Forge** | Smelts iron and other ores into metal bars, later alloys | Ore and fuel | 8 |
| **Kitchen** | Food, healing and buff meals, potions, and antidotes | Forage, crops, monster materials | 9 (food), 10 (potions) |
| **Builder's table** | Home upgrades, furniture, defenses, and moving the home | Building parts, bars | 11 |

- Metal weapons and tools use a two-step chain: ore → **Forge** (bars) →
  **Workshop** (weapon or tool). The Forge only smelts and never outputs
  weapons.
- Potions belong to the Kitchen. The separate Alchemy table is retired from
  the plan.
- Code today: `CraftingContext` in `src/game/content/recipes/types.ts` is
  `'portable' | 'workbench' | 'forge' | 'kitchen' | 'alchemy'`. Rename
  `workbench` to `workshop` and remove `alchemy` when UX.2 is implemented.
- Every building uses one shared crafting popup and recipe authority, filtered
  by building and tier (see UX.2).

## 3. Home Exterior

### [—] 3.1 — Author the one player home

- Dropped: doors can be placed anywhere and link to any interior, so there is
  no single authored home instance to build.

- Build: place one stable player-home instance in an authored map with its visual,
  collider, depth bounds, and interaction point.
- Player proof: the player can recognize a home and walk up to its entrance.
- Done when: Scene Studio, `maps:check`/`scenes:check`, and the runtime agree
  on the same instance.

### [—] 3.2 — Add home ownership and persistence

- Dropped: home identity is no longer a concept; beds and placed furniture own
  the persistent state instead (see 3.3 and 4.6).

- Build: give the home a stable identity and save its placement, ownership, and
  current upgrade state.
- Player proof: the same home remains the player’s home after reload.
- Done when: no duplicate or fallback player home appears.

### [~] 3.3 — Beds are home: respawn at the last bed slept in

- Build: sleeping in any bed makes it the player's respawn point (saved), so
  defeat returns the player to that bed instead of the level-1 start.
- Current: sleeping in a bed saves `world.respawnPoint`; defeat reloads into
  that bed's area (or teleports within the same map) with the player at the
  bed's wake point, falling back to the level-1 start when no bed is set.
- Player proof: sleep in a bed, get defeated elsewhere, wake up at that bed.
- Done when: the respawn bed survives save/load and falls back to level 1 when
  the bed's map no longer has it.

**Milestone 3 complete when:** one authored, persistent home exists in the world
and is usable without procedural fallback.

## 4. Home Interior — Visuals, Logic, And Editor Support

### [x] 4.1 — Define the interior map link

- Build: define a stable relationship between the exterior home instance and its
  authored interior map/room, including entry and return points.
- Current: `game.door` ScriptNodes link level 1's `home-door` (in front of the
  forge house) to `slime-home` entry `south`, and the interior `house-door` back to
  level 1 entry `south`. Doors can be placed anywhere and linked to any
  interior. Verified in game.
- Player proof: entering a particular home always leads to its matching interior.
- Done when: the link is validated and survives save/load.

### [x] 4.2 — Author the first interior visual kit

- Build: create an interior floor, walls, doorway, bed, and a small set of
  furniture visuals that follow the project’s object/depth conventions.
- Current: `wood-floor` terrain tile plus one `object.interior-<category>-*`
  scene per atlas sprite (529 scenes in `objects/interiors/<category>/`,
  generated from `scripts/interiors/interior_catalog.py`);
  `world.slime-home` follows the `woody.png` concept.
- Player proof: the interior feels like a room rather than a camera overlay.
- Done when: the complete room renders with coherent collision and depth.

### [ ] 4.3 — Add interior authoring to Scene Studio

- Build: support creating and opening an interior world scene, painting its
  floor with the shared terrain TileSet, placing furniture scene instances,
  setting the entrance and exit, and editing collision shapes and depth guides
  with the same stable-ID rules as outdoor maps.
- Player proof: an editor change appears in the playable interior.
- Done when: an interior can be authored and saved without hand-editing JSON.

### [x] 4.4 — Implement enter, move, and leave logic

- Build: transition from the exterior door into the interior, place the player at
  the authored entry, constrain the camera, and return to the exterior door.
- Current: press F near either door to travel (same queued navigation as area
  exits); the camera and physics are bounded by the 14×11 room. A bobbing F key
  badge marks the chosen door, chest, or NPC whenever one is in range.
- Player proof: walk inside, move around, then leave through the door.
- Done when: repeated enter/leave cycles do not duplicate players or lose state.

### [~] 4.5 — Add interior collision and interaction

- Build: block walls and solid furniture, keep walkable floor clear, and connect
  bed/home interactions to the existing home system.
- Current: `game.bed` scripts on every sleepable interior bed; F to sleep plays
  the new `doze`/`sleep` clips with floating z's, restores
  `rest.sleepHpRegenPerSec` HP/s, and any input or damage wakes the player.
- Player proof: the room has believable boundaries and a useful bed/interior action.
- Done when: collision, interaction, and depth remain correct from every direction.

### [~] 4.6 — Persist interior state

- Build: save the home interior’s furniture/upgrades and restore them when the
  player re-enters or reloads.
- Current: the `workbench` item (craft-workbench: 40 wood, craftable anywhere)
  is placed from the inventory with a mouse-aimed, grid-snapped preview (R
  switches variant, Esc cancels) and saved per map as `placedFurniture`;
  placed furniture is re-mounted on every visit and G picks it back up. F at a
  placed workbench opens its recipes — every wood and stone recipe now needs one.
- Player proof: a change made inside the home is still there later.
- Done when: the exterior home, interior map, and save data remain in sync.

**Milestone 4 complete when:** the player can enter a visibly authored home,
walk through it, use it, leave it, and see the same interior after reload;
Scene Studio can create the room and the checks validate it.

## 5. Workshop — First Crafting Building

### [ ] 5.1 — Author the Workshop building

- Build: add a Workshop building scene (exterior, collision, depth guide, and
  an interaction point or interior station) and place it at the home site in
  Scene Studio.
- Player proof: the Workshop is a real building the player walks to, not a
  button in a menu.
- Done when: it can be moved or replaced through the authored-scene workflow
  and survives reload.

### [ ] 5.2 — Give the Workshop its recipe family

- Build: assign weapons, tools, and items (bombs, storage, building parts,
  repairs) to the `workshop` context, and show locked recipes clearly. This
  needs UX.2 (station-aware crafting).
- Player proof: the player knows which recipes belong at the Workshop.
- Done when: progression recipes can only be crafted at the Workshop.

### [ ] 5.3 — Add the first Workshop upgrade tier

- Build: add one upgrade step that visibly changes the building and unlocks a
  next-tier recipe.
- Player proof: upgrading the Workshop immediately unlocks something useful.
- Done when: the tier and its unlock survive save/load.

**Milestone 5 complete when:** the Workshop is the first meaningful crafting
destination.

## 6. Iron And Tool-Gated Regions

### [ ] 6.1 — Author the first tougher region

- Build: add a connected authored region with a distinct visual identity, map
  connection, and clear reason it is more dangerous.
- Player proof: leaving the starter area feels like progress.
- Done when: the region is reachable through exits authored in Scene Studio.

### [ ] 6.2 — Add iron nodes and improved harvesting

- Build: add iron ore material and nodes. Add the improved tool tier that can
  harvest them, crafted at the Workshop.
- Player proof: returning with a better tool opens previously blocked resources.
- Done when: the old tool fails clearly and the improved tool succeeds.

### [ ] 6.3 — Verify the tool-gated path

- Build: add map placement, feedback, inventory, and save coverage for the full
  wood → stone → iron path.
- Player proof: the player can name the next resource they are working toward.
- Done when: a fresh playthrough reaches iron without debug grants.

**Milestone 6 complete when:** tool upgrades open a new region and a new material.

## 7. Enemy Drops And Dangerous Access

### [ ] 7.1 — Add special enemy materials

- Build: define one enemy-gated material and add it to an authored enemy drop table.
- Player proof: fighting has a resource purpose beyond XP or coins.
- Done when: the material is collectible, visible, saved, and counted correctly.

### [ ] 7.2 — Make danger affect access

- Build: author a dangerous area with enemy presence, readable boundaries, and a
  reward path that uses the new material.
- Player proof: the player chooses whether the reward is worth the risk.
- Done when: enemies cannot appear in authored safe zones and the area remains fair.

### [ ] 7.3 — Connect enemy materials to crafting

- Build: add one recipe that cannot be completed without the enemy material.
- Player proof: defeating the enemy visibly advances a recipe goal.
- Done when: the complete fight → drop → craft chain works in one playtest.

**Milestone 7 complete when:** enemies gate a real crafting outcome and a dangerous
area has a meaningful reward.

## 8. Forge — Smelting Metal Bars

### [ ] 8.1 — Author the Forge building

- Build: add the Forge building scene with collision, depth guide, interaction,
  a looping anvil/fire sound (A.5), and placement at the home site.
- Player proof: the Forge has a clearly different purpose from the Workshop.
- Done when: Scene Studio and the runtime show the same Forge instance.

### [ ] 8.2 — Smelt ore into bars

- Build: add `forge` recipes that turn iron ore (and later other ores) plus
  fuel into metal bars. The Forge outputs bars, never weapons.
- Player proof: raw ore becomes a visible, stackable bar material.
- Done when: bars are collected, saved, and counted correctly.

### [ ] 8.3 — Use bars in Workshop recipes

- Build: add the first metal weapon and metal tool to the Workshop, both
  requiring bars and at least one enemy-gated material.
- Player proof: the player sees the chain ore → Forge → bar → Workshop →
  stronger weapon.
- Done when: the first stronger weapon can be crafted in a fresh run without
  debug grants.

### [ ] 8.4 — Upgrade the Forge once

- Build: add one Forge upgrade that visibly changes the building and unlocks
  the next ore or alloy tier.
- Player proof: upgrading the Forge immediately expands what can be smelted.
- Done when: the upgrade persists and portable crafting cannot bypass it.

**Milestone 8 complete when:** the player can smelt ore into bars and turn
them into a stronger weapon or metal tool at the Workshop.

## 9. Kitchen — Food, Healing, And Buffs

### [ ] 9.1 — Establish edible forage

- Build: add at least one hand-collectible edible ingredient and distinguish raw
  food, seeds, and crafting-only materials in inventory and item-use feedback.
- Player proof: the player can find, collect, save, and consume or reserve food.
- Done when: edible forage is obtainable through normal exploration and never
  conflicts with its recipe-material form.

### [ ] 9.2 — Add the first persistent crop loop

- Build: author one plot and seed with planting, growth, harvesting, and
  reload-safe state. Defer watering, seasons, and large farm management until
  the first loop is proven.
- Player proof: planting now produces a later harvest instead of an instant item.
- Done when: one crop survives area changes and reload, then yields a cookable ingredient.

### [ ] 9.3 — Author the Kitchen building

- Build: add the Kitchen building scene (exterior, collision, depth guide, and
  interaction, with a cauldron or campfire station inside) and place it at the
  home site in Scene Studio.
- Player proof: the Kitchen is visually distinct and easy to find.
- Done when: its recipe family is separate from the Workshop and Forge recipes.

### [ ] 9.4 — Add food and buff recipes

- Build: add at least one healing recipe and one temporary buff recipe with readable
  item descriptions and use feedback through the shared station-aware crafting
  workflow.
- Player proof: preparation changes how the next exploration trip feels.
- Done when: crafted food persists and applies its intended effect once.

### [ ] 9.5 — Add one kitchen tier upgrade

- Build: add a station upgrade and one stronger recipe tier.
- Player proof: the kitchen has a reason to be upgraded.
- Done when: the next tier is locked until the station upgrade is complete.

**Milestone 9 complete when:** the player can forage or farm an ingredient, cook
it at home, and use the result to prepare for exploration.

## 10. Kitchen Potions — Monster-Material Brewing

The separate Alchemy table has been dropped: potions and antidotes are brewed
in the Kitchen, and bombs are crafted at the Workshop (see
[Crafting Buildings](#crafting-buildings--where-each-craft-happens)).

### [ ] 10.1 — Add a brewing station to the Kitchen

- Build: add a brewing station (cauldron) to the Kitchen building as a Kitchen
  upgrade or a second station inside it. It shares the Kitchen's recipe
  context.
- Player proof: the Kitchen visibly gains a place to brew.
- Done when: Scene Studio and the runtime show the same station, and it
  persists.

### [ ] 10.2 — Add potion-family recipes

- Build: add healing potions, antidotes, and at least one recipe that needs a
  monster material. Add the first bomb recipe to the Workshop.
- Player proof: enemy drops now unlock several ways to prepare for a trip.
- Done when: ingredients, output capacity, and recipe feedback are reliable.

### [ ] 10.3 — Add the brewing tier step

- Build: upgrade the brewing station once to unlock a stronger potion tier.
- Player proof: the player can see what the next expedition requires.
- Done when: tier ownership and crafted items survive reload.

**Milestone 10 complete when:** enemy materials support a clear preparation loop
through Kitchen potions.

## 11. Builder’s Table — Upgrades And Moving The Home

### [ ] 11.1 — Place the builder’s table

- Build: author the station and its editor/runtime interaction path.
- Player proof: the home now has a visible construction center.
- Done when: its recipe family is distinct from crafting consumables and weapons.

### [ ] 11.2 — Add visible home upgrades

- Build: add one home upgrade that changes interior or exterior visuals, capacity,
  or available functionality.
- Player proof: resources spent at home produce a visible improvement.
- Done when: the upgrade is represented in authored content and saved state.

### [ ] 11.3 — Add furniture, storage, and defenses

- Build: add the first placeable furniture/storage piece and one defensive piece,
  each with clear collision and interaction rules.
- Player proof: the home becomes more useful and more personal over time.
- Done when: placed pieces are editable, persistent, and not duplicated on reload.

### [ ] 11.4 — Make the one home movable

- Build: add the move-home flow through the builder’s table; preserve the home’s
  stable identity, interior link, upgrades, furniture, and storage contents.
- Player proof: the player can relocate the home without losing its progress.
- Done when: moving once and reloading produces the same home at its new location.

### [ ] 11.5 — Verify Scene Studio support for moving home content

- Build: support placing and editing the exterior anchor, interior link,
  crafting buildings, furniture, defenses, visual bounds, and collision guides
  in Scene Studio.
- Player proof: editor-authored home content matches what appears in play.
- Done when: the map checker rejects broken home/interior references clearly.

**Milestone 11 complete when:** the home is visibly upgradable, useful, and movable
without losing its interior or persistent contents.

## 12. Safety, Recovery, And Storage

### [ ] 12.1 — Decide and document safety rules

- Build: resolve how map conditions and nearby enemies determine home safety,
  including what recovery is allowed when the home is unsafe.
- Player proof: the player can understand the current safety state.
- Done when: the rule is written before it is encoded in gameplay.

### [ ] 12.2 — Add safety and recovery feedback

- Build: show safe/unsafe state, recovery outcome, and any nearby-enemy reason.
- Player proof: returning home reduces uncertainty instead of creating a hidden rule.
- Done when: the same conditions always produce the same result.

### [ ] 12.3 — Add persistent storage

- Build: implement storage capacity, item transfer, save/load, and failure feedback.
- Player proof: the home can hold supplies for a later expedition.
- Done when: stored items remain correct after moving home and reloading.

### [ ] 12.4 — Verify recovery and no-loss behavior

- Build: test death, unsafe-home arrival, interrupted transitions, and full storage.
- Player proof: failure is understandable and does not silently erase progression.
- Done when: the agreed recovery/storage rules hold in repeated playtests.

**Milestone 12 complete when:** the home is a dependable planning point without
being an automatic invulnerability zone.

## 13. Recipe Discovery, Content, And Balance

### [ ] 13.1 — Decide recipe discovery

- Build: choose whether recipes are learned by station tier, exploration, quests,
  drops, or another documented rule.
- Player proof: the player knows how to find the next recipe.
- Done when: the discovery rule is written and testable.

### [ ] 13.2 — Set material tiers and biome distribution

- Build: define the exact wood/stone/iron/rare-material path and where each tier appears.
- Player proof: each new region introduces a recognizable resource goal.
- Done when: no recipe requires a material with no reachable source.

### [ ] 13.3 — Set enemy drops and recipe counts

- Build: author enemy drop tables and target recipe counts per workstation family.
- Player proof: fights and exploration advance the next station goal at a readable pace.
- Done when: early recipes are attainable and high-tier recipes remain aspirational.

### [ ] 13.4 — Tune progression pacing

- Build: balance harvest rates, station upgrade costs, tool durability/repairs if used,
  enemy difficulty, and recipe outputs.
- Player proof: the loop feels motivating rather than stalled or finished too quickly.
- Done when: a fresh playtest reaches the next milestone without debug grants.

**Milestone 13 complete when:** the resource, enemy, station, and recipe systems
form one understandable progression path.

## 14. Beta Slice — Complete Playable Loop

### [ ] 14.1 — Run the full first-version loop

- Build: connect exploration, resource gathering, combat, drops, home return,
  station crafting, home upgrade, and tougher-area access.
- Player proof: the player always has a clear next goal.
- Done when: a fresh save can complete the loop without debug shortcuts.

### [ ] 14.2 — Verify authored-map workflow end to end

- Build: create or edit an outdoor region, home exterior, interior, resource
  node, enemy camp, crafting building, and exit through Scene Studio.
- Player proof: editor-authored content is playable immediately after validation.
- Done when: `pnpm scenes:check`, `pnpm maps:check`, and the runtime agree on
  every authored reference.

### [ ] 14.3 — Do the motivation and readability pass

- Build: improve task feedback, loot visibility, station lock messaging, map hints,
  and milestone notifications where playtests show confusion.
- Player proof: progress feels visible after every short session.
- Done when: a new player can explain what to gather, where to go, and what to upgrade.

### [ ] 14.4 — Harden saves, transitions, and performance

- Build: extend and harden the Roadmap P save/load foundation under home moves,
  interior transitions, full inventories, enemy camps, repeated station use,
  and larger multi-map snapshots; fix duplication, loss, and softlock cases.
- Player proof: progress feels safe enough to keep playing.
- Done when: the target beta loop is stable and no known progression blocker remains.

**Milestone 14 complete when:** Slime Isa delivers a motivating gather → fight →
upgrade home → craft → tackle tougher area loop with authored interiors and maps.

## Immediate Next Sprint

Milestones 1 and 2, the save/load foundation, and the universal scene
refactor are complete. The current sprint is **Audio** (Milestone A); then
Milestone 3.

1. Finish A.0 and A.1 (audio loading and node upgrades) and get `pnpm check`
   passing again. The in-progress `propertyDescriptors.ts` change currently
   breaks `scenes:check` and typecheck.
2. Build the synth bake tool and the P1 synth cues. Get approval before
   downloading the Kenney library packs.
3. Wire the P1 cues into scenes and the `AudioEventBridge`, then verify them in
   the browser preview.
4. Do the synth vs. library A/B listen and delete the losing flavour.
5. Start Milestone 3 (home exterior). Draft the replacement for the deleted
   station-aware crafting doc before Milestone 5, following
   [Crafting Buildings](#crafting-buildings--where-each-craft-happens).

A.5 and A.6 (world sounds, music, settings) can run alongside Milestone 3.
Keep the legacy debug grant clearly separated from production progression.

## Cross-Cutting Engine — Universal Scene Architecture

Design:
[Godot-inspired universal scene node architecture](./superpowers/specs/2026-09-12-godot-inspired-universal-scene-node-architecture-design.md).
Plan:
[Universal scene node full refactor](./superpowers/plans/2026-09-12-universal-scene-node-full-refactor-implementation-plan.md).
Evidence:
[Final implementation report](./superpowers/plans/evidence/universal-scene-final-report.md).

### [x] S.1 — Author every world as a scene

- Result: world scenes nest authored placements and navigation areas and use
  shape-based world areas. Production loads authored worlds only, and the
  cutover was atomic.

### [x] S.2 — Mount UI and audio as authored scenes

- Result: the HUD, weapon hotbar, ability bar, health and boss bars, area title
  and floating text, inventory, chest panel, crafting, quest journal and offer,
  world map, level-up modal, canvas minimap, and the global audio composition
  are authored UI and audio scenes.

### [x] S.3 — Move behavior to ScriptNodes and retire the legacy paths

- Result: behavior lives in registered TypeScript ScriptNodes, and scene
  documents store data only. The direct entity factories, world adapter,
  temporary chest and boss UI bridges, and old category editors are retired.
  `scene-ownership:check` guards against their return. Fatty is a ranked enemy
  that uses the ordinary enemy capabilities. The object catalog stays as a
  read-only validator, and NPC identity and placement stay as project data.

### [x] S.4 — Ship one editor: Scene Studio

- Result: `?studio=scenes` edits every scene and external resource with a shared
  inspector, undo/redo, hash-checked saves, and instance overrides you can
  revert. It adds document tabs, editable depth guides, animation keys set from
  the timeline, viewport, and inspector, and boss links. Resources follow
  Godot's sub-resource convention. Legacy editor URLs redirect here.

### [x] S.5 — Hold performance and verification

- Result: `pnpm check` and 43 real-Chromium browser cases pass. On the large
  `tiktok` map, the main thread does 9–14% less work per frame than before the
  refactor. The user gameplay checklist was covered by the Milestone 2 playtest
  on 2026-09-28.

## Cross-Cutting Persistence

Implementation order, schema ownership, UI behavior, migration rules, and the
acceptance matrix are defined in the
[Named save, load, and reset implementation plan](./superpowers/plans/2026-08-24-named-save-load-reset-implementation-plan.md).

### [x] P.1 — Define immutable initial game state

- Build: declare `level-1.map.json` as the initial authored map and move the
  initial player stats, equipment, inventory, location, and quest defaults into
  one content-owned initial-state definition.
- Player proof: starting or resetting a run always produces the same intentional
  Level 1 setup without rebuilding inventory ad hoc in `WorldScene`.
- Current: `src/game/content/initial-state/InitialRun.ts` owns the fresh-run
  player, starter inventory, quests, Level 1 location, and empty map progress;
  `GameState` and Reset Run consume fresh clones from that factory.
- Done when: authored map files and the initial-player definition are the only
  sources used to create a new run.

### [x] P.2 — Store runtime progress per map

- Build: replace the flat resource-state collection with a map-keyed runtime
  state model. Each `mapId` owns deltas for its stable object instances,
  resources, encounters, boss respawn timers, chest contents, rewards, gates,
  and future placed content; authored map JSON remains unchanged and acts only
  as the baseline.
- Player proof: leaving Level 1, changing another map, and returning restores the
  correct state of both maps independently.
- Current: `WorldProgress` stores map-keyed resource, collectible, inventory-drop,
  encounter, boss-camp timer, partial chest-content, reward, gate, and object-state
  containers. Save schema version 9 preserves that state, retains unknown map
  IDs, and migrates legacy composite resource keys at the progress boundary.
- Done when: a save can contain state for multiple maps and loading one map never
  discards state belonging to another.

### [x] P.3 — Add named save records with explicit overwrite

- Build: add a save index and independent named snapshot records. Save first
  shows existing records, then lets the player explicitly overwrite one selected
  record or create a new named record with a new stable ID. Overwrite requires
  confirmation and never changes another record. Keep one separate recovery
  autosave that never appears as a user-created named save.
- Player proof: the player can create several named moments and see their name,
  last-saved time, current map, and player level before deciding whether to
  overwrite or create new.
- Current: the repository now owns an indexed, newest-first list, independent
  snapshot keys, recovery autosave, name validation, explicit conflict errors,
  rollback-safe create/overwrite/delete, schema guards, and legacy-envelope
  migration.
- Done when: new-save and overwrite paths are explicit, canceling an overwrite
  changes nothing, and older schemas migrate through validators instead of casts.

### [x] P.4 — Add Save, Load, and Reset controls

- Build: replace the ambiguous Restart Map action with three explicit controls:
  **Save Game**, **Load Game**, and **Reset Run**. Save opens the snapshot browser
  with **Overwrite** and **Create New Save** actions; Load opens the same records
  in load mode; Reset confirms, discards only the active runtime state, restores
  the initial player, and starts from the authored Level 1 map. Named saves
  remain untouched unless the player explicitly overwrites or deletes one.
- Player proof: the player can understand whether an action creates a snapshot,
  loads one, or begins again from defaults before confirming it.
- Current: Development Tools now exposes Save Game, Load Game, and Reset Run
  modals with explicit overwrite confirmation, delete confirmation, name
  validation feedback, operation locking, Escape/backdrop close, focus return,
  and a persistence pause event. Typed handoffs rebuild the normal map-load path.
- Done when: the controls pause gameplay safely, report failures, clean up their
  listeners, and rebuild the world through the normal map-loading path.

### [x] P.5 — Verify complete multi-map round trips

- Build: add schema/repository tests and a manual two-map playtest covering
  partial resource damage, depleted objects, inventory, equipment, player
  position, quests, boss respawn timing, partial and empty chests, keyed gates,
  map transitions, new saves, confirmed/canceled overwrites, reset, and load.
- Player proof: any named snapshot restores one coherent moment—player and every
  visited map agree—while Reset Run reliably returns to untouched Level 1.
- Current: schema tests, including boss timers and partial chest contents,
  persistence tests (20/20), authored-content checks, and the production build
  are green. A local browser pass already covers named create/conflict/overwrite/
  load and modal focus. The reset click, the boss/chest/gate state matrix, and
  the manual Level 1 → Gloop Forest → Level 1 round trip were verified by the
  user on 2026-09-28. The old Windows Character Studio `EPERM` blocker went
  away when Character Studio was retired.
- Done when: the persistence acceptance matrix passes, corrupted saves fail
  visibly without damaging valid snapshots, and `pnpm check` passes.

**Persistence foundation complete (verified 2026-09-28):** authored maps remain immutable
defaults, named saves are independent snapshots, every visited map keeps its own
runtime deltas, and Reset Run restores Level 1 plus the initial player without
deleting saved games.

## Cross-Cutting Gameplay Configuration

The phased ownership, migration rules, and acceptance gates are defined in the
[Central gameplay configuration implementation plan](./superpowers/plans/2026-08-26-central-game-constants-implementation-plan.md).

### [x] C.1 — Define central gameplay configuration ownership

- Build: add the validated JSON source, strict schema, pure validator, readonly runtime gateway, and repository checker.
- Current: invalid configuration fails before game startup, and runtime code imports the frozen gateway instead of the JSON document.
- Done when: configuration validation, item-ID parity, ownership guards, typecheck, and production build pass.

### [x] C.2 — Centralize inventory tuning

- Build: centralize initial capacity and item/weapon stack limits, then persist mutable per-run capacity with legacy migration.
- Current: stack rules and initial capacity are centralized; mutable per-run capacity is persisted, and legacy overflow expands capacity without dropping items.
- Done when: capacity upgrades and legacy overflow survive every save path without item loss.

### [x] C.3 — Centralize player character tuning

- Build: centralize initial attributes, movement, protection, base combat values, level cap, XP requirements, and level gains.
- Current: player defaults, global rules, level cap, XP requirements, and level gains are centralized. Saves persist level/current XP and legacy cumulative XP migrates through explicit clamp rules.
- Done when: saved level/current XP drive table-resolved stats and legacy saves migrate without synthetic rewards.

### [x] C.4 — Add Character Studio constants authoring

- Build: add independent validated editing and atomic persistence for gameplay constants.
- Current: the primary-player inspector provides a separate gameplay-defaults draft, validation/history, conflict-aware atomic save, progression ledger, and max-level controls.
- Done when: package and gameplay-default edits have separate revisions, dirty states, conflicts, and save actions.

### [ ] C.5 — Migrate remaining shared gameplay defaults by domain

- Build: move additional cross-feature balance values only after classifying each as a default, global rule, or mutable saved value.
- Done when: each migrated value has one named owner and focused runtime and persistence coverage.

## Cross-Cutting Player Experience

### [x] UX.0 — Make Escape close the topmost UI surface

- Build: add a shared modal stack and route Escape through it for inventory,
  crafting, world map, quest journal, level-up, chat, shop, persistence
  dialogs, and future dashboards.
- Current: the shared `ModalStack` owns LIFO ordering, document-capture Escape
  routing, token-scoped cleanup, nested-surface handling, and stale-registration
  protection. Current gameplay and DOM surfaces no longer install independent
  Escape listeners. Transient persistence dialogs unregister after successful
  close and remain topmost while busy. Escape dismisses a pending level-up
  without spending the point; `P` reopens the same choices only when idle.
- Player proof: pressing Escape closes only the currently active surface, and
  nested dialogs close from the top down.
- Done when: runtime keyboard/DOM-focused playtests confirm every current
  surface closes correctly, pause state remains correct, and complete project
  verification passes. The implementation design is documented in
  [Escape closes open overlays](./superpowers/specs/2026-08-26-escape-closes-overlays-design.md).

### [ ] UX.0.1 — Apply artwork-first in-world HUD surfaces

- Build: omit the compact-frame asset from the visible HUD and six-slot weapon
  hotbar, then remove dark slot fills, filled key plates, and heavy shadows.
  Keep the organic minimap border, transparent meter tracks, compact labels,
  and clear active-slot treatment; use a low-opacity minimap tint only for
  marker readability.
- Scope: `HUD.ts`, `Minimap.ts`, and `WeaponHotbar.ts`. Inventory and crafting
  remain separate work; `AbilityBar.ts` remains deferred until it is mounted in
  `WorldScene`.
- Player proof: the grass/world art remains visible through the three widgets,
  all values fit at wide, medium, and narrow viewports, and active/owned/
  unavailable states remain understandable.
- Done when: the approved visual treatment passes the manual viewport matrix,
  resize and pointer behavior remain correct, inventory/crafting are untouched,
  and the scoped typecheck/build checks pass. See
  [World HUD Artwork-First Presentation](./superpowers/specs/2026-09-04-world-hud-artwork-first-design.md).

### [ ] UX.1 — Unify the bottom action dashboard and loadout workflow

- Build: compose the existing six weapon/tool slots and fixed ability slots into
  one responsive bottom dashboard. Add weapon assignment by drag/drop and an
  accessible **Equip to slot 1–6** control, both routed through the existing
  loadout authority. Follow
  [Player action dashboard and loadout assignment](./task/ideas/open/player-action-dashboard-and-loadout.md).
- Player proof: weapons, tools, abilities, hotkeys, cooldowns, locks, and the
  active weapon are readable in one place.
- Done when: both assignment methods produce identical saved state, swaps never
  duplicate items, and the dashboard works on narrow through ultrawide layouts.

### [ ] UX.2 — Make crafting building-aware without duplicating the popup

- Build: refactor the authored crafting UI scene and the recipe catalog to
  filter recipes by unlock, context (`portable`, Workshop, Forge, or Kitchen),
  and building tier. Rename the `workbench` context to `workshop` and remove
  `alchemy`. Validate the transaction before consuming ingredients. The earlier
  design doc was deleted, so write a new spec from
  [Crafting Buildings](#crafting-buildings--where-each-craft-happens) before
  Milestone 5.
- Player proof: opening crafting in the field or at a building shows the right
  recipes and explains every lock.
- Done when: all station families use one component and recipe authority, wrong
  stations cannot craft a recipe, and failed output never consumes materials.

### [ ] UX.3 — Add authored weapon dropping and pickup

- Build: give every droppable weapon an explicit ground visual and physical
  pickup definition, then route inventory removal, equipped/hotbar cleanup,
  map-scoped persistence, and recollection through the shared world-drop
  lifecycle. Define unique-weapon and full-inventory behavior before enabling
  the action.
- Player proof: the player can discard excess weapons into the world, recognize
  each weapon on the ground, leave or reload, and pick it up again later.
- Done when: no weapon can be duplicated or lost across drop, pickup, map
  transition, save/load, equipped state, or a full inventory.

## Cross-Cutting World Authoring

### [ ] E.1 — Build the shared world graph and all-map organizer

- Build: project one validated world graph from authored exits; add draggable
  map-preview cards and north/east/south/west connectors to Scene Studio, then
  rebuild the player full-map view from the same graph. Preserve dropdown
  connection editing as the accessible fallback. Follow
  [Shared world map and Map Studio graph](./task/ideas/open/global-map-and-map-joining.md).
- Player proof: creators can see and organize every map, while players get a
  useful discovered-world representation with current location and locked exits.
- Done when: visual connectors and dropdowns edit the same reciprocal links,
  graph layout never changes map-local content, and runtime/editor/validator all
  agree on neighbors.

### [x] E.2 — Terrain is ground; walls are placed objects

- Build: ground tiles stay plain textured terrain with organic blended borders
  (`TerrainBlendField`). Crystal clusters and forest trees become real object
  scenes (sprite plus a collision shape fitted to the rock or trunk base), placed
  as instances in the world scenes, the same way interior furniture works. A
  one-time conversion replaces `crystal-wall` / `tree-wall` cells with floor plus
  placed objects. Water collision merges neighbouring solid cells into larger
  rectangles instead of one body per cell.
- Player proof: caves and forests read as scenes of real objects; bumping into a
  crystal or trunk stops the player where the art is, not on a square cell.
- Done when: crystals and trees are selectable, movable, and deletable in Scene
  Studio, no world uses wall tiles for them, and water uses merged collision.

### [ ] E.3 — Shallow water and deep water

- Build: split water behaviour by tile. Shallow `water` is walkable but slows
  movement (with a wading visual such as a lower body cut or ripple); only
  `deep-water` blocks. Keep the rule in the tile set (a movement modifier on the
  tile), not in map data, so every map picks it up.
- Player proof: the player can wade through rivers and puddles more slowly, but
  deep lakes stay a barrier.
- Done when: shallow water applies the speed modifier and visual, deep water
  blocks, enemies respect the same rules, and existing maps are reviewed so
  shallow crossings and deep barriers are intentional.

### [ ] E.4 — Swimming with the right equipment

- Build: add a swimming ability unlocked by equipment (for example flippers or
  a swim charm). With it equipped, deep water stops blocking and the player
  swims (swim animation, slower speed, no attacking or item use while swimming);
  without it, deep water stays a barrier.
- Player proof: deep lakes that were barriers become explorable once the player
  finds or crafts the swimming gear, opening islands and hidden areas.
- Done when: the gear toggles deep-water passability for the player only,
  swimming state persists across saves and area changes safely, and at least one
  area is gated behind deep water.

## Cross-Cutting Rendering Quality

### [~] R.1 — Stabilize pixel rendering during movement

- Build: replace the unsuccessful fractional-grid snapping path with fixed-step
  physics plus interpolated presentation transforms, a responsive camera
  deadzone, refresh-independent camera damping, and intentional high-DPI output
  scaling without mass-rescaling source artwork.
- Current: the core runtime fix is implemented: default integer `1.0` zoom,
  explicit smooth overview levels, fixed-step presentation interpolation,
  post-physics visual synchronization, responsive deadzone, time-based camera
  damping, ten-speed tuning ladder, and expanded diagnostics/tests. Hardware
  capture and device-pixel/output-scaling approval remain. The plan is documented in
  [World Motion Rendering Instability](./task/bugs/world-motion-rendering-instability.md).
- Player proof: terrain, characters, attachments, projectiles, and effects remain
  stable while moving; the camera stays still inside its responsive deadzone and
  follows the interpolated player smoothly outside it. Normal gameplay defaults
  to integer `1.0` zoom; fractional wheel levels remain smooth overview modes.
- Done when: default `1.0` zoom, fractional overview zoom, and the ten-speed
  movement ladder pass the documented refresh-rate/device-pixel motion matrix,
  responsive resize keeps the canvas and screen UI aligned, teleports reset
  interpolation, wheel zoom remains stable, and complete verification passes.

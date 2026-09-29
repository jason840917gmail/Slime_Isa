# Game Roadmap — Road to Release 1

> **Status: active living checklist.** Design direction lives in
> [Game Guidelines](./GAME_GUIDELINES.md); this file owns task order and
> status. Reorganized on 2026-09-29 around **Release 1**. The former
> `BETA_PLAN.md` was folded into this file and the guidelines, then removed.

## Release 1 (v0.1) — The Target

Release 1 is a free web build of **Chapters 1 and 2**, about an hour of play
from the title screen to an end-of-Chapter-2 card: a first-time player takes
**45–75 minutes**, timed in the blind playtest (11.1). In it, a player can:

- start from a title screen, continue an autosave, pause, change settings, and
  wake at their last bed after a defeat;
- finish Chapter 1 in Slimeshire Meadow (playable today), then Chapter 2 in
  Gloop Forest: a new enemy, iron, an enemy-only material, the Forge, metal
  gear, and a second boss;
- restore two Slimeshire buildings, the Workshop and the Forge, and use them
  to craft the recipes they unlock;
- grow stronger through crafted gear, Goo Hearts, and story-unlocked
  abilities (no XP or levels);
- use **Gulp**, the signature mechanic, to solve Chapter 2 puzzles;
- hear music and ambience in every area and feel every hit.

**Not in Release 1:** the Kitchen, farming, hats, Crystal Caverns beyond a
locked teaser, the unconnected `icege`/`emberleef`/`hot` maps, the mobile app,
and new Scene Studio features. They wait in
[After Release 1](#after-release-1--idea-parking-lot).

**No target date.** Release 1 ships when it is ready. By choice, milestones
are ordered but not sized or dated (decided 2026-09-29).

### Rules That Keep Release 1 Shippable

- **New ideas go to the [parking lot](#after-release-1--idea-parking-lot)**,
  never straight into a Release 1 milestone. An idea moves in only by replacing
  work of the same size.
- **Scene Studio is feature-frozen.** Fix bugs and real blockers for Release 1
  content only. Tooling is not progress unless a player can see the result.
- **Every milestone lists its art and audio.** Placeholders are fine while
  building; a milestone is `[x]` only when its assets are final or explicitly
  accepted as final. All new art follows the
  [art style guide](./assets/visual-style-guide.md) and is generated with
  Magnific following the [Magnific MCP guide](./assets/magnific-mcp-guide.md),
  then packed and registered through [docs/assets/](./assets/README.md).
- **New features prove they are fun first.** A new mechanic (Gulp, the slime
  trail, a new enemy behavior) is built in the dev-only `playground` map
  (3.7). It enters chapter content only after the user accepts it there.
- **Testing:** at the end of each milestone (not after every task), Claude
  plays the milestone's player proofs once in the in-app browser and reports
  what works. The user does the final acceptance. Players who have never seen
  the game test twice: after the game shell (4.9) and before release (11.1).
- **A task is `[x]` only when a fresh save can do it in the running game**,
  without debug grants.
- **Finish milestones in order.** Two exceptions: the rough Gulp prototype
  (7.0) runs right after the playground (3.7), and Milestone 9 (game feel) may
  run alongside 6–8. No task's check depends on a later milestone; work that
  needs later content lives in the milestone that builds that content.

## Progress Board

| # | Milestone | Player-visible result | Status |
|---|---|---|---|
| 1 | Wood gathering | Chop a tree and keep the wood | `[x]` |
| 2 | Stone and starter tools | Craft starter gear, beat Fatty One Eye, open the Verdant Gate | `[x]` |
| Q | Chapter 1 — The Clearing | Six NPC quests lead from an empty clearing to Gloop Forest | `[x]` |
| P | Save, load, and reset | Named saves, recovery autosave, per-map progress | `[x]` |
| S | Universal scene architecture | Every world, entity, UI, and audio surface is an authored scene | `[x]` |
| **Release 1** | | | |
| 3 | Finish homes, interiors, and audio | Beds are home, interiors are solid and persistent, today's content sounds finished | `[~]` |
| 4 | Game shell | Title, continue, pause, game over, settings, credits | `[ ]` |
| 5 | Gear-based progression | XP and levels are gone; gear, Goo Hearts, and story unlocks make you stronger | `[ ]` |
| 6 | Rebuild Slimeshire: the Workshop | Restore a ruined building and craft at the Workshop | `[ ]` |
| 7 | Gulp | Swallow a material to take its form and solve a puzzle | `[ ]` |
| 8 | Chapter 2 — Gloop Forest | New enemy, iron, Forge, metal gear, second boss | `[ ]` |
| 9 | Game feel | Hit-stop, shake, squash and stretch, particles, slime trail | `[ ]` |
| 10 | Release hygiene | Small download, production-only content, licenses, browsers | `[ ]` |
| 11 | Playtest and ship | Blind playtest, fixes, `v0.1.0` published | `[ ]` |

Why this order: 3 closes the work already half done. 4 gives every later
playtest a real start and end. 5 comes before new content so Chapter 2 is
balanced once, against gear. 6 and 7 build the systems Chapter 2 uses. 10 and
11 turn the build into a release.

## How To Use The Checklist

- `[ ]` not started, `[~]` in progress, `[x]` verified in the running game,
  `[—]` dropped (keep the line and say why).
- After each milestone, do a short fresh-save playtest and note what became
  possible.
- Unresolved design choices go to the guidelines'
  [open questions](./GAME_GUIDELINES.md#open-questions), not into silent rules.

Task tile format:

```md
### [ ] 6.1 — Short task name

- Build: the smallest implementation or content change.
- Player proof: what the player can see or do afterward.
- Done when: the concrete acceptance check passes.
```

Each milestone ends with an **Assets** list: what can be reused and which new
art or audio must be made. See [docs/assets/](./assets/README.md) for sizes,
packing, and registration.

## 3. Finish Homes, Interiors, And Audio

The home stays in Slimeshire (Level 1) and never moves. Other maps can have
their own homes with their own interiors, linked by doors. The last bed slept
in is where the player wakes.

### [x] 3.1 — Doors link to doors (was 4.1)

- Done: `game.door` ScriptNodes name a `targetDoorId` and own an `arrival`
  child, so leaving a house puts the player in front of the door they used.
  Level 1 doors lead to `slime-home` and `mushroom-home` and back; a test checks
  that every door targets an existing door with an arrival.

### [x] 3.2 — First interior visual kit (was 4.2)

- Done: `wood-floor` terrain plus one `object.interior-<category>-*` scene per
  atlas sprite (842 scenes, generated from `scripts/interiors/interior_catalog.py`).
  `world.slime-home` and `world.mushroom-home` are furnished rooms.

### [x] 3.3 — Enter, move, and leave (was 4.4)

- Done: F near a door travels through the queued navigation path; interior
  worlds use a fixed camera that fits the room; a bobbing F badge marks the
  door, chest, or NPC in range.

### [~] 3.4 — Beds are home (was 3.3)

- Build: sleeping in a bed saves `world.respawnPoint`; defeat returns the
  player to that bed's map and wake point, falling back to the Level 1 start.
- Player proof: sleep in a bed, get defeated elsewhere, wake at that bed.
- Done when: the respawn bed survives save/load and falls back to Level 1 when
  the bed's map no longer has it.

### [~] 3.5 — Interior collision and interaction (was 4.5)

- Current: `game.bed` scripts on sleepable beds; F plays the `doze`/`sleep`
  clips with floating z's and restores `rest.sleepHpRegenPerSec` HP/s; input or
  damage wakes the player.
- Build: block walls and solid furniture everywhere in both rooms.
- Done when: collision, interaction, and depth are correct from every direction.

### [~] 3.6 — Persist placed furniture (was 4.6)

- Current: the workbench is placed from the inventory with a grid-snapped
  preview (R variant, Esc cancel), saved per map as `placedFurniture`, and
  picked up with G.
- Done when: placed furniture in homes and outdoors survives leaving, reload,
  and a second placement without duplication.

### [ ] 3.7 — The playground map

- Build: a dev-only `playground` world scene for trying new mechanics: open
  ground, a few enemies, resource nodes, and room for test puzzles. It is
  reachable with `?map=playground` in development and left out of production
  builds. Today every world ships, so this task adds the dev-only world list
  that keeps it out; 10.2 later adds the other test maps to the same list. It
  is built early because 4.7, 7.x, 8.2, and 9.4 test in it.
- Player proof: a new feature can be tried in isolation before any chapter
  depends on it.
- Done when: the map opens with `?map=playground`, `pnpm scenes:check`
  passes, and a production build does not contain it.

Interior authoring in Scene Studio (was 4.3) is not a separate task: the next
interior, the Gloop Forest hut, is built in 8.8 with Scene Studio as it is
today, and only real blockers get fixed.

### [ ] 3.8 — Pick one sound flavour (was A.4)

- Build: compare synth and library takes per category, delete the losing
  flavour, and remove the `?sfx` toggle.
- Done when: each cue ID has one shipped flavour and `assets:check` finds no
  orphans.

### [~] 3.9 — World sounds for today's content (was A.5)

- Current: terrain footsteps, status, chest, gate, NPC, and area-title cues
  exist, and Level 1 plays its town music.
- Build: prop loops for the campfire, cauldron, grindstone, and anvil; Level 1
  ambience; interior ambience or music.
- Player proof: Slimeshire sounds alive and props can be heard as you approach.
- Done when: each of the four props plays its loop within hearing range and
  fades out when the player walks away; Level 1 and both interiors each have
  ambience or music; `pnpm audio:check` passes.

### [~] 3.10 — Audio polish (was A.6)

- Current: the Esc sound modal has master, effects, and music sliders plus
  mute, saved per device by `AudioSettingsStore`.
- Build: duck music while paused, crossfade on `area.enter`, switch to boss
  music on `boss_spawn_requested`, and pass the crit flag to hit sounds.
- Done when: music transitions never stack or cut off abruptly.

The cue list, hooks, and sourcing rules are in the
[Audio & SFX implementation plan](./superpowers/plans/2026-09-28-audio-sfx-implementation-plan.md).

**Milestone 3 complete when:** the home and bed loop works across defeat,
save/load, and map changes, and today's content has final sound and music.

**Assets**

- Reuse: interior catalog, `house-*` exteriors, the CC0 library packs listed in
  `asset/audio/CREDITS.md`, `level-1-home-town.ogg`.
- [ ] Ambience loops: meadow day, forest, interior.
- [ ] Prop loops: campfire, cauldron, grindstone, anvil.
- [ ] Boss music track (CC0 or commissioned).

## 4. Game Shell

Today there is no title, pause, or game-over screen, and Save, Load, and Reset
live in the Development Tools panel (see P.4).

### [ ] 4.1 — Title screen

- Build: New Game, Continue (newest save or recovery autosave), Load,
  Settings, Credits, and the version number. A slow camera pan over Slimeshire
  can serve as the background.
- Player proof: the game starts like a game.
- Done when: every button works on a fresh browser profile and with saves.

### [ ] 4.2 — Pause menu

- Build: Escape with no other surface open pauses and shows Resume, Journal,
  Inventory, Map, Settings, Save, and Quit to Title, routed through the
  existing `ModalStack`. The sound settings become a Settings tab.
- Done when: pause state, Escape order, and resume are correct from every
  surface.

### [ ] 4.3 — Player-facing saves

- Build: move Save, Load, and Reset Run out of Development Tools into the pause
  menu and title screen, and hide Development Tools in production builds.
- Player proof: a player can save, quit, and continue without developer UI.
- Done when: the P.5 persistence matrix still passes through the new menus.

### [ ] 4.4 — Game over

- Build: on defeat, a short screen (what defeated you, time played) with
  "Wake at your bed" and "Load a save".
- Done when: repeated defeats never duplicate the player or lose progress.

### [ ] 4.5 — Settings

- Build: sound (existing), screen shake, reduce motion, and a controls list.
  Settings stay per device, separate from save slots.
- Done when: every setting survives a reload and is readable by gameplay code
  through one settings store. (Milestone 9 checks that its effects obey them.)

### [ ] 4.6 — First-time control hints

- Build: contextual hints for move, attack, dodge, interact (F), inventory,
  and crafting that fade after first use.
- Player proof: a new player never needs a manual.
- Done when: on a fresh save each of the six hints appears once, disappears
  after the player performs that action, and never returns on reload.

### [ ] 4.7 — Credits screen and end-card component

- Build: a credits screen, opened from the title, that reads its entries from
  one credits data file (today: the audio packs in `asset/audio/CREDITS.md`
  and Magnific-generated art), and a reusable end-card screen that any story
  flag can trigger. Chapter 2 hooks the card up in 8.11; 10.3 completes the
  credits list.
- Done when: the credits screen shows every entry in the data file, and
  setting a test flag in the playground shows the end card and returns to the
  title.

### [ ] 4.8 — Artwork-first HUD (was UX.0.1)

- Build: apply the approved artwork-first treatment to the `hud`, `minimap`,
  and `weapon-hotbar` UI scenes. See
  [World HUD Artwork-First Presentation](./superpowers/specs/2026-09-04-world-hud-artwork-first-design.md).
- Done when: the world art shows through the widgets and every value fits at
  wide, medium, and narrow viewports.

### [ ] 4.9 — First fresh-eyes playtest

- Build: two people who have never seen the game play Chapter 1 from the
  title screen while you watch without helping. Note where they get stuck and
  time each run.
- Player proof: Chapter 2 is built on what new players actually did, not on
  guesses.
- Done when: both runs have written notes and a time recorded under this task,
  every blocker they hit is fixed or has its own task, and lessons that affect
  Chapter 2 are carried into the outline (8.1).

**Milestone 4 complete when:** boot → title → new game → play → defeat →
wake → pause → settings → save → quit → title → continue works end to end,
and two new players have played Chapter 1 (4.9).

**Assets**

- Reuse: `ui-organic-modal-frame`, `ui-map-journal-paper`, the existing UI
  sound cues, the player's defeat clip.
- [ ] Game logo (title screen, browser tab icon, store page).
- [ ] Menu button states (normal, hover, pressed, disabled), matching the
      organic frame style.
- [ ] Title music (CC0 or commissioned).
- [ ] Game-over illustration or an animated melted-slime puddle.
- [ ] Control-hint key and mouse glyphs.

## 5. Gear-Based Progression

Decided 2026-09-29: the player gets stronger through gear, not experience.
XP, levels, and perks are removed. See
[Progression](./GAME_GUIDELINES.md#progression-gear-not-levels).

Today XP and levels touch about 36 source files: enemy drops, quest rewards,
the HUD, the level-up modal and perks, save schema v9, `game-constants.json`
level tables, weapon `unlockLevel`, and ability unlocks (Jump at level 2, Squash
Slam 3, Stretch Lash 4, Teleport 5).

### [ ] 5.1 — Retire XP, levels, and perks

- Build: remove XP from enemy drops and quest rewards, the XP bar, the level-up
  modal and its `P` reopen, perks, weapon `unlockLevel`, and the level tables.
  Add a save migration (schema v10) that drops level, XP, and perk data without
  touching anything else.
- Done when: no XP or level text remains, old saves load, and `pnpm check`
  passes.

### [ ] 5.2 — Story-unlocked abilities

- Build: quest and boss rewards can grant abilities, like they grant recipes.
  A Chapter 1 quest teaches Jump (players reach level 2 during Chapter 1
  today). Teleport waits for a later chapter. The ability bar says how a
  locked ability is earned instead of "Lv N". Chapter 2 assigns its two
  abilities in 8.1: Stretch Lash from a Chapter 2 quest, Squash Slam from the
  boss (8.7).
- Player proof: a new ability arrives as a story moment.
- Done when: Jump unlocks from its Chapter 1 quest on a fresh save and
  survives save/load, and the reward type is covered by the quest tests
  (`pnpm test:quests`).

### [ ] 5.3 — Goo Hearts

- Build: a collectible that permanently raises max HP, and hide at least two
  in Slimeshire Meadow. Gloop Forest's hearts are placed in 8.9 and the
  boss's heart in 8.7.
- Player proof: exploring pays off in permanent strength.
- Done when: both Meadow hearts raise max HP by the configured amount, can be
  collected only once per run, and stay collected after save/load.

### [ ] 5.4 — Rebalance Chapter 1 without levels

- Build: set base stats so a fresh run with stone gear matches today's typical
  end-of-Chapter-1 player. Fatty One Eye and the worms keep their current
  numbers and behavior.
- Done when: before 5.1, record how many hits each starter weapon needs to
  defeat a worm brawler and Fatty One Eye, and how many worm hits the player
  survives; after the change, a fresh Chapter 1 run with the same gear matches
  each number within one hit, with no debug grants.

### [ ] 5.5 — Resources respawn

- Build: harvested trees and stone nodes (and later iron nodes) come back after
  a long respawn time set in `game-constants.json`, tracked per map in the
  saved progress like Fatty's respawn timer. Loose starter piles and quest
  rewards still keep a fresh save softlock-free.
- Player proof: returning to a harvested area later finds it grown back.
- Done when: a harvested node respawns after its timer across map changes and
  save/load, and never respawns early.

**Milestone 5 complete when:** the player grows only through gear, Goo Hearts,
and story unlocks, and Chapter 1 still plays as it did.

**Assets**

- Reuse: the area-title banner for "ability learned", Kenney music jingles.
- [ ] Goo Heart world sprite, inventory icon, and pickup effect.
- [ ] HUD heart or max-HP growth display.
- [ ] Ability-learned sting.
- Retire: `ui-levelup-crest-frame` (2.2 MB) and the eight perk icons.

## 6. Rebuild Slimeshire: The Workshop

Crafting buildings are ruined buildings in Slimeshire. Restoring one turns it
into a station the player uses directly and unlocks its recipes; no NPC runs
it. The placeable
workbench stays as the Chapter 1 field station for tier-1 recipes; portable
recipes stay portable so a fresh save cannot softlock.

### [ ] 6.1 — Story-flag scene variants

- Build: a ScriptNode that shows one child subtree per story-flag state, so a
  building can be authored as both ruined and restored in the same world scene,
  including collision. Story flags already persist; quests can already test
  them.
- Player proof: the town changes when the story does.
- Done when: setting the flag swaps visuals and collision, and save/load keeps
  the right variant.

### [ ] 6.2 — Station-aware crafting (was UX.2)

- Build: one crafting popup and recipe catalog filtered by unlock, station
  (`portable`, `workbench`, `workshop`, `forge`), and station tier; explain
  every lock; validate before consuming ingredients. Remove the `alchemy`
  context and move `brew-fizzy` and `weave-tonics` to `kitchen`, where they
  stay unavailable until the Kitchen exists. Write a short spec first.
- Done when: a wrong station cannot craft a recipe, and a failed craft never
  consumes materials.

### [ ] 6.3 — Restore the Workshop

- Build: a ruined Workshop in Slimeshire and a restoration quest paid in
  materials (wood and stone; coins are saved for the later shop and repairs).
  Restoring it swaps the variant (6.1); pressing F at its station opens the
  Workshop recipes.
- Player proof: the player rebuilt part of the town and can see it.
- Done when: the restoration quest completes on a fresh save, and the restored
  Workshop and its station survive leaving the map and save/load.

### [ ] 6.4 — Restoring a building unlocks its recipes

- Build: restoring the Workshop unlocks its tier-1 recipes; upgrading it
  unlocks the next tier. The Workshop crafts everything the workbench does,
  plus its own recipes. Its tier-2 upgrade happens in Chapter 2 (8.6).
- Done when: before restoration the Workshop recipes show as locked with the
  reason, afterwards they are craftable, and the unlock survives save/load.

**Milestone 6 complete when:** the player restores the Workshop and crafts
there, and the town visibly changed.

**Assets**

- Reuse: `decoration-world-solid--tool-bench`, `--anvil`, `--grindstone`, the
  crafting backplates.
- [ ] Ruined Workshop exterior (320 × 320 house frame).
- [ ] Restored Workshop exterior.
- [ ] Restoration effect (dust puff or scaffold) and a construction sound.
- [ ] Workshop header art for the crafting popup (optional).

## 7. Gulp — The Signature Mechanic

The slime eats a Gulp material and takes its form for a while. Each form has a
look and one rule. See
[Gulp](./GAME_GUIDELINES.md#signature-mechanic-gulp).

**Controls (decided 2026-09-29): W is the slime's mouth.** W is already bound
to an unused `eat` action with a short eat clip. No menu ever opens to eat.

| Input | Result |
|---|---|
| Tap W near a Gulp spot | Eat from the world: free, uses nothing from the inventory |
| Tap W anywhere else | Eat the last-used Gulp material from the inventory (costs one) |
| Tap W in a form, away from a Gulp spot | Burp the form away (cancel) |
| Hold W | Quick wheel of carried Gulp materials; the game keeps running; release on one to eat it (from 7.2) |

Eating a different material switches forms; eating the same material at a
Gulp spot resets the timer. **Gulp spots** are world objects (a mossy
boulder, a silk cocoon) that never run out and look different from walk-over
piles, which are collected on contact. Every Gulp puzzle has its spot beside
it, so a puzzle never depends on what the player carries.

### [ ] 7.0 — Rough Gulp prototype

- Build: right after the playground (3.7), and ahead of Milestones 4–6: the
  Heavy form only, with placeholder art, in the playground. Tapping W at a
  stone Gulp spot or with stone in the inventory starts it; tapping W again
  burps it; one rough pressure plate opens one gate. No save/load, no polish.
- Player proof: Gulp can be felt in a day or two instead of on paper.
- Done when: the user has played it and decided keep, change, or drop; the
  verdict and any control changes are written under this task before the
  Chapter 2 outline (8.1) is finished.

### [ ] 7.1 — Gulp action and the Heavy form

- Build: the W controls above for stone, with a proper Gulp spot. Heavy lasts
  **1 minute** (a `game-constants.json` value, tuned after playtests): no
  knockback, holds pressure plates down, moves slower. A HUD timer shows the
  form, and a prompt near a Gulp spot reads "[W] Gulp".
- Player proof: the slime visibly becomes heavier and plays differently.
- Done when: the form starts from a Gulp spot and from the inventory, ends,
  cancels with a burp, and survives map changes and save/load safely (or ends
  cleanly on them); eating never opens a menu; and the user accepts it as fun
  in the playground (3.7).

### [ ] 7.2 — The Sticky form and the quick wheel

- Build: eating silk makes the slime Sticky: it crosses spider webs that would
  catch it normally. Holding W opens the quick wheel of carried Gulp materials.
- Done when: both forms reuse one form system, eating the other material
  switches forms, the wheel picks a form without pausing, and adding a third
  form is data plus art.

### [ ] 7.3 — Gulp puzzle pieces

- Build: stone and silk Gulp spots, a pressure plate linked to a gate (reuse
  `game.gate`), and a web barrier or bridge, all authored in world scenes.
- Done when: the pieces work from Scene Studio placement alone, and a Gulp spot
  can be eaten any number of times.

**Milestone 7 complete when:** the playground has one Heavy and one Sticky
puzzle that a player solves without a hint, and the user has accepted Gulp as
fun.

**Assets**

- Reuse: stone and silk icons, status-effect tints, the player's `eat` clip.
- [ ] Player form-end (burp) clip: new frames on the player sheet or an
      overlay effect.
- [ ] Heavy and Sticky form overlays (stone flecks, silk strands).
- [ ] Two form icons for the HUD timer and the quick wheel.
- [ ] Gulp spots: a stone spot and a silk cocoon, clearly different from
      loose piles.
- [ ] Pressure plate (up and down) and web barrier or bridge sprites.
- [ ] Eat, burp, plate click, and web tear sounds.

## 8. Chapter 2 — Gloop Forest

Chapter 2 turns Gloop Forest from an empty map behind the Verdant Gate into
the second chapter. It absorbs the former milestones 6 (iron), 7 (enemy
materials), 8 (Forge), and 13 (progression pass).

### [ ] 8.1 — Write the Chapter 2 outline

- Build: 5–6 quests in `chapterTwo.ts` form, with givers, objectives,
  rewards, flags, and material sources (resources respawn after 5.5). Assign
  the chapter's abilities: Stretch Lash from a quest, Squash Slam from the boss
  (8.7). Plan the Gulp puzzles and the boss's use of Sticky form around the
  Gulp prototype's verdict (7.0) and the fresh-eyes playtest notes (4.9).
- Done when: the outline is written, every recipe in the chapter has a
  reachable source, it follows the 7.0 verdict, and `pnpm quests:check` passes
  on the stubbed quests. If Gulp changes later in Milestone 7, update the
  outline before starting 8.7 and 8.9.

### [ ] 8.2 — A new Gloop Forest enemy

- Build: add the Forest Orb-Weaver Slime to the roster: behavior, drops, spawn
  areas. Its sprite sheet is already registered in `asset/assets.json` but
  has no enemy type. Try it in the playground (3.7) before placing it.
- Player proof: Gloop Forest has a threat the Meadow did not.
- Done when: the user accepts it in the playground, `pnpm enemies:check`
  passes, and Gloop Forest has at least two orb-weaver spawn areas outside its
  safe zones.

### [ ] 8.3 — An enemy-only material

- Build: the orb-weaver drops a material that the Reinforced Pickaxe (8.4)
  needs. Nothing else in the game drops it.
- Player proof: fighting has a purpose beyond coins.
- Done when: defeating orb-weavers on a fresh save yields the material at its
  configured rate, and it stacks, saves, and reloads with the right count.

### [ ] 8.4 — Iron and the Reinforced Pickaxe

- Build: iron ore nodes in Gloop Forest that need the Reinforced Pickaxe
  (stone plus the enemy material, crafted at the Workshop). The `iron-ore`
  item and its loose pile already exist.
- Player proof: the stone pickaxe fails clearly, the new one succeeds.
- Done when: hitting an iron node with the Stone Pickaxe shows the
  Reinforced Pickaxe hint and deals no damage; the Reinforced Pickaxe breaks it
  into `iron-ore`; the node respawns (5.5).

### [ ] 8.5 — Restore the Forge

- Build: a second restoration using 6.1: a ruined Forge in Slimeshire and a
  Chapter 2 quest to rebuild it. The player uses the restored Forge directly to
  smelt iron ore and charcoal into iron bars; it never outputs weapons.
- Done when: bars are crafted, stacked, and saved correctly.

### [ ] 8.6 — Metal gear and the Workshop's second tier

- Build: upgrade the Workshop to tier 2 with bars, then craft an iron spear or
  sword and an iron axe.
- Player proof: ore → Forge → bar → Workshop → stronger weapon.
- Done when: the tier-2 recipes stay locked until the upgrade, the upgrade
  persists, and the iron weapon defeats an orb-weaver in fewer hits than the
  Stone Spear.

### [ ] 8.7 — The Chapter 2 boss

- Build: one boss on the Fatty model: a telegraphed signature attack, boss
  bar, arena leash, guarded reward, and persisted defeat. Proposal: the
  **Orb-Weaver Matron** webs the arena, and Sticky form lets you cross her
  webs. She drops a Goo Heart and teaches Squash Slam. Write a short spec
  first.
- Done when: every attack has a telegraph of at least half a second; the
  user beats her with Chapter 2 gear; defeat, save/load, and leaving the arena
  reset or persist her as the spec says; the heart and Squash Slam are granted
  exactly once.

### [ ] 8.8 — A second home in Gloop Forest

- Build: a hut exterior and furnished interior with a bed, so Chapter 2 has its
  own respawn point. Build the interior with Scene Studio as it is today (this
  replaces the old interior-authoring task 4.3); write the steps in a short
  note in `docs/knowledge/` and fix only real blockers.
- Done when: the hut's doors link both ways, sleeping in its bed sets the
  respawn point, and the room was built without hand-editing JSON (or the
  blockers are listed with their fixes).

### [ ] 8.9 — Gulp puzzles and hearts in the world

- Build: at least three Gulp puzzles in Gloop Forest, each with its Gulp spot
  beside it, and at least two hidden Goo Hearts, one of them behind a puzzle.
- Done when: a playtester solves each puzzle without a hint, and each heart is
  collectable once and persists.

### [ ] 8.10 — Build the Chapter 2 quests

- Build: turn the 8.1 stubs into full quests in `chapterTwo.ts`, alongside
  8.2–8.9: givers (existing NPC sheets unless the outline asks for new art),
  dialogue, objectives, rewards, the Stretch Lash grant, a chapter banner, and
  the `chapter-2-complete` flag. The Forge restoration quest (8.5) is one of
  them.
- Player proof: Chapter 2 is guided step by step, the way Chapter 1 is.
- Done when: `pnpm quests:check` and `pnpm test:quests` pass; on a fresh save
  every quest can be accepted and completed in order without debug grants;
  and Stretch Lash is granted exactly once and survives save/load.

### [ ] 8.11 — Close the chapter

- Build: the exit to Crystal Caverns stays locked with a "Chapter 3" hint, and
  finishing Chapter 2 sets the flag that shows the end card (4.7).
- Done when: a fresh run reaches the end card without debug grants.

**Milestone 8 complete when:** Chapter 2 plays from the Verdant Gate to the end
card, and the gear path wood → stone → iron is complete.

**Assets**

- Reuse: `64x64-8x10-forest-orb-weaver-slime.png`, `house-world-solid--forge-red`
  (the restored Forge), `collectible-iron-ore-pile`, `collectible-charcoal-pile`,
  `rock-amber-ore-mineable` (as a style reference), the interior catalog.
- [ ] Iron ore node (intact and depleted).
- [ ] Icons: enemy material, iron bar, Reinforced Pickaxe, iron weapons.
- [ ] Weapon art for the iron spear or sword and iron axe (directional swing
      art like the stone weapons).
- [ ] Ruined Forge exterior.
- [ ] Boss sprite sheet, web projectile and web-ground effects, and arena
      dressing.
- [ ] Gloop Forest hut exterior.
- [ ] Gloop Forest music and ambience; Forge fire and anvil loops.

## 9. Game Feel

A slime's feel is mostly hit-stop, screen shake, and squash and stretch. Every
effect respects the reduce-motion setting (4.5).

### [ ] 9.1 — Hit-stop and screen shake

- Build: named presets per event (light hit, heavy hit, boss slam, defeat).
- Done when: each preset fires on its event, the screen-shake setting (4.5)
  scales or disables shake, and reduce motion turns both off.

### [ ] 9.2 — Squash and stretch

- Build: event-driven squash and stretch on move start, jump, land, hit, and
  Gulp.
- Done when: each of the five events plays its deformation, the slime always
  returns to its rest shape, and reduce motion softens it.

### [ ] 9.3 — Particle presets

- Build: pooled hit sparks, slime splash, dodge dust, loot sparkle, and boss
  defeat bursts.
- Done when: each preset plays on its event, particles come from a pool (no
  per-hit allocations), and a 20-enemy fight in the playground holds 60 fps.

### [ ] 9.4 — Slime trail

- Build: the slime leaves fading goo marks behind it. Enemies that cross fresh
  goo are slowed through the existing `slow` status.
- Player proof: the slime leaves a mark on the world and can use it tactically.
- Done when: trail marks are pooled, fade, cost no measurable frame time, and
  the user accepts the trail in the playground (3.7).

**Milestone 9 complete when:** a side-by-side capture shows the difference and
reduce motion turns the strong effects off.

**Assets**

- [ ] Small particle sprites (spark, splash, dust, sparkle).
- [ ] Two or three goo splat decals for the trail.

## 10. Release Hygiene

### [ ] 10.1 — Download size

- Build: `dist/` is 70 MB today: a 5.4 MB main script and UI backplates of
  2–5 MB each. Compress and resize images to their display size, load area art
  when the area loads, and show a loading bar.
- Done when: the first load is under about 25 MB and a cold start on a normal
  connection shows the title within a few seconds.

### [ ] 10.2 — Production-only content

- Build: ship only reachable worlds (`level-1`, `slime-home`, `mushroom-home`,
  `gloop-forest`, `crystal-caverns`, and the 8.8 hut). Add these to the
  dev-only world list from 3.7, next to `playground`: `174`, `236`, `cole`,
  `girls`, `jk`, `tiktok`, `test-rectangle`, `depth-occlusion-test`,
  `meadow-crossing`, `icege`, `emberleef`, and `hot`.
  Disable `?map=`, the dev item grant, debug hotkeys, and Development Tools in
  production.
- Done when: a production build contains none of them.

### [ ] 10.3 — Licenses and credits

- Build: record the source and license of every image, sound, and font in the
  production build.
- Done when: every asset may be redistributed and appears in the credits (4.7).

### [ ] 10.4 — Browsers and performance (absorbs R.1)

- Build: test Chrome, Edge, Firefox, and Safari; hold 60 fps on the reference
  laptop (a mid-range laptop with integrated graphics; record its model here
  the first time this task runs) in Level 1 and Gloop Forest; close the
  [motion rendering](./task/bugs/world-motion-rendering-instability.md) work or
  accept its current state.
- Done when: a fresh run through Chapter 1 works in all four browsers, the
  frame rate stays at 60 fps in the busiest spot of each map on the reference
  laptop, and R.1 is closed or its state accepted in writing.

### [ ] 10.5 — Save safety

- Build: saves from the release build must load in later builds; a corrupted
  save shows an error and never blocks New Game.
- Done when: a persistence test loads a saved `v0.1.0` fixture, and a test
  with a corrupted save shows the error while New Game still works.

### [ ] 10.6 — Hosting and store page

- Build: choose where to publish (for example itch.io as an HTML5 game), with
  screenshots, a short GIF, and a description.
- Done when: the store page exists (it can stay private) and the uploaded
  production build runs from it in a fresh browser.

**Assets**

- [ ] Store-page cover image, screenshots, and a gameplay GIF.

## 11. Playtest And Ship

### [ ] 11.1 — Blind playtest

- Build: 3–5 people who have never seen the game play from the title screen
  while you watch without helping. Note where they get stuck and time each run
  from the title screen to the end card.
- Done when: at least three players finished or quit, each has written notes
  and a time, and the median time is compared with the 45–75 minute target.

### [ ] 11.2 — Fix what they hit

- Build: fix the top confusions and every blocker; sweep for softlocks (defeat
  during a boss, full inventory, leaving mid-quest, quitting mid-transition).
- Done when: every blocker from 11.1 is fixed, each softlock case above was
  tried and passes, and the three most common confusions are fixed or
  accepted in writing.

### [ ] 11.3 — Tag and publish

- Build: tag `v0.1.0`, publish, and record the release in this file.
- Done when: `pnpm check` passes on the tagged commit, the store page is
  public, and the published build runs in a fresh browser.

## After Release 1 — Idea Parking Lot

Everything here waits until Release 1 ships. When one is picked up, it gets a
numbered milestone and task tiles.

### First update candidates

- **Kitchen** (was milestones 9 and 10): a third restorable building; fishing
  at the lake feeds it; healing and buff meals, then potions and antidotes from monster
  materials. The two parked `kitchen` recipes return here.
- **Hats:** cosmetic hats that wobble with squash and stretch, earned from
  quests and secrets. Needs hat art and a per-frame anchor on the player sheet.
- **Goo charms:** equippable trinkets crafted from enemy materials that bring
  back the old perk effects (crit, life steal, speed) as gear.
- **Goo-pedia:** a bestiary filled in by defeating enemies, with notes from
  Elder Plop.
- **Coins get a use:** a Slimeshire shop, and repairing equipment at the
  Workshop (repairs need a durability rule first). Until then coins are only
  earned and saved.
- **Home furnishing** (was milestone 11, without moving the home): a builder's
  table for furniture, storage, and defenses.
- **Home storage and safety rules** (was milestone 12).
- **More Gulp forms:** Glow (crystal shard, lights dark caves), Bouncy
  (berry), and later biome forms such as ice and lava.

### World

- **Chapter 3 — Crystal Caverns** with the Crystal Colossus (armored, weak to
  hammers; teaches weapon switching) and the Glow form.
- Later biomes: Sticky Swamp (slow, poison, spider-slimes, rain), Frostpeak
  (ice physics, snow), Volcano Ridge (lava, burn, the finale). The authored
  `icege`, `emberleef`, and `hot` maps are candidates.
- Shallow and deep water (was E.3), then swimming gear (was E.4).
- Day and night (enemies stronger at night, glowing slimes), weather with
  gameplay hooks (rain puts out burn), fast-travel shrines.

### Characters and enemies

- **The worm who surrenders:** one unique, named worm (its own scene, so
  ordinary worms are untouched) that gives up at low HP. Sparing him sets a
  story flag; the 6.1 variant node then places him in Slimeshire as a
  shopkeeper, which also gives coins a use.
- A mimic slime; see-through slimes that show the loot inside them;
  companions; a rideable mount.
- More enemies from [Future Enemy Types](./task/ideas/open/future-enemy-types.md);
  each needs authored art, animation, behavior, and validation.
- Boss extras: HP phases, intro name cards and camera pans, victory sequences.

### Combat and abilities

- Weapons: Bouncy Bow (arrows bounce off walls), Sticky Whip (pulls enemies
  in), Bubble Wand (AoE slow). Charge attacks and weapon upgrade tiers.
- Abilities: Slime Split (two mini-slimes, one per switch), Puddle form (slip
  under fences, hide in grass), Bouncy Bubble shield, Fizzy Frenzy, Sticky
  Trap, Geyser Leap.
- Bombs at the Workshop.

### Interface and platform

- Unified action dashboard (was UX.1):
  [Player action dashboard and loadout](./task/ideas/open/player-action-dashboard-and-loadout.md).
- Weapon dropping and pickup (was UX.3).
- Gamepad support, key rebinding, colorblind-safe status colors, text size,
  photo mode.
- The Android app in `MobileVersion/` stays frozen until after Release 1.

### Tooling (frozen)

- Shared world graph and all-map organizer (was E.1):
  [Shared world map and Map Studio graph](./task/ideas/open/global-map-and-map-joining.md).
- Remaining shared gameplay defaults (was C.5).
- New Scene Studio features of any kind.

### Dropped

- `[—]` Moving the home: the home stays in Slimeshire; other maps get their
  own homes.
- `[—]` A single authored home instance with ownership (was 3.1, 3.2).
- `[—]` The Alchemy table: potions belong to the Kitchen, bombs to the
  Workshop.
- `[—]` XP, levels, and perks: replaced by gear-based progression (Milestone 5).

## Immediate Next Sprint

1. Milestone 3: pick the sound flavour (3.8), verify the bed respawn round
   trip (3.4), finish interior collision (3.5), and build the playground
   (3.7).
2. The rough Gulp prototype (7.0) in the playground, so the Chapter 2 outline
   builds on a Gulp that has been played.
3. Milestone 4: title screen, pause menu, and player-facing saves (4.1–4.3).
4. In parallel, write the gear-progression change list (Milestone 5). Start
   the Chapter 2 outline (8.1) once the 7.0 verdict is in.

## Done — Foundations

Completed milestones, kept short. Their plans and evidence hold the details.

### [x] 1 — Wood gathering (1.0–1.5)

Numeric resource damage modifiers, persistent wood, harvestable authored trees
with hit feedback, the starter axe, and a verified five-minute fresh-game loop.

### [x] 2 — Stone and starter tools (2.1–2.7), verified 2026-09-28

- Stone nodes (80 HP, up to three piles), walk-over collectibles for loose wood,
  stone, and berries, and tool-gated harvesting with clear feedback.
- Workbench-context recipes for the Wooden Spear, Stone Axe, Stone Pickaxe, and
  Stone Spear, taught by Chapter 1 quests; fresh runs start unarmed.
- Fatty One Eye: a mouthless one-eyed slime whose eye only spears can hit, a
  telegraphed leap, an arena leash, a guarded chest with a persistent green
  key, a three-minute respawn, and the Verdant Gate.
- Animation packages and the New Object dialog (2.4, 2.5) were superseded by
  Scene Studio.
- Plans: [Stone and starter tools](./superpowers/plans/2026-08-23-stone-and-starter-tools-implementation-plan.md),
  [Walk-over collectibles](./superpowers/plans/2026-08-24-walk-over-collectibles-and-editor-attributes-implementation-plan.md),
  [Fatty One Eye design](./superpowers/specs/2026-09-11-fatty-one-eye-guarded-chest-design.md),
  [verification checklist](./task/ideas/completed/level-1-milestone-2-verification-checklist.md).

### [x] Q — Chapter 1 — The Clearing

`src/game/content/quests/quests/chapterOne.ts`: Village Elder Plop, Mossy,
Lili, and Lily the Fishergirl give six quests (`a-place-to-work`,
`stone-tools`, `worm-trouble`, `the-one-eyed-guardian`, `a-tonic-for-lili`,
`snack-for-the-road`) with dialogue, a chapter banner, quest-taught recipes, and
the `chapter-1-complete` flag. Slimeshire Meadow (`level-1`, built by
`scripts/maps/build-level-1.mjs`) holds the town, river and lake, Fatty's hedge
maze, the worm ruins, the Webwood, and the Verdant Gate. See the
[Quest authoring guide](./knowledge/quest-authoring-guide.md).

### [x] P — Save, load, and reset (P.1–P.5), verified 2026-09-28

Immutable initial run state, map-keyed progress, independent named saves with
explicit overwrite, a recovery autosave, save schema v9 with migrations, and
Save/Load/Reset controls. Plan:
[Named save, load, and reset](./superpowers/plans/2026-08-24-named-save-load-reset-implementation-plan.md).

### [x] S — Universal scene architecture (S.1–S.5)

Worlds, UI, and audio are authored scenes; behavior lives in ScriptNodes;
Scene Studio (`?studio=scenes`) is the only editor; `pnpm check` and 43
browser cases pass. Design:
[universal scene architecture](./superpowers/specs/2026-09-12-godot-inspired-universal-scene-node-architecture-design.md);
evidence: [final report](./superpowers/plans/evidence/universal-scene-final-report.md).

### [x] Audio foundation (A.0–A.3)

Audio loads from `asset/assets.json`; audio nodes support variants, pitch
randomness, polyphony, and buses; every P1 cue exists; `pnpm audio:wire` and
`audio:check` keep scene wiring in sync. Plan:
[Audio & SFX](./superpowers/plans/2026-09-28-audio-sfx-implementation-plan.md).

### [x] Other finished cross-cutting work

- **C.1–C.4 — Central gameplay configuration:** `game-constants.json` with a
  strict schema and a frozen runtime gateway
  ([plan](./superpowers/plans/2026-08-26-central-game-constants-implementation-plan.md)).
  Edit the JSON directly and run `pnpm constants:check`.
- **UX.0 — Escape closes the topmost surface** through the shared `ModalStack`
  ([design](./superpowers/specs/2026-08-26-escape-closes-overlays-design.md)).
- **E.2 — Terrain is ground; walls are placed objects:** crystal clusters and
  forest trees are object scenes, and water collision is merged.

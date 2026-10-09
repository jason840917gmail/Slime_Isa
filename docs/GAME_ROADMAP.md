# Game Roadmap — Road to Release 1

> **Status: active living checklist.** Design direction lives in
> [Game Guidelines](GAME_GUIDELINES.md); this file owns task order and
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
- restore a Slimeshire building, the Forge, and use it
  to craft the recipes they unlock;
- grow stronger through crafted gear, heart quarters, and story-unlocked
  abilities (no XP or levels);
- use **Gulp**, the signature mechanic, to solve Chapter 2 puzzles (being
  redesigned: [the 2026-10-08 decisions](#the-2026-10-08-decisions));
- earn bags, a vault and abilities, each with the item ceremony
  ([the 2026-10-02 decisions](#the-2026-10-02-decisions));
- hear music and ambience in every area and feel every hit.

**Not in Release 1:** the Kitchen, farming, hats, Crystal Caverns beyond a
locked teaser, the unconnected `icege`/`emberleef`/`hot` maps, the mobile app,
and custom editor tooling. They wait in
[After Release 1](#after-release-1--idea-parking-lot).

**No target date.** Release 1 ships when it is ready. By choice, milestones
are ordered but not sized or dated (decided 2026-09-29).

### Rules That Keep Release 1 Shippable

- **New ideas go to the [parking lot](#after-release-1--idea-parking-lot)**,
  never straight into a Release 1 milestone. An idea moves in only by replacing
  work of the same size.
- **Tooling is not progress unless a player can see the result.** Levels and
  scenes are built in the Godot editor; Scene Studio was retired with the Phaser
  app (2026-10-05).
- **Every milestone lists its art and audio.** Placeholders are fine while
  building; a milestone is `[x]` only when its assets are final or explicitly
  accepted as final. All new art follows the
  [art style guide](assets/visual-style-guide.md) and is generated with
  Magnific following the [Magnific MCP guide](assets/magnific-mcp-guide.md),
  then packed and registered through [docs/assets/](assets/README.md).
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

### The 2026-10-02 Decisions

On 2026-10-02 the owner made a set of design decisions
([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built))
and answered that all of them go into Release 1
([open question 1](story/06-open-questions.md#scope)). They came in by the
owner's choice, not through the parking-lot rule above. Their tasks were added
on 2026-10-07, each in the milestone it changes; none is built yet, and
several are large (the bottom console HUD, the armors, the place where the Silk
Armor is earned). Where a task depends on a question that is still open, it
says "Open:" and links the question; nothing here decides one.

| Decision | Roadmap tasks |
|---|---|
| Getting an item (the item ceremony) | 4.13 (new) |
| Life and energy display, as a bottom console (shape chosen 2026-10-07) | 4.12 (new); the heart display in Milestone 5's assets |
| Boss reset: the bar hides outside the arena | 4.12 (new) |
| Hearts: heart quarters | 5.3 (reopened), 8.7, 8.9 |
| Energy | 5.6 (new) |
| Bags | 5.7 (new), 8.9 |
| Vault, found in a house quest that teaches sleeping | 5.8 (new), 8.8 |
| Each boss's Pearl grants an ability ([answered](story/06-open-questions.md#answered) the same day) | 5.9 (new), 8.7, 8.10 |
| Crafting time | 6.5 (new), 8.5, 8.6 |
| Gulp armors (replaced 2026-10-08 by essences: [the 2026-10-08 decisions](#the-2026-10-08-decisions)) | 7.5 (new), 7.4, 8.9, 8.12 (new), 8.13 (new) |
| Webs | 7.6 (new), 8.7, 8.9 |
| Sprint becomes a mid-game roll | 7.7 (new), 4.10, 4.11 |
| The Weaver (Matron) | 8.7, 8.10 |
| Dropping weapons | Removed from the plan: [Dropped](#dropped) (was UX.3) |

The first step is the owner's approval of the HUD mockup (4.12). The order of
the other tasks is not set.

### The 2026-10-08 Decisions

On 2026-10-08 the owner removed the jump and redesigned Gulp.

- **The jump is removed from the game** (done 2026-10-08). It was stronger than
  the other abilities (its landing check ignores placed objects, so it hopped
  over walls and gates), it did not fit the game, it was needed only for the
  Heavy landing on cracked ground, and it misbehaved around elevation. Its
  logic stays: the `jump` action has no key (Space is free), no HUD slot or
  Controls row shows it, nothing in the story teaches it, and ledge drops
  still use its flight. Tasks: 4.10, 5.2, 5.9, 7.4.
- **Fatty One Eye's Pearl grants Squash Slam** instead of the jump: his fight
  is a leap that lands hard. Until the Pearls exist (5.9), finishing The
  One-Eyed Guardian teaches the slam, and The Matron's Nest no longer does
  (done 2026-10-08; 8.7).
- **Cracked ground breaks under a Heavy Squash Slam**, not a Heavy jump
  landing (done 2026-10-08). A Heavy slime standing on it hears it creak and,
  once the slam is learned, is told to slam it. Tasks: 7.4, 8.9.
- **Gulp is redesigned around essences**, replacing the armors (the design is
  in [Gulp](GAME_GUIDELINES.md#signature-mechanic-gulp)).
  - Holding Q sucks in an essence or a light object (pots and dozens of other
    things for every kind of place), and Q throws it. A thrown thing breaks by
    what it is made of. Pots are fine as long as they are the game's own, not
    copies of Zelda's (owner, 2026-10-09).
  - Swallow, learned from Tom in Chapter 2, turns a held essence into its form.
  - Some enemies drop essences and some maps hold them.
  - A hit pops the form out as a blob.
  - Tasks: 7.5, 7.6, 8.12 (the Clod Stomper, the stone essence's enemy) and
    8.13 (Tom and the Swallow lesson).
- **The Roll replaces the Dodge** on key 2: it spins up in place, then dashes
  straight on while held, like Zelda's Pegasus Boots, and bonks back off
  walls. Built 2026-10-09, waiting for the owner's feel. Task 7.7.
- **New keys** (changed by the owner on 2026-10-09, applied with 7.5): Q sucks
  and throws; 1 swallows; 2 rolls; Stretch Lash, Squash Slam and Teleport
  move to 3, 4 and 5; interact stays on right-click (W in the keys-only
  scheme). The 2026-10-08 plan (R swallows, Space
  interacts) was dropped. Task 4.10.

## Progress Board

| # | Milestone | Player-visible result | Status |
|---|---|---|---|
| 1 | Wood gathering | Chop a tree and keep the wood | `[x]` |
| 2 | Stone and starter tools | Craft starter gear, beat Fatty One Eye, open the Verdant Gate | `[x]` |
| Q | Chapter 1 — The Clearing | Six NPC quests lead from an empty clearing to Gloop Forest | `[x]` |
| P | Save, load, and reset | Named saves, recovery autosave, per-map progress | `[x]` |
| S | Universal scene architecture | Every world, entity, UI, and audio surface is an authored scene | `[x]` |
| **G** | **Godot migration** | **The game runs in Godot 4.7 with the same worlds and mechanics, edited in the Godot editor** ([plan](GODOT_MIGRATION.md); trial first) | `[~]` |
| **Release 1** | | | |
| 3 | Finish homes, interiors, and audio | Beds are home, interiors are solid and persistent, today's content sounds finished | `[~]` |
| 4 | Game shell | Title, continue, pause, game over, settings, credits, simple controls | `[~]` |
| 5 | Gear-based progression | XP and levels are gone; gear, heart quarters, and story unlocks make you stronger | `[~]` |
| 6 | Rebuild Slimeshire: restoration | Ruined buildings can be restored and become stations (the Forge uses it in Chapter 2; the Workshop waits until after Chapter 2) | `[~]` |
| 7 | Gulp | Suck, throw and swallow essences; their forms solve puzzles and pass webs | `[~]` |
| 8 | Chapter 2 — Gloop Forest | New enemy, iron, Forge, metal gear, second boss | `[~]` |
| 9 | Game feel | Hit-stop, shake, squash and stretch, particles, slime trail | `[~]` |
| 10 | Release hygiene | Small download, production-only content, licenses, browsers | `[~]` |
| 11 | Playtest and ship | Blind playtest, fixes, `v0.1.0` published | `[ ]` |

Milestone G (2026-10-04) moves the game from Phaser to Godot. Its
[plan](GODOT_MIGRATION.md) owns the phases. Done 2026-10-05: the owner played
Chapter 1 through in Godot and the Phaser app was removed; the Release 1
milestones continue in Godot (entries dated before the cutover describe the
Phaser build).

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
  [open questions](GAME_GUIDELINES.md#open-questions), not into silent rules.

Task tile format:

```md
### [ ] 6.1 — Short task name

- Build: the smallest implementation or content change.
- Player proof: what the player can see or do afterward.
- Done when: the concrete acceptance check passes.
```

Each milestone ends with an **Assets** list: what can be reused and which new
art or audio must be made. See [docs/assets/](assets/README.md) for sizes,
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

### [x] 3.4 — Beds are home (was 3.3), verified 2026-09-29

- Done: sleeping saves `world.respawnPoint` with the bed's identity (`bedId`:
  the instance's persistence key, or `placed-furniture:<id>` for a placed bed).
  Defeat wakes the player at that bed on its own map; if the bed's world no
  longer has it (`features/rest/RespawnDestination.ts` checks the scene
  catalog), the point is cleared and the player wakes at the Level 1 spawn.
  Played headless: sleep in the Slime Home, die in Level 1, wake in the bed;
  the bed survives a reload; a removed bed falls back to Level 1.
  `pnpm test:progression` covers the lookup.

### [x] 3.5 — Interior collision and interaction (was 4.5), verified 2026-09-29

- Done: `game.bed` scripts on sleepable beds (F dozes, sleeps, and restores
  `rest.sleepHpRegenPerSec` HP/s; input or damage wakes the player). A
  flood-fill of where the player's body can stand shows both rooms closed:
  no footprint reaches wall art. Beds, tables, hearths, the alchemy bench and
  the water basin got deeper footprints (`FOOTPRINT_SHARES` in
  `scripts/interiors/interior_catalog.py`), so the player can no longer walk
  into the hearth alcove or across tabletops. Depth and the F badge were
  checked from the north, south, east and west of each large piece.

### [x] 3.6 — Persist placed furniture (was 4.6), verified 2026-09-29

- Done: the workbench is placed from the inventory with a grid-snapped
  preview (R variant, Esc cancel), saved per map as `placedFurniture`, and
  picked up with G. Played headless: one bench in Level 1 and one in the Slime
  Home each stay exactly once through leaving, returning, and a reload;
  picking one up and placing it again leaves one record.

### [x] 3.7 — The playground map, verified 2026-09-29

- Done: `world.playground` (40 × 28 tiles) has a resource grove, an empty
  cobble puzzle yard, an enemy pen (worm brawlers, a worm archer, a slime
  spider) and a chest of stone gear, materials and potions by the spawn. It
  opens with `?map=playground`. `src/game/content/scenes/devOnlyWorlds.ts` is
  the dev-only world list; the scene content plugin drops those worlds from
  production builds (a build contains no `world.playground`). 10.2 adds the
  other test maps to the same list. Dev-only worlds have no legacy
  `.map.json`, so a named save made in one cannot be loaded back.

Interior authoring in Scene Studio (was 4.3) is not a separate task: the next
interior, the Gloop Forest hut, is built in 8.8 with Scene Studio as it is
today, and only real blockers get fixed.

### [x] 3.8 — Pick one sound flavour (was A.4), applied 2026-09-30

- Done: the owner's final picks live in `scripts/audio/picks.json` (79
  library, 50 synth); `pnpm audio:bake` ships only the picked flavour, the
  losing takes and the six dropped takes are gone, and the `?sfx` switch and
  manifest alternates are removed. The 20 cues marked "Neither" got new takes
  made with Magnific from the owner's descriptions (66 takes, sources in
  `asset/Originals/audio/magnific/`). In round 2 of the
  [picker](https://claude.ai/artifact/RDDoJKEVByiJCSsRvzwLHZ) the owner kept
  the new takes for all 20 and dropped a few (recorded under `round2` in
  `picks.json`); Fatty's recover and the arrow hit now ship take 3. Shipped
  sound went from about 7.5 MB to 5.6 MB. `assets:check` finds no orphans.

- 2026-09-30: the picker now also offers **Neither** per cue (with a "how
  should it sound?" box, for replacements to make) and a ✕ to drop single
  takes, plus a **My picks are final** button. Claude applies the picks only
  once they are marked final.

- Current: every cue's library and synth takes are on an A/B listening page,
  [Slime Isa Sound Picker](https://claude.ai/artifact/RDDoJKEVByiJCSsRvzwLHZ);
  picks made there save for Claude to apply.
- Build: compare synth and library takes per category, delete the losing
  flavour, and remove the `?sfx` toggle.
- Done when: each cue ID has one shipped flavour and `assets:check` finds no
  orphans.

### [~] 3.9 — World sounds for today's content (was A.5)

- Current: terrain footsteps, status, chest, gate, NPC, and area-title cues
  exist, and Level 1 plays its town music.
- Built 2026-09-29 with synth placeholder loops (`world/*-loop`,
  `world/meadow-ambience`, `world/interior-ambience` in
  `scripts/audio/cues.mjs`, rendered as seamless loops): every campfire,
  cauldron, grindstone and anvil plays a positional loop on the ambience bus
  (audible within ~420 px, silent beyond); Level 1 has a meadow bed and both
  interiors a room-and-hearth bed. Played headless: each prop is audible up
  close and silent 700 px away. Open: final recordings (see Assets), or the
  user accepting the placeholders.
- Build: prop loops for the campfire, cauldron, grindstone, and anvil; Level 1
  ambience; interior ambience or music.
- Player proof: Slimeshire sounds alive and props can be heard as you approach.
- Done when: each of the four props plays its loop within hearing range and
  fades out when the player walks away; Level 1 and both interiors each have
  ambience or music; `pnpm audio:check` passes.

### [~] 3.10 — Audio polish (was A.6)

- Current: Settings (pause menu or title) has master, effects, and music
  sliders plus mute, saved per device by `GameSettingsService`.
- Build: duck music while paused, crossfade on `area.enter`, switch to boss
  music on `boss_spawn_requested`, and pass the crit flag to hit sounds.
- Done when: music transitions never stack or cut off abruptly.
- Built 2026-09-29: `features/audio/MusicDirector.ts` fades world music in on
  arrival, dips the music bus to 35% while a menu pauses the game, crossfades
  to `Music/BossMusic` in `audio.global` while a boss fight lasts
  (`boss.engaged` / `boss.disengaged`) and back, and fades music and picture
  out before any map change. A critical hit plays the `weapon/crit` sting
  once per swing. Played headless on Fatty's arena; `pnpm test:audio`.
  Open: `BossMusic` is a placeholder (the town theme pitched up) until a boss
  track is sourced.

### [x] 3.11 — Steps, water and the silent actions (Sound Picker rounds 3 and 4), applied 2026-10-06

- Built 2026-10-06:
  - Steps on every ground, wading, the waterline splashes and swim strokes
    (`game/audio/footsteps.gd`).
  - New cues for the Gulp forms (one transform sound per form), the lash catch, plates, gates,
    doors, the training dummy, cracked ground and dialogue typing.
  - Earlier picks that nothing played are now wired: coins, drops, potions, sleep, web struggle,
    dull and blocked hits, save, the quest toast and the shell menus. Details:
    [audio spec §10](godot/specs/audio.md#10-steps-water-and-the-round-3-cues).
  - 42 sounds with options are on the
    [Sound Picker](https://claude.ai/artifact/RDDoJKEVByiJCSsRvzwLHZ), round 3. Steps have a
    Walk button in the slime's rhythm. `?audition` switches the options in the game (F7/F8).
  - `godot/tests/test_footsteps.gd` covers the steps, water and new cues.
- Round 3 picks applied 2026-10-06 (`scripts/audio/picker/round-3-picks.json`). Steps play well
  under the rest, as the owner asked. A lash miss stays silent. The shipped takes are registered
  in `cues.mjs` and `picks.json`.
- Round 4 picks applied 2026-10-06 (`round-4-picks.json`): one transform sound per Gulp form.
  The Heavy sounds like rock, the Frog plays round 3's Bubbly pop take 3 as the owner named it,
  and the Sticky has a silk stretch. They are registered for the bake.
- Not covered yet: enemy footsteps and strike whooshes, Fatty's chase steps (the takes exist),
  the gulp wheel, the ability-ready sound, button hover.
- Round 5 (2026-10-09, applied the same day): 15 cues for the essence Gulp, things breaking, the
  Roll, the Clod Stomper and the ceremony. The owner accepted the defaults ("sound the defaults
  are ok"), so option A of each ships (`scripts/audio/picker/round-5-picks.json`), registered for
  the bake (Milestone 7's assets, [audio spec §11](godot/specs/audio.md#11-round-5-the-gulp-the-breaks-the-roll-the-clod-stomper-and-the-ceremony)).

The cue list, hooks, and sourcing rules are in the
[Audio & SFX implementation plan](archive/phaser/superpowers/plans/2026-09-28-audio-sfx-implementation-plan.md).

**Milestone 3 complete when:** the home and bed loop works across defeat,
save/load, and map changes, and today's content has final sound and music.

**Assets**

- Reuse: interior catalog, `house-*` exteriors, the CC0 library packs listed in
  `godot/asset/audio/CREDITS.md`, `level-1-home-town.ogg`.
- [ ] Ambience loops: meadow day, forest, interior (synth placeholders for
      meadow and interior are wired).
- [ ] Prop loops: campfire, cauldron, grindstone, anvil (synth placeholders
      are wired).
- [ ] Boss music track (CC0 or commissioned); a placeholder is wired.

## 4. Game Shell

Built 2026-09-29 as `features/shell/` (one `MenuSurface` base, one authored
`ui.*` scene per menu, composed by `GameShell`); `pnpm test:shell` covers the
menus and hints. Played headless end to end: fresh profile → title (Continue
and Load disabled) → New Game → play → Esc → Save to Slot 1 → Quit to Title
(Continue and Load enabled) → Load Slot 1 (same position) → defeat → "Defeated
by Worm Brawler" → wake. The Development Tools panel (with its Save, Load, and
Reset) only exists in `pnpm dev`. Placeholder presentation until the assets
below exist.

### [x] 4.1 — Title screen, verified 2026-09-29

- Done: the first world of a page load is a title screen over a paused,
  empty Slimeshire that drifts slowly (`WorldScene` title mode; nothing is
  autosaved behind it). New Game (asks first when an autosave exists; save
  slots are kept), Continue (`SaveSystem.continueLatest`: the autosave, else
  the newest slot), Load, Settings, Credits, and the version. Run handoffs
  (travel, load, reset) and dev `?map=` previews skip it.

- Build: New Game, Continue (newest save or recovery autosave), Load,
  Settings, Credits, and the version number. A slow camera pan over Slimeshire
  can serve as the background.
- Player proof: the game starts like a game.
- Done when: every button works on a fresh browser profile and with saves.

### [x] 4.2 — Pause menu, verified 2026-09-29

- Done: Esc with nothing open pauses and shows Resume, Journal, Inventory,
  Map, Settings, Save, and Quit to Title (which saves, fades out, and reloads
  to the title). Settings and Save open on top of it; Esc closes the topmost
  window first. The sound settings are part of Settings.

- Build: Escape with no other surface open pauses and shows Resume, Journal,
  Inventory, Map, Settings, Save, and Quit to Title, routed through the
  existing `ModalStack`. The sound settings become a Settings tab.
- Done when: pause state, Escape order, and resume are correct from every
  surface.

### [x] 4.3 — Player-facing saves, verified 2026-09-29

- Done: three save slots (named saves "Slot 1"–"Slot 3") from Save in the
  pause menu, and Load from the title or the game-over screen; overwriting a
  slot asks first. The P.5 matrix stays covered by `pnpm test:persistence`
  plus the menu round trip above.

- Build: move Save, Load, and Reset Run out of Development Tools into the pause
  menu and title screen, and hide Development Tools in production builds.
- Player proof: a player can save, quit, and continue without developer UI.
- Done when: the P.5 persistence matrix still passes through the new menus.

### [x] 4.4 — Game over, verified 2026-09-29

- Done: after the defeat animation, "Defeated" names the attacker from the
  last hit ("Defeated by Worm Brawler") and the time played, with "Wake at
  your bed" (or "Wake in Slimeshire") and "Load a save". Three defeats in a
  row left one player and the inventory intact.

- Build: on defeat, a short screen (what defeated you, time played) with
  "Wake at your bed" and "Load a save".
- Done when: repeated defeats never duplicate the player or lose progress.

### [x] 4.5 — Settings, verified 2026-09-29

- Done: master, effects, music, screen shake, reduce motion (which turns
  shake off), and a Controls list. `features/settings/GameSettingsService`
  (`gameSettings`) is the one store gameplay reads (`shakeScale`), saved per
  device under `slime-isa:settings:v1`; older sound settings carry over.

- Build: sound (existing), screen shake, reduce motion, and a controls list.
  Settings stay per device, separate from save slots.
- Done when: every setting survives a reload and is readable by gameplay code
  through one settings store. (Milestone 9 checks that its effects obey them.)

### [x] 4.6 — First-time control hints, verified 2026-09-29

- Done: `features/hints/ControlHints.ts` shows one banner at a time above the
  hotbar while it is useful (move at start; F when a prompt shows; attack
  once armed; dodge near an enemy; inventory once you carry something;
  crafting at 40 wood). Using the control saves a `hint.<id>` story flag, so a
  hint never returns in that run and a new game shows them again. All six
  were checked headless, including after a reload.

- Build: contextual hints for move, attack, dodge, interact (F), inventory,
  and crafting that fade after first use.
- Player proof: a new player never needs a manual.
- Done when: on a fresh save each of the six hints appears once, disappears
  after the player performs that action, and never returns on reload.

### [~] 4.11 — Owner playtest fixes, 2026-10-01

- Built 2026-10-01 after the owner played Chapter 2, waiting for the owner:
  - **Tutorial:** the first time the menu opens, a pointer under the tab strip
    names the Bag, Crafting, Journal and Map tabs until one is clicked. A new
    automatic quest, **Slime Basics** (`slime-basics`, beside A Place to Work),
    asks to open the bag, the Crafting tab, the Journal and the map, to sprint
    and to pause; its objectives are the new `use-control` kind and the
    tracker adds each key. Stone Tools asks to switch tools on the belt. Four
    more first-time hints (switch weapons, sprint, map, pause), and quest text
    no longer names unbound keys ("(C)", "(F)", "U · Quest book").
  - **Belt:** four slots, and the weapon in hand always swings (tools no longer
    swap in by themselves, which lost fights against enemies behind a tree). A
    tree or rock the weapon cannot harvest says where the right tool is.
  - **Bag:** the weapon belt is always shown at the top with each slot's
    weapon and an IN HAND tag; weapons drag from the bag onto a slot (the
    weapon there goes back to the bag); bigger cells with names, a status line
    (in hand / on belt slot N / in the bag), bigger buttons.
  - **Fangs:** level 1 has no orb-weavers; its Meadow spiders now use the
    yellow spider sheet (`character.enemy.meadow-spider`), and a tinted enemy
    keeps its tint after a hit flash. A drop that does not fit in the bag says
    so instead of vanishing.
  - **Load:** the Load window (title, pause menu, defeat screen) lists the
    autosave, shows why an unreadable slot cannot load, fits stale quest
    progress instead of failing the load (that left a blank screen), and
    returns to the title with the reason if a save still cannot be installed.
    The autosave no longer records a defeated slime.
  - **Dev panel:** "Weapon hitboxes" draws the slime's live swing (yellow
    open, green hit, red refused) and "Hurtboxes" where the slime, enemies and
    bosses take damage, bosses labelled with the weapons they accept. Ticking
    a box no longer scrolls the page (the game was cut in half).
  - **Fatty:** his eye hurtbox follows the drawn eye in every clip (it missed
    the landing and recovery punish windows), every spear reaches it (the Iron
    Spear did not), hits flash and show damage, and he heals to full after a
    minute with the slime outside his arena (the Matron too).
- Played headless (Brave): the bag drag, belt click, tab pointer, Slime
  Basics progress, a stale-quest save loading, the defeat-screen load, the
  overlays and a spear hit on Fatty.
- Planned 2026-10-02: Slime Basics drops its Sprint step and the sprint hint
  goes, because sprinting becomes a mid-game ability (7.7); its bag step comes
  after Elder Plop's bag (5.7).
- Second list, built 2026-10-01:
  - **Loot on the ground:** an enemy's item drops scatter around where it
    fell and are picked up by walking over them, like resource piles; they
    count for quests on pickup and persist until picked up (bag drops' store,
    `origin: 'loot'`). Picking your own bag drop back up no longer counts
    for quests or berry coins, and a regrown tree or rock gives its piles
    again (their old "collected" records were never cleared).
  - **Mossy's quests:** Beyond the Verdant Gate (v2) asks for 5 orb-weavers
    and 3 fangs together; A Harder Pick (v2) starts at the pickaxe. Saves
    reconcile.
  - **Gloop Forest:** tree walls on the west, east and south edges (openings
    at the level-1 entry and the crystal corridor), a deep-water band on the
    north; the Matron's nest is ringed by trees with one web-draped entrance
    to the west, its arena carpeted with webs, egg sacs and victim cocoons.
    Webs, hanging and ground cocoons (motion-only idle loops) dress every
    orb-weaver thicket, the silk nook and level-1's Webwood and south meadow.
    Art: `sheet.props.web-decor.4x3` (Magnific, 11 pieces).
  - **Windows:** bag cells are one size, crafting shows the item, its
    description and a materials list with have / need, the Quest Book shows
    the quest's name and state on top, and every window's buttons are centred.

### [x] 4.7 — Credits screen and end-card component, verified 2026-09-29

- Done: credits read `src/game/content/credits/credits.json`. End cards
  (`content/story/endCards.ts`) show when their story flag is newly set and
  return to the title. In the playground, the Heavy form on the plate inside
  the puzzle pen sets `playground-end-card-test` through a `game.story-flag`
  node; the card appeared and returned to the title.

- Build: a credits screen, opened from the title, that reads its entries from
  one credits data file (today: the audio packs in `godot/asset/audio/CREDITS.md`
  and Magnific-generated art), and a reusable end-card screen that any story
  flag can trigger. Chapter 2 hooks the card up in 8.11; 10.3 completes the
  credits list.
- Done when: the credits screen shows every entry in the data file, and
  setting a test flag in the playground shows the end card and returns to the
  title.

### [x] 4.8 — Artwork-first HUD (was UX.0.1), verified 2026-09-29

- Done: the HUD and weapon hotbar have no filled boxes (transparent meter
  tracks and slots, thin outlines, text shadows; the selected slot has a gold
  double outline and a marker); the minimap already used its frame over a
  0.16-alpha interior. Checked at 1280×720, 800×600 and 390×720 (hotbar
  350 px wide at 390). Label and button text alignment now works in every
  UI scene (it was ignored before).
- Planned 2026-10-07: the bottom console HUD (4.12) replaces this layout. It
  was built for the old rule of 1 game pixel to 1 CSS pixel; the HUD now
  scales with the 16 × 14 tile view and crowds it.

- Build: apply the approved artwork-first treatment to the `hud`, `minimap`,
  and `weapon-hotbar` UI scenes. See
  [World HUD Artwork-First Presentation](archive/phaser/superpowers/specs/2026-09-04-world-hud-artwork-first-design.md).
- Done when: the world art shows through the widgets and every value fits at
  wide, medium, and narrow viewports.

### [~] 4.9 — First fresh-eyes playtest

- Owner playtest, 2026-09-29. Findings and what changed (2026-09-30):
  - Crafting a placeable item needed close → inventory → place: crafting one
    now closes the popup and starts placing it at once (Esc keeps it in the
    bag).
  - Missing materials were easy to miss: Craft stays pressable and answers
    "Missing: 15 Wood." in red; short recipes show a red edge and "Missing 15
    Wood" in the list; the details mark each short material.
  - The first worm camp was too hard: it now holds worm swordsmen (slower,
    telegraphed), and Worm Trouble asks for three of them (definition v2;
    older saves keep their progress, clamped to the new target).
  - Quests needed a WoW-style pointer: clicking the quest tracker shows a gold
    arrow with the distance to the next step (giver, turn-in NPC, camp, boss,
    exit, tree or rock, workbench), a marker over it once on screen, and a pin
    on the minimap (`features/quests/QuestWaypoint.ts`).
  - Fatty's camp was cramped and cheesable: his clearing is now an open
    7-tile circle with no props, walls or trees inside, his arena and
    activation circles sit just inside it (so he never leaps over hedges), the
    chest waits at the north rim, and the maze has no enemy spawns, so no
    worm joins his fight (`scripts/maps/build-level-1.mjs`).
  - Credits read "Created by Daniel, Isa and Dany6".
- Owner feedback, 2026-09-30, and what changed:
  - A web crossed with the Sticky form could trap a slime whose form wore off
    on the far side: the web now tears open for good when the Sticky slime
    pushes through (remembered per placement).
  - Cracked ground broke too easily: the Heavy form now has to land a jump on
    it; standing on it only makes it creak, with a hint. (Since 2026-10-08 a
    Heavy Squash Slam breaks it: 7.4.)
  - Enemies could be killed from just outside their pursue area, where they
    stood passive: camp enemies now keep a territory
    (`enemies/ai/Territory.ts`): sight blocked by walls, houses and trees, a
    hit always alerts them, a leash (distance from home plus how far the
    player is out of reach) decides how far they chase, a lost player is
    searched for 3 s where last seen, and they walk home healing. Played
    headless: a worm engaged at 150 px in sight, searched then went home when
    the slime hid behind the ruins, and healed to full after giving up.
  - The controls felt odd: attacking by clicking while walking with the
    arrows, and many keys that each do one thing. Planned as 4.10.
- Open: a second new player.

- Build: two people who have never seen the game play Chapter 1 from the
  title screen while you watch without helping. Note where they get stuck and
  time each run.
- Player proof: Chapter 2 is built on what new players actually did, not on
  guesses.
- Done when: both runs have written notes and a time recorded under this task,
  every blocker they hit is fixed or has its own task, and lessons that affect
  Chapter 2 are carried into the outline (8.1).

### [~] 4.10 — Simple mouse-and-keyboard controls

- Plan: [Simple controls design](archive/phaser/superpowers/specs/2026-09-30-simple-controls-design.md),
  agreed 2026-09-30 after the owner feedback in 4.9.
- Built 2026-09-30, waiting for the owner's playtest:
  - every control comes from one binding table
    (`features/player/PlayerInputActions.ts`), and so does every key label;
  - Dodge is a learned ability (Stone Tools), and Jump was on Space (the jump
    was removed on 2026-10-08, and Space is free);
  - the belt has three slots on the mouse wheel, and tools pick themselves
    (both changed by the 2026-10-01 playtest, 4.11: four slots, no automatic
    tools);
  - right click interacts with what the pointer is on, and holding it picks
    up placed furniture;
  - E opens the menu with tabs (since 2026-10-08 B does, J opens the journal
    and E is the weapon scroll: 4.12);
  - cheats are dev-panel buttons.
  - Two headless playtests passed 34 of 34 checks. See
    [As Built](archive/phaser/superpowers/specs/2026-09-30-simple-controls-design.md#as-built-2026-09-30).
- Open:
  - the owner picks the attack direction (pointer or facing; the dev panel's
    "Controls test" switch);
  - the key and mouse glyph art;
  - planned 2026-10-02: Shift no longer sprints from the start; a mid-game
    roll replaces sprinting (7.7).
- Decided 2026-10-09 (owner), applied with 7.5: Q sucks and throws; 1
  swallows; 2 rolls (the Roll, built 2026-10-09, 7.7); 3 Stretch Lash, 4 Squash Slam,
  5 Teleport; interact stays on right-click (W in the keys-only scheme).
- Build: the left hand on WASD, the right hand on the mouse.
  - Left click attacks, and the right tool is picked automatically for trees
    and rocks. Whether attacks aim at the pointer or the facing is under test,
    with a switch.
  - Right click interacts with whatever the pointer is on.
  - Space is Jump (removed 2026-10-08; Space is free). 1 is Dodge, a roll of
    0.5 s toward the pointer (4 directions) that Stone Tools now teaches (the
    Roll on 2 since 2026-10-09, 7.7).
    Holding Shift sprints.
  - Q is the mouth (Gulp), and 2–4 are the other abilities.
  - The mouse wheel switches between up to 3 equipped weapons.
  - E opens one menu with tabs.
  - One binding table supplies every key label, and key presses expire after
    150 ms.
- Player proof: a new player finishes Chapter 1 without taking their right
  hand off the mouse.
- Done when: the plan's "Done When" checks pass on a fresh save, and the owner
  accepts the feel in the playground and in a Chapter 1 run.

### [~] 4.12 — Bottom console HUD: life and energy orbs

- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Life and energy display" and "Boss reset"): two goo orbs, one on each side
  of the weapon belt, in slime-styled frames (Diablo-like). The life orb shows
  its number and a ring of pips for the hearts found. The boss bar moves to
  the top of the screen and hides while the slime is outside the boss's arena.
  A mockup comes before the build.
- Decided 2026-10-07: the screen shows 16 × 14 tiles (base 1024 × 896,
  [World size and screen](story/03-world.md#world-size-and-screen)) and the HUD
  scales with it, so today's HUD crowds the view. The chosen direction, pending
  the mockup, is a Diablo-style bottom console.
- Today: HP and energy bars at the top left, the weapon hotbar and ability bar
  (4.8), a quest tracker card with up to four quests, hint banners above the
  hotbar (4.6), a boss bar that stays on screen when the slime leaves the
  arena, and the FPS panel (`game/ui/fps_readout.gd`) shown by default.
- Build, in order:
  1. Done 2026-10-08: the owner approved the direction of the
     [HUD console mockup](design/2026-10-07-hud-console-mockup.md) and
     answered its questions (the steps below carry the answers). Still open
     there: the menu buttons (keep, move or remove).
  2. One centred console along the bottom, about 2 tiles (128 units) tall and
     about 890 units wide: the minimap (never bigger than the orbs), the life
     orb, one slot for the weapon in hand, the ability buttons, the energy orb
     and the menu buttons. The belt keeps its four weapons; a scroll (the
     wheel, or E) opens a carousel over the slot that slides by one weapon per
     scroll, shows the other weapons faded and fades away a moment after the
     last scroll. Every console action has a key in every control scheme
     (owner, 2026-10-08; built the same day): E scrolls the weapon (the mouse
     wheel too, except in the keys-only scheme, where only E cycles the belt),
     B opens the bag (it was E) and J the journal
     ([MOUSE_CONTROLS](godot/MOUSE_CONTROLS.md#the-keys-only-scheme)).
  3. Its height is reserved: the base view becomes 1024 × 1024, so 16 × 14
     world tiles stay clear above the console. The world camera
     (`godot/game/world/world_camera.gd`, `_viewport_size()`) reports the play
     area above the console and shifts the centre to match. Update
     [World size and screen](story/03-world.md#world-size-and-screen) in the
     same change.
  4. The orbs show their numbers only when the value changes (a hit, a heal,
     energy spent or refilled), the life orb with the change beside it, then
     the numbers fade. The life orb's ring shows the hearts: none at the
     start, each heart quarter (5.3) as a quarter of a pip, a whole pip per
     whole heart.
  5. The quest tracker shrinks to one line for the current goal; the full list
     stays in the journal. Tutorial prompts become short messages above the
     console. The FPS panel is off by default.
  6. The boss bar moves to the top. It hides while the slime is outside the
     arena and comes back on return, for Fatty One Eye and the Matron (their
     full heal after 60 s outside is built, 4.11). This step does not wait for
     the mockup.
- Built 2026-10-08 (steps 2-6, `godot/game/ui/console/`): the base view
  1024 x 1024 and the camera's play area; the console with the minimap (no
  see-through gaps), the goo orbs (numbers on a change, heart pips), the
  weapon slot and its carousel, the ability icon slots (from BAR_SLOTS, no
  Jump) and the menu buttons; the one-line goal tracker ("+n" for the next
  quest); the hints above the console, a J hint for the Journal, no sprint
  hint (sprint has no key: owner, 2026-10-08); the boss bar at the top,
  hidden outside the arena; the FPS panel off. Open: the owner's playtest, and
  the heart pips' quarters once 5.3 builds them.
- Replaces: the 4.8 layout (its four belt slots become one slot and the
  carousel), the four-quest tracker card, the hint banner of
  4.6, and the "HUD heart or max-HP growth display" in Milestone 5's assets.
- Player proof: the whole 16 × 14 tile view is clear, and life, energy,
  weapons and abilities are read in one console at the bottom.
- Done when: the owner has approved the mockup; at the 1024 × 1024 base and
  in a 16:9 window no HUD covers the 16 × 14 tiles above the console except
  the goal line, the boss bar and the short messages, and the slime is centred in that play
  area; the orbs follow HP and energy and show their numbers only on a
  change; the pips show each quarter found; a scroll opens the weapon
  carousel; the tracker is
  one line; in both boss fights the bar is at the top, hides when
  the slime leaves the arena and returns when it comes back; a fresh profile
  shows no FPS panel.

### [~] 4.13 — The item ceremony

- Built 2026-10-09 for abilities, then the same day for permanent items and
  Goo Hearts ("implement the ceremony so i can test in level 1"), waiting for
  the owner. The owner asked for the slime to raise what it learned, "or
  something original but exciting". Code: `game/ui/ceremony/ability_ceremony.gd`
  and `ceremony_stage.gd`.
  - The world pauses (pause reason `ceremony`) and dims around the slime,
    like a spotlight. The slime squashes and stretches up, and the fanfare
    plays (cue `Ceremony`).
  - A glossy goo bubble carrying the thing's icon (an ability's HUD console
    `ability-<id>.webp`, an item's bag icon, the heart's own picture) wells
    out of the top of the slime and floats above it, wobbling, with 14
    turning light rays and sparkles.
  - A card slides up: what it is ("New ability", "New weapon", "New tool" for
    a weapon that harvests, "Key item", "Goo Heart"), the name, one line of
    what it does, and how to use it (an ability's `AbilityDefinitions.CEREMONY`;
    a weapon's "It goes on your belt: swing it with <attack>", a tool adding
    what it harvests; a key's "it opens a lock somewhere"), with the keys from
    the 4.10 binding table. A key counts after 1.6 s, and "Press any key"
    shows at 1.8 s.
  - Any key: the bubble sinks back into the slime, which gulps it down (cue
    `GulpCatch`, a squash, a burst of sparkles). The dim lifts and the game
    goes on.
  - It waits while a window is open (a crafted tool plays once the crafting
    window closes) and queues when several things come at once.
  - `game/quests/quest_notifications.gd` plays it for every active ability
    `RunState` learns while main's `ability_ceremonies` is on (the default).
    The test runner turns it off, so tests still see the old banner. The
    passive Goo Trail keeps its banner.
  - Items: the first time a weapon or tool or a key (`RunState`
    `PERMANENT_ITEM_CATEGORIES`) comes into the bag, by any way in (a pickup,
    a chest, a craft, a reward), `RunState` remembers it in the save
    (`story.celebrated_item_ids`) and emits `permanent_item_gained`, and
    `quest_notifications.gd` plays its ceremony. It plays once per item and
    never again after save and load. Quiet grants (the start weapon, the
    playground's kit, `?arsenal`) count without one, and so does whatever an
    older save already holds.
  - Every Goo Heart plays it too ("+10 max HP", `goo_heart.gd`); the floating
    text stays.
  - Tests: `godot/tests/test_ceremony.gd` (`pnpm test:godot -- --filter=test_ceremony`).
  - `godot/tools/render_ceremony.gd` renders it in the running playground for
    tuning.
- Not done: bags (5.7), heart quarters (5.3), energy upgrades, the lift
  upgrades and story items (they end in it when they are built), the smaller
  recipe sting and the owner's acceptance. The fanfare is Sound Picker round
  5's option A (the owner accepted the defaults on 2026-10-09).
- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Getting an item"): the game pauses, the item rises out of the slime with
  light rays and a fanfare, and a card shows the name, one line of text and
  how to use it. Permanent items get the full ceremony the first time. New
  recipes get a smaller sting, and materials get nothing. New player
  animations are welcome when they improve the game.
- Today: a learned ability, the first of each weapon, tool and key, and every
  Goo Heart play the ceremony above (the passive Goo Trail shows its banner);
  everything else shows floating text. In level 1: the Stone Axe and Stone
  Pickaxe from the workbench, the Roll from Elder Plop, the Verdant Key at
  Fatty's camp and the lakeside Goo Heart.
- Build: one reusable ceremony. Permanent things are those in
  [Direction](story/01-direction.md#the-rule-behind-every-chapter): weapons
  and tools, abilities, the lift upgrades, bags and vaults, hearts, heart quarters and
  energy upgrades, keys and story items. The [unlock map](story/05-unlock-map.md)'s
  Ceremony column is the checklist. The card's "how to use it" takes its key
  labels from the 4.10 binding table. Wire it to what exists today (crafted
  weapons and tools, the Roll, Squash Slam, Stretch Lash, Swallow from Tom
  (8.13), the green key, Goo Hearts); the bags (5.7), the vault (5.8), the
  Pearls (5.9) and hammering (6.5) end in it when they are built.
- Player proof: earning something permanent is a moment, like a Zelda chest.
- Done when: on a fresh save the first Stone Axe, the Roll and the green key
  each play the full ceremony once and never again after save and load; a
  learned recipe plays the smaller sting; picking up wood plays neither; the
  game stays paused under the card and resumes cleanly.

**Milestone 4 complete when:** boot → title → new game → play → defeat →
wake → pause → settings → save → quit → title → continue works end to end,
two new players have played Chapter 1 (4.9), the new controls are in (4.10),
and the bottom console HUD and the item ceremony are in (4.12, 4.13, added
2026-10-07). The loop works (headless, 2026-09-29); open: 4.9, 4.10, 4.12,
4.13 and the assets below.

**Assets**

- Reuse: `ui-map-journal-paper`, the existing UI
  sound cues, the player's defeat clip.
- [~] Game logo: Magnific GPT-2 (`godot/asset/UI/ui-slime-isa-logo.webp`,
      `ui.logo.slime-isa`), shown at the top of the title panel; owner to
      accept. Open: the browser tab icon and store page.
- [ ] Menu button states (normal, hover, pressed, disabled), matching the
      organic frame style.
- [ ] Title music (CC0 or commissioned).
- [~] Game-over illustration: a melted-slime puddle, Magnific GPT-2
      (`godot/asset/UI/ui-game-over-puddle.webp`, `ui.illustration.game-over`), above
      "Defeated"; owner to accept.
- [ ] Control-hint key and mouse glyphs: left click, right click, wheel, and
      a keycap (4.10).
- [ ] The bottom console (4.12), drawn from the approved mockup: the console
      frame, the life and energy orb frames and goo fills, the heart pips,
      and the menu buttons.
- [~] The item ceremony (4.13): light rays, the card, a fanfare and the
      smaller recipe sting; a new player animation if it helps. Since
      2026-10-09 the ability ceremony draws its rays, goo bubble and sparkles
      in code (`ceremony_stage.gd`) and its spotlight with a shader. Its card
      uses the theme's `BannerPanel`, and the slime squashes and stretches
      (no new clip). Its fanfare is the `Ceremony` cue of Sound Picker
      round 5 (Harp and bells, option A, accepted with the round's defaults
      on 2026-10-09). Open: the recipe sting; owner to accept.

## 5. Gear-Based Progression

Decided 2026-09-29: the player gets stronger through gear, not experience.
XP, levels, and perks are removed. See
[Progression](GAME_GUIDELINES.md#progression-gear-not-levels).

Built 2026-09-29 (5.1–5.5). The player has flat base stats
(`character.player.stats` in `game-constants.json`), Goo Hearts raise max HP,
and quests teach abilities the way they teach recipes. The work is verified in
the running game with placeholder art and sound; the assets below are open.

Reopened 2026-10-07 for the [2026-10-02 decisions](#the-2026-10-02-decisions):
heart quarters (5.3), an energy cost for every ability (5.6), bags (5.7), the
vault and its house quest (5.8), and the bosses' Pearls (5.9).

### [x] 5.1 — Retire XP, levels, and perks, verified 2026-09-29

- Done: enemy drops and quest rewards carry no XP; the HUD shows coins, HP, and
  energy only; the level-up modal, its `P` reopen, perks and their icons,
  weapon `unlockLevel`, and the level table are gone (`GameState` holds coins,
  HP, energy, Goo Hearts, attributes, and equipment). Save schema v10 (player
  shape v5) drops `level`, `currentXp`, `skillPoints`, and `perks` from older
  saves, keeps their story progress, and gives back every ability their
  completed quests teach. Played headless: a v9 save at level 3 with 124 HP
  loaded as a v10 save at 100 HP with Jump kept (Worm Trouble was done) and its
  recipes intact. The level-up jingle became the ability-learned sting; the
  perk sound and the 2.2 MB level-up crest frame were removed (its source art
  stays in `asset/Originals/ui/`).
- Checks: `pnpm test:persistence` covers the v9 migration;
  `test:game-constants`, `test:progression`, `test:quests`,
  `test:scene-integration`, `test:ui`, and the ability-bar and HUD Playwright
  specs pass. `pnpm check` still stops on failures that predate this work: 6
  scene-conversion tests and 4 Playwright specs (global audio, worm arrow,
  quest journal, Studio controls).

- Build: remove XP from enemy drops and quest rewards, the XP bar, the level-up
  modal and its `P` reopen, perks, weapon `unlockLevel`, and the level tables.
  Add a save migration (schema v10) that drops level, XP, and perk data without
  touching anything else.
- Done when: no XP or level text remains, old saves load, and `pnpm check`
  passes.

### [x] 5.2 — Story-unlocked abilities, verified 2026-09-29

- Done: quest rewards take `abilityIds` (validated against
  `content/abilities.ts`); `StoryProgress` saves learned abilities and emits
  `ability.learned`, shown as the area-title banner ("Jump learned: press
  Space") with the placeholder sting. Mossy teaches Jump when Worm Trouble is
  handed in, with a new line of dialogue. Locked abilities show how they are
  earned on the ability bar: Jump "Quest", Squash Slam "Boss", Stretch Lash
  "Quest", Teleport "Later". Played headless from a save at the Worm Trouble
  hand-in: Jump was locked, the turn-in taught it, Space jumped, and it
  survived Continue. The full Chapter 1 run is part of the 4.9 playtest.
- Planned 2026-10-02: Jump moves from Worm Trouble to Fatty One Eye's Pearl
  (5.9), and Stretch Lash to the Matron's (8.7).
- Changed 2026-10-08 ([the 2026-10-08 decisions](#the-2026-10-08-decisions)):
  the jump is removed, so Worm Trouble no longer teaches it and Mossy's jump
  line is gone. The One-Eyed Guardian teaches Squash Slam in its place (until
  Fatty's Pearl exists, 5.9), and The Matron's Nest no longer teaches it.

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

### [~] 5.3 — Goo Hearts (verified 2026-09-29), reopened for heart quarters

- Reopened 2026-10-07 for the decision of 2026-10-02
  ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Hearts"): heart quarters replace the Goo Hearts. Four quarters make one
  heart, worth +20 max HP. For now each map hides four quarters, and secrets
  are spread across the whole game.
  - Today: five Goo Hearts of +10 each: the two below in Slimeshire Meadow,
    two in Gloop Forest (8.9) and one in the Matron's nest (8.7).
  - Build: a heart-quarter pickup with the item ceremony (4.13), its values in
    `game-constants.json` (today `character.player.gooHeart.maxHpBonus`).
    Hide four quarters in Slimeshire Meadow; today's two Meadow hearts become
    quarter spots or move to harder ones
    ([Chapter 1](story/chapters/chapter-1-the-clearing.md), Secrets). Gloop
    Forest's four are placed in 8.9.
  - Decided 2026-10-08: a quarter adds no life on its own; the fourth
    quarter completes a heart, and only a whole heart adds +20 max HP. The
    run starts with no hearts, and the life orb's ring shows each quarter
    found (4.12).
  - Open: whether bosses also give a full heart
    ([question 17](story/06-open-questions.md#progression)).
  - Done when: each Meadow quarter is taken once per run and stays taken
    after save and load; four quarters give exactly +20 max HP; the life orb's
    pips (4.12) show what was found; saves that took Goo Hearts still load.

- Done: `object.goo-heart` (script `game.goo-heart`) is a walk-over pickup;
  each one raises max HP by `character.player.gooHeart.maxHpBonus` (10) and
  fills HP. A collected heart sets the story flag `goo-heart.<heartId>`, so it
  is taken once per run and stays gone after save and load. Two are hidden in
  Slimeshire Meadow: on the sand behind the big west lake
  (`meadow-lakeside`) and behind the trees in the far south-east of the
  autumn grove (`meadow-autumn-thicket`). Played headless: 100 → 110 → 120 max
  HP, walking over a taken heart does nothing, and both stayed taken after
  Continue.

- Build: a collectible that permanently raises max HP, and hide at least two
  in Slimeshire Meadow. Gloop Forest's hearts are placed in 8.9 and the
  boss's heart in 8.7.
- Player proof: exploring pays off in permanent strength.
- Done when: both Meadow hearts raise max HP by the configured amount, can be
  collected only once per run, and stay collected after save/load.

### [x] 5.4 — Rebalance Chapter 1 without levels, verified 2026-09-29

- Done: base stats are the old level-2 values (attack 12, defense 3), with 100
  max HP and 100 energy. Chapter 1 quests give about 410 XP, so a typical
  player ended the chapter at level 2. Measured in the running game with no
  crits (axes and pickaxes do not hurt worms), before the change at level 2
  and after it on a fresh run:

  | Check | Before (level 2) | After (fresh run) |
  |---|---|---|
  | Wooden spear hits to defeat a worm brawler (55 HP) | 8 | 8 |
  | Stone spear hits to defeat a worm brawler | 7 | 7 |
  | Wooden spear hits to defeat Fatty One Eye (140 HP) | 20 | 20 |
  | Stone spear hits to defeat Fatty One Eye | 16 | 16 |
  | Worm brawler hits the player survives | 2 | 2 |
  | Worm swordsman hits the player survives | 3 | 2 (3 with one Goo Heart) |
  | Worm archer arrows the player survives | 5 | 5 (6 with two Goo Hearts) |

  Level 1 for reference: 10 and 7 swings per brawler, 24 and 18 on Fatty,
  survives 1 brawler hit.

- Build: set base stats so a fresh run with stone gear matches today's typical
  end-of-Chapter-1 player. Fatty One Eye and the worms keep their current
  numbers and behavior.
- Done when: before 5.1, record how many hits each starter weapon needs to
  defeat a worm brawler and Fatty One Eye, and how many worm hits the player
  survives; after the change, a fresh Chapter 1 run with the same gear matches
  each number within one hit, with no debug grants.

### [x] 5.5 — Resources respawn, verified 2026-09-29

- Done: a depleted tree, stone node or ore node records
  `respawnReadyAtEpochMs` (now + `resources.respawnMs`, provisionally 10
  minutes) in the map's saved progress. When its map loads after that time
  and its dropped piles are collected, it grows back full
  (`features/resources/ResourceRespawn.ts`); older saves start the timer on
  first load, so nothing returns early. Only scripts that opt in regrow
  (`ResourceNodeScript.regrows`). Played headless: a chopped tree stayed gone
  through a trip into the Slime Home before its time and stood again at full
  health after it. `pnpm test:progression` covers the rules.

- Build: harvested trees and stone nodes (and later iron nodes) come back after
  a long respawn time set in `game-constants.json`, tracked per map in the
  saved progress like Fatty's respawn timer. Loose starter piles and quest
  rewards still keep a fresh save softlock-free.
- Player proof: returning to a harvested area later finds it grown back.
- Done when: a harvested node respawns after its timer across map changes and
  save/load, and never respawns early.

### [ ] 5.6 — Every ability costs energy

- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Energy"): every ability costs energy, some per use (Dodge, Squash Slam),
  others over time (rolling, 7.7). Energy is not too easy to recover, so
  cooldowns get shorter. Max energy grows over the game.
- Today: only Stretch Lash (20), Squash Slam (30) and Teleport (35) cost
  energy per use; the Roll costs nothing to start, and only its held part
  drains 12 per second (`rollEnergyPerSecond`, 7.7; energy does not refill
  while rolling). Max energy is 100 and refills 8 per second
  (`character.player.stats` in `game-constants.json`). The costs and cooldowns
  are literals in `game/player/abilities/ability_definitions.gd`.
- Build: an energy cost for every ability, per use or per second; the costs
  and cooldowns move into `game-constants.json`; a slower refill and shorter
  cooldowns; max energy that can grow (saved with the run, like the max HP
  that hearts add). The Roll (7.7) uses the same costs; Gulp forms cost no
  energy (2026-10-08, 7.5).
  Tune in the playground first.
- Open: the refill pause, free basic attacks, tiny cooldowns, a minimum to
  start rolling, and energy drops
  ([questions 20–24](story/06-open-questions.md#energy-rework-details)); the
  item that raises max energy and where it is found
  ([question 19](story/06-open-questions.md#progression)).
- Player proof: the slime has to choose when to dodge, lash or slam.
- Done when: in the playground each learned ability spends its configured
  energy and shows "Low energy" when there is not enough; the refill is slower
  and the cooldowns shorter than today, with every value in
  `game-constants.json`; a fresh Chapter 1 run still beats Fatty One Eye; the
  owner accepts the feel.

### [ ] 5.7 — Bags: 10 slots from Elder Plop, 20 in the Gloop Cavern

- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Bags"): the slime starts with no bag. Elder Plop gives a 10-slot bag when
  the player accepts the first quest. A 20-slot bag waits in a coffer in the
  Gloop Cavern. A new bag replaces the old one.
- Today: 20 slots from the start (`inventory.initialMaxSlots`).
- Build: the bag is a permanent item that sets the number of slots, and a
  fresh run has none. Accepting A Place to Work hands over the 10-slot bag
  with the item ceremony (4.13), the game's first
  ([Chapter 1](story/chapters/chapter-1-the-clearing.md), Beat 1). The 20-slot
  bag exists as an item for the cavern coffer, which is placed in 8.9. Slime
  Basics' bag step comes after the bag (4.11). Check that nothing before
  Plop's quest needs carrying.
- Player proof: the first thing the slime is given is somewhere to carry
  things.
- Done when: on a fresh save there are no bag slots until A Place to Work is
  accepted, then 10, with the ceremony; an eleventh stack says the bag is full
  (the 4.11 message); the 20-slot bag replaces the 10-slot one and keeps every
  item; the bag survives save and load; saves made before the change still
  load with nothing lost.

### [ ] 5.8 — A Home of Your Own: sleeping and the vault

- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Vault"): the vault is found inside a house during a quest that also
  teaches sleeping to recover. It has 50 slots, all vaults share one storage,
  and weapons can be stored. The vault screen shows the vault on the right and
  the bag on the left, with drag and drop both ways. Weapons go into the vault
  instead of being dropped ([Dropped](#dropped), was UX.3).
- Today: there is no storage, and chests are take-only. Beds work (3.4, 3.5),
  but nothing teaches them.
- Build: the new Chapter 1 quest **A Home of Your Own**, after Stone Tools
  ([Chapter 1](story/chapters/chapter-1-the-clearing.md), Beat 3): the slime
  explores the house, sleeps in its bed (rest to recover, and wake here after
  a defeat), and finds the vault with the full ceremony (4.13). The vault
  object, one shared vault storage saved through `RunState`, and the
  two-panel vault screen.
- Open: which house, and whether Elder Plop gives the quest
  ([question 11](story/06-open-questions.md#progression)); whether more vaults
  can be crafted after the first
  ([question 12](story/06-open-questions.md#progression)).
- Depends on: 4.13 and 5.7.
- Player proof: the slime has a home to rest in and somewhere to keep what the
  bag cannot hold.
- Done when: on a fresh save the quest follows Stone Tools; sleeping in the
  house's bed completes its step and sets the respawn point; the vault's
  ceremony plays once; items and a weapon dragged into the vault and back
  stay where they were put through a map change and save and load; a second
  vault in the playground shows the same contents.

### [ ] 5.9 — A boss's Pearl grants its ability

- Answered 2026-10-02 ([Open questions](story/06-open-questions.md#answered)):
  each of the eight Pearls grants one unique permanent ability. Pearl 1 grants
  Squash Slam (it was Jump until the jump was removed on 2026-10-08); Pearl 2,
  the Matron's, grants Stretch Lash (8.7). Dodge (the Roll since 2026-10-09)
  stays basic training from Elder Plop.
- Today: finishing The One-Eyed Guardian teaches Squash Slam (since
  2026-10-08, 5.2).
- Build: a Pearl that a beaten boss leaves; taking it plays the full ceremony
  (4.13) and grants the boss's ability for good (the reward type of 5.2).
  Fatty One Eye leaves Pearl 1, which grants Squash Slam; The One-Eyed
  Guardian's reward no longer teaches it
  ([Chapter 1](story/chapters/chapter-1-the-clearing.md), Beat 5).
- Open: the premise around the Pearls
  ([question 2](story/06-open-questions.md#story)), where the Wellspring is
  ([question 5](story/06-open-questions.md#story)), and what a boss does once
  its Pearl is gone ([question 6](story/06-open-questions.md#story)).
- Done when: on a fresh save Squash Slam is locked until Fatty One Eye is
  beaten; his Pearl grants it once, with the ceremony; it survives save and
  load; older saves keep the abilities they have.

**Milestone 5 complete when:** the player grows only through gear, Goo Hearts,
and story unlocks, and Chapter 1 still plays as it did. The systems are in
(2026-09-29); open: the assets below and a human Chapter 1 run (4.9). Since
2026-10-07 it also needs 5.3 (heart quarters) and 5.6–5.9.

**Assets**

- Reuse: the area-title banner for "ability learned" and "Goo Heart", Kenney
  music jingles.
- [~] Goo Heart world sprite: generated 2026-09-30 (Magnific GPT-2, a glossy
      goo heart, `sheet.props.gulp.8x1` frame 5). Open: a pickup effect and
      sound (the heal chime stands in).
- [ ] HUD heart or max-HP growth display. Since 2026-10-02 this is the life
      orb's ring of heart pips in the bottom console (4.12, mockup first).
      Placeholder: the longer HP bar and the "Goo Heart! Max HP 110" banner.
- [ ] Heart quarter sprite and pickup effect (5.3).
- [ ] Bag icons for the 10-slot and 20-slot bags (5.7).
- [ ] Vault object, its sounds, and the two-panel vault screen (5.8).
- [ ] Pearl sprite (5.9).
- [ ] Ability-learned sting. Placeholder: the old level-up jingle
      (`audio.sfx.player.ability-learned.1`).
- [x] Retired: `ui-levelup-crest-frame` (2.2 MB), the eight perk icons, and the
      perk-choose sound.

## 6. Rebuild Slimeshire: The Workshop

- **2026-09-30 (owner: the Workshop comes too early):** the Workshop is now a
  later upgrade of the workbench, after Chapter 2 at the earliest, once the
  Forge makes iron bars. **The Old Workshop** now needs the
  `chapter-2-complete` flag, so Chapters 1 and 2 never offer it. The ruin
  stays in Slimeshire ("Rebuilding it will take iron from a working Forge."),
  and saves that already restored it keep it. Everything built here (story
  variants, station-aware crafting, restoration sites, recipes unlocked by a
  building) stays, and the Forge (8.5) uses it in Chapter 2. The Workshop's
  return is in the [parking lot](#after-release-1--idea-parking-lot).

Crafting buildings are ruined buildings in Slimeshire. Restoring one turns it
into a station the player uses directly and unlocks its recipes; no NPC runs
it. The placeable
workbench stays as the Chapter 1 field station for tier-1 recipes; portable
recipes stay portable so a fresh save cannot softlock.

### [x] 6.1 — Story-flag scene variants, verified 2026-09-30

- Done: `game.story-variant` keeps only one of two authored subtrees in the
  tree ("When Set" once its story flag is set, "When Unset" before); visuals,
  collision, doors and stations swap with it, parked subtrees are freed with
  the script, and the world controller ignores interactables that are parked.
  Its `set` handler sets the flag. First use: the cracked ground (7.4), whose
  sinkhole and door appear when the Heavy form breaks it, and stay after save
  and load. `pnpm test:scene-integration` covers the swap.

- Build: a ScriptNode that shows one child subtree per story-flag state, so a
  building can be authored as both ruined and restored in the same world scene,
  including collision. Story flags already persist; quests can already test
  them.
- Player proof: the town changes when the story does.
- Done when: setting the flag swaps visuals and collision, and save/load keeps
  the right variant.

### [x] 6.2 — Station-aware crafting (was UX.2), verified 2026-09-29

- Done ([spec](archive/phaser/superpowers/specs/2026-09-29-station-aware-crafting-design.md)):
  recipes name a `station` (`portable`, `workbench`, `workshop`, `forge`,
  `kitchen`) and a tier; a site is a station plus its tier, authored on the
  `game.workbench` script (`recipeContext`, `tier`). `recipesAt(site)` lists a
  station's recipes (the Workshop also lists the workbench's), including ones
  above its tier, and `CraftingService` refuses `wrong-station` and
  `station-tier` before touching the inventory. The one crafting popup is
  titled for its site ("Crafting", "Workbench", "Workshop · Tier 2") and names
  every lock ("Needs tier 2", "Not learned yet", "Already owned"). `alchemy` is
  gone; `brew-fizzy` and `weave-tonics` wait in `kitchen`. Played headless: C
  listed only the three portable recipes, a placed workbench its four.
  `pnpm test:ui` covers wrong station, tier, and untouched inventory; the
  crafting Playwright spec passes again.


- Build: one crafting popup and recipe catalog filtered by unlock, station
  (`portable`, `workbench`, `workshop`, `forge`), and station tier; explain
  every lock; validate before consuming ingredients. Remove the `alchemy`
  context and move `brew-fizzy` and `weave-tonics` to `kitchen`, where they
  stay unavailable until the Kitchen exists. Write a short spec first.
- Done when: a wrong station cannot craft a recipe, and a failed craft never
  consumes materials.

### [x] 6.3 — Restore the Workshop, verified 2026-09-30

- Done: `object.workshop` stands in Slimeshire's woodcutter yard, north of the
  plaza (hand-placed `level-1-workshop`, 0.85 scale). It is a story variant on
  `workshop.restored`: the ruin carries a `game.restoration-site` (F: "Restore
  the Workshop (60 wood, 40 stone)"), the restored building a Workshop station
  (`game.workbench`, `recipeContext: workshop`, tier 1). Elder Plop offers
  **The Old Workshop** (optional, after Stone Tools; `activate-object`
  objective, completes on the spot, 25 coins). Without the quest the ruin says
  to ask Elder Plop; short of materials it says what is missing, in red; paying
  sets the flag, raises a dust cloud with a small shake and plays the
  restoration sound, and the ruin becomes the Workshop at once. The quest
  arrow points at the ruin. Played headless on the running game: locked, then
  missing wood, then restored and completed; the station stayed after a trip
  into the Slime Home and back and after save and load.
  `pnpm test:scene-integration` (the scene before and after its flag),
  `test:quests` (the arrow) and `test:ui` cover it.

- Build: a ruined Workshop in Slimeshire and a restoration quest paid in
  materials (wood and stone; coins are saved for the later shop and repairs).
  Restoring it swaps the variant (6.1); pressing F at its station opens the
  Workshop recipes.
- Player proof: the player rebuilt part of the town and can see it.
- Done when: the restoration quest completes on a fresh save, and the restored
  Workshop and its station survive leaving the map and save/load.

### [x] 6.4 — Restoring a building unlocks its recipes, verified 2026-09-30

- Done: the Workshop's first own recipe is the **Slam Hammer** (25 wood, 25
  stone; a slow, short-reach hammer with heavy knockback, retuned from its
  debug-arsenal stats to 14 damage, 1.3 s, knockback 320). A placed workbench
  lists the Workshop's tier-1 recipes last, locked: "At the Workshop" in the
  list and "Craft this at the Workshop." in the details; the Workshop lists
  its own recipes first, then every workbench recipe. The restored building is
  the unlock, so it survives save and load with the story flag. Played
  headless: the hammer was locked at the workbench and crafted at the restored
  Workshop.

- Build: restoring the Workshop unlocks its tier-1 recipes; upgrading it
  unlocks the next tier. The Workshop crafts everything the workbench does,
  plus its own recipes. Its tier-2 upgrade happens in Chapter 2 (8.6).
- Done when: before restoration the Workshop recipes show as locked with the
  reason, afterwards they are craftable, and the unlock survives save/load.

### [ ] 6.5 — Weapons and tools are hammered at the bench

- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Crafting time"): weapons and tools are made by staying at the bench and
  hammering: a few timed strikes and a new hammering animation, ending in the
  item ceremony. Quick recipes stay instant. Forge materials cook in the
  background instead (8.5).
- Today: every recipe is instant.
- Build: a hammering session at the workbench for every weapon and tool recipe
  (the stone tools and spears, the Reinforced Pickaxe, the iron gear), the
  slime's hammering animation, and the ceremony (4.13) at the end. Every other
  recipe (the workbench itself, the tonics, the berry basket) stays instant.
  Write a short spec first (how many strikes, their timing, what a missed
  strike does) and get the owner's yes.
- Player proof: forging a weapon is the moment the player earns it.
- Done when: on a fresh save the Stone Axe is made by hammering and ends in
  the ceremony; walking away before the last strike uses no materials (the
  6.2 rule); quick recipes are still instant; the owner accepts the feel.

**Milestone 6 complete when:** the player restores the Workshop and crafts
there, and the town visibly changed. Built 2026-09-30; waiting on the owner to
accept the Workshop art and restoration sound. Reopened 2026-10-07 for
hammering (6.5).

**Assets**

- Reuse: `decoration-world-solid--tool-bench`, `--anvil`, `--grindstone`, the
  crafting backplates.
- [~] Ruined Workshop exterior (320 × 320 house frame): Magnific GPT-2,
  `godot/asset/MAPS/Houses/320-workshop-2x1.webp` frame 0
  (`scripts/houses/pack-workshop.py`); owner to accept.
- [~] Restored Workshop exterior: frame 1 of the same sheet; owner to accept.
- [~] Restoration effect and a construction sound: a procedural dust cloud and
  camera shake; `world/restore-building` has a Magnific take (library) and a
  synth take, both in the next picker round; owner to accept.
- [ ] Workshop header art for the crafting popup (optional).
- [ ] The slime's hammering animation and strike sounds (6.5).

## 7. Gulp — The Signature Mechanic

The slime eats a Gulp material and takes its form for a while. Each form has a
look and one rule. See
[Gulp](GAME_GUIDELINES.md#signature-mechanic-gulp).

**Controls (decided 2026-09-29): one key is the slime's mouth.** It was W
until 4.10 moved movement to WASD; it is now Q (the `eat` control, with a
short eat clip). No menu ever opens to eat. The task notes below say W
because they describe the game when they were checked.

| Input | Result |
|---|---|
| Tap Q near a Gulp spot (or right-click the spot) | Eat from the world: free, uses nothing from the inventory |
| Tap Q away from a Gulp spot, not in a form | Nothing but a hint: "Hold Q to eat what you carry" (changed 2026-09-30: stray taps turned the slime Heavy far from any rock) |
| Tap Q in a form, away from a Gulp spot | Burp the form away (cancel) |
| Hold Q | Quick wheel of carried Gulp materials; the game keeps running; WASD or the mouse choose, release eats (built in 7.2) |

Eating a different material switches forms; eating the same material at a
Gulp spot resets the timer. **Gulp spots** are world objects (a mossy
boulder, a silk cocoon) that never run out and look different from walk-over
piles, which are collected on contact. Every Gulp puzzle has its spot beside
it, so a puzzle never depends on what the player carries.

**Replaced 2026-10-09:** the table above is the old eating; 7.5 built the essence
Gulp in its place.

**Planned 2026-10-02, not built** ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built)):
the forms become armors the slime keeps (7.5), webs trap the slime and only the
Silk Armor passes them (7.6), and sprint becomes a mid-game roll that breaks
cracked walls in the Stone Armor (7.7). The table above and tasks 7.0–7.4
describe the game today.

**Since 2026-10-08** Gulp is redesigned around essences instead of armors
([the 2026-10-08 decisions](#the-2026-10-08-decisions),
[Gulp](GAME_GUIDELINES.md#signature-mechanic-gulp)). 7.5–7.7, 8.12 and 8.13
build it.

### [x] 7.0 — Rough Gulp prototype, verdict 2026-09-29: keep

- Verdict (owner): "I like the Gulp." Add more effects; Heavy should also
  break cracked ground to discover caverns. Both are now in the playground:
  Heavy cracks ground into a cavern (7.4) and the Sticky form crosses webs
  (7.2).

- Build: right after the playground (3.7), and ahead of Milestones 4–6: the
  Heavy form only, with placeholder art, in the playground. Tapping W at a
  stone Gulp spot or with stone in the inventory starts it; tapping W again
  burps it; one rough pressure plate opens one gate. No save/load, no polish.
- Built 2026-09-29, waiting for the user's verdict. Try it with `pnpm dev` at
  `http://localhost:3000/?map=playground`: walk to the mossy boulder west of
  the plate below the cobble yard, press W ("HEAVY 1:00" appears), stand on
  the plate to open the sealed gate, and walk into the pen. W away from the
  boulder burps; W elsewhere eats a stone from the chest by the spawn. Heavy
  moves at 0.6× speed and ignores knockback; the form lasts
  `gulp.formDurationMs` (60 s). Code: `features/gulp/`, `content/gulp/`,
  `game.gulp-spot` and `game.pressure-plate` scripts, `object.gulp-spot-stone`
  and `object.pressure-plate` scenes; `pnpm test:gulp`.
- Player proof: Gulp can be felt in a day or two instead of on paper.
- Done when: the user has played it and decided keep, change, or drop; the
  verdict and any control changes are written under this task before the
  Chapter 2 outline (8.1) is finished.

### [x] 7.1 — Gulp action and the Heavy form, verified 2026-09-30

- Done: the W controls above for stone, with stone Gulp spots; Heavy lasts
  `gulp.formDurationMs` (1 minute): no knockback, holds plates down, moves
  slower. The form's badge (Magnific art, `ui.icons.gulp-forms.2x1`) and time
  left float over the slime; "[W] Gulp" floats over the spot in reach. A form
  is not saved: it ends cleanly on a map change and on save and load (played
  headless: Heavy through the Slime Home door and after a reload, the stone
  stays spent). The owner accepted Gulp as fun (7.0 verdict).
- Planned 2026-10-02: the Heavy form becomes the Stone Armor, kept for good
  and costing energy (7.5).

- Build: the W controls above for stone, with a proper Gulp spot. Heavy lasts
  **1 minute** (a `game-constants.json` value, tuned after playtests): no
  knockback, holds pressure plates down, moves slower. A HUD timer shows the
  form, and a prompt near a Gulp spot reads "[W] Gulp".
- Player proof: the slime visibly becomes heavier and plays differently.
- Done when: the form starts from a Gulp spot and from the inventory, ends,
  cancels with a burp, and survives map changes and save/load safely (or ends
  cleanly on them); eating never opens a menu; and the user accepts it as fun
  in the playground (3.7).

### [x] 7.2 — The Sticky form and the quick wheel, verified 2026-09-30

- Done: eating a silk cocoon Gulp spot or a silk clump makes the slime
  **Sticky** (`content/gulp/gulpForms.ts`); a `game.spider-web` barrier
  catches a normal slime (stuck for a moment, set back on its side) and lets a
  Sticky one through. The playground's web nook (south-west) hides a chest
  behind a web, with the cocoon beside it. The Sticky slime tears a web open
  for good as it passes (owner feedback 2026-09-30), so a form that wears off
  on the far side never traps it.
- Quick wheel: W is decided on release. A tap does what it did; holding W for
  a quarter second opens a ring of the carried Gulp materials around the slime
  (`features/gulp/GulpWheel.ts`), starting on the last-used one; the arrow keys
  or the mouse choose, the slime stands still while choosing, the game keeps
  running, and releasing eats the choice (switching forms directly, no burp).
  Holding with nothing carried says so. The wheel lists `GULP_FORMS`, so a
  third form is one entry there plus its art. Played headless in the
  playground: tap → Heavy, hold + Down → Sticky, hold + Up → Heavy, 700 ms of
  simulation passed while the wheel was open. `pnpm test:gulp` covers the
  entries, the switch and the slot picking.
- Planned 2026-10-02: the Sticky form becomes the Silk Armor and the quick
  wheel of carried materials changes with the armors (7.5); webs trap the
  slime until the Silk Armor passes them (7.6).

- Build: eating silk makes the slime Sticky: it crosses spider webs that would
  catch it normally. Holding W opens the quick wheel of carried Gulp materials.
- Done when: both forms reuse one form system, eating the other material
  switches forms, the wheel picks a form without pausing, and adding a third
  form is data plus art.

### [x] 7.3 — Gulp puzzle pieces, verified 2026-09-30

- Done: the pieces are object scenes placed from Scene Studio and set up in
  its inspector, with no scene connections: `object.gulp-spot-stone` and
  `object.gulp-spot-silk` (eaten any number of times), `object.pressure-plate`
  (new art; **Opens Gate ID** opens every `game.gate` with that id when the
  Heavy form presses it; latching by default), `object.gate-verdant`
  (`game.gate`), `object.spider-web` (Sticky crosses) and
  `object.cracked-ground` (Heavy breaks it; ids and door target in the
  inspector). Studio has no signal-connection editor yet, so links are
  properties. The playground's plate now opens its gate through the property
  (played headless: a light slime does nothing, the Heavy form opens it).
  `pnpm test:scene-integration` covers the plate frames, the latch and the
  gate link.
- Planned 2026-10-02: the web barrier traps the slime and only the Silk Armor
  passes it (7.6); what the Gulp spots become with the armors is open (7.5).

- Build: stone and silk Gulp spots, a pressure plate linked to a gate (reuse
  `game.gate`), and a web barrier or bridge, all authored in world scenes.
- Done when: the pieces work from Scene Studio placement alone, and a Gulp spot
  can be eaten any number of times.

### [~] 7.4 — Heavy breaks cracked ground into caverns

- Built 2026-09-30 (playground): `object.cracked-ground` is weak ground only
  the Heavy form breaks (`game.cracked-ground`): it has to land a jump on it
  (owner feedback; standing on it only creaks, `requiresLanding` off restores
  the old rule). It sets a
  story flag, and a story variant (6.1) swaps the cracks for a sinkhole with a
  rope ladder; F climbs down into the dev-only `playground-cavern` (a chest and
  crystal shards), and the cave ladder climbs back up beside the hole.
  Played headless both ways; the hole stays open after returning.
- Next: the owner tries it; then a first real cavern secret in Chapter 1 or 2.
- Changed 2026-10-08 ([the 2026-10-08 decisions](#the-2026-10-08-decisions)):
  with the jump removed, a Squash Slam in the Heavy form breaks it (the slam's
  impact counts as the Heavy landing did; `requires_impact` off restores the
  standing rule). The creak hint names the slam and its key once the slam is
  learned. Tests: `test_gulp.gd`.
- Planned 2026-10-02: the Stone Armor (7.5) breaks the cracked ground instead
  of the one-minute Heavy form, and rolling in the Stone Armor breaks cracked
  walls (7.7).

### [~] 7.5 — Suck, throw and swallow essences

- Built 2026-10-09 as a playground prototype, waiting for the owner's
  playtest; its art came the same day and the owner accepted it. A second
  round the same day, after the owner's feedback, brought 64 more things to
  lift (67 kinds in all), breaking by material, and sounds. Try it with F6 on
  `game/dev/playground.tscn` (the playground teaches Swallow and puts essences
  in the bag):
  - The **gulp yard**, north-west of the spawn, has mossy rocks, puffballs and
    pinecones, and a stone, a silk and a swim essence. The old stone spot (by
    the heavy plate) and silk spot (by the web nook) are placed essences now.
  - The **liftable gallery**, east of the spawn (x 1600–2084, y 1540–1780),
    has all 67 kinds in rows of 12, to suck, throw and break.
  - Hold Q facing something to suck it in. Q throws it at the pointer: try the
    training dummies east of the spawn. 1 swallows a held essence; 1 with
    nothing held spits the form out. A right click (W in the keys-only scheme)
    on an essence puts it in the bag, and Use in the bag puts it back in the
    mouth. The suck reaches 80 px (`gulp.suckRangePx`, shortened 2026-10-09).
  - A hit pops the form out for about 3 s. Orb-weavers and slime-spiders drop a
    silk essence a third of the time; the Clod Stomper (8.12) always drops a
    stone essence.
  - Code: `game/player/gulp/` (`mouth.gd`, `thrown_object.gd`,
    `break_burst.gd`, `gulp_controller.gd`), `game/scripts/essence.gd` and
    `liftable.gd`, `game/data/liftables.json`, the `gulp.*` game constants.
    Tests: `test_gulp.gd`.
  - Art (2026-10-09, accepted by the owner the same day): sucking plays the
    `suck` clip; a throw faces the aim and plays `spit` (300 ms); while the
    mouth holds something the slime idles and walks as the full slime
    (`full-idle`, `full`), and the held thing shows inside, on its belly. The
    liftables and the essences have their own sheets (Assets below). The
    first pot (`object.liftable-pot`, `pot_art.gd`), a copy of a Zelda
    vessel, is gone. Still placeholder: the suction lines are pale streaks
    (`suction_fx.gd`). `godot/tools/render_gulp_art.gd` draws all of it on one
    sheet with the game's scenes.
  - **67 liftables** (second round, 2026-10-09). The owner asked for at least
    8 by 8 things to suck and throw, for dungeons, terrains and interiors,
    pots included as long as they are original. They cover home and kitchen,
    dungeon, forest, cave and crystal, snow and ice, desert, beach and swamp,
    garden and lava, plus four spares. Each kind has a name and a material
    (clay, glass, wood, metal, stone, soft, ice, snow or crystal) in
    `game/data/liftables.json`. One scene, `object.liftable`, serves every
    kind: set `kind` on the placed instance (and the Visual's `frame`, so the
    editor shows it); the frame and the body's footprint follow the kind.
    `object.liftable-rock`, `-puffball` and `-pinecone` preset the kind.
  - **Breaking:** a thrown liftable bursts into 3 × 3 chunks of its own
    picture that fly, tumble, skip once and fade (0.7 s, `break_burst.gd`),
    with its material's particles and sound: a pot shatters, a crate
    splinters, a kettle clangs, a pumpkin splats. Since the owner's third round
    (2026-10-09) essences are never thrown: Q spits one out whole 44 px ahead,
    where it stays (`mouth.gd`); the thrown stone's stun and silk's slow patch
    are gone. A full slime walks at 70% (`gulp.holdingSpeedMultiplier`).
    It hits for `gulp.throwDamage` times its
    material's `gulp.throwDamageByMaterial` (metal 1.5, stone 1.3, crystal
    1.2, ice 1.1, clay, wood and essences 1, glass 0.8, soft 0.6, snow
    0.4). A hit that knocks the held thing out breaks it the same way at the
    slime's feet.
  - **Sounds** (Sound Picker round 5; the game plays option A until the owner
    picks): the suck `GulpSuck`, the catch `GulpCatch`, the throw `GulpSpit`,
    and one break per material (`BreakClay`, `BreakGlass`, `BreakWood`,
    `BreakMetal`, `BreakStone`, `BreakSoft`, `BreakIce`).
  - Since 2026-10-09 Tom teaches Swallow (8.13). Beyond the Verdant Gate no
    longer does (it was a stand-in).
- Decided 2026-10-08 ([the 2026-10-08 decisions](#the-2026-10-08-decisions);
  the design is in [Gulp](GAME_GUIDELINES.md#signature-mechanic-gulp)). It
  replaces the armors of 2026-10-02, and it answers owner questions 13–15.
- Before 2026-10-09: one-minute forms eaten from Gulp spots or carried
  materials, chosen on the hold-Q quick wheel (7.1, 7.2).
- Build, in the playground first:
  - **Suck** (hold Q, short range). An essence or a light liftable object (a
    pot, a rock, a pumpkin and dozens more; original pots are fine, owner
    2026-10-09) flies into the slime; never a live enemy. A tap with nothing
    in reach puffs.
  - **Holding.** The slime swells up and waddles. It cannot attack or use
    abilities. Q throws what it holds, aimed at the pointer (the facing in
    keys-only); it breaks where it lands, by its material, for damage. Stone
    also stuns, and silk leaves a patch that slows enemies.
  - **Swallow**, a learned ability (`swallow`) on 1, in the
    jump's old HUD place. A held essence becomes its form. With nothing held,
    the current form drops out as a whole essence.
  - **Forms.** One at a time, no timer, no energy. A hit pops the form out as a
    blob the slime can suck back for a moment, and the pop takes the hit's
    side effect. Swallowing another essence pops the old one out. A form and a
    held thing survive doors and saves.
  - **Essences** are items: stone, silk and swim.
    - Today's Gulp spots become placed essences, which come back when the map
      is entered again.
    - Enemy drops fade after about 30 s.
    - Interact puts an essence in the bag, and "Use" in the bag puts it in the
      slime. Walking over one does nothing. Recipes can use them.
  - **Forms:** Stone (today's Heavy), Silk (Sticky) and Swim (today's Frog).
    The frog on its lily pad becomes decoration, and swim essences are placed
    by hand until an aquatic monster drops them.
  - The quick wheel and eating carried materials go away.
  - Keys: Q, and 1 for Swallow (4.10).
- Later: two upgrades that let the slime suck in heavy rocks, like Zelda's
  gloves, each with the full ceremony. What they are and where they are found
  is Open.
- Depends on: 4.13 (Swallow's ceremony).
- Player proof: the slime eats the world and becomes it, and a puzzle's
  essence is something to find.
- Done when:
  - in the playground the slime sucks, throws and swallows, and each form does
    its rule;
  - a hit pops the blob, and the blob can be taken back;
  - a form and a held thing survive a door and a save;
  - a wasted placed essence is back after re-entering the map;
  - the owner accepts the feel.

### [ ] 7.6 — Webs trap; only the Silk form passes

- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Webs"): a web blocks the path and traps the slime in place. Only the Silk
  Armor passes a web, and passing costs energy; when the energy runs out
  while the armor is passing, the armor comes off at that moment. The
  Matron's special-attack webs work the same way, as do some webs in spider
  camps. A web door closes the Matron's camp.
- Changed 2026-10-08 (7.5): the **Silk form**, from a silk essence, passes
  webs. Forms cost no energy, so the energy rule is gone. Tom's web (8.13) is
  different: a weapon tears it.
- Today: a web holds the slime 0.9 s and pushes it back; the one-minute
  Sticky form passes it and, since the 2026-09-30 feedback (4.9), tears it
  open for good.
- Build: one web rule for world webs, the Matron's volley patches (8.7) and
  the spider-camp webs chosen in 8.9. Without the Silk form the slime is
  trapped in place; in it, the slime passes. Also a web door object for the
  Matron's camp (8.7).
- Not decided: how a trapped slime gets free, and whether a web stays after
  the Silk form passes (it tears open today, a fix made for the timed form).
  Ask the owner before building.
- Depends on: 7.5.
- Done when: in the playground a web traps the slime without the Silk form (in
  the Stone form too) and lets the Silk slime through; a Matron volley patch
  behaves the same.

### [~] 7.7 — The Roll replaces the Dodge

- Built 2026-10-09 and reworked the same day after the owner's feedback ("the
  roll should feel like the Zelda sprint"): a dash like Zelda's Pegasus
  Boots. Waiting for the owner's feel. Try it on 2 with F6 on
  `game/dev/playground.tscn`. It keeps the ability id and input action
  `dodge` (saves, quests and the HUD slot are unchanged) and shows as "Roll";
  Stone Tools still teaches it ("curl up, spin, and roll away! Keep holding it
  and you keep rolling.").
  - **Spin-up:** the slime curls into the ball and spins in place for 260 ms
    (`rollSpinUpMs`), laying two dark skid streaks and kicking dust back like
    screeching tires (cue `RollRev`). It does not move and has no i-frames.
  - **Launch:** it shoots off along one of eight directions: the pointer aim,
    else the held movement keys, else the facing, snapped. 460 px/s
    (`rollLaunchSpeed`) easing to 340 (`rollSpeed`) over 450 ms
    (`rollMinMs`), with 400 ms of i-frames from the launch
    (`rollInvulnerabilityMs`); cue `RollLaunch`.
  - **Straight:** the movement keys do nothing while it rolls. It cannot turn
    or slide sideways (`rollTurnRadPerS` was removed).
  - **Held:** after that it keeps rolling while 2 is held and drains 12 energy
    per second (`rollEnergyPerSecond`; energy does not refill while rolling).
    Letting go or running out of energy stops it.
  - **Bonk:** when a wall, a rock or an enemy stops the ball, it bonks (cue
    `RollBonk`). The screen shakes (220 ms at 0.008, `rollBonkShakeMs`,
    `rollBonkShakeIntensity`) with a 60 ms hit-stop (`rollBonkHitStopMs`).
    Things standing within 140 px of the impact wobble
    (`rollBonkWobbleRadiusPx`). An enemy within 34 px takes 10 damage and 300
    knockback (`rollBonkHitRadiusPx`, `rollBonkDamage`, `rollBonkKnockback`;
    damage 0 turns this off). The slime bounces back off it in the knockback
    pose with an 18 px hop, at 400 px/s easing out over 360 ms, 72 px back:
    at least a tile (owner, 2026-10-09; `rollBounceHopPx`, `rollBounceSpeed`,
    `rollBounceMs`), and then the roll
    ends.
  - A knockback, a death, a door or an opened window ends it at once. The
    next roll can start 250 ms after one ends (`rollCooldownMs`). Holding
    something in the mouth or swimming still blocks it.
  - Everything comes with the lesson (owner, 2026-10-09: once learned, the
    slime learns everything about it). There is no later upgrade.
  - Values in `character.player.movement` of `game-constants.json` (the
    `dodge*` values are gone). Code: `game/player/roll/player_roll.gd` and
    `roll_fx.gd`. Art: the `ball-side` row of slime v2 page 4 (Assets below).
    Sounds: Sound Picker round 5 (the game plays option A until the owner
    picks). Tests: `test_player_movement.gd` (updated for the dash, not run
    yet).
- Open (for the owner): the feel and the numbers; its energy cost (5.6
  decides per-use costs; only the held part drains today); and whether a roll
  in the Stone form breaks cracked walls (not built).
- Decided 2026-10-08 ([the 2026-10-08 decisions](#the-2026-10-08-decisions)):
  the Dodge becomes the Roll, on key 2 (owner, 2026-10-09). The slime curls into a ball with a
  swirl, like the roll in the old sheet
  (`godot/asset/characters/slime_normalized.webp`, row 6). It first spins in
  place, like tires screeching, then shoots off, and it keeps rolling while
  the key is held. On 2026-10-09 the owner set the rest: it goes straight
  like Zelda's dash and cannot move sideways, hitting a wall shakes things
  and the screen and bounces the slime back, and it comes whole with its
  lesson.
- Done 2026-10-08 (in the HUD session, for the owner): Shift no longer sprints,
  and Slime Basics' sprint step and the sprint hint are gone.
- Decided 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Sprint"): sprint is not available at the start. An Open Pearl grants it
  mid-game as a powerful milestone, and it is a fast roll. It combines with
  armors: rolling in the Stone Armor breaks cracked walls. Since 2026-10-08
  the Roll takes the Dodge's place instead, and since 2026-10-09 the slime
  learns all of it at once.
- Today: the Roll (key 2, taught by Stone Tools) spins up, dashes straight on
  while held and bonks back off walls (built 2026-10-09, above). The old
  dodge's 0.5 s roll is gone; its page-2 `roll-*` rows are still built but no
  longer played.
- Build: the Roll in the Dodge's place (`roll`, key 2, taught where the Dodge
  was): the curled ball, the spin-up in place, the launch, rolling straight
  on while the key is held, and the bonk. It is built and tried in the
  playground first.
- Depends on: 5.6 for its energy cost.
- Done when: on a fresh save Stone Tools teaches the Roll on 2; it spins up,
  dashes straight on while held and bonks back off a wall; the owner accepts
  the feel.

**Milestone 7 complete when:** the playground has one Heavy and one Sticky
puzzle that a player solves without a hint, and the user has accepted Gulp as
fun. Since 2026-10-08 it also needs the essence Gulp, the web rule and the Roll
(7.5–7.7) accepted in the playground.

**Assets**

- Reuse: stone and silk icons, status-effect tints, the player's `eat` clip.
- [ ] Player form-end (burp) clip: new frames on the player sheet or an
      overlay effect.
- [ ] Heavy and Sticky form overlays (stone flecks, silk strands).
- [~] Form icons for the HUD: Magnific GPT-2 badges
      (`godot/asset/UI/ui-gulp-form-icons-3x1.webp`, read by
      `game/ui/console/hud_console.gd`); owner to accept.
- [~] Gulp spots: a stone spot and a silk cocoon, clearly different from
      loose piles.
- [~] Pressure plate (up and down) and web barrier or bridge sprites: the
      silk cocoon, spider web, cracked ground, sinkhole, cave ladder and a
      mossy rune plate (raised, and pressed with its rune glowing; the plate
      shows `pressedFrame` while held) were generated 2026-09-30
      (`scripts/props/pack-gulp-props.py`, frames 0–7); owner to accept.
- [ ] Eat, burp, plate click, and web tear sounds.
- [ ] A slime-trapped-in-web effect (7.6).
- [ ] A cracked wall with its broken frame (7.7, if the Stone roll breaks
      walls).
- New for the essence Gulp (owner, 2026-10-08), each in the three player
  directions. The player clips of 2026-10-09 are Seedance 1.5 Pro videos of
  the three-quarter slime v2 (sources in `asset/Originals/characters/slime-v2/`,
  packed by `scripts/characters/pack-slime-v2-page.py --page 4|5`, aliases in
  `godot/tools/build_player_clips.gd`):
  - [~] **Suck:** the slime opens wide and pulls, with suction lines. The
        suck-down, suck-up and suck-side rows of
        `godot/asset/characters/256x256-tile_8x8-slime-v2-page-4.webp` loop
        while Q sucks (accepted by the owner 2026-10-09); the suction lines
        are still placeholder streaks.
  - [~] **Spit:** the throw, plus an arc and break effects for a rock, a
        puffball, a pinecone and an essence. The spit-down, spit-up and
        spit-side rows of page 4 play once (300 ms) on a throw, starting full
        and popping empty (accepted by the owner 2026-10-09). The arc and the
        break are drawn in code: a low arc with a shadow
        (`thrown_object.gd`), and a burst of 3 × 3 chunks of the thing's own
        picture with its material's particles (`break_burst.gd`, second round
        of 2026-10-09). Owner to judge the break.
  - [x] **The full slime:** swollen with the held thing showing inside, and
        walking funny (a waddle); idle and walk. The full-down, full-up and
        full-side rows of
        `godot/asset/characters/256x256-tile_8x8-slime-v2-page-5.webp` (an
        8 fps waddle), and the full-idle clips (the same rows at 2.67 fps, a
        slow sway). Accepted by the owner 2026-10-09.
  - [x] **The Roll:** a green ball with a swirl, like row 6 of
        `godot/asset/characters/slime_normalized.webp`. A spin-up in place with
        dust and skid marks, like screeching tires, then the launch and the
        rolling loop. The ball-side row of page 4 (from `start-ball.png`, spun
        clockwise in 45° steps) and, since the owner's third round (2026-10-09:
        "good on the side but not on top and down"), ball-down and ball-up on
        page 5 (the same still rolled on a sphere toward and away from the
        camera, `ROLLS` in the packer), with skid
        streaks and dust from `roll_fx.gd`. Accepted by the owner 2026-10-09.
        The bounce after a bonk reuses the `knockback` clip.
  - [ ] Swallow: the `eat` clip may do; a new gulp-down if it does not read.
- [x] Essence sprites on the ground, in the mouth and as bag icons (stone,
      silk, swim): `godot/asset/MAPS/items/128x128-tile_3x1-gulp-essences.webp`
      (item-icons key `gulp-essences-3x1`). Accepted by the owner 2026-10-09.
- [ ] The popped blob.
- [~] Liftables: 67 kinds on one sheet,
      `godot/asset/MAPS/props/192x192-tile_8x9-gulp-liftables.webp` (8
      columns × 9 rows of 192 px; it replaced the 6 × 1 sheet on 2026-10-09).
      Rows 0–7 hold 64 objects for every kind of place: home and kitchen,
      dungeon, forest, cave and crystal, snow and ice, desert, beach and
      swamp, garden and lava, and four spares. Row 8 holds the first three, a
      mossy rock, a puffball mushroom and a pinecone, two variants each
      (frames 64–69; accepted by the owner 2026-10-09). The 64 come from four
      Magnific GPT 2.5 grids of 16 (`grid-1.png` .. `grid-4.png`, 400
      credits). Pots are fine as long as they are original (owner,
      2026-10-09). `scripts/props/pack-gulp-art.py` packs the liftables and
      the essences from the stills in `asset/Originals/gulp/generated/` and
      writes `godot/game/data/liftables.json`. Owner to accept the 64. No
      break frames are needed: a thing bursts into chunks of its own picture.
- [x] Sounds for the Gulp, the breaks and the Roll (Sound Picker round 5,
      2026-10-09): the suck, catch and spit (`GulpSuck`, `GulpCatch`,
      `GulpSpit`), one break per material (`BreakClay`, `BreakGlass`,
      `BreakWood`, `BreakMetal`, `BreakStone`, `BreakSoft`, `BreakIce`), and
      the Roll's spin-up, launch and bonk (`RollRev`, `RollLaunch`,
      `RollBonk`). Magnific (ElevenLabs) sound effects, three takes per
      option; option A of each ships (the owner accepted the defaults on
      2026-10-09; [Sound Picker](https://claude.ai/artifact/RDDoJKEVByiJCSsRvzwLHZ))
      ([audio spec §11](godot/specs/audio.md#11-round-5-the-gulp-the-breaks-the-roll-the-clod-stomper-and-the-ceremony)).
- [ ] The Stone, Silk and Swim looks: today's shader skins (Heavy, Sticky,
      Frog) are the start.
- [~] HUD icons for Swallow and the Roll: the console's `ability-swallow.webp` and
      `ability-dodge.webp` exist (the HUD session's, `godot/asset/UI/hud-console/`); the ability
      ceremony shows them too. Owner to accept. A held-thing indicator (4.12) is not built.
- Superseded 2026-10-08: the Stone and Silk Armor looks and icons, and the
  quick wheel.

## 8. Chapter 2 — Gloop Forest

Chapter 2 turns Gloop Forest from an empty map behind the Verdant Gate into
the second chapter. It absorbs the former milestones 6 (iron), 7 (enemy
materials), 8 (Forge), and 13 (progression pass).

### [~] 8.1 — Write the Chapter 2 outline

- Draft 2026-09-30, waiting on the owner:
  [Chapter 2 outline](design/2026-09-30-chapter-2-outline.md)
  (six quests, places, characters from existing sheets, materials with
  renewable sources, recipes, the Matron built around Sticky, three Gulp
  puzzles, build order, and five questions). The quests are not stubbed in the
  catalog yet: `quests:check` needs their items and recipes, which 8.3–8.6
  add; they become `chapterTwo.ts` as those land.
- Squash Slam (fixed 2026-09-30): it hits every enemy and training dummy
  within its radius through the damage router (30 damage, pushed outwards);
  before, like the lash, it only hit the Shift+8 target dummy. Measured in
  the playground: a worm archer went from 40 to 10.
- Owner's answers 2026-09-30: The Old Workshop becomes required in Chapter 2
  (superseded the same day: the Workshop moved after Chapter 2, see 6);
  Pip and Sunny reuse the existing sheets (new art for further characters);
  the Matron's web-volley design is approved for now. Stretch Lash: option B,
  a tool as well as a hit, so the main line teaches it (the outline has it
  as Q1's reward).
- Stretch Lash built 2026-09-30: an animated goo tendril
  (`effect.player.stretch-lash`, Magnific art packed by
  `scripts/effects/pack-stretch-lash.py`) reaches 180 px along the slime's
  facing. Reworked the same day (owner: a hook, not a weapon): it does no
  damage. A loose pickup it touches flies to the slime; anything solid it
  catches (a tree, rock, post, wall, statue or bell) pulls the slime across
  to it, over water too, landing just short of it on walkable ground; a
  **lash bell post** it catches rings (`object.lash-bell-post`,
  `game.lash-bell`, opens the gates named in Opens Gate ID, Magnific bell
  sound). Enemies ignore it. Try it in the playground's lash yard
  (south-east): walking in teaches the lash (`game.ability-lesson`); from the
  west bank pull the wood and stone piles off the island, hook the bell to
  ring it (the pen to the west opens) and fly onto the island, then hook the
  armor statue on the bank to fly back.

- Build: 5–6 quests in `chapterTwo.ts` form, with givers, objectives,
  rewards, flags, and material sources (resources respawn after 5.5). Assign
  the chapter's abilities: Stretch Lash from a quest, Squash Slam from the boss
  (8.7; since 2026-10-08 Squash Slam comes from Fatty One Eye instead, 5.9). Plan the Gulp puzzles and the boss's use of Sticky form around the
  Gulp prototype's verdict (7.0) and the fresh-eyes playtest notes (4.9).
- Done when: the outline is written, every recipe in the chapter has a
  reachable source, it follows the 7.0 verdict, and `pnpm quests:check` passes
  on the stubbed quests. If Gulp changes later in Milestone 7, update the
  outline before starting 8.7 and 8.9.

### [~] 8.2 — A new Gloop Forest enemy

- Built 2026-09-30 (owner: "use the orb-weaver for now"): `orb-weaver`
  (`content/characters/orb-weaver/`, `character.orb-weaver`) shares the
  orb-weaver sheet (the Meadow spider went back to its yellow sheet on
  2026-10-01, so the two never look alike), drawn 1.3× larger and
  tinted darker. It is tougher (70 HP, knockback resist 0.3), sees and shoots
  farther (300 / 240 px), keeps its distance and roots with webs (30 damage,
  1.3 s), and drops silk (50 %) and shards (20 %). Its voice is the spider's,
  pitched down (placeholder). It is in the playground pen, and Gloop Forest
  has two orb-weaver camps (north-east and south-west, away from both safe
  zones). Played headless: it spawned in both places, engaged and webbed the
  slime. Open: the owner tries it; its own art and sounds later.

- Build: add the Forest Orb-Weaver Slime to the roster: behavior, drops, spawn
  areas. Its sprite sheet is already registered in `asset/assets.json` but
  has no enemy type. Try it in the playground (3.7) before placing it.
- Player proof: Gloop Forest has a threat the Meadow did not.
- Done when: the user accepts it in the playground, `pnpm enemies:check`
  passes, and Gloop Forest has at least two orb-weaver spawn areas outside its
  safe zones.

### [x] 8.3 — An enemy-only material, verified 2026-09-30

- Built 2026-09-30: the **weaver fang** (`weaver-fang`, icon frame 0 of
  `sheet.items.chapter-2.5x2`, stacks to 99, drops as its own pile
  `collectible.weaver-fang`). Orb-weavers drop it 60 % of the time
  (`orb-weaver/character.json` and its scene); nothing else does. Since the
  2026-10-01 playtest enemy drops land on the ground and count as collected
  when picked up (4.11), so a quest can ask for "3 weaver fangs". Played headless on a fresh
  playground save: two orb-weaver kills gave two fangs (plus silk and a
  shard), and five fangs saved and reloaded as one stack of five.
- Build: the orb-weaver drops a material that the Reinforced Pickaxe (8.4)
  needs. Nothing else in the game drops it.
- Player proof: fighting has a purpose beyond coins.
- Done when: defeating orb-weavers on a fresh save yields the material at its
  configured rate, and it stacks, saves, and reloads with the right count.

### [x] 8.4 — Iron and the Reinforced Pickaxe, verified 2026-09-30

- Built 2026-09-30: `object.resource-iron-node` (Magnific art, 120 HP, tags
  `iron` first, two 5-ore piles, ore clink and shatter sounds) needs harvest
  tier 2 on `iron`. The **Reinforced Pickaxe** (`weapon.reinforced-pickaxe`,
  15 damage, harvests stone and iron at tier 2, icon frame 2; it swings the
  Stone Pickaxe art for now) is a workbench recipe: 10 wood, 15 stone, 3 weaver
  fangs. It is not quest-locked yet; quest Q2 (8.10) decides. Iron nodes stand
  in the playground grove and in Gloop Forest's south-east, the future iron
  hollow. The quest waypoint now finds a node by what its piles give
  (`iron-ore`), not by its tag. The dev panel gained "Learn all recipes".
  Played headless: the Stone Pickaxe showed "Requires a Reinforced Pickaxe" and
  dealt no damage; the Reinforced Pickaxe broke the node in five hits into
  two piles (10 ore); the workbench crafted it from the materials. Open: the
  node's rubble frame is unused (broken nodes vanish, as stone nodes do), and
  the pickaxe has no swing art of its own.
- Build: iron ore nodes in Gloop Forest that need the Reinforced Pickaxe
  (stone plus the enemy material, crafted at the workbench). The `iron-ore`
  item and its loose pile already exist.
- Player proof: the stone pickaxe fails clearly, the new one succeeds.
- Done when: hitting an iron node with the Stone Pickaxe shows the
  Reinforced Pickaxe hint and deals no damage; the Reinforced Pickaxe breaks it
  into `iron-ore`; the node respawns (5.5).

### [~] 8.5 — Restore the Forge

- Built 2026-09-30: `object.forge` (`objects/forge.scene.json`, the Workshop
  pattern) is an outdoor smelting furnace in the forge yard, between the home's
  door and the pond (the anvil and grindstone moved a little east). The red
  forge house stays the player's home: its door leads to the Slime Home, so it
  could not become the ruin the outline suggested. Until the `forge.restored`
  flag the furnace is a cold ruin (new Magnific art, `sheet.houses.forge.2x1`,
  packed by `scripts/houses/pack-forge.py`) with a restoration site (40
  stone, 20 wood, 6 iron ore) that only a player on the quest
  `rekindle-the-forge` (8.10) can use; anyone else reads "The Forge has gone
  cold…". Restored, it is a `forge` crafting station with Smelt Charcoal (5
  wood → 2 charcoal) and Smelt Iron Bar (2 ore + 1 charcoal → 1 bar), and its
  fire and anvil loops play (the anvil prop no longer clangs while the Forge is
  cold). New item `iron-bar` (icon frame 1, stacks to 99). Played headless
  with the flag set: 10 wood made 4 charcoal, 6 ore made 3 bars, and bars,
  charcoal and the flag survived a reload. The quest (Rekindle the Forge, Pip,
  8.10) was then played headless: the restoration paid 40 stone, 20 wood and 6
  ore through the site and the furnace lit. Open: the owner's acceptance on a
  fresh save.
- Planned 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "Crafting time"): smelting takes time. Charcoal and iron bars cook in the
  background with a progress bar on the Forge, and the slime claims them
  later ([Chapter 2](story/chapters/chapter-2-gloop-forest.md), Beat 5). Today
  both recipes are instant. Done when: a batch started at the Forge shows its
  progress, finishes while the slime is away, is claimed on return, and
  survives save and load; Rekindle the Forge counts the claimed charcoal and
  bars.
- Build: a second restoration using 6.1: a ruined Forge in Slimeshire and a
  Chapter 2 quest to rebuild it. The player uses the restored Forge directly to
  smelt iron ore and charcoal into iron bars; it never outputs weapons.
- Done when: bars are crafted, stacked, and saved correctly.

### [~] 8.6 — Metal gear

- Built 2026-09-30: the **Iron Spear** (`weapon.iron-spear`, 10 damage,
  800 ms; the Stone Spear's swing) and the **Iron Axe** (`weapon.iron-axe`,
  16 damage, fells trees at tier 2 and deals 60 % to enemies, where the Stone
  Axe deals none) are workbench recipes (10 wood + 4 bars, 10 wood + 3 bars),
  locked until a quest teaches them (`learnedByQuest`, Q3 and Q4 in 8.10).
  New weapon art (Magnific, `weapon.player.iron-tools-tiles`, packed by
  `scripts/weapons/pack-iron-tools.py`): the iron spear with a silver thrust
  trail, the iron axe, and a fang-bound Reinforced Pickaxe, which now swings
  its own art. Measured on the playground dummies: the Stone Spear hits for 9,
  the Iron Spear for 14, so an orb-weaver (70 HP) takes 5 hits instead of 8.
  Rekindle the Forge teaches the spear and Iron Gear the axe (8.10), both
  played headless. Open: the owner's acceptance on a fresh save.
- Planned 2026-10-02: the Iron Spear and Iron Axe are hammered at the
  workbench and end in the item ceremony (6.5).
- Build: craft an iron spear and an iron axe at the workbench from iron bars
  (the Workshop's second tier moved after Chapter 2 with the Workshop).
- Player proof: ore → Forge → bar → workbench → stronger weapon.
- Done when: the iron recipes stay locked until the quest teaches them, and
  the iron weapon defeats an orb-weaver in fewer hits than the Stone Spear.

### [~] 8.7 — The Chapter 2 boss

- Built 2026-10-01 to the spec
  [The Orb-Weaver Matron](design/2026-10-01-orb-weaver-matron.md):
  `encounter.gloop-matron-nest` in Gloop Forest's north-east (the north-east
  thicket moved west to keep its weavers out of her arena). `MatronScript`
  (`game.matron`) fights like an orb-weaver (web spit, 0.7 s wind-up) and every
  6.5 s stops for a **web volley**: four circles marked for 0.9 s, 20 damage
  inside them, then each becomes a web patch (`effect.matron-web-patch`,
  `game.web-patch`) that catches a normal slime and lets the Sticky form
  through; she rests 1.3 s after. 300 HP, immune to knockback, boss bar,
  arena leash (and a full heal after a minute alone outside it), a guarded
  chest (3 iron bars, 2 tonics), respawn after 5
  minutes, and a silk cocoon Gulp spot inside the arena. Quest 6, **The
  Matron's Nest** (Mossy, after Iron Gear), completes on her defeat: 100
  coins, Squash Slam (until 2026-10-08, when it moved to The One-Eyed
  Guardian) and `chapter-2-complete` (the end card); a Goo Heart then
  appears in the nest. Played headless: the circles showed for about a second
  before landing, the patches caught the normal slime and not the Sticky one,
  21 Iron Spear swings defeated her, and the quest, Squash Slam, the flag and
  the end card followed. Open: her own art and sounds (the orb-weaver sheet,
  2.6× and purple, and the spider's voice pitched down are placeholders),
  the owner's fight, and tuning (standing still in her
  volleys is deadly).
- Planned 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built),
  "The Weaver (Matron)", "Webs", "Hearts" and "Boss reset";
  [Chapter 2](story/chapters/chapter-2-gloop-forest.md), Beat 9):
  - New art (the boss sprite sheet in the Assets below).
  - Her normal attack becomes Stretch Lash in three directions, in place of
    the web spit. A hit deals damage, pulls the slime toward her and traps it,
    unless the slime is in the Silk form (7.5); then the hit pops the silk
    out instead.
  - Her volley webs follow the web rule (7.6).
  - A web door (7.6) closes her camp's only entrance (today a web-draped
    opening, 4.11).
  - Her Pearl (5.9) grants Stretch Lash after the fight (it leaves Beyond the
    Verdant Gate, 8.10). Squash Slam left her reward on 2026-10-08: Fatty One
    Eye's Pearl grants it.
  - Her bar hides while the slime is outside the arena (4.12).
  - Recheck her damage (18 to 30 a hit, tuned for 100–150 HP) against the
    heart-quarter totals (5.3,
    [unlock map](story/05-unlock-map.md#health-and-energy-totals)).
  - Open: whether she also gives a full heart (+20) on top of the map's
    quarters ([question 17](story/06-open-questions.md#progression)); today a
    +10 Goo Heart appears in the nest.
  - Update the [Matron spec](design/2026-10-01-orb-weaver-matron.md) first.
    Depends on: 5.9, 7.5, 7.6.
  - Done when: the user beats her in the Silk form with Chapter 2 gear (the
    Silk Armor until 2026-10-08); a lash hit pulls the slime, traps it only
    without the form, and pops the form when it has one; the web door lets
    only the Silk slime in; her Pearl grants Stretch Lash
    exactly once. This replaces the "heart is granted exactly once" check
    below.
- Build: one boss on the Fatty model: a telegraphed signature attack, boss
  bar, arena leash, guarded reward, and persisted defeat. Proposal: the
  **Orb-Weaver Matron** webs the arena, and Sticky form lets you cross her
  webs. She drops a Goo Heart and teaches Squash Slam. Write a short spec
  first.
- Done when: every attack has a telegraph of at least half a second; the
  user beats her with Chapter 2 gear; defeat, save/load, and leaving the arena
  reset or persist her as the spec says; the heart is granted exactly once
  (Squash Slam left her reward on 2026-10-08).

### [~] 8.8 — A second home in Gloop Forest

- Built 2026-10-01: the blue cottage in Gloop Forest's walled camp is the hut.
  A door (`hut-door`) leads to `world.gloop-hut`, a one-bed room in the
  Slime Home's plaster-and-beam style with the interior ambience, and back.
  Played headless: in, sleep (the respawn point became the hut's bed), out. The
  room was copied from the Slime Home's scene by a script, not furnished in
  Scene Studio; the steps, including the Studio route, are in
  [Adding an interior](archive/phaser/knowledge/adding-an-interior.md). Open: the Studio
  route is untried (no blocker found), and the room reuses the Slime Home's
  layout.
- Open since 2026-10-02: whether the hut gets a vault too, sharing the first
  vault's storage (5.8, [question 12](story/06-open-questions.md#progression)).
- Build: a hut exterior and furnished interior with a bed, so Chapter 2 has its
  own respawn point. Build the interior with Scene Studio as it is today (this
  replaces the old interior-authoring task 4.3); write the steps in a short
  note in `docs/knowledge/` and fix only real blockers.
- Done when: the hut's doors link both ways, sleeping in its bed sets the
  respawn point, and the room was built without hand-editing JSON (or the
  blockers are listed with their fixes).

### [~] 8.9 — Gulp puzzles and hearts in the world

- Built 2026-10-01 in Gloop Forest (playground pieces reused):
  - **Iron hollow** (Heavy), south-east of the camp: a walled pen around the
    three iron nodes and two ore piles; its gate opens while something heavy
    stands on the plate below it, with a stone Gulp spot beside the plate.
  - **Silk nook** (Sticky), north-west: a Goo Heart (`gloop-silk-nook`) behind
    a spider web, a silk cocoon Gulp spot outside.
  - **Cracked clearing** (Heavy), south-west of the camp: cracked ground with a
    stone Gulp spot; the sinkhole leads down to `world.gloop-cavern` (crystal
    walls, shards, a chest with iron ore and charcoal, the second Goo Heart
    `gloop-cavern`, the ladder back up).
  - **Sunny's stream** (Stretch Lash, quest 5): a moat against the north edge
    with her basket on the far side.
  - A third orb-weaver thicket south of the camp, a workbench and a campfire in
    the camp, and Mossy and Sunny there (both leave Slimeshire once Chapter 1
    is done).
  Played headless: the stone form opened the hollow's gate and the slime walked
  in; the silk form walked through the nook's web to its heart; the stone form's
  jump broke the cracked ground (a Heavy Squash Slam since 2026-10-08, 7.4),
  the sinkhole led down to the cavern's heart and
  the ladder back up; the lash pulled the basket across the moat while the bank
  stopped the slime. Open: no playtester has tried the puzzles without a hint.
- Planned 2026-10-02 ([Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built);
  [Chapter 2](story/chapters/chapter-2-gloop-forest.md), Beat 7 and Secrets):
  - Hearts: four heart quarters in Gloop Forest (5.3). Today's silk nook and
    cavern Goo Hearts become quarter spots. Open: whether the Gloop Cavern
    has its own four ([question 18](story/06-open-questions.md#progression)).
  - Bags: a coffer in the Gloop Cavern holds the 20-slot bag (5.7), with the
    ceremony.
  - Forms (since 2026-10-08): the iron hollow's plate and the cracked clearing
    need the Stone form, and the silk nook's web the Silk form (7.5, 7.6). The
    Gulp spots beside them become placed essences, which come back when the
    map is entered again.
  - Webs: choose the spider-camp webs in the orb-weaver thickets that trap
    (7.6).
  - Done when: each quarter is taken once and persists; the coffer's bag
    replaces the 10-slot bag once; each puzzle opens with its form and not
    without it.
- Build: at least three Gulp puzzles in Gloop Forest, each with its Gulp spot
  beside it, and at least two hidden Goo Hearts, one of them behind a puzzle.
- Done when: a playtester solves each puzzle without a hint, and each heart is
  collectable once and persists.

### [~] 8.10 — Build the Chapter 2 quests

- Built 2026-10-01 (`content/quests/quests/chapterTwo.ts`): **Beyond the
  Verdant Gate** (Mossy at the forest camp: defeat 3 orb-weavers; teaches the
  Stretch Lash and the Reinforced Pickaxe), **A Harder Pick** (Mossy: 3 weaver
  fangs, craft the pickaxe, mine 6 iron ore), **Rekindle the Forge** (Pip:
  restore the Forge, smelt 2 charcoal and 3 bars; teaches the Iron Spear),
  **Iron Gear** (Elder Plop: craft an Iron Spear; teaches the Iron Axe) and
  **Sunny's Basket** (optional, Sunny at the camp: pull her basket across the
  stream). Red Slime Boy is now Pip and the Yellow-Blond Slime Girl is Sunny
  (`NpcDefinitions.ts`). Played headless on a post-Chapter-1 state, quest by
  quest, with real kills, crafting at the camp workbench and the Forge, the
  Heavy plate gate, mining, the Forge restoration and the lash; Forge, quests
  and recipes survived a reload. Also fixed: an NPC that a story variant takes
  out of the world no longer breaks the quest waypoint or its name tag. Open:
  the Matron quest (with 8.7), the end card (8.11), and a full fresh-save run.
- Planned 2026-10-02 ([Chapter 2](story/chapters/chapter-2-gloop-forest.md)):
  - Beyond the Verdant Gate no longer teaches Stretch Lash; the Matron's Pearl
    does (5.9, 8.7). Sunny's Basket, which needs the lash, moves after The
    Matron's Nest.
  - Since 2026-10-08: Tom's rescue teaches Swallow before A Harder Pick
    sends the slime into the iron hollow (8.13), and Clod Stompers near the
    hollow drop the stone essence (8.12). Spiders drop silk. Built 2026-10-09:
    Tom in the Web comes between Beyond the Verdant Gate and A Harder Pick,
    and Clod Stompers camp by the hollow and the cracked clearing.
  - Rekindle the Forge smelts on the Forge's timer (8.5), and Iron Gear's
    spear is hammered (6.5).
  - Done when: the "Stretch Lash is granted exactly once" check below holds
    for the Matron's Pearl instead of a quest.
- Build: turn the 8.1 stubs into full quests in `chapterTwo.ts`, alongside
  8.2–8.9: givers (existing NPC sheets unless the outline asks for new art),
  dialogue, objectives, rewards, the Stretch Lash grant, a chapter banner, and
  the `chapter-2-complete` flag. The Forge restoration quest (8.5) is one of
  them.
- Player proof: Chapter 2 is guided step by step, the way Chapter 1 is.
- Done when: `pnpm quests:check` and `pnpm test:quests` pass; on a fresh save
  every quest can be accepted and completed in order without debug grants;
  and Stretch Lash is granted exactly once and survives save/load.

### [~] 8.11 — Close the chapter

- Built 2026-10-01: Gloop Forest's east exit to the Crystal Caverns is locked
  by a crystal key that Release 1 never gives (`crystal-key`, "The way into
  the Crystal Caverns is sealed with crystal. (Chapter 3)"), and the
  `chapter-2-complete` flag shows an **End of Chapter 2** card
  (`content/story/endCards.ts`). Played headless: defeating the Matron set the
  flag and opened the card. Open: a fresh run from the title to the card.
- Build: the exit to Crystal Caverns stays locked with a "Chapter 3" hint, and
  finishing Chapter 2 sets the flag that shows the end card (4.7).
- Done when: a fresh run reaches the end card without debug grants.

### [~] 8.12 — The Clod Stomper drops the stone essence

- Built 2026-10-09, waiting for the owner: `character.clod-stomper`
  (`game/scripts/clod_stomper.gd`, on the enemy script), a camp enemy with
  90 HP, aggro range 230, speed 70 and knockback resist 0.8.
  - In reach (70 px) it never swings: it crouches 700 ms behind a ring
    telegraph (an ellipse 168×100 at its feet), hops 30 px for 340 ms and
    slams. A slime in the ring takes 26 damage and 300 knockback; the screen
    shakes, the ground cracks, and cracked ground within 90 px of its feet
    (`crack_radius`, plus the cracked ground's own radius) breaks. Then it is dazed 700 ms (the time to hit it) and
    stomps again 1400 ms later. Hits never break a stomp; a rolling slime's
    i-frames dodge it.
  - It drops a stone essence every time (`gulp.essenceDrops`), and 10 coins.
  - Placed: the playground's enemy pen; Gloop Forest camps
    `gloop-clod-stompers-hollow` (2560, 3160), south of the iron hollow's
    plate, and `gloop-clod-stompers-clearing` (1700, 2370), east of the
    cracked clearing. That camp keeps it about 260 px from the cracked ground,
    so it breaks the ground only for a slime that lures it over.
  - Art: `godot/asset/MAPS/enemies/256x256-tile_5x1-clod-stomper.webp`
    (idle, crouch, air, slam, defeated) from Magnific GPT 2.5 stills in
    `asset/Originals/enemies/clod-stomper/`, packed by
    `scripts/characters/pack-clod-stomper.py`. Tests: `test_clod_stomper.gd`.
- Decided 2026-10-08 ([the 2026-10-08 decisions](#the-2026-10-08-decisions)).
  It replaces "Earn the Stone Armor"; the armors were dropped.
- **The Clod Stomper** is a squat golem of mud and pebbles, a small Fatty One
  Eye. It jumps in place and slams the ground behind a ring telegraph, and its
  slam cracks weak ground near it. The player sees the enemy do what a stone
  essence plus Squash Slam will let them do. Beaten, it drops a stone essence.
- The slime meets it before A Harder Pick sends it into the iron hollow
  ([Chapter 2](story/chapters/chapter-2-gloop-forest.md), Beat 4), and after
  Tom has taught Swallow (8.13).
- Today: the Clod Stomper is built (above). Its slam plays its own
  `StomperSlam` (Mud stomp, Sound Picker round 5, 2026-10-09) instead of
  SlamImpact. Not done: the owner's acceptance, and its other sounds (it
  reuses SlamWindup, Jump, hit-dull and stone-crumble).
- Build: the enemy (scene, AI on the enemy model, art), its stone essence drop,
  and its camps near the iron hollow and the cracked clearing. It is tried in
  the playground first.
- Depends on: 7.5.
- Done when: in the playground and in Gloop Forest the Clod Stomper
  telegraphs, slams and drops its essence; a slime that swallows the essence
  opens the iron hollow's plate; the owner accepts it.

### [~] 8.13 — Tom in the web: learning Swallow

- Built 2026-10-09, waiting for the owner: the quest **Tom in the Web**
  (`tom-in-the-web`, in `quests-chapter-2.json`). Mossy gives it after Beyond
  the Verdant Gate; its one stage asks to "Cut Tom out of the web"; Tom takes
  the turn-in and gives 20 coins and Swallow. A Harder Pick now requires it.
  - **Tom** (`tom` in `npc-definitions.json`, `character.tom`, idles in
    place): a round blue jelly slime with a moss-green scarf and a small bottle
    of glowing essence (`godot/asset/characters/authored/npcs/tom.webp`). The
    prompt asked for amber-orange; the blue was kept because it reads well and
    differs from the other NPCs.
  - **The web** (`object.tom-web`, `game/scripts/tom_web.gd`) hangs in Gloop
    Forest's south-west spider thicket at (860, 2470). Three weapon hits tear
    it; thrown things and abilities only shake it; it tears only while the
    quest is active (before that, Tom mumbles). Torn, it sets `tom-freed` and
    Tom calls "I'm free! Thank you! Meet me at Mossy's camp!". Story variants
    then show the torn web and Tom by the camp fire (`camp/tom-at-camp`). The
    quest arrow finds the web.
  - Art: `godot/asset/MAPS/props/256x256-tile_2x1-tom-web.webp` (Tom in the
    cocoon, the torn web); sources in `asset/Originals/characters/tom/`,
    packed by `scripts/characters/pack-tom.py`. Tests: `test_tom.gd`.
- Decided 2026-10-08 ([the 2026-10-08 decisions](#the-2026-10-08-decisions)).
  It replaces "Earn the Silk Armor"; the armors were dropped.
- The story:
  - Mossy asks the slime to rescue **Tom**, a new NPC.
  - Tom already knew how to swallow. He went to a spider thicket in Gloop
    Forest to swallow silk and got caught in its web.
  - The slime frees him by hitting the web around him with a weapon. It cannot
    swallow yet, and a path web would trap it.
  - Back at Mossy's forest camp, Tom teaches **Swallow** with the full
    ceremony.
  - The owner may add more to this story later.
- Spiders drop silk essences (7.5), so silk is no longer a hard-to-get key
  item. Swallow is Chapter 2's key item: the Matron and the web secrets need
  the forms it opens.
- Today: Tom teaches Swallow (built 2026-10-09, above), and learning it plays
  the ability ceremony (4.13, built later the same day). Beyond the Verdant
  Gate no longer teaches it (it was a stand-in). Not done: the owner's
  acceptance; the owner may add more story later.
- Build:
  - Tom: NPC art, and dialogue in `quests-chapter-2.json`.
  - Mossy's quest, after Beyond the Verdant Gate and before A Harder Pick.
  - Tom's web, which weapon hits tear.
  - The Swallow lesson at the camp.
- Open: the Weaver Hollow proposal (Beat 8) no longer earns an armor. Keep it
  as a small dungeon, or drop it.
- Depends on: 7.5 and 4.13.
- Done when: on a fresh save Mossy's quest leads to Tom; the web tears under
  weapon hits; Tom teaches Swallow at the camp, with the ceremony, before A
  Harder Pick; Swallow survives save and load.

**Milestone 8 complete when:** Chapter 2 plays from the Verdant Gate to the end
card, and the gear path wood → stone → iron is complete. Since 2026-10-08 Tom
teaches Swallow and the Clod Stomper drops stone on the way (8.12, 8.13).

**Assets**

- Reuse: `64x64-8x10-forest-orb-weaver-slime.webp`, `collectible-iron-ore-pile`, `collectible-charcoal-pile`,
  `rock-amber-ore-mineable` (as a style reference), the interior catalog.
- [x] Iron ore node (intact and depleted; the depleted frame is not shown yet).
- [x] Icons: enemy material, iron bar, Reinforced Pickaxe, iron weapons.
- [x] Weapon art for the iron spear and iron axe (and the Reinforced
      Pickaxe), drawn like the stone weapons so they reuse their swings.
- [x] Ruined Forge exterior.
- [ ] Boss sprite sheet, web projectile and web-ground effects, and arena
      dressing (placeholders today: the orb-weaver sheet scaled and tinted,
      the web-cover effect as the ground web, no dressing).
- [ ] The Matron's lash in three directions (8.7); the Stretch Lash tendril
      art is the starting point.
- [ ] The web door (8.7) and the cavern coffer for the 20-slot bag (8.9).
- [~] The Clod Stomper's sprite sheet (8.12):
      `godot/asset/MAPS/enemies/256x256-tile_5x1-clod-stomper.webp` (idle,
      crouch, air, slam, defeated); accepted by the owner 2026-10-09 ("the art is fine"). Its slam has its own
      sound since 2026-10-09 (`StomperSlam`, Sound Picker round 5, owner to
      pick); the rest are reused (SlamWindup, Jump, hit-dull and
      stone-crumble).
- [~] Tom's NPC sheet and the web around him (8.13):
      `godot/asset/characters/authored/npcs/tom.webp` and
      `godot/asset/MAPS/props/256x256-tile_2x1-tom-web.webp`; accepted by the owner 2026-10-09.
- [x] Gloop Forest hut exterior (the blue cottage already in the camp).
- [x] Gloop Forest music and ambience (Magnific, `audio.music.gloop-forest*`);
      Forge fire and anvil loops (the campfire and anvil loops, on the
      restored Forge).

## 9. Game Feel

A slime's feel is mostly hit-stop, screen shake, and squash and stretch. Every
effect respects the reduce-motion setting (4.5).

### [x] 9.1 — Hit-stop and screen shake, verified 2026-09-30

- 2026-09-30 (owner could not see hit-stop or the dodge dust): hit-stop now
  freezes Arcade physics, tweens and sprite animation too, not only the scene
  runtime, so the slime and knocked-back enemies really stop. It lasts about
  four frames on a light hit (65 ms) and five to ten on heavy hits and
  defeats. The dodge dust is a puff of sandy cloud instead of faint goo dots.
  The playground panel's hit-stop buttons hold the stop five times longer so
  it can be seen; hitting a training dummy shows the real one.

- Done: `features/feel/GameFeel.ts` holds named presets (hit, critical hit,
  combo finisher, player hurt, slam, boss landing, boss and player defeat,
  ground crack, restoration), and every camera shake in the game now goes
  through it (`gameFeel` in `features/feel/sharedFeel.ts`), so the Screen
  shake slider finally scales them (before, the slider changed nothing).
  Hit-stop holds the simulation still (the world advances by zero) while
  rendering and the shake carry on; overlapping stops never add up; burn and
  poison ticks never stop the game. Reduce motion turns both off. Measured
  in the running game: a boss defeat froze the simulation for about 135 ms,
  none with reduce motion. `pnpm test:feel` covers presets, scaling and
  reduce motion.

- Build: named presets per event (light hit, heavy hit, boss slam, defeat).
- Done when: each preset fires on its event, the screen-shake setting (4.5)
  scales or disables shake, and reduce motion turns both off.

### [x] 9.2 — Squash and stretch, verified 2026-09-30

- Done: `features/feel/SquashStretch.ts` snaps the slime's body to a preset
  shape and springs it back through the sprite's effect channel: a lean on
  move start (only after standing still, not on every tap), the jump's
  take-off stretch, a landing splat, a flattening when hit, and a wobbling
  bulge on Gulp. A new event replaces the one playing, the body always ends
  at rest, and abilities that animate the body are left alone. Reduce motion
  keeps a third of each shape. Read live in the playground: move start
  0.93 × 1.08, jump 0.85 × 1.29, landing 1.13 × 0.78, all back to 1 × 1.
  `pnpm test:feel` covers the five events, replacement and reduce motion.

- Build: event-driven squash and stretch on move start, jump, land, hit, and
  Gulp.
- Done when: each of the five events plays its deformation, the slime always
  returns to its rest shape, and reduce motion softens it.

### [~] 9.3 — Particle presets

- Built 2026-09-30: `features/feel/ParticlePresets.ts` keeps one emitter per
  preset for the world scene and reuses it for every burst: hit sparks when a
  weapon lands on a creature, a goo splash when the slime is hit, dodge dust
  (it used to make and destroy an emitter per dodge), a sparkle on every
  pickup, and a burst where a boss is defeated. The textures are procedural
  (`fx-spark`, `fx-goo-drop`, `fx-sparkle`). Headless: all five fire, and 200
  bursts plus a dodge leave the emitter count at 5. `pnpm test:feel` covers
  the pool. Open: the 60 fps check of a 20-enemy fight on a real machine
  (headless runs on a software renderer), and particle art (assets below).

- Build: pooled hit sparks, slime splash, dodge dust, loot sparkle, and boss
  defeat bursts.
- Done when: each preset plays on its event, particles come from a pool (no
  per-hit allocations), and a 20-enemy fight in the playground holds 60 fps.

### [~] 9.4 — Slime trail

- Built 2026-09-30: `features/feel/SlimeTrail.ts` drops a translucent goo mark
  every 30 px the slime moves on the ground (none mid-jump), from a pool of 28
  images reused oldest first; each fades over 5 s. Every 100 ms, ordinary
  enemies within 26 px of a mark younger than 2.5 s get the `slow` status's
  multiplier (0.55) for 0.4 s through the new `EnemyScript.applySlow`; bosses
  are not slowed. Measured in the playground: a chasing worm brawler went
  from 50 to 28 px/s on fresh goo. `pnpm test:feel` covers the pool, the fade
  and freshness.
- 2026-09-30 (owner: since it slows enemies, it should be an ability a later
  quest teaches, when a mission needs it): the trail is now the passive
  **Goo Trail** ability (`content/abilities.ts` passive abilities, no key or
  bar slot). Until a quest reward teaches `goo-trail` the slime leaves no
  goo; learning it shows "Goo Trail learned". No quest teaches it yet; pick
  the chapter and mission when one benefits from slowing enemies. In dev
  builds the playground panel's checkboxes teach any ability, the Goo Trail
  included.

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

### [~] 10.1 — Download size

- 2026-09-30 (owner: remove unused backplates; make the grounds lighter
  without losing much quality):
  - Removed the two images nothing used (`ui-organic-modal-frame`,
    `ui-crafting-workbench-backplate`, 4.9 MB).
  - The eleven ground sheets are lossless WebP now (identical pixels, checked
    pixel by pixel): 25.4 MB to 13.6 MB. `grounds:pack` writes WebP;
    `assets:check` reads WebP sizes and finds WebP orphans.
  - Sound: one flavour per cue (3.8), 7.5 MB to 5.6 MB.
  - Production-only worlds (10.2): the main script went from 5.4 MB to 4.5 MB.
- Next, measured: lossless WebP for the other 43 images over 300 KB (UI
  backplates, character and prop sheets) would save about 15 MB more with no
  quality change; lossy WebP (quality 95) would save much more with slight
  noise, so it needs the owner's eye first. Then lazy area loading and a
  loading bar.
- 2026-09-30 (owner: lossy WebP is fine, but transparency must stay exact):
  every mapped image is WebP now. The 87 PNGs went from 62.4 MB to 14.8 MB:
  79 lossy (quality 90) and 8 small outlined icon sheets (items, weapon
  icons, arrows) lossless, because lossy colour visibly shifted them at close
  zoom (below 26 dB on visible pixels). Transparency is stored lossless and
  checked identical on every file; Phaser premultiplies alpha on upload, so
  colour under fully transparent pixels never shows. Side-by-side crops of
  the NPC, furniture and tree sheets showed no visible difference.
  `scripts/lib/game_webp.py` holds the rule; every pack script saves through
  it, and `scripts/assets/convert-png-to-webp.py` converts hand-exported PNGs.
- 2026-09-30 (owner: load each area only when it is entered, with a loading
  bar): boot loads only the images that can appear anywhere (6.8 MB: the
  player, weapons, effects, item icons, UI) plus sound; each world's own
  images load when the player enters it (`pnpm assets:worlds` writes the
  per-world lists from the scene graphs into
  `worldAssetSets.generated.json`; `assets:check` fails when they are stale;
  anything not listed loads at boot). A plain HTML loader covers the code
  download, then a loading bar shows boot and each world's load. Measured
  headless: the slime home downloads 8.6 MB of images, Gloop Forest about
  15 MB and Slimeshire (the title backdrop) 22 MB, against 31 MB for every
  page before. Every area change reloads the page, so nothing needs
  unloading; the browser cache serves repeat visits.
  The Vite asset glob now mirrors every manifest `ignore` pattern, so the two
  unused PNGs no longer ship. `pnpm build`: `dist/` went from 89 MB to 43 MB.

- 2026-10-05 (Godot): the web export is one data pack (46.6 MB, textures
  imported as lossy WebP) plus the engine (about 9 MB compressed). It loads the
  whole pack at start; the Phaser build's per-area loading was not ported.
- Build (Phaser, before the cutover): `dist/` was 70 MB: a 5.4 MB main script and UI backplates of
  2–5 MB each. Compress and resize images to their display size, load area art
  when the area loads, and show a loading bar.
- Done when: the first load is under about 25 MB and a cold start on a normal
  connection shows the title within a few seconds.

### [x] 10.2 — Production-only content, verified 2026-09-30

- Done: the twelve maps below joined `devOnlyWorlds.ts`, so a production
  build bundles only the five reachable world scenes (about 8 MB of world
  JSON left out). `?map=`, the debug hotkeys and Development Tools were
  already dev-only, and the development arsenal grant has no caller. Checked
  by running the scene plugin in build mode (`pnpm test:scene-content`) and a
  real `pnpm build`: the main script went from 5.4 MB to 4.5 MB, and the
  bundle holds only the five reachable world scenes.

- Build: ship only reachable worlds (`level-1`, `slime-home`, `mushroom-home`,
  `gloop-forest`, `crystal-caverns`, and the 8.8 hut). Add these to the
  dev-only world list from 3.7, next to `playground`: `174`, `236`, `cole`,
  `girls`, `jk`, `tiktok`, `test-rectangle`, `depth-occlusion-test`,
  `meadow-crossing`, `icege`, `emberleef`, and `hot`.
  Disable `?map=`, the dev item grant, debug hotkeys, and Development Tools in
  production.
- Done when: a production build contains none of them.

### [~] 10.3 — Licenses and credits

- 2026-09-30: [Credits and licenses](CREDITS.md) lists every shipped
  library, sound and image family with its source, license and evidence
  (C2PA metadata on the generated sources), and what the credits screen must
  show. The credits screen names the generated sound effects and the
  shipped libraries, and says the art was made by the team with AI image
  tools (the owner made the older art without a recorded source with AI).
  Open: the AI terms of use are checked, and the MIT notices ship with the
  build.

- Build: record the source and license of every image, sound, and font in the
  production build.
- Done when: every asset may be redistributed and appears in the credits (4.7).

### [ ] 10.4 — Browsers and performance (absorbs R.1)

- Build: test Chrome, Edge, Firefox, and Safari; hold 60 fps on the reference
  laptop (a mid-range laptop with integrated graphics; record its model here
  the first time this task runs) in Level 1 and Gloop Forest; close the
  [motion rendering](archive/phaser/task/bugs/world-motion-rendering-instability.md) work or
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
- Done when: `pnpm test:godot` passes on the tagged commit, the store page is
  public, and the published build (the Godot "Web" export) runs in a fresh browser.

## After Release 1 — Idea Parking Lot

Everything here waits until Release 1 ships. When one is picked up, it gets a
numbered milestone and task tiles.

### First update candidates

- **The Workshop** (moved out of Chapter 1 on 2026-09-30): an upgrade of the
  workbench once the Forge makes iron bars, after Chapter 2. Its art, story
  variant, restoration site, quest (The Old Workshop) and first recipe (the
  Slam Hammer) are built and waiting; the restoration cost should take iron
  bars then, and its second tier brings the heavier gear.

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
  (berry), and later biome forms such as ice and lava. Since 2026-10-08 each
  comes from an essence (7.5), dropped by an enemy designed around it.

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
- More enemies from [Future Enemy Types](task/ideas/open/future-enemy-types.md);
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
  [Player action dashboard and loadout](task/ideas/open/player-action-dashboard-and-loadout.md).
- Gamepad support, key rebinding, colorblind-safe status colors, text size,
  photo mode. For rebinding, the 4.10 binding table is already the data; only
  the settings screen is missing.
- An Android export of the Godot project (the old `MobileVersion/` prototype
  was removed on 2026-10-04).

### Tooling (frozen)

- Shared world graph and all-map organizer (was E.1):
  [Shared world map and Map Studio graph](task/ideas/open/global-map-and-map-joining.md).
- Remaining shared gameplay defaults (was C.5).
- Custom editor tooling beyond the Godot editor (Scene Studio was retired with the Phaser app).

### Dropped

- `[—]` Moving the home: the home stays in Slimeshire; other maps get their
  own homes.
- `[—]` A single authored home instance with ownership (was 3.1, 3.2).
- `[—]` The Alchemy table: potions belong to the Kitchen, bombs to the
  Workshop.
- `[—]` XP, levels, and perks: replaced by gear-based progression (Milestone 5).
- `[—]` Weapon dropping and pickup (was UX.3), removed 2026-10-02: weapons go
  into the vault instead (5.8,
  [Direction](story/01-direction.md#decisions-of-2026-10-02-planned-not-built)).

## Immediate Next Sprint

Milestones 3 to 7 and 9 are built and played headless (2026-09-30); each waits
on its assets and the owner's acceptance. Waiting on the owner:

- 4.9: play the second round of fixes (tearing webs, the Heavy cracked ground
  (a Squash Slam since 2026-10-08), enemy territories), then a second new
  player.
- 7: try the Heavy plate gate, the Sticky web nook, the hold-W quick wheel and
  the cracked-ground cavern in the playground (`?map=playground`); accept the
  new plate and form-badge art.
- Owner's feedback 2026-09-30 (round 5), done:
  - **Quest tracker, WoW style:** the card under the HUD lists up to four
    quests at once, main story first (gold), then side quests, each with its
    objectives; clicking a quest points the gold arrow at it, and more quests
    are counted "+N in the book" (`QuestTrackerSurfacePort`,
    `ui/quest-tracker.scene.json`).
  - **The Workshop moved after Chapter 2** (see 6): The Old Workshop waits for
    `chapter-2-complete`; Chapter 2 crafts at the workbench.
  - **Gulp forms have their own sprites:** Heavy draws the slime as a mosaic of
    grey pebbles, Sticky as a slime wrapped in silk, every frame of the player
    sheet re-textured (`slime-form-heavy`, `slime-form-sticky`, built by
    `scripts/characters/build-gulp-form-skins.py`); the face and outline stay,
    and the form's tint is only a fallback.
- Owner's playtest fixes 2026-09-30: Jump from standing still hops in place
  (a moving jump still follows the movement); Teleport lands on the farthest
  safe spot in reach, across rivers and thin walls, and says "No safe spot
  there" when there is none (costing nothing); a tap of W away from a Gulp
  spot no longer eats carried stone (hold W for the quick wheel); the dev
  panel only reacts to the mouse, so Space no longer unticks Jump.
- Playground (dev builds): the dev tools panel has a **Playground** section:
  checkboxes that teach or forget each ability (Jump, Squash Slam, Stretch
  Lash, Teleport, Goo Trail) and buttons that play each game-feel effect on
  the slime (hit-stop, shakes, squash shapes, every particle preset). Three
  straw **training dummies** stand east of the spawn (`object.training-dummy`,
  `game.training-dummy`): they take any weapon or ability hit, show the
  damage and wobble, and never fight back.
- 8.1: try the Stretch Lash hook in the playground's lash yard (the
  outline's questions are all answered).
- 8.2: fight the orb-weavers in the playground pen and in Gloop Forest.
- 9: play the new feel (hit-stop, squash and stretch, particles) on the
  playground's training dummies and with the panel's game-feel buttons. The
  goo trail is now a learned ability (9.4) that no quest teaches yet.

Next (2026-10-07): the owner approves the
[HUD console mockup](design/2026-10-07-hud-console-mockup.md), the first step
of the bottom console (4.12) and of the
[2026-10-02 decisions](#the-2026-10-02-decisions); the order of the other
decision tasks is not set. Art keeps coming from Magnific (GPT-2) as each task
needs it. (The next step named here before, 8.3–8.6, was built on 2026-09-30.)

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
- Plans: [Stone and starter tools](archive/phaser/superpowers/plans/2026-08-23-stone-and-starter-tools-implementation-plan.md),
  [Walk-over collectibles](archive/phaser/superpowers/plans/2026-08-24-walk-over-collectibles-and-editor-attributes-implementation-plan.md),
  [Fatty One Eye design](archive/phaser/superpowers/specs/2026-09-11-fatty-one-eye-guarded-chest-design.md),
  [verification checklist](archive/phaser/task/ideas/completed/level-1-milestone-2-verification-checklist.md).

### [x] Q — Chapter 1 — The Clearing

`src/game/content/quests/quests/chapterOne.ts`: Village Elder Plop, Mossy,
Lili, and Lily the Fishergirl give six quests (`a-place-to-work`,
`stone-tools`, `worm-trouble`, `the-one-eyed-guardian`, `a-tonic-for-lili`,
`snack-for-the-road`) with dialogue, a chapter banner, quest-taught recipes, and
the `chapter-1-complete` flag. Slimeshire Meadow (`level-1`, built by
`scripts/maps/build-level-1.mjs`) holds the town, river and lake, Fatty's hedge
maze, the worm ruins, the Webwood, and the Verdant Gate. See the
[Quest authoring guide](archive/phaser/knowledge/quest-authoring-guide.md).

### [x] P — Save, load, and reset (P.1–P.5), verified 2026-09-28

Immutable initial run state, map-keyed progress, independent named saves with
explicit overwrite, a recovery autosave, save schema v9 with migrations, and
Save/Load/Reset controls. Plan:
[Named save, load, and reset](archive/phaser/superpowers/plans/2026-08-24-named-save-load-reset-implementation-plan.md).

### [x] S — Universal scene architecture (S.1–S.5)

Worlds, UI, and audio are authored scenes; behavior lives in ScriptNodes;
Scene Studio (`?studio=scenes`) is the only editor; `pnpm check` and 43
browser cases pass. Design:
[universal scene architecture](archive/phaser/superpowers/specs/2026-09-12-godot-inspired-universal-scene-node-architecture-design.md);
evidence: [final report](archive/phaser/superpowers/plans/evidence/universal-scene-final-report.md).

### [x] Audio foundation (A.0–A.3)

Audio loads from `asset/assets.json`; audio nodes support variants, pitch
randomness, polyphony, and buses; every P1 cue exists; `pnpm audio:wire` and
`audio:check` keep scene wiring in sync. Plan:
[Audio & SFX](archive/phaser/superpowers/plans/2026-09-28-audio-sfx-implementation-plan.md).

### [x] Other finished cross-cutting work

- **C.1–C.4 — Central gameplay configuration:** `game-constants.json` with a
  strict schema and a frozen runtime gateway
  ([plan](archive/phaser/superpowers/plans/2026-08-26-central-game-constants-implementation-plan.md)).
  Edit the JSON directly and run `pnpm constants:check`.
- **UX.0 — Escape closes the topmost surface** through the shared `ModalStack`
  ([design](archive/phaser/superpowers/specs/2026-08-26-escape-closes-overlays-design.md)).
- **E.2 — Terrain is ground; walls are placed objects:** crystal clusters and
  forest trees are object scenes, and water collision is merged.

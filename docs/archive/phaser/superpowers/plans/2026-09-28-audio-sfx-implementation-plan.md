# Audio & SFX Implementation Plan

**Date:** 2026-09-28
**Goal:** Add sound effects, ambience and music to Slime Isa by building sound assets, authoring them as
`AudioStreamPlayer` / `AudioStreamPlayer2D` nodes in scene JSON, and triggering them from existing signals and
`gameEvents`.

**Sourcing decision:** A/B comparison. Every P1 sound ships in two flavours that share the same cue ID:
- `synth`: generated deterministically by our own bake tool (`pnpm audio:bake`).
- `library`: CC0 samples from Kenney's packs (credited in `asset/audio/CREDITS.md`).

A dev toggle (`?sfx=synth|library`, default `synth`) picks the flavour at boot. After comparing, the losing flavour
is deleted per category (or globally).

> 2026-09-30: the flavours were picked per cue (`scripts/audio/picks.json`) and the `?sfx` toggle was removed; see
> [GAME_ROADMAP 3.8](../../../../GAME_ROADMAP.md).

## Status (2026-09-28)
- **Done:**
  - Phases 0–3 for the P1 set and most P2 cues. 183 takes in total; 180 have CC0 library takes, and library is the shipping default. `?sfx=synth` switches to the synthesized takes.
  - 107 scenes are wired, and the global event bridge is live.
  - Phase 4 sound settings: Settings (pause menu or title) has Master / Effects / Music sliders plus Mute and Defaults. Changes apply live and persist per device through `GameSettingsService` (roadmap 4.5).
  - New `Slider` control node. Mouse drag and click work because the input router keeps the browser default for pointer presses on native form fields.
  - Level 1 world music: Juhani Junkala's "Home Town" (CC0). A looping `MusicPlayer` node on the music bus sits in `worlds/level-1.scene.json`.
  - 2026-09-29: synth placeholder loops for the campfire, cauldron, grindstone and anvil (positional, ambience bus) and ambience beds for Level 1 and both interiors; the synth renders seamless loops (`loop: { seconds, crossfade }`). `features/audio/MusicDirector.ts` fades world music in, ducks it under pause menus, crossfades to `Music/BossMusic` during boss fights, and fades out before map changes; crits play `weapon/crit`.
- **Open:**
  - Footstep wiring.
  - Low-hp heartbeat, burn loop, gloop-forest and other biome ambience; final recordings for the placeholder loops.
  - Music for the other worlds and a real boss track (`BossMusic` currently pitches up the town theme). The CC0 candidates are the rest of Juhani Junkala's JRPG packs and his Epic Boss Battle track.
  - Crafting-failure cue.
  - Library takes for burn, Fatty's fall whistle and the area transition.
- **Tooling:**
  - `pnpm audio:bake -- --library <packs>` renders the cues and syncs the manifest.
  - `pnpm audio:wire` / `pnpm audio:check` place and verify scene nodes.

---

## 1. Current state

**Already exists**
- `AudioStreamPlayerNode` and `AudioStreamPlayer2DNode` (`src/game/infrastructure/phaser-nodes/`):
  - Buses `effects` and `music`, with per-bus volume and mute (`GlobalAudioServices`).
  - Playback waits until the browser unlocks audio.
  - The 2D node applies linear falloff and pan relative to the camera centre.
- Scene property descriptors for both node types (`stream`, `bus`, `volume`, `pitch`, `loop`, `autoplay`,
  `maxDistance`, `panDistance`), plus scene resources of kind `audio`.
- Scene `connections` (`source.signal -> target.handler`), so a scene can call `SfxNode.play` from any signal.
- The `audio.global` scene (`content/scenes/authored/audio/global.scene.json`) is mounted by
  `UniversalSceneWorldController`. It contains empty `Music` and `Effects` groups.

**Gaps**
1. There are no audio files, and no audio entries in `asset/assets.json`.
2. `AssetLoader.loadAssetBundle` ignores `kind: audio`, and `assertAssetBundleTextures` would reject audio entries.
3. The nodes play a single instance, so rapid hits cut each other off.
4. The nodes have no variation (no pitch jitter, no random pick between variants).
5. A sound dies when its owning node is freed (pickups, deaths).
6. No bridge exists from `gameEvents` (`player.damage`, `level.up`, `quest.completed`, ...) to sounds.
7. There is no volume or mute UI, and no persistence for it.
8. ffmpeg is not installed. The synth therefore writes 16-bit mono WAV at 22.05 kHz (small for short SFX).
   Kenney packs already ship `.ogg`.

## 2. Phases

### Phase 0: Loadable audio
- `asset/assets.json` uses `source.kind: "audio"`. `runtime.textureKey` is reused as the Phaser *cache key*;
  schema text is updated to say "Phaser cache key" rather than "texture key".
- `AssetLoader.loadAssetBundle` calls `scene.load.audio(key, url)` for audio entries.
- `assertAssetBundleTextures` checks audio keys through `scene.cache.audio` instead of textures.
- A new `audio` bundle holds all audio entries and loads at boot.
- `assets:check` validates that audio files exist and have an accepted extension (`.wav`, `.ogg`, `.mp3`, `.m4a`).
- Asset ID convention: `audio.sfx.<flavour>.<category>.<cue>[.<n>]`, `audio.music.<id>`, `audio.ambience.<id>`.

### Phase 1: Node upgrades (`AudioPlaybackController`)
| Property | Purpose |
|---|---|
| `variants: resource[]` | Pick randomly on each play. Avoids repetition. |
| `pitchRandomness` | Random pitch offset of ± this amount on each play. |
| `polyphony` (default 4) | Overlapping one-shots instead of restarting one. |
| `minInterval` ms | Throttles duplicate triggers in the same frame. |
| `detached` (2D) | Lets a one-shot keep playing after its node is freed. |

- Add an `ambience` bus.
- One-shots create fresh Phaser sound instances. Looping players keep the current single-instance model.

### Phase 2: Sound creation
- **Synth:** `scripts/audio/sfx-bake.mjs` plus `scripts/audio/recipes/*.json`.
  - Recipes are built from oscillators (sine, square, saw, triangle), white and brown noise, ADSR envelopes,
    pitch slides, one-pole low-pass and high-pass filters, bit-crush, and layered voices.
  - Output goes to `asset/audio/sfx/synth/<category>/<cue>.wav`.
  - The seed is fixed, so output is deterministic.
  - New script: `pnpm audio:bake`.
- **Library:** Kenney CC0 packs ("RPG Audio", "Impact Sounds", "Interface Sounds").
  - Chosen samples are copied to `asset/audio/sfx/library/<category>/<cue>.ogg`.
  - The source file names are recorded in `asset/audio/CREDITS.md`.
  - Downloading these packs requires the user's OK.
- **Music and ambience:** CC0 packs later. Synth placeholder loops for now.

### Phase 3: Wiring (nodes in scenes)
| Location | Mechanism |
|---|---|
| Effect scenes (`effects/*-impact`, `boss-ground-crack`, `enemy-worm-brawler-hit`, `spider-web-cover`) | `AudioStreamPlayer2D`, `autoplay: true`, `detached`. Every visible impact plays its sound. |
| Weapon scenes (10) | A `SwingSfx` node connected to `attack_started`. |
| Player `player-slime.scene.json` | Hurt, dodge, jump, abilities, eat. Footsteps come from animation events plus the terrain tile. |
| Enemy scenes (4) and Fatty | Connected to `hit_reaction` and `defeated`. New signals: `alerted`, `attack_windup`, `attack_released`. Fatty cues come from `phase_changed`. |
| Trees (47 variant scenes), stone, ore | A shared `audio/*-sfx` sub-scene instance, added to every variant by a script. Connected to `resource_hit`, `harvest_blocked`, `drops_requested`, `destroyed`. |
| Projectiles and collectibles | Connected to `launched`, the hit handler, `expire` and `pickup_resolved`. Uses `detached`. |
| Props (campfire, cauldron, grindstone, anvil, birdhouse) | Looping `AudioStreamPlayer2D`, autoplay, ambience bus. |
| `audio.global` | UI sounds, music, biome ambience. New `features/audio/AudioEventBridge` maps `gameEvents` to named nodes. It uses a context interface (never imports `WorldScene`) and cleans up with `DisposableBag`. |

### Phase 4: Settings and polish
- Volume sliders for master, effects, music and ambience, persisted through `SaveSystem`.
- Duck music while `setSimulationPaused` is active.
- Crossfade music on `area.enter`.
- Switch to boss music on `boss_spawn_requested`.
- Pass the crit flag through to hit feedback (`player.damage` currently hardcodes `crit:false`).

## 3. Sound catalogue (~150 cues)

Priority key: **P1** = combat feel, **P2** = world alive, **P3** = polish.

### Player
| Cue | Hook | Pri |
|---|---|---|
| step-{grass, forest, stone, crystal, snow, sand, water} x3 | Animation events and terrain tile | P2 |
| boost-roll loop | Q held, `slime-roll` | P2 |
| dodge | `PlayerController.tryDodge()` | P1 |
| jump, land | `presentJump()` | P1 |
| teleport-out, teleport-in | `presentTeleport()` | P2 |
| slam-windup, slam-impact | `presentSquashSlam()` | P1 |
| lash-whoosh, lash-hit | `presentStretchLash()` | P1 |
| web-struggle | Rooted branch in `move()` | P2 |
| eat | `slime-eat` | P2 |
| hurt x3, knockback | `player.damage`, `PlayerHealthController` | P1 |
| dot-tick (burn, poison) | `player.damage` with a status source | P2 |
| low-hp heartbeat loop | `hp.changed` < 25% | P3 |
| death, respawn | `player.death`, `player.respawn` | P1 |
| heal, potion-drink, energy-restore | `player.heal`, `useItem()` | P2 |
| level-up / xp-tick / perk-taken | `level.up` / `xp.changed` / `perk.taken` | P1 / P3 / P2 |
| coin | `coins.changed` | P1 |
| ability-unlocked | Level-up toast | P2 |

### Status effects
- **Applied** (`status.added`, P2): one cue each for burn, poison, slow, sticky, bouncy, frenzy.
- **Active** (P3): burn crackle loop.
- **Removed** (`status.removed`, P3): shared expire cue.

### Weapons
Swings play on `attack_started`. Hits play from the impact effect or from `onManagedWeaponOutcome`.

| Weapon | Swing | Hit |
|---|---|---|
| goo-gauntlet | light whoosh x2 | squish punch x3 |
| basic-sword | blade swish x3 | slash x3 |
| basic-spear, wooden-spear, stone-spear | thrust x2 | stab x3 |
| slam-hammer | heavy windup and whoosh | heavy thud and rumble x2 |
| wooden-axe, stone-axe | axe swing x2 | chop wood x4, weak thunk on enemies |
| pickaxe, stone-pickaxe | pick swing x2 | stone clink x4, weak thunk on enemies |

**Combat extras**
- P1:
  - crit layer
  - combo hits 1, 2, 3 (rising pitch)
  - combo finisher
  - immune/blocked clink (Fatty)
- P2: equip (blade shing, wooden clack)
- P3: combo reset, weapon-ready tick

### Enemies
- **Worms:**
  - alert chirp (new `alerted` signal): P2
  - slither steps: P3
  - windup grunt: P2
  - hurt x3: P1
  - death pop: P1
- **worm-archer:** bow draw, arrow release, arrow whiz, arrow hit, arrow thunk. P1–P2.
- **worm-swordsman:** swing, hit. P1.
- **worm-brawler:** punch whoosh, punch hit. P1.
- **slime-spider:**
  - hiss: P2
  - skitter: P3
  - web spit, web splat: P1
  - hurt, death: P1
- **Attack telegraph warning ping** (`AttackTelegraphs.show`): P1.

### Boss: Fatty One Eye
| Cue | Hook | Pri |
|---|---|---|
| intro roar and boss music | `boss_spawn_requested` | P1 |
| heavy steps | `chase` phase | P2 |
| contact hop and crack | `requestContactHop()` and its impact | P1 |
| small hops x3 | `small-hop` phase | P1 |
| leap takeoff and fall whistle | `beginAirborne()` | P1 |
| landing slam, splash, rumble | `land()` | P1 |
| recovery pant | `beginRecovery()` | P2 |
| hurt x2, blocked clink | damage, `canReceiveDamage()` | P1 |
| death and victory sting | `boss_defeated` | P1 |
| fight reset | `resetActiveFight()` | P3 |

### Resources and pickups
| Cue | Hook | Pri |
|---|---|---|
| axe-chop-wood x4 | `resource_hit` (wood) | P1 |
| leaf rustle | same | P2 |
| tree creak and fall | tree `drops_requested` | P1 |
| pickaxe-stone x4 | `resource_hit` (stone) | P1 |
| stone crumble | stone depleted | P1 |
| ore clink and shatter | `DestructibleScript` hit / `destroyed` | P1 |
| wrong-tool clank | `harvest_blocked` | P1 |
| drop pop and bounce | `animateWorldDrop()` | P2 |
| pickup: wood, stone, ore/crystal, silk, berry, potion, key | `pickup_resolved` by item | P1 |
| inventory full | rejected pickup | P2 |
| drop from inventory | `dropFromSlot()` | P3 |

### World
- **P3:** interact prompt, new area discovered, save chime.
- **P2:**
  - NPC voice blip, pitch set per NPC (6 NPCs)
  - chest: locked, open, take, close
  - gate: locked, unlock
  - area transition whoosh
  - area title sting
- **Prop loops (P2–P3):** campfire, cauldron, grindstone, anvil (forge), birdhouse.
- **Biome ambience (P2):**
  - meadow: wind and birds
  - gloop-forest: drips and bubbles
  - icege: howling wind
  - crystal-caverns: drips and hum
- **Music (P2):**
  - Tracks: meadow/village, gloop forest, icege, caverns, boss.
  - Stings: death, level-up, quest-complete, victory.

### UI
UI cues hook `ControlNodes.ts` for all menus.

- **P1:**
  - hover/focus, click, confirm, cancel, error
  - craft success, craft fail
  - level-up modal open
  - quest accept, quest complete fanfare
  - ability denied (locked, cooldown, energy)
- **P2:**
  - inventory open/close
  - item select, item use, item equip
  - crafting open
  - perk choose
  - quest offer, quest progress tick, quest stage done, quest failed
  - hotbar switch
- **P3:** journal page flip, ability-ready ping, toast pop.

## 4. Execution order
1. Phase 0 and Phase 1. `pnpm check` must stay green.
2. Synth bake tool and all P1 synth cues. Then the Kenney library P1 cues (after download approval), plus the flavour
   toggle.
3. Wire effect scenes, weapons, player, enemies, Fatty, resources, UI and the global bridge. Verify in the browser
   preview.
4. User compares synth vs library, and the losing flavour is deleted.
5. P2: footsteps, status effects, world, ambience, music.
6. Settings sliders, then P3 polish.

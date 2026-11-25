# Audio spec — music director, global cues, buses

Source of truth: the Phaser code at `feat/godot-migration`. Everything below is read from code;
file:line references are to `src/game/...` unless they start with `godot/` or `node_modules/`.
A GDScript engineer should be able to port this without opening the TypeScript.

Godot targets: autoload `MusicDirector` → `res://game/audio/music_director.gd` (reached as
`Services.music()`); global cues stay on `GameFeel.audio_cue(cue)` (`game/feel/game_feel.gd`);
converted audio players stay on `game/runtime/sfx_player(_2d).gd` (runtime spec 4.12); buses
`Master`, `Effects`, `Music`, `Ambience` (`godot/default_bus_layout.tres`). Since 2026-11-16 the
`Master` bus ends in a hard limiter (`AudioEffectHardLimiter`, ceiling -0.3 dB): several break cues
peak over full scale at their player volume (the loudness rule on click-like takes), and without
it they clipped.

---

## 0. Scope

### IN
- Which music a world plays, and that ambience is the world's own business.
- The music director: fade-in on arrival, crossfade to boss music while a boss fight lasts and
  back, the duck under a pause menu, the fade-out before leaving an area, the Web Audio unlock gate.
- What audio does during a hit-stop and a menu pause.
- The global cue table (`AudioEventBridge`): which Phaser event plays which `audio.global` cue, and
  who plays it in Godot. The director itself plays `AreaTransition` (arrival); every other cue
  belongs to the system that owns its event.
- The sound mix semantics behind the settings (master × bus, master mute, ambience follows effects)
  and the hook the shell calls to apply them.

### OUT (exist in Phaser; other areas or later phases port them)
| Feature | Where | Notes |
|---|---|---|
| Settings storage and the settings UI | `infrastructure/persistence/GameSettingsStore.ts`, `features/shell/SettingsSurfacePort.ts` | The shell worker. They call `MusicDirector.apply_mix(...)` (§6.3); the director reads nothing from disk |
| Cues of other systems (abilities, eat, sleep, heal, energy, coins, crafting, quests, NPC talk, status effects, weapon equip, menus) | `features/audio/AudioEventBridge.ts:71-109` | Each owner calls `GameFeel.audio_cue(cue)` where Phaser emitted the event (§5 lists them) |
| Stopping a looping global cue (`SleepBreath`) | `AudioEventBridge.ts:74`, `GlobalAudioCuePort.ts:15-17` | `GameFeel` has no `stop` counterpart yet; needed when sleep is ported |
| Pausing sound when the tab loses focus | Phaser default `pauseOnBlur: true` (no override in `config.ts`) | A web-build decision for later |
| Positional audio (2D attenuation and pan), `detached` voices, variants, pitch randomness, `minIntervalMs`, payload filters | `infrastructure/phaser-nodes/AudioStreamPlayer*Node.ts` | Converter helpers, runtime spec 4.12 (already ported) |
| Title-mode music | `scenes/WorldScene.ts:304, 512-518, 630-642` | The title shows over the start world: its music plays, ducked by the `title-screen` pause source, and no `AreaTransition` cue. Godot: the director plays the registered backdrop's music without the cue; the duck is the shell's call (§7.6) |

---

## 1. Data: where every number comes from

### 1.1 Code literals
| Name | Value | Source |
|---|---|---|
| `MUSIC_FADE_IN_MS` | 1500 (world music rises after arriving) | `features/audio/MusicDirector.ts:22` |
| `MUSIC_CROSSFADE_MS` | 1200 (world ↔ boss swap) | `MusicDirector.ts:24` |
| `MUSIC_PAUSE_DUCK` | 0.35 (music level under a pause menu) | `MusicDirector.ts:26` |
| `MUSIC_DUCK_MS` | 250 (1 → 0.35 and back) | `MusicDirector.ts:27` |
| `AREA_LEAVE_FADE_MS` | 320 (picture and music fade before a map change) | `scenes/WorldScene.ts:128` |
| `AREA_ARRIVE_FADE_MS` | 400 (picture fade-in on arrival; the music uses `MUSIC_FADE_IN_MS`) | `WorldScene.ts:129, 1480-1481` |
| `ENERGY_RESTORE_CUE_MIN_DELTA` | 20 | `AudioEventBridge.ts:57` |
| `BLADE_WEAPON_PATTERN` | `/sword\|spear/` | `AudioEventBridge.ts:60` |
| `SILENT_MODALS` | `chest-inventory`, `furniture-placement` | `AudioEventBridge.ts:54` |
| frame delta sanity | a frame longer than `1000 / minFps` = 200 ms reuses the last sane delta | `node_modules/phaser/src/core/TimeStep.js:99, 174, 576-585` |

No audio value lives in `game-constants.json`.

### 1.2 Authored audio
World scenes (`content/scenes/authored/worlds/*.scene.json`); every node is a direct child of the
world root, `loop: true`, `autoplay: true`, `polyphony: 1`:
| World | `MusicPlayer` (bus `music`) | `Ambience` (bus `ambience`) |
|---|---|---|
| `level-1` | `audio.music.level-1-home-town` (`godot/asset/audio/music/level-1-home-town.ogg`), volume 0.55 | `audio.sfx.world.meadow-ambience.1`, volume 0.35 |
| `gloop-forest` | `audio.music.gloop-forest` (`gloop-forest.mp3`), volume 0.5 | `audio.music.gloop-forest-ambience` (mp3), volume 0.35 |
| the dungeons: every room world of Fatty's Lair (`fatty-lair`, `fatty-lair-<room>`: each room scene has its own MusicPlayer, one track), every room world of the Weaver Hollow (`weaver-hollow-<room>`, rebuilt 2026-11-25, each room scene with its own MusicPlayer; today's four floors `weaver-hollow-trunk`, `-roots`, `-boughs`, `-crown` are no longer entered), every room world of the Crystal Mine (`crystal-mine-<room>`, rebuilt 2026-11-25, each room scene with its own MusicPlayer; today's one-scene `crystal-mine` is no longer entered) | `dungeon.wav` (72 s loop), volume 0.5 | — |
| the caves: `gloop-cavern`, `hollow-hill-cave` | `cave-a.wav` ("bass and drops"), volume 0.5 | — |
| the cave `lake-island-cave` | `cave-b.wav` ("chiptune bass"), volume 0.5 | — |
| the interiors `slime-home`, `gloop-hut` | `interior-a.wav` ("solo piano"), volume 0.5 | `audio.sfx.world.interior-ambience.1`, volume 0.35 |
| the interiors `mushroom-home`, `watchkeeper-hideout` | `interior-b.wav` ("chiptune, two voices"), volume 0.5 | `audio.sfx.world.interior-ambience.1`, volume 0.35 |
| every other world (the playground and its caves, the labs, the old maps) | — | — |

Godot (2026-10-18): the dungeon, boss, cave and interior tracks are Magnific (Google Lyria) songs
cut into seamless loops by `scripts/audio/make-music-loop.py` ([TOOLING.md](../../TOOLING.md));
the files in `godot/asset/audio/music/` are 44.1 kHz stereo 16-bit WAVs imported with
`edit/loop_mode=2` (forward, `loop_begin=0`, `loop_end=-1`: the whole file) and `compress/mode=2`
(QOA), about 2.5 MB each once imported. Their sources and the other candidate songs stay in
`asset/Originals/audio/music/` (`dungeon/loops/`, `loops/`). The two cave and two interior tracks
alternate between worlds; any of them can be swapped by changing a world's `MusicPlayer` stream.

`audio/global.scene.json` (`audio.global`, root `GlobalAudio`):
- `Music/BossMusic`: Phaser: `music.level-1-home-town` again at **pitch 1.12**. Godot (2026-10-18):
  `boss-fight.wav` (41 s loop), pitch 1.0; bus `music`, `loop`, volume 0.5, polyphony 1, no
  autoplay. The only boss track: every boss fight with a camp (Fatty, the Matron, the Colossus)
  plays it.
- `Effects/<Cue>`: 43 players, all bus `effects`: 41 one-shots (pitch randomness 0.06, min
  interval 60 ms) plus `SleepBreath` (loop, volume 0.3, polyphony 1) and `Rested` (volume 0.35,
  min interval 1000 ms). Names in §5.

No world metadata, area id, biome or story flag chooses music: a world plays what its scene
holds (no story-variant subtree contains an audio node). An "area change" is a map change, which
reloads the page (§3.6).

### 1.3 Settings defaults (`infrastructure/persistence/GameSettingsStore.ts:27-35`)
`master 0.8`, `effects 1`, `music 0.7`, `muted false`. Every volume is linear in [0, 1]; a
stored value outside it is clamped on load (`:37-49`). There is no ambience slider: ambience
follows `effects` (`:9`, `SettingsSurfacePort.ts:85`).

---

## 2. Which tracks the director drives

The world controller builds the director after mounting the player and the world
(`features/world/UniversalSceneWorldController.ts:758-764`):
- **World track** = the first `AudioStreamPlayerNode` (not the 2D node, which is a separate class,
  `AudioStreamPlayer2DNode.ts:10`) whose bus is `music`, in pre-order depth-first order under the
  mounted world root (`:1743`, `descendants` `:2214-2222`). level-1 and gloop-forest have one; the
  others have none (`world` undefined). Godot: the dungeons, caves and interiors of §1.2 have one
  too.
- **Boss track** = `Music/BossMusic` of the mounted `audio.global` scene (`:801-806`), undefined
  if missing.
- **Ambience** is not driven: it autoplays at its authored volume, is never ducked (the duck is on
  the `music` bus only) and is never faded; the page reload cuts it.

The music bus has no other users (only these three nodes in all authored scenes set `bus: music`;
Godot: every world's `MusicPlayer` of §1.2 and `BossMusic`).

---

## 3. The director (`features/audio/MusicDirector.ts`)

### 3.1 State
`worldGain = 0`, `bossGain = 0`, `duck = 1`, `bossFight = false`, `paused = false`,
`leavingMs = undefined` (`:36-41`). The constructor calls `world.setGain(0)` and
`boss.setGain(0)` (`:43-46`), in the same JS turn as the world mount, so the autoplaying world
track never sounds at full volume.

### 3.2 Inputs
| Call | Effect | Caller |
|---|---|---|
| `setBossFight(active)` | `bossFight = active`; when active, the boss track exists and is not `playing` → `boss.play()` (from the top) (`:48-51`) | `gameEvents 'boss.engaged'` → true, `'boss.disengaged'` → false (`UniversalSceneWorldController.ts:765-772`). Last event wins: one boolean, not a count |
| `setPaused(paused)` | `paused = paused` (`:53-55`) | `WorldScene.setSimulationPaused` (`:750-772`) → `UniversalSceneWorldController.setPaused` (`:789-793`) whenever the set of pause sources becomes empty / non-empty |
| `fadeOut(ms)` | `leavingMs = max(1, ms)`; never cleared (`:58-60`) | `WorldScene.leaveAreaThen` with 320 (`:1011-1016`), used by area travel (`:1005-1009`) and quit to title (`:645-650`) |
| `update(deltaMs)` | §3.3 | `WorldScene.handlePresentationPostUpdate` every rendered frame (`:1590-1591`), with the scene's frame delta, during menus, hit-stops and the title too |

Pause sources (all menus): `pause-menu`, `settings`, `controls`, `save-slots`, `credits`,
`title-screen`, `game-over`, `end-card` (`features/shell/GameShell.ts:59-97`), `managed-chest`,
`inventory`, `crafting`, `journal`, `quest-npc`, `npc-dialogue`, `worldmap`
(`WorldScene.ts:2279-2285`), `persistence` (`:418`). A hit-stop is **not** a pause source.

### 3.3 `update(deltaMs)` (`MusicDirector.ts:62-81`)
```
step = max(0, deltaMs)
duck = approach(duck, paused ? 0.35 : 1, step / 250 * (1 - 0.35))   # 250 ms for the full swing
setMusicDuck(duck)                                                   # also while locked
if not audioUnlocked: return                                         # gains frozen until unlock
bossActive = bossFight and boss track exists
leaving    = leavingMs defined
worldTarget   = (leaving or bossActive) ? 0 : 1
bossTarget    = (not leaving and bossActive) ? 1 : 0
worldDuration = leaving ? leavingMs : (bossActive or bossGain > 0) ? 1200 : 1500
bossDuration  = leaving ? leavingMs : 1200
worldGain = approach(worldGain, worldTarget, step / worldDuration)
bossGain  = approach(bossGain,  bossTarget,  step / bossDuration)
world.setGain(worldGain); boss.setGain(bossGain)
if bossGain == 0 and not bossActive and boss.playing: boss.stop()    # next fight starts from the top
```
`approach(v, t, s)` moves `v` toward `t` by at most `s` and never overshoots (`:84-88`).

Derived behaviour:
- **Arrival:** world music starts (autoplay) at gain 0 and reaches 1 after 1500 ms of unlocked time.
- **Boss engaged:** the boss track starts from the top; both gains move 1/1200 per ms, so from a
  settled world track the swap is linear and complementary (0.5/0.5 at 600 ms, done at 1200 ms).
  The world track keeps playing silently; it is never paused or restarted.
- **Boss disengaged (defeat, reset after the player's death, camp exit):** the reverse over
  1200 ms; at boss gain 0 the boss track stops. Re-engaging while it still fades out does not
  restart it (`playing` is still true) and fades it back up from where it is.
- **Leaving:** both gains fall to 0 over exactly the leave time (320 ms) from wherever they are.
- **Menu pause:** the duck goes 1 → 0.35 in 250 ms and back in 250 ms; fades keep running
  under the duck (the gains do not wait for the menu).

### 3.4 Track gain mechanics (`infrastructure/phaser-nodes/AudioStreamPlayerNode.ts`)
- Heard volume = `authored volume × (muted ? 0 : bus volume × master × duck) × gain`
  (`synchronize :190-201`, `GlobalAudioServices.volume :24`), re-applied every frame, also while
  paused (`:302-304, 314`).
- `setGain(g)` clamps to [0, 1] (`:155-158`). `playing` is the *desired* state (`:151`), true from
  `play()` until `stop()` even while the page is locked.
- A loop owns one voice; `play()` while it plays is ignored (`:221-227`). `stop()` stops it; the
  next `play()` restarts from the beginning.
- `autoplay` makes the node want to play on tree enter; the voice starts once audio is unlocked
  (`:160-166, 205-217`).

### 3.5 Frame delta
Phaser's scene delta is smoothed (`TimeStep.smoothDelta`, `TimeStep.js:563-611`): the average of
the last 10 frame deltas; a frame longer than 200 ms (`1000 / minFps 5`) is replaced by the last
sane value; the first 120 frames after boot or a focus change are capped at 16.67 ms. So a
loading stall never makes a fade jump.

### 3.6 Map change
A map change (travel, quit to title, load) fades picture and music out for 320 ms
(`WorldScene.ts:1011-1016`) and then **reloads the page**: a new world controller, a new director
at gains 0, every track restarted from the top (even when the next world plays the same file).
The boss fight cannot outlive the page.

---

## 4. Pause, hit-stop and the audio unlock

- **Hit-stop** (`WorldScene.ts:735-748, 792-798`): physics, tweens and sprite animation hold;
  the scene runtime advances 0 s. Audio is untouched: voices keep playing, the director keeps
  updating with real frame time, and there is no duck.
- **Menu pause:** the simulation stops, every audio node keeps processing (`processWhenPaused`,
  `AudioStreamPlayerNode.ts:302-304`), music ducks (§3.3), effects and ambience do not.
- **Web Audio unlock:** Phaser's sound manager is `locked` until the first `touchstart`,
  `touchend`, `mousedown`, `mouseup` or `keydown` on the page
  (`node_modules/phaser/src/sound/webaudio/WebAudioSoundManager.js:339-377`). Until then voices do
  not start (`AudioStreamPlayerNode.ts:205-217`) and the director's gains stay frozen (only the
  duck moves, `MusicDirector.ts:67`); after it, the world track starts from the top and fades in
  over 1500 ms. `GlobalAudioServices.isUnlocked/onUnlocked` (`:48-66`) are the gate.

---

## 5. Global cues (`features/audio/AudioEventBridge.ts`)

The bridge listens to `gameEvents` and plays `Effects/<Cue>` of `audio.global` through
`createGlobalAudioCuePort` (`infrastructure/audio/GlobalAudioCuePort.ts:7-30`: only nodes under
`Effects`, a missing cue warns once in dev and is otherwise silent; `stop(cue)` stops a loop).
Positional and per-entity sounds stay in their own scenes, wired by scene connections (`:12-13`).
The cues Godot added after the port (steps, water, Gulp forms, puzzles, typing) are in §10, and
those of Sound Picker round 5 (the Gulp's suck and throw, breaks, the Roll, the Clod Stomper, the
ceremony) in §11.
Godot: `GameFeel.audio_cue(cue)` plays the same node (it searches the whole `GlobalAudio` tree,
`game_feel.gd:143-155`; no cue name repeats outside `Effects`, so this is equivalent).

**Heard only on screen** (owner, 2026-10-17: steps were heard at Fatty's Lair's entrance from Bone
Marchers two rooms away). A global cue has no position, so an enemy that plays one would sound as
if beside the slime wherever it is. The patterned enemies (`patterned_enemy.gd` `_cue`) and the
Clod Stomper ask `game/audio/hearing.gd` first: a cue plays only when the enemy is inside the
camera's view grown by `combat.hearing.cueMarginPx` (96) and, in a world with camera rooms, inside
the room the view keeps to, as Zelda's other screens are silent.

| Phaser event (emitter) | Cue | Godot |
|---|---|---|
| `area.enter` (`WorldScene.ts:515`, every world arrival outside title mode) | `AreaTransition` | **MusicDirector** on `WorldService.world_registered` (§7.4) |
| `boss.defeated` (`UniversalSceneWorldController.ts:596-600`) | `Victory` | `boss_camp.gd:319-330` (ported) |
| `player.respawn` (`core/GameState.ts:216-219`) | `Respawn` | `player.gd` (ported) |
| `weapon.critical-hit` (`features/combat/CombatController.ts:216`) | `Crit` | `player_combat.gd:223` (ported) |
| `player.action {anim}` (`AudioEventBridge.ts:30-42`): `dodge` → `Dodge`, `ability-denied` → `AbilityDenied` | as listed | `player.gd` (ported). Since 2026-10-09 the Roll plays its own cues (§11) and nothing plays `Dodge` (its player stays) |
| `player.action`: `eat` → `Eat`, `ability-jump` → `Jump`, `jump-land` → `Land`, `ability-teleport` → `TeleportOut`, `teleport-in` → `TeleportIn`, `ability-squash-slam` → `SlamWindup`, `slam-impact` → `SlamImpact`, `ability-stretch-lash` → `Lash` | as listed | abilities ([abilities.md](abilities.md) §16) |
| `ability.learned` (`features/progression/StoryProgress.ts`) | `AbilityLearned` | abilities |
| `ground.cracked`, `lash-bell.rung`, `web.torn`, `building.restored`, `building.restore-refused {reason:'missing-materials'}`, `goo-heart.collected` (`WorldScene.ts`) | `GroundCrack`, `BellRing`, `WebTear`, `BuildingRestored`, `CraftFail`, `Heal` (placeholder) | abilities / world objects |
| `energy.changed {delta ≥ 20}` (`GameState.ts`) | `EnergyRestore` (also on every respawn refill) | abilities (energy) |
| `player.heal {source ≠ 'rest'}` (`GameState.ts`) | `Heal` | inventory (consumables) |
| `coins.changed {delta > 0}` (`GameState.ts:108-112`) | `Coin` | `run_state.gd` `add_coins` (a gain) |
| `weapon.equipped {weaponId}` (`GameState.ts:169-173`, also on restore/reset `:82, 92`) | `EquipBlade` if the id matches `sword\|spear`, else `EquipTool`; nothing for `null` | inventory (weapon switching) |
| `craft.completed` / `craft.failed` (`crafting/Crafting.ts`, `features/ui/CraftingSurfacePort.ts`) | `CraftSuccess` / `CraftFail` | crafting |
| `npc.talked` (`features/interaction/QuestNpcController.ts`) | `NpcBlip` | dialogue |
| `quest.accepted` / `.progressed` / `.stage-completed` / `.completed` / `.failed` (`quests/QuestService.ts`) | `QuestAccept` / `QuestProgress` / `QuestProgress` / `QuestComplete` / `QuestFailed` | quests |
| `status.added {kind}` / `status.removed` (`systems/StatusEffects.ts`) | `StatusBurn` … `StatusFrenzy` / `StatusExpire` | `player/status_effects.gd` (only `sticky` is applied today) |
| `player.sleep {asleep}` / `player.rested` (`WorldScene.ts`) | `SleepBreath` play / stop, `Rested` | `rest/sleep_controller.gd`: the loop starts with deep sleep and stops on waking (`GameFeel.stop_audio_cue`) |
| any modal opens / closes (`ui/ModalStack`, `AudioEventBridge.ts:104-109`) except `chest-inventory` and `furniture-placement` | `JournalOpen` for `quest-journal`, else `MenuOpen`; `MenuClose` | game windows (`game_windows.gd`) and the shell's menus (`shell.gd` `_on_menu_opened` / `_closed`) |

No death cue is global: the player's `DeathSfx` and `HurtSfx` live in the player scene
(connections `defeated` / `damaged` → `play`, player spec), and the defeat itself only plays
`player-defeated` feel (shake 400 ms × 0.012, hit-stop 150 ms; `WorldScene.ts:1920-1940`). A
player death changes the music only through the boss camps: `resetActiveFights` hides the boss
bar, which emits `boss.disengaged` (`BossCampScript.ts:134-141`).

---

## 6. Mix and settings

### 6.1 Phaser (`infrastructure/audio/GlobalAudioServices.ts`)
- Per bus `effects | music | ambience`: a volume in [0, 1] (`setVolume`, throws outside), a mute
  flag, and a temporary **duck** (`setDuck`, clamped, not a setting) (`:13-16, 37-47`).
- `master` in [0, 1] and `masterMuted` (`:11-12, 30-35`).
- Effective gain of a bus = `volume[bus] × master × duck[bus]`, silenced when master or the bus is
  muted (`:24-25`).
- `applyMix` (`features/shell/SettingsSurfacePort.ts:81-87`), run now and on every settings
  change (`UniversalSceneWorldController.ts:483`): master ← `master`, master mute ← `muted`,
  effects ← `effects`, **ambience ← `effects`**, music ← `music`. Per-bus mutes are never set.

### 6.2 Godot mapping
| Phaser | Godot |
|---|---|
| bus volume (linear) | `AudioServer.set_bus_volume_linear(bus, v)` on `Effects` / `Music` / `Ambience` |
| `master` | the `Master` bus volume: Godot sends every bus through `Master`, so the product is the same |
| `masterMuted` | `AudioServer.set_bus_mute(Master, muted)` |
| music duck | **not** on the bus: the director multiplies it into its own tracks' volume (it owns every music-bus player, §7.2), so the shell can set the `Music` bus freely |
| authored node volume | the node's `volume_db` (`linear_to_db(volume)`, runtime spec 4.12) |

### 6.3 The hook for the shell
`MusicDirector.apply_mix(master, effects, music, muted)` (static; call it through
`const MusicDirectorScript := preload("res://game/audio/music_director.gd")`, so it works before
the autoload exists) applies §6.1's `applyMix` exactly; `MusicDirector.set_bus_volume_linear(bus,
value)` sets one bus (value clamped to [0, 1], a non-finite value is ignored). The shell stores
the settings (defaults §1.3) and calls `apply_mix` at boot and on every change. Nothing in the
director reads or writes settings.

---

## 7. Godot port

### 7.1 Files and registration
- `res://game/audio/music_director.gd`: `extends Node`, no `class_name` (autoload rule), reached
  as `Services.music()` (null while unregistered). `PROCESS_MODE_ALWAYS`.
- Autoload name `MusicDirector`, path `*res://game/audio/music_director.gd`, registered **after
  `RunState`** (it needs `WorldService` and `GameFeel` only at run time, not in `_ready`, so any
  position after `GameFeel` works). It must exist before `main.tscn` loads its first world (every
  autoload does).
- Unregistered (tests, or before registration), `MusicDirectorScript.new()` added anywhere in the
  tree adopts the current world at `_ready` and then follows the same signals.

### 7.2 Claiming the world track
1. `SceneTree.node_added` (fires on tree enter, before `_ready`): every `AudioStreamPlayer` on bus
   `Music` with `autoplay_cue` set that enters the tree outside the director gets
   `autoplay_cue = false`, so it cannot start at full volume before the director has it (Phaser
   §3.1). In Phaser every music-bus node is a world track or BossMusic, so nothing else is lost; a
   future music-bus autoplay outside a world would stay silent unless it is adopted.
2. `WorldService.world_registered`: the first `AudioStreamPlayer` on bus `Music` under
   `world_root` in tree order (Godot's `find_children` is pre-order, as Phaser's `descendants`) is
   stopped (`stop_cue`), **moved under the director** (renamed `WorldMusic`), set to silence and
   started from the top (`play_cue`) at gain 0 once audio is unlocked. Its authored volume
   (`volume_db` at adoption) is kept as the track's base. Further music-bus players of that world
   (none are authored) get their autoplay back and play unmanaged, as in Phaser.
3. The node lives under the director, so a world teardown (`main.gd` `_teardown_world`) does not
   free it, and `AreaTravel.fade_out_music` no longer finds it.
4. A world registered twice (same root) is not adopted again.

The boss track is `audio.global`'s `Music/BossMusic`, taken from a private instance of the scene
(the rest is freed) and kept as the director's child `BossMusic`. `GameFeel`'s own copy of
`audio.global` keeps an idle `BossMusic` that nothing plays.

### 7.3 Signals and polling
| Source | Director |
|---|---|
| `WorldService.world_registered` | adopt the world (§7.4); play `AreaTransition` when the world is under main (`world_main`), not for a title backdrop (Phaser has no `area.enter` in title mode) |
| the adopted world root's `tree_exiting`, with no leave fade running | `fade_out(320)`: a world freed without a travel (quit to title, a test teardown) does not leave its music playing at full volume |
| every node in group `boss_camp` (bound on adoption and each frame, like the boss bar) | `boss_engaged {campId}` → engaged; `boss_disengaged {campId}` → not; a camp bound while its boss lives counts as engaged |
| `world_main` group node's `is_transitioning()` turning true (checked each frame) | `fade_out(AreaTravel.LEAVE_FADE_MS)` (Phaser `fadeOutMusic(320)`); main.gd may instead call `Services.music().fade_out(ms)` directly |
| tree paused with any reason other than `hit-stop` (or with `modal`), or `set_menu_paused(true)` | the menu duck (Phaser `setPaused`) |
| first key, mouse button or touch press on the web | `audio_unlocked = true` (desktop: unlocked from the start) |
| `_process(delta)` (real time, ALWAYS) | `advance(ms)`: a frame longer than 200 ms counts as the last sane frame (§3.5) |

The player's `defeated` needs no listener: the camps already turn it into `boss_disengaged`.

### 7.4 Adopting a world (the Godot stand-in for the page reload)
On `world_registered`: forget the leave fade and every engaged camp (the old world's camps are
gone); the old world track, if still audible (no leave fade ran), fades out as `FadingMusic` over
the remaining leave time or 1200 ms and is freed at silence, otherwise it is stopped and freed at
once; the new world's track is claimed at gain 0 and fades in over 1500 ms (1200 if the boss track
is still audible, Phaser's rule). Godot: when the new world plays the same file as the track still
playing, that track carries on and the new world's player is freed: on a scroll into the next
chunk of a region or through a room door into the next room of Fatty's Lair (main.gd
`is_travelling_within_region`: no leave fade, the music never dips), and on any travel of main's
after the leave fade (the next floor of the Weaver Hollow, a door between two worlds with one track,
a stair hatch, a pause-menu load, a faint waking in another world: `load_run` and
`respawn_in_world` travel too): the track keeps its place and fades back in over 1500 ms instead of
starting over. A quit to title or a
new main still starts the track from the top. The boss track is not restarted; with no engaged camp it fades
out and stops by the normal rule. Then `AreaTransition` plays for main's worlds
(`play_arrival_cue`, default true, turns it off entirely).

### 7.5 Deviations (Godot only)
- Engaged camps are a set keyed by camp id instead of one boolean: two fights at once would keep
  the boss music until both end (no world has two camps).
- A world replaced without the leave fade crossfades instead of cutting (Phaser always fades first).
- The leave fade also fades the world's ambience (`AreaTravel.fade_out_music`); Phaser lets it
  play until the reload cuts it.
- A world that leaves the tree without the leave fade starts the 320 ms fade then, after the
  world is gone (Phaser fades before every map change).
- The frame-delta rule keeps only Phaser's 200 ms sanity cap, not the 10-frame average or the
  120-frame boot cap.

### 7.6 Open hooks for other areas
- Title screen (shell): its backdrop world gets the world music and no arrival cue by itself.
  Phaser's title is the `title-screen` pause source, so its music plays at 0.35: call
  `Services.music().set_menu_paused(true)` while the title shows (the Godot title does not pause
  the tree) and `false` when it goes.
- Quit to title (shell): for Phaser's order (music fades with the 320 ms picture fade, before the
  world goes) call `Services.music().fade_out(320)` when the quit fade starts; without it the
  director fades when the world leaves the tree.
- Settings (shell): `apply_mix` at boot and on change (§6.3).
- Main / area travel (world objects): may call `Services.music().fade_out(AreaTravel.LEAVE_FADE_MS)`
  in `travel_to`; until then the director watches `is_transitioning()`. Once the director is
  registered, `AreaTravel.fade_out_music` only fades ambience.

### 7.7 API (`music_director.gd`)
| Member | Meaning |
|---|---|
| `MUSIC_FADE_IN_MS`, `MUSIC_CROSSFADE_MS`, `MUSIC_PAUSE_DUCK`, `MUSIC_DUCK_MS` | §1.1 |
| `var audio_unlocked: bool` | the Web Audio gate (§4) |
| `var play_arrival_cue: bool` | `AreaTransition` on arrival |
| `set_boss_fight(active, camp_id = "")` | Phaser `setBossFight` per camp |
| `fade_out(duration_ms)` | Phaser `fadeOut` |
| `set_menu_paused(paused)` | an explicit pause source for a menu that does not pause the tree |
| `advance(delta_ms)` | one Phaser `update` plus the camp binding and travel watch |
| `world_gain()`, `boss_gain()`, `duck()`, `is_boss_fight()`, `is_leaving()`, `is_menu_paused()` | state |
| `world_track()`, `boss_track()` | the `AudioStreamPlayer`s (null when none) |
| static `apply_mix(master, effects, music, muted)`, `set_bus_volume_linear(bus, value)` | §6.3 |

A track's heard volume is `volume_linear = base × gain × duck` on its own player; buses carry the
settings.

Body-shapes rework (branch `exp/body-shapes`): `dip(db, duration_ms)` drops every music track by
`db` for `duration_ms` of real time (a factor `_dip` in the volume, 1 otherwise), for the rework's
room clear (`GameFeel.room_clear`, `combat.roomClear.musicDropDb` / `musicDropMs`); nothing calls
it outside the rework ([BODY_SHAPES.md](../BODY_SHAPES.md) "Juice").

---

## 8. Edge cases
- A world without music (the playground): no world track; a boss fight there still brings in the
  boss track; leaving fades whatever plays.
- Boss engaged while the arrival fade-in runs: the world gain falls from where it is at the
  crossfade rate; after the fight it rises at the crossfade rate while the boss gain is above 0,
  then at the fade-in rate.
- Locked page: nothing advances except the duck; `set_boss_fight(true)` marks the boss track as
  wanted and it starts on unlock.
- Hit-stop during a menu: the duck holds while `modal` is among the reasons.
- `fade_out` during a boss fight: both tracks fall to 0 over the leave time; the camps' exit then
  disengages and the boss track stops at silence.

---

## 9. Tests (`godot/tests/test_audio.gd`)
Run against `Services.music()` when registered, otherwise against an instance added under main
(freed with it). Numbers are checked by calling `advance(ms)` with processing off (restored when
main leaves the tree) except the travel test, which runs on real time.
- level-1: the claimed track plays `level-1-home-town.ogg` on `Music` from under the director at
  base 0.55, nothing on `Music` plays under the world root, the ambience plays on `Ambience` in the
  world; +750 ms → gain +0.5, then 1.0; `volume_linear = 0.55 × gain`.
- Boss: walking into the camp starts `BossMusic` (`boss-fight.wav`, pitch 1.0, base 0.5); 600 ms → 0.5 / 0.5,
  1200 ms → 0 / 1 with the world track still playing; five spear hits defeat Fatty → `Victory`
  plays on `Effects`; 1200 ms later the world is back at 1 and `BossMusic` has stopped.
- Player death mid-fight → disengaged → the world music returns over 1200 ms.
- Travel to gloop-forest: the music falls to 0 within the leave fade, `AreaTransition` plays on
  arrival, the new track is `gloop-forest.mp3` at base 0.5 rising from 0 to 1 over about 1500 ms,
  the old track is freed.
- Main leaving the tree without a travel: the music falls to 0 over 320 ms.
- Menu pause ducks to 0.35 in 250 ms and back; a hit-stop alone does not duck;
  `set_menu_paused` ducks too.
- Locked audio freezes the gains (not the duck) and holds a wanted boss track until unlock.
- `apply_mix`: bus volumes and the master mute as §6.1 (restored afterwards).

---

## 10. Steps, water and the round-3 cues

Added 2026-10-06 (Sound Picker round 3): the actions the Phaser game left silent. The owner
chose their takes on the [Sound Picker](https://claude.ai/artifact/RDDoJKEVByiJCSsRvzwLHZ):
`scripts/audio/picker/round-3.json`, picks in `round-3-picks.json`. Round 4 added one transform
sound per Gulp form (`round-4.json`, `round-4-picks.json`). Both rounds were applied 2026-10-06.
The workflow is in [TOOLING.md](../../TOOLING.md#sound-picker-rounds).
Steps, wading and strokes are mixed well under the one-shots, at the owner's request ("make steps
softer than the rest"). The levels are the `TARGET_DB` of `scripts/audio/stage-round.py`.

### 10.1 Steps, wading and swimming (`game/audio/footsteps.gd`)

The player instances `game/scenes/audio/footsteps.tscn` as its child `Footsteps`. It has one
`sfx_player.gd` per surface, on the Effects bus, holding its takes in an AudioStreamRandomizer.
- **Step**: each time a `walk` clip starts or loops. Frame 0 of every walk row is the slime's
  squash, the moment it lands, so a step comes about every 0.54 s. The surface is the `tile_id`
  of the ground cell under the feet, mapped by `surface_by_ground`:

  | Ground ids | Player |
  |---|---|
  | `grass-a`, `grass-b` | `Grass` |
  | `forest-floor`, `forest-moss` | `Forest` |
  | `amberleaf-ground` | `Leaves` |
  | `sanddessert-ground` | `Sand` |
  | `frozen-ground` | `Snow` |
  | `town-cobble` | `Stone` |
  | `cavern-floor`, `rock-wall` | `Cave` |
  | `crystal-floor` | `Crystal` |
  | `wood-floor` | `Wood` |
  | `mushroom-earth-floor`, `mushroom-plain-floor`, `mushroom-clover-floor` | `Soft` |
  | `water` (and `deep-water` under a walker) | `Shallow` (wading) |

- **Stroke** (`Swim`): while swimming (the Swim form, id `frog`, in deep water) and moving faster than
  8 units/s. One plays as the slime starts to move and one at each loop of the swim clip (about
  1.1 s). Floating still plays none, though the swim clip loops then too.
- **Crossing the waterline**: land → shallows plays `WaterEnter`; starting to swim plays
  `SwimEnter`; climbing out onto land plays `WaterExit`. Swimming back into the shallows is quiet.
- Nothing plays in the air (`is_airborne`, the jump and ledge drops), on a cell without a tile or
  on the stairs walk (`is_on_stairs`; it plays its own `StairsStep`, §10.2).
- Each player's minimum interval (steps 180 ms, strokes 300 ms) absorbs a clip restart when the
  facing changes.

### 10.2 Global cues added (`Effects/<Cue>` in `global.tscn`)

| Cue | Plays when | Where |
|---|---|---|
| `BathSoak` (loop; Sound Picker round 9, applied 2026-11-13: "Soft lapping") | the slime is in a bath, from the step in to the step out; the bath's only sound (owner) | `rest/bath_controller.gd` ([Baths](interaction.md#351-baths-gamebath-godot-only-2026-11-12)) |
| `GulpTransformHeavy` / `GulpTransformSticky` / `GulpTransformFrog` | that form starts or is refreshed (the form's `transform_cue` in `gulp_forms.gd`; the eat sound plays too) | `player.gd` `on_gulp_form_changed` |
| `GulpBurp` / `GulpWearOff` | a tap away from a spot ends the form / the form's time runs out | same |
| `LashCatch` | the tendril hooks a pickup or an anchor (a miss stays silent, the owner's pick) | `lash_sequence.gd` `_catch` |
| `WebStruggle` | a direction held while a web roots the slime (700 ms apart) | `player.gd` `_move` |
| `FallDown` | climbing down the cracked-ground hole (that door's `use_cue`), falling into a ladderless hole (`fall_cue`) | `door.gd` `_play_lead` |
| `DoorUse` | an opening, a ladder, an interior's way out (`door.gd` `use_cue` default); also the placeholder for a door cue without a take | same |
| `DoorOpen` / `DoorClose` | a real door's leaf swings open as the slime pushes in / closes behind it on arrival (2026-10-14; **no takes yet**: `DoorUse` plays instead until `Effects/DoorOpen` and `Effects/DoorClose` are added to `global.tscn`) | `door.gd` `_play_lead`, `_physics_process` |
| `PlatePress` / `PlateRelease` | a pressure plate goes down / comes back up | `pressure_plate.gd` |
| `GateOpen` | a gate opens (plate, bell or key) | `gate.gd` `open` |
| `GateUnlock` / `GateLocked` | a key unlocks a gate / a gate stays shut (no key, stuck), when the slime pushes against it | `gate.gd` `push_open` |
| `GroundCreak` | cracked ground creaks under a Heavy slime (with its text, 4 s apart) | `cracked_ground.gd` |
| `DummyHit` | any hit on the training dummy | `training_dummy.gd` |
| `DropPop` / `DropLand` | each loot or resource pile flies out / lands | `resource_drops.gd` `_launch` |
| `PotionDrink` | the item's `use.cue` (both potions; the berry basket plays `Eat`) | `inventory_actions.gd` `use_item` |
| `HitDull` | a player hit with a weapon that has no impact effect (gauntlet, axes, pickaxes) | `player_combat.gd` `on_outcome` |
| `HitBlocked` | a player hit refused as `source-blocked`, `state-blocked` or `immune` (Fatty in the air; Phaser was silent) | same |
| `Save` | a save to a slot succeeds | `save_slots_menu.gd` `_report` |
| `Toast` | "New quest available" | `quest_notifications.gd` |
| `TalkBlip` | letters appear in the dialogue box (80 ms apart at most) | `dialogue_box.gd` `_update_reveal` |
| `WaterSplash` | the slime falls into deep water under a plank bridge; a falling plank drops into the water (the `SwimEnter` takes reused; 2026-10-17) | `hazard_watch.gd` `_start_fall`, `falling_plank.gd` |
| `StairsStep` | as each footstep of the stairs walk lands, every `elevation.stairsFootstepMs` (400 ms; [ELEVATION.md](../ELEVATION.md#stairs-walk)) (`footstep.stairs`, Sound Picker round 6 of 2026-10-14: the owner picked A, a stone tap, of six kinds; a 60 ms minimum interval) | `stairs_sequence.gd` `_cue_footsteps` |

### 10.3 Sound audition (dev)

`?audition` on the web (Web (dev) export) or `-- --audition` on desktop adds
`game/dev/sound_audition.gd`. F8 / F7 step through the option sets: what the game plays, then every
option key of the staged round in the order it first appears in `audition.json` (`now`, the sound
before the round, last; since 2026-10-16, before which only A, B and round 2 were sets). Every
staged cue that has the set's option plays those takes from `res://asset/audio/sfx/audition/` (MP3s
plus `audition.json`, written by `stage-round.py`), at the volume measured for them; the others keep
what the game plays. A corner panel names the set (its key and its options' labels) and the ground
under the slime. The release Web export excludes the audition folder; applying the picks deletes
it. It holds only the open round's cues. Round 4 was applied on 2026-10-06, round 5 (§11) on
2026-10-09, round 6 (the stairs step, `scripts/audio/picker/round-6.json`) on 2026-10-14 and
round 7 (§12, the Gulp's suck, catch and throw) on 2026-10-17; rounds 8 to 10 are applied too.
Round 11 (§13, the throw's toss and kill) was applied on 2026-11-16 and round 12 (§14, each material
its own sound) on 2026-11-17, so no round is open: the folder is gone and the panel says no round
is staged.

### 10.4 Tests

`godot/tests/test_footsteps.gd` (level-1's lake) covers these:
- steps once per walk cycle on the ground under the feet, and none standing;
- one splash walking into the shallows, then wading;
- the Frog's plunge, no strokes floating still, strokes swimming;
- the form's own transform cue, the burp, and no lash-miss player;
- every added cue has a player with takes.

---

## 11. Round 5: the Gulp, the breaks, the Roll, the Clod Stomper and the ceremony

Added 2026-10-09 (Sound Picker round 5, `scripts/audio/picker/round-5.json`): 15 cues for the
essence Gulp's suck and throw, the liftables breaking by material, the Roll's Pegasus-boots dash,
the Clod Stomper's slam and the ability ceremony. They are Magnific (ElevenLabs) sound effects,
three takes per option; eight cues also had an option B on the picker. The owner accepted the
defaults on 2026-10-09 ("sound the defaults are ok"): option A of each ships, applied with
`stage-round.py --picks scripts/audio/picker/round-5-picks.json`. That wrote the library files
(`godot/asset/audio/sfx/library/<player|world|enemy|ui>/<cue>-<n>.wav`) and the players under
`Effects` in `global.tscn`, kept the takes in `asset/Originals/audio/magnific/`
(`<category>-<cue>-r5-<n>.wav`) and removed the audition copies; the takes are registered in
`cues.mjs` and `picks.json` ([TOOLING.md](../../TOOLING.md#sound-picker-rounds)).

| Cue | Options (A / B) | Plays when | Where |
|---|---|---|---|
| `GulpSuck` | Jelly vacuum / Whistling slurp (replaced in round 7, §12) | Q starts a suck | `mouth.gd` `begin_suck` |
| `GulpCatch` | Gloop plop / Cork plunk (replaced in round 7, §12) | the sucked thing reaches the mouth, or the bag's Use puts an essence in it; also the slime gulping down the ceremony's bubble | `mouth.gd`; `ability_ceremony.gd` |
| `GulpSpit` | Ptoo / Boing pop (replaced in round 7, §12) | Q throws what the mouth holds | `mouth.gd` `throw` |
| `BreakClay` | Pot shatter / Jar pop and tinkle | a clay thing breaks (pots, jugs, urns, shells) | `thrown_object.gd` `BREAK_CUES` (a throw), `mouth.gd` `drop` (knocked out by a hit) |
| `BreakGlass` | Glass shatter | glass; crystal has `BreakCrystal` since round 12 (§14) (jars, bottles, floats, crystals, obsidian) | same |
| `BreakWood` | Crate smash (two takes since round 12, §14) | wood; bone has `BreakBone` since round 12 (crates, kegs, buckets, logs, coconuts) | same |
| `BreakMetal` | Clang | metal (kettles, lanterns, the iron ball) | same |
| `BreakStone` | Rock crack (replaced in round 12, §14) | stone (rocks, bricks, stone urns, coral) | same |
| `BreakSoft` | Splat (one take since round 12, §14) | soft; snow has `BreakSnow` since round 12 (pumpkins, sacks, mud, snow) | same |
| `BreakIce` | Ice shatter (two takes since round 12, §14) | ice (ice blocks, icicles, frost crystals, frosted jars) | same |
| `RollRev` | Squeaky screech / Peel-out | the Roll's spin-up | `player_roll.gd` `begin` |
| `RollLaunch` | Zip / Boing whoosh | the ball shoots off | `player_roll.gd` `_launch` |
| `RollBonk` | Thud bonk / Crash and boing | the ball bonks into a wall, a rock or an enemy | `player_roll.gd` `_bonk` |
| `StomperSlam` | Mud stomp | the Clod Stomper lands its stomp (it played `SlamImpact` before) | `clod_stomper.gd` |
| `Ceremony` | Harp and bells / Marimba jingle | the ceremony's fanfare (an ability, a permanent item's first arrival, a Goo Heart) | `ability_ceremony.gd` |

A material with no cue falls back to `HitDull` (`thrown_object.gd` `CUE_FALLBACK`).

---

## 12. Round 7: the Gulp's suck, catch and throw

Opened 2026-10-16, applied 2026-10-17. The owner: "Sucking should be short, throwing should sound
like throwing something. Those sounds are going to play a lot, so they need to be pleasant." Manifest
`scripts/audio/picker/round-7.json`; the Magnific downloads are in `temp/sound-round-7/raw/`, the
shaped sources in `temp/sound-round-7/cut/` and the prepared takes in `temp/sound-round-7/takes/`.
Each option's generated takes are levelled to one loudness (`even`, TOOLING.md); the owner's own
sounds ("Yours") are only trimmed and levelled. `now` is the round-5 sound.

| Cue | Options | Shipped (the owner's picks) |
|---|---|---|
| `GulpSuck` | S1 Yours: suck1 (0.39 s), S2 Yours: suck2 (0.45 s), A Quick fwip, B Rising whoop, C Bubble bwip, D Soft breath-in, E Rewound whoosh (0.08 to 0.28 s), now | S1, his suck1: `gulp-suck.wav`, 0.39 s |
| `GulpCatch` | A Soft plop, B Bubble pop, C Cork bloop, D Lip pop, E Gummy boing, F Marimba plip (0.06 to 0.31 s), now | A, Soft plop, its first take only: `gulp-catch.wav`, 0.10 s |
| `GulpSpit` (the throw) | T1 Yours: throwing (0.27 s), T2 Yours: throwing2 (0.36 s), T3 Yours: throwing3 (0.38 s), A Airy whoosh, B Hup and swish, C Spinning whirl, D Whistle whoosh, E Whip swish (0.12 to 0.42 s), now | T, his three throws together ("for throw use my 3 sound alternative"; option T was added for it, levelled to one loudness): `gulp-spit-1` to `-3.wav`, 0.27, 0.36 and 0.38 s |

The picks are `scripts/audio/picker/round-7-picks.json` (the picker's `picks/round-7`, version 17,
with the throw's T1 applied as T); `stage-round.py --picks` wrote the files in
`godot/asset/audio/sfx/library/player/` and kept them as
`asset/Originals/audio/magnific/player-gulp-{suck,catch}-r7-1.wav` and `player-gulp-spit-r7-<n>.wav`,
registered in `cues.mjs`. The suck and the throws are the owner's own sounds
(`asset/audio/CREDITS.md`, source to be recorded).

### 12.1 The cues that borrowed the Gulp's sounds

Other things played `GulpSuck`, `GulpCatch` or `GulpSpit`. They have their own cues now, playing the
round-5 takes, kept as `player/goo-inhale-<n>.wav` (the old suck), `goo-plop-<n>.wav` (the old
catch) and `goo-ptoo-<n>.wav` (the old spit) at the old players' volumes (registered in `cues.mjs`
and `picks.json`), so the new Gulp sounds are the Gulp's alone:

| Cue | Takes | Plays when | Where |
|---|---|---|---|
| `GulpThroat` | goo-inhale | the swallow ring's rising throat sound (its stream pitched up) | `mouth_hold.gd` `THROAT_SOURCE_CUE` |
| `BubbleRise` / `BubblePop` | goo-inhale / goo-ptoo | the prologue's birth bubble rises / pops | `prologue/birth_bubble.gd` |
| `MimicWrap` / `MimicGrab` / `MimicSpit` | goo-inhale / goo-plop / goo-ptoo | the Cocoon Mimic wraps, grabs, spits the slime out | `cocoon_mimic.gd` |
| `PipeWormSpit` | pipe-worm-spit (Sound Picker round 8, 2026-10-19; `PipeWormCharge` is left in `global.tscn`, never played: the charge is silent) | the Pipe Worm spits its glob, its only sound | `pipe_worm.gd` |
| `CrawlerTurn` | crystal-crawler-turn (Sound Picker round 10, applied 2026-11-13: "Chitin scuttle", two takes; the owner did not like the shared `GroundCreak` it played before; levelled as a stroke, -29 dB, so it stays quiet) | the Crystal Crawler twists round a corner of its pillar, heard only where the slime could see it | `crystal_crawler.gd` `CUE_TURN` |
| `SpitcapCharge` / `SpitcapSpit` | goo-inhale / goo-ptoo | the Spitcap charges, spits its seed | `spitcap.gd` |
| `RookSteal` | goo-plop | the Rook Thief steals | `rook_thief.gd` |
| `HeavyBlockGrab` | goo-plop | the slime grabs a heavy block (it played its placeholder `GulpCatch`) | `heavy_grab.gd` |
| `GooBombSpit` | goo-ptoo | the Goo Bomb leaves the mouth (it played its placeholder `GulpSpit`) | `goo_bomb_sequence.gd` |
| `LanternSpit` | goo-ptoo | the Lantern's flame leaves the mouth | `lantern_sequence.gd` |
| `FireIgnite` | goo-ptoo | a burnable or a candle catches fire | `world/fire/burnable.gd`, `candle.gd` |

The ceremony's gulp (`ability_ceremony.gd`) and the bag's Use putting an essence in the mouth keep
`GulpCatch`: they are the mouth catching.

### 12.2 Bringing your own sounds

1. **Drop the files** in `asset/Originals/audio/sounds/` (outside the Godot project; the tools never
   change them). MP3, WAV, OGG or FLAC; mono or stereo (the tools mix them to mono); any sample rate
   (they become 44.1 kHz). Any file name. One sound per file, or several sounds with silence
   between them, which can be cut into takes of one option. Keep the sound itself short: the suck
   under about 0.45 s, the catch under 0.3 s, the throw under 0.4 s. Silence before and after is
   trimmed; add `"max": <seconds>` to the option to cut it shorter.
2. **Add an option** to the cue in the open round's manifest, like round 7's "Yours" ones. Round 7
   is applied, so start a new round (`scripts/audio/picker/round-8.json`, with its own `round` and
   `takes` folder) from round 7's cue, keeping the shipped option so it can be compared:
   `{"key": "s3", "label": "Yours: <name>", "note": "...", "kind": "oneshot", "takes":
   ["asset/Originals/audio/sounds/<file>"]}` (several files in `takes` are variants the game picks
   among). To hear it in the game first, set the cue's `inGame` to its key.
3. **Stage it**: `python scripts/audio/prep-takes.py <manifest>`, then
   `python scripts/audio/picker/build-picker.py <manifest> <out.html>` for the picker page and
   `python scripts/audio/stage-round.py <manifest>` for the game (it measures the loudness and sets
   the player's volume). Let the Godot editor import the new files (or run one headless `--import`
   while the editor is closed), then play with `?audition` (F7 / F8).

The names that must stay are the game's: the players `GulpSuck`, `GulpCatch` and `GulpSpit` under
`Effects` in `game/scenes/audio/global.tscn`, and their files `player/gulp-suck[-<n>].wav`,
`gulp-catch[-<n>].wav`, `gulp-spit[-<n>].wav`, which `stage-round.py` writes (`<cue>.wav` for one
take, `<cue>-<n>.wav` for several). A quick swap without the tools: overwrite one of those WAVs with
a mono or stereo 16-bit WAV of the same name (keep the count of files), and let the editor import
it; its volume stays the one measured for the old take, so re-stage when the level differs.

---

## 13. Round 11: the throw's toss and kill

Opened and applied 2026-11-16. The owner on the throw: "it was a strong hit and the monster got
pushed back with nice effects and sounds" (Zelda). Until this round a liftable's throw played
`GulpSpit` and a kill only the enemy's own death sound. Manifest `scripts/audio/picker/round-11.json`,
picks `round-11-picks.json` (the picker's `picks/round-11`, version 45). The cues are named in
`gulp.throwFeel.cues` of `game-constants.json` and played by the throw's feel code while
`gulp.throwFeel.enabled` is on (`game/throw/throw_feel.gd`, `mouth.gd`, `thrown_object.gd`;
[THROW_COMBAT.md](../THROW_COMBAT.md)).

| Cue | Plays when | Options | Shipped (the owner's picks) |
|---|---|---|---|
| `ThrowToss` | a liftable is thrown (an essence spat out whole keeps `GulpSpit`) | A Quick whup, B Airy swish, C Slingshot fwip, D Synth: springy fling, now: his three throws (`GulpSpit`'s takes) | A, its third take alone: `player/throw-toss.wav`, 0.105 s, a dry mid swish (centre 0.8 kHz, loudest 38 ms in). One take on every throw, so its player's pitch randomness is 0.08 (the kind's is 0.06) |
| `ThrowKill` | a throw kills; the game raises its pitch with each kill of a chain (the `pitch` payload), so its player has no pitch randomness | A Pop and tinkle, B Bell ting, C Cork pop and glitter, D Synth: blip and glass note | A, its first take alone: `player/throw-kill.wav`, 0.25 s, a round pop (0.8 kHz) then tiny bells near 8.6 kHz |

**No body-blow cue.** The round also offered `ThrowImpact` and `ThrowImpactHeavy`, a thump under the
material's break sound for a thrown thing striking an enemy (light or medium, and heavy). The owner
picked neither, on purpose: "i believe the hit sound depends of the object that hits, already the
pot make a sound when it breaks on an enemy and that should be enough, the other materials should
have their sound as much as possible, that will give identity to each type of material." Their
players, files and audition copies are removed; the thrown thing's own material cue is the hit
sound (§11, §14). Their options stay in the manifest and in `temp/sound-round-11/` as the record.

Options A to C were Magnific (ElevenLabs) sound effects, 19 prompts of four one-second takes each
(`temp/sound-round-11/raw/`), cut to their attack and length by `scripts/audio/shape-takes.py`
(`scripts/audio/picker/round-11-shape.json`); D was the game's own synth
(`scripts/audio/picker/round-11-synth.mjs`). The shipped takes are kept as
`asset/Originals/audio/magnific/player-throw-toss-r11-1.wav` and `player-throw-kill-r11-1.wav` and
registered in `cues.mjs` and `picks.json` ([TOOLING.md](../../TOOLING.md#sound-picker-rounds)).

---

## 14. Round 12: each material its own sound

Opened 2026-11-16, applied 2026-11-17, after the owner's note on round 11 (§13). Manifest
`scripts/audio/picker/round-12.json`, picks `round-12-picks.json` (the picker's `picks/round-12`,
version 17). The Magnific downloads are in `temp/sound-round-12/raw/` (13 prompts of four
one-second takes), the cut sources in `temp/sound-round-12/cut/`
(`scripts/audio/picker/round-12-shape.json`), the prepared takes in `temp/sound-round-12/takes/`.

Snow, crystal and bone borrowed the soft, glass and wood cues; each has its own player now, named
by `thrown_object.gd` `BREAK_CUES`. Four round-5 cues had options because they measured weak as hit
sounds: stone and ice start with small clicks and their loudest crack comes 63 to 166 ms in, and
wood and soft each had one take 8 to 10 dB quieter than its others.

| Cue | Options | Shipped (the owner's picks) | Player |
|---|---|---|---|
| `BreakSnow` | A Crunch and poof, B Powder puff, C Squeaky crunch, now: the soft splat | A, all three takes: `world/break-snow-<n>.wav`, 0.37 to 0.43 s | +0.70 dB (the rule asks +2.6) |
| `BreakCrystal` | A Crack and ring, B Chiming shards, C Glitter shimmer, now: the glass shatter | now, its second take alone: crystal keeps the glass sound, as its own file `world/break-crystal.wav` (0.58 s), so a later change to glass does not change it | -0.94 dB, pitch randomness 0.08 |
| `BreakBone` | A Clack and rattle, B Hollow clack, C Bone rattle, now: the crate smash | C, its second take alone: `world/break-bone.wav`, 0.27 s | +0.70 dB (the rule asks +3.1), pitch randomness 0.08 |
| `BreakStone` | now; T Yours, started on the crack; A Hard crack and crumbs; B Gritty crumble | A, all three takes: `world/break-stone-crack-<n>.wav`, 0.29 to 0.34 s, the crack within 5 ms. The round-5 `break-stone-<n>.wav` stay: three enemy scenes play them | +0.70 dB (the rule asks +2.3; it was +4.12 with the old takes) |
| `BreakIce` | now; T Yours, started on the crack; A Sharp crack and shards; B Icicle snap | now, without its first take: `break-ice-2.wav` and `break-ice-3.wav` (the file of take 1 stays: the Prism Eye plays it) | +4.08 dB (it was +3.42) |
| `BreakWood` | now; T Yours, one loudness | now, without its quiet first take: `break-wood-2.wav` and the old third take, now `break-wood-1.wav` (the old first is deleted) | -8.56 dB (it was -5.02) |
| `BreakSoft` | now; T Yours, one loudness | now, its second take alone: `break-soft-2.wav` (takes 1 and 3 stay: 17 enemy and projectile scenes play them) | +4.10 dB (the rule asks +7.3; it was +2.01), pitch randomness 0.08 |

Glass, clay and metal were not in the round and are unchanged.

**Levels.** Each player's volume follows the loudness rule (the takes' loudest 100 ms at -17 dB),
held lower where the peaks would go over full scale, since the buses have no limiter
(`stage-round.py` `PEAK_CEILING_DB`, `KEPT_MAX_DB`; [TOOLING.md](../../TOOLING.md#sound-picker-rounds)).
The new takes (snow, bone, stone) peak at -0.3 dBFS after the volume, so they sit 1.6 to 2.4 dB
under the rule. The owner's kept takes are not altered: ice plays at the rule's volume and soft at
+4.1 dB, the most a break player had before this round; both peak about 3 dB over full scale, as
his stone and ice did before. Soft's one take is the quiet one of its three: it plays 2.1 dB louder
than it did and measures 3.2 dB under the rule. A limiter on the Effects bus would let every player
take the rule's volume.

**Files other scenes play.** Enemy and projectile scenes name some break files by path as their
hurt and death sounds (`break-soft-<n>`: 17 scenes; `break-stone-<n>`: crystal-colossus, shardback,
watcher-eye; `break-ice-1` and `-2`: prism-eye; `break-wood-2`: the three bone enemies; glass: five
crystal enemies). Those files are untouched, so those enemies sound as before; only the global
players changed. The shipped takes of the new and changed cues are kept as
`asset/Originals/audio/magnific/world-break-{snow,crystal,bone,stone-crack}-r12-<n>.wav` and
registered in `cues.mjs` and `picks.json`; nobody had listened to the takes before the owner did.

---

## 15. Round 13: the beetle and the bubble

Opened 2026-11-21, applied 2026-11-22 with `round-13-picks.json` (the picker's `picks/round-13`,
version 57, final; every cue picked, none Neither, no note). The owner, on the Dung Roller: "we need
to work on the sound effects of the beetle i dont like it"; then, on the slime's `SlamWindup` bubble
(`library/player/slam-windup.ogg`, a rubberduck-slime bubble) that ten enemies borrowed for their
wind-ups: "why is use that much i don't like at all, lets pick sound for all those". Manifest
`scripts/audio/picker/round-13.json`, written by `round-13-make.py`. The Magnific downloads are in
`temp/sound-round-13/raw/` (63 prompts of four one-second takes, the ore lift's two seconds; `ids.json`
and `ids2.json` map them to the creations), trimmed by `prep-takes.py` to their loudest event and
each cue's `max` length (no shape file), the prepared takes in `temp/sound-round-13/takes/`. Each
cue had three new options of four takes and "now", what it played before. The shipped takes are
`library/<category>/<cue>[-<n>].wav` (players under `Effects` in `global.tscn`), kept as
`asset/Originals/audio/magnific/<category>-<cue>-r13-<n>.wav` and registered in `cues.mjs` and
`picks.json`.

| Cue | Plays when | Where | Played before |
|---|---|---|---|
| `DungBrace`, `DungPush`, `DungBump`, `DungFury`, `DungCharge`, `DungBall`, `DungHurt`, `DungDeath` | the Dung Roller ([BESTIARY.md](../BESTIARY.md)) | `dung_roller.gd` | `SlamWindup`, `RollLaunch`, `RollBonk`, `SlamWindup`, `RollLaunch`, `DropPop`, its scene's hit-dull and break-soft-1 players |
| `BoarScrape` | the Bramble Boar scrapes before its charge | `bramble_boar.gd` | `SlamWindup` |
| `WardenWindup` | the Brood Warden pulls its blades back | `brood_warden.gd` | `SlamWindup` |
| `StomperCrouch` | the Clod Stomper crouches before its stomp | `clod_stomper.gd` | `SlamWindup` |
| `ColossusRaise` | the Crystal Colossus lifts a fist | `crystal_colossus.gd` | `SlamWindup` |
| `PrismCharge` | the Prism Eye and the Watcher Eye charge their beam | `prism_eye.gd` | `SlamWindup` |
| `ChuckerWindup` | the Rock Chucker heaves its boulder | `rock_chucker.gd` | `SlamWindup` |
| `ShardbackRear` | the Shardback rears up | `shardback.gd` | `SlamWindup` |
| `SquintRear` | the Squint and the Big Squint rear up | `squint.gd` | `SlamWindup` |
| `ThornballCurl` | the Thornball curls up (and cowers from a Goo Bomb) | `thornball.gd` | `SlamWindup` |
| `SlamRise` | the slime springs up for a Slam | `slam_sequence.gd` (it was a placeholder for `SlamWindup`), `classic_slam_sequence.gd` | `SlamWindup` |
| `GooBombCast` | the slime forms a Goo Bomb (silent since 2026-11-24: the bomb has no cast, `castMs` 0) | `goo_bomb_sequence.gd` (a placeholder for `SlamWindup`) | `SlamWindup` |
| `HammerSwing` | the Hammer shape swings | `shape_controller.gd` `SWING_CUES` | `SlamWindup` |
| `OreLiftRide` | the Crystal Mine's ore lift rides | `ore_lift.gd` | `SlamWindup` |

**Shipped** (the owner's picks; takes he struck out are not shipped):

| Cue | Pick | Takes | Player |
|---|---|---|---|
| `DungBrace` | C Feet scrape | its second alone | +7.0 dB, pitch randomness 0.08 (one take, every few seconds) |
| `DungPush` | B Mud shove | all four | +0.7 dB |
| `DungBump` | B Wet splat-thud | all four | +0.7 dB |
| `DungFury` | B Angry chitter | all four | -3.6 dB |
| `DungCharge` | B Wing-case whirr | 3 and 4 | -2.4 dB |
| `DungBall` | B Mud squish | all four | +0.7 dB |
| `DungHurt` | B Knock and squeak | 2 to 4 | +0.7 dB |
| `DungDeath` | B Squeal and topple | all four | -4.5 dB |
| `BoarScrape` | B Hoof scrape | 2 and 4 | -2.6 dB |
| `WardenWindup` | C Leg clicks and chitter | 2 to 4 | +0.7 dB |
| `StomperCrouch` | A Mud squelch and pebbles | all four | -3.4 dB |
| `ColossusRaise` | A Crystal grind | its second alone | -4.5 dB |
| `PrismCharge` | C Power-up whine | 1 and 2 | -3.3 dB |
| `ChuckerWindup` | C Effortful growl | its second alone | -5.2 dB |
| `ShardbackRear` | C Tired old grunt | its second alone | -6.5 dB |
| `SquintRear` | C Growl and scuff | 2 to 4 | -4.2 dB |
| `ThornballCurl` | C Grumpy huff | 2 and 3 | -4.1 dB |
| `SlamRise` | B Wobbly stretch | 3 and 4 | -5.8 dB |
| `GooBombCast` | C Bomb armed | its second alone | +0.7 dB |
| `HammerSwing` | A Deep whoosh | all four | -9.0 dB |
| `OreLiftRide` | A Pulley and chains | all four | -2.5 dB |

Volumes follow the loudness rule, held at +0.7 dB where it would push the peaks over full scale
(§14). **`SlamWindup` is gone**: its player, `library/player/slam-windup.ogg`, its `cues.mjs` entry
and its `picks.json` line; `slam_sequence.gd` and `goo_bomb_sequence.gd` no longer fall back to it.
The manifest's "now" options still name that file, as the record of the round.

## 16. Round 14: the Carnivore Plant

Opened and applied 2026-11-22 with `round-14-picks.json` (the picker's `picks/round-14`, version 21,
final; every cue picked, none Neither, no note). The owner, on the Carnivore Plant (bestiary row 38, [BESTIARY.md](../BESTIARY.md)):
"use the sound play to give me some sound for here". Manifest `scripts/audio/picker/round-14.json`,
written by `round-14-make.py`; the Magnific (ElevenLabs) downloads in `temp/sound-round-14/raw/` (24
prompts of four takes, one second each, the burn's two; `ids.json` and `urls.json` map them to the
creations), trimmed by `prep-takes.py` to their loudest event and each cue's `max` length, the
prepared takes in `temp/sound-round-14/takes/`, the page published to the Sound Picker artifact
(version 19; 560 credits). Each cue has three new options of four takes and "now", what she played
before. The shipped takes are `library/enemy/plant-<cue>[-<n>].wav` (players under `Effects` in
`global.tscn`), kept as `asset/Originals/audio/magnific/enemy-plant-<cue>-r14-<n>.wav` and registered
in `cues.mjs` and `picks.json`; `carnivore_plant.gd` plays them. Her scene's old death player
(`break-soft-1.wav`) is gone, as `PlantBurn` covers her death.

| Cue | Plays when | Played before |
|---|---|---|
| `PlantOpen` | she rears up, jaws wide (the tell) | `MimicWrap` (a goo inhale) |
| `PlantSnap` | her jaws snap shut | `MimicGrab` (a goo plop) |
| `PlantMunch` | each chew: the slime (one, 20 damage) or an enemy (two) | `MimicGrab` |
| `PlantSwallow` | she swallows an enemy | `GulpThroat` (a goo inhale) |
| `PlantBurp` | the burp after the swallow | `GulpBurp` (the slime's burp) |
| `PlantSpit` | she spits the slime far | `MimicSpit` (a goo ptoo) |
| `PlantDoze` | a thrown thing puts her to sleep | `SleepBreath` |
| `PlantBurn` | the Lantern's flame burns her | `FireIgnite` (a goo ptoo) and the scene's soft splat |

**Shipped** (the owner's picks; takes struck out are not shipped):

| Cue | Pick | Takes | Player |
|---|---|---|---|
| `PlantOpen` | A Hungry hiss | its first and fourth | +6.0 dB (the loudness rule asked +6.6, held for headroom) |
| `PlantSnap` | A Wet chomp | its first three | +0.7 dB |
| `PlantMunch` | B Squishy chew | its first and fourth | +0.7 dB |
| `PlantSwallow` | A Big gulp | its last three | -8.0 dB |
| `PlantBurp` | C Smug burp and chuckle | its first three | +0.7 dB |
| `PlantSpit` | B Goo blast | its first alone | -1.4 dB |
| `PlantDoze` | A Woozy yawn | its first, second and fourth | -6.3 dB |
| `PlantBurn` | A Flame and shriek | all four | -8.3 dB |

## 17. Round 15: the dungeon mechanisms

Opened and applied 2026-11-23 with `round-15-picks.json`, **without the owner**: these are the
builder's defaults for the knock target, the ram and the runaway cart
([DUNGEONS.md](../DUNGEONS.md#mechanisms-the-knock-target-the-ram-the-runaway-cart)), shipped so the
mechanisms are not silent. He has not heard or picked them, and no picker page was published.
Manifest `scripts/audio/picker/round-15.json`, written by `round-15-make.py` (the prompts are in
it); the Magnific (ElevenLabs) downloads in `temp/sound-round-15/raw/` (ten prompts, 22 takes, one
second each, the cart's loop two; `urls.json` maps them to the creations; 115 credits), trimmed by
`prep-takes.py` to their loudest event and each cue's `max` length. Each cue has ONE option, "a".
To let him pick, add options to the manifest, stage the round without `--picks` and publish the
picker page, as the earlier rounds did. The shipped takes are `library/world/<cue>[-<n>].wav`,
kept as `asset/Originals/audio/magnific/world-<cue>-r15-<n>.wav` and registered in `cues.mjs` and
`picks.json`. `stage-round.py` knows `world.cart-roll` as a loop.

**The players name packed copies, not the WAV files.** The round was applied while an editor held
the project, and a WAV the editor has not imported yet cannot be loaded by a game run: with one such
take named in it, `global.tscn` does not load at all and every global cue is silent (seen on
2026-11-23: `load("res://game/scenes/audio/global.tscn")` returned null in a film run). So
`tools/pack_cue_sounds.gd -- --cues=world/knock-target-hit,...` saved each take as a native
`AudioStreamWAV` resource, `godot/asset/audio/sfx/packed/world/<cue>[-<n>].res` (a folder
`pnpm audio:bake` does not prune), and the ten players under `Effects` in `global.tscn` name those.
They need no import. The WAV files stay in `library/world/` as the audio tools' record; once a
later round stages these cues again (`stage-round.py` writes `.wav` paths) the packed copies can go,
provided the editor imports the new takes before a game runs outside it.

| Cue | Plays when | Where | Takes | Player |
|---|---|---|---|---|
| `KnockTargetHit` | a thrown thing, an arrow or a blast knocks the target (6 dB quieter on a slack one) | `knock_target.gd` | 3 | -5.3 dB |
| `KnockTargetTap` | the Spear, a Roll or the slime's body only knocks on it (700 ms apart at most) | same | 2 | +0.7 dB |
| `KnockTargetRearm` | its mechanism is ready: the target snaps upright | same | 2 | +0.7 dB |
| `RamWindup` | the ram is let go: the 0.35 s shudder | `ram.gd` | 2 | +0.1 dB |
| `RamSwing` | the log swings out | same | 2 | -8.0 dB |
| `RamThud` | the swing's end | same | 3 | -4.8 dB |
| `RamRatchet` | each tooth of the ram's winch back (every 500 ms for 8 s) and of the cart's haul back (every 400 ms) | `ram.gd`, `ram_cart.gd` | 3 | +0.7 dB |
| `CartBrake` | the cart's brake snaps off; again, lower, when the chock drops back | `ram_cart.gd` | 2 | -0.3 dB |
| `CartRoll` (loop) | the cart rolls (pitch 0.8 to 1.3 with its speed) and is hauled back (0.6) | same | 1 (option b) | -1.0 dB |
| `CartBump` | the cart reaches its buffer stop or stops against something | same | 2 | -5.1 dB |

The bricked arch plays `BreakStone` and the rail gate `BreakWood`, each followed by `SecretFound`.
Volumes follow the loudness rule, held at +0.7 dB where it would push the peaks over full scale.

**Redone on 2026-11-24** (the review of step 1, 50 Magnific credits), still without the owner:

- **`CartRoll`, option "b"** (in the game; option "a" stays in the manifest for the picker): the
  first take was the quietest of the round, half near-silent, with almost no low end. Two new
  five-second looping takes (`raw/cart-roll-b-1.mp3`, `-b-2.mp3`; the prompt is in
  `round-15-make.py`'s `EXTRA`); b-2 drops out in its middle and is not used. b-1's steady part
  (from 1.4 s) was levelled, its last 0.3 s crossfaded into its start (a 3.3 s loop, the seam within
  0.6 dB) and written as `cut/cart-roll-b-1.src.wav`, the library's `world/cart-roll.wav` and
  `asset/Originals/audio/magnific/world-cart-roll-r15b-1.wav` (`cues.mjs` names it). It holds
  between -23.5 and -18.5 dB per 100 ms, a tenth of its energy under 200 Hz, a clatter about every
  100 ms. Its loudness is `stage-round.py`'s `CUE_TARGET_DB` -19 dB (2 dB under the one-shots'
  -17, since it is held), not the loops' -26: the player is at -1.0 dB.
- **The tails of `ram-windup-2`, `ram-ratchet-2` and `-3`** were cut off (a 30 ms straight fade
  on a sound still ringing): each now dies away in a longer curved fade (60 ms, 40 ms), in the
  library, the kept originals and the picker's takes alike. Their players' volumes are unchanged.
- The packed copies were written again (`tools/pack_cue_sounds.gd --
  --cues=world/cart-roll,world/ram-windup,world/ram-ratchet`).

## 18. Round 16: the two bosses

The reworked Orb-Weaver Matron's and Crystal Colossus's own sounds (step 2 of the
[dungeons 2 and 3 rework](../../design/2026-11-23-dungeons-2-3-rework.md#the-bosses)), made
2026-11-24 with their frames, published on the Sound Picker page and **picked by the owner** the
same day (`round-16-picks.json`: every cue its option "a"; he struck out the second take of the hiss
and of the shriek). Manifest `scripts/audio/picker/round-16.json`, written by `round-16-make.py` (the
prompts are in it); the Magnific (ElevenLabs) downloads in `temp/sound-round-16/raw/` (eleven
prompts, two takes each, two seconds, the roar three; `urls.json`; 230 credits). Applied with
`stage-round.py --picks`: the takes are `library/boss/<cue>[-<n>].wav`, kept as
`asset/Originals/audio/magnific/boss-<cue>-r16-<n>.wav`, registered in `cues.mjs` and `picks.json`;
as round 15's, the players name packed copies (`asset/audio/sfx/packed/boss/*.res`, written by
`tools/pack_cue_sounds.gd`), so they play before the editor imports the WAV files.

| Cue | Plays when | Where | Takes | Player |
|---|---|---|---|---|
| `MatronHiss` | she dives, and when she spits her glob at a knock target (her ram call) | `game/bosses/matron_ram.gd` | 1 | -4.8 dB |
| `MatronShriek` | a ram catches her, knocks her cocoon down; a blast tears it | same | 1 | -6.8 dB |
| `MatronImpact` | her dive lands, she crashes on her back, a cocoon hits the floor | same | 2 | -9.1 dB |
| `ColossusStomp` | his stomp lands (also his landing) | the Colossus's plate fight | 2 | -6.8 dB |
| `ColossusRoar` | he wakes, a plate bursts, he leaps onto the wall | same | 2 | -9.6 dB |
| `ColossusShatter` | a cart bursts a hot plate | same | 2 | -3.5 dB |
| `ColossusClang` | a cart clangs off a cold plate | same | 2 | -6.5 dB |

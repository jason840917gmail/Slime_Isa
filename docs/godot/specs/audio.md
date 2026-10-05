# Audio spec — music director, global cues, buses

Source of truth: the Phaser code at `feat/godot-migration`. Everything below is read from code;
file:line references are to `src/game/...` unless they start with `godot/` or `node_modules/`.
A GDScript engineer should be able to port this without opening the TypeScript.

Godot targets: autoload `MusicDirector` → `res://game/audio/music_director.gd` (reached as
`Services.music()`); global cues stay on `GameFeel.audio_cue(cue)` (`game/feel/game_feel.gd`);
converted audio players stay on `game/runtime/sfx_player(_2d).gd` (runtime spec 4.12); buses
`Master`, `Effects`, `Music`, `Ambience` (`godot/default_bus_layout.tres`).

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
| `gloop-hut`, `mushroom-home`, `slime-home` | — | `audio.sfx.world.interior-ambience.1`, volume 0.35 |
| every other world | — | — |

`audio/global.scene.json` (`audio.global`, root `GlobalAudio`):
- `Music/BossMusic`: `music.level-1-home-town` again, bus `music`, `loop`, volume 0.5,
  **pitch 1.12**, polyphony 1, no autoplay. The only boss track.
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
  others have none (`world` undefined).
- **Boss track** = `Music/BossMusic` of the mounted `audio.global` scene (`:801-806`), undefined
  if missing.
- **Ambience** is not driven: it autoplays at its authored volume, is never ducked (the duck is on
  the `music` bus only) and is never faded; the page reload cuts it.

The music bus has no other users (only these three nodes in all authored scenes set `bus: music`).

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
Godot: `GameFeel.audio_cue(cue)` plays the same node (it searches the whole `GlobalAudio` tree,
`game_feel.gd:143-155`; no cue name repeats outside `Effects`, so this is equivalent).

| Phaser event (emitter) | Cue | Godot |
|---|---|---|
| `area.enter` (`WorldScene.ts:515`, every world arrival outside title mode) | `AreaTransition` | **MusicDirector** on `WorldService.world_registered` (§7.4) |
| `boss.defeated` (`UniversalSceneWorldController.ts:596-600`) | `Victory` | `boss_camp.gd:319-330` (ported) |
| `player.respawn` (`core/GameState.ts:216-219`) | `Respawn` | `player.gd` (ported) |
| `weapon.critical-hit` (`features/combat/CombatController.ts:216`) | `Crit` | `player_combat.gd:223` (ported) |
| `player.action {anim}` (`AudioEventBridge.ts:30-42`): `dodge` → `Dodge`, `ability-denied` → `AbilityDenied` | as listed | `player.gd` (ported) |
| `player.action`: `eat` → `Eat`, `ability-jump` → `Jump`, `jump-land` → `Land`, `ability-teleport` → `TeleportOut`, `teleport-in` → `TeleportIn`, `ability-squash-slam` → `SlamWindup`, `slam-impact` → `SlamImpact`, `ability-stretch-lash` → `Lash` | as listed | abilities ([abilities.md](abilities.md) §16) |
| `ability.learned` (`features/progression/StoryProgress.ts`) | `AbilityLearned` | abilities |
| `ground.cracked`, `lash-bell.rung`, `web.torn`, `building.restored`, `building.restore-refused {reason:'missing-materials'}`, `goo-heart.collected` (`WorldScene.ts`) | `GroundCrack`, `BellRing`, `WebTear`, `BuildingRestored`, `CraftFail`, `Heal` (placeholder) | abilities / world objects |
| `energy.changed {delta ≥ 20}` (`GameState.ts`) | `EnergyRestore` (also on every respawn refill) | abilities (energy) |
| `player.heal {source ≠ 'rest'}` (`GameState.ts`) | `Heal` | inventory (consumables) |
| `coins.changed {delta > 0}` (`GameState.ts:108-112`) | `Coin` | inventory |
| `weapon.equipped {weaponId}` (`GameState.ts:169-173`, also on restore/reset `:82, 92`) | `EquipBlade` if the id matches `sword\|spear`, else `EquipTool`; nothing for `null` | inventory (weapon switching) |
| `craft.completed` / `craft.failed` (`crafting/Crafting.ts`, `features/ui/CraftingSurfacePort.ts`) | `CraftSuccess` / `CraftFail` | crafting |
| `npc.talked` (`features/interaction/QuestNpcController.ts`) | `NpcBlip` | dialogue |
| `quest.accepted` / `.progressed` / `.stage-completed` / `.completed` / `.failed` (`quests/QuestService.ts`) | `QuestAccept` / `QuestProgress` / `QuestProgress` / `QuestComplete` / `QuestFailed` | quests |
| `status.added {kind}` / `status.removed` (`systems/StatusEffects.ts`) | `StatusBurn` … `StatusFrenzy` / `StatusExpire` | status effects (not ported) |
| `player.sleep {asleep}` / `player.rested` (`WorldScene.ts`) | `SleepBreath` play / stop, `Rested` | sleep (not ported) |
| any modal opens / closes (`ui/ModalStack`, `AudioEventBridge.ts:104-109`) except `chest-inventory` and `furniture-placement` | `JournalOpen` for `quest-journal`, else `MenuOpen`; `MenuClose` | shell / UI (each menu that opens or closes) |

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
is still audible, Phaser's rule). The boss track is not restarted; with no engaged camp it fades
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

---

## 8. Edge cases
- A world without music (`gloop-hut`): no world track; a boss fight there still brings in the
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
- Boss: walking into the camp starts `BossMusic` (pitch 1.12, base 0.5); 600 ms → 0.5 / 0.5,
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

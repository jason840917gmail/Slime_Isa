# Shell spec: title, pause, settings, controls, credits, area titles, game over, end cards

The game's frame around play, as the Phaser build behaves today, and how the Godot port does it.
Phaser sources are under `src/game/`; line numbers are for the commit this port was written
against. Godot files: `godot/game/shell/` (scenes and scripts), `godot/game/ui/theme/` and
`godot/tools/build_ui_theme.gd` (the look, [UI_THEME.md](../UI_THEME.md)), `godot/tests/test_shell.gd`.

Tags: **[IN]** ported, **[OUT]** not yet (with the reason), **[DIFF]** deliberate difference.

## 0. Pieces

| Phaser | Godot |
|---|---|
| `features/shell/GameShell.ts` (owns the menus, wires them to the world) | `game/shell/shell.gd`, autoload `Shell` (registration pending, see ARCHITECTURE §2); `Services.shell()` |
| `features/shell/MenuSurface.ts` (open/close, pause source, modal-stack entry) | `game/shell/shell_menu.gd` (base of every window) + the Shell's window stack |
| `ui/ModalStack.ts` (Escape closes the top surface) | `Shell.handle_escape()` from `_unhandled_input` |
| `TitleSurfacePort.ts` + `ui/title-screen.scene.json` + WorldScene title mode | `title.tscn` / `title.gd` (the project's main scene once registered) |
| `PauseMenuSurfacePort.ts` + `ui/pause-menu.scene.json` | `pause_menu.tscn` / `.gd` |
| `SettingsSurfacePort.ts`, `features/settings/GameSettingsService.ts`, `infrastructure/persistence/GameSettingsStore.ts` + `ui/settings.scene.json` | `settings_menu.tscn` / `.gd`, `game_settings.gd` (`GameSettings`) |
| `ControlsSurfacePort.ts`, `features/player/ControlLabels.ts` + `ui/controls.scene.json` | `controls_menu.tscn` / `.gd`, `control_labels.gd` (`ControlLabels`) |
| `CreditsSurfacePort.ts`, `content/credits/credits.json` + `ui/credits.scene.json` | `credits_menu.tscn` / `.gd` |
| `features/ui/AreaTitleSurfacePort.ts` + `ui/area-title-card.scene.json` | `area_title_card.tscn` / `.gd`, `area_titles.gd` (`AreaTitles`) |
| `GameOverSurfacePort.ts` + `ui/game-over.scene.json` | `game_over.tscn` / `.gd` |
| `EndCardSurfacePort.ts`, `content/story/endCards.ts` + `ui/end-card.scene.json` | `end_card.tscn` / `.gd` |
| `SaveSlotsSurfacePort.ts` + `ui/save-slots.scene.json` | **[OUT]** owned by the saves work; it plugs in with `Shell.set_action(&"save"/&"load", ...)` |

**Feature windows on the shell.** A feature whose window belongs to the shell's stack (the
save-slots window) mounts it once with `Shell.mount_menu(scene: PackedScene) -> ShellMenu` (the
scene's root must extend `shell_menu.gd`; null otherwise or before the Shell's `_ready`), opens it
with `open_menu(menu)` and can close every shell window with `close_all_menus()` (top first, e.g.
before `Main.load_run`). Mounted windows get Escape, focus and the `shell:<surface id>` pause
reason like the shell's own, and sit below the quit fade. Game windows that are not part of the
shell (bag, crafting, journal, world map) go through `GameWindows` instead.

All shell scenes are Godot-owned (hand-made from the converted `ui.*` scenes, CONVENTIONS "Scenes
Godot owns"); they are loaded by path, not by scene id. Each window is a full-screen Control that
stops the mouse (the world behind takes no clicks) around a `ModalPanel` panel with Phaser's size.
Every button plays `sfx.ui.click`, the settings sliders `sfx.ui.hover`, as the converted scenes'
connections do.

## 1. Title flow

Phaser:
- Title mode is on for the first world of a page load unless it came from an area hand-off or the
  dev `?map=` preview (`WorldScene.ts:303-304`). Behind the title the world is built on a throwaway
  run that is never saved (`:305-312`), with no player or HUD; the camera drifts
  (`panTitleCamera`, `:1600-1605`): centre = spawn + (160, 120) + (sin(t / 60 s · 2π) · 360, 0)
  (`:161-164`), clamped by the world bounds.
- The menu (`TitleSurfacePort.ts:49-61`): logo, tagline, New Game (accent), Continue (disabled
  without a run to continue), Load (disabled without anything loadable), Settings, Credits (muted),
  a warning status line, the version `v0.1.0` (`WorldScene.ts:166`). Escape never closes it
  (`:35`).
- New Game (`:63-71`): with an autosave it asks "Start a new game? Your autosave will be replaced.
  Save slots are kept." with Start new game (danger) / Cancel (muted); otherwise, or on confirm, the
  status reads "Starting…" and `saveSystem.resetRun()` reloads into the start area.
- Continue loads the newest run (`SaveSystem.continueLatest`), Load opens the save slots, Settings
  and Credits open those windows on top.

Godot:
- **[IN]** `title.gd` skips straight to `res://game/main.tscn` when the launch has any development
  option main.gd reads: `map`, `spawn`, `weapon`, `quest`, `recipes`, `arsenal` or `skip-title`
  (desktop `-- --map=level-1`, web `?map=level-1`; `LaunchOptions.SKIP_TITLE_OPTIONS`).
- **[IN]** The backdrop: `world.level-1` instanced under `Title/Backdrop` and registered with
  WorldService (water, areas; the Shell shows no area card because no `world_main` node exists),
  NPCs wander (**[DIFF]** Phaser's title is a pause source, so its world stands still), the
  camera drifts as above with the world rect as limits, and the music plays ducked
  (`MusicDirector.set_menu_paused(true)` while the title shows). The run is
  `RunState.ensure_started()` (thrown away by New Game, replaced by Continue). Leaving the title
  calls `WorldService.clear()` before `change_scene_to_file(main.tscn)`.
- **[IN]** New Game: confirmation only when `RunState.has_save(0)`; then `RunState.new_run()` and
  main.tscn. **[DIFF]** Continue is hidden (not disabled) without `has_save(0)`, and loads with
  `RunState.load_slot(0)` ("That save could not be loaded." on failure). Load shows only when a save
  window registered `Shell.set_action(&"load", ...)`. The panel keeps Phaser's 380 px width and
  shrinks to the visible buttons.
- `title.gd` uses `Services.shell()`, or makes its own Shell child while the autoload is not
  registered, so Settings and Credits work either way.

## 2. Pause rules

Phaser:
- Escape (`PauseMenuSurfacePort.ts:66-73`) opens the pause menu only when nothing else consumed
  the key, no surface is open in the modal stack, the key did not come from a text field and
  `canOpen()`: not title mode, not travelling, the player not dead, no furniture placement
  (`WorldScene.ts:543-544`). Otherwise the modal stack closes its top surface when it may be
  closed (`ModalStack.ts:130-144`; title, game over and end card refuse).
- Every shell menu is a pause source while open (`GameShell.ts:59`,
  `WorldScene.setSimulationPaused`, `:750-770`): the simulation stops while any source is set.
- Buttons (`PauseMenuSurfacePort.ts:45-58`): Resume (accent) closes; Journal, Inventory and Map
  close the menu and open that window; Settings, Save and Load open on top (closing them returns
  here); Quit to Title (muted) closes and calls `quitToTitle`. The hint reads "Esc resumes"
  (`:41-43`); Load is disabled with nothing to load.
- Quit to Title (`WorldScene.ts:645-650`): writes the recovery autosave, fades the camera and music
  out over 320 ms (`AREA_LEAVE_FADE_MS`, `:128`, `leaveAreaThen` `:1012-1016`) and reloads the page
  to the title (`AreaNavigation.returnToTitle`).

Godot:
- **[IN]** `Shell._unhandled_input` hears `pause` / `ui_cancel` (Escape). Game windows that
  want Escape consume it first (they sit in main.tscn, which gets unhandled input before the
  autoloads). `handle_escape()`: an open shell window is closed when `closable_by_escape`, else the
  key is swallowed; with none open, `open_pause()` when `can_open_pause()`: a node in group
  `world_main` exists, it is not `is_transitioning()`, the player is not `is_dead()`, no quit is
  under way.
- **[IN]** Pause = `WorldService.set_pause_reason(&"shell:<surface id>", true)` per open window
  (`shell:pause-menu`, `shell:settings`, ...), so a hit-stop ending never resumes a menu. Without a
  WorldService the Shell sets `get_tree().paused`. The Shell's layer and windows are
  PROCESS_MODE_ALWAYS. When the last window closes the player's buffered presses are dropped
  (`PlayerScript.clear_input()`), standing in for Phaser's modal key trap.
- **[IN]** Buttons as above. Journal, Inventory, Map run `Shell.set_action` handlers (registered
  by the game windows) and are disabled until one exists. **[DIFF]** Save / Load use the `save` /
  `load` actions when registered; until then Save calls `RunState.save_slot(0)` and shows "Game
  saved" / "Could not save" in the hint line, and Load (enabled with `has_save(0)`) reloads the
  recovery autosave in place with `Main.load_run(0)` (group `world_main`). The save-slots window
  (`ui.save-slots`, built on `RunState.list_saves()`) belongs to the saves work and is out of the
  shell's scope; it takes over Save and Load by registering those actions.
- **[IN]** Quit to Title: closes the windows, holds the pause (`shell:quit`), calls
  `RunState.save_slot(0)` (the recovery autosave's place), fades to `#0b1020` and the music out
(`MusicDirector.fade_out(320)`) over 320 ms, then
  `WorldService.clear()`, unpauses and changes to `title.tscn`, fading back in.

## 3. Settings

Phaser (`GameSettingsStore.ts`, `GameSettingsService.ts`, `SettingsSurfacePort.ts`):

| Key | Default | Range | Effect |
|---|---|---|---|
| `master` | 0.8 | [0, 1] | master volume (`applyMix`, `SettingsSurfacePort.ts:81-87`) |
| `effects` | 1 | [0, 1] | effects bus, and the ambience bus follows it |
| `music` | 0.7 | [0, 1] | music bus |
| `muted` | false | bool | mutes the master |
| `screenShake` | 1 | [0, 1] | camera shake scale (`GameFeel.ts:91`) |
| `reduceMotion` | false | bool | no shake and no hit-stop (`GameFeel.ts:91-98`, `shakeScale`, `GameSettingsService.ts:27`), softer squash (`SquashStretch.ts:33-35`) |
| `attackAim` | "pointer" | "pointer" / "facing" | dev panel only |

- Defaults `GameSettingsStore.ts:27-35`; parsing `:42-52` (numbers clamped to [0, 1], non-numbers
  fall back to the default, booleans only when exactly `true`, aim "facing" else "pointer");
  stored as `{version: 1, ...}` in localStorage, another version reads as defaults (`:55-71`);
  a failed save still applies for the session (`:73-80`). Separate from save slots.
- The window (`SettingsSurfacePort.ts:44-73`): sliders Master / Effects / Music / Shake (step 0.05)
  captioned "Master volume  80%", "Sound effects  100%", "Music  70%", "Screen shake  100%" (or
  "Screen shake  off (reduce motion)" with the slider disabled), Reduce motion: On/Off, Controls,
  the status "Changes apply immediately and are saved on this device" (or "All sound is muted"),
  Mute all / Unmute (warning), Defaults and Close (muted). Every edit saves and applies at once.

Godot:
- **[IN]** `GameSettings` keeps the same keys in snake_case (`master`, `effects`, `music`, `muted`,
  `screen_shake`, `reduce_motion`, `attack_aim`), defaults, ranges and parsing, in
  `user://settings.cfg` (ConfigFile: `[meta] version=1`, `[settings]`). `update()` clamps, saves,
  applies and emits `changed`; `reset()` is Defaults.
- Test runs (`-s res://tests/run_tests.gd`) neither read nor depend on the player's file: the
  Shell keeps the defaults there, so reduce motion cannot switch hit-stop off under the tests.
- **[IN]** Buses through `MusicDirector.apply_mix` (static, linear gains like WebAudio): Master =
  `master` and `muted`, Effects and Ambience = `effects`, Music = `music`. Applied by the Shell at
  start-up and on every change.
- **[IN]** `GameFeel.screen_shake_scale` and `GameFeel.reduce_motion` (shake scale, and no shake or
  hit-stop under reduce motion).
- **[OUT]** The softer squash under reduce motion: `game/player/squash_stretch.gd` does not read a
  setting yet (it can read `Services.shell().get_settings().reduce_motion()`). `attack_aim` is
  stored only. Phaser has no fullscreen or key-rebinding setting, so neither is added.

## 4. Area title card

Phaser:
- After a world loads outside title mode, `showAreaTitle(area.name, BIOMES[area.biome].titleColor)`
  (`WorldScene.ts:515-517`); names and biomes from `world/Area.ts:24-88` (unknown ids become their
  title-cased parts: "elder-house" → "Elder House", meadow biome), colours from
  `world/Biome.ts:11-40` (meadow `#a3f0c0`, gloop forest `#8cff9a`, crystal caverns `#9ad8ff`,
  icege `#bcecff`; `#ffd277` for an invalid colour). The same banner announces learned abilities
  (`WorldScene.ts:483-491`).
- Timing (`AreaTitleSurfacePort.ts:6-8, 29-52`), on the scene clock (not frozen by hit-stop):
  320 ms in, 1200 ms hold, 320 ms out; progress eased `1 - (1 - p)^3`; opacity = eased; the card is
  440 × 64 at the top centre with `top = round(54 + eased · 18)`; visible for 1840 ms.
- Label 24 px bold in the given colour with a `0 2px 4px #081022` shadow, centred.

Godot:
- **[IN]** `Shell` listens to `WorldService.world_registered` and shows `AreaTitles.area_name(id)`
  in `AreaTitles.title_color(id)` while a `world_main` node exists (so a travel shows the new area,
  the title backdrop shows nothing). Same timing on real time (`Time.get_ticks_msec`), same
  geometry; the card widens for a long line (never wider than the screen − 24 px).
- **[IN]** `Shell.show_area_title(text, colour)` for other banners. **[OUT]** The "learned"
  banners are the abilities port's to call (its spec marks them OUT).
- Area names and biome colours are kept in `area_titles.gd` until the converter exports
  `Area.ts` / `Biome.ts` as data.

## 5. Controls and credits

- Controls (`ControlsSurfacePort.ts:9-27`): fifteen rows, key label then action, from the binding
  table. Key labels (`ControlLabels.ts:4-70`): named keys (Space, Shift, Esc, arrows, "+", "−",
  Left / Right / Middle click, Mouse wheel), letters and digits as printed by the keyboard layout,
  movement as one label ("WASD"). **[IN]** from Godot's InputMap (`ControlLabels.control_rows()`,
  the layout label through `DisplayServer.keyboard_get_label_from_physical`). **[DIFF]** One grid
  row per control in 13 px, so a wrapped description keeps its key on its row.
- Credits (`CreditsSurfacePort.ts:22-27`): per section the heading in capitals, then
  "name  ·  detail  ·  license" per entry, blocks separated by a blank line. **[IN]** with the
  sections of `content/credits/credits.json` kept in `credits_menu.gd`; **[DIFF]** "Built with"
  names Godot Engine (MIT) instead of Phaser and its build tools.

## 6. Game over and end cards

Phaser:
- Defeat (`WorldScene.ts:1920-1940`): 1400 ms after the killing blow the game-over screen shows
  "Defeated by <cause>" (or "You were defeated"), "H:MM played" (`formatPlayTime`,
  `SaveSlotsSurfacePort.ts:39-42`), "Wake at your bed" / "Wake in Slimeshire" and "Load a save"
  (disabled with nothing to load); Escape never skips it; Wake respawns at the bed or the start
  (`GameOverSurfacePort.ts:46-65`).
- End cards (`EndCardSurfacePort.ts`, `content/story/endCards.ts`): when a story flag of a card
  (`chapter-2-complete`, `playground-end-card-test`) is set during play, its card opens (title,
  subtitle, body, "Return to title"); flags already set when the world loaded never show a card
  (`:22-25`). Escape never closes it; Return to title saves and goes to the title (`:40-44`).

Godot:
- **[IN]** `Shell.show_defeat({cause?, play_time_ms, has_bed})` and the window as above; Wake runs
  the `wake` action or `PlayerScript.respawn()`, Load the `load` action or `Main.load_run(0)`.
  **[OUT, owner decision O5]** The trial player respawns itself 1400 ms after defeat with no screen,
  so the Shell only shows the game over for a player whose `auto_respawn` is `false` (it connects
  that player's `defeated` on `WorldService.player_registered` and waits 1400 ms of real time).
- **[IN]** End cards: on `RunState.story_flag_changed` (set) inside a world the first card whose
  flag is newly set opens and pauses; on `world_registered` the run's existing flags are marked
  shown. Return to title = Quit to Title (§2).

## 7. Tests

`godot/tests/test_shell.gd`: settings defaults, clamping, file round trip, other versions, the bus
mix and GameFeel; the Settings window editing them; Escape pausing and resuming the tree only while
a world runs (window stack, a hit-stop under the menu, travelling); the title's launch-option skip
(args and query) and menu (New Game, Settings, Credits, no Continue without a save); the area card's
text, colour and timing on world registration and none outside main; end cards; and the theme
(documented variations present, `.tres` not older than its builder, icons stored). Each test uses
its own Shell and takes a registered `Shell` autoload out of the tree while it runs.

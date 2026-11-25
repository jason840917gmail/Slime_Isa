extends SceneTree
## Plays the rebuilt Crystal Mine's rooms (step 4 of the dungeons rework; the rooms:
## tools/build_crystal_mine_rooms.gd, the wings and the list of links:
## docs/handover/2026-11-23-dungeons-rework.md "Step 4: the Mine") in the running game, the designed
## way: doors pushed through (the screen scrolls), lamps lit with the Lantern, the Heavy Roll, pots
## thrown with the Gulp, chests opened. Run windowed (it renders), one at a time:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/film_crystal_mine_rooms.gd -- --film=<walk|cart|ride|shardback|look|old-save> --out=<dir> [--every=<n>] [--from=wing2|wing3|wing4]
## - `walk`: all four wings from the camp in G4 (the mine's gate holds, the Lantern lights its brazier,
##   up through G4's door into M1; the powers a run started in M1 gets, lent). Wing 1 (the Mouth and the High Line): the rail gate and the shelf refuse, the Lamp
##   Tunnel lit and its void, the hub (the Foreman's Gate and the ledge refuse), the Bat Gallery (its walk
##   out of reach, the timbers hold, a Heavy Roll smashes them), the Ore Store (the Spear on the target
##   and on the rail gate refused; a pot at the target: the cart bursts the gate and rolls on into M1),
##   the shortcut both ways, the High Line (the loft's stair, the high walk, the hub's ledge: key 2, a
##   drop to the gallery unhurt), key 2 in the Foreman's Gate (one lock of two). Wing 2 (the Lantern's
##   half): the Tally Room (its crack holds; key 1 where the Gloomling sat; a Goo Bomb on the crack),
##   the Survey Office (the map; its shelf out of reach), key 1 in the Foreman's Gate, the Dark Maze
##   (its gate holds, its wall tops out of reach; the four candles lit with the Lantern open the gate),
##   the Chasm (a step into it costs health; the Bow's arrow in the lens lowers the bridge; the Den's
##   doorway, not built, stands without loading a world), the travel cart to the mouth and back; then,
##   the Feral skin lent (as Pearl 3 gives it), the vines up the hub's west shelf, the Survey Office's
##   shelf, the maze's wall tops to S1's chest, a drop to the floor (wings 1 and 2 as first built; the
##   wall tops are walked in wing 3 since). Wing 3 (the Den, Pearl 3, the rift, the Fort Hall's big key,
##   the Prism Gallery), with wing 4's first visit after Pearl 3: down the Den's sunk rim onto M14's
##   ledge, the roots down, the boss door refused without the big key, the lift worked from below up
##   to the hub (refused from the gallery in wing 1), the mouth sealed, the wall tops to S1, round by
##   the maze and the Chasm. Wing 4 with the big key: the boss door, M15 (the Colossus lab's arena),
##   the crystal over the nook, the climb out refused while he stands, his fight ended by the tool
##   (filmed by tools/film_colossus_arena.gd), Release 1's end card closed, the seals sunk, his full
##   heart, the climb out to the Lookout (H4), round to the camp (the open world, the quick way), in by the mouth (its seal sunk) and out to
##   the camp. `--from=wing4`: wing 4 alone from M14 (the boss door refused, the lift up and down, the
##   big key given).
##   A picture a step (`<nn>-<step>.png`) and `walk.json` (each check: its world, the slime's spot and
##   level); the last line says PASS or FAIL.
## - `cart`: the mechanism's teach filmed (every `--every`-th physics step a frame `f<nnn>.png`): the
##   Spear clinks on the target, a pot thrown at it, the brake let go, the cart down its line, the rail
##   gate burst, the cart rolling on out through the doorway; then a still of M1 with the cart at its
##   buffer stop (`m1-after.png`). PASS or FAIL in `cart.json`.
## - `ride`: the travel cart between worlds filmed frame by frame: the interact key at the Chasm's
##   station, the fade, out at the Mine Mouth's station. `--from=wing2` (with `walk`): the walk starts in
##   the hub with key 2 in hand and plays wing 2 only.
## - `old-save`: a save half-played in today's one-scene Mine (sealed by Pearl 3, a key held, a lock
##   open, the lift worked, the cart at the mouth) written to the tool runs' save folder and loaded:
##   it wakes in M1 at its entrance; the hub, the Den and the Chasm read today's records. PASS or FAIL.
## - `look`: a still picture of a room in the game, `look-<room>.png` (`--world=<room name>`,
##   `--at=<x>,<y>` cells, `--zoom=<z>`, `--slime=<x>,<y>` where the slime stands, `--lit` lights a dark
##   room's lamps, `--bright` hides the darkness of a room that stays dark): its ground edges and lights,
##   which the editor render lacks.
## Staging: the slime is put near each step's spot (the rooms are big), never through a lock; every
## lock is opened by playing it; enemies are calmed and the slime's health and energy kept full (the walk
## proves the way, not a fight).

const Services := preload("res://game/shared/services.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const BowArrow := preload("res://game/player/abilities/bow_arrow.gd")
## How far ahead of the slime the Bow's arrow leaves (bow_sequence.gd BOW_AHEAD_PX).
const BOW_AHEAD_PX := 26.0
const GOO_BOMBS := &"goo-bombs"
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const CELL := 64.0
const LANTERN := &"lantern"
const MAIN_SCENE := "res://game/main.tscn"
const W := "crystal-mine-"
const DUNGEON_ID := "crystal-mine"
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 3000.0
const AMMO_BEHIND_PX := 34.0
const TIMBERS_FLAG := "crystal-mine.rotten-timbers"
const SURVEY_FLAG := "crystal-mine.survey-wall"
## The Den's cart line's row (cells; build_crystal_mine_rooms.gd DEN_RAIL_Y).
const DEN_RAIL_Y := 12.6
const CAMP := "crystal-caverns-g4"

var _main: Node
var _out := "user://crystal-mine-rooms"
var _film := "walk"
## `--from=wing2`: the walk starts in the hub with key 2 in hand (wing 1 played); `wing3` on the
## Chasm's far rim; `wing4` on M14's floor.
var _from := ""
var _every := 2
var _filming := false
var _step := 0
var _index := 0
var _shot := 0
var _log: Array = []
## The saved frames' rows (film.json, for scripts/godot/mechanism-film-sheet.py): game time and states.
var _rows: Array = []
var _start_ms := -1.0
var _fails: Array = []
var _caption: Label
var _heal := true
var _look_world := "m4-great-shaft"
var _look_at := Vector2(18.0, 8.0)
var _look_zoom := 0.45
var _look_slime := Vector2.INF
var _look_lit := false
## `--bright`: a room that stays dark for good pictured without its darkness (its floor seen).
var _look_bright := false
## The `shardback` film: the Den's darkness hidden once the slime is in (so the blow can be seen).
var _dark_hidden_on_arrival := false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--film="):
			_film = arg.trim_prefix("--film=")
		elif arg.begins_with("--world="):
			_look_world = arg.trim_prefix("--world=")
		elif arg.begins_with("--at="):
			var xy := arg.trim_prefix("--at=").split(",")
			_look_at = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--slime="):
			var sxy := arg.trim_prefix("--slime=").split(",")
			_look_slime = Vector2(float(sxy[0]), float(sxy[1]))
		elif arg.begins_with("--zoom="):
			_look_zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--lit":
			_look_lit = true
		elif arg == "--bright":
			_look_bright = true
		elif arg.begins_with("--from="):
			_from = arg.trim_prefix("--from=")
		elif arg.begins_with("--every="):
			_every = maxi(1, int(arg.trim_prefix("--every=")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_crystal_mine_rooms: gave up after %d s" % int(WATCHDOG_S))
		_finish())
	DisplayServer.window_set_size(WINDOW)
	var start := W + ("m7-ore-store" if _film == "cart" else "m9-the-chasm" if _film == "ride" or _film == "shardback" or _from == "wing3"
		else _look_world if _film == "look" else "m4-great-shaft" if _from == "wing2" else "m14-shaft-floor" if _from == "wing4"
		else "m1-mine-mouth")
	if _film == "walk" and _from.is_empty():
		start = CAMP
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", start)
	_main.set(&"ability_ceremonies", false)
	_main.set(&"direct_world_run", true)
	root.add_child(_main)
	for i in 90:
		await process_frame
	if Services.feel() != null:
		Services.feel().frame_clock_ms = 1000.0 / 60.0
	_hide_hints()
	_make_caption()
	match _film:
		"walk":
			await _walk()
		"cart":
			await _cart_film()
		"ride":
			await _ride_film()
		"shardback":
			await _from_far_rim()
			_dark_hidden_on_arrival = true
			await _walk_wing3()
		"look":
			await _look()
		"old-save":
			await _old_save()
		_:
			push_error("film_crystal_mine_rooms: no film " + _film)
	_finish()


func _finish() -> void:
	var report := {"film": _film, "fails": _fails, "steps": _log}
	var file := FileAccess.open(ProjectSettings.globalize_path(_out.path_join(_film + ".json")), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if not _rows.is_empty():
		var film := FileAccess.open(ProjectSettings.globalize_path(_out.path_join("film.json")), FileAccess.WRITE)
		film.store_string(JSON.stringify({"film": _film, "rows": _rows, "fails": _fails}, "\t"))
		film.close()
	print("film_crystal_mine_rooms: %s %s (%d checks failed)" % [_film, "PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	for fail: String in _fails:
		print("  FAIL ", fail)
	quit(0 if _fails.is_empty() else 1)


# --- the walk (wing 1) -----------------------------------------------------------------------------

func _walk() -> void:
	if _from == "wing2":
		DungeonState.add_small_key(Services.run(), DUNGEON_ID, 1)
		_place(Vector2(13.0, 12.6), Vector2.DOWN)
		await _run(20)
		await _walk_wing2()
		await _walk_wing3()
		return
	if _from == "wing3":
		await _from_far_rim()
		await _walk_wing3()
		return
	if _from == "wing4":
		await _walk_wing4_alone()
		return
	await _from_camp()
	await _walk_wing1()
	await _walk_wing2()
	await _walk_wing3()


## Staged for `--from=wing3` and the `shardback` film: the Chasm's bridge let down (the lens struck as
## the Bow's arrow strikes it), the slime on the far rim.
func _from_far_rim() -> void:
	var lens := _node("Objects/M9-chasm-lens")
	if lens != null:
		lens.call(&"on_arrow_hit", {})
	await _run(30)
	_place(Vector2(14.0, 11.0), Vector2.DOWN)
	await _run(10)


## Wing 1, the Mouth and the High Line: M1 to key 2 and one lock of the Foreman's Gate.
func _walk_wing1() -> void:
	# M1: the way in; the rail gate and the shelf refuse
	await _note("m1", "M1 the Mine Mouth: the rail gate shut east, the shelf's chest, the way north")
	_check(_world() == W + "m1-mine-mouth", "the walk starts in M1")
	var gate := _node("Objects/m1-rail-gate")
	_place(Vector2(14.8, 7.0), Vector2.RIGHT)
	await _hold("move_right", 900)
	_check(_world() == W + "m1-mine-mouth" and gate != null and not bool(gate.call(&"is_smashed")), "M1's rail gate holds the slime")
	_place(Vector2(3.5, 6.4), Vector2.UP)
	await _hold("move_up", 700)
	_check(_level() == 0, "without the Feral skin the shelf's vines are no way up (level %d)" % _level())
	await _through(Vector2(13.0, 2.6), "move_up", "m2-lamp-tunnel", "M1 north to the Lamp Tunnel")
	# M2: dark; the Lantern lights its three lamps for good; its void
	AbilityBox.select(Services.world().player, LANTERN)
	await _run(30)
	await _note("m2", "M2 the Lamp Tunnel: dark, the Lantern's ember shows the voids beside the rails")
	await _light(Vector2(2.6, 2.9), Vector2.UP)
	await _light(Vector2(15.4, 2.9), Vector2.UP)
	await _light(Vector2(15.2, 11.5), Vector2.DOWN)
	_check(Services.run().has_flag("crystal-mine.lamp-tunnel-lit"), "the Lantern lights M2's three lamps: lit for good")
	await _note("m2-lit", "M2: the three lamps lit, the tunnel lit for good")
	_place(Vector2(9.6, 5.0), Vector2.LEFT)
	await _run(10)
	_heal = false
	var hp := _health()
	await _hold("move_left", 1400)
	await _run(90)
	_check(_health() < hp and _level() == 0 and _world() == W + "m2-lamp-tunnel",
		"a step into M2's void costs health and puts the slime back on the floor (hp %.0f -> %.0f)" % [hp, _health()])
	_heal = true
	await _through(Vector2(13.0, 2.6), "move_up", "m4-great-shaft", "M2 north to the hub")
	# M4: the hub
	await _note("m4", "M4 the Great Shaft: the Foreman's Gate north, key 2 on the ledge (south-east)")
	_place(Vector2(9.0, 2.9), Vector2.UP)
	await _hold("move_up", 800)
	_check(_world() == W + "m4-great-shaft" and _feet().y > 2.0 * CELL, "the Foreman's Gate holds without its keys")
	_place(Vector2(27.6, 10.5), Vector2.RIGHT)
	await _hold("move_right", 900)
	_check(_level() == 0, "the ledge (key 2) is out of reach from the gallery (level %d)" % _level())
	_place(Vector2(3.0, 7.4), Vector2.UP)
	await _hold("move_up", 700)
	_check(_level() == 0, "the west shelf's vines are no way up without Feral (level %d)" % _level())
	# the ore lift waits down, its crank below: from the gallery it is not offered
	var lift := _node("Objects/m4-lift")
	_place(Vector2(21.6, 3.9), Vector2.RIGHT)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	await _run(60)
	_check(lift != null and not bool(lift.call(&"can_use")) and _world() == W + "m4-great-shaft",
		"the ore lift waits down (its crank below): from the gallery it does not ride")
	await _through(Vector2(23.0, 13.4), "move_down", "m6-bat-gallery", "the hub south to the Bat Gallery")
	# M6: dark; its walk out of reach; the timbers
	await _note("m6", "M6 the Bat Gallery: dark, the high walk overhead, the rotten timbers south")
	_place(Vector2(20.0, 6.2), Vector2.UP)
	await _hold("move_up", 800)
	_check(_level() == 0, "M6's high walk is out of reach from the floor (level %d)" % _level())
	_place(Vector2(21.0, 12.9), Vector2.DOWN)
	await _hold("move_down", 800)
	_check(_world() == W + "m6-bat-gallery", "the rotten timbers hold the slime")
	_place(Vector2(21.0, 11.4), Vector2.DOWN)
	await _run(10)
	await _roll(Vector2.DOWN)
	await _run(90)
	_check(Services.run().has_flag(TIMBERS_FLAG), "a Heavy Roll smashes the rotten timbers")
	await _note("m6-timbers", "M6: the timbers smashed by a Heavy Roll")
	await _through(Vector2(21.0, 13.4), "move_down", "m7-ore-store", "M6 through the timbers into the Ore Store")
	var timbers := _node("Objects/m7-rotten-timbers")
	_check(timbers != null and bool(timbers.call(&"is_smashed")), "the timbers stand smashed on the Ore Store's side too")
	# M7: the mechanism's teach
	await _note("m7", "M7 the Ore Store: the loaded cart held, its brake's target; the crate loft")
	await _cart_teach()
	# the shortcut, both ways
	# the burst gate walked through off the rails, near the doorway's upper edge (its posts block nothing now)
	await _through(Vector2(3.6, 6.65), "move_left", "m1-mine-mouth", "the burst gate: M7 west into M1 (the short way back), off the rails")
	var arrived := _node("Objects/m1-ore-cart")
	var m1_gate := _node("Objects/m1-rail-gate")
	_check(arrived != null and str(arrived.call(&"state_name")) == "spent", "M1: the cart stands at its buffer stop")
	_check(m1_gate != null and bool(m1_gate.call(&"is_smashed")), "M1: the rail gate stands burst on this side too")
	await _note("m1-shortcut", "M1: the cart at its buffer stop, the gate burst: the short way back")
	await _through(Vector2(14.4, 7.4), "move_right", "m7-ore-store", "M1 east back into the Ore Store, off the rails near the lower edge")
	# the High Line: the loft's stair, its north doorway, the high walk, the hub's ledge
	_place(Vector2(27.5, 8.2), Vector2.UP)
	await _run(6)
	await _hold("move_up", 1500)
	_check(_level() == 1, "up the loft's stair onto the crate loft (level %d)" % _level())
	await _note("m7-loft", "M7: on the crate loft, the Pick Mole behind his crates")
	await _through(Vector2(32.0, 2.7), "move_up", "m6-bat-gallery", "the loft's north doorway onto M6's high walk")
	_check(_level() == 1, "into M6 on the high walk (level %d)" % _level())
	await _note("m6-walk", "M6: on the high walk, the bats over the rails below")
	await _hold("move_up", 3200)
	_check(_level() == 1 and _feet().y < 5.0 * CELL, "along the walk's east leg (level %d, row %.1f)" % [_level(), _feet().y / CELL])
	_place(Vector2(31.5, 3.2), Vector2.LEFT)
	await _hold("move_left", 5600)
	_check(_level() == 1 and _feet().x < 16.0 * CELL, "along the walk's north leg (level %d, col %.1f)" % [_level(), _feet().x / CELL])
	await _note("m6-walk-west", "M6: the walk's west end, the doorway to the hub's ledge")
	await _through(Vector2(13.0, 2.7), "move_up", "m4-great-shaft", "the walk's north doorway onto the hub's ledge")
	_check(_level() == 1 and _feet().x > 28.5 * CELL, "on the hub's high ledge (level %d, col %.1f)" % [_level(), _feet().x / CELL])
	var keys := DungeonState.small_keys(Services.run(), DUNGEON_ID)
	await _open_chest(Vector2(31.5, 11.2), "m4-key2-chest")
	_check(DungeonState.small_keys(Services.run(), DUNGEON_ID) == keys + 1, "key 2 from the ledge's chest")
	await _note("m4-key2", "M4's ledge: key 2")
	_place(Vector2(29.5, 10.0), Vector2.LEFT)
	await _run(10)
	_heal = false
	hp = _health()
	await _hold("move_left", 1600)
	_heal = true
	_check(_level() == 0 and is_equal_approx(_health(), hp), "a drop off the ledge lands on the gallery unhurt (level %d, hp %.0f -> %.0f)" % [_level(), hp, _health()])
	await _note("m4-drop", "M4: off the ledge, down on the gallery")
	await _run(60)
	# key 2 in the Foreman's Gate: one lock of two (key 1 is wing 2's)
	var foreman := _node("Objects/foremans-gate")
	_place(Vector2(9.0, 2.9), Vector2.UP)
	await _hold("move_up", 1200)
	_check(foreman != null and int(foreman.call(&"open_keyholes")) == 1 and _world() == W + "m4-great-shaft",
		"key 2 opens one of the Foreman's Gate's two locks; it still holds")
	await _note("m4-gate", "M4: one lock of the Foreman's Gate open")


## Wing 2, the Lantern's half: from the hub (key 2 had) to the Chasm, the cart, the wall tops, out.
func _walk_wing2() -> void:
	await _through(Vector2(13.0, 13.4), "move_down", "m2-lamp-tunnel", "the hub south to the Lamp Tunnel")
	await _through(Vector2(2.6, 9.0), "move_left", "m5-tally-room", "the Lamp Tunnel west into the Tally Room")
	AbilityBox.select(Services.world().player, LANTERN)
	await _run(20)
	await _note("m5", "M5 the Tally Room: dark; a Gloomling sits on key 1 among the pillars; the cracked north wall")
	_place(Vector2(5.0, 2.9), Vector2.UP)
	await _hold("move_up", 700)
	_check(_world() == W + "m5-tally-room" and not Services.run().has_flag(SURVEY_FLAG), "the Tally Room's cracked wall holds the slime")
	# key 1: the Lantern's light on the Gloomling, then onto the key
	var keys_before := DungeonState.small_keys(Services.run(), DUNGEON_ID)
	_place(Vector2(9.0, 11.2), Vector2.UP)
	await _run(90)
	await _take_floor_key()
	_check(DungeonState.small_keys(Services.run(), DUNGEON_ID) == keys_before + 1, "key 1 picked up where the Gloomling sat")
	await _note("m5-key1", "M5: key 1")
	# the crack: a Goo Bomb opens the way to the Survey Office
	_place(Vector2(5.0, 3.0), Vector2.UP)
	await _run(10)
	await _bomb(Vector2.UP, 3400)
	_check(Services.run().has_flag(SURVEY_FLAG), "a Goo Bomb blows the Tally Room's cracked wall")
	await _note("m5-crack", "M5: the cracked wall blown")
	await _through(Vector2(5.0, 2.6), "move_up", "m3-survey-office", "the blown wall north into the Survey Office")
	await _note("m3", "M3 the Survey Office: the map chest on the surveyor's table; the shelf overhead")
	await _open_chest(Vector2(9.0, 10.7), "M3-map-chest")
	_check(DungeonState.has_item(Services.run(), DUNGEON_ID, DungeonState.MAP), "the map from the Survey Office's chest")
	_place(Vector2(9.0, 6.6), Vector2.UP)
	await _hold("move_up", 800)
	_check(_level() == 0, "the Survey Office's shelf is out of reach from the floor (level %d)" % _level())
	await _through(Vector2(5.0, 13.4), "move_down", "m5-tally-room", "back south through the blown wall")
	await _through(Vector2(15.4, 9.0), "move_right", "m2-lamp-tunnel", "the Tally Room east to the Lamp Tunnel")
	await _through(Vector2(13.0, 2.6), "move_up", "m4-great-shaft", "the Lamp Tunnel north to the hub")
	# key 1 in the Foreman's Gate: its second lock opens, and through it into the Dark Maze
	await _through(Vector2(9.0, 2.9), "move_up", "m8-dark-maze", "key 1 opens the Foreman's Gate: through it into the Dark Maze")
	await _note("m8", "M8 the Dark Maze: dark; four cold candles in its corners, the exit gate shut")
	var exit_gate := _node("Objects/M8-exit-gate")
	_place(Vector2(31.0, 10.7), Vector2.UP)
	await _hold("move_up", 800)
	_check(exit_gate != null and not bool(exit_gate.call(&"is_open")) and _feet().y > 9.5 * CELL, "the maze's exit gate holds while its candles are cold")
	_place(Vector2(15.0, 12.5), Vector2.UP)
	await _hold("move_up", 800)
	_check(_level() == 0, "the maze's wall tops are out of reach from its floor (level %d)" % _level())
	await _candle_run(exit_gate)
	await _note("m8-gate", "M8: the four candles lit, the exit gate open")
	_place(Vector2(31.0, 10.7), Vector2.UP)
	await _hold("move_up", 900)
	_check(_feet().y < 8.5 * CELL, "through the exit gate into the goal's enclosure")
	await _through(Vector2(33.4, 7.0), "move_right", "m9-the-chasm", "the enclosure's east doorway into the Chasm")
	# M9: the chasm, the lens, the bridge, the dead doorway, the cart
	await _note("m9", "M9 the Chasm: the bridge raised on the far rim, the lens beside it")
	var bridge := _node("Objects/M9-chasm-bridge")
	var lens := _node("Objects/M9-chasm-lens")
	_check(bridge != null and not bool(bridge.call(&"is_lowered")), "the Chasm's bridge stands raised")
	_place(Vector2(6.3, 6.0), Vector2.RIGHT)
	await _run(10)
	_heal = false
	var hp_chasm := _health()
	await _hold("move_right", 1400)
	await _run(90)
	_check(_health() < hp_chasm and _feet().x < 7.0 * CELL and _world() == W + "m9-the-chasm",
		"a step into the chasm costs health and puts the slime back on the near side (hp %.0f -> %.0f)" % [hp_chasm, _health()])
	_heal = true
	_place(Vector2(6.4, 8.0), Vector2.RIGHT)
	await _run(10)
	var world := Services.world()
	var arrow := BowArrow.new()
	arrow.name = "BowArrow"
	world.entities_root().add_child(arrow)
	arrow.launch(world.player, world.player_body.global_position, Vector2.RIGHT, BOW_AHEAD_PX)
	await _run(150)
	_check(lens != null and bool(lens.call(&"is_struck")), "the Bow's arrow across the chasm strikes the lens")
	_check(bridge != null and bool(bridge.call(&"is_down_for_good")), "the lens lowers the bridge for good")
	await _note("m9-bridge", "M9: the arrow in the lens, the bridge down")
	_place(Vector2(6.0, 9.5), Vector2.RIGHT)
	await _hold("move_right", 4000)
	_check(_feet().x > 13.0 * CELL, "over the bridge to the far rim (col %.1f)" % (_feet().x / CELL))
	await _note("m9-far", "M9: the far rim; the way down to the Den")
	# the cart: to the Mine Mouth and back
	var station := _node("Objects/M9-cart-station")
	_check(station != null and bool(station.call(&"has_cart")), "the cart stands at the Chasm's station")
	await _ride(Vector2(4.0, 12.0), "m1-mine-mouth")
	var mouth := _node("Objects/M1-cart-station")
	_check(_world() == W + "m1-mine-mouth" and mouth != null and bool(mouth.call(&"has_cart")), "the cart rides to the Mine Mouth and stands there")
	await _note("m1-cart", "M1: off the cart at the mouth's station")
	await _ride(Vector2(8.6, 4.6) + Vector2(0, -10) / CELL, "m9-the-chasm")
	station = _node("Objects/M9-cart-station")
	_check(_world() == W + "m9-the-chasm" and station != null and bool(station.call(&"has_cart")), "and back to the Chasm")
	# on over the bridge to the far rim: wing 3 goes on from there
	_place(Vector2(14.0, 11.0), Vector2.DOWN)
	await _run(10)


## Wing 3, the Den and the Feral half: from the Chasm's far rim (the bridge down) into the Den, the
## Shardback's fight (a cold clang, then the shatter), Pearl 3 and the Feral skin, the rift, the Fort
## Hall's balcony and the big key, the veil and the Prism Gallery, back to the Den and its rim (the shaft,
## wing 4), the wall-top secret, and the seal at the mouth.
func _walk_wing3() -> void:
	await _through(Vector2(14.0, 13.4), "move_down", "m13-shardback-den", "the Chasm's far rim south into the Shardback's Den")
	await _run(30)
	if _dark_hidden_on_arrival and _node("DarkRooms") != null:
		(_node("DarkRooms") as CanvasItem).visible = false
	await _note("m13", "M13 the Den: dark; the Shardback, the cart held on its line, its target, two cold braziers")
	var shutter := _node("Objects/M13-den-shutter")
	_place(Vector2(13.5, 12.1), Vector2.UP)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	await _hold("move_up", 1200)
	_check(_level() == 0, "without the Feral skin the ledge's vines are no way up (level %d)" % _level())
	_check(shutter != null and bool(shutter.call(&"is_shut")), "in the room, his fight shuts the Den's north shutter behind the slime")
	var shard := _enemy_of("shardback")
	var cart := _node("Objects/M13-den-cart")
	var target := _node("Objects/M13-den-target")
	if not _check_ok(shard != null and cart != null and target != null, "the Den has its Shardback, its cart and its target"):
		return
	AbilityBox.select(Services.world().player, LANTERN)
	# the slime on the rails by the target; he plods toward it along them (staged: put on the rails)
	_place(Vector2(12.4, DEN_RAIL_Y), Vector2.RIGHT)
	await _run(10)
	await _spear()
	_check(bool(cart.call(&"is_held")), "the Spear only knocks on the Den's target: the cart stays held")
	await _shardback_on_rails(shard, Vector2(8.6, DEN_RAIL_Y))
	_check(not bool(shard.call(&"is_brittle")), "out of the braziers' light his shell is cold")
	# a pot thrown at the target lets the cart go: it strikes him from behind and clangs off the cold shell
	var hp_before := float(shard.get(&"_hp"))
	await _throw(Vector2.RIGHT)
	var staggered := false
	for i in 240:
		await _tick()
		if bool(shard.call(&"is_staggered")):
			staggered = true
			break
	_check(staggered and not bool(shard.call(&"is_defeated")) and float(shard.get(&"_hp")) < hp_before,
		"cold, the cart clangs off his shell: staggered, a little hurt, standing (%.0f -> %.0f)" % [hp_before, float(shard.get(&"_hp"))])
	await _note("m13-clang", "M13: the cart clangs off his cold shell")
	# the cart is hauled back up its line, the target rearmed
	var back := false
	for i in 900:
		await _tick()
		if bool(cart.call(&"is_held")) and bool(target.call(&"is_armed")):
			back = true
			break
	_check(back, "the counterweight hauls the cart back and the target rearms (the blow comes again)")
	# his slam's chunk: thrown ammo that never runs out
	shard.set(&"_slam_at", Vector2(8.0, 9.0) * CELL)
	shard.call(&"_knock_chunk_loose")
	var chunks: Array = shard.get(&"_chunks")
	_check(not chunks.is_empty() and is_instance_valid(chunks[chunks.size() - 1]), "a slam knocks a crystal chunk loose beside its ring (ammo for the target; %d lie)" % chunks.size())
	# the brazier lit with the Lantern: in its light, on the rails, his shell is brittle
	await _light(Vector2(9.5, 10.1), Vector2.DOWN)
	_place(Vector2(12.4, DEN_RAIL_Y), Vector2.RIGHT)
	await _shardback_on_rails(shard, Vector2(8.8, DEN_RAIL_Y))
	await _run(20)
	_check(bool(shard.call(&"is_brittle")), "in the brazier's light his shell glows brittle")
	_filming = _film == "shardback"
	if _filming:
		_still_camera(Vector2(8.0, 9.4) * CELL, 0.7)
		await _run(10)
	await _throw(Vector2.RIGHT)
	var fallen := false
	for i in 300:
		await _tick()
		if bool(shard.call(&"is_defeated")):
			fallen = true
			break
	await _run(150)
	_filming = false
	_check(fallen, "brittle, the cart shatters his shell in one blow: the Shardback falls")
	await _run(60)
	_check(shutter != null and not bool(shutter.call(&"is_shut")), "his fall opens the north shutter")
	var rim := _node("Objects/M13-den-ledge")
	_check(rim != null and not bool(rim.call(&"is_shut")), "his fall sinks the broken rim's shutter for good")
	await _note("m13-won", "M13: his shell shattered by the cart; Pearl 3 rises")
	if _film == "shardback":
		return
	# Pearl 3: the Feral skin, the seal
	_place(Vector2(7.5, 3.5), Vector2.DOWN)
	await _hold("move_down", 500)
	await _run(240)
	_check(SkinState.is_won(&"feral"), "Pearl 3 taken: the Feral skin")
	_check(DungeonState.is_sealed(Services.run(), DUNGEON_ID), "the take seals the mine")
	await _note("m13-pearl", "M13: Pearl 3 taken, the Feral skin; the mine sealed")
	# the teach: up the ledge's vines (the skin the route just gave), and down again
	await _climb(Vector2(13.5, 12.1), Vector2.UP, 1800)
	_check(_level() == 1, "with the Feral skin, up the ledge's vines (level %d)" % _level())
	await _climb(Vector2(13.5, 10.6), Vector2.DOWN, 1800)
	_check(_level() == 0, "and down them again (level %d)" % _level())
	# the broken rim, sunk: down to the shaft's floor before the big key (wing 4's first visit), up by
	# the lift, the mouth, the wall tops, round by the maze and the Chasm back to the Den
	await _shaft_floor_first()
	await _round_to_the_den()
	await _climb(Vector2(13.5, 12.1), Vector2.UP, 1800)
	_check(_level() == 1, "up the Den's ledge again (level %d)" % _level())
	await _through(Vector2(15.4, 9.0), "move_right", "m11-crystal-veil", "the ledge's east doorway into the rift")
	_check(_level() == 1, "into M11 on the west landing (level %d)" % _level())
	await _note("m11", "M11 the rift: dark; the west landing, the rift below, the east landing and the veil")
	# down the west landing's vines, across the rift, up the east landing's
	await _climb(Vector2(3.5, 10.6), Vector2.DOWN, 1800)
	_check(_level() == 0, "down the west landing's vines into the rift (level %d)" % _level())
	_place(Vector2(3.5, 12.5), Vector2.RIGHT)
	await _run(6)
	await _walk_path(PackedVector2Array([Vector2(12.5, 12.5)]))
	_check(_feet().x > 11.5 * CELL, "across the rift's floor")
	await _climb(Vector2(12.5, 12.1), Vector2.UP, 1800)
	_check(_level() == 1, "up the east landing's vines (level %d)" % _level())
	await _note("m11-east", "M11: up the east landing")
	await _through(Vector2(15.4, 9.0), "move_right", "m12-fort-hall", "the east landing's doorway into the Fort Hall")
	await _note("m12", "M12 the Fort Hall: the big chest on the balcony, the Watcher Eye, the Bone Marcher")
	_place(Vector2(8.5, 6.4), Vector2.UP)
	await _hold("move_up", 800)
	_check(_level() == 0, "the balcony is out of reach where no vines grow (level %d)" % _level())
	await _climb(Vector2(4.5, 6.1), Vector2.UP, 1800)
	_check(_level() == 1, "up the balcony's vines (level %d)" % _level())
	await _open_chest(Vector2(8.5, 4.1), "M12-big-key-chest")
	_check(DungeonState.has_item(Services.run(), DUNGEON_ID, DungeonState.BIG_KEY), "the big key from the balcony's big chest")
	await _note("m12-bigkey", "M12: the big key")
	_place(Vector2(10.5, 4.5), Vector2.DOWN)
	await _run(10)
	_heal = false
	var hp := _health()
	await _hold("move_down", 1200)
	_heal = true
	_check(_level() == 0 and is_equal_approx(_health(), hp), "a drop off the balcony lands on the hall's floor unhurt (level %d)" % _level())
	await _through(Vector2(2.6, 9.0), "move_left", "m11-crystal-veil", "the Fort Hall west back onto the rift's east landing")
	_check(_level() == 1, "back on the east landing (level %d)" % _level())
	# the veil holds while its brazier is cold; the Lantern lights it and the veil opens
	_place(Vector2(14.0, 3.8), Vector2.UP)
	await _hold("move_up", 800)
	_check(_world() == W + "m11-crystal-veil" and _feet().y > 2.4 * CELL, "the crystal veil holds the north doorway while its brazier is cold")
	await _light(Vector2(12.0, 2.7), Vector2.DOWN)
	await _run(60)
	await _through(Vector2(14.0, 2.6), "move_up", "m10-prism-gallery", "the brazier opens the veil: north into the Prism Gallery")
	await _note("m10", "M10 the Prism Gallery: the Prism Eye, the ore crate, the journal's chest")
	var eye := _enemy_of("prism-eye")
	if eye != null:
		var eye_hp := float(eye.get(&"_hp"))
		var eye_at := (eye as Node).get(&"body") as Node2D
		var at := (eye_at.global_position if eye_at != null else Vector2(8.5, 7.5) * CELL) / CELL
		_place(at + Vector2(-1.0, 0.0), Vector2.RIGHT)
		await _run(6)
		await _spear()
		_check(is_equal_approx(float(eye.get(&"_hp")), eye_hp), "the Prism Eye takes no harm from the Spear (invulnerable: go round it)")
	await _open_chest(Vector2(5.5, 4.9), "M10-journal-chest")
	var journal := _node("Objects/M10-journal-chest")
	_check(journal != null and bool(journal.get_node(^"ChestScript").call(&"is_empty")), "the journal's chest opens: its page taken")
	# back: this side's veil holds until its own brazier burns
	_place(Vector2(14.0, 12.4), Vector2.DOWN)
	await _hold("move_down", 800)
	_check(_world() == W + "m10-prism-gallery", "the veil on the gallery's side holds while its brazier is cold")
	await _light(Vector2(12.0, 11.5), Vector2.DOWN)
	await _run(60)
	var far_veil := _node("Objects/M10-veil")
	var far_brazier := _node("Objects/M10-brazier")
	_check(far_brazier != null and bool(far_brazier.call(&"is_lit")) and far_veil != null and bool(far_veil.call(&"is_open")),
		"the Lantern lights the gallery's brazier and its veil opens")
	await _through(Vector2(14.0, 13.0), "move_down", "m11-crystal-veil", "its brazier lit, back south through the veil")
	# back across the rift to the Den
	await _climb(Vector2(12.5, 10.6), Vector2.DOWN, 1800)
	_place(Vector2(12.5, 12.5), Vector2.LEFT)
	await _run(6)
	await _walk_path(PackedVector2Array([Vector2(3.5, 12.5)]))
	await _climb(Vector2(3.5, 12.1), Vector2.UP, 1800)
	_check(_level() == 1, "back across the rift and up the west landing (level %d)" % _level())
	await _through(Vector2(2.6, 9.0), "move_left", "m13-shardback-den", "the west landing's doorway back onto the Den's ledge")
	await _climb(Vector2(13.5, 10.6), Vector2.DOWN, 1800)
	_check(_level() == 0, "down the ledge's vines onto the Den's floor (level %d)" % _level())
	# wing 4: the big key had, down the rim again to the boss door
	await _through(Vector2(13.0, 13.2), "move_down", "m14-shaft-floor", "the broken rim south again onto the shaft floor's ledge")
	await _climb(Vector2(13.0, 4.6), Vector2.DOWN, 1800)
	_check(_level() == 0, "down the roots onto the shaft's floor (level %d)" % _level())
	await _walk_wing4()


## The full walk's start: the camp in G4 (Crystal Caverns), with the powers a run started in M1 gets
## (`dungeon.devPowers.crystal-mine`, lent as F6 on M1 lends them): the mine's gate holds while its
## brazier is cold, the Lantern lights it, and up through the gate and G4's mine door into M1 (the
## rebuilt Mine since the switch-over).
func _from_camp() -> void:
	var run := Services.run()
	for power: String in _main.call(&"dev_powers_for", W + "m1-mine-mouth"):
		if power.begins_with("skin."):
			SkinState.lend(StringName(power.trim_prefix("skin.")))
		elif run != null:
			run.learn_session_ability(power)
	await _run(20)
	var camp := _node("Spiral/camp-mine-mouth") as Node2D
	if camp != null:
		_place(camp.global_position / CELL + Vector2(0.0, 0.6), Vector2.UP)
	await _run(20)
	await _note("g4-camp", "G4: the camp at the mine's mouth")
	_check(_world() == CAMP, "the walk starts at the camp in G4")
	var gate := _node("Spiral/mine-gate")
	var brazier := _node("Spiral/mine-gate-brazier") as Node2D
	await _hold("move_up", 900)
	_check(_world() == CAMP and gate != null and not bool(gate.call(&"is_open")), "the mine's gate holds while its brazier is cold")
	if brazier != null:
		await _light(brazier.global_position / CELL + Vector2(1.1, 0.0), Vector2.LEFT)
	await _run(60)
	_check(gate != null and bool(gate.call(&"is_open")), "the Lantern lights the gate's brazier: the mine's gate opens")
	await _in_by_the_mouth()


## From the camp in G4 up through the mine's gate and G4's mine door into M1 (the rebuilt Mine).
func _in_by_the_mouth() -> void:
	var camp := _node("Spiral/camp-mine-mouth") as Node2D
	if camp != null:
		_place(camp.global_position / CELL, Vector2.UP)
	await _run(6)
	_push(&"move_up", true)
	var inside := await _wait_world("m1-mine-mouth", 600)
	_push(&"move_up", false)
	await _run(70)
	_check(inside, "up through the gate and G4's mine door into M1, the rebuilt Mine's mouth")


## Wing 4's first visit (before the big key): from the Den's sunk rim down onto M14's ledge, the roots
## down, the boss door refuses, the lift worked from below rides up to the hub.
func _shaft_floor_first() -> void:
	await _through(Vector2(13.0, 13.2), "move_down", "m14-shaft-floor", "the Den's broken rim (sunk): south down onto the shaft floor's ledge")
	_check(_level() == 1, "into M14 on the rim's foot, the ledge (level %d)" % _level())
	await _note("m14", "M14 the Shaft Floor: the ledge under the rim, the lift's crank, the boss door")
	await _climb(Vector2(13.0, 4.6), Vector2.DOWN, 1800)
	_check(_level() == 0, "down the roots off the ledge onto the shaft's floor (level %d)" % _level())
	await _boss_door_refuses()
	await _lift_up()


func _boss_door_refuses() -> void:
	var boss_door := _node("Objects/colossus-door")
	_place(Vector2(8.0, 2.9), Vector2.UP)
	await _run(6)
	await _hold("move_up", 1200)
	_check(boss_door != null and not bool(boss_door.call(&"is_open")) and _world() == W + "m14-shaft-floor",
		"the boss door holds without the big key")


## The lift from M14's landing (its crank) up to M4's gallery.
func _lift_up() -> void:
	var lower := _node("Objects/m14-lift")
	_check(lower != null and bool(lower.call(&"can_use")), "the lift's crank is down here: the lift is offered on the shaft's floor")
	_place(Vector2(5.0, 4.9), Vector2.LEFT)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	var up := await _wait_world("m4-great-shaft", 400)
	await _run(70)
	_check(up, "the crank worked from below: the lift rides up to the hub's gallery")
	var upper := _node("Objects/m4-lift")
	_check(upper != null and bool(upper.call(&"can_use")) and str(upper.call(&"platform_at")) == "upper",
		"from then on it runs both ways: offered on the gallery, its platform up here")
	await _note("m4-lift", "M4: up by the ore lift from the shaft's floor (the shortcut)")


## From the hub (up by the lift) round to the Den: the mouth sealed since Pearl 3, the wall-top secret
## (the skin the route gave), the maze's open gate, the Chasm's bridge.
func _round_to_the_den() -> void:
	await _through(Vector2(13.0, 13.4), "move_down", "m2-lamp-tunnel", "the hub south to the Lamp Tunnel")
	await _through(Vector2(13.0, 13.4), "move_down", "m1-mine-mouth", "the Lamp Tunnel south to the mouth")
	_place(Vector2(9.0, 13.2), Vector2.DOWN)
	await _hold("move_down", 1500)
	_check(_world() == W + "m1-mine-mouth", "the seal holds the mine's mouth since Pearl 3")
	await _note("m1-sealed", "M1: the mouth sealed until the Colossus falls")
	await _through(Vector2(13.0, 2.6), "move_up", "m2-lamp-tunnel", "the mouth north to the Lamp Tunnel")
	await _through(Vector2(13.0, 2.6), "move_up", "m4-great-shaft", "the Lamp Tunnel north to the hub")
	await _wall_top_secret()
	await _through(Vector2(33.4, 7.0), "move_right", "m9-the-chasm", "the maze east through its open gate to the Chasm")
	await _through(Vector2(14.0, 13.4), "move_down", "m13-shardback-den", "the Chasm's far rim south back into the Den")


## Wing 4 with the big key: on M14's floor, the boss door, his arena (the lab's), the crystal over the
## nook, the climb out refused while he stands, his fight ended by the tool (filmed in the room by
## tools/film_colossus_arena.gd), his fall: the seals sink, his full heart, the climb out to the
## Lookout; then the mouth open and out to the camp.
func _walk_wing4() -> void:
	# the big key in the boss door: the push opens it and goes on through
	_place(Vector2(8.0, 2.9), Vector2.UP)
	await _run(6)
	_push(&"move_up", true)
	var inside := await _wait_world("m15-colossus-arena", 400)
	_push(&"move_up", false)
	await _run(70)
	_check(inside, "the big key opens the boss door: through it into the arena's nook")
	await _note("m15", "M15 the Colossus's arena (his lab's): the nook, his wall, the lines and braziers")
	var run := Services.run()
	var arena := _node("Objects/ColossusArena")
	if not _check_ok(arena != null, "M15 has his arena"):
		return
	_check(str(arena.get(&"camp_id")) == "crystal-mine-colossus" and str(arena.get(&"boss_id")) == "crystal-colossus"
		and not bool(arena.get(&"refights")) and bool(arena.get(&"plate_fight")), "his camp: today's ids, the plate fight, once")
	# in: he wakes (from the nook, north onto his floor)
	_place(Vector2(13.0, 21.5), Vector2.UP)
	await _run(6)
	await _hold("move_up", 1200)
	var boss: Node = null
	for i in 400:
		await _tick()
		boss = arena.call(&"get_live_boss")
		if boss != null:
			break
	_check(boss != null, "he wakes as the slime walks in")
	await _run(90)
	# the crystal over the nook behind it
	_place(Vector2(13.0, 20.3), Vector2.DOWN)
	await _run(6)
	await _hold("move_down", 900)
	_check(_world() == W + "m15-colossus-arena" and _feet().y < 21.0 * CELL,
		"crystal grows over the nook behind the slime: no way back while he stands (row %.1f)" % (_feet().y / CELL))
	# the climb out refuses while he stands (the mine sealed)
	_place(Vector2(21.0, 5.9), Vector2.UP)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	await _hold("move_up", 1200)
	_check(_world() == W + "m15-colossus-arena", "the climb out to the Lookout refuses while he stands (the mine sealed)")
	await _note("m15-fight", "M15: he is up, the nook grown shut, the climb out sealed")
	# his fight ended by the tool (filmed in the room by tools/film_colossus_arena.gd)
	if boss != null and is_instance_valid(boss):
		boss.set(&"_hp", 0.0)
		boss.call(&"_defeat")
	await _run(420)
	# Release 1's end card shows (his fall sets `chapter-3-complete`); in play "Return to title" saves
	# and the run goes on from the save: the tool closes it
	var shell := Services.shell()
	var card: Node = shell.get(&"end_card") if shell != null else null
	_check(card != null and bool(card.call(&"is_open")), "his fall shows Release 1's end card (the first three Pearls)")
	await _note("m15-end-card", "M15: Release 1's end card (closed by the tool, as returning to the title and going on)")
	if card != null and bool(card.call(&"is_open")):
		card.call(&"close")
	await _run(120)
	_check("crystal-colossus" in (run.world.get("defeated_boss_ids", []) as Array), "his defeat is recorded (defeated_boss_ids)")
	_check(DungeonState.is_boss_beaten(run, DUNGEON_ID, "crystal-colossus"), "the mine's record: its boss beaten")
	_check(not DungeonState.is_sealed(run, DUNGEON_ID), "his fall breaks the seals (Pearl 3's)")
	var heart := _node("Objects/M15-full-heart/FullHeartScript")
	_check(heart != null and bool(heart.call(&"is_shown")), "his full heart rises")
	await _note("m15-fallen", "M15: he has fallen; the braziers burn, his full heart")
	_place(Vector2(13.0, 10.8), Vector2.UP)
	await _run(6)
	await _hold("move_up", 500)
	await _run(120)
	_check(heart != null and bool(heart.call(&"is_taken")), "his full heart taken")
	# the climb out to the Lookout
	_place(Vector2(21.0, 5.9), Vector2.UP)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	_push(&"move_up", true)
	var out := await _wait_world("crystal-caverns-h4", 900)
	_push(&"move_up", false)
	await _run(90)
	_check(out, "up the roots of his wall and out to the Lookout (Crystal Caverns H4)")
	await _note("h4-lookout", "H4: the Lookout, out of the mine")
	# back in by the mouth (from the Lookout round to the camp, put there the quick way through the
	# open world) and out again: Pearl 3's seal sunk
	var world := Services.world()
	var main := get_first_node_in_group(&"world_main")
	var result: Dictionary = main.call(&"request_exit", {"map_id": world.map_id(), "exit_id": "walk:lookout-to-camp",
		"target_area_id": CAMP, "entry": "", "target_door_id": "camp-mine-mouth", "entry_marker": "",
		"gate": {}, "transition": "fade", "door_side": "", "lead_ms": 0.0})
	var at_camp := str(result.get("status", "")) == "queued" and await _wait_world(CAMP, 400)
	await _run(60)
	_check(at_camp, "round from the Lookout to the camp in G4 (the open world, the quick way)")
	await _in_by_the_mouth()
	var seal := _node("Objects/M1-mouth-seal")
	_check(seal != null and not bool(seal.call(&"is_shut")), "in by the mouth: Pearl 3's seal sunk since his fall")
	await _note("m1-open", "M1: the mouth's seal sunk since his fall")
	await _through(Vector2(9.0, 13.4), "move_down", CAMP, "out through the mouth to the camp in G4")
	await _note("g4-out", "G4: out at the camp")


## `--from=wing4`: on M14's floor (a run started there: the mine's F6 powers), the Feral skin lent (as
## Pearl 3 gives it): the boss door refuses, the lift rides up and back down, the big key given (as
## M12's chest gives it), then the rest of wing 4.
func _walk_wing4_alone() -> void:
	SkinState.lend(&"feral")
	DungeonState.seal(Services.run(), DUNGEON_ID, "crystal-colossus", "pearl")
	_place(Vector2(9.0, 9.5), Vector2.UP)
	await _run(20)
	await _note("m14", "M14 the Shaft Floor: the lift's crank, the boss door, the rim's ledge")
	await _boss_door_refuses()
	await _lift_up()
	_place(Vector2(21.6, 3.9), Vector2.RIGHT)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	var down := await _wait_world("m14-shaft-floor", 400)
	await _run(70)
	_check(down, "the lift rides back down from the gallery")
	DungeonState.give_item(Services.run(), DUNGEON_ID, DungeonState.BIG_KEY)
	await _walk_wing4()



## `old-save`: a save half-played in today's one-scene Mine (before the switch-over) loaded for real:
## written to the tool runs' own save folder (RunState TOOL_SAVE_ROOT, never the player's saves) as an
## old save would stand: in today's world (`crystal-mine`, in its Dark Maze), the mine sealed by Pearl 3
## (taken, the Feral skin won, the Shardback beaten), one small key held, one of the Foreman's Gate's
## locks open, the lift worked, the travel cart at the mouth, the record's entrance today's mouth; then
## `main.load_run`: it wakes in M1 at its entrance, and the rooms read today's records.
const OLD_SAVE_SLOT := 7


func _old_save() -> void:
	var run := Services.run()
	DungeonState.add_small_key(run, DUNGEON_ID, 1)
	DungeonState.open_keyhole(run, DUNGEON_ID, DUNGEON_ID + ":foremans-gate")
	DungeonState.mark_boss_beaten(run, DUNGEON_ID, "crystal-mine-shardback")
	run.set_flag("pearl.crystal-colossus")
	SkinState.grant(&"feral", false)
	DungeonState.seal(run, DUNGEON_ID, "crystal-colossus", "crystal-colossus")
	run.set_object_state(DUNGEON_ID, "ore-lift:great-shaft-lift:working", true)
	run.set_object_state(DUNGEON_ID, "ore-lift:great-shaft-lift", "lower")
	run.set_object_state(DUNGEON_ID, "mine-cart:crystal-mine-cart", "mouth")
	DungeonState.set_entrance(run, DUNGEON_ID, DUNGEON_ID, Vector2(1504, 4216))
	run.location = {"area_id": DUNGEON_ID, "map_id": DUNGEON_ID, "x": 640.0, "y": 640.0, "facing": "down"}
	# written as the game writes a slot (a save is blocked inside a dungeon but for its resume save, so
	# the file is written here in the same form), standing in today's world
	var data: Dictionary = run.call(&"serialize")
	data["location"] = run.location.duplicate()
	var root_dir := str(run.get(&"save_root"))
	DirAccess.make_dir_recursive_absolute(root_dir)
	var path := root_dir.path_join("%s%d.json" % [run.SLOT_PREFIX, OLD_SAVE_SLOT])
	var out := FileAccess.open(path, FileAccess.WRITE)
	var saved := out != null
	if out != null:
		out.store_string(JSON.stringify({"schema_version": run.SAVE_SCHEMA_VERSION, "saved_at": Time.get_unix_time_from_system() * 1000.0,
			"data": data}, "	"))
		out.close()
	var file := FileAccess.get_file_as_string(path) if saved else ""
	_check(saved and root_dir.begins_with("user://tool-saves"), "the old save written to the tool runs' own folder (%s)" % root_dir)
	_check(file.contains("\"map_id\": \"crystal-mine\""), "it stands in today's world, crystal-mine")
	# loaded for real
	var loaded := bool(_main.call(&"load_run", OLD_SAVE_SLOT))
	var in_m1 := loaded and await _wait_world("m1-mine-mouth", 400)
	await _run(90)
	_check(in_m1, "the old save loads into the rebuilt Mine's M1, not today's world")
	run = Services.run()
	var spawn := _node("player-spawn") as Node2D
	var from_spawn := _feet().distance_to(spawn.global_position) if spawn != null else -1.0
	_check(spawn != null and from_spawn < 96.0, "it wakes at M1's entrance (%.0f px from its player spawn), inside" % from_spawn)
	await _note("old-save-m1", "An old save from today's Mine: awake in M1 at its entrance")
	_check(DungeonState.is_sealed(run, DUNGEON_ID), "the mine still sealed (Pearl 3 taken, he stands)")
	var seal := _node("Objects/M1-mouth-seal")
	_check(seal != null and bool(seal.call(&"is_shut")), "the mouth's seal stands shut")
	_check(DungeonState.small_keys(run, DUNGEON_ID) == 1, "its small key kept (%d)" % DungeonState.small_keys(run, DUNGEON_ID))
	var entrance := DungeonState.entrance(run, DUNGEON_ID)
	_check(str(entrance.get("map_id", "")) != DUNGEON_ID, "the record's entrance no longer names today's world (%s)" % entrance)
	_check(SkinState.is_won(&"feral"), "the Feral skin kept")
	# the hub: the Foreman's Gate's lock kept, the lift worked
	await _through(Vector2(13.0, 2.6), "move_up", "m2-lamp-tunnel", "M1 north to the Lamp Tunnel")
	await _through(Vector2(13.0, 2.6), "move_up", "m4-great-shaft", "the Lamp Tunnel north to the hub")
	var foreman := _node("Objects/foremans-gate")
	_check(foreman != null and int(foreman.call(&"open_keyholes")) == 1, "the Foreman's Gate's lock opened in today's Mine stays open (%d of 2)"
		% (int(foreman.call(&"open_keyholes")) if foreman != null else -1))
	var lift := _node("Objects/m4-lift")
	_check(lift != null and bool(lift.call(&"can_use")), "the lift worked in today's Mine is offered on the gallery")
	# the Den: his fall kept, the rim open, Pearl 3 not risen again
	_main.call(&"travel_to", W + "m13-shardback-den", "", "", "RoomEntry")
	var den := await _wait_world("m13-shardback-den", 400)
	await _run(90)
	_check(den, "to the Den (put there the quick way)")
	var rim := _node("Objects/M13-den-ledge")
	_check(rim != null and not bool(rim.call(&"is_shut")), "the Shardback beaten in today's Mine: the Den's rim shutter sunk (the fight's reward)")
	_check(_enemy_of("shardback") == null, "he does not stand in the Den again")
	var pearl := _node("Objects/M13-pearl-three")
	_check(pearl != null and bool(pearl.call(&"is_taken")), "Pearl 3 taken in today's Mine does not rise again")
	await _note("old-save-den", "The old save in the Den: no Shardback, no Pearl, the rim open")
	# the Chasm: the travel cart at the mouth (today's record)
	_main.call(&"travel_to", W + "m9-the-chasm", "", "", "RoomEntry")
	var chasm := await _wait_world("m9-the-chasm", 400)
	await _run(60)
	var station := _node("Objects/M9-cart-station")
	_check(chasm and station != null and not bool(station.call(&"has_cart")), "the travel cart left at the mouth in today's Mine is not at the Chasm")


## The Shardback put on the cart's rails at `at` (cells), his home there (a calmed beast walks home).
func _shardback_on_rails(shard: Node, at: Vector2) -> void:
	var shard_body := shard.get(&"body") as CharacterBody2D
	if shard_body != null:
		shard_body.global_position = at * CELL
		shard_body.reset_physics_interpolation()
		shard.set(&"_home", shard.call(&"get_centre"))
	await _run(6)


## Takes hold of the vines from `at` (cells) facing `way` (the interact key) and climbs that way for `ms`.
func _climb(at: Vector2, way: Vector2, ms: float) -> void:
	_place(at, way)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	await _hold("move_up" if way == Vector2.UP else "move_down", ms)
	await _run(20)


## The wall tops (the Feral secret): the vines up the hub's west shelf, the Survey Office's shelf, the
## maze's west and north wall tops to S1's chest, a drop off the west wall's side.
func _wall_top_secret() -> void:
	await _run(10)
	_place(Vector2(2.5, 7.1), Vector2.UP)
	await _run(6)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	await _hold("move_up", 2600)
	_check(_level() == 1, "with the Feral skin, up the vines onto the hub's west shelf (level %d)" % _level())
	await _note("m4-shelf", "M4: up the vines onto the west shelf (Feral)")
	await _through(Vector2(2.6, 3.0), "move_left", "m3-survey-office", "the west shelf's doorway onto the Survey Office's shelf")
	_check(_level() == 1, "on the Survey Office's shelf (level %d)" % _level())
	await _through(Vector2(8.0, 2.6), "move_up", "m8-dark-maze", "the shelf's north doorway onto the maze's west wall")
	_check(_level() == 1, "on top of the maze's wall (level %d)" % _level())
	await _note("m8-walltop", "M8: on top of the maze's walls")
	# walked up the west wall's top until it meets the north wall (no further: past it is the drop)
	_push(&"move_up", true)
	for i in 900:
		await _tick()
		if _feet().y < 10.2 * CELL:
			break
	_push(&"move_up", false)
	await _run(8)
	_check(_level() == 1 and _feet().y < 11.0 * CELL, "north along the west wall's top (level %d, row %.1f)" % [_level(), _feet().y / CELL])
	_place(Vector2(8.0, 9.9), Vector2.RIGHT)
	await _hold("move_right", 3600)
	_check(_level() == 1, "east along the north wall's top (level %d, col %.1f)" % [_level(), _feet().x / CELL])
	_place(Vector2(20.6, 10.5), Vector2.UP)
	await _run(10)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	await _run(120)
	var s1 := _node("Objects/M8-S1-chest")
	# its window shows two things: taken, as the window's buttons take them
	if s1 != null:
		var chest_script := s1.get_node(^"ChestScript")
		for item: String in (chest_script.call(&"remaining") as Dictionary).keys():
			chest_script.call(&"transfer_stack", item)
	await _run(20)
	await _close_chest_window()
	_check(s1 != null and bool(s1.get_node(^"ChestScript").call(&"is_empty")), "S1's chest on the wall top opens: emptied (50 coins, the belt slot)")
	await _note("m8-s1", "M8: S1's chest on the wall top")
	_place(Vector2(7.3, 20.0), Vector2.LEFT)
	await _hold("move_left", 1500)
	_check(_level() == 0 and _feet().x < 7.0 * CELL, "a drop off the west wall's side lands on the maze's floor (level %d)" % _level())


## M7's teach, as the walk and the `cart` film play it: the Spear refused at the target and at the
## gate, a pot at the target, the cart's run, the gate burst, the cart gone on into M1.
func _cart_teach() -> void:
	var target := _node("Objects/m7-cart-target")
	var cart := _node("Objects/m7-ore-cart")
	var gate := _node("Objects/m7-rail-gate")
	if not _check_ok(target != null and cart != null and gate != null, "M7 has its target, its cart and its rail gate"):
		return
	_place(Vector2(22.2, 4.4), Vector2.RIGHT)
	await _run(10)
	await _spear()
	await _run(40)
	_check(bool(target.call(&"is_armed")) and bool(cart.call(&"is_held")), "the Spear only knocks on the target: the cart stays held")
	_place(Vector2(3.2, 7.0), Vector2.LEFT)
	await _run(10)
	await _spear()
	await _hold("move_left", 700)
	_check(not bool(gate.call(&"is_smashed")) and _world() == W + "m7-ore-store", "the Spear does nothing to the rail gate; it holds the slime")
	# the throw, from beside the pots west of the target
	_place(Vector2(20.4, 4.4), Vector2.RIGHT)
	await _run(20)
	_filming = _film == "cart"
	if _filming:
		_still_camera(Vector2(12.0, 6.6) * CELL, 0.62)
		await _run(20)
	await _throw(Vector2.RIGHT)
	for i in 300:
		await _tick()
		if str(cart.call(&"state_name")) == "spent":
			break
	await _run(60)
	_filming = false
	_check(not bool(target.call(&"is_armed")), "the pot knocks the target (%s)" % target.call(&"state_name"))
	_check(bool(gate.call(&"is_smashed")), "the runaway cart bursts the rail gate")
	_check(str(cart.call(&"state_name")) == "spent", "the cart rolls on out through the doorway, gone for good (%s)" % cart.call(&"state_name"))
	await _note("m7-burst", "M7: the cart ran, the rail gate burst")


func _cart_film() -> void:
	await _cart_teach()
	_still_camera(Vector2(12.0, 6.6) * CELL, 0.62)
	await _run(30)
	await _shoot("m7-after.png")
	await _through(Vector2(2.6, 7.0), "move_left", "m1-mine-mouth", "M7 west through the burst gate into M1")
	var arrived := _node("Objects/m1-ore-cart")
	_check(arrived != null and str(arrived.call(&"state_name")) == "spent", "M1: the cart stands at its buffer stop")
	_still_camera(Vector2(10.5, 7.5) * CELL, 0.72)
	await _run(40)
	await _shoot("m1-after.png")


## The travel cart between worlds, filmed: at the Chasm's station, the interact key, the fade, out at
## the Mine Mouth's station (the cart there now, none left at the Chasm).
func _ride_film() -> void:
	var station := _node("Objects/M9-cart-station")
	_check(station != null and bool(station.call(&"has_cart")), "the cart stands at the Chasm's station")
	_place(Vector2(4.0, 12.0), Vector2.DOWN)
	await _run(20)
	_filming = true
	await _run(20)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	var ok := await _wait_world("m1-mine-mouth", 600)
	await _run(120)
	_filming = false
	_check(ok, "the cart rides from the Chasm to the Mine Mouth")
	var mouth := _node("Objects/M1-cart-station")
	_check(mouth != null and bool(mouth.call(&"has_cart")), "the cart stands at the Mine Mouth's station")


## A still picture of a room in the game (its ground edges, lights, enemies): `look-<room>.png`.
func _look() -> void:
	if _look_lit:
		# every lamp of the room lit and kept lit: the dark room lifts
		for node: Node in Services.world().world_root.find_children("*", "", true, false):
			if node.has_method(&"keep_lit") and node.has_method(&"light"):
				node.call(&"light")
				node.call(&"keep_lit")
		await _run(30)
	if _look_bright:
		var dark := _node("DarkRooms") as CanvasItem
		if dark != null:
			dark.visible = false
	_place(_look_slime if _look_slime.is_finite() else _look_at + Vector2(0.0, 1.0), Vector2.DOWN)
	await _run(40)
	_still_camera(_look_at * CELL, _look_zoom)
	await _run(60)
	await _shoot("look-%s%s.png" % [_look_world, "-bright" if _look_bright else "-lit" if _look_lit else ""])


# --- acting --------------------------------------------------------------------------------------

## The Dark Maze's four candles lit by walking the maze in the best order from its way in (south-east,
## north-east, north-west, south-west: each at the end of its branch, lit from beside it), the Lantern
## held on the north-west candle's Gloomling until it leaves the wick; the game time from the first flame
## to the last checked against the candles' burn (the scene's `burn_ms`), the gate open.
func _candle_run(exit_gate: Node) -> void:
	AbilityBox.select(Services.world().player, LANTERN)
	_place(Vector2(27.0, 28.4), Vector2.UP)
	await _run(20)
	var burn := float(_node("Objects/M8-candle-se").get(&"burn_ms"))
	var walked := 0.0
	walked += await _walk_path(PackedVector2Array([Vector2(28.5, 28.4), Vector2(28.5, 23.5), Vector2(31.5, 23.5), Vector2(31.5, 21.5)]))
	await _flame(Vector2.RIGHT)
	var first_ms := Services.now_ms()
	walked += await _walk_path(PackedVector2Array([Vector2(29.5, 21.5), Vector2(29.5, 23.5), Vector2(23.5, 23.5),
		Vector2(23.5, 26.5), Vector2(22.5, 26.5), Vector2(22.5, 27.5), Vector2(12.5, 27.5), Vector2(12.5, 12.5),
		Vector2(23.5, 12.5), Vector2(23.5, 3.5)]))
	await _flame(Vector2.RIGHT)
	walked += await _walk_path(PackedVector2Array([Vector2(23.5, 7.5), Vector2(15.5, 7.5), Vector2(15.5, 3.5),
		Vector2(6.5, 3.5), Vector2(6.5, 6.5), Vector2(5.5, 6.5)]))
	# the north-west candle's Gloomling smothers its wick: the Lantern's light on it drives it off
	await _run(150)
	walked += await _walk_path(PackedVector2Array([Vector2(3.5, 6.5), Vector2(3.5, 3.5)]))
	await _flame(Vector2.LEFT)
	walked += await _walk_path(PackedVector2Array([Vector2(4.5, 3.5), Vector2(4.5, 6.5), Vector2(5.5, 6.5),
		Vector2(5.5, 13.5), Vector2(2.5, 13.5), Vector2(2.5, 18.5), Vector2(5.5, 18.5), Vector2(5.5, 23.5),
		Vector2(3.5, 23.5), Vector2(3.5, 27.5)]))
	await _flame(Vector2.DOWN)
	var span := Services.now_ms() - first_ms
	await _run(30)
	var lit: Array[String] = []
	for candle_name: String in ["M8-candle-se", "M8-candle-ne", "M8-candle-nw", "M8-candle-sw"]:
		var candle := _node("Objects/" + candle_name)
		if candle != null and bool(candle.call(&"is_lit")):
			lit.append(candle_name)
	_log.append({"candle_run": {"walked_cells": snappedf(walked / CELL, 0.1), "first_to_last_flame_ms": int(span), "burn_ms": int(burn),
		"lit": lit}})
	_check(span < burn, "the four candles lit by walking the maze in %.1f s, inside their %.0f s (%.0f cells walked)" % [span / 1000.0, burn / 1000.0, walked / CELL])
	_check(exit_gate != null and bool(exit_gate.call(&"is_open")), "the four candles lit at once open the exit gate for good (lit: %s)" % ", ".join(lit))


## Walks the slime through `points` (cells) one straight leg after another, the movement keys held
## toward each until it gets there (or a leg's time runs out). Returns the units walked.
func _walk_path(points: PackedVector2Array) -> float:
	var walked := 0.0
	for target: Vector2 in points:
		var goal := target * CELL
		var from := _feet()
		var along_x := absf(goal.x - from.x) >= absf(goal.y - from.y)
		var way := Vector2(signf(goal.x - from.x), 0.0) if along_x else Vector2(0.0, signf(goal.y - from.y))
		if way == Vector2.ZERO:
			continue
		var action := StringName({Vector2.LEFT: "move_left", Vector2.RIGHT: "move_right", Vector2.UP: "move_up", Vector2.DOWN: "move_down"}[way])
		var limit := int((from.distance_to(goal) / 180.0 + 1.5) * 60.0)
		_push(action, true)
		for i in limit:
			await _tick()
			var left := (goal - _feet()).dot(way)
			if left <= 4.0:
				break
		_push(action, false)
		await _tick()
		walked += from.distance_to(_feet())
	return walked


## The Lantern's flame the way `way` from where the slime stands.
func _flame(way: Vector2) -> void:
	var player: Node = Services.world().player
	player.call(&"face", way)
	await _run(3)
	_push(&"ability_use", true)
	await _run(3)
	_push(&"ability_use", false)
	await _run(30)


## The first live enemy of `type` (its `enemy_type`, or its node's name), or null.
func _enemy_of(type: String) -> Node:
	for enemy: Node in get_nodes_in_group(&"enemy"):
		if is_instance_valid(enemy) and (str(enemy.get(&"enemy_type")) == type or String(enemy.name).contains(type)):
			return enemy
	return null


## Walks onto every key lying in the world (the kit's floor key).
func _take_floor_key() -> void:
	for node: Node in Services.world().world_root.find_children("*", "", true, false):
		if is_instance_valid(node) and node is DungeonKeyPickup:
			_place((node as Node2D).global_position / CELL + Vector2(0.0, 0.3), Vector2.UP)
			await _hold("move_up", 300)
			await _run(40)


## The Goo Bomb cast facing `way`, then `wait_ms` for its blast.
func _bomb(way: Vector2, wait_ms: float) -> void:
	var player: Node = Services.world().player
	if not AbilityBox.select(player, GOO_BOMBS):
		_fails.append("the Goo Bomb is not in the Ability Box")
		return
	player.call(&"face", way)
	await _run(2)
	_push(&"ability_use", true)
	await _run(2)
	_push(&"ability_use", false)
	await _run(int(wait_ms / 1000.0 * 60.0))


## Rides the travel cart from beside its station, at `at` (cells; within its reach): the interact key there,
## then the world `room` once the ride's fade is over.
func _ride(at: Vector2, room: String) -> void:
	_place(at, Vector2.DOWN)
	await _run(10)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	var ok := await _wait_world(room, 600)
	await _run(80)
	_check(ok, "the travel cart rides to " + room)


## Closes a chest's window if one opened (a chest of several things holds the slime's keys), and a
## page's reading window (a war journal page taken), as Escape does.
func _close_chest_window() -> void:
	for node: Node in root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		var path := script.resource_path if script != null else ""
		if (path.ends_with("chest_window.gd") or path.ends_with("page_window.gd")) and node is CanvasItem \
				and (node as CanvasItem).is_visible_in_tree() and node.has_method(&"close"):
			node.call(&"close")
			await _run(20)


## The Lantern's flame at what stands ahead of the slime put at `at` facing `way`.
func _light(at: Vector2, way: Vector2) -> void:
	var player: Node = Services.world().player
	if not AbilityBox.select(player, LANTERN):
		_fails.append("the Lantern is not in the Ability Box")
		return
	_place(at, way)
	await _run(6)
	_push(&"ability_use", true)
	await _run(3)
	_push(&"ability_use", false)
	await _run(50)


## The Spear's strike the way the slime faces.
func _spear() -> void:
	var shapes: Node = _main.get(&"shapes")
	if shapes != null:
		shapes.call(&"power_strike", &"shape-spear")
	await _run(30)


func _roll(way: Vector2) -> void:
	var action := StringName({Vector2.LEFT: "move_left", Vector2.RIGHT: "move_right", Vector2.UP: "move_up", Vector2.DOWN: "move_down"}[way])
	Services.world().player.call(&"face", way)
	_push(action, true)
	await physics_frame
	await physics_frame
	_push(&"dodge", true)
	await physics_frame
	await physics_frame
	_push(&"dodge", false)
	await _run(16)
	_push(action, false)


## Walks out of the room through the opening near `at`.
func _through(at: Vector2, action: String, room: String, what: String) -> void:
	_place(at, _way_of(action))
	await _run(6)
	_push(StringName(action), true)
	var ok := await _wait_world(room, 400)
	_push(StringName(action), false)
	await _run(70)
	_check(ok, what)


## Sucks in the nearest thing ahead (Q) and throws it along `way` (Q).
func _suck_and_throw(way: Vector2) -> void:
	var player: Node = Services.world().player
	var mouth: RefCounted = player.call(&"get_mouth")
	player.call(&"face", way)
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	for i in 60:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	_check(bool(mouth.call(&"is_holding")), "the Gulp sucks it in")
	for i in 8:
		await _tick()
	player.call(&"face", way)
	await _tick()
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)


## A clay pot put behind the slime, sucked in and thrown along `way`.
func _throw(way: Vector2) -> void:
	var player: Node = Services.world().player
	player.call(&"face", -way)
	ThrowAmmo.spawn_liftable("clay-pot", _feet() - way * AMMO_BEHIND_PX, {"pop": false})
	await _tick()
	await _suck_and_throw(way)


## Walks up to a chest from below and opens it (interact).
func _open_chest(at: Vector2, chest_name: String) -> void:
	_place(at, Vector2.UP)
	await _run(10)
	_push(&"interact", true)
	await _run(3)
	_push(&"interact", false)
	await _run(120)
	var chest := _node("Objects/" + chest_name)
	_check(chest != null, "the chest " + chest_name)
	# a window on what it holds: taken, as the window's buttons take it
	if chest != null and chest.get_node_or_null(^"ChestScript") != null:
		var chest_script := chest.get_node(^"ChestScript")
		for item: String in (chest_script.call(&"remaining") as Dictionary).keys():
			chest_script.call(&"transfer_stack", item)
	await _run(10)
	await _close_chest_window()


# --- helpers -------------------------------------------------------------------------------------

func _world() -> String:
	return Services.world().map_id()


func _feet() -> Vector2:
	return Services.world().player_body.global_position


func _level() -> int:
	var elevation: Node = Services.world().elevation
	return int(elevation.call(&"level_of", Services.world().player_body)) if elevation != null else 0


func _health() -> float:
	var player: Node = Services.world().player
	return float((player.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


func _node(path: String) -> Node:
	return Services.world().world_root.get_node_or_null(path)


func _place(at: Vector2, facing: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var body := world.player_body
	player.call(&"teleport", at * CELL + ((player.call(&"get_centre") as Vector2) - body.global_position))
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	if world.elevation != null:
		world.elevation.call(&"track", body)
	player.call(&"face", facing)


func _way_of(action: String) -> Vector2:
	return {"move_up": Vector2.UP, "move_down": Vector2.DOWN, "move_left": Vector2.LEFT, "move_right": Vector2.RIGHT}.get(action, Vector2.DOWN)


func _hold(action: String, ms: float) -> void:
	_push(StringName(action), true)
	await _run(int(ms / 1000.0 * 60.0))
	_push(StringName(action), false)
	await _run(8)


func _wait_world(room: String, frames: int) -> bool:
	var want := room if room.begins_with(W) or room.begins_with("crystal-caverns-") else W + room
	for i in frames:
		var world := Services.world()
		if world != null and world.map_id() == want and world.player_body != null and is_instance_valid(world.player_body):
			return true
		await physics_frame
	return false


func _check_ok(ok: bool, what: String) -> bool:
	_check(ok, what)
	return ok


func _check(ok: bool, what: String) -> void:
	_log.append({"check": what, "ok": ok, "world": _world(), "at": (_feet() / CELL).snapped(Vector2(0.1, 0.1)), "level": _level()})
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


## A picture of the step (the walk's), named `<nn>-<name>.png`, with `caption` over it.
func _note(name: String, caption: String) -> void:
	_caption.text = caption
	for i in 4:
		await RenderingServer.frame_post_draw
	if _film != "walk":
		return
	_shot += 1
	var file := "%02d-%s.png" % [_shot, name]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(file)))
	_log.append({"shot": file, "caption": caption, "world": _world(), "at": (_feet() / CELL).snapped(Vector2(0.1, 0.1)), "level": _level(), "hp": _health()})


func _shoot(file: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(file)))


func _run(frames: int) -> void:
	for i in frames:
		await _tick()


## One physics step; while filming, every `_every`-th one is saved. The enemies stay calm and the
## slime's health full.
func _tick() -> void:
	await physics_frame
	_step += 1
	if _step % 10 == 0:
		_calm()
	if not _filming or _step % _every != 0:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	var now := Services.now_ms()
	if _start_ms < 0.0:
		_start_ms = now
	var cart := _node("Objects/m7-ore-cart")
	var target := _node("Objects/m7-cart-target")
	var gate := _node("Objects/m7-rail-gate")
	_rows.append({"frame": _index, "ms": int(now - _start_ms), "world": _world(),
		"cart": str(cart.call(&"state_name")) if cart != null else "-",
		"target": str(target.call(&"state_name")) if target != null else "-",
		"gate": "burst" if gate != null and bool(gate.call(&"is_smashed")) else "shut"})
	_index += 1


func _calm() -> void:
	for enemy: Node in get_nodes_in_group(&"enemy"):
		enemy.set(&"targeting_radius", 0.0)
		enemy.set(&"attack_range", 0.0)
	var player: Node = Services.world().player if Services.world() != null else null
	if _heal and player != null and is_instance_valid(player) and player.has_method(&"heal"):
		player.call(&"heal", 999)
		# the Lantern's flames and the Spear spend energy: kept full too (the walk proves the way)
		if player.has_method(&"restore_energy"):
			player.call(&"restore_energy", 999.0)


## The camera stands still over `at` at `zoom`.
func _still_camera(at: Vector2, zoom: float) -> void:
	var camera: Node = Services.world().camera
	if camera == null:
		return
	camera.call(&"stop_follow")
	camera.set(&"use_bounds", false)
	camera.set(&"center", at)
	camera.set(&"target_zoom", zoom)
	if camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", zoom)


func _hide_hints() -> void:
	for child: Node in _main.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("control_hints.gd"):
			child.set(&"visible", false)
			child.set_process(false)


func _make_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(10.0, 8.0)
	_caption.add_theme_font_size_override(&"font_size", 16)
	_caption.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.6))
	_caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override(&"outline_size", 5)
	layer.add_child(_caption)


func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

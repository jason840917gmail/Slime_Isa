extends SceneTree
## Plays the rebuilt Weaver Hollow's Trunk, Roots, Boughs and Crown (step 3 of the dungeons rework; the rooms:
## tools/build_weaver_hollow_rooms.gd, the list of links: docs/handover/2026-11-23-dungeons-rework.md
## "Step 3") in the running game, the designed way: doors pushed through (the screen scrolls), Goo
## Bombs cast from the Ability Box, pots and bombs sucked in and thrown with the Gulp, chests opened,
## the winch pushed, the key door opened with key 1. Run windowed (it renders), one at a time:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/film_weaver_hollow_rooms.gd -- --film=<walk|ram|wall-walk> --out=<dir> [--every=<n>]
## - `walk`: the whole way from the forecourt (`gloop-forest-f4`): a Goo Bomb blows the Watch Oak's root
##   gate, in through it to T1, the Trunk, the Roots, the Boughs (Pearl 2, the big key) and the Crown
##   (her fight ended by the tool), C3's drop to the forecourt, in through the gate again and out by
##   T1's way out to the gate, a picture a step
##   (`<nn>-<step>.png`) and `walk.json`: each step's world, the slime's spot, level and health, and
##   what it checked (a door led on, a lock opened, a wrong way refused). The film's last line says PASS
##   or FAIL.
## - `ram`: R3's lesson filmed (every `--every`-th physics step a frame `f<nnn>.png`): in from R2, a pot
##   thrown over the void at the target, the ram's swing bursting the bricked arch, up the Guard's stair.
## - `wall-walk`: the wall-walk filmed: out of the Guard's stair on T4's ledge, into T3's walk, a bomb
##   thrown over the gap at the cracked post, the bridge coming down, across it into the hub's gallery
##   and key 1, then a drop off the gallery onto the floor (unhurt).
## - `warden-ram`: B5's lesson filmed: the Warden on the ram's lane, a pot at the target, knocked flat,
##   a Spear thrust while he lies there, his rise.
## - `webbed-slab`: B2's rafters filmed: without the Silk skin a Roll sticks on the webbed slab and falls
##   with it; with the skin it rolls across.
## - `--from=boughs` (with `walk`): the walk starts at the hub's south door (key 1 given);
##   `--from=crown`: at the hub's Crown Door (refused first, the winch turned; then the big key, key 3 and the Silk skin
##   given, the Hollow sealed as Pearl 2 leaves it, its entrance T1 recorded).
## - `look`: a still picture of a room in the game, `look-<room>.png` (`--world=<room name>`,
##   `--at=<x>,<y>` cells, `--zoom=<z>`, `--slime=<x>,<y>` where the slime stands): its ground edges and
##   lights, which the editor render lacks.
## Staging: the slime is put near each step's spot (the rooms are big), never through a lock; every
## lock is opened by playing it.

const Services := preload("res://game/shared/services.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const CELL := 64.0
const GOO_BOMBS := &"goo-bombs"
const MAIN_SCENE := "res://game/main.tscn"
const W := "weaver-hollow-"
const DUNGEON_ID := "weaver-hollow"
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 1200.0
const AMMO_BEHIND_PX := 34.0
## The forecourt and its root gate (the Hollow's way in since the switch-over, 2026-11-25).
const FORECOURT := "gloop-forest-f4"
const ROOT_GATE := "weaver-hollow-forecourt/root-gate"

var _main: Node
var _out := "user://weaver-hollow-rooms"
var _film := "walk"
## `--from=boughs`: the walk starts at the hub's south door (key 1 given), not in T1.
var _from := ""
var _every := 3
var _filming := false
var _step := 0
var _index := 0
var _shot := 0
var _log: Array = []
var _fails: Array = []
var _caption: Label
var _line := ""
## The slime's health kept full (off while a drop is checked for damage).
var _heal := true
## `--film=look`: the world, the point (cells) and the zoom of a still picture of a room in the game.
var _look_world := "t2-hollow-heart"
var _look_at := Vector2(18.0, 16.0)
var _look_zoom := 0.6
## `--slime=<x>,<y>` (cells): where the slime stands in the still (default: a cell below `--at`).
var _look_slime := Vector2.INF


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--film="):
			_film = arg.trim_prefix("--film=")
		elif arg.begins_with("--from="):
			_from = arg.trim_prefix("--from=")
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
		elif arg.begins_with("--every="):
			_every = maxi(1, int(arg.trim_prefix("--every=")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_weaver_hollow_rooms: gave up after %d s" % int(WATCHDOG_S))
		_finish())
	DisplayServer.window_set_size(WINDOW)
	var start := W + ("r2-bone-cellar" if _film == "ram" else "t4-well-room" if _film == "wall-walk" 		else "b5-wardens-den" if _film == "warden-ram" else "b2-drawbridge" if _film == "webbed-slab" 		else "t2-hollow-heart" if _film == "walk" and (_from == "boughs" or _from == "crown") 		else _look_world if _film == "look" else "t1-root-door")
	if _film == "walk" and _from.is_empty():
		start = FORECOURT
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
		"ram":
			await _ram()
		"wall-walk":
			await _wall_walk()
		"look":
			await _look()
		"warden-ram":
			await _warden_ram()
		"webbed-slab":
			await _webbed_slab()
		_:
			push_error("film_weaver_hollow_rooms: no film " + _film)
	_finish()


func _finish() -> void:
	var report := {"film": _film, "fails": _fails, "steps": _log}
	var file := FileAccess.open(ProjectSettings.globalize_path(_out.path_join(_film + ".json")), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("film_weaver_hollow_rooms: %s %s (%d checks failed)" % [_film, "PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	for fail: String in _fails:
		print("  FAIL ", fail)
	quit(0 if _fails.is_empty() else 1)


# --- the walk ------------------------------------------------------------------------------------

func _walk() -> void:
	if _from == "boughs":
		DungeonState.add_small_key(Services.run(), DUNGEON_ID, 1)
		await _key_door_south()
		await _walk_boughs()
		await _walk_crown(true)
		return
	if _from == "crown":
		_place(Vector2(17.0, 2.8), Vector2.UP)
		await _run(20)
		await _crown_door_refused()
		# the winch turned, as on the way to key 1 (the stair block sunk for good)
		_place(Vector2(22.2, 4.6), Vector2.UP)
		await _hold("move_up", 1600)
		var run := Services.run()
		DungeonState.give_item(run, DUNGEON_ID, DungeonState.BIG_KEY)
		DungeonState.add_small_key(run, DUNGEON_ID, 1)
		SkinState.lend(&"silk")
		DungeonState.seal(run, DUNGEON_ID, "orb-weaver-matron")
		# the entrance, as walking in through T1 records it (a faint wakes the slime there)
		DungeonState.set_entrance(run, DUNGEON_ID, W + "t1-root-door", Vector2(9.0, 11.5) * CELL)
		await _run(30)
		await _walk_crown(false)
		return
	# the forecourt: a Goo Bomb blows the root gate, and in through it
	await _in_through_the_gate(true)
	# T1: the way in; north into the hub
	await _note("t1", "T1 Root Door: the loft's chest in sight, floor webs")
	_check(_world() == W + "t1-root-door", "in T1 through the root gate")
	_check(str(DungeonState.entrance(Services.run(), DUNGEON_ID).get("map_id", "")) == W + "t1-root-door",
		"T1 records itself as the Hollow's entrance (a faint wakes the slime there)")
	await _through(Vector2(8, 3.2), "move_up", "t2-hollow-heart", "T1 north doorway to the hub")
	await _note("t2-floor", "T2 the Hollow Heart: key 1 and the Crown Door on the gallery, the stair blocked")
	# the stair is shut by its block: pushing up it from the floor goes nowhere
	_place(Vector2(25, 8.4), Vector2.UP)
	await _hold("move_up", 900)
	_check(_level() == 0 and _feet().y > 7.0 * CELL, "the gallery stair's block stops the slime (level %d, y %.0f)" % [_level(), _feet().y])
	await _note("t2-block", "T2: the stone block at the stair's foot")
	# the key door wants key 1
	_place(Vector2(9, 28.4), Vector2.DOWN)
	await _hold("move_down", 700)
	_check(_world() == W + "t2-hollow-heart" and _feet().y < 30.0 * CELL, "the south key door holds without key 1")
	# west through the floor doorway into T3
	await _through(Vector2(3.2, 28.0), "move_left", "t3-larder", "T2 west floor doorway to T3")
	await _note("t3", "T3 the Larder: two orb-weavers; the walk above, its bridge raised")
	# the walk's south part cannot be reached from the floor
	_place(Vector2(12.0, 8.0), Vector2.RIGHT)
	await _hold("move_right", 700)
	_check(_level() == 0, "T3's walk is out of reach from the floor (level %d)" % _level())
	# the map: the west crack, the nook
	_place(Vector2(3.0, 6.0), Vector2.LEFT)
	await _bomb(Vector2.LEFT, 3400)
	_check(Services.run().has_flag("weaver-hollow.t3-crack-nook"), "a Goo Bomb blows T3's west crack")
	await _note("t3-nook-crack", "T3: the west crack blown")
	await _through(Vector2(2.6, 6.0), "move_left", "t3-map-nook", "T3 west crack to the map nook")
	await _open_chest(Vector2(4.0, 4.1), "t3-map-chest")
	_check(DungeonState.has_item(Services.run(), DUNGEON_ID, DungeonState.MAP), "the map from the nook's chest")
	await _note("t3-map", "The map nook: the map")
	await _through(Vector2(7.4, 4.0), "move_right", "t3-larder", "the nook back to T3")
	# north: the crack into T4
	_place(Vector2(8.0, 3.0), Vector2.UP)
	await _bomb(Vector2.UP, 3400)
	_check(Services.run().has_flag("weaver-hollow.t3-crack-well"), "a Goo Bomb blows T3's north crack")
	await _through(Vector2(8.0, 2.6), "move_up", "t4-well-room", "T3 north crack to T4")
	await _note("t4", "T4 the Well Room: the cracked floor; the ledge with the Guard's stair, out of reach")
	_place(Vector2(12.0, 7.0), Vector2.RIGHT)
	await _hold("move_right", 700)
	_check(_level() == 0, "T4's ledge is out of reach from the floor (level %d)" % _level())
	# the cracked floor: the one-way fall to R1
	_place(Vector2(6.5, 8.0), Vector2.UP)
	await _bomb(Vector2.UP, 3400)
	_check(Services.run().has_flag("weaver-hollow.t4-well-floor"), "a Goo Bomb breaks T4's floor")
	await _run(90)
	await _note("t4-hole", "T4: the floor broken")
	_place(Vector2(6.5, 7.7), Vector2.UP)
	_push(&"move_up", true)
	await _wait_world("r1-root-fall", 300)
	_push(&"move_up", false)
	await _wait_world("r1-root-fall", 900)
	_check(_world() == W + "r1-root-fall", "the hole drops the slime into R1")
	await _run(90)
	_check(_level() == 1, "R1: the slime lands on the ledge (level %d)" % _level())
	await _note("r1", "R1 Root Fall: on the landing ledge over the egg sac")
	# down the ledge's stair, east into R2
	_place(Vector2(4.0, 4.0), Vector2.DOWN)
	await _run(20)
	await _hold("move_down", 2000)
	_check(_level() == 0 and _feet().y > 6.5 * CELL, "down R1's stair to the floor (level %d)" % _level())
	await _through(Vector2(15.4, 8.0), "move_right", "r2-bone-cellar", "R1 east to R2")
	await _note("r2", "R2 the Bone Cellar: the Watcher Eye among the pillars, two Bone Throwers")
	# the compass behind the north crack
	_place(Vector2(10.0, 3.0), Vector2.UP)
	await _bomb(Vector2.UP, 3400)
	_check(Services.run().has_flag("weaver-hollow.r2-crack-pocket"), "a Goo Bomb blows R2's north crack")
	await _through(Vector2(10.0, 2.6), "move_up", "r2-compass-pocket", "R2 north crack to the compass pocket")
	await _open_chest(Vector2(5.0, 3.9), "r2-compass-chest")
	_check(DungeonState.has_item(Services.run(), DUNGEON_ID, DungeonState.COMPASS), "the compass from R2's pocket")
	await _note("r2-compass", "R2's pocket: the compass")
	await _through(Vector2(5.0, 5.4), "move_down", "r2-bone-cellar", "the pocket back to R2")
	await _through(Vector2(33.4, 8.0), "move_right", "r3-ram-cellar", "R2 east to R3")
	await _ram_lesson()
	await _wall_walk_steps()
	# key 1 opens the south door, and the way on to the Boughs
	await _key_door_south()
	await _walk_boughs()
	await _walk_crown(true)


## R3's lesson: the target thrown at over the void, the ram, the arch, the Guard's stair up.
func _ram_lesson() -> void:
	await _note("r3", "R3 the Ram Cellar: the ram before the bricked arch, its target across the void")
	var arch := _node("Objects/r3-arch")
	var target := _node("Objects/r3-target")
	_check(arch != null and target != null, "R3 has its arch and its target")
	# the stair behind the arch is shut to the slime while the arch stands
	_place(Vector2(11.0, 2.4), Vector2.UP)
	await _hold("move_up", 800)
	_check(_world() == W + "r3-ram-cellar", "the bricked arch holds the stair")
	# a pot thrown over the void from its west rim
	_place(Vector2(7.2, 12.0), Vector2.RIGHT)
	await _run(20)
	_filming = _film == "ram"
	await _throw(Vector2.RIGHT)
	await _run(150)
	_check(str(target.call(&"state_name")) != "armed" if target != null else false, "the pot knocks the target (%s)" % (str(target.call(&"state_name")) if target != null else "-"))
	await _run(120)
	_check(arch != null and bool(arch.call(&"is_burst")), "the ram bursts the bricked arch")
	await _note("r3-burst", "R3: the ram swung and burst the arch")
	await _run(60)
	# up the Guard's stair: out on T4's ledge
	_place(Vector2(11.0, 2.6), Vector2.UP)
	await _hold("move_up", 900)
	await _wait_world("t4-well-room", 900)
	_filming = false
	_check(_world() == W + "t4-well-room", "the Guard's stair climbs to T4")
	await _run(120)
	_check(_level() == 1 and _feet().x > 12.9 * CELL, "out of the stair on T4's ledge (level %d, x %.0f)" % [_level(), _feet().x])
	await _note("t4-ledge", "T4: out on the ledge, above the room the slime left")


## The wall-walk: T4's ledge, T3's walk and its bridge, the hub's gallery, key 1, the winch, the drop.
func _wall_walk_steps() -> void:
	_filming = _film == "wall-walk"
	await _through(Vector2(14.0, 13.4), "move_down", "t3-larder", "T4's ledge into T3's walk")
	_check(_level() == 1, "into T3 on the walk (level %d)" % _level())
	await _note("t3-walk", "T3's walk: the gap, the bridge raised on the far rim, its cracked post")
	# a bomb spat at the gap's edge, sucked in, thrown over the gap at the post
	_place(Vector2(15.3, 3.5), Vector2.DOWN)
	await _run(10)
	await _bomb(Vector2.DOWN, 0)
	await _run(12)
	await _suck_and_throw(Vector2.DOWN)
	await _run(240)
	var bridge := _node("Objects/t3-bridge")
	_check(bridge != null and bool(bridge.call(&"is_down_for_good")), "the bomb over the gap breaks the post: the bridge comes down")
	await _note("t3-bridge", "T3: the bridge down across the gap")
	_place(Vector2(14.0, 3.6), Vector2.DOWN)
	await _hold("move_down", 1500)
	_check(_level() == 1 and _feet().y > 7.0 * CELL, "over the bridge to the walk's south part (level %d, y %.0f)" % [_level(), _feet().y])
	await _through(Vector2(15.4, 8.0), "move_right", "t2-hollow-heart", "T3's walk into the hub's west gallery")
	_check(_level() == 1, "into the hub on the gallery (level %d)" % _level())
	await _open_chest(Vector2(3.6, 20.4), "t2-key-chest")
	_check(DungeonState.small_keys(Services.run(), DUNGEON_ID) >= 1, "key 1 from the gallery's chest")
	await _note("t2-key", "T2's west gallery: key 1")
	# up the gallery to the winch: it sinks the stair block
	_place(Vector2(22.2, 4.6), Vector2.UP)
	await _hold("move_up", 1600)
	var block := _node("Objects/t2-stair-block")
	_check(block != null and not bool(block.call(&"is_shut")), "the winch sinks the stair block")
	await _note("t2-winch", "T2: the winch turned, the stair block sunk")
	if _film == "walk":
		await _crown_door_refused()
	_place(Vector2(24.9, 5.2), Vector2.DOWN)
	await _hold("move_down", 1400)
	_check(_level() == 0 and _feet().y > 7.0 * CELL, "down the gallery's stair to the floor (level %d)" % _level())
	_filming = false
	# a drop off the gallery lands unhurt
	_place(Vector2(3.4, 12.0), Vector2.RIGHT)
	await _run(10)
	_heal = false
	var hp := _health()
	await _hold("move_right", 1600)
	_heal = true
	_check(_level() == 0 and is_equal_approx(_health(), hp), "a drop off the west gallery lands on the floor unhurt (level %d, hp %.0f -> %.0f)" % [_level(), hp, _health()])
	await _note("t2-drop", "T2: a drop off the gallery lands on the floor, unhurt")


## A still picture of a room in the game (its ground edges, lights, enemies): `look.png`.
func _look() -> void:
	_place(_look_slime if _look_slime.is_finite() else _look_at + Vector2(0.0, 1.0), Vector2.DOWN)
	await _run(40)
	_still_camera(_look_at * CELL, _look_zoom)
	await _run(40)
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("look-%s.png" % _look_world)))


func _ram() -> void:
	await _through(Vector2(33.4, 8.0), "move_right", "r3-ram-cellar", "R2 east to R3")
	# the whole room in the picture (the arch is a room's height from the void)
	_still_camera(Vector2(9.0, 7.6) * CELL, 0.78)
	_filming = true
	await _run(40)
	await _ram_lesson()


func _wall_walk() -> void:
	# from T4's floor, as after the Guard's stair: put on the ledge by its stair
	_place(Vector2(14.0, 3.4), Vector2.DOWN)
	await _run(30)
	_check(_level() == 1, "on T4's ledge (level %d)" % _level())
	await _wall_walk_steps()


# --- the Boughs (the second piece) -----------------------------------------------------------------

## From the hub's south door (key 1 spent) up through the Boughs to the big key, the drop back onto the
## hub's gallery, and the Silk skin's locks in the Trunk (the east gallery's web wall, T1's loft).
func _walk_boughs() -> void:
	await _note("stair-foot", "The stair foot: the Guard's stair up to the Boughs")
	_place(Vector2(14.0, 2.6), Vector2.UP)
	await _hold("move_up", 900)
	var up := await _wait_world("b1-bough-stair", 900)
	_check(up, "the stair foot's stair climbs to B1")
	await _run(120)
	await _note("b1", "B1 the Bough Stair: a Silk Lurker, floor webs")
	await _through(Vector2(8.0, 2.6), "move_up", "b2-drawbridge", "B1 north into B2")
	await _note("b2", "B2 the Drawbridge: the void, the bridge raised on this rim, chained to the post across")
	# the void holds without the bridge (a push long enough drops the slime in: it is put back on the rim)
	_place(Vector2(16.4, 11.0), Vector2.RIGHT)
	await _hold("move_right", 600)
	await _run(150)
	_check(_feet().x < 17.0 * CELL, "the void stops the way east (x %.0f)" % _feet().x)
	# a bomb spat away from the void, sucked in, thrown over the void at the post
	_place(Vector2(16.3, 9.6), Vector2.LEFT)
	await _run(10)
	await _bomb(Vector2.LEFT, 0)
	await _run(14)
	await _suck_and_throw(Vector2.RIGHT, Vector2.LEFT)
	await _run(240)
	var bridge := _node("Objects/b2-bridge")
	_check(bridge != null and bool(bridge.call(&"is_down_for_good")), "a bomb over the void breaks B2's post: the bridge comes down")
	await _note("b2-bridge", "B2: the bridge down across the void")
	_place(Vector2(16.2, 7.6), Vector2.RIGHT)
	await _hold("move_right", 2300)
	_check(_feet().x > 21.2 * CELL, "over B2's bridge to the east rim (x %.0f)" % _feet().x)
	# the Warden's door wants key 2
	_place(Vector2(33.2, 8.0), Vector2.RIGHT)
	await _hold("move_right", 800)
	_check(_world() == W + "b2-drawbridge", "the Warden's door holds without key 2")
	# the rafters are out of reach from the floor
	_place(Vector2(10.0, 5.2), Vector2.UP)
	await _hold("move_up", 700)
	_check(_level() == 0, "B2's rafters are out of reach from the floor (level %d)" % _level())
	# B3: the Mimic, key 2
	await _through(Vector2(2.6, 8.0), "move_left", "b3-mimics-pantry", "B2 west into B3")
	await _note("b3", "B3 the Mimic's Pantry: the big chest on the rafters, in sight; a cocoon that breathes")
	_place(Vector2(8.0, 6.2), Vector2.UP)
	await _hold("move_up", 700)
	_check(_level() == 0, "B3's rafters are out of reach from the floor (level %d)" % _level())
	var keys_before := DungeonState.small_keys(Services.run(), DUNGEON_ID)
	await _beat("cocoon-mimic")
	await _run(120)
	await _take_floor_key()
	_check(DungeonState.small_keys(Services.run(), DUNGEON_ID) > keys_before, "the Mimic, beaten, spits key 2")
	await _note("b3-key", "B3: the Mimic beaten, key 2")
	# key 2 in the Warden's door
	await _through(Vector2(15.4, 8.0), "move_right", "b2-drawbridge", "B3 back into B2")
	await _through(Vector2(33.4, 8.0), "move_right", "b5-wardens-den", "key 2 opens the Warden's door into B5")
	await _note("b5", "B5 the Warden's Den: the Brood Warden; the ram across the den, its target in line")
	await _ram_on_warden()
	await _beat("brood-warden")
	await _beat("egg-sac")
	await _beat("broodling")
	await _run(120)
	var hoard_shutter := _node("Objects/b5-hoard-shutter")
	_check(hoard_shutter != null and not bool(hoard_shutter.call(&"is_shut")), "the Warden beaten: the Hoard's shutter sinks")
	await _through(Vector2(8.0, 2.6), "move_up", "hoard", "B5 north into the Hoard")
	await _note("hoard", "The Hoard: Pearl 2 on the brood's altar; the loft's stair behind a web wall")
	# the loft is the Silk skin's: its web wall holds without it
	_place(Vector2(4.0, 12.4), Vector2.UP)
	await _hold("move_up", 900)
	_check(_feet().y > 11.0 * CELL, "the loft stair's web wall holds without the Silk skin (y %.0f)" % _feet().y)
	# the Pearl: the Silk skin, the seal
	_place(Vector2(11.5, 7.9), Vector2.UP)
	await _hold("move_up", 400)
	await _run(240)
	_check(SkinState.is_won(&"silk"), "Pearl 2 taken: the Silk skin")
	_check(DungeonState.is_sealed(Services.run(), DUNGEON_ID), "the take seals the Hollow")
	await _note("hoard-pearl", "The Hoard: Pearl 2 taken, the Silk skin; the way out sealed")
	# the Rafter Run
	_place(Vector2(4.0, 12.4), Vector2.UP)
	await _hold("move_up", 2600)
	_check(_level() == 1 and _feet().y < 10.0 * CELL, "the Silk slime wades the web wall and climbs to the loft (level %d)" % _level())
	await _through(Vector2(2.6, 8.0), "move_left", "b6-spinning-loft", "the Hoard's loft west into the Spinning Loft")
	await _note("b6", "B6 the Spinning Loft: rows of web walls, Slime Spiders, key 3 in its parcel")
	_place(Vector2(14.4, 7.4), Vector2.UP)
	await _hold("move_up", 1500)
	_check(_feet().y < 6.0 * CELL, "the Silk slime wades the north row of webs (y %.0f)" % _feet().y)
	var keys_loft := DungeonState.small_keys(Services.run(), DUNGEON_ID)
	var parcel := _node("Objects/b6-key-parcel")
	if parcel != null:
		parcel.call(&"free_parcel")
	await _run(90)
	await _take_floor_key()
	_check(DungeonState.small_keys(Services.run(), DUNGEON_ID) > keys_loft, "key 3 from the Spinning Loft's parcel")
	await _note("b6-key", "B6: key 3")
	_place(Vector2(10.0, 4.6), Vector2.DOWN)
	await _hold("move_down", 3600)
	_check(_feet().y > 10.0 * CELL, "the Silk slime wades both rows down to the south corridor (y %.0f)" % _feet().y)
	await _through(Vector2(10.0, 13.4), "move_down", "b2-drawbridge", "the Spinning Loft south onto B2's rafters")
	_check(_level() == 1, "onto B2's rafters at level 1 (level %d)" % _level())
	await _note("b2-rafters", "B2's rafters: the webbed slabs over the void")
	await _cross_slabs()
	_check(_world() == W + "b2-drawbridge" and _level() == 1 and _feet().x < 17.0 * CELL,
		"the Silk slime rolls over the webbed slabs to the west rafters (x %.0f, level %d)" % [_feet().x, _level()])
	await _through(Vector2(2.6, 3.0), "move_left", "b3-mimics-pantry", "B2's rafters west onto B3's rafters")
	_check(_level() == 1, "onto B3's rafters at level 1 (level %d)" % _level())
	await _open_chest(Vector2(5.5, 4.5), "b3-big-chest")
	_check(DungeonState.has_item(Services.run(), DUNGEON_ID, DungeonState.BIG_KEY), "the big key from B3's rafters")
	await _note("b3-big-key", "B3's rafters: the big key")
	_place(Vector2(9.4, 3.4), Vector2.RIGHT)
	_push(&"move_right", true)
	var fell := await _wait_world("t2-hollow-heart", 500)
	_push(&"move_right", false)
	_check(fell, "the rafters' hole drops the slime into the hub")
	await _run(120)
	_check(_level() == 1 and _feet().y < 6.0 * CELL, "on the hub's north gallery by the Crown Door (level %d, y %.0f)" % [_level(), _feet().y])
	await _note("t2-gallery-drop", "The hub's gallery: down from the rafters, the Crown Door in front (the next piece)")
	# the Silk skin's locks in the Trunk: the east gallery's web wall, T1's loft
	_place(Vector2(29.4, 4.0), Vector2.RIGHT)
	await _hold("move_right", 1500)
	_check(_feet().x > 31.0 * CELL, "the Silk slime wades the east gallery's web wall (x %.0f)" % _feet().x)
	await _through(Vector2(31.8, 29.4), "move_down", "t1-root-door", "the east gallery down into T1's loft")
	_check(_level() == 1, "into T1's loft at level 1 (level %d)" % _level())
	await _open_chest(Vector2(13.5, 4.5), "t1-loft-chest")
	await _note("t1-loft", "T1's loft: the chest seen from the floor in the first minute")


# --- the Crown (the third piece) -------------------------------------------------------------------

## The Crown Door (the hub's north gallery) refuses the slime without the big key.
func _crown_door_refused() -> void:
	_place(Vector2(17.0, 2.8), Vector2.UP)
	await _run(10)
	await _hold("move_up", 800)
	_check(_world() == W + "t2-hollow-heart" and _feet().y > 2.0 * CELL, "the Crown Door holds without the big key (y %.0f)" % _feet().y)


## From T1's loft (`from_loft`) back to the hub's gallery, the Crown Door (the big key), C1: up through
## the floor webs and the web wall at the flight's foot, the key 3 door (refused without key 3); C2: she
## wakes, the shutter shuts, the seal holds the east doorway, her fight ended by the tool, the shutter
## open and the seals sunk; C3: her web wall, the hole out to the forecourt; then T1's way out open.
func _walk_crown(from_loft: bool) -> void:
	if from_loft:
		await _through(Vector2(14.0, 2.6), "move_up", "t2-hollow-heart", "T1's loft north into the hub's east gallery")
		_check(_level() == 1, "into the hub on the east gallery (level %d)" % _level())
	# along the north gallery to the Crown Door
	await _through(Vector2(17.0, 2.8), "move_up", "c1-crown-stair", "the big key opens the Crown Door: into C1")
	_check(_level() == 0, "into C1 on its floor (level %d)" % _level())
	await _note("c1", "C1 the Crown Stair: floor webs wall to wall, the flight up choked by a web wall")
	_place(Vector2(9.0, 12.4), Vector2.UP)
	await _run(10)
	await _hold("move_up", 3200)
	_check(_level() == 1 and _feet().y < 7.6 * CELL,
		"the Silk slime wades the floor webs and the web wall, up the flight (level %d, y %.0f)" % [_level(), _feet().y])
	await _note("c1-top", "C1's top: four pots by the key 3 door, the calm spot before her")
	# the key 3 door without key 3 (staged: the key taken from the record, then given back)
	var run := Services.run()
	var spent := DungeonState.spend_small_key(run, DUNGEON_ID)
	_place(Vector2(9.0, 3.0), Vector2.UP)
	await _run(10)
	await _hold("move_up", 900)
	_check(spent and _world() == W + "c1-crown-stair" and _feet().y > 2.0 * CELL,
		"the key 3 door holds without key 3 (keys %d)" % DungeonState.small_keys(run, DUNGEON_ID))
	if spent:
		DungeonState.add_small_key(run, DUNGEON_ID, 1)
	await _through(Vector2(9.0, 2.8), "move_up", "c2-crown", "key 3 opens the key 3 door: into C2, the Crown")
	await _note("c2", "C2 the Crown: her arena as her lab has it, five rams and their targets")
	# she wakes as the slime walks in; the shutter shuts behind it
	await _hold("move_up", 700)
	var matron := await _matron()
	_check(matron != null, "she wakes as the slime walks in")
	await _run(60)
	var shutter := _node("Objects/c2-crown-shutter")
	_check(shutter != null and bool(shutter.call(&"is_shut")), "the boss shutter shuts behind the slime")
	_place(Vector2(10.0, 16.8), Vector2.DOWN)
	await _run(10)
	await _hold("move_down", 800)
	_check(_world() == W + "c2-crown", "the shut shutter holds the way back while she stands")
	await _note("c2-shut", "C2: she is up in her cocoon, the shutter shut behind the slime")
	# a faint in her fight wakes the slime at T1; the way back up is short, every lock on it open for good
	_heal = false
	Services.world().player.call(&"commit_damage", {"result": {"actual_damage": 9999}})
	var woke := await _wait_world("t1-root-door", 1200)
	await _run(150)
	_heal = true
	_check(woke, "a faint in her fight wakes the slime at T1, the Hollow's entrance")
	var keys := DungeonState.small_keys(run, DUNGEON_ID)
	var back_from := Services.now_ms()
	await _through(Vector2(8.0, 3.2), "move_up", "t2-hollow-heart", "back up: T1 north into the hub")
	_place(Vector2(25.0, 8.6), Vector2.UP)
	await _run(10)
	# the stair walk is slow (two steps a stair): held until it is done (a slime on a stair ignores a
	# placing)
	await _hold("move_up", 2600)
	await _run(30)
	_check(_level() == 1 and _feet().y < 5.6 * CELL, "back up: the gallery's stair, its block sunk for good (level %d, y %.0f)" % [_level(), _feet().y])
	await _through(Vector2(17.0, 2.8), "move_up", "c1-crown-stair", "back up: the Crown Door stands open")
	_place(Vector2(9.0, 12.4), Vector2.UP)
	await _run(10)
	await _hold("move_up", 3200)
	_check(_level() == 1, "back up: C1's flight (level %d)" % _level())
	await _through(Vector2(9.0, 2.8), "move_up", "c2-crown", "back up: the key 3 door stands open")
	_check(DungeonState.small_keys(run, DUNGEON_ID) == keys, "no key spent on the way back (%d)" % keys)
	_notes_back(int(Services.now_ms() - back_from))
	await _hold("move_up", 700)
	matron = await _matron()
	_check(matron != null, "she wakes again as the slime walks in")
	await _run(60)
	shutter = _node("Objects/c2-crown-shutter")
	_check(shutter != null and bool(shutter.call(&"is_shut")), "the shutter shuts behind it again")
	# the seal holds the east doorway
	_place(Vector2(20.8, 10.0), Vector2.RIGHT)
	await _run(10)
	await _hold("move_right", 900)
	_check(_world() == W + "c2-crown" and _feet().x < 22.0 * CELL, "the seal holds C2's east doorway while she stands (x %.0f)" % _feet().x)
	await _note("c2-fight", "C2: she is up, the shutter shut, the seal in the east doorway")
	# her fight ended by the tool (filmed in the room by tools/film_crown.gd)
	if matron != null and is_instance_valid(matron):
		matron.set(&"_hp", 0.0)
		matron.call(&"_defeat")
	await _run(360)
	_check("orb-weaver-matron" in (run.world.get("defeated_boss_ids", []) as Array), "her defeat is recorded (defeated_boss_ids)")
	_check(DungeonState.is_boss_beaten(run, DUNGEON_ID, "orb-weaver-matron"), "the Hollow's record: its boss beaten")
	_check(not DungeonState.is_sealed(run, DUNGEON_ID), "her fall breaks the seals")
	_check(shutter != null and not bool(shutter.call(&"is_shut")), "her fall opens the shutter")
	var heart := _node("Objects/matron-camp/FullHeart")
	_check(heart != null and (heart as CanvasItem).is_visible_in_tree(), "her full heart lies in the arena")
	await _note("c2-fallen", "C2: she has fallen; the seals sink, the shutter opens, her full heart")
	await _through(Vector2(21.0, 10.0), "move_right", "c3-outer-bough", "the seal sunk: C2's east doorway into C3")
	await _note("c3", "C3 the Outer Bough: her web wall across the walk, the hole at its end")
	_place(Vector2(3.6, 4.0), Vector2.RIGHT)
	await _run(10)
	await _hold("move_right", 2000)
	_check(_feet().x > 7.0 * CELL, "the Silk slime wades her web wall (x %.0f)" % _feet().x)
	_place(Vector2(12.3, 4.0), Vector2.RIGHT)
	_push(&"move_right", true)
	var fell := await _wait_world("gloop-forest-f4", 600)
	_push(&"move_right", false)
	_check(fell, "C3's hole drops the slime out to the forecourt")
	await _run(120)
	await _note("forecourt", "The forecourt: down from the Outer Bough, by S1's nook")
	# in through the gate again (blown for good), and out by T1's way out, which stands open now
	await _in_through_the_gate(false)
	await _note("t1-open", "T1: the seal sunk, the way out open")
	await _through(Vector2(9.0, 13.2), "move_down", FORECOURT, "T1's way out stands open: out to the forecourt")
	var gate := _node(ROOT_GATE) as Node2D
	_check(gate != null and _feet().distance_to(gate.global_position) < 2.0 * CELL,
		"T1's way out lands at the root gate (%.0f px from it)" % (_feet().distance_to(gate.global_position) if gate != null else -1.0))
	await _note("gate-out", "The forecourt: out of the Hollow at the root gate")


## The forecourt's root gate (gloop-forest-f4, the switch-over of 2026-11-25): the first time a Goo
## Bomb blows its bricks (the Goo Bomb learned for the session: the story has it by Chapter 2, and the
## Hollow's F6 powers are learned only inside), then the slime walks up through it into T1.
func _in_through_the_gate(blow: bool) -> void:
	_check(_world() == FORECOURT, "in the forecourt (%s)" % _world())
	var gate := _node(ROOT_GATE) as Node2D
	if not _check_ok(gate != null, "the forecourt's root gate stands in " + FORECOURT):
		return
	var at := gate.global_position / CELL
	if blow:
		await _note("forecourt-gate", "The forecourt: the Watch Oak's bricked root gate")
		_place(at + Vector2(0.0, 0.7), Vector2.UP)
		await _hold("move_up", 600)
		_check(_world() == FORECOURT, "the bricked gate holds the slime out")
		Services.run().learn_session_ability(String(GOO_BOMBS))
		_place(at + Vector2(0.0, 0.7), Vector2.UP)
		await _run(10)
		await _bomb(Vector2.UP, 3400)
		_check(Services.run().has_flag("weaver-hollow.root-gate"), "a Goo Bomb blows the root gate")
		await _note("forecourt-blown", "The forecourt: the root gate blown")
	await _through(at + Vector2(0.0, 0.7), "move_up", "t1-root-door", "the root gate leads into the rebuilt T1")


func _check_ok(ok: bool, what: String) -> bool:
	_check(ok, what)
	return ok


## The way back up from T1 to her door after a faint: four doors, its game time (staged: the slime is
## put along the floors, never through a lock) in walk.json.
func _notes_back(ms: int) -> void:
	_log.append({"back_up_from_t1": "T1, the hub, the gallery stair, the Crown Door, C1's flight, the key 3 door: 4 doors", "staged_ms": ms})


## The Matron, once her camp has woken her (null after a while without her).
func _matron() -> Node:
	for i in 300:
		for node: Node in get_nodes_in_group(&"enemy"):
			if is_instance_valid(node) and node.has_method(&"get_open_kind"):
				return node
		await _tick()
	return null


## Key 1 in the hub's south door: it opens and the slime walks on through it into the stair foot.
func _key_door_south() -> void:
	_place(Vector2(9.0, 28.6), Vector2.DOWN)
	_push(&"move_down", true)
	var through := await _wait_world("stair-foot", 400)
	_push(&"move_down", false)
	await _run(70)
	_check(through, "key 1 opens the hub's south door: through it into the stair foot")


## B5's lesson: the Warden put on the ram's lane, a pot thrown at the target from beside it.
func _ram_on_warden() -> void:
	var warden := _enemy_of("brood-warden")
	_check(warden != null, "B5 has its Brood Warden")
	if warden == null:
		return
	_place(Vector2(14.5, 9.4), Vector2.DOWN)
	await _run(10)
	# staged: he stands on the lane (his home put there, so a calmed Warden stays on it), as a Warden
	# lured onto the grooves does
	var warden_body := warden.get(&"body") as CharacterBody2D
	if warden_body != null:
		warden_body.global_position = Vector2(9.0, 11.0) * CELL
		warden_body.reset_physics_interpolation()
		warden.set(&"_home", warden.call(&"get_centre"))
	await _run(4)
	await _throw(Vector2.DOWN)
	var knocked := false
	for i in 150:
		await _tick()
		if warden.has_method(&"is_knocked") and bool(warden.call(&"is_knocked")):
			knocked = true
			break
	_check(knocked, "the target lets the ram go: its log knocks the Warden flat")
	await _note("b5-knocked", "B5: the ram's log caught the Warden on its lane: knocked flat, his plates open")


## Every live enemy of `type` in the world beaten (the walk proves the way, not a fight).
func _beat(type: String) -> void:
	for enemy: Node in get_nodes_in_group(&"enemy"):
		if not is_instance_valid(enemy) or str(enemy.get(&"enemy_type")) != type and not String(enemy.name).contains(type):
			continue
		if enemy.has_method(&"take_reaction_damage"):
			enemy.call(&"take_reaction_damage", 99999.0)
	await _run(30)


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


## B2's webbed slabs crossed west the way DUNGEONS.md times them: a quick Roll from the east rim's
## edge (the body clear of the first slab) to the landing, a walk to the landing's far edge (still
## clear of the next slab), the Roll's cooldown, a second Roll onto the west rafters.
func _cross_slabs() -> void:
	# walked along the rafters first (where a fall puts the slime back), then at the rim's edge
	_place(Vector2(24.0, 3.5), Vector2.LEFT)
	await _run(20)
	_place(Vector2(21.3, 3.5), Vector2.LEFT)
	await _run(20)
	await _roll(Vector2.LEFT, false)
	_push(&"move_left", true)
	var waited := 0
	# frame by physics frame (a filmed tick can span several): the stop must not overshoot
	for i in 40:
		await physics_frame
		waited += 1
		# the landing's west edge, the body still clear of the slab beyond (else it starts to give)
		if _feet().x <= 18.0 * CELL + 18.0:
			break
	_push(&"move_left", false)
	# the Roll's cooldown (`rollCooldownMs`, 1 s) runs out on the landing
	await _run(maxi(0, 80 - waited))
	await _roll(Vector2.LEFT, false)
	_push(&"move_left", true)
	await _run(14)
	_push(&"move_left", false)
	await _run(40)


## A Roll along `way` (the dodge key). `hold_on`: the way kept held through the Roll (else let go as
## it launches: the Roll keeps its way, and nothing walks on after it; a filmed tick can span several
## physics frames, so a held key outlasts the Roll).
func _roll(way: Vector2, hold_on := true) -> void:
	var action := StringName({Vector2.LEFT: "move_left", Vector2.RIGHT: "move_right", Vector2.UP: "move_up", Vector2.DOWN: "move_down"}[way])
	Services.world().player.call(&"face", way)
	_push(action, true)
	await physics_frame
	await physics_frame
	_push(&"dodge", true)
	await physics_frame
	await physics_frame
	_push(&"dodge", false)
	if not hold_on:
		await physics_frame
		_push(action, false)
	await _run(16)
	_push(action, false)


## B5's film: the Warden lured onto the lane, the pot at the target, the log, knocked flat, a Spear
## thrust while he lies there, his rise.
func _warden_ram() -> void:
	_filming = true
	await _run(30)
	await _ram_on_warden()
	var warden := _enemy_of("brood-warden")
	if warden != null:
		var hp_before := float((warden.call(&"get_damage_state") as Dictionary).get("hp", 0.0))
		await _run(20)
		hp_before = float((warden.call(&"get_damage_state") as Dictionary).get("hp", 0.0))
		_place((warden.get(&"body") as Node2D).global_position / CELL + Vector2(-0.9, 0.0), Vector2.RIGHT)
		# the strike aims where the slime last pushed: right, at him
		_push(&"move_right", true)
		await _run(3)
		_push(&"move_right", false)
		await _run(2)
		var shapes: Node = _main.get(&"shapes")
		var struck := str(shapes.call(&"power_strike", &"shape-spear")) if shapes != null else "no shapes"
		print("warden: the Spear's strike: ", struck, "; the Warden ", warden.call(&"get_damage_state"), " knocked ", warden.call(&"is_knocked"),
			"; the slime at ", _feet(), " he at ", (warden.get(&"body") as Node2D).global_position)
		await _run(60)
		var hp_after := float((warden.call(&"get_damage_state") as Dictionary).get("hp", 0.0))
		_check(hp_after < hp_before, "knocked flat, the Spear hurts him (%.0f -> %.0f)" % [hp_before, hp_after])
		_place(Vector2(14.5, 6.0), Vector2.DOWN)
		await _run(200)
		_check(not bool(warden.call(&"is_knocked")), "he rises after his window")


## B2's film: the webbed slabs with the Silk skin (two Rolls cross), then without it (a Roll sticks
## in the web on a slab and falls with it; a fall puts the slime back on the rafters).
func _webbed_slab() -> void:
	SkinState.lend(&"silk")
	_place(Vector2(24.0, 3.5), Vector2.LEFT)
	await _run(30)
	_still_camera(Vector2(19.0, 5.0) * CELL, 1.0)
	_filming = true
	await _cross_slabs()
	_check(_level() == 1 and _feet().x < 17.0 * CELL, "with the Silk skin it rolls across (x %.0f, level %d)" % [_feet().x, _level()])
	await _run(30)
	# the fallen slabs come back (`slab.returnMs` 10 s and `riseMs`), unfilmed; the skin given back
	_filming = false
	SkinState.give_back(&"silk")
	await _run(720)
	_place(Vector2(24.0, 3.5), Vector2.LEFT)
	await _run(30)
	_place(Vector2(21.3, 3.5), Vector2.LEFT)
	await _run(10)
	_filming = true
	await _roll(Vector2.LEFT)
	await _run(150)
	var fell := _feet().x > 20.9 * CELL or _level() != 1 or _feet().y > 4.5 * CELL
	_check(fell, "without the Silk skin the Roll sticks on the webbed slab and falls with it (x %.0f, level %d)" % [_feet().x, _level()])
	await _run(40)


# --- acts ----------------------------------------------------------------------------------------

## Puts the slime at `at` (cells) facing `way`, then holds `action` until the world is `room`'s.
func _through(at: Vector2, action: String, room: String, what: String) -> void:
	_place(at, _way_of(action))
	await _run(6)
	_push(StringName(action), true)
	var ok := await _wait_world(room, 400)
	_push(StringName(action), false)
	await _run(70)
	_check(ok, what)


## The Goo Bomb cast facing `way`, then `wait_ms` for its blast (0: no wait).
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
	if wait_ms > 0.0:
		await _run(int(wait_ms / 1000.0 * 60.0))
	else:
		# spat (`spitMs`) and hopped (`hopMs`): resting before anything picks it up
		for i in 90:
			await _tick()
			if not get_nodes_in_group(&"goo_bombs").is_empty():
				break
		await _run(20)


## Sucks in the nearest thing ahead (Q; facing `suck_way` when given) and throws it along `way` (Q).
func _suck_and_throw(way: Vector2, suck_way: Vector2 = Vector2.ZERO) -> void:
	var player: Node = Services.world().player
	var mouth: RefCounted = player.call(&"get_mouth")
	player.call(&"face", way if suck_way == Vector2.ZERO else suck_way)
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	for i in 60:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	if not bool(mouth.call(&"is_holding")):
		for b: Node in get_nodes_in_group(&"goo_bombs"):
			print("suck: a bomb at ", (b as Node2D).global_position, " can_take ", b.call(&"can_take"), "; the slime at ", _feet())
		print("suck: bombs ", get_nodes_in_group(&"goo_bombs").size(), " energy ", (player.call(&"get_damage_state") as Dictionary))
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
	# a chest of several things opens its window (it holds the slime's keys): closed, as Escape does
	for node: Node in root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script != null and script.resource_path.ends_with("chest_window.gd") and node is CanvasItem \
				and (node as CanvasItem).is_visible_in_tree():
			node.call(&"close")
			await _run(20)


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
	var want := room if room.begins_with(W) or room.begins_with("gloop-") else W + room
	for i in frames:
		var world := Services.world()
		if world != null and world.map_id() == want and world.player_body != null and is_instance_valid(world.player_body):
			return true
		await physics_frame
	return false


func _check(ok: bool, what: String) -> void:
	_log.append({"check": what, "ok": ok, "world": _world(), "at": (_feet() / CELL).snapped(Vector2(0.1, 0.1)), "level": _level()})
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


## A picture of the step (the walk's), named `<nn>-<name>.png`, with `caption` over it.
func _note(name: String, caption: String) -> void:
	_line = caption
	_caption.text = caption
	for i in 4:
		await RenderingServer.frame_post_draw
	if _film != "walk":
		return
	_shot += 1
	var file := "%02d-%s.png" % [_shot, name]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(file)))
	_log.append({"shot": file, "caption": caption, "world": _world(), "at": (_feet() / CELL).snapped(Vector2(0.1, 0.1)), "level": _level(), "hp": _health()})


func _run(frames: int) -> void:
	for i in frames:
		await _tick()


## One physics step; while filming, every `_every`-th one is saved. The enemies stay calm and the
## slime's health full: the walk proves the way, not a fight (a faint would put it back at T1).
func _tick() -> void:
	await physics_frame
	_step += 1
	if _step % 10 == 0:
		_calm()
	if not _filming or _step % _every != 0:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	_index += 1


func _calm() -> void:
	for enemy: Node in get_nodes_in_group(&"enemy"):
		enemy.set(&"targeting_radius", 0.0)
		enemy.set(&"attack_range", 0.0)
	var player: Node = Services.world().player if Services.world() != null else null
	if _heal and player != null and is_instance_valid(player) and player.has_method(&"heal"):
		player.call(&"heal", 999)


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

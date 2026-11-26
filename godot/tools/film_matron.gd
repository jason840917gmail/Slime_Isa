extends SceneTree
## Films the Orb-Weaver Matron's ram fight (docs/godot/specs/matron.md section 9;
## game/bosses/matron_ram.gd) in her lab (world.matron-lab, game/dev/bosses/matron-lab.tscn), frame by
## frame, the camera still over the room. Run windowed (it renders) with a fixed frame time, one film
## at a time (or through `scripts/godot/film-matron.sh <name> --film=<film>`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_matron.gd -- \
##         --out=<dir> --film=<name> [--every=<n>] [--zoom=<z>] [--tail=<frames>]
## Films (her health is staged by the tool where a film starts past round 1, and noted):
##   round1    her low cocoon breathes; the slime spits a Goo Bomb under it and backs off; it tears and
##             she falls dazed; the Spear, then a thrown pot (half a Spear hit); her health staged at
##             230, so the hits take her to round 2's floor: she climbs up to hang and rings the
##             targets with web walls
##   dive      round 2: she hangs high, crawls over the slime (in a gap between two lanes) and dives;
##             the slime steps aside (a miss) and she lies `landed_ms` (noted) before she climbs;
##             it stays for the next one (her blow)
##   ground-call round 2, her ram call from the floor: she dives on the slime in the second ram's lane;
##             it steps down the lane and stays; lying there she spits at that lane's target, the
##             slime steps out of the lane and her own log flings her down it (on her back, open);
##             the Spear and a pot
##   ram-catch round 2: the slime baits her over the lower end of the second ram's lane, picks a pot
##             up beside that ram's target (straight below the lane, by the south wall), wades into
##             its web ring (the Silk skin) and throws up at it as she dives: the ram flings her down
##             the lane to the wall (its blow), on her back; the Spear and a thrown pot; she climbs
##             back up
##   ring      round 2: a pot thrown down at the second target from above its ring stops in the silk;
##             the Spear cuts the ring's north wall and the next pot flies through the gap
##   web-balls her missed webs as ammo: the room's pots taken away (staged, noted); round 1, her
##             volley from the cocoon misses the slime (it steps out of the mark) and leaves web
##             balls; the slime sucks one up and throws it at her lane's target from its side: the ram
##             knocks the cocoon down
##   round3    round 3, her last hit (health staged at 20): her high cocoon over a random lane; a
##             blast under it is refused (called by the tool), a pot at that lane's ram's target: the
##             ram knocks the cocoon down; a Goo Bomb on it tears it, she spills out dazed and one
##             Spear thrust finishes her (her brood burst by the tool first: it bites through a cast); with
##             --lie=south (she lies by the south wall, as after a crash) or --lie=west (on the far
##             west lane) her new cocoon's lane is staged as the farthest from her: she climbs and
##             crawls there before she spins (the notes give her x at the close against the lane's)
##   quiet3    round 3 left to play (her last hit, her attacks free, the slime between two lanes): no
##             volley comes; the notes count her volleys
##   ram-call  her ram call: the slime stands in another ram's lane; she spits a glob of web at its
##             target and the log comes for the slime
##   look      nothing staged: she hangs in her cocoon over a random lane; the camera over the room
## Writes <dir>/f<nnn>.png and <dir>/film.json (per saved frame its time, her shell, round and
## health, the slime's health; the notes).

const Services := preload("res://game/shared/services.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "matron-lab"
const CELL := 64.0
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 480.0
const GOO_BOMBS := &"goo-bombs"
const AMMO_BEHIND_PX := 34.0
## Where the spit bomb lands ahead of the slime (as the mechanism films measured it).
const BOMB_AHEAD_PX := 112.0
## The lab's spots (cells): her camp, and the room's middle (the camera).
const HOME := Vector2(12.0, 10.0)
const ROOM_MIDDLE := Vector2(12.0, 10.0)
## ram-catch: the bait stands this far above its lane's lower end; the pot is picked up this far beside
## the target (outside its ring, short of the next target's).
const LANE_END_BAIT_PX := 40.0
const BESIDE_RING_PX := 118.0
## web-balls: the slime stands this far below a ball to suck it up, and steps this far out of the
## volley's mark on it.
const SUCK_BELOW_PX := 40.0
const DODGE_PX := 130.0
## dive: the slime's spot (cells), in the gap between the third and fourth lanes.
const DIVE_GAP := Vector2(13.9, 9.5)
## ground-call: the bait's place down its lane (share of the lane from the ram), how far down the lane
## the slime steps out of her dive, and how far past the lane's side it steps when she spits.
const GROUND_BAIT_SHARE := 0.4
const GROUND_STEP_DOWN_PX := 120.0
const GROUND_STEP_OUT_PX := 40.0
## round3, quiet3: her health staged for round 3 (her last hit: under the rework scene's
## `round_three_below_hp` 25).
const ROUND_THREE_HP := 20.0
## crush: the slime's start (cells, in the gap west of the third lane) and the Broodlings' row ahead
## of it (the first this far east, then this far apart).
const CRUSH_START := Vector2(6.4, 12.0)
const CRUSH_FIRST_PX := 80.0
const CRUSH_GAP_PX := 55.0

var _main: Node
var _out := "user://matron-films"
var _film := "round1"
var _every := 2
var _zoom := 0.78
var _tail := 60
## round3's staging: "" (where she is), "south" or "west" (see `_film_round3`).
var _from := ""
var _index := 0
var _step := 0
var _start_ms := 0.0
var _rows: Array = []
var _notes: Dictionary = {}
var _caption: Label
var _matron: Node
## While the slime casts: her attacks and her brood's are held (newly hatched ones too).
var _holding := false
## The liftables' sheet read from its file (see `_fresh_sheet`).
var _sheet_path := ""
var _sheet_fresh: Texture2D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--film="):
			_film = arg.trim_prefix("--film=")
		elif arg.begins_with("--every="):
			_every = maxi(1, int(arg.trim_prefix("--every=")))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--tail="):
			_tail = maxi(0, int(arg.trim_prefix("--tail=")))
		elif arg.begins_with("--lie="):
			_from = arg.trim_prefix("--lie=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_matron: gave up after %d s" % int(WATCHDOG_S))
		quit(1))
	DisplayServer.window_set_size(WINDOW)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", MAP_ID)
	_main.set(&"ability_ceremonies", false)
	_main.set(&"direct_world_run", true)
	root.add_child(_main)
	for i in 90:
		await process_frame
	if Services.feel() != null:
		Services.feel().frame_clock_ms = 1000.0 / 60.0
	_hide_hints()
	_make_caption()
	# the slime walks in: she wakes
	_place_slime(_at(HOME + Vector2(0.0, 3.0)), Vector2.UP)
	await _settle(60)
	_matron = await _find_matron()
	if _matron == null:
		push_error("film_matron: she did not spawn")
		quit(1)
		return
	_still_camera(_at(ROOM_MIDDLE))
	_start_ms = Services.now_ms()
	match _film:
		"round1":
			await _film_round1()
		"dive":
			await _film_dive()
		"ram-catch":
			await _film_ram_catch()
		"ground-call":
			await _film_ground_call()
		"ring":
			await _film_ring()
		"round3":
			await _film_round3()
		"ram-call":
			await _film_ram_call()
		"web-balls":
			await _film_web_balls()
		"crush":
			await _film_crush()
		"quiet3":
			await _film_quiet3()
		"bombs":
			await _film_bombs()
		"smash":
			await _film_smash()
		"look":
			_notes["shadow"] = _shadow()
			_notes["home"] = _matron.call(&"get_home")
			var lanes: Array = []
			for ram: String in ["ram-1", "ram-2", "ram-3", "ram-4", "ram-5"]:
				lanes.append(_piece(ram).call(&"lane_rect"))
			_notes["lanes"] = lanes
			await _run(_tail)
		_:
			push_error("film_matron: no film '%s'" % _film)
	_notes["slime_hp_at_end"] = _slime_health()
	_notes["matron_hp_at_end"] = _hp()
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"film": _film, "frames": _index, "notes": _notes, "rows": _rows}, "\t"))
	file.close()
	print("film_matron: ", _film, " ", JSON.stringify(_notes))
	quit()


# --- the films -------------------------------------------------------------------------------------

## Round 1: a bomb under her low cocoon, the tear, the Spear and a pot, her climb into round 2.
func _film_round1() -> void:
	_matron.set(&"_hp", 230.0)
	_notes["staged_hp"] = 230
	_hold_her_attacks(true)
	await _run(70)
	var shadow := _shadow()
	_place_slime(shadow + Vector2(0.0, BOMB_AHEAD_PX), Vector2.UP)
	await _tick()
	_every = 4
	_notes["bomb"] = await _spit_bomb(Vector2.UP)
	_push(&"move_down", true)
	await _run(30)
	_push(&"move_down", false)
	_notes["torn"] = await _wait_shell("torn", 260)
	_hold_her_attacks(false)
	_every = 2
	await _run(30)
	_notes["hits"] = await _spear_and_pot(Vector2.LEFT)
	_notes["after_round1"] = await _wait_shell("hanging", 360)
	_notes["ring_walls"] = (_matron.call(&"get_ring_walls") as Array).size()
	await _run(_tail)


## Round 2: a dive that misses (she lies `landed_ms` before she climbs), then one that lands on the
## slime. The slime stays in the gap between two lanes (in a lane she would trip its ram from the floor).
func _film_dive() -> void:
	await _stage_round_two()
	var spot := _at(DIVE_GAP)
	_place_slime(spot, Vector2.UP)
	await _tick()
	_notes["first_dive"] = await _wait_shell("diving", 400)
	await _run(8)
	# it steps aside, down the gap
	_push(&"move_down", true)
	await _run(22)
	_push(&"move_down", false)
	_notes["hp_after_miss"] = _slime_health()
	_notes["landed"] = await _wait_shell("landed", 90)
	var landed_at := Services.now_ms()
	await _wait_shell("climbing", 400)
	_notes["landed_for_ms"] = int(Services.now_ms() - landed_at)
	_notes["second_dive"] = await _wait_shell("diving", 420)
	var before := _slime_health()
	await _wait_shell("landed", 90)
	await _run(4)
	_notes["blow"] = before - _slime_health()
	await _run(_tail)


## Round 2: baited over the lower end of the second ram's lane, a pot at its target (straight below the
## lane, inside its web ring) as she dives: the ram flings her down the lane to the wall.
func _film_ram_catch() -> void:
	await _stage_round_two()
	_matron.set(&"_next_ram_call_at", INF)
	# her spit sticks the slime and it cannot pick a pot up: held for the staging (her dive still comes)
	_hold_her_attacks(true)
	var ram := _piece("ram-2")
	var lane := ram.call(&"lane_rect") as Rect2
	var bait := Vector2(lane.get_center().x, lane.end.y - LANE_END_BAIT_PX)
	_place_slime(bait, Vector2.DOWN)
	await _run(10)
	# she crawls over the bait; the tool brings her the last way, then the slime steps down to the target
	_put_matron(bait)
	await _run(6)
	var target := ram.call(&"get_knock_target") as Node2D
	_notes["catch_target"] = str(target.name)
	_notes["target_below_lane_by"] = target.global_position.y - lane.end.y
	# a pot picked up beside the ring (outside it), then into the ring holding it, below the disc (the
	# Silk skin wades the silk)
	_place_slime(target.global_position + Vector2(BESIDE_RING_PX, 30.0), Vector2.UP)
	await _tick()
	await _hold_pot(Vector2.DOWN)
	_place_slime(target.global_position + Vector2(0.0, 44.0), Vector2.UP)
	_notes["slime_inside_ring"] = true
	await _tick()
	_matron.set(&"_next_dive_at", 0.0)
	_notes["dive"] = await _wait_shell("diving", 60)
	await _release_throw(Vector2.UP)
	_notes["catch_throw_frame"] = _index
	_notes["held_before_throw"] = str((Services.world().player.call(&"get_mouth") as RefCounted).call(&"is_holding"))
	_hold_her_attacks(false)
	_matron.set(&"_next_ram_call_at", INF)
	var seen: Array = []
	for i in 40:
		var line := "%s/%s/%s" % [target.call(&"state_name"), ram.call(&"state_name"), _matron.call(&"get_shell")]
		if seen.is_empty() or seen[-1] != line:
			seen.append(line)
		if str(_matron.call(&"get_shell")) == "flung":
			break
		await _tick()
	_notes["target_ram_her"] = seen
	_notes["flung"] = await _wait_shell("flung", 120)
	_notes["crashed"] = await _wait_shell("torn", 90)
	_notes["open_kind"] = str(_matron.call(&"get_open_kind"))
	_notes["crash_at"] = _shadow()
	_notes["hp_after_crash"] = _hp()
	await _run(16)
	var her := _shadow()
	_place_slime(her + Vector2(-78.0, 4.0), Vector2.RIGHT)
	await _run(4)
	_notes["hits"] = await _spear_and_pot(Vector2.RIGHT)
	_notes["after_window"] = await _wait_shell("hanging", 360)
	await _run(_tail)


## Round 2, her ram call from the floor: she dives on the slime in the second ram's lane; it steps down
## the lane out of the blow and stays in it; lying there she spits a glob at the lane's target, the
## slime steps out of the lane, and her own ram's log flings her down it: on her back, open.
func _film_ground_call() -> void:
	await _stage_round_two()
	# her hanging ram calls wait (the ram stays ready for the one from the floor); her spit too
	_matron.set(&"_next_ram_call_at", INF)
	_hold_her_attacks(true)
	var ram := _piece("ram-2")
	var target := ram.call(&"get_knock_target") as Node2D
	var lane := ram.call(&"lane_rect") as Rect2
	var bait := Vector2(lane.get_center().x, lane.position.y + lane.size.y * GROUND_BAIT_SHARE)
	_place_slime(bait, Vector2.DOWN)
	await _run(10)
	_put_matron(bait)
	await _run(4)
	_matron.set(&"_next_dive_at", 0.0)
	_notes["dive"] = await _wait_shell("diving", 60)
	# down its lane, out of the dive's blow and still in the lane
	var body := Services.world().player_body
	_push(&"move_down", true)
	for i in 50:
		await _tick()
		if body.global_position.y - bait.y >= GROUND_STEP_DOWN_PX:
			break
	_push(&"move_down", false)
	_notes["landed"] = await _wait_shell("landed", 90)
	var landed_at := Services.now_ms()
	_notes["her_spot"] = _shadow()
	_notes["slime_in_her_lane"] = lane.has_point(body.global_position) and lane.has_point(_shadow())
	var before := _slime_health()
	for i in 120:
		await _tick()
		if bool(_matron.get(&"_ground_called")):
			break
	_notes["ground_call_after_landing_ms"] = int(Services.now_ms() - landed_at) if bool(_matron.get(&"_ground_called")) else -1
	# she spat: the slime steps out of the lane, east
	_push(&"move_right", true)
	for i in 50:
		await _tick()
		if body.global_position.x >= lane.end.x + GROUND_STEP_OUT_PX:
			break
	_push(&"move_right", false)
	var seen: Array = []
	for i in 120:
		var line := "%s/%s/%s" % [target.call(&"state_name"), ram.call(&"state_name"), _matron.call(&"get_shell")]
		if seen.is_empty() or seen[-1] != line:
			seen.append(line)
		if str(_matron.call(&"get_shell")) == "flung":
			break
		await _tick()
	_notes["target_ram_her"] = seen
	_notes["flung_after_landing_ms"] = int(Services.now_ms() - landed_at)
	_notes["slime_hurt_by_the_log"] = before - _slime_health()
	_notes["crashed"] = await _wait_shell("torn", 90)
	_notes["open_kind"] = str(_matron.call(&"get_open_kind"))
	_notes["crash_at"] = _shadow()
	_notes["hp_after_crash"] = _hp()
	await _run(16)
	var her := _shadow()
	_place_slime(her + Vector2(-78.0, 4.0), Vector2.RIGHT)
	await _run(4)
	_notes["hits"] = await _spear_and_pot(Vector2.RIGHT)
	_notes["after_window"] = await _wait_shell("hanging", 360)
	await _run(_tail)


## Round 3 left to play (health staged at 20: her last hit, her attacks free, the slime in the gap between two lanes
## south of her): no volley comes (`volley_in_round_three` off); the notes count her volleys and spits.
func _film_quiet3() -> void:
	_matron.set(&"_hp", ROUND_THREE_HP)
	_matron.set(&"_round", 2)
	_matron.call(&"_begin_respin", Services.now_ms())
	_notes["staged_hp"] = ROUND_THREE_HP
	_notes["cocooned"] = await _wait_shell("cocooned", 600)
	_notes["round"] = int(_matron.call(&"get_round"))
	_place_slime(_at(DIVE_GAP + Vector2(0.0, 4.0)), Vector2.UP)
	var volleys := 0
	var spits := 0
	var last_phase := ""
	var was_attacking := false
	for i in 720:
		await _tick()
		var phase := str(_matron.get(&"_phase"))
		if phase != last_phase and phase == "volley-telegraph":
			volleys += 1
		last_phase = phase
		var attacking := bool(_matron.call(&"is_attacking"))
		if attacking and not was_attacking:
			spits += 1
		was_attacking = attacking
	_notes["volleys_in_round_three"] = volleys
	_notes["attacks_begun"] = spits
	await _run(_tail)


## The Goo Bomb with no cast (2026-11-24): the slime (her attacks held) spits a bomb, presses again half
## a second later (refused: the cooldown), then spits two more a second apart, stepping between: three
## bombs lie at once; then they blow.
func _film_bombs() -> void:
	_hold_her_attacks(true)
	_matron.set(&"_next_ram_call_at", INF)
	var start := _at(CRUSH_START)
	_still_camera(start + Vector2(160.0, -20.0))
	_place_slime(start, Vector2.RIGHT)
	var player: Node = Services.world().player
	_notes["selected"] = AbilityBox.select(player, GOO_BOMBS)
	await _run(6)
	var counts: Array = []
	for press: Array in [[0, true], [30, false], [62, true], [124, true]]:
		while _step < int(press[0]) + _step_base():
			await _tick()
		player.call(&"face", Vector2.RIGHT)
		_push(&"ability_use", true)
		await _tick()
		await _tick()
		_push(&"ability_use", false)
		await _run(4)
		counts.append(get_nodes_in_group(&"goo_bombs").size())
		_push(&"move_right", true)
		await _run(8)
		_push(&"move_right", false)
	_notes["bombs_after_each_press"] = counts
	_notes["bombs_at_once"] = get_nodes_in_group(&"goo_bombs").size()
	await _run(150)
	_notes["bombs_left_after_the_fuses"] = get_nodes_in_group(&"goo_bombs").size()
	await _run(_tail)


var _bombs_from_step := -1


## The step the bombs film's presses count from (its first call).
func _step_base() -> int:
	if _bombs_from_step < 0:
		_bombs_from_step = _step
	return _bombs_from_step


## The Heavy Roll smashes light things to throw: three clay pots (made by the tool) in a row ahead of
## the slime burst as thrown ones do and the ball rolls on; then a crate (medium) ahead of it: a bonk.
func _film_smash() -> void:
	_hold_her_attacks(true)
	_matron.set(&"_next_ram_call_at", INF)
	var start := _at(CRUSH_START)
	_still_camera(start + Vector2(220.0, -40.0))
	_place_slime(start, Vector2.RIGHT)
	var pots: Array[Node2D] = []
	for i in 3:
		pots.append(ThrowAmmo.spawn_liftable("clay-pot", start + Vector2(CRUSH_FIRST_PX + CRUSH_GAP_PX * float(i), 0.0), {"pop": false}))
	await _run(10)
	var player: Node = Services.world().player
	var roll: RefCounted = player.get(&"_roll")
	player.call(&"face", Vector2.RIGHT)
	_push(&"dodge", true)
	await _tick()
	_push(&"dodge", false)
	var bonked := false
	for i in 60:
		await _tick()
		bonked = bonked or bool(roll.call(&"is_bouncing"))
	var left := 0
	for pot: Node2D in pots:
		if is_instance_valid(pot) and not pot.is_queued_for_deletion():
			left += 1
	_notes["pots_left_after_the_roll"] = left
	_notes["bonked_on_the_pots"] = bonked
	_notes["rolled_px"] = Services.world().player_body.global_position.x - start.x
	# a crate (medium) is no light thing: the ball bonks on it
	var feet := Services.world().player_body.global_position
	var crate := ThrowAmmo.spawn_liftable("crate", feet + Vector2(90.0, 0.0), {"pop": false})
	await _run(30)
	player.call(&"face", Vector2.RIGHT)
	_push(&"dodge", true)
	await _tick()
	_push(&"dodge", false)
	bonked = false
	for i in 50:
		await _tick()
		bonked = bonked or bool(roll.call(&"is_bouncing"))
	_notes["bonked_on_the_crate"] = bonked
	_notes["crate_whole"] = is_instance_valid(crate) and not crate.is_queued_for_deletion()
	await _run(_tail)


## The Heavy Roll crushes her brood: three Broodlings (made by the tool) in a row ahead of the slime
## (her attacks held); a quick roll east through them pops each flat and rolls on, no bonk.
func _film_crush() -> void:
	_hold_her_attacks(true)
	_matron.set(&"_next_ram_call_at", INF)
	var world := Services.world()
	var start := _at(CRUSH_START)
	_still_camera(start + Vector2(220.0, -40.0))
	_place_slime(start, Vector2.RIGHT)
	var brood: Array[Node] = []
	for i in 3:
		var root := world.instantiate_scene("character.broodling") as Node2D
		if root == null:
			continue
		world.entities_root().add_child(root)
		FeetAnchor.place_at_phaser_position(root, start + Vector2(CRUSH_FIRST_PX + CRUSH_GAP_PX * float(i), -20.0))
		for child: Node in root.get_children():
			if child.has_method(&"configure_arena"):
				var no_zones: Array[Dictionary] = []
				child.call(&"configure_navigation", {}, no_zones)
				brood.append(child)
	_notes["brood_made"] = brood.size()
	_notes["heavy"] = bool((Services.world().player.get(&"_roll") as RefCounted).call(&"is_heavy")) if Services.world().player.get(&"_roll") != null else "?"
	await _run(6)
	Services.world().player.call(&"face", Vector2.RIGHT)
	_push(&"dodge", true)
	await _tick()
	_push(&"dodge", false)
	var bonked := false
	var roll: RefCounted = Services.world().player.get(&"_roll")
	for i in 60:
		await _tick()
		if roll != null and bool(roll.call(&"is_bouncing")):
			bonked = true
	var alive := 0
	for node: Node in brood:
		if is_instance_valid(node) and not bool(node.call(&"is_defeated")):
			alive += 1
	_notes["brood_alive_after_roll"] = alive
	_notes["bonked"] = bonked
	_notes["rolled_px"] = Services.world().player_body.global_position.x - start.x
	await _run(_tail)


## Her ram call: the slime stands in a ram's lane (not the one her cocoon hangs over); she spits a
## glob at that ram's target and the log comes for the slime.
func _film_ram_call() -> void:
	var lane_ram: Node = _matron.call(&"get_lane_ram")
	var ram: Node2D = null
	for i in range(1, 6):
		var candidate := _piece("ram-%d" % i)
		if candidate != lane_ram:
			ram = candidate
			break
	_notes["slime_in_lane_of"] = str(ram.name)
	_notes["her_lane"] = str((lane_ram as Node).name) if lane_ram != null else ""
	var spot := (ram.call(&"lane_rect") as Rect2).get_center() + Vector2(0.0, 120.0)
	_place_slime(spot, Vector2.UP)
	_matron.set(&"_next_ram_call_at", Services.now_ms() + 600.0)
	_matron.set(&"_next_volley_at", INF)
	var before := _slime_health()
	for i in 150:
		await _tick()
		if str(ram.call(&"state_name")) == "hold":
			break
	_notes["ram_state"] = str(ram.call(&"state_name"))
	_notes["slime_hurt"] = before - _slime_health()
	await _run(_tail)


## Round 2: a pot thrown down at the second target stops in its ring's north wall; the Spear cuts that
## wall; a pot through.
func _film_ring() -> void:
	await _stage_round_two()
	_matron.set(&"_next_dive_at", INF)
	_matron.set(&"_next_ram_call_at", INF)
	var target := _piece("target-2")
	var north := target.global_position + Vector2(0.0, -float(_matron.get(&"target_ring_radius")))
	_place_slime(north + Vector2(0.0, -100.0), Vector2.DOWN)
	_still_camera(target.global_position + Vector2(60.0, -160.0))
	await _run(10)
	await _throw(Vector2.DOWN)
	await _run(50)
	_notes["target_after_first_pot"] = str(target.call(&"state_name"))
	_place_slime(north + Vector2(0.0, -44.0), Vector2.DOWN)
	await _run(6)
	_notes["spear"] = _spear()
	await _run(30)
	_notes["north_cut"] = _ring_wall_cut_near(north)
	_place_slime(north + Vector2(0.0, -100.0), Vector2.DOWN)
	await _run(6)
	await _throw(Vector2.DOWN)
	await _run(50)
	_notes["target_after_second_pot"] = str(target.call(&"state_name"))
	await _run(_tail)


## Her missed webs as ammo (no pots left): her volley misses, its marks leave web balls; one sucked up
## and thrown at her lane's target: the ram knocks the cocoon down.
func _film_web_balls() -> void:
	var removed := 0
	for node: Node in get_nodes_in_group(&"liftable"):
		node.get_parent().queue_free()
		removed += 1
	_notes["pots_removed_by_the_tool"] = removed
	_matron.set(&"_next_ram_call_at", INF)
	var stand := _at(Vector2(10.1, 11.5))
	_place_slime(stand, Vector2.UP)
	await _run(4)
	_matron.set(&"_next_volley_at", Services.now_ms() + 300.0)
	for i in 120:
		await _tick()
		if str(_matron.call(&"get_phase")) == "volley-telegraph":
			break
	_notes["volley"] = str(_matron.call(&"get_phase"))
	# the slime steps out of the mark on it (before the webs land), the way that ends farthest from
	# every mark
	var marks: Array = _matron.call(&"get_volley")
	var ways := {&"move_right": Vector2.RIGHT, &"move_left": Vector2.LEFT, &"move_up": Vector2.UP, &"move_down": Vector2.DOWN}
	var best: StringName = &"move_right"
	var best_gap := -INF
	for action: StringName in ways:
		var end: Vector2 = stand + (ways[action] as Vector2) * DODGE_PX
		var gap := INF
		for mark: Vector2 in marks:
			gap = minf(gap, end.distance_to(mark))
		if gap > best_gap:
			best_gap = gap
			best = action
	_notes["dodge"] = str(best)
	var topped_before := int(_notes.get("slime_topped_up", 0))
	_push(best, true)
	for i in 52:
		await _tick()
		if Services.world().player_body.global_position.distance_to(stand) > DODGE_PX:
			break
	_push(best, false)
	_notes["stepped_out_px"] = Services.world().player_body.global_position.distance_to(stand)
	for i in 90:
		await _tick()
		if str(_matron.call(&"get_phase")) == "volley-rest":
			break
	_hold_her_attacks(true)
	_matron.set(&"_next_ram_call_at", INF)
	_notes["slime_hurt_by_volley"] = 80.0 - _slime_health() \
		+ 40.0 * float(int(_notes.get("slime_topped_up", 0)) - topped_before)
	await _run(30)
	var balls: Array = _matron.call(&"get_web_balls")
	_notes["web_balls"] = balls.map(func(ball: Node2D) -> Vector2: return ball.global_position)
	if balls.is_empty():
		await _run(_tail)
		return
	# the slime goes to the nearest ball and sucks it up (the ball above it)
	var feet := Services.world().player_body.global_position
	var ball := balls[0] as Node2D
	for other: Node2D in balls:
		if other.global_position.distance_to(feet) < ball.global_position.distance_to(feet):
			ball = other
	_place_slime(ball.global_position + Vector2(0.0, SUCK_BELOW_PX), Vector2.UP)
	await _run(6)
	var mouth: RefCounted = Services.world().player.call(&"get_mouth")
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 50:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	_notes["holding_web_ball"] = bool(mouth.call(&"is_holding"))
	await _run(10)
	# her lane's ram's target, from its side toward the room's middle (as round3)
	var lane_ram := _matron.call(&"get_lane_ram") as Node2D
	var target := lane_ram.call(&"get_knock_target") as Node2D
	_notes["her_lane"] = str(lane_ram.name)
	var way := Vector2.RIGHT if target.global_position.x > _at(ROOM_MIDDLE).x else Vector2.LEFT
	_place_slime(target.global_position + Vector2(-150.0 * way.x, 30.0), way)
	await _run(6)
	await _release_throw(way)
	_notes["downed"] = await _wait_shell("downed", 120)
	# the sucked ball is freed: one more web lands and the list still reads (a freed ball once broke
	# the list's typed filter on the next drop, 2026-11-24)
	_matron.call(&"_drop_web_ball", _at(ROOM_MIDDLE) + Vector2(0.0, 160.0))
	_notes["web_balls_after_throw"] = (_matron.call(&"get_web_balls") as Array).size()
	await _run(_tail)


## Round 3 (her last hit: health staged at 20): the high cocoon, a blast refused, the ram knocks it
## down, a bomb tears it, one Spear hit ends her.
func _film_round3() -> void:
	_matron.set(&"_hp", ROUND_THREE_HP)
	_matron.set(&"_round", 2)
	# --lie=south (as after a crash at the south wall) or west (on the far west lane): she lies there,
	# and her new cocoon's lane is staged as the one farthest from her
	# --lie=slime: from the far west lane to the far east one, the slime standing on its middle;
	# --lie=post: from the south floor to the far west lane, her straight line through target-4's post
	var lie := Vector2.INF
	var forced := ""
	if _from == "south":
		lie = Vector2(_at(ROOM_MIDDLE).x, 1088.0)
	elif _from == "west" or _from == "slime":
		lie = (_piece("ram-1").call(&"lane_rect") as Rect2).get_center()
		forced = "ram-5" if _from == "slime" else ""
	elif _from == "post":
		var west := (_piece("ram-1").call(&"lane_rect") as Rect2).get_center()
		var post := _piece("target-4").global_position
		lie = west + (post - west) * 5.0
		forced = "ram-1"
	if lie.is_finite():
		_put_matron(lie)
		# the lane she lies on is hers now (her next pick leaves it out, as in play)
		for i in range(1, 6):
			var on := _piece("ram-%d" % i)
			if (on.call(&"lane_rect") as Rect2).has_point(lie):
				_matron.set(&"_lane_ram", on)
		await _run(2)
	_matron.call(&"_begin_respin", Services.now_ms())
	if lie.is_finite():
		var far: Node2D = _piece(forced) if not forced.is_empty() else null
		if far == null:
			for i in range(1, 6):
				var ram := _piece("ram-%d" % i)
				if far == null or (ram.call(&"lane_rect") as Rect2).get_center().distance_to(lie) \
						> (far.call(&"lane_rect") as Rect2).get_center().distance_to(lie):
					far = ram
		var home := (far.call(&"lane_rect") as Rect2).get_center()
		_matron.set(&"_lane_ram", far)
		_matron.set(&"_home", home)
		_notes["staged_from"] = lie
		_notes["staged_lane"] = str(far.name)
		_notes["shell_after_respin_call"] = str(_matron.call(&"get_shell"))
		if _from == "slime":
			_place_slime(home, Vector2.UP)
			_notes["slime_on_the_lane_middle"] = home
		if _from == "post":
			_notes["post_at"] = _piece("target-4").global_position
	var started := Services.now_ms()
	_notes["staged_hp"] = ROUND_THREE_HP
	_notes["cocooned"] = await _wait_shell("cocooned", 600)
	_notes["to_cocoon_ms"] = int(Services.now_ms() - started)
	var lane := (_matron.call(&"get_lane_ram") as Node2D).call(&"lane_rect") as Rect2
	_notes["her_at_close"] = _shadow()
	_notes["lane_middle"] = lane.get_center()
	_notes["her_x_off_lane_middle"] = _shadow().x - lane.get_center().x
	_notes["inside_lane"] = lane.has_point(_shadow())
	_notes["round"] = int(_matron.call(&"get_round"))
	if _from == "slime" or _from == "post":
		# only the crawl is checked
		await _run(_tail)
		return
	await _run(20)
	_notes["blast_high"] = bool(_matron.call(&"receive_blast", {}))
	await _run(30)
	# the ram whose lane her cocoon hangs over, and its target (found by the tool, as the player finds
	# it by following the ropes)
	var lane_ram := _matron.call(&"get_lane_ram") as Node2D
	_notes["her_lane"] = str(lane_ram.name)
	var target := lane_ram.call(&"get_knock_target") as Node2D
	_notes["its_target"] = str(target.name)
	# from below a target in the room's top half (beside it there may be a ram's gantry), else from
	# its side, toward the room's middle
	var way := Vector2.RIGHT if target.global_position.x > _at(ROOM_MIDDLE).x else Vector2.LEFT
	var stand := target.global_position + Vector2(-150.0 * way.x, 30.0)
	if target.global_position.y < _at(ROOM_MIDDLE).y:
		way = Vector2.UP
		stand = target.global_position + Vector2(0.0, 150.0)
	_place_slime(stand, way)
	_matron.set(&"_next_ram_call_at", INF)
	await _run(6)
	await _throw(way)
	_notes["downed"] = await _wait_shell("downed", 120)
	await _run(30)
	var cocoon := _shadow()
	_notes["cocoon_down_at"] = cocoon
	_hold_her_attacks(true)
	# her brood latches on and bites through a cast: burst for the film (staged, noted)
	_matron.call(&"_burst_brood")
	_notes["brood_burst_by_the_tool"] = true
	# beside the fallen cocoon (it is solid and wide): the bomb lands by her
	_place_slime(cocoon + Vector2(130.0, 0.0), Vector2.LEFT)
	await _run(20)
	_every = 4
	_notes["bomb"] = await _spit_bomb(Vector2.LEFT)
	_push(&"move_right", true)
	await _run(26)
	_push(&"move_right", false)
	_notes["torn"] = await _wait_shell("torn", 260)
	_hold_her_attacks(false)
	_every = 2
	_notes["open_kind"] = str(_matron.call(&"get_open_kind"))
	_notes["hp_when_open"] = _hp()
	await _run(24)
	var her := _shadow()
	_place_slime(her + Vector2(78.0, 4.0), Vector2.LEFT)
	await _run(4)
	# her last hit: one Spear thrust
	_notes["hits"] = [["spear %s" % _spear(), _hp()]]
	await _run(40)
	_notes["defeated"] = bool(_matron.call(&"is_defeated"))
	await _run(_tail + 60)


## Round 2 at once: health 190, she climbs from her cocoon to hang free and rings the targets.
func _stage_round_two() -> void:
	_matron.set(&"_hp", 190.0)
	_matron.call(&"_begin_respin", Services.now_ms())
	_notes["staged_hp"] = 190
	_notes["hanging"] = await _wait_shell("hanging", 200)


# --- acting ----------------------------------------------------------------------------------------

## Spear hits then a thrown pot: [the hit, her health after it].
func _spear_and_pot(way: Vector2, spears: int = 3) -> Array:
	var out: Array = []
	for i in spears:
		out.append(["spear %s" % _spear(), _hp()])
		await _run(22)
	var feet := Services.world().player_body.global_position
	_place_slime(feet - way * 70.0, way)
	await _run(2)
	var before := _hp()
	await _throw(way)
	await _run(30)
	out.append(["pot", before - _hp(), _hp()])
	return out


func _spear() -> String:
	var shapes: Node = _main.get(&"shapes")
	return str(shapes.call(&"fire_charge", &"shape-spear")) if shapes != null else "no shapes"


## Her volleys and spit wait while the slime casts (a hit breaks the cast; in play the slime casts
## between her attacks): the film's staging, noted.
func _hold_her_attacks(hold: bool) -> void:
	if not is_instance_valid(_matron):
		return
	_holding = hold
	if hold:
		_notes["her_attacks_held_while_casting"] = true
		_matron.set_meta(&"film_range", _matron.get(&"attack_range"))
		_matron.set(&"attack_range", 0.0)
		_matron.set(&"_next_volley_at", INF)
		_matron.call(&"cancel_attack")
		# her brood too (round 3's Broodlings bite through a cast)
		for enemy: Node in get_nodes_in_group(&"enemy"):
			if enemy != _matron:
				enemy.set(&"targeting_radius", 0.0)
				enemy.set(&"attack_range", 0.0)
	else:
		_matron.set(&"attack_range", _matron.get_meta(&"film_range", 300.0))
		_matron.set(&"_next_volley_at", Services.now_ms() + 2500.0)


func _spit_bomb(way: Vector2) -> String:
	var world := Services.world()
	var player: Node = world.player
	if not AbilityBox.select(player, GOO_BOMBS):
		return "the Goo Bomb is not in the Ability Box"
	player.call(&"face", way)
	await _tick()
	_push(&"ability_use", true)
	await _tick()
	await _tick()
	_push(&"ability_use", false)
	var cast_ms := Services.constants().number("abilities.gooBomb.castMs") if Services.constants() != null else 2000.0
	var spit_ms := Services.constants().number("abilities.gooBomb.spitMs") if Services.constants() != null else 320.0
	await _run(int((cast_ms + spit_ms) / 1000.0 * 60.0 / float(_every)) + 4)
	return "spat" if not get_nodes_in_group(&"goo_bombs").is_empty() else "no bomb in the world after the cast"


## A clay pot put behind the slime and sucked in (held); `_release_throw` throws it.
func _hold_pot(way: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var mouth: RefCounted = player.call(&"get_mouth")
	player.call(&"face", -way)
	ThrowAmmo.spawn_liftable("clay-pot", world.player_body.global_position - way * AMMO_BEHIND_PX, {"pop": false})
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 50:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	for i in 8:
		await _tick()


func _release_throw(way: Vector2) -> void:
	Services.world().player.call(&"face", way)
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	_notes["throw_frame"] = _index


func _throw(way: Vector2) -> void:
	await _hold_pot(way)
	await _release_throw(way)


# --- staging ---------------------------------------------------------------------------------------

func _at(cells: Vector2) -> Vector2:
	return cells * CELL


func _find_matron() -> Node:
	for i in 120:
		for node: Node in get_nodes_in_group(&"enemy"):
			if node.has_method(&"get_open_kind"):
				return node
		await physics_frame
	return null


func _shadow() -> Vector2:
	var body := _matron.call(&"get_body") as Node2D if is_instance_valid(_matron) else null
	return body.global_position if body != null else Vector2.ZERO


func _put_matron(at: Vector2) -> void:
	var body := _matron.call(&"get_body") as CharacterBody2D
	if body != null:
		body.global_position = at
		body.reset_physics_interpolation()


func _hp() -> float:
	if not is_instance_valid(_matron):
		return 0.0
	return float(_matron.get(&"_hp"))


func _ring_wall_cut_near(at: Vector2) -> bool:
	for wall: Node in _matron.call(&"get_ring_walls"):
		if (wall as Node2D).global_position.distance_to(at) < 40.0:
			return bool(wall.call(&"is_cut"))
	return false


func _piece(name: String) -> Node2D:
	var node := root.find_child(name, true, false) as Node2D
	if node == null:
		push_error("film_matron: the lab has no '%s'" % name)
	return node


func _place_slime(feet: Vector2, facing: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var body := world.player_body
	player.call(&"teleport", feet + ((player.call(&"get_centre") as Vector2) - body.global_position))
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	player.call(&"face", facing)


func _still_camera(at: Vector2) -> void:
	var camera: Node = Services.world().camera
	if camera == null:
		return
	camera.call(&"stop_follow")
	camera.set(&"use_bounds", false)
	camera.set(&"center", at)
	camera.set(&"target_zoom", _zoom)
	if camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", _zoom)


func _hide_hints() -> void:
	for child: Node in _main.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("control_hints.gd"):
			child.set(&"visible", false)
			child.set_process(false)
	for label: Node in root.find_children("note", "Label", true, false):
		(label as Label).visible = false


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


# --- running -----------------------------------------------------------------------------------------

func _settle(frames: int = 100) -> void:
	for i in frames:
		await physics_frame


func _run(frames: int) -> void:
	for i in frames:
		await _tick()


func _wait_shell(shell: String, frames: int) -> String:
	for i in frames:
		if not is_instance_valid(_matron) or str(_matron.call(&"get_shell")) == shell:
			break
		await _tick()
	return str(_matron.call(&"get_shell")) if is_instance_valid(_matron) else "gone"


func _tick() -> void:
	await physics_frame
	_step += 1
	# a film must not end in a faint (it resets her fight): the slime is topped up when low (noted)
	for bomb: Node in get_nodes_in_group(&"goo_bombs"):
		if bomb is Node2D:
			var at: Vector2 = bomb.call(&"ground_point") if bomb.has_method(&"ground_point") else (bomb as Node2D).global_position
			_notes["bomb_last_at"] = at
			_notes["bomb_from_her_shadow"] = at - _shadow()
	if _holding:
		for enemy: Node in get_nodes_in_group(&"enemy"):
			if enemy != _matron:
				enemy.set(&"targeting_radius", 0.0)
				enemy.set(&"attack_range", 0.0)
	var hp_now := _slime_health()
	if hp_now >= 0.0 and hp_now <= 40.0:
		Services.world().player.call(&"heal", 80)
		_notes["slime_topped_up"] = int(_notes.get("slime_topped_up", 0)) + 1
	if _step % _every != 0:
		return
	_fresh_sheet()
	var ms := Services.now_ms() - _start_ms
	var shell := str(_matron.call(&"get_shell")) if is_instance_valid(_matron) else "gone"
	var round_number := int(_matron.call(&"get_round")) if is_instance_valid(_matron) else 0
	_caption.text = "%s   %d ms   round %d   %s   her hp %d   slime hp %d" % [_film, int(ms), round_number, shell, int(_hp()), int(_slime_health())]
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	_rows.append({"ms": int(ms), "step": _step, "shell": shell, "round": round_number, "hp": _hp(), "slime_hp": _slime_health()})
	_index += 1


## The liftables drawn from the sheet's file: a sheet repacked since the editor last imported it (the
## web ball's cells, 2026-11-24) shows empty cells from the import cache in a run.
func _fresh_sheet() -> void:
	if _sheet_fresh == null:
		_sheet_path = str(LiftableScript.catalog().get("sheet", ""))
		var image := Image.load_from_file(ProjectSettings.globalize_path(_sheet_path)) if not _sheet_path.is_empty() else null
		if image == null or image.is_empty():
			return
		_sheet_fresh = ImageTexture.create_from_image(image)
	for node: Node in root.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if sprite.texture != null and sprite.texture != _sheet_fresh and sprite.texture.resource_path == _sheet_path:
			sprite.texture = _sheet_fresh


func _slime_health() -> float:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not player.has_method(&"get_damage_state"):
		return -1.0
	return float((player.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

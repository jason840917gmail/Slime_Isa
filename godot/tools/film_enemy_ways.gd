extends SceneTree
## Films the Dung Roller's stolen ball and the enemies' walk home in the playground, frame by frame
## (docs/godot/BESTIARY.md "Dung Roller", docs/godot/specs/enemy.md 4.3 "Getting home"). Each film
## stages its own scene on the open grass by the spawn point, with the camera still over it.
## Run windowed (it renders) with a fixed frame time, one film at a time, from the repo:
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_enemy_ways.gd -- \
##         --out=<dir> --film=<name> [--frames=<n>] [--every=<n>] [--zoom=<z>] [--look=<x>,<y>]
##         [--set=<constant path>=<number>]
## Films:
##   axis         two rollers, one horizontal and one vertical (`patrol_axis`), their tracks drawn
##   steal        the Gulp takes the ball; the beetle rages and dashes; its hit makes the slime drop
##                the ball; it takes it back and rolls on
##   throw-miss   the ball is taken and thrown at nothing: it lies there, the beetle fetches it
##   throw-back   the ball is taken and thrown back at the beetle
##   throw-other  the ball is taken and thrown at another enemy (a Worm Swordsman)
##   leave        the ball is taken and broken on another enemy, the slime walks off: the beetle
##                goes home and kneads a new one
##   pen          the Bestiary corner's pen 13, as it stands: the Gulp takes its roller's ball there
##   home-wall    a Worm Swordsman walks home out of a walled pocket (its path drawn);
##                `--set=combat.wayAround.probePx=0` films the old straight line
##   home-notice  a Worm Swordsman on its way home sees the slime step into view and turns on it
## Writes <dir>/f<nnn>.png (every `--every`-th frame) and <dir>/film.json (what each tracked enemy did
## per saved frame). `scripts/godot/throw-film-sheet.py <dir> --crop=...` lays them out as a strip.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const ENEMY_SCENE_PREFIX := "character."
const WINDOW := Vector2i(1024, 768)
## Where the stage's middle stands from the playground's spawn point (open ground).
const STAGE_OFFSET := Vector2(60.0, -40.0)
const WATCHDOG_S := 300.0
const WALL_COLOR := Color(0.42, 0.44, 0.5)
const TRAIL_COLORS: Array[Color] = [Color(1.0, 0.85, 0.2, 0.9), Color(0.3, 0.9, 1.0, 0.9), Color(1.0, 0.5, 0.8, 0.9)]
const HOME_COLOR := Color(0.4, 1.0, 0.5, 0.8)

var _main: Node
var _out := "user://enemy-ways"
var _film := "steal"
var _frames := 300
var _every := 6
var _zoom := 2.0
## --look=<x>,<y>: where the camera stands from the stage's middle (each film has its own default).
var _look := Vector2.INF
var _sets: Dictionary = {}
var _index := 0
var _step := 0
var _stage := Vector2.ZERO
var _tracked: Array = []
var _trails: Array = []
var _rows: Array = []
var _notes: Dictionary = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--film="):
			_film = arg.trim_prefix("--film=")
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--every="):
			_every = maxi(1, int(arg.trim_prefix("--every=")))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--look="):
			var place := arg.trim_prefix("--look=").split(",")
			if place.size() == 2:
				_look = Vector2(float(place[0]), float(place[1]))
		elif arg.begins_with("--set="):
			var pair := arg.trim_prefix("--set=").split("=")
			if pair.size() == 2:
				_sets[pair[0]] = float(pair[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_enemy_ways: gave up after %d s" % int(WATCHDOG_S))
		quit(1))
	DisplayServer.window_set_size(WINDOW)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", MAP_ID)
	_main.set(&"ability_ceremonies", false)
	root.add_child(_main)
	for i in 90:
		await process_frame
	var world := Services.world()
	if Services.feel() != null:
		Services.feel().frame_clock_ms = 1000.0 / 60.0
	for path: String in _sets:
		_set_constant(Services.constants(), path, _sets[path])
	_stage = world.player_spawn_point() + STAGE_OFFSET
	match _film:
		"axis":
			await _film_axis()
		"steal":
			await _film_steal("")
		"throw-miss":
			await _film_steal("miss")
		"throw-back":
			await _film_steal("back")
		"throw-other":
			await _film_steal("other")
		"leave":
			await _film_steal("leave")
		"pen":
			await _film_pen()
		"home-wall":
			await _film_home_wall()
		"home-notice":
			await _film_home_notice()
		_:
			push_error("film_enemy_ways: no film '%s'" % _film)
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"film": _film, "frames": _index, "every": _every, "sets": _sets,
		"notes": _notes, "rows": _rows}, "\t"))
	file.close()
	print("film_enemy_ways: ", _film, " ", JSON.stringify(_notes))
	quit()


# --- the films ---------------------------------------------------------------------------------------

func _film_axis() -> void:
	_place_slime(_stage + Vector2(0.0, 150.0), Vector2.UP)
	_still_camera(_stage + Vector2(0.0, 10.0))
	var across := _spawn("dung-roller", _stage + Vector2(-90.0, -40.0), {"patrol_axis": 1, "patrol_length": 130.0}, 1.0)
	var down := _spawn("dung-roller", _stage + Vector2(170.0, 0.0), {"patrol_axis": 2, "patrol_length": 110.0}, 1.0)
	_track(across)
	_track(down)
	await _run(_frames)


## The Gulp takes the ball off a roller; then, by `then`: "" the slime stands (the dash hits it, the
## ball drops, the beetle takes it back), "miss" it throws the ball away from everything, "back" at
## the beetle, "other" at a Worm Swordsman, "leave" breaks it on the swordsman and walks out of reach.
func _film_steal(then: String) -> void:
	var player: Node = Services.world().player
	_place_slime(_stage, Vector2.RIGHT)
	_still_camera(_stage + Vector2(60.0, 0.0))
	var roller := _spawn("dung-roller", _stage + Vector2(200.0, 0.0), {"patrol_axis": 1, "patrol_length": 130.0}, 420.0)
	_track(roller)
	var other: Node = null
	if then == "other" or then == "leave":
		other = _spawn("worm-swordsman", _stage + Vector2(-150.0, 0.0), {}, 1.0)
		_track(other)
	var mouth: RefCounted = player.call(&"get_mouth")
	# Wait for the ball to roll into the Gulp's reach, then tap the Gulp key.
	for i in 600:
		await _tick()
		var thing: Node = mouth.call(&"find_target", Vector2.RIGHT)
		if thing != null and thing.has_method(&"is_lying"):
			break
	_notes["suck_frame"] = _index
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 40:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	_notes["held"] = (mouth.get(&"held") as Dictionary).get("kind", "")
	_notes["has_ball_after_suck"] = bool(roller.call(&"has_ball"))
	if then == "miss" or then == "back" or then == "other" or then == "leave":
		# A miss goes up into the crystal wall (the training dummies stand to the left).
		var way := Vector2.RIGHT if then == "back" else (Vector2.UP if then == "miss" else Vector2.LEFT)
		for i in 6:
			await _tick()
		player.call(&"face", way)
		_notes["throw_frame"] = _index
		_push(&"eat", true)
		await _tick()
		await _tick()
		_push(&"eat", false)
	if then == "leave":
		# The slime walks out of the beetle's reach (its arena), up the screen.
		for i in 40:
			await _tick()
		_place_slime(_stage + Vector2(-40.0, -520.0), Vector2.DOWN)
	await _run(_frames)
	_notes["roller_alive"] = is_instance_valid(roller) and not bool(roller.call(&"is_defeated"))
	_notes["has_ball_at_end"] = is_instance_valid(roller) and bool(roller.call(&"has_ball"))
	_notes["other_health"] = _health(other) if other != null else -1.0
	_notes["held_at_end"] = (mouth.get(&"held") as Dictionary).get("kind", "")
	_notes["balls_lying"] = get_nodes_in_group(&"dung-ball").size()


## The Bestiary corner's pen 13 (docs/godot/BESTIARY.md "The Bestiary corner"): its own roller, on
## the pen's track, inside the pen's fence and arena. The slime stands by the track's west end, takes
## the ball and stands (the dash hits it, the ball drops, the beetle takes it back).
func _film_pen() -> void:
	var corner := root.find_child("bestiary-corner", true, false)
	var pen: Node = corner.call(&"pen", 13) if corner != null else null
	if pen == null:
		push_error("film_enemy_ways: no pen 13")
		return
	var rect: Rect2 = pen.call(&"pen_rect")
	_stage = rect.get_center()
	var living: Array = pen.call(&"living")
	var roller: Node = living[0]
	var roller_body := roller.call(&"get_body") as Node2D
	var player: Node = Services.world().player
	_place_slime(Vector2(rect.position.x + 56.0, roller_body.global_position.y), Vector2.RIGHT)
	_still_camera(_stage)
	_track(roller)
	var mouth: RefCounted = player.call(&"get_mouth")
	for i in 900:
		await _tick()
		var thing: Node = mouth.call(&"find_target", Vector2.RIGHT)
		if thing != null and thing.has_method(&"is_lying"):
			break
	_notes["suck_frame"] = _index
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	await _run(_frames)
	_notes["roller_alive"] = is_instance_valid(roller) and not bool(roller.call(&"is_defeated"))
	_notes["has_ball_at_end"] = is_instance_valid(roller) and bool(roller.call(&"has_ball"))
	_notes["held_at_end"] = (mouth.get(&"held") as Dictionary).get("kind", "")


## A Worm Swordsman whose home lies behind a walled pocket (open to the left): it stands inside the
## pocket and walks home. The slime stands out of its sight behind the pocket's upper wall.
func _film_home_wall() -> void:
	var home := _stage + Vector2(250.0, 0.0)
	_place_slime(_stage + Vector2(40.0, -230.0), Vector2.DOWN)
	_still_camera(_stage + Vector2(90.0, -10.0))
	_pocket(_stage)
	_mark_home(home, 50.0)
	var worm := _spawn("worm-swordsman", _stage + Vector2(40.0, 0.0), {}, 0.0, _home_record(home, 50.0))
	_track(worm)
	await _run(_frames)
	_notes["from_home_at_end"] = snappedf(maxf(0.0, (worm.call(&"get_centre") as Vector2).distance_to(home) - 50.0), 0.1)
	_notes["mode_at_end"] = _mode(worm)


## A Worm Swordsman on a long walk home (a wall between it and home to walk round); the slime, out
## of sight behind a wall at first, steps into its view on the way.
func _film_home_notice() -> void:
	var home := _stage + Vector2(300.0, 60.0)
	_place_slime(_stage + Vector2(-60.0, -260.0), Vector2.DOWN)
	_still_camera(_stage + Vector2(90.0, -10.0))
	_wall(_stage + Vector2(150.0, 60.0), Vector2(40.0, 200.0))
	_wall(_stage + Vector2(20.0, -150.0), Vector2(320.0, 40.0))
	_mark_home(home, 50.0)
	var worm := _spawn("worm-swordsman", _stage + Vector2(0.0, 60.0), {}, 0.0, _home_record(home, 50.0))
	_track(worm)
	await _run(70)
	_notes["mode_before"] = _mode(worm)
	_notes["step_in_frame"] = _index
	# The slime steps into the open, in the worm's sight, inside its leash.
	_place_slime(_stage + Vector2(-70.0, -20.0), Vector2.RIGHT)
	await _run(_frames)
	_notes["mode_at_end"] = _mode(worm)
	_notes["state_at_end"] = str(worm.call(&"get_runtime_state"))


# --- staging ---------------------------------------------------------------------------------------

## An enemy of `type_id` with its old centre at `centre`, `properties` set on its EnemyScript before
## it enters the tree (as a placed enemy's are). `arena_px` > 0 gives it an arena of that radius
## round the stage (it goes after the slime inside it); 0 none; `record` is its camp record
## (`configure_navigation`), {} for none.
func _spawn(type_id: String, centre: Vector2, properties: Dictionary, arena_px: float, record: Dictionary = {}) -> Node:
	var world := Services.world()
	var parent: Node = world.entities_root()
	var enemy_root := world.instantiate_scene(ENEMY_SCENE_PREFIX + type_id) as Node2D
	var enemy: Node = null
	for child: Node in enemy_root.get_children():
		if child.has_method(&"configure_navigation"):
			enemy = child
			break
	for key: String in properties:
		enemy.set(key, properties[key])
	var target: Vector2 = FeetAnchor.global_for_phaser_position(enemy_root, centre)
	var parent_item := parent as CanvasItem
	enemy_root.position = parent_item.get_global_transform().affine_inverse() * target if parent_item != null else target
	parent.add_child(enemy_root)
	enemy_root.reset_physics_interpolation()
	var no_zones: Array[Dictionary] = []
	enemy.call(&"configure_navigation", record, no_zones)
	# A wide arena is round the stage (the slime is in it); a dot is on the enemy (it stays put).
	var middle := _stage if arena_px > 1.0 else centre
	if arena_px > 0.0:
		enemy.call(&"configure_arena", {"shape": "circle", "x": middle.x, "y": middle.y, "radius": arena_px})
	return enemy


## A camp record whose home is a circle of `radius` round `centre` (PlacedEnemy.wander_record's shape).
func _home_record(centre: Vector2, radius: float) -> Dictionary:
	var circle := {"shape": "circle", "x": centre.x, "y": centre.y, "radius": radius}
	return {"id": "", "kind": "enemy-wander", "data": {}, "perimeter": circle, "stay_perimeter": circle}


func _place_slime(feet: Vector2, facing: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var body := world.player_body
	player.call(&"teleport", feet + ((player.call(&"get_centre") as Vector2) - body.global_position))
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	player.call(&"face", facing)


## The camera stands still over `at` at the film's zoom.
func _still_camera(at: Vector2) -> void:
	var camera: Node = Services.world().camera
	if camera == null:
		return
	camera.call(&"stop_follow")
	camera.set(&"use_bounds", false)
	camera.set(&"center", _stage + _look if _look.is_finite() else at)
	camera.set(&"target_zoom", _zoom)
	if camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", _zoom)


## A pocket of three walls open to the left, its inside 150 wide and 180 tall, round `at`.
func _pocket(at: Vector2) -> void:
	_wall(at + Vector2(140.0, 0.0), Vector2(40.0, 260.0))
	_wall(at + Vector2(45.0, -110.0), Vector2(230.0, 40.0))
	_wall(at + Vector2(45.0, 110.0), Vector2(230.0, 40.0))


## A staged wall (a grey block, a static body on the world layer) with its middle at `at`.
func _wall(at: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	var look := ColorRect.new()
	look.color = WALL_COLOR
	look.size = size
	look.position = -size * 0.5
	wall.add_child(look)
	Services.world().entities_root().add_child(wall)
	wall.global_position = at


## A ring on the ground where an enemy's home is.
func _mark_home(centre: Vector2, radius: float) -> void:
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = HOME_COLOR
	ring.z_index = 50
	for i in 33:
		ring.add_point(centre + Vector2.from_angle(TAU * float(i) / 32.0) * radius)
	Services.world().entities_root().add_child(ring)


## `enemy` leaves a drawn trail and a row in film.json.
func _track(enemy: Node) -> void:
	var trail := Line2D.new()
	trail.width = 2.0
	trail.default_color = TRAIL_COLORS[_tracked.size() % TRAIL_COLORS.size()]
	trail.z_index = 60
	Services.world().entities_root().add_child(trail)
	_tracked.append(enemy)
	_trails.append(trail)


# --- running -----------------------------------------------------------------------------------------

func _run(frames: int) -> void:
	for i in frames:
		await _tick()


## One physics step; every `_every`-th one is saved as a picture and a row.
func _tick() -> void:
	await physics_frame
	_step += 1
	for i in _tracked.size():
		var enemy: Variant = _tracked[i]
		if is_instance_valid(enemy) and (enemy as Node).has_method(&"get_body"):
			var enemy_body := (enemy as Node).call(&"get_body") as Node2D
			if enemy_body != null and is_instance_valid(enemy_body):
				(_trails[i] as Line2D).add_point(enemy_body.global_position)
	if _step % _every != 0:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	var row: Array = []
	for enemy: Variant in _tracked:
		if not is_instance_valid(enemy):
			row.append(null)
			continue
		var node := enemy as Node
		var at: Vector2 = node.call(&"get_centre")
		row.append({"x": snappedf(at.x - _stage.x, 0.1), "y": snappedf(at.y - _stage.y, 0.1), "hp": _health(node),
			"phase": str(node.call(&"get_phase")) if node.has_method(&"get_phase") else str(node.call(&"get_runtime_state")),
			"mode": _mode(node)})
	_rows.append(row)
	_index += 1


## A camp enemy's territory mode ("" for none).
func _mode(enemy: Variant) -> String:
	if not is_instance_valid(enemy):
		return ""
	var territory: Variant = (enemy as Node).get(&"_territory")
	return str((territory as RefCounted).get(&"mode")) if territory is RefCounted else ""


func _health(enemy: Variant) -> float:
	if not is_instance_valid(enemy):
		return 0.0
	var value: Variant = (enemy as Node).get(&"_hp")
	return float(value) if value is float or value is int else -1.0


func _set_constant(constants: Node, path: String, number: float) -> void:
	var current: Variant = constants.get(&"_constants")
	var segments := path.split(".")
	for i in segments.size() - 1:
		if not current is Dictionary or not (current as Dictionary).has(segments[i]):
			push_warning("film_enemy_ways: no constant '%s'" % path)
			return
		current = (current as Dictionary)[segments[i]]
	if current is Dictionary:
		(current as Dictionary)[segments[segments.size() - 1]] = number


## The key as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

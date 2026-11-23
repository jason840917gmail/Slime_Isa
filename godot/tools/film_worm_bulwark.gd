extends SceneTree
## Films the Worm Bulwark (docs/godot/BESTIARY.md "37. Worm Bulwark") in the playground, frame by
## frame, with the camera still over the stage: by default the open grass between the Bestiary
## corner's first and second rows of pens (a corridor 160 px tall and 3,000 px long). Run windowed (it
## renders) with a fixed frame time, one film at a time, from the repo (or through
## `scripts/godot/film-enemy-ways.sh <name> --tool=film_worm_bulwark --film=<film>`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_worm_bulwark.gd -- \
##         --out=<dir> --film=<name> [--frames=<n>] [--every=<n>] [--zoom=<z>] [--gulp=<1..3>]
##         [--pattern=<key>=<number>] (on the filmed Bulwark's own `pattern` numbers)
##         [--stage=<x>,<y>] (the slime's feet at the start; he starts 230 px to its left)
## Films:
##   dodge   he winds up and charges; the slime steps aside; he runs past, skids and turns; the
##           slime steps back onto his line and throws a pot at his back
##   bowl    the slime stands in his way: he bowls it aside and runs on
##   wall    the slime steps aside and he slams his shield into a wall behind it: dazed; the slime
##           throws `--throws` things (`--kind`, a clay pot) at his back while he is dazed
##           (`--pattern=dazedMs=<ms>` holds the daze for more than one throw)
##   front   a pot thrown at his front clinks off the shield
##   walk    pen 37's Bulwark with his charge off (`sightPx` 0) plods after the slime: to the left,
##           down, then up the screen (his three walk cycles)
##   look    nothing staged: the camera over `--stage`, to see a place
##   pen     the Bestiary corner's pen 37 as it stands: the slime by its pots, he charges, the slime
##           steps aside and he slams into the pen's fence; a pot at his back
## Writes <dir>/f<nnn>.png (every `--every`-th frame) and <dir>/film.json (his place, phase and
## health per saved frame, and the notes).

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const ENEMY_SCENE := "character.worm-bulwark"
const WINDOW := Vector2i(1024, 768)
## The stage by default: the grass between the Bestiary corner's pen rows 1 and 2 (y 1024 to 1184),
## under the middle of pen 3's column.
const STAGE := Vector2(4992.0, 1104.0)
const WATCHDOG_S := 300.0
const WALL_COLOR := Color(0.42, 0.44, 0.5)
const TRAIL_COLOR := Color(1.0, 0.85, 0.2, 0.9)
## The slime steps aside when he charges and is this close.
const DODGE_PX := 150.0
## His old centre at the start from the slime's feet: 230 px to its left, his feet level with its
## feet (his old centre stands 22 px over them: the scene's depth anchor).
const START := Vector2(-230.0, -22.0)
## Frames the slime walks to step aside.
const DODGE_FRAMES := 24
## Where a thing to throw is put, ahead of the slime's feet.
const AMMO_AHEAD_PX := 34.0

var _main: Node
var _out := "user://worm-bulwark"
var _film := "dodge"
var _frames := 360
var _every := 4
var _zoom := 2.0
var _throws := 1
var _kind := "clay-pot"
var _pattern_sets: Dictionary = {}
var _index := 0
var _step := 0
var _stage := STAGE
var _worm: Node = null
var _trail: Line2D = null
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
		elif arg.begins_with("--throws="):
			_throws = maxi(0, int(arg.trim_prefix("--throws=")))
		elif arg.begins_with("--stage="):
			var place := arg.trim_prefix("--stage=").split(",")
			if place.size() == 2:
				_stage = Vector2(float(place[0]), float(place[1]))
		elif arg.begins_with("--kind="):
			_kind = arg.trim_prefix("--kind=")
		elif arg.begins_with("--pattern="):
			var pair := arg.trim_prefix("--pattern=").split("=")
			if pair.size() == 2:
				_pattern_sets[pair[0]] = float(pair[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_worm_bulwark: gave up after %d s" % int(WATCHDOG_S))
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
	match _film:
		"dodge":
			await _film_dodge()
		"bowl":
			await _film_bowl()
		"wall":
			await _film_wall()
		"front":
			await _film_front()
		"pen":
			await _film_pen()
		"walk":
			await _film_walk()
		"look":
			# Only the place: the camera over `--stage` (to find room for a pen).
			_still_camera(_stage)
			await _run(_frames)
		_:
			push_error("film_worm_bulwark: no film '%s'" % _film)
	_notes["health_at_end"] = _health()
	_notes["defeated"] = not is_instance_valid(_worm) or bool(_worm.call(&"is_defeated"))
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"film": _film, "frames": _index, "every": _every, "notes": _notes,
		"rows": _rows}, "\t"))
	file.close()
	print("film_worm_bulwark: ", _film, " ", JSON.stringify(_notes))
	quit()


# --- the films ---------------------------------------------------------------------------------------

## He charges from the left; the slime steps up out of his way; he runs past; the slime steps back
## onto his line and throws a pot at his back as he skids and turns.
func _film_dodge() -> void:
	_place_slime(_stage, Vector2.LEFT)
	_still_camera(_stage + Vector2(30.0, -10.0))
	_spawn(_stage + START)
	await _dodge(&"move_up")
	_notes["dodged_frame"] = _index
	var hurt_from := _health()
	# Once he is past, back onto his line behind him.
	var player: Node = Services.world().player
	for i in 120:
		await _tick()
		if (_worm.call(&"get_centre") as Vector2).x > (player.call(&"get_centre") as Vector2).x + 40.0:
			break
	_notes["passed_frame"] = _index
	await _walk(&"move_down", DODGE_FRAMES)
	await _throw_at_worm()
	await _run(_frames)
	_notes["hurt_by_throw"] = hurt_from - _health()


## The slime stands still in his way.
func _film_bowl() -> void:
	_place_slime(_stage, Vector2.LEFT)
	_still_camera(_stage + Vector2(40.0, 0.0))
	_spawn(_stage + START)
	var slime_health := _slime_health()
	await _run(_frames)
	_notes["slime_hurt"] = slime_health - _slime_health()


## A wall behind the slime: it steps aside and he slams into the wall, dazed; the slime walks back
## level with him and throws `_throws` things at his back.
func _film_wall() -> void:
	_place_slime(_stage, Vector2.LEFT)
	_still_camera(_stage + Vector2(-20.0, -10.0))
	_wall(_stage + Vector2(150.0, -10.0), Vector2(40.0, 150.0))
	_spawn(_stage + START)
	await _dodge(&"move_up")
	for i in 120:
		await _tick()
		if _phase() == "dazed":
			break
	_notes["dazed_frame"] = _index
	# Back down, level with him, behind him (he faces the wall).
	await _walk(&"move_down", DODGE_FRAMES)
	for throw in _throws:
		if not is_instance_valid(_worm) or bool(_worm.call(&"is_defeated")):
			break
		await _throw_at_worm()
		_notes["health_after_throw_%d" % (throw + 1)] = _health()
		for i in 30:
			await _tick()
	await _run(_frames)


## He plods at the slime; a pot thrown straight at his shield.
func _film_front() -> void:
	_place_slime(_stage, Vector2.LEFT)
	_still_camera(_stage + Vector2(-80.0, 0.0))
	_spawn(_stage + START + Vector2(30.0, 0.0), {"sightPx": 0.0})
	for i in 20:
		await _tick()
	await _throw_at_worm()
	_notes["health_after_front_throw"] = _health()
	await _run(_frames)


## Pen 37 (docs/godot/BESTIARY.md "The Bestiary corner"): its own Bulwark, fence and supplies.
func _film_pen() -> void:
	var corner := root.find_child("bestiary-corner", true, false)
	var pen: Node = corner.call(&"pen", 37) if corner != null else null
	if pen == null:
		push_error("film_worm_bulwark: no pen 37")
		return
	var rect: Rect2 = pen.call(&"pen_rect")
	_stage = rect.get_center()
	var living: Array = pen.call(&"living")
	if living.is_empty():
		push_error("film_worm_bulwark: pen 37 has no enemy")
		return
	_worm = living[0]
	_trail = Line2D.new()
	_trail.width = 2.0
	_trail.default_color = TRAIL_COLOR
	_trail.z_index = 60
	Services.world().entities_root().add_child(_trail)
	_place_slime(rect.position + Vector2(110.0, 260.0), Vector2.RIGHT)
	_still_camera(_stage)
	await _dodge(&"move_up")
	for i in 120:
		await _tick()
		if _phase() == "dazed" or _phase() == "skid":
			break
	_notes["after_run"] = _phase()
	await _walk(&"move_down", DODGE_FRAMES)
	await _throw_at_worm()
	await _run(_frames)


## Pen 37's Bulwark plods after the slime, which stands still in three places in turn: left of him,
## below him, above him. His charge is off for the film.
func _film_walk() -> void:
	var corner := root.find_child("bestiary-corner", true, false)
	var pen: Node = corner.call(&"pen", 37) if corner != null else null
	if pen == null:
		push_error("film_worm_bulwark: no pen 37")
		return
	var rect: Rect2 = pen.call(&"pen_rect")
	_stage = rect.get_center()
	var living: Array = pen.call(&"living")
	if living.is_empty():
		push_error("film_worm_bulwark: pen 37 has no enemy")
		return
	_worm = living[0]
	var own: Dictionary = (_worm.get(&"_pattern") as Dictionary).duplicate()
	own["sightPx"] = 0.0
	_worm.set(&"_pattern", own)
	_still_camera(_stage)
	var spots: Array[Vector2] = [Vector2(110.0, 190.0), Vector2(250.0, 420.0), Vector2(250.0, 40.0)]
	for spot in spots:
		_place_slime(rect.position + spot, Vector2.RIGHT)
		_notes["slime_at_%d" % _index] = str(spot)
		await _run(_frames)


# --- the slime's moves -----------------------------------------------------------------------------

## Waits for his charge to come within DODGE_PX, then walks `way` out of the line.
func _dodge(way: StringName) -> void:
	var player: Node = Services.world().player
	for i in 600:
		await _tick()
		if _phase() == "charge" and (_worm.call(&"get_centre") as Vector2).distance_to(player.call(&"get_centre")) <= DODGE_PX:
			break
	_notes["charge_frame"] = _index
	await _walk(way, DODGE_FRAMES)


func _walk(way: StringName, frames: int) -> void:
	_push(way, true)
	for i in frames:
		await _tick()
	_push(way, false)


## A thing of `_kind` put ahead of the slime, sucked in and thrown at him along the line he stands
## on from the slime (left, right, up or down: the nearer axis).
func _throw_at_worm() -> void:
	var world := Services.world()
	var player: Node = world.player
	var mouth: RefCounted = player.call(&"get_mouth")
	var feet := world.player_body.global_position
	var toward := (_worm.call(&"get_centre") as Vector2) - (player.call(&"get_centre") as Vector2)
	var way := Vector2(signf(toward.x), 0.0) if absf(toward.x) >= absf(toward.y) else Vector2(0.0, signf(toward.y))
	# The thing lies behind the slime, so the suck faces away from him and the throw turns round.
	player.call(&"face", -way)
	ThrowAmmo.spawn_liftable(_kind, feet - way * AMMO_AHEAD_PX, {"pop": false})
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 50:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	_notes["held_%d" % _index] = (mouth.get(&"held") as Dictionary).get("kind", "")
	for i in 6:
		await _tick()
	player.call(&"face", way)
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	_notes["throw_frame_%d" % _index] = str(way)


# --- staging ---------------------------------------------------------------------------------------

## The Bulwark with his old centre at `centre`, in an arena round the stage; `pattern` numbers set
## on his own copy of his type's `pattern` (with `--pattern=`).
func _spawn(centre: Vector2, pattern: Dictionary = {}) -> void:
	var world := Services.world()
	var parent: Node = world.entities_root()
	var enemy_root := world.instantiate_scene(ENEMY_SCENE) as Node2D
	for child: Node in enemy_root.get_children():
		if child.has_method(&"configure_navigation"):
			_worm = child
			break
	var target: Vector2 = FeetAnchor.global_for_phaser_position(enemy_root, centre)
	var parent_item := parent as CanvasItem
	enemy_root.position = parent_item.get_global_transform().affine_inverse() * target if parent_item != null else target
	parent.add_child(enemy_root)
	enemy_root.reset_physics_interpolation()
	var own: Dictionary = (_worm.get(&"_pattern") as Dictionary).duplicate()
	for key: String in pattern:
		own[key] = pattern[key]
	for key: String in _pattern_sets:
		own[key] = _pattern_sets[key]
	_worm.set(&"_pattern", own)
	var no_zones: Array[Dictionary] = []
	_worm.call(&"configure_navigation", {}, no_zones)
	_worm.call(&"configure_arena", {"shape": "circle", "x": _stage.x, "y": _stage.y, "radius": 700.0})
	_trail = Line2D.new()
	_trail.width = 2.0
	_trail.default_color = TRAIL_COLOR
	_trail.z_index = 60
	world.entities_root().add_child(_trail)


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
	camera.set(&"center", at)
	camera.set(&"target_zoom", _zoom)
	if camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", _zoom)


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


# --- running -----------------------------------------------------------------------------------------

func _run(frames: int) -> void:
	for i in frames:
		await _tick()


## One physics step; every `_every`-th one is saved as a picture and a row.
func _tick() -> void:
	await physics_frame
	_step += 1
	if is_instance_valid(_worm) and _trail != null:
		var worm_body := _worm.call(&"get_body") as Node2D
		if worm_body != null and is_instance_valid(worm_body):
			_trail.add_point(worm_body.global_position)
	if _step % _every != 0:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	var row := {}
	if is_instance_valid(_worm):
		var at: Vector2 = _worm.call(&"get_centre")
		row = {"x": snappedf(at.x - _stage.x, 0.1), "y": snappedf(at.y - _stage.y, 0.1), "hp": _health(),
			"phase": _phase(), "slime_hp": _slime_health()}
	_rows.append(row)
	_index += 1


func _phase() -> String:
	return str(_worm.call(&"get_phase")) if is_instance_valid(_worm) else "gone"


func _health() -> float:
	if not is_instance_valid(_worm):
		return 0.0
	var value: Variant = _worm.get(&"_hp")
	return float(value) if value is float or value is int else -1.0


func _slime_health() -> float:
	var player: Node = Services.world().player
	if player == null or not player.has_method(&"get_damage_state"):
		return -1.0
	return float((player.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


## The key as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

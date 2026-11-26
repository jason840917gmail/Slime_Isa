extends SceneTree
## Pictures the Spear's reach in the game (docs/godot/BODY_SHAPES.md "The Spear's reach"): the jab, the
## finisher (the lunging jab) and the Lunge (its charge) in all four directions against the shapes testbed's
## boss dummy, then the jab against a wall in all four directions, one still each at the strike's full reach
## (the middle of its active window), with the hit line the game queries outlined (yellow), the slime's feet
## (a cross), the tip's reach from the feet along the aim (cyan) and its number written beside it. Run
## windowed (it renders), one game window at a time:
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_spear_reach.gd -- \
##         --out=<dir> [--zoom=<z>] [--at=<x>,<y>] [--dummy-px=<d>] [--wall-px=<d>]
## `--at` is where the slime stands (world px; the player's spawn by default), `--dummy-px` how far ahead of
## its feet the dummy's feet stand (90), `--wall-px` how far ahead of its feet a wall's near face is (75).
## Writes <dir>/<strike>-<direction>.png (each still, framed a little ahead of the slime's feet) and
## <dir>/film.json (per still: the strike, the direction, the line's reach from the centre, the tip's reach
## from the feet, the wall's distance, whether the dummy was hit). `scripts/godot/spear-reach-sheet.py` lays
## them out.

const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapeStrike := preload("res://game/shapes/shape_strike.gd")
const ShapeControllerScript := preload("res://game/shapes/shape_controller.gd")
const TrainingDummyScript := preload("res://game/scripts/training_dummy.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 300.0
## The still is cut round a point FRAME_AHEAD_PX ahead of the slime's feet along the aim (screen px).
const CROP := Vector2i(500, 500)
const FRAME_AHEAD_PX := 66.0
const DUMMY_NAME := "shapes-dummy-boss"
## Open grass in the playground, from the player's spawn: clear of the testbed's pen and the corners.
const OPEN_GRASS := Vector2(-880.0, 430.0)
const DIRECTIONS: Dictionary = {"right": Vector2.RIGHT, "left": Vector2.LEFT, "down": Vector2.DOWN, "up": Vector2.UP}
## Each strike: the chain step's index (-1: the charge).
const STRIKES: Dictionary = {"jab": 0, "finisher": 2, "lunge": -1}
const LINE_COLOR := Color(1.0, 0.92, 0.2, 0.95)
const REACH_COLOR := Color(0.3, 0.95, 1.0, 0.95)
const WALL_COLOR := Color(0.32, 0.3, 0.36, 1.0)
const TEXT_SIZE := 9
## Where the world's walls sit (project.godot `layer_names/2d_physics`).
const LAYER_WORLD := "world"

var _main: Node
var _out := "user://spear-reach"
var _zoom := 1.6
var _at := Vector2.INF
var _dummy_px := 90.0
var _wall_px := 75.0
var _shapes: Node = null
var _dummy: Node = null
var _overlay: Node2D = null
var _wall: StaticBody2D = null
var _draw_info: Dictionary = {}
var _rows: Array = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--at="):
			var parts := arg.trim_prefix("--at=").split(",")
			if parts.size() == 2:
				_at = Vector2(float(parts[0]), float(parts[1]))
		elif arg.begins_with("--dummy-px="):
			_dummy_px = float(arg.trim_prefix("--dummy-px="))
		elif arg.begins_with("--wall-px="):
			_wall_px = float(arg.trim_prefix("--wall-px="))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_spear_reach: gave up after %d s" % int(WATCHDOG_S))
		quit(1))
	DisplayServer.window_set_size(WINDOW)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", MAP_ID)
	_main.set(&"ability_ceremonies", false)
	root.add_child(_main)
	for i in 90:
		await process_frame
	if Services.feel() != null:
		Services.feel().frame_clock_ms = 1000.0 / 60.0
	if not _setup():
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--overview"):
		_center_camera(_at)
		var camera: Node = Services.world().camera
		camera.set(&"target_zoom", 0.35)
		camera.call(&"apply_zoom", 0.35)
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("overview.png")))
		print("film_spear_reach: overview at ", _at, " spawn ", Services.world().player_spawn_point())
		quit()
		return
	for strike: String in STRIKES:
		for direction: String in DIRECTIONS:
			await _still(strike, direction, false)
	for direction: String in DIRECTIONS:
		await _still("jab", direction, true)
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"zoom": _zoom, "dummy_px": _dummy_px, "wall_px": _wall_px, "crop": [CROP.x, CROP.y],
		"rows": _rows}, "\t"))
	file.close()
	print("film_spear_reach: ", _rows.size(), " stills")
	quit()


func _setup() -> bool:
	var world := Services.world()
	var player: Node = world.player
	_shapes = player.get(&"_shapes")
	if _shapes == null:
		push_error("film_spear_reach: the slime has no shapes")
		return false
	Services.run().learn_ability(String(ShapeDefs.SPEAR), true)
	_shapes.call(&"sync_learned")
	_shapes.call(&"set_current", ShapeDefs.SPEAR)
	var dummy_root := root.find_child(DUMMY_NAME, true, false)
	if dummy_root != null:
		for node: Node in dummy_root.find_children("*", "", true, false):
			if node.get_script() == TrainingDummyScript:
				_dummy = node
				break
	if _dummy == null:
		push_error("film_spear_reach: no %s" % DUMMY_NAME)
		return false
	if _at == Vector2.INF:
		_at = world.player_spawn_point() + OPEN_GRASS
	_overlay = Node2D.new()
	_overlay.name = "SpearReachOverlay"
	_overlay.z_index = 100
	_overlay.draw.connect(_draw_overlay)
	world.entities_root().add_child(_overlay)
	return true


## One still: the slime at `_at` facing `direction`, the dummy ahead (or a wall ahead, `walled`), the strike
## begun and pictured at the middle of its active window.
func _still(strike: String, direction: String, walled: bool) -> void:
	var aim: Vector2 = DIRECTIONS[direction]
	var world := Services.world()
	var player: Node = world.player
	_place_slime(_at, aim)
	_place_dummy(_at + aim * _dummy_px if not walled else _at + Vector2(-600.0, 300.0))
	_place_wall(Vector2.ZERO)
	_draw_info = {}
	_overlay.queue_redraw()
	if player.has_method(&"set_energy"):
		player.call(&"set_energy", 100.0)
	for i in 40:
		await physics_frame
	# The wall from where the feet stand now (the slime may have settled a few units off the spot).
	_place_slime(world.player_body.global_position, aim)
	_place_wall(aim if walled else Vector2.ZERO)
	for i in 3:
		await physics_frame
	_shapes.call(&"reset_chain", "film")
	var hits_before := int(_dummy.get(&"hits"))
	var index: int = STRIKES[strike]
	var data: Dictionary
	if index >= 0:
		_shapes.call(&"_begin_step", index, aim)
		data = ShapeDefs.step(ShapeDefs.SPEAR, index)
	else:
		data = ShapeDefs.charge(ShapeDefs.SPEAR)
		_shapes.call(&"_begin_unit", ShapeControllerScript.Phase.CHARGE, data, aim)
	var at_ms := ShapeDefs.num(data, "windupMs") + ShapeDefs.num(data, "activeMs") * 0.5
	var started := float(_shapes.get(&"_started_ms"))
	for i in 120:
		await physics_frame
		if Services.now_ms() - started >= at_ms:
			break
	_measure(walled)
	_overlay.queue_redraw()
	_center_camera(world.player_body.global_position + aim * FRAME_AHEAD_PX)
	_hide_screens()
	await process_frame
	await RenderingServer.frame_post_draw
	var name := "%s-%s%s" % [strike, direction, "-wall" if walled else ""]
	var image := root.get_texture().get_image()
	var size := image.get_size()
	var crop := Rect2i((size - CROP) / 2, CROP).intersection(Rect2i(Vector2i.ZERO, size))
	image.get_region(crop).save_png(ProjectSettings.globalize_path(_out.path_join(name + ".png")))
	for i in 20:
		await physics_frame
	var row: Dictionary = _draw_info.duplicate()
	row.erase("outline")
	row.erase("feet")
	row.erase("tip")
	row["name"] = name
	row["strike"] = strike
	row["direction"] = direction
	row["walled"] = walled
	row["dummy_hit"] = int(_dummy.get(&"hits")) > hits_before
	_rows.append(row)
	print("film_spear_reach: ", name, " ", JSON.stringify(row))
	_draw_info = {}
	_overlay.queue_redraw()


## What the shape controller hits with now: its hit line (the area it queries, `ShapeStrike.area_shapes`), the
## tip (the line's far end) and its reach from the feet along the aim.
func _measure(walled: bool) -> void:
	var world := Services.world()
	var player: Node = world.player
	var feet: Vector2 = world.player_body.global_position
	var centre: Vector2 = player.call(&"get_centre")
	var aim: Vector2 = _shapes.get(&"_aim")
	# The reach the hit uses at this moment (its wall cut taken from where the feet are now, as `_contact` does).
	var reach := float(_shapes.call(&"_line_reach", centre))
	var hit_data: Dictionary = _shapes.get(&"_hit_data")
	var origin := centre + ShapeStrike.hit_offset(hit_data)
	var tip := origin + aim * reach
	var outline := PackedVector2Array()
	for shape: Dictionary in ShapeStrike.area_shapes(hit_data, centre, aim, reach, float(_shapes.get(&"_sweep"))):
		var rect := shape["shape"] as RectangleShape2D
		var xf: Transform2D = shape["transform"]
		if rect == null:
			continue
		var half := rect.size * 0.5
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y),
				Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]:
			outline.append(xf * corner)
	_draw_info = {
		"feet": feet,
		"tip": tip,
		"aim": [aim.x, aim.y],
		"outline": outline,
		"reach_from_centre": snappedf(reach, 0.1),
		"tip_from_feet": snappedf((tip - feet).dot(aim), 0.1),
		"centre_above_feet": snappedf(feet.y - centre.y, 0.01),
		"wall_px": _wall_face(aim, feet) if walled else -1.0,
		"feet_off_spot": [snappedf(feet.x - _at.x, 0.1), snappedf(feet.y - _at.y, 0.1)],
	}


## How far ahead of `feet` along `aim` the wall's near face is now.
func _wall_face(aim: Vector2, feet: Vector2) -> float:
	if _wall == null or not is_instance_valid(_wall):
		return -1.0
	var rect := (_wall.get_child(0) as CollisionShape2D).shape as RectangleShape2D
	var half := absf(rect.size.dot(aim)) * 0.5
	return snappedf((_wall.global_position - feet).dot(aim) - half, 0.1)


func _draw_overlay() -> void:
	if _draw_info.is_empty():
		return
	var feet: Vector2 = _draw_info["feet"]
	var tip: Vector2 = _draw_info["tip"]
	var aim := Vector2(_draw_info["aim"][0], _draw_info["aim"][1])
	var outline: PackedVector2Array = _draw_info["outline"]
	if outline.size() >= 2:
		_overlay.draw_polyline(outline, LINE_COLOR, 1.0)
	_overlay.draw_line(feet + Vector2(-5, 0), feet + Vector2(5, 0), REACH_COLOR, 1.0)
	_overlay.draw_line(feet + Vector2(0, -5), feet + Vector2(0, 5), REACH_COLOR, 1.0)
	# The tip's reach from the feet along the aim, drawn beside the aim line through the feet.
	var across := Vector2(-aim.y, aim.x) * (-18.0 if absf(aim.x) < 0.5 else 14.0)
	var along := (tip - feet).dot(aim)
	var from := feet + across
	var to := feet + across + aim * along
	_overlay.draw_line(from, to, REACH_COLOR, 1.0)
	_overlay.draw_line(to - Vector2(-aim.y, aim.x) * 4.0, to + Vector2(-aim.y, aim.x) * 4.0, REACH_COLOR, 1.0)
	_overlay.draw_line(from - Vector2(-aim.y, aim.x) * 4.0, from + Vector2(-aim.y, aim.x) * 4.0, REACH_COLOR, 1.0)
	_overlay.draw_circle(tip, 2.0, LINE_COLOR)
	var font := ThemeDB.fallback_font
	var text := "%d" % roundi(along)
	var label_at := (from + to) * 0.5 + across.normalized() * 10.0 + Vector2(-8.0, 3.0)
	_overlay.draw_string_outline(font, label_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, 3, Color.BLACK)
	_overlay.draw_string(font, label_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TEXT_SIZE, REACH_COLOR)


# --- staging ---------------------------------------------------------------------------------------

## The HUD, hints and texts out of the pictures.
func _hide_screens() -> void:
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false


func _place_slime(feet: Vector2, facing: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var body := world.player_body
	player.call(&"teleport", feet + ((player.call(&"get_centre") as Vector2) - body.global_position))
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	player.call(&"face", facing)


## The dummy's feet at `feet`, its post moved there too (it walks back to its post after a knock).
func _place_dummy(feet: Vector2) -> void:
	var body := _dummy.call(&"get_body") as CharacterBody2D
	if body == null:
		return
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	_dummy.set(&"_post", feet)
	_dummy.call(&"set_hit_stun_until", 0.0)


## A wall across `aim` (none for ZERO), its near face `_wall_px` ahead of the slime's feet as they stand, on the world's
## layer (what the Spear's wall ray stops at), drawn grey.
func _place_wall(aim: Vector2) -> void:
	if _wall != null and is_instance_valid(_wall):
		_wall.queue_free()
		_wall = null
	if aim == Vector2.ZERO:
		return
	var thick := 40.0
	var wide := 160.0
	_wall = StaticBody2D.new()
	_wall.name = "SpearReachWall"
	_wall.collision_layer = ShapeStrike.layer_bit(LAYER_WORLD)
	_wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(thick, wide) if absf(aim.x) > 0.5 else Vector2(wide, thick)
	shape.shape = rect
	_wall.add_child(shape)
	var look := Polygon2D.new()
	var half := rect.size * 0.5
	look.polygon = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y),
		Vector2(-half.x, half.y)])
	look.color = WALL_COLOR
	_wall.add_child(look)
	_wall.z_index = 50
	Services.world().entities_root().add_child(_wall)
	_wall.global_position = Services.world().player_body.global_position + aim * (_wall_px + thick * 0.5)


func _center_camera(at: Vector2) -> void:
	var camera: Node = Services.world().camera
	if camera == null:
		return
	camera.call(&"stop_follow")
	camera.set(&"use_bounds", false)
	camera.set(&"center", at)
	camera.set(&"target_zoom", _zoom)
	if camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", _zoom)

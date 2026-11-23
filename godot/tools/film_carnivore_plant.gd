extends SceneTree
## Films the Carnivore Plant (docs/godot/BESTIARY.md "38. Carnivore Plant") in her Bestiary pen
## (pen 38), frame by frame, with the camera still over the pen. Run windowed (it renders) with a
## fixed frame time, one film at a time (or through
## `scripts/godot/film-enemy-ways.sh <name> --tool=film_carnivore_plant --film=<film>`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_carnivore_plant.gd -- \
##         --out=<dir> --film=<name> [--frames=<n>] [--every=<n>] [--zoom=<z>] [--approach=left|below|above]
##         [--reach=<px>] (her `reach_px`; her bite and tell reach are drawn round her, as the editor does)
## Films (spots are from the pen's top-left; the plant stands at (256, 210)):
##   bite   the slime walks at her (`--approach`: the left, below her, above her) and stops in reach: she
##          opens, snaps, drags it in, chews and spits it far back out
##   eat    the pen's worm on her right, the slime on her left out of her reach: the worm walks at
##          the slime past her; she snaps it up, eats it and sleeps to digest
##   doze   a pot thrown at her puts her to sleep; the slime walks right past her
##   fire   a Lantern puff (the pen's ability) burns her
##   feed   a slime spider lies knocked down by the slime (as a throw leaves it: helpless); the Gulp
##          takes it and throws it at her: it bounces off her and lies there; she picks it up off the
##          floor, eats it and sleeps to digest
## Writes <dir>/f<nnn>.png and <dir>/film.json (her phase and the slime's health per saved frame).

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const PEN := 38
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 300.0
## Where a thing to throw is put, behind the slime's feet.
const AMMO_AHEAD_PX := 34.0

var _main: Node
var _out := "user://carnivore-plant"
var _film := "bite"
var _frames := 240
var _every := 3
var _zoom := 1.6
var _from := "left"
var _reach := 0.0
var _index := 0
var _step := 0
var _rect := Rect2()
var _plant: Node = null
var _worm: Node = null
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
		elif arg.begins_with("--reach="):
			_reach = float(arg.trim_prefix("--reach="))
		elif arg.begins_with("--approach="):
			_from = arg.trim_prefix("--approach=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_carnivore_plant: gave up after %d s" % int(WATCHDOG_S))
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
	if not _find_pen():
		quit(1)
		return
	match _film:
		"bite":
			await _film_bite()
		"eat":
			await _film_eat()
		"doze":
			await _film_doze()
		"fire":
			await _film_fire()
		"feed":
			await _film_feed()
		_:
			push_error("film_carnivore_plant: no film '%s'" % _film)
	_notes["phase_at_end"] = _phase()
	_notes["slime_hp_at_end"] = _slime_health()
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"film": _film, "frames": _index, "every": _every, "notes": _notes,
		"rows": _rows}, "\t"))
	file.close()
	print("film_carnivore_plant: ", _film, " ", JSON.stringify(_notes))
	quit()


func _find_pen() -> bool:
	var corner := root.find_child("bestiary-corner", true, false)
	var pen: Node = corner.call(&"pen", PEN) if corner != null else null
	if pen == null:
		push_error("film_carnivore_plant: no pen %d" % PEN)
		return false
	_rect = pen.call(&"pen_rect")
	for enemy: Node in pen.call(&"living"):
		if enemy.has_method(&"catch_thrown"):
			_plant = enemy
		else:
			_worm = enemy
	if _plant == null:
		push_error("film_carnivore_plant: pen %d has no plant" % PEN)
		return false
	_still_camera(_rect.get_center())
	if _reach > 0.0:
		_plant.set(&"reach_px", _reach)
	_draw_reach()
	return true


## Her bite reach (red) and where she starts to open (orange) round her pot, as the editor draws them.
func _draw_reach() -> void:
	var feet: Vector2 = (_plant.call(&"get_body") as Node2D).global_position
	var rings := [[float(_plant.call(&"bite_reach")), Color(1.0, 0.3, 0.3, 0.9)], [float(_plant.call(&"tell_reach")), Color(1.0, 0.65, 0.3, 0.75)]]
	for ring: Array in rings:
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = ring[1]
		line.z_index = 60
		for i in 65:
			line.add_point(feet + Vector2.from_angle(TAU * float(i) / 64.0) * float(ring[0]))
		Services.world().entities_root().add_child(line)


# --- the films ---------------------------------------------------------------------------------------

## The pen's worm lies knocked down in its corner for the films that are not about it.
func _hold_worm() -> void:
	if _worm != null and is_instance_valid(_worm):
		EnemyReactions.put_down(_worm, 60000.0)


func _film_bite() -> void:
	_hold_worm()
	var start := _at(60.0, 210.0)
	var way := Vector2.RIGHT
	var key := &"move_right"
	if _from == "below":
		start = _at(256.0, 400.0)
		way = Vector2.UP
		key = &"move_up"
	elif _from == "above":
		start = _at(256.0, 30.0)
		way = Vector2.DOWN
		key = &"move_down"
	_place_slime(start, way)
	_push(key, true)
	for i in 180:
		await _tick()
		if _phase() == "open":
			break
	_push(key, false)
	_notes["open_frame"] = _index
	await _run(_frames)
	_notes["slime_hurt"] = 100.0 - _slime_health()


func _film_eat() -> void:
	# The worm on her right, the slime on her left out of her reach: the worm walks straight at the
	# slime, past her.
	if _worm != null and is_instance_valid(_worm):
		var worm_body := _worm.call(&"get_body") as Node2D
		worm_body.global_position = _at(346.0, 216.0)
		worm_body.reset_physics_interpolation()
	_place_slime(_at(150.0, 216.0), Vector2.RIGHT)
	await _run(_frames)
	_notes["worm_eaten"] = _worm == null or not is_instance_valid(_worm) or bool(_worm.call(&"is_defeated"))


func _film_doze() -> void:
	_hold_worm()
	_place_slime(_at(100.0, 210.0), Vector2.RIGHT)
	for i in 6:
		await _tick()
	await _throw(Vector2.RIGHT, "clay-pot")
	for i in 60:
		await _tick()
		if _phase() == "doze":
			break
	_notes["doze_frame"] = _index
	# Right past her while she sleeps.
	_push(&"move_right", true)
	for i in 70:
		await _tick()
	_push(&"move_right", false)
	await _run(_frames)
	_notes["slime_hurt"] = 100.0 - _slime_health()


func _film_fire() -> void:
	_hold_worm()
	_place_slime(_at(160.0, 210.0), Vector2.RIGHT)
	for i in 20:
		await _tick()
	_push(&"ability_use", true)
	await _tick()
	await _tick()
	_push(&"ability_use", false)
	await _run(_frames)
	_notes["burnt"] = bool(_plant.call(&"is_defeated")) if is_instance_valid(_plant) else true


func _film_feed() -> void:
	_hold_worm()
	_place_slime(_at(100.0, 210.0), Vector2.DOWN)
	var spider := _spawn("slime-spider", _at(100.0, 268.0))
	for i in 4:
		await _tick()
	EnemyReactions.put_down(spider, 4000.0)
	# Helpless as a throw leaves it (only then can the Gulp take an enemy).
	EnemyReactions.state_of(spider).throw_helpless = true
	for i in 10:
		await _tick()
	var mouth: RefCounted = Services.world().player.call(&"get_mouth")
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 60:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	_notes["held"] = (mouth.get(&"held") as Dictionary).get("kind", "")
	for i in 8:
		await _tick()
	Services.world().player.call(&"face", Vector2.RIGHT)
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	await _run(_frames)
	_notes["spider_eaten"] = not is_instance_valid(spider) or bool(spider.call(&"is_defeated"))


# --- the slime's moves -------------------------------------------------------------------------------

func _walk(way: StringName, frames: int) -> void:
	_push(way, true)
	for i in frames:
		await _tick()
	_push(way, false)


## A thing of `kind` put behind the slime, sucked in and thrown along `way`.
func _throw(way: Vector2, kind: String) -> void:
	var world := Services.world()
	var player: Node = world.player
	var mouth: RefCounted = player.call(&"get_mouth")
	player.call(&"face", -way)
	ThrowAmmo.spawn_liftable(kind, world.player_body.global_position - way * AMMO_AHEAD_PX, {"pop": false})
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 50:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	for i in 6:
		await _tick()
	player.call(&"face", way)
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	_notes["throw_frame"] = _index


# --- staging ---------------------------------------------------------------------------------------

func _at(x: float, y: float) -> Vector2:
	return _rect.position + Vector2(x, y)


## An enemy of `type_id` with its feet at `feet`, in the pen's arena.
func _spawn(type_id: String, feet: Vector2) -> Node:
	var world := Services.world()
	var parent: Node = world.entities_root()
	var enemy_root := world.instantiate_scene("character." + type_id) as Node2D
	var enemy: Node = null
	for child: Node in enemy_root.get_children():
		if child.has_method(&"configure_navigation"):
			enemy = child
			break
	var parent_item := parent as CanvasItem
	enemy_root.position = parent_item.get_global_transform().affine_inverse() * feet if parent_item != null else feet
	parent.add_child(enemy_root)
	enemy_root.reset_physics_interpolation()
	var no_zones: Array[Dictionary] = []
	enemy.call(&"configure_navigation", {}, no_zones)
	var middle := _rect.get_center()
	enemy.call(&"configure_arena", {"shape": "circle", "x": middle.x, "y": middle.y, "radius": 400.0})
	return enemy


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


# --- running -----------------------------------------------------------------------------------------

func _run(frames: int) -> void:
	for i in frames:
		await _tick()


func _tick() -> void:
	await physics_frame
	_step += 1
	if _step % _every != 0:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	_rows.append({"phase": _phase(), "slime_hp": _slime_health(),
		"worm": "gone" if _worm == null or not is_instance_valid(_worm) else ("dead" if bool(_worm.call(&"is_defeated")) else "alive")})
	_index += 1


func _phase() -> String:
	return str(_plant.call(&"get_phase")) if is_instance_valid(_plant) else "gone"


func _slime_health() -> float:
	var player: Node = Services.world().player
	if player == null or not player.has_method(&"get_damage_state"):
		return -1.0
	return float((player.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

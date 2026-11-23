extends SceneTree
## Films the Jelly Bouncer (docs/godot/BESTIARY.md "39. Jelly Bouncer") in his Bestiary pen (pen 39),
## frame by frame, with the camera still over him. Run windowed (it renders) with a fixed frame time,
## one film at a time (or through
## `scripts/godot/film-enemy-ways.sh <name> --tool=film_jelly_bouncer --film=<film>`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_jelly_bouncer.gd -- \
##         --out=<dir> --film=<name> [--frames=<n>] [--every=<n>] [--zoom=<z>]
## Films (the jelly is held still at the pen's middle, his zap's reach drawn round him):
##   zap     the slime beside him and the pen's brawler (knocked down) on his other side: he charges
##           and zaps; both are shocked, their bones flickering
##   throw   the slime throws a clay pot at him from afar: it bounces back and hits the slime
##   catch   the same with a lump of coal (stone: sturdy, light), and Q as it comes back: the mouth catches it ("Catch!")
##   spear   the slime strikes him with the Spear: no harm to him, the slime is shocked
##   arrows  the slime shoots him twice with the Bow: he melts
## Writes <dir>/f<nnn>.png and <dir>/film.json (his phase and health, the slime's health per frame).

const Services := preload("res://game/shared/services.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ThrowRebound := preload("res://game/throw/throw_rebound.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const PEN := 39
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 300.0
## Where a thing to throw is put, behind the slime's feet.
const AMMO_AHEAD_PX := 34.0
## Where the jelly is held (from the pen's top-left).
const STAGE := Vector2(256.0, 224.0)

var _main: Node
var _out := "user://jelly-bouncer"
var _film := "zap"
var _frames := 150
var _every := 3
var _zoom := 1.8
var _index := 0
var _step := 0
var _rect := Rect2()
var _jelly: Node = null
var _brawler: Node = null
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_jelly_bouncer: gave up after %d s" % int(WATCHDOG_S))
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
		"zap":
			await _film_zap()
		"throw":
			await _film_throw("clay-pot", false)
		"catch":
			await _film_throw("coal", true)
		"spear":
			await _film_spear()
		"arrows":
			await _film_arrows()
		_:
			push_error("film_jelly_bouncer: no film '%s'" % _film)
	_notes["phase_at_end"] = _phase()
	_notes["jelly_hp_at_end"] = _jelly_health()
	_notes["slime_hp_at_end"] = _slime_health()
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"film": _film, "frames": _index, "every": _every, "notes": _notes,
		"rows": _rows}, "\t"))
	file.close()
	print("film_jelly_bouncer: ", _film, " ", JSON.stringify(_notes))
	quit()


func _find_pen() -> bool:
	var corner := root.find_child("bestiary-corner", true, false)
	var pen: Node = corner.call(&"pen", PEN) if corner != null else null
	if pen == null:
		push_error("film_jelly_bouncer: no pen %d" % PEN)
		return false
	_rect = pen.call(&"pen_rect")
	for enemy: Node in pen.call(&"living"):
		if enemy.has_method(&"bounces_throw"):
			_jelly = enemy
		else:
			_brawler = enemy
	if _jelly == null:
		push_error("film_jelly_bouncer: pen %d has no jelly" % PEN)
		return false
	var jelly_body := _jelly.call(&"get_body") as Node2D
	jelly_body.global_position = _at(STAGE.x, STAGE.y)
	jelly_body.reset_physics_interpolation()
	_jelly.call(&"set_home", _jelly.call(&"get_centre"))
	_hold_jelly()
	_still_camera(_at(STAGE.x, STAGE.y - 20.0))
	_draw_reach()
	return true


## He stays where he is (no hop) and does not zap until a film says so.
func _hold_jelly() -> void:
	_jelly.set(&"_next_hop_at", INF)
	_jelly.set(&"_zap_at", INF)


func _zap_now() -> void:
	_jelly.set(&"_zap_at", Services.now_ms())


## His zap's reach round his feet.
func _draw_reach() -> void:
	var feet: Vector2 = (_jelly.call(&"get_body") as Node2D).global_position
	var line := Line2D.new()
	line.width = 1.5
	line.default_color = Color(1.0, 0.4, 0.3, 0.7)
	line.z_index = 60
	var reach := float(_jelly.call(&"zap_reach"))
	for i in 65:
		line.add_point(feet + Vector2.from_angle(TAU * float(i) / 64.0) * reach)
	Services.world().entities_root().add_child(line)


# --- the films ---------------------------------------------------------------------------------------

func _hold_brawler(at: Vector2) -> void:
	if _brawler == null or not is_instance_valid(_brawler):
		return
	var body := _brawler.call(&"get_body") as Node2D
	body.global_position = at
	body.reset_physics_interpolation()
	EnemyReactions.put_down(_brawler, 60000.0)


func _brawler_away() -> void:
	_hold_brawler(_at(470.0, 420.0))


func _film_zap() -> void:
	_hold_brawler(_at(STAGE.x + 64.0, STAGE.y + 10.0))
	_place_slime(_at(STAGE.x - 62.0, STAGE.y), Vector2.RIGHT)
	for i in 8:
		await _tick()
	_zap_now()
	await _run(_frames)
	_notes["slime_hurt"] = 100.0 - _slime_health()
	_notes["brawler_hp"] = float((_brawler.call(&"get_damage_state") as Dictionary).get("hp", -1.0)) if _brawler != null and is_instance_valid(_brawler) else -1.0


func _film_throw(kind: String, catch: bool) -> void:
	_brawler_away()
	_place_slime(_at(STAGE.x - 150.0, STAGE.y), Vector2.RIGHT)
	for i in 6:
		await _tick()
	await _throw(Vector2.RIGHT, kind)
	if not catch:
		await _run(_frames)
		_notes["slime_hurt"] = 100.0 - _slime_health()
		return
	var mouth: RefCounted = Services.world().player.call(&"get_mouth")
	var caught := false
	for i in 120:
		await _tick()
		var feet: Vector2 = Services.world().player_body.global_position
		if ThrowRebound.nearest_catchable(feet, ThrowFeel.rebound_number("catchRangePx", 0.0)) != null:
			_push(&"eat", true)
			await _tick()
			_push(&"eat", false)
			_notes["catch_frame"] = _index
			break
	for i in 10:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			caught = true
	_notes["caught"] = caught
	_notes["held"] = (mouth.get(&"held") as Dictionary).duplicate()
	await _run(_frames)
	_notes["slime_hurt"] = 100.0 - _slime_health()


func _film_spear() -> void:
	_brawler_away()
	Services.run().learn_ability(String(ShapeDefs.SPEAR), true)
	var shapes: Node = Services.world().player.get(&"_shapes")
	if shapes != null:
		shapes.call(&"sync_learned")
		shapes.call(&"set_current", ShapeDefs.SPEAR)
		_notes["shape"] = String(shapes.call(&"current_shape_id"))
	_notes["learned"] = Services.run().has_learned_ability(String(ShapeDefs.SPEAR))
	_place_slime(_at(STAGE.x - 48.0, STAGE.y), Vector2.RIGHT)
	for i in 6:
		await _tick()
	_push(&"attack", true)
	await _tick()
	await _tick()
	_push(&"attack", false)
	for i in 20:
		await _tick()
		if shapes != null and bool(shapes.call(&"is_busy")):
			_notes["struck_frame"] = _index
			break
	# No strike from the pressed key (the input map): the press straight to the shapes, a tap.
	if shapes != null and not _notes.has("struck_frame"):
		_notes["pressed_direct"] = bool(shapes.call(&"press_attack", Vector2.RIGHT))
	await _run(_frames)
	_notes["slime_hurt"] = 100.0 - _slime_health()


func _film_arrows() -> void:
	_brawler_away()
	_place_slime(_at(STAGE.x - 170.0, STAGE.y), Vector2.RIGHT)
	for i in 10:
		await _tick()
	var player: Node = Services.world().player
	Services.run().learn_ability(String(AbilityDefinitions.BOW), true)
	AbilityBox.select(player, AbilityDefinitions.BOW)
	_notes["box"] = String(AbilityBox.selected(player))
	for shot in 2:
		player.call(&"face", Vector2.RIGHT)
		_push(&"ability_use", true)
		await _tick()
		await _tick()
		_push(&"ability_use", false)
		for i in 40:
			await _tick()
		_notes["jelly_hp_after_%d" % (shot + 1)] = _jelly_health()
	await _run(_frames)


# --- the slime's moves -------------------------------------------------------------------------------

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
	_rows.append({"phase": _phase(), "jelly_hp": _jelly_health(), "slime_hp": _slime_health()})
	_index += 1


func _phase() -> String:
	return str(_jelly.call(&"get_phase")) if is_instance_valid(_jelly) else "gone"


func _jelly_health() -> float:
	if not is_instance_valid(_jelly):
		return -1.0
	return float((_jelly.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


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

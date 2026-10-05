extends RefCounted
## Stretch Lash (Phaser `LegacyPlayerAbilityPresentation.ts:319-424`; abilities spec 8). A goo
## hook thrown 180 px along the aim: the slime leans in while the tendril reaches out (frames 0-2
## over 120 ms), then acts on what it caught:
## - nothing: the tendril pulls back; done at 270 ms;
## - a pile (light): the pile flies to the slime in 220 ms and is picked up; done at 290 ms;
## - a wall, post or bell (heavy): bells at the tip ring, and the slime is pulled to 30 px short of
##   the catch (over water too) in max(120, travel / 0.9) ms from 170 ms, then springs; a pull
##   under 8 px just retracts (done at 280 ms).
## No damage. The pull moves the body directly (`owns_body`), so nothing blocks it.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const AbilityTerrain := preload("res://game/player/abilities/ability_terrain.gd")

const TENDRIL_TEXTURE := "res://asset/MAPS/effects/384x96-tile_4x2-stretch-lash.webp"
const TENDRIL_FRAME_WIDTH := 384.0
const TENDRIL_ORIGIN_Y := 52.0
const TENDRIL_MIN_LENGTH := 48.0
const LEAN_PX := 8.0
const LEAN_SCALE := Vector2(1.14, 0.88)
const LEAN_MS := 110.0
const CATCH_MS := 120.0
const PULL_START_MS := 170.0
## STRETCH_LASH_PULL_SPEED (px per ms) and the shortest pull.
const PULL_SPEED := 0.9
const PULL_MIN_MS := 120.0
const PULL_SPRING := Vector2(1.2, 0.82)
const PULL_SPRING_MS := 90.0
const MIN_TRAVEL_PX := 8.0
## The light catch: the pile flies to the slime.
const PICKUP_PULL_MS := 220.0

var _player: Node
var _intent: Dictionary
var _started_ms: float = 0.0
var _from: Vector2
var _direction: Vector2
var _probe: Dictionary = {}
var _tendril: Sprite2D
var _tween: Tween
## Frame changes after the catch: [[ms from the start, frame (-1 = remove the tendril)], ...].
var _frames: Array = []
var _done_ms: float = INF
var _caught: bool = false
var _landing: Vector2
var _flight_ms: float = 0.0
var _flying: bool = false
var _flight_over: bool = false


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_intent = intent
	_started_ms = now_ms
	_from = intent["start"]
	_direction = intent["direction"]
	var definition: Dictionary = intent["definition"]
	_probe = AbilityWorld.lash_probe(_from, _from + _direction * float(definition["distance"]), _player.call(&"body_rids"))
	_player.call(&"action_cue", &"Lash")
	# The slime turns toward the throw so its directional lash clip reaches where the tendril goes
	# (Phaser keeps the facing; its side-view art did not show it).
	_player.call(&"face", _direction)
	_player.call(&"play_animation", "stretch")
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_tween = _player.call(&"effect_tween")
	if _tween != null:
		_tween.tween_method(_offset, Vector2.ZERO, _direction * LEAN_PX, LEAN_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_method(_scale, Vector2.ONE, LEAN_SCALE, LEAN_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_offset, _direction * LEAN_PX, Vector2.ZERO, LEAN_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_method(_scale, LEAN_SCALE, Vector2.ONE, LEAN_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tendril = _make_tendril()
	_frames = [[40.0, 1], [80.0, 2]]


func owns_body() -> bool:
	return _flying


func advance(now_ms: float) -> bool:
	var elapsed := now_ms - _started_ms
	while not _frames.is_empty() and elapsed >= float(_frames[0][0]):
		var step: Array = _frames.pop_front()
		_set_frame(int(step[1]))
	if not _caught and elapsed >= CATCH_MS:
		_catch()
	if _flying:
		_fly(elapsed)
	return elapsed >= _done_ms


func cancel() -> void:
	_flying = false
	_kill()
	_free_tendril()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


func _catch() -> void:
	_caught = true
	match str(_probe.get("kind", "none")):
		"light":
			_set_frame(4)
			_pull_pickup(_probe.get("pickup"))
			_frames = [[CATCH_MS + 60.0, 6], [CATCH_MS + 120.0, 7], [CATCH_MS + 170.0, -1]]
			_done_ms = CATCH_MS + 170.0
		"heavy":
			_set_frame(4)
			var caught: Vector2 = _probe["at"]
			AbilityWorld.lash_ring(_from, caught)
			_landing = AbilityTerrain.lash_landing(_from, _probe.get("anchor", caught))
			var travel := _from.distance_to(_landing)
			if travel < MIN_TRAVEL_PX:
				_frames = [[CATCH_MS + 60.0, 6], [CATCH_MS + 110.0, 7], [CATCH_MS + 160.0, -1]]
				_done_ms = CATCH_MS + 160.0
			else:
				_flight_ms = maxf(PULL_MIN_MS, travel / PULL_SPEED)
				_frames = [[PULL_START_MS, 3]]
				_flying = true
				_done_ms = INF
		_:
			_set_frame(3)
			_frames = [[CATCH_MS + 50.0, 6], [CATCH_MS + 100.0, 7], [CATCH_MS + 150.0, -1]]
			_done_ms = CATCH_MS + 150.0


## The pull: from 170 ms the body follows the line to the landing (Quad.In), the tendril drawn
## from it to the catch; then the spring and the end 180 ms later.
func _fly(elapsed: float) -> void:
	if elapsed < PULL_START_MS or _flight_over:
		return
	var t := clampf((elapsed - PULL_START_MS) / _flight_ms, 0.0, 1.0)
	var point := _from + (_landing - _from) * (t * t)
	_player.call(&"teleport", point)
	_place_tendril(point, _probe["at"])
	if t < 1.0:
		return
	_flight_over = true
	_flying = false
	_free_tendril()
	_kill()
	_tween = _player.call(&"effect_tween")
	if _tween != null:
		_tween.tween_method(_scale, Vector2.ONE, PULL_SPRING, PULL_SPRING_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_scale, PULL_SPRING, Vector2.ONE, PULL_SPRING_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_done_ms = elapsed + 2.0 * PULL_SPRING_MS


## `lashPull`: the pile flies to the slime's centre in 220 ms (Quad.In), then it is picked up.
func _pull_pickup(pickup: Variant) -> void:
	var script := pickup as Node
	if script == null or not is_instance_valid(script):
		return
	var root := script.get_parent() as Node2D
	if root == null:
		return
	var to: Vector2 = _player.call(&"get_centre")
	var tween := root.create_tween()
	tween.tween_property(root, "global_position", to, PICKUP_PULL_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var player := _player
	tween.tween_callback(func() -> void:
		if is_instance_valid(script) and is_instance_valid(player):
			script.call(&"request_pickup", player.call(&"get_pickup_area")))


func _make_tendril() -> Sprite2D:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null or not ResourceLoader.exists(TENDRIL_TEXTURE):
		return null
	var sprite := Sprite2D.new()
	sprite.name = "LashTendril"
	sprite.texture = load(TENDRIL_TEXTURE)
	sprite.hframes = 4
	sprite.vframes = 2
	sprite.centered = false
	sprite.offset = Vector2(0.0, -TENDRIL_ORIGIN_Y)
	parent.add_child(sprite)
	# Assigned before placing it: `_place_tendril` places `_tendril` (until 2026-10-05 it ran on null,
	# so every lash but a pull drew its tendril unplaced at the world origin).
	_tendril = sprite
	var caught: Vector2 = _probe.get("at", _from)
	_place_tendril(_from, caught)
	return sprite


func _place_tendril(at: Vector2, caught: Vector2) -> void:
	if _tendril == null or not is_instance_valid(_tendril):
		return
	# Sorted just behind the slime (attachment slot -2): a hair above its feet.
	_tendril.global_position = at
	_tendril.rotation = _direction.angle()
	_tendril.scale = Vector2(maxf(TENDRIL_MIN_LENGTH, at.distance_to(caught)) / TENDRIL_FRAME_WIDTH, 0.5)


func _set_frame(frame: int) -> void:
	if frame < 0:
		_free_tendril()
		return
	if _tendril != null and is_instance_valid(_tendril):
		_tendril.frame = frame


func _free_tendril() -> void:
	if _tendril != null and is_instance_valid(_tendril):
		_tendril.queue_free()
	_tendril = null


func _offset(value: Vector2) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"set_effect_offset", value)


func _scale(value: Vector2) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"set_effect_scale", value)


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

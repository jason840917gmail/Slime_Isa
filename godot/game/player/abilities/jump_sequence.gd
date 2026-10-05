extends RefCounted
## The jump (Phaser `LegacyPlayerAbilityPresentation.ts:131-204`; abilities spec 5.3). The body
## stays at the start (hurtbox, camera, plates) while only the art arcs 54 px over the line to
## the target; at 420 ms the body lands there, with the Land cue, the forced `land` squash and
## goo dust, and a Heavy slime records the landing for cracked ground.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")

const DURATION_MS := 420.0
const ARC_HEIGHT := 54.0
const STRETCH := Vector2(0.82, 1.35)
const SQUASH := Vector2(1.18, 0.70)

var _player: Node
var _intent: Dictionary
var _started_ms: float = 0.0
var _landed: bool = false
var _tween: Tween


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_intent = intent
	_started_ms = now_ms
	var start: Vector2 = intent["start"]
	var target: Vector2 = intent["target"]
	_player.call(&"action_cue", &"Jump")
	_player.call(&"play_animation", "hop")
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	AbilityFx.jump_shadow(start, DURATION_MS / 2.0)
	var mid := (start + target) / 2.0 - Vector2(0.0, ARC_HEIGHT)
	var half := DURATION_MS / 2000.0
	_tween = _player.call(&"effect_tween")
	if _tween == null:
		return
	# Two steps of two parallel tweeners: up to the arc's top, then down to the target.
	_tween.tween_method(_offset, Vector2.ZERO, mid - start, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_scale, Vector2.ONE, STRETCH, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_offset, mid - start, target - start, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_scale, STRETCH, SQUASH, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func advance(now_ms: float) -> bool:
	if not _landed and now_ms - _started_ms >= DURATION_MS:
		_land()
	return _landed


func cancel() -> void:
	_kill()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


func _land() -> void:
	_landed = true
	_kill()
	var target: Vector2 = _intent["target"]
	_player.call(&"teleport", target)
	_player.call(&"reset_effects")
	_player.call(&"action_cue", &"Land")
	_player.call(&"squash", &"land", true)
	_player.call(&"record_landing", target)
	AbilityFx.goo_dust(target)


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

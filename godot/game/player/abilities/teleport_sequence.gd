extends RefCounted
## Teleport (Phaser `LegacyPlayerAbilityPresentation.ts:206-234`; abilities spec 7.3). A blue
## flash at the start, the slime shrinks and fades out over 120 ms, the body jumps to the landing
## (TeleportIn, a green flash there) and the slime pops back over 180 ms; done at 300 ms. No
## i-frames: the hurtbox stays at the start for the first 120 ms.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")

const ARRIVE_MS := 120.0
const DONE_MS := 300.0
const OUT_COLOR := Color("#72d8ff")
const IN_COLOR := Color("#a3f0c0")

var _player: Node
var _intent: Dictionary
var _started_ms: float = 0.0
var _arrived: bool = false
var _tween: Tween


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_intent = intent
	_started_ms = now_ms
	AbilityFx.flash(intent["start"], OUT_COLOR)
	_player.call(&"action_cue", &"TeleportOut")
	_player.call(&"play_animation", "teleport")
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_tween = _player.call(&"effect_tween")
	if _tween == null:
		return
	_tween.tween_method(_alpha, 1.0, 0.0, ARRIVE_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_scale, 1.0, 0.36, ARRIVE_MS / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func advance(now_ms: float) -> bool:
	var elapsed := now_ms - _started_ms
	if not _arrived and elapsed >= ARRIVE_MS:
		_arrive()
	return elapsed >= DONE_MS


func cancel() -> void:
	_kill()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


func _arrive() -> void:
	_arrived = true
	_kill()
	var landing: Vector2 = _intent["target"]
	_player.call(&"teleport", landing)
	_player.call(&"action_cue", &"TeleportIn")
	AbilityFx.flash(landing, IN_COLOR)
	_tween = _player.call(&"effect_tween")
	if _tween == null:
		return
	_tween.tween_method(_alpha, 0.0, 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_scale, 0.36, 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _alpha(value: float) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"set_effect_alpha", value)


func _scale(value: float) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"set_effect_scale", Vector2(value, value))


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

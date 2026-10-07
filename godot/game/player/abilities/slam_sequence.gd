extends RefCounted
## Squash Slam (Phaser `LegacyPlayerAbilityPresentation.ts:236-310`; abilities spec 6). The slime
## winds up (stretches to 1.36 tall over 200 ms, squashes to 0.64 over 120 ms) and at 320 ms
## strikes everything in 90 px around its centre for 30 (knockback 320; not trees or rocks), with
## the ring, the `slam` feel (shake and a 90 ms hit-stop) and the SlamImpact cue; it springs back
## and is done at 470 ms.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")

const IMPACT_MS := 320.0
const DONE_MS := 470.0
const KNOCKBACK := 320.0

var _player: Node
var _intent: Dictionary
var _started_ms: float = 0.0
var _struck: bool = false
var _tween: Tween


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_intent = intent
	_started_ms = now_ms
	_player.call(&"action_cue", &"SlamWindup")
	_player.call(&"play_animation", "squash")
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_tween = _player.call(&"effect_tween")
	if _tween == null:
		return
	_tween.tween_method(_scale_y, 1.0, 1.36, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_scale_y, 1.36, 0.64, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func advance(now_ms: float) -> bool:
	var elapsed := now_ms - _started_ms
	if not _struck and elapsed >= IMPACT_MS:
		_impact()
	return elapsed >= DONE_MS


func cancel() -> void:
	_kill()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


func _impact() -> void:
	_struck = true
	var definition: Dictionary = _intent["definition"]
	var radius := float(definition["radius"])
	var centre: Vector2 = _player.call(&"get_centre")
	AbilityFx.ring(centre, radius)
	var feel := Services.feel()
	if feel != null:
		feel.play(&"slam")
	_player.call(&"action_cue", &"SlamImpact")
	AbilityWorld.strike_area(_player, centre, radius, float(definition["damage"]), KNOCKBACK, ["slam"])
	_kill()
	_tween = _player.call(&"effect_tween")
	if _tween != null:
		_tween.tween_method(_scale_y, 0.64, 1.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _scale_y(value: float) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"set_effect_scale", Vector2(1.0, value))


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

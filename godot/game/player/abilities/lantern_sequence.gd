extends RefCounted
## The Lantern's use (bomb-lantern-and-secrets design section 2; BODY_SHAPES.md "The Lantern"): a
## short sequence run by PlayerAbilities. The slime turns to the aim, its ember flares
## (lantern_glow.gd) and a short spit plays (the `spit-<direction>` clip sped up to
## `abilities.lantern.clipMs`); at `releaseMs` the flame (lantern_flame.gd) leaves the mouth along
## the aim. The sequence ends with the clip (the slime idles). The 10 energy and the cooldown are
## PlayerAbilities' (`abilities.lantern.energy`, `.cooldownMs`).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const LanternFlame := preload("res://game/player/abilities/lantern_flame.gd")
const LanternGlow := preload("res://game/player/abilities/lantern_glow.gd")

## The player clip of a spit (mouth_hold.gd CLIP_SPIT), and its length at speed 1 when the scene
## cannot tell.
const CLIP_SPIT := "spit"
const CLIP_FALLBACK_MS := 300.0
## The mouth: this far ahead of the feet along the aim (px), so the flame leaves the lips.
const MOUTH_PX := 16.0
const CUE_THROW := &"GulpSpit"

var _player: Node
var _direction: Vector2 = Vector2.RIGHT
var _started_ms: float = 0.0
var _release_ms: float = 70.0
var _done_ms: float = 200.0
var _released: bool = false
var _done: bool = false


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_started_ms = now_ms
	var direction: Vector2 = intent.get("direction", Vector2.RIGHT)
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_release_ms = FireTargets.lantern_number("releaseMs", _release_ms)
	_done_ms = maxf(_release_ms, FireTargets.lantern_number("clipMs", _done_ms))
	_player.call(&"face", _direction)
	_player.call(&"stop_movement")
	_play_short_spit()
	var ember := LanternGlow.ensure(_player)
	if ember != null:
		ember.call(&"flare")
	if _release_ms <= 0.0:
		_release()


func advance(now_ms: float) -> bool:
	if _done:
		return true
	var elapsed := now_ms - _started_ms
	if not _released and elapsed >= _release_ms:
		_release()
	if elapsed >= _done_ms:
		_done = true
		return true
	return false


func cancel() -> void:
	_done = true


## The spit clip, sped up so it lasts `clipMs`.
func _play_short_spit() -> void:
	if not bool(_player.call(&"play_animation", CLIP_SPIT, true)):
		return
	var animation := _player.get(&"animation") as AnimationPlayer
	if animation == null or animation.current_animation.is_empty():
		return
	var length_ms := animation.get_animation(animation.current_animation).length * 1000.0
	if length_ms <= 0.0:
		length_ms = CLIP_FALLBACK_MS
	animation.play(animation.current_animation, -1.0, length_ms / maxf(1.0, _done_ms))


func _release() -> void:
	_released = true
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	var body := _player.get(&"body") as Node2D
	if parent == null or body == null:
		return
	var flame := LanternFlame.new()
	flame.name = "LanternFlame"
	parent.add_child(flame)
	flame.launch(_player, body.global_position + _direction * MOUTH_PX, _direction)
	_player.call(&"action_cue", CUE_THROW)

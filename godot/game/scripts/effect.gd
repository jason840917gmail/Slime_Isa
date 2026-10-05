extends Node
class_name EffectScript
## Scene script `game.effect` (Phaser `features/scripts/EffectScript.ts`). Combat spec 9.1.
## One-shot visual effects (sword impact, ...). Lifetime runs on SimClock (frozen by hit-stop).
## The effect's own AudioStreamPlayer2D autoplays and is detached by sfx_player_2d, so it
## survives the free.
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")

## JSON `effectId` ("basic-sword-impact").
@export var effect_id: String = ""
## JSON `animation`: AnimationPlayer with directional clips (right/left/up/down).
@export var animation: AnimationPlayer
## JSON `lifetimeMs` (1000).
@export var lifetime_ms: float = 0.0

## Emitted when the lifetime ends, just before the root is freed. Payload {"effectId": String}.
signal finished(payload: Dictionary)

var _age_ms: float = 0.0
var _playing: bool = false
## SimClock time of the last `play()`; the age is `now - _started_at` (one gameplay clock).
var _started_at: float = 0.0


## Phaser `_enter_tree`: play "right" (the spawner then calls play(direction)).
func _ready() -> void:
	play("right")


## Phaser `_exit_tree`: stop ageing.
func _exit_tree() -> void:
	_playing = false


## True between play() and finish().
func is_playing() -> bool:
	return _playing


## Plays clip `variant` when present, age = 0, playing.
## Like Phaser's `AnimationPlayerNode.play` (clock.start dispatches frame 0 at once), the clip's
## first frame is applied immediately through the converter runtime's `play_clip` (stop, play,
## seek(0, true)), so e.g. a "left" impact spawned inside a hit step shows flipped through the
## hit-stop freeze instead of on the first step after it.
func play(variant: String) -> void:
	if animation != null and is_instance_valid(animation) and animation.has_animation(variant):
		var clip := StringName(variant)
		if animation.has_method(&"play_clip"):
			animation.call(&"play_clip", clip)
		else:
			animation.play(clip)
			animation.seek(0.0, true)
	_started_at = Services.now_ms()
	_age_ms = 0.0
	_playing = true


## Age += delta ms while playing; `finish()` at lifetime_ms.
func _physics_process(_delta: float) -> void:
	if not _playing:
		return
	_age_ms = Services.now_ms() - _started_at
	if _age_ms >= maxf(0.0, lifetime_ms):
		finish()


## Emit finished, free the effect root (the script's owner scene root; its holder, if any,
## frees itself).
func finish() -> void:
	if not _playing:
		return
	_playing = false
	finished.emit({"effectId": effect_id})
	var root := get_parent()
	if root != null:
		root.queue_free()
	else:
		queue_free()

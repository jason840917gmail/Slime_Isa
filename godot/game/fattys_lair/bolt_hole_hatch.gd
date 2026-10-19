extends Node2D
## The Lair's bolt-hole mouth in D4 (`object.fatty-lair-bolt-hole-mouth`, docs/godot/DUNGEONS.md
## "Outside: Fatty's Hollow and the bolt-hole"): a one-way way out. The hatch lies shut (frame 0);
## when the slime climbs out through it (its DoorScript's `arrived`), it shows open, and once the slime
## has walked `dungeon.boltHole.clearPx` away (or after `dungeon.boltHole.closeAfterMs` at most) it
## slams shut behind it with a thud and dust, so the Lair cannot be entered that way (owner,
## 2026-10-18). The door has no target, so nothing leads back down either way.
##
## Owner: Fatty's Lair.

const Services := preload("res://game/shared/services.gd")

const FRAME_SHUT := 0
const FRAME_OPEN := 1
const CUE_SHUT := &"BreakWood"
const CUE_THUD := &"DoorUse"
const DUST := &"dodge-dust"

@export var visual: Sprite2D
@export var door: Node

var _open_since_ms: float = -1.0


func _ready() -> void:
	_show(false)
	if door != null and door.has_signal(&"arrived"):
		door.connect(&"arrived", _on_arrived)


func _on_arrived() -> void:
	_show(true)
	_open_since_ms = Services.now_ms()


func _physics_process(_delta: float) -> void:
	if _open_since_ms < 0.0:
		return
	var waited := Services.now_ms() - _open_since_ms
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var away := true
	if player != null and player.has_method(&"get_centre"):
		var centre: Vector2 = player.call(&"get_centre")
		away = centre.distance_to(global_position) >= _number("clearPx")
	if (away and waited >= _number("minOpenMs")) or waited >= _number("closeAfterMs"):
		_slam()


func _slam() -> void:
	_open_since_ms = -1.0
	_show(false)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_THUD)
		feel.audio_cue(CUE_SHUT)
		feel.particles(DUST, global_position + Vector2(0.0, -24.0))
		feel.shake(_number("shakeMs"), _number("shakeIntensity"))


func _show(open: bool) -> void:
	if visual != null:
		visual.frame = FRAME_OPEN if open else FRAME_SHUT


func _number(key: String) -> float:
	var constants := Services.constants()
	return constants.number("dungeon.boltHole." + key) if constants != null else 0.0

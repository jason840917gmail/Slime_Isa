@tool
extends Node2D
class_name EnergyFlower
## An energy flower that grows back (docs/godot/DUNGEONS.md "Refills that grow back";
## `object.energy-flower`): a glowing honey-gold bloom in a room with an energy puzzle, and in the
## calm room before a boss door. The slime walks into it while its energy is not full: it drinks
## `dungeon.refill.flowerEnergy` energy, the flower closes into a bud, and it opens again
## `dungeon.refill.flowerRegrowMs` of play later. Not saved (a world built again has it in bloom).
##
## Its look is the pickups sheet's flower and bud (`look`, 2 x 2 frames: 0 the bloom, 1 the bud).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const FRAME_BLOOM := 0
const FRAME_BUD := 1
const CUE := &"EnergyRestore"
const TEXT_RISE := 44.0
const SPARKLE := &"loot-sparkle"

## Drunk. Payload: {"energy": gained}.
signal drunk(payload: Dictionary)
## In bloom again. Payload: {}.
signal regrown(payload: Dictionary)

## The flower's picture.
@export var look: Sprite2D

var _bloom := true
var _regrow_at_ms := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_show()


func is_in_bloom() -> bool:
	return _bloom


func _physics_process(_delta: float) -> void:
	var now := Services.now_ms()
	if not _bloom:
		if now >= _regrow_at_ms:
			_bloom = true
			_show()
			regrown.emit({})
		return
	var world := Services.world()
	if world == null or world.player == null or world.player_body == null or not is_instance_valid(world.player):
		return
	var player: Node = world.player
	if bool(player.call(&"is_dead")):
		return
	if world.player_body.global_position.distance_to(global_position) > DungeonState.number("refill.flowerReachPx", 30.0):
		return
	if float(player.call(&"get_energy")) >= float(player.call(&"get_max_energy")):
		return
	var gained := float(player.call(&"restore_energy", DungeonState.number("refill.flowerEnergy", 25.0)))
	_bloom = false
	_regrow_at_ms = now + DungeonState.number("refill.flowerRegrowMs", 20000.0)
	_show()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE)
		feel.particles(SPARKLE, global_position - Vector2(0.0, 20.0))
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), "+%d" % roundi(gained), &"cyan", false)
	drunk.emit({"energy": gained})


func _show() -> void:
	if look != null and look.hframes * look.vframes > FRAME_BUD:
		look.frame = FRAME_BLOOM if _bloom else FRAME_BUD

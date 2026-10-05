extends Node
class_name AbilityLessonScript
## Scene script `game.ability-lesson` (Phaser `features/scripts/AbilityLessonScript.ts`;
## abilities spec 13.5). Teaches its abilities once the living player's centre comes within
## `radius` (test areas; the story teaches through quest rewards). Only new ids are learned
## (AbilityLearned cue each) and reported in `taught`.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const CUE_LEARNED := &"AbilityLearned"

## JSON `abilityIds`.
@export var ability_ids: Array = []
## JSON `radius`.
@export var radius: float = 96.0

## New abilities were taught. Payload: {"abilityIds": Array}.
signal taught(payload: Dictionary)

var _done: bool = false


func _ready() -> void:
	if not (is_finite(radius) and radius > 0.0):
		radius = 96.0


func _physics_process(_delta: float) -> void:
	if _done or ability_ids.is_empty():
		return
	var world := Services.world()
	var player = world.player if world != null else null
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		return
	var root := get_parent() as Node2D
	if root == null or (player.call(&"get_centre") as Vector2).distance_to(root.global_position) > radius:
		return
	_done = true
	var run := Services.run()
	if run == null:
		return
	var fresh: Array = []
	for id: Variant in ability_ids:
		if id is String and not (id as String).is_empty() and run.learn_ability(id):
			fresh.append(id)
	if fresh.is_empty():
		return
	var feel := Services.feel()
	if feel != null:
		for _id in fresh:
			feel.audio_cue(CUE_LEARNED)
	taught.emit({"abilityIds": fresh})

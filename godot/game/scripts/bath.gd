extends Node
class_name BathScript
## Scene script `game.bath`: a bath the slime can soak in (owner, 2026-11-12; the bed's pattern,
## bed.gd). A data holder: the interaction controller offers "Bathe" and puts the player in the
## bath with `bath_request()` (game/rest/bath_controller.gd): the body waits at the way-out point in
## front of the tub while the art sits in the water at the soak point, behind the tub's `front`
## layer; soaking heals. Any tub can be a bath: a scene with this script as a child of its root
## (game/scenes/objects/bath-tub.tscn is the wooden tub).
##
## Owner: interaction.

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const GROUP := &"bath"

@export var prompt: String = "Bathe"
@export var interact_radius: float = 90.0
@export var badge_rise: float = 70.0
## Local to the bath's root: where the slime's feet are while it soaks (in the water).
@export var soak_point: Vector2 = Vector2(0.0, -40.0)
## Local to the bath's root: where the body waits during the bath and stands after it.
@export var out_point: Vector2 = Vector2(0.0, 28.0)
## The tub's front layer (its near wall and the water in front of the bather): raised over the
## slime's art for the soak. Empty: nothing covers the slime.
@export var front: CanvasItem


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if prompt.is_empty():
		prompt = "Bathe"
	if not (is_finite(interact_radius) and interact_radius > 0.0):
		interact_radius = 90.0
	if not is_finite(badge_rise):
		badge_rise = 70.0


## Old Phaser position of the bath (its parent), as a bed's.
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## {"bath_id", "soak_point", "out_point", "front"} with the points in old Phaser world coordinates.
func bath_request() -> Dictionary:
	var at := origin()
	return {"bath_id": str(get_path()), "soak_point": at + soak_point, "out_point": at + out_point, "front": front}

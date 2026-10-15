extends Node2D
## The playground's Bomb corner (bomb-lantern-and-secrets design section 4; BODY_SHAPES.md "Goo
## Bomb": the corner's layout). Instanced once into game/scenes/worlds/playground.tscn at the world's
## origin, so its children stand at world positions on the west edge, around the lake cliff's west
## end: a cracked wall in the cliff whose hole, once blown, is a north door to a small cave with a
## chest (the world `playground-bomb-cave`: you arrive at its south door, and walking back out of it
## brings you out in front of the hole, facing down; door.gd pairing rule), a rubble heap choking the path
## between the cliff and the map's edge, a rubble heap on the lake's islet (only a thrown bomb gets
## there; it hides a chest that slides into the shallows), a second cracked wall in the root-rock
## plateau south of the lake (a plain opening with a nook and a chest in it), and two light training
## dummies on the shore.
##
## It is a rework-mode testbed: with the mode off (the classic game, the test runner's playground)
## it takes itself out, so nothing of it is in the classic world.
##
## Owner: abilities.

const ReworkMode := preload("res://game/shapes/rework_mode.gd")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not ReworkMode.is_on():
		queue_free()

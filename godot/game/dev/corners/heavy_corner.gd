extends Node2D
## The playground's Heavy corner (bomb-lantern-and-secrets design section 4; BODY_SHAPES.md "Heavy
## plates and heavy blocks": the corner's layout). Instanced once into
## game/scenes/worlds/playground.tscn at the world's origin, so its children stand at world positions
## on the east edge, south of the Lantern corner (x 2496..3328, y 2816..3712): two walled vaults with
## a gate each in their south wall. Vault A's heavy plate lies far south of its gate, so the Stone
## slime must run through while the plate rises (a second heavy plate inside lets it out again);
## vault B's plate sits in front of its gate and stays down only with a pushed pedestal on it. A spare
## statue stands to push and pull, and two stone essences lie by the way in.
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

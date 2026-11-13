extends Node2D
## The playground's Skins corner (docs/godot/SKINS.md "The Skins corner"; roadmap 7.8). Instanced
## once into game/scenes/worlds/playground.tscn at the world's origin, so its children stand at
## world positions east of the Bestiary corner (x 6656 to 7936, the columns the playground grew by
## for it; `?map=playground&spawn=6800,1240`). Three lanes, each with a skin pedestal
## (skin_pedestal.gd: lends the skin for the session, or gives it back) and that skin's locks:
## - **Heavy** (north): a heavy plate, a heavy statue to push, and the Heavy Roll's breakables (a plank
##   barricade, a loose rock, a rubble heap, an old fence, an old trunk, rotten timbers) and a coin
##   pouch caught in a tree that a Heavy Roll's bonk shakes loose.
## - **Silk** (middle): floor webs (a walk is halved and a Roll sticks without the skin), a web wall
##   between stone walls (the Spear cuts it with the skin; it hides a silk parcel), a silk parcel.
## - **Feral** (south): a level-2 plateau with vines painted on its face (the playground's own
##   `vines` VineLayer, beside its `elevation` layer, game/world/vines/vine_layer.gd: clung to and
##   crossed any way, from its foot or its lip), and a
##   training dummy to feel the Spear strike twice as fast.
## None of the breakables keeps a flag: building the world again brings them back.
##
## It is a rework-mode testbed: with the mode off (the classic game, the test runner's playground)
## it takes itself out, so nothing of it is in the classic world.
##
## Owner: skins.

const ReworkMode := preload("res://game/shapes/rework_mode.gd")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not ReworkMode.is_on():
		queue_free()

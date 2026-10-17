extends Sprite2D
## The skull on a beaten skeleton's bone pile (the bestiary's rows 30 to 32; docs/godot/BESTIARY.md
## "The bone pile"; game/enemy/skeleton_enemy.gd). While it lies on the pile (`show_on_pile(true)`)
## it is in the mouth's `suckable` group (game/player/gulp/mouth.gd), so the Gulp (Q) takes it as a
## pot (a pile is not a live enemy, so this is the only part of a skeleton the mouth ever pulls).
## Taken, the mouth holds {"kind": KIND, "texture": its own picture, "art_px", "material"}
## (held_look.gd) and `taken` tells the skeleton, which can then never stand up; thrown
## (thrown_object.gd), its hit carries the tags `thrown` and KIND and hits as a pot does.
##
## Owner: enemy builder.

const SUCKABLE_GROUP := &"suckable"
## The held kind and the tag its throw carries.
const KIND := "skull"
const MATERIAL := "bone"
## The skull's drawn size in its 64 px picture (scripts/characters/pack-bestiary-enemies.py).
const ART_PX := 60.0

## Emitted once when the Gulp takes it.
signal taken

## The picture (`res://asset/MAPS/enemies/64x64-skull.webp`, the Bone Marcher's helmeted one).
var picture_path: String = ""
var _on_pile: bool = false


## On the pile (shown, takeable) or not (hidden: the skeleton stands, or the skull is gone).
func show_on_pile(on: bool) -> void:
	_on_pile = on
	visible = on
	if on and not is_in_group(SUCKABLE_GROUP):
		add_to_group(SUCKABLE_GROUP)
	elif not on and is_in_group(SUCKABLE_GROUP):
		remove_from_group(SUCKABLE_GROUP)


func is_on_pile() -> bool:
	return _on_pile


# --- the mouth's suckable contract (game/player/gulp/mouth.gd) -------------------------------------

## The ground point under it (the pile's feet).
func origin() -> Vector2:
	var feet := get_parent() as Node2D
	return feet.global_position if feet != null else global_position


func can_take() -> bool:
	return _on_pile and is_inside_tree() and not is_queued_for_deletion()


func suck_info() -> Dictionary:
	return {"kind": KIND, "essence": "", "variant": 0, "texture": picture_path, "art_px": ART_PX,
		"material": MATERIAL}


## Sucked in: it leaves the pile.
func take() -> void:
	if not _on_pile:
		return
	show_on_pile(false)
	taken.emit()

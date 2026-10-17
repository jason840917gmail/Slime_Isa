extends "res://game/scripts/projectile.gd"
class_name SporeSeedScript
## Scene script `game.spore-seed` (docs/godot/BESTIARY.md "Spitcap"): the Spitcap's spore seed, an
## enemy projectile (game/scripts/projectile.gd: it flies straight, hits the slime's hurtbox once,
## stops at walls) that the Gulp can catch. While it flies it is in the mouth's `suckable` group
## (game/player/gulp/mouth.gd): sucked in, it leaves the world without a hit and the mouth holds
## {"kind": KIND, "texture", "art_px", "material"} (its own picture, held_look.gd); thrown back
## (thrown_object.gd) its hit carries the tag KIND, which kills a Spitcap at once
## (spitcap.gd `_kill_hit`) and hits anything else as a soft thrown thing.
##
## Owner: enemy builder.

const SUCKABLE_GROUP := &"suckable"
## The held kind and the tag its throw carries.
const KIND := "spore-seed"
const MATERIAL := "soft"
const SEED_TEXTURE := "res://asset/MAPS/enemies/64x64-spore-seed.webp"
## The seed's drawn size in its 64 px picture.
const SEED_ART_PX := 56.0
## Presentation: it spins as it flies.
const SPIN_PER_S := 7.0


func _enter_tree() -> void:
	add_to_group(SUCKABLE_GROUP)


func _physics_process(delta: float) -> void:
	super(delta)
	if is_launched() and visual != null:
		visual.rotation += SPIN_PER_S * delta


# --- the mouth's suckable contract (game/player/gulp/mouth.gd) -----------------------------------

func origin() -> Vector2:
	var root := get_parent() as Node2D
	return root.global_position if root != null else Vector2.ZERO


func can_take() -> bool:
	var root := get_parent()
	return is_launched() and root != null and not root.is_queued_for_deletion()


func suck_info() -> Dictionary:
	return {"kind": KIND, "essence": "", "variant": 0, "texture": SEED_TEXTURE, "art_px": SEED_ART_PX,
		"material": MATERIAL}


## Sucked in: it leaves the world without hitting anything (no `expired` thunk).
func take() -> void:
	if not is_launched():
		return
	_launched = false
	_end_activation()
	var root := get_parent()
	if root is CollisionObject2D:
		(root as CollisionObject2D).set_deferred(&"collision_layer", 0)
	if root != null:
		root.queue_free()

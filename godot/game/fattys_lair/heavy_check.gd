extends RefCounted
## Is the slime heavy? (Fatty's Lair: the plank barricade's lock; docs/godot/DUNGEONS.md "Fatty's
## Lair (built)".) The Heavy skin, Pearl 1's, is not built as a skin yet (roadmap 7.8). Until it is,
## the slime counts as heavy in the Stone form (GulpForms.HEAVY, the rework's Heavy check, which the
## Roll already uses for its `heavy` bonk tag) or once Pearl 1 granted the skin: the story flag
## SKIN_FLAG, set by game/scripts/pearl.gd. When 7.8 builds the skin, this file is where the
## barricade asks, and the flag is the record the skin reads.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")

## Set by Pearl 1 (game/scripts/pearl.gd `skin_flag`).
const SKIN_FLAG := "skin.heavy"
const ROLL_TAG := "roll"
const HEAVY_TAG := "heavy"


## True once Pearl 1 granted the Heavy skin.
static func has_skin() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(SKIN_FLAG)


## True while `player` (player.gd) is heavy: the Stone form, or the Heavy skin learned.
static func is_heavy(player: Node) -> bool:
	if has_skin():
		return true
	if player == null or not is_instance_valid(player) or not player.has_method(&"current_form_id"):
		return false
	return StringName(player.call(&"current_form_id")) == GulpForms.HEAVY


## True when `request` (a DamageRouter request) is a Heavy Roll's bonk: the Roll's hit (tag `roll`)
## carrying `heavy` (the Stone form), or any Roll's once the Heavy skin is learned.
static func is_heavy_roll(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	if not tags is Array or not (tags as Array).has(ROLL_TAG):
		return false
	return (tags as Array).has(HEAVY_TAG) or has_skin()

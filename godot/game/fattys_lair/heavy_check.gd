extends RefCounted
## Is the slime heavy? The Heavy skin's checks (docs/godot/SKINS.md "Heavy"): Pearl 1's skin, won in
## Fatty's Lair, always on once won (SkinState). The Heavy Roll's breakables ask here (the plank
## barricade, the rotten timbers, rubble heaps, loose rocks, old trunks and fences:
## game/scripts/plank_barricade.gd), as do the heavy plates and blocks through player.gd
## `presses_plates`.
##
## Owner: skins.

const SkinState := preload("res://game/player/skins/skin_state.gd")

const ROLL_TAG := "roll"
## The Roll's bonk carries it while the Heavy skin is on (game/player/roll/player_roll.gd).
const HEAVY_TAG := "heavy"


## True once the Heavy skin is on (won, or lent for the session).
static func has_skin() -> bool:
	return SkinState.is_on(null, SkinState.HEAVY)


## True while `player` (player.gd) is heavy: the Heavy skin is on.
static func is_heavy(player: Node) -> bool:
	return SkinState.is_on(player, SkinState.HEAVY)


## True when `request` (a DamageRouter request) is a Heavy Roll's bonk: the Roll's hit (tag `roll`)
## made with the Heavy skin on (it carries `heavy`).
static func is_heavy_roll(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	if not tags is Array or not (tags as Array).has(ROLL_TAG):
		return false
	return (tags as Array).has(HEAVY_TAG) or has_skin()

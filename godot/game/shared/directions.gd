extends RefCounted
class_name Directions
## 4-way direction helpers shared by the player, the weapon and the combat controller.
##
## Owner: world builder. Architect wrote it complete (exact Phaser rules).

## Cardinal names used by weapon attack plans and impact-effect clips.
const RIGHT := "right"
const LEFT := "left"
const UP := "up"
const DOWN := "down"


## `PointerAim.ts:29-32` snapToCardinal: `|x| >= |y|` -> `(sign x, 0)` with x == 0 -> +1,
## else `(0, sign y)`. Ties go sideways.
static func snap_to_cardinal(direction: Vector2) -> Vector2:
	if absf(direction.x) >= absf(direction.y):
		return Vector2(-1.0 if direction.x < 0.0 else 1.0, 0.0)
	return Vector2(0.0, -1.0 if direction.y < 0.0 else 1.0)


## `CombatController.ts:63-66`: facing (zero -> (1,0)) to "left|right|up|down";
## `|x| >= |y|` -> x < 0 ? left : right, else y < 0 ? up : down.
static func cardinal_name(direction: Vector2) -> String:
	var d := direction if direction != Vector2.ZERO else Vector2.RIGHT
	if absf(d.x) >= absf(d.y):
		return LEFT if d.x < 0.0 else RIGHT
	return UP if d.y < 0.0 else DOWN


## `WeaponScript.ts:396-401` attackVector: right (1,0), left (-1,0), up (0,-1), down (0,1);
## unknown names -> Vector2.ZERO.
static func cardinal_vector(direction_name: String) -> Vector2:
	match direction_name:
		RIGHT:
			return Vector2.RIGHT
		LEFT:
			return Vector2.LEFT
		UP:
			return Vector2.UP
		DOWN:
			return Vector2.DOWN
	return Vector2.ZERO


## Slime flip rule (player spec 4.4): `flip_h = |x| >= |y| and x > 0` (the slime art faces left).
static func slime_flip_h(direction: Vector2) -> bool:
	return absf(direction.x) >= absf(direction.y) and direction.x > 0.0

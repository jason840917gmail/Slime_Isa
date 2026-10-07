extends RefCounted
class_name PointerAim
## Pointer aim for attack facing and dodge direction (Phaser `features/player/PointerAim.ts`,
## `WorldScene.pointerAim`). Player spec 9.1, combat spec 4.1.
##
## Owner: player builder.

## POINTER_DEAD_ZONE_PX (PointerAim.ts:2).
const DEAD_ZONE_PX := 16.0


## Unit vector from `origin` to `pointer_world`, or Vector2.ZERO when the pointer was never seen
## over the game or is within DEAD_ZONE_PX of the origin (Phaser returns undefined there).
static func aim(origin: Vector2, pointer_world: Vector2, pointer_seen: bool) -> Vector2:
	if not pointer_seen:
		return Vector2.ZERO
	var delta := pointer_world - origin
	if delta.length() < DEAD_ZONE_PX:
		return Vector2.ZERO
	return delta.normalized()

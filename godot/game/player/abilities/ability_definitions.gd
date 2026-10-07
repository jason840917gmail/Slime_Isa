extends RefCounted
## The player's ability table (Phaser `features/player/PlayerAbilityDefinitions.ts:39-60`, literals
## there too; abilities spec 1). The dodge's cooldown comes from game constants at run time
## (`dodgeDurationMs + dodgeCooldownMs` = 750).
##
## Owner: abilities.

const JUMP := &"jump"
const DODGE := &"dodge"
const TELEPORT := &"teleport"
const SQUASH_SLAM := &"squash-slam"
const STRETCH_LASH := &"stretch-lash"
const GOO_TRAIL := &"goo-trail"

## Dispatch order inside one step (WorldScene.handleActionInput :1810).
const DISPATCH_ORDER: Array[StringName] = [JUMP, DODGE, STRETCH_LASH, SQUASH_SLAM, TELEPORT]

## id -> {title, action (input action), earned_by, cooldown_ms, energy_cost, distance, duration_ms,
## radius, damage}. The dodge's cooldown_ms is filled from constants (`cooldown_ms()`).
const TABLE := {
	JUMP: {"title": "Jump", "action": &"jump", "earned_by": "Quest", "cooldown_ms": 700.0,
		"energy_cost": 0.0, "distance": 168.0, "duration_ms": 420.0},
	DODGE: {"title": "Dodge", "action": &"dodge", "earned_by": "Quest", "cooldown_ms": -1.0,
		"energy_cost": 0.0, "duration_ms": 500.0},
	TELEPORT: {"title": "Teleport", "action": &"teleport", "earned_by": "Later", "cooldown_ms": 1800.0,
		"energy_cost": 35.0, "distance": 240.0},
	SQUASH_SLAM: {"title": "Squash Slam", "action": &"squash_slam", "earned_by": "Boss", "cooldown_ms": 2500.0,
		"energy_cost": 30.0, "radius": 90.0, "damage": 30.0},
	STRETCH_LASH: {"title": "Stretch Lash", "action": &"stretch_lash", "earned_by": "Quest", "cooldown_ms": 2000.0,
		"energy_cost": 20.0, "distance": 180.0},
}

## Short names on the ability bar (AbilityBarSurfacePort.ts:8-14).
const BAR_NAMES := {JUMP: "Jump", DODGE: "Dodge", STRETCH_LASH: "Lash", SQUASH_SLAM: "Slam", TELEPORT: "Teleport"}

## Rejection feedback (LegacyPlayerAbilityPresentation.ts:119-129): reason -> [text, colour].
const REJECTION_TEXT := {
	"locked": ["Not learned yet", &"red"],
	"energy": ["Low energy", &"orange"],
	"blocked": ["No safe spot there", &"orange"],
}


static func has(id: StringName) -> bool:
	return TABLE.has(id)


static func entry(id: StringName) -> Dictionary:
	return TABLE.get(id, {})


static func title(id: StringName) -> String:
	return str(entry(id).get("title", String(id)))


static func action(id: StringName) -> StringName:
	return entry(id).get("action", StringName())


static func energy_cost(id: StringName) -> float:
	return float(entry(id).get("energy_cost", 0.0))


## Cooldown from the press; the dodge's is roll duration + post-roll cooldown (game constants).
static func cooldown_ms(id: StringName, constants: Node) -> float:
	if id == DODGE:
		if constants == null:
			return 0.0
		return float(constants.call(&"number", "character.player.movement.dodgeDurationMs")) \
			+ float(constants.call(&"number", "character.player.movement.dodgeCooldownMs"))
	return float(entry(id).get("cooldown_ms", 0.0))

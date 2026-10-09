extends RefCounted
## The player's ability table (Phaser `features/player/PlayerAbilityDefinitions.ts:39-60`, literals
## there too; abilities spec 1). The dodge's cooldown comes from game constants at run time
## (`rollSpinUpMs + rollMinMs + rollCooldownMs` = 960).
##
## The dodge is the Roll (owner, 2026-10-09; roadmap 7.7, game/player/roll/player_roll.gd): it
## keeps the id `dodge` and the `dodge` action, so saves and quests stay valid, and shows as "Roll".
##
## The jump is hidden (owner, 2026-10-08): its logic stays (tests run it, and ledge drops use its
## flight), but no key is bound to `jump`, nothing in the story teaches it and no HUD slot shows it.
##
## Owner: abilities.

const JUMP := &"jump"
const DODGE := &"dodge"
const TELEPORT := &"teleport"
const SQUASH_SLAM := &"squash-slam"
const STRETCH_LASH := &"stretch-lash"
const GOO_TRAIL := &"goo-trail"
## Swallow (owner, 2026-10-08): what the mouth holds becomes the slime's form (player.gd
## `_swallow`, game/player/gulp/). An instant ability on the shared rules; no cost, no cooldown.
const SWALLOW := &"swallow"

## Dispatch order inside one step (WorldScene.handleActionInput :1810).
const DISPATCH_ORDER: Array[StringName] = [JUMP, DODGE, STRETCH_LASH, SQUASH_SLAM, TELEPORT]

## id -> {title, action (input action), earned_by, cooldown_ms, energy_cost, distance, duration_ms,
## radius, damage}. The dodge's cooldown_ms is filled from constants (`cooldown_ms()`).
const TABLE := {
	JUMP: {"title": "Jump", "action": &"jump", "earned_by": "Quest", "cooldown_ms": 700.0,
		"energy_cost": 0.0, "distance": 168.0, "duration_ms": 420.0},
	DODGE: {"title": "Roll", "action": &"dodge", "earned_by": "Quest", "cooldown_ms": -1.0,
		"energy_cost": 0.0},
	TELEPORT: {"title": "Teleport", "action": &"teleport", "earned_by": "Later", "cooldown_ms": 1800.0,
		"energy_cost": 35.0, "distance": 240.0},
	SQUASH_SLAM: {"title": "Squash Slam", "action": &"squash_slam", "earned_by": "Boss", "cooldown_ms": 2500.0,
		"energy_cost": 30.0, "radius": 90.0, "damage": 30.0},
	STRETCH_LASH: {"title": "Stretch Lash", "action": &"stretch_lash", "earned_by": "Quest", "cooldown_ms": 2000.0,
		"energy_cost": 20.0, "distance": 180.0},
	SWALLOW: {"title": "Swallow", "action": &"swallow", "earned_by": "Quest", "cooldown_ms": 0.0,
		"energy_cost": 0.0},
}

## The abilities the HUD shows, in slot order, which is key order (the jump is hidden; owner,
## 2026-10-09: "1 first, 2 after").
const BAR_SLOTS: Array[StringName] = [SWALLOW, DODGE, STRETCH_LASH, SQUASH_SLAM, TELEPORT]

## Short names on the ability bar (AbilityBarSurfacePort.ts:8-14).
const BAR_NAMES := {JUMP: "Jump", DODGE: "Roll", STRETCH_LASH: "Lash", SQUASH_SLAM: "Slam", TELEPORT: "Teleport",
	SWALLOW: "Swallow"}

## The ability ceremony's card (owner, 2026-10-09; game/ui/ceremony/ability_ceremony.gd): one line of
## what the ability does and how to use it, "%s" being the key label from the binding table (content
## text never names a key).
const CEREMONY := {
	JUMP: ["Hop over gaps and up onto low ledges.", "Press %s"],
	DODGE: ["Curl into a ball, spin up and dash straight ahead. Walls go bonk!", "Press %s, and hold it to keep rolling"],
	STRETCH_LASH: ["Stretch out a strand of goo: light things come to you, heavy things pull you to them.",
		"Press %s toward what you want to catch"],
	SQUASH_SLAM: ["Spring up and slam down, knocking back everything around you.", "Press %s"],
	TELEPORT: ["Blink ahead to the farthest safe spot.", "Press %s"],
	SWALLOW: ["Swallow the essence in your mouth and become what it was made of.", "Suck an essence in, then press %s"],
}
## The ability icons the ceremony shows (the HUD console's, by the HUD session).
const ICON_PATH := "res://asset/UI/hud-console/ability-%s.webp"

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


## The ceremony card's line about `id` ("" when it has none).
static func ceremony_line(id: StringName) -> String:
	return str((CEREMONY.get(id, ["", ""]) as Array)[0])


## The ceremony card's how-to for `id` with its key label in place of "%s".
static func ceremony_how(id: StringName, key_label: String) -> String:
	var how := str((CEREMONY.get(id, ["", ""]) as Array)[1])
	return how % key_label if how.contains("%s") else how


## The ability's icon (the HUD console's), or null.
static func icon(id: StringName) -> Texture2D:
	var path := ICON_PATH % String(id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func action(id: StringName) -> StringName:
	return entry(id).get("action", StringName())


static func energy_cost(id: StringName) -> float:
	return float(entry(id).get("energy_cost", 0.0))


## Cooldown from the press; the Roll's is its spin-up, its shortest roll and the pause after it
## (game constants; a longer roll waits its own `rollCooldownMs` after it ends, player_roll.gd).
static func cooldown_ms(id: StringName, constants: Node) -> float:
	if id == DODGE:
		if constants == null:
			return 0.0
		var movement := "character.player.movement."
		return float(constants.call(&"number", movement + "rollSpinUpMs")) \
			+ float(constants.call(&"number", movement + "rollMinMs")) \
			+ float(constants.call(&"number", movement + "rollCooldownMs"))
	return float(entry(id).get("cooldown_ms", 0.0))

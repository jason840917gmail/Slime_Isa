extends RefCounted
## The player's ability table (Phaser `features/player/PlayerAbilityDefinitions.ts:39-60`, literals
## there too; abilities spec 1). The dodge's cooldown comes from game constants at run time
## (`rollSpinUpMs + rollMinMs + rollCooldownMs` = 960; in the body-shapes rework mode the quick
## roll's `quickRollMs + rollCooldownMs` = 580).
##
## The dodge is the Roll (owner, 2026-10-09; roadmap 7.7, game/player/roll/player_roll.gd): it
## keeps the id `dodge` and the `dodge` action, so saves and quests stay valid, and shows as "Roll".
##
## The jump is hidden (owner, 2026-10-08): its logic stays (tests run it, and ledge drops use its
## flight), but no key is bound to `jump`, nothing in the story teaches it and no HUD slot shows it.
##
## Squash Slam: the classic game keeps the old Slam (classic_slam_sequence.gd, this table's cost,
## cooldown, radius and damage). In the body-shapes rework mode (docs/godot/BODY_SHAPES.md) the
## improved Slam of the body-shapes plan (section 4) runs instead (slam_sequence.gd): its energy cost
## and cooldown then come from game constants (`abilities.squashSlam.energy`, `.cooldownMs`), and its
## numbers from the same block.
##
## The Ability Box (body-shapes plan section 6; game/player/abilities/ability_box.gd) reads its
## socket order here (`box_sockets`, from `abilityBox.sockets`); the classic BAR_SLOTS stay as they are.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")

const JUMP := &"jump"
const DODGE := &"dodge"
const TELEPORT := &"teleport"
const SQUASH_SLAM := &"squash-slam"
const STRETCH_LASH := &"stretch-lash"
const GOO_TRAIL := &"goo-trail"
## Swallow (owner, 2026-10-08): what the mouth holds becomes the slime's form (player.gd
## `_swallow`, game/player/gulp/). An instant ability on the shared rules; no cost, no cooldown.
const SWALLOW := &"swallow"
## The Lantern (bomb-lantern-and-secrets design section 2; BODY_SHAPES.md "The Lantern"): a box
## ability (rework mode). A use throws a small flame (lantern_sequence.gd); learned, the slime glows
## in dark rooms (lantern_glow.gd). Its numbers are `abilities.lantern`.
const LANTERN := &"lantern"
## The Goo Bomb (bomb-lantern-and-secrets design section 1; BODY_SHAPES.md "Goo Bomb"): a box ability
## (rework mode). A use casts a bomb inside the slime (2 s, standing still) and spits it out
## (goo_bomb_sequence.gd); the energy is checked at the press and spent at the spit. Its numbers are
## `abilities.gooBomb`.
const GOO_BOMBS := &"goo-bombs"

## Dispatch order inside one step (WorldScene.handleActionInput :1810).
const DISPATCH_ORDER: Array[StringName] = [JUMP, DODGE, STRETCH_LASH, SQUASH_SLAM, TELEPORT]

## The improved Slam's block in game-constants.json (`energy`, `cooldownMs`, its timeline and hits).
const SLAM_CONSTANTS := "abilities.squashSlam"
## The Lantern's block in game-constants.json (`energy`, `cooldownMs`, the flame, the glow, dark rooms).
const LANTERN_CONSTANTS := "abilities.lantern"
## The Goo Bomb's block in game-constants.json (`energy`, `cooldownMs`, the cast, the fuse, the blast).
const GOO_BOMB_CONSTANTS := "abilities.gooBomb"
## The Ability Box's sockets in game-constants.json: their fixed order and count.
const BOX_SOCKETS_PATH := "abilityBox.sockets"
const BOX_SOCKET_COUNT_PATH := "abilityBox.socketCount"
## The rework mode's player numbers in game-constants.json (the quick roll's length).
const REWORK_PLAYER_CONSTANTS := "character.player.rework."

## id -> {title, action (input action), earned_by, cooldown_ms, energy_cost, distance, duration_ms,
## radius, damage}. The dodge's cooldown_ms is filled from constants (`cooldown_ms()`); in the rework
## mode so are the Slam's cost and cooldown (`energy_cost()`, `cooldown_ms()`; its radius and damage
## are not used there).
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
	LANTERN: {"title": "Lantern", "action": &"ability_use", "earned_by": "Quest", "cooldown_ms": 300.0,
		"energy_cost": 10.0},
	GOO_BOMBS: {"title": "Goo Bomb", "action": &"ability_use", "earned_by": "Quest", "cooldown_ms": 600.0,
		"energy_cost": 20.0},
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
	LANTERN: ["An ember glows inside you: see in the dark, and throw small flames that burn and light candles.",
		"Press %s to throw a flame"],
	GOO_BOMBS: ["Brew a jelly bomb inside you and spit it out. It blows up cracked walls, rubble and foes, and you too!",
		"Press %s and stand still while it grows; suck it in with Q to throw it"],
}
## The rework mode's how-to lines where they differ (body-shapes plan section 5: Swallow is a Q hold;
## "%s" is the key of `eat`, AbilityBox.key_action; owner, 2026-10-12: the Roll fires on the release,
## a hold charges only with the `roll-charge` upgrade).
const REWORK_CEREMONY_HOW := {
	SWALLOW: "Hold %s with an essence in your mouth until the ring fills",
	DODGE: "Tap %s to roll; with the charged-roll upgrade, hold it to spin up and keep rolling",
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


## The ceremony card's how-to for `id` with its key label in place of "%s" (the rework mode's line
## when it has its own, REWORK_CEREMONY_HOW).
static func ceremony_how(id: StringName, key_label: String) -> String:
	var how := str((CEREMONY.get(id, ["", ""]) as Array)[1])
	if ReworkMode.is_on() and REWORK_CEREMONY_HOW.has(id):
		how = str(REWORK_CEREMONY_HOW[id])
	return how % key_label if how.contains("%s") else how


## The ability's icon (the HUD console's), or null.
static func icon(id: StringName) -> Texture2D:
	var path := ICON_PATH % String(id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func action(id: StringName) -> StringName:
	return entry(id).get("action", StringName())


## The energy a use costs; in the rework mode the Slam's is `abilities.squashSlam.energy` (0 without
## constants).
static func energy_cost(id: StringName) -> float:
	if id == LANTERN:
		return _lantern_number("energy", float(entry(id).get("energy_cost", 0.0)))
	if id == GOO_BOMBS:
		return _block_number(GOO_BOMB_CONSTANTS, "energy", float(entry(id).get("energy_cost", 0.0)))
	if id == SQUASH_SLAM and ReworkMode.is_on():
		var constants := Services.constants()
		return float(constants.call(&"number", SLAM_CONSTANTS + ".energy")) if constants != null else 0.0
	return float(entry(id).get("energy_cost", 0.0))


## Cooldown from the press; the Roll's is its spin-up, its shortest roll and the pause after it
## (game constants; a longer roll waits its own `rollCooldownMs` after it ends, player_roll.gd);
## in the rework mode the Roll's is the quick roll and the pause after it
## (`character.player.rework.quickRollMs` + `rollCooldownMs`; a charged roll is held back by its own
## end, player_roll.gd), and the Slam's is `abilities.squashSlam.cooldownMs`.
static func cooldown_ms(id: StringName, constants: Node) -> float:
	if id == DODGE:
		if constants == null:
			return 0.0
		var movement := "character.player.movement."
		if ReworkMode.is_on():
			return float(constants.call(&"number", REWORK_PLAYER_CONSTANTS + "quickRollMs")) \
				+ float(constants.call(&"number", movement + "rollCooldownMs"))
		return float(constants.call(&"number", movement + "rollSpinUpMs")) \
			+ float(constants.call(&"number", movement + "rollMinMs")) \
			+ float(constants.call(&"number", movement + "rollCooldownMs"))
	if id == LANTERN:
		return _lantern_number("cooldownMs", float(entry(id).get("cooldown_ms", 0.0)))
	if id == GOO_BOMBS:
		return _block_number(GOO_BOMB_CONSTANTS, "cooldownMs", float(entry(id).get("cooldown_ms", 0.0)))
	if id == SQUASH_SLAM and ReworkMode.is_on():
		return float(constants.call(&"number", SLAM_CONSTANTS + ".cooldownMs")) if constants != null else 0.0
	return float(entry(id).get("cooldown_ms", 0.0))


## `abilities.lantern.<key>` as a number, or `fallback` without constants or the key.
static func _lantern_number(key: String, fallback: float) -> float:
	var constants := Services.constants()
	var raw: Variant = constants.value(LANTERN_CONSTANTS + "." + key) if constants != null else null
	return float(raw) if (raw is float or raw is int) else fallback


## `<block>.<key>` of game-constants.json as a number, or `fallback` without constants or the key.
static func _block_number(block: String, key: String, fallback: float) -> float:
	var constants := Services.constants()
	var raw: Variant = constants.value(block + "." + key) if constants != null else null
	return float(raw) if (raw is float or raw is int) else fallback


## The Ability Box's sockets in their fixed order (`abilityBox.sockets`: squash-slam, stretch-lash,
## teleport, then the later gadgets), whether this table knows them yet or not; [] without constants.
static func box_sockets() -> Array[StringName]:
	var ids: Array[StringName] = []
	var constants := Services.constants()
	var raw: Variant = constants.value(BOX_SOCKETS_PATH, []) if constants != null else []
	if raw is Array:
		for id: Variant in raw:
			ids.append(StringName(str(id)))
	return ids


## How many sockets the box has (`abilityBox.socketCount`; at least the listed ones).
static func box_socket_count() -> int:
	var constants := Services.constants()
	var count: Variant = constants.value(BOX_SOCKET_COUNT_PATH, 0) if constants != null else 0
	var listed := box_sockets().size()
	return maxi(listed, int(count)) if (count is int or count is float) else listed


## True when `id` sits in an Ability Box socket and this table knows it (it can be used).
static func is_box_ability(id: StringName) -> bool:
	return has(id) and box_sockets().has(id)

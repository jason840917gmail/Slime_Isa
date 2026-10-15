extends RefCounted
## An enemy's reaction profile (combat-feel plan section 5 "The fields"; BODY_SHAPES.md
## "Reactions"). Three layers merge, in this order: the weight defaults `combat.weights[weight]`
## (game-constants.json), the type's `reactions` block in `enemy-types.json` (`types[type]`), then
## the scene's `reaction_overrides` export. Dictionaries merge key by key, all other values replace.
## The training dummy's `reaction_preset` (light, medium, heavy, boss) stands in for the type: its
## profile is that weight's defaults.
##
## Profile keys (every one present after the merge): `type`, `weight` (tiny | light | medium |
## heavy | boss), `material`, `knockbackScale`, `hitstunScale`, `holdCap`, `breakFree`, `poise`,
## `breakVerb`?, `roll` (bowl | bonk | break), `suck` (none for everyone: owner, 2026-10-11),
## `classes` (impact class -> a verb or {"verb", "stunMs"?, "damageTaken"?}), `byTag`, `immune`
## (classes that clink; "*" = all), `states` (phase -> {"armor"?, "classes"?, "immune"?, "open"?}),
## `parts` (hurtbox part -> its gate).
##
## Complete as far as the layers go (foundation, 2026-10-11); the reactions module may add keys.
##
## Owner: reactions.

const Services := preload("res://game/shared/services.gd")

const ENEMY_TYPES_FILE := "enemy-types.json"
## The weight of a type without a `reactions` block.
const DEFAULT_WEIGHT := "medium"
## The training dummy's material (sparks and sounds pick it).
const DUMMY_MATERIAL := "wood"
const DUMMY_TYPE := "training-dummy"
## Keys every profile has, with their neutral values.
const NEUTRAL := {
	"type": "",
	"weight": DEFAULT_WEIGHT,
	"material": "",
	"knockbackScale": 1.0,
	"hitstunScale": 1.0,
	"holdCap": 2,
	"breakFree": "push",
	"poise": 0,
	"roll": "bonk",
	"suck": "none",
	"classes": {},
	"byTag": {},
	"immune": [],
	"states": {},
	"parts": {},
}

## Type id (or "preset:<weight>") -> the merged type layers.
static var _cache: Dictionary = {}


## The merged profile of `enemy` (an EnemyScript, or a TrainingDummyScript with a preset).
static func for_enemy(enemy: Node) -> Dictionary:
	if enemy == null:
		return for_type("")
	var preset: Variant = enemy.get(&"reaction_preset")
	var base := for_preset(preset) if preset is String and not (preset as String).is_empty() else for_type(type_of(enemy))
	var overrides: Variant = enemy.get(&"reaction_overrides")
	if overrides is Dictionary and not (overrides as Dictionary).is_empty():
		return merge(base, overrides)
	return base


## The weight defaults plus `enemy-types.json`'s `reactions` for `type_id` (cached). A type with no
## block gets DEFAULT_WEIGHT's defaults. Warns once when `hitstunScale` < 1 (chains can break).
static func for_type(type_id: String) -> Dictionary:
	if _cache.has(type_id):
		return _cache[type_id]
	var reactions := _type_reactions(type_id)
	var weight := str(reactions.get("weight", DEFAULT_WEIGHT))
	var profile := merge(merge(NEUTRAL, _weight_defaults(weight)), reactions)
	profile["type"] = type_id
	profile["weight"] = weight
	if float(profile.get("hitstunScale", 1.0)) < 1.0:
		push_warning("ReactionProfile: '%s' has hitstunScale %s < 1; chains can break" % [type_id, profile["hitstunScale"]])
	_cache[type_id] = profile
	return profile


## A training dummy preset: `weight`'s defaults (light, medium, heavy or boss).
static func for_preset(weight: String) -> Dictionary:
	var key := "preset:" + weight
	if _cache.has(key):
		return _cache[key]
	var profile := merge(NEUTRAL, _weight_defaults(weight))
	profile["type"] = DUMMY_TYPE
	profile["weight"] = weight
	profile["material"] = DUMMY_MATERIAL
	_cache[key] = profile
	return profile


## The enemy's type id: its `enemy_type` export, else the file name of its root's scene
## (`character.<type>` scenes are named after their type), else "".
static func type_of(enemy: Node) -> String:
	if enemy == null:
		return ""
	var exported: Variant = enemy.get(&"enemy_type")
	if exported is String and not (exported as String).is_empty():
		return exported
	var body: Variant = enemy.get(&"body")
	var root: Node = body if body is Node else enemy.get_parent()
	if root != null and not root.scene_file_path.is_empty():
		return root.scene_file_path.get_file().get_basename()
	return ""


## `base` with `over` on top: Dictionaries merge key by key (recursively), anything else replaces.
## Neither argument changes.
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key: Variant in over:
		var value: Variant = over[key]
		if value is Dictionary and merged.get(key) is Dictionary:
			merged[key] = merge(merged[key], value)
		elif value is Dictionary or value is Array:
			merged[key] = value.duplicate(true)
		else:
			merged[key] = value
	return merged


## Forgets the cached layers (tests, or data edited while the game runs).
static func clear_cache() -> void:
	_cache.clear()


static func _weight_defaults(weight: String) -> Dictionary:
	var constants := Services.constants()
	var row: Variant = constants.value("combat.weights.%s" % weight, {}) if constants != null else {}
	return row if row is Dictionary else {}


static func _type_reactions(type_id: String) -> Dictionary:
	var constants := Services.constants()
	if constants == null or type_id.is_empty():
		return {}
	var data: Variant = constants.data_file(ENEMY_TYPES_FILE)
	if not data is Dictionary:
		return {}
	var types: Variant = (data as Dictionary).get("types", {})
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	var reactions: Variant = (entry as Dictionary).get("reactions", {}) if entry is Dictionary else {}
	return reactions if reactions is Dictionary else {}

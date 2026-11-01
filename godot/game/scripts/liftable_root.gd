@tool
extends StaticBody2D
## The root of `object.liftable` (game/scenes/objects/liftable.tscn; docs/godot/PROPS.md
## "Suckables"): what a designer sets on a placed suckable thing, in the Inspector, with the editor
## showing it at once (the owner, 2026-10-19: "an easy way to place suckable objects and set what is
## under them"; the Scenery dock's Suckables category places them with their kind set).
##
## - `kind`: which liftable it is (game/data/liftables.json, a list to pick from); "" keeps the
##   scene's own (LiftableScript `kind`, as the older scenes and rooms set it on the child).
## - `under`: what it leaves where it stood when the slime sucks it up (a PotLoot, game/dungeon/
##   pot_loot.gd): "keep" (the scene's own PotLoot, if any, as the dungeon pot's random one),
##   "none", "heart", "energy", "coins" or "random".
## - `weight` (throw combat): its usual weight comes from the data file, picked as the game picks it
##   (ThrowMode.weight_in, effect_in on `gulp.throwCombat`, read here: the editor has no autoloads);
##   a thing whose LiftableScript has `heavy` set is heavy.
##
## Owner: abilities.

const CATALOG := "res://game/data/liftables.json"
const PotLoot := preload("res://game/dungeon/pot_loot.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const SCRIPT_NODE := "LiftableScript"
const LOOT_NODE := "PotLoot"
const CONSTANTS := "res://game/data/game-constants.json"

## Which liftable it is ("" keeps the scene's own).
@export var kind: String = "":
	set(value):
		kind = value
		# Picking a kind in the editor fills in its usual weight (loading a scene does not).
		if Engine.is_editor_hint() and is_inside_tree() and not value.is_empty():
			weight = _usual_weight(value)
		_apply_kind()
## What it leaves where it stood when it is sucked up.
@export_enum("keep", "none", "heart", "energy", "coins", "random") var under: String = "keep"
## Throw combat: how heavy it is, "light", "medium" or "heavy" (the Gulp's level decides whether it
## lifts). The source of truth for this thing's weight: picking a kind fills in that kind's usual
## weight (`gulp.throwCombat.kindWeights`), and it can be changed after. "" (a scene not yet opened
## in the editor) uses the kind's usual weight.
@export var weight: String = "":
	set(value):
		weight = value
		_apply_weight()

static var _kinds_cache: Dictionary = {}
static var _combat_cache: Dictionary = {}


## The catalog's kinds (id -> {"name", "frames", ...}), read once.
static func catalog_kinds() -> Dictionary:
	if _kinds_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if parsed is Dictionary:
			var kinds: Variant = (parsed as Dictionary).get("kinds")
			if kinds is Dictionary:
				_kinds_cache = kinds
	return _kinds_cache


## A kind's first sheet frame (its picture), 0 when unknown.
static func first_frame(id: String) -> int:
	var found: Variant = catalog_kinds().get(id)
	var frames: Variant = (found as Dictionary).get("frames") if found is Dictionary else null
	return int((frames as Array)[0]) if frames is Array and not (frames as Array).is_empty() else 0


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "weight":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = ",".join(PackedStringArray(ThrowMode.WEIGHTS))
	elif property["name"] == "kind":
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(PackedStringArray(catalog_kinds().keys()))


## Before the LiftableScript child's _ready (a root enters the tree before its children are ready).
func _enter_tree() -> void:
	_apply_kind()
	# In the editor an older scene's thing shows its usual weight (saved with the scene).
	if Engine.is_editor_hint() and weight.is_empty():
		var script_node := get_node_or_null(SCRIPT_NODE)
		var id := kind if not kind.is_empty() else (str(script_node.get(&"kind")) if script_node != null else "")
		if not id.is_empty():
			weight = _usual_weight(id)
	_apply_weight()


func _ready() -> void:
	if not Engine.is_editor_hint():
		_apply_under()


## A kind's usual weight (`gulp.throwCombat.kindWeights`, read once): "light" when it has none.
static func kind_weight(id: String) -> String:
	return ThrowMode.weight_in(_combat(), id)


## A kind's throw effect, as the game picks it (ThrowMode.effect_in: `kindEffects`, then its
## material's `materialEffects`): "freeze", "sleep", "stick", "shatter", "pierce" or "" for none.
## Read from the files, so the editor can show it (the Scenery dock's hover text).
static func kind_effect(id: String) -> String:
	var entry: Variant = catalog_kinds().get(id)
	var material := str((entry as Dictionary).get("material", "")) if entry is Dictionary else ""
	return ThrowMode.effect_in(_combat(), id, material)


## This thing's usual weight: heavy when its LiftableScript has `heavy` set (it counts as heavy in
## the game too: liftable.gd `weight`), else its kind's.
func _usual_weight(id: String) -> String:
	var script_node := get_node_or_null(SCRIPT_NODE)
	if script_node != null and bool(script_node.get(&"heavy")):
		return ThrowMode.HEAVY
	return kind_weight(id)


## `gulp.throwCombat` in the game constants (read once), {} when missing.
static func _combat() -> Dictionary:
	if _combat_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONSTANTS))
		var gulp: Variant = (parsed as Dictionary).get("gulp") if parsed is Dictionary else null
		var combat: Variant = (gulp as Dictionary).get("throwCombat") if gulp is Dictionary else null
		if combat is Dictionary:
			_combat_cache = combat
	return _combat_cache


## The child keeps the weight ("" leaves its kind's usual one).
func _apply_weight() -> void:
	var script_node := get_node_or_null(SCRIPT_NODE)
	if script_node != null:
		script_node.set(&"weight_class", weight)


## The child keeps the kind; the editor's picture shows it at once.
func _apply_kind() -> void:
	if kind.is_empty():
		return
	var script_node := get_node_or_null(SCRIPT_NODE)
	if script_node != null:
		script_node.set(&"kind", kind)
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		visual.frame = first_frame(kind)


## In the game: what it hides (a PotLoot made, set or taken away), unless the scene's own is kept.
func _apply_under() -> void:
	if under == "keep":
		return
	var loot := get_node_or_null(LOOT_NODE)
	if under == "none":
		if loot != null:
			loot.queue_free()
		return
	if loot == null:
		loot = PotLoot.new()
		loot.name = LOOT_NODE
		loot.set(&"loot", under)
		add_child(loot)
	else:
		loot.set(&"loot", under)

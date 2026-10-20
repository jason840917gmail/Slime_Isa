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
##
## Owner: abilities.

const CATALOG := "res://game/data/liftables.json"
const PotLoot := preload("res://game/dungeon/pot_loot.gd")
const SCRIPT_NODE := "LiftableScript"
const LOOT_NODE := "PotLoot"

## Which liftable it is ("" keeps the scene's own).
@export var kind: String = "":
	set(value):
		kind = value
		_apply_kind()
## What it leaves where it stood when it is sucked up.
@export_enum("keep", "none", "heart", "energy", "coins", "random") var under: String = "keep"

static var _kinds_cache: Dictionary = {}


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
	if property["name"] == "kind":
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(PackedStringArray(catalog_kinds().keys()))


## Before the LiftableScript child's _ready (a root enters the tree before its children are ready).
func _enter_tree() -> void:
	_apply_kind()


func _ready() -> void:
	if not Engine.is_editor_hint():
		_apply_under()


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

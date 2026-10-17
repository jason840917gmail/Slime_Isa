extends Node
class_name WorldAreaScript
## Scene script `game.world-area` (Phaser `features/scripts/WorldAreaScript.ts` +
## `WorldSceneLoader.worldAreaData`): a data holder under an Area2D in world scenes. World spec
## 3.1, enemy spec 3.1. WorldService.register_world() calls `to_record()` on every one.
##
## `enemy-wander` (roadmap 5.25, 2026-10-16) is not Phaser's: the wander area a camp of placed
## enemies shares (game/enemy/placed_enemy.gd names it by `area_id`), one shape, no data. The
## `enemy-spawn` areas (a camp that refills on a timer) are left only in the playground and the dev
## worlds (enemy spec 3).
##
## Owner: world builder.

const Perimeter := preload("res://game/shared/perimeter.gd")

const KIND_ENEMY_SAFE_ZONE := "enemy-safe-zone"
const KIND_ENEMY_SPAWN := "enemy-spawn"
const KIND_ENEMY_WANDER := "enemy-wander"
const KIND_NPC_WANDER := "npc-wander"
## Authored child names, used only when a node export did not resolve (converter node_paths).
const STAY_SHAPE_NAME := "stay-shape"

## JSON `areaKind`: "enemy-safe-zone" | "enemy-spawn" | "enemy-wander" | "npc-wander"; anything
## else -> push_error.
@export var area_kind: String = ""
## JSON `areaId` (e.g. "level-1-starter-camp").
@export var area_id: String = ""
## JSON `area`: the owning Area2D.
@export var area: Area2D
## JSON `data` (camelCase keys kept: enemies[{type, weight, maxAlive}], intervalMs,
## maxPopulation, npcInstanceId).
@export var data: Dictionary = {}
## JSON `shape`: the outer perimeter (pursue perimeter for enemy-spawn, the wander perimeter for
## enemy-wander).
@export var shape: CollisionShape2D
## JSON `stayShape`: enemy-spawn only, the inner stay perimeter.
@export var stay_shape: CollisionShape2D


## The record WorldService exposes (see WorldService.areas()):
## `{"id": area_id, "kind": area_kind, "data": data, "perimeter": Perimeter.from_shape(shape)}`
## plus `"stay_perimeter"` (and the alias `"pursue_perimeter"`) for enemy-spawn; an enemy-wander
## record's `"stay_perimeter"` is its perimeter (what EnemyScript.configure_navigation reads).
## Validation (push_error and return {}): unknown kind; safe zone not a rectangle; spawn area
## without stay shape, stay/pursue of different kinds, or stay not inside pursue
## (`Perimeter.fits_inside`). Must be called after the world is in the tree (uses global
## transforms).
func to_record() -> Dictionary:
	var label := area_id if not area_id.is_empty() else String(get_path())
	if not area_kind in [KIND_ENEMY_SAFE_ZONE, KIND_ENEMY_SPAWN, KIND_ENEMY_WANDER, KIND_NPC_WANDER]:
		push_error("WorldArea '%s': unknown areaKind '%s'" % [label, area_kind])
		return {}
	if area_id.is_empty():
		push_error("WorldArea %s: missing areaId" % label)
		return {}
	var outer_node := _resolve_shape()
	if outer_node == null:
		push_error("WorldArea '%s': missing shape" % label)
		return {}
	var perimeter := Perimeter.from_shape(outer_node)
	if perimeter.is_empty():
		return {}
	var record := {"id": area_id, "kind": area_kind, "data": data.duplicate(true), "perimeter": perimeter}
	if area_kind == KIND_ENEMY_SAFE_ZONE:
		if perimeter["shape"] != Perimeter.SHAPE_RECTANGLE:
			push_error("WorldArea '%s': enemy safe zones must be rectangles" % label)
			return {}
	elif area_kind == KIND_ENEMY_SPAWN:
		var stay_node := _resolve_stay_shape()
		if stay_node == null:
			push_error("WorldArea '%s': enemy-spawn areas need a stay shape" % label)
			return {}
		var stay := Perimeter.from_shape(stay_node)
		if stay.is_empty():
			return {}
		if stay["shape"] != perimeter["shape"]:
			push_error("WorldArea '%s': stay and pursue shapes must be the same kind" % label)
			return {}
		if not Perimeter.fits_inside(stay, perimeter):
			push_error("WorldArea '%s': the stay shape must fit inside the pursue shape" % label)
			return {}
		record["stay_perimeter"] = stay
		record["pursue_perimeter"] = perimeter
	elif area_kind == KIND_ENEMY_WANDER:
		record["stay_perimeter"] = perimeter
	return record


func _owner_area() -> Node:
	if area != null:
		return area
	return get_parent()


## `shape`, or (when the export did not resolve) the area's first CollisionShape2D that is not
## the stay shape.
func _resolve_shape() -> CollisionShape2D:
	if shape != null:
		return shape
	var owner_node := _owner_area()
	if owner_node == null:
		return null
	for child: Node in owner_node.get_children():
		if child is CollisionShape2D and child != stay_shape and child.name != STAY_SHAPE_NAME:
			return child as CollisionShape2D
	return null


func _resolve_stay_shape() -> CollisionShape2D:
	if stay_shape != null:
		return stay_shape
	var owner_node := _owner_area()
	if owner_node == null:
		return null
	return owner_node.get_node_or_null(NodePath(STAY_SHAPE_NAME)) as CollisionShape2D

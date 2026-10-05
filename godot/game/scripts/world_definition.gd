extends Node
class_name WorldDefinitionScript
## Scene script `game.world-definition` (Phaser `features/scripts/WorldDefinitionScript.ts`):
## a data holder on every world scene (node `world-definition`). World spec 2.1.
##
## level-1: map_id "level-1", tile_size 64, columns 56, rows 56, metadata.player.spawn (640,704).
## The spawn used at runtime is the `player-spawn` marker node, not metadata (world spec 2.1).
##
## Owner: world builder.

const CAMERA_FOLLOW := "follow"
const CAMERA_FIXED := "fixed"

## JSON `mapId`.
@export var map_id: String = ""
## JSON `tileSize` (px).
@export var tile_size: int = 0
## JSON `columns`.
@export var columns: int = 0
## JSON `rows`.
@export var rows: int = 0
## JSON `metadata` (camelCase keys kept: objects, player.spawn, player.entries).
@export var metadata: Dictionary = {}
## JSON `cameraMode`: "follow" (default, absent in level-1) or "fixed" (interiors).
@export var camera_mode: String = "follow"


## `{"tile_size", "columns", "rows", "width" = columns*tile_size, "height" = rows*tile_size}`.
func dimensions() -> Dictionary:
	return {
		"tile_size": tile_size,
		"columns": columns,
		"rows": rows,
		"width": float(columns * tile_size),
		"height": float(rows * tile_size),
	}


## Validation as `WorldSceneLoader.ts:57-60` / `WorldDimensions.ts:15-19`: tile_size, columns,
## rows positive integers; camera_mode "follow" or "fixed". Returns the problems ([] when valid).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if map_id.is_empty():
		problems.append("mapId is empty")
	if tile_size <= 0:
		problems.append("tileSize must be a positive integer (got %d)" % tile_size)
	if columns <= 0:
		problems.append("columns must be a positive integer (got %d)" % columns)
	if rows <= 0:
		problems.append("rows must be a positive integer (got %d)" % rows)
	if not camera_mode.is_empty() and camera_mode != CAMERA_FOLLOW and camera_mode != CAMERA_FIXED:
		problems.append("cameraMode must be 'follow' or 'fixed' (got '%s')" % camera_mode)
	return problems

extends Node
## Autoload `WorldService`: the world-level service locator. Replaces the Phaser script-service
## map (`ENEMY_TARGET_SERVICE`, world navigation, `world.elevation` [not ported], exit service)
## and the bits of `WorldScene` / `UniversalSceneWorldController` other systems query.
##
## Lifecycle: main.gd loads the world scene, then calls `register_world()`, `register_player()`
## and `register_camera()` in that order (world spec 1.2). Everything here is read-only for the
## other builders except `set_pause_reason()`.
## Access: `Services.world()`.
##
## Coordinates: "phaser position" = old Phaser root position (FeetAnchor). Areas, safe zones,
## spawn points and `primary_target().centre` are in that space (enemy spec 9, world spec 0).
##
## Owner: world builder.

const PlayerScript := preload("res://game/scripts/player.gd")
const WorldDefinitionScript := preload("res://game/scripts/world_definition.gd")
const WorldAreaScript := preload("res://game/scripts/world_area.gd")
const WorldCamera := preload("res://game/world/world_camera.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const Perimeter := preload("res://game/shared/perimeter.gd")
const WaterSurface := preload("res://game/world/water_surface.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")

## Scene id -> scene path for every scene Godot owns (docs/godot/CONVENTIONS.md "Scenes Godot owns").
const SCENE_INDEX_PATH := "res://game/scenes/scene_index.json"
## Area kinds (WorldAreaScript.ts); anything else is a content error.
const AREA_ENEMY_SAFE_ZONE := "enemy-safe-zone"
const AREA_ENEMY_SPAWN := "enemy-spawn"
const AREA_NPC_WANDER := "npc-wander"
## Pause reasons. The tree is paused while any reason is active.
const PAUSE_HIT_STOP := &"hit-stop"
const PAUSE_MODAL := &"modal"
## The terrain TileSet (contract C6): the ground layer is the TileMapLayer using it.
const TERRAIN_TILESET_PATH := "res://game/world/terrain_tileset.tres"
## Name of the spawn marker Node2D in world scenes (WorldSceneLoader.ts:90-96).
const PLAYER_SPAWN_MARKER := "player-spawn"
## Custom data layer of the converted terrain TileSet that holds the terrain tile id.
const TILE_ID_DATA_LAYER := "tile_id"
## Terrain tiles whose `terrain.tiles` entry has `physics` (resources/terrain/
## terrain.tile-set.resource.json; TileCatalog.isTileCollidable).
const SOLID_TILE_IDS: PackedStringArray = ["water", "deep-water", "rock-wall"]
## Collision mask used by line_of_sight: the "world" layer (bit 1).
const SIGHT_COLLISION_MASK := 1

## Emitted after `register_world()` succeeded. Payload: {"mapId": String}.
signal world_registered(payload: Dictionary)
## Emitted after `register_player()`. Payload: {"player": Node}.
signal player_registered(payload: Dictionary)

## Root of the instanced world scene (y-sorted by the converter). Null before register_world().
var world_root: Node2D
## The world's `world_definition.gd` node.
var definition: WorldDefinitionScript
## The ground TileMapLayer (the world's TileMapLayer whose tile_set is the terrain tileset).
var ground_layer: TileMapLayer
## The player's PlayerScript node and its CharacterBody2D root. Null until register_player().
var player: PlayerScript
var player_body: CharacterBody2D
## The WorldCamera (res://game/world/world_camera.gd): GameFeel calls `camera.shake()`.
## Null until register_camera().
var camera: WorldCamera

var _scene_index: Dictionary = {}
var _areas: Array[Dictionary] = []
var _pause_reasons: Dictionary = {}
var _dimensions: Dictionary = {}
## PackedScene cache: res:// path -> PackedScene (packed_scene()). Emptied by clear().
var _packed: Dictionary = {}


## Loads SCENE_INDEX_PATH into `_scene_index` (push_error when missing).
func _ready() -> void:
	_load_scene_index()


func _load_scene_index() -> void:
	if not FileAccess.file_exists(SCENE_INDEX_PATH):
		push_error("WorldService: %s is missing" % SCENE_INDEX_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SCENE_INDEX_PATH)) != OK or not (json.data is Dictionary):
		push_error("WorldService: %s is not a JSON object" % SCENE_INDEX_PATH)
		return
	_scene_index = json.data


# --- scene index -------------------------------------------------------------------------

## The scene for `scene_id` (e.g. "character.worm-swordsman"), "" when unknown:
## `SCENE_INDEX_PATH[scene_id]`.
func scene_path(scene_id: String) -> String:
	if _scene_index.is_empty():
		_load_scene_index()
	var path: Variant = _scene_index.get(scene_id, "")
	return path if path is String else ""


## Loads and instantiates the scene for `scene_id`; null + push_error() when unknown.
## The instance is NOT added to the tree. The PackedScene is cached (see packed_scene()), so
## repeated spawns (camp enemies, hit effects) never re-read the .tscn mid-step.
func instantiate_scene(scene_id: String) -> Node:
	var packed := packed_scene(scene_id)
	if packed == null:
		return null
	var path := packed.resource_path
	var instance := packed.instantiate()
	if instance == null:
		push_error("WorldService: could not instantiate %s" % path)
	return instance


## The converted PackedScene for `scene_id`, loaded once and kept in `_packed` (an instance
## holds no reference to its PackedScene, so without this the ResourceLoader cache drops it
## and every spawn re-parses the file and reloads its textures and sounds). Phaser has every
## scene document and media file in memory before the world starts (MapLoadScene.ts:56-67);
## main.gd warms the trial's runtime-spawned scenes through this at bootstrap.
## Null + push_error() when the id is unknown or the file does not load.
func packed_scene(scene_id: String) -> PackedScene:
	var path := scene_path(scene_id)
	if path.is_empty():
		push_error("WorldService: unknown scene id '%s'" % scene_id)
		return null
	var cached: PackedScene = _packed.get(path) as PackedScene
	if cached != null:
		return cached
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("WorldService: could not load %s for '%s'" % [path, scene_id])
		return null
	_packed[path] = packed
	return packed


## Instantiates `scene_id`, places its root so its old Phaser root position is `phaser_point`
## (`P + depth_anchor * scale`, conventions "Feet origin"), adds it to `parent` (default:
## `entities_root()`) and returns it. Used for the player spawn (world spec 2.2), camp enemies
## (enemy spec 3.2 step 4) and effects. Null on failure.
## The position is set BEFORE the node enters the tree, so its scripts already see the final
## position in `_enter_tree` / `_ready`.
func spawn_at_phaser_position(scene_id: String, phaser_point: Vector2, parent: Node = null) -> Node2D:
	var target_parent: Node = parent if parent != null else entities_root()
	if target_parent == null:
		push_error("WorldService: no parent to spawn '%s' into (world not registered)" % scene_id)
		return null
	var instance := instantiate_scene(scene_id)
	if instance == null:
		return null
	var root := instance as Node2D
	if root == null:
		push_error("WorldService: scene '%s' root is not a Node2D" % scene_id)
		instance.free()
		return null
	var global_target := FeetAnchor.global_for_phaser_position(root, phaser_point)
	var parent_item := target_parent as CanvasItem
	if parent_item != null and parent_item.is_inside_tree():
		root.position = parent_item.get_global_transform().affine_inverse() * global_target
	else:
		root.position = global_target
	target_parent.add_child(root)
	root.reset_physics_interpolation()
	return root


# --- world ---------------------------------------------------------------------------------

## Registers the instanced world: finds the `world_definition.gd` node (exactly one; push_error
## and return false otherwise), validates it (world spec 2.1), finds the ground TileMapLayer,
## mounts the animated water on it (`WaterSurface.mount`, docs/godot/specs/water.md) and the
## hand-made terrain edges over both (`TerrainEdges.mount`, docs/godot/TERRAIN_LAB.md),
## and builds the area records from every `world_area.gd` node (world spec 3.1). Emits
## `world_registered`. The world must already be inside the tree (areas use global transforms).
func register_world(root: Node2D) -> bool:
	if root == null:
		push_error("WorldService.register_world: null world root")
		return false
	var definitions: Array[Node] = []
	var area_scripts: Array[Node] = []
	var tile_layers: Array[TileMapLayer] = []
	_collect(root, definitions, area_scripts, tile_layers)
	if definitions.size() != 1:
		push_error("WorldService.register_world: expected exactly one world definition in '%s', found %d" % [root.name, definitions.size()])
		return false
	var found_definition := definitions[0] as WorldDefinitionScript
	var problems := found_definition.validate()
	if not problems.is_empty():
		push_error("WorldService.register_world: invalid world definition: %s" % "; ".join(problems))
		return false
	world_root = root
	definition = found_definition
	_dimensions = found_definition.dimensions()
	ground_layer = _pick_ground_layer(tile_layers)
	if ground_layer == null:
		push_warning("WorldService.register_world: no ground TileMapLayer found; every tile counts as open")
	else:
		# Animated water over the ground's water tiles (water spec 4.1); nothing on a dry world.
		WaterSurface.mount(ground_layer)
		# Hand-made edges where grounds meet, shores included: after the water, so they draw over it.
		TerrainEdges.mount(ground_layer)
	_areas.clear()
	for node: Node in area_scripts:
		var record: Dictionary = (node as WorldAreaScript).to_record()
		if not record.is_empty():
			_areas.append(record)
	world_registered.emit({"mapId": map_id()})
	return true


## Depth-first in tree order (= authored order): definitions, area scripts and tile layers.
func _collect(node: Node, definitions: Array[Node], area_scripts: Array[Node], tile_layers: Array[TileMapLayer]) -> void:
	var script := node.get_script() as Script
	if script == WorldDefinitionScript:
		definitions.append(node)
	elif script == WorldAreaScript:
		area_scripts.append(node)
	if node is TileMapLayer:
		tile_layers.append(node as TileMapLayer)
	for child: Node in node.get_children():
		_collect(child, definitions, area_scripts, tile_layers)


func _pick_ground_layer(tile_layers: Array[TileMapLayer]) -> TileMapLayer:
	for layer: TileMapLayer in tile_layers:
		if layer.tile_set != null and layer.tile_set.resource_path == TERRAIN_TILESET_PATH:
			return layer
	for layer: TileMapLayer in tile_layers:
		if layer.tile_set != null:
			return layer
	return null


## Parent for runtime-spawned world entities (player, enemies, effect holders): the world root,
## so they Y-sort with props.
func entities_root() -> Node2D:
	return world_root if is_instance_valid(world_root) else null


## `{"tile_size": int, "columns": int, "rows": int, "width": float, "height": float}`
## (level-1: 64, 56, 56, 3584, 3584). {} before register_world().
func dimensions() -> Dictionary:
	return _dimensions.duplicate()


## `Rect2(0, 0, width, height)`: world bounds and camera bounds.
func world_rect() -> Rect2:
	if _dimensions.is_empty():
		return Rect2()
	return Rect2(0.0, 0.0, float(_dimensions["width"]), float(_dimensions["height"]))


## World definition `map_id` ("level-1").
func map_id() -> String:
	return definition.map_id if is_instance_valid(definition) else ""


## World definition `camera_mode` ("follow" | "fixed"; "follow" when absent).
func camera_mode() -> String:
	if not is_instance_valid(definition) or definition.camera_mode.is_empty():
		return "follow"
	return definition.camera_mode


## Area records of one kind (world spec 3.1):
##   enemy-safe-zone: {"id", "kind", "data", "perimeter"}                   (rectangle only)
##   enemy-spawn:     {"id", "kind", "data", "perimeter", "stay_perimeter"} (pursue = perimeter;
##                    "pursue_perimeter" is an alias of "perimeter")
##   npc-wander:      {"id", "kind", "data", "perimeter"}
## `data` is the raw JSON Dictionary (camelCase keys: enemies, intervalMs, maxPopulation,
## npcInstanceId). Perimeters use res://game/shared/perimeter.gd.
func areas(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _areas:
		if record["kind"] == kind:
			result.append(record)
	return result


## Perimeters of every enemy-safe-zone (rectangles), in authored order.
func safe_zones() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in areas(AREA_ENEMY_SAFE_ZONE):
		result.append(record["perimeter"])
	return result


## The npc-wander record whose `data.npcInstanceId == instance_id`, {} when none.
func npc_wander_area(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	for record: Dictionary in areas(AREA_NPC_WANDER):
		var data: Dictionary = record["data"]
		if str(data.get("npcInstanceId", "")) == instance_id:
			return record
	return {}


## True when cell (tx, ty) is outside the grid or holds a solid ground tile (water, deep-water,
## rock-wall: the tiles whose terrain entry has `physics`). The converter tags every tile with
## the custom data layer `tile_id` (its tile collisions are separate StaticBody2D nodes under
## `ground/TileCollision`), so a cell is solid when its `tile_id` is in SOLID_TILE_IDS; a
## TileSet collision polygon on any physics layer also counts (contract C3). An empty cell is
## not solid (WorldScene.isSolidTile).
func is_solid_tile(tx: int, ty: int) -> bool:
	if not _is_within_world(tx, ty):
		return true
	if not is_instance_valid(ground_layer) or ground_layer.tile_set == null:
		return false
	var tile_data := ground_layer.get_cell_tile_data(Vector2i(tx, ty))
	if tile_data == null:
		return false
	if ground_layer.tile_set.has_custom_data_layer_by_name(TILE_ID_DATA_LAYER):
		var tile_id: Variant = tile_data.get_custom_data(TILE_ID_DATA_LAYER)
		if tile_id is String and SOLID_TILE_IDS.has(tile_id):
			return true
	for layer_index: int in ground_layer.tile_set.get_physics_layers_count():
		if tile_data.get_collision_polygons_count(layer_index) > 0:
			return true
	return false


func _is_within_world(tx: int, ty: int) -> bool:
	if _dimensions.is_empty():
		return false
	return tx >= 0 and ty >= 0 and tx < int(_dimensions["columns"]) and ty < int(_dimensions["rows"])


## The `player-spawn` marker's global position (old Phaser root position; level-1 (640, 704)).
## Missing marker -> push_error and the world centre.
func player_spawn_marker() -> Vector2:
	var rect := world_rect()
	if not is_instance_valid(world_root):
		push_error("WorldService.player_spawn_marker: no world registered")
		return rect.get_center()
	var marker := world_root.get_node_or_null(NodePath(PLAYER_SPAWN_MARKER)) as Node2D
	if marker == null:
		marker = world_root.find_child(PLAYER_SPAWN_MARKER, true, false) as Node2D
	if marker == null:
		push_error("WorldService: world '%s' has no '%s' marker" % [map_id(), PLAYER_SPAWN_MARKER])
		return rect.get_center()
	return marker.global_position


## World spec 2.2 for a new run: the marker if valid (finite, inside the world, tile under it
## not solid), else `find_spawn_point(marker)`. Old Phaser root position (the slime centre).
func player_spawn_point() -> Vector2:
	var marker := player_spawn_marker()
	if _is_valid_position(marker):
		return marker
	return find_spawn_point(marker)


## `WorldScene.isValidSavedPosition` (WorldScene.ts:1542-1548): tests the tile under the old
## root position (the slime centre), not the feet.
func _is_valid_position(point: Vector2) -> bool:
	if _dimensions.is_empty() or not point.is_finite():
		return false
	if point.x < 0.0 or point.y < 0.0 or point.x > float(_dimensions["width"]) or point.y > float(_dimensions["height"]):
		return false
	var tile_size := float(_dimensions["tile_size"])
	var tx := floori(point.x / tile_size)
	var ty := floori(point.y / tile_size)
	return _is_within_world(tx, ty) and not is_solid_tile(tx, ty)


## `WorldScene.findSpawnPoint` (world spec 2.2 step 3): ring search from the anchor's tile for
## the first non-solid in-grid cell, returning its centre `(tx*64+32, ty*64+32)`; nothing ->
## world centre.
func find_spawn_point(anchor: Vector2) -> Vector2:
	if _dimensions.is_empty():
		return Vector2.ZERO
	var tile_size := float(_dimensions["tile_size"])
	var start_x := floori(anchor.x / tile_size)
	var start_y := floori(anchor.y / tile_size)
	var max_radius := maxi(int(_dimensions["columns"]), int(_dimensions["rows"]))
	for radius: int in max_radius:
		for ty: int in range(start_y - radius, start_y + radius + 1):
			for tx: int in range(start_x - radius, start_x + radius + 1):
				if not _is_within_world(tx, ty) or is_solid_tile(tx, ty):
					continue
				return Vector2(tx * tile_size + tile_size / 2.0, ty * tile_size + tile_size / 2.0)
	return world_rect().get_center()


# --- player / targets ------------------------------------------------------------------------

## Registers the spawned player (its PlayerScript node). Emits `player_registered`.
func register_player(player_script: PlayerScript) -> void:
	player = player_script
	player_body = null
	if player_script != null:
		player_body = player_script.body
		if player_body == null:
			player_body = player_script.get_parent() as CharacterBody2D
	player_registered.emit({"player": player_script})


## Phaser `ENEMY_TARGET_SERVICE.primaryTarget()` (enemy spec 8):
## `{"player": PlayerScript, "body": CharacterBody2D, "centre": Vector2 (old Phaser position),
##   "hurtbox": Area2D, "active": bool (not dead), "hostile": true}`; {} when no player.
func primary_target() -> Dictionary:
	if not is_instance_valid(player) or not is_instance_valid(player_body) or not player.is_inside_tree():
		return {}
	return {
		"player": player,
		"body": player_body,
		"centre": player.get_centre(),
		"hurtbox": player.get_damage_area(),
		"active": not player.is_dead(),
		"hostile": true,
	}


## Phaser `lineOfSight` (enemy spec 4.3): true when no body on the world layer (bit 1) crosses
## the segment `from -> to`. Ray query on the world's direct space state, `collision_mask = 1`,
## bodies only, excluding `exclude` RIDs (the enemy and player bodies). Water never blocks.
## The "< 20 px on both sides never blocks" exception is skipped in the trial. Call only from
## `_physics_process`. True when there is no world.
func line_of_sight(from: Vector2, to: Vector2, exclude: Array[RID]) -> bool:
	if not is_instance_valid(world_root) or not world_root.is_inside_tree() or from.is_equal_approx(to):
		return true
	var space := world_root.get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to, SIGHT_COLLISION_MASK, exclude)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()


# --- camera --------------------------------------------------------------------------------

## Registers the WorldCamera so GameFeel can shake it and the player respawn can pan it.
func register_camera(world_camera: WorldCamera) -> void:
	camera = world_camera


# --- pause ---------------------------------------------------------------------------------

## Adds/removes a pause reason; `get_tree().paused = not reasons.is_empty()`. Hit-stop uses
## PAUSE_HIT_STOP; a modal (OUT in the trial) uses PAUSE_MODAL, so ending a hit-stop never
## unpauses a menu (combat spec 16, last edge case).
func set_pause_reason(reason: StringName, active: bool) -> void:
	if active:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	_apply_pause()


## True while `reason` is active.
func has_pause_reason(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


func _apply_pause() -> void:
	if not is_inside_tree():
		return
	var should_pause := not _pause_reasons.is_empty()
	if get_tree().paused != should_pause:
		get_tree().paused = should_pause


## Forgets the world, player, camera, areas, pause reasons and the PackedScene cache (world
## unload / reload).
func clear() -> void:
	_packed.clear()
	world_root = null
	definition = null
	ground_layer = null
	player = null
	player_body = null
	camera = null
	_areas.clear()
	_dimensions = {}
	_pause_reasons.clear()
	_apply_pause()

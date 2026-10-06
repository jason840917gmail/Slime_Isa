@tool
extends Node2D
## Cliffs, holes and ground levels over a world's ground (docs/godot/ELEVATION.md).
##
## A world paints its levels on an `elevation` TileMapLayer (elevation_layer.gd, the elevation
## tile set) beside its ground layer. `Elevation.mount(ground, collide)` adds this node as the
## child "Elevation" of the ground layer, after the water and the terrain edges, and draws from the
## model (elevation_grid.gd), bottom to top:
##   Patches  chamfered corner triangles that take the ground across the corner, and the top's own
##            ground over the water surface's soft edge along a rim over water;
##   Shade    the ground of holes, darker with every level of depth (elevation_shade.gdshader);
##   Shadows  what raised ground casts on lower ground, towards the lower right, longer for a
##            taller drop (elevation_cast_shadow.gdshader);
##   Walls    the cliff faces, one stone course per level (elevation_wall.gdshader, world space),
##            and rounded corner stones where a wall ends;
##   Rims     the light a top edge facing the upper left catches;
##   Water    water lapping at the foot of walls that stand in water (elevation_water_foot.gdshader);
##   Feet     the lower ground's border growing up the foot of each wall;
##   Lips     every top's border as one continuous strip of its ground's fringe: hanging over its
##            walls, a rim of tufts elsewhere, round at convex corners (elevation_rims.gd);
##   Stairs   the flights of stairs (elevation_stairs.gd), back to front in one mesh
##            (elevation_stairs.gdshader), and StairsFeet: the ground growing up their railings.
## The terrain is the master of every cliff top and foot: a ground's own cliff fringes
## (`art/<ground>-lip.png`, `art/<ground>-foot.png`, scripts/art/build-elevation-art.py,
## elevation_fringe.gdshader) or, for a ground without them, its terrain edge art (the straight
## tiles of `<ground>-edges.png`, elevation_strip.gdshader). A ground without either keeps hard edges.
##
## The child "Occlusion" (elevation_occlusion.gd) holds the terrain's depth map: the cast shadows
## read it, and so do the bodies, which hide (the player: shows as a silhouette) where higher
## ground in front covers them.
##
## With `collide`, each level gets a static body on its own physics layer (12 + level − MIN_LEVEL)
## whose segments surround what that level can walk on (elevation_grid.gd: its tops, stairs, and a
## strip `elevation.behindDepth` deep behind higher ground), and every body that walks the world
## (the player, enemies, NPCs) collides with the layer of its level (`track`).
##
## Stairs are painted as one cell per cell of width (`painted_stairs`): the first cell past the rim,
## on the lower ground, in the flight's direction. The terrain is built as if they were that lower
## ground; each run of them side by side is a flight (elevation_stairs.gd) standing on it, which
## overrides the terrain where it stands: its steps are walkable by every level it joins, the rest
## of it by none (`is_walkable`, the collision).
##
## Moving between levels: stairs (the level of the stretch a body stands on), and drops. A rim
## holds a body; `drop_target` says where it lands when it goes over: out past the rim and straight
## down by the drop, so off a south face it lands at the wall's foot, off a back rim behind the
## hill, off a side down beside it. The player's ledge push and hop (game/player/abilities/
## jump_sequence.gd) fly there; `set_flight` gives the body its depth while in the air.
##
## Owner: world (elevation).

const Self := preload("res://game/world/elevation/elevation.gd")
const Services := preload("res://game/shared/services.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const ElevationRims := preload("res://game/world/elevation/elevation_rims.gd")
const ElevationOcclusion := preload("res://game/world/elevation/elevation_occlusion.gd")
const ElevationStairs := preload("res://game/world/elevation/elevation_stairs.gd")
const ElevationFences := preload("res://game/world/elevation/fences/elevation_fences.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const WALL_SHADER := preload("res://game/world/elevation/elevation_wall.gdshader")
const WALL_END_SHADER := preload("res://game/world/elevation/elevation_wall_end.gdshader")
const STRIP_SHADER := preload("res://game/world/elevation/elevation_strip.gdshader")
const GROUND_SHADER := preload("res://game/world/elevation/elevation_ground.gdshader")
const SHADE_SHADER := preload("res://game/world/elevation/elevation_shade.gdshader")
const CAST_SHADOW_SHADER := preload("res://game/world/elevation/elevation_cast_shadow.gdshader")
const FRINGE_SHADER := preload("res://game/world/elevation/elevation_fringe.gdshader")
const GLOW_SHADER := preload("res://game/world/elevation/elevation_glow.gdshader")
const WATER_FOOT_SHADER := preload("res://game/world/elevation/elevation_water_foot.gdshader")
const STAIRS_SHADER := preload("res://game/world/elevation/elevation_stairs.gdshader")
const WATER_SURFACE_NODE := "WaterSurface"

const NODE_NAME := "Elevation"
const LEVEL_DATA_LAYER := "elevation_level"
const KIND_DATA_LAYER := "elevation_kind"
## Painted stairs (`elevation_kind`): "stairs-<direction>" (ElevationStairs.DIRECTIONS) with a
## railed landing, "stairs-<direction>-open" with an open one; plain "stairs" is "stairs-s".
const STAIRS_KIND := "stairs"
const OPEN_SUFFIX := "-open"
const TILE_ID_DATA_LAYER := "tile_id"
const TERRAIN_TILESET_PATH := "res://game/world/terrain_tileset.tres"
## Ground sheets wrap every 19 cells (Phaser sheet-wrap).
const SHEET_CELLS := 19
## Physics layer of level MIN_LEVEL; one layer per level up to MAX_LEVEL (project.godot names them).
const FIRST_PHYSICS_LAYER := 12
## Bodies that walk the world: player, enemy and npc layers.
const WALKER_LAYERS := 2 | 4 | 128
## Gameplay values (game-constants.json `elevation`); these defaults serve the editor preview.
const DEFAULTS := {
	"behindDepth": 32.0, "dropPushMs": 280.0, "dropOutward": 22.0, "dropBaseMs": 260.0,
	"dropMsPerLevel": 90.0, "hopArcHeight": 36.0,
}
## A walking body's collision rect around its feet (player_slime.tscn BodyShape 30 x 26, slightly
## inset) and how far past its edge a ledge is looked for.
const BODY_HALF := Vector2(13.0, 12.0)
const RIM_PROBE := 6.0
## The rect's corners and edge middles (times BODY_HALF, from its centre): the ledge probes.
const BODY_SIDES: Array[Vector2] = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0),
		Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)]
## `ledge_below` when there is no ledge.
const NO_LEDGE := -100
## Hop path samples (world units).
const HOP_STEP := 8.0
## How far a landing may be moved to find room (world units).
const LANDING_SEARCH_STEP := 4.0

## Wall and stairs art per style (scripts/art/build-elevation-art.py) and the style every cliff uses;
## the stairs kit: "<style>", "tread" / "riser" / "coping".
const WALL_ART := "res://game/world/elevation/art/%s-wall.png"
const STAIRS_ART := "res://game/world/elevation/art/%s-stairs-%s.png"
## Corner stones where a wall ends ("<style>", "right" or "left"); their end line lies
## WALL_END_OUTSIDE world units inside the art's outer side (build-elevation-art.py WALL_END_OUTSIDE,
## 10 px), and the wall's foot reaches WALL_END_FRINGE past it.
const WALL_END_ART := "res://game/world/elevation/art/%s-wall-end-%s.png"
const WALL_END_OUTSIDE := 5.0
const WALL_END_FRINGE := 8.0
## The end stones turn away from the light on a wall's east end, towards it on its west end.
const SHADE_END_EAST := 0.9
const SHADE_END_WEST := 1.04
const WALL_STYLE := "meadow-rock"
## Wall shading by the way a face looks: south-west faces catch the upper-left light.
const SHADE_SOUTH := 0.86
const SHADE_SOUTH_WEST := 1.0
const SHADE_SOUTH_EAST := 0.66

## Terrain-edge strips (grounds without fringe art; world units): how far a rim reaches out of its
## ground and back into it, and a foot.
const LIP_OUT := 28.0
const LIP_IN := 10.0
const FOOT_OUT := 26.0
const FOOT_IN := 14.0
## Shadow a strip casts beyond its art: under a lip on a wall top, and up the foot of a wall.
const SHADOW_WALL_LIP := 0.45
const SHADOW_FOOT := 0.45
## Cast shadows: how far a level of height throws them (world units) and how dark they are; they
## reach over lower ground up to SHADOW_REACH cells right of and one cell below a drop.
const SHADOW_UNITS := 20.0
const SHADOW_STRENGTH := 0.36
const SHADOW_REACH := 2
## Water at a wall foot: how far the strip reaches into the water and up the wall (world units).
const WATER_FOOT_IN := 10.0
const WATER_FOOT_OUT := 34.0
## A rim over water covers the water surface's soft edge with its own ground this far (world units).
const RIM_WATER_COVER := 30.0
## The depth map covers the elevated part of the world and this many cells around it.
const DEPTH_MARGIN := 3
## Cliff fringe art per ground and kind ("lip", "foot"), the strip row its edge line runs on and
## the strip's height (scripts/art/build-elevation-art.py EDGE_ROWS, LAYOUT).
const FRINGE_ART := "res://game/world/elevation/art/%s-%s.png"
const FRINGE_EDGE_ROW := {"lip": 96.0, "foot": 80.0}
const FRINGE_HEIGHT := {"lip": 160.0, "foot": 128.0}
## Mesh key suffix of fringe strips (the rest is the ground).
const FRINGE_KEY := ":fringe"
## Terrain edge atlas: 128 px tiles with a 2 px gutter; the straight tiles by where the rim points.
const ART_TILE := 128.0
const TILE_RIM_DOWN := 3
const TILE_RIM_UP := 12
const TILE_RIM_RIGHT := 5
const TILE_RIM_LEFT := 10

## The ground layer (the parent).
var ground: TileMapLayer
## The painted elevation layer.
var layer: TileMapLayer
## The model of the last build.
var grid: ElevationGrid
## Cell size in world units.
var cell := 64.0
## Bodies tracked by `track`: body -> level.
var bodies: Dictionary = {}
## The flights of stairs (ElevationStairs), back to front.
var stairs: Array = []
## The terrain's depth map and the bodies' occlusion.
var occlusion: ElevationOcclusion
## Bodies in the air (a hop or a drop): body -> depth (elevation_occlusion.gd) while they fly.
var flights: Dictionary = {}
## The fences along painted rims (fences/elevation_fences.gd, docs/godot/FENCES.md), null without.
var fences: ElevationFences

var _queued := false
var _collide := false
## ground name -> its 19x19 sheet texture.
var _sheets: Dictionary = {}


## Mounts the elevation over `ground_layer` from the elevation layer beside it (a second call
## rebuilds). Removes it and returns null when the world has no elevation layer or nothing raised.
static func mount(ground_layer: TileMapLayer, collide: bool) -> Self:
	if ground_layer == null:
		return null
	var existing := ground_layer.get_node_or_null(NodePath(NODE_NAME)) as Self
	var painted := find_layer(ground_layer)
	if painted == null or painted.get_used_cells().is_empty():
		if existing != null:
			existing.queue_free()
		return null
	var elevation := existing
	if elevation == null:
		elevation = Self.new()
		elevation.name = NODE_NAME
		ground_layer.add_child(elevation)
	else:
		ground_layer.move_child(elevation, -1)
	elevation.ground = ground_layer
	elevation.layer = painted
	elevation._collide = collide
	elevation.rebuild()
	return elevation


## The elevation layer beside `ground_layer` (a sibling TileMapLayer whose tile set has the
## `elevation_level` data layer), or null.
static func find_layer(ground_layer: TileMapLayer) -> TileMapLayer:
	var parent := ground_layer.get_parent() if ground_layer != null else null
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var candidate := child as TileMapLayer
		if candidate != null and candidate != ground_layer and candidate.tile_set != null \
				and candidate.tile_set.has_custom_data_layer_by_name(LEVEL_DATA_LAYER):
			return candidate
	return null


## The ground layer beside an elevation layer (the sibling using the terrain tile set), or null.
static func find_ground(elevation_layer: TileMapLayer) -> TileMapLayer:
	var parent := elevation_layer.get_parent() if elevation_layer != null else null
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var candidate := child as TileMapLayer
		if candidate != null and candidate.tile_set != null and candidate.tile_set.resource_path == TERRAIN_TILESET_PATH:
			return candidate
	return null


## Painted levels beside `ground_layer`: Vector2i cell -> int (only painted cells). A stairs cell
## takes the level of the ground it leads down to (the next cell along its direction that is not
## stairs): the terrain is built as if it were not there, the flight stands on it.
static func painted_levels(ground_layer: TileMapLayer) -> Dictionary:
	var painted := find_layer(ground_layer)
	var levels := {}
	if painted == null:
		return levels
	var stairs_cells := painted_stairs(ground_layer)
	for cell: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell)
		if data != null and not stairs_cells.has(cell):
			levels[cell] = int(data.get_custom_data(LEVEL_DATA_LAYER))
	for cell: Vector2i in stairs_cells:
		var step := stairs_step(str(stairs_cells[cell]))
		var below := cell + step
		while stairs_cells.has(below) and below.distance_squared_to(cell) < 64:
			below += step
		if levels.has(below):
			levels[cell] = levels[below]
	return levels


## Painted stairs beside `ground_layer`: Vector2i cell -> kind ("stairs-<direction>[-open]").
static func painted_stairs(ground_layer: TileMapLayer) -> Dictionary:
	var painted := find_layer(ground_layer)
	var cells := {}
	if painted == null or not painted.tile_set.has_custom_data_layer_by_name(KIND_DATA_LAYER):
		return cells
	for cell: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell)
		if data == null:
			continue
		var kind := str(data.get_custom_data(KIND_DATA_LAYER))
		if kind == STAIRS_KIND:
			kind = STAIRS_KIND + "-s"
		if kind.begins_with(STAIRS_KIND + "-") and ElevationStairs.DIRECTIONS.has(stairs_direction(kind)):
			cells[cell] = kind
	return cells


## The direction (ElevationStairs.DIRECTIONS key) of a stairs kind.
static func stairs_direction(kind: String) -> String:
	return kind.trim_prefix(STAIRS_KIND + "-").trim_suffix(OPEN_SUFFIX)


## The cell step of a stairs kind's direction.
static func stairs_step(kind: String) -> Vector2i:
	var d: Vector2 = ElevationStairs.DIRECTIONS[stairs_direction(kind)][0]
	return Vector2i(int(d.x), int(d.y))


## Physics layer bit of `level`'s collision.
static func level_bit(level: int) -> int:
	return 1 << (FIRST_PHYSICS_LAYER - 1 + clampi(level, ElevationGrid.MIN_LEVEL, ElevationGrid.MAX_LEVEL) - ElevationGrid.MIN_LEVEL)


## Every level's bit.
static func all_level_bits() -> int:
	var bits := 0
	for level in range(ElevationGrid.MIN_LEVEL, ElevationGrid.MAX_LEVEL + 1):
		bits |= level_bit(level)
	return bits


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	set_physics_process(not Engine.is_editor_hint())


## Bodies on stairs take the level of the stretch they stand on; every body's sprites get its depth.
func _physics_process(_delta: float) -> void:
	if grid == null:
		return
	for body: Node in bodies.keys():
		var walker := body as CharacterBody2D
		if not is_instance_valid(walker):
			continue
		var depth := float(flights.get(walker, NAN))
		if not stairs.is_empty():
			var local := walker.global_position - global_position
			var flight := stairs_at(local)
			if flight != null:
				var level := flight.level_at(local, int(bodies[body]))
				if level != int(bodies[body]) and not flights.has(walker):
					track(walker, level)
				if is_nan(depth):
					depth = flight.depth_at(local) + global_position.y
		if occlusion != null:
			occlusion.update_body(walker, int(bodies[body]), depth)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Rebuilds the model, the drawing and (in the game) the collision.
func rebuild() -> void:
	_queued = false
	if ground == null or layer == null or ground.tile_set == null:
		return
	cell = float(ground.tile_set.tile_size.x)
	var used := ground.get_used_rect()
	var columns := int(ground.get_meta("columns", used.end.x))
	var rows := int(ground.get_meta("rows", used.end.y))
	grid = ElevationGrid.build(columns, rows, painted_levels(ground), _ground_names(), setting("behindDepth") / cell)
	_build_stairs()
	_build_drawing()
	if _collide:
		_build_collision()
		for body: Node in bodies.keys():
			if is_instance_valid(body):
				track(body as CharacterBody2D, int(bodies[body]))
		# Bodies already in the world (NPCs placed in the scene); later ones arrive by node_added.
		var world_root := ground.get_parent()
		if world_root != null:
			for node: Node in world_root.find_children("*", "CharacterBody2D", true, false):
				var walker := node as CharacterBody2D
				if walker.collision_layer & WALKER_LAYERS != 0 and not bodies.has(walker):
					track(walker)
	elif has_node("Collision"):
		get_node("Collision").free()
	# Fences along painted rims, over the cliffs and into the depth map (docs/godot/FENCES.md).
	fences = ElevationFences.mount(self, grid, occlusion, _collide)


## Queues a rebuild for the end of the frame (painting sends many changes).
func queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	rebuild.call_deferred()


## Level of the ground seen at `world_point` (on stairs, of the stretch there), `fallback` on a wall
## or off the map.
func level_at(world_point: Vector2, fallback: int = 0) -> int:
	if grid == null:
		return fallback
	var local := world_point - global_position
	var flight := stairs_at(local)
	if flight != null:
		return flight.level_at(local, fallback)
	return grid.level_at(local / cell, fallback)


## True when bodies of `level` can stand at `world_point` (its tops, the steps of stairs it joins,
## the strip behind higher ground; never a wall or the rest of a flight of stairs).
func is_walkable(world_point: Vector2, level: int) -> bool:
	if grid == null:
		return level == 0
	var local := world_point - global_position
	var rule := _stairs_rule(local, level)
	if rule >= 0:
		return rule == 1
	return grid.is_walkable_point(local / cell, level)


## The flight of stairs whose steps hold `point` (Elevation space), or null.
func stairs_at(point: Vector2) -> ElevationStairs:
	for flight: ElevationStairs in stairs:
		if flight.walks(point):
			return flight
	return null


## Stairs at `point` (Elevation space) for a body of `level`: 1 walkable (steps of a flight it
## joins), 0 blocked (what of a flight stands at its level's height), -1 no stairs there. What of a
## flight is only drawn over the ground there (standing higher, in front) blocks nothing: it hides
## the body (the depth map).
func _stairs_rule(point: Vector2, level: int) -> int:
	var rule := -1
	for flight: ElevationStairs in stairs:
		if not flight.bounds.has_point(point):
			continue
		if flight.walks(point):
			# Its steps: walkable by the levels it joins; the landing the top level's alone.
			if flight.walks_level(point, level):
				return 1
			rule = 0
		elif flight.blocks(point, level):
			rule = 0
	return rule


## A gameplay value of game-constants.json `elevation` (DEFAULTS without the autoload).
static func setting(key: String) -> float:
	var constants := Services.constants()
	if constants == null:
		return float(DEFAULTS[key])
	return constants.number("elevation." + key)


## True when a body of `level` with its feet at `feet` fits: its collision rect stands on ground
## it can walk on, off solid tiles (deep water) and off the strip between a fence and its rim.
func body_fits(feet: Vector2, level: int) -> bool:
	var world := Services.world()
	for corner: Vector2 in [Vector2.ZERO, Vector2(-BODY_HALF.x, 0.0), Vector2(BODY_HALF.x, 0.0),
			Vector2(-BODY_HALF.x, -2.0 * BODY_HALF.y), Vector2(BODY_HALF.x, -2.0 * BODY_HALF.y)]:
		var point := feet + corner
		if not is_walkable(point, level):
			return false
		if fences != null and fences.blocks_point(point, level):
			return false
		if world != null and world.is_solid_tile(floori(point.x / cell), floori(point.y / cell)):
			return false
	return true


## The level of the lower ground past the ledge a body of `level` with its feet at `feet` pushes
## against going `direction`, NO_LEDGE when it is not at one. Shape does not matter (a straight rim,
## a 45° one, a corner, a wall's top): the side of the body facing `direction` (its corners and edge
## middles) is probed `reach` further. It is at a ledge when a probe leaves the ground it walks on
## and every probe that does is over lower ground (a lower top, or a wall whose top is at or below
## its level), none over higher ground, a wall going up, stairs, a fence or the map's border; the
## ledge drops to the highest of those lower grounds.
func ledge_below(feet: Vector2, level: int, direction: Vector2, reach: float = RIM_PROBE) -> int:
	if grid == null or direction == Vector2.ZERO:
		return NO_LEDGE
	var unit := direction.normalized()
	var centre := feet - Vector2(0.0, BODY_HALF.y)
	var lower := NO_LEDGE
	for side: Vector2 in BODY_SIDES:
		var offset := side * BODY_HALF
		if offset.dot(unit) <= 0.0:
			continue
		var probe := centre + offset + unit * reach
		if fences != null and fences.blocks_point(probe, level):
			return NO_LEDGE
		if is_walkable(probe, level):
			continue
		var below := _lower_level_at(probe, level)
		if below < ElevationGrid.MIN_LEVEL:
			return NO_LEDGE
		lower = maxi(lower, below)
	return lower


## Where a body of `level` with its feet at `feet`, going `direction`, lands when it goes over the
## ledge in front of it (`ledge_below`): {"feet", "level", "drop"}, or {} when it is not at one or
## finds no room below. The landing follows height alone: `outward` past where it stood (the ledge
## push's `dropOutward` by default) and one cell lower on screen per level dropped, as a fall
## straight down looks from the camera: in front of a south face at its foot (straight or 45°),
## behind a back rim (as deep as the ground behind allows), beside a side rim. When that spot has
## no room the landing takes the nearest spot that has, up (towards the rim behind it) or further
## out: a side drop beside a wall lands past the wall, not hidden behind the hill.
func drop_target(feet: Vector2, level: int, direction: Vector2, outward: float = -1.0, reach: float = RIM_PROBE) -> Dictionary:
	var lower := ledge_below(feet, level, direction, reach)
	if lower == NO_LEDGE:
		return {}
	var unit := direction.normalized()
	var drop := level - lower
	var out := outward if outward >= 0.0 else setting("dropOutward")
	var landing := feet + unit * out + Vector2(0.0, float(drop) * cell)
	var up_reach := float(drop) * cell + cell
	var step := 0.0
	while step <= up_reach:
		var up := landing - Vector2(0.0, step)
		if body_fits(up, lower):
			return {"feet": up, "level": lower, "drop": drop}
		var out_more := landing + unit * step
		if step > 0.0 and step <= cell and body_fits(out_more, lower):
			return {"feet": out_more, "level": lower, "drop": drop}
		step += LANDING_SEARCH_STEP
	return {}


## The hop of a body of `level` from `feet` along `direction` for `distance`: {"feet", "level",
## "drop"}. It goes as far as the body fits on its level; at a rim it goes over and drops (landing
## out by what is left of the hop); higher ground or a wall stops it before them. A hop never
## climbs.
func hop_target(feet: Vector2, level: int, direction: Vector2, distance: float) -> Dictionary:
	var result := {"feet": feet, "level": level, "drop": 0}
	if grid == null or direction == Vector2.ZERO or distance <= 0.0:
		return result
	var unit := direction.normalized()
	var steps := maxi(1, ceili(distance / HOP_STEP))
	for i in range(1, steps + 1):
		var point := feet + unit * (distance * float(i) / steps)
		if body_fits(point, level):
			result["feet"] = point
			continue
		var last: Vector2 = result["feet"]
		var over := drop_target(last, level, unit, maxf(setting("dropOutward"), distance - last.distance_to(feet)), RIM_PROBE + HOP_STEP)
		return over if not over.is_empty() else result
	return result


## A body in the air at `depth` (its feet's y + 64 · the level it is over, blended over the
## flight): its sprites hide behind what is nearer than that. `end_flight` hands it back to its level.
func set_flight(body: Node, depth: float) -> void:
	flights[body] = depth


func end_flight(body: Node) -> void:
	flights.erase(body)


## The level of the lower ground at `point` for a body of `level`: a lower top, or the foot of a
## wall at or below its level; MIN_LEVEL - 1 when there is none.
func _lower_level_at(point: Vector2, level: int) -> int:
	var tri := grid.tri_at((point - global_position) / cell)
	if tri < 0 or _stairs_rule(point - global_position, level) >= 0:
		return ElevationGrid.MIN_LEVEL - 1
	var band := grid.tri_band[tri]
	if band >= 0:
		var wall: Dictionary = grid.bands[band]
		return int(wall["bottom"]) if int(wall["top"]) <= level else ElevationGrid.MIN_LEVEL - 1
	return grid.tri_level[tri] if grid.tri_level[tri] < level else ElevationGrid.MIN_LEVEL - 1


## Makes `body` collide with `level`'s walls only (when `level` is unset: the level it can walk on
## where its feet are, the one it sees there first). The body keeps every other bit of its mask.
func track(body: CharacterBody2D, level: int = ElevationGrid.MIN_LEVEL - 1) -> void:
	if body == null:
		return
	if level < ElevationGrid.MIN_LEVEL:
		var local := body.global_position - global_position
		var flight := stairs_at(local) if grid != null else null
		if flight != null:
			level = flight.level_at(local, flight.top)
		else:
			var point := local / cell
			level = grid.walkable_level(point, grid.level_at(point, 0)) if grid != null else 0
	bodies[body] = level
	body.collision_mask = (body.collision_mask & ~all_level_bits()) | level_bit(level)
	if not body.tree_exiting.is_connected(_forget):
		body.tree_exiting.connect(_forget.bind(body))


## The level `body` walks on (0 when untracked).
func level_of(body: Node) -> int:
	return int(bodies.get(body, 0))


func _forget(body: Node) -> void:
	bodies.erase(body)
	flights.erase(body)
	if occlusion != null:
		occlusion.forget(body)


func _on_node_added(node: Node) -> void:
	var body := node as CharacterBody2D
	if body == null or body.collision_layer & WALKER_LAYERS == 0:
		return
	var world_root := ground.get_parent() if ground != null else null
	if world_root != null and world_root.is_ancestor_of(body):
		# Placed by its spawner after it enters the tree.
		_track_when_placed.call_deferred(body)


func _track_when_placed(body: CharacterBody2D) -> void:
	if is_instance_valid(body) and body.is_inside_tree() and not bodies.has(body):
		track(body)


# --- grounds -------------------------------------------------------------------------------

## Vector2i cell -> ground name (terrain edge materials); fills `_sheets`.
func _ground_names() -> Dictionary:
	_sheets.clear()
	var names := {}
	var by_source := {}
	for cell_pos: Vector2i in ground.get_used_cells():
		var source_id := ground.get_cell_source_id(cell_pos)
		if not by_source.has(source_id):
			var data := ground.get_cell_tile_data(cell_pos)
			var tile_id := str(data.get_custom_data(TILE_ID_DATA_LAYER)) if data != null and ground.tile_set.has_custom_data_layer_by_name(TILE_ID_DATA_LAYER) else ""
			var name_of_ground := TerrainMaterials.ground_of(tile_id)
			by_source[source_id] = name_of_ground
			if name_of_ground != "" and not _sheets.has(name_of_ground):
				var source := ground.tile_set.get_source(source_id) as TileSetAtlasSource
				if source != null:
					_sheets[name_of_ground] = source.texture
		names[cell_pos] = by_source[source_id]
	return names


func _has_edge_art(name_of_ground: String) -> bool:
	return _sheets.has(name_of_ground) and name_of_ground != TerrainMaterials.WATER \
			and ResourceLoader.exists(TerrainMaterials.edges_path(name_of_ground)) \
			and ResourceLoader.exists(TerrainMaterials.rim_path(name_of_ground))


func _has_fringe(name_of_ground: String, kind: String) -> bool:
	return name_of_ground != "" and ResourceLoader.exists(FRINGE_ART % [name_of_ground, kind])


func _ground_origin() -> Vector2:
	return ground.global_position if ground.is_inside_tree() else ground.position


# --- drawing -------------------------------------------------------------------------------

func _build_drawing() -> void:
	for group_name: String in ["Patches", "Shade", "Shadows", "Walls", "Rims", "Water", "Feet", "Lips", "Stairs", "StairsFeet"]:
		var old := get_node_or_null(group_name)
		if old != null:
			old.free()
	var patches := {}
	var shade := {}
	var shadows := {}
	var walls := {}
	var rims := {}
	var water := {}
	var feet := {}
	var lips := {}
	var depth := MeshData.new()
	for patch: Dictionary in grid.patches:
		var name_of_ground := str(patch["ground"])
		if _sheets.has(name_of_ground) and name_of_ground != TerrainMaterials.WATER:
			_arrays_for(patches, name_of_ground).add_flat(_world(grid.tri_points(int(patch["tri"]))), Vector2.ZERO, Color.WHITE)
	for tri in grid.tri_level.size():
		var level := grid.tri_level[tri]
		if level < 0 and grid.tri_band[tri] < 0:
			_arrays_for(shade, "holes").add_flat(_world(grid.tri_points(tri)), Vector2.ZERO, Color(_level_channel(level), 0.0, 0.0, 1.0))
	for index in grid.bands.size():
		_add_band(_arrays_for(walls, WALL_STYLE), index)
		_add_foot(feet, water, index)
	_add_wall_ends(walls)
	var rims_builder := ElevationRims.new()
	var leftover := rims_builder.build(grid, cell, func(g: String) -> bool: return _has_fringe(g, "lip"),
			lips, FRINGE_KEY, _arrays_for(rims, "glow"), depth, SHADOW_WALL_LIP,
			func(level: int, dy: float) -> Color: return ElevationOcclusion.encode(level, dy))
	_add_plain_rims(leftover, lips)
	_add_water_covers(rims_builder, patches)
	var stairs_mesh := MeshData.new()
	var stairs_feet := {}
	for flight: ElevationStairs in stairs:
		flight.add_mesh(stairs_mesh)
		for foot: Array in flight.feet:
			_add_stairs_foot(stairs_feet, foot)
	var depth_rect := _add_depth(depth)
	_add_receivers(_arrays_for(shadows, "cast"), depth_rect)
	if occlusion == null:
		occlusion = ElevationOcclusion.new()
		occlusion.name = "Occlusion"
		add_child(occlusion)
	occlusion.build(depth, depth_rect, _ground_origin())
	_add_group("Patches", patches, func(key: String) -> Material: return _ground_material(key))
	_add_group("Shade", shade, func(_key: String) -> Material: return _shade_material())
	_add_group("Shadows", shadows, func(_key: String) -> Material: return _cast_shadow_material())
	_add_group("Walls", walls, func(key: String) -> Material: return _wall_material(key))
	_add_group("Rims", rims, func(key: String) -> Material: return _rim_material(key))
	_add_group("Water", water, func(_key: String) -> Material: return _water_foot_material())
	_add_group("Feet", feet, func(key: String) -> Material: return _strip_material(key, true))
	_add_group("Lips", lips, func(key: String) -> Material: return _strip_material(key, false))
	_add_group("Stairs", {"stairs": stairs_mesh}, func(_key: String) -> Material: return _stairs_material())
	_add_group("StairsFeet", stairs_feet, func(key: String) -> Material: return _strip_material(key, true))


## The flights of stairs from the painted stairs cells: a run of cells side by side along the rim
## with the same kind is one flight. It leaves the rim where the higher ground behind its cells
## begins, from that ground's level down to theirs; a column of old-style stairs cells counts once.
func _build_stairs() -> void:
	stairs.clear()
	var cells := painted_stairs(ground)
	var done := {}
	var keys := cells.keys()
	keys.sort()
	for start: Vector2i in keys:
		if done.has(start):
			continue
		var kind := str(cells[start])
		var step := stairs_step(kind)
		done[start] = true
		if str(cells.get(start - step, "")) == kind:
			continue
		# Side by side along the rim: across the direction (along the diagonal for a 45° flight).
		var side := Vector2i(1, 0) if step.x == 0 else (Vector2i(0, 1) if step.y == 0 else Vector2i(1, -step.x * step.y))
		var run_cells: Array[Vector2i] = [start]
		var next := start + side
		while str(cells.get(next, "")) == kind:
			run_cells.append(next)
			done[next] = true
			next += side
		var rim_sum := Vector2.ZERO
		var top := ElevationGrid.MIN_LEVEL - 1
		for run_cell in run_cells:
			var hit := _rim_point(run_cell, step)
			if hit.z < ElevationGrid.MIN_LEVEL:
				top = ElevationGrid.MIN_LEVEL - 1
				break
			rim_sum += Vector2(hit.x, hit.y)
			top = maxi(top, int(hit.z))
		var bottom := grid.level_of_cell(start)
		if top <= bottom:
			continue
		var flight := ElevationStairs.create(stairs_direction(kind), rim_sum / run_cells.size() * cell, top, bottom,
				run_cells.size(), kind.ends_with(OPEN_SUFFIX))
		flight.occlude(_tops_around(flight.bounds, top))
		stairs.append(flight)
	stairs.sort_custom(func(a: ElevationStairs, b: ElevationStairs) -> bool: return a.bounds.end.y < b.bounds.end.y)


## The tops of `level` or higher in `rect` (Elevation space) and a cell around it, merged (screen
## polygons): what a flight leaving such ground hides behind.
func _tops_around(rect: Rect2, level: int) -> Array[PackedVector2Array]:
	var tris: Array[PackedVector2Array] = []
	var from := Vector2i(floori(rect.position.x / cell) - 1, floori(rect.position.y / cell) - 1)
	var to := Vector2i(floori(rect.end.x / cell) + 1, floori(rect.end.y / cell) + 1)
	for cy in range(maxi(0, from.y), mini(grid.rows - 1, to.y) + 1):
		for cx in range(maxi(0, from.x), mini(grid.columns - 1, to.x) + 1):
			var index := grid.cell_index(Vector2i(cx, cy))
			var high: Array[int] = []
			for tri in range(index * 8, index * 8 + 8):
				if grid.tri_band[tri] < 0 and grid.tri_level[tri] >= level:
					high.append(tri)
			if high.size() == 8:
				var corner := Vector2(cx, cy) * cell
				tris.append(PackedVector2Array([corner, corner + Vector2(cell, 0.0), corner + Vector2(cell, cell), corner + Vector2(0.0, cell)]))
				continue
			for tri in high:
				tris.append(_world(grid.tri_points(tri)))
	return ElevationStairs._union(tris)


## Where the higher ground behind stairs cell `c` begins, from its centre against its direction
## `step`: Vector3(x, y in cells, that ground's level); z = MIN_LEVEL - 1 when none is within 2.5
## cells.
func _rim_point(c: Vector2i, step: Vector2i) -> Vector3:
	var own := grid.level_of_cell(c)
	var back := -Vector2(step).normalized()
	var from := Vector2(c) + Vector2(0.5, 0.5)
	var higher := func(at: Vector2) -> int:
		var tri := grid.tri_at(at)
		return grid.tri_level[tri] if tri >= 0 and grid.tri_band[tri] < 0 and grid.tri_level[tri] > own else ElevationGrid.MIN_LEVEL - 1
	var lo := 0.0
	var hi := -1.0
	for i in range(1, 161):
		if int(higher.call(from + back * (i / 64.0))) >= ElevationGrid.MIN_LEVEL:
			lo = (i - 1) / 64.0
			hi = i / 64.0
			break
	if hi < 0.0:
		return Vector3(0.0, 0.0, ElevationGrid.MIN_LEVEL - 1)
	for _i in 8:
		var mid := (lo + hi) * 0.5
		if int(higher.call(from + back * mid)) >= ElevationGrid.MIN_LEVEL:
			hi = mid
		else:
			lo = mid
	var rim_point := from + back * hi
	return Vector3(rim_point.x, rim_point.y, int(higher.call(rim_point + back * 0.01)))


## The ground growing up a flight's railing or post where it stands on the lower ground in sight:
## foot = [from, to (Elevation space), level].
func _add_stairs_foot(feet: Dictionary, foot: Array) -> void:
	var from: Vector2 = foot[0]
	var to: Vector2 = foot[1]
	if absf(to.x - from.x) < 1.0:
		return
	if from.x > to.x:
		var swap := from
		from = to
		to = swap
	var tri := grid.tri_at((from + to) * 0.5 / cell + Vector2(0.0, 0.05))
	if tri < 0:
		return
	var name_of_ground := grid.tri_ground[tri]
	if _has_fringe(name_of_ground, "foot"):
		_add_fringe_strip(_arrays_for(feet, name_of_ground + FRINGE_KEY), from / cell, to / cell, "foot", SHADOW_FOOT, int(foot[2]))


func _arrays_for(groups: Dictionary, key: String) -> MeshData:
	if not groups.has(key):
		groups[key] = MeshData.new()
	return groups[key]


func _add_group(group_name: String, groups: Dictionary, material_for: Callable) -> void:
	var holder := Node2D.new()
	holder.name = group_name
	add_child(holder)
	for key: String in groups:
		var arrays: MeshData = groups[key]
		if arrays.is_empty():
			continue
		var material_of := material_for.call(key) as Material
		if material_of == null:
			continue
		var instance := MeshInstance2D.new()
		instance.name = key
		instance.mesh = arrays.to_mesh()
		instance.material = material_of
		holder.add_child(instance)


## Points in cells -> ground-layer space.
func _world(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point * cell)
	return out


## Where a wall ends beside lower ground, at row `s` of its half-column:
## (left side open, right side open).
func _open_ends(band: Dictionary, s: int) -> Vector2i:
	var column := int(band["column"])
	var open := Vector2i.ZERO
	for side: int in [-1, 1]:
		var beside := column + side
		if beside < 0 or beside >= grid.columns * 2:
			continue
		var tri := grid.column_tri(beside, s)
		if grid.tri_band[tri] < 0 and grid.tri_level[tri] < int(band["top"]):
			if side < 0:
				open.x = 1
			else:
				open.y = 1
	return open


## Corner stones at every wall end: a vertical edge between a wall tri and lower ground beside it. The column of stones covers the wall's last stretch and bulges a little past its end,
## its courses on the wall's courses (the same UV as the wall).
func _add_wall_ends(walls: Dictionary) -> void:
	for edge: Array in grid.tri_edges():
		if int(edge[2]) != ElevationGrid.VERTICAL:
			continue
		var a := int(edge[0])
		var b := int(edge[1])
		var band_index := -1
		var outward := 0.0
		if grid.tri_band[a] >= 0 and grid.tri_band[b] < 0:
			band_index = grid.tri_band[a]
			outward = 1.0
		elif grid.tri_band[b] >= 0 and grid.tri_band[a] < 0:
			band_index = grid.tri_band[b]
			outward = -1.0
		else:
			continue
		var band: Dictionary = grid.bands[band_index]
		var other := b if outward > 0.0 else a
		if grid.tri_level[other] >= int(band["top"]):
			continue
		var side := "right" if outward > 0.0 else "left"
		var texture := _wall_end_texture(side)
		if texture == null:
			continue
		var width := float(texture.get_width())
		var outside_px := WALL_END_OUTSIDE * 2.0
		var p0: Vector2 = edge[3]
		var p1: Vector2 = edge[4]
		var x_end := p0.x * cell
		var x_in := x_end - outward * (width - outside_px) * 0.5
		var x_out := x_end + outward * WALL_END_OUTSIDE
		# UV.x: px in the art (its outer side is the art's right for a right end, left for a left end).
		var u_in := 0.0 if outward > 0.0 else width
		var u_out := width if outward > 0.0 else 0.0
		var face := SHADE_SOUTH if is_zero_approx(float(band["slope"])) else (SHADE_SOUTH_WEST if float(band["slope"]) > 0.0 else SHADE_SOUTH_EAST)
		var shade := face * (SHADE_END_EAST if outward > 0.0 else SHADE_END_WEST)
		var arrays := _arrays_for(walls, WALL_STYLE + ":end-" + side)
		var corners := [[x_in, p0.y, u_in], [x_out, p0.y, u_out], [x_out, p1.y, u_out],
				[x_in, p0.y, u_in], [x_out, p1.y, u_out], [x_in, p1.y, u_in]]
		for corner: Array in corners:
			var x := float(corner[0])
			var y := float(corner[1])
			var uv := _band_uv(band, x / cell, y)
			arrays.add(Vector2(x, y * cell), Vector2(float(corner[2]), uv.y),
					Color(shade, _level_channel(float(band["top"]) - uv.x), uv.x * cell / 256.0, 1.0))


## A wall's (depth below its top edge in cells, texture v in world units) at point (x, y) in cells,
## its top edge carried on in a straight line past its own half-column.
func _band_uv(band: Dictionary, x: float, y: float) -> Vector2:
	var depth := y - (float(band["y_left"]) + float(band["slope"]) * (x - int(band["column"]) * 0.5))
	return Vector2(depth, depth * cell + float(posmod(int(band["top"]), 2)) * cell)


## The corner stones of a wall's `side` ("right" or "left") end, null without art.
func _wall_end_texture(side: String) -> Texture2D:
	var path := WALL_END_ART % [WALL_STYLE, side]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## One wall: its covered tris with UV (x, depth below the top edge + the course of its level),
## shaded by the way the face looks.
func _add_band(arrays: MeshData, index: int) -> void:
	var band: Dictionary = grid.bands[index]
	var column := int(band["column"])
	var slope := float(band["slope"])
	var shade := SHADE_SOUTH if is_zero_approx(slope) else (SHADE_SOUTH_WEST if slope > 0.0 else SHADE_SOUTH_EAST)
	var x_left := column * 0.5
	var y_left := float(band["y_left"])
	# Stacked walls show the same course at the same height: course = level of its top, mod 2.
	var course := float(posmod(int(band["top"]), 2)) * cell
	var top_level := float(band["top"])
	for s in range(int(band["start"]), int(band["end"]) + 1):
		var tri := grid.column_tri(column, s)
		for point in grid.tri_points(tri):
			var depth := point.y - (y_left + slope * (point.x - x_left))
			arrays.add(point * cell, Vector2(point.x * cell, depth * cell + course),
					Color(shade, _level_channel(top_level - depth), depth * cell / 256.0, 1.0))


## The foot of a wall that reaches its foot: the ground in front of it, growing up its base, or
## water lapping at it.
func _add_foot(feet: Dictionary, water: Dictionary, index: int) -> void:
	var band: Dictionary = grid.bands[index]
	if not bool(band["natural"]):
		return
	var column := int(band["column"])
	var end := int(band["end"])
	var below := grid.column_tri(column, end + 1)
	var name_of_ground := ""
	if grid.tri_band[below] >= 0 or grid.tri_level[below] < int(band["bottom"]):
		# Another wall starts right here (a terrace without a ledge): the ledge's own ground.
		name_of_ground = grid.tri_ground[grid.column_tri(column, end)]
	elif grid.tri_level[below] == int(band["bottom"]):
		name_of_ground = grid.tri_ground[below]
	var edge := ElevationGrid.column_edge(column, end)
	var x0 := column * 0.5
	var p0 := Vector2(x0, edge.x)
	var p1 := Vector2(x0 + 0.5, edge.x + edge.y * 0.5)
	if name_of_ground != TerrainMaterials.WATER:
		# Where the wall ends, the foot wraps the base of its corner stones.
		var open := _open_ends(band, end)
		if open.x:
			p0 -= Vector2(1.0, edge.y) * WALL_END_FRINGE / cell
		if open.y:
			p1 += Vector2(1.0, edge.y) * WALL_END_FRINGE / cell
	if name_of_ground == TerrainMaterials.WATER:
		_add_water_foot(_arrays_for(water, "water"), p0, p1, int(band["bottom"]))
	elif _has_fringe(name_of_ground, "foot"):
		_add_fringe_strip(_arrays_for(feet, name_of_ground + FRINGE_KEY), p0, p1, "foot", SHADOW_FOOT, int(band["bottom"]))
	elif _has_edge_art(name_of_ground):
		_add_sweep_strip(_arrays_for(feet, name_of_ground), p0, p1, -1, FOOT_OUT, FOOT_IN, TILE_RIM_UP, SHADOW_FOOT, int(band["bottom"]))


## Tops of a ground without fringe art: its terrain edge rims along each boundary edge (cells).
func _add_plain_rims(edges: Array[Dictionary], lips: Dictionary) -> void:
	for edge in edges:
		var name_of_ground := str(edge["ground"])
		if not _has_edge_art(name_of_ground):
			continue
		var from: Vector2 = edge["from"]
		var to: Vector2 = edge["to"]
		var level := int(edge["level"])
		var arrays := _arrays_for(lips, name_of_ground)
		var shadow := SHADOW_WALL_LIP if int(edge["mode"]) == ElevationRims.LIP else 0.0
		if is_equal_approx(from.x, to.x):
			# Vertical: the top lies left of the way along it, the rim points right of it.
			var toward := 1 if to.y < from.y else -1
			_add_side_strip(arrays, Vector2(from.x, minf(from.y, to.y)), Vector2(from.x, maxf(from.y, to.y)), toward,
					LIP_OUT, LIP_IN, TILE_RIM_RIGHT if toward > 0 else TILE_RIM_LEFT, shadow, level)
		else:
			var toward_down := to.x > from.x
			_add_sweep_strip(arrays, from if from.x < to.x else to, to if from.x < to.x else from, 1 if toward_down else -1,
					LIP_OUT, LIP_IN, TILE_RIM_DOWN if toward_down else TILE_RIM_UP, shadow, level)


## Rims over water: the top's own ground over the water surface's soft edge, which no shore tile
## hides there.
func _add_water_covers(rims_builder: ElevationRims, patches: Dictionary) -> void:
	for edge: Dictionary in rims_builder.boundary_edges():
		if int(edge["mode"]) != ElevationRims.RIM or grid.tri_ground[int(edge["x"])] != TerrainMaterials.WATER:
			continue
		var name_of_ground := str(edge["ground"])
		if not _sheets.has(name_of_ground):
			continue
		var from: Vector2 = (edge["from"] as Vector2) * cell
		var to: Vector2 = (edge["to"] as Vector2) * cell
		var dir := (to - from).normalized()
		# Into the top: left of the way along the edge.
		var into := Vector2(dir.y, -dir.x) * RIM_WATER_COVER
		_arrays_for(patches, name_of_ground).add_flat(PackedVector2Array([from, to, to + into]), Vector2.ZERO, Color.WHITE)
		_arrays_for(patches, name_of_ground).add_flat(PackedVector2Array([from, to + into, from + into]), Vector2.ZERO, Color.WHITE)


## Every tri of the elevated part of the world (and DEPTH_MARGIN cells around it) into the depth
## mesh: tops at their level, walls with their depth below the top edge; then the stairs' faces at
## their height, back to front. Returns the rect it covers (ground-layer space).
func _add_depth(depth: MeshData) -> Rect2:
	var low := Vector2i(grid.columns, grid.rows)
	var high := Vector2i(-1, -1)
	for index in grid.columns * grid.rows:
		if grid.cell_level[index] != 0:
			var c := Vector2i(index % grid.columns, index / grid.columns)
			low = Vector2i(mini(low.x, c.x), mini(low.y, c.y))
			high = Vector2i(maxi(high.x, c.x), maxi(high.y, c.y))
	for flight: ElevationStairs in stairs:
		low = Vector2i(mini(low.x, floori(flight.bounds.position.x / cell)), mini(low.y, floori(flight.bounds.position.y / cell)))
		high = Vector2i(maxi(high.x, floori(flight.bounds.end.x / cell)), maxi(high.y, floori(flight.bounds.end.y / cell)))
	if high.x < 0:
		return Rect2()
	# Walls hang up to 3 cells below what is painted.
	low = Vector2i(maxi(0, low.x - DEPTH_MARGIN), maxi(0, low.y - DEPTH_MARGIN))
	high = Vector2i(mini(grid.columns - 1, high.x + DEPTH_MARGIN), mini(grid.rows - 1, high.y + DEPTH_MARGIN + 3))
	for cy in range(low.y, high.y + 1):
		for cx in range(low.x, high.x + 1):
			var index := grid.cell_index(Vector2i(cx, cy))
			for tri in range(index * 8, index * 8 + 8):
				var points := grid.tri_points(tri)
				if grid.tri_band[tri] >= 0:
					var band: Dictionary = grid.bands[grid.tri_band[tri]]
					for point in points:
						var uv := _band_uv(band, point.x, point.y)
						depth.add(point * cell, Vector2.ZERO, ElevationOcclusion.encode(int(band["top"]), uv.x * cell))
				else:
					depth.add_flat(_world(points), Vector2.ZERO, ElevationOcclusion.encode(grid.tri_level[tri], 0.0))
	for flight: ElevationStairs in stairs:
		flight.add_depth(depth)
	return Rect2(Vector2(low) * cell, Vector2(high - low + Vector2i.ONE) * cell)


## The tops that can lie in a cast shadow: up to SHADOW_REACH cells right of and one cell below
## anything higher (a top, a wall's top, a flight of stairs).
func _add_receivers(arrays: MeshData, depth_rect: Rect2) -> void:
	if depth_rect.size == Vector2.ZERO:
		return
	var heights := PackedInt32Array()
	heights.resize(grid.columns * grid.rows)
	for index in heights.size():
		var high := ElevationGrid.MIN_LEVEL
		for tri in range(index * 8, index * 8 + 8):
			var band := grid.tri_band[tri]
			high = maxi(high, int(grid.bands[band]["top"]) if band >= 0 else grid.tri_level[tri])
		heights[index] = high
	for flight: ElevationStairs in stairs:
		var from := Vector2i(floori(flight.bounds.position.x / cell), floori(flight.bounds.position.y / cell))
		var to := Vector2i(floori(flight.bounds.end.x / cell), floori(flight.bounds.end.y / cell))
		for cy in range(maxi(0, from.y), mini(grid.rows - 1, to.y) + 1):
			for cx in range(maxi(0, from.x), mini(grid.columns - 1, to.x) + 1):
				var index := grid.cell_index(Vector2i(cx, cy))
				heights[index] = maxi(heights[index], flight.top)
	for cy in grid.rows:
		for cx in grid.columns:
			var index := grid.cell_index(Vector2i(cx, cy))
			var nearby := ElevationGrid.MIN_LEVEL
			for dy in [-1, 0]:
				for dx in range(-SHADOW_REACH, 1):
					var other := Vector2i(cx + dx, cy + dy)
					if grid.has_cell(other):
						nearby = maxi(nearby, heights[grid.cell_index(other)])
			for tri in range(index * 8, index * 8 + 8):
				if grid.tri_band[tri] >= 0 or grid.tri_level[tri] >= nearby:
					continue
				arrays.add_flat(_world(grid.tri_points(tri)), Vector2.ZERO, Color(1.0, 1.0, 1.0, _level_channel(grid.tri_level[tri])))


## A strip along a horizontal or diagonal edge p0 -> p1 (cells, p0.x < p1.x), swept vertically:
## `toward` 1 = its rim hangs down, -1 = it points up. UV = the edge tile's own pixels (the tile
## repeats every cell; an edge spans half a cell, so it never crosses the tile's wrap).
func _add_sweep_strip(arrays: MeshData, p0: Vector2, p1: Vector2, toward: int, reach_out: float, reach_in: float, tile: int, shadow: float, level: int) -> void:
	var tx0 := fposmod(p0.x * cell * 2.0, ART_TILE)
	var tx1 := tx0 + (p1.x - p0.x) * cell * 2.0
	# v: world units below the edge; outward distance = toward · v.
	var v_top := -reach_in if toward > 0 else -reach_out
	var v_bottom := reach_out if toward > 0 else reach_in
	var corners := [
		[p0, tx0, v_top], [p1, tx1, v_top], [p1, tx1, v_bottom],
		[p0, tx0, v_top], [p1, tx1, v_bottom], [p0, tx0, v_bottom],
	]
	for corner: Array in corners:
		var p: Vector2 = corner[0]
		var v := float(corner[2])
		arrays.add(p * cell + Vector2(0.0, v), Vector2(float(corner[1]), ART_TILE * 0.5 + v * 2.0), _strip_color(shadow, toward * v, tile, level))


## Water along a wall foot p0 -> p1 (cells, p0.x < p1.x), swept vertically: UV.y = height above
## the foot line (world units).
func _add_water_foot(arrays: MeshData, p0: Vector2, p1: Vector2, level: int) -> void:
	var corners := [[p0, -WATER_FOOT_IN], [p1, -WATER_FOOT_IN], [p1, WATER_FOOT_OUT],
			[p0, -WATER_FOOT_IN], [p1, WATER_FOOT_OUT], [p0, WATER_FOOT_OUT]]
	for corner: Array in corners:
		var p: Vector2 = corner[0]
		var h := float(corner[1])
		arrays.add(p * cell - Vector2(0.0, h), Vector2(p.x * cell, h), Color(1.0, 1.0, 1.0, _level_channel(level)))


## A quad from the edge q0 -> q1 (world) to the edge moved by `offset`: `color` at the edge, fading
## to transparent at the far side.
func _add_fade_quad(arrays: MeshData, q0: Vector2, q1: Vector2, offset: Vector2, color: Color) -> void:
	var clear := Color(color, 0.0)
	arrays.add(q0, Vector2.ZERO, color)
	arrays.add(q1, Vector2.ZERO, color)
	arrays.add(q1 + offset, Vector2.ZERO, clear)
	arrays.add(q0, Vector2.ZERO, color)
	arrays.add(q1 + offset, Vector2.ZERO, clear)
	arrays.add(q0 + offset, Vector2.ZERO, clear)


## A cliff fringe along a horizontal or diagonal edge p0 -> p1 (cells, p0.x < p1.x), swept
## vertically: the strip's edge row on the edge, a foot's fringe above it.
func _add_fringe_strip(arrays: MeshData, p0: Vector2, p1: Vector2, kind: String, shadow: float, level: int) -> void:
	var edge_row: float = FRINGE_EDGE_ROW[kind]
	var height: float = FRINGE_HEIGHT[kind]
	var toward := 1.0 if kind == "lip" else -1.0
	var v_top := -edge_row * 0.5
	var v_bottom := (height - edge_row) * 0.5
	var corners := [[p0, v_top], [p1, v_top], [p1, v_bottom], [p0, v_top], [p1, v_bottom], [p0, v_bottom]]
	for corner: Array in corners:
		var p: Vector2 = corner[0]
		var v := float(corner[1])
		arrays.add(p * cell + Vector2(0.0, v), Vector2(p.x * cell * 2.0, edge_row + v * 2.0),
				Color(shadow, (toward * v + 64.0) / 128.0, 0.0, _level_channel(level)))


## A strip along a vertical edge p0 -> p1 (cells, p0.y < p1.y), swept sideways: `toward` 1 = its
## rim points right (east), -1 = left.
func _add_side_strip(arrays: MeshData, p0: Vector2, p1: Vector2, toward: int, reach_out: float, reach_in: float, tile: int, shadow: float, level: int) -> void:
	var ty0 := fposmod(p0.y * cell * 2.0, ART_TILE)
	var ty1 := ty0 + (p1.y - p0.y) * cell * 2.0
	var u_left := -reach_in if toward > 0 else -reach_out
	var u_right := reach_out if toward > 0 else reach_in
	var corners := [
		[p0, ty0, u_left], [p0, ty0, u_right], [p1, ty1, u_right],
		[p0, ty0, u_left], [p1, ty1, u_right], [p1, ty1, u_left],
	]
	for corner: Array in corners:
		var p: Vector2 = corner[0]
		var u := float(corner[2])
		arrays.add(p * cell + Vector2(u, 0.0), Vector2(ART_TILE * 0.5 + u * 2.0, float(corner[1])), _strip_color(shadow, toward * u, tile, level))


## Strip vertex data: r = shadow strength, g = outward distance ((d + 64) / 128), b = tile / 15,
## a = the ground's level.
static func _strip_color(shadow: float, outward: float, tile: int, level: int) -> Color:
	return Color(shadow, (outward + 64.0) / 128.0, float(tile) / 15.0, _level_channel(level))


## A level (or a height between levels) in a vertex colour channel (elevation_light.gdshaderinc).
static func _level_channel(level: float) -> float:
	return (level + 4.0) / 8.0


# --- materials -----------------------------------------------------------------------------

func _ground_material(name_of_ground: String) -> Material:
	if not _sheets.has(name_of_ground):
		return null
	var material_of := ShaderMaterial.new()
	material_of.shader = GROUND_SHADER
	material_of.set_shader_parameter(&"ground_texture", _sheets[name_of_ground])
	material_of.set_shader_parameter(&"ground_period", cell * SHEET_CELLS)
	material_of.set_shader_parameter(&"ground_origin", _ground_origin())
	return material_of


## The water foot: the water surface's own mask and sheets (null where the ground has no mounted
## water surface, as in the editor).
func _water_foot_material() -> Material:
	var surface := ground.get_node_or_null(NodePath(WATER_SURFACE_NODE)) as CanvasItem
	var surface_material := surface.material as ShaderMaterial if surface != null else null
	if surface_material == null:
		return null
	var material_of := ShaderMaterial.new()
	material_of.shader = WATER_FOOT_SHADER
	for parameter: StringName in [&"water_mask", &"shallow_texture", &"deep_texture", &"grid_size", &"tile_size", &"texture_period"]:
		material_of.set_shader_parameter(parameter, surface_material.get_shader_parameter(parameter))
	material_of.set_shader_parameter(&"ground_origin", _ground_origin())
	return material_of


## The light along rims is added.
func _rim_material(_key: String) -> Material:
	var material_of := ShaderMaterial.new()
	material_of.shader = GLOW_SHADER
	return material_of


func _shade_material() -> Material:
	var material_of := ShaderMaterial.new()
	material_of.shader = SHADE_SHADER
	return material_of


func _cast_shadow_material() -> Material:
	if occlusion == null or occlusion.texture == null:
		return null
	var material_of := ShaderMaterial.new()
	material_of.shader = CAST_SHADOW_SHADER
	material_of.set_shader_parameter(&"elevation_depth", occlusion.texture)
	material_of.set_shader_parameter(&"depth_rect", occlusion.rect_uniform(occlusion.local_rect))
	material_of.set_shader_parameter(&"shadow_units", SHADOW_UNITS)
	material_of.set_shader_parameter(&"strength", SHADOW_STRENGTH)
	return material_of


## `style` is a wall style, or "<style>:end-right" / ":end-left" for its corner stones.
func _wall_material(style: String) -> Material:
	if style.contains(":end-"):
		var texture := _wall_end_texture(style.get_slice(":end-", 1))
		if texture == null:
			return null
		var end_material := ShaderMaterial.new()
		end_material.shader = WALL_END_SHADER
		end_material.set_shader_parameter(&"end_texture", texture)
		end_material.set_shader_parameter(&"end_size", Vector2(texture.get_size()))
		return end_material
	var path := WALL_ART % style
	if not ResourceLoader.exists(path):
		push_warning("Elevation: no wall art for '%s' (%s)" % [style, path])
		return null
	var texture := load(path) as Texture2D
	var material_of := ShaderMaterial.new()
	material_of.shader = WALL_SHADER
	material_of.set_shader_parameter(&"wall_texture", texture)
	# 2 px of art per world unit.
	material_of.set_shader_parameter(&"wall_size", Vector2(texture.get_size()) * 0.5)
	return material_of


## The flights of stairs: the stairs kit and the wall of WALL_STYLE (null without their art).
func _stairs_material() -> Material:
	var material_of := ShaderMaterial.new()
	material_of.shader = STAIRS_SHADER
	for part: String in ["tread", "riser", "coping", "wall"]:
		var path := WALL_ART % WALL_STYLE if part == "wall" else STAIRS_ART % [WALL_STYLE, part]
		if not ResourceLoader.exists(path):
			push_warning("Elevation: no stairs art '%s'" % path)
			return null
		var texture := load(path) as Texture2D
		material_of.set_shader_parameter(StringName(part + "_texture"), texture)
		material_of.set_shader_parameter(StringName(part + "_size"), Vector2(texture.get_size()))
	return material_of


func _strip_material(key: String, foot: bool) -> Material:
	if key.ends_with(FRINGE_KEY):
		return _fringe_material(key.trim_suffix(FRINGE_KEY), "foot" if foot else "lip")
	var name_of_ground := key
	if not _has_edge_art(name_of_ground):
		return null
	var edges := load(TerrainMaterials.edges_path(name_of_ground)) as Texture2D
	var material_of := ShaderMaterial.new()
	material_of.shader = STRIP_SHADER
	material_of.set_shader_parameter(&"edge_tiles", edges)
	material_of.set_shader_parameter(&"rim_weight", load(TerrainMaterials.rim_path(name_of_ground)))
	material_of.set_shader_parameter(&"atlas_size", Vector2(edges.get_size()))
	material_of.set_shader_parameter(&"ground_texture", _sheets[name_of_ground])
	material_of.set_shader_parameter(&"ground_period", cell * SHEET_CELLS)
	material_of.set_shader_parameter(&"ground_origin", _ground_origin())
	# A foot darkens its own ground where it meets the wall (contact shadow).
	material_of.set_shader_parameter(&"inner_shade", 0.35 if foot else 0.0)
	return material_of


func _fringe_material(name_of_ground: String, kind: String) -> Material:
	var texture := load(FRINGE_ART % [name_of_ground, kind]) as Texture2D
	if texture == null:
		return null
	var material_of := ShaderMaterial.new()
	material_of.shader = FRINGE_SHADER
	material_of.set_shader_parameter(&"strip", texture)
	material_of.set_shader_parameter(&"strip_size", Vector2(texture.get_size()))
	material_of.set_shader_parameter(&"inner_shade", 0.35 if kind == "foot" else 0.0)
	return material_of


# --- collision -----------------------------------------------------------------------------

func _build_collision() -> void:
	var old := get_node_or_null("Collision")
	if old != null:
		old.free()
	var holder := Node2D.new()
	holder.name = "Collision"
	add_child(holder)
	for level in range(ElevationGrid.MIN_LEVEL, ElevationGrid.MAX_LEVEL + 1):
		var segments := grid.collision_segments(level)
		for i in segments.size():
			segments[i] *= cell
		if not stairs.is_empty():
			segments = _with_stairs(segments, level)
		if segments.is_empty():
			continue
		var shape := ConcavePolygonShape2D.new()
		shape.segments = segments
		var body := StaticBody2D.new()
		body.name = "Level%d" % level
		body.collision_layer = level_bit(level)
		body.collision_mask = 0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
		holder.add_child(body)


## `segments` (a level's terrain outline, Elevation space) with the flights of stairs: the outline
## of what the level can walk on where stairs stand (their steps if it joins them; nothing else of
## them). Terrain segments away from every flight stay; near one, they, the flight's steps and its
## silhouette are cut where they cross, and each piece is kept where it parts walkable from blocked
## ground (`is_walkable` on either side of it).
func _with_stairs(segments: PackedVector2Array, level: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var near: Array = []
	for flight: ElevationStairs in stairs:
		near.append([])
	for i in range(0, segments.size(), 2):
		var a := segments[i]
		var b := segments[i + 1]
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(1.0)
		var touched := false
		for f in stairs.size():
			if (stairs[f] as ElevationStairs).bounds.intersects(box):
				(near[f] as Array).append([a, b])
				touched = true
		if not touched:
			out.append(a)
			out.append(b)
	var kept := {}
	for f in stairs.size():
		var flight: ElevationStairs = stairs[f]
		var grid_near: Array = near[f]
		# Away from the terrain's outline the ground around a flight is all one: nothing to trace
		# when the level can neither walk the flight nor meet it.
		if grid_near.is_empty() and not flight.joins(level) and (flight.blockers(level).is_empty() \
				or not grid.is_walkable_point(flight.bounds.get_center() / cell, level)):
			continue
		# Cut where the terrain's outline and the outlines of flights it touches cross it.
		var others: Array = grid_near.duplicate()
		for other: ElevationStairs in stairs:
			if other != flight and other.bounds.intersects(flight.bounds):
				others.append_array(other.outline_edges(level))
		var pieces: Array = []
		for piece: Array in flight.outline_pieces(level):
			pieces.append_array(split_edge(piece, others))
		var flight_edges := flight.outline_edges(level)
		for other_edge: Array in others.slice(grid_near.size()):
			flight_edges.append(other_edge)
		for edge: Array in grid_near:
			pieces.append_array(split_edge(edge, flight_edges))
		for piece: Array in pieces:
			var from: Vector2 = piece[0]
			var to: Vector2 = piece[1]
			var middle := (from + to) * 0.5
			# Probe either side close enough that a short piece's probes stay beside it.
			var normal := (to - from).orthogonal().normalized() * minf(0.5, from.distance_to(to) * 0.2)
			if _local_walkable(middle + normal, level) == _local_walkable(middle - normal, level):
				continue
			_keep_on_line(kept, from, to)
	# Pieces along one line (cut differently by overlapping edges) merge into whole segments.
	for direction_key: Vector2i in kept:
		for line: Array in kept[direction_key]:
			var d: Vector2 = line[0]
			var offset: Vector2 = line[1]
			var spans: Array = line[3]
			spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
			var current: Vector2 = spans[0]
			for i in range(1, spans.size() + 1):
				var next: Vector2 = spans[i] if i < spans.size() else Vector2(INF, INF)
				if i < spans.size() and next.x <= current.y + 0.05:
					current.y = maxf(current.y, next.y)
					continue
				out.append(offset + d * current.x)
				out.append(offset + d * current.y)
				current = next
	return _weld(out)


## `segments` with ends closer than 0.05 made one point: lines rebuilt apart meet exactly, so a body
## sliding along one never catches on the next one's end a hair inside its way.
static func _weld(segments: PackedVector2Array) -> PackedVector2Array:
	var points := {}
	for i in segments.size():
		var point := segments[i]
		var key := Vector2i(roundi(point.x * 20.0), roundi(point.y * 20.0))
		var found := false
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var near: Variant = points.get(key + Vector2i(dx, dy))
				if near != null and (near as Vector2).distance_to(point) < 0.05:
					segments[i] = near
					found = true
					break
			if found:
				break
		if not found:
			points[key] = point
	return segments


## Files the piece from -> to under its line in `lines` (direction key -> lines [direction, a
## point of the line, its offset, spans along it]); a piece within 0.3 of a line is on it.
static func _keep_on_line(lines: Dictionary, from: Vector2, to: Vector2) -> void:
	var d := (to - from).normalized()
	if d.x < -1e-6 or (absf(d.x) <= 1e-6 and d.y < 0.0):
		d = -d
	var key := Vector2i(roundi(d.x * 100.0), roundi(d.y * 100.0))
	if not lines.has(key):
		lines[key] = []
	var line: Array = []
	for candidate: Array in lines[key]:
		var normal := (candidate[0] as Vector2).orthogonal()
		var on_line: Vector2 = candidate[1]
		if absf((from - on_line).dot(normal)) < 0.3 and absf((to - on_line).dot(normal)) < 0.3:
			line = candidate
			break
	if line.is_empty():
		var c := d.orthogonal().dot(from)
		line = [d, d.orthogonal() * c, c, []]
		(lines[key] as Array).append(line)
	var along: Vector2 = line[0]
	var a := along.dot(from)
	var b := along.dot(to)
	(line[3] as Array).append(Vector2(minf(a, b), maxf(a, b)))


## The edge [a, b] cut where `others` cross it or end on it: its pieces [from, to] (none shorter
## than 0.05).
static func split_edge(edge: Array, others: Array) -> Array:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var cuts := PackedFloat32Array([0.0, 1.0])
	for other: Array in others:
		var c: Vector2 = other[0]
		var d: Vector2 = other[1]
		if c == a and d == b:
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
		if hit != null:
			cuts.append(_fraction_on(a, b, hit))
		for point: Vector2 in [c, d]:
			if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) < 0.01:
				cuts.append(_fraction_on(a, b, point))
	cuts.sort()
	var pieces: Array = []
	for k in cuts.size() - 1:
		var from := a.lerp(b, cuts[k])
		var to := a.lerp(b, cuts[k + 1])
		if from.distance_to(to) >= 0.05:
			pieces.append([from, to])
	return pieces


static func _fraction_on(a: Vector2, b: Vector2, point: Vector2) -> float:
	var length := a.distance_squared_to(b)
	return clampf((point - a).dot(b - a) / length, 0.0, 1.0) if length > 0.0 else 0.0


## `is_walkable` in Elevation space.
func _local_walkable(point: Vector2, level: int) -> bool:
	var rule := _stairs_rule(point, level)
	if rule >= 0:
		return rule == 1
	return grid.is_walkable_point(point / cell, level)

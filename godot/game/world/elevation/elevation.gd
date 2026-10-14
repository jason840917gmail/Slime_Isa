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
##            and rounded corner stones where a wall ends, in the wall style of the top they hang
##            from (painted on the `cliffs` layer, else picked by its ground: `band_styles`);
##   Rims     the light a top edge facing the upper left catches;
##   Water    water lapping at the foot of walls that stand in water (elevation_water_foot.gdshader);
##   Feet     the lower ground's border growing up the foot of each wall;
##   Lips     every top's border as one continuous strip of its ground's fringe: hanging over its
##            walls, a rim of tufts elsewhere, round at convex corners (elevation_rims.gd);
##   Ramps    the ramps' slopes as their ground (elevation_ramp.gd, elevation_ramp.gdshader), over
##            the walls they taper, then RampEnds (corner stones where a front ramp cuts a wall)
##            and RampFeet (the ground's foot along a slope's edge at a face); with them the top's
##            own ground over its lip where a flight of stairs leaves it (ElevationStairs.add_approach);
##   Stairs   the flights of stairs (elevation_stairs.gd), back to front in one mesh per colour
##            (elevation_stairs.gdshader, `_stairs_material`), and StairsFeet: the ground growing up
##            their side walls.
## A world whose ground layer has the metadata `cliff_look` = "sides" (`_sides_look`) draws Sides
## (sides/elevation_sides.gd) instead of Walls, Feet and Lips: walls on every side of a top (a
## narrow strip on the east and west sides, a thin band on the back), round front corners, back
## corners where the side wall starts with a slanted end, wobbling edges drawn from the grounds.
## The terrain is the master of every cliff top and foot: a ground's own cliff fringes
## (`asset/MAPS/elevation/<ground>-lip.png`, `-foot.png`, scripts/art/build-elevation-art.py,
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
## of it by none (`is_walkable`, the collision). A front flight is set into the wall over those
## cells, from its top edge to its foot; the others run out over the lower ground. Every flight is
## drawn in the colour of the road or ground at its ends (`_stairs_ground`, `_stairs_colour`).
##
## Ramps (elevation_ramp.gd, a flight without stone) are painted on every cell of lower ground they
## run over (`painted_ramps`), in the direction down the slope: a block of cells, its length the
## cells along that direction, its width the cells side by side. The terrain takes them as that
## lower ground too; the ramp joins it to the top right behind its top cells or to the top whose
## wall runs beside them (`_make_ramp`), and is drawn after the lips (Ramps, RampEnds, RampFeet), so
## it covers the wall below its slope: the wall tapers to nothing where the slope meets the top. Its
## open sides let a body step off onto the ground there (`_stairs_rule`, `_level_off_ramp`). Where
## its top end lies at the face's end and the top ends there too (`_top_ends_at`: a tip, not a
## plateau's corner) the cliff opens (ElevationRamp.opens): the top's rim does not turn around the
## end (`_closes_open_end`), and the ground beyond it takes no cast shadow (`_shadow_take`); no
## corner stones end a wall under any ramp (`_end_under_ramp`). A top one row thick that ramps join
## (a one-row open cliff, `_find_open_tops`) has no back rim and casts no shadow, and its ramps
## take none. Around it only walls collide (`_open_zone`): a body walks between its top, its ramps
## and the ground around them anywhere no wall stands, taking the level of where its feet are, so
## it stands at the cliff's level by the time it reaches the rim it jumps from.
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
const ElevationRamp := preload("res://game/world/elevation/elevation_ramp.gd")
const GroundSurface := preload("res://game/world/ground_surface.gd")
const ElevationFences := preload("res://game/world/elevation/fences/elevation_fences.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const TileColours := preload("res://game/ui/map/map_terrain.gd")
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
const RAMP_SHADER := preload("res://game/world/elevation/elevation_ramp.gdshader")
const ElevationSides := preload("res://game/world/elevation/sides/elevation_sides.gd")
const ElevationCache := preload("res://game/world/elevation/elevation_cache.gd")
## The baked cache (docs/godot/ELEVATION.md "Baked cache", elevation_cache.gd): one per world scene in
## CACHE_DIR, named after its path under WORLDS_DIR. Bump CACHE_VERSION when what the build makes
## changes (debug runs also compare the sources of CACHE_SCRIPTS, so a stale cache is rebuilt there).
const CACHE_DIR := "res://game/scenes/worlds/elevation_cache/"
const WORLDS_DIR := "res://game/scenes/worlds/"
const CACHE_VERSION := 2
const CACHE_SCRIPTS: PackedStringArray = [
	"res://game/world/elevation/elevation.gd", "res://game/world/elevation/elevation_grid.gd",
	"res://game/world/elevation/elevation_rims.gd", "res://game/world/elevation/elevation_stairs.gd",
	"res://game/world/elevation/elevation_ramp.gd", "res://game/world/elevation/elevation_mesh.gd",
	"res://game/world/elevation/sides/elevation_sides.gd",
]
## The drawing's groups, bottom to top.
const GROUP_NAMES: PackedStringArray = ["Patches", "Shade", "Shadows", "Walls", "Sides", "Rims", "Water", "Feet",
	"Lips", "Ramps", "RampEnds", "RampFeet", "Stairs", "StairsFeet"]
const SIDES_SHADER := preload("res://game/world/elevation/sides/elevation_sides.gdshader")
## Bucket size (world units) for cutting the sides look's collision edges (`_split_all`).
const SPLIT_BUCKET := 32.0
## A ground darker than this (its average colour's value) gets a light top edge outline in the sides
## look (`_sides_material`).
const DARK_GROUND := 0.32
## Cell size (world units) of the lookup of the sides look's shapes by place (`_side_cells`).
const SHAPE_CELL := 128.0
## How far (world units) a drawn wall's uneven foot may dip below the bottom step of a front flight
## of stairs and still be the ground the flight starts from (`_at_stairs_foot`).
const STAIRS_FOOT_SLACK := 12.0
## A wall style's art for the sides look (scripts/art/build-side-wall-art.py): its side strip and
## its corner stones; a style without them uses its wall art.
const SIDES_ART := "res://asset/MAPS/elevation/%s-%s.png"
const WATER_SURFACE_NODE := "WaterSurface"

const NODE_NAME := "Elevation"
const LEVEL_DATA_LAYER := "elevation_level"
const KIND_DATA_LAYER := "elevation_kind"
## Painted stairs (`elevation_kind`): "stairs-<direction>" (ElevationStairs.DIRECTIONS); plain
## "stairs" is "stairs-s". "stairs-<direction>-open" (the palette's second row, once an open
## landing) paints the same flight: since 2026-10-11 no flight has a landing.
const STAIRS_KIND := "stairs"
const OPEN_SUFFIX := "-open"
## Painted ramps (`elevation_kind`): "ramp-<direction>" (ElevationStairs.DIRECTIONS), the way down
## the slope.
const RAMP_KIND := "ramp"
## How far (cells) a ramp's painted cells may lie from the rim behind them, past the wall of each
## level of the drop, and how far across them the face of a top beside them is looked for.
const RAMP_RIM_SLACK := 0.75
const RAMP_FACE_REACH := 1.5
## How far a ramp's top end may move to meet the start of the face beside it, and its bottom end
## to meet the corner where that face turns into another face of the top (cells, either way).
const RAMP_FACE_SNAP := 1.0
## A ramp's top end where its face begins is an open end only where the top ends there too: within
## RAMP_TOP_REACH of that corner no top lies more than RAMP_TOP_BEYOND past the top end (cells; a
## 45° ridge's square tip reaches 0.35 past it, a plateau's side runs on).
const RAMP_TOP_REACH := 1.0
const RAMP_TOP_BEYOND := 0.45
## Steps (cells) of the searches along a ramp's sides, and of the search for the top or face it
## joins (finer: it finds an edge, then halves the step).
const RAMP_PROBE := 1.0 / 32.0
const RAMP_SEARCH_STEP := 1.0 / 64.0
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
	"stairsFootstepMs": 400.0, "stairsPerFootstep": 2.0, "stairsStepBob": 3.0, "stairsExit": 22.0,
	"stairsExitMs": 160.0, "stairsAlong": 0.35,
}
## Stairs are the player's passage only (docs/godot/ELEVATION.md "Stairs walk"; owner, 2026-10-14:
## "enemies or NPCs don't walk stairs, they stay in their levels; they do walk ramps"): every
## flight's steps stand on STAIRS_LAYER (physics layer 19), which every tracked body but the
## player (PLAYER_LAYER) collides with (`track`).
const STAIRS_LAYER := 1 << 18
const PLAYER_LAYER := 2
## A walking body's collision rect around its feet (player_slime.tscn BodyShape 30 x 26, slightly
## inset) and how far past its edge a ledge is looked for.
const BODY_HALF := Vector2(13.0, 12.0)
const RIM_PROBE := 6.0
## Open cliffs' seams (`_cut_open_seams`): the stretch of collision tested at once, and how far off
## it each side is probed (Elevation space).
const SEAM_STEP := 4.0
const SEAM_PROBE := 3.0
## The rect's corners and edge middles (times BODY_HALF, from its centre): the ledge probes.
const BODY_SIDES: Array[Vector2] = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0),
		Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)]
## `ledge_below` when there is no ledge.
const NO_LEDGE := -100
## Rows above the map a painted top may lie on (`cell_offset`): the highest wall (MAX_LEVEL −
## MIN_LEVEL courses) reaches no further.
const MAX_ROWS_ABOVE := 6
## Hop path samples (world units).
const HOP_STEP := 8.0
## How far a landing may be moved to find room (world units).
const LANDING_SEARCH_STEP := 4.0

## Wall and stairs art per style (scripts/art/build-elevation-art.py); the stairs kit: "<style>",
## "tread" / "riser" / "coping".
const WALL_ART := "res://asset/MAPS/elevation/%s-wall.png"
const STAIRS_ART := "res://asset/MAPS/elevation/%s-stairs-%s.png"
## A wall's style: the one painted on the world's `cliffs` layer (cliffs/cliff_layer.gd, data layer
## WALL_STYLE_DATA_LAYER) over the top it hangs from, else the ground on top's (the world's own
## choice, WORLD_WALL_STYLES_META, else GROUND_WALL_STYLES), else DEFAULT_WALL_STYLE; a style
## without wall art falls back to DEFAULT_WALL_STYLE.
const WALL_STYLE_DATA_LAYER := "wall_style"
const DEFAULT_WALL_STYLE := "meadow-rock"
## Ground layer metadata giving a world its own wall style per ground ({"highland": "storybook-rock"})
## and its own fringe art per ground ({"highland": "storybook-grass"}, FRINGE_ART): other worlds keep
## the defaults.
const WORLD_WALL_STYLES_META := &"cliff_wall_styles"
const WORLD_FRINGE_META := &"cliff_fringe"
## Ground layer metadata choosing how a world's cliffs look: SIDES_LOOK draws walls on every side
## (sides/elevation_sides.gd, docs/godot/ELEVATION.md "Side walls"); anything else the front walls.
const WORLD_CLIFF_LOOK_META := &"cliff_look"
const SIDES_LOOK := "sides"
const GROUND_WALL_STYLES := {
	"highland": "meadow-rock", "frozen": "snow-rock", "sanddessert": "sandstone",
	"forest-floor": "root-rock", "forest-moss": "mossy-rock", "amberleaf": "red-rock",
	"cavern-floor": "cave-rock", "crystal-floor": "crystal-rock", "town-cobble": "masonry",
}
## The stone kit of every flight of stairs: its treads, risers and (the coping row) the blocks of its
## posts and side walls, whose grain the stairs shader takes in the flight's colour.
const STAIRS_STYLE := "meadow-rock"
const STAIRS_BLOCK_PART := "coping"
## A flight's colour: a road at its foot or its top end (the foot's first), else the ground of the
## top it leaves, else the ground at its foot (`_stairs_ground`). That ground's average colour
## made paler stone: its saturation times STAIRS_SATURATION, its value STAIRS_VALUE.x +
## STAIRS_VALUE.y · value; STAIRS_NO_GROUND without one (`_stairs_colour`).
const STAIRS_ROAD_GROUNDS: PackedStringArray = ["town-cobble", "sanddessert", "forest-floor"]
const STAIRS_SATURATION := 0.45
const STAIRS_VALUE := Vector2(0.38, 0.6)
const STAIRS_NO_GROUND := Color(0.62, 0.6, 0.56)
## Corner stones where a wall ends ("<style>", "right" or "left"); their end line lies
## WALL_END_OUTSIDE world units inside the art's outer side (build-elevation-art.py WALL_END_OUTSIDE,
## 10 px), and the wall's foot reaches WALL_END_FRINGE past it.
const WALL_END_ART := "res://asset/MAPS/elevation/%s-wall-end-%s.png"
const WALL_END_OUTSIDE := 5.0
const WALL_END_FRINGE := 8.0
## The end stones turn away from the light on a wall's east end, towards it on its west end.
const SHADE_END_EAST := 0.9
const SHADE_END_WEST := 1.04
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
## Cliff fringe art per ground (or the world's choice, WORLD_FRINGE_META) and kind ("lip", "foot"),
## the strip row its edge line runs on and the strip's height (scripts/art/build-elevation-art.py
## EDGE_ROWS, LAYOUT).
const FRINGE_ART := "res://asset/MAPS/elevation/%s-%s.png"
const FRINGE_EDGE_ROW := {"lip": 96.0, "foot": 80.0}
const FRINGE_HEIGHT := {"lip": 160.0, "foot": 128.0}
## Mesh key suffix of fringe strips (the rest is the ground).
const FRINGE_KEY := ":fringe"
## A ramp's foot fringe (RampFeet, elevation_fringe.gdshader `fade_by_b`): the art rows at its top
## that fade out (`top_fade`), and the face's height (world units) over which it fades in from
## nothing at the ramp's top end, so the lip's hanging ferns end on the slope there.
const RAMP_FOOT_TOP_FADE := 40.0
const RAMP_FOOT_FADE_IN := 40.0
## The sides look's foot along a ramp's slope (`_add_sides_ramp_foot`): its shadow's reach over the
## slope (world units) and strength.
const SIDES_RAMP_FOOT_OUT := 12.0
## …and the face's height (world units) over which it fades in from the ramp's top end: short, so
## the line runs on almost to the tip.
const SIDES_RAMP_FOOT_FADE_IN := 6.0
const SIDES_RAMP_FOOT_SHADOW := 0.25
## How far apart (world units along the slope) `_ramp_wall_span` looks for the wall beside a ramp.
const RAMP_FOOT_PROBE := 4.0
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
## The flights of stairs (ElevationStairs), back to front, and the ramps among them.
var stairs: Array = []
var _ramps: Array[ElevationRamp] = []
## The terrain's depth map and the bodies' occlusion.
var occlusion: ElevationOcclusion
## Bodies in the air (a hop or a drop): body -> depth (elevation_occlusion.gd) while they fly.
var flights: Dictionary = {}
## The fences along painted rims (fences/elevation_fences.gd, docs/godot/FENCES.md), null without.
var fences: ElevationFences
## The wall style of each wall (index into `grid.bands`).
var band_styles := PackedStringArray()

## Rows painted above the map (off-map tops whose walls hang into the map): the grid starts this
## many rows above the map's first row, and this node sits as far up (grid cell = map cell + offset).
var cell_offset := Vector2i.ZERO
## Set by the bake tool (tools/bake_elevation.gd): build everything, never load a cache.
static var ignore_cache := false
## True when the last build came from the baked cache.
var from_cache := false
## What the build makes, recorded while it builds (a game build without a valid cache), for
## `save_cache`.
var _cache_record: ElevationCache
## The build scripts' sources' hash, worked out once per run (`_code_hash`).
static var _code := "?"
var _queued := false
## style -> whether its wall art exists; WALL_END_ART path -> its texture (null without art), loaded
## once.
var _wall_art: Dictionary = {}
var _wall_end_art: Dictionary = {}
## level -> its terrain outline (world units) while the collision is built (`_terrain_outline`).
var _outlines: Dictionary = {}
var _collide := false
## ground name -> its 19x19 sheet texture, and the atlas source it is (for its average colour).
var _sheets: Dictionary = {}
var _sources: Dictionary = {}
## The one-row open cliffs of the last drawing (`_find_open_tops`): grid index -> level.
var _open_tops: Dictionary = {}
## The ground around them where only walls collide (`_find_open_zone`): grid index ->
## Vector2i(the cliff's level, the level its ramps start from); and its bounds (Elevation space).
var _open_zone: Dictionary = {}
## With the sides look: every top's drawn shape (ElevationSides.shapes, Elevation space). The lower
## levels walk and collide by it (`_terrain_walkable`, `_with_sides`), not by the model's cells.
var _side_shapes: Array = []
## The shapes whose bounds touch each SHAPE_CELL-unit cell (Vector2i -> indices into _side_shapes).
var _side_cells: Dictionary = {}
var _open_rect := Rect2()
## The lower ground behind each one-row open cliff, inside its outline (`_find_open_inner`): cell
## index -> the cliff's level. A side of the cliff facing it is open like its back (no wall, no rim).
var _open_inner: Dictionary = {}
## Sheet texture path -> its average colour (`_ground_colour`), for the run.
static var _ground_colours: Dictionary = {}


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
	return _sibling_with_data(ground_layer, LEVEL_DATA_LAYER)


## The cliffs layer beside `ground_layer` (a sibling TileMapLayer whose tile set has the
## `wall_style` data layer, cliffs/cliff_tileset.tres), or null.
static func find_cliff_layer(ground_layer: TileMapLayer) -> TileMapLayer:
	return _sibling_with_data(ground_layer, WALL_STYLE_DATA_LAYER)


static func _sibling_with_data(ground_layer: TileMapLayer, data_layer: String) -> TileMapLayer:
	var parent := ground_layer.get_parent() if ground_layer != null else null
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var candidate := child as TileMapLayer
		if candidate != null and candidate != ground_layer and candidate.tile_set != null \
				and candidate.tile_set.has_custom_data_layer_by_name(data_layer):
			return candidate
	return null


## Wall styles painted beside `ground_layer`: Vector2i cell -> style (only painted cells).
static func painted_wall_styles(ground_layer: TileMapLayer) -> Dictionary:
	var painted := find_cliff_layer(ground_layer)
	var styles := {}
	if painted == null:
		return styles
	for cell_pos: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell_pos)
		if data != null:
			styles[cell_pos] = str(data.get_custom_data(WALL_STYLE_DATA_LAYER))
	return styles


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


## Painted levels beside `ground_layer`: Vector2i cell -> int (only painted cells). A stairs or ramp
## cell takes the level of the ground it leads down to (the next cell along its direction that is
## not of its kind): the terrain is built as if it were not there, the flight or ramp stands on it.
static func painted_levels(ground_layer: TileMapLayer) -> Dictionary:
	var painted := find_layer(ground_layer)
	var levels := {}
	if painted == null:
		return levels
	var stairs_cells := painted_stairs(ground_layer)
	var ramp_cells := painted_ramps(ground_layer)
	for cell: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell)
		if data != null and not stairs_cells.has(cell) and not ramp_cells.has(cell):
			levels[cell] = int(data.get_custom_data(LEVEL_DATA_LAYER))
	# [cells, how far (squared, cells) a run of them is followed]: a ramp may be long.
	for kind: Array in [[stairs_cells, 64], [ramp_cells, 1024]]:
		var cells: Dictionary = kind[0]
		for cell: Vector2i in cells:
			var step := stairs_step(str(cells[cell]))
			var below := cell + step
			while cells.has(below) and below.distance_squared_to(cell) < int(kind[1]):
				below += step
			if levels.has(below):
				levels[cell] = levels[below]
	return levels


## Painted ramps beside `ground_layer`: Vector2i cell -> kind ("ramp-<direction>").
static func painted_ramps(ground_layer: TileMapLayer) -> Dictionary:
	var painted := find_layer(ground_layer)
	var cells := {}
	if painted == null or not painted.tile_set.has_custom_data_layer_by_name(KIND_DATA_LAYER):
		return cells
	for cell: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell)
		if data == null:
			continue
		var kind := str(data.get_custom_data(KIND_DATA_LAYER))
		if kind.begins_with(RAMP_KIND + "-") and ElevationStairs.DIRECTIONS.has(stairs_direction(kind)):
			cells[cell] = kind
	return cells


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


## The direction (ElevationStairs.DIRECTIONS key) of a stairs or ramp kind.
static func stairs_direction(kind: String) -> String:
	return kind.trim_prefix(STAIRS_KIND + "-").trim_prefix(RAMP_KIND + "-").trim_suffix(OPEN_SUFFIX)


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


## Bodies on stairs or a ramp take the level of the stretch they stand on; a body that steps off a
## ramp's open side takes the level of the ground there; every body's sprites get its depth. A body
## of a level that may not stand where its feet touch a ramp (its high end, the top level's alone:
## the feet of a body walking past a tip touch its top corner, beside the wall they meet there)
## keeps its level: nothing climbs onto a ramp's highest part from below.
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
			var own := int(bodies[body])
			var flight := stairs_at(local)
			if flight is ElevationRamp and not flight.walks_level(local, own):
				pass
			elif flight != null:
				var level := flight.level_at(local, own)
				if level != own and not flights.has(walker):
					track(walker, level)
				if is_nan(depth):
					depth = flight.depth_at(local) + global_position.y
			elif not _ramps.is_empty() and not flights.has(walker):
				var off := _level_off_ramp(local, own)
				if off != own:
					track(walker, off)
		if not _open_zone.is_empty() and not flights.has(walker):
			var own := int(bodies[body])
			var across := _level_across_open(walker.global_position, own)
			if across != own:
				track(walker, across)
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
	var levels := painted_levels(ground)
	# Tops painted above the map: only their walls (and lips) reach into it.
	var above := 0
	for c: Vector2i in levels:
		if c.y < 0 and c.x >= 0 and c.x < columns:
			above = maxi(above, -c.y)
	above = mini(above, MAX_ROWS_ABOVE)
	cell_offset = Vector2i(0, above)
	position = Vector2(0.0, -above * cell)
	var names := _ground_names()
	for x in columns:
		if names.has(Vector2i(x, 0)):
			for y in range(-above, 0):
				names[Vector2i(x, y)] = names[Vector2i(x, 0)]
	grid = ElevationGrid.build(columns, rows + above, _shifted(levels), _shifted(names), setting("behindDepth") / cell)
	_build_stairs()
	_open_tops = _find_open_tops()
	_mark_open_tops()
	_find_open_zone()
	_find_open_inner()
	_build_wall_styles()
	var cache := _load_cache() if _collide else null
	from_cache = cache != null
	_cache_record = ElevationCache.new() if _collide and not from_cache else null
	if from_cache:
		_apply_cache(cache)
	else:
		_build_drawing()
	if _collide:
		if from_cache:
			_make_collision(cache.collision)
		else:
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
	if _cache_record != null and _saves_on_its_own():
		save_cache()


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
	return _terrain_walkable(local, level)


## The terrain's walkability at `point` (Elevation space) for `level`, stairs aside: the model's, and
## with the sides look the drawn shapes' (`_sides_walkable`).
func _terrain_walkable(point: Vector2, level: int) -> bool:
	var base := grid.is_walkable_point(point / cell, level)
	return base if _side_shapes.is_empty() else _sides_walkable(point, level, base)


## With the sides look, `level`'s walkability at `point` near the tops: a top of `level` ends at its
## drawn round corners (the model's square corner past one is not walkable); above `level`, a drawn
## wall is solid (a side strip stands on ground the model calls walkable), and where the model blocks
## a point for a higher top drawn round (the square corner past a round one, its wall below the drawn
## foot) the point is the ground below that top's wall. `base`: the model's answer.
func _sides_walkable(point: Vector2, level: int, base: bool) -> bool:
	var reopen := false
	for index: int in _side_cells.get(Vector2i(floori(point.x / SHAPE_CELL), floori(point.y / SHAPE_CELL)), []):
		var shape: Dictionary = _side_shapes[index]
		var top_level := int(shape["level"])
		if top_level < level or int(shape["lowest"]) > level or not (shape["bounds"] as Rect2).has_point(point):
			continue
		if top_level == level:
			if base and _in_zone(shape, point):
				return false
			continue
		var walls: Array = shape["walls"]
		var wall_bounds: Array = shape["wall_bounds"]
		for w in walls.size():
			if (wall_bounds[w] as Rect2).has_point(point) and Geometry2D.is_point_in_polygon(point, walls[w]):
				return _at_stairs_foot(point, level)
		if not base and not reopen and (_in_zone(shape, point) or _in_model_wall(point, top_level)):
			reopen = _below_at(shape, point) == level
	return base or reopen


## True when `point` (on a drawn wall) lies just below the bottom step of a front flight of stairs
## that climbs from `level`: the wall's uneven foot dips under the step there, and that strip is the
## ground the flight starts from (as a wall it closed the foot of the stairs to `level`).
func _at_stairs_foot(point: Vector2, level: int) -> bool:
	for flight: ElevationStairs in stairs:
		if flight.in_face and flight.bottom == level and not flight is ElevationRamp 				and flight.walks(point - Vector2(0.0, STAIRS_FOOT_SLACK)):
			return true
	return false


## True when `point` lies between one of `shape`'s round outer corners and the model's square corner.
static func _in_zone(shape: Dictionary, point: Vector2) -> bool:
	for zone: PackedVector2Array in shape["zones"]:
		if Geometry2D.is_point_in_polygon(point, zone):
			return true
	return false


## True when the model has a wall hanging from a top of `top_level` at `point`.
func _in_model_wall(point: Vector2, top_level: int) -> bool:
	var tri := grid.tri_at(point / cell)
	if tri < 0 or grid.tri_band[tri] < 0:
		return false
	return int(grid.bands[grid.tri_band[tri]]["top"]) == top_level


## The level under `shape`'s wall nearest `point`.
func _below_at(shape: Dictionary, point: Vector2) -> int:
	if not bool(shape["mixed"]):
		return int(shape["below"])
	var nearest := _nearest_point(shape["points"], point)
	return (shape["belows"] as PackedInt32Array)[nearest] if nearest >= 0 else int(shape["below"])


static func _nearest_point(points: PackedVector2Array, point: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for k in points.size():
		var d := points[k].distance_squared_to(point)
		if d < best_distance:
			best_distance = d
			best = k
	return best


## The flight of stairs (never a ramp) whose steps hold the world point `world_point`, or null: the
## stairs walk starts there (player.gd `_enter_stairs`).
func flight_at(world_point: Vector2) -> ElevationStairs:
	var local := world_point - global_position
	for flight: ElevationStairs in stairs:
		if not flight is ElevationRamp and flight.walks(local):
			return flight
	return null


## The flight of stairs (or ramp) whose steps (or slope) hold `point` (Elevation space), or null.
func stairs_at(point: Vector2) -> ElevationStairs:
	for flight: ElevationStairs in stairs:
		if flight.walks(point):
			return flight
	return null


## The level a body of `level` takes at `point` (Elevation space), off every slope: on a ramp's
## skirt its bottom level, just past its open sides the level of the ground there (the body stepped
## off), elsewhere its own.
func _level_off_ramp(point: Vector2, level: int) -> int:
	var near_ramp := false
	for ramp in _ramps:
		if ramp.skirts(point):
			return ramp.bottom
		near_ramp = near_ramp or ramp.reaches(point)
	return grid.walkable_level(point / cell, level) if near_ramp else level


## Stairs at `point` (Elevation space) for a body of `level`: 1 walkable (steps of a flight it
## joins), 0 blocked (what of a flight stands at its level's height), -1 no stairs there. What of a
## flight is only drawn over the ground there (standing higher, in front) blocks nothing: it hides
## the body (the depth map). A ramp's slope counts as steps (its high end the top level's alone);
## its skirt is ground of its bottom level, onto which a body on the slope may step too (below the
## high end); just past its open sides a body on it may step off onto ground of a level from the
## ramp's bottom up to its own (1 there). The way just past a flight's ends (ElevationStairs.overhang:
## into the top, past a side or back flight's bottom end) is walkable by every level it joins where
## the ground of that end is (1 there): a body on the steps reaches over them before it takes the
## next level.
func _stairs_rule(point: Vector2, level: int) -> int:
	var rule := -1
	var off_ramp := false
	var over_end := false
	for flight: ElevationStairs in stairs:
		if not flight.bounds.has_point(point):
			continue
		if flight.walks(point):
			# Its steps (a ramp's slope): walkable by the levels it joins.
			if flight.walks_level(point, level):
				return 1
			rule = 0
		elif flight.blocks(point, level):
			rule = 0
		elif not off_ramp and flight is ElevationRamp:
			var ramp := flight as ElevationRamp
			if ramp.skirts(point):
				off_ramp = ramp.skirt_walks(point, level)
			elif ramp.lets_off(point, level):
				off_ramp = _ground_between(point, ramp.bottom, level)
		elif not over_end and flight.joins(level):
			var end_of := flight.overhang(point)
			if end_of != 0:
				over_end = grid.is_walkable_point(point / cell, flight.top if end_of == 1 else flight.bottom)
	if rule < 0 and (off_ramp or over_end):
		return 1
	return rule


## True when the terrain at `point` (Elevation space) is walkable at a level from `low` to `high`.
func _ground_between(point: Vector2, low: int, high: int) -> bool:
	for level in range(low, high + 1):
		if grid.is_walkable_point(point / cell, level):
			return true
	return false


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
## ledge drops to the highest of those lower grounds. The face a ramp tapers is a wall (as in Zelda)
## where the probe straight ahead meets it; the other probes over it count for nothing, so the rim
## drops normally once the body is past the face's end. Around a one-row open cliff (`_open_zone`)
## the tapered face is a rim like any other: a body drops over it. A body on a ramp's slope below its high end
## stands lower than its level's ground: a wall beside it whose top is higher than the slope there
## (the wall a front ramp cuts through) goes up, whatever its level.
func ledge_below(feet: Vector2, level: int, direction: Vector2, reach: float = RIM_PROBE) -> int:
	if grid == null or direction == Vector2.ZERO:
		return NO_LEDGE
	var unit := direction.normalized()
	var centre := feet - Vector2(0.0, BODY_HALF.y)
	var lower := NO_LEDGE
	var ahead := _probe_ahead(unit)
	var on_slope := _height_on_slope(feet - global_position) if not _ramps.is_empty() else NAN
	for side: Vector2 in BODY_SIDES:
		var offset := side * BODY_HALF
		if offset.dot(unit) <= 0.0:
			continue
		var probe := centre + offset + unit * reach
		if fences != null and fences.blocks_point(probe, level):
			return NO_LEDGE
		# An open cliff's tapered face drops like any rim (`_open_zone`).
		if not _ramps.is_empty() and _on_tapered_face(probe - global_position) and _open_pair(probe - global_position) == Vector2i.ZERO:
			if side == ahead:
				return NO_LEDGE
			continue
		if is_walkable(probe, level) or _open_across(feet, probe, level):
			continue
		if not is_nan(on_slope) and _wall_top_at(probe - global_position) > on_slope:
			return NO_LEDGE
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
## out: a side drop beside a wall lands past the wall, not hidden behind the hill. A ramp's slope
## takes a drop only right where it falls, and only below where it started (it lands at the level
## of the slope there); a drop never lands on the slope it starts from, and the search for room
## passes over slopes (`_landing_level`).
func drop_target(feet: Vector2, level: int, direction: Vector2, outward: float = -1.0, reach: float = RIM_PROBE) -> Dictionary:
	var lower := ledge_below(feet, level, direction, reach)
	if lower == NO_LEDGE:
		return {}
	var unit := direction.normalized()
	var drop := level - lower
	var out := outward if outward >= 0.0 else setting("dropOutward")
	var landing := feet + unit * out + Vector2(0.0, float(drop) * cell)
	var up_reach := float(drop) * cell + cell
	var from_ramp: ElevationRamp = null
	if not _ramps.is_empty():
		from_ramp = stairs_at(feet - global_position) as ElevationRamp
	var step := 0.0
	while step <= up_reach:
		var up := landing - Vector2(0.0, step)
		var to := lower if _ramps.is_empty() else _landing_level(up, level, lower, from_ramp, step == 0.0)
		if to >= ElevationGrid.MIN_LEVEL and body_fits(up, to):
			return {"feet": up, "level": to, "drop": level - to}
		var out_more := landing + unit * step
		if step > 0.0 and step <= cell:
			to = lower if _ramps.is_empty() else _landing_level(out_more, level, lower, from_ramp, false)
			if to >= ElevationGrid.MIN_LEVEL and body_fits(out_more, to):
				return {"feet": out_more, "level": to, "drop": level - to}
		step += LANDING_SEARCH_STEP
	return {}


## The level a drop from `level` towards `lower` lands at on `point` (world): `lower`, or on a
## ramp's slope (only `where_it_falls`, the spot straight below, never the slope `from_ramp` it
## starts from, and never a slope that leads back up to `level`: off the tip of a 45° arm the body
## would fall onto its ramp and climb straight back) the slope's level there when that is below
## `level`; MIN_LEVEL − 1 when it may not land there.
func _landing_level(point: Vector2, level: int, lower: int, from_ramp: ElevationRamp, where_it_falls: bool) -> int:
	var local := point - global_position
	for ramp in _ramps:
		if ramp.walks(local):
			var there := ramp.level_at(local, lower)
			if ramp == from_ramp or not where_it_falls or there >= level or ramp.top >= level:
				return ElevationGrid.MIN_LEVEL - 1
			return there
	return lower


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


## True when `point` (Elevation space) lies on the visible part of a face a ramp tapers.
func _on_tapered_face(point: Vector2) -> bool:
	for ramp in _ramps:
		if ramp.on_face(point):
			return true
	return false


## The height (world units, 64 per level) of the slope a body stands on with its feet at `point`
## (Elevation space), below a ramp's high end; NAN off every slope and on a high end (the top's).
func _height_on_slope(point: Vector2) -> float:
	var ramp := stairs_at(point) as ElevationRamp
	if ramp == null:
		return NAN
	var s := ramp.s_at(point)
	if is_nan(s) or s < ramp.high_end:
		return NAN
	return ElevationStairs.LEVEL * ramp.bottom + ramp.nosing(s)


## The height of the top edge of the wall at `point` (Elevation space), -INF off every wall.
func _wall_top_at(point: Vector2) -> float:
	var tri := grid.tri_at(point / cell)
	if tri < 0 or grid.tri_band[tri] < 0:
		return -INF
	return ElevationStairs.LEVEL * int(grid.bands[grid.tri_band[tri]]["top"])


## The ledge probe (BODY_SIDES) straight ahead of a body going `unit`.
static func _probe_ahead(unit: Vector2) -> Vector2:
	var best := BODY_SIDES[0]
	for side: Vector2 in BODY_SIDES:
		if side.normalized().dot(unit) > best.normalized().dot(unit):
			best = side
	return best


## The level of the lower ground at `point` for a body of `level`: a lower top, or the foot of a
## wall at or below its level; MIN_LEVEL - 1 when there is none.
func _lower_level_at(point: Vector2, level: int) -> int:
	var tri := grid.tri_at((point - global_position) / cell)
	if tri < 0 or _stairs_rule(point - global_position, level) >= 0:
		return ElevationGrid.MIN_LEVEL - 1
	# The sides look: past a top's round corner (the model's square corner) lies the ground below.
	var local := point - global_position
	for shape: Dictionary in _side_shapes:
		if int(shape["level"]) == level and (shape["bounds"] as Rect2).has_point(local) and _in_zone(shape, local):
			return _below_at(shape, local)
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
	var stairs_bit := STAIRS_LAYER if body.collision_layer & PLAYER_LAYER == 0 else 0
	body.collision_mask = (body.collision_mask & ~all_level_bits() & ~STAIRS_LAYER) | level_bit(level) | stairs_bit
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
	_sources.clear()
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
					_sources[name_of_ground] = source
		names[cell_pos] = by_source[source_id]
	return names


func _has_edge_art(name_of_ground: String) -> bool:
	return _sheets.has(name_of_ground) and name_of_ground != TerrainMaterials.WATER \
			and ResourceLoader.exists(TerrainMaterials.edges_path(name_of_ground)) \
			and ResourceLoader.exists(TerrainMaterials.rim_path(name_of_ground))


func _has_fringe(name_of_ground: String, kind: String) -> bool:
	return name_of_ground != "" and ResourceLoader.exists(FRINGE_ART % [_fringe_art(name_of_ground), kind])


## The fringe art of a ground: the world's choice (WORLD_FRINGE_META), else the ground's own.
func _fringe_art(name_of_ground: String) -> String:
	var own: Dictionary = ground.get_meta(WORLD_FRINGE_META, {}) if ground != null else {}
	return str(own.get(name_of_ground, name_of_ground))


func _ground_origin() -> Vector2:
	return ground.global_position if ground.is_inside_tree() else ground.position


## `painted` (map cell -> value) in grid cells (`cell_offset`).
func _shifted(painted: Dictionary) -> Dictionary:
	if cell_offset == Vector2i.ZERO:
		return painted
	var out := {}
	for c: Vector2i in painted:
		out[c + cell_offset] = painted[c]
	return out


# --- drawing -------------------------------------------------------------------------------

func _build_drawing() -> void:
	_free_drawing()
	var patches := {}
	var shade := {}
	var shadows := {}
	var walls := {}
	var rims := {}
	var water := {}
	var feet := {}
	var lips := {}
	var depth := MeshData.new()
	var ramps := _ramps
	var sides := _sides_look()
	_side_shapes = []
	_side_cells = {}
	for patch: Dictionary in grid.patches:
		var name_of_ground := str(patch["ground"])
		if _sheets.has(name_of_ground) and name_of_ground != TerrainMaterials.WATER:
			_arrays_for(patches, name_of_ground).add_flat(_world(grid.tri_points(int(patch["tri"]))), Vector2.ZERO, Color.WHITE)
	for tri in grid.tri_level.size():
		var level := grid.tri_level[tri]
		if level < 0 and grid.tri_band[tri] < 0:
			_arrays_for(shade, "holes").add_flat(_world(grid.tri_points(tri)), Vector2.ZERO, Color(_level_channel(level), 0.0, 0.0, 1.0))
	for index in grid.bands.size():
		if not sides:
			_add_band(_arrays_for(walls, band_styles[index]), index)
		if ramps.is_empty() or not _foot_under_ramp(index, ramps):
			_add_foot(feet, water, index)
	if not sides:
		_add_wall_ends(walls, ramps)
	var rims_builder := ElevationRims.new()
	# Where a cliff opens at a ramp's top end, its top's rim does not turn around the end; a one-row
	# open cliff has no back rim (`_is_back_rim`).
	var open_ends := _open_ramps()
	var left_out := func(edge: Dictionary) -> bool:
		return _is_back_rim(edge) or _is_inner_side(edge) or (not open_ends.is_empty() and _closes_open_end(edge, open_ends))
	var leftover := rims_builder.build(grid, cell, func(g: String) -> bool: return _has_fringe(g, "lip"),
			lips, FRINGE_KEY, _arrays_for(rims, "glow"), depth, SHADOW_WALL_LIP,
			func(level: int, dy: float) -> Color: return ElevationOcclusion.encode(level, dy), left_out)
	_add_plain_rims(leftover, lips)
	_add_water_covers(rims_builder, patches)
	# Flights are drawn back to front; a run of flights of one colour (the ground they take it from)
	# shares a mesh ("<ground>-<run>").
	var stairs_meshes := {}
	var stairs_feet := {}
	var ramp_meshes := {}
	var ramp_feet := {}
	var run_ground := ""
	var run_key := ""
	for flight: ElevationStairs in stairs:
		if flight is ElevationRamp:
			var ramp := flight as ElevationRamp
			if _sheets.has(ramp.ground_name):
				ramp.hard_edge = sides
				ramp.add_mesh(_arrays_for(ramp_meshes, ramp.ground_name))
				if sides:
					_add_sides_ramp_foot(ramp_feet, ramp)
				else:
					_add_ramp_foot(ramp_feet, ramp)
			if ramp.rimmed and _sheets.has(ramp.top_ground):
				ramp.add_landing(_arrays_for(ramp_meshes, ramp.top_ground))
			if ramp.opens() and _sheets.has(ramp.top_ground):
				ramp.add_cap_top(_arrays_for(ramp_meshes, ramp.top_ground), _top_tris_in(ramp.cap_rect, ramp.top))
			continue
		if flight.ground_name != run_ground or run_key == "":
			run_ground = flight.ground_name
			run_key = "%s-%d" % [run_ground, stairs_meshes.size()]
		flight.add_mesh(_arrays_for(stairs_meshes, run_key))
		for foot: Array in flight.feet:
			_add_stairs_foot(stairs_feet, foot)
		# The top's ground over its lip where the flight leaves it, so the lip breaks there.
		if _sheets.has(flight.top_ground) and flight.top_ground != TerrainMaterials.WATER:
			flight.add_approach(_arrays_for(ramp_meshes, flight.top_ground))
	var depth_rect := _add_depth(depth)
	_add_receivers(_arrays_for(shadows, "cast"), depth_rect)
	if occlusion == null:
		occlusion = ElevationOcclusion.new()
		occlusion.name = "Occlusion"
		add_child(occlusion)
	# The depth is drawn in this node's space (moved up by rows painted above the map).
	occlusion.build(depth, depth_rect, _ground_origin() + position)
	if _cache_record != null:
		_cache_record.depth_vertices = depth.vertices
		_cache_record.depth_colors = depth.colors
		_cache_record.depth_rect = depth_rect
	_add_group("Patches", patches)
	_add_group("Shade", shade)
	# The model's cast shadows follow its square cells: the sides look casts its own, round, along
	# the walls' feet (sides/elevation_sides.gd).
	if not sides:
		_add_group("Shadows", shadows)
	if sides:
		_add_sides(rims_builder, left_out)
	else:
		_add_group("Walls", walls)
	# The light along the model's rims follows its square outline: the sides look rounds its tops.
	if not sides:
		_add_group("Rims", rims)
	# The water lapping at a wall follows the model's square feet: the sides look draws its own foam
	# along the round ones.
	if not sides:
		_add_group("Water", water)
	if not sides:
		_add_group("Feet", feet)
		_add_group("Lips", lips)
	if not ramp_meshes.is_empty():
		_add_group("Ramps", ramp_meshes)
	if not ramps.is_empty():
		var ramp_ends := {}
		_add_ramp_cut_ends(ramp_ends, ramps)
		_add_group("RampEnds", ramp_ends)
		_add_group("RampFeet", ramp_feet)
	_add_group("Stairs", stairs_meshes)
	_add_group("StairsFeet", stairs_feet)


## True when the world draws its cliffs with walls on every side (WORLD_CLIFF_LOOK_META).
func _sides_look() -> bool:
	return ground != null and str(ground.get_meta(WORLD_CLIFF_LOOK_META, "")) == SIDES_LOOK


## Sides (sides/elevation_sides.gd): every top's walls on all its sides, its lip and its foot, one
## mesh per level and art, lowest level first. `left_out` drops the edges no rim runs along (an
## open end, a one-row open cliff's back), so no wall hangs there either.
func _add_sides(rims_builder: ElevationRims, left_out: Callable) -> void:
	var holder := _add_holder("Sides")
	var edges: Array[Dictionary] = []
	for edge: Dictionary in rims_builder.boundary_edges():
		if not bool(left_out.call(edge)):
			edges.append(edge)
	var painted := _shifted(painted_wall_styles(ground))
	var style_of := func(edge: Dictionary) -> String:
		var across := int(edge["x"])
		if int(edge["mode"]) == ElevationRims.LIP and grid.tri_band[across] >= 0:
			return band_styles[grid.tri_band[across]]
		var from: Vector2 = edge["from"]
		var way: Vector2 = (edge["to"] as Vector2) - from
		return _wall_style_at(from + way * 0.5, Vector2(way.y, -way.x).normalized(), int(edge["level"]), painted)
	# The top's ground and the ground under the wall (its own where that has no sheet: water).
	var grounds_of := func(edge: Dictionary) -> PackedStringArray:
		var top := str(edge["ground"])
		var low := grid.tri_ground[int(edge["x"])]
		if not _sheets.has(low) and low != TerrainMaterials.WATER:
			low = top
		return PackedStringArray([top, low])
	var wall_width_of := func(style: String) -> float:
		var texture := load(WALL_ART % style) as Texture2D
		return float(texture.get_width()) if texture != null else 0.0
	var builder := ElevationSides.new()
	var under_ramp := func(point: Vector2) -> bool:
		for ramp in _ramps:
			if ramp.bounds.has_point(point) and ramp.covers(point):
				return true
		return false
	var meshes := builder.build(grid, cell, edges, style_of, grounds_of, wall_width_of,
			under_ramp if not _ramps.is_empty() else Callable())
	_side_shapes = builder.shapes
	_index_side_shapes()
	if _cache_record != null:
		for shape: Dictionary in _side_shapes:
			var stored := shape.duplicate()
			stored.erase("edges")
			_cache_record.side_shapes.append(stored)
	for entry: Dictionary in meshes:
		var arrays: MeshData = entry["arrays"]
		if not arrays.is_empty():
			_add_instance(holder, "Sides", str(entry["key"]), arrays.to_mesh())


## `_side_cells`: the shapes whose bounds touch each SHAPE_CELL cell.
func _index_side_shapes() -> void:
	_side_cells = {}
	for index in _side_shapes.size():
		var box: Rect2 = _side_shapes[index]["bounds"]
		for y in range(floori(box.position.y / SHAPE_CELL), floori(box.end.y / SHAPE_CELL) + 1):
			for x in range(floori(box.position.x / SHAPE_CELL), floori(box.end.x / SHAPE_CELL) + 1):
				var at := Vector2i(x, y)
				if not _side_cells.has(at):
					_side_cells[at] = []
				(_side_cells[at] as Array).append(index)


# --- baked cache (docs/godot/ELEVATION.md "Baked cache") ------------------------------------

## The cache file of this world's scene ("" when it has none: not instanced from a scene file).
func cache_path() -> String:
	var owner_node := ground.owner if ground != null else null
	var scene := owner_node.scene_file_path if owner_node != null else ""
	if scene == "":
		return ""
	var relative := scene.trim_prefix(WORLDS_DIR) if scene.begins_with(WORLDS_DIR) else scene.trim_prefix("res://")
	return CACHE_DIR + relative.trim_suffix(".tscn").replace("/", "__") + ".res"


## The painting the build follows: the elevation, ground and cliffs layers' cells, the ground's
## metadata, the elevation settings and CACHE_VERSION, hashed.
func _cache_key() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(layer.tile_map_data)
	context.update(ground.tile_map_data)
	var cliffs := find_cliff_layer(ground)
	if cliffs != null:
		context.update(cliffs.tile_map_data)
	var settings := []
	for key: String in DEFAULTS:
		settings.append(setting(key))
	var meta := [CACHE_VERSION, cell, ground.get_meta("columns", 0), ground.get_meta("rows", 0),
		ground.get_meta(WORLD_CLIFF_LOOK_META, ""), ground.get_meta(WORLD_WALL_STYLES_META, {}),
		ground.get_meta(WORLD_FRINGE_META, {}), settings]
	context.update(var_to_str(meta).to_utf8_buffer())
	return context.finish().hex_encode()


## The hash of CACHE_SCRIPTS' sources in a debug run from the project (where they can be read), ""
## elsewhere (an exported game trusts its caches).
static func _code_hash() -> String:
	if _code != "?":
		return _code
	_code = ""
	if not OS.is_debug_build() or OS.has_feature("template"):
		return _code
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path in CACHE_SCRIPTS:
		var source := FileAccess.get_file_as_string(path)
		if source == "":
			return _code
		context.update(source.to_utf8_buffer())
	_code = context.finish().hex_encode()
	return _code


## This world's baked cache when it matches the painting (and, in a debug run, the build scripts),
## else null.
func _load_cache() -> ElevationCache:
	if ignore_cache:
		return null
	var path := cache_path()
	if path == "" or not ResourceLoader.exists(path):
		return null
	var cache := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ElevationCache
	if cache == null or cache.key != _cache_key():
		return null
	var code := _code_hash()
	if code != "" and cache.code != code:
		return null
	return cache


## The drawing, the depth map and the sides look's shapes from `cache`.
func _apply_cache(cache: ElevationCache) -> void:
	_free_drawing()
	if occlusion == null:
		occlusion = ElevationOcclusion.new()
		occlusion.name = "Occlusion"
		add_child(occlusion)
	var depth := MeshData.new()
	depth.vertices = cache.depth_vertices
	depth.colors = cache.depth_colors
	var uvs := PackedVector2Array()
	uvs.resize(cache.depth_vertices.size())
	depth.uvs = uvs
	occlusion.build(depth, cache.depth_rect, _ground_origin() + position)
	_side_shapes = cache.side_shapes
	_index_side_shapes()
	for group: Array in cache.groups:
		var holder := _add_holder(str(group[0]))
		for item: Array in group[1]:
			_add_instance(holder, str(group[0]), str(item[0]), item[1] as Mesh)


## Saves what the last build made as this world's cache (`cache_path`). OK, or why not.
func save_cache() -> Error:
	if _cache_record == null:
		return ERR_UNAVAILABLE
	var path := cache_path()
	if path == "":
		return ERR_FILE_BAD_PATH
	_cache_record.key = _cache_key()
	_cache_record.code = _code_hash()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	return ResourceSaver.save(_cache_record, path, ResourceSaver.FLAG_COMPRESS)


## True when a build without a valid cache saves one by itself: a game run from the project (not an
## exported game, a headless run or a tool script, which bake on purpose).
static func _saves_on_its_own() -> bool:
	return OS.is_debug_build() and not OS.has_feature("template") and DisplayServer.get_name() != "headless" \
			and (Engine.get_main_loop() as Object).get_script() == null


## The flights of stairs from the painted stairs cells: a run of cells side by side along the rim
## with the same kind is one flight. It leaves the rim where the higher ground behind its cells
## begins, from that ground's level down to theirs; a column of old-style stairs cells counts once.
## Then the ramps (`_build_ramps`, also listed in `_ramps`).
func _build_stairs() -> void:
	stairs.clear()
	_ramps.clear()
	var cells := _shifted(painted_stairs(ground))
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
				run_cells.size())
		flight.occlude(_tops_around(flight.bounds, top))
		_stairs_ground(flight)
		stairs.append(flight)
	_build_ramps()
	stairs.sort_custom(func(a: ElevationStairs, b: ElevationStairs) -> bool: return a.bounds.end.y < b.bounds.end.y)


## The grounds at a flight's two ends, a quarter cell past them (the top it leaves, the ground it
## leads onto): its `top_ground`, and the ground it takes its colour from (`ground_name`): a road at
## either end (STAIRS_ROAD_GROUNDS, the foot's first), else the top's ground, else the foot's.
func _stairs_ground(flight: ElevationStairs) -> void:
	var height := ElevationStairs.LEVEL * (flight.top - flight.bottom)
	var at := func(point: Vector2) -> String:
		var tri := grid.tri_at(point / cell)
		return grid.tri_ground[tri] if tri >= 0 else ""
	var high := str(at.call(flight.screen_of(Vector3(-cell * 0.25, 0.0, height))))
	var low := str(at.call(flight.screen_of(Vector3(flight.end + cell * 0.25, 0.0, 0.0))))
	flight.top_ground = high
	if STAIRS_ROAD_GROUNDS.has(low):
		flight.ground_name = low
	elif STAIRS_ROAD_GROUNDS.has(high) or (high != "" and high != TerrainMaterials.WATER):
		flight.ground_name = high
	else:
		flight.ground_name = low


## The ramps from the painted ramp cells (`painted_ramps`), into `stairs`: a block of cells with one
## kind is one ramp. Its top cells are the run side by side (across its direction; along the
## diagonal for a 45° ramp) with no cell of the kind behind them, its length the most cells along
## its direction from one of them.
func _build_ramps() -> void:
	var cells := _shifted(painted_ramps(ground))
	var done := {}
	var keys := cells.keys()
	keys.sort()
	for start: Vector2i in keys:
		if done.has(start):
			continue
		var kind := str(cells[start])
		var step := stairs_step(kind)
		if str(cells.get(start - step, "")) == kind:
			continue
		var side := Vector2i(1, 0) if step.x == 0 else (Vector2i(0, 1) if step.y == 0 else Vector2i(1, -step.x * step.y))
		var tops: Array[Vector2i] = [start]
		var next := start + side
		while str(cells.get(next, "")) == kind and str(cells.get(next - step, "")) != kind:
			tops.append(next)
			next += side
		var length := 0
		for top_cell in tops:
			var count := 0
			var at := top_cell
			while str(cells.get(at, "")) == kind:
				done[at] = true
				count += 1
				at += step
			length = maxi(length, count)
		var ramp := _make_ramp(stairs_direction(kind), tops, length)
		if ramp == null:
			push_warning("Elevation: the ramp painted at %s leads to no higher ground (paint it at the foot of a wall, or below a rim)" % [tops[0] - cell_offset])
			continue
		ramp.ground_name = _ramp_ground(tops, step, length)
		if ramp.rimmed:
			# The top's ground just behind the rim it leaves (its landing covers that top's lip).
			var tri := grid.tri_at((ramp.rim - ramp.dir * 8.0) / cell)
			ramp.top_ground = grid.tri_ground[tri] if tri >= 0 else ramp.ground_name
		elif ramp.opens():
			# The top's ground just inside the face where it opens (its cap covers that top there).
			var tri := grid.tri_at(ramp.screen_of(Vector3(8.0, ramp.near * (ramp.half + 8.0), ElevationStairs.LEVEL * (ramp.top - ramp.bottom))) / cell)
			ramp.top_ground = grid.tri_ground[tri] if tri >= 0 else ramp.ground_name
		ramp.occlude(_tops_around(ramp.bounds, ramp.top))
		stairs.append(ramp)
		_ramps.append(ramp)


## A ramp down towards `direction` from the cells `tops` (side by side), `length` cells long, or
## null when it leads to no higher ground. Positions in cells; a painted cell lies on the screen of
## its own (the bottom) level, the ramp's frame on the ground (y + the level).
func _make_ramp(direction: String, tops: Array[Vector2i], length: int) -> ElevationRamp:
	var along: Vector2 = ElevationStairs.DIRECTIONS[direction][0]
	var step_cells := along.length()
	var unit := along / step_cells
	var across := Vector2(-unit.y, unit.x)
	var bottom := grid.level_of_cell(tops[0])
	var centre := Vector2.ZERO
	for top_cell in tops:
		centre += Vector2(top_cell) + Vector2(0.5, 0.5)
	centre /= tops.size()
	var half_cells := ElevationStairs.HALF_CELL * tops.size() / cell
	var floor_of := Vector2(0.0, bottom)
	# The back of the top cells and the front of the last ones, on the ground.
	var back := centre - unit * step_cells * 0.5 + floor_of
	var front := back + unit * step_cells * length
	var top := ElevationGrid.MIN_LEVEL - 1
	var base := back
	var rimmed := false
	# A rim right behind the top cells: past one wall course per level of the drop (a front ramp),
	# right at them (a back or side ramp).
	var rim := _ramp_search(centre, -unit, step_cells * 0.5 + ElevationGrid.MAX_LEVEL - bottom + RAMP_RIM_SLACK, bottom, false)
	if rim.z >= ElevationGrid.MIN_LEVEL and Vector2(rim.x, rim.y).distance_to(centre) <= step_cells * 0.5 + rim.z - bottom + RAMP_RIM_SLACK:
		top = int(rim.z)
		base = Vector2(rim.x, rim.y + rim.z)
		rimmed = true
	# The face of a top beside the cells: the wall the ramp runs along. Searched across the arrow
	# (along the other diagonal for a 45° ramp) from the cells' middle and a quarter step either
	# way along it, so a search line through a cell corner still meets the face.
	var face := Vector4(0.0, 0.0, ElevationGrid.MIN_LEVEL - 1, 0.0)
	var reach := half_cells + ElevationGrid.MAX_LEVEL - bottom + RAMP_FACE_REACH
	for way: float in [1.0, -1.0]:
		for along_by: float in [0.0, -0.25, 0.25]:
			var from := centre + unit * step_cells * along_by
			var found := _ramp_search(from, across * way, reach, bottom, true)
			if found.z < ElevationGrid.MIN_LEVEL:
				continue
			# Its distance across from the cells' middle line.
			var distance := absf((Vector2(found.x, found.y) - centre).dot(across))
			if face.z < ElevationGrid.MIN_LEVEL or distance < absf((Vector2(face.x, face.y) - centre).dot(across)):
				face = Vector4(found.x, found.y, found.z, way)
	var near := 0.0
	var at_face_end := false
	var top_ends := false
	if face.z >= ElevationGrid.MIN_LEVEL and (top < ElevationGrid.MIN_LEVEL or int(face.z) == top):
		var u := across * face.w
		# The face's foot on the ground; the ramp lies beside it, away from the top.
		var distance := (Vector2(face.x, face.y + face.z) - (centre + floor_of)).dot(u)
		if absf(distance - half_cells) <= RAMP_FACE_REACH:
			near = face.w
			var shift := u * (distance - half_cells)
			base += shift
			front += shift
			if top < ElevationGrid.MIN_LEVEL:
				top = int(face.z)
				# Its top end where the face begins (a tip), when that is near.
				var begins := _face_begins(base, unit, u * half_cells, top)
				if not is_nan(begins):
					base += unit * begins
					at_face_end = true
					top_ends = _top_ends_at(base + u * half_cells - Vector2(0.0, top), unit, top)
	if top <= bottom:
		return null
	if near != 0.0 and not rimmed:
		# Its bottom end where the face beside it turns a corner into another face of the top (where
		# a 45° arm meets the main wall), when that is near: the slope reaches the ground there.
		var side := across * near * half_cells
		var slope := _face_slope((base + front) * 0.5, side, top)
		if not is_nan(slope):
			var turns := _face_turns(front, unit, side, top, slope)
			if not is_nan(turns):
				front += unit * turns
	var length_cells := (front - base).dot(unit)
	if length_cells <= 0.25:
		return null
	var face_span := Vector2.ZERO
	if near != 0.0:
		face_span = _face_span(base, unit, across * near * half_cells, top, length_cells)
	return ElevationRamp.create_ramp(direction, base * cell, top, bottom, half_cells * cell, length_cells * cell, near,
			face_span.x * cell, face_span.y * cell, rimmed, at_face_end, top_ends)


## From `from` (cells) along `way` (unit) up to `reach` cells: the first top higher than `level`
## (not a wall), refined to its edge: Vector3(x, y, its level); z = MIN_LEVEL - 1 when none. With
## `through_wall`, only a top reached across a wall counts (the face of a top beside a ramp).
func _ramp_search(from: Vector2, way: Vector2, reach: float, level: int, through_wall: bool) -> Vector3:
	var none := Vector3(0.0, 0.0, ElevationGrid.MIN_LEVEL - 1)
	var higher := func(at: Vector2) -> int:
		var tri := grid.tri_at(at)
		return grid.tri_level[tri] if tri >= 0 and grid.tri_band[tri] < 0 and grid.tri_level[tri] > level else ElevationGrid.MIN_LEVEL - 1
	var walled := false
	var lo := 0.0
	var hi := -1.0
	var steps := ceili(reach / RAMP_SEARCH_STEP)
	for i in range(1, steps + 1):
		var at := from + way * (i * RAMP_SEARCH_STEP)
		var tri := grid.tri_at(at)
		if tri >= 0 and grid.tri_band[tri] >= 0 and int(grid.bands[grid.tri_band[tri]]["top"]) > level:
			walled = true
		if int(higher.call(at)) >= ElevationGrid.MIN_LEVEL:
			if through_wall and not walled:
				return none
			lo = (i - 1) * RAMP_SEARCH_STEP
			hi = i * RAMP_SEARCH_STEP
			break
	if hi < 0.0:
		return none
	for _i in 8:
		var mid := (lo + hi) * 0.5
		if int(higher.call(from + way * mid)) >= ElevationGrid.MIN_LEVEL:
			hi = mid
		else:
			lo = mid
	var edge := from + way * hi
	return Vector3(edge.x, edge.y, int(higher.call(edge + way * 0.01)))


## True when the near side of a ramp (its middle line at `point` on the ground, cells; `side` from
## the middle to the near side) runs at the face of a top of `level` there: a wall of that top right
## below its edge.
func _face_at(point: Vector2, side: Vector2, level: int) -> bool:
	return not is_nan(_face_slope(point, side, level))


## True when the top of `level` ends at the corner where the face beside a ramp begins (`corner`,
## cells, on screen at the top's height; `unit` down the ramp): within RAMP_TOP_REACH of the corner
## nothing of it lies more than RAMP_TOP_BEYOND beyond the ramp's top end. The corner is then a
## ridge's or an arm's tip, or the end of a face where the top's side runs on along the ramp, and
## the cliff opens there (ElevationRamp.opens); at a plateau's corner the top's side runs on beyond
## the top end, and its rim stays.
func _top_ends_at(corner: Vector2, unit: Vector2, level: int) -> bool:
	for ring in range(1, 5):
		var radius := RAMP_TOP_REACH * ring / 4.0
		for k in 64:
			var point := corner + Vector2.from_angle(TAU * k / 64.0) * radius
			if (point - corner).dot(unit) > -RAMP_TOP_BEYOND:
				continue
			var tri := grid.tri_at(point)
			if tri >= 0 and grid.tri_band[tri] < 0 and grid.tri_level[tri] >= level:
				return false
	return true


## The slope of that face (its wall's top edge: 0 a south face, ±1 a 45° one) at `point`, NAN
## where there is none (`_face_at`).
func _face_slope(point: Vector2, side: Vector2, level: int) -> float:
	var edge := point + side - Vector2(0.0, level)
	# Just below the top edge: the wall hangs straight down from it (a 45° face begins at its tip).
	var tri := grid.tri_at(edge + Vector2(0.0, 0.05))
	if tri < 0 or grid.tri_band[tri] < 0 or int(grid.bands[grid.tri_band[tri]]["top"]) != level:
		return NAN
	return float(grid.bands[grid.tri_band[tri]]["slope"])


## Where (cells along `unit` from `front`) the face beside a ramp's bottom end turns a corner into
## another face of its top (a 45° arm meeting the main wall), when that lies within
## RAMP_FACE_SNAP; NAN when it runs on, ends, or turns further away. `slope`: the face's slope
## along the ramp.
func _face_turns(front: Vector2, unit: Vector2, side: Vector2, level: int, slope: float) -> float:
	var last := NAN
	var s := -RAMP_FACE_SNAP
	while s <= RAMP_FACE_SNAP + 1e-4:
		var here := _face_slope(front + unit * s, side, level)
		if is_equal_approx(here, slope):
			last = s
		elif not is_nan(last):
			if is_nan(here):
				return NAN
			# Refined between the last step on this face and the first on the other.
			var lo := last
			var hi := s
			for _i in 10:
				var mid := (lo + hi) * 0.5
				if is_equal_approx(_face_slope(front + unit * mid, side, level), slope):
					lo = mid
				else:
					hi = mid
			return lo
		s += RAMP_PROBE
	return NAN


## Where (cells along `unit` from `base`) the face beside a ramp begins, when that lies within
## RAMP_FACE_SNAP of its top end; NAN when the face runs on past it or is not there.
func _face_begins(base: Vector2, unit: Vector2, side: Vector2, level: int) -> float:
	if _face_at(base - unit * RAMP_FACE_SNAP, side, level):
		return NAN
	var s := -RAMP_FACE_SNAP
	while s <= RAMP_FACE_SNAP:
		if _face_at(base + unit * s, side, level):
			# Refined between the last step without the face and this one.
			var lo := s - RAMP_PROBE
			var hi := s
			for _i in 10:
				var mid := (lo + hi) * 0.5
				if _face_at(base + unit * mid, side, level):
					hi = mid
				else:
					lo = mid
			return lo
		s += RAMP_PROBE
	return NAN


## The stretch (cells along the ramp from its top end) its near side runs at the face of its top:
## Vector2(from, to), the first unbroken one.
func _face_span(base: Vector2, unit: Vector2, side: Vector2, level: int, length: float) -> Vector2:
	var from := NAN
	var to := 0.0
	var s := 0.0
	while s <= length + 1e-4:
		if _face_at(base + unit * s, side, level):
			if is_nan(from):
				# A face that begins within a step of the top end begins at it (`_face_begins`
				# put the top end a hair before the face).
				from = s if s > RAMP_PROBE * 1.5 else 0.0
			to = s
		elif not is_nan(from):
			break
		s += RAMP_PROBE
	return Vector2.ZERO if is_nan(from) else Vector2(from, minf(length, to + RAMP_PROBE))


## The ground a ramp is made of: its lower ground's (the cell past its bottom end), else its top
## cells'.
func _ramp_ground(tops: Array[Vector2i], step: Vector2i, length: int) -> String:
	for at: Vector2i in [tops[0] + step * length, tops[0] + step * (length - 1), tops[0]]:
		if grid.has_cell(at) and grid.cell_ground[grid.cell_index(at)] != "":
			return grid.cell_ground[grid.cell_index(at)]
	return ""


## The wall style of every wall (`band_styles`): the style of the top the wall hangs from.
func _build_wall_styles() -> void:
	var painted := _shifted(painted_wall_styles(ground))
	band_styles.resize(grid.bands.size())
	for index in grid.bands.size():
		var band: Dictionary = grid.bands[index]
		# The middle of the wall's top edge, in its half-column.
		var middle := Vector2(int(band["column"]) * 0.5 + 0.25, float(band["y_left"]) + float(band["slope"]) * 0.25)
		band_styles[index] = _wall_style_at(middle, Vector2.UP, int(band["top"]), painted)


## The wall style of the top of `level` that begins at `edge` (cells) and lies towards `into`: the
## style painted on its cell (a little in, else half a cell in: a corner triangle a chamfer raised
## belongs to the painted cell across the corner), else its ground's (the world's choice first);
## DEFAULT_WALL_STYLE for a style without wall art.
func _wall_style_at(edge: Vector2, into: Vector2, level: int, painted: Dictionary) -> String:
	var style := ""
	for reach: float in [0.05, 0.5]:
		var point := edge + into * reach
		var at := Vector2i(floori(point.x), floori(point.y))
		if painted.has(at) and grid.has_cell(at) and grid.cell_level[grid.cell_index(at)] == level:
			style = str(painted[at])
			break
	if style == "":
		var tri := grid.tri_at(edge + into * 0.05)
		var name_of_ground := grid.tri_ground[tri] if tri >= 0 else ""
		var own: Dictionary = ground.get_meta(WORLD_WALL_STYLES_META, {}) if ground != null else {}
		style = str(own.get(name_of_ground, GROUND_WALL_STYLES.get(name_of_ground, DEFAULT_WALL_STYLE)))
	if not _wall_art.has(style):
		_wall_art[style] = ResourceLoader.exists(WALL_ART % style)
		if not bool(_wall_art[style]):
			push_warning("Elevation: no wall art for the style '%s' (%s)" % [style, WALL_ART % style])
	return style if bool(_wall_art[style]) else DEFAULT_WALL_STYLE


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


func _add_group(group_name: String, groups: Dictionary) -> void:
	var holder := _add_holder(group_name)
	for key: String in groups:
		var arrays: MeshData = groups[key]
		if not arrays.is_empty():
			_add_instance(holder, group_name, key, arrays.to_mesh())


## A group's node (and its entry in the cache being recorded).
func _add_holder(group_name: String) -> Node2D:
	var holder := Node2D.new()
	holder.name = group_name
	add_child(holder)
	if _cache_record != null:
		_cache_record.groups.append([group_name, []])
	return holder


## A mesh of group `group_name` with the material made for `key` (`_material_for`; none: left out),
## recorded for the cache.
func _add_instance(holder: Node2D, group_name: String, key: String, mesh: Mesh) -> void:
	var material_of := _material_for(group_name, key)
	if material_of == null:
		return
	var instance := MeshInstance2D.new()
	instance.name = key.replace("|", " ")
	instance.mesh = mesh
	instance.material = material_of
	holder.add_child(instance)
	if _cache_record != null:
		(_cache_record.groups[_cache_record.groups.size() - 1][1] as Array).append([key, mesh])


## The material of group `group_name`'s mesh for `key` (null: the mesh is not drawn).
func _material_for(group_name: String, key: String) -> Material:
	match group_name:
		"Patches":
			return _ground_material(key)
		"Shade":
			return _shade_material()
		"Shadows":
			return _cast_shadow_material()
		"Walls", "RampEnds":
			return _wall_material(key)
		"Sides":
			# "<level>|<style>|<top ground>|<lower ground>" (ElevationSides.build).
			var parts := key.split("|")
			return _sides_material(parts[1], parts[2], parts[3]) if parts.size() == 4 else null
		"Rims":
			return _rim_material(key)
		"Water":
			return _water_foot_material()
		"Feet", "StairsFeet":
			return _strip_material(key, true)
		"Lips":
			return _strip_material(key, false)
		"Ramps":
			return _ramp_material(key)
		"RampFeet":
			return _sides_material(DEFAULT_WALL_STYLE, key, key) if _sides_look() else _ramp_foot_material(key)
		"Stairs":
			return _stairs_material(key.left(key.rfind("-")))
	return null


func _free_drawing() -> void:
	for group_name in GROUP_NAMES:
		var old := get_node_or_null(NodePath(group_name))
		if old != null:
			old.free()


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
## its courses on the wall's courses (the same UV as the wall). None where a ramp tapers the wall to
## nothing (`ramps`: the end lies under its slope or on the face it tapers).
func _add_wall_ends(walls: Dictionary, ramps: Array[ElevationRamp] = []) -> void:
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
		if not ramps.is_empty() and _end_under_ramp(((edge[3] as Vector2) + (edge[4] as Vector2)) * 0.5 * cell - Vector2(outward * 2.0, 0.0), ramps):
			continue
		_add_wall_end(walls, band_index, edge[3], edge[4], outward)


## The corner stones of wall `band_index` over its vertical edge p0 -> p1 (cells), its outer side
## towards `outward` (1: the wall's east end, −1: its west end).
func _add_wall_end(walls: Dictionary, band_index: int, p0: Vector2, p1: Vector2, outward: float) -> void:
	var band: Dictionary = grid.bands[band_index]
	var side := "right" if outward > 0.0 else "left"
	var style := band_styles[band_index]
	var texture := _wall_end_texture(style, side)
	if texture == null:
		return
	var width := float(texture.get_width())
	var outside_px := WALL_END_OUTSIDE * 2.0
	var x_end := p0.x * cell
	var x_in := x_end - outward * (width - outside_px) * 0.5
	var x_out := x_end + outward * WALL_END_OUTSIDE
	# UV.x: px in the art (its outer side is the art's right for a right end, left for a left end).
	var u_in := 0.0 if outward > 0.0 else width
	var u_out := width if outward > 0.0 else 0.0
	var face := SHADE_SOUTH if is_zero_approx(float(band["slope"])) else (SHADE_SOUTH_WEST if float(band["slope"]) > 0.0 else SHADE_SOUTH_EAST)
	var shade := face * (SHADE_END_EAST if outward > 0.0 else SHADE_END_WEST)
	var arrays := _arrays_for(walls, style + ":end-" + side)
	var corners := [[x_in, p0.y, u_in], [x_out, p0.y, u_out], [x_out, p1.y, u_out],
			[x_in, p0.y, u_in], [x_out, p1.y, u_out], [x_in, p1.y, u_in]]
	for corner: Array in corners:
		var x := float(corner[0])
		# Never above the wall's top edge (a 45° face's top drops away from its end).
		var y := maxf(float(corner[1]), _band_top(band, x / cell))
		var uv := _band_uv(band, x / cell, y)
		arrays.add(Vector2(x, y * cell), Vector2(float(corner[2]), uv.y),
				Color(shade, _level_channel(float(band["top"]) - uv.x), uv.x * cell / 256.0, 1.0))


## Corner stones where a ramp leaving a south face cuts through the wall (`ends`, drawn over the
## ramp): the wall beside it ends there as at any wall end. Only straight front ramps cut a wall
## along a vertical line.
func _add_ramp_cut_ends(ends: Dictionary, ramps: Array[ElevationRamp]) -> void:
	for ramp in ramps:
		if not ramp.rimmed or ramp.near != 0.0 or absf(ramp.dir.x) > 1e-6 or ramp.dir.y <= 0.0:
			continue
		var near_it := ramp.bounds.grow(cell)
		for edge: Array in grid.tri_edges():
			if int(edge[2]) != ElevationGrid.VERTICAL or not near_it.has_point((edge[3] as Vector2) * cell):
				continue
			var a := int(edge[0])
			var b := int(edge[1])
			var inside_a := ramp.covers(_tri_centre(a))
			var inside_b := ramp.covers(_tri_centre(b))
			if inside_a == inside_b:
				continue
			var outside := b if inside_a else a
			if grid.tri_band[outside] < 0 or int(grid.bands[grid.tri_band[outside]]["top"]) != ramp.top:
				continue
			_add_wall_end(ends, grid.tri_band[outside], edge[3], edge[4], -1.0 if inside_a else 1.0)


## The centre of a tri (Elevation space).
func _tri_centre(tri: int) -> Vector2:
	var points := grid.tri_points(tri)
	return (points[0] + points[1] + points[2]) / 3.0 * cell


## The ramps whose top end is an open end of the cliff (ElevationRamp.opens).
func _open_ramps() -> Array[ElevationRamp]:
	var open_ends: Array[ElevationRamp] = []
	for ramp in _ramps:
		if ramp.opens():
			open_ends.append(ramp)
	return open_ends


## True when the top's boundary edge `edge` (elevation_rims.gd, cells) is the back rim of a
## one-row open cliff (`_open_tops`): its lower ground lies behind it (north, or north-east or
## north-west on a 45° edge; the edge runs west with the top on its left). It gets no strip, glow
## or depth core: the narrow top runs on into the ground behind it, so it shows one top edge, not
## two (owner, 2026-10-11). Every other top keeps its back rim.
func _is_back_rim(edge: Dictionary) -> bool:
	if _open_tops.is_empty() or int(edge["mode"]) != ElevationRims.RIM:
		return false
	var from: Vector2 = edge["from"]
	var way := (edge["to"] as Vector2) - from
	if way.x >= -0.01 * way.length():
		return false
	# The top lies on the left of the way: the cell a little in from the edge's middle.
	var inside := from + way * 0.5 + Vector2(way.y, -way.x).normalized() * 0.1
	var at := Vector2i(floori(inside.x), floori(inside.y))
	return grid.has_cell(at) and _quiet_at(_open_tops, grid.cell_index(at), int(edge["level"]))


## The lower ground behind the one-row open cliffs (owner, 2026-10-14: "when the structure is an
## open cliff ... do not paint the inner wall"): per cliff (its cells joined by their corners), the
## lower cells right behind (north of) its cells, and those joined to them inside the cliff's bounding
## box (`_open_inner`). An L of single cells with its front to the south encloses the ground behind
## its row: its arm's side facing that ground is inner, its other side is not.
func _find_open_inner() -> void:
	_open_inner.clear()
	var tops := {}
	for index: int in _open_tops:
		if grid.cell_level[index] == int(_open_tops[index]):
			tops[index] = int(_open_tops[index])
	var seen := {}
	for start: int in tops:
		if seen.has(start):
			continue
		var level: int = tops[start]
		# This cliff: its cells (joined by their corners) and their box.
		var cells: Array[Vector2i] = []
		var todo: Array[int] = [start]
		seen[start] = true
		while not todo.is_empty():
			var index: int = todo.pop_back()
			var at := Vector2i(index % grid.columns, index / grid.columns)
			cells.append(at)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var next := at + Vector2i(dx, dy)
					if grid.has_cell(next):
						var next_index := grid.cell_index(next)
						if not seen.has(next_index) and int(tops.get(next_index, ElevationGrid.MIN_LEVEL - 1)) == level:
							seen[next_index] = true
							todo.append(next_index)
		var box := Rect2i(cells[0], Vector2i.ONE)
		for at in cells:
			box = box.merge(Rect2i(at, Vector2i.ONE))
		# The ground right behind it, then what joins that inside the box.
		var flood: Array[Vector2i] = []
		for at in cells:
			var behind := at + Vector2i(0, -1)
			if box.has_point(behind) and grid.has_cell(behind) and grid.cell_level[grid.cell_index(behind)] < level:
				flood.append(behind)
		while not flood.is_empty():
			var at: Vector2i = flood.pop_back()
			var index := grid.cell_index(at)
			if _open_inner.has(index):
				continue
			_open_inner[index] = level
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next := at + step
				if box.has_point(next) and grid.has_cell(next) and grid.cell_level[grid.cell_index(next)] < level \
						and not _open_inner.has(grid.cell_index(next)):
					flood.append(next)


## True when the top's boundary edge `edge` (elevation_rims.gd, cells) is a side of a one-row open
## cliff facing the ground behind it (`_open_inner`): no wall and no rim there, as on its back.
func _is_inner_side(edge: Dictionary) -> bool:
	if _open_inner.is_empty() or int(edge["mode"]) != ElevationRims.RIM:
		return false
	var level := int(edge["level"])
	var across := grid.tri_cell(int(edge["x"]))
	if int(_open_inner.get(grid.cell_index(across), ElevationGrid.MIN_LEVEL - 1)) != level:
		return false
	var from: Vector2 = edge["from"]
	var way := (edge["to"] as Vector2) - from
	var inside := from + way * 0.5 + Vector2(way.y, -way.x).normalized() * 0.1
	var at := Vector2i(floori(inside.x), floori(inside.y))
	return grid.has_cell(at) and _quiet_at(_open_tops, grid.cell_index(at), level)


## True when the top's boundary edge `edge` (elevation_rims.gd, cells) would turn the top's rim
## around the open end of one of `open_ends` (ElevationRamp.closes): it is left out of the rim, and
## that ramp's cap fades the strips' cut ends in (ElevationRamp.cuts_rim).
func _closes_open_end(edge: Dictionary, open_ends: Array[ElevationRamp]) -> bool:
	var from: Vector2 = (edge["from"] as Vector2) * cell
	var to: Vector2 = (edge["to"] as Vector2) * cell
	for ramp in open_ends:
		if ramp.closes(from, to, int(edge["level"])):
			ramp.cuts_rim = true
			return true
	return false


## How much of the cast shadows the ground at `point` (Elevation space) takes: none just beyond the
## open end of a ramp (ElevationRamp.shadow_take), all of it elsewhere.
func _shadow_take(point: Vector2, open_ends: Array[ElevationRamp]) -> float:
	var take := 1.0
	for ramp in open_ends:
		take = minf(take, ramp.shadow_take(point))
	return take


## True when a wall end's stones at `point` (Elevation space, inside the wall) lie under a ramp
## (its slope or skirt) or on the face it tapers: the wall ends in nothing there.
func _end_under_ramp(point: Vector2, ramps: Array[ElevationRamp]) -> bool:
	for ramp in ramps:
		if ramp.on_face(point) or ramp.covers(point):
			return true
	return false


## True when the foot of wall `index` lies under a ramp, all of it (its slope or skirt: the ramp lays
## its own foot along the slope's edge).
func _foot_under_ramp(index: int, ramps: Array[ElevationRamp]) -> bool:
	var band: Dictionary = grid.bands[index]
	if not bool(band["natural"]):
		return false
	var column := int(band["column"])
	var edge := ElevationGrid.column_edge(column, int(band["end"]))
	# Both ends of the foot line, a unit in and a unit down (a slope ends level with the foot): a
	# foot the ramp covers only in part stays, so the foot runs on where the slope ends.
	var start := Vector2(column * 0.5, edge.x) * cell
	var finish := start + Vector2(0.5, edge.y * 0.5) * cell
	var inward := (finish - start).normalized()
	for ramp in ramps:
		if ramp.covers(start + inward + Vector2(0.0, 1.0)) and ramp.covers(finish - inward + Vector2(0.0, 1.0)):
			return true
	return false


## The lower ground's foot along the edge of a ramp's slope where it runs at the face of its top
## (`face_from` … `face_to`): the wall's foot follows the slope up, its fringe never above the
## face's own height, and the part below the edge (the fringe's ground and its contact shade) as
## deep as the face is tall, so it comes to nothing where the face does (the top end of a taper).
## Where the slope's edge climbs steeper than 45° on screen (a steep ramp along a 45° face), a
## fringe swept straight up would shear its art into streaks: the sweep leans towards the face by
## the excess, so the art shears no more than along a 45° foot.
func _add_ramp_foot(feet: Dictionary, ramp: ElevationRamp) -> void:
	if ramp.near == 0.0 or ramp.face_to - ramp.face_from < 1.0 or not _has_fringe(ramp.ground_name, "foot"):
		return
	var arrays := _arrays_for(feet, ramp.ground_name + FRINGE_KEY)
	var height := ElevationStairs.LEVEL * (ramp.top - ramp.bottom)
	var reach: float = FRINGE_EDGE_ROW["foot"] * 0.5
	var below: float = (FRINGE_HEIGHT["foot"] - FRINGE_EDGE_ROW["foot"]) * 0.5
	var t := ramp.near * ramp.half
	# The sweep (`up`, the art's columns) and the art's rows (`rows`, u = 2 px per unit along them).
	var high := ramp.screen_of(Vector3(0.0, t, height))
	var along := (ramp.screen_of(Vector3(ramp.ramp, t, 0.0)) - high).normalized()
	var lean := maxf(0.0, atan2(absf(along.y), absf(along.x)) - PI * 0.25)
	# Towards the face, which lies above the edge: the way the edge runs down the screen.
	var toward := 1.0 if along.x >= 0.0 else -1.0
	var up := Vector2(sin(lean) * toward, -cos(lean))
	var rows := Vector2(cos(lean), sin(lean) * toward)
	# How far along `up` the face's top edge lies per unit of the face's height (1 straight up).
	var top_way := (ramp.screen_of(Vector3(ramp.ramp, t, height)) - high).normalized()
	var turn := up.x * top_way.y - up.y * top_way.x
	var per := top_way.x / turn if absf(turn) > 1e-3 else 1.0
	# The face's height (height − the slope's) grows linearly along s: cut where the fringe reaches
	# the depth below the edge and the reach above it, and at the height over which the foot fades
	# in (RAMP_FOOT_FADE_IN: the lip's hanging ferns end on the slope near the top end), so each
	# piece is linear.
	# Only where a wall stands beside the slope: the face found for the ramp may run on past the end
	# of the wall (the top beside it repainted), and a foot there would lie on open ground.
	var span := _ramp_wall_span(ramp, t, height, up, per)
	if span.y - span.x < 1.0:
		return
	var cuts := PackedFloat32Array([span.x])
	for face_height: float in [below / per, reach / per, RAMP_FOOT_FADE_IN]:
		var at := face_height / height * ramp.ramp
		if at > span.x and at < span.y and not cuts.has(at):
			cuts.append(at)
	cuts.append(span.y)
	cuts.sort()
	for i in cuts.size() - 1:
		var ends := []
		for s: float in [cuts[i], cuts[i + 1]]:
			var face := height - ramp.nosing(s)
			ends.append([ramp.screen_of(Vector3(s, t, ramp.nosing(s))), minf(reach, face * per), minf(below, face * per),
					float(ramp.bottom) + ramp.nosing(s) / ElevationStairs.LEVEL, minf(1.0, face / RAMP_FOOT_FADE_IN)])
		# The first end towards the art's left (the piece's diagonal runs as along a plain foot).
		if (ends[0][0] as Vector2).dot(rows) > (ends[1][0] as Vector2).dot(rows):
			ends.reverse()
		_add_fringe_cut(arrays, ends[0], ends[1], up, rows)


## The sides look's foot along the edge of a ramp's slope where it runs at the face of its top: the
## same dark line over a few clumps of the slope's ground as at every wall's foot
## (sides/elevation_sides.gdshader), with a short shadow on the slope, both fading in from nothing
## where the face does (SIDES_RAMP_FOOT_FADE_IN, at the ramp's top end). It lies on the slope's
## hard edge (ElevationRamp.hard_edge, `edge_t`), where the wall's stones end. Keyed by the slope's
## ground.
func _add_sides_ramp_foot(feet: Dictionary, ramp: ElevationRamp) -> void:
	if ramp.near == 0.0 or ramp.face_to - ramp.face_from < 1.0:
		return
	var height := ElevationStairs.LEVEL * (ramp.top - ramp.bottom)
	var t := ramp.near * ramp.half
	# The way up the face from the slope's edge, as `_add_ramp_foot` finds it, for the wall's span.
	var high := ramp.screen_of(Vector3(0.0, t, height))
	var along := (ramp.screen_of(Vector3(ramp.ramp, t, 0.0)) - high).normalized()
	var lean := maxf(0.0, atan2(absf(along.y), absf(along.x)) - PI * 0.25)
	var toward := 1.0 if along.x >= 0.0 else -1.0
	var up := Vector2(sin(lean) * toward, -cos(lean))
	var top_way := (ramp.screen_of(Vector3(ramp.ramp, t, height)) - high).normalized()
	var turn := up.x * top_way.y - up.y * top_way.x
	var per := top_way.x / turn if absf(turn) > 1e-3 else 1.0
	var span := _ramp_wall_span(ramp, t, height, up, per)
	if span.y - span.x < 1.0:
		return
	var steps := maxi(1, ceili((span.y - span.x) / 6.0))
	var points := PackedVector2Array()
	var faces := PackedFloat32Array()
	var levels := PackedFloat32Array()
	# On the slope's hard edge (ElevationRamp.hard_edge), where the stones end.
	var edge := ramp.edge_t()
	for k in steps + 1:
		var at := lerpf(span.x, span.y, float(k) / steps)
		points.append(ramp.screen_of(Vector3(at, edge, ramp.nosing(at))))
		faces.append(maxf(0.0, (height - ramp.nosing(at)) * per))
		levels.append(float(ramp.bottom) + ramp.nosing(at) / ElevationStairs.LEVEL)
	var arrays := _arrays_for(feet, ramp.ground_name)
	var u := 0.0
	for k in steps:
		var a := points[k]
		var b := points[k + 1]
		var tangent := (b - a).normalized()
		# Out over the slope: away from the face.
		var out := Vector2(-tangent.y, tangent.x)
		if out.dot(up) > 0.0:
			out = -out
		var length := a.distance_to(b)
		var ends := []
		for e in 2:
			var face := faces[k + e]
			var show := minf(1.0, face / SIDES_RAMP_FOOT_FADE_IN)
			ends.append([points[k + e], minf(ElevationSides.FOOT_UP, face), u + length * e, show, levels[k + e]])
		for index: int in [0, 3, 4, 0, 4, 1, 1, 4, 5, 1, 5, 2]:
			var end: Array = ends[index / 3]
			var offset: float = [-float(end[1]), 0.0, SIDES_RAMP_FOOT_OUT][index % 3]
			arrays.add((end[0] as Vector2) + out * offset, Vector2(float(end[2]), offset),
					Color(ElevationSides.KIND_FOOT, SIDES_RAMP_FOOT_SHADOW * float(end[3]), 1.0 - float(end[3]),
					_level_channel(float(end[4]))))
		u += length


## The stretch of `ramp`'s face (Vector2(s from, s to), within face_from … face_to) where a wall
## stands just above the edge of its slope (its near side, at `t`): probed RAMP_FOOT_PROBE apart, a
## little way up the face (`up`, `per`: Elevation `_add_ramp_foot`); where the face is lower than
## that it counts as wall. Empty (y < x) when none does.
func _ramp_wall_span(ramp: ElevationRamp, t: float, height: float, up: Vector2, per: float) -> Vector2:
	var first := INF
	var last := -INF
	var s := ramp.face_from
	while s <= ramp.face_to + 0.01:
		var at := minf(s, ramp.face_to)
		var face := height - ramp.nosing(at)
		var wall := face * per < 2.0
		if not wall:
			var probe := ramp.screen_of(Vector3(at, t, ramp.nosing(at))) + up * minf(face * per * 0.5, 12.0)
			var tri := grid.tri_at(probe / cell)
			wall = tri >= 0 and grid.tri_band[tri] >= 0
		if wall:
			first = minf(first, at)
			last = at
		elif last > -INF:
			break
		s += RAMP_FOOT_PROBE
	return Vector2(first, last) if last > -INF else Vector2(1.0, 0.0)


## A foot fringe along the edge from one end to the other (each [point (Elevation space; the first
## towards the art's left), world units up, world units down, its ground's level, its opacity
## (colour b, elevation_fringe.gdshader `fade_by_b`)]), swept along `up` (straight up for a plain
## foot; its art's rows run along `rows`, 2 px per unit) and squeezed into what height and depth
## there is: the fern tips end at the face's top however short it is (never cut along a ruled line
## there), and the art's ground and shade fade out over what depth there is.
func _add_fringe_cut(arrays: MeshData, from: Array, to: Array, up: Vector2 = Vector2.UP, rows: Vector2 = Vector2.RIGHT) -> void:
	var edge_row: float = FRINGE_EDGE_ROW["foot"]
	var v_top := -edge_row * 0.5
	var v_bottom: float = (FRINGE_HEIGHT["foot"] - edge_row) * 0.5
	# [end, offset along `up`, art v].
	var corners := [[from, float(from[1]), v_top], [to, float(to[1]), v_top], [to, -float(to[2]), v_bottom],
			[from, float(from[1]), v_top], [to, -float(to[2]), v_bottom], [from, -float(from[2]), v_bottom]]
	for corner: Array in corners:
		var end: Array = corner[0]
		var p: Vector2 = end[0]
		var v := float(corner[2])
		arrays.add(p + up * float(corner[1]), Vector2(p.dot(rows) * 2.0, edge_row + v * 2.0),
				Color(SHADOW_FOOT * float(end[4]), (-v + 64.0) / 128.0, float(end[4]), _level_channel(float(end[3]))))


## A wall's (depth below its top edge in cells, texture v in world units) at point (x, y) in cells,
## its top edge carried on in a straight line past its own half-column.
func _band_uv(band: Dictionary, x: float, y: float) -> Vector2:
	var depth := y - _band_top(band, x)
	return Vector2(depth, depth * cell + float(posmod(int(band["top"]), 2)) * cell)


## The y (cells) of a wall's top edge at x (cells), carried on in a straight line past its own
## half-column.
func _band_top(band: Dictionary, x: float) -> float:
	return float(band["y_left"]) + float(band["slope"]) * (x - int(band["column"]) * 0.5)


## The corner stones of the `side` ("right" or "left") end of a wall of `style`, null without art
## (loaded once: `_wall_end_art`).
func _wall_end_texture(style: String, side: String) -> Texture2D:
	var path := WALL_END_ART % [style, side]
	if not _wall_end_art.has(path):
		_wall_end_art[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _wall_end_art[path]


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
		if flight is ElevationRamp:
			(flight as ElevationRamp).add_ramp_depth(depth, _wall_tris_in(flight.bounds))
		else:
			flight.add_depth(depth)
	return Rect2(Vector2(low) * cell, Vector2(high - low + Vector2i.ONE) * cell)


## The tris of tops of `level` or higher in `rect` (Elevation space), as screen triangles.
func _top_tris_in(rect: Rect2, level: int) -> Array[PackedVector2Array]:
	var tris: Array[PackedVector2Array] = []
	var from := Vector2i(floori(rect.position.x / cell), floori(rect.position.y / cell))
	var to := Vector2i(floori(rect.end.x / cell), floori(rect.end.y / cell))
	for cy in range(maxi(0, from.y), mini(grid.rows - 1, to.y) + 1):
		for cx in range(maxi(0, from.x), mini(grid.columns - 1, to.x) + 1):
			var index := grid.cell_index(Vector2i(cx, cy))
			for tri in range(index * 8, index * 8 + 8):
				if grid.tri_band[tri] < 0 and grid.tri_level[tri] >= level:
					tris.append(_world(grid.tri_points(tri)))
	return tris


## The wall tris in `rect` (Elevation space), as screen triangles: what a ramp there may cover.
func _wall_tris_in(rect: Rect2) -> Array[PackedVector2Array]:
	var tris: Array[PackedVector2Array] = []
	var from := Vector2i(floori(rect.position.x / cell), floori(rect.position.y / cell))
	var to := Vector2i(floori(rect.end.x / cell), floori(rect.end.y / cell))
	for cy in range(maxi(0, from.y), mini(grid.rows - 1, to.y) + 1):
		for cx in range(maxi(0, from.x), mini(grid.columns - 1, to.x) + 1):
			var index := grid.cell_index(Vector2i(cx, cy))
			for tri in range(index * 8, index * 8 + 8):
				if grid.tri_band[tri] >= 0:
					tris.append(_world(grid.tri_points(tri)))
	return tris


## The tops that can lie in a cast shadow: up to SHADOW_REACH cells right of and one cell below
## anything higher (a top, a wall's top, a flight of stairs).
func _add_receivers(arrays: MeshData, depth_rect: Rect2) -> void:
	if depth_rect.size == Vector2.ZERO:
		return
	# A one-row open cliff and its walls cast none (`_open_tops`).
	var heights := PackedInt32Array()
	heights.resize(grid.columns * grid.rows)
	for index in heights.size():
		var high := ElevationGrid.MIN_LEVEL
		for tri in range(index * 8, index * 8 + 8):
			var band := grid.tri_band[tri]
			if band >= 0:
				var hangs_from := _band_top_cell(band)
				if not _quiet_at(_open_tops, hangs_from, int(grid.bands[band]["top"])):
					high = maxi(high, int(grid.bands[band]["top"]))
			elif not _quiet_at(_open_tops, index, grid.tri_level[tri]):
				high = maxi(high, grid.tri_level[tri])
		heights[index] = high
	for flight: ElevationStairs in stairs:
		# A ramp casts only the shadow of the wall it covers, and walls already count.
		if flight is ElevationRamp:
			continue
		var from := Vector2i(floori(flight.bounds.position.x / cell), floori(flight.bounds.position.y / cell))
		var to := Vector2i(floori(flight.bounds.end.x / cell), floori(flight.bounds.end.y / cell))
		for cy in range(maxi(0, from.y), mini(grid.rows - 1, to.y) + 1):
			for cx in range(maxi(0, from.x), mini(grid.columns - 1, to.x) + 1):
				var index := grid.cell_index(Vector2i(cx, cy))
				heights[index] = maxi(heights[index], flight.top)
	# Beyond a ramp's open end the ground takes no shadow (colour r, ElevationRamp.shadow_take).
	var open_ends := _open_ramps()
	var open_rects: Array[Rect2] = []
	for ramp in open_ends:
		open_rects.append(Rect2(ramp.open_corner(), Vector2.ZERO).grow(ElevationRamp.OPEN_FAR + cell))
	for cy in grid.rows:
		for cx in grid.columns:
			var index := grid.cell_index(Vector2i(cx, cy))
			var nearby := ElevationGrid.MIN_LEVEL
			for dy in [-1, 0]:
				for dx in range(-SHADOW_REACH, 1):
					var other := Vector2i(cx + dx, cy + dy)
					if grid.has_cell(other):
						nearby = maxi(nearby, heights[grid.cell_index(other)])
			var near_open := false
			for rect in open_rects:
				near_open = near_open or rect.has_point((Vector2(cx, cy) + Vector2(0.5, 0.5)) * cell)
			for tri in range(index * 8, index * 8 + 8):
				if grid.tri_band[tri] >= 0 or grid.tri_level[tri] >= nearby:
					continue
				var level_channel := _level_channel(grid.tri_level[tri])
				if not near_open:
					arrays.add_flat(_world(grid.tri_points(tri)), Vector2.ZERO, Color(1.0, 1.0, 1.0, level_channel))
					continue
				for point in _world(grid.tri_points(tri)):
					arrays.add(point, Vector2.ZERO, Color(_shadow_take(point, open_ends), 1.0, 1.0, level_channel))


## The one-row open cliffs (owner, 2026-10-11): the cells (grid index -> level) of every top a
## ramp joins (8-connected at the ramp's level) that are one row thick (no cell of that top right
## above or below them), and the lower cells touching them, for that level (along a 45° edge the
## corner triangles a chamfer raises lie in the lower cells beside it, and so does the top edge of
## the wall below). Such a cliff has no back rim (`_is_back_rim`) and casts no shadow
## (`_add_receivers`), and its ramps take none (ElevationRamp.no_shadow); every other top keeps
## both.
func _find_open_tops() -> Dictionary:
	var quiet := {}
	var seeds_of := {}
	for ramp in _ramps:
		var height := ElevationStairs.LEVEL * (ramp.top - ramp.bottom)
		var end := ramp.screen_of(Vector3(0.0, 0.0, height)) / cell
		var todo: Array[Vector2i] = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var seed := Vector2i(floori(end.x) + dx, floori(end.y) + dy)
				if grid.has_cell(seed) and grid.cell_level[grid.cell_index(seed)] == ramp.top:
					todo.append(seed)
		seeds_of[ramp] = todo.duplicate()
		while not todo.is_empty():
			var at: Vector2i = todo.pop_back()
			var index := grid.cell_index(at)
			if quiet.has(index):
				continue
			quiet[index] = ramp.top
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var next := at + Vector2i(dx, dy)
					if grid.has_cell(next) and not quiet.has(grid.cell_index(next)) and grid.cell_level[grid.cell_index(next)] == ramp.top:
						todo.append(next)
	# Only where the top is one row thick, or one column (an arm running north-south).
	var thin := {}
	for index: int in quiet:
		var at := Vector2i(index % grid.columns, index / grid.columns)
		var level: int = quiet[index]
		var thick_rows := false
		var thick_columns := false
		for d: int in [-1, 1]:
			for pair: Array in [[Vector2i(0, d), true], [Vector2i(d, 0), false]]:
				var next: Vector2i = at + (pair[0] as Vector2i)
				var same := grid.has_cell(next) and int(quiet.get(grid.cell_index(next), ElevationGrid.MIN_LEVEL - 1)) == level
				if bool(pair[1]):
					thick_rows = thick_rows or same
				else:
					thick_columns = thick_columns or same
		if not thick_rows or not thick_columns:
			thin[index] = level
	# A ramp joining such a cliff takes no shadow.
	for ramp: ElevationRamp in seeds_of:
		ramp.no_shadow = false
		for seed: Vector2i in seeds_of[ramp]:
			ramp.no_shadow = ramp.no_shadow or thin.has(grid.cell_index(seed))
	# And the lower cells touching them, for their level.
	var touching := thin.duplicate()
	for index: int in thin:
		var at := Vector2i(index % grid.columns, index / grid.columns)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := at + Vector2i(dx, dy)
				if grid.has_cell(next) and not touching.has(grid.cell_index(next)) and grid.cell_level[grid.cell_index(next)] < int(thin[index]):
					touching[grid.cell_index(next)] = thin[index]
	return touching


## No hidden strip behind a one-row open cliff (ElevationGrid.no_strip): its back shows as flat
## ground, so nothing walks under it from behind, and a drop off its back lands behind it in sight
## (`drop_target` finds no room in the strip and moves out past the rim).
func _mark_open_tops() -> void:
	grid.no_strip = PackedByteArray()
	if _open_tops.is_empty():
		return
	grid.no_strip.resize(grid.tri_level.size())
	for index: int in _open_tops:
		for tri in range(index * 8, index * 8 + 8):
			var band := grid.tri_band[tri]
			var level := int(grid.bands[band]["top"]) if band >= 0 else grid.tri_level[tri]
			if level == int(_open_tops[index]):
				grid.no_strip[tri] = 1


## The ground around the one-row open cliffs where only walls collide (owner, 2026-10-12): the
## cells of each cliff and the lower cells touching it (`_open_tops`), and those its ramps stand on.
## Between them a collision line that parts ground of the cliff's level from ground of its ramps'
## bottom level (its back edge, an arm's side, a ramp's sides and ends, its tip) is a seam, not a
## wall: it is cut out (`_cut_open_seams`), no ledge drops over it (`ledge_below`), and a body
## crossing it takes the level of where its feet are (`_level_across_open`). So the cliff, its ramps
## and the ground around them are one walk, as they look: a body coming onto the top from anywhere
## stands at its level by the time it reaches the front rim, and a drop off that rim lands at the
## right level whatever the ground behind is painted. Walls (the faces, the wall a ramp tapers)
## still collide and their rims still hold; closed cliffs keep everything.
func _find_open_zone() -> void:
	_open_zone.clear()
	_open_rect = Rect2()
	if _open_tops.is_empty():
		return
	var low_of := {}
	for ramp in _ramps:
		if ramp.no_shadow:
			low_of[ramp.top] = mini(int(low_of.get(ramp.top, ramp.bottom)), ramp.bottom)
	for index: int in _open_tops:
		var top: int = _open_tops[index]
		if low_of.has(top):
			_open_zone[index] = Vector2i(top, low_of[top])
	for ramp in _ramps:
		if not ramp.no_shadow:
			continue
		var box := ramp.bounds
		for y in range(floori(box.position.y / cell), floori(box.end.y / cell) + 1):
			for x in range(floori(box.position.x / cell), floori(box.end.x / cell) + 1):
				if grid.has_cell(Vector2i(x, y)):
					_open_zone[grid.cell_index(Vector2i(x, y))] = Vector2i(ramp.top, low_of[ramp.top])
	for index: int in _open_zone:
		var square := Rect2(Vector2(index % grid.columns, index / grid.columns) * cell, Vector2(cell, cell))
		_open_rect = square if _open_rect.size == Vector2.ZERO else _open_rect.merge(square)


## The zone (`_open_zone`) of `point` (Elevation space): Vector2i(top, low), or (0, 0) with x > y
## false when it lies outside every one.
func _open_pair(point: Vector2) -> Vector2i:
	var at := Vector2i(floori(point.x / cell), floori(point.y / cell))
	if not grid.has_cell(at):
		return Vector2i.ZERO
	return _open_zone.get(grid.cell_index(at), Vector2i.ZERO)


## The level a body of `level` takes with its feet at `feet` (world space) in an open cliff's zone
## (`_find_open_zone`): where it cannot walk at its own level but can at the zone's other one, that
## one; elsewhere its own.
func _level_across_open(feet: Vector2, level: int) -> int:
	var pair := _open_pair(feet - global_position)
	if pair.x <= pair.y or (level != pair.x and level != pair.y) or is_walkable(feet, level):
		return level
	var other := pair.y if level == pair.x else pair.x
	return other if is_walkable(feet, other) else level


## True when a body of `level` with its feet at `feet` walks on to `point` (world space) over a
## seam of an open cliff's zone (`_find_open_zone`): both in the zone, `point` ground of its other
## level. It is no ledge.
func _open_across(feet: Vector2, point: Vector2, level: int) -> bool:
	if _open_zone.is_empty():
		return false
	var pair := _open_pair(point - global_position)
	if pair.x <= pair.y or (level != pair.x and level != pair.y) or _open_pair(feet - global_position) != pair:
		return false
	return is_walkable(point, pair.y if level == pair.x else pair.x)


## `segments` (a level's collision, Elevation space: [p0, p1, ...]) without the seams of the open
## cliffs' zones (`_find_open_zone`): every stretch (SEAM_STEP long) with ground of the zone's levels
## on both sides, SEAM_PROBE off it, and both sides in the zone. What parts walkable ground from a
## wall stays.
func _cut_open_seams(segments: PackedVector2Array, level: int) -> PackedVector2Array:
	if _open_zone.is_empty():
		return segments
	var out := PackedVector2Array()
	for i in range(0, segments.size(), 2):
		var a := segments[i]
		var b := segments[i + 1]
		if not _open_rect.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(SEAM_PROBE)):
			out.append(a)
			out.append(b)
			continue
		var pieces := maxi(1, ceili(a.distance_to(b) / SEAM_STEP))
		var normal := (b - a).orthogonal().normalized()
		var start := -1
		for k in pieces + 1:
			var keep := k < pieces and not _is_open_seam(a.lerp(b, (k + 0.5) / pieces), normal, level)
			if keep and start < 0:
				start = k
			elif not keep and start >= 0:
				out.append(a.lerp(b, float(start) / pieces))
				out.append(a.lerp(b, float(k) / pieces))
				start = -1
	return out


## True when the collision of `level` at `middle` (Elevation space, `normal` across it) is a seam of
## an open cliff's zone (`_cut_open_seams`).
func _is_open_seam(middle: Vector2, normal: Vector2, level: int) -> bool:
	var pair := _open_pair(middle + normal * SEAM_PROBE)
	if pair.x <= pair.y or (level != pair.x and level != pair.y) or _open_pair(middle - normal * SEAM_PROBE) != pair:
		return false
	for side: float in [1.0, -1.0]:
		var point := middle + normal * side * SEAM_PROBE + global_position
		if not is_walkable(point, pair.x) and not is_walkable(point, pair.y):
			return false
	return true


## True when ground of `level` in cell `index` belongs to an open top (`quiet`, `_open_tops`, which
## also lists the cells touching one: along a 45° edge the corner triangles a chamfer raises lie in
## the lower cells beside it, and so does the top edge of the wall below).
static func _quiet_at(quiet: Dictionary, index: int, level: int) -> bool:
	return index >= 0 and int(quiet.get(index, ElevationGrid.MIN_LEVEL - 1)) == level


## The grid index of the cell whose top wall `band` hangs from (the cell just above its top edge).
func _band_top_cell(band: int) -> int:
	var wall: Dictionary = grid.bands[band]
	var at := Vector2i(floori(int(wall["column"]) * 0.5), floori(float(wall["y_left"]) + float(wall["slope"]) * 0.25 - 0.05))
	return grid.cell_index(at) if grid.has_cell(at) else -1


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
		var texture := _wall_end_texture(style.get_slice(":end-", 0), style.get_slice(":end-", 1))
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


## A ramp's slope: its ground's sheet in world space, as the ground draws it (the 128 px sheet where
## there is one, ground_surface.gd), so it joins the ground around it without a seam, with the
## shadows higher ground casts on it at its height.
func _ramp_material(name_of_ground: String) -> Material:
	if not _sheets.has(name_of_ground):
		return null
	var sheet: Texture2D = _sheets[name_of_ground]
	var sharp := GroundSurface.sharp_sheet(sheet)
	var material_of := ShaderMaterial.new()
	material_of.shader = RAMP_SHADER
	material_of.set_shader_parameter(&"ground_texture", sharp if sharp != null else sheet)
	material_of.set_shader_parameter(&"ground_period", cell * SHEET_CELLS)
	material_of.set_shader_parameter(&"ground_origin", _ground_origin())
	# The shadows on it, as on the ground it covers (_cast_shadow_material).
	if occlusion != null and occlusion.texture != null:
		material_of.set_shader_parameter(&"elevation_depth", occlusion.texture)
		material_of.set_shader_parameter(&"depth_rect", occlusion.rect_uniform(occlusion.local_rect))
		material_of.set_shader_parameter(&"shadow_units", SHADOW_UNITS)
		material_of.set_shader_parameter(&"strength", SHADOW_STRENGTH)
	else:
		material_of.set_shader_parameter(&"shadows", 0.0)
	return material_of


## Flights of stairs that take their colour from `name_of_ground` (`_stairs_colour`): the
## STAIRS_STYLE kit's treads, risers and blocks in that colour; null without their art.
func _stairs_material(name_of_ground: String) -> Material:
	var material_of := ShaderMaterial.new()
	material_of.shader = STAIRS_SHADER
	var parts := {"tread": "tread", "riser": "riser", "block": STAIRS_BLOCK_PART}
	for uniform: String in parts:
		var path := STAIRS_ART % [STAIRS_STYLE, parts[uniform]]
		if not ResourceLoader.exists(path):
			push_warning("Elevation: no stairs art '%s'" % path)
			return null
		var texture := load(path) as Texture2D
		material_of.set_shader_parameter(StringName(uniform + "_texture"), texture)
		material_of.set_shader_parameter(StringName(uniform + "_size"), Vector2(texture.get_size()))
	material_of.set_shader_parameter(&"tint", _stairs_colour(name_of_ground))
	return material_of


## The colour of the flights that take it from `name_of_ground`: its average made paler stone
## (STAIRS_SATURATION, STAIRS_VALUE), STAIRS_NO_GROUND when it has no readable sheet.
func _stairs_colour(name_of_ground: String) -> Color:
	var mean := _ground_colour(name_of_ground)
	if mean.a <= 0.0:
		return STAIRS_NO_GROUND
	return Color.from_hsv(mean.h, mean.s * STAIRS_SATURATION, STAIRS_VALUE.x + STAIRS_VALUE.y * mean.v)


## The average colour of `name_of_ground`'s sheet (transparent when it cannot be read): the average
## of its tiles' (MapTerrain, whose shrunk sheets the minimap shares), worked out once per run.
func _ground_colour(name_of_ground: String) -> Color:
	var source := _sources.get(name_of_ground) as TileSetAtlasSource
	if source == null or source.texture == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var key := source.texture.resource_path
	if _ground_colours.has(key):
		return _ground_colours[key]
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	var size := source.get_atlas_grid_size()
	for y in size.y:
		for x in size.x:
			var colour := TileColours.tile_color(source, Vector2i(x, y))
			if colour.a > 0.0:
				sum += colour
				count += 1
	var mean := Color(sum.r / count, sum.g / count, sum.b / count, 1.0) if count > 0 else Color(0.0, 0.0, 0.0, 0.0)
	_ground_colours[key] = mean
	return mean


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


## A ramp's foot along its slope's edge (RampFeet): the ground's foot fringe with its top rows
## faded out (RAMP_FOOT_TOP_FADE) and colour b its opacity (RAMP_FOOT_FADE_IN), since it ends on
## the face's top edge near the top end.
func _ramp_foot_material(key: String) -> Material:
	var material_of := _strip_material(key, true) as ShaderMaterial
	if material_of != null and key.ends_with(FRINGE_KEY):
		material_of.set_shader_parameter(&"top_fade", RAMP_FOOT_TOP_FADE)
		material_of.set_shader_parameter(&"fade_by_b", true)
	return material_of


## Sides (sides/elevation_sides.gdshader): `style`'s wall, and the sheets of the top's ground and
## the lower ground (the 128 px sheet where there is one, as the ground draws it) for the edges.
func _sides_material(style: String, top_ground: String, low_ground: String) -> Material:
	var wall := load(WALL_ART % style) as Texture2D
	if wall == null or not _sheets.has(top_ground):
		return null
	var material_of := ShaderMaterial.new()
	material_of.shader = SIDES_SHADER
	material_of.set_shader_parameter(&"wall_texture", wall)
	material_of.set_shader_parameter(&"wall_size", Vector2(wall.get_size()))
	if ResourceLoader.exists(SIDES_ART % [style, "side"]):
		var side := load(SIDES_ART % [style, "side"]) as Texture2D
		material_of.set_shader_parameter(&"side_texture", side)
		material_of.set_shader_parameter(&"side_size", Vector2(side.get_size()))
		material_of.set_shader_parameter(&"has_side", 1.0)
	if ResourceLoader.exists(SIDES_ART % [style, "corners"]):
		material_of.set_shader_parameter(&"corner_texture", load(SIDES_ART % [style, "corners"]))
		material_of.set_shader_parameter(&"has_corners", 1.0)
	# On a dark ground the top edge's outline is a light rim instead (the dark one disappears there).
	var mean := _ground_colour(top_ground)
	if mean.a > 0.0 and mean.v < DARK_GROUND:
		var rim := Color.from_hsv(mean.h, mean.s * 0.6, clampf(mean.v * 1.9 + 0.14, 0.0, 0.9))
		material_of.set_shader_parameter(&"outline_colour", rim)
		material_of.set_shader_parameter(&"back_outline_colour", rim)
	# Standing in water, the feet are foam on the water (its sheet fills the corners).
	material_of.set_shader_parameter(&"low_is_water", 1.0 if low_ground == TerrainMaterials.WATER else 0.0)
	for pair: Array in [[&"top_ground", top_ground], [&"low_ground", low_ground if _sheets.has(low_ground) else top_ground]]:
		var sheet: Texture2D = _sheets[pair[1]]
		var sharp := GroundSurface.sharp_sheet(sheet)
		material_of.set_shader_parameter(pair[0], sharp if sharp != null else sheet)
	material_of.set_shader_parameter(&"ground_period", cell * SHEET_CELLS)
	material_of.set_shader_parameter(&"ground_origin", _ground_origin())
	return material_of


func _fringe_material(name_of_ground: String, kind: String) -> Material:
	var texture := load(FRINGE_ART % [_fringe_art(name_of_ground), kind]) as Texture2D
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
	var by_level := {}
	_outlines.clear()
	for level in range(ElevationGrid.MIN_LEVEL, ElevationGrid.MAX_LEVEL + 1):
		var segments := _terrain_outline(level)
		if not stairs.is_empty():
			segments = _with_stairs(segments, level)
		if not _side_shapes.is_empty():
			segments = _with_sides(segments, level)
		segments = _cut_open_seams(segments, level)
		if not segments.is_empty():
			by_level[level] = segments
	_outlines.clear()
	if _cache_record != null:
		_cache_record.collision = by_level
	_make_collision(by_level)


## A static body per level (on its own physics layer) with its collision outline: `by_level`
## level -> segments.
func _make_collision(by_level: Dictionary) -> void:
	var old := get_node_or_null("Collision")
	if old != null:
		old.free()
	var holder := Node2D.new()
	holder.name = "Collision"
	add_child(holder)
	for level: int in by_level:
		var segments: PackedVector2Array = by_level[level]
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
	# The steps of every flight (not ramps) on STAIRS_LAYER: enemies and NPCs stay off them.
	var steps := StaticBody2D.new()
	steps.name = "Stairs"
	steps.collision_layer = STAIRS_LAYER
	steps.collision_mask = 0
	for flight: ElevationStairs in stairs:
		if flight is ElevationRamp or flight.walk.size() < 3:
			continue
		var polygon := CollisionPolygon2D.new()
		polygon.polygon = flight.walk
		steps.add_child(polygon)
	if steps.get_child_count() > 0:
		holder.add_child(steps)
	else:
		steps.free()


## `segments` (a level's terrain outline, Elevation space) with the flights of stairs: the outline
## of what the level can walk on where stairs stand (their steps if it joins them; nothing else of
## them). Terrain segments away from every flight stay; near one, they, the flight's steps and its
## silhouette are cut where they cross, and each piece is kept where it parts walkable from blocked
## ground (`is_walkable` on either side of it).
func _with_stairs(segments: PackedVector2Array, level: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var near: Array = []
	# A ramp makes ground of the other levels it joins walkable (its skirt, past its open sides): the
	# borders of their ground near it may part walkable from blocked ground too. Terrain edges as
	# far as those borders reach are traced with the ramp (a border kept there must merge with them).
	var borders_of: Array = []
	var regions: Array[Rect2] = []
	for flight: ElevationStairs in stairs:
		near.append([])
		var borders: Array = _ramp_borders(flight as ElevationRamp, level) if flight is ElevationRamp else []
		var region := flight.bounds
		for edge: Array in borders:
			region = region.expand(edge[0]).expand(edge[1])
		borders_of.append(borders)
		regions.append(region)
	for i in range(0, segments.size(), 2):
		var a := segments[i]
		var b := segments[i + 1]
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(1.0)
		var touched := false
		for f in stairs.size():
			if regions[f].intersects(box):
				(near[f] as Array).append([a, b])
				touched = true
		if not touched:
			out.append(a)
			out.append(b)
	var kept := {}
	var has_ramps := not _ramps.is_empty()
	for f in stairs.size():
		var flight: ElevationStairs = stairs[f]
		var grid_near: Array = near[f]
		# Away from the terrain's outline the ground around a flight is all one: nothing to trace
		# when the level can neither walk the flight nor meet it.
		if grid_near.is_empty() and not flight.joins(level) and (flight.blockers(level).is_empty() \
				or not grid.is_walkable_point(flight.bounds.get_center() / cell, level)):
			continue
		var borders: Array = borders_of[f]
		# The way past its ends is walkable where the ground of that end is: the outline of the top
		# (the bottom) there bounds it too.
		var ends: Array = _end_outlines(flight, level)
		# Cut where the terrain's outline and the outlines of flights it touches cross it.
		var others: Array = grid_near.duplicate()
		for other: ElevationStairs in stairs:
			if other != flight and other.bounds.intersects(flight.bounds):
				others.append_array(other.outline_edges(level))
		var pieces: Array = []
		for piece: Array in flight.outline_pieces(level):
			pieces.append_array(split_edge(piece, others + borders + ends))
		var flight_edges := flight.outline_edges(level)
		for other_edge: Array in others.slice(grid_near.size()):
			flight_edges.append(other_edge)
		for edge: Array in ends:
			pieces.append_array(split_edge(edge, flight_edges + grid_near + borders))
		# A terrain edge near a ramp may run on to another flight further along it (a rim with a
		# ramp at each end): cut it where that one's outline crosses it too, so each piece is judged
		# on its own ground.
		var further := _flights_further(f, grid_near + borders, level) if has_ramps else []
		for edge: Array in grid_near:
			pieces.append_array(split_edge(edge, flight_edges + borders + further))
		for edge: Array in borders:
			pieces.append_array(split_edge(edge, flight_edges + grid_near + borders + further))
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


## The terrain outline of a flight's top level over the way into its top, and of its bottom level
## over the way past its bottom end (ElevationStairs.overhang), for a `level` it joins: where that
## ground ends, so does the way.
func _end_outlines(flight: ElevationStairs, level: int) -> Array:
	var edges: Array = []
	if not flight.joins(level):
		return edges
	for end_of: Array in [[flight.reach, flight.top], [flight.beyond, flight.bottom]]:
		var polygon: PackedVector2Array = end_of[0]
		if polygon.size() < 3 or int(end_of[1]) == level:
			continue
		var box := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			box = box.expand(point)
		box = box.grow(1.0)
		var outline := _terrain_outline(int(end_of[1]))
		for i in range(0, outline.size(), 2):
			if box.intersects(Rect2(outline[i], Vector2.ZERO).expand(outline[i + 1]).grow(0.5)):
				edges.append([outline[i], outline[i + 1]])
	return edges


## The outline edges, at `level`, of the flights (other than flight `index`, and away from it) that
## the terrain `edges` near flight `index` run on to, when a ramp is one of the two.
func _flights_further(index: int, edges: Array, level: int) -> Array:
	var flight: ElevationStairs = stairs[index]
	var box := flight.bounds
	for edge: Array in edges:
		box = box.expand(edge[0]).expand(edge[1])
	var further: Array = []
	for other: ElevationStairs in stairs:
		if other == flight or other.bounds.intersects(flight.bounds) or not other.bounds.intersects(box):
			continue
		if flight is ElevationRamp or other is ElevationRamp:
			further.append_array(other.outline_edges(level))
	return further


## The terrain's outline of `level` (`collision_segments`, Elevation space), worked out once per
## build of the collision (`_outlines`).
func _terrain_outline(level: int) -> PackedVector2Array:
	if not _outlines.has(level):
		var segments := grid.collision_segments(level)
		for i in segments.size():
			segments[i] *= cell
		_outlines[level] = segments
	return _outlines[level]


## The terrain's outlines of the levels `ramp` joins other than `level`, near it (Elevation space):
## [from, to] edges.
func _ramp_borders(ramp: ElevationRamp, level: int) -> Array:
	var borders: Array = []
	for other in range(ramp.bottom, ramp.top + 1):
		if other == level:
			continue
		var segments := _terrain_outline(other)
		for i in range(0, segments.size(), 2):
			var a := segments[i]
			var b := segments[i + 1]
			if ramp.bounds.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(1.0)):
				borders.append([a, b])
	return borders


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
	return _terrain_walkable(point, level)


## `segments` (a level's outline) with the sides look's tops above that level: near each, the
## outline, the drawn top's border and its walls' outlines are cut where they cross, and a piece is
## kept where it parts walkable from blocked ground (`_local_walkable`, which knows the drawn
## shapes), so the level's collision follows the walls as drawn.
func _with_sides(segments: PackedVector2Array, level: int) -> PackedVector2Array:
	if segments.is_empty():
		return segments
	var regions: Array[Rect2] = []
	var candidates: Array = []
	for shape: Dictionary in _side_shapes:
		# Only tops of this level, and those above whose walls come down to it (one standing on a
		# higher terrace lies inside ground this level cannot walk anyway).
		if int(shape["level"]) >= level and (int(shape["level"]) == level or int(shape["lowest"]) <= level):
			regions.append(shape["bounds"])
			candidates.append_array(shape["edges"])
	if regions.is_empty():
		return segments
	var out := PackedVector2Array()
	for i in range(0, segments.size(), 2):
		var box := Rect2(segments[i], Vector2.ZERO).expand(segments[i + 1]).grow(1.0)
		var near := false
		for region in regions:
			if region.intersects(box):
				near = true
				break
		if near:
			candidates.append([segments[i], segments[i + 1]])
		else:
			out.append(segments[i])
			out.append(segments[i + 1])
	var kept := {}
	for piece: Array in _split_all(candidates):
		var from: Vector2 = piece[0]
		var to: Vector2 = piece[1]
		var middle := (from + to) * 0.5
		var normal := (to - from).orthogonal().normalized() * minf(0.5, from.distance_to(to) * 0.2)
		if _local_walkable(middle + normal, level) != _local_walkable(middle - normal, level):
			_keep_on_line(kept, from, to)
	out.append_array(_merged(kept))
	return _weld(out)


## Every edge of `edges` ([from, to]) cut where the others cross it or end on it (a grid of
## SPLIT_BUCKET-unit buckets finds the others near it): the pieces.
static func _split_all(edges: Array) -> Array:
	var buckets := {}
	for index in edges.size():
		var edge: Array = edges[index]
		var box := Rect2(edge[0], Vector2.ZERO).expand(edge[1])
		for y in range(floori(box.position.y / SPLIT_BUCKET), floori(box.end.y / SPLIT_BUCKET) + 1):
			for x in range(floori(box.position.x / SPLIT_BUCKET), floori(box.end.x / SPLIT_BUCKET) + 1):
				var key := Vector2i(x, y)
				if not buckets.has(key):
					buckets[key] = []
				(buckets[key] as Array).append(index)
	var pieces: Array = []
	for index in edges.size():
		var edge: Array = edges[index]
		var box := Rect2(edge[0], Vector2.ZERO).expand(edge[1])
		var seen := {}
		var others: Array = []
		for y in range(floori(box.position.y / SPLIT_BUCKET), floori(box.end.y / SPLIT_BUCKET) + 1):
			for x in range(floori(box.position.x / SPLIT_BUCKET), floori(box.end.x / SPLIT_BUCKET) + 1):
				for other: int in buckets.get(Vector2i(x, y), []):
					if other != index and not seen.has(other):
						seen[other] = true
						others.append(edges[other])
		pieces.append_array(split_edge(edge, others))
	return pieces


## The pieces filed by `_keep_on_line`, those along one line merged into whole segments.
static func _merged(kept: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
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
	return out

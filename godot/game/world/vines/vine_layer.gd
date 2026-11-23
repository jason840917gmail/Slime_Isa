@tool
class_name VineLayer
extends TileMapLayer
## Climbable vines painted on a cliff's front wall (docs/godot/SKINS.md "Painting vines"; the
## owner, 2026-11-12: "how do I paint those vines on a wall?", and a mountain with many climbs):
## Add Node > VineLayer in a world scene, name it `vines`, beside the ground and `elevation` layers
## (same grid, position (0, 0)), and paint from its palette (game/world/vines/vine_tileset.tres)
## **on the cells of the wall's face**: the rows under a raised edge, one per level of the drop.
## What is painted is what is climbed: the vines are drawn over the painted cells, and with the
## Feral skin (docs/godot/SKINS.md "Feral") the slime clings to them while the interact key is held
## and moves over them with the movement keys, any way, cell to cell.
##
## - **Getting on:** an interact press at the wall's foot facing up, under vines that reach the foot;
##   or on the ledge above facing down, over vines that reach the rim.
## - **Getting off:** pushing up at the rim (onto the ledge), or down at the foot. Vines that stop
##   short of the rim have no way off there: the slime moves on sideways or lets go.
## - **Falling off:** the vines have no limit at their sides (the owner, 2026-11-13): moved off
##   their open side, or down past a run that stops short of the foot, the slime falls
##   (`climb_lets_go`), once its centre is `letGoPastPx` past the painted cells.
## - **Letting go** drops the slime to the wall's foot under it, unhurt.
## - **Without the skin** nothing is offered; pushing up at vines' foot says `refusal_text`.
##
## **Balconies** (the owner, 2026-11-13: "a step out balcony where the slime can fall from above",
## after A Link to the Past's ledges on its mountain walls): the palette's second tile, painted in a
## row of the face, is a rock balcony that steps out of the wall over those cells, the wall running
## on behind it. Its grass is a floor: the slime lands on it from the rim above or from a let-go,
## walks on it (game/player/balcony_stand.gd), and drops off its edge to the wall's foot. Vines
## painted right over it or right under it lead onto it and off it. No skin is needed to stand on
## one, only to climb to it.
##
## The wall is read from the world's `elevation` paint (the nearest raised edge above a painted
## cell; found beside this layer or any node above it); with none, as in a corner scene opened by
## itself, each painted column is taken as a wall from its top cell to its bottom one. Cells painted
## off a front wall show a warning on the node.
##
## The vines are drawn by this layer and saved nowhere (the scene stores only the cells): one
## picture per painted rectangle, repeated across a wide one, under bodies at the layer's z_index
## (-1). The palette squares are drawn at `paint_opacity` in the editor and never in the game.
## It is a climbable surface of game/player/skins/feral_climb.gd (in its WALL_GROUP).
##
## **Across a chunk line** (owner, 2026-11-21: the mushroom yard's wall in level-1-c4 climbed up into
## North Wilds C3 and back, "a both way entrance", painted on the vine tilemap): a chunk world's
## vines painted on past its top or bottom edge go on in the chunk world there (the wall's other
## part, painted on that world's own vines). Climbing toward that edge, the slime crosses when its
## centre comes within CROSS_PX of it (`climb_crosses`): it travels there and comes in clinging on
## that world's vines (this layer is that world's arrival end, door CROSS_DOOR) at the same x (else
## on the nearest painted column within CROSS_REACH cells), CROSS_IN_PX inside the edge, and climbs
## on while the interact key, held through the crossing, stays held; let go, it drops.
##
## Owner: skins.

const Services := preload("res://game/shared/services.gd")
const NodeFind := preload("res://game/shared/node_find.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const AreaTravel := preload("res://game/world/area_travel.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")
const BorderCrossing := preload("res://game/world/crossings/border_crossing.gd")

const TILESET := "res://game/world/vines/vine_tileset.tres"
const ART := "res://asset/MAPS/props/mine/256x256-root-wall.webp"
## Across a chunk line (see the class notes): the arrival end's door id, how near the edge (the
## slime's centre) a climb crosses, how far inside the next world's edge it comes in, how many
## columns away from its x it looks for painted vines there.
const CROSS_DOOR := "vines-across"
const CROSS_PX := 12.0
const CROSS_IN_PX := 28.0
const CROSS_REACH := 3
## The keys a slime crossing on the vines may still hold down (play_arrival).
const HELD_ON_ARRIVAL: Array[StringName] = [&"interact", &"move_up", &"move_down", &"move_left", &"move_right"]
const MAIN_GROUP := &"world_main"
## The painted part of the picture (px).
const ART_REGION := Rect2(4, 6, 248, 246)
## How far the picture reaches past the painted cells: its mossy cap over the rim, its roots under
## the foot, its sides.
const CAP_PX := 16.0
const FOOT_PX := 10.0
const SIDE_PX := 12.0
## A patch more than TALL_STRETCH times as tall as the picture at its width is drawn in pieces: the
## picture's top ART_CAP_PX (the moss over the rim), its bottom ART_FOOT_PX (the roots' ends), and
## the rows between them repeated. A picture is at most TALL_FROM_ROWS cells wide on a tall wall.
const TALL_STRETCH := 1.4
const TALL_FROM_ROWS := 2.0
const ART_CAP_PX := 84.0
const ART_FOOT_PX := 62.0
const HOLDER := "Vines"
## The palette's tiles (vine_tileset.tres, tools/pack_vine_tileset.gd): vines, and a balcony.
const VINES_TILE := Vector2i(0, 0)
const BALCONY_TILE := Vector2i(1, 0)
## The balcony's picture: the one made for the wall style of the face it is painted on
## (game/world/elevation/wall_pictures.gd, `asset/MAPS/objects/balcony-<style>.webp`, 512 px wide,
## meadow rock's for a style without one), its straight back edge (WallPictures.BALCONY_BACKS) on
## the top of the painted row.
const WallPictures := preload("res://game/world/elevation/wall_pictures.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
## Its floor, where the slime's feet may be, as shares of the balcony's width: half an ellipse from
## the middle of its back edge, FLOOR_HALF wide each way and FLOOR_DEPTH deep, from FLOOR_BACK out
## of the wall on.
const FLOOR_HALF := 0.34
const FLOOR_DEPTH := 0.2
const FLOOR_BACK := 0.05
## The balcony's shadow on the wall: its picture again, dark, this far down and across (shares of
## its width).
const BALCONY_SHADOW := Color(0.12, 0.08, 0.04, 0.4)
const BALCONY_SHADOW_AT := Vector2(0.03, 0.07)
## The layer's draw order: over the cliff's wall (the ground layer's, -2), under every body.
const Z_INDEX := -1
## game/player/skins/feral_climb.gd WALL_GROUP.
const GROUP := &"climb_walls"
const LEVEL_DATA := "elevation_level"
## The tallest wall looked for above a painted cell (the lowest level to the highest).
const MAX_DROP := ElevationGrid.MAX_LEVEL - ElevationGrid.MIN_LEVEL
## The slime's feet below its centre: the vines hold its centre.
const FEET_BELOW_CENTRE := 27.56
## How square the slime must face the wall (up from its foot, down from its lip) to take hold.
const FACING_DOT := 0.5
## How near an edge (px) pushing on gets the slime off there.
const EDGE_PX := 8.0
## The cells a slime's centre hangs off the vines from (`_held_cell`): beside them, or under them
## (beside and under at a run's bottom corner). Never over them: their top holds the slime in.
const HANG_WAYS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i(-1, -1), Vector2i(1, -1)]
## No painted cell (`_held_cell`).
const NO_CELL := Vector2i(-1073741824, -1073741824)
## How far past its limits a clinging slime may be (a glide's last step, a float's rounding).
const SLACK_PX := 0.5
const TEXT_RISE := 90.0
const TEXT_MS := 2400.0

## How strongly the painted squares show over the vines in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.3:
	set(value):
		paint_opacity = value
		_apply_opacity()
## Said when the slime pushes up at the vines' foot without the Feral skin.
@export var refusal_text: String = "Thick vines and handholds... too steep for a slime. Something wilder could climb them."

var _queued := false
## cell -> Vector2i(the first row of its wall's face, the row after its last): `_face_rows`.
var _faces := {}
var _next_refusal_ms := 0.0
static var _texture: Texture2D
## The crossing under way to the next world: {"map", "x" (the slime's centre), "from" ("south": it
## comes in at that world's bottom edge, climbing up; "north": at its top, climbing down)}; read by
## that world's vines as the slime arrives.
static var _crossing: Dictionary = {}
## This layer's climb has crossed out of its world (it holds the slime still until the world goes).
var _crossed := false
## An arrival end's id (area_travel.gd `find_door` reads it).
var door_id: String = CROSS_DOOR


func _init() -> void:
	z_index = Z_INDEX


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
		# an arrival end only for a climb crossing into this world (the other doors' users never see it)
		if not _crossing.is_empty():
			add_to_group(AreaTravel.DOOR_GROUP)
	# the balconies take the style of their wall, known once the elevation is built
	add_to_group(Elevation.WALL_PICTURES_GROUP)


## The elevation of this world was built (Elevation.WALL_PICTURES_GROUP): the balconies match their
## walls again.
func walls_built(elevation: Node) -> void:
	if elevation == Elevation.around(self) and not get_used_cells().is_empty():
		_queue_rebuild()


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	y_sort_enabled = false
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	if Engine.is_editor_hint():
		var levels := _levels()
		if levels != null and not levels.changed.is_connected(_queue_rebuild):
			levels.changed.connect(_queue_rebuild)
	set_physics_process(not Engine.is_editor_hint())
	_rebuild()


func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0
	if not Engine.is_editor_hint():
		# The game never draws the palette squares; the cells stay readable.
		enabled = false


## `self_modulate` follows `paint_opacity`: not stored, so opening a world never writes it.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "self_modulate":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


func _get_configuration_warnings() -> PackedStringArray:
	if _levels() == null:
		return []
	var off := 0
	for cell: Vector2i in get_used_cells():
		if _wall_rows(cell) == Vector2i.ZERO:
			off += 1
	if off > 0:
		return ["%d painted cell(s) are not on a front wall: paint vines on the rows under a raised edge (one row per level of the drop)." % off]
	return []


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


# --- the wall under the paint ---------------------------------------------------------------------

## True where vines are painted (the palette's other tile is a balcony: `_balcony`).
func _painted(cell: Vector2i) -> bool:
	return get_cell_source_id(cell) != -1 and get_cell_atlas_coords(cell) != BALCONY_TILE


func _balcony(cell: Vector2i) -> bool:
	return get_cell_source_id(cell) != -1 and get_cell_atlas_coords(cell) == BALCONY_TILE


## The world's `elevation` paint: beside this layer, or beside any node above it (a corner scene's
## layer reads the world's); null when there is none.
func _levels() -> TileMapLayer:
	var node := get_parent()
	while node != null:
		var found := NodeFind.layer_with_data(node, LEVEL_DATA)
		if found != null:
			return found
		node = node.get_parent()
	return null


## The level painted under this layer's `cell` (0 where nothing is painted).
func _level(levels: TileMapLayer, cell: Vector2i) -> int:
	var data := levels.get_cell_tile_data(levels.local_to_map(levels.to_local(to_global(map_to_local(cell)))))
	return int(data.get_custom_data(LEVEL_DATA)) if data != null else 0


## The face `cell` lies on, from the elevation paint: (its first row, the row after its last), under
## the nearest raised edge above the cell; Vector2i.ZERO when the cell is on no front wall (or there
## is no elevation paint).
func _wall_rows(cell: Vector2i) -> Vector2i:
	var levels := _levels()
	if levels == null:
		return Vector2i.ZERO
	for rim in range(cell.y - 1, cell.y - 1 - MAX_DROP, -1):
		var drop := _level(levels, Vector2i(cell.x, rim)) - _level(levels, Vector2i(cell.x, rim + 1))
		if drop > 0:
			return Vector2i(rim + 1, rim + 1 + drop) if cell.y <= rim + drop else Vector2i.ZERO
	return Vector2i.ZERO


## The painted run `cell` is in, in its column: (its first row, the row after its last).
func _run_rows(cell: Vector2i) -> Vector2i:
	var first := cell.y
	while _painted(Vector2i(cell.x, first - 1)):
		first -= 1
	var end := cell.y + 1
	while _painted(Vector2i(cell.x, end)):
		end += 1
	return Vector2i(first, end)


## The wall `cell` (painted) climbs: its face from the elevation paint, else its painted run.
func _face_rows(cell: Vector2i) -> Vector2i:
	if _faces.has(cell):
		return _faces[cell]
	var rows := _wall_rows(cell)
	if rows == Vector2i.ZERO:
		rows = _run_rows(cell)
	_faces[cell] = rows
	return rows


## True when the vines of `cell`'s column reach the wall's rim, or a balcony right over them: the
## slime gets onto the ledge (the balcony) there.
func _reaches_rim(cell: Vector2i) -> bool:
	var run := _run_rows(cell)
	return run.x == _face_rows(cell).x or _balcony(Vector2i(cell.x, run.x - 1))


## True when the vines of `cell`'s column reach the wall's foot, or a balcony right under them: the
## slime gets on and off there.
func _reaches_foot(cell: Vector2i) -> bool:
	var run := _run_rows(cell)
	return run.y == _face_rows(cell).y or _balcony(Vector2i(cell.x, run.y))


func _cell_size() -> Vector2:
	return Vector2(tile_set.tile_size) if tile_set != null else Vector2(64, 64)


static func _setting(key: String, fallback: float) -> float:
	return SkinState.setting("feral.vines." + key, fallback)


# --- the climbable surface (game/player/skins/feral_climb.gd), in the slime's feet (world) --------

## True when feet at `feet`, facing `facing`, can take hold: the Feral skin on, at the foot of vines
## that reach it facing up, or on the ledge over vines that reach the rim facing down.
func can_grab(feet: Vector2, facing: Vector2) -> bool:
	if not SkinState.is_on(null, SkinState.FERAL) or not is_visible_in_tree() or facing == Vector2.ZERO:
		return false
	return _hold_from(feet, facing.normalized()).is_finite()


## Where the slime takes hold from `feet`: just onto the vines over (facing up) or under (facing
## down) it.
func climb_start(feet: Vector2, facing: Vector2 = Vector2.ZERO) -> Vector2:
	for way: Vector2 in [facing.normalized(), Vector2.UP, Vector2.DOWN]:
		var at := _hold_from(feet, way)
		if at.is_finite():
			return at
	return feet


## True when the slime may cling with its feet at `feet`: its centre on the vines (or hanging off
## their open side, or under a run that stops on the face, by at most `letGoPastPx`: `_held_cell`),
## under a top that stops on the face by `sideInsetPx`, its feet no lower than where it stands at
## the foot.
func climb_allows(feet: Vector2) -> bool:
	var local := to_local(feet)
	var centre := local - Vector2(0.0, FEET_BELOW_CENTRE)
	var cell := _held_cell(centre)
	if cell == NO_CELL:
		return false
	var size := _cell_size()
	var inset := _setting("sideInsetPx", 14.0)
	if not _painted(cell + Vector2i.UP) and not _reaches_rim(cell) and centre.y - cell.y * size.y < inset - SLACK_PX:
		return false
	if not _painted(cell + Vector2i.DOWN) and _reaches_foot(cell):
		return local.y <= (cell.y + 1) * size.y + _setting("footStandPx", 20.0) + SLACK_PX
	return true


## True when feet at `feet` have left the vines and the slime falls (the owner, 2026-11-13: "there
## is no limits to the sides when climbing, if the player body abandons the vine it should fall"):
## its centre more than `letGoPastPx` past their open side, or under a run that stops on the face.
## Over their top and at the rim or the foot the slime stays on them (or gets off: `climb_exit`).
func climb_lets_go(feet: Vector2) -> bool:
	var centre := to_local(feet) - Vector2(0.0, FEET_BELOW_CENTRE)
	if _held_cell(centre) != NO_CELL:
		return false
	var cell := local_to_map(centre)
	for way: Vector2i in HANG_WAYS:
		if _painted(cell + way):
			return true
	return false


## The painted cell whose vines hold a centre at `centre` (local): the one it is on, else the nearest
## it hangs off by at most `letGoPastPx` (beside it, or under it); NO_CELL when it has left them.
func _held_cell(centre: Vector2) -> Vector2i:
	var cell := local_to_map(centre)
	if _painted(cell):
		return cell
	var size := _cell_size()
	var past := _setting("letGoPastPx", SIDE_PX) + SLACK_PX
	var held := NO_CELL
	var nearest := INF
	for way: Vector2i in HANG_WAYS:
		var near := cell + way
		if not _painted(near):
			continue
		var rect := Rect2(Vector2(near) * size, size)
		var gap := centre.distance_to(centre.clamp(rect.position, rect.end))
		if gap <= past and gap < nearest:
			nearest = gap
			held = near
	return held


## The painted run of vines through `point` (world), as a world rectangle: its column's run
## (`horizontal` false) or its row's (true); an empty Rect2 where no vines are painted. A creature
## living on the vines crawls along it (game/scripts/spiny_caterpillar.gd).
func run_rect(point: Vector2, horizontal: bool) -> Rect2:
	var cell := local_to_map(to_local(point))
	if tile_set == null or not _painted(cell):
		return Rect2()
	var first := cell
	var last := cell
	var way := Vector2i.RIGHT if horizontal else Vector2i.DOWN
	while _painted(first - way):
		first -= way
	while _painted(last + way):
		last += way
	var size := _cell_size()
	var from := to_global(Vector2(first) * size)
	return Rect2(from, to_global(Vector2(last + Vector2i.ONE) * size) - from)


## Pushing `way` at the vines' edge: where the slime stands when it gets off there (the ledge over
## the rim, the ground at the foot), or Vector2.INF.
func climb_exit(feet: Vector2, way: Vector2) -> Vector2:
	var local := to_local(feet)
	var centre := local - Vector2(0.0, FEET_BELOW_CENTRE)
	var cell := _held_cell(centre)
	if cell == NO_CELL:
		return Vector2.INF
	var size := _cell_size()
	if way.y < -FACING_DOT and not _painted(cell + Vector2i.UP) and _reaches_rim(cell) \
			and centre.y - cell.y * size.y <= EDGE_PX:
		var over := Vector2(local.x, cell.y * size.y - _setting("topInsidePx", 40.0) + FEET_BELOW_CENTRE)
		# onto a balcony right over the vines: its floor
		return to_global(_on_floor(cell + Vector2i.UP, over) if _balcony(cell + Vector2i.UP) else over)
	var stand := (cell.y + 1) * size.y + _setting("footStandPx", 20.0)
	if way.y > FACING_DOT and not _painted(cell + Vector2i.DOWN) and _reaches_foot(cell) and stand - local.y <= EDGE_PX:
		var under := Vector2(local.x, stand)
		return to_global(_on_floor(cell + Vector2i.DOWN, under) if _balcony(cell + Vector2i.DOWN) else under)
	return Vector2.INF


## Climbing `way` with the feet at `feet` (feral_climb.gd asks each step, `way` ZERO when the slime
## does not climb): true while this layer's climb crosses out of its world (it then holds the slime
## still), and starts the crossing when the slime's centre comes within CROSS_PX of the world's top
## or bottom edge climbing toward it, its column's vines painted on past that edge and a chunk world
## lying there (see the class notes).
func climb_crosses(feet: Vector2, way: Vector2) -> bool:
	if _crossed:
		return true
	if Engine.is_editor_hint() or absf(way.y) < FACING_DOT:
		return false
	var world := Services.world()
	if world == null or not is_instance_valid(world.world_root):
		return false
	var rect: Rect2 = world.world_rect()
	var centre := feet - Vector2(0.0, FEET_BELOW_CENTRE)
	var up := way.y < 0.0
	var edge := rect.position.y if up else rect.end.y
	if absf(centre.y - edge) > CROSS_PX:
		return false
	var past := local_to_map(to_local(Vector2(centre.x, edge + (-1.0 if up else 1.0))))
	if not _painted(past):
		return false
	var target := chunk_beyond(world.world_root, Vector2i(0, -1 if up else 1))
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if target.is_empty() or main == null or not main.has_method(&"travel_to"):
		return false
	_crossed = true
	_crossing = {"map": target, "x": centre.x, "from": "south" if up else "north"}
	main.call(&"travel_to", target, "", CROSS_DOOR, "")
	return true


## The chunk world `step` away on the atlas grid from chunk world `root` (its `world_map_chunk`
## metadata), in any region; "" when `root` is no chunk world or nothing lies there.
static func chunk_beyond(root: Node, step: Vector2i) -> String:
	if root == null or not root.has_meta(&"world_map_chunk"):
		return ""
	var at: Variant = BorderCrossing.chunk_cell(str(root.get_meta(&"world_map_chunk")))
	if not at is Vector2i:
		return ""
	var want: Vector2i = (at as Vector2i) + step
	var table := WorldChunks.table()
	for world: String in table:
		var chunk_names: Dictionary = (table[world] as Dictionary).get("chunks", {})
		for chunk_world: String in chunk_names:
			var cell: Variant = BorderCrossing.chunk_cell(str(chunk_names[chunk_world]))
			if cell is Vector2i and cell == want:
				return chunk_world
	return ""


# --- the arrival end of a crossing (area_travel.gd finds it by `door_id`) -------------------------

## Where the slime comes in (its centre): CROSS_IN_PX inside the edge it crossed, at the x it left,
## kept on the nearest painted column within CROSS_REACH cells.
func arrival_point() -> Vector2:
	var world := Services.world()
	var rect: Rect2 = world.world_rect() if world != null else Rect2()
	var x := float(_crossing.get("x", rect.get_center().x))
	var y := rect.end.y - CROSS_IN_PX if str(_crossing.get("from", "south")) == "south" else rect.position.y + CROSS_IN_PX
	var local := to_local(Vector2(x, y))
	var cell := local_to_map(local)
	for reach in range(0, CROSS_REACH + 1):
		for dx: int in ([0] if reach == 0 else [-reach, reach]):
			var near := Vector2i(cell.x + dx, cell.y)
			if _painted(near):
				var at := to_global(Vector2(_across(near, local.x), local.y))
				return Vector2(floorf(at.x + 0.5), floorf(at.y + 0.5))
	return Vector2(floorf(x + 0.5), floorf(y + 0.5))


## The slime comes in exactly there.
func exact_arrival() -> bool:
	return true


func has_side() -> bool:
	return false


## main.gd `_start_arrival`: the slime came in on these vines from the next world. It is put on them
## and takes hold; the keys still held down from the climb there count as held (the new world's
## slime saw no press of them), so with the interact key held it climbs on, else it drops.
func play_arrival(player: Node, _delay_ms: float) -> float:
	if player == null or not is_instance_valid(player) or _crossing.is_empty():
		return 0.0
	var centre := arrival_point()
	_crossing = {}
	player.call(&"teleport", centre)
	# Tracked now: the elevation's own deferred track of the new slime would give its body back the
	# level's walls in the middle of the climb.
	var world := Services.world()
	var body := player.get(&"body") as CharacterBody2D
	if world != null and world.elevation != null and body != null:
		world.elevation.track(body)
	if player.has_method(&"hold_keys_still_down"):
		player.call(&"hold_keys_still_down", HELD_ON_ARRIVAL)
	player.call(&"start_climb", self)
	return 0.0


## Where a let-go from `feet` lands: on a balcony under the slime, else before the foot of the wall.
func climb_landing(feet: Vector2) -> Vector2:
	var foot := _foot_under(feet)
	var caught := balcony_catch(feet, foot)
	return caught if caught.is_finite() else foot


## The depth a slime clinging (or falling) at `feet` is drawn at: before the foot of its wall,
## whatever balcony is under it (a balcony's own y is part-way up the wall, behind its face: the
## slime drawn at that depth was hidden behind the wall).
func climb_depth(feet: Vector2) -> float:
	return _foot_under(feet).y


## Before the foot of the wall under `feet` (world): where a fall past every balcony lands.
func _foot_under(feet: Vector2) -> Vector2:
	var local := to_local(feet)
	var centre := local - Vector2(0.0, FEET_BELOW_CENTRE)
	var cell := local_to_map(centre)
	# getting off over the rim, the slime's centre is on the ledge: the wall is the one under it
	if not _painted(cell) and _painted(cell + Vector2i.DOWN):
		cell += Vector2i.DOWN
	elif not _painted(cell) and _wall_rows(cell) == Vector2i.ZERO and _held_cell(centre) != NO_CELL:
		# hanging off the vines' side past the end of their wall's face: their wall's foot
		cell = _held_cell(centre)
	return to_global(Vector2(local.x, _face_rows(cell).y * _cell_size().y + _setting("landBelowFootPx", 30.0)))


# --- the balconies (game/player/balcony_stand.gd), in the slime's feet (world) ------------------------

## The balcony `cell` (a balcony's) is part of: its cells, a row of them.
func _balcony_run(cell: Vector2i) -> Rect2i:
	var first := cell.x
	while _balcony(Vector2i(first - 1, cell.y)):
		first -= 1
	var end := cell.x + 1
	while _balcony(Vector2i(end, cell.y)):
		end += 1
	return Rect2i(first, cell.y, end - first, 1)


## The middle of a balcony's back edge (local): the top of its row, where it meets the wall.
func _balcony_back(run: Rect2i) -> Vector2:
	var size := _cell_size()
	return Vector2((run.position.x + run.size.x * 0.5) * size.x, run.position.y * size.y)


## True when `local` (feet) is on the floor of the balcony `run`.
func _floor_has(run: Rect2i, local: Vector2) -> bool:
	var width := run.size.x * _cell_size().x
	var from := local - _balcony_back(run)
	if from.y < width * FLOOR_BACK - SLACK_PX:
		return false
	return pow(from.x / (width * FLOOR_HALF), 2.0) + pow(from.y / (width * FLOOR_DEPTH), 2.0) <= 1.0 + 0.001


## `local` moved onto the floor of the balcony `cell` is part of: as it is when it is on it, else the
## floor's nearest point towards its middle.
func _on_floor(cell: Vector2i, local: Vector2) -> Vector2:
	var run := _balcony_run(cell)
	var width := run.size.x * _cell_size().x
	var back := _balcony_back(run)
	var from := local - back
	from.y = clampf(from.y, width * FLOOR_BACK, width * FLOOR_DEPTH)
	var reach := pow(from.x / (width * FLOOR_HALF), 2.0) + pow(from.y / (width * FLOOR_DEPTH), 2.0)
	if reach > 1.0:
		# in towards the middle of the floor, on its edge and a little inside
		var middle := Vector2(0.0, width * (FLOOR_BACK + FLOOR_DEPTH) * 0.5)
		for step in 20:
			from = from.lerp(middle, 0.1)
			if pow(from.x / (width * FLOOR_HALF), 2.0) + pow(from.y / (width * FLOOR_DEPTH), 2.0) <= 1.0:
				break
	return back + from


## The balcony whose floor holds `feet` (its cells), or an empty Rect2i.
func balcony_at(feet: Vector2) -> Rect2i:
	var local := to_local(feet)
	var cell := local_to_map(local)
	for row in [cell.y, cell.y - 1, cell.y - 2, cell.y - 3]:
		var at := Vector2i(cell.x, row)
		if _balcony(at):
			var run := _balcony_run(at)
			return run if _floor_has(run, local) else Rect2i()
	return Rect2i()


## True when feet at `feet` stand on a balcony's floor.
func balcony_holds(feet: Vector2) -> bool:
	return balcony_at(feet).size.x > 0


## How much of `move` feet at `feet` on a balcony can take and stay on its floor: all of it, else its
## part along the floor's edge, else nothing.
func balcony_step(feet: Vector2, move: Vector2) -> Vector2:
	var run := balcony_at(feet)
	if run.size.x == 0:
		return move
	var local := to_local(feet)
	for candidate: Vector2 in [move, Vector2(move.x, 0.0), Vector2(0.0, move.y)]:
		if candidate != Vector2.ZERO and _floor_has(run, local + candidate):
			return candidate
	return Vector2.ZERO


## The first balcony a straight fall from `from` down to `to` (feet) comes onto: where it lands on
## its floor, or Vector2.INF (none under it, or the fall passes beside the floor, by its rim).
func balcony_catch(from: Vector2, to: Vector2) -> Vector2:
	if tile_set == null:
		return Vector2.INF
	# on a floor already (the vines' last hold over a balcony): it stays there
	if balcony_holds(from):
		return from
	var a := to_local(from)
	var b := to_local(to)
	var size := _cell_size()
	var column := local_to_map(a).x
	for row in range(floori(a.y / size.y) + 1, floori(b.y / size.y) + 1):
		if not _balcony(Vector2i(column, row)):
			continue
		var run := _balcony_run(Vector2i(column, row))
		var width := run.size.x * size.x
		var back := _balcony_back(run)
		var across := a.x - back.x
		if absf(across) > width * FLOOR_HALF * 0.95:
			continue
		# half-way out on the floor there
		var deep := width * FLOOR_DEPTH * sqrt(1.0 - pow(across / (width * FLOOR_HALF), 2.0))
		var land := back + Vector2(across, maxf(width * FLOOR_BACK, deep * 0.55))
		if land.y > a.y + 1.0:
			return to_global(land)
	return Vector2.INF


## Where a drop off the balcony at `feet` lands: on a balcony under it, else before the wall's foot.
func balcony_drop(feet: Vector2) -> Vector2:
	var run := balcony_at(feet)
	var local := to_local(feet)
	var cell := run.position if run.size.x > 0 else local_to_map(local)
	cell.x = local_to_map(local).x
	var size := _cell_size()
	var foot := to_global(Vector2(local.x, _face_rows(cell).y * size.y + _setting("landBelowFootPx", 30.0)))
	# from past this balcony's own floor on
	var past := cell.y * size.y + run.size.x * size.x * FLOOR_DEPTH + 2.0
	var caught := balcony_catch(to_global(Vector2(local.x, past)), foot)
	return caught if caught.is_finite() else foot


## The depth a slime on the balcony at `feet` is drawn at: the wall's foot, so it shows before the
## wall (the elevation hides what is behind higher ground: Elevation.set_flight).
func balcony_depth(feet: Vector2) -> float:
	var run := balcony_at(feet)
	var cell := run.position if run.size.x > 0 else local_to_map(to_local(feet))
	return to_global(Vector2(0.0, _face_rows(cell).y * _cell_size().y)).y + 1.0


## Where on the vines the slime takes hold from `feet` facing `way` (a unit vector), or Vector2.INF.
func _hold_from(feet: Vector2, way: Vector2) -> Vector2:
	if tile_set == null:
		return Vector2.INF
	var local := to_local(feet)
	var size := _cell_size()
	var cell := local_to_map(local)
	if way.dot(Vector2.UP) >= FACING_DOT:
		# At the foot: the vines' bottom cell is the one over the slime's (or its own, its feet just in).
		for bottom: Vector2i in [cell, cell + Vector2i.UP]:
			if _painted(bottom) and not _painted(bottom + Vector2i.DOWN) and _reaches_foot(bottom):
				var stand := (bottom.y + 1) * size.y + _setting("footStandPx", 20.0)
				return to_global(Vector2(_across(bottom, local.x), minf(local.y, stand)))
	elif way.dot(Vector2.DOWN) >= FACING_DOT:
		# On the ledge: the vines' top cell is the one under the slime's.
		var top := cell + Vector2i.DOWN
		if _painted(top) and not _painted(cell) and _reaches_rim(top):
			var rim := top.y * size.y
			if rim - local.y <= _setting("lipStandPx", 20.0) + SkinState.setting("feral.grabReachPx", 44.0):
				return to_global(Vector2(_across(top, local.x), rim + FEET_BELOW_CENTRE + _setting("lipHangPx", 10.0)))
	return Vector2.INF


## `x` (local) kept on `cell`'s vines: off its open sides by the side inset.
func _across(cell: Vector2i, x: float) -> float:
	var size := _cell_size()
	var inset := _setting("sideInsetPx", 14.0)
	var from := cell.x * size.x + (0.0 if _painted(cell + Vector2i.LEFT) else inset)
	var to := (cell.x + 1) * size.x - (0.0 if _painted(cell + Vector2i.RIGHT) else inset)
	return clampf(x, from, to)


## Without the Feral skin, pushing up at the vines' foot says `refusal_text` (the clarity rule: a
## wrong tool is refused with a line), at most every `skins.feral.refusalEveryMs`.
func _physics_process(_delta: float) -> void:
	if SkinState.is_on(null, SkinState.FERAL) or not is_visible_in_tree():
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player) or not player.has_method(&"get_move_intent"):
		return
	var intent: Vector2 = player.call(&"get_move_intent")
	if intent == Vector2.ZERO or intent.normalized().dot(Vector2.UP) < 0.7:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_refusal_ms:
		return
	var body := player.get(&"body") as Node2D
	var feet: Vector2 = body.global_position if body != null else player.call(&"get_centre")
	if not _hold_from(feet, Vector2.UP).is_finite():
		return
	_next_refusal_ms = now + SkinState.setting("feral.refusalEveryMs", 2500.0)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(&"HitBlocked")
		feel.floating_text(feet - Vector2(0.0, TEXT_RISE), refusal_text, &"white", false, TEXT_MS)


# --- the look --------------------------------------------------------------------------------------

## The painted cells as rectangles (cells): each column's runs, joined with the neighbours that
## begin and end on the same rows.
func patches() -> Array[Rect2i]:
	var runs := {}
	for cell: Vector2i in get_used_cells():
		if _painted(cell) and not _painted(cell + Vector2i.UP):
			runs[cell] = _run_rows(cell).y - cell.y
	var starts := runs.keys()
	starts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array[Rect2i] = []
	for start: Vector2i in starts:
		var height := int(runs[start])
		if int(runs.get(start + Vector2i.LEFT, -1)) == height:
			continue
		var width := 1
		while int(runs.get(start + Vector2i(width, 0), -1)) == height:
			width += 1
		out.append(Rect2i(start, Vector2i(width, height)))
	return out


func _rebuild() -> void:
	_queued = false
	_faces.clear()
	if not is_inside_tree() or tile_set == null:
		return
	if Engine.is_editor_hint():
		update_configuration_warnings()
	var holder := get_node_or_null(HOLDER) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = HOLDER
		add_child(holder)
	for child in holder.get_children():
		child.free()
	var size := _cell_size()
	if not ResourceLoader.exists(ART):
		_add_balconies(holder, size)
		return
	if _texture == null:
		_texture = load(ART) as Texture2D
	for patch: Rect2i in patches():
		# About as wide as tall each (two cells at most): a wide patch repeats the picture, every other
		# one mirrored.
		var copies := maxi(1, roundi(float(patch.size.x) / minf(float(patch.size.y), TALL_FROM_ROWS)))
		var width := patch.size.x * size.x / copies
		for index in copies:
			var area := Rect2(patch.position.x * size.x + index * width - SIDE_PX, patch.position.y * size.y - CAP_PX,
				width + SIDE_PX * 2.0, patch.size.y * size.y + CAP_PX + FOOT_PX)
			var mirrored := (patch.position.x + index) % 2 != 0
			for piece: Dictionary in pieces(area, mirrored):
				_add_piece(holder, piece["area"], piece["region"], bool(piece["mirrored"]))
	# over the vines: those under a balcony run in under its rim
	_add_balconies(holder, size)


## The pieces the vines' picture is drawn in over `area` (world or local units), each
## {"area", "region" (of ART), "mirrored"}: the whole picture when the area is not much taller than
## it at its width; on a tall wall the picture's cap at the top, its foot at the bottom and its middle
## repeated between them (every other one mirrored), none of them stretched much. The placed
## climbable wall draws its roots the same way (game/scripts/climb_wall.gd; owner, 2026-11-21: "I
## don't want you to stretch the vine").
static func pieces(area: Rect2, mirrored: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var natural := ART_REGION.size.y * area.size.x / ART_REGION.size.x
	if area.size.y <= natural * TALL_STRETCH:
		out.append({"area": area, "region": ART_REGION, "mirrored": mirrored})
		return out
	var ratio := area.size.x / ART_REGION.size.x
	var cap := Rect2(ART_REGION.position, Vector2(ART_REGION.size.x, ART_CAP_PX))
	var foot := Rect2(ART_REGION.position.x, ART_REGION.end.y - ART_FOOT_PX, ART_REGION.size.x, ART_FOOT_PX)
	var body := Rect2(ART_REGION.position.x, cap.end.y, ART_REGION.size.x, foot.position.y - cap.end.y)
	out.append({"area": Rect2(area.position, Vector2(area.size.x, cap.size.y * ratio)), "region": cap, "mirrored": mirrored})
	out.append({"area": Rect2(area.position.x, area.end.y - foot.size.y * ratio, area.size.x, foot.size.y * ratio),
		"region": foot, "mirrored": mirrored})
	var between := area.size.y - (cap.size.y + foot.size.y) * ratio
	var count := maxi(1, roundi(between / (body.size.y * ratio)))
	for piece in count:
		out.append({"area": Rect2(area.position.x, area.position.y + cap.size.y * ratio + piece * between / count,
			area.size.x, between / count), "region": body, "mirrored": mirrored != (piece % 2 != 0)})
	return out


## Every painted balcony's picture, as wide as its cells, its back edge on the top of their row,
## over its own shadow on the wall: the picture of its wall's style (the face's in the middle of
## its row).
func _add_balconies(holder: Node2D, size: Vector2) -> void:
	var seen := {}
	for cell: Vector2i in get_used_cells():
		if not _balcony(cell) or seen.has(cell):
			continue
		var run := _balcony_run(cell)
		for x in range(run.position.x, run.end.x):
			seen[Vector2i(x, run.position.y)] = true
		var middle := to_global(Vector2((run.position.x + run.size.x * 0.5) * size.x, (run.position.y + 0.5) * size.y))
		var style := WallPictures.style_for(WallPictures.BALCONY, WallPictures.wall_style(self, middle))
		var picture := WallPictures.texture(WallPictures.BALCONY, style)
		if picture == null:
			continue
		var width := run.size.x * size.x
		var ratio := width / float(picture.get_width())
		var at := Vector2(run.position.x * size.x, run.position.y * size.y - float(WallPictures.BALCONY_BACKS[style]) * ratio)
		for shadow: bool in [true, false]:
			var sprite := Sprite2D.new()
			sprite.texture = picture
			sprite.centered = false
			sprite.scale = Vector2(ratio, ratio)
			sprite.position = at + (BALCONY_SHADOW_AT * width if shadow else Vector2.ZERO)
			if shadow:
				sprite.modulate = BALCONY_SHADOW
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			holder.add_child(sprite)


## One piece of the picture (`region`, px of the art) drawn over `area` (local units).
func _add_piece(holder: Node2D, area: Rect2, region: Rect2, mirrored: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = _texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = true
	sprite.position = area.get_center()
	sprite.scale = area.size / region.size
	sprite.flip_h = mirrored
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	holder.add_child(sprite)

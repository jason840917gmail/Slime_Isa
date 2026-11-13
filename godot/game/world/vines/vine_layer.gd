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
##   short of the rim or the foot have no way off there: the slime moves on sideways or lets go.
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
## Owner: skins.

const Services := preload("res://game/shared/services.gd")
const NodeFind := preload("res://game/shared/node_find.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const TILESET := "res://game/world/vines/vine_tileset.tres"
const ART := "res://asset/MAPS/props/mine/256x256-root-wall.webp"
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
## The balcony's picture (packed from asset/Originals/elevation/balcony/, 512 px wide): the row of
## its straight back edge, which lies on the top of the painted row, and its width in the art.
const BALCONY_ART := "res://asset/MAPS/objects/balcony-meadow-rock.webp"
const BALCONY_ART_WIDTH := 512.0
const BALCONY_ART_BACK := 140.0
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
static var _balcony_texture: Texture2D


func _init() -> void:
	z_index = Z_INDEX


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


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


## True when the slime may cling with its feet at `feet`: its centre on a painted cell, its body
## kept on the vines at their open sides, its feet no lower than where it stands at the foot.
func climb_allows(feet: Vector2) -> bool:
	var local := to_local(feet)
	var centre := local - Vector2(0.0, FEET_BELOW_CENTRE)
	var cell := local_to_map(centre)
	if not _painted(cell):
		return false
	var size := _cell_size()
	var inset := _setting("sideInsetPx", 14.0)
	var across := centre.x - cell.x * size.x
	if across < inset - SLACK_PX and not _painted(cell + Vector2i.LEFT):
		return false
	if across > size.x - inset + SLACK_PX and not _painted(cell + Vector2i.RIGHT):
		return false
	if not _painted(cell + Vector2i.UP) and not _reaches_rim(cell) and centre.y - cell.y * size.y < inset - SLACK_PX:
		return false
	if not _painted(cell + Vector2i.DOWN) and _reaches_foot(cell):
		return local.y <= (cell.y + 1) * size.y + _setting("footStandPx", 20.0) + SLACK_PX
	return true


## Pushing `way` at the vines' edge: where the slime stands when it gets off there (the ledge over
## the rim, the ground at the foot), or Vector2.INF.
func climb_exit(feet: Vector2, way: Vector2) -> Vector2:
	var local := to_local(feet)
	var centre := local - Vector2(0.0, FEET_BELOW_CENTRE)
	var cell := local_to_map(centre)
	if not _painted(cell):
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


## Where a let-go from `feet` lands: on a balcony under the slime, else before the foot of the wall.
func climb_landing(feet: Vector2) -> Vector2:
	var local := to_local(feet)
	var cell := local_to_map(local - Vector2(0.0, FEET_BELOW_CENTRE))
	# getting off over the rim, the slime's centre is on the ledge: the wall is the one under it
	if not _painted(cell) and _painted(cell + Vector2i.DOWN):
		cell += Vector2i.DOWN
	var foot := to_global(Vector2(local.x, _face_rows(cell).y * _cell_size().y + _setting("landBelowFootPx", 30.0)))
	var caught := balcony_catch(feet, foot)
	return caught if caught.is_finite() else foot


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
			var natural := ART_REGION.size.y * area.size.x / ART_REGION.size.x
			if area.size.y <= natural * TALL_STRETCH:
				_add_piece(holder, area, ART_REGION, mirrored)
				continue
			# A tall wall: the picture's cap at the rim, its foot at the foot, its middle repeated between
			# them (every other one mirrored), none of them stretched much.
			var ratio := area.size.x / ART_REGION.size.x
			var cap := Rect2(ART_REGION.position, Vector2(ART_REGION.size.x, ART_CAP_PX))
			var foot := Rect2(ART_REGION.position.x, ART_REGION.end.y - ART_FOOT_PX, ART_REGION.size.x, ART_FOOT_PX)
			var body := Rect2(ART_REGION.position.x, cap.end.y, ART_REGION.size.x, foot.position.y - cap.end.y)
			_add_piece(holder, Rect2(area.position, Vector2(area.size.x, cap.size.y * ratio)), cap, mirrored)
			_add_piece(holder, Rect2(area.position.x, area.end.y - foot.size.y * ratio, area.size.x, foot.size.y * ratio), foot, mirrored)
			var between := area.size.y - (cap.size.y + foot.size.y) * ratio
			var count := maxi(1, roundi(between / (body.size.y * ratio)))
			for piece in count:
				_add_piece(holder, Rect2(area.position.x, area.position.y + cap.size.y * ratio + piece * between / count,
					area.size.x, between / count), body, mirrored != (piece % 2 != 0))
	# over the vines: those under a balcony run in under its rim
	_add_balconies(holder, size)


## Every painted balcony's picture, as wide as its cells, its back edge on the top of their row,
## over its own shadow on the wall.
func _add_balconies(holder: Node2D, size: Vector2) -> void:
	var seen := {}
	for cell: Vector2i in get_used_cells():
		if not _balcony(cell) or seen.has(cell):
			continue
		var run := _balcony_run(cell)
		for x in range(run.position.x, run.end.x):
			seen[Vector2i(x, run.position.y)] = true
		if _balcony_texture == null:
			_balcony_texture = _load_picture(BALCONY_ART)
		if _balcony_texture == null:
			return
		var width := run.size.x * size.x
		var ratio := width / BALCONY_ART_WIDTH
		var at := Vector2(run.position.x * size.x, run.position.y * size.y - BALCONY_ART_BACK * ratio)
		for shadow: bool in [true, false]:
			var sprite := Sprite2D.new()
			sprite.texture = _balcony_texture
			sprite.centered = false
			sprite.scale = Vector2(ratio, ratio)
			sprite.position = at + (BALCONY_SHADOW_AT * width if shadow else Vector2.ZERO)
			if shadow:
				sprite.modulate = BALCONY_SHADOW
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			holder.add_child(sprite)


## The picture at `path`: its import, or (a picture the editor has not imported yet) its file.
static func _load_picture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image != null else null


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

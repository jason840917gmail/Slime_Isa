@tool
class_name InteriorWallLayer
extends TileMapLayer
## Interior walls, Zelda's bevelled frame (docs/godot/INTERIOR_WALLS.md): Add Node > InteriorWallLayer
## in a room scene (beside the ground layer, same grid, name it `interior-walls`) and paint the
## room's rim, two cells thick, from its palette (game/world/interior/interior_wall_tileset.tres).
## Every side of the room is a wall FACE seen from above, sloping up and away from the floor, two
## cells deep on every side: a north face of horizontal courses seen from the front, a south face
## the same sloping the other way, east and west faces of vertical courses; the faces meet on 45
## degree mitres at the corners (outer corners where the floor turns convex, inner ones where it
## turns concave), so the wall bends round a room of any shape by itself. Floor is every cell the
## painted walls enclose.
##
## An opening is painted over the two-by-two block of its face (two along, two deep) with an opening
## tile: doorway, cracked, blown, stairs. The block draws that side's opening piece, cut into the
## face in its perspective, and its passage is open in the collision (`interior.gapUnits` wide, the
## jambs solid); a cracked stretch is solid until blown. The door objects (key doors, bolted doors,
## shutters, the seal, cracked walls) stand on the floor line in the passage and keep their logic;
## with `frame_drawn_by_wall` they draw only their leaf from the style's sheet, which fills the
## opening exactly (`leaf_at`).
##
## The pieces come from scripts/art/pack-interior-walls.py; this draws them (nothing it draws is
## saved: the layer keeps only its cells, and the closed doors' objects are the room's own nodes).
## They lie under every body (z -1): bodies walk over a face's foot as in Zelda. Every wall cell is
## solid but an opening's passage. The palette squares show in the editor only.
##
## Owner: world (interior walls).

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const FILL_SCRIPT := preload("res://game/world/interior/interior_wall_fill.gd")
const PaintedObjects := preload("res://game/world/painted_objects.gd")
const NodeFind := preload("res://game/shared/node_find.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
## The `elevation` layer's level data layer (Elevation.LEVEL_DATA_LAYER): how its layer is found.
const ELEVATION_DATA := "elevation_level"

const TILESET := "res://game/world/interior/interior_wall_tileset.tres"
const TABLE := "res://asset/MAPS/walls/interior/interior-walls.json"
const STYLE_DATA := "interior_style"
const OPENING_DATA := "interior_opening"
const GROUP := &"interior_walls"
const HOLDER := "Walls"
const FLOOR_HOLDER := "Floor"
const FRONTS := "Fronts"
const COLLISION := "Collision"
const CELL := 64.0
## Sheet px per unit.
const DENSITY := 2.0
## The face's depth, cells.
const DEPTH := 2
const SIDES := {"n": Vector2i.UP, "s": Vector2i.DOWN, "w": Vector2i.LEFT, "e": Vector2i.RIGHT}
const WALL_SIDE := {"north": "n", "south": "s", "west": "w", "east": "e"}
const SIDE_WALL := {"n": "north", "s": "south", "w": "west", "e": "east"}
## Closed doors painted on the layer (palette rows 5..11): the opening is a doorway and the layer
## keeps a door object of that kind in it (`sync_doors`). Kind -> its scene and settings.
const DOOR_KINDS := {
	"key1": {"scene": "res://game/scenes/objects/dungeon/key-door.tscn", "props": {"keyholes": 1}},
	"key2": {"scene": "res://game/scenes/objects/dungeon/key-door.tscn", "props": {"keyholes": 2}},
	"boss": {"scene": "res://game/scenes/objects/dungeon/boss-door.tscn", "props": {}},
	"bolt": {"scene": "res://game/scenes/objects/dungeon/bolted-door.tscn", "props": {}},
	"shutter": {"scene": "res://game/scenes/objects/dungeon/shutter.tscn", "props": {}},
	"seal": {"scene": "res://game/scenes/objects/dungeon/dungeon-seal.tscn", "props": {}},
	"barricade": {"scene": "res://game/scenes/objects/plank-barricade.tscn", "props": {}},
}
## The meta a door object made (or adopted) by the layer carries: its opening's block ("x,y", the
## block's top-left cell on this layer) and its kind.
const DOOR_BLOCK_META := &"interior_door_block"
const DOOR_KIND_META := &"interior_door_kind"
const DOOR_TAGS: Array[StringName] = [DOOR_BLOCK_META, DOOR_KIND_META]
## How near (units) an untagged door must stand to an opening's spot to be adopted.
const ADOPT_REACH := 40.0
## How far (units) from a cracked block's middle a blast still opens it (`change_opening_at`).
const BLAST_REACH := CELL * 3.0
## How often (ms, real time) the editor looks for a repacked table or sheet (`_check_caches`).
const CACHE_CHECK_MS := 1000

## The floor and the pieces were laid again (the floor trim beside the layer follows: InteriorTrimLayer).
signal rebuilt

## How strongly the painted squares show over the walls in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.3:
	set(value):
		paint_opacity = value
		_apply_opacity()

## Draws the style's floor (a seamless texture, `floor` in the table) over the room's floor cells,
## over the ground layer; off: the ground layer shows.
@export var draw_floor: bool = true:
	set(value):
		draw_floor = value
		_queue_rebuild()

## The style whose floor is drawn ("": the walls' own style; one without a floor draws none, the
## ground layer shows). A cave-rock room on cobble takes "lair-stone"'s cobble.
@export var floor_style: String = "":
	set(value):
		floor_style = value
		_queue_rebuild()

var _queued := false
var _floors: Dictionary = {}
## The room each painted cell came from (cell -> room scene name), set by the dungeon shell as it
## gathers the room scenes' layers (room_scene_shell.gd): a wall faces only its own room's floor.
var cell_rooms: Dictionary = {}
## Each floor cell's camera room name ("" without camera rooms), after the build.
var _floor_rooms: Dictionary = {}
## camera room name -> the room scene whose walls it uses (its `walls_in` meta, else itself).
var _wall_owner: Dictionary = {}
## The drawn pieces: [{"piece": name, "cell": top-left cell, "style"}].
var _pieces: Array[Dictionary] = []
## Opening blocks: [{"side", "kind", "cell": top-left, "style"}].
var _openings: Array[Dictionary] = []
static var _table := {}
## The table file's modified time when it was read (the editor reads it again once it changes).
static var _table_time := 0
## The sheets read (path -> texture) and their files' modified times when read (`picture`).
static var _textures := {}
static var _texture_times := {}
## When (ms, real time) the editor last looked for a repacked table or sheet (`_check_caches`).
static var _checked_ms := -1


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	# the doorway fronts sort with the world's bodies (`_draw_fronts`)
	y_sort_enabled = true
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	_rebuild()


## The palette squares show in the editor only. The layer is enabled there whatever the scene says (a
## scene saved by a headless tool keeps the game's `enabled = false`, which hid the squares).
func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0
	enabled = Engine.is_editor_hint()


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild_queued.call_deferred()


## The queued rebuild, unless a direct one (`change_opening_at`) has drawn the change since.
func _rebuild_queued() -> void:
	if _queued:
		_rebuild()


## The styles' table (interior-walls.json).
static func table() -> Dictionary:
	_check_caches()
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		_table = parsed if parsed is Dictionary else {}
		_table_time = _modified(TABLE)
	return _table


## In the editor, drops the cached table and sheets whose files were written again since they were
## read (a repack shows on the layer's next redraw, without restarting the editor); checked at most
## every CACHE_CHECK_MS. The game reads them once.
static func _check_caches() -> void:
	if not Engine.is_editor_hint():
		return
	var now := Time.get_ticks_msec()
	if _checked_ms >= 0 and now - _checked_ms < CACHE_CHECK_MS:
		return
	_checked_ms = now
	if not _table.is_empty() and _modified(TABLE) != _table_time:
		_table = {}
	for path: String in _textures.keys():
		if _modified(path) != int(_texture_times.get(path, 0)):
			_textures.erase(path)
			_texture_times.erase(path)


## The file's modified time, 0 when it cannot be read (an exported game's packed files).
static func _modified(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0


static func _number(key: String, fallback: float) -> float:
	var constants := Services.constants()
	if constants == null:
		return fallback
	var found: Variant = constants.value("interior." + key, null)
	return float(found) if found != null else fallback


## The style painted on `cell`, or "".
func style_of(cell: Vector2i) -> String:
	var data := get_cell_tile_data(cell)
	if data == null or tile_set == null or not tile_set.has_custom_data_layer_by_name(STYLE_DATA):
		return ""
	return str(data.get_custom_data(STYLE_DATA))


## The opening kind painted on `cell` ("" for a plain wall or no wall).
func opening_of(cell: Vector2i) -> String:
	var data := get_cell_tile_data(cell)
	if data == null or tile_set == null or not tile_set.has_custom_data_layer_by_name(OPENING_DATA):
		return ""
	return str(data.get_custom_data(OPENING_DATA))


func is_wall(cell: Vector2i) -> bool:
	return not style_of(cell).is_empty()


## True when `cell` is floor: no wall there and enclosed by the painted walls.
func is_floor(cell: Vector2i) -> bool:
	return _floors.has(cell)


## True when the wall cell `wall` shows its face toward the floor cell `floor_cell` beside it (a wall
## of the floor's own room): the floor trim runs along it.
func faces(wall: Vector2i, floor_cell: Vector2i) -> bool:
	return is_wall(wall) and is_floor(floor_cell) and _faces_floor(wall, floor_cell)


## The drawn pieces after the build: [{"piece", "cell", "style"}] (a run "n0".., a corner "nw"..,
## an inner corner "in_se".., an opening "<side>_<kind>").
func pieces() -> Array[Dictionary]:
	return _pieces


## The opening blocks after the build: [{"side", "kind", "cell", "style"}].
func openings() -> Array[Dictionary]:
	return _openings


# --- reading the room ------------------------------------------------------------------------

## Floods the outside from round the painted cells' bounds: every other unpainted cell is floor.
func _find_floors() -> void:
	_floors.clear()
	_floor_rooms.clear()
	var used := get_used_rect()
	if not used.has_area():
		return
	var bounds := used.grow(1)
	var outside := {}
	var stack: Array[Vector2i] = []
	for x in range(bounds.position.x, bounds.end.x):
		stack.append(Vector2i(x, bounds.position.y))
		stack.append(Vector2i(x, bounds.end.y - 1))
	for y in range(bounds.position.y, bounds.end.y):
		stack.append(Vector2i(bounds.position.x, y))
		stack.append(Vector2i(bounds.end.x - 1, y))
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if outside.has(cell) or not bounds.has_point(cell) or is_wall(cell):
			continue
		outside[cell] = true
		for side: Vector2i in SIDES.values():
			stack.append(cell + side)
	var open_cells := {}
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var cell := Vector2i(x, y)
			if is_wall(cell):
				continue
			# floor is a room's own cells the walls enclose (never empty space outside the room)
			var room := _camera_room_at(cell)
			if room == "-":
				continue
			if outside.has(cell):
				open_cells[cell] = room
				continue
			_floors[cell] = true
			_floor_rooms[cell] = room
	# a room whose own walls enclose none of its cells (a pocket painted on two sides only: R1's
	# store, its other walls are its neighbour's) takes all its cells as floor
	var enclosed_rooms := {}
	for cell: Vector2i in _floor_rooms:
		enclosed_rooms[_floor_rooms[cell]] = true
	for cell: Vector2i in open_cells:
		var name := str(open_cells[cell])
		if not name.is_empty() and not enclosed_rooms.has(name):
			_floors[cell] = true
			_floor_rooms[cell] = name


## The camera rooms beside this layer (its parent's `CameraRooms`): their names and outlines, and
## whose walls each uses. Empty when there are none (the box-room tests, a bare layer).
func _camera_rooms() -> Array[Node]:
	var out: Array[Node] = []
	var holder := get_parent().get_node_or_null(^"CameraRooms") if get_parent() != null else null
	if holder != null:
		for node: Node in holder.get_children():
			if node.has_method(&"contains"):
				out.append(node)
	return out


## The name of the camera room holding `cell`'s middle: "" when the scene has no camera rooms, "-"
## when it has some and none holds it (empty space outside every room: never floor).
func _camera_room_at(cell: Vector2i) -> String:
	var rooms := _camera_rooms()
	if rooms.is_empty():
		return ""
	var at := to_global((Vector2(cell) + Vector2(0.5, 0.5)) * Vector2(tile_set.tile_size))
	for room in rooms:
		if bool(room.call(&"contains", at)):
			return String(room.name)
	return "-"


## True when the wall cell `wall` may show a face toward the floor cell `floor_cell`: both of one room
## (the wall's painting room, the floor's camera room or the room its walls are in).
func _faces_floor(wall: Vector2i, floor_cell: Vector2i) -> bool:
	if cell_rooms.is_empty():
		return true
	var painter := str(cell_rooms.get(wall, ""))
	if painter.is_empty():
		return true
	var room := str(_floor_rooms.get(floor_cell, ""))
	return room == painter or str(_wall_owner.get(room, room)) == painter


## The pieces: a two-deep strip of face behind every floor cell's wall side, a corner block at every
## vertex where the floor turns (one floor quadrant: outer, three: inner; an inner corner's block
## replaces the strips over it), an opening piece over each opening's first strip.
func _layout() -> void:
	_pieces.clear()
	_openings.clear()
	_wall_owner.clear()
	for room in _camera_rooms():
		_wall_owner[String(room.name)] = str(room.get_meta(&"walls_in", String(room.name)))
	var corner_cells := {}
	var used := get_used_rect().grow(1)
	for vy in range(used.position.y, used.end.y + 1):
		for vx in range(used.position.x, used.end.x + 1):
			# a corner turns for one room: the floor quadrants of the room its wall cells were painted in
			var corner_room := _vertex_room(vx, vy)
			var nw := _floor_of(Vector2i(vx - 1, vy - 1), corner_room)
			var ne := _floor_of(Vector2i(vx, vy - 1), corner_room)
			var sw := _floor_of(Vector2i(vx - 1, vy), corner_room)
			var se := _floor_of(Vector2i(vx, vy), corner_room)
			var count := int(nw) + int(ne) + int(sw) + int(se)
			var name := ""
			var at := Vector2i.ZERO
			if count == 1:
				if se:
					name = "nw"; at = Vector2i(vx - DEPTH, vy - DEPTH)
				elif sw:
					name = "ne"; at = Vector2i(vx, vy - DEPTH)
				elif ne:
					name = "sw"; at = Vector2i(vx - DEPTH, vy)
				else:
					name = "se"; at = Vector2i(vx, vy)
			elif count == 3:
				# the wall block sits in the quadrant without floor
				if not nw:
					name = "in_se"; at = Vector2i(vx - DEPTH, vy - DEPTH)
				elif not ne:
					name = "in_sw"; at = Vector2i(vx, vy - DEPTH)
				elif not sw:
					name = "in_ne"; at = Vector2i(vx - DEPTH, vy)
				else:
					name = "in_nw"; at = Vector2i(vx, vy)
				for j in DEPTH:
					for i in DEPTH:
						corner_cells[at + Vector2i(i, j)] = true
			if not name.is_empty():
				_pieces.append({"piece": name, "cell": at, "style": _style_near(at)})
	for floor_cell: Vector2i in _floors:
		for side: String in SIDES:
			var d: Vector2i = SIDES[side]
			var first := floor_cell + d
			if not is_wall(first) or corner_cells.has(first) or not _faces_floor(first, floor_cell):
				continue
			var top_left := _strip_top_left(floor_cell, side)
			var style := style_of(first)
			var period := _period(style, side)
			var along := floor_cell.x if side == "n" or side == "s" else floor_cell.y
			_pieces.append({"piece": side + str(posmod(along, period)), "cell": top_left, "style": style})
			var kind := opening_of(first)
			if kind.is_empty():
				continue
			var step := Vector2i.RIGHT if side == "n" or side == "s" else Vector2i.DOWN
			if opening_of(first - step) == kind:
				continue
			_openings.append({"side": side, "kind": kind, "cell": top_left, "style": style,
				"draw": "doorway" if DOOR_KINDS.has(kind) else kind})
	for opening in _openings:
		_pieces.append({"piece": "%s_%s" % [opening["side"], opening["draw"]], "cell": opening["cell"], "style": opening["style"]})


## The room the wall cells round vertex (vx, vy) were painted in ("" when unknown or mixed).
func _vertex_room(vx: int, vy: int) -> String:
	if cell_rooms.is_empty():
		return ""
	for cell in [Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1), Vector2i(vx - 1, vy), Vector2i(vx, vy)]:
		if cell_rooms.has(cell):
			return str(cell_rooms[cell])
	return ""


## True when `cell` is floor of `room` (any room when `room` is "").
func _floor_of(cell: Vector2i, room: String) -> bool:
	if not is_floor(cell):
		return false
	if room.is_empty():
		return true
	var floor_room := str(_floor_rooms.get(cell, ""))
	return floor_room == room or str(_wall_owner.get(floor_room, floor_room)) == room


## The top-left cell of the two-deep strip of face behind `floor_cell` on `side`.
static func _strip_top_left(floor_cell: Vector2i, side: String) -> Vector2i:
	match side:
		"n":
			return floor_cell + Vector2i(0, -DEPTH)
		"s":
			return floor_cell + Vector2i(0, 1)
		"w":
			return floor_cell + Vector2i(-DEPTH, 0)
	return floor_cell + Vector2i(1, 0)


func _style_near(top_left: Vector2i) -> String:
	for j in DEPTH:
		for i in DEPTH:
			var style := style_of(top_left + Vector2i(i, j))
			if not style.is_empty():
				return style
	return ""


static func _period(style: String, side: String) -> int:
	var periods: Variant = (table().get(style, {}) as Dictionary).get("run_period", {})
	return maxi(1, int((periods as Dictionary).get(side, 3))) if periods is Dictionary else 3


## True for a run piece ("n0", "e2": its side and its place along the run), false for an outer corner
## ("nw", "ne", "sw", "se"), an inner corner or an opening.
static func _is_run(name: String) -> bool:
	return name.length() == 2 and name[1].is_valid_int()


# --- drawing ---------------------------------------------------------------------------------

func _rebuild() -> void:
	_queued = false
	if not is_inside_tree() or tile_set == null:
		return
	_find_floors()
	_layout()
	var holder := get_node_or_null(HOLDER) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = HOLDER
		add_child(holder)
	# under every body: a face's foot is walked over, as in Zelda
	holder.z_index = -1
	holder.z_as_relative = false
	for child in holder.get_children():
		child.free()
	var size := Vector2(tile_set.tile_size)
	# runs first, corners and openings over them (an opening's ends fade into its run)
	var order: Array[Dictionary] = []
	for p in _pieces:
		if _is_run(str(p["piece"])):
			order.append(p)
	for p in _pieces:
		if not order.has(p):
			order.append(p)
	for p in order:
		var sprite := piece_sprite(str(p["style"]), str(p["piece"]))
		if sprite == null:
			continue
		sprite.position = Vector2(p["cell"] as Vector2i) * size
		holder.add_child(sprite)
	_draw_fill(size, holder)
	_draw_fronts(size)
	_draw_floor(size)
	if not Engine.is_editor_hint():
		_build_collision(size)
	elif is_inside_tree() and get_tree().edited_scene_root != null and get_tree().edited_scene_root.is_ancestor_of(self):
		# painting a closed door makes its door object, erasing it lets it go (the editor only)
		sync_doors(true)
	rebuilt.emit()


## Keeps a door object in every opening painted with a closed door (DOOR_KINDS), under the room's
## `Objects` node (made when missing; doors grouped under plain nodes in it, `Objects/Doors`, count
## too): an untagged door of that kind already at the opening's spot is adopted (tagged), else (with
## `create`) one is made from the kind's scene, placed on the floor line in the middle of the passage,
## `wall` its side, `frame_drawn_by_wall` on, the layer's style, a unique `door_id`. A tagged door
## whose opening is no longer painted with its kind is let go (with `create`;
## game/world/painted_objects.gd `retire`): removed when the layer made it and nothing of it was
## changed since, else kept, untagged, with a warning, and adopted again when its block is painted
## back, so its settings (a door id, a fight id: save records) are never lost to a stroke or an undo.
## Returns the doors made.
func sync_doors(create: bool) -> int:
	var room := get_parent()
	if room == null or tile_set == null:
		return 0
	if _openings.is_empty() and get_used_cells().size() > 0:
		_find_floors()
		_layout()
	var objects := room.get_node_or_null(^"Objects")
	var owner_node := room.owner if room.owner != null else room
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		owner_node = get_tree().edited_scene_root
	var wanted := {}
	for opening in _openings:
		if DOOR_KINDS.has(str(opening["kind"])):
			var cell := opening["cell"] as Vector2i
			wanted["%d,%d" % [cell.x, cell.y]] = opening
	if objects == null:
		if wanted.is_empty() or not create:
			return 0
		objects = Node2D.new()
		objects.name = "Objects"
		(objects as Node2D).y_sort_enabled = true
		room.add_child(objects)
		objects.owner = owner_node
	var placed := objects_in(objects)
	var tagged := {}
	for node in placed:
		if node.has_meta(DOOR_BLOCK_META):
			tagged[str(node.get_meta(DOOR_BLOCK_META))] = node
	var made := 0
	for key: String in wanted:
		var opening: Dictionary = wanted[key]
		var kind := str(opening["kind"])
		var spot := _door_spot(opening)
		var node: Node = tagged.get(key)
		if node != null and str(node.get_meta(DOOR_KIND_META, "")) != kind:
			# repainted with another kind: the old door is let go, the new one comes
			if create:
				placed.erase(node)
				if not PaintedObjects.retire(node, DOOR_TAGS, "InteriorWallLayer"):
					placed.append(node)
			node = null
		if node == null:
			node = _adoptable(placed, kind, spot)
			if node != null:
				node.set_meta(DOOR_BLOCK_META, key)
				node.set_meta(DOOR_KIND_META, kind)
		if node == null and create:
			node = _make_door(objects, owner_node, placed, opening, key, spot)
			if node != null:
				placed.append(node)
				made += 1
		tagged.erase(key)
	if create:
		for key: String in tagged:
			PaintedObjects.retire(tagged[key] as Node, DOOR_TAGS, "InteriorWallLayer")
	return made


## Where a door stands for `opening` (in the Objects node's parent space: the layer's): the floor
## line in the middle of the passage.
func _door_spot(opening: Dictionary) -> Vector2:
	var cell := Vector2(opening["cell"] as Vector2i)
	var at: Vector2
	match str(opening["side"]):
		"n":
			at = (cell + Vector2(1, DEPTH)) * CELL
		"s":
			at = (cell + Vector2(1, 0)) * CELL
		"w":
			at = (cell + Vector2(DEPTH, 1)) * CELL
		_:
			at = (cell + Vector2(0, 1)) * CELL
	return position + at


## The objects under `objects`: its children and, through plain nodes that group them (no scene of
## their own: `Objects/Doors`), theirs. An object's own insides are not searched.
static func objects_in(objects: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in objects.get_children():
		out.append(node)
		if node.scene_file_path.is_empty() and node.get_script() == null:
			out.append_array(objects_in(node))
	return out


## `node`'s position in the room's space (this layer's parent's), through the nodes it is grouped in.
func _room_position(node: Node2D) -> Vector2:
	var xform := node.transform
	var up := node.get_parent()
	while up != null and up != get_parent():
		if up is Node2D:
			xform = (up as Node2D).transform * xform
		up = up.get_parent()
	return xform.origin


## An untagged door of `kind`'s scene among `placed` standing within ADOPT_REACH of `spot`, or null.
func _adoptable(placed: Array[Node], kind: String, spot: Vector2) -> Node:
	var scene := str(DOOR_KINDS[kind]["scene"])
	for node in placed:
		if node.has_meta(DOOR_BLOCK_META) or not node is Node2D or node.scene_file_path != scene:
			continue
		if kind == "key1" or kind == "key2":
			if int(node.get(&"keyholes")) != int(DOOR_KINDS[kind]["props"]["keyholes"]):
				continue
		if _room_position(node as Node2D).distance_to(spot) <= ADOPT_REACH:
			return node
	return null


func _make_door(objects: Node, owner_node: Node, placed: Array[Node], opening: Dictionary, key: String, spot: Vector2) -> Node:
	var kind := str(opening["kind"])
	var packed := load(str(DOOR_KINDS[kind]["scene"])) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node2D
	var side := str(opening["side"])
	var room_name := String(get_parent().name)
	# a name (and door id) of its own, beside a door of the same block kept for its settings (in
	# `Objects` or grouped deeper in it)
	var taken := {}
	for other in placed:
		taken[String(other.name)] = true
	var base := "%s-%s-%s" % [room_name, kind, key.replace(",", "-")]
	node.name = base
	var n := 2
	while taken.has(String(node.name)) or objects.has_node(NodePath(String(node.name))):
		node.name = "%s-%d" % [base, n]
		n += 1
	node.position = spot - ((objects as Node2D).position if objects is Node2D else Vector2.ZERO)
	var props: Dictionary = DOOR_KINDS[kind]["props"]
	for prop: String in props:
		node.set(prop, props[prop])
	node.set(&"wall", SIDE_WALL[side])
	node.set(&"frame_drawn_by_wall", true)
	if &"interior_style" in node:
		node.set(&"interior_style", str(opening["style"]))
	if &"door_id" in node:
		node.set(&"door_id", node.name)
	if &"shutter_id" in node:
		node.set(&"shutter_id", node.name)
	node.set_meta(DOOR_BLOCK_META, key)
	node.set_meta(DOOR_KIND_META, kind)
	objects.add_child(node)
	node.owner = owner_node
	PaintedObjects.remember(node)
	return node


## Each way-through opening's front (its jambs, lintel and the face round them, without the passage:
## the sheet's `<side>_<kind>_front`) drawn again among the bodies, y-sorted at the opening block's
## bottom edge: a body whose feet are in the passage is drawn under it (it walks under the lintel and
## between the jambs, as Zelda's doorway tiles cover Link), a body south of it (in the room below a
## north door) over it, so standing in front of a north door it still covers the face behind it.
func _draw_fronts(size: Vector2) -> void:
	var old := get_node_or_null(FRONTS)
	if old != null:
		old.free()
	var fronts := Node2D.new()
	fronts.name = FRONTS
	fronts.y_sort_enabled = true
	add_child(fronts)
	for opening in _openings:
		var draw := str(opening["draw"])
		if draw == "cracked":
			continue
		var sprite := piece_sprite(str(opening["style"]), "%s_%s_front" % [opening["side"], draw])
		if sprite == null:
			continue
		var top_left := Vector2(opening["cell"] as Vector2i) * size
		var sort := top_left + Vector2(size.x, size.y * DEPTH)
		sprite.position = sort
		sprite.offset = (top_left - sort) * DENSITY
		fronts.add_child(sprite)


## Wall cells no piece covers (deep rock: a thick wall's inside, a carved pocket's surroundings)
## are the dark beyond the faces, as Zelda draws past its frame.
func _draw_fill(size: Vector2, holder: Node2D) -> void:
	var covered := {}
	for p in _pieces:
		var name := str(p["piece"])
		# a run is one cell along by two deep; corners, inner corners and openings are 2 x 2
		var extent := Vector2i(DEPTH, DEPTH)
		if _is_run(name):
			extent = Vector2i(1, DEPTH) if name[0] == "n" or name[0] == "s" else Vector2i(DEPTH, 1)
		for j in extent.y:
			for i in extent.x:
				covered[(p["cell"] as Vector2i) + Vector2i(i, j)] = true
	var fill := Node2D.new()
	fill.name = "Fill"
	fill.set_script(FILL_SCRIPT)
	var cells: Array[Vector2i] = []
	for cell in get_used_cells():
		if is_wall(cell) and not covered.has(cell):
			cells.append(cell)
	fill.set(&"cells", cells)
	fill.set(&"cell_size", size)
	holder.add_child(fill)
	holder.move_child(fill, 0)


## The style's floor texture under every floor cell (the style of the nearest wall), its pattern
## following the world grid so neighbouring cells join.
func _draw_floor(size: Vector2) -> void:
	# the floor lies on the ground layer, before the elevation's drawing there, so a pit's rims, walls
	# and stairs (painted on the `elevation` layer) draw over it, in the editor as in the game
	var ground := _ground_layer()
	var host: Node = ground if ground != null else self
	var holder_name := "%s-%s" % [FLOOR_HOLDER, name]
	for node: Node in [get_node_or_null(FLOOR_HOLDER), host.get_node_or_null(holder_name)]:
		if node != null:
			node.free()
	if not draw_floor or _floors.is_empty() or _pieces.is_empty():
		return
	var holder := Node2D.new()
	holder.name = holder_name if ground != null else FLOOR_HOLDER
	if ground == null:
		holder.z_index = -2
		holder.z_as_relative = false
	host.add_child(holder)
	host.move_child(holder, 0)
	holder.position = (position - ground.position) if ground != null else Vector2.ZERO
	var cell_px := size.x * DENSITY
	# holes keep their own drawing, and the side and back stairs and ramps down into them (the
	# world's elevation layer beside this one, found by its tile set's level data: a room may name it
	# anything, R4's is "Elevation"); a raised floor (a level above 0) and a flight leading down to
	# level 0 or higher take the room's floor like level 0, which the elevation's tops then light by
	# their height (2026-11-13, the playground's cliff cave: they showed the ground layer's tiles),
	# and so does a front flight: it covers its cell but for the strip above its top step, the top's
	# floor (Elevation draws no approach in a room)
	var elevation := NodeFind.layer_with_data(get_parent(), ELEVATION_DATA)
	var levels: Dictionary = Elevation.painted_levels(ground) if elevation != null and ground != null else {}
	for cell: Vector2i in _floors:
		if elevation != null and elevation.get_cell_source_id(cell) >= 0 \
				and (ground == null or (int(levels.get(cell, 0)) < 0 and not _front_flight(elevation, cell))):
			continue
		var style := floor_style if not floor_style.is_empty() else _nearest_wall_style(cell)
		var entry: Dictionary = table().get(style, {})
		if str(entry.get("floor", "")).is_empty():
			continue
		var tile := float(entry.get("floor_px", 640))
		var at := Vector2(posmod(int(cell.x * cell_px), int(tile)), posmod(int(cell.y * cell_px), int(tile)))
		var sprite := _sprite(str(entry["floor"]), Rect2(at, Vector2(cell_px, cell_px)))
		sprite.position = Vector2(cell) * size
		holder.add_child(sprite)


## Whether `cell` is painted on `elevation` with a front flight of stairs (going down south, set into
## the face it leaves).
static func _front_flight(elevation: TileMapLayer, cell: Vector2i) -> bool:
	var data := elevation.get_cell_tile_data(cell)
	if data == null or not elevation.tile_set.has_custom_data_layer_by_name(Elevation.KIND_DATA_LAYER):
		return false
	var kind := str(data.get_custom_data(Elevation.KIND_DATA_LAYER))
	if kind == Elevation.STAIRS_KIND:
		return true
	return kind.begins_with(Elevation.STAIRS_KIND + "-") and Elevation.stairs_direction(kind).begins_with("s")


## The world's ground layer beside this one (the terrain tile set), or null.
func _ground_layer() -> TileMapLayer:
	var parent := get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var layer := child as TileMapLayer
		if layer != null and layer != self and layer.tile_set != null and layer.tile_set.resource_path == "res://game/world/terrain_tileset.tres":
			return layer
	return null


## The sheet at `path`, read once and shared by the walls, the floor and every door's leaf (the
## editor reads it again once the file is packed again: `_check_caches`).
static func picture(path: String) -> Texture2D:
	_check_caches()
	if not _textures.has(path):
		_textures[path] = _read_picture(path)
		_texture_times[path] = _modified(path)
	return _textures[path]


## The sheet's imported texture, unless the file was packed again after its import (an editor holds
## the project and has not imported it yet: the file is read itself), so a repack shows without an
## import (game/runtime/sheet_sprite.gd does the same for files never imported).
static func _read_picture(path: String) -> Texture2D:
	var file := ProjectSettings.globalize_path(path)
	var imported := file + ".import"
	if FileAccess.file_exists(imported) and FileAccess.file_exists(file) \
			and FileAccess.get_modified_time(file) > FileAccess.get_modified_time(imported):
		var image := Image.load_from_file(file)
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			return ImageTexture.create_from_image(image)
	return SheetSprite.load_picture(path)


## The interior style of the room `cell` lies in (its nearest wall's), "" outside the walls: the
## elevation gives a pit inside the room the matching cliff style (Elevation `_interior_style_at`).
func room_style_at(cell: Vector2i) -> String:
	if _floors.is_empty() and get_used_cells().size() > 0:
		_find_floors()
	if not _floors.has(cell) and not is_wall(cell):
		return ""
	return style_of(cell) if is_wall(cell) else _nearest_wall_style(cell)


## The style of the nearest wall straight out from `cell` (a room's floor takes its room's).
func _nearest_wall_style(cell: Vector2i) -> String:
	var best := ""
	var best_distance := 1 << 20
	for d: Vector2i in SIDES.values():
		for step in range(1, 64):
			var at := cell + d * step
			var style := style_of(at)
			if not style.is_empty():
				if step < best_distance:
					best_distance = step
					best = style
				break
			if not _floors.has(at):
				break
	return best


## A sprite of `style`'s piece `name`, its top-left at its origin; null when unknown.
static func piece_sprite(style: String, name: String) -> Sprite2D:
	var entry: Dictionary = table().get(style, {})
	var rect: Array = (entry.get("pieces", {}) as Dictionary).get(name, [])
	if rect.is_empty():
		return null
	return _sprite(str(entry["texture"]), Rect2(rect[0], rect[1], rect[2], rect[3]))


static func _sprite(path: String, region: Rect2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = picture(path)
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.scale = Vector2.ONE / DENSITY
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


## Where a door's leaf goes: for a door object on the floor line in the middle of an opening's
## passage (`wall` the wall of the room its face looks into), the sheet region of `style`'s leaf
## `kind` for that side and the leaf's top-left as an offset from the door, in world units (upright,
## unturned). Empty when the style has no such leaf.
static func leaf_at(style: String, wall: String, kind: String) -> Dictionary:
	var side: String = WALL_SIDE.get(wall, "n")
	var entry: Dictionary = table().get(style, {})
	var leaf: Dictionary = (entry.get("leaves", {}) as Dictionary).get("%s_%s" % [side, kind], {})
	if leaf.is_empty():
		return {}
	var region: Array = leaf["region"]
	var inside: Array = leaf["in_opening"]
	var span := CELL * DEPTH
	# the opening piece's top-left from the door (two cells along, two deep)
	var top_left: Vector2
	match side:
		"n":
			top_left = Vector2(-span * 0.5, -span)
		"s":
			top_left = Vector2(-span * 0.5, 0.0)
		"w":
			top_left = Vector2(-span, -span * 0.5)
		_:
			top_left = Vector2(0.0, -span * 0.5)
	return {"texture": str(entry["texture"]), "region": Rect2(region[0], region[1], region[2], region[3]),
		"offset": top_left + Vector2(float(inside[0]), float(inside[1])) / DENSITY,
		"size": Vector2(float(region[2]), float(region[3])) / DENSITY}


## Every wall cell is solid but an opening's passage (`interior.gapUnits` wide in the middle of a north
## or south block, `interior.sideGapUnits` tall in the middle of an east or west one, through its
## whole depth); a cracked stretch is solid until blown.
func _build_collision(size: Vector2) -> void:
	var old := get_node_or_null(COLLISION)
	if old != null:
		old.free()
	var body := StaticBody2D.new()
	body.name = COLLISION
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var gap := _number("gapUnits", 64.0)
	# a side door's passage is taller, centred on its block like a north or south one's: taller than
	# the drawn passage (about 64), as the slime walks it at its feet; a door object's body (at least
	# 128 long) still closes it whole
	var side_gap := _number("sideGapUnits", 120.0)
	var passage := {}
	var passages: Array[Rect2] = []
	for opening in _openings:
		if str(opening["kind"]) == "cracked":
			continue
		var top_left := Vector2(opening["cell"] as Vector2i) * size
		var horizontal := str(opening["side"]) == "n" or str(opening["side"]) == "s"
		var block := Vector2(DEPTH, DEPTH) * size
		var rect := Rect2(top_left + Vector2((block.x - gap) * 0.5, 0.0), Vector2(gap, block.y)) if horizontal \
			else Rect2(top_left + Vector2(0.0, (block.y - side_gap) * 0.5), Vector2(block.x, side_gap))
		passages.append(rect)
		for j in DEPTH:
			for i in DEPTH:
				passage[(opening["cell"] as Vector2i) + Vector2i(i, j)] = rect
	for cell in get_used_cells():
		if not is_wall(cell):
			continue
		var cell_rect := Rect2(Vector2(cell) * size, size)
		if not passage.has(cell):
			_add_box(body, cell_rect)
			continue
		# the part of the cell beside the passage
		var open: Rect2 = passage[cell]
		for part in _subtract(cell_rect, open):
			_add_box(body, part)


static func _subtract(rect: Rect2, hole: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var cut := rect.intersection(hole)
	if not cut.has_area():
		out.append(rect)
		return out
	if cut.position.x > rect.position.x:
		out.append(Rect2(rect.position, Vector2(cut.position.x - rect.position.x, rect.size.y)))
	if cut.end.x < rect.end.x:
		out.append(Rect2(Vector2(cut.end.x, rect.position.y), Vector2(rect.end.x - cut.end.x, rect.size.y)))
	if cut.position.y > rect.position.y:
		out.append(Rect2(Vector2(cut.position.x, rect.position.y), Vector2(cut.size.x, cut.position.y - rect.position.y)))
	if cut.end.y < rect.end.y:
		out.append(Rect2(Vector2(cut.position.x, cut.end.y), Vector2(cut.size.x, rect.end.y - cut.end.y)))
	return out


static func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	if not rect.has_area():
		return
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)


## A cracked wall's hole: every cracked block within BLAST_REACH of `point` (world units) turns into
## `kind` ("blown"), so a crack painted in both rooms' rims opens on both sides; a doorway or a door's
## block nearby never changes. The wall redraws once. Returns false when no cracked block is there.
func change_opening_at(point: Vector2, kind: String) -> bool:
	var size := Vector2(tile_set.tile_size)
	var at := to_local(point)
	var changed_any := false
	for opening in _openings:
		if str(opening["kind"]) != "cracked":
			continue
		var centre := (Vector2(opening["cell"] as Vector2i) + Vector2(DEPTH, DEPTH) * 0.5) * size
		if centre.distance_to(at) > BLAST_REACH:
			continue
		var tile := _tile_for(str(opening["style"]), kind)
		if tile.x < 0:
			continue
		var from := opening["cell"] as Vector2i
		for j in DEPTH:
			for i in DEPTH:
				if is_wall(from + Vector2i(i, j)):
					set_cell(from + Vector2i(i, j), 0, tile)
		changed_any = true
	if not changed_any:
		return false
	# the cells' change signal comes now, so the rebuild it queues is dropped for this direct one
	update_internals()
	_rebuild()
	return true


## The palette tile painting `style` with opening `kind` ("" for a plain wall); (-1, -1) when none.
func _tile_for(style: String, kind: String) -> Vector2i:
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		return Vector2i(-1, -1)
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if str(data.get_custom_data(STYLE_DATA)) == style and str(data.get_custom_data(OPENING_DATA)) == kind:
			return coords
	return Vector2i(-1, -1)


## The interior wall layer of the current world, or null.
static func find(tree: SceneTree) -> InteriorWallLayer:
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node is InteriorWallLayer and node.is_inside_tree():
			return node as InteriorWallLayer
	return null

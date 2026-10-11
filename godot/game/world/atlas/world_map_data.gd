extends RefCounted
## The world layout (docs/godot/WORLD_ATLAS.md): res://game/data/world-map.json, a sketch of the
## whole overworld on a grid of cells (one cell = `tiles_per_cell` x `tiles_per_cell` tiles) cut
## into chunks (A1 is the north-west chunk), with the regions that own the cells, the scene of each
## region (`world`) and its interiors, markers and the passages between touching regions.
##
## The sketch tool (scripts/story/world-map, pnpm story:map) paints it; the world atlas
## (game/dev/world_atlas.tscn) moves regions on it; godot/tools/build_region_worlds.gd builds the
## placeholder region worlds and writes the passages; the in-game world map draws it.
##
## Layout edits move whole blocks of chunks with everything on them (all three grids, markers and
## passages), so nothing is lost: `swap_blocks` exchanges two blocks of the same size, `shift_block`
## slides a block one chunk and puts the strip it covers on the side it left, and `move_region`
## does either for a region's chunk block (a slide only along one axis, so the opposite move undoes
## it). `preview_move` says which regions a move would tear apart (a region that ends up in more
## pieces); the atlas and the sketch tool refuse those moves.
##
## Saving refuses to overwrite a file that changed on disk since it was read or saved
## (`changed_on_disk`), unless forced.
##
## Owner: world (atlas).

const Self := preload("res://game/world/atlas/world_map_data.gd")

const PATH := "res://game/data/world-map.json"
const FORMAT := "slime-isa-world-map"
const VERSION := 2
const GRIDS: Array[String] = ["terrain", "elevation", "regionCells"]
const NO_REGION := "."
const COLUMN_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

## Everything in the file but the grids, in file order (regions, markers, passages, ...).
var head: Dictionary = {}
## layer name -> rows (one PackedByteArray of ASCII characters per row).
var grids: Dictionary = {}
var cols := 0
var rows := 0
var chunk_cols := 1
var chunk_rows := 1
var tiles_per_cell := 2
var tile_size := 64
## Where the map was read from (save writes it back there by default).
var path := PATH
## The file's text when it was read or last saved ("" for a map not read from a file).
var disk_text := ""


# --- loading and saving ---------------------------------------------------------------------

## The map at `file`, or null (with an error pushed) when it is missing or not a world map.
static func load_file(file: String = PATH) -> Self:
	if not FileAccess.file_exists(file):
		push_error("WorldMapData: no world map at %s" % file)
		return null
	var text := FileAccess.get_file_as_string(file)
	var map := from_dictionary(JSON.parse_string(text))
	if map != null:
		map.path = file
		map.disk_text = text
	return map


## A map from a parsed JSON value, or null when it is not a world map.
static func from_dictionary(parsed: Variant) -> Self:
	if not parsed is Dictionary or str((parsed as Dictionary).get("format", "")) != FORMAT:
		push_error("WorldMapData: not a %s file" % FORMAT)
		return null
	var source := parsed as Dictionary
	var map := Self.new()
	for key: String in source:
		if not GRIDS.has(key):
			map.head[key] = source[key]
	map.cols = int(source.get("cols", 0))
	map.rows = int(source.get("rows", 0))
	var chunks: Dictionary = source.get("chunks", {})
	map.chunk_cols = maxi(1, int(chunks.get("cols", 1)))
	map.chunk_rows = maxi(1, int(chunks.get("rows", 1)))
	map.tiles_per_cell = maxi(1, int(source.get("tilesPerCell", 2)))
	map.tile_size = maxi(1, int(source.get("tileSize", 64)))
	for layer in GRIDS:
		var out: Array[PackedByteArray] = []
		var lines: Array = source.get(layer, [])
		var fill := "0" if layer == "elevation" else "."
		for y in map.rows:
			var line := str(lines[y]) if y < lines.size() else ""
			var bytes := line.rpad(map.cols, fill).substr(0, map.cols).to_ascii_buffer()
			out.append(bytes)
		map.grids[layer] = out
	for key in ["regions", "markers", "passages"]:
		if not map.head.get(key) is Array:
			map.head[key] = []
	return map


## The whole map as a Dictionary (the head, then the grids), numbers that are whole kept as ints.
func to_dictionary() -> Dictionary:
	var out: Dictionary = _ints(head.duplicate(true))
	for layer in GRIDS:
		var lines: Array[String] = []
		for row: PackedByteArray in grids[layer]:
			lines.append(row.get_string_from_ascii())
		out[layer] = lines
	return out


## The file text, laid out like the sketch tool's server (scripts/story/world-map/server.mjs
## formatMap): the head indented with tabs, then one grid row per line.
func to_text() -> String:
	var text := JSON.stringify(_ints(head.duplicate(true)), "\t", false)
	text = text.trim_suffix("\n}")
	for layer in GRIDS:
		var lines := PackedStringArray()
		for row: PackedByteArray in grids[layer]:
			lines.append("\t\t" + JSON.stringify(row.get_string_from_ascii()))
		text += ",\n\t\"%s\": [\n%s\n\t]" % [layer, ",\n".join(lines)]
	return text + "\n}\n"


## Writes the map (default: where it was read from), keeping the previous file as <file>.bak.
## Returns ERR_ALREADY_IN_USE, writing nothing, when the file it was read from changed on disk since
## (someone else saved it: the sketch tool, the atlas or the region builder), unless `force`.
func save_file(file: String = "", force: bool = false) -> Error:
	var target := file if file != "" else path
	if not force and target == path and changed_on_disk():
		push_warning("WorldMapData: %s changed on disk since it was read; not saved (read it again)" % target)
		return ERR_ALREADY_IN_USE
	if FileAccess.file_exists(target):
		var previous := FileAccess.get_file_as_string(target)
		var backup := FileAccess.open(target + ".bak", FileAccess.WRITE)
		if backup != null:
			backup.store_string(previous)
			backup.close()
	var out := FileAccess.open(target, FileAccess.WRITE)
	if out == null:
		return FileAccess.get_open_error()
	var text := to_text()
	out.store_string(text)
	out.close()
	if target == path:
		disk_text = text
	return OK


## True when the file the map was read from no longer holds what was read (or last saved).
func changed_on_disk() -> bool:
	if disk_text == "" or not FileAccess.file_exists(path):
		return false
	return FileAccess.get_file_as_string(path) != disk_text


static func _ints(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)) and absf(value) < 1e15:
		return int(value)
	if value is Dictionary:
		for key: Variant in value:
			value[key] = _ints(value[key])
	elif value is Array:
		for i in (value as Array).size():
			value[i] = _ints(value[i])
	return value


# --- cells ----------------------------------------------------------------------------------

func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


## The character of `layer` ("terrain", "elevation", "regionCells") at `cell` ("" outside).
func cell_value(layer: String, cell: Vector2i) -> String:
	if not has_cell(cell):
		return ""
	return String.chr((grids[layer][cell.y] as PackedByteArray)[cell.x])


func set_cell_value(layer: String, cell: Vector2i, value: String) -> void:
	if has_cell(cell) and value.length() == 1:
		# Packed arrays are values: change the row, then put it back.
		var row: PackedByteArray = grids[layer][cell.y]
		row[cell.x] = value.unicode_at(0)
		grids[layer][cell.y] = row


func terrain_at(cell: Vector2i) -> String:
	return cell_value("terrain", cell)


func elevation_at(cell: Vector2i) -> int:
	var value := cell_value("elevation", cell)
	return int(value) if value != "" else 0


func region_key_at(cell: Vector2i) -> String:
	return cell_value("regionCells", cell)


# --- chunks ---------------------------------------------------------------------------------

## Cells per chunk (the grid is cut evenly; the map size is a whole number of chunks).
func chunk_cells() -> Vector2i:
	return Vector2i(cols / chunk_cols, rows / chunk_rows)


## Tiles per chunk (32 x 32 for the 8 x 8 chunk overworld).
func chunk_tiles() -> Vector2i:
	return chunk_cells() * tiles_per_cell


## World units per chunk (2048 x 2048).
func chunk_units() -> Vector2:
	return Vector2(chunk_tiles() * tile_size)


## World units per cell.
func cell_units() -> float:
	return float(tiles_per_cell * tile_size)


## "A1" for the north-west chunk.
static func chunk_name(chunk: Vector2i) -> String:
	var letter := COLUMN_LETTERS[chunk.x] if chunk.x >= 0 and chunk.x < COLUMN_LETTERS.length() else "?"
	return "%s%d" % [letter, chunk.y + 1]


## The cells of a chunk rectangle (chunk coordinates) as a cell rectangle.
func chunk_rect_cells(chunks: Rect2i) -> Rect2i:
	return Rect2i(chunks.position * chunk_cells(), chunks.size * chunk_cells())


func chunk_of_cell(cell: Vector2i) -> Vector2i:
	var size := chunk_cells()
	return Vector2i(floori(float(cell.x) / size.x), floori(float(cell.y) / size.y))


# --- regions --------------------------------------------------------------------------------

func regions() -> Array:
	return head.get("regions", [])


func markers() -> Array:
	return head.get("markers", [])


func passages() -> Array:
	return head.get("passages", [])


## The region with `key` ({} when none).
func region(key: String) -> Dictionary:
	for entry: Dictionary in regions():
		if str(entry.get("key", "")) == key:
			return entry
	return {}


## The region whose overworld scene (`world`) or one of whose interiors is `map_id` ({} when none).
func region_for_map(map_id: String) -> Dictionary:
	for entry: Dictionary in regions():
		if str(entry.get("world", "")) == map_id or (entry.get("interiors", []) as Array).has(map_id):
			return entry
	return {}


## The cells of region `key`.
func region_cells(key: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if key.length() != 1:
		return out
	var code := key.unicode_at(0)
	var rows_of: Array = grids["regionCells"]
	for y in rows:
		var row: PackedByteArray = rows_of[y]
		for x in cols:
			if row[x] == code:
				out.append(Vector2i(x, y))
	return out


## The chunks region `key` holds most of (more than half the chunk's cells), in reading order.
func region_chunks(key: String) -> Array[Vector2i]:
	var counts := {}
	for cell in region_cells(key):
		var chunk := chunk_of_cell(cell)
		counts[chunk] = int(counts.get(chunk, 0)) + 1
	var half := chunk_cells().x * chunk_cells().y / 2
	var out: Array[Vector2i] = []
	for chunk: Vector2i in counts:
		if int(counts[chunk]) > half:
			out.append(chunk)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## The bounding block of region `key`'s chunks (chunk coordinates; empty when it has none).
func region_chunk_rect(key: String) -> Rect2i:
	var chunks := region_chunks(key)
	if chunks.is_empty():
		return Rect2i()
	var rect := Rect2i(chunks[0], Vector2i.ONE)
	for chunk in chunks:
		rect = rect.expand(chunk).expand(chunk + Vector2i.ONE)
	return rect


## True when region `key` fills its bounding block (a rectangle of whole chunks) and has no cell
## outside it: such a region can be moved and swapped.
func region_is_rect(key: String) -> bool:
	var rect := region_chunk_rect(key)
	if not rect.has_area() or key.length() != 1:
		return false
	var cells := chunk_rect_cells(rect)
	if region_cells(key).size() != cells.size.x * cells.size.y:
		return false
	var code := key.unicode_at(0)
	var rows_of: Array = grids["regionCells"]
	for y in range(cells.position.y, cells.end.y):
		var row: PackedByteArray = rows_of[y]
		for x in range(cells.position.x, cells.end.x):
			if row[x] != code:
				return false
	return true


## How many separate pieces (4-connected groups of cells) each region has: region key -> count.
func region_pieces() -> Dictionary:
	var counts := {}
	var rows_of: Array = grids["regionCells"]
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var none := NO_REGION.unicode_at(0)
	for y in rows:
		for x in cols:
			var code: int = (rows_of[y] as PackedByteArray)[x]
			if code == none or seen[y * cols + x] == 1:
				continue
			var key := String.chr(code)
			counts[key] = int(counts.get(key, 0)) + 1
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * cols + x] = 1
			while not stack.is_empty():
				var cell: Vector2i = stack.pop_back()
				for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
					var next := cell + step
					if not has_cell(next) or seen[next.y * cols + next.x] == 1:
						continue
					if (rows_of[next.y] as PackedByteArray)[next.x] == code:
						seen[next.y * cols + next.x] = 1
						stack.append(next)
	return counts


## Where region `key`'s world scene sits in the overworld (world units of its block's corner).
func region_origin(key: String) -> Vector2:
	return Vector2(region_chunk_rect(key).position) * chunk_units()


## The region keys that touch `key` across a cell edge (4-neighbours), each once.
func neighbours(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	var code := key.unicode_at(0) if key.length() == 1 else -1
	for cell in region_cells(key):
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var other := region_key_at(cell + step)
			if other != "" and other != NO_REGION and other.unicode_at(0) != code and not out.has(other):
				out.append(other)
	return out


## A number that changes whenever the layout (grids or region scenes) changes: placeholder worlds
## record it, so the atlas can tell when they are out of date.
func layout_hash() -> int:
	var parts: Array = [cols, rows, chunk_cols, chunk_rows, tiles_per_cell, tile_size]
	for layer in GRIDS:
		for row: PackedByteArray in grids[layer]:
			parts.append(row.get_string_from_ascii())
	for entry: Dictionary in regions():
		parts.append([entry.get("key", ""), entry.get("world", ""), entry.get("theme", ""), entry.get("placeholder", false)])
	# The builder routes roads to markers and names openings after them.
	for marker: Dictionary in markers():
		parts.append([marker.get("type", ""), int(marker.get("x", 0)), int(marker.get("y", 0)), marker.get("label", "")])
	return hash(parts)


# --- moving blocks --------------------------------------------------------------------------

## Exchanges two equal, non-overlapping blocks of chunks with everything on them. False when
## they differ in size, overlap or leave the map.
func swap_blocks(a: Rect2i, b: Rect2i) -> bool:
	if a.size != b.size or a.intersects(b) or not _inside(a) or not _inside(b) or not a.has_area():
		return false
	var ca := chunk_rect_cells(a)
	var cb := chunk_rect_cells(b)
	var delta := cb.position - ca.position
	var moves := {}
	for y in range(ca.position.y, ca.end.y):
		for x in range(ca.position.x, ca.end.x):
			var cell := Vector2i(x, y)
			moves[cell] = cell + delta
			moves[cell + delta] = cell
	_apply_moves(moves)
	return true


## Slides block `block` one chunk towards `step` (a unit vector); the strip of chunks it slides
## onto goes to the side it left. False when the block would leave the map.
func shift_block(block: Rect2i, step: Vector2i) -> bool:
	if absi(step.x) + absi(step.y) != 1 or not block.has_area() or not _inside(block):
		return false
	var union := block.merge(Rect2i(block.position + step, block.size))
	if not _inside(union):
		return false
	var cells := chunk_rect_cells(union)
	var along := cells.size.x if step.x != 0 else cells.size.y
	var by := chunk_cells().x if step.x != 0 else chunk_cells().y
	var moves := {}
	for y in range(cells.position.y, cells.end.y):
		for x in range(cells.position.x, cells.end.x):
			var cell := Vector2i(x, y)
			var offset := (x - cells.position.x) if step.x != 0 else (y - cells.position.y)
			var moved := posmod(offset + (by if step.x + step.y > 0 else -by), along)
			moves[cell] = Vector2i(cells.position.x + moved, y) if step.x != 0 else Vector2i(x, cells.position.y + moved)
	_apply_moves(moves)
	return true


## Moves region `key`'s chunk block so its north-west chunk lands on `to`: onto a block it does
## not overlap by swapping the two blocks (a region there moves to where this one was), else by
## sliding it chunk by chunk along one axis (a diagonal slide is refused: its opposite would not
## undo it). False when the region is not a rectangle of whole chunks or the move leaves the map.
func move_region(key: String, to: Vector2i) -> bool:
	if not region_is_rect(key):
		return false
	var from := region_chunk_rect(key)
	var target := Rect2i(to, from.size)
	if target == from:
		return true
	if not _inside(target):
		return false
	if not target.intersects(from):
		return swap_blocks(from, target)
	if to.x != from.position.x and to.y != from.position.y:
		return false
	var block := from
	while block.position.x != to.x:
		var step := Vector2i(signi(to.x - block.position.x), 0)
		if not shift_block(block, step):
			return false
		block.position += step
	while block.position.y != to.y:
		var step := Vector2i(0, signi(to.y - block.position.y))
		if not shift_block(block, step):
			return false
		block.position += step
	return true


## A copy of the map to try edits on (saving it is guarded like the map's own save).
func duplicate_map() -> Self:
	var copy := Self.from_dictionary(to_dictionary())
	copy.path = path
	# A copy of a map read from a file keeps its guard against overwriting newer edits.
	copy.disk_text = disk_text
	return copy


## What `move_region(key, to)` would do, without doing it: {ok, broken (the other regions it
## would tear apart: in more pieces than before, or no longer a whole rectangle of chunks when they
## were one), swapped (the other regions whose block would move)}.
func preview_move(key: String, to: Vector2i) -> Dictionary:
	var copy := duplicate_map()
	var before := {}
	for entry: Dictionary in regions():
		var other := str(entry.get("key", ""))
		if other != key:
			before[other] = [region_is_rect(other), region_chunk_rect(other)]
	var pieces_before := region_pieces()
	var ok := copy.move_region(key, to)
	var broken := PackedStringArray()
	var swapped := PackedStringArray()
	if ok:
		var pieces_after := copy.region_pieces()
		for other: String in before:
			if int(pieces_after.get(other, 0)) > int(pieces_before.get(other, 0)) \
					or (bool(before[other][0]) and not copy.region_is_rect(other)):
				broken.append(other)
			elif copy.region_chunk_rect(other) != before[other][1]:
				swapped.append(other)
	return {"ok": ok, "broken": broken, "swapped": swapped}


func _inside(block: Rect2i) -> bool:
	return block.position.x >= 0 and block.position.y >= 0 and block.end.x <= chunk_cols and block.end.y <= chunk_rows


## Moves every cell `from` to `moves[from]` in all grids, and the markers and passages on them.
func _apply_moves(moves: Dictionary) -> void:
	for layer in GRIDS:
		var rows_of: Array = grids[layer]
		var old := {}
		for cell: Vector2i in moves:
			old[cell] = (rows_of[cell.y] as PackedByteArray)[cell.x]
		# Packed arrays are values: change copies of the rows, then put them back.
		var changed := {}
		for cell: Vector2i in moves:
			var to: Vector2i = moves[cell]
			if not changed.has(to.y):
				changed[to.y] = (rows_of[to.y] as PackedByteArray).duplicate()
			var row: PackedByteArray = changed[to.y]
			row[to.x] = old[cell]
			changed[to.y] = row
		for y: int in changed:
			rows_of[y] = changed[y]
	for list_key in ["markers", "passages"]:
		for item: Dictionary in head.get(list_key, []):
			var at := Vector2i(int(item.get("x", 0)), int(item.get("y", 0)))
			if moves.has(at):
				var to: Vector2i = moves[at]
				item["x"] = to.x
				item["y"] = to.y

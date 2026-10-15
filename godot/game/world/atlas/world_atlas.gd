@tool
extends Node2D
## The world atlas (docs/godot/WORLD_ATLAS.md): open game/dev/world_atlas.tscn in the editor to see
## the whole overworld of the world map (res://game/data/world-map.json) at once, every region's
## world scene side by side on the chunk grid, and to rearrange the regions.
##
## It draws the chunk grid with the chunk names (A1 is the north-west chunk), the world's frame,
## every region's outline and name, the passages between regions, the markers, the sketch's terrain
## colours where no world scene is shown (`sketch_under_worlds`: under the worlds too), every exit of
## the worlds as an arrow (green: it leads to the region across its edge, which leads back; amber:
## no way back; red: wrong) and the interiors on a shelf under the grid, below their region. A world
## smaller than its block shows the unused part hatched; the world of a region that is not a
## rectangle shows only its own cells. Every problem it finds is also listed in the atlas's
## configuration warnings (and on the slot of its region).
##
## The regions are slots (atlas_region.gd) saved in the scene. Drag one to move its region by whole
## chunks: dropped on a block it does not overlap, it swaps places with what is there; dropped
## overlapping its old place, it slides there along one axis. A move that would tear any region
## apart (WorldMapData.preview_move's `broken`: in more pieces than before, or a rectangle of
## chunks no longer whole) or slide diagonally over its old place is refused (drawn red; "Save
## layout" refuses too); regions that are not a rectangle of chunks (the Wilds, Volcano Ridge) are
## locked. Every drag is a new move, played after the ones before it on the layout as it is shown;
## while the mouse button is held the drag's move follows the mouse. Moves stay pending (dashed)
## until "Save layout" writes them to the world map (WorldMapData.move_region, in the order they
## were made; the old file is kept as .bak) and reloads. When the file changed on disk since the
## atlas read it (the sketch tool or the region builder saved it), Save layout plays the moves again
## on the new file, each checked like a new drop: it saves when they all still work, else it writes
## nothing and shows the new file with the moves that no longer work drawn red.
##
## The world scenes themselves never change: the placeholder worlds are rebuilt for a new layout by
## godot/tools/build_region_worlds.gd, and the exits of the real worlds are fixed in their own
## scenes ("Open world" on a slot).
##
## The world scenes are read from disk and instanced one per frame, so the editor stays usable
## while they load, as instances with no owner: never saved with the atlas and never selectable
## (the atlas's own helper nodes, the interior shelf and the painters, are locked groups).
## "Refresh worlds" reads them again after one was edited; a slot's `live` switches its world off.
##
## Owner: world (atlas).

## The queue of world scenes to read is empty (every world is instanced and checked).
signal worlds_ready

const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const AtlasRegion := preload("res://game/world/atlas/atlas_region.gd")
const WorldSurvey := preload("res://game/world/atlas/atlas_world_survey.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")

## The sketch's colour of each terrain (TERRAINS of the sketch tool, scripts/story/world-map/index.html).
const TERRAIN_COLORS := {
	".": Color("#23262e"), "g": Color("#5da544"), "f": Color("#357a38"), "p": Color("#b98d55"),
	"t": Color("#cfc6a8"), "h": Color("#8a5a2b"), "b": Color("#e4d08e"), "d": Color("#d6ad62"),
	"r": Color("#9a7444"), "m": Color("#5e4b3b"), "s": Color("#62a0e6"), "w": Color("#2f5cb8"),
	"x": Color("#5f6f3c"), "n": Color("#e9f1f6"), "i": Color("#a6dcec"), "l": Color("#e2531f"),
	"k": Color("#b58be3"), "c": Color("#3d3548"), "v": Color("#07070a"),
}
## The colour of each marker type (MARKERS of the sketch tool).
const MARKER_COLORS := {
	"gate": Color("#e8912c"), "cave": Color("#55456b"), "warp": Color("#3fb8c9"),
	"dungeon": Color("#c43c3c"), "boss": Color("#8e1f1f"), "town": Color("#d9b44a"),
	"house": Color("#a0663a"), "landmark": Color("#e3d35a"), "npc": Color("#5aa0e3"),
	"item": Color("#3fbf7f"), "secret": Color("#e05aa0"), "note": Color("#9aa1b2"),
}
## How much lighter the sketch gets per elevation step.
const ELEVATION_LIGHT := 0.07
const BACKGROUND := Color("#16181d")
const GRID_COLOR := Color(1, 1, 1, 0.3)
const FRAME_COLOR := Color("#f2e8c9")
const TEXT_COLOR := Color("#f7f3e8")
const PANEL_COLOR := Color(0.05, 0.06, 0.08, 0.8)
const SHADOW_COLOR := Color(0, 0, 0, 0.65)
const HATCH_COLOR := Color(0, 0, 0, 0.55)
const PASSAGE_COLOR := Color(1, 1, 1, 0.55)
const PENDING_COLOR := Color(1, 1, 1, 0.95)
const REFUSED_COLOR := Color("#ff4d5e")
const EXIT_COLORS := {"ok": Color("#57d977"), "one-way": Color("#ffb627"), "wrong": Color("#ff4d5e")}
## Drawing sizes, in world units (the atlas is seen far zoomed out).
const LINE := 16.0
const OUTLINE := 40.0
const FRAME := 64.0
const DASH := 192.0
const HATCH_SPACING := 192.0
const ARROW_LENGTH := 720.0
const ARROW_WIDTH := 72.0
const ARROW_HEAD := 260.0
const MARKER_RADIUS := 56.0
const PAD := 96.0
const CHUNK_FONT := 150
const NAME_FONT := 230
const INFO_FONT := 100
const BANNER_FONT := 170
## Room above the grid for the banner, and between the grid and the interior shelf.
const BANNER_SPACE := 760.0
const SHELF_GAP := 1024.0
## How far (cells) an exit inside its world may stand from the border of its region.
const BORDER_REACH := 8
## An interior card when its scene is unknown (world units).
const CARD_SIZE := Vector2(896.0, 704.0)
const SKETCH_Z := -100
const MARKS_Z := 100
## A moved world is instanced again this long after the last move (real time, the editor's).
const SETTLE_MS := 600
const SHELF_NODE := "Interiors"
const STALE_NOTE := "is a placeholder built for another layout."
const REBUILD_PLACEHOLDERS := "\"<Godot 4.7.2 console exe>\" --headless --path godot -s res://tools/build_region_worlds.gd"

## The world map shown and edited.
@export_file("*.json") var map_path: String = WorldMapData.PATH:
	set(value):
		map_path = value
		if is_node_ready():
			reload()
## The sketch's terrain colours where no world scene is shown.
@export var show_sketch := true:
	set(value):
		show_sketch = value
		_view_changed()
## The sketch under the world scenes too (it shows through where a world leaves its block unused).
@export var sketch_under_worlds := false:
	set(value):
		sketch_under_worlds = value
		_view_changed()
## The world scenes (each slot's `live` switches one off).
@export var show_live_worlds := true:
	set(value):
		show_live_worlds = value
		_worlds_switched()
@export var show_exits := true:
	set(value):
		show_exits = value
		_view_changed()
@export var show_markers := true:
	set(value):
		show_markers = value
		_view_changed()
## The interior shelf under the grid.
@export var show_interiors := true:
	set(value):
		show_interiors = value
		_worlds_switched()
@export_tool_button("Reload", "Reload") var reload_button: Callable = reload
@export_tool_button("Save layout", "Save") var save_button: Callable = save_layout
@export_tool_button("Refresh worlds", "Reload") var refresh_button: Callable = refresh_worlds

## The world map as saved, and with the pending moves applied (neither is ever changed in place).
var map: WorldMapData
var plan: WorldMapData
## The pending moves in the order they were made: [region key, chunk of its new corner].
var _moves: Array = []
## Region key -> why its move is refused.
var _refused: Dictionary = {}
## Region key -> its block in `map` / `plan` (`_blocks`).
var _saved_blocks: Dictionary = {}
var _plan_blocks: Dictionary = {}
## The saved map as the start of the plan: {plan, blocks, pieces} (`_survey`).
var _base: Dictionary = {}
## What each pending move did, in `_moves` order (`_step`): a drag replays only the moves after
## the last one that is unchanged.
var _steps: Array[Dictionary] = []
## Region key -> the outline segments of its cells in `plan` (pairs of points), and the plan they
## were traced on.
var _outlines: Dictionary = {}
var _outlined: WorldMapData
var _layout_hash := 0
var _index: Dictionary = {}
## Map id -> what WorldSurvey.read found in its scene ({} when it has no scene).
var _surveys: Dictionary = {}
## The exits of the worlds, judged: {key, exit, status, reason}.
var _exits: Array[Dictionary] = []
var _warnings := PackedStringArray()
## The last thing refused that has no region to show it on (a locked region dragged).
var _notice := ""
## Why the last Save layout wrote nothing (until the next change of the moves, Save or Reload).
var _save_note := ""
## Slots dragged onto another chunk since the last frame (`_flush_drags`).
var _dragged: Array[AtlasRegion] = []
var _flush_queued := false
## The first move made by the drag in progress (mouse button held), -1 when none.
var _drag_from := -1
## Slots waiting for their scene to be read and instanced, one per frame.
var _jobs: Array[Node2D] = []
var _settle_at := 0
var _sketch_texture: ImageTexture
var _sketch: Painter
var _marks: Painter
var _shelf: Node2D


func _ready() -> void:
	_sketch = _painter("Sketch", SKETCH_Z, _paint_sketch)
	_sketch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_marks = _painter("Marks", MARKS_Z, _paint_marks)
	_shelf = get_node_or_null(SHELF_NODE) as Node2D
	if _shelf == null:
		_shelf = Node2D.new()
		_shelf.name = SHELF_NODE
		add_child(_shelf)
	_lock(_shelf)
	reload()


func _process(_delta: float) -> void:
	if _drag_from >= 0 and not _mouse_held():
		_drag_from = -1
	if _settle_at > 0 and Time.get_ticks_msec() >= _settle_at:
		_settle_at = 0
		for holder in holders():
			var slot := holder as AtlasRegion
			if slot.world() != null and slot.built_at != slot.position:
				_queue(slot)
	if not _jobs.is_empty():
		var next: Variant = _jobs.pop_front()
		if is_instance_valid(next):
			_load(next as AtlasRegion)
		return
	if _settle_at == 0 and _drag_from < 0:
		set_process(false)
		worlds_ready.emit()


func _get_configuration_warnings() -> PackedStringArray:
	return _warnings


# --- buttons --------------------------------------------------------------------------------

## Reads the world map again and rebuilds everything (pending moves are dropped).
func reload() -> void:
	WorldChunks.reload()
	var loaded := WorldMapData.load_file(map_path)
	if loaded == null:
		_warnings = PackedStringArray(["Cannot read the world map %s." % map_path])
		_show_warnings({})
		return
	_moves.clear()
	_notice = ""
	_save_note = ""
	_adopt(loaded)


## Writes the pending moves to the world map (in the order they were made), then reloads. When the
## file changed on disk since the atlas read it, nothing is written: the atlas shows the new file
## with the moves played on it again (each checked like a new drop), marks the ones that no longer
## work, and the next Save layout writes what is shown.
func save_layout() -> void:
	if map == null:
		return
	if _flush_queued:
		_flush_drags()
	if not _refused.is_empty():
		push_warning("World atlas: Save layout refused: %s" % " ".join(PackedStringArray(_refused.values())))
		return
	if _moves.is_empty() or plan.to_text() == map.to_text():
		print("World atlas: no pending moves to save.")
		return
	# The plan is the saved map with the moves played on it (it keeps the map's guard against
	# overwriting newer edits).
	var error := ERR_ALREADY_IN_USE if map.changed_on_disk() else plan.save_file()
	if error == ERR_ALREADY_IN_USE:
		_save_over_newer()
	elif error != OK:
		_not_saved("cannot write %s (%s): nothing was saved; the moves are still pending." % [map.path, error_string(error)])
	else:
		_saved("")


## Save layout found the file changed on disk: plays the pending moves on the new file and saves
## it when every move still works; else adopts the new file with the moves still pending.
func _save_over_newer() -> void:
	var fresh := WorldMapData.load_file(map_path)
	if fresh == null:
		_not_saved("%s changed on disk and cannot be read now: nothing was saved; the moves are still pending." % map_path)
		return
	var out := fresh.duplicate_map()
	var refused := PackedStringArray()
	for move: Array in _moves:
		var reason := _move_problem(out, move[0], move[1])
		if reason == "" and not out.move_region(move[0], move[1]):
			reason = "%s cannot move to %s." % [_name(out, move[0]), WorldMapData.chunk_name(move[1])]
		if reason != "":
			refused.append(reason)
	var file := map_path.get_file()
	if refused.is_empty():
		# Nothing is written that was not on screen: show the new file with the moves played on it,
		# and let the next Save layout write it.
		_adopt(fresh)
		_not_saved("%s changed on disk since the atlas read it: nothing was saved yet. The pending moves were played again on the new file (shown): check it, then Save layout again." % file)
		return
	_adopt(fresh)
	_not_saved("%s changed on disk since the atlas read it: nothing was saved. On the new file (shown) %d of the pending moves no longer work (red): move them again or Reload, then Save layout." % [file, refused.size()],
			" ".join(refused))


## A save that wrote the file: tells the editor, prints what moved and reloads.
func _saved(how: String) -> void:
	var done := PackedStringArray()
	for move: Array in _moves:
		done.append("%s to %s" % [_name(map, move[0]), WorldMapData.chunk_name(move[1])])
	var editor := Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	var file_system: Object = editor.call(&"get_resource_filesystem") if editor != null else null
	if file_system != null:
		file_system.call(&"update_file", map.path)
	print("World atlas: saved %s%s (moved %s; the old file is %s.bak). Placeholder worlds need a rebuild: %s" % [
			map.path, how, ", ".join(done), map.path, REBUILD_PLACEHOLDERS])
	reload()


## A save that wrote nothing: says why (in the banner and the warnings; in the Output with `detail`).
func _not_saved(note: String, detail: String = "") -> void:
	_save_note = note
	push_warning("World atlas: Save layout: %s%s" % [note, " " + detail if detail != "" else ""])
	_check()
	_marks.queue_redraw()


## Shows `loaded` as the saved map: every slot on its block, the pending moves played on it again.
func _adopt(loaded: WorldMapData) -> void:
	map = loaded
	_layout_hash = map.layout_hash()
	var survey := _survey(map)
	_saved_blocks = survey["blocks"]
	_base = {"plan": map, "blocks": _saved_blocks, "pieces": survey["pieces"]}
	_steps.clear()
	_drag_from = -1
	_index = WorldSurvey.scene_index()
	_surveys.clear()
	sync_slots(map, _scene_owner())
	_sync_shelf()
	_replan()
	_queue_all()


## Reads every world scene again from disk and instances it anew (after editing one).
func refresh_worlds() -> void:
	_index = WorldSurvey.scene_index()
	WorldChunks.reload()
	for holder in holders():
		var slot := holder as AtlasRegion
		_assign_scene(slot)
		slot.clear_world()
	_surveys.clear()
	_check()
	_queue_all()


# --- slots ----------------------------------------------------------------------------------

## The region slots and the interior slots.
func holders() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child: Node in get_children():
		if child.get_script() == AtlasRegion:
			out.append(child as Node2D)
	if _shelf != null:
		for child: Node in _shelf.get_children():
			out.append(child as Node2D)
	return out


## True while world scenes are still waiting to be read and instanced.
func busy() -> bool:
	return not _jobs.is_empty() or _settle_at > 0


## Gives every region of `source` a slot (a new one owned by `scene_owner` when given, so the scene
## saves it), sets each up and puts it on its block. The regions that are not rectangles come
## first, so the rectangular ones over their bounding blocks draw and pick on top.
func sync_slots(source: WorldMapData, scene_owner: Node) -> void:
	var slots := _slots_by_key()
	var blocks := _blocks(source)
	var keys: Array[String] = []
	for whole: bool in [false, true]:
		for entry: Dictionary in source.regions():
			var key := str(entry.get("key", ""))
			if blocks.has(key) and bool(blocks[key]["whole"]) == whole:
				keys.append(key)
	var index := 0
	for key in keys:
		var slot := slots.get(key) as AtlasRegion
		if slot == null:
			slot = AtlasRegion.new()
			slot.name = str(source.region(key).get("id", key)).validate_node_name()
			slot.region_key = key
			add_child(slot)
			if scene_owner != null:
				slot.owner = scene_owner
		move_child(slot, index)
		index += 1
		var block: Dictionary = blocks[key]
		var rect: Rect2i = block["rect"]
		slot.map_id = str(source.region(key).get("world", ""))
		_assign_scene(slot)
		slot.chunk_units = source.chunk_units()
		slot.block_size = rect.size
		slot.grid_size = Vector2i(source.chunk_cols, source.chunk_rows)
		slot.set_meta(&"_edit_group_", true)
		if bool(block["whole"]):
			if slot.has_meta(&"_edit_lock_"):
				slot.remove_meta(&"_edit_lock_")
		else:
			slot.set_meta(&"_edit_lock_", true)
		slot.ensure_hit(slot.owner)
		if not slot.dragged.is_connected(_on_slot_dragged):
			slot.dragged.connect(_on_slot_dragged)
		if not slot.live_changed.is_connected(_on_live_changed):
			slot.live_changed.connect(_on_live_changed)
		slot.place(Vector2(rect.position) * source.chunk_units())


func _slots_by_key() -> Dictionary:
	var out := {}
	for child: Node in get_children():
		if child.get_script() == AtlasRegion:
			out[(child as AtlasRegion).region_key] = child
	return out


## The slot of region `key` (null when it has none).
func slot_of(key: String) -> AtlasRegion:
	return _slots_by_key().get(key) as AtlasRegion


## One unsaved slot per interior of every region, on the shelf.
func _sync_shelf() -> void:
	var wanted := {}
	for entry: Dictionary in map.regions():
		for interior: Variant in entry.get("interiors", []):
			wanted[str(interior)] = str(entry.get("key", ""))
	for child: Node in _shelf.get_children():
		var slot := child as AtlasRegion
		if slot == null or not wanted.has(slot.map_id) or wanted[slot.map_id] != slot.region_key:
			_shelf.remove_child(child)
			child.queue_free()
	var have := {}
	for child: Node in _shelf.get_children():
		have[(child as AtlasRegion).map_id] = true
	for interior: String in wanted:
		if have.has(interior):
			continue
		var slot := AtlasRegion.new()
		slot.interior = true
		slot.name = interior.validate_node_name()
		slot.map_id = interior
		slot.region_key = wanted[interior]
		_lock(slot)
		_shelf.add_child(slot)
	for child: Node in _shelf.get_children():
		var slot := child as AtlasRegion
		_assign_scene(slot)


## Interiors stand on the shelf under the grid, one per chunk width, from their region's column
## (left to right; a region whose column is taken moves along).
func _place_shelf() -> void:
	var pitch := plan.chunk_units().x
	var top := float(plan.rows) * plan.cell_units() + SHELF_GAP
	var keys: Array[String] = []
	for key: String in _plan_blocks:
		keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool:
		return (_plan_blocks[a]["first"] as Vector2i).x < (_plan_blocks[b]["first"] as Vector2i).x)
	var free_x := 0.0
	for key in keys:
		var x := maxf(float((_plan_blocks[key]["first"] as Vector2i).x) * pitch, free_x)
		for interior: Variant in plan.region(key).get("interiors", []):
			var slot := _shelf.get_node_or_null(NodePath(str(interior).validate_node_name())) as AtlasRegion
			if slot != null:
				slot.place(Vector2(x, top))
				x += pitch
		free_x = x


## A slot snapped onto another chunk: noted, and planned once at the end of the frame. (On every
## motion of a drag the editor puts the slot back where the drag began, then under the mouse: only
## where it ends counts.)
func _on_slot_dragged(slot: Node2D) -> void:
	var region := slot as AtlasRegion
	if region != null and not _dragged.has(region):
		_dragged.append(region)
	if not _flush_queued:
		_flush_queued = true
		_flush_drags.call_deferred()


## Turns the slots dragged since the last frame into pending moves and plans again, only when the
## moves changed.
func _flush_drags() -> void:
	_flush_queued = false
	var slots := _dragged
	_dragged = []
	if map == null:
		return
	var held := _mouse_held()
	if held:
		# Watch for the button's release: the next drag is a new move.
		set_process(true)
	else:
		_drag_from = -1
	# Where every dragged slot was dropped, read before any replan puts the slots back on their blocks
	# (several regions can be dragged at once).
	var drops: Array = []
	for slot in slots:
		if is_instance_valid(slot) and slot.get_parent() == self:
			drops.append([slot.region_key, slot.chunk()])
	var changed := false
	var snapped_back := false
	for drop: Array in drops:
		var key: String = drop[0]
		if _saved_blocks.has(key) and not bool(_saved_blocks[key]["whole"]):
			_notice = "%s is locked: it is not a rectangle of whole chunks, so it cannot move." % _name(map, key)
			snapped_back = true
			continue
		if changed:
			# Each slot's move is made on the layout with the moves before it shown.
			_replan()
			changed = false
		if _record_move(key, drop[1], held):
			_notice = ""
			changed = true
	if changed or snapped_back:
		_replan()


## Records region `key` dropped with its corner on `chunk`: true when the moves changed. A drag
## in progress moves its own move (dropped back where it began: no move); any other drop is a new
## move after the others (the region's refused moves, which changed nothing, are dropped).
func _record_move(key: String, chunk: Vector2i, held: bool) -> bool:
	if held and _drag_from >= 0:
		for i in range(_moves.size() - 1, _drag_from - 1, -1):
			if _moves[i][0] != key:
				continue
			if _moves[i][1] == chunk:
				return false
			if i < _steps.size() and _steps[i]["from"] == chunk:
				_moves.remove_at(i)
			else:
				_moves[i] = [key, chunk]
			return true
	var changed := false
	for i in range(_moves.size() - 1, -1, -1):
		if _moves[i][0] == key and i < _steps.size() and str(_steps[i]["reason"]) != "":
			_moves.remove_at(i)
			changed = true
			if i < _drag_from:
				_drag_from -= 1
	if held and _drag_from < 0:
		_drag_from = _moves.size()
	if _plan_blocks.has(key) and (_plan_blocks[key]["rect"] as Rect2i).position == chunk:
		return changed
	_moves.append([key, chunk])
	return true


## True while the left mouse button is down (a drag in the editor is going on).
static func _mouse_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _on_live_changed(slot: Node2D) -> void:
	_show_or_hide(slot as AtlasRegion)
	_build_sketch()


func _worlds_switched() -> void:
	if not is_node_ready():
		return
	for holder in holders():
		_show_or_hide(holder as AtlasRegion)
	_build_sketch()
	_marks.queue_redraw()


func _view_changed() -> void:
	if not is_node_ready():
		return
	_build_sketch()
	_marks.queue_redraw()


func _show_or_hide(slot: AtlasRegion) -> void:
	if not _wants_world(slot):
		slot.clear_world()
	elif slot.world() == null:
		_queue(slot)


func _wants_world(slot: AtlasRegion) -> bool:
	return show_interiors if slot.interior else (slot.live and show_live_worlds)


# --- reading and instancing the worlds ------------------------------------------------------

func _queue_all() -> void:
	_jobs.clear()
	for holder in holders():
		_jobs.append(holder)
	set_process(true)


func _queue(slot: AtlasRegion) -> void:
	if not _jobs.has(slot):
		_jobs.append(slot)
	set_process(true)


## The scene a slot shows: its world's, or its chunk worlds' when the world was cut (WorldChunks).
func _assign_scene(slot: AtlasRegion) -> void:
	var scenes := {}
	var chunks := WorldChunks.chunks(slot.map_id)
	for id: String in chunks:
		var path := WorldChunks.scene_path(id)
		if ResourceLoader.exists(path):
			scenes[str(chunks[id])] = path
	slot.chunk_scenes = scenes
	slot.scene_path = "" if not scenes.is_empty() else WorldSurvey.scene_path(slot.map_id, _index)


## Reads one world scene (fresh from disk), checks it and, when wanted, instances it on its slot.
func _load(slot: AtlasRegion) -> void:
	if not slot.chunk_scenes.is_empty():
		_load_chunks(slot)
		return
	var packed: PackedScene = null
	if slot.scene_path != "":
		packed = ResourceLoader.load(slot.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_surveys[slot.map_id] = WorldSurvey.read(packed) if packed != null else {}
	if packed != null and _wants_world(slot):
		var whole := slot.interior or bool(_plan_blocks.get(slot.region_key, {}).get("whole", true))
		slot.show_world(packed, Callable() if whole else _trim_to_region.bind(slot.region_key))
	else:
		slot.clear_world()
	_check()
	_build_sketch()
	_marks.queue_redraw()


## Reads the chunk worlds of a cut region (fresh from disk), checks them as one world laid out on
## the region's block and, when wanted, instances them on its slot.
func _load_chunks(slot: AtlasRegion) -> void:
	var corner := Vector2i(1 << 20, 1 << 20)
	for chunk_name: String in slot.chunk_scenes:
		corner = corner.min(_chunk_coords(chunk_name))
	var parts: Array = []
	var surveys: Array = []
	for chunk_name: String in slot.chunk_names():
		var packed := ResourceLoader.load(slot.chunk_scenes[chunk_name], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null:
			continue
		var offset := Vector2(_chunk_coords(chunk_name) - corner) * slot.chunk_units
		parts.append({"packed": packed, "offset": offset})
		surveys.append({"survey": WorldSurvey.read(packed), "offset": offset})
	_surveys[slot.map_id] = WorldSurvey.merge(slot.map_id, surveys) if not surveys.is_empty() else {}
	if not parts.is_empty() and _wants_world(slot):
		var whole := bool(_plan_blocks.get(slot.region_key, {}).get("whole", true))
		slot.show_chunks(parts, Callable() if whole else _trim_chunk.bind(slot.region_key))
	else:
		slot.clear_world()
	_check()
	_build_sketch()
	_marks.queue_redraw()


## Chunk "C6" as grid coordinates (2, 5).
static func _chunk_coords(chunk_name: String) -> Vector2i:
	return Vector2i(WorldMapData.COLUMN_LETTERS.find(chunk_name.left(1)), int(chunk_name.substr(1)) - 1)


## `_trim_to_region` for one chunk world of a cut region, `offset` (world units) into its block.
func _trim_chunk(world: Node2D, offset: Vector2, key: String) -> void:
	_trim_to_region(world, key, Vector2i((offset / float(plan.tile_size)).round()))


## The world of a region that is not a rectangle of chunks spans its whole bounding block: the
## atlas's copy keeps only the tiles on the region's own cells, so it does not cover the worlds of
## the regions around it.
func _trim_to_region(world: Node2D, key: String, offset_tiles: Vector2i = Vector2i.ZERO) -> void:
	var cells := plan.chunk_rect_cells(_plan_blocks[key]["rect"])
	var per := plan.tiles_per_cell
	var code := key.unicode_at(0)
	var rows_of: Array = plan.grids["regionCells"]
	for child: Node in world.get_children():
		var layer := child as TileMapLayer
		if layer == null:
			continue
		for tile: Vector2i in layer.get_used_cells():
			var at := tile + offset_tiles
			var cell := cells.position + Vector2i(floori(float(at.x) / per), floori(float(at.y) / per))
			if not plan.has_cell(cell) or (rows_of[cell.y] as PackedByteArray)[cell.x] != code:
				layer.erase_cell(tile)


## After a move, instance the moved worlds again once the dragging stops: their drawing bakes
## where they were built.
func _settle_later() -> void:
	for holder in holders():
		var slot := holder as AtlasRegion
		if slot.world() != null and slot.built_at != slot.position:
			_settle_at = Time.get_ticks_msec() + SETTLE_MS
			set_process(true)
			return


# --- the plan (pending moves) ---------------------------------------------------------------

## Plays the pending moves on the saved map (refusing the bad ones; the moves before the first one
## that changed are not played again) and puts every slot on its planned block (a slot whose last
## move is refused stays where it was dropped).
func _replan() -> void:
	if map == null:
		return
	var kept := 0
	while kept < mini(_steps.size(), _moves.size()) and _steps[kept]["move"] == _moves[kept]:
		kept += 1
	_steps.resize(kept)
	var state: Dictionary = _steps[kept - 1] if kept > 0 else _base
	for i in range(kept, _moves.size()):
		state = _step(state, _moves[i])
		_steps.append(state)
	plan = state["plan"]
	_plan_blocks = state["blocks"]
	_refused.clear()
	var dropped := {}
	for step in _steps:
		var key: String = step["move"][0]
		if str(step["reason"]) != "":
			_refused[key] = step["reason"]
			dropped[key] = step["move"][1]
		else:
			dropped.erase(key)
	if _refused.is_empty():
		_save_note = ""
	if _outlined != plan:
		_outlines = _cell_outlines(plan, OUTLINE * 0.5)
		_outlined = plan
	for holder in get_children():
		var slot := holder as AtlasRegion
		if slot == null:
			continue
		if dropped.has(slot.region_key):
			var at: Vector2i = dropped[slot.region_key]
			slot.place(Vector2(at) * plan.chunk_units())
		elif _plan_blocks.has(slot.region_key):
			slot.place(Vector2((_plan_blocks[slot.region_key]["rect"] as Rect2i).position) * plan.chunk_units())
	_place_shelf()
	_check()
	_build_sketch()
	_marks.queue_redraw()
	_settle_later()


## One pending move played on `state` ({plan, blocks, pieces}): the state after it, with the
## `move`, where the region's block was (`from`) and why the move is refused (`reason`, "" when it
## is played). The rules of `_move_problem` (WorldMapData.preview_move), from one pass over the map.
func _step(state: Dictionary, move: Array) -> Dictionary:
	var m: WorldMapData = state["plan"]
	var blocks: Dictionary = state["blocks"]
	var key: String = move[0]
	var to: Vector2i = move[1]
	var out := state.duplicate()
	out["move"] = move.duplicate()
	out["from"] = Vector2i(-1, -1)
	out["reason"] = ""
	if not blocks.has(key) or not bool(blocks[key]["whole"]):
		out["reason"] = _locked(m, key)
		return out
	var from: Rect2i = blocks[key]["rect"]
	out["from"] = from.position
	if to == from.position:
		return out
	var reason := _place_problem(m, key, from, to)
	if reason == "":
		var trial := m.duplicate_map()
		if not trial.move_region(key, to):
			reason = "%s cannot move to %s." % [_name(m, key), WorldMapData.chunk_name(to)]
		else:
			var after := _survey(trial)
			var torn := _torn(m, key, blocks, state["pieces"], after["blocks"], after["pieces"])
			if torn.is_empty():
				out["plan"] = trial
				out["blocks"] = after["blocks"]
				out["pieces"] = after["pieces"]
			else:
				reason = _split(m, key, to, torn)
	out["reason"] = reason
	return out


## Why moving region `key` to `to` on `m` is refused ("" when it is fine), by
## WorldMapData.preview_move (Save layout checks the moves again with it on a file that changed).
func _move_problem(m: WorldMapData, key: String, to: Vector2i) -> String:
	var from := m.region_chunk_rect(key)
	if not from.has_area() or not m.region_is_rect(key):
		return _locked(m, key)
	if to == from.position:
		return ""
	var reason := _place_problem(m, key, from, to)
	if reason != "":
		return reason
	var preview := m.preview_move(key, to)
	if not bool(preview["ok"]):
		return "%s cannot move to %s." % [_name(m, key), WorldMapData.chunk_name(to)]
	var broken: PackedStringArray = preview["broken"]
	if not broken.is_empty():
		return _split(m, key, to, broken)
	return ""


static func _locked(m: WorldMapData, key: String) -> String:
	if m.region(key).is_empty():
		return "Region '%s' is not on the world map." % key
	return "%s is locked: it is not a rectangle of whole chunks." % _name(m, key)


## Why block `from` of region `key` cannot go to `to` whatever is there ("" when it can): off the
## map, or diagonally over its old place (a slide goes along one axis, so the opposite move undoes it).
static func _place_problem(m: WorldMapData, key: String, from: Rect2i, to: Vector2i) -> String:
	var target := Rect2i(to, from.size)
	if to.x < 0 or to.y < 0 or target.end.x > m.chunk_cols or target.end.y > m.chunk_rows:
		return "%s cannot move to %s: it would leave the map." % [_name(m, key), WorldMapData.chunk_name(to)]
	if target.intersects(from) and to.x != from.position.x and to.y != from.position.y:
		return "%s cannot move to %s: it overlaps its old place diagonally; slide along one axis at a time." % [
				_name(m, key), WorldMapData.chunk_name(to)]
	return ""


## The regions of `m` other than `key` a move tears apart (preview_move's `broken`): in more pieces
## than before, or no longer a rectangle of whole chunks when they were one.
static func _torn(m: WorldMapData, key: String, blocks: Dictionary, pieces: Dictionary, after_blocks: Dictionary, after_pieces: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in m.regions():
		var other := str(entry.get("key", ""))
		if other == key or out.has(other):
			continue
		var was_whole := blocks.has(other) and bool(blocks[other]["whole"])
		var whole := after_blocks.has(other) and bool(after_blocks[other]["whole"])
		if int(after_pieces.get(other, 0)) > int(pieces.get(other, 0)) or (was_whole and not whole):
			out.append(other)
	return out


static func _split(m: WorldMapData, key: String, to: Vector2i, torn: PackedStringArray) -> String:
	var names := PackedStringArray()
	for other in torn:
		names.append(_name(m, other))
	return "moving %s to %s would tear %s apart." % [_name(m, key), WorldMapData.chunk_name(to), ", ".join(names)]


## The regions whose planned block is not their saved block.
func _pending_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in _plan_blocks:
		if _saved_blocks.has(key) and _plan_blocks[key]["rect"] != _saved_blocks[key]["rect"]:
			out.append(key)
	return out


## Every region's block (`_survey`): key -> {"rect", "whole", "first"}.
static func _blocks(m: WorldMapData) -> Dictionary:
	return _survey(m)["blocks"]


## Every region's block and pieces in one pass over `m`, by the rules of WorldMapData
## region_chunk_rect, region_is_rect and region_pieces (a chunk is the region's when it holds more
## than half of its cells): {"blocks": key -> {"rect": Rect2i in chunks, "whole": a rectangle of
## whole chunks, "first": its first chunk in reading order}, "pieces": key -> how many 4-connected
## pieces it has}. It reads each row as runs of one region (a drag plans with it, so it is quick).
static func _survey(m: WorldMapData) -> Dictionary:
	var size := m.chunk_cells()
	var none := WorldMapData.NO_REGION.unicode_at(0)
	var counts := {}
	var totals := {}
	# The runs (union-find: each run's parent and region code); `above` is the previous row's runs
	# as start, end, run.
	var parent := PackedInt32Array()
	var codes := PackedInt32Array()
	var above := PackedInt32Array()
	var rows_of: Array = m.grids["regionCells"]
	for y in m.rows:
		var row: PackedByteArray = rows_of[y]
		var runs := PackedInt32Array()
		var x := 0
		while x < m.cols:
			var code := row[x]
			var start := x
			x += 1
			while x < m.cols and row[x] == code:
				x += 1
			if code == none:
				continue
			if not counts.has(code):
				counts[code] = {}
				totals[code] = 0
			totals[code] += x - start
			var per_chunk: Dictionary = counts[code]
			for chunk_x in range(start / size.x, (x - 1) / size.x + 1):
				var chunk := Vector2i(chunk_x, y / size.y)
				per_chunk[chunk] = int(per_chunk.get(chunk, 0)) + mini(x, (chunk_x + 1) * size.x) - maxi(start, chunk_x * size.x)
			var run := parent.size()
			parent.append(run)
			codes.append(code)
			for i in range(0, above.size(), 3):
				if above[i] < x and above[i + 1] > start and codes[above[i + 2]] == code:
					var a := run
					while parent[a] != a:
						a = parent[a]
					var b := above[i + 2]
					while parent[b] != b:
						b = parent[b]
					if a != b:
						parent[maxi(a, b)] = mini(a, b)
			runs.append(start)
			runs.append(x)
			runs.append(run)
		above = runs
	var pieces := {}
	for run in parent.size():
		if parent[run] == run:
			var key := String.chr(codes[run])
			pieces[key] = int(pieces.get(key, 0)) + 1
	var blocks := {}
	for code: int in counts:
		var chunks: Array[Vector2i] = []
		var full := true
		for chunk: Vector2i in counts[code]:
			var cells := int(counts[code][chunk])
			if cells > size.x * size.y / 2:
				chunks.append(chunk)
				full = full and cells == size.x * size.y
		if chunks.is_empty():
			continue
		chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var rect := Rect2i(chunks[0], Vector2i.ONE)
		for chunk in chunks:
			rect = rect.expand(chunk).expand(chunk + Vector2i.ONE)
		var area := rect.size.x * rect.size.y
		blocks[String.chr(code)] = {
			"rect": rect,
			# Every chunk of the block all the region's, and no cell elsewhere.
			"whole": full and chunks.size() == area and int(totals[code]) == area * size.x * size.y,
			"first": chunks[0],
		}
	return {"blocks": blocks, "pieces": pieces}


## The outline of every region's cells, drawn `inset` inside them so two regions that touch show
## both colours: key -> PackedVector2Array of segment pairs.
static func _cell_outlines(m: WorldMapData, inset: float) -> Dictionary:
	var out := {}
	var cell := m.cell_units()
	var rows_of: Array = m.grids["regionCells"]
	var none := WorldMapData.NO_REGION.unicode_at(0)
	for y in m.rows:
		var row: PackedByteArray = rows_of[y]
		var below: PackedByteArray = rows_of[y + 1] if y + 1 < m.rows else PackedByteArray()
		var above: PackedByteArray = rows_of[y - 1] if y > 0 else PackedByteArray()
		for x in m.cols:
			var here := row[x]
			if here == none:
				continue
			var corner := Vector2(x, y) * cell
			if x == 0 or row[x - 1] != here:
				_segment(out, here, corner + Vector2(inset, 0), corner + Vector2(inset, cell))
			if x + 1 == m.cols or row[x + 1] != here:
				_segment(out, here, corner + Vector2(cell - inset, 0), corner + Vector2(cell - inset, cell))
			if above.is_empty() or above[x] != here:
				_segment(out, here, corner + Vector2(0, inset), corner + Vector2(cell, inset))
			if below.is_empty() or below[x] != here:
				_segment(out, here, corner + Vector2(0, cell - inset), corner + Vector2(cell, cell - inset))
	var keyed := {}
	for code: int in out:
		keyed[String.chr(code)] = out[code]
	return keyed


static func _segment(out: Dictionary, code: int, from: Vector2, to: Vector2) -> void:
	if not out.has(code):
		out[code] = PackedVector2Array()
	var points: PackedVector2Array = out[code]
	points.append(from)
	points.append(to)
	out[code] = points


# --- checks ---------------------------------------------------------------------------------

## Checks every region and its world (scene, size, placeholder age, exits, interiors) against the
## plan, and shows the problems as configuration warnings.
func _check() -> void:
	if plan == null:
		return
	_exits.clear()
	var per_key := {}
	var found := PackedStringArray()
	if _save_note != "":
		found.append("Save layout: " + _save_note)
	if _notice != "":
		found.append(_notice)
	for entry: Dictionary in plan.regions():
		var key := str(entry.get("key", ""))
		var notes := _check_region(entry)
		if _refused.has(key):
			notes.append("Save layout refuses: " + str(_refused[key]))
		per_key[key] = notes
		found.append_array(notes)
	for key: String in _slots_by_key():
		if plan.region(key).is_empty():
			found.append("The slot of region '%s' has no region in the world map." % key)
	for line in found:
		if line.ends_with(STALE_NOTE):
			found.append("To rebuild the placeholder worlds for this layout: " + REBUILD_PLACEHOLDERS)
			break
	_warnings = found
	_show_warnings(per_key)


func _check_region(entry: Dictionary) -> PackedStringArray:
	var notes := PackedStringArray()
	var key := str(entry.get("key", ""))
	var region_name := str(entry.get("name", key))
	var world_id := str(entry.get("world", ""))
	if not _plan_blocks.has(key):
		notes.append("%s has no chunks on the map." % region_name)
		return notes
	var rect: Rect2i = _plan_blocks[key]["rect"]
	if world_id == "":
		notes.append("%s has no world id." % region_name)
	elif WorldSurvey.scene_path(world_id, _index) == "" and not WorldChunks.is_cut(world_id):
		notes.append("%s has no scene yet (%s%s.tscn): the sketch shows it." % [region_name, WorldSurvey.WORLDS_DIR, world_id])
	elif not (_surveys.get(world_id, {}) as Dictionary).is_empty():
		var survey: Dictionary = _surveys[world_id]
		var tiles := Vector2i(int(survey["columns"]), int(survey["rows"]))
		var wanted := rect.size * plan.chunk_tiles()
		if tiles != wanted:
			var fits := tiles.x <= wanted.x and tiles.y <= wanted.y
			notes.append("%s (%s) is %d x %d tiles, its block %s %d x %d: %s." % [
					region_name, world_id, tiles.x, tiles.y, _block_name(rect), wanted.x, wanted.y,
					"the rest of the block is unused" if fits else "it spills over its neighbours"])
		if bool(entry.get("placeholder", false)) and (survey["hash"] == null or int(survey["hash"]) != _layout_hash):
			notes.append("%s %s" % [world_id, STALE_NOTE])
		for exit: Dictionary in survey["exits"]:
			var judged := _judge_exit(key, world_id, exit)
			_exits.append(judged)
			if judged["status"] != "ok":
				notes.append(str(judged["reason"]))
	for interior: Variant in entry.get("interiors", []):
		if WorldSurvey.scene_path(str(interior), _index) == "":
			notes.append("%s's interior %s has no scene." % [region_name, interior])
	return notes


## {key, exit, edge, status ("ok", "one-way" or "wrong"), reason} for one exit of world `world_id`
## (region `key`), against the plan. An exit on an edge of its world (or, inside the bounding
## block of a region that is not a rectangle, at a border of the region: `edge` is the way out)
## must lead to the region across it, arrive on that region's facing edge (or at its
## `entry_marker`) and have an exit back.
func _judge_exit(key: String, world_id: String, exit: Dictionary) -> Dictionary:
	var out := {"key": key, "exit": exit, "edge": str(exit["edge"]), "status": "ok", "reason": ""}
	var where := "%s's exit %s" % [world_id, exit["name"]]
	var target := str(exit["target"])
	var edge := str(exit["edge"])
	if target == "":
		return _verdict(out, "wrong", "%s leads nowhere (no target_area_id)." % where)
	var target_region := plan.region_for_map(target)
	if target_region.is_empty():
		return _verdict(out, "wrong", "%s leads to %s, which is not on the world map." % [where, target])
	if str(target_region.get("world", "")) != target:
		return out
	var across := ""
	if edge != "":
		across = _region_across(key, exit["rect"], edge)
	else:
		var border := _nearest_border(key, exit["rect"])
		edge = border[0]
		across = border[1]
		out["edge"] = edge
		if edge == "":
			return _verdict(out, "wrong", "%s leads to %s but is on no edge of %s and at no border of its region." % [where, target, world_id])
	if across != str(target_region.get("key", "")):
		var across_name := "nothing" if across == "" or across == WorldMapData.NO_REGION else _name(plan, across)
		return _verdict(out, "wrong", "%s (%s edge) leads to %s, but %s is across that edge." % [where, edge, target, across_name])
	if not _surveys.has(target):
		return out
	var back: Dictionary = _surveys[target]
	if back.is_empty():
		return _verdict(out, "one-way", "%s leads to %s, which has no scene yet." % [where, target])
	var marker := str(exit["entry_marker"])
	var entry := str(exit["entry"])
	if marker != "":
		if not (back["names"] as Dictionary).has(marker):
			return _verdict(out, "wrong", "%s arrives at marker %s, which %s does not have." % [where, marker, target])
	elif entry != WorldSurvey.opposite(edge):
		return _verdict(out, "wrong", "%s arrives on the %s edge of %s, not its %s edge." % [where, entry if entry != "" else "(no)", target, WorldSurvey.opposite(edge)])
	elif not (back["names"] as Dictionary).has("player-entry-" + entry):
		return _verdict(out, "wrong", "%s arrives on %s's %s edge, which has no player-entry-%s marker (the player lands at player-spawn)." % [where, target, entry, entry])
	for other: Dictionary in back["exits"]:
		if str(other["target"]) == world_id:
			return out
	return _verdict(out, "one-way", "%s leads to %s, which has no exit back." % [where, target])


static func _verdict(out: Dictionary, status: String, reason: String) -> Dictionary:
	out["status"] = status
	out["reason"] = reason
	return out


## The first region met going out of region `key`'s world from the middle of `rect` (the exit, in
## world units) across `edge`, on the plan ("" off the map).
func _region_across(key: String, rect: Rect2, edge: String) -> String:
	var origin := Vector2((_plan_blocks[key]["rect"] as Rect2i).position) * plan.chunk_units()
	var cell := Vector2i(((origin + rect.get_center()) / plan.cell_units()).floor())
	var step := WorldSurvey.edge_step(edge)
	for i in maxi(plan.cols, plan.rows):
		cell += step
		if not plan.has_cell(cell):
			return ""
		var other := plan.region_key_at(cell)
		if other != key:
			return other
	return ""


## For an exit inside its world: [edge, region key] of the nearest border of region `key` (within
## BORDER_REACH cells of the middle of `rect`, on the plan), or ["", ""]. An exit whose middle is
## already across the border leads out the way its own cells lie behind it.
func _nearest_border(key: String, rect: Rect2) -> Array[String]:
	var origin := Vector2((_plan_blocks[key]["rect"] as Rect2i).position) * plan.chunk_units()
	var start := Vector2i(((origin + rect.get_center()) / plan.cell_units()).floor())
	var here := plan.region_key_at(start)
	var found: Array[String] = ["", ""]
	var nearest := BORDER_REACH + 1
	for edge in WorldSurvey.EDGES:
		var step := WorldSurvey.edge_step(edge)
		if here != key:
			if here != "" and plan.region_key_at(start - step) == key:
				return [edge, here]
			continue
		var cell := start
		for distance in range(1, mini(nearest, BORDER_REACH + 1)):
			cell += step
			var other := plan.region_key_at(cell)
			if other != key:
				if other != "":
					found = [edge, other]
					nearest = distance
				break
	return found


func _show_warnings(per_key: Dictionary) -> void:
	if not Engine.is_editor_hint():
		return
	for holder in get_children():
		var slot := holder as AtlasRegion
		if slot != null:
			slot.warnings = per_key.get(slot.region_key, PackedStringArray())
			slot.update_configuration_warnings()
	update_configuration_warnings()


# --- drawing --------------------------------------------------------------------------------

func _painter(node_name: String, z: int, paint: Callable) -> Painter:
	var painter := get_node_or_null(node_name) as Painter
	if painter == null:
		painter = Painter.new()
		painter.name = node_name
		add_child(painter)
	painter.z_index = z
	painter.paint = paint
	_lock(painter)
	return painter


## The atlas's own nodes (no owner) are locked groups: a click on them (or on a world inside them)
## selects nothing in the 2D editor.
static func _lock(node: Node) -> void:
	node.set_meta(&"_edit_group_", true)
	node.set_meta(&"_edit_lock_", true)


## The sketch as one texel per cell: the terrain's colour, lighter with height, clear where a
## world scene is shown (unless `sketch_under_worlds`).
func _build_sketch() -> void:
	if plan == null or _sketch == null:
		return
	# 1 on the cells a shown world covers: all of its rect for a rectangular region, only the
	# region's own cells for the others (their worlds span their whole bounding block).
	var covered := PackedByteArray()
	covered.resize(plan.cols * plan.rows)
	var region_rows: Array = plan.grids["regionCells"]
	if not sketch_under_worlds:
		for holder in get_children():
			var slot := holder as AtlasRegion
			if slot == null or not slot.has_scene() or not _wants_world(slot):
				continue
			var whole := bool(_plan_blocks.get(slot.region_key, {}).get("whole", true))
			var code := slot.region_key.unicode_at(0)
			var cells := Rect2i(Vector2i((slot.position / plan.cell_units()).round()),
					Vector2i((_world_size(slot) / plan.cell_units()).ceil()))
			cells = cells.intersection(Rect2i(0, 0, plan.cols, plan.rows))
			for y in range(cells.position.y, cells.end.y):
				var region_row: PackedByteArray = region_rows[y]
				for x in range(cells.position.x, cells.end.x):
					if whole or region_row[x] == code:
						covered[y * plan.cols + x] = 1
	var colors := {}
	for terrain: String in TERRAIN_COLORS:
		colors[terrain.unicode_at(0)] = TERRAIN_COLORS[terrain]
	var data := PackedByteArray()
	data.resize(plan.cols * plan.rows * 4)
	var terrain_rows: Array = plan.grids["terrain"]
	var height_rows: Array = plan.grids["elevation"]
	for y in plan.rows:
		var terrain_row: PackedByteArray = terrain_rows[y]
		var height_row: PackedByteArray = height_rows[y]
		for x in plan.cols:
			var color: Color = colors.get(terrain_row[x], TERRAIN_COLORS["."])
			color = color.lerp(Color.WHITE, ELEVATION_LIGHT * clampi(height_row[x] - 48, 0, 9))
			var at := (y * plan.cols + x) * 4
			data[at] = color.r8
			data[at + 1] = color.g8
			data[at + 2] = color.b8
			data[at + 3] = 255 if show_sketch and covered[y * plan.cols + x] == 0 else 0
	var image := Image.create_from_data(plan.cols, plan.rows, false, Image.FORMAT_RGBA8, data)
	if _sketch_texture != null and _sketch_texture.get_size() == Vector2(image.get_size()):
		_sketch_texture.update(image)
	else:
		_sketch_texture = ImageTexture.create_from_image(image)
	_sketch.queue_redraw()


## The size of a slot's world in world units (its block, or a card, until its scene is read).
func _world_size(slot: AtlasRegion) -> Vector2:
	var survey: Dictionary = _surveys.get(slot.map_id, {})
	if not survey.is_empty() and (survey["size"] as Vector2).x > 0.0:
		return survey["size"]
	return CARD_SIZE if slot.interior else Vector2(slot.block_size) * slot.chunk_units


func _paint_sketch(canvas: Node2D) -> void:
	if plan == null:
		return
	var grid := Vector2(plan.cols, plan.rows) * plan.cell_units()
	var bottom := grid.y + (SHELF_GAP + plan.chunk_units().y if show_interiors else 0.0)
	canvas.draw_rect(Rect2(-BANNER_SPACE, -BANNER_SPACE, grid.x + 2.0 * BANNER_SPACE, bottom + 2.0 * BANNER_SPACE), BACKGROUND)
	if _sketch_texture != null:
		canvas.draw_texture_rect(_sketch_texture, Rect2(Vector2.ZERO, grid), false)


func _paint_marks(canvas: Node2D) -> void:
	if plan == null:
		return
	var font := ThemeDB.fallback_font
	var chunk := plan.chunk_units()
	var grid := Vector2(plan.chunk_cols, plan.chunk_rows) * chunk
	for x in range(1, plan.chunk_cols):
		canvas.draw_line(Vector2(x * chunk.x, 0), Vector2(x * chunk.x, grid.y), GRID_COLOR, LINE)
	for y in range(1, plan.chunk_rows):
		canvas.draw_line(Vector2(0, y * chunk.y), Vector2(grid.x, y * chunk.y), GRID_COLOR, LINE)
	for y in plan.chunk_rows:
		for x in plan.chunk_cols:
			_text(canvas, font, Vector2(x, y) * chunk + Vector2(PAD * 0.5, PAD * 0.5 + CHUNK_FONT),
					WorldMapData.chunk_name(Vector2i(x, y)), CHUNK_FONT, GRID_COLOR * Color(1, 1, 1, 2.2))
	for passage: Variant in plan.passages():
		if passage is Dictionary:
			var p := passage as Dictionary
			var cell := plan.cell_units()
			var rect := Rect2(Vector2(float(p.get("x", 0)), float(p.get("y", 0))) * cell, Vector2(float(p.get("w", 1)), float(p.get("h", 1))) * cell)
			canvas.draw_rect(rect, PASSAGE_COLOR)
			canvas.draw_rect(rect, Color.WHITE, false, LINE)
	for key: String in _outlines:
		canvas.draw_multiline(_outlines[key], _region_color(key), OUTLINE)
	for holder in holders():
		_paint_world_frame(canvas, font, holder as AtlasRegion)
	if show_markers:
		for marker: Variant in plan.markers():
			if marker is Dictionary:
				_paint_marker(canvas, font, marker as Dictionary)
	for entry: Dictionary in plan.regions():
		_paint_label(canvas, font, entry)
	if show_exits:
		for judged in _exits:
			_paint_exit(canvas, font, judged)
	_paint_moves(canvas)
	canvas.draw_rect(Rect2(Vector2.ZERO, grid), FRAME_COLOR, false, FRAME)
	_paint_banner(canvas, font)
	if show_interiors and _shelf.get_child_count() > 0:
		_text(canvas, font, Vector2(0, grid.y + SHELF_GAP - PAD * 3.0), "Interiors (off the grid), under their region", NAME_FONT, TEXT_COLOR)


## A world smaller than its block: the unused part hatched; bigger: its spill outlined in red. On
## the shelf: the interior's card and name.
func _paint_world_frame(canvas: Node2D, font: Font, slot: AtlasRegion) -> void:
	var size := _world_size(slot)
	if slot.interior:
		if not show_interiors:
			return
		var card := Rect2(slot.position, size)
		canvas.draw_rect(card, _region_color(slot.region_key), false, OUTLINE)
		var title := slot.map_id + ("" if slot.has_scene() else " (no scene)")
		_text(canvas, font, card.position + Vector2(0, -PAD * 0.5), title, INFO_FONT, TEXT_COLOR)
		return
	if not slot.has_scene() or (_surveys.get(slot.map_id, {}) as Dictionary).is_empty():
		return
	var whole := bool(_plan_blocks.get(slot.region_key, {}).get("whole", true))
	var block := Rect2(slot.position, Vector2(slot.block_size) * slot.chunk_units)
	var world := Rect2(slot.position, size)
	# Only a rectangular block is all the region's (another region's cells are not "unused").
	if whole and world.end.x < block.end.x:
		_hatch(canvas, Rect2(world.end.x, block.position.y, block.end.x - world.end.x, block.size.y))
	if whole and world.end.y < block.end.y:
		_hatch(canvas, Rect2(block.position.x, world.end.y, minf(world.size.x, block.size.x), block.end.y - world.end.y))
	if world.end.x > block.end.x or world.end.y > block.end.y:
		canvas.draw_rect(world, REFUSED_COLOR, false, OUTLINE)


## Diagonal lines over `rect`.
func _hatch(canvas: Node2D, rect: Rect2) -> void:
	canvas.draw_rect(rect, HATCH_COLOR * Color(1, 1, 1, 0.5))
	var c := rect.position.x - rect.end.y
	while c < rect.end.x - rect.position.y:
		var top := maxf(rect.position.y, rect.position.x - c)
		var bottom := minf(rect.end.y, rect.end.x - c)
		if bottom > top:
			canvas.draw_line(Vector2(top + c, top), Vector2(bottom + c, bottom), HATCH_COLOR, LINE * 1.5)
		c += HATCH_SPACING


## The exit's area, an arrow out of its edge and, inside its world, its name and target.
func _paint_exit(canvas: Node2D, font: Font, judged: Dictionary) -> void:
	var slot := slot_of(str(judged["key"]))
	if slot == null:
		return
	var exit: Dictionary = judged["exit"]
	var rect: Rect2 = exit["rect"]
	rect.position += slot.position
	var color: Color = EXIT_COLORS[judged["status"]]
	canvas.draw_rect(rect.grow(LINE), SHADOW_COLOR)
	canvas.draw_rect(rect, color)
	var edge := str(judged["edge"])
	var step := Vector2(WorldSurvey.edge_step(edge))
	var centre := rect.get_center()
	var start := centre + step * (rect.size * 0.5)
	if step == Vector2.ZERO:
		step = Vector2.UP
		start = centre
	var tip := start + step * ARROW_LENGTH
	var side := Vector2(-step.y, step.x)
	var head := PackedVector2Array([tip, tip - step * ARROW_HEAD + side * ARROW_HEAD * 0.6, tip - step * ARROW_HEAD - side * ARROW_HEAD * 0.6])
	canvas.draw_line(start, tip - step * ARROW_HEAD * 0.5, SHADOW_COLOR, ARROW_WIDTH + LINE * 2.0)
	canvas.draw_line(start, tip - step * ARROW_HEAD * 0.5, color, ARROW_WIDTH)
	canvas.draw_colored_polygon(head, color)
	canvas.draw_polyline(head + PackedVector2Array([tip]), SHADOW_COLOR, LINE)
	var label := "%s > %s%s" % [exit["name"], exit["target"], " (needs %s)" % exit["gate"] if str(exit["gate"]) != "" else ""]
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_FONT).x
	var at := start - step * PAD + Vector2(0, INFO_FONT * 0.35)
	if step.x > 0.0:
		at.x -= width
	elif step.y != 0.0:
		at.x -= width * 0.5
		at.y += INFO_FONT * 0.5 if step.y < 0.0 else -INFO_FONT * 0.3
	_text(canvas, font, at, label, INFO_FONT, color)


func _paint_marker(canvas: Node2D, font: Font, marker: Dictionary) -> void:
	var at := (Vector2(float(marker.get("x", 0)), float(marker.get("y", 0))) + Vector2(0.5, 0.5)) * plan.cell_units()
	var color: Color = MARKER_COLORS.get(str(marker.get("type", "")), MARKER_COLORS["note"])
	canvas.draw_circle(at, MARKER_RADIUS + LINE, SHADOW_COLOR)
	canvas.draw_circle(at, MARKER_RADIUS, color)
	_text(canvas, font, at + Vector2(MARKER_RADIUS + PAD * 0.5, INFO_FONT * 0.35), str(marker.get("label", "")), INFO_FONT, TEXT_COLOR)


## Pending moves dashed (the new place bright, the old one faint); refused drops red.
func _paint_moves(canvas: Node2D) -> void:
	var chunk := plan.chunk_units()
	for key in _pending_keys():
		var new_place := Rect2(Vector2((_plan_blocks[key]["rect"] as Rect2i).position) * chunk, Vector2((_plan_blocks[key]["rect"] as Rect2i).size) * chunk)
		var old_place := Rect2(Vector2((_saved_blocks[key]["rect"] as Rect2i).position) * chunk, Vector2((_saved_blocks[key]["rect"] as Rect2i).size) * chunk)
		_dashed(canvas, old_place.grow(-OUTLINE * 2.0), PENDING_COLOR * Color(1, 1, 1, 0.4), LINE * 2.0)
		_dashed(canvas, new_place.grow(-OUTLINE * 2.0), PENDING_COLOR, OUTLINE * 1.5)
	for key: String in _refused:
		var slot := slot_of(key)
		if slot != null:
			var block := Rect2(slot.position, Vector2(slot.block_size) * slot.chunk_units)
			canvas.draw_rect(block, REFUSED_COLOR * Color(1, 1, 1, 0.3))
			canvas.draw_rect(block, REFUSED_COLOR, false, FRAME)


func _dashed(canvas: Node2D, rect: Rect2, color: Color, width: float) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		canvas.draw_dashed_line(corners[i], corners[(i + 1) % 4], color, width, DASH)


## The region's name and state on a panel at its first chunk (where its slot is).
func _paint_label(canvas: Node2D, font: Font, entry: Dictionary) -> void:
	var key := str(entry.get("key", ""))
	if not _plan_blocks.has(key):
		return
	var block: Dictionary = _plan_blocks[key]
	var rect: Rect2i = block["rect"]
	var corner := Vector2(block["first"] as Vector2i) * plan.chunk_units()
	var slot := slot_of(key)
	if slot != null and _refused.has(key):
		corner = slot.position + Vector2((block["first"] as Vector2i) - rect.position) * plan.chunk_units()
	var lines := PackedStringArray()
	lines.append("%s  [%s]  %s, world %s" % [_block_name(rect), key, str(entry.get("status", "")), str(entry.get("world", ""))])
	var world_id := str(entry.get("world", ""))
	var survey: Dictionary = _surveys.get(world_id, {})
	if slot == null or slot.scene_path == "":
		lines.append("no scene yet: the sketch shows the plan")
	elif not survey.is_empty():
		lines.append("%d x %d tiles%s%s" % [int(survey["columns"]), int(survey["rows"]),
				"" if slot.live else ", not live", ", placeholder" if bool(entry.get("placeholder", false)) else ""])
	if not bool(block["whole"]):
		lines.append("locked: not a rectangle of whole chunks")
	if _pending_keys().has(key):
		lines.append("pending: %s > %s (Save layout writes it)" % [_block_name(_saved_blocks[key]["rect"]), _block_name(rect)])
	if _refused.has(key):
		lines.append("refused: " + str(_refused[key]))
	var title := str(entry.get("name", key))
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT).x
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_FONT).x)
	var height := NAME_FONT * 1.2 + lines.size() * INFO_FONT * 1.3 + PAD * 0.5
	var panel := Rect2(corner + Vector2(PAD, PAD), Vector2(width + PAD * 1.5, height))
	canvas.draw_rect(panel, PANEL_COLOR)
	canvas.draw_rect(Rect2(panel.position, Vector2(PAD * 0.35, panel.size.y)), _region_color(key))
	var at := panel.position + Vector2(PAD * 0.75, NAME_FONT)
	_text(canvas, font, at, title, NAME_FONT, TEXT_COLOR)
	at.y += NAME_FONT * 0.2
	for line in lines:
		at.y += INFO_FONT * 1.3
		var color := TEXT_COLOR
		if line.begins_with("refused"):
			color = REFUSED_COLOR
		elif line.begins_with("locked") or line.begins_with("pending") or line.begins_with("no scene"):
			color = EXIT_COLORS["one-way"]
		_text(canvas, font, at, line, INFO_FONT, color)


## What this is and what is pending, over the grid.
func _paint_banner(canvas: Node2D, font: Font) -> void:
	var lines := PackedStringArray()
	lines.append("World atlas: %s, %d x %d chunks of %d x %d tiles. Drag a region to move it; Save layout writes the moves." % [
			map_path, plan.chunk_cols, plan.chunk_rows, plan.chunk_tiles().x, plan.chunk_tiles().y])
	var pending := _pending_keys()
	if not _refused.is_empty():
		lines.append("Refused: " + " ".join(PackedStringArray(_refused.values())))
	elif not pending.is_empty():
		var names := PackedStringArray()
		for key in pending:
			names.append("%s to %s" % [_name(plan, key), _block_name(_plan_blocks[key]["rect"])])
		lines.append("Pending (not saved): " + ", ".join(names))
	if _notice != "":
		lines.append(_notice)
	if _save_note != "":
		lines.append("Not saved: " + _save_note)
	var at := Vector2(0, -BANNER_SPACE + BANNER_FONT)
	for line in lines:
		_text(canvas, font, at, line, BANNER_FONT, TEXT_COLOR if line == lines[0] else EXIT_COLORS["one-way"])
		at.y += BANNER_FONT * 1.25


func _text(canvas: Node2D, font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(4, size / 8), SHADOW_COLOR)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# --- small helpers --------------------------------------------------------------------------

func _region_color(key: String) -> Color:
	var source := plan if plan != null else map
	return Color.from_string(str(source.region(key).get("color", "")), Color.WHITE) if source != null else Color.WHITE


static func _name(m: WorldMapData, key: String) -> String:
	return str(m.region(key).get("name", key)) if m != null else key


## "C4-D5" for a block of chunks ("C4" for one chunk).
static func _block_name(rect: Rect2i) -> String:
	var first := WorldMapData.chunk_name(rect.position)
	return first if rect.size == Vector2i.ONE else "%s-%s" % [first, WorldMapData.chunk_name(rect.end - Vector2i.ONE)]


## The atlas root owns new slots when it is the scene open in the editor (so they are saved).
func _scene_owner() -> Node:
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root == self:
		return self
	return null


## Draws what the atlas paints on it (made at run time, never saved: no owner).
class Painter:
	extends Node2D
	var paint: Callable

	func _draw() -> void:
		if paint.is_valid():
			paint.call(self)

@tool
extends Node2D
## The root of an area scene (game/dev/area_edit/area_edit.gd, docs/godot/WORLD_ATLAS.md "Editing
## an area"): a few chunk worlds joined to be edited as one. In the editor it draws the chunk lines
## and names over the area, and its buttons (Inspector) write the area back into the chunk files,
## read the chunks again (dropping the edits not written back), or close the area. Its warnings list
## what the last write-back did and the chunks it will not write.
##
## Owner: world (atlas).

const AreaEdit := preload("res://game/dev/area_edit/area_edit.gd")
const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")
const BorderCrossing := preload("res://game/world/crossings/border_crossing.gd")
const ChunkEdges := preload("res://game/world/elevation/chunk_edges.gd")
const EditorDialogs := preload("res://game/shared/editor_dialogs.gd")
const ATLAS_SCRIPT := "res://game/world/atlas/world_atlas.gd"
const BAKE_TOOL := "res://tools/bake_elevation.gd"
const LINES_NODE := "_ChunkLines"
const LINE_COLOR := Color(1.0, 0.85, 0.3, 0.8)
const NAME_COLOR := Color(1.0, 0.85, 0.3, 0.9)
const LINE_WIDTH := 6.0
const NAME_FONT := 64
## The shade past the area's edge, over the cells the area holds there (the chunks' margins).
const OUTSIDE_COLOR := Color(0.0, 0.0, 0.0, 0.45)
## Frames to wait after the area opens before the editor's first save is kept as the copy the
## write-back compares with (the tool scripts have settled).
const SETTLE_FRAMES := 3
## What F6 on the area's tab runs: the game bootstrap, with one chunk world (see `_play`).
const MAIN_SCENE := "res://game/main.tscn"

@export_tool_button("Write back", "Save") var write_back_button: Callable = write_back
@export_tool_button("Discard edits (read the chunks again)", "Reload") var discard_button: Callable = discard
@export_tool_button("Close area", "Close") var close_button: Callable = close_area

## What the last write-back did (shown as warnings, not saved).
var _report := PackedStringArray()


func _ready() -> void:
	if not has_meta(AreaEdit.AREA_META):
		return
	if not Engine.is_editor_hint():
		if get_tree().current_scene == self:
			_play.call_deferred()
		return
	var lines := Node2D.new()
	lines.name = LINES_NODE
	lines.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	lines.draw.connect(_draw_lines.bind(lines))
	add_child(lines)
	# The shade follows what is painted past the edge.
	for child: Node in get_children():
		if child is TileMapLayer:
			(child as TileMapLayer).changed.connect(lines.queue_redraw)
	if get_tree().edited_scene_root == self and bool(_info().get("base_pending", false)):
		_keep_base.call_deferred()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	for part: Dictionary in _info().get("chunks", []):
		if not bool(part.get("exact", true)):
			out.append("%s does not come back exactly from the area: a write-back that changes it writes nothing." % part["chunk"])
	for note: String in _info().get("notes", []):
		out.append(note + ".")
	out.append_array(_report)
	return out


func _info() -> Dictionary:
	return get_meta(AreaEdit.AREA_META, {})


## Each save of the area in the editor (Godot saves the scene before F6 runs it) notes the chunk in
## the middle of the 2D view, for `_play`.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE and Engine.is_editor_hint() and has_meta(AreaEdit.AREA_META):
		_note_view_chunk()


## Run on its own (F6 with the area's tab open), an area plays one of its chunk worlds in the game,
## as F6 on a chunk scene does, from that chunk's spawn: the chunk that was in the middle of the
## editor's view when the area was last saved, else the area's first chunk. The game reads the
## chunk files, so edits not written back do not show (a warning says so).
func _play() -> void:
	var chunks: Array = _info().get("chunks", [])
	if chunks.is_empty() or not is_inside_tree():
		return
	var id := str((chunks[0] as Dictionary)["id"])
	var noted := _noted_chunk()
	for part: Dictionary in chunks:
		if str(part["id"]) == noted:
			id = noted
	var name_of_area := AreaEdit.rect_name(_info().get("rect", Rect2i()))
	if AreaEdit.has_edits(scene_file_path):
		push_warning("Area %s: it has edits not written back; the game plays the chunk files without them (Write back first)." % name_of_area)
	print("Area %s: F6 plays %s from its spawn (%s)." % [name_of_area, id,
			"the chunk in the middle of the editor's view" if id == noted else "the area's first chunk"])
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", id)
	main.set(&"direct_world_run", true)
	get_tree().change_scene_to_node(main)


## Where the chunk F6 plays is noted: beside the area's copy (user://, not in git), never in the area
## scene itself (that would count as an edit).
func _play_note_path() -> String:
	return AreaEdit.WORK_DIR + scene_file_path.get_file().get_basename() + ".play.txt"


func _noted_chunk() -> String:
	var path := _play_note_path()
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


## Notes the chunk under the middle of the editor's 2D view (nothing when the view is not on it).
func _note_view_chunk() -> void:
	var editor := _editor()
	if editor == null or not is_inside_tree() or get_tree().edited_scene_root != self \
			or not editor.has_method(&"get_editor_viewport_2d"):
		return
	var viewport := editor.call(&"get_editor_viewport_2d") as Viewport
	if viewport == null:
		return
	var view := viewport.global_canvas_transform * viewport.canvas_transform
	var centre := global_transform.affine_inverse() * (view.affine_inverse() * (viewport.get_visible_rect().size * 0.5))
	var units: Vector2 = _info().get("chunk_units", Vector2.ZERO)
	for part: Dictionary in _info().get("chunks", []):
		if Rect2(part["offset"], units).has_point(centre):
			DirAccess.make_dir_recursive_absolute(AreaEdit.WORK_DIR)
			var file := FileAccess.open(_play_note_path(), FileAccess.WRITE)
			if file != null:
				file.store_string(str(part["id"]))
			return


## The chunk lines and names, and a shade over the cells the area holds past its edge (the
## chunks' margins: what is painted there is not written back).
func _draw_lines(canvas: Node2D) -> void:
	var font := ThemeDB.fallback_font
	var units: Vector2 = _info().get("chunk_units", Vector2.ZERO)
	var area := Rect2(Vector2.ZERO, units * Vector2((_info().get("rect", Rect2i()) as Rect2i).size))
	# In cell space, as the write-back tells inside from outside (the layers' own offsets aside).
	var outer := area
	for child: Node in get_children():
		var layer := child as TileMapLayer
		var used := layer.get_used_rect() if layer != null and layer.tile_set != null else Rect2i()
		if used.has_area():
			var size := Vector2(layer.tile_set.tile_size)
			outer = outer.merge(Rect2(Vector2(used.position) * size, Vector2(used.size) * size))
	for side in [Rect2(outer.position, Vector2(outer.size.x, area.position.y - outer.position.y)),
			Rect2(Vector2(outer.position.x, area.end.y), Vector2(outer.size.x, outer.end.y - area.end.y)),
			Rect2(Vector2(outer.position.x, area.position.y), Vector2(area.position.x - outer.position.x, area.size.y)),
			Rect2(Vector2(area.end.x, area.position.y), Vector2(outer.end.x - area.end.x, area.size.y))]:
		if side.has_area():
			canvas.draw_rect(side, OUTSIDE_COLOR)
	for part: Dictionary in _info().get("chunks", []):
		var rect := Rect2(part["offset"], units)
		canvas.draw_rect(rect, LINE_COLOR, false, LINE_WIDTH)
		canvas.draw_string_outline(font, rect.position + Vector2(24, 24 + NAME_FONT), "%s  %s" % [part["chunk"], part["id"]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT, 12, Color(0, 0, 0, 0.6))
		canvas.draw_string(font, rect.position + Vector2(24, 24 + NAME_FONT), "%s  %s" % [part["chunk"], part["id"]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT, NAME_COLOR)


## The editor's first save of the area is the copy the write-back compares with, so what the
## editor's tool scripts change on opening counts as no edit; only while the area's file is still
## as `AreaEdit.open` wrote it (the copy's text): once edits were saved into it, the copy stays.
func _keep_base() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var editor := _editor()
	if editor == null or not is_inside_tree() or get_tree().edited_scene_root != self:
		return
	var info := _info()
	var opened := FileAccess.get_file_as_string(str(info["base"]))
	info["base_pending"] = false
	set_meta(AreaEdit.AREA_META, info)
	if opened.is_empty() or FileAccess.get_file_as_string(scene_file_path) != opened:
		return
	if editor.call(&"save_scene") == OK:
		AreaEdit.SceneSave.write_text(str(info["base"]), FileAccess.get_file_as_string(scene_file_path))


## Saves the area and writes it back into its chunk files (all or nothing); then reads the chunks
## again into the area (so editing goes on from what was written), bakes the elevation cache of the
## chunks written and refreshes an open world atlas.
func write_back() -> void:
	var editor := _editor()
	if editor == null or get_tree().edited_scene_root != self:
		push_warning("Area: open the area's own tab to write it back.")
		return
	var open := _open_chunk_tabs(editor)
	if not open.is_empty():
		_tell("Not written: %s %s open in the editor, which keeps its own copy (a save there would write it over the chunk). Close %s first." % [
				", ".join(open), "is" if open.size() == 1 else "are", "it" if open.size() == 1 else "them"])
		return
	if editor.call(&"save_scene") != OK:
		_tell("Not written: the area could not be saved.")
		return
	var report := AreaEdit.write_back(scene_file_path)
	var written: PackedStringArray = report["written"]
	var lines := PackedStringArray()
	if not str(report["error"]).is_empty():
		lines.append(report["error"])
	if written.is_empty() and not lines.is_empty():
		lines.append_array(report["notes"])
		_tell("\n".join(lines))
		return
	lines.append("Written: %s." % (", ".join(written) if not written.is_empty() else "nothing (no chunk changed)"))
	lines.append_array(report["notes"])
	var filesystem: Object = editor.call(&"get_resource_filesystem")
	for id in written:
		filesystem.call(&"update_file", "res://game/scenes/worlds/chunks/%s.tscn" % id)
	# The chunks' paint read by their neighbours' cliffs ("Across chunk lines") is kept by file time,
	# one second fine: read it again.
	ChunkEdges.forget()
	var baked := _bake(written)
	if not baked.is_empty():
		lines.append(baked)
	_refresh_atlases(editor)
	var reopened := AreaEdit.open(_info()["rect"], WorldMapData.load_file(), true)
	if not str(reopened["error"]).is_empty():
		lines.append("The area could not be read again: " + str(reopened["error"]))
	_report = lines
	_tell("\n".join(lines))
	if str(reopened["error"]).is_empty():
		Callable(editor, &"reload_scene_from_path").call_deferred(scene_file_path)


## Reads the chunks again into the area: the edits not written back are lost.
func discard() -> void:
	var editor := _editor()
	if editor == null:
		return
	var reopened := AreaEdit.open(_info()["rect"], WorldMapData.load_file(), true)
	if not str(reopened["error"]).is_empty():
		_tell(reopened["error"])
		return
	Callable(editor, &"reload_scene_from_path").call_deferred(scene_file_path)


## Closes the area's tab and deletes the area (the edits not written back are lost).
func close_area() -> void:
	var editor := _editor()
	if editor == null or get_tree().edited_scene_root != self:
		return
	var path := scene_file_path
	editor.call(&"close_scene")
	AreaEdit.discard(path)
	(editor.call(&"get_resource_filesystem") as Object).call(&"update_file", path)
	_refresh_atlases(editor)


## The area's chunks whose scene is open in an editor tab.
func _open_chunk_tabs(editor: Object) -> PackedStringArray:
	var open: PackedStringArray = editor.call(&"get_open_scenes")
	var out := PackedStringArray()
	for part: Dictionary in _info().get("chunks", []):
		if open.has(part["path"]):
			out.append(str(part["id"]))
	return out


## Bakes the elevation cache (docs/godot/ELEVATION.md "Baked cache") of the chunk worlds `ids` and of
## the chunk worlds around them that paint elevation (their ground, cliffs and elevation make the
## cache's key, and each chunk's cliffs read its neighbours' paint past its edges: "Across chunk
## lines") with a headless run of tools/bake_elevation.gd; returns what it did, "" when there was
## nothing to bake.
func _bake(ids: PackedStringArray) -> String:
	if ids.is_empty():
		return ""
	var all := _with_neighbours(ids)
	print("Area: baking the elevation caches of %d chunk worlds (the written ones and their neighbours); the editor waits until it is done." % all.size())
	var output := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", BAKE_TOOL, "--", "--world=" + ",".join(all)], output, true)
	return "Elevation caches baked (the written chunks and their neighbours that paint elevation)." if code == 0 else \
			"The elevation bake failed (exit %d): run tools/bake_elevation.gd -- --world=%s." % [code, ",".join(all)]


## `ids` (chunk worlds) and the chunk worlds around each of them on the atlas grid.
static func _with_neighbours(ids: PackedStringArray) -> PackedStringArray:
	var all := ids.duplicate()
	for id: String in ids:
		var cell: Variant = BorderCrossing.chunk_cell(WorldChunks.chunk_of(id))
		if not cell is Vector2i:
			continue
		var around := ChunkEdges.neighbours(cell as Vector2i)
		for step: Vector2i in around:
			var neighbour := str(around[step]).get_file().get_basename()
			if not all.has(neighbour):
				all.append(neighbour)
	return all


## Reads the worlds again in every open world atlas.
func _refresh_atlases(editor: Object) -> void:
	if not editor.has_method(&"get_open_scene_roots"):
		return
	for root: Node in editor.call(&"get_open_scene_roots"):
		var script := root.get_script() as Script if root != null else null
		if script != null and script.resource_path == ATLAS_SCRIPT:
			root.call(&"refresh_worlds")


func _tell(text: String) -> void:
	print("Area %s: %s" % [AreaEdit.rect_name(_info().get("rect", Rect2i())), text])
	update_configuration_warnings()
	var editor := _editor()
	if editor == null:
		return
	# Freed through EditorDialogs: the editor's progress popup moves into this dialog when the
	# write-back's files are scanned while it is open.
	EditorDialogs.notice(editor, "Area %s" % AreaEdit.rect_name(_info().get("rect", Rect2i())), text)


## The editor's interface, null outside the editor (Engine.get_singleton keeps the script loading in
## exported builds: docs/godot/WORLD_ATLAS.md).
static func _editor() -> Object:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		return Engine.get_singleton(&"EditorInterface")
	return null

@tool
extends EditorPlugin
## The Scenery dock (docs/godot/PROPS.md): every scenery prop of the `cell-props` and `details`
## palettes by its picture, by category and with a name search. Drag a picture into the 2D view and
## Godot places the prop's scene there as a node; this plugin then moves it under the edited
## world's `Scenery` node (made when missing) and gives it the size chosen in the dock (its root's
## scale), in one step Ctrl+Z undoes. While dragging, Godot's own preview of the prop is shown at
## that size too. Painting stays for the mass of small scenery; this is for the props to place and
## nudge one by one. An enemy dragged from the Enemies category is a placed enemy
## (game/enemy/placed_enemy.gd, roadmap 5.25): it gets its type at once (Godot's preview shows the
## enemy too) and goes under the world's `Enemies` node, at its own size. A suckable dragged from the
## Suckables category is `object.liftable` with its `kind` set (game/scripts/liftable_root.gd), under
## Scenery at its own size. A piece from the Dungeon objects category keeps its own size and goes
## under the node the dock names for it (`Objects`, `RoomDoors` or `Hazards`; made when missing). A
## villager or an animal (the Villagers and Animals categories) keeps its own size and goes under
## `NPCs` or `Animals`.
##
## Also leaves the palette pictures out of exported games (palette_export.gd).
##
## Owner: world (props).

const Dock := preload("res://addons/scenery_dock/scenery_dock.gd")
const PaletteExport := preload("res://addons/scenery_dock/palette_export.gd")
## The node placed props go under, a child of the world's root; the one placed enemies go under.
const CONTAINER := "Scenery"
const ENEMIES_CONTAINER := "Enemies"

var _dock: Control
var _export: EditorExportPlugin
## The drag in flight: {scene, size, settings (the properties the placed node gets: {"enemy_type"}
## for an enemy, {"kind"} for a suckable, {} for a prop)}, until the drag ends.
var _pending := {}
## The props the drag's drop placed in the edited scene.
var _dropped: Array[Node] = []


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Scenery"
	_dock.set(&"prepare_drop", _prepare_drop)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	get_tree().node_added.connect(_on_node_added)
	_export = PaletteExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	if _export != null:
		remove_export_plugin(_export)
		_export = null
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _pending.is_empty():
		# Godot has dropped the prop (or the drag was cancelled) by now
		_finish_drop.call_deferred(_pending.duplicate(), _dropped.duplicate())
		_pending = {}
		_dropped.clear()


## Readies a drag of `scene` at `size` with `settings` (the properties the placed node gets), to go
## under `container` ("": Scenery, or Enemies), with Editable Children on when `editable`. False when
## no 2D scene is being edited.
func _prepare_drop(scene: String, size: float, settings: Dictionary = {}, container: String = "",
		editable: bool = false) -> bool:
	if not EditorInterface.get_edited_scene_root() is Node2D:
		return false
	_pending = {"scene": scene, "size": size, "settings": settings, "container": container, "editable": editable}
	_dropped.clear()
	return true


## While a drag is in flight: Godot's preview of the prop (outside the edited scene) takes the
## dock's size at once (a prop only) and its settings; the node dropped into the edited scene is
## kept for _finish_drop.
func _on_node_added(node: Node) -> void:
	if _pending.is_empty() or node.scene_file_path != _pending["scene"] or not node is Node2D:
		return
	var settings: Dictionary = _pending.get("settings", {})
	for key: String in settings:
		node.set(StringName(key), settings[key])
	var root := EditorInterface.get_edited_scene_root()
	if root != null and root.is_ancestor_of(node):
		_dropped.append(node)
	elif settings.is_empty() and str(_pending.get("container", "")).is_empty():
		(node as Node2D).scale *= float(_pending["size"])


## Placeholder heart ids: a heart quarter's scene comes as "unassigned", a full heart's empty; a heart
## with either is never picked up (goo_heart.gd).
const HEART_PLACEHOLDERS: PackedStringArray = ["", "unassigned"]


## A heart dropped in (a heart quarter, a full heart: a script node with `heart_id`) gets an id of its
## own in the same step, `<scene root>-heart-<n>` (the scene root is the world, so it is unique across
## maps), the first number no heart of the scene has; rename it in the Inspector if you like.
func _name_heart(undo: EditorUndoRedoManager, root: Node, node: Node) -> void:
	for child: Node in node.get_children():
		if not &"heart_id" in child or not HEART_PLACEHOLDERS.has(str(child.get(&"heart_id"))):
			continue
		var taken := {}
		for other: Node in root.find_children("*", "", true, false):
			if &"heart_id" in other:
				taken[str(other.get(&"heart_id"))] = true
		var number := 1
		while taken.has("%s-heart-%d" % [root.name, number]):
			number += 1
		undo.add_do_property(child, &"heart_id", "%s-heart-%d" % [root.name, number])
		undo.add_undo_property(child, &"heart_id", child.get(&"heart_id"))


## Moves the dropped props under the world's Scenery node, where they stood, at the dock's size
## (one undoable step; the Scenery node is made when missing).
func _finish_drop(pending: Dictionary, dropped: Array[Node]) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var nodes := dropped.filter(func(node: Node) -> bool: return is_instance_valid(node) and node.is_inside_tree() \
			and root != null and root.is_ancestor_of(node))
	if nodes.is_empty():
		return
	var settings: Dictionary = pending.get("settings", {})
	var enemy := settings.has("enemy_type")
	var named := str(pending.get("container", ""))
	# enemies, suckables and dungeon pieces keep their own size
	var size := 1.0 if not settings.is_empty() or not named.is_empty() else float(pending["size"])
	var container_name := named if not named.is_empty() else ENEMIES_CONTAINER if enemy else CONTAINER
	var undo := get_undo_redo()
	undo.create_action("Place in %s" % container_name)
	var container := root.get_node_or_null(container_name) as Node2D
	if container == null:
		container = Node2D.new()
		container.name = container_name
		# Scenery, Objects, NPCs and Animals sort with the world; Enemies, RoomDoors and Hazards do not
		container.y_sort_enabled = container_name in [CONTAINER, "Objects", "NPCs", "Animals"]
		undo.add_do_method(root, &"add_child", container, true)
		undo.add_do_method(container, &"set_owner", root)
		undo.add_do_reference(container)
		undo.add_undo_method(root, &"remove_child", container)
	for node: Node2D in nodes:
		var parent := node.get_parent()
		if parent != container:
			undo.add_do_method(node, &"reparent", container, true)
			undo.add_do_method(node, &"set_owner", root)
			# undo runs backwards: back to its parent first, then its owner again
			undo.add_undo_method(node, &"set_owner", root)
			undo.add_undo_method(node, &"reparent", parent, true)
		if not is_equal_approx(size, 1.0):
			undo.add_do_property(node, &"scale", node.scale * size)
			undo.add_undo_property(node, &"scale", node.scale)
		if bool(pending.get("editable", false)):
			# After the move (the scene keeps its editable instances by path), and first on the way
			# back: its script node, which holds its ids, shows in the Scene dock at once.
			undo.add_do_method(root, &"set_editable_instance", node, true)
			undo.add_undo_method(root, &"set_editable_instance", node, false)
		_name_heart(undo, root, node)
	undo.commit_action()
	if bool(pending.get("editable", false)):
		# The Scene dock draws an instance's children only when it builds the tree again.
		EditorInterface.get_selection().clear()
		for node: Node2D in nodes:
			EditorInterface.get_selection().add_node(node)

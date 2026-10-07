extends Node2D
## NPC quest markers (Phaser `features/npcs/NpcNameTags.ts` markers and
## `QuestNpcController.markerFor`; quests spec 4.5 and 10.7): a bold "!" / "?" / "…" over every NPC
## that has quest business. Child "QuestMarkers" of main in world space, made once and kept across
## worlds; `z_index = 1` draws it over the y-sorted world (owner decision Q6).
##
## | kind        | text | colour  | size |
## | main-offer  | !    | #ffd277 | 30   |
## | side-offer  | !    | #72d8ff | 26   |
## | turn-in     | ?    | #ffd277 | 30   |
## | in-progress | ?    | #a7bbd6 | 24   |
## | talk        | …    | #f5f7ff | 24   |
##
## Each marker's bottom centre sits at the NPC's old position (sprite bottom) - (0, 93.28) (the
## name tag offset: display height 229 x 0.32 + 2, then 18 above the tag) plus a bob of 3 px every
## 900 ms; outline 6 px #081022; a new marker pops from 0.4 to full size in 220 ms (back-out).
## Kinds come from the quest service's `marker_for(npc_id)` and are recomputed after every
## `quest_changed`; NPCs out of the tree (a story variant parked them) have none.
##
## Owner: quests.

const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const GROUP := &"npc_quest_markers"
const QUESTS_GROUP := &"quests"
const NPC_GROUP := &"npc"
const MARKERS := {
	"main-offer": ["!", Color("#ffd277"), 30],
	"side-offer": ["!", Color("#72d8ff"), 26],
	"turn-in": ["?", Color("#ffd277"), 30],
	"in-progress": ["?", Color("#a7bbd6"), 24],
	"talk": ["…", Color("#f5f7ff"), 24],
}
## NpcNameTags: nameTagY = npc.y - 229 * 0.32 - 2, the marker 18 above it.
const MARKER_RISE := 93.28
const BOB_PERIOD_MS := 900.0
const BOB_PX := 3.0
const POP_FROM := 0.4
const POP_MS := 220.0
const OUTLINE_COLOR := Color("#081022")
const OUTLINE_SIZE := 6

var _service: Node
## NPC definition id -> marker kind ("" = none); cleared on every quest change.
var _kinds: Dictionary = {}
## NPC node instance id -> {"npc": Node, "label": Label, "kind": String}.
var _markers: Dictionary = {}
var _theme: Theme


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = UiTokens.theme()


func _process(_delta: float) -> void:
	if _service == null or not is_instance_valid(_service):
		_bind()
		if _service == null:
			return
	var seen := {}
	var bob := sin(float(Time.get_ticks_msec()) / BOB_PERIOD_MS * TAU) * BOB_PX
	for node: Node in get_tree().get_nodes_in_group(NPC_GROUP):
		if not node.has_method(&"get_phaser_position"):
			continue
		var npc_id := str(node.get(&"npc_definition_id"))
		if not QuestCatalog.has_npc(npc_id):
			continue
		var key := node.get_instance_id()
		seen[key] = true
		if not _kinds.has(npc_id):
			_kinds[npc_id] = str(_service.call(&"marker_for", npc_id))
		var entry: Dictionary = _markers.get(key, {})
		if entry.is_empty():
			entry = {"npc": node, "label": _make_label(), "kind": ""}
			_markers[key] = entry
		_show(entry, str(_kinds[npc_id]))
		var label: Label = entry["label"]
		var body := node.get(&"body") as CanvasItem
		label.visible = not str(entry["kind"]).is_empty() and (body == null or body.is_visible_in_tree())
		if label.visible:
			var at: Vector2 = node.call(&"get_phaser_position")
			label.position = Vector2(at.x - label.size.x / 2.0, roundf(at.y - MARKER_RISE + bob) - label.size.y)
	for key: Variant in _markers.keys():
		if not seen.has(key):
			_drop(key)


## The marker kind shown over the NPC whose instance id key is `instance_key` ("" = none).
func kind_for(instance_key: String) -> String:
	for entry: Dictionary in _markers.values():
		var npc: Variant = entry["npc"]
		if is_instance_valid(npc) and str((npc as Node).call(&"get_instance_id_key")) == instance_key:
			return str(entry["kind"])
	return ""


## Recomputes every kind on the next frame (also called by main after a world change).
func refresh() -> void:
	_kinds.clear()


## World teardown: every marker goes (their NPCs are being freed).
func clear() -> void:
	for key: Variant in _markers.keys():
		_drop(key)
	_kinds.clear()


func _bind() -> void:
	_service = get_tree().get_first_node_in_group(QUESTS_GROUP)
	if _service != null and not _service.is_connected(&"quest_changed", _on_quest_changed):
		_service.connect(&"quest_changed", _on_quest_changed)


func _on_quest_changed(_payload: Dictionary) -> void:
	refresh()


func _make_label() -> Label:
	var label := Label.new()
	label.theme = _theme
	label.theme_type_variation = &"PanelTitle"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_constant_override(&"outline_size", OUTLINE_SIZE)
	label.add_theme_color_override(&"font_outline_color", OUTLINE_COLOR)
	label.visible = false
	add_child(label)
	return label


## Applies `kind` to a marker; a new (or changed) marker pops in.
func _show(entry: Dictionary, kind: String) -> void:
	if str(entry["kind"]) == kind:
		return
	entry["kind"] = kind
	var label: Label = entry["label"]
	if kind.is_empty() or not MARKERS.has(kind):
		entry["kind"] = ""
		label.visible = false
		return
	var style: Array = MARKERS[kind]
	label.text = str(style[0])
	label.add_theme_color_override(&"font_color", style[1])
	label.add_theme_font_size_override(&"font_size", int(style[2]))
	label.reset_size()
	label.pivot_offset = Vector2(label.size.x / 2.0, label.size.y)
	label.scale = Vector2.ONE * POP_FROM
	var tween := label.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "scale", Vector2.ONE, POP_MS / 1000.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _drop(key: Variant) -> void:
	var entry: Dictionary = _markers.get(key, {})
	_markers.erase(key)
	var label: Variant = entry.get("label")
	if label is Label and is_instance_valid(label):
		(label as Label).queue_free()

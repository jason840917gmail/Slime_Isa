@tool
extends VBoxContainer
## The Scenery dock's panel: a category list, a name search and the props' pictures (the palettes'
## normal tiles, cut from the palette images), which drag into the 2D view (scenery_list.gd).

const List := preload("res://addons/scenery_dock/scenery_list.gd")
const MANIFEST := "res://game/world/props/prop_palettes.json"
const ART_DIR := "res://asset/MAPS/palettes/"
## The manifest's palettes the dock lists, with their cell (px in the palette images).
const PALETTES := {"cell": 64, "detail": 32}
## The size the pictures are shown at.
const ICON := Vector2i(80, 80)

## Called before a drag starts: selects the node the drop goes under (the plugin's).
var prepare_drop := Callable()

var _categories: OptionButton
var _search: LineEdit
var _list: ItemList
## category -> [[name, scene path, picture]].
var _props := {}


func _ready() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	_categories = OptionButton.new()
	_categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_categories.item_selected.connect(func(_index: int) -> void: _show())
	bar.add_child(_categories)
	var reload := Button.new()
	reload.text = "Reload"
	reload.tooltip_text = "Read the palettes again (after tools/build_prop_palettes.gd)."
	reload.pressed.connect(_load)
	bar.add_child(reload)
	_search = LineEdit.new()
	_search.placeholder_text = "Search all props by name"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _show())
	add_child(_search)
	_list = List.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.max_columns = 0
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.fixed_icon_size = ICON
	_list.fixed_column_width = ICON.x + 16
	_list.same_column_width = true
	_list.set(&"dock", self)
	add_child(_list)
	var hint := Label.new()
	hint.text = "Drag a picture into the map: it becomes a node under Scenery."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 12)
	add_child(hint)
	_load()


## Reads the manifest and cuts every prop's picture out of its palette image.
func _load() -> void:
	_props.clear()
	_categories.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		return
	for palette: String in PALETTES:
		for entry: Dictionary in (parsed as Dictionary).get(palette, []):
			if entry.get("retired", false):
				continue
			var art := ART_DIR + "%s-%s.png" % [palette, str(entry["name"]).replace(" ", "-")]
			if not ResourceLoader.exists(art):
				continue
			var sheet := load(art) as Texture2D
			var slots: Dictionary = entry.get("slots", {})
			var normal := 1 if entry.get("sized", false) else 0
			var props: Array = []
			for scene: String in entry["scenes"]:
				var slot: Variant = slots.get("%s|%d" % [scene, normal])
				if scene.is_empty() or slot == null:
					continue
				var picture := AtlasTexture.new()
				picture.atlas = sheet
				picture.region = Rect2(Vector2(slot[0], slot[1]) * PALETTES[palette], Vector2(slot[2], slot[3]) * PALETTES[palette])
				props.append([_title(scene), scene, picture])
			if not props.is_empty():
				var category := str(entry["name"]) if palette == "cell" else "%s (details)" % entry["name"]
				_props[category] = props
				_categories.add_item(category)
	_show()


## A scene's name without its family prefix: "rock-world-wall-decorative--field-03" -> "field 03".
static func _title(scene: String) -> String:
	var name := scene.get_file().get_basename()
	if name.contains("--"):
		name = name.get_slice("--", 1)
	for prefix in ["interior-mushroom-", "interior-"]:
		name = name.trim_prefix(prefix)
	return name.replace("-", " ")


## Fills the list: the chosen category, or every prop whose name holds the search.
func _show() -> void:
	_list.clear()
	var needle := _search.text.strip_edges().to_lower()
	var shown: Array = []
	if needle.is_empty():
		if _categories.selected >= 0:
			shown = _props.get(_categories.get_item_text(_categories.selected), [])
	else:
		for category: String in _props:
			for prop: Array in _props[category]:
				if str(prop[0]).contains(needle) or str(prop[1]).get_file().to_lower().contains(needle):
					shown.append(prop)
	for prop: Array in shown:
		var index := _list.add_item(prop[0], prop[2])
		_list.set_item_metadata(index, prop[1])
		_list.set_item_tooltip(index, str(prop[1]).get_file())

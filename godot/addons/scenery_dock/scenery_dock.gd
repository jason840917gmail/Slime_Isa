@tool
extends VBoxContainer
## The Scenery dock's panel: a category list, a name search and the props' pictures (the palettes'
## normal tiles, cut from the palette images), which drag into the 2D view (scenery_list.gd). The
## **Enemies** category lists every enemy type by its picture: dragging one places a placed enemy
## (game/enemy/placed_enemy.gd) of that type (roadmap 5.25). The **Suckables** category (owner,
## 2026-10-19) lists every liftable kind (game/data/liftables.json: pots, crates, rocks, jars ...,
## the light things the Gulp sucks in, none of a mechanic's own like the skeleton's skull or the Goo
## Bomb): dragging one places `object.liftable` of that kind under Scenery; what it hides is its
## `under` in the Inspector (game/scripts/liftable_root.gd).

const List := preload("res://addons/scenery_dock/scenery_list.gd")
const PlacedEnemyScript := preload("res://game/enemy/placed_enemy.gd")
const LiftableRoot := preload("res://game/scripts/liftable_root.gd")
## The placed enemy scene and the category listing the enemy types.
const PLACED_SCENE := "res://game/scenes/encounters/placed-enemy.tscn"
const ENEMIES_CATEGORY := "Enemies"
## The suckable things' scene and their category.
const LIFTABLE_SCENE := "res://game/scenes/objects/liftable.tscn"
const SUCKABLES_CATEGORY := "Suckables"
const MANIFEST := "res://game/world/props/prop_palettes.json"
const ART_DIR := "res://asset/MAPS/palettes/"
## The manifest's palettes the dock lists, with their cell (px in the palette images).
const PALETTES := {"cell": 64, "detail": 32}
## The size the pictures are shown at.
const ICON := Vector2i(80, 80)

## The sizes a prop can be placed at.
const SIZES := [["Small", 0.7], ["Normal", 1.0], ["Big", 1.3]]

## Called before a drag starts with (scene, size, settings: the properties the placed node gets, as
## {"enemy_type": ...} or {"kind": ...}, {} for a prop): readies the drop (the plugin's).
var prepare_drop := Callable()

var _categories: OptionButton
var _size: OptionButton
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
	var size_bar := HBoxContainer.new()
	add_child(size_bar)
	var size_label := Label.new()
	size_label.text = "Size"
	size_bar.add_child(size_label)
	_size = OptionButton.new()
	_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for size: Array in SIZES:
		_size.add_item("%s (%d %%)" % [size[0], roundi(size[1] * 100)])
	_size.select(1)
	_size.tooltip_text = "The size props are placed at; change one later with its Scale in the Inspector."
	size_bar.add_child(_size)
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
	hint.text = "Drag a picture into the map: it becomes a node under Scenery, at the size above (an enemy: a placed enemy under Enemies)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 12)
	add_child(hint)
	_load()


## Reads the manifest and cuts every prop's picture out of its palette image; then the enemy types
## and their pictures (the Enemies category: [name, placed enemy scene, picture, type]).
func _load() -> void:
	_props.clear()
	_categories.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var palettes: Dictionary = parsed if parsed is Dictionary else {}
	for palette: String in PALETTES:
		for entry: Dictionary in palettes.get(palette, []):
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
	PlacedEnemyScript.reload()
	var enemies: Array = []
	for type_id in PlacedEnemyScript.known_types():
		var picture := PlacedEnemyScript.picture_texture(type_id)
		if picture != null:
			enemies.append([type_id.replace("-", " "), PLACED_SCENE, picture, {"enemy_type": type_id}])
	if not enemies.is_empty():
		_props[ENEMIES_CATEGORY] = enemies
		_categories.add_item(ENEMIES_CATEGORY)
	var suckables := _suckables()
	if not suckables.is_empty():
		_props[SUCKABLES_CATEGORY] = suckables
		_categories.add_item(SUCKABLES_CATEGORY)
	_show()


## Every liftable kind by its picture on the liftables sheet: [name, LIFTABLE_SCENE, picture, {"kind"}].
static func _suckables() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LiftableRoot.CATALOG))
	if not parsed is Dictionary:
		return []
	var catalog: Dictionary = parsed
	var sheet := load(str(catalog.get("sheet", ""))) as Texture2D if ResourceLoader.exists(str(catalog.get("sheet", ""))) else null
	if sheet == null:
		return []
	var cell := float(catalog.get("cell", 192))
	var columns := maxi(1, int(catalog.get("columns", 8)))
	var out: Array = []
	for id: String in (catalog.get("kinds", {}) as Dictionary):
		var frame := LiftableRoot.first_frame(id)
		var picture := AtlasTexture.new()
		picture.atlas = sheet
		picture.region = Rect2(Vector2(frame % columns, frame / columns) * cell, Vector2(cell, cell))
		var entry: Dictionary = catalog["kinds"][id]
		out.append([str(entry.get("name", id)).to_lower(), LIFTABLE_SCENE, picture, {"kind": id}])
	return out


## The size chosen for the next prop placed.
func drop_size() -> float:
	return SIZES[maxi(_size.selected, 0)][1]


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
		if prop.size() > 3:
			var settings: Dictionary = prop[3]
			_list.set_item_metadata(index, {"scene": prop[1], "settings": settings})
			if settings.has("enemy_type"):
				_list.set_item_tooltip(index, "%s (a placed enemy)" % settings["enemy_type"])
			else:
				_list.set_item_tooltip(index, "%s (suckable: set what is under it in the Inspector, `under`)" % settings.get("kind", ""))
		else:
			_list.set_item_metadata(index, prop[1])
			_list.set_item_tooltip(index, str(prop[1]).get_file())

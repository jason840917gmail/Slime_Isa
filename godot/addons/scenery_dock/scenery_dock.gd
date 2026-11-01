@tool
extends VBoxContainer
## The Scenery dock's panel: a category list, a name search and the props' pictures (the palettes'
## normal tiles, cut from the palette images), which drag into the 2D view (scenery_list.gd). The
## **Enemies** category lists every enemy type by its picture: dragging one places a placed enemy
## (game/enemy/placed_enemy.gd) of that type (roadmap 5.25). The **Suckables** category (owner,
## 2026-10-19) lists every liftable kind (game/data/liftables.json: pots, crates, rocks, jars ...,
## the light things the Gulp sucks in, none of a mechanic's own like the skeleton's skull or the Goo
## Bomb): dragging one places `object.liftable` of that kind under Scenery; what it hides is its
## `under` in the Inspector (game/scripts/liftable_root.gd). The **Dungeon objects** category
## (2026-10-19) lists the dungeons' pieces with logic (doors, chests, keys, shutters, winches,
## plates, heavy blocks, braziers ...) by their scene's own picture: dragging one places its scene
## at its own size under the room's `Objects` node (a room door under `RoomDoors`, a hazard under
## `Hazards`); its ids are set in the Inspector (docs/godot/DUNGEONS.md). The **Holes & hatches**
## category (owner, 2026-10-19) lists the ways down and up for any world: open holes (fall, ladder),
## cracked ground and walls (a Goo Bomb opens them), and hatches, placed the same way under `Objects`;
## their targets are set in the Inspector (docs/godot/DUNGEONS.md "Holes and hatches").

const List := preload("res://addons/scenery_dock/scenery_list.gd")
const PlacedEnemyScript := preload("res://game/enemy/placed_enemy.gd")
const LiftableRoot := preload("res://game/scripts/liftable_root.gd")
## The placed enemy scene and the category listing the enemy types.
const PLACED_SCENE := "res://game/scenes/encounters/placed-enemy.tscn"
const ENEMIES_CATEGORY := "Enemies"
## The suckable things' scene and their category.
const LIFTABLE_SCENE := "res://game/scenes/objects/liftable.tscn"
## A throw effect in the suckables' hover text (`gulp.throwCombat.effects`).
const EFFECT_TEXT := {
	"freeze": "freeze (a long stun, about 3 s)",
	"sleep": "sleep (no damage, a longer stun, about 4.5 s)",
	"stick": "stick (a stun, about 2.5 s)",
	"shatter": "shatter (breaks over 2.2x the radius)",
	"pierce": "pierce (flies on through up to 3 enemies)",
}
const SUCKABLES_CATEGORY := "Suckables"
## The dungeon pieces with logic: every scene of DUNGEON_DIR but the world-level ones, and the
## puzzle objects kept among the other objects.
const DUNGEON_CATEGORY := "Dungeon objects"
const OBJECTS_DIR := "res://game/scenes/objects/"
const DUNGEON_DIR := "res://game/scenes/objects/dungeon/"
const DUNGEON_SKIP: PackedStringArray = ["dungeon.tscn", "fatty-lair-dungeon.tscn"]
const DUNGEON_EXTRAS: PackedStringArray = [
	"brazier", "pressure-plate", "heavy-block", "heavy-plate", "heavy-statue", "heavy-statue-flipped",
	"heavy-ore-crate", "cracked-wall", "cracked-floor", "climb-wall", "cave-ladder",
	"barred-gate", "drop-gate", "eye-latch", "gate-winch", "winch-post-cracked", "latch-door",
	"lantern-gate", "plank-barricade", "rotten-timbers", "web-wall", "blast-keg", "mine-cart",
	"ore-lift", "crystal-lens", "crystal-veil", "gulp-spot-frog", "gulp-spot-silk", "gulp-spot-stone",
	"loose-prize", "full-heart", "pearl", "pearl-two", "pearl-three",
]
## The ways down and up, for the overworld as for rooms: scene ids under OBJECTS_DIR.
const HOLES_CATEGORY := "Holes & hatches"
const HOLES: PackedStringArray = [
	"open-hole", "open-hole-ladder", "cracked-floor", "cracked-ground", "cracked-wall", "hill-doorway", "hatch-exit",
	"cave-ladder",
]
## The node a dungeon piece goes under, by scene file name; the rest go under DUNGEON_CONTAINER.
const DUNGEON_CONTAINERS := {"room-door.tscn": "RoomDoors", "hazard.tscn": "Hazards", "hazard-deck.tscn": "Hazards"}
const DUNGEON_CONTAINER := "Objects"
const MANIFEST := "res://game/world/props/prop_palettes.json"
const ART_DIR := "res://asset/MAPS/palettes/"
## The manifest's palettes the dock lists, with their cell (px in the palette images).
const PALETTES := {"cell": 64, "detail": 32}
## The size the pictures are shown at.
const ICON := Vector2i(80, 80)

## The sizes a prop can be placed at.
const SIZES := [["Small", 0.7], ["Normal", 1.0], ["Big", 1.3]]

## Called before a drag starts with (scene, size, settings: the properties the placed node gets, as
## {"enemy_type": ...} or {"kind": ...}, {} for a prop) and container (the node a dungeon piece goes
## under, "" otherwise): readies the drop (the plugin's).
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
	# one line, the rest on hover: a wrapped label in a hidden tab keeps the height of its
	# narrowest layout and pushes the editor's bottom panel off the window
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.tooltip_text = hint.text
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
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
	var holes: Array = []
	for id in HOLES:
		var path := OBJECTS_DIR + id + ".tscn"
		if ResourceLoader.exists(path):
			holes.append([_title(path), path, _scene_picture(path), {}, DUNGEON_CONTAINER])
	if not holes.is_empty():
		_props[HOLES_CATEGORY] = holes
		_categories.add_item(HOLES_CATEGORY)
	var dungeon := _dungeon_objects()
	if not dungeon.is_empty():
		_props[DUNGEON_CATEGORY] = dungeon
		_categories.add_item(DUNGEON_CATEGORY)
	_show()


## The dungeon pieces by their scene's picture: [name, scene, picture, {}, container].
func _dungeon_objects() -> Array:
	var paths := PackedStringArray()
	for file in DirAccess.get_files_at(DUNGEON_DIR):
		if file.ends_with(".tscn") and not DUNGEON_SKIP.has(file):
			paths.append(DUNGEON_DIR + file)
	for id in DUNGEON_EXTRAS:
		if ResourceLoader.exists(OBJECTS_DIR + id + ".tscn"):
			paths.append(OBJECTS_DIR + id + ".tscn")
	var out: Array = []
	for path in paths:
		var container: String = DUNGEON_CONTAINERS.get(path.get_file(), DUNGEON_CONTAINER)
		out.append([_title(path), path, _scene_picture(path), {}, container])
	out.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	return out


## The biggest visible sprite of a scene, its current frame (Godot's scene icon when it has none).
func _scene_picture(path: String) -> Texture2D:
	var packed := load(path) as PackedScene
	var root := packed.instantiate() if packed != null else null
	var best: Texture2D = null
	var best_area := 0.0
	if root != null:
		for item in [root] + root.find_children("*", "", true, false):
			var picture := _sprite_frame(item)
			if picture != null and picture.get_size().x * picture.get_size().y > best_area:
				best = picture
				best_area = picture.get_size().x * picture.get_size().y
		root.free()
	if best != null:
		return best
	return EditorInterface.get_editor_theme().get_icon(&"PackedScene", &"EditorIcons")


## A visible sprite's current frame (an AtlasTexture; flipped as the sprite draws it, a statue facing
## the other side, so the two read apart), or null.
static func _sprite_frame(node: Node) -> Texture2D:
	if not node is CanvasItem or not (node as CanvasItem).visible:
		return null
	var texture: Texture2D = null
	var region := Rect2()
	if node is Sprite2D:
		var sprite := node as Sprite2D
		texture = sprite.texture
		if texture == null:
			return null
		region = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, texture.get_size())
		var cell := region.size / Vector2(sprite.hframes, sprite.vframes)
		region = Rect2(region.position + Vector2(sprite.frame % sprite.hframes, sprite.frame / sprite.hframes) * cell, cell)
	elif node is AnimatedSprite2D:
		var animated := node as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return null
		texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		if texture == null:
			return null
		region = Rect2(Vector2.ZERO, texture.get_size())
	else:
		return null
	if texture is AtlasTexture:
		region.position += (texture as AtlasTexture).region.position
		texture = (texture as AtlasTexture).atlas
	var picture := AtlasTexture.new()
	picture.atlas = texture
	picture.region = region
	var sprite := node as Sprite2D
	if sprite != null and (sprite.flip_h or sprite.flip_v):
		var image := picture.get_image()
		if image == null:
			return picture
		if sprite.flip_h:
			image.flip_x()
		if sprite.flip_v:
			image.flip_y()
		return ImageTexture.create_from_image(image)
	return picture


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


## A suckable's hover text: its kind's usual weight and its throw effect (each placed one's weight
## can be changed in the Inspector).
static func _suckable_tooltip(kind: String) -> String:
	var effect := LiftableRoot.kind_effect(kind)
	return "Weight: %s\nEffect: %s" % [LiftableRoot.kind_weight(kind), str(EFFECT_TEXT.get(effect, effect)) if not effect.is_empty() else "none"]


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
		if prop.size() > 4:
			_list.set_item_metadata(index, {"scene": prop[1], "settings": {}, "container": prop[4]})
			_list.set_item_tooltip(index, "%s (goes under %s; set its ids in the Inspector)" % [str(prop[1]).get_file(), prop[4]])
		elif prop.size() > 3:
			var settings: Dictionary = prop[3]
			_list.set_item_metadata(index, {"scene": prop[1], "settings": settings})
			if settings.has("enemy_type"):
				_list.set_item_tooltip(index, "%s (a placed enemy)" % settings["enemy_type"])
			else:
				_list.set_item_tooltip(index, _suckable_tooltip(str(settings.get("kind", ""))))
		else:
			_list.set_item_metadata(index, prop[1])
			_list.set_item_tooltip(index, str(prop[1]).get_file())

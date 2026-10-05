extends RefCounted
## Item icons for the bag, the belt, the crafting window and the HUD hotbar (Phaser draws the
## sheet frame with `object-fit: contain`). `generated/data/item-icons.json` maps each texture key
## to its sheet: {"path": "res://asset/...", "frame": [w, h], "columns", "rows"}, or
## {"procedural": true} for icons Phaser draws in code (the goo gauntlet). An item's icon is the
## frame `iconFrame` (row-major) of its `icon` key, as an AtlasTexture. A procedural or
## unknown key gets a 32 × 32 placeholder. Crafting spec 1.5, 10.3.
##
## Owner: crafting / inventory.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const ICONS_FILE := "item-icons.json"
## ProceduralAssetScene.ts:133: the gauntlet icon is 32 × 32.
const PLACEHOLDER_SIZE := 32
const PLACEHOLDER_COLOR := Color("#86f0c3")


## The icon of `item_id` (items and weapons alike); the placeholder when it has none.
static func icon(item_id: String) -> Texture2D:
	var definition := ItemCatalog.definition(item_id)
	if definition.is_empty():
		return placeholder()
	return frame_texture(str(definition.get("icon", "")), int(definition.get("iconFrame", 0)))


## Frame `frame` of sheet `key` as a new AtlasTexture (region = that cell; the sheet itself is
## cached by the ResourceLoader). Nothing is kept in static variables, so no texture outlives the
## game at exit.
static func frame_texture(key: String, frame: int) -> Texture2D:
	return _build(key, frame)


## The region of frame `frame` in sheet `key`: Rect2(col * w, row * h, w, h); empty when unknown.
static func frame_region(key: String, frame: int) -> Rect2:
	var sheet := _sheet(key)
	var size: Variant = sheet.get("frame")
	if not size is Array or (size as Array).size() < 2:
		return Rect2()
	var columns := maxi(1, int(sheet.get("columns", 1)))
	var w := float(size[0])
	var h := float(size[1])
	var index := maxi(0, frame)
	return Rect2((index % columns) * w, floori(float(index) / columns) * h, w, h)


static func placeholder() -> Texture2D:
	var image := Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(PLACEHOLDER_COLOR, 0.0))
	image.fill_rect(Rect2i(8, 8, 16, 16), PLACEHOLDER_COLOR)
	return ImageTexture.create_from_image(image)


static func _build(key: String, frame: int) -> Texture2D:
	var sheet := _sheet(key)
	var path := str(sheet.get("path", ""))
	if sheet.is_empty() or bool(sheet.get("procedural", false)) or path.is_empty() or not ResourceLoader.exists(path):
		return placeholder()
	var texture := load(path) as Texture2D
	if texture == null:
		return placeholder()
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = frame_region(key, frame)
	return atlas


static func _sheet(key: String) -> Dictionary:
	var constants := Services.constants()
	if constants == null or key.is_empty():
		return {}
	var data: Variant = constants.data_file(ICONS_FILE)
	if data is Dictionary and (data as Dictionary).get(key) is Dictionary:
		return data[key]
	return {}

extends RefCounted
class_name DungeonItems
## The dungeon items (docs/godot/DUNGEONS.md "Keys and the map"): small keys (a counter, never a
## bag item), the big key, the map and the compass. `give` puts one in the current dungeon's record
## (DungeonState) and shows it: the ceremony (game/ui/ceremony/ability_ceremony.gd) for the big key,
## the map, the compass and the run's first small key; later small keys pop up over the slime
## (item_pop.gd) with a jingle. Their pictures are the cells of one 2 x 2 sheet (ICONS_PATH: small
## key, big key, map, compass), with a drawn fallback until it exists.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const ItemPop := preload("res://game/dungeon/item_pop.gd")

const ICONS_PATH := "res://asset/UI/items/dungeon-items.webp"
const ICON_CELLS := Vector2i(2, 2)
const CELL_OF := {
	DungeonState.SMALL_KEY: Vector2i(0, 0), DungeonState.BIG_KEY: Vector2i(1, 0),
	DungeonState.MAP: Vector2i(0, 1), DungeonState.COMPASS: Vector2i(1, 1),
}
const NAMES := {
	DungeonState.SMALL_KEY: "Small Key", DungeonState.BIG_KEY: "Big Key",
	DungeonState.MAP: "Dungeon Map", DungeonState.COMPASS: "Compass",
}
const LINES := {
	DungeonState.SMALL_KEY: "It opens one locked door of this dungeon. Each keyhole takes one.",
	DungeonState.BIG_KEY: "It opens the great door, where this dungeon's master waits.",
	DungeonState.MAP: "Every room of this dungeon is on your map now, and the master's room too.",
	DungeonState.COMPASS: "Your map marks every chest not opened yet.",
}
## Fallback colours (the drawn icons).
const COLOURS := {
	DungeonState.SMALL_KEY: Color("#c8653c"), DungeonState.BIG_KEY: Color("#e3b341"),
	DungeonState.MAP: Color("#e8d6a8"), DungeonState.COMPASS: Color("#b98a3e"),
}
## The run's first small key gets the ceremony (a story flag), the next ones the pop.
const FIRST_KEY_FLAG := "dungeon.first-small-key"
const CUE_SMALL := &"QuestProgress"
const CUE_BIG := &"SecretFound"
const POP_RISE := 70.0

static var _icons: Dictionary = {}


## Gives `item` in the current dungeon and shows it. False outside a dungeon (or an unknown item).
static func give(tree: SceneTree, item: String) -> bool:
	var run := Services.run()
	var dungeon_id := DungeonState.current_id(tree)
	if run == null or dungeon_id.is_empty() or not item in DungeonState.ITEMS:
		return false
	var fresh := DungeonState.give_item(run, dungeon_id, item)
	present(tree, item, fresh)
	return true


## Shows `item` coming to the slime: the ceremony (big things, the first small key; only while
## main's ceremonies are on) or the pop over its head.
static func present(tree: SceneTree, item: String, fresh: bool = true) -> void:
	var run := Services.run()
	var ceremony := fresh and AbilityCeremony.enabled(tree) and (item != DungeonState.SMALL_KEY
		or (run != null and not run.has_flag(FIRST_KEY_FLAG)))
	if item == DungeonState.SMALL_KEY and run != null:
		run.set_flag(FIRST_KEY_FLAG)
	var feel := Services.feel()
	if ceremony:
		AbilityCeremony.request_entry(tree, entry(item))
		return
	var world := Services.world()
	if world != null and world.player != null and is_instance_valid(world.player):
		var head: Vector2 = world.player.get_centre() - Vector2(0.0, 30.0)
		ItemPop.spawn(icon(item), head, POP_RISE)
		if feel != null:
			feel.floating_text(head - Vector2(0.0, POP_RISE + 10.0), str(NAMES.get(item, item)) + "!", &"yellow", true)
	if feel != null:
		feel.audio_cue(CUE_SMALL if item == DungeonState.SMALL_KEY else CUE_BIG)


## The ceremony card of `item`.
static func entry(item: String) -> Dictionary:
	var how := ""
	match item:
		DungeonState.SMALL_KEY:
			how = "Walk into a locked door to use it."
		DungeonState.BIG_KEY:
			how = "Walk into the great door to open it."
		DungeonState.MAP, DungeonState.COMPASS:
			var key := ControlLabels.control_label(&"map")
			how = ("Open the map with %s." % key) if not key.is_empty() else ""
	return {"kicker": "Dungeon item", "name": str(NAMES.get(item, item)), "line": str(LINES.get(item, "")), "how": how,
		"icon": icon(item)}


## The picture of `item` (a cell of the sheet, else a drawn stand-in).
static func icon(item: String) -> Texture2D:
	if _icons.has(item):
		return _icons[item]
	var sheet := SheetSprite.load_picture(ICONS_PATH)
	var picture: Texture2D
	if sheet != null and CELL_OF.has(item):
		var cell := Vector2(sheet.get_size()) / Vector2(ICON_CELLS)
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(Vector2(CELL_OF[item]) * cell, cell)
		picture = atlas
	else:
		picture = _drawn(COLOURS.get(item, Color.WHITE))
	_icons[item] = picture
	return picture


## A plain round stand-in icon.
static func _drawn(colour: Color) -> Texture2D:
	var size := 48
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var middle := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(middle)
			if d < size * 0.42:
				image.set_pixel(x, y, colour.darkened(0.25) if d > size * 0.34 else colour)
	return ImageTexture.create_from_image(image)

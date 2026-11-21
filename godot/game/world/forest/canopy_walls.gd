extends RefCounted
## The canopy walls' crowns and roots (docs/godot/FORESTS.md "Canopy walls"; owner, 2026-11-20): the
## forest layer's second way to paint a wood, one solid mass of big round overlapping crowns with
## roots only along its foot. A palette tile paints one when its `forest_trees` data is
## "canopy:<set>"; ForestLayer lays the set's crowns over the painted cells and its roots along their
## south edge. The table godot/asset/MAPS/trees/canopy/canopy.json (scripts/art/build-canopy-walls.py)
## holds per set its atlas and its pieces' rectangles; each piece stands on the middle of its
## rectangle's bottom edge.
##
## Owner: world (forest).

const TABLE := "res://asset/MAPS/trees/canopy/canopy.json"
## A tile's `forest_trees` entry that paints a canopy wall of the set after it.
const PREFIX := "canopy:"
const CROWNS := "crowns"
const ROOTS := "roots"

static var _table := {}
static var _textures := {}


## The table: {scale, sets: {set: {texture, crowns: [[x, y, w, h]], roots: [[x, y, w, h]]}}}.
static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		_table = parsed if parsed is Dictionary else {"sets": {}}
	return _table


## The canopy set a painted cell's trees name ("canopy:forest" -> "forest"), or "" for trees.
static func set_of(trees: PackedStringArray) -> String:
	if trees.size() != 1 or not trees[0].begins_with(PREFIX):
		return ""
	return trees[0].trim_prefix(PREFIX)


## How many pieces of `kind` (CROWNS or ROOTS) the set has.
static func count(set_name: String, kind: String) -> int:
	var entry: Dictionary = (table().get("sets", {}) as Dictionary).get(set_name, {})
	return (entry.get(kind, []) as Array).size()


## Sets `sprite` up as piece `index` of `kind` of `set_name`: standing on the middle of its bottom
## edge `sink` world units below the sprite's position (so a root sorts behind the crown above it
## while its feet reach further down), at the table's scale, mipmapped. False when there is no such
## piece.
static func configure(sprite: Sprite2D, set_name: String, kind: String, index: int, sink := 0.0) -> bool:
	var entry: Dictionary = (table().get("sets", {}) as Dictionary).get(set_name, {})
	var rects: Array = entry.get(kind, [])
	if rects.is_empty():
		push_warning("CanopyWalls: no %s of set '%s' in %s" % [kind, set_name, TABLE])
		return false
	var rect: Array = rects[posmod(index, rects.size())]
	var path := str(entry["texture"])
	if not _textures.has(path):
		_textures[path] = load(path)
	var scale := float(table().get("scale", 0.5))
	sprite.texture = _textures[path]
	sprite.region_enabled = true
	sprite.region_rect = Rect2(rect[0], rect[1], rect[2], rect[3])
	sprite.centered = false
	sprite.offset = Vector2(-float(rect[2]) * 0.5, -float(rect[3]) + sink / scale)
	sprite.scale = Vector2.ONE * scale
	# Drawn at half size: mipmaps keep the leaf outlines from shimmering as the view moves.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return true

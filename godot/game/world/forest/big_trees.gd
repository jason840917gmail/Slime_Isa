extends RefCounted
## The big trees of every region set (docs/godot/FORESTS.md): forest, autumn, frost, desert,
## volcano, swamp, crystal, ruins and village, one atlas each, with the table
## godot/asset/MAPS/trees/sets/trees.json (scripts/art/build-tree-sets.py): per tree
## (<kind>-<variant>-<size>) its atlas, its rectangle there, its foot and whether it sways.
## ForestLayer draws them on painted cells; the placed tree scenes were set up from the same table
## (tools/retree_scenes.gd).
##
## Owner: world (forest).

const TABLE := "res://asset/MAPS/trees/sets/trees.json"
const SWAY_MATERIAL := "res://game/world/forest/tree_sway_material.tres"
const SHADOW_TEXTURE := "res://game/world/forest/tree_shadow.tres"
## A tree's shade on the ground (`shadow_for`): its size (width: of the tree; height: of the
## width), where it lies from the foot (in widths, a little to the lower right: the light comes
## from the upper left), its colour, and its draw order (above the ground at -2, below everything
## standing at 0).
const SHADOW_SIZE := Vector2(1.05, 0.62)
const SHADOW_OFFSET := Vector2(0.08, -0.12)
const SHADOW_COLOR := Color(0.03, 0.05, 0.02, 0.5)
const SHADOW_Z := -1

static var _table := {}
static var _textures := {}


## The table: {scale, trees: {name: {set, texture, rect, foot, sway}}}.
static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		_table = parsed if parsed is Dictionary else {"trees": {}}
	return _table


static func has(tree: String) -> bool:
	return (table().get("trees", {}) as Dictionary).has(tree)


## The trees of `set` (e.g. "desert"), by name.
static func of_set(set_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var trees: Dictionary = table().get("trees", {})
	for tree: String in trees:
		if str((trees[tree] as Dictionary).get("set", "")) == set_name:
			out.append(tree)
	return out


## Sets `sprite` up as `tree`: its atlas region standing on its foot (the sprite's origin), at
## 2 px per world unit, swaying when the tree sways. False when the table has no such tree.
static func configure(sprite: Sprite2D, tree: String) -> bool:
	var entry: Dictionary = (table().get("trees", {}) as Dictionary).get(tree, {})
	if entry.is_empty():
		push_warning("BigTrees: no tree '%s' in %s" % [tree, TABLE])
		return false
	var path := str(entry["texture"])
	if not _textures.has(path):
		_textures[path] = load(path)
	var rect: Array = entry["rect"]
	var foot: Array = entry["foot"]
	sprite.texture = _textures[path]
	sprite.hframes = 1
	sprite.vframes = 1
	sprite.frame = 0
	sprite.region_enabled = true
	sprite.region_rect = Rect2(rect[0], rect[1], rect[2], rect[3])
	sprite.centered = false
	sprite.offset = -Vector2(foot[0], foot[1])
	sprite.scale = Vector2.ONE * float(table().get("scale", 0.5))
	sprite.material = load(SWAY_MATERIAL) if bool(entry.get("sway", true)) else null
	return true


## The soft shade `tree` (a sprite set up by `configure`, positioned at its foot) casts on the
## ground. The shades of a wood overlap into a dark floor, so the ground between trunks reads as
## the inside of the wood.
static func shadow_for(tree: Sprite2D) -> Sprite2D:
	var width := tree.region_rect.size.x * absf(tree.scale.x) * SHADOW_SIZE.x
	var shade := Sprite2D.new()
	shade.name = "Shadow"
	shade.texture = load(SHADOW_TEXTURE)
	shade.modulate = SHADOW_COLOR
	shade.z_index = SHADOW_Z
	shade.scale = Vector2(width, width * SHADOW_SIZE.y) / 64.0
	shade.position = tree.position + SHADOW_OFFSET * width
	return shade

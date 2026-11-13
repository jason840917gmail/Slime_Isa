@tool
extends TileMapLayer
## The painted ground levels of a world (docs/godot/ELEVATION.md): a TileMapLayer named
## `elevation` beside the ground layer, on the same grid, using elevation_tileset.tres. Paint a
## level (−3 … 16; unpainted cells are level 0) on the cells whose top you walk on; the cliff wall
## hangs below the painted area's south edges by itself. Single-cell steps make 45° edges.
##
## In the editor the cliffs follow the paint (and the ground's paint) at once: this layer mounts
## the Elevation drawing under the ground layer. Its own squares are only a painting aid: hide the
## layer (eye icon) to see the result; the game hides it and WorldService mounts the elevation
## with its collision.
##
## Owner: world (elevation).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const GroundWallStyles := preload("res://game/world/elevation/cliffs/ground_wall_styles.gd")

## Inside dungeon rooms (an `interior-walls` layer), a raised floor shows a wall face on its north
## side too, like its front and sides: four visible walls (docs/godot/ELEVATION.md "Faces in rooms").
## The lower level stops at the face's foot, the upper floor's rim stays on its edge. Off, the north
## edge shows only a cap and is the lower level's wall foot itself (an edge in level-collision).
@export var room_back_faces: bool = false:
	set(value):
		room_back_faces = value
		if Engine.is_editor_hint() and is_inside_tree():
			_queue_rebuild()

## This world's own wall style for a ground (docs/godot/ELEVATION.md "Wall styles"; the owner,
## 2026-11-06: "trying different wall on a ground right there in the inspector"): the Inspector's
## "Wall Styles" section, one drop-down per ground this world paints: "default: <style>" (each
## ground's default, cliffs/ground_wall_styles.tres) or any style the `cliffs` layer paints. Kept in
## the ground layer's metadata (Elevation.WORLD_WALL_STYLES_META, which the walls read); the walls
## follow at once. A `cliffs` layer paint over a hill still wins.
const WALL_PREFIX := "wall_styles/"
const DEFAULT_CHOICE := "default"

var _queued := false
var _ground: TileMapLayer
## The grounds this world paints (`_grounds_here`), "" until asked; reset when the ground changes.
var _grounds: PackedStringArray = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		return
	changed.connect(_queue_rebuild)
	_ground = Elevation.find_ground(self)
	if _ground != null and not _ground.changed.is_connected(_queue_rebuild):
		_ground.changed.connect(_queue_rebuild)
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	_grounds = []
	if not is_inside_tree():
		return
	Elevation.mount(Elevation.find_ground(self), false)


func _get_property_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Engine.is_editor_hint() or _ground_layer() == null:
		return out
	var styles := GroundWallStyles.style_names()
	var defaults := Elevation.ground_wall_styles()
	for ground: String in _grounds_here():
		var options := PackedStringArray([_default_choice(ground, defaults)])
		options.append_array(styles)
		var own := _own_style(ground)
		if own != "" and not options.has(own):
			options.append(own)
		out.append({
			"name": WALL_PREFIX + _label(ground), "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM,
			"hint_string": ",".join(options), "usage": PROPERTY_USAGE_EDITOR,
		})
	return out


func _get(property: StringName) -> Variant:
	var ground := _ground_of(property)
	if ground == "":
		return null
	var own := _own_style(ground)
	return own if own != "" else _default_choice(ground, Elevation.ground_wall_styles())


func _set(property: StringName, value: Variant) -> bool:
	var ground := _ground_of(property)
	var layer := _ground_layer()
	if ground == "" or layer == null:
		return false
	var styles: Dictionary = (layer.get_meta(Elevation.WORLD_WALL_STYLES_META, {}) as Dictionary).duplicate()
	if str(value).begins_with(DEFAULT_CHOICE) or str(value) == "":
		styles.erase(ground)
	else:
		styles[ground] = str(value)
	if styles.is_empty():
		layer.remove_meta(Elevation.WORLD_WALL_STYLES_META)
	else:
		layer.set_meta(Elevation.WORLD_WALL_STYLES_META, styles)
	if Engine.is_editor_hint() and is_inside_tree():
		_queue_rebuild()
	return true


func _property_can_revert(property: StringName) -> bool:
	var ground := _ground_of(property)
	return ground != "" and _own_style(ground) != ""


func _property_get_revert(property: StringName) -> Variant:
	var ground := _ground_of(property)
	return _default_choice(ground, Elevation.ground_wall_styles()) if ground != "" else null


func _ground_layer() -> TileMapLayer:
	if _ground == null or not is_instance_valid(_ground):
		_ground = Elevation.find_ground(self)
	return _ground


## This world's own style for `ground` ("" when it takes the default).
func _own_style(ground: String) -> String:
	var layer := _ground_layer()
	if layer == null:
		return ""
	return str((layer.get_meta(Elevation.WORLD_WALL_STYLES_META, {}) as Dictionary).get(ground, ""))


## The drop-down's first choice: "default: <the ground's default style>".
static func _default_choice(ground: String, defaults: Dictionary) -> String:
	return "%s: %s" % [DEFAULT_CHOICE, str(defaults.get(ground, Elevation.DEFAULT_WALL_STYLE))]


## "Sand (sanddessert)": the name the Inspector shows (GroundWallStyles.GROUNDS) and the ground.
static func _label(ground: String) -> String:
	return "%s (%s)" % [GroundWallStyles.GROUNDS.get(ground, ground), ground]


## The ground a "Wall Styles" property is for ("" for any other property).
static func _ground_of(property: StringName) -> String:
	var name := str(property)
	if not name.begins_with(WALL_PREFIX) or not name.ends_with(")") or not name.contains("("):
		return ""
	return name.substr(name.rfind("(") + 1).trim_suffix(")")


## The grounds this world paints, in GroundWallStyles.GROUNDS' order (others after), and any it
## already gives a style of its own.
func _grounds_here() -> PackedStringArray:
	if not _grounds.is_empty():
		return _grounds
	var layer := _ground_layer()
	var found := {}
	if layer != null and layer.tile_set != null and layer.tile_set.has_custom_data_layer_by_name(Elevation.TILE_ID_DATA_LAYER):
		var seen := {}
		for cell_pos: Vector2i in layer.get_used_cells():
			var key := Vector3i(layer.get_cell_source_id(cell_pos), layer.get_cell_atlas_coords(cell_pos).x, layer.get_cell_atlas_coords(cell_pos).y)
			if seen.has(key):
				continue
			seen[key] = true
			var data := layer.get_cell_tile_data(cell_pos)
			var ground := Elevation.TerrainMaterials.ground_of(str(data.get_custom_data(Elevation.TILE_ID_DATA_LAYER))) if data != null else ""
			if ground != "" and ground != Elevation.TerrainMaterials.WATER:
				found[ground] = true
		for ground: String in (layer.get_meta(Elevation.WORLD_WALL_STYLES_META, {}) as Dictionary):
			found[ground] = true
	var out := PackedStringArray()
	for ground: String in GroundWallStyles.GROUNDS:
		if found.has(ground):
			out.append(ground)
	for ground: String in found:
		if not out.has(ground):
			out.append(ground)
	_grounds = out
	return out

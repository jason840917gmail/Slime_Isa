@tool
extends "res://game/runtime/sheet_sprite.gd"
## The picture of a door in a cliff's face: the cave mouth or the wall hole (docs/godot/DUNGEONS.md
## "Holes and hatches"), drawn in the style of the wall it stands in. The style is read from the wall
## just above the door's root (WallPictures.wall_style: the style the elevation draws that face in),
## so a door dragged onto any wall matches it by itself; `wall_style` picks one by hand instead. A
## style without its picture shows the default style's (meadow rock). The picture is centred on the
## root, its bottom edge `foot_px` above it.
##
## Owner: skins.

const WallPictures := preload("res://game/world/elevation/wall_pictures.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const GroundWallStyles := preload("res://game/world/elevation/cliffs/ground_wall_styles.gd")
## `wall_style`'s choice that reads the style from the wall.
const FROM_WALL := "from the wall"
## How far above the root (world units) the wall is read: on the face, above its foot.
const PROBE_ABOVE := 20.0

## Which door: its pictures are asset/MAPS/objects/<kind>-<style>.webp.
@export_enum("cave-mouth", "wall-hole") var kind: String = WallPictures.CAVE_MOUTH:
	set(value):
		kind = value
		_show()
## The wall style drawn: the wall's own (`FROM_WALL`), or one picked.
@export var wall_style: String = FROM_WALL:
	set(value):
		wall_style = value
		_show()
## How far the picture's bottom edge stands above the door's root (picture px; negative: below it).
@export var foot_px: float = 0.0:
	set(value):
		foot_px = value
		_show()


func _init() -> void:
	# out of the tree too (a scene instanced for its picture): the default style's
	_show()


func _enter_tree() -> void:
	add_to_group(Elevation.WALL_PICTURES_GROUP)
	if Engine.is_editor_hint():
		# dragged onto another wall in the editor: that wall's style
		set_notify_transform(true)


func _ready() -> void:
	_show()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_show()


## The elevation of this world was built (Elevation.WALL_PICTURES_GROUP): the picture matches its wall.
func walls_built(elevation: Node) -> void:
	if wall_style == FROM_WALL and elevation == Elevation.around(self):
		_show()


## The style shown: the one picked, else the wall's ("" off any wall).
func shown_style() -> String:
	if wall_style != FROM_WALL:
		return wall_style
	if not is_inside_tree():
		return ""
	return WallPictures.wall_style(self, global_position - Vector2(0.0, PROBE_ABOVE))


func _show() -> void:
	var path := WallPictures.path_of(kind, WallPictures.style_for(kind, shown_style()))
	if path != sheet_path:
		sheet_path = path
	if texture != null:
		offset = Vector2(-texture.get_width() * 0.5, -texture.get_height() - foot_px).round()


## The picture and its offset follow the style: never stored. `wall_style` offers every style.
func _validate_property(property: Dictionary) -> void:
	var key := str(property["name"])
	if key == "sheet_path" or key == "offset" or key == "texture":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE
	elif key == "wall_style":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = ",".join(PackedStringArray([FROM_WALL]) + GroundWallStyles.style_names())

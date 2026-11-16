@tool
extends Sprite2D
## A Sprite2D whose picture is the file `sheet_path` (the bestiary's enemy sheets, 2026-10-16;
## docs/godot/BESTIARY.md "Art"). It loads the imported texture when the picture has been imported,
## and until then reads the file itself, so a sheet packed while an editor holds the project shows
## in the game and in the editor before the editor imports it (the door leaf does the same:
## CONVENTIONS.md "Real doors' look"). An exported game always has the imported texture.
##
## Owner: enemy builder.

## The picture (`res://asset/...webp`). Loaded as soon as it is set, so a scene instanced outside
## the tree has its picture too (the placed enemies' editor picture, placed_enemy.gd `picture_of`).
@export_file("*.webp", "*.png") var sheet_path: String = "":
	set(value):
		sheet_path = value
		_load_sheet()


func _ready() -> void:
	if texture == null:
		_load_sheet()


func _load_sheet() -> void:
	var picture := load_picture(sheet_path)
	if picture != null:
		texture = picture


## The picture at `path`: the imported texture when there is one, else (not imported yet, or its
## import failed: a file the editor imported while it was still being written) the file read as an
## image; null when neither works.
static func load_picture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			return imported
	var file := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(file):
		return null
	var image := Image.load_from_file(file)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

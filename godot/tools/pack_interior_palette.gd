extends SceneTree
## Saves the interior walls' paint palette (asset/MAPS/walls/interior/palette.png, written by
## scripts/art/pack-interior-walls.py) as a native texture, palette.res, which the tileset uses: it
## needs no editor import, so a repacked palette works at once in the editor and the game, even while
## an editor holds the project (docs/godot/INTERIOR_WALLS.md "The sheet").
##     "<Godot console exe>" --headless --path godot -s res://tools/pack_interior_palette.gd
const SOURCE := "res://asset/MAPS/walls/interior/palette.png"
const OUT := "res://asset/MAPS/walls/interior/palette.res"
func _initialize() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if image == null or image.is_empty():
		print("interior palette: could not read ", SOURCE)
		quit(1)
		return
	var err := ResourceSaver.save(ImageTexture.create_from_image(image), OUT, ResourceSaver.FLAG_COMPRESS)
	print("interior palette: ", "saved " + OUT if err == OK else error_string(err))
	quit(0 if err == OK else 1)

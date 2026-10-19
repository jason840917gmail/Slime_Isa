extends SceneTree
## Saves the fences' paint palette (asset/MAPS/fences/fence_paint_tiles.png, written by
## scripts/art/build-fence-paint-tiles.py) as a native texture, fence_paint_tiles.res, which the
## tile set uses: it needs no editor import, so a repacked palette works at once in the editor and
## the game, even while an editor holds the project (docs/godot/FENCES.md).
##     "<Godot console exe>" --headless --path godot -s res://tools/pack_fence_paint_tiles.gd
const SOURCE := "res://asset/MAPS/fences/fence_paint_tiles.png"
const OUT := "res://asset/MAPS/fences/fence_paint_tiles.res"
func _initialize() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if image == null or image.is_empty():
		print("fence palette: could not read ", SOURCE)
		quit(1)
		return
	var err := ResourceSaver.save(ImageTexture.create_from_image(image), OUT, ResourceSaver.FLAG_COMPRESS)
	print("fence palette: ", "saved " + OUT if err == OK else error_string(err))
	quit(0 if err == OK else 1)

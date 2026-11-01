extends SceneTree
## Saves the interior walls' and floor trims' paint palettes (asset/MAPS/walls/interior/palette.png and
## trim-palette.png, written by scripts/art/pack-interior-walls.py and pack-floor-trims.py) as native
## textures, palette.res and trim-palette.res, which the tilesets use: they need no editor import, so a
## repacked palette works at once in the editor and the game, even while an editor holds the project
## (docs/godot/INTERIOR_WALLS.md "The sheet", "Floor trim").
##     "<Godot console exe>" --headless --path godot -s res://tools/pack_interior_palette.gd
const PALETTES := {
	"res://asset/MAPS/walls/interior/palette.png": "res://asset/MAPS/walls/interior/palette.res",
	"res://asset/MAPS/walls/interior/trim-palette.png": "res://asset/MAPS/walls/interior/trim-palette.res",
}
func _initialize() -> void:
	var failed := false
	for source: String in PALETTES:
		var image := Image.load_from_file(ProjectSettings.globalize_path(source))
		if image == null or image.is_empty():
			print("interior palette: could not read ", source)
			failed = true
			continue
		var out: String = PALETTES[source]
		var err := ResourceSaver.save(ImageTexture.create_from_image(image), out, ResourceSaver.FLAG_COMPRESS)
		print("interior palette: ", "saved " + out if err == OK else error_string(err))
		failed = failed or err != OK
	quit(1 if failed else 0)

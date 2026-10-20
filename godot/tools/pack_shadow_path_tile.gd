extends SceneTree
## Saves the shadow-path layer's paint palette (docs/godot/DUNGEONS.md "Dark-room extras"): one 64 px
## tile, the glow-moss patch (asset/MAPS/objects/dungeon/glow-moss.webp) on a faint square, as a
## native texture (shadow_path_paint_tile.res) that the tile set uses without an editor import.
##     "<Godot console exe>" --headless --path godot -s res://tools/pack_shadow_path_tile.gd
const SOURCE := "res://asset/MAPS/objects/dungeon/glow-moss.webp"
const OUT := "res://asset/MAPS/objects/dungeon/shadow_path_paint_tile.res"
const SIZE := 64
const MOSS := 58
const BACK := Color(0.08, 0.3, 0.25, 0.35)
func _initialize() -> void:
	var moss := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if moss == null or moss.is_empty():
		print("shadow path tile: could not read ", SOURCE)
		quit(1)
		return
	moss.convert(Image.FORMAT_RGBA8)
	moss.resize(MOSS, MOSS, Image.INTERPOLATE_LANCZOS)
	var tile := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	tile.fill(BACK)
	var at := (SIZE - MOSS) / 2
	tile.blend_rect(moss, Rect2i(0, 0, MOSS, MOSS), Vector2i(at, at))
	var err := ResourceSaver.save(ImageTexture.create_from_image(tile), OUT, ResourceSaver.FLAG_COMPRESS)
	print("shadow path tile: ", "saved " + OUT if err == OK else error_string(err))
	quit(0 if err == OK else 1)

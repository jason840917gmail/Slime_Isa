extends SceneTree
## Packs a painted pit picture (a source PNG under asset/Originals/) into a texture resource the game
## loads as it is, without an import (an ImageTexture saved compressed, as pack_interior_palette.gd
## does): cropped about its middle to the hole's aspect, made opaque (laid over black). PitDepth's
## `picture` draws it over the hole, under its dark, dust and glints (docs/godot/DUNGEONS.md, "The
## Crystal Mine rebuilt").
##
##   godot --headless --path godot -s res://tools/pack_pit_picture.gd -- \
##     --in=../asset/Originals/dungeon-kit/pits/mine-shaft-a.png \
##     --out=res://asset/MAPS/interiors/mine-shaft.res --aspect=832x448 [--width=1344]


func _init() -> void:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		var at := arg.find("=")
		if arg.begins_with("--") and at > 2:
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	var source := String(args.get("in", ""))
	var out := String(args.get("out", ""))
	if source.is_empty() or out.is_empty():
		push_error("pack_pit_picture: --in=<png> and --out=<res://...res> are needed")
		quit(1)
		return
	if source.is_relative_path():
		source = ProjectSettings.globalize_path("res://").path_join(source).simplify_path()
	var image := Image.load_from_file(source)
	if image == null or image.is_empty():
		push_error("pack_pit_picture: cannot read " + source)
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	# the hole's aspect: crop about the middle
	var aspect := String(args.get("aspect", ""))
	if aspect.contains("x"):
		var parts := aspect.split("x")
		var want := float(parts[0]) / float(parts[1])
		var w := image.get_width()
		var h := image.get_height()
		if float(w) / float(h) > want:
			var cw := int(round(h * want))
			image = image.get_region(Rect2i((w - cw) / 2, 0, cw, h))
		else:
			var ch := int(round(w / want))
			image = image.get_region(Rect2i(0, (h - ch) / 2, w, ch))
	if args.has("width"):
		var width := int(args["width"])
		image.resize(width, int(round(float(image.get_height()) * width / image.get_width())), Image.INTERPOLATE_LANCZOS)
	# opaque: laid over black (a hole shows nothing through it)
	var flat := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color.BLACK)
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	flat.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var err := ResourceSaver.save(ImageTexture.create_from_image(flat), out, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("pack_pit_picture: cannot save %s (%d)" % [out, err])
		quit(1)
		return
	print("pack_pit_picture: %s (%d x %d)" % [out, flat.get_width(), flat.get_height()])
	quit(0)

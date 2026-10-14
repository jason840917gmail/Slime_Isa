extends RefCounted
## What the prop palette builders share (docs/godot/PROPS.md): finding the scenery scenes and
## measuring a prop's visible picture.

const Props := preload("res://game/world/props/prop_layer.gd")
const OBJECTS := "res://game/scenes/objects/"
## Scripts a scenery scene may carry.
const PRESENTATION: PackedStringArray = [
	"res://game/runtime/animation_player.gd", "res://game/runtime/sfx_player_2d.gd",
	"res://game/runtime/sfx_player.gd",
]

static var _images := {}


## The scenery scenes under OBJECTS whose path (after OBJECTS) starts with one of `prefixes`: their
## only scripts are presentation (idle animation, sound), so scenes with gameplay scripts
## (resources, collectibles, beds, workbenches...) stay out.
static func scenery(prefixes: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for path in scenes_under(OBJECTS):
		var rel := path.trim_prefix(OBJECTS)
		var matched := false
		for prefix: String in prefixes:
			matched = matched or rel.begins_with(prefix)
		if matched and _is_scenery(path):
			out.append(path)
	out.sort()
	return out


static func scenes_under(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(scenes_under(dir.path_join(sub)))
	return out


static func _is_scenery(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var scripts := RegEx.create_from_string("path=\"(res://[^\"]+\\.gd)\"")
	for found in scripts.search_all(text):
		if not PRESENTATION.has(found.get_string(1)):
			return false
	return true


## The box of a prop's visible pixels at `size`, from its foot (units), or an empty Rect2.
static func picture(scene: String, size: float) -> Rect2:
	var prop := Props.make_prop({"scene": scene, "at": Vector2.ZERO, "size": size, "flip": false})
	if prop == null:
		return Rect2()
	var box := bounds(prop, Transform2D.IDENTITY)
	prop.free()
	return box


## Keeps `node`'s idle animations from starting (a swimming fish would leave its picture).
static func still(node: Node) -> void:
	for player in node.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).autoplay = ""


## The box `node`'s visible pixels cover, in the space `transform` maps `node`'s parent to.
static func bounds(node: Node, transform: Transform2D) -> Rect2:
	var here := transform * (node as Node2D).transform if node is Node2D else transform
	var box := Rect2()
	if (node is Sprite2D or node is AnimatedSprite2D) and (node as CanvasItem).visible:
		box = here * visible_rect(node as Node2D)
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var inner := bounds(child, here)
		if inner.has_area():
			box = inner if not box.has_area() else box.merge(inner)
	return box


## The rect of a sprite's opaque pixels, in its own space (its whole frame when the texture cannot
## be read).
static func visible_rect(item: Node2D) -> Rect2:
	var frame := Props.picture_rect(item)
	var texture: Texture2D = null
	var source := Rect2()
	if item is Sprite2D:
		var sprite := item as Sprite2D
		texture = sprite.texture
		if texture == null:
			return Rect2()
		source = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, texture.get_size())
		var cell := source.size / Vector2(sprite.hframes, sprite.vframes)
		source = Rect2(source.position + Vector2(sprite.frame % sprite.hframes, sprite.frame / sprite.hframes) * cell, cell)
	else:
		var animated := item as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return Rect2()
		texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		if texture == null:
			return Rect2()
		if texture is AtlasTexture:
			source = (texture as AtlasTexture).region
			texture = (texture as AtlasTexture).atlas
		else:
			source = Rect2(Vector2.ZERO, texture.get_size())
	var key := texture.resource_path
	if not _images.has(key):
		var loaded := texture.get_image()
		if loaded != null and loaded.is_compressed():
			loaded.decompress()
		_images[key] = loaded
	var image: Image = _images[key]
	if image == null:
		return frame
	var used := image.get_region(Rect2i(source)).get_used_rect()
	if not used.has_area():
		return Rect2()
	var scale := frame.size / source.size
	return Rect2(frame.position + Vector2(used.position) * scale, Vector2(used.size) * scale)

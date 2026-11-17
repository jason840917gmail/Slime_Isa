extends Sprite2D
## The picture of an enemy the slime carries as ammo (the enemy-ammo prototype:
## game/throw/gulpable_enemy.gd): the enemy's own sprite frame as it was when it was gulped, cut to
## its drawn art, about `size_px` across. It wriggles in the mouth (a small jiggle and a skew wobble,
## harder in the last `gulp.throwFeel.enemyAmmo.tellMs` before it bursts out at the held
## Dictionary's `struggle_until_ms`); a thrown thing spins its look itself (thrown_object.gd
## `_place_look`), so the wriggle touches only the sprite's `offset` and `skew`, never its position,
## scale or rotation (the mouth and the throw own those).
##
## The held Dictionary carries the picture as plain values (`frame_of`), so it survives a copy and a
## snapshot: `enemy_texture` (a res:// path), `enemy_region` ([x, y, w, h] on the sheet), `flip_h`
## and `art_px` (the art's longer side). `make` builds the look from them.
##
## Presentation only (real time).
##
## Owner: throw combat (the enemy-ammo prototype).

const Services := preload("res://game/shared/services.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")

## The wriggle: a jiggle of this many art px and a skew wobble of this many radians, this often; the
## tell before it bursts out is this many times as big and as fast.
const JIGGLE_SHARE := 0.05
const SKEW_RAD := 0.16
const WRIGGLE_HZ := 3.2
const TELL_SCALE := 2.2

## The used rectangle of each frame looked at so far ("<texture path>#<frame rect>" -> Rect2).
static var _used: Dictionary = {}

## Simulation ms at which the carried enemy bursts out (0 = never: a look in flight).
var struggle_until_ms: float = 0.0
## The art's longer side (sheet px): the jiggle is a share of it.
var art_px: float = 64.0

var _age_s: float = 0.0


## The picture of `visual` now, for a held Dictionary: {"enemy_texture", "enemy_region", "flip_h",
## "art_px"}; {} without a texture that has a file.
static func frame_of(visual: Sprite2D) -> Dictionary:
	if visual == null or not is_instance_valid(visual) or visual.texture == null:
		return {}
	var path := visual.texture.resource_path
	if path.is_empty():
		return {}
	var frame := _frame_rect(visual)
	var art := _art_rect(visual.texture, path, frame)
	return {
		"enemy_texture": path,
		"enemy_region": [art.position.x, art.position.y, art.size.x, art.size.y],
		"flip_h": visual.flip_h != (visual.scale.x < 0.0),
		"art_px": maxf(1.0, maxf(art.size.x, art.size.y)),
	}


## A look of `held` (an enemy's held Dictionary) about `size_px` across, centred on its node. A
## plain empty sprite when the picture is gone.
static func make(held: Dictionary, size_px: float) -> Sprite2D:
	var look: Sprite2D = new()
	look.centered = true
	var path := str(held.get("enemy_texture", ""))
	var region: Variant = held.get("enemy_region")
	if not path.is_empty() and ResourceLoader.exists(path) and region is Array and (region as Array).size() == 4:
		look.texture = load(path)
		look.region_enabled = true
		look.region_rect = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
		look.flip_h = bool(held.get("flip_h", false))
	look.set(&"art_px", maxf(1.0, float(held.get("art_px", size_px))))
	look.set(&"struggle_until_ms", float(held.get("struggle_until_ms", 0.0)))
	look.scale = Vector2.ONE * (size_px / maxf(1.0, float(held.get("art_px", size_px))))
	return look


func _process(delta: float) -> void:
	_age_s += delta
	var strength := 1.0
	var left := struggle_until_ms - Services.now_ms()
	if struggle_until_ms > 0.0 and left < ThrowFeel.number("enemyAmmo.tellMs", 0.0):
		strength = TELL_SCALE
	var turn := _age_s * TAU * WRIGGLE_HZ * strength
	offset = Vector2(sin(turn * 1.7), cos(turn)) * art_px * JIGGLE_SHARE * strength
	skew = sin(turn) * SKEW_RAD * strength


## The sheet rectangle of the frame `visual` shows (its region, or its cell of the frame grid).
static func _frame_rect(visual: Sprite2D) -> Rect2:
	var whole := Rect2(Vector2.ZERO, visual.texture.get_size())
	var sheet := visual.region_rect if visual.region_enabled else whole
	var columns := maxi(1, visual.hframes)
	var rows := maxi(1, visual.vframes)
	var cell := Vector2(sheet.size.x / float(columns), sheet.size.y / float(rows))
	@warning_ignore("integer_division")
	var at := Vector2(float(visual.frame % columns), float(visual.frame / columns))
	return Rect2(sheet.position + at * cell, cell)


## The part of `frame` that is drawn (its pixels that are not clear), on the sheet; `frame` itself
## when the picture cannot be read. Looked at once per frame of a sheet.
static func _art_rect(texture: Texture2D, path: String, frame: Rect2) -> Rect2:
	var key := "%s#%s" % [path, frame]
	if _used.has(key):
		return _used[key]
	var art := frame
	var image := texture.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed() and image.decompress() != OK:
			image = null
	if image != null and not image.is_empty():
		var cut := Rect2i(frame).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if cut.size.x > 0 and cut.size.y > 0:
			var part := image.get_region(cut)
			if part.detect_alpha() != Image.ALPHA_NONE:
				var used := part.get_used_rect()
				if used.size.x > 0 and used.size.y > 0:
					art = Rect2(Vector2(cut.position + used.position), Vector2(used.size))
	_used[key] = art
	return art

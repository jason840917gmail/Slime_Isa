extends Sprite2D
## One frame of a reworked boss's packed animations (step 2 of the dungeons 2 and 3 rework): the
## strips and `frames.json` that `scripts/art/boss_frames.py pack <boss>` writes to
## `res://asset/MAPS/enemies/bosses/<boss>/`. Each animation is a strip of equal cells at
## `px_per_unit` art pixels a game unit; its `anchor` is the art point placed at this sprite's
## position, its `box` the anchor frame's picture in the cell, `fps` and `order` how it plays.
##
## `show_frame(key, index)` swaps the strip and the frame; `play_index(key, elapsed_ms)` gives the
## frame an animation shows after `elapsed_ms` (looping its `order`, or held on the last). Pictures
## load through SheetSprite (they show before the editor imports them).
##
## Owner: boss port.

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const MANIFEST := "frames.json"

## The boss's packed folder (`res://asset/MAPS/enemies/bosses/<boss>`).
@export_dir var folder: String = ""

static var _manifests: Dictionary = {}
static var _pictures: Dictionary = {}

var _key: String = ""
var _flip: bool = false


## The folder's manifest (cached), {} when it cannot be read.
static func manifest_of(dir: String) -> Dictionary:
	if _manifests.has(dir):
		return _manifests[dir]
	var text := FileAccess.get_file_as_string(dir.path_join(MANIFEST))
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var out: Dictionary = parsed if parsed is Dictionary else {}
	_manifests[dir] = out
	return out


func _ready() -> void:
	centered = false
	if scale == Vector2.ONE:
		scale = Vector2.ONE / px_per_unit()


func px_per_unit() -> float:
	return maxf(0.01, float(manifest_of(folder).get("px_per_unit", 2.0)))


func has_animation(key: String) -> bool:
	return _entry(key).size() > 0


## The animation's frame count (0 when there is none).
func frame_count(key: String) -> int:
	return int(_entry(key).get("frames", 0))


## The frame shown `elapsed_ms` into `key`: its `order` at its `fps`, looping or held on the last.
func play_index(key: String, elapsed_ms: float, loop: bool = true) -> int:
	var entry := _entry(key)
	var order: Array = entry.get("order", [])
	if order.is_empty():
		return 0
	var step := int(maxf(0.0, elapsed_ms) / 1000.0 * float(entry.get("fps", 6.0)))
	return int(order[step % order.size()]) if loop else int(order[mini(step, order.size() - 1)])


## Shows frame `index` of `key`, mirrored round the anchor when `flip`.
func show_frame(key: String, index: int, flip: bool = false) -> void:
	var entry := _entry(key)
	if entry.is_empty():
		visible = false
		return
	if key != _key or flip != _flip:
		_key = key
		_flip = flip
		texture = _picture(str(entry.get("file", "")))
		hframes = maxi(1, int(entry.get("frames", 1)))
		vframes = 1
		var anchor := _vec(entry.get("anchor", [0, 0]))
		var cell := _vec(entry.get("cell", [0, 0]))
		flip_h = flip
		offset = Vector2(-(cell.x - anchor.x) if flip else -anchor.x, -anchor.y)
	frame = clampi(index, 0, hframes - 1)


## The anchor frame's picture as a Rect2 relative to the anchor, in world units (this sprite's
## scale applied; mirrored when shown flipped).
func box_of(key: String) -> Rect2:
	var entry := _entry(key)
	if entry.is_empty():
		return Rect2()
	var anchor := _vec(entry.get("anchor", [0, 0]))
	var box: Array = entry.get("box", [0, 0, 0, 0])
	var rect := Rect2(Vector2(float(box[0]), float(box[1])) - anchor,
		Vector2(float(box[2]) - float(box[0]), float(box[3]) - float(box[1])))
	rect.position *= scale
	rect.size *= scale
	return rect


## How far the picture reaches below its anchor (world units): a pose's feet, a hanging one's legs.
func below_anchor(key: String) -> float:
	var rect := box_of(key)
	return rect.position.y + rect.size.y


func current_key() -> String:
	return _key


func _entry(key: String) -> Dictionary:
	var animations: Variant = manifest_of(folder).get("animations", {})
	if animations is Dictionary and (animations as Dictionary).has(key):
		return (animations as Dictionary)[key]
	return {}


func _picture(file: String) -> Texture2D:
	var path := folder.path_join(file)
	if not _pictures.has(path):
		_pictures[path] = SheetSprite.load_picture(path)
	return _pictures[path]


static func _vec(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

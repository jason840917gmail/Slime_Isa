extends Node2D
## Two eye sockets glowing (the bestiary's Bone Leaper casting its leap; docs/godot/BESTIARY.md
## "Bone Leaper"): soft orange-gold halos over the sheet frame's eyes, so the tell reads from across
## the room. A child of the enemy's Visual (a sheet sprite with `centered` off and its own offset):
## `eyes` gives, per sheet frame, the two eyes' pixels in the frame's cell; the Visual's offset,
## scale and flip place them. `strength` (0..1) is how bright they burn. Presentation only.
##
## Owner: enemy builder.

const CORE := Color(1.0, 0.86, 0.42, 0.95)
const HALO := Color(1.0, 0.55, 0.12, 0.42)
const POINTS := 14

## Frame -> Array of eye pixels (Vector2) in the frame's cell (a frame not listed shows none).
var eyes: Dictionary = {}
## The core's and the halo's radius in cell pixels (the Visual's scale makes them world px).
var core_px: float = 5.0
var halo_px: float = 15.0
var strength: float = 0.0:
	set(value):
		strength = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	# Over the sprite's own pixels.
	z_index = 1
	z_as_relative = true


## Call after the frame or the flip changed.
func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var sprite := get_parent() as Sprite2D
	if sprite == null or strength <= 0.0:
		return
	var points: Variant = eyes.get(sprite.frame)
	if not points is Array:
		return
	var cell := sprite.texture.get_size() / Vector2(maxi(1, sprite.hframes), maxi(1, sprite.vframes)) \
		if sprite.texture != null else Vector2(256.0, 256.0)
	for eye: Variant in points:
		if not eye is Vector2:
			continue
		var at: Vector2 = eye
		if sprite.flip_h:
			at.x = cell.x - at.x
		var centre := at + sprite.offset if not sprite.centered else at - cell * 0.5
		draw_colored_polygon(_circle(centre, halo_px * lerpf(0.6, 1.0, strength)), Color(HALO, HALO.a * strength))
		draw_colored_polygon(_circle(centre, core_px), Color(CORE, CORE.a * strength))


func _circle(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in POINTS:
		var angle := TAU * float(i) / float(POINTS)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points

extends Node2D
class_name ParticleFx
## Pooled one-shot particle bursts (Phaser `features/feel/ParticlePresets.ts`, procedural
## textures from `ProceduralAssetScene.ts:87-101`). Combat spec 13, player spec 8.
## World-space Node2D created by GameFeel (z_index high so bursts draw over the world),
## PROCESS_MODE_ALWAYS (bursts keep moving during hit-stop). CPUParticles2D, one_shot,
## explosiveness 1, restarted per burst.
##
## Presets (count, lifespan ms, speed min-max, angle deg, gravity y, scale from->to, alpha
## from->to, blend, texture):
##   hit-spark:    7, 220, 90-220, 0-360, 0, 0.9->0, 1->0, additive, "fx-spark" 16x16
##   slime-splash: 9, 420, 50-140, 200-340, +420, 0.8->0.3, 1->0, normal, "fx-goo-drop" 16x16
##   dodge-dust:   9, 460, 30-95, 0-360, -30, 0.9->0.25, 0.8->0, normal, "dust-puff"
##   boss-burst:   36, 900, 120-320, 0-360, 0, 1.6->0, 1->0, normal, "fx-sparkle", random rotation
##                 0-360, each particle tinted one of #ffe89a #86f0c3 #ffffff (boss spec 4.4)
##   loot-sparkle: 6, 520, 20-60, 220-320, 0, 0.9->0, 1->0, normal, "fx-sparkle", random rotation
##                 0-180 (world-objects spec 7.4: every pickup, over the slime)
##   dust-puff:    60, 700-1200, 30-130, 180-360, 0, 2.2->0.6, 0.95->0, normal, "dust-puff",
##                 spawned anywhere in the rect (-140, -90, 280, 120) around the point (abilities
##                 spec 13.8: a restored building; WorldScene.ts:2117-2126)
##
## Optional preset keys: "lifespan_min_ms" (a random lifespan between it and "lifespan_ms") and
## "emit_rect" (a Rect2 around the burst point that particles start in; Phaser `emitZone`).
##
## Layers: "over" bursts stay under this node (z_index OVER_Z_INDEX, above every world object).
## "ground" bursts are moved under the y-sorted world entities root (holder at y + 2, emitter
## offset back up), so they sort with the creatures like Phaser's `resolveWorldDepth(y + 2)`.
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")

const PRESET_IDS: Array[StringName] = [&"hit-spark", &"slime-splash", &"dodge-dust", &"boss-burst", &"loot-sparkle", &"dust-puff"]

## Emitters per preset (round robin): a new burst restarts the oldest emitter, so up to this many
## bursts of one preset overlap (Phaser recycles particles of a single emitter).
const EMITTERS_PER_PRESET := 6
## Draw layer for "over" bursts (ParticlePresets.ts OVER_DEPTH: above every world object).
const OVER_Z_INDEX := 100
## "ground" bursts sort with the world at y + 2 (ParticlePresets.ts:69).
const GROUND_SORT_OFFSET_Y := 2.0
const LAYER_OVER := "over"
const LAYER_GROUND := "ground"

## ParticlePresets.ts:18-31. Phaser angles are degrees clockwise from +x (y down); an absent
## angle means 0-360. "rotate" is the particle's random initial rotation.
const PRESETS := {
	&"hit-spark": {"texture": "fx-spark", "count": 7, "layer": LAYER_OVER, "lifespan_ms": 220.0,
		"speed_min": 90.0, "speed_max": 220.0, "angle_min": 0.0, "angle_max": 360.0, "gravity_y": 0.0,
		"scale_start": 0.9, "scale_end": 0.0, "alpha_start": 1.0, "alpha_end": 0.0, "additive": true,
		"rotate_min": 0.0, "rotate_max": 0.0},
	&"slime-splash": {"texture": "fx-goo-drop", "count": 9, "layer": LAYER_GROUND, "lifespan_ms": 420.0,
		"speed_min": 50.0, "speed_max": 140.0, "angle_min": 200.0, "angle_max": 340.0, "gravity_y": 420.0,
		"scale_start": 0.8, "scale_end": 0.3, "alpha_start": 1.0, "alpha_end": 0.0, "additive": false,
		"rotate_min": 0.0, "rotate_max": 0.0},
	&"dodge-dust": {"texture": "dust-puff", "count": 9, "layer": LAYER_GROUND, "lifespan_ms": 460.0,
		"speed_min": 30.0, "speed_max": 95.0, "angle_min": 0.0, "angle_max": 360.0, "gravity_y": -30.0,
		"scale_start": 0.9, "scale_end": 0.25, "alpha_start": 0.8, "alpha_end": 0.0, "additive": false,
		"rotate_min": 0.0, "rotate_max": 360.0},
	# ParticlePresets.ts:35-38; "tints" = Phaser `tint: [...]` (one picked per particle).
	&"boss-burst": {"texture": "fx-sparkle", "count": 36, "layer": LAYER_OVER, "lifespan_ms": 900.0,
		"speed_min": 120.0, "speed_max": 320.0, "angle_min": 0.0, "angle_max": 360.0, "gravity_y": 0.0,
		"scale_start": 1.6, "scale_end": 0.0, "alpha_start": 1.0, "alpha_end": 0.0, "additive": false,
		"rotate_min": 0.0, "rotate_max": 360.0,
		"tints": [Color("#ffe89a"), Color("#86f0c3"), Color("#ffffff")]},
	# ParticlePresets.ts:31-34.
	&"loot-sparkle": {"texture": "fx-sparkle", "count": 6, "layer": LAYER_OVER, "lifespan_ms": 520.0,
		"speed_min": 20.0, "speed_max": 60.0, "angle_min": 220.0, "angle_max": 320.0, "gravity_y": 0.0,
		"scale_start": 0.9, "scale_end": 0.0, "alpha_start": 1.0, "alpha_end": 0.0, "additive": false,
		"rotate_min": 0.0, "rotate_max": 180.0},
	&"dust-puff": {"texture": "dust-puff", "count": 60, "layer": LAYER_OVER, "lifespan_ms": 1200.0,
		"lifespan_min_ms": 700.0, "emit_rect": Rect2(-140.0, -90.0, 280.0, 120.0),
		"speed_min": 30.0, "speed_max": 130.0, "angle_min": 180.0, "angle_max": 360.0, "gravity_y": 0.0,
		"scale_start": 2.2, "scale_end": 0.6, "alpha_start": 0.95, "alpha_end": 0.0, "additive": false,
		"rotate_min": 0.0, "rotate_max": 0.0},
}

## texture name -> ImageTexture
var _textures: Dictionary = {}
## preset -> Array of holder Node2D (each holds one CPUParticles2D child "Emitter")
var _pools: Dictionary = {}
## preset -> next pool index
var _cursor: Dictionary = {}


## Draws the procedural textures into ImageTextures and builds the emitter pool.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = OVER_Z_INDEX
	_textures = {
		"fx-spark": _make_texture(16, 16, [
			[8.0, 8.0, 7.0, Color(Color("#fff2b8"), 0.55)],
			[8.0, 8.0, 3.5, Color(1, 1, 1, 1)],
		]),
		"fx-goo-drop": _make_texture(16, 16, [
			[8.0, 9.0, 6.0, Color("#2f8f3a")],
			[8.0, 8.0, 5.0, Color("#7be08a")],
			[6.0, 6.0, 1.6, Color(1, 1, 1, 0.8)],
		]),
		"dust-puff": _make_texture(32, 32, [
			[16.0, 16.0, 15.0, Color(Color("#d9c8a4"), 0.18)],
			[16.0, 16.0, 12.0, Color(Color("#d9c8a4"), 0.28)],
			[16.0, 16.0, 9.0, Color(Color("#d9c8a4"), 0.4)],
			[16.0, 16.0, 6.0, Color(Color("#d9c8a4"), 0.5)],
			[13.0, 13.0, 4.0, Color(Color("#f3ead6"), 0.45)],
		]),
		"fx-sparkle": _make_sparkle_texture(),
	}
	for preset: StringName in PRESET_IDS:
		var pool: Array = []
		for i in EMITTERS_PER_PRESET:
			pool.append(_make_holder(preset, i))
		_pools[preset] = pool
		_cursor[preset] = 0


## Emits one burst of `preset` at `world_position`; unknown presets are ignored.
func emit_burst(preset: StringName, world_position: Vector2) -> void:
	if not PRESETS.has(preset) or not _pools.has(preset):
		return
	var config: Dictionary = PRESETS[preset]
	var pool: Array = _pools[preset]
	var index: int = _cursor[preset]
	_cursor[preset] = (index + 1) % pool.size()
	var holder: Node2D = pool[index] if is_instance_valid(pool[index]) else null
	if holder == null or holder.is_queued_for_deletion():
		holder = _make_holder(preset, index)
		pool[index] = holder
	var emitter := holder.get_node(^"Emitter") as CPUParticles2D
	var zone_centre: Vector2 = (config["emit_rect"] as Rect2).get_center() if config.has("emit_rect") else Vector2.ZERO
	if config["layer"] == LAYER_GROUND:
		_attach_ground(holder)
		holder.global_position = world_position + Vector2(0.0, GROUND_SORT_OFFSET_Y)
		emitter.position = zone_centre - Vector2(0.0, GROUND_SORT_OFFSET_Y)
	else:
		if holder.get_parent() != self:
			_reparent(holder, self)
		holder.global_position = world_position
		emitter.position = zone_centre
	emitter.restart()


# --- private ---------------------------------------------------------------------------------

## A holder Node2D with one configured CPUParticles2D child named "Emitter", added under self.
func _make_holder(preset: StringName, index: int) -> Node2D:
	var config: Dictionary = PRESETS[preset]
	var holder := Node2D.new()
	holder.name = "%s_%d" % [String(preset).replace("-", "_"), index]
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var emitter := CPUParticles2D.new()
	emitter.name = "Emitter"
	emitter.process_mode = Node.PROCESS_MODE_ALWAYS
	emitter.emitting = false
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.amount = int(config["count"])
	emitter.lifetime = float(config["lifespan_ms"]) / 1000.0
	if config.has("lifespan_min_ms"):
		emitter.lifetime_randomness = clampf(1.0 - float(config["lifespan_min_ms"]) / float(config["lifespan_ms"]), 0.0, 1.0)
	if config.has("emit_rect"):
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = (config["emit_rect"] as Rect2).size / 2.0
	# Local coordinates: the holder never moves during a burst, and a one-shot burst in global
	# coordinates draws nothing on 4.7.2 with physics interpolation on (checked in the running game).
	emitter.local_coords = true
	emitter.texture = _textures.get(config["texture"])
	# Phaser angle range [min, max] (clockwise from +x, y down) -> centre direction + half spread.
	var angle_min := float(config["angle_min"])
	var angle_max := float(config["angle_max"])
	emitter.direction = Vector2.from_angle(deg_to_rad((angle_min + angle_max) / 2.0))
	emitter.spread = minf(180.0, (angle_max - angle_min) / 2.0)
	emitter.initial_velocity_min = float(config["speed_min"])
	emitter.initial_velocity_max = float(config["speed_max"])
	emitter.gravity = Vector2(0.0, float(config["gravity_y"]))
	emitter.angle_min = float(config["rotate_min"])
	emitter.angle_max = float(config["rotate_max"])
	var scale_start := float(config["scale_start"])
	var scale_end := float(config["scale_end"])
	emitter.scale_amount_min = scale_start
	emitter.scale_amount_max = scale_start
	if scale_start > 0.0:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		curve.add_point(Vector2(1.0, scale_end / scale_start), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		emitter.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, float(config["alpha_start"])))
	ramp.set_color(1, Color(1, 1, 1, float(config["alpha_end"])))
	emitter.color_ramp = ramp
	var tints: Array = config.get("tints", [])
	if not tints.is_empty():
		# One tint per particle, picked uniformly (constant-interpolation ramp sampled at random).
		var initial := Gradient.new()
		initial.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var offsets := PackedFloat32Array()
		var colors := PackedColorArray()
		for i in tints.size():
			offsets.append(float(i) / float(tints.size()))
			colors.append(tints[i])
		initial.offsets = offsets
		initial.colors = colors
		emitter.color_initial_ramp = initial
	if bool(config["additive"]):
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		emitter.material = material
	holder.add_child(emitter)
	add_child(holder)
	return holder


## Ground bursts sort with the world: move the holder under the y-sorted world entities root
## when one is registered (it then dies with the world and is recreated lazily); else keep it
## under this node.
func _attach_ground(holder: Node2D) -> void:
	var world := Services.world()
	var root: Node2D = world.entities_root() if world != null else null
	var target: Node = self
	if root != null and is_instance_valid(root) and root.is_inside_tree():
		target = root
	if holder.get_parent() != target:
		_reparent(holder, target)
	# Under this node the holder inherits OVER_Z_INDEX; inside the world it sorts at z 0.
	holder.z_index = 0 if target != self else -OVER_Z_INDEX


func _reparent(node: Node, parent: Node) -> void:
	var old := node.get_parent()
	if old != null:
		old.remove_child(node)
	parent.add_child(node)


## Draws filled circles (Phaser Graphics.fillCircle, source-over) into an ImageTexture. Each
## circle is [cx, cy, radius, Color]; a pixel is covered when its centre is inside the circle.
static func _make_texture(width: int, height: int, circles: Array) -> ImageTexture:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for circle: Array in circles:
		var cx := float(circle[0])
		var cy := float(circle[1])
		var radius := float(circle[2])
		var color: Color = circle[3]
		for y in height:
			for x in width:
				var dx := float(x) + 0.5 - cx
				var dy := float(y) + 0.5 - cy
				if dx * dx + dy * dy > radius * radius:
					continue
				image.set_pixel(x, y, _blend_over(image.get_pixel(x, y), color))
	return ImageTexture.create_from_image(image)


## The "fx-sparkle" texture (ProceduralAssetScene.ts:103-111): four #ffe89a triangles
## (a four-point star) and a white circle r 2 at the centre of 16 x 16; a pixel is covered when
## its centre is inside the shape.
static func _make_sparkle_texture() -> ImageTexture:
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var star := Color("#ffe89a")
	var triangles: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(8, 0), Vector2(10, 8), Vector2(6, 8)]),
		PackedVector2Array([Vector2(8, 16), Vector2(10, 8), Vector2(6, 8)]),
		PackedVector2Array([Vector2(0, 8), Vector2(8, 6), Vector2(8, 10)]),
		PackedVector2Array([Vector2(16, 8), Vector2(8, 6), Vector2(8, 10)]),
	]
	for y in 16:
		for x in 16:
			var centre := Vector2(float(x) + 0.5, float(y) + 0.5)
			for triangle: PackedVector2Array in triangles:
				if Geometry2D.is_point_in_polygon(centre, triangle):
					image.set_pixel(x, y, star)
					break
			if centre.distance_to(Vector2(8.0, 8.0)) <= 2.0:
				image.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(image)


## Straight-alpha source-over.
static func _blend_over(dst: Color, src: Color) -> Color:
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a <= 0.0:
		return Color(0, 0, 0, 0)
	var r := (src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / out_a
	var g := (src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / out_a
	var b := (src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / out_a
	return Color(r, g, b, out_a)

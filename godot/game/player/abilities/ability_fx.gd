extends Node2D
## One-off ability visuals (Phaser `LegacyPlayerAbilityPresentation.ts`: `spawnFlash`, the slam
## ring, the jump shadow, the landing goo dust, the lash tendril; abilities spec 5.3, 6.1, 7.3,
## 8.2). Each is a node in the world that tweens itself and frees itself; tweens pause with the
## tree (hit-stop), like Phaser's scene tweens.
##
## The improved Squash Slam's landing (body-shapes plan section 4 "Effects and sound", section 9
## "Effects: drawn or code"; slam_sequence.gd), all drawn in code: a shockwave ellipse on the ground
## (`shockwave`), the crack decal at the feet (`crack_decal`, the boss crack art reused), pebbles
## and dust in the colour of the ground under the slime (`debris`, `ground_tint`: the tile's average
## colour, as the minimap draws it) and the liftables around rocking (`wobble_liftables`).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Liftable := preload("res://game/scripts/liftable.gd")
const MapTerrainColors := preload("res://game/ui/map/map_terrain.gd")
const Self := preload("res://game/player/abilities/ability_fx.gd")

## Drawn over entities ("reveal-effects" band).
const OVER_Z := 50
## Lies on the ground, under the bodies (as the jump shadow).
const GROUND_Z := -1
const KIND_CIRCLE := 0
const KIND_ELLIPSE := 1
const KIND_DOTS := 2
const KIND_SHOCKWAVE := 3
const KIND_DECAL := 4
const KIND_DEBRIS := 5

## The Slam's shockwave: a ring that grows from SHOCKWAVE_START of the ellipse to all of it in
## SHOCKWAVE_S (cubic ease out), thinning from SHOCKWAVE_WIDTH.x to .y px and fading from
## SHOCKWAVE_ALPHA; the inner half (`inner_share`) flashes for the first half of it. Its colour is
## SHOCKWAVE_COLOR with SHOCKWAVE_TINT_SHARE of the ground's.
const SHOCKWAVE_S := 0.34
const SHOCKWAVE_START := 0.3
const SHOCKWAVE_WIDTH := Vector2(7.0, 1.5)
const SHOCKWAVE_ALPHA := 0.85
const SHOCKWAVE_FLASH_ALPHA := 0.35
const SHOCKWAVE_COLOR := Color("#fff6dc")
const SHOCKWAVE_TINT_SHARE := 0.35
const SHOCKWAVE_POINTS := 40
## The crack decal: the boss crack's 4 frames (res://game/scenes/effects/boss-ground-crack.tscn)
## open in CRACK_OPEN_S, stay CRACK_HOLD_S and fade in CRACK_FADE_S.
const CRACK_TEXTURE_PATH := "res://asset/MAPS/effects/boss-ground-crack-4x1.webp"
const CRACK_FRAMES := 4
const CRACK_OPEN_S := 0.24
const CRACK_HOLD_S := 1.1
const CRACK_FADE_S := 0.7
## The Slam's debris: pebbles hop out (ground speed and take-off speed ranges, px/s, under
## PEBBLE_GRAVITY) and lie where they land; dust puffs drift out (slowed by DUST_DRAG) and swell;
## everything fades over the last DEBRIS_FADE_S of DEBRIS_LIFE_S. Pebbles are the ground's colour
## darkened, dust lightened.
const PEBBLE_SPEED := Vector2(60.0, 170.0)
const PEBBLE_LIFT := Vector2(90.0, 200.0)
const PEBBLE_GRAVITY := 900.0
const PEBBLE_SIZE := Vector2(1.6, 3.4)
const PEBBLE_DARKEN := 0.35
const PEBBLE_SHINE := 0.25
const DUST_SPEED := Vector2(60.0, 140.0)
const DUST_DRAG := 3.5
const DUST_SIZE := Vector2(6.0, 12.0)
const DUST_SWELL := 1.8
const DUST_ALPHA := 0.55
const DUST_LIGHTEN := 0.3
const DEBRIS_LIFE_S := 0.75
const DEBRIS_FADE_S := 0.3
## Where there is no ground tile: a dry soil colour.
const GROUND_FALLBACK := Color("#8a7656")
## Liftables near a slam rock this much (radians) at the centre, WOBBLE_FALLOFF less at the edge,
## dying away over WOBBLE_S (the Roll's bonk wobble, game/player/roll/player_roll.gd, is the model).
const WOBBLE_RAD := 0.14
const WOBBLE_FALLOFF := 0.6
const WOBBLE_S := 0.5
const WOBBLE_TURNS := 3.0
const WOBBLE_META := &"ability_fx_wobble"
const WOBBLE_REST_META := &"ability_fx_wobble_rest"

## The crack art, loaded on the first slam.
static var _crack_texture: Texture2D

var kind: int = KIND_CIRCLE
var radius: float = 10.0
var ellipse_size: Vector2 = Vector2(40.0, 16.0)
var color: Color = Color.WHITE
## The shockwave's inner flash, as a share of `ellipse_size`.
var inner_share: float = 0.5
## Goo dust: [{"velocity": Vector2, "life": float}] per particle.
var _dots: Array = []
var _dot_age: float = 0.0
var _dot_life: float = 0.32
## Shockwave progress 0..1; the crack's frame.
var _progress: float = 0.0
var _frame: int = 0
## Debris: pebbles {"direction", "speed", "lift", "size"} and puffs {"direction", "speed", "size"}.
var _pebbles: Array[Dictionary] = []
var _puffs: Array[Dictionary] = []


func _draw() -> void:
	match kind:
		KIND_CIRCLE:
			draw_circle(Vector2.ZERO, radius, color)
		KIND_ELLIPSE:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(ellipse_size.x / ellipse_size.y, 1.0))
			draw_circle(Vector2.ZERO, ellipse_size.y / 2.0, color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		KIND_DOTS:
			var t := clampf(_dot_age / _dot_life, 0.0, 1.0)
			var scale_now := lerpf(0.3, 0.0, t)
			var alpha := lerpf(0.6, 0.0, t)
			for dot: Dictionary in _dots:
				var at: Vector2 = dot["velocity"] * _dot_age
				draw_circle(at, 7.0 * scale_now, Color(Color("#1a3a24"), alpha))
				draw_circle(at, 5.0 * scale_now, Color(Color("#7be08a"), alpha))
				draw_circle(at, 2.0 * scale_now, Color(1, 1, 1, 0.85 * alpha))
		KIND_SHOCKWAVE:
			_draw_shockwave()
		KIND_DECAL:
			_draw_decal()
		KIND_DEBRIS:
			_draw_debris()


func _process(delta: float) -> void:
	if kind == KIND_DOTS or kind == KIND_DEBRIS:
		_dot_age += delta
		queue_redraw()


## `spawnFlash`: a circle r 10 at `at` that grows to r 60 and fades over 260 ms (Quad.Out).
static func flash(at: Vector2, tint: Color) -> Node2D:
	var node := _spawn(at, KIND_CIRCLE, Color(tint, 0.9))
	if node == null:
		return null
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(6.0, 6.0), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)
	return node


## The slam ring: r 10 #86f0c3 at 0.5 alpha growing to `ring_radius` and fading over 300 ms.
static func ring(at: Vector2, ring_radius: float) -> Node2D:
	var node := _spawn(at, KIND_CIRCLE, Color(Color("#86f0c3"), 0.5))
	if node == null:
		return null
	var grow := ring_radius / 10.0
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(grow, grow), 0.3)
	tween.parallel().tween_property(node, "modulate:a", 0.0, 0.3)
	tween.tween_callback(node.queue_free)
	return node


## The jump shadow: a 40 x 16 black ellipse at 0.35 alpha at `at`. The flight that owns it moves
## it along the ground under the slime, shrinks and fades it with height and frees it
## (jump_sequence.gd; Phaser's stayed at the start and tweened itself). The Slam's rise uses it too.
static func jump_shadow(at: Vector2) -> Node2D:
	return _spawn(at, KIND_ELLIPSE, Color(0, 0, 0, 0.35), false)


## The landing's 8 goo dots: speed 20-60 any direction, 320 ms, shrinking and fading.
static func goo_dust(at: Vector2) -> Node2D:
	var node := _spawn(at, KIND_DOTS, Color.WHITE)
	if node == null:
		return null
	for i in 8:
		var angle := randf() * TAU
		node._dots.append({"velocity": Vector2.from_angle(angle) * randf_range(20.0, 60.0)})
	var timer := node.create_tween()
	timer.tween_interval(0.4)
	timer.tween_callback(node.queue_free)
	return node


## The Slam's shockwave on the ground at `at`: a ring growing to the ground ellipse `size` (full
## axes), its inner `inner` share flashing, in `tint` (the ground's colour) mixed into
## SHOCKWAVE_COLOR.
static func shockwave(at: Vector2, size: Vector2, tint: Color, inner: float) -> Node2D:
	var node := _spawn(at, KIND_SHOCKWAVE, SHOCKWAVE_COLOR.lerp(tint, SHOCKWAVE_TINT_SHARE), false)
	if node == null:
		return null
	node.z_index = GROUND_Z
	node.ellipse_size = size
	node.inner_share = inner
	var tween := node.create_tween()
	tween.tween_method(node._set_progress, 0.0, 1.0, SHOCKWAVE_S)
	tween.tween_callback(node.queue_free)
	return node


## The crack decal at the feet `at`: the boss crack's frames opening over `size`, then fading.
## Null when the art is missing.
static func crack_decal(at: Vector2, size: Vector2) -> Node2D:
	if _crack() == null:
		return null
	var node := _spawn(at, KIND_DECAL, Color.WHITE, false)
	if node == null:
		return null
	node.z_index = GROUND_Z
	node.ellipse_size = size
	var tween := node.create_tween()
	tween.tween_method(node._set_frame, 0.0, float(CRACK_FRAMES) - 0.001, CRACK_OPEN_S)
	tween.tween_interval(CRACK_HOLD_S)
	tween.tween_property(node, "modulate:a", 0.0, CRACK_FADE_S)
	tween.tween_callback(node.queue_free)
	return node


## The Slam's debris at the feet `at`: `pebbles` pebbles and `puffs` dust puffs thrown out on the
## ground ellipse (`aspect` = its height / width), in the colours of `tint` (the ground's).
static func debris(at: Vector2, tint: Color, pebbles: int, puffs: int, aspect: float) -> Node2D:
	var node := _spawn(at, KIND_DEBRIS, tint)
	if node == null:
		return null
	for i in maxi(0, pebbles):
		node._pebbles.append({"direction": _ground_direction(aspect), "speed": randf_range(PEBBLE_SPEED.x, PEBBLE_SPEED.y),
			"lift": randf_range(PEBBLE_LIFT.x, PEBBLE_LIFT.y), "size": randf_range(PEBBLE_SIZE.x, PEBBLE_SIZE.y)})
	for i in maxi(0, puffs):
		node._puffs.append({"direction": _ground_direction(aspect), "speed": randf_range(DUST_SPEED.x, DUST_SPEED.y),
			"size": randf_range(DUST_SIZE.x, DUST_SIZE.y)})
	var timer := node.create_tween()
	timer.tween_interval(DEBRIS_LIFE_S)
	timer.tween_callback(node.queue_free)
	return node


## The colour of the ground under `at`: its tile's average colour (MapTerrain, the minimap's), or
## GROUND_FALLBACK without a ground tile there.
static func ground_tint(at: Vector2) -> Color:
	var world := Services.world()
	var ground: TileMapLayer = world.ground_layer if world != null else null
	if ground == null or not is_instance_valid(ground) or ground.tile_set == null:
		return GROUND_FALLBACK
	var cell := ground.local_to_map(ground.to_local(at))
	var source_id := ground.get_cell_source_id(cell)
	if source_id < 0 or not ground.tile_set.has_source(source_id):
		return GROUND_FALLBACK
	var source := ground.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return GROUND_FALLBACK
	var tile := MapTerrainColors.tile_color(source, ground.get_cell_atlas_coords(cell))
	return Color(tile, 1.0) if tile.a > 0.0 else GROUND_FALLBACK


## The Slam's wobble: every liftable (game/scripts/liftable.gd) whose ground point is within
## `wobble_radius` of `at` rocks its art from side to side, away from `at`, less the farther it is.
## Returns how many.
static func wobble_liftables(at: Vector2, wobble_radius: float) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or wobble_radius <= 0.0:
		return 0
	var count := 0
	for node: Node in tree.get_nodes_in_group(Liftable.GROUP):
		var root := node.get_parent() as Node2D
		if root == null or root.is_queued_for_deletion():
			continue
		var distance := root.global_position.distance_to(at)
		if distance > wobble_radius:
			continue
		var art := root.get_node_or_null(^"Visual") as Node2D
		if art == null:
			continue
		var side := -1.0 if root.global_position.x < at.x else 1.0
		wobble(art, side * WOBBLE_RAD * (1.0 - WOBBLE_FALLOFF * distance / wobble_radius))
		count += 1
	return count


## Rocks `art` by `amplitude` radians, dying away over WOBBLE_S; a new wobble replaces a running
## one from the same rest angle.
static func wobble(art: Node2D, amplitude: float) -> void:
	var rest := art.rotation
	var running: Variant = art.get_meta(WOBBLE_META) if art.has_meta(WOBBLE_META) else null
	if running is Tween:
		if (running as Tween).is_valid():
			(running as Tween).kill()
		rest = float(art.get_meta(WOBBLE_REST_META, rest))
	art.set_meta(WOBBLE_REST_META, rest)
	var tween := art.create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(art):
			art.rotation = rest + amplitude * (1.0 - t) * sin(t * TAU * WOBBLE_TURNS), 0.0, 1.0, WOBBLE_S)
	tween.tween_callback(func() -> void:
		if is_instance_valid(art):
			art.rotation = rest
			art.remove_meta(WOBBLE_META)
			art.remove_meta(WOBBLE_REST_META))
	art.set_meta(WOBBLE_META, tween)


static func _spawn(at: Vector2, node_kind: int, tint: Color, over: bool = true) -> Self:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return null
	var node := Self.new()
	node.name = "AbilityFx"
	node.kind = node_kind
	node.color = tint
	if over:
		node.z_index = OVER_Z
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(node)
	node.global_position = at
	return node


## A unit direction on the ground ellipse (`aspect` = its height / width), as a velocity's shape.
static func _ground_direction(aspect: float) -> Vector2:
	var angle := randf() * TAU
	return Vector2(cos(angle), sin(angle) * aspect)


static func _crack() -> Texture2D:
	if _crack_texture == null and ResourceLoader.exists(CRACK_TEXTURE_PATH):
		_crack_texture = load(CRACK_TEXTURE_PATH) as Texture2D
	return _crack_texture


func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()


func _set_frame(value: float) -> void:
	var frame := clampi(int(value), 0, CRACK_FRAMES - 1)
	if frame != _frame:
		_frame = frame
		queue_redraw()


func _draw_shockwave() -> void:
	var t := clampf(_progress, 0.0, 1.0)
	var grown := 1.0 - pow(1.0 - t, 3.0)
	var half := ellipse_size * 0.5
	if t < 0.5:
		draw_colored_polygon(_ellipse(half * inner_share), Color(color, SHOCKWAVE_FLASH_ALPHA * (1.0 - t * 2.0)))
	var ring_points := _ellipse(half * lerpf(SHOCKWAVE_START, 1.0, grown))
	ring_points.append(ring_points[0])
	draw_polyline(ring_points, Color(color, SHOCKWAVE_ALPHA * (1.0 - t)), lerpf(SHOCKWAVE_WIDTH.x, SHOCKWAVE_WIDTH.y, t), true)


func _draw_decal() -> void:
	var texture := _crack()
	if texture == null:
		return
	var frame_width := float(texture.get_width()) / float(CRACK_FRAMES)
	var source := Rect2(frame_width * float(_frame), 0.0, frame_width, float(texture.get_height()))
	draw_texture_rect_region(texture, Rect2(-ellipse_size * 0.5, ellipse_size), source)


func _draw_debris() -> void:
	var fade := clampf((DEBRIS_LIFE_S - _dot_age) / DEBRIS_FADE_S, 0.0, 1.0)
	var dust := Color(color.lightened(DUST_LIGHTEN), DUST_ALPHA * fade)
	var life_t := clampf(_dot_age / DEBRIS_LIFE_S, 0.0, 1.0)
	for puff: Dictionary in _puffs:
		var out := float(puff["speed"]) * (1.0 - exp(-DUST_DRAG * _dot_age)) / DUST_DRAG
		var at: Vector2 = (puff["direction"] as Vector2) * out
		draw_circle(at, float(puff["size"]) * lerpf(1.0, DUST_SWELL, life_t), Color(dust, dust.a * (1.0 - life_t)))
	var stone := Color(color.darkened(PEBBLE_DARKEN), fade)
	var shine := Color(color.lightened(PEBBLE_SHINE), fade)
	for pebble: Dictionary in _pebbles:
		var lift := float(pebble["lift"])
		var flight := 2.0 * lift / PEBBLE_GRAVITY
		var age := minf(_dot_age, flight)
		var height := maxf(0.0, lift * age - 0.5 * PEBBLE_GRAVITY * age * age)
		var at: Vector2 = (pebble["direction"] as Vector2) * float(pebble["speed"]) * age - Vector2(0.0, height)
		var size := float(pebble["size"])
		draw_circle(at, size, stone)
		draw_circle(at - Vector2(size, size) * 0.3, size * 0.4, shine)


## The points of an ellipse of half axes `half` around the origin.
static func _ellipse(half: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in SHOCKWAVE_POINTS:
		var angle := TAU * float(i) / float(SHOCKWAVE_POINTS)
		points.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
	return points

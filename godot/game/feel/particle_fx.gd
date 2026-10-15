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
## Body-shapes rework (combat-feel plan section 6 "Sparks", section 8 `feel/particle_fx.gd`;
## docs/godot/BODY_SHAPES.md "Juice"): `emit_burst` also takes an optional `direction` (the burst
## flies in a cone of +-"cone_deg" around it, DEFAULT_CONE_DEG when the preset has none), a `tint`
## (the particles' colour, which multiplies the texture; WHITE = the preset's own "color", default
## white) and a `count_scale` (the burst's particle count x it, at least 1). With the defaults a
## burst is exactly as before.
## The rework's presets, all with code-drawn textures:
##   finisher-spark: 14, 300, 160-380, 0-360, 0, 1.3->0, 1->0, additive, "fx-spark", cone 35
##   impact-ring:    1, 120, 0, -, 0, 0.21->1 (r6 to r28), 1->0, additive, "fx-ring" (r28)
##   mud-chunk:      8, 380-520, 70-190, 200-340, +560, 1->0.7, 1->0, "fx-chunk", cone 45
##   stone-chip:     8, 300-420, 100-240, 200-340, +640, 1->0.6, 1->0, "fx-chip", cone 40
##   silk-tuft:      6, 500-800, 20-70, 0-360, -24, 0.7->1.2, 0.9->0, "fx-tuft", cone 60
##   goo-splat:      10, 360-520, 80-230, 200-340, +420, 1->0.4, 1->0, "fx-splat-drop" tinted
##                   #7be08a, cone 50
## (all "over": the debris flies from the struck point, in front of the victim)
## And the rework's painted flipbooks (FLIPBOOKS; the body-shapes art of 2026-10-12): `emit_burst`
## with a flipbook's id plays one pooled Sprite2D through the sheet's frames instead of particles,
## sized by `count_scale` (the hit's weight), then its "with" particles:
##   goo-splat-sheet: 256x256-tile_4x1-goo-splat.webp, 4 frames of 50 ms, the last fading over
##                    110 ms; 46 px wide at count_scale 1 (a finisher's or a smash's debris), 31 px
##                    at 0.5 (a tap's), turned up to +-18 deg and mirrored at random; with goo-splat
##                    drops at 0.6 of the count scale (HitJuice: the goo material's debris)
## `set_picture_speed(speed)` (GameFeel, every frame: `GameFeel.picture_speed()`) runs every burst at
## that speed (CPUParticles2D `speed_scale`, the flipbooks' clock): in the rework mode a hit-stop
## holds the bursts with the frozen world and the room clear's stutter slows them; it stays 1 with the
## mode off, so the classic bursts keep moving through a hit-stop as before.
##
## Layers: "over" bursts stay under this node (z_index OVER_Z_INDEX, above every world object).
## "ground" bursts are moved under the y-sorted world entities root (holder at y + 2, emitter
## offset back up), so they sort with the creatures like Phaser's `resolveWorldDepth(y + 2)`.
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")

const PRESET_IDS: Array[StringName] = [&"hit-spark", &"slime-splash", &"dodge-dust", &"boss-burst", &"loot-sparkle", &"dust-puff"]
## The rework's presets: their pools are built on their first burst, so the classic game makes no
## extra emitters.
const REWORK_PRESET_IDS: Array[StringName] = [&"finisher-spark", &"impact-ring", &"mud-chunk", &"stone-chip",
	&"silk-tuft", &"goo-splat"]
## The cone half-angle (degrees) of a burst given a direction, for presets without "cone_deg"
## (combat-feel plan section 6: sparks in a +-30 degree cone along the hit).
const DEFAULT_CONE_DEG := 30.0

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
	# Body-shapes rework (combat-feel plan section 6): the finisher's sparks, its impact ring
	# (r6 to r28 in 120 ms) and the material debris. Presentation values, as above.
	&"finisher-spark": {"texture": "fx-spark", "count": 14, "layer": LAYER_OVER, "lifespan_ms": 300.0,
		"speed_min": 160.0, "speed_max": 380.0, "angle_min": 0.0, "angle_max": 360.0, "gravity_y": 0.0,
		"scale_start": 1.3, "scale_end": 0.0, "alpha_start": 1.0, "alpha_end": 0.0, "additive": true,
		"rotate_min": 0.0, "rotate_max": 0.0, "cone_deg": 35.0},
	&"impact-ring": {"texture": "fx-ring", "count": 1, "layer": LAYER_OVER, "lifespan_ms": 120.0,
		"speed_min": 0.0, "speed_max": 0.0, "angle_min": 0.0, "angle_max": 360.0, "gravity_y": 0.0,
		"scale_start": 6.0 / 28.0, "scale_end": 1.0, "alpha_start": 1.0, "alpha_end": 0.0, "additive": true,
		"rotate_min": 0.0, "rotate_max": 0.0},
	&"mud-chunk": {"texture": "fx-chunk", "count": 8, "layer": LAYER_OVER, "lifespan_ms": 520.0,
		"lifespan_min_ms": 380.0, "speed_min": 70.0, "speed_max": 190.0, "angle_min": 200.0, "angle_max": 340.0,
		"gravity_y": 560.0, "scale_start": 1.0, "scale_end": 0.7, "alpha_start": 1.0, "alpha_end": 0.0,
		"additive": false, "rotate_min": 0.0, "rotate_max": 360.0, "cone_deg": 45.0},
	&"stone-chip": {"texture": "fx-chip", "count": 8, "layer": LAYER_OVER, "lifespan_ms": 420.0,
		"lifespan_min_ms": 300.0, "speed_min": 100.0, "speed_max": 240.0, "angle_min": 200.0, "angle_max": 340.0,
		"gravity_y": 640.0, "scale_start": 1.0, "scale_end": 0.6, "alpha_start": 1.0, "alpha_end": 0.0,
		"additive": false, "rotate_min": 0.0, "rotate_max": 360.0, "cone_deg": 40.0},
	&"silk-tuft": {"texture": "fx-tuft", "count": 6, "layer": LAYER_OVER, "lifespan_ms": 800.0,
		"lifespan_min_ms": 500.0, "speed_min": 20.0, "speed_max": 70.0, "angle_min": 0.0, "angle_max": 360.0,
		"gravity_y": -24.0, "scale_start": 0.7, "scale_end": 1.2, "alpha_start": 0.9, "alpha_end": 0.0,
		"additive": false, "rotate_min": 0.0, "rotate_max": 360.0, "cone_deg": 60.0},
	&"goo-splat": {"texture": "fx-splat-drop", "count": 10, "layer": LAYER_OVER, "lifespan_ms": 520.0,
		"lifespan_min_ms": 360.0, "speed_min": 80.0, "speed_max": 230.0, "angle_min": 200.0, "angle_max": 340.0,
		"gravity_y": 420.0, "scale_start": 1.0, "scale_end": 0.4, "alpha_start": 1.0, "alpha_end": 0.0,
		"additive": false, "rotate_min": 0.0, "rotate_max": 0.0, "cone_deg": 50.0, "color": Color("#7be08a")},
}

## The rework's painted flipbooks (see the header): "texture" (a sheet of "frames" side by side),
## "frame_ms" per frame, "fade_ms" (the last frame fades out over it), "size_px" (a frame's width on
## screen at count_scale 1; "size_floor" of it at count_scale 0, linear between and beyond, at most
## "size_max_scale" x), "turn_deg" (a random turn either way) and "with" (a particle preset burst with
## it, at "with_share" of the count scale). Presentation values, as above.
const GOO_SPLAT_SHEET := preload("res://asset/MAPS/effects/256x256-tile_4x1-goo-splat.webp")
const FLIPBOOKS := {
	&"goo-splat-sheet": {"texture": GOO_SPLAT_SHEET, "frames": 4, "frame_ms": 50.0, "fade_ms": 110.0,
		"size_px": 46.0, "size_floor": 0.35, "size_max_scale": 1.6, "turn_deg": 18.0, "with": &"goo-splat",
		"with_share": 0.6},
}
## The flipbooks draw with mipmaps where the import makes them (linear otherwise): clean at their
## small size on screen.
const FLIPBOOK_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## texture name -> ImageTexture
var _textures: Dictionary = {}
## preset -> Array of holder Node2D (each holds one CPUParticles2D child "Emitter")
var _pools: Dictionary = {}
## preset -> next pool index
var _cursor: Dictionary = {}
## The speed every burst runs at (`set_picture_speed`; 1 = real time).
var _picture_speed: float = 1.0
## Flipbook preset -> Array of Sprite2D (round robin, EMITTERS_PER_PRESET, made on first use) and the
## next index; the ones playing: {"sprite", "preset", "age_ms", "alpha"}.
var _flipbook_pools: Dictionary = {}
var _flipbook_cursor: Dictionary = {}
var _playing: Array[Dictionary] = []


## Draws the procedural textures into ImageTextures and builds the emitter pool.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = OVER_Z_INDEX
	# Only a playing flipbook needs the frame step.
	set_process(false)
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
		_build_pool(preset)


## Emits one burst of `preset` at `world_position`; unknown presets are ignored. Rework options
## (see the header): `direction` (unit; ZERO = the preset's own angles), `tint` (WHITE = the
## preset's colour) and `count_scale` (x the preset's count, at least one particle; a flipbook's
## size).
func emit_burst(preset: StringName, world_position: Vector2, direction: Vector2 = Vector2.ZERO,
		tint: Color = Color.WHITE, count_scale: float = 1.0) -> void:
	if FLIPBOOKS.has(preset):
		_emit_flipbook(preset, world_position, direction, tint, count_scale)
		return
	if not PRESETS.has(preset):
		return
	if not _pools.has(preset):
		if not REWORK_PRESET_IDS.has(preset):
			return
		_build_pool(preset)
	var config: Dictionary = PRESETS[preset]
	var pool: Array = _pools[preset]
	var index: int = _cursor[preset]
	_cursor[preset] = (index + 1) % pool.size()
	var holder: Node2D = pool[index] if is_instance_valid(pool[index]) else null
	if holder == null or holder.is_queued_for_deletion():
		holder = _make_holder(preset, index)
		pool[index] = holder
	var emitter := holder.get_node(^"Emitter") as CPUParticles2D
	_shape_burst(emitter, config, direction, tint, count_scale)
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


## Runs every burst, the flying ones and the next ones, at `speed` (0..1, the CPUParticles2D
## `speed_scale`; GameFeel passes `picture_speed()`). A burst restarted at a speed above 0 still
## spawns at once; at 0 it would wait for the speed to come back.
func set_picture_speed(speed: float) -> void:
	var value := clampf(speed, 0.0, 1.0) if is_finite(speed) else 1.0
	if is_equal_approx(value, _picture_speed):
		return
	_picture_speed = value
	for preset: StringName in _pools:
		for holder: Variant in _pools[preset]:
			if not is_instance_valid(holder):
				continue
			var emitter := (holder as Node).get_node_or_null(^"Emitter") as CPUParticles2D
			if emitter != null:
				emitter.speed_scale = value


## The particle count of one burst of `preset` (its "count"; 0 for an unknown preset). The rework's
## feel scales a burst to a step's "sparks" with `count_scale = sparks / preset_count`.
static func preset_count(preset: StringName) -> int:
	if not PRESETS.has(preset):
		return 0
	return int((PRESETS[preset] as Dictionary)["count"])


## Steps the playing flipbooks at the picture speed (`set_picture_speed`: a hit-stop holds them with
## the bursts): each shows its frames in turn and fades on its last; stops once none plays.
func _process(delta: float) -> void:
	var step_ms := delta * 1000.0 * _picture_speed
	var still: Array[Dictionary] = []
	for entry: Dictionary in _playing:
		var node: Variant = entry.get("sprite")
		if not is_instance_valid(node):
			continue
		var sprite := node as Sprite2D
		var config: Dictionary = FLIPBOOKS[entry["preset"]]
		var frames := maxi(1, int(config["frames"]))
		var frame_ms := maxf(1.0, float(config["frame_ms"]))
		var last_from := frame_ms * float(frames - 1)
		var fade_ms := maxf(1.0, float(config["fade_ms"]))
		var age := float(entry["age_ms"]) + step_ms
		if age >= last_from + fade_ms:
			sprite.visible = false
			continue
		sprite.frame = clampi(int(age / frame_ms), 0, frames - 1)
		sprite.modulate.a = float(entry["alpha"]) * (1.0 - clampf((age - last_from) / fade_ms, 0.0, 1.0))
		entry["age_ms"] = age
		still.append(entry)
	_playing = still
	if _playing.is_empty():
		set_process(false)


# --- private ---------------------------------------------------------------------------------

## One painted flipbook of `preset` (FLIPBOOKS) at `world_position`: its pooled sprite restarted on
## the first frame, sized by `count_scale` (the hit's weight: a tap's debris 0.5, a finisher's 1),
## turned a little and mirrored at random, `tint` over it; then its "with" particles along
## `direction`.
func _emit_flipbook(preset: StringName, world_position: Vector2, direction: Vector2, tint: Color,
		count_scale: float) -> void:
	var config: Dictionary = FLIPBOOKS[preset]
	if not _flipbook_pools.has(preset):
		var empty: Array = []
		empty.resize(EMITTERS_PER_PRESET)
		_flipbook_pools[preset] = empty
		_flipbook_cursor[preset] = 0
	var pool: Array = _flipbook_pools[preset]
	var index: int = _flipbook_cursor[preset]
	_flipbook_cursor[preset] = (index + 1) % pool.size()
	var sprite: Sprite2D = pool[index] if is_instance_valid(pool[index]) else null
	if sprite == null or sprite.is_queued_for_deletion():
		sprite = _make_flipbook_sprite(preset, index, config)
		pool[index] = sprite
	var weight := count_scale if is_finite(count_scale) and count_scale > 0.0 else 1.0
	var share := minf(float(config["size_max_scale"]), lerpf(float(config["size_floor"]), 1.0, weight))
	var frame_px := float(sprite.texture.get_width()) / float(maxi(1, sprite.hframes))
	var turn := deg_to_rad(float(config["turn_deg"]))
	sprite.scale = Vector2.ONE * float(config["size_px"]) * share / maxf(1.0, frame_px)
	sprite.rotation = randf_range(-turn, turn)
	sprite.flip_h = randf() < 0.5
	sprite.frame = 0
	sprite.modulate = tint
	sprite.visible = true
	sprite.global_position = world_position
	# A restarted sprite plays from its first frame again (a freed one is dropped).
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _playing:
		var other: Variant = entry.get("sprite")
		if is_instance_valid(other) and other != sprite:
			kept.append(entry)
	kept.append({"sprite": sprite, "preset": preset, "age_ms": 0.0, "alpha": tint.a})
	_playing = kept
	set_process(true)
	var companion := StringName(str(config.get("with", "")))
	if not companion.is_empty():
		emit_burst(companion, world_position, direction, tint, weight * float(config.get("with_share", 1.0)))


## A hidden flipbook sprite of `preset` (its sheet, its frames side by side), added under self (the
## "over" layer).
func _make_flipbook_sprite(preset: StringName, index: int, config: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "%s_%d" % [String(preset).replace("-", "_"), index]
	sprite.texture = config["texture"]
	sprite.hframes = maxi(1, int(config["frames"]))
	sprite.centered = true
	sprite.visible = false
	sprite.texture_filter = FLIPBOOK_FILTER
	sprite.process_mode = Node.PROCESS_MODE_ALWAYS
	sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(sprite)
	return sprite


## Builds the round-robin pool of `preset`.
func _build_pool(preset: StringName) -> void:
	var pool: Array = []
	for i in EMITTERS_PER_PRESET:
		pool.append(_make_holder(preset, i))
	_pools[preset] = pool
	_cursor[preset] = 0


## Sets the rework options on a pooled emitter before its burst: the cone around `direction` (else
## the preset's own angles), the colour (`tint`, else the preset's "color") and the count. Every
## value goes back to the preset's when the option is left at its default, so a reused emitter
## never keeps an earlier burst's options.
func _shape_burst(emitter: CPUParticles2D, config: Dictionary, direction: Vector2, tint: Color,
		count_scale: float) -> void:
	if direction != Vector2.ZERO and direction.is_finite():
		emitter.direction = direction.normalized()
		emitter.spread = float(config.get("cone_deg", DEFAULT_CONE_DEG))
	else:
		var angle_min := float(config["angle_min"])
		var angle_max := float(config["angle_max"])
		emitter.direction = Vector2.from_angle(deg_to_rad((angle_min + angle_max) / 2.0))
		emitter.spread = minf(180.0, (angle_max - angle_min) / 2.0)
	var base_color: Color = config.get("color", Color.WHITE)
	emitter.color = base_color if tint == Color.WHITE else tint
	var count := int(config["count"])
	if count_scale > 0.0 and is_finite(count_scale) and not is_equal_approx(count_scale, 1.0):
		count = maxi(1, roundi(float(count) * count_scale))
	if emitter.amount != count:
		emitter.amount = count


## The texture called `texture_name`: the old ones are drawn in `_ready`, the rework's on first use.
func _texture_for(texture_name: String) -> Texture2D:
	if not _textures.has(texture_name):
		var made := _make_rework_texture(texture_name)
		if made == null:
			return null
		_textures[texture_name] = made
	return _textures[texture_name]


## The rework presets' code-drawn textures (combat-feel plan section 6: sparks, the impact ring and
## the material debris); null for another name.
static func _make_rework_texture(texture_name: String) -> ImageTexture:
	match texture_name:
		"fx-ring":
			return _make_ring_texture(64, 28.0, 3.0)
		"fx-chunk":
			return _make_texture(12, 12, [
				[6.0, 7.0, 5.0, Color("#5e3f22")],
				[5.5, 6.0, 4.0, Color("#8a6239")],
				[8.0, 5.5, 2.5, Color("#8a6239")],
				[4.5, 4.5, 1.6, Color("#b08455")],
			])
		"fx-chip":
			return _make_polygon_texture(10, [
				[PackedVector2Array([Vector2(1, 6), Vector2(4, 1), Vector2(9, 3), Vector2(8, 8), Vector2(3, 9)]), Color("#6f737b")],
				[PackedVector2Array([Vector2(2, 6), Vector2(4, 2), Vector2(8, 4), Vector2(6, 7)]), Color("#a9adb5")],
				[PackedVector2Array([Vector2(4, 3), Vector2(6, 3), Vector2(5, 5)]), Color("#e1e4e9")],
			])
		"fx-tuft":
			return _make_texture(16, 16, [
				[8.0, 8.0, 7.0, Color(1, 1, 1, 0.25)],
				[7.0, 8.0, 5.0, Color(1, 1, 1, 0.45)],
				[9.5, 7.0, 3.5, Color(1, 1, 1, 0.55)],
				[7.5, 7.5, 2.5, Color(1, 1, 1, 0.9)],
			])
		"fx-splat-drop":
			return _make_texture(16, 16, [
				[8.0, 9.0, 6.0, Color("#8c8c8c")],
				[8.0, 8.0, 5.0, Color("#ececec")],
				[6.0, 6.0, 1.6, Color(1, 1, 1, 0.9)],
			])
	return null


## A white ring of `radius` px and `thickness` px, centred in a `size` x `size` texture, with a
## one-pixel soft edge.
static func _make_ring_texture(size: int, radius: float, thickness: float) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2(float(size), float(size)) / 2.0
	for y in size:
		for x in size:
			var distance := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre)
			var edge := absf(distance - radius) - thickness / 2.0
			var alpha := clampf(1.0 - edge, 0.0, 1.0)
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)


## Filled polygons ([PackedVector2Array, Color], drawn in order) in a `size` x `size` texture; a
## pixel is covered when its centre is inside the polygon.
static func _make_polygon_texture(size: int, polygons: Array) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var centre := Vector2(float(x) + 0.5, float(y) + 0.5)
			for entry: Array in polygons:
				var polygon: PackedVector2Array = entry[0]
				var color: Color = entry[1]
				if Geometry2D.is_point_in_polygon(centre, polygon):
					image.set_pixel(x, y, _blend_over(image.get_pixel(x, y), color))
	return ImageTexture.create_from_image(image)


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
	emitter.speed_scale = _picture_speed
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
	emitter.texture = _texture_for(str(config["texture"]))
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
		# A growing particle (the impact ring, silk tufts) needs room above 1: Curve clamps its points
		# to [min_value, max_value]. The old presets only shrink, so their range stays 0-1.
		curve.max_value = maxf(1.0, scale_end / scale_start)
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

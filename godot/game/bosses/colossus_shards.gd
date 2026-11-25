extends Node2D
## A plate of the Crystal Colossus bursting (the plate fight: docs/godot/DUNGEONS.md "The Crystal
## Colossus (roadmap 12.4)"): a flash where the plate was, a puff of crystal dust and glints, and the
## eight shards of `shards.webp` (hot ones for a brittle plate, cold ones else) flying out from it,
## mostly the way the blow pushes, falling to the floor round him, bouncing once, lying a moment and
## fading. Presentation only: nothing collides. Stepped by the frame (`_process`), so it stops with the
## tree (a pause, a hit-stop), as the mechanisms' debris (game/dungeon/mechanism_debris.gd).
##
## `burst(parent, at, floor_y, hot, way, seed)` makes one under `parent` (a y-sorted node).
##
## Owner: dungeons (the Crystal Mine).

const ColossusLook := preload("res://game/bosses/colossus_look.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

## The shards' size against their art (the plate is about a cell across; each shard a third of it).
const SHARD_SCALE := 0.3
## How they fly: speed along the floor (units/s), how high they rise over their start, how long the
## first flight lasts (ms), how wide round `way` they spread (radians), how far they turn.
const SPEED_MIN := 90.0
const SPEED_MAX := 230.0
const RISE_MIN := 18.0
const RISE_MAX := 46.0
const AIR_MS := 560.0
const SPREAD := 2.4
const TURN := 8.0
## The bounce: this share of the first flight's height, length and time.
const BOUNCE_SHARE := 0.3
const LIE_MS := 1100.0
const FADE_MS := 600.0
## The dust and glints: their size from start to end (of the art), how long they last.
const DUST_FROM := 0.16
const DUST_TO := 0.46
const DUST_MS := 520.0
## The flash: its size (of the glow texture), its colours, how long.
const FLASH_FROM := 0.5
const FLASH_TO := 2.6
const FLASH_MS := 260.0
const FLASH_HOT := Color(1.0, 0.62, 0.22, 0.95)
const FLASH_COLD := Color(0.75, 0.92, 1.0, 0.9)
const SHADOW_COLOR := Color(0.05, 0.04, 0.03, 0.3)

var _pieces: Array[Dictionary] = []
var _dust: Sprite2D
var _flash: Sprite2D
var _age_ms := 0.0
var _end_ms := 0.0


## One burst at `at` (global, the plate's middle), its shards landing on the floor at `floor_y`
## (his feet's y) round it; `way` the way the blow pushes (ZERO: every way).
static func burst(parent: Node, at: Vector2, floor_y: float, hot: bool, way: Vector2, seed: int) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var made: Node2D = load("res://game/bosses/colossus_shards.gd").new()
	made.name = "ColossusShards"
	made.y_sort_enabled = true
	parent.add_child(made)
	made.global_position = Vector2.ZERO
	made.call(&"_start", at, floor_y, hot, way, seed)
	return made


func _start(at: Vector2, floor_y: float, hot: bool, way: Vector2, seed: int) -> void:
	var shards: Variant = ColossusLook.manifest().get("shards", {})
	var rects: Array = (shards as Dictionary).get("hot" if hot else "cold", []) if shards is Dictionary else []
	var atlas := ColossusLook.picture(str(ColossusLook.manifest().get("shards_file", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lift := maxf(0.0, floor_y - at.y)
	var ground := Vector2(at.x, floor_y)
	for i in rects.size():
		var rect: Array = rects[i]
		var heading := way.rotated(rng.randf_range(-SPREAD, SPREAD) * 0.5) if way != Vector2.ZERO \
			else Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var holder := Node2D.new()
		var start := ground + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-6.0, 6.0))
		holder.position = start
		add_child(holder)
		var shadow := Node2D.new()
		shadow.z_index = -1
		holder.add_child(shadow)
		shadow.draw.connect(_draw_shadow.bind(shadow))
		var sprite := Sprite2D.new()
		sprite.texture = atlas
		sprite.region_enabled = true
		sprite.region_rect = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		sprite.scale = Vector2.ONE * SHARD_SCALE
		holder.add_child(sprite)
		_pieces.append({"holder": holder, "sprite": sprite, "shadow": shadow, "start": start, "way": heading,
			"speed": rng.randf_range(SPEED_MIN, SPEED_MAX), "rise": rng.randf_range(RISE_MIN, RISE_MAX),
			"lift": lift + rng.randf_range(-10.0, 10.0), "turn": rng.randf_range(-TURN, TURN),
			"turn0": rng.randf_range(0.0, TAU), "air_ms": AIR_MS * rng.randf_range(0.85, 1.15)})
	# the dust and glints, and the flash, where the plate was (above the bodies round it)
	var dust_rect: Variant = (shards as Dictionary).get("dust") if shards is Dictionary else null
	if dust_rect is Array and atlas != null:
		_dust = Sprite2D.new()
		_dust.texture = atlas
		_dust.region_enabled = true
		_dust.region_rect = Rect2(float(dust_rect[0]), float(dust_rect[1]), float(dust_rect[2]), float(dust_rect[3]))
		_dust.z_index = 4
		_dust.position = at
		add_child(_dust)
	_flash = Sprite2D.new()
	_flash.texture = FireFx.glow_texture()
	_flash.material = FireFx.additive()
	_flash.modulate = FLASH_HOT if hot else FLASH_COLD
	_flash.z_index = 5
	_flash.position = at
	add_child(_flash)
	_end_ms = AIR_MS * 1.15 * (1.0 + BOUNCE_SHARE) + LIE_MS + FADE_MS
	_step()


func _process(delta: float) -> void:
	_age_ms += delta * 1000.0
	_step()
	if _age_ms >= _end_ms:
		queue_free()


func _step() -> void:
	if _flash != null:
		var t := clampf(_age_ms / FLASH_MS, 0.0, 1.0)
		_flash.scale = Vector2.ONE * lerpf(FLASH_FROM, FLASH_TO, sqrt(t))
		_flash.self_modulate.a = 1.0 - t
		_flash.visible = t < 1.0
	if _dust != null:
		var t := clampf(_age_ms / DUST_MS, 0.0, 1.0)
		_dust.scale = Vector2.ONE * lerpf(DUST_FROM, DUST_TO, sqrt(t))
		_dust.self_modulate.a = 1.0 - t * t
		_dust.visible = t < 1.0
	for piece: Dictionary in _pieces:
		var holder: Node2D = piece["holder"]
		var sprite: Sprite2D = piece["sprite"]
		var first := float(piece["air_ms"])
		var second := first * BOUNCE_SHARE
		var speed := float(piece["speed"])
		var height := 0.0
		var travelled := 0.0
		var turning := 0.0
		if _age_ms < first:
			var t := _age_ms / first
			# from the plate's height up over the top and down to the floor
			height = float(piece["lift"]) * (1.0 - t) + float(piece["rise"]) * 4.0 * t * (1.0 - t)
			travelled = speed * _age_ms / 1000.0
			turning = _age_ms / 1000.0
		elif _age_ms < first + second:
			var t := (_age_ms - first) / second
			height = float(piece["rise"]) * BOUNCE_SHARE * 4.0 * t * (1.0 - t)
			travelled = speed * first / 1000.0 + speed * BOUNCE_SHARE * (_age_ms - first) / 1000.0
			turning = first / 1000.0 + (_age_ms - first) / 2000.0
		else:
			travelled = speed * first / 1000.0 + speed * BOUNCE_SHARE * second / 1000.0
			turning = first / 1000.0 + second / 2000.0
		holder.position = (piece["start"] as Vector2) + (piece["way"] as Vector2) * travelled
		sprite.position = Vector2(0.0, -height - 3.0)
		sprite.rotation = float(piece["turn0"]) + float(piece["turn"]) * turning
		var lying := _age_ms - first - second
		holder.modulate.a = 1.0 if lying < LIE_MS else clampf(1.0 - (lying - LIE_MS) / FADE_MS, 0.0, 1.0)
		(piece["shadow"] as Node2D).scale = Vector2.ONE * clampf(1.0 - height / 160.0, 0.4, 1.0)


func _draw_shadow(shadow: Node2D) -> void:
	shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	shadow.draw_circle(Vector2.ZERO, 7.0, SHADOW_COLOR)
	shadow.draw_set_transform(Vector2.ZERO)

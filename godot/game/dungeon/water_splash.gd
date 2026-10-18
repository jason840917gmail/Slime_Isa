extends Node2D
## A splash on deep water (docs/godot/DUNGEONS.md "Falling planks over water"): drops thrown up
## and falling back, and `rings` rings that swell out of the spot and fade over `life_ms` (real time:
## presentation). The slime falling in (hazard_watch.gd, kind "water") and a falling plank
## (falling_plank.gd) make one with `spawn`, on the world's entity layer, drawn on the water under
## the bodies.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")

const Z := -1
const RING := Color(0.86, 0.95, 1.0, 0.85)
const FOAM := Color(1.0, 1.0, 1.0, 0.9)
const RING_WIDTH := 2.5
## A ring is this much flatter than wide (the water seen from the game's three-quarter view).
const RING_SQUASH := 0.5
const DROPS := 9
const DROP_RISE_PX := 26.0
const DROP_SPREAD_PX := 22.0
const DROP_SHARE := 0.45

var radius: float = 40.0
var life_ms: float = 900.0
var rings: int = 3
var _born_ms := 0.0
var _seed := 0


## A splash at `at` (global): rings out to `radius_px` over `ms`. Null without a world.
static func spawn(at: Vector2, radius_px: float, ms: float, ring_count: int) -> Node2D:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null:
		return null
	var splash: Node2D = (load("res://game/dungeon/water_splash.gd") as GDScript).new()
	splash.set(&"radius", radius_px)
	splash.set(&"life_ms", maxf(1.0, ms))
	splash.set(&"rings", maxi(1, ring_count))
	splash.position = parent.to_local(at)
	parent.add_child(splash)
	return splash


func _ready() -> void:
	z_as_relative = false
	z_index = Z
	_born_ms = Time.get_ticks_msec()
	_seed = int(global_position.x * 7.0 + global_position.y * 13.0)


func _process(_delta: float) -> void:
	if (Time.get_ticks_msec() - _born_ms) >= life_ms:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf((Time.get_ticks_msec() - _born_ms) / life_ms, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, RING_SQUASH))
	for i in rings:
		# Each ring starts a little after the one before it.
		var start := float(i) / float(rings) * 0.45
		var local := clampf((t - start) / (1.0 - start), 0.0, 1.0)
		if local <= 0.0:
			continue
		var eased := 1.0 - pow(1.0 - local, 2.0)
		draw_arc(Vector2.ZERO, maxf(2.0, radius * eased), 0.0, TAU, 40, Color(RING, RING.a * (1.0 - local)), RING_WIDTH, true)
	draw_set_transform(Vector2.ZERO)
	var drop_t := t / DROP_SHARE
	if drop_t >= 1.0:
		return
	var random := RandomNumberGenerator.new()
	random.seed = _seed
	for i in DROPS:
		var angle := random.randf_range(-PI, 0.0)
		var spread := random.randf_range(0.4, 1.0) * DROP_SPREAD_PX
		var rise := random.randf_range(0.6, 1.0) * DROP_RISE_PX
		var at := Vector2(cos(angle) * spread * drop_t, -sin(drop_t * PI) * rise + sin(angle) * spread * 0.3 * drop_t)
		draw_circle(at, lerpf(3.0, 1.5, drop_t), Color(FOAM, FOAM.a * (1.0 - drop_t)))

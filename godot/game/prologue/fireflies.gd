extends Node2D
## Fireflies going home at dawn (docs/design/2026-10-16-prologue.md, the Wellspring; the level-design
## guide: "the fireflies drift toward the exit: breadcrumbs"): `count` little lights that wander
## inside `extent` around this node and blink, and drift away along `drift_toward` (an offset from
## this node: the way out) when the slime comes within `flee_radius` of one; one that drifts past
## `extent` fades and comes back at its start. Drawn added to the world (additive), on real time.
## Presentation only.
##
## Owner: prologue.

const Services := preload("res://game/shared/services.gd")
const SoftGlow := preload("res://game/prologue/soft_glow.gd")

@export var count: int = 6
## Half the size of the box they wander in (px, around this node).
@export var extent: Vector2 = Vector2(260, 160)
## Where they drift when the slime comes near (px from this node).
@export var drift_toward: Vector2 = Vector2(400, 0)
@export var flee_radius: float = 110.0
@export var wander_speed: float = 18.0
@export var flee_speed: float = 70.0
@export var color: Color = Color(0.85, 1.0, 0.45, 1.0)
@export var glow_radius: float = 14.0
@export var seed_value: int = 7

var _flies: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 4
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend
	_rng.seed = seed_value
	for i in count:
		var start := Vector2(_rng.randf_range(-extent.x, extent.x), _rng.randf_range(-extent.y, extent.y))
		_flies.append({"home": start, "pos": start, "vel": Vector2.ZERO, "phase": _rng.randf() * TAU,
			"fleeing": false, "alpha": 1.0})


func _process(delta: float) -> void:
	var slime: Variant = _slime_position()
	for fly: Dictionary in _flies:
		fly["phase"] = float(fly["phase"]) + delta * _rng.randf_range(1.5, 3.0)
		var pos: Vector2 = fly["pos"]
		var wander := Vector2(sin(float(fly["phase"]) * 0.7), cos(float(fly["phase"]) * 0.9)) * wander_speed
		var vel: Vector2 = fly["vel"]
		if slime is Vector2 and (to_global(pos) as Vector2).distance_to(slime) < flee_radius:
			fly["fleeing"] = true
		if bool(fly["fleeing"]):
			var toward := (drift_toward - pos).normalized() * flee_speed
			vel = vel.lerp(toward + wander * 0.5, minf(1.0, delta * 2.0))
			if pos.distance_to(drift_toward) < 40.0 or absf(pos.x) > extent.x * 2.5 or absf(pos.y) > extent.y * 2.5:
				fly["alpha"] = maxf(0.0, float(fly["alpha"]) - delta)
				if float(fly["alpha"]) <= 0.0:
					fly["pos"] = fly["home"]
					fly["fleeing"] = false
					fly["alpha"] = 1.0
					fly["vel"] = Vector2.ZERO
					continue
		else:
			var back := ((fly["home"] as Vector2) - pos) * 0.4
			vel = vel.lerp(wander + back, minf(1.0, delta * 1.5))
		fly["vel"] = vel
		fly["pos"] = pos + vel * delta
	queue_redraw()


func _draw() -> void:
	var texture := SoftGlow.glow_texture()
	for fly: Dictionary in _flies:
		var blink := 0.55 + 0.45 * sin(float(fly["phase"]) * 2.3)
		var tint := color
		tint.a = blink * float(fly["alpha"])
		var pos: Vector2 = fly["pos"]
		draw_texture_rect(texture, Rect2(pos - Vector2.ONE * glow_radius, Vector2.ONE * glow_radius * 2.0), false, tint * Color(1, 1, 1, 0.6))
		draw_circle(pos, 1.8, tint)


func _slime_position() -> Variant:
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return null
	return (player as Node).call(&"get_centre")

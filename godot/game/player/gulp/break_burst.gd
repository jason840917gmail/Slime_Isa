extends Node2D
## A thrown thing breaking (owner, 2026-10-09): its own picture cut into PIECES x PIECES chunks that
## fly out, tumble, drop to the ground, skip once and fade, so a pot bursts into pot shards and a
## pumpkin into pumpkin bits. Presentation only (real-time `_process`); a child of the entities root
## at the break point, freed when the last chunk has faded (game/player/gulp/thrown_object.gd).
##
## The new throw feel (game/throw/throw_feel.gd; owner, 2026-11-16) passes `options` to `burst`, the
## numbers of `gulp.throwFeel.shards.<hit|miss|wall>`: "pieces" (the cut, per side), "forwardMin" /
## "forwardMax" (each chunk's speed along "direction", the throw: the shards fly ON past the blow),
## "spreadMin" / "spreadMax" (its speed out from the picture's middle), "liftMin" / "liftMax" (up),
## "spin", "gravity", "bounce", "friction", "lifeMs", "fadeFromMs", and from the caller "direction"
## (a unit Vector2) and "floorDrop" (how far under the break the ground is, px). A key left out
## keeps the number below, and no options at all is the burst as it always was. The chunks wait
## through a hit-stop with the world (the node pauses with the tree), so during the freeze the thing
## still shows whole at the blow, and bursts when it ends.
##
## Owner: abilities.

const PIECES := 3
const LIFE_S := 0.7
const FADE_FROM_S := 0.45
const GRAVITY := 620.0
const SPEED_MIN := 50.0
const SPEED_MAX := 160.0
const LIFT_MIN := 90.0
const LIFT_MAX := 190.0
const SPIN_MAX := 9.0
## Chunks land this far below the break point (world px), give or take FLOOR_SPREAD.
const FLOOR_DROP := 16.0
const FLOOR_SPREAD := 8.0
const BOUNCE := 0.35
const FRICTION := 0.55

## [{"node": Sprite2D, "velocity": Vector2, "spin": float, "floor": float}].
var _chunks: Array[Dictionary] = []
var _age: float = 0.0
## This burst's numbers (the constants above unless `options` gave others).
var _life_s: float = LIFE_S
var _fade_from_s: float = FADE_FROM_S
var _gravity: float = GRAVITY
var _bounce: float = BOUNCE
var _friction: float = FRICTION


## Bursts `look` (a Sprite2D showing one frame of a sheet, as held_look.gd makes them) at `at`
## under `parent`. Nothing happens for a look without a texture. `options`: see the header.
static func burst(parent: Node, at: Vector2, look: Sprite2D, options: Dictionary = {}) -> void:
	if parent == null or look == null or look.texture == null:
		return
	var node := new()
	node.name = "BreakBurst"
	node.z_index = 5
	if not options.is_empty():
		# The chunks move every drawn frame: unsmoothed, they leave the blow the frame the freeze ends.
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(node)
	node.global_position = at
	node._cut(look, options)


func _cut(look: Sprite2D, options: Dictionary) -> void:
	var pieces := maxi(1, int(_option(options, "pieces", PIECES)))
	var forward_min := _option(options, "forwardMin", 0.0)
	var forward_max := _option(options, "forwardMax", 0.0)
	var spread_min := _option(options, "spreadMin", SPEED_MIN)
	var spread_max := _option(options, "spreadMax", SPEED_MAX)
	var lift_min := _option(options, "liftMin", LIFT_MIN)
	var lift_max := _option(options, "liftMax", LIFT_MAX)
	var spin := _option(options, "spin", SPIN_MAX)
	var floor_drop := _option(options, "floorDrop", FLOOR_DROP)
	_life_s = _option(options, "lifeMs", LIFE_S * 1000.0) / 1000.0
	_fade_from_s = minf(_life_s, _option(options, "fadeFromMs", FADE_FROM_S * 1000.0) / 1000.0)
	_gravity = _option(options, "gravity", GRAVITY)
	_bounce = _option(options, "bounce", BOUNCE)
	_friction = _option(options, "friction", FRICTION)
	var along_value: Variant = options.get("direction", Vector2.ZERO)
	var along: Vector2 = along_value if along_value is Vector2 else Vector2.ZERO
	var texture := look.texture
	var frames := Vector2(maxi(1, look.hframes), maxi(1, look.vframes))
	var cell := texture.get_size() / frames
	var origin := Vector2(look.frame % maxi(1, look.hframes), look.frame / maxi(1, look.hframes)) * cell
	var piece := cell / float(pieces)
	for column in pieces:
		for row in pieces:
			var chunk := Sprite2D.new()
			chunk.texture = texture
			chunk.region_enabled = true
			chunk.region_rect = Rect2(origin + piece * Vector2(column, row), piece)
			chunk.scale = look.scale.abs()
			var offset := (piece * (Vector2(column, row) + Vector2(0.5, 0.5)) - cell * 0.5) * look.scale.abs()
			chunk.position = offset
			add_child(chunk)
			var outward := offset.normalized() if offset.length() > 0.1 else Vector2.RIGHT.rotated(randf() * TAU)
			var velocity := outward * randf_range(spread_min, spread_max) + along * randf_range(forward_min, forward_max) \
				- Vector2(0.0, randf_range(lift_min, lift_max))
			_chunks.append({"node": chunk, "velocity": velocity, "spin": randf_range(-spin, spin),
				"floor": floor_drop + randf_range(-FLOOR_SPREAD, FLOOR_SPREAD)})


func _process(delta: float) -> void:
	_age += delta
	var alpha := 1.0 - clampf((_age - _fade_from_s) / maxf(0.01, _life_s - _fade_from_s), 0.0, 1.0)
	for chunk: Dictionary in _chunks:
		var node: Sprite2D = chunk["node"]
		var velocity: Vector2 = chunk["velocity"]
		velocity.y += _gravity * delta
		node.position += velocity * delta
		node.rotation += float(chunk["spin"]) * delta
		if node.position.y > float(chunk["floor"]) and velocity.y > 0.0:
			node.position.y = float(chunk["floor"])
			velocity = Vector2(velocity.x * _friction, -velocity.y * _bounce)
			chunk["spin"] = float(chunk["spin"]) * _friction
		chunk["velocity"] = velocity
		node.modulate.a = alpha
	if _age >= _life_s:
		queue_free()


static func _option(options: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = options.get(key, fallback)
	return float(value) if value is float or value is int else fallback

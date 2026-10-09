extends Node2D
## A thrown thing breaking (owner, 2026-10-09): its own picture cut into PIECES x PIECES chunks that
## fly out, tumble, drop to the ground, skip once and fade, so a pot bursts into pot shards and a
## pumpkin into pumpkin bits. Presentation only (real-time `_process`); a child of the entities root
## at the break point, freed when the last chunk has faded (game/player/gulp/thrown_object.gd).
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


## Bursts `look` (a Sprite2D showing one frame of a sheet, as held_look.gd makes them) at `at`
## under `parent`. Nothing happens for a look without a texture.
static func burst(parent: Node, at: Vector2, look: Sprite2D) -> void:
	if parent == null or look == null or look.texture == null:
		return
	var node := new()
	node.name = "BreakBurst"
	node.z_index = 5
	parent.add_child(node)
	node.global_position = at
	node._cut(look)


func _cut(look: Sprite2D) -> void:
	var texture := look.texture
	var frames := Vector2(maxi(1, look.hframes), maxi(1, look.vframes))
	var cell := texture.get_size() / frames
	var origin := Vector2(look.frame % maxi(1, look.hframes), look.frame / maxi(1, look.hframes)) * cell
	var piece := cell / float(PIECES)
	for column in PIECES:
		for row in PIECES:
			var chunk := Sprite2D.new()
			chunk.texture = texture
			chunk.region_enabled = true
			chunk.region_rect = Rect2(origin + piece * Vector2(column, row), piece)
			chunk.scale = look.scale.abs()
			var offset := (piece * (Vector2(column, row) + Vector2(0.5, 0.5)) - cell * 0.5) * look.scale.abs()
			chunk.position = offset
			add_child(chunk)
			var outward := offset.normalized() if offset.length() > 0.1 else Vector2.RIGHT.rotated(randf() * TAU)
			var velocity := outward * randf_range(SPEED_MIN, SPEED_MAX) - Vector2(0.0, randf_range(LIFT_MIN, LIFT_MAX))
			_chunks.append({"node": chunk, "velocity": velocity, "spin": randf_range(-SPIN_MAX, SPIN_MAX),
				"floor": FLOOR_DROP + randf_range(-FLOOR_SPREAD, FLOOR_SPREAD)})


func _process(delta: float) -> void:
	_age += delta
	var alpha := 1.0 - clampf((_age - FADE_FROM_S) / maxf(0.01, LIFE_S - FADE_FROM_S), 0.0, 1.0)
	for chunk: Dictionary in _chunks:
		var node: Sprite2D = chunk["node"]
		var velocity: Vector2 = chunk["velocity"]
		velocity.y += GRAVITY * delta
		node.position += velocity * delta
		node.rotation += float(chunk["spin"]) * delta
		if node.position.y > float(chunk["floor"]) and velocity.y > 0.0:
			node.position.y = float(chunk["floor"])
			velocity = Vector2(velocity.x * FRICTION, -velocity.y * BOUNCE)
			chunk["spin"] = float(chunk["spin"]) * FRICTION
		chunk["velocity"] = velocity
		node.modulate.a = alpha
	if _age >= LIFE_S:
		queue_free()

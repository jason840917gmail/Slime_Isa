extends Node2D
## The suck's motes (game/player/gulp/gulp_feel.gd; game-constants.json `gulp.feel.suck`): a few pale
## specks drawn in from a cone ahead of the slime into its mouth, speeding up and swirling a little
## as they come, each over `moteMs`, started over `moteStaggerMs`. A child of the slime's body at its
## mouth, so they follow it; presentation only (`_process`, it pauses with the tree), freed when the
## last one has arrived.
##
## Owner: abilities.

const COLOR := Color(0.94, 1.0, 0.9, 0.95)
const GLOW := Color(0.78, 1.0, 0.72, 0.35)
const GLOW_SCALE := 2.2
## A mote starts this share of `moteFromPx` away at least (the rest is random), and shrinks to this
## share of its size at the mouth.
const NEAREST_SHARE := 0.55
const END_SIZE_SHARE := 0.35
const FADE_IN_SHARE := 0.2

## [{"delay": s, "angle": rad, "from": px, "size": px}]
var _motes: Array[Dictionary] = []
var _direction: Vector2 = Vector2.DOWN
var _life_s: float = 0.26
var _swirl: float = 0.0
var _age_s: float = 0.0


## `count` motes into `mouth` (the parent's local point) from ahead along `direction`, spread over
## `cone_deg`, starting up to `from_px` away; each lives `life_ms`, all start within `stagger_ms`,
## turning `swirl_turns` of a turn on the way in, `size_px` across.
static func spawn(parent: Node2D, mouth: Vector2, direction: Vector2, cone_deg: float, count: int, life_ms: float,
		stagger_ms: float, from_px: float, size_px: float, swirl_turns: float) -> void:
	if parent == null or count <= 0 or life_ms <= 0.0:
		return
	var node := new()
	node.name = "SuckMotes"
	node.z_index = 2
	node.position = mouth
	node._direction = direction.normalized() if direction != Vector2.ZERO else Vector2.DOWN
	node._life_s = life_ms / 1000.0
	node._swirl = swirl_turns * TAU
	var half := deg_to_rad(cone_deg) * 0.5
	for i in count:
		var share := (float(i) + 0.5) / float(count)
		node._motes.append({
			"delay": stagger_ms / 1000.0 * randf(),
			"angle": lerpf(-half, half, share) + randf_range(-0.12, 0.12),
			"from": from_px * randf_range(NEAREST_SHARE, 1.0),
			"size": size_px * randf_range(0.75, 1.15),
		})
	parent.add_child(node)


func _process(delta: float) -> void:
	_age_s += delta
	queue_redraw()
	var last := 0.0
	for mote: Dictionary in _motes:
		last = maxf(last, float(mote["delay"]))
	if _age_s >= last + _life_s:
		queue_free()


func _draw() -> void:
	for mote: Dictionary in _motes:
		var t := (_age_s - float(mote["delay"])) / maxf(0.01, _life_s)
		if t <= 0.0 or t >= 1.0:
			continue
		var eased := t * t
		var turn := float(mote["angle"]) + _swirl * eased
		var at := _direction.rotated(turn) * float(mote["from"]) * (1.0 - eased)
		var alpha := clampf(t / FADE_IN_SHARE, 0.0, 1.0)
		var radius := float(mote["size"]) * 0.5 * lerpf(1.0, END_SIZE_SHARE, eased)
		draw_circle(at, radius * GLOW_SCALE, Color(GLOW, GLOW.a * alpha))
		draw_circle(at, radius, Color(COLOR, COLOR.a * alpha))

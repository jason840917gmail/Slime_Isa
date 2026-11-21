extends Node2D
## The weight cue (owner, 2026-11-19, question 162; docs/godot/THROW_COMBAT.md "The weight cue"):
## the thing the Gulp would take now is highlighted, and pips over it say how heavy it is, so the
## slime knows before it tries.
##
## - **The target**: the mouth's own pick (mouth.gd `find_target` on the Gulp's aim: the nearest
##   suckable in reach the Gulp's level lifts), else the nearest in reach it is too weak for
##   (`find_too_heavy`). Nothing while the mouth holds something, the slime is dead, the world is
##   paused, or the throw-combat mode is off (weights mean nothing there).
## - **The highlight**: a ring on the ground round the target's feet, breathing gently; solid when
##   the Gulp can lift it, dashed (and in `heavyColor`) when it cannot.
## - **The pips**, over the thing, just above its "[Q] Suck" prompt (gulp_hud.gd, `promptClearPx`
##   over its feet, or over the top of its picture when that is higher), or under its ring when it
##   lies below the slime, which would hide them: one, two or three filled pips for light, medium and
##   heavy (the thing's `weight`, ThrowMode.level_for); when the Gulp's level is too low, one more
##   "too heavy" pip after them: a ring with a slash through it, in `heavyColor`. Shape, not colour
##   alone, tells them apart.
## - **The strain** (`strain`, from mouth_hold.gd when a suck ends with only a too-heavy thing in
##   reach, beside the "Too heavy!" line): the thing jitters and lifts a hair, the slash pip swells,
##   and the slime squashes as if it pulled.
##
## One per world, made on first use under the entities root (`ensure`, from mouth_hold.gd's step);
## it follows the slime on its own every frame (presentation, real time). Every number is in
## game-constants.json `gulp.throwCombat.weightCue`.
##
## Owner: throw combat.

const Services := preload("res://game/shared/services.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")

const NODE_NAME := "WeightCue"
const ROOT := "gulp.throwCombat.weightCue"
const STRAIN_META := &"weight_cue_strain"
const RING_POINTS := 40
const DASHES := 12
## Draw over the world (the ring sits on the thing's feet, the pips over its head).
const Z_INDEX := 120

var _target: WeakRef = weakref(null)
var _weight: String = ""
var _too_heavy: bool = false
var _since: float = 0.0
var _clock: float = 0.0
## The slash pip's swell after a strain (1 = none), real time.
var _swell: float = 1.0
var _numbers: Dictionary = {}


## The world's cue, made on first use under the entities root (freed with the world); null without a
## world.
static func ensure() -> Node2D:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return null
	var cue := parent.get_node_or_null(NODE_NAME) as Node2D
	if cue == null:
		cue = new()
		cue.name = NODE_NAME
		parent.add_child(cue)
	return cue


## A suck ended with only `thing` (too heavy) in reach: it strains (see the class notes).
static func strain(thing: Node, player: Node) -> void:
	var cue := ensure()
	if cue != null:
		cue.call(&"_strain", thing, player)


func _ready() -> void:
	z_index = Z_INDEX
	z_as_relative = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var constants := Services.constants()
	_numbers = constants.dictionary(ROOT) if constants != null else {}


## The thing highlighted now (null when none), whether it is too heavy, and its weight.
func target() -> Node:
	return _target.get_ref() as Node


func is_too_heavy() -> bool:
	return _too_heavy and target() != null


func target_weight() -> String:
	return _weight if target() != null else ""


func _process(delta: float) -> void:
	_clock += delta
	_swell = move_toward(_swell, 1.0, delta * 2.5)
	var picked := _pick()
	var thing: Node = picked.get("thing")
	if thing != target():
		_since = _clock
	_target = weakref(thing)
	_too_heavy = bool(picked.get("too_heavy", false))
	_weight = str(picked.get("weight", ""))
	visible = thing != null
	queue_redraw()


## {"thing", "too_heavy", "weight"} for the target now ({} for none).
func _pick() -> Dictionary:
	if not bool(_numbers.get("enabled", true)) or not ThrowMode.is_on() or get_tree().paused:
		return {}
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		return {}
	if not (player.call(&"held") as Dictionary).is_empty():
		return {}
	var mouth: Object = player.call(&"get_mouth")
	if mouth == null or bool(mouth.call(&"is_sucking")):
		return {}
	var aim: Vector2 = player.call(&"get_gulp_aim")
	var thing: Node = mouth.call(&"find_target", aim)
	var too_heavy := false
	if thing == null:
		thing = mouth.call(&"find_too_heavy", aim)
		too_heavy = thing != null
	if thing == null:
		return {}
	var weight := str(thing.call(&"weight")) if thing.has_method(&"weight") else ThrowMode.LIGHT
	return {"thing": thing, "too_heavy": too_heavy, "weight": weight if ThrowMode.WEIGHTS.has(weight) else ThrowMode.LIGHT}


func _draw() -> void:
	var thing := target()
	if thing == null or not thing.has_method(&"origin"):
		return
	var feet: Vector2 = to_local(thing.call(&"origin"))
	var appear := clampf((_clock - _since) / maxf(0.01, _num("fadeInS", 0.12)), 0.0, 1.0)
	var light := Color(str(_numbers.get("pipColor", "#fff6d8")))
	var edge := Color(str(_numbers.get("pipEdgeColor", "#2b1d10")))
	var heavy := Color(str(_numbers.get("heavyColor", "#ff9a3c")))
	var ring_colour := heavy if _too_heavy else light
	ring_colour.a *= _num("ringAlpha", 0.85) * appear
	# The ring round its feet, breathing.
	var breath := 1.0 + sin(_clock * TAU * _num("pulseHz", 1.5)) * _num("pulseShare", 0.1)
	var radius := Vector2(_num("ringRadiusPx", 20.0), _num("ringRadiusPx", 20.0) * _num("ringSquash", 0.42)) * breath
	var width := _num("ringWidthPx", 2.0)
	_ring(feet, radius + Vector2(1.0, 1.0), Color(edge, ring_colour.a * 0.6), width + 2.0, _too_heavy)
	_ring(feet, radius, ring_colour, width, _too_heavy)
	# The pips over it (above its "[Q] Suck" prompt), or under its ring when it lies below the slime
	# (so the slime never hides them).
	var level := ThrowMode.level_for(_weight)
	var count := level + (1 if _too_heavy else 0)
	var pip := _num("pipRadiusPx", 3.5)
	var gap := _num("pipGapPx", 10.0)
	var top := minf(_art_top(thing, feet) - _num("pipRisePx", 8.0), feet.y - _num("promptClearPx", 62.0))
	if feet.y > _slime_feet_y() + _num("belowPx", 12.0):
		top = feet.y + radius.y + _num("pipRisePx", 8.0) + pip
	var first_x := feet.x - gap * float(count - 1) * 0.5
	for index in count:
		var at := Vector2(first_x + gap * index, top)
		if index < level:
			draw_circle(at, pip + 1.5, Color(edge, appear))
			draw_circle(at, pip, Color(light, appear))
		else:
			_slash_pip(at, pip * _swell, Color(heavy, appear), Color(edge, appear))


## An ellipse outline round `centre` (`radius` its half axes); dashed when `dashed`.
func _ring(centre: Vector2, radius: Vector2, colour: Color, width: float, dashed: bool) -> void:
	if not dashed:
		var points := PackedVector2Array()
		for i in RING_POINTS + 1:
			var angle := TAU * float(i) / RING_POINTS
			points.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_polyline(points, colour, width, true)
		return
	var turn := _clock * 0.6
	for dash in DASHES:
		var from := turn + TAU * float(dash) / DASHES
		var arc := PackedVector2Array()
		for i in 4:
			var angle := from + (TAU / DASHES) * 0.55 * float(i) / 3.0
			arc.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_polyline(arc, colour, width, true)


## The "too heavy" pip: a ring with a slash through it.
func _slash_pip(at: Vector2, radius: float, colour: Color, edge: Color) -> void:
	draw_arc(at, radius + 1.0, 0.0, TAU, 20, edge, 3.5, true)
	draw_arc(at, radius + 1.0, 0.0, TAU, 20, colour, 2.0, true)
	var slash := Vector2(radius, -radius) * 0.75
	draw_line(at - slash, at + slash, edge, 3.5, true)
	draw_line(at - slash, at + slash, colour, 2.0, true)


## The top of the thing's picture in this node's space (its root's "Visual" Sprite2D), else
## `artHeightPx` over its feet.
func _art_top(thing: Node, feet: Vector2) -> float:
	var visual := _visual_of(thing) as Sprite2D
	if visual != null and visual.texture != null:
		var rect := visual.get_rect()
		var corners := [rect.position, rect.position + Vector2(rect.size.x, 0.0)]
		var top := INF
		for corner: Vector2 in corners:
			top = minf(top, to_local(visual.global_transform * corner).y)
		# A picture with empty space on top still keeps the pips close: at most artHeightPx x 1.6.
		return maxf(top, feet.y - _num("artHeightPx", 44.0) * 1.6)
	return feet.y - _num("artHeightPx", 44.0)


## The slime's feet's height in this node's space (-INF without a slime).
func _slime_feet_y() -> float:
	var world := Services.world()
	var body: Node2D = world.player_body if world != null else null
	return to_local(body.global_position).y if body != null and is_instance_valid(body) else -INF


## The thing's picture: its root's "Visual" (a liftable's script sits under the root).
static func _visual_of(thing: Node) -> Node2D:
	var root := thing.get_parent() if not thing is Node2D else thing
	var visual := root.get_node_or_null(^"Visual") as Node2D if root != null else null
	if visual == null and thing.get_parent() != null:
		visual = thing.get_parent().get_node_or_null(^"Visual") as Node2D
	return visual


func _strain(thing: Node, player: Node) -> void:
	_swell = _num("strainSwell", 1.6)
	var ms := _num("strainMs", 420.0)
	if player != null and is_instance_valid(player) and player.has_method(&"squash_by"):
		player.call(&"squash_by", Vector2(_num("slimeStrainX", 1.1), _num("slimeStrainY", 0.9)), ms * 0.5, Tween.TRANS_SINE, false)
	var visual := _visual_of(thing) if thing != null and is_instance_valid(thing) else null
	if visual == null:
		return
	var running: Variant = visual.get_meta(STRAIN_META) if visual.has_meta(STRAIN_META) else null
	var rest := visual.position
	if running is Array and (running as Array).size() == 2:
		var old_tween := (running as Array)[0] as Tween
		rest = (running as Array)[1]
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
	var shake := _num("strainPx", 3.0)
	var lift := _num("strainLiftPx", 3.0)
	var turns := _num("strainTurns", 4.0)
	var tween := visual.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(visual):
			visual.position = rest + Vector2(sin(t * TAU * turns) * shake * (1.0 - t), -sin(t * PI) * lift), 0.0, 1.0, ms / 1000.0)
	tween.tween_callback(func() -> void:
		if is_instance_valid(visual):
			visual.position = rest
			visual.remove_meta(STRAIN_META))
	visual.set_meta(STRAIN_META, [tween, rest])


func _num(key: String, fallback: float) -> float:
	var value: Variant = _numbers.get(key)
	return float(value) if value is float or value is int else fallback

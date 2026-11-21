extends NpcScript
class_name VillagerScript
## A West town villager (docs/godot/VILLAGERS.md): an NPC (npc.gd: lines from npc-definitions.json,
## a name tag, the wander policy) placed by hand from the Scenery dock's Villagers category, under
## the world's `NPCs` node. How it moves, in this order:
##
## - an `npc-wander` world area that names it (world spec 3.1 and 5.3), as for the old NPCs;
## - else `follow`: it mills about within `follow_radius` of that node (Dany after Isa, the parents
##   after Gavy, a pup at its owner's heels);
## - else a route: the points of the Path2D `route` (by default its child "Route"; turn on Editable
##   Children on the instance to drag them), walked in order with a pause at each, round and round
##   or (`route_loop` off) there and back;
## - else its own circle of `wander_radius` around where it stands;
## - else it stays put (the shopkeepers and the villagers at their posts).
##
## Standing still it keeps facing its last way ("idle-left", "-right", "-up" when its library has
## them), and it plays "talk" while a dialogue holds it (npc.gd `_rest_clip`).
##
## **Climbers** (`climbs_over`; owner, 2026-11-01: Gavy climbs walls and fences, and her father
## after her): walking into a fence (the `fences` layer) or a wall (a `walls` WallLayer: stone,
## hedges), it hops over: it looks for a free spot past it, `climb_step` by `climb_step` up to
## `climb_reach` px on its way, where nothing stands, inside the world, and crosses to it at
## `climb_speed` with no collision, its picture rising `climb_height` px in an arc (its shadow stays
## on the ground). It climbs only what blocks its way about head on (`climb_head_on`), rests
## `climb_rest_ms` after each landing and then picks a fresh spot, and a follower climbs only to
## catch up with its leader. It never climbs over houses, cliffs, water or anything else.
##
## **Asleep** (Glimmerhill asleep, owner 2026-11-17/19; docs/godot/VILLAGERS.md "Asleep until its
## Pearl comes home"): standing in a part of Glimmerhill that sleeps (the wake table,
## game/glimmerhill/glimmerhill_wake.gd: its chunk inside the town's rectangle, or its room, and the
## part's wake flag unset), it is in a trance: frozen on its idle's eyes-shut (blink) frame at its
## idle's first scale, with no wander, route, follow or climb, out of the `npc` and `interactable`
## groups (no talk prompt, no name tag, no quest or tip marker) and a soft "z" drifting over its head
## (sleep_z.gd). It says nothing. When the flag is set it wakes where it stands, after a short random
## delay: the "z" fades, it stretches tall and squashes back on its eyes-shut frame, then its idle
## plays, it is an NPC again and it moves as it would have from the start. No scene holds any of it.
##
## Owner: world (villagers).

const Perimeter := preload("res://game/shared/perimeter.gd")
const GlimmerhillWake := preload("res://game/glimmerhill/glimmerhill_wake.gd")
const SleepZ := preload("res://game/glimmerhill/sleep_z.gd")
const FRAME_TRACK := "Visual:frame"
const SCALE_TRACK := "Visual:scale"
const FLIP_TRACK := "Visual:flip_h"
const POSITION_TRACK := "Visual:position"
## The name tags' usual height over the feet (npc_name_tags.gd TAG_RISE) and how far under the tag
## the "z" starts (about the top of the head), and how far aside.
const DEFAULT_TAG_RISE := 75.28
const Z_UNDER_TAG := 16.0
const Z_ASIDE := 8.0
const FencesScript := preload("res://game/world/fences/fences.gd")
const WallLayerScript := preload("res://game/world/walls/wall_layer.gd")
## How far ahead (px) a climber probes for what stops its walk, and how many parents up a collider
## may sit under its fences or walls layer.
const CLIMB_PROBE_PX := 4.0
const CLIMB_PARENT_DEPTH := 3
const BODY_SHAPE_NAME := "BodyShape"

## The wander body bounds relative to the feet (the scene root): Rect2(minX, minY, width, height).
@export var body_bounds: Rect2 = Rect2()
## Its own wander circle's radius (world units) around where it stands; 0 = none.
@export_range(0.0, 1024.0, 1.0, "or_greater") var wander_radius: float = 0.0
## A Path2D whose points it walks in order; empty = its child "Route", when it has one.
@export var route: NodePath = NodePath("")
## Round and round (true) or there and back (false).
@export var route_loop: bool = true
## A node it follows (another villager's root): it wanders within `follow_radius` of its feet.
@export var follow: NodePath = NodePath("")
@export_range(0.0, 512.0, 1.0, "or_greater") var follow_radius: float = 48.0
## How high its name tag floats over its feet (world units); 0 = the NPCs' usual height.
@export var name_tag_rise: float = 0.0
## Hops over fences and walls (see above), and how: crossing speed (px/s), how far past it may land
## (px), the step its landing spots are tried by (px), and the hop's height (px).
@export var climbs_over: bool = false
@export var climb_speed: float = 0.0
@export var climb_reach: float = 0.0
@export var climb_step: float = 0.0
@export var climb_height: float = 0.0
## How straight on the fence or wall must block its way to climb it (the dot of its way and the
## wall's normal, 0..1: 1 only dead on), and how long after landing before it may climb again (ms).
@export_range(0.0, 1.0) var climb_head_on: float = 0.0
@export var climb_rest_ms: float = 0.0

const ROUTE_CHILD := "Route"

var _route_points: PackedVector2Array = PackedVector2Array()
var _route_index: int = 0
var _route_step: int = 1
var _leader: Node2D
## A climb under way: its way, when it started and ends (Services.now_ms()), the body's own mask,
## and the picture's own offset.
var _climb_direction: Vector2 = Vector2.ZERO
var _climb_from_ms: float = 0.0
var _climb_until_ms: float = 0.0
var _climb_mask: int = 0
var _visual_offset: Vector2 = Vector2.ZERO
## No climbing before this (Services.now_ms()): the rest after a landing.
var _climb_rest_until_ms: float = 0.0
## The Glimmerhill part it sleeps in ("" awake), whether it is waking (the stretch), and its "z".
var _asleep_part: String = ""
var _waking: bool = false
var _sleep_z: Node2D


func _ready() -> void:
	super._ready()
	if body == null:
		return
	_asleep_part = GlimmerhillWake.asleep_part_of(body)
	if not _asleep_part.is_empty():
		_fall_asleep()


func _exit_tree() -> void:
	super._exit_tree()
	GlimmerhillWake.unlisten(_on_story_flag_changed)


func _enter_tree() -> void:
	if not _asleep_part.is_empty():
		GlimmerhillWake.listen(_on_story_flag_changed)


## True while it sleeps (or is still stretching awake).
func is_asleep() -> bool:
	return not _asleep_part.is_empty() or _waking


func _physics_process(delta: float) -> void:
	if is_asleep():
		return
	if _climb_until_ms > 0.0:
		_climb(delta)
		return
	super._physics_process(delta)
	if climbs_over and not _is_paused() and _has_agent:
		_try_climb()


## Starts a climb when its walk is stopped by a fence or a wall and a free spot lies past it.
func _try_climb() -> void:
	var target: Variant = _state.get("target")
	if target == null or str(_state.get("phase", "")) != NpcWanderPolicy.PHASE_MOVE \
			or Services.now_ms() < _climb_rest_until_ms:
		return
	var way: Vector2 = (target as Vector2) - get_phaser_position()
	if way.length() < 1.0:
		return
	# a follower climbs only to catch up, never while its leader is within reach
	if _leader != null and is_instance_valid(_leader) \
			and FeetAnchor.phaser_position(_leader).distance_to(get_phaser_position()) <= follow_radius:
		return
	way = way.normalized()
	var collision := KinematicCollision2D.new()
	if not body.test_move(body.global_transform, way * CLIMB_PROBE_PX, collision) or not _climbable(collision.get_collider()) \
			or -way.dot(collision.get_normal()) < climb_head_on:
		return
	var reach := 0.0
	var distance := climb_step
	while distance <= climb_reach and climb_step > 0.0:
		if _free_landing(body.global_position + way * distance):
			reach = distance
			break
		distance += climb_step
	if reach <= 0.0 or climb_speed <= 0.0:
		return
	_climb_direction = way
	_climb_from_ms = Services.now_ms()
	_climb_until_ms = _climb_from_ms + reach / climb_speed * 1000.0
	_climb_mask = body.collision_mask
	body.collision_mask = 0
	if visual != null:
		_visual_offset = visual.offset


## One step of a climb: across at `climb_speed`, the picture in its hop; it lands when the time is up.
func _climb(delta: float) -> void:
	var now := Services.now_ms()
	var share := clampf((now - _climb_from_ms) / maxf(1.0, _climb_until_ms - _climb_from_ms), 0.0, 1.0)
	body.velocity = _climb_direction * climb_speed
	if visual != null:
		visual.offset = _visual_offset - Vector2(0.0, sin(share * PI) * climb_height / maxf(0.001, visual.scale.y))
	ArcadeMover.move(body, delta)
	if now >= _climb_until_ms:
		_climb_until_ms = 0.0
		_climb_rest_until_ms = now + climb_rest_ms
		body.collision_mask = _climb_mask
		body.velocity = Vector2.ZERO
		if visual != null:
			visual.offset = _visual_offset
		# a fresh spot from where it landed (a follower's is near its leader again)
		_state = NpcWanderPolicy.create_state(0.0, str(_state.get("facing", "down")))


## True for a fence's or a wall's collision body (under a `fences` layer or a WallLayer).
func _climbable(collider: Object) -> bool:
	var node := collider as Node
	for _i in CLIMB_PARENT_DEPTH:
		if node == null:
			return false
		var script := node.get_script() as Script
		if script == FencesScript or script == WallLayerScript:
			return true
		node = node.get_parent()
	return false


## Whether its body could stand at `feet`: inside the world and touching nothing (so it lands past
## the fence or wall, never on top of it).
func _free_landing(feet: Vector2) -> bool:
	var world_rect: Rect2 = Services.world().world_rect() if Services.world() != null else Rect2()
	if world_rect.has_area() and not world_rect.has_point(feet):
		return false
	var shape_node := body.get_node_or_null(NodePath(BODY_SHAPE_NAME)) as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = Transform2D(0.0, feet + shape_node.position)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func configure_wander(perimeter: Dictionary) -> void:
	_route_points = _read_route()
	_leader = get_node_or_null(follow) as Node2D if not follow.is_empty() else null
	if not perimeter.is_empty():
		super.configure_wander(perimeter)
	elif _leader != null:
		_start_agent(_circle(FeetAnchor.phaser_position(_leader), follow_radius))
	elif _route_points.size() >= 2:
		_route_index = 0
		_route_step = 1
		_start_agent(_circle(_route_points[0], 0.0))
	elif wander_radius > 0.0 and body != null:
		super.configure_wander(_circle(get_phaser_position(), wander_radius))
	else:
		super.configure_wander({})


func _body_bounds() -> Rect2:
	return body_bounds


func _before_step() -> void:
	if _leader != null and is_instance_valid(_leader):
		_domain = _circle(FeetAnchor.phaser_position(_leader), follow_radius)


func _on_rest() -> void:
	if _leader != null or _route_points.size() < 2:
		return
	var last := _route_points.size() - 1
	if route_loop:
		_route_index = (_route_index + 1) % _route_points.size()
	else:
		if _route_index + _route_step < 0 or _route_index + _route_step > last:
			_route_step = -_route_step
		_route_index += _route_step
	_domain = _circle(_route_points[_route_index], 0.0)


func _rest_clip() -> String:
	var clip := super._rest_clip()
	if clip != ANIM_IDLE or animation == null:
		return clip
	var facing := str(_state.get("facing", "down"))
	if facing != "down" and animation.has_animation(ANIM_IDLE + "-" + facing):
		return ANIM_IDLE + "-" + facing
	return clip


## Its route's points in world space (read once: the points do not move with it), or none.
func _read_route() -> PackedVector2Array:
	var path_node: Node = get_node_or_null(route) if not route.is_empty() else null
	if path_node == null and body != null:
		path_node = body.get_node_or_null(NodePath(ROUTE_CHILD))
	var path := path_node as Path2D
	var points := PackedVector2Array()
	if path == null or path.curve == null:
		return points
	for index in path.curve.point_count:
		points.append(path.to_global(path.curve.get_point_position(index)))
	return points


## Starts the agent on `domain` as it is (no inset for the body: a route stop or a leader's circle).
func _start_agent(domain: Dictionary) -> void:
	_domain = domain
	_state = NpcWanderPolicy.create_state(random_pause())
	_has_agent = true


static func _circle(centre: Vector2, radius: float) -> Dictionary:
	return {"shape": Perimeter.SHAPE_CIRCLE, "x": centre.x, "y": centre.y, "radius": maxf(0.0, radius)}


# --- asleep (Glimmerhill) ----------------------------------------------------------------------

## Into its trance: out of the NPC groups, frozen eyes shut, the "z" over its head, waiting for its
## part's wake flag.
func _fall_asleep() -> void:
	remove_from_group(GROUP_NPC)
	remove_from_group(GROUP_INTERACTABLE)
	_has_agent = false
	body.velocity = Vector2.ZERO
	if animation != null:
		animation.pause()
	if visual != null:
		visual.frame = _blink_frame()
		var flip: Variant = _idle_key(FLIP_TRACK, 0)
		if flip is bool:
			visual.flip_h = flip
		var scale_key: Variant = _idle_key(SCALE_TRACK, 0)
		if scale_key is Vector2:
			visual.scale = scale_key
		var position_key: Variant = _idle_key(POSITION_TRACK, 0)
		if position_key is Vector2:
			visual.position = position_key
	_sleep_z = SleepZ.new()
	_sleep_z.name = "SleepZ"
	_sleep_z.count = int(GlimmerhillWake.tunable_number("villagers", "zCount", 2.0))
	_sleep_z.cycle_ms = GlimmerhillWake.tunable_number("villagers", "zCycleMs", 3400.0)
	_sleep_z.rise_px = GlimmerhillWake.tunable_number("villagers", "zRisePx", 30.0)
	_sleep_z.drift_px = GlimmerhillWake.tunable_number("villagers", "zDriftPx", 12.0)
	_sleep_z.font_size = int(GlimmerhillWake.tunable_number("villagers", "zFontSize", 13.0))
	_sleep_z.alpha = GlimmerhillWake.tunable_number("villagers", "zAlpha", 0.8)
	var rise := name_tag_rise if name_tag_rise > 0.0 else DEFAULT_TAG_RISE
	_sleep_z.position = Vector2(Z_ASIDE, -(rise - Z_UNDER_TAG))
	# Over the town's sleep overlay (town_sleep.gd), so the "z" keeps its own colour.
	_sleep_z.z_as_relative = false
	_sleep_z.z_index = int(GlimmerhillWake.tunable_number("sleep", "overlayZ", 30.0)) + 1
	body.add_child(_sleep_z)
	GlimmerhillWake.listen(_on_story_flag_changed)


func _on_story_flag_changed(payload: Dictionary) -> void:
	if not _asleep_part.is_empty() and not _waking and GlimmerhillWake.wakes(payload, _asleep_part):
		_wake()


## Wakes where it stands: after a short random delay the "z" fades and it stretches tall and squashes
## back (still eyes shut), then `_finish_waking`.
func _wake() -> void:
	_waking = true
	_asleep_part = ""
	GlimmerhillWake.unlisten(_on_story_flag_changed)
	var delay_s := randf() * GlimmerhillWake.tunable_number("villagers", "wakeDelayMaxMs", 900.0) / 1000.0
	var stretch_s := maxf(0.05, GlimmerhillWake.tunable_number("villagers", "stretchMs", 650.0) / 1000.0)
	var stretch := GlimmerhillWake.tunable_number("villagers", "stretch", 0.14)
	var tween := create_tween()
	tween.tween_interval(delay_s)
	tween.tween_callback(_stop_sleep_z)
	if visual != null:
		var base := visual.scale
		tween.tween_property(visual, "scale", base * Vector2(1.0 - stretch * 0.6, 1.0 + stretch), stretch_s * 0.45) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "scale", base * Vector2(1.0 + stretch * 0.4, 1.0 - stretch * 0.35), stretch_s * 0.3) \
				.set_trans(Tween.TRANS_SINE)
		tween.tween_property(visual, "scale", base, stretch_s * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_waking)


func _stop_sleep_z() -> void:
	if _sleep_z != null and is_instance_valid(_sleep_z):
		_sleep_z.call(&"stop")
	_sleep_z = null


## Awake: its idle plays, it is an NPC again (talk, name tag, markers) and moves as placed.
func _finish_waking() -> void:
	_waking = false
	add_to_group(GROUP_NPC)
	add_to_group(GROUP_INTERACTABLE)
	if animation != null:
		animation.play(ANIM_IDLE)
	var world := Services.world()
	var record: Dictionary = world.npc_wander_area(get_instance_id_key()) if world != null else {}
	configure_wander(record.get("perimeter", {}))


## Its pose sheet's eyes-shut frame: the first frame of its idle's frame track that differs from the
## idle's first (the blink), else the first.
func _blink_frame() -> int:
	var first: Variant = _idle_key(FRAME_TRACK, 0)
	var track := _idle_track(FRAME_TRACK)
	var clip := animation.get_animation(ANIM_IDLE) if animation != null and animation.has_animation(ANIM_IDLE) else null
	if clip != null and track >= 0:
		for key in clip.track_get_key_count(track):
			var frame: Variant = clip.track_get_key_value(track, key)
			if frame != first:
				return int(frame)
	return int(first) if first != null else 0


## The value of key `key` of the idle clip's track on `path`, null without one.
func _idle_key(path: String, key: int) -> Variant:
	var track := _idle_track(path)
	if track < 0:
		return null
	var clip := animation.get_animation(ANIM_IDLE)
	return clip.track_get_key_value(track, key) if key < clip.track_get_key_count(track) else null


func _idle_track(path: String) -> int:
	if animation == null or not animation.has_animation(ANIM_IDLE):
		return -1
	return animation.get_animation(ANIM_IDLE).find_track(NodePath(path), Animation.TYPE_VALUE)

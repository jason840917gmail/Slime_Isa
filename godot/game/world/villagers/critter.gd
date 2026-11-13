extends CharacterBody2D
class_name Critter
## A West town animal (docs/godot/VILLAGERS.md "Animals"): pigs, the pup, the cat, hens and chicks,
## sheep, ducks, birds, the snail, the hedgehog, the squirrel; and a cave animal ("Cave animals":
## fireflies, the glow-worm, the pill bug, the cave newt, the crystal snail, the lantern moth). Placed
## by hand from the Scenery dock's Animals and Cave animals categories under the world's `Animals`
## node; nothing spawns them. It moves only through `ArcadeMover.move` and never hurts or blocks the
## slime's attacks.
##
## Where it goes (the villagers' rules, villager_script.gd): after `follow` (piglets after the
## sow, chicks after the hen, the pup at Old Sedge's heels: within `follow_radius` of its feet,
## hurrying at `catch_up_speed` when it falls behind), else along the Path2D `route` (its child
## "Route" by default: the ducks' loop on the pond), else within the `npc-wander` world area that
## names it (`data.npcInstanceId` = its `metadata/instance_id`, else its node name: a shape to drag
## and resize in the editor, as the old NPCs'), else within its own circle of `wander_radius`
## around where it stands (none: it stays put), with the wander policy's pauses
## (npc_wander_policy.gd). Pausing, it sometimes plays one of `rest_clips` (a snuffle, a peck) for
## the whole pause, else its idle, facing its last way ("idle-left"... when it has them).
##
## How it takes the slime coming within `notice_px` (`reaction`):
## - "flee": runs straight away at `flee_speed` for `flee_ms`, then wanders back (hens, cat, squirrel);
## - "fly": flies off (its picture rises and drifts `fly_px` away over `fly_ms`, fading), stays away
##   `gone_ms`, then flies back in somewhere in its circle and lands (the robin, the doves);
## - "curl" / "hide": plays that clip while the slime is near and `calm_ms` after (the hedgehog's
##   ball, the snail in its shell);
## - "none": takes no notice (pigs, sheep, ducks).
##
## **Birds fly about** (owner, 2026-11-01: "the bird need to fly as well"): when a pause would start,
## a bird with `flight_chance` takes off instead: its picture rises `flight_height` over `fly_ms`
## (its shadow stays on the ground and shrinks), it flies at `flight_speed` to a random spot of its
## circle over walls and roofs (no collision while up), and comes down there. `always_flying` (the
## swallow) never lands: it flies from spot to spot round its circle. One that never lands and
## has the reaction "flee" (the fireflies) scatters instead of running: it makes for a far spot of
## its circle at `flee_speed` for `flee_ms`. `flight_wobble_px` sways a flier's picture about its
## path (a firefly's drift, a moth's flutter).
##
## **A glow** (`glow`, cave animals: the firefly's and the glow-worm's tail, the crystal snail's
## crystals): a soft light under its Visual whose brightness its clips animate. It stays on its side
## of the picture when the picture is mirrored, and in a dark room that is still dark it is drawn
## over the darkness (as the enemies' eyes, game/enemy/dark_eyes.gd), so there only the glow shows.
## It is a picture, not a light source: it lights nothing and no enemy or puzzle reads it.
##
## All its numbers are scene properties, tuned per animal in its scene (game/scenes/objects/animals/).
##
## Owner: world (villagers).

const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const NpcWanderPolicy := preload("res://game/world/npc_wander_policy.gd")
const Perimeter := preload("res://game/shared/perimeter.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const DarkRoom := preload("res://game/world/darkness/dark_room.gd")

const PLAYER_GROUP := &"player"
const ANIM_IDLE := "idle"
const ROUTE_CHILD := "Route"
const STATE_WANDER := "wander"
const STATE_FLEE := "flee"
const STATE_HUDDLE := "huddle"
const STATE_FLY_OFF := "fly-off"
const STATE_GONE := "gone"
const STATE_FLY_IN := "fly-in"
const STATE_TAKE_OFF := "take-off"
const STATE_FLIGHT := "flight"
const STATE_LANDING := "landing"
const SHADOW_NAME := "Shadow"
## The share of its size the shadow keeps at the top of a flight.
const SHADOW_HIGH_SCALE := 0.55
## How near (world units) a flight's spot counts as reached (the wander policy's arrival).
const FLIGHT_ARRIVAL := 6.0
## Over a dark room's darkness overlay (dark_room.gd OVERLAY_Z 45), where a glow is drawn in the dark.
const GLOW_DARK_Z := 46
## How many spots of its circle a scattering flier looks at for the one farthest from the slime.
const SCATTER_TRIES := 6
## A flier's sway (flight_wobble_px): its turns a second sideways and up and down, and how much of
## the sway goes up and down.
const WOBBLE_RATE := Vector2(1.7, 2.9)
const WOBBLE_RISE_SHARE := 0.6

## The sprite and its AnimationPlayer (clips idle, walk-left/-right/-down/-up; fly-left/-right,
## curl, hide and rest clips by animal).
@export var visual: Sprite2D
@export var animation: AnimationPlayer
## Walking speed (px/s) and the pauses between walks (ms).
@export var walk_speed: float = 0.0
@export var pause_min_ms: float = 0.0
@export var pause_max_ms: float = 0.0
## Its own wander circle around where it stands (world units); 0 = it stays put.
@export_range(0.0, 1024.0, 1.0, "or_greater") var wander_radius: float = 0.0
## A node it follows (its mother, its owner): it wanders within `follow_radius` of its feet.
@export var follow: NodePath = NodePath("")
@export_range(0.0, 512.0, 1.0, "or_greater") var follow_radius: float = 32.0
## Its speed (px/s) while farther than twice `follow_radius` from the node it follows.
@export var catch_up_speed: float = 0.0
## A Path2D whose points it walks (or swims) round and round; empty = its child "Route".
@export var route: NodePath = NodePath("")
## Clips it may play for a whole pause instead of its idle, and how often (0..1).
@export var rest_clips: PackedStringArray = PackedStringArray()
@export_range(0.0, 1.0) var rest_clip_chance: float = 0.0
## How it takes the slime coming near (see above).
@export_enum("none", "flee", "fly", "curl", "hide") var reaction: String = "none"
@export var notice_px: float = 0.0
@export var flee_speed: float = 0.0
@export var flee_ms: float = 0.0
@export var calm_ms: float = 0.0
@export var fly_px: float = 0.0
@export var fly_ms: float = 0.0
@export var gone_ms: float = 0.0
## Flying about (birds): the chance (0..1) it takes off when a pause would start, how high its
## picture rises (px), its flying speed (px/s), and whether it never lands.
@export_range(0.0, 1.0) var flight_chance: float = 0.0
@export var flight_height: float = 0.0
@export var flight_speed: float = 0.0
@export var always_flying: bool = false
## How far (px) a flier's picture sways about its path while it is up (0: a straight flight).
@export var flight_wobble_px: float = 0.0
## Its glow (a node under its Visual; see above): mirrored with the picture, over the dark in a
## dark room.
@export var glow: Node2D
## Its body bounds for the wander domain, relative to its feet.
@export var body_bounds: Rect2 = Rect2()

var _state: Dictionary = {}
var _domain: Dictionary = {}
var _home: Dictionary = {}
var _mode: String = STATE_WANDER
## When the current flee, huddle, flight or absence ends (Services.now_ms()).
var _until_ms: float = 0.0
var _flee_direction: Vector2 = Vector2.ZERO
var _fly_from: Vector2 = Vector2.ZERO
var _rest_clip: String = ""
var _route_points: PackedVector2Array = PackedVector2Array()
var _route_index: int = 0
var _leader: Node2D
var _player: Node2D
## Its own collision mask (cleared while it flies).
var _mask: int = 0
## How high its picture is (px) and where its flight goes.
var _height: float = 0.0
var _flight_target: Vector2 = Vector2.ZERO
var _shadow: Node2D
## Whether the world's `npc-wander` areas were looked at (once, on its first step: the world
## registers its areas after its nodes are ready).
var _area_read: bool = false
## The glow's own place and depth (as the scene has them) and whether it is drawn over a dark room.
var _glow_x: float = 0.0
var _glow_z: int = 0
var _glow_dark: bool = false
var _wobble_phase: float = 0.0


func _ready() -> void:
	_mask = collision_mask
	_shadow = get_node_or_null(NodePath(SHADOW_NAME)) as Node2D
	_route_points = _read_route()
	_leader = get_node_or_null(follow) as Node2D if not follow.is_empty() else null
	var feet := FeetAnchor.phaser_position(self)
	if wander_radius > 0.0:
		_home = NpcWanderPolicy.wander_domain(_circle(feet, wander_radius), body_bounds)
	if _route_points.size() >= 2:
		_domain = _circle(_route_points[0], 0.0)
	elif not _home.is_empty():
		_domain = _home
	_state = NpcWanderPolicy.create_state(_random_pause())
	_wobble_phase = randf() * TAU
	if glow != null:
		_glow_x = glow.position.x
		_glow_z = glow.z_index
	_play(ANIM_IDLE)
	if always_flying:
		_take_off(Services.now_ms())
		_mode = STATE_FLIGHT
		_set_height(flight_height)


func _physics_process(delta: float) -> void:
	if not _area_read:
		_read_area()
	var now := Services.now_ms()
	var player := _find_player()
	var near := player != null and notice_px > 0.0 and player.global_position.distance_to(global_position) <= notice_px
	match _mode:
		STATE_FLEE:
			velocity = _flee_direction * flee_speed
			_play(_walk_clip(_facing_of(_flee_direction)))
			if now >= _until_ms:
				_settle()
		STATE_HUDDLE:
			velocity = Vector2.ZERO
			if near:
				_until_ms = now + calm_ms
			elif now >= _until_ms:
				_settle()
		STATE_FLY_OFF:
			velocity = Vector2.ZERO
			_fly_step(now, true)
			if now >= _until_ms:
				_mode = STATE_GONE
				_until_ms = now + gone_ms
				visual.visible = false
		STATE_GONE:
			velocity = Vector2.ZERO
			if now >= _until_ms:
				_land_somewhere_else(now)
		STATE_FLY_IN:
			velocity = Vector2.ZERO
			_fly_step(now, false)
			if now >= _until_ms:
				visual.position = Vector2.ZERO
				visual.modulate.a = 1.0
				_settle()
		STATE_TAKE_OFF:
			velocity = Vector2.ZERO
			_set_height(flight_height * _share(now))
			if now >= _until_ms:
				_mode = STATE_FLIGHT
		STATE_FLIGHT:
			var scatters := always_flying and reaction == "flee"
			if scatters and near and now >= _until_ms and not _home.is_empty():
				_flight_target = _far_spot(player)
				_until_ms = now + flee_ms
			var speed := maxf(flee_speed, flight_speed) if scatters and now < _until_ms else flight_speed
			if flight_wobble_px > 0.0:
				# Presentation, on real time: the picture sways, the body flies straight.
				var t := float(Time.get_ticks_msec()) / 1000.0 + _wobble_phase
				visual.position = Vector2(sin(t * WOBBLE_RATE.x) * flight_wobble_px,
						-_height + sin(t * WOBBLE_RATE.y) * flight_wobble_px * WOBBLE_RISE_SHARE)
			var to_target := _flight_target - global_position
			if to_target.length() <= FLIGHT_ARRIVAL:
				velocity = Vector2.ZERO
				if always_flying:
					_flight_target = _flight_spot()
				else:
					_mode = STATE_LANDING
					_until_ms = now + fly_ms
			else:
				velocity = to_target.normalized() * minf(speed, to_target.length() / maxf(delta, 0.001))
				_play("fly-left" if velocity.x < 0.0 else "fly-right")
		STATE_LANDING:
			velocity = Vector2.ZERO
			_set_height(flight_height * (1.0 - _share(now)))
			if now >= _until_ms:
				_set_height(0.0)
				collision_mask = _mask
				_settle()
		_:
			if not (near and _react(player, now)):
				_wander(delta)
	ArcadeMover.move(self, delta)
	_show_glow()


func _wander(delta: float) -> void:
	if _leader == null and not follow.is_empty():
		_leader = get_node_or_null(follow) as Node2D
	if _leader != null and is_instance_valid(_leader):
		_domain = _circle(FeetAnchor.phaser_position(_leader), follow_radius)
	var speed := walk_speed
	if _leader != null and is_instance_valid(_leader) and catch_up_speed > 0.0 \
			and FeetAnchor.phaser_position(_leader).distance_to(global_position) > follow_radius * 2.0:
		speed = catch_up_speed
	var result := NpcWanderPolicy.step(_state, FeetAnchor.phaser_position(self), delta * 1000.0, speed, _domain)
	var next_state: Dictionary = result["state"]
	var clip: String = result["animation"]
	if clip == ANIM_IDLE and next_state["phase"] == NpcWanderPolicy.PHASE_PAUSE \
			and float(next_state["pause_remaining_ms"]) == 0.0:
		if flight_chance > 0.0 and not _home.is_empty() and randf() < flight_chance:
			_state = next_state
			_take_off(Services.now_ms())
			return
		next_state = NpcWanderPolicy.create_state(_random_pause(), next_state["facing"])
		_next_stop()
		_rest_clip = rest_clips[randi() % rest_clips.size()] \
				if not rest_clips.is_empty() and randf() < rest_clip_chance else ""
	_state = next_state
	velocity = result["velocity"]
	if clip == ANIM_IDLE:
		_play(_idle_clip())
	else:
		_rest_clip = ""
		_play(_walk_clip(str(_state.get("facing", "down"))))


## Starts its reaction to the slime; false when it takes no notice.
func _react(player: Node2D, now: float) -> bool:
	var away := global_position - player.global_position
	if away.length() < 0.01:
		away = Vector2.RIGHT
	match reaction:
		"flee":
			_mode = STATE_FLEE
			_flee_direction = away.normalized()
			_until_ms = now + flee_ms
		"fly":
			_mode = STATE_FLY_OFF
			_fly_from = Vector2(signf(away.x) if absf(away.x) > 0.01 else 1.0, -0.6) * fly_px
			_until_ms = now + fly_ms
			_play("fly-right" if _fly_from.x > 0.0 else "fly-left")
		"curl", "hide":
			_mode = STATE_HUDDLE
			_until_ms = now + calm_ms
			_play(reaction)
		_:
			return false
	velocity = Vector2.ZERO
	return true


## A flight's picture: rising away (`leaving`) or coming down to its feet.
func _fly_step(now: float, leaving: bool) -> void:
	var t := clampf(1.0 - (_until_ms - now) / maxf(1.0, fly_ms), 0.0, 1.0)
	var share := t if leaving else 1.0 - t
	visual.position = _fly_from * share
	visual.modulate.a = 1.0 - share * share


## After its absence: it comes back down at a random spot of its circle, flying in from the side
## it left by. The body is set there while nobody sees it (a respawn, not a move).
func _land_somewhere_else(now: float) -> void:
	if not _home.is_empty():
		global_position = Perimeter.random_point(_home) + (global_position - FeetAnchor.phaser_position(self))
	_mode = STATE_FLY_IN
	_until_ms = now + fly_ms
	visual.visible = true
	_fly_step(now, false)
	_play("fly-left" if _fly_from.x > 0.0 else "fly-right")


## Its home becomes the `npc-wander` world area that names it, when there is one.
func _read_area() -> void:
	_area_read = true
	var world := Services.world()
	if world == null:
		return
	var key := str(get_meta(&"instance_id")) if has_meta(&"instance_id") else String(name)
	var perimeter: Dictionary = world.npc_wander_area(key).get("perimeter", {})
	if perimeter.is_empty():
		return
	_home = NpcWanderPolicy.wander_domain(perimeter, body_bounds)
	if _route_points.size() < 2 and follow.is_empty():
		_domain = _home


## Takes off for a spot of its circle: no collision while it is up.
func _take_off(now: float) -> void:
	_mode = STATE_TAKE_OFF
	_until_ms = now + fly_ms
	_flight_target = _flight_spot()
	collision_mask = 0
	velocity = Vector2.ZERO
	_play("fly-left" if _flight_target.x < global_position.x else "fly-right")


## A random spot of its circle for its body (feet) to fly to.
func _flight_spot() -> Vector2:
	if _home.is_empty():
		return global_position
	return Perimeter.random_point(_home) + (global_position - FeetAnchor.phaser_position(self))


## The spot of its circle farthest from `from`, of a few tries: where a scattering flier makes for.
func _far_spot(from: Node2D) -> Vector2:
	var best := _flight_spot()
	for i in SCATTER_TRIES - 1:
		var spot := _flight_spot()
		if spot.distance_squared_to(from.global_position) > best.distance_squared_to(from.global_position):
			best = spot
	return best


## Keeps its glow on its side of a mirrored picture, and over the darkness of a dark room.
func _show_glow() -> void:
	if glow == null:
		return
	glow.position.x = -_glow_x if visual.flip_h else _glow_x
	var dark := DarkRoom.is_dark_at(get_tree(), global_position)
	if dark == _glow_dark:
		return
	_glow_dark = dark
	glow.z_as_relative = not dark
	glow.z_index = GLOW_DARK_Z if dark else _glow_z


## How far (0..1) the current take-off or landing is.
func _share(now: float) -> float:
	return clampf(1.0 - (_until_ms - now) / maxf(1.0, fly_ms), 0.0, 1.0)


## Raises its picture `height` px over its feet; its shadow shrinks as it rises.
func _set_height(height: float) -> void:
	_height = height
	visual.position = Vector2(0.0, -height)
	if _shadow != null:
		var scale_share := lerpf(1.0, SHADOW_HIGH_SCALE, clampf(height / maxf(1.0, flight_height), 0.0, 1.0))
		_shadow.scale = Vector2(scale_share, scale_share)


func _settle() -> void:
	_mode = STATE_WANDER
	_state = NpcWanderPolicy.create_state(_random_pause(), str(_state.get("facing", "down")))
	_rest_clip = ""
	_play(_idle_clip())


## The next stop of its route (round and round), when it has one.
func _next_stop() -> void:
	if _leader != null or _route_points.size() < 2:
		return
	_route_index = (_route_index + 1) % _route_points.size()
	_domain = _circle(_route_points[_route_index], 0.0)


func _idle_clip() -> String:
	if not _rest_clip.is_empty():
		return _rest_clip
	var facing := str(_state.get("facing", "down"))
	if facing != "down" and animation != null and animation.has_animation(ANIM_IDLE + "-" + facing):
		return ANIM_IDLE + "-" + facing
	return ANIM_IDLE


## Its walk that way, or its side walk when it has no walk up or down (the birds' hop).
func _walk_clip(facing: String) -> String:
	var clip := "walk-" + facing
	if animation != null and not animation.has_animation(clip) and (facing == "up" or facing == "down"):
		clip = "walk-left" if velocity.x < 0.0 else "walk-right"
	return clip


func _read_route() -> PackedVector2Array:
	var path_node: Node = get_node_or_null(route) if not route.is_empty() else get_node_or_null(NodePath(ROUTE_CHILD))
	var path := path_node as Path2D
	var points := PackedVector2Array()
	if path == null or path.curve == null:
		return points
	for index in path.curve.point_count:
		points.append(path.to_global(path.curve.get_point_position(index)))
	return points


func _find_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
	return _player


func _random_pause() -> float:
	return pause_min_ms + randf() * maxf(0.0, pause_max_ms - pause_min_ms)


func _play(clip: String) -> void:
	if animation == null or animation.current_animation == clip or not animation.has_animation(clip):
		return
	animation.play(clip)


static func _facing_of(direction: Vector2) -> String:
	if absf(direction.x) >= absf(direction.y):
		return "left" if direction.x < 0.0 else "right"
	return "up" if direction.y < 0.0 else "down"


static func _circle(centre: Vector2, radius: float) -> Dictionary:
	return {"shape": Perimeter.SHAPE_CIRCLE, "x": centre.x, "y": centre.y, "radius": maxf(0.0, radius)}

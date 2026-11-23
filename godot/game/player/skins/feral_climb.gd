extends RefCounted
## The Feral skin's climb (docs/godot/SKINS.md "Feral"; Direction "The skins": Pearl 3's skin
## climbs walls with thick living roots and rocky handholds, claws showing; letting go drops the
## slime, and a fall costs nothing: owner, 2026-10-16, questions 68 and 86). Since 2026-11-12 it
## works as the push and pull of a heavy block (the owner: "with W it sticks to the wall and then
## you move with the arrows in the direction you want", so a mountain can carry many climbs): the
## held interact key clings, the movement keys move the slime over the wall, any way. Owned by
## player.gd, which starts it on an interact press (`try_begin`, or a climbable wall's `use` through
## `begin`) and lets it own the step while it holds (`step`).
##
## What is climbed is a **climbable surface** in WALL_GROUP: vines painted on a VineLayer
## (game/world/vines/vine_layer.gd) or a placed climbable wall (game/scripts/climb_wall.gd). Each
## answers, in the slime's feet (world):
## - `can_grab(feet, facing) -> bool`: the slime can take hold from there;
## - `climb_start(feet, facing) -> Vector2`: where on the surface it takes hold;
## - `climb_allows(feet) -> bool`: it may cling there;
## - `climb_exit(feet, way) -> Vector2`: pushing `way` at the surface's edge, where it stands when it
##   gets off there (a ledge above, the ground at the foot), or Vector2.INF;
## - `climb_landing(feet) -> Vector2`: where it lands when it lets go;
## and optionally `climb_depth(feet) -> float` (the depth it is drawn at there, when not its
## landing's), `climb_holds(feet) -> bool` (it clings at an end with nothing to stand on),
## `climb_lets_go(feet) -> bool` (feet there have left it: the slime falls), `on_grabbed()`,
## `on_held_at_end()`, `climb_left(feet)` (the climb ended there, not cancelled).
##
## - **Grab:** with the Feral skin on, an interact press where a surface's `can_grab` says so (its
##   foot facing up, its lip facing down). The slime's body stops colliding (the rock between the
##   levels), its art is drawn in front of the face (Elevation `set_flight` at its landing's depth),
##   claws show, and it glides onto the surface (`climb_start`).
## - **Cling and move:** while the interact key stays held the slime clings; the movement keys move
##   it at `skins.feral.climbSpeed` wherever the surface allows, sliding along its edges. It faces
##   the wall the whole climb, whichever way it moves: its back to the camera (the owner,
##   2026-11-12: "it should always face the wall while climbing"). Vines have no limit at their
##   sides (the owner, 2026-11-13): a slime moved off them there (`climb_lets_go`) falls, as from a
##   hit; a surface without it (a climbable wall) holds the slime on.
## - **Getting off:** pushing on past an edge with ground beyond (`climb_exit`: up over the rim, down
##   at the foot) it glides there, stands and takes that level (Elevation `track`); the surface's
##   `climb_left` follows (a climbable wall can lead out of the world).
## - **Let go** (the key released): the slime drops straight to its landing over
##   `skins.feral.dropMs` with a little hop and a landing squash, and takes that level. No damage.
##   Already standing by its landing, it just lets go.
## - **A catch** (the owner, 2026-11-12): the key pressed again while the slime drops takes hold of
##   the surface right where it is, when the surface allows a cling there (vines under it; a drop
##   past bare rock catches nothing). After a hit's drop the key must be let go and pressed again.
## - **An end with nothing to stand on** (climb_wall.gd `holds_at_top`: roots beside the Colossus's
##   climb spots): the slime clings there (`is_holding`) until it lets go or moves away; the
##   surface's `on_held_at_end` says why.
## - **The strike while clinging** (the plan's proposal, for the Colossus's claws; player.gd
##   `_climb_strike`): an attack press thrusts the slime's shape along the face, left or right
##   (`strike_side`); the slime holds still on the face while the strike runs.
## - A hit drops it (`drop`); a door or death ends it (`cancel`: the slime is put down at its landing).
##
## The body moves through player.gd's ArcadeMover step: this only sets its velocity.
##
## Owner: skins.

const Services := preload("res://game/shared/services.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const FeralClaws := preload("res://game/player/skins/feral_claws.gd")

const WALL_GROUP := &"climb_walls"
## Enemies a strike along the face turns toward (game/scripts/enemy.gd ENEMY_GROUP).
const ENEMY_GROUP := &"enemy"
const CUE_GRAB := &"GulpCatch"
const CUE_PULL := &"StairsStep"
const CUE_LAND := &"Land"
const CLAWS_NAME := "FeralClaws"
## A pull cue every this many px climbed.
const PULL_EVERY_PX := 48.0
## A glide ends this near its target: on it, to the eye and to the surface's own limits (a slime left
## a fraction of a px outside them could not move along the edge it took hold at).
const ARRIVE_PX := 0.05
## A let-go this near its landing just stands there (no fall).
const NEAR_LANDING_PX := 14.0
## Taking hold and getting off glide at this many times the climb's speed.
const GLIDE_SPEED := 1.6
## The way the slime looks on a wall: at it, its back to the camera (walls face the camera).
const FACING := Vector2.UP

var _player: Node
var _body: CharacterBody2D
var _wall: Node2D
var _active := false
var _falling := false
var _mask := 0
var _fall_from := Vector2.ZERO
var _fall_to := Vector2.ZERO
var _fall_started_ms := 0.0
## The interact key has been up during this fall: held again, it catches the surface.
var _fall_released := false
var _climbed_px := 0.0
var _next_pull_px := PULL_EVERY_PX
var _claws: Node2D
## Clinging at an end with nothing to stand on (the surface's `climb_holds`).
var _holding := false
## The way the last strike along the face went (RIGHT or LEFT).
var _last_side := Vector2.RIGHT
## Gliding to `_glide_to` (the slime's feet): onto the surface as it takes hold, or off it
## (`_leaving`) to where it stands. No key moves the slime meanwhile.
var _gliding := false
var _leaving := false
var _glide_to := Vector2.ZERO


func is_active() -> bool:
	return _active


func is_falling() -> bool:
	return _active and _falling


func wall() -> Node2D:
	return _wall if _active else null


## On an interact press: the climbable surface the slime can take hold of from where it stands,
## facing `facing` (the Feral skin on). True when a climb began.
func try_begin(player: Node, body: CharacterBody2D, facing: Vector2) -> bool:
	if _active or body == null or not SkinState.is_on(player, SkinState.FERAL):
		return false
	for node: Node in player.get_tree().get_nodes_in_group(WALL_GROUP):
		var climb_wall := node as Node2D
		if climb_wall == null or not climb_wall.is_visible_in_tree():
			continue
		if bool(climb_wall.call(&"can_grab", body.global_position, facing)):
			return begin(player, body, climb_wall, facing)
	return false


## Takes hold of `climb_wall` (a climbable wall's `use`, or `try_begin`). False without the Feral
## skin, or when a climb is on.
func begin(player: Node, body: CharacterBody2D, climb_wall: Node2D, facing: Vector2 = Vector2.ZERO) -> bool:
	if _active or body == null or climb_wall == null or not SkinState.is_on(player, SkinState.FERAL):
		return false
	_player = player
	_body = body
	_wall = climb_wall
	_active = true
	_falling = false
	_holding = false
	_leaving = false
	_climbed_px = 0.0
	_next_pull_px = PULL_EVERY_PX
	_mask = body.collision_mask
	body.collision_mask = 0
	body.velocity = Vector2.ZERO
	# Onto the surface from where the slime stands: from its lip it comes down over the rim.
	var feet := body.global_position
	_glide_to = climb_wall.call(&"climb_start", feet, facing)
	_gliding = feet.distance_to(_glide_to) > ARRIVE_PX
	_set_depth(_glide_to)
	player.call(&"face", FACING)
	player.call(&"squash", &"move-start", true)
	_show_claws(true)
	_cue(CUE_GRAB)
	SkinState.show(player, SkinState.FERAL)
	if climb_wall.has_method(&"on_grabbed"):
		climb_wall.call(&"on_grabbed")
	return true


## One physics step while it holds: `held` is the interact key, `direction` the movement keys.
## Returns true while the slime moves (for its walk clip).
func step(now_ms: float, delta: float, held: bool, direction: Vector2) -> bool:
	if not _active:
		return false
	if _body == null or not is_instance_valid(_body) or _wall == null or not is_instance_valid(_wall):
		_finish()
		return false
	SkinState.show(_player, SkinState.FERAL)
	if _falling:
		return _fall(now_ms, delta, held)
	# At the wall every step: a strike along the face turned the slime sideways.
	_player.call(&"face", FACING)
	var speed := SkinState.setting("feral.climbSpeed", 150.0)
	if _gliding:
		return _glide(delta, speed)
	# Vines going on past a chunk world's edge (vine_layer.gd `climb_crosses`): the climb goes on in the
	# world there; the slime holds still, the key's release by the travel not letting go, while it changes.
	if _wall.has_method(&"climb_crosses") \
			and bool(_wall.call(&"climb_crosses", _body.global_position, direction if held else Vector2.ZERO)):
		_body.velocity = Vector2.ZERO
		return false
	if not held:
		_let_go(now_ms, true)
		return false
	var feet := _body.global_position
	_set_depth(feet)
	if direction == Vector2.ZERO:
		_body.velocity = Vector2.ZERO
		_cling(feet)
		return false
	var way := direction.normalized()
	# Pushing on past an edge with ground beyond: off the wall, onto it.
	var off: Vector2 = _wall.call(&"climb_exit", feet, way)
	if off.is_finite():
		_gliding = true
		_leaving = true
		_glide_to = off
		return _glide(delta, speed)
	var move := way * speed * delta
	# Off the surface that way (vines have no limit at their sides: the owner, 2026-11-13): the slime
	# lets go there and falls, as from a hit (the key let go and pressed again catches).
	if _wall.has_method(&"climb_lets_go") and not bool(_wall.call(&"climb_allows", feet + move)) \
			and bool(_wall.call(&"climb_lets_go", feet + move)):
		_let_go(now_ms, false)
		return is_falling()
	# Wherever the surface allows, sliding along its edges.
	var next := feet
	for candidate: Vector2 in [move, Vector2(move.x, 0.0), Vector2(0.0, move.y)]:
		if candidate != Vector2.ZERO and bool(_wall.call(&"climb_allows", feet + candidate)):
			next = feet + candidate
			break
	if next == feet:
		_body.velocity = Vector2.ZERO
		_cling(feet)
		return false
	_holding = false
	_body.velocity = (next - feet) / maxf(delta, 0.0001)
	_climbed_px += feet.distance_to(next)
	if _climbed_px >= _next_pull_px:
		_next_pull_px += PULL_EVERY_PX
		_cue(CUE_PULL)
	return true


## A door, a teleport, death: the slime is put down at its landing at once.
func cancel() -> void:
	if not _active:
		return
	_active = false
	if _body != null and is_instance_valid(_body) and _player != null and is_instance_valid(_player):
		var land := _body.global_position
		if _wall != null and is_instance_valid(_wall):
			land = _wall.call(&"climb_landing", land)
		# player.gd `teleport` places the slime by its centre (it cancels nothing more: off already).
		var centre_to_feet: Vector2 = _body.global_position - (_player.call(&"get_centre") as Vector2)
		_player.call(&"teleport", land - centre_to_feet)
		_body.velocity = Vector2.ZERO
	_finish()


## A hit knocks the slime off the wall: it drops to its landing (no damage from the fall).
func drop(now_ms: float) -> void:
	if _active and not _falling and _body != null and is_instance_valid(_body):
		_let_go(now_ms, false)


## The key released (`released`) or a hit: the slime falls to its landing, or just stands when it
## is there.
func _let_go(now_ms: float, released: bool) -> void:
	var feet := _body.global_position
	var land: Vector2 = _wall.call(&"climb_landing", feet)
	_gliding = false
	_holding = false
	if feet.distance_to(land) <= NEAR_LANDING_PX:
		_body.velocity = Vector2.ZERO
		_leave(feet)
		return
	_falling = true
	_fall_released = released
	_fall_from = feet
	_fall_to = land
	_fall_started_ms = now_ms
	_set_depth(land)
	_show_claws(false)


func _fall(now_ms: float, delta: float, held: bool) -> bool:
	# A catch: the key down again takes hold where the slime is, where the surface allows a cling.
	if not held:
		_fall_released = true
	elif _fall_released and bool(_wall.call(&"climb_allows", _body.global_position)):
		_falling = false
		_body.velocity = Vector2.ZERO
		_set_depth(_body.global_position)
		_player.call(&"squash", &"move-start", true)
		_show_claws(true)
		_cue(CUE_GRAB)
		return false
	var length := maxf(1.0, SkinState.setting("feral.dropMs", 320.0))
	var t := clampf((now_ms - _fall_started_ms) / length, 0.0, 1.0)
	# Falling: it speeds up (ease-in), drifting off the face, with a little hop at the start.
	var eased := t * t
	var hop := sin(minf(t * 2.0, 1.0) * PI) * SkinState.setting("feral.dropHopPx", 10.0) * (1.0 - t)
	var target := _fall_from.lerp(_fall_to, eased) - Vector2(0.0, hop)
	_body.velocity = (target - _body.global_position) / maxf(delta, 0.0001)
	if t >= 1.0:
		_body.velocity = Vector2.ZERO
		_player.call(&"squash", &"land", true)
		_cue(CUE_LAND)
		_leave(_fall_to)
	return true


## Toward `_glide_to`, no key asked: onto the surface, or off it to where the slime stands.
func _glide(delta: float, speed: float) -> bool:
	var to := _glide_to - _body.global_position
	var distance := to.length()
	if distance <= ARRIVE_PX:
		_body.velocity = Vector2.ZERO
		_gliding = false
		if _leaving:
			_leave(_glide_to)
		return false
	_body.velocity = to / distance * minf(speed * GLIDE_SPEED, distance / maxf(delta, 0.0001))
	return true


## The slime clings where it is: at an end with nothing to stand on the surface says why, once each
## time it gets there (`on_held_at_end`).
func _cling(feet: Vector2) -> void:
	var holds := _wall.has_method(&"climb_holds") and bool(_wall.call(&"climb_holds", feet))
	if holds and not _holding and _wall.has_method(&"on_held_at_end"):
		_wall.call(&"on_held_at_end")
	_holding = holds


## True while the slime clings at an end with nothing to stand on (a wall that ends on the face).
func is_holding() -> bool:
	return _active and not _falling and _holding


## The slime holds still on the face this step (its strike runs: player.gd `_climb_strike`).
func hold_still() -> void:
	if _active and not _falling and _body != null and is_instance_valid(_body):
		_body.velocity = Vector2.ZERO
		SkinState.show(_player, SkinState.FERAL)


## The way a strike along the face goes (RIGHT or LEFT): the left or right movement key held
## (`direction`), else toward the nearest standing enemy within `skins.feral.strikeSeekPx` beside
## the slime, else the way the last one went.
func strike_side(player: Node, direction: Vector2) -> Vector2:
	if absf(direction.x) >= 0.3:
		_last_side = Vector2(signf(direction.x), 0.0)
		return _last_side
	var centre: Vector2 = player.call(&"get_centre")
	var seek := SkinState.setting("feral.strikeSeekPx", 240.0)
	var best := INF
	for node: Node in player.get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not node.has_method(&"get_centre") or (node.has_method(&"is_defeated") and bool(node.call(&"is_defeated"))):
			continue
		var offset: Vector2 = (node.call(&"get_centre") as Vector2) - centre
		if absf(offset.x) < 1.0 or offset.length() > seek or offset.length() >= best:
			continue
		best = offset.length()
		_last_side = Vector2(signf(offset.x), 0.0)
	return _last_side


## The climb ended at `feet` (the slime stands there): the surface hears of it (`climb_left`).
func _leave(feet: Vector2) -> void:
	var climb_wall := _wall
	_finish()
	if climb_wall != null and is_instance_valid(climb_wall) and climb_wall.has_method(&"climb_left"):
		climb_wall.call(&"climb_left", feet)


## Ends the climb: the mask back, the level where the feet are, the claws hidden.
func _finish() -> void:
	_active = false
	_falling = false
	_holding = false
	_gliding = false
	_leaving = false
	_show_claws(false)
	if _body != null and is_instance_valid(_body):
		_body.collision_mask = _mask
		var world := Services.world()
		if world != null and world.elevation != null:
			world.elevation.end_flight(_body)
			world.elevation.track(_body)
	_wall = null


## The slime's art is drawn in front of the face: at the depth the surface names for `feet`
## (`climb_depth`: its wall's foot, also over a balcony), else at that of where it would land.
func _set_depth(feet: Vector2) -> void:
	var world := Services.world()
	if world == null or world.elevation == null or _wall == null or not is_instance_valid(_wall):
		return
	var depth: float = float(_wall.call(&"climb_depth", feet)) if _wall.has_method(&"climb_depth") 		else (_wall.call(&"climb_landing", feet) as Vector2).y
	world.elevation.set_flight(_body, depth)


func _show_claws(on: bool) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	if _claws == null or not is_instance_valid(_claws):
		_claws = _body.get_node_or_null(CLAWS_NAME) as Node2D
	if _claws == null and on:
		_claws = FeralClaws.new()
		_claws.name = CLAWS_NAME
		_body.add_child(_claws)
	if _claws != null:
		_claws.call(&"set_shown", on)


static func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)

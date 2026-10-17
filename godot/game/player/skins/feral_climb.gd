extends RefCounted
## The Feral skin's climb (docs/godot/SKINS.md "Feral"; Direction "The skins": Pearl 3's skin
## climbs walls with thick living roots and rocky handholds while the interact key is held, claws
## showing; it climbs up and down; letting go midway drops the slime, and a fall costs nothing:
## owner, 2026-10-16, questions 68 and 86). Owned by player.gd, which starts it on an interact press
## (`try_begin`, or a climbable wall's `use` through `begin`) and lets it own the step while it holds
## (`step`).
##
## - **Grab:** with the Feral skin on, the slime's feet within a climbable wall's start zone
##   (game/scripts/climb_wall.gd `can_grab`: its foot, or its lip for a wall climbed down), facing
##   along the climb. The slime's body stops colliding (the rock between the levels), its art is drawn
##   in front of the face (Elevation `set_flight` at the lower end's depth), and claws show.
## - **Climb:** while the interact key stays held the slime climbs toward the wall's far end at
##   `skins.feral.climbSpeed`; the movement key the other way climbs it back. It faces the wall and
##   walks its clip (a back view going up, a front view going down).
## - **Top out:** at the far end it stands on the ground there and takes its level (Elevation
##   `track`); the wall's `on_climbed` follows (a wall can lead out of the world).
## - **Back at the start:** it lets go where it started.
## - **Let go midway** (the key released): the slime drops straight to the lower end over
##   `skins.feral.dropMs` with a little hop and a landing squash, and takes that level. No damage.
## - **A wall that ends on the face** (climb_wall.gd `holds_at_end`: roots beside the Colossus's climb
##   spots, a climb-out while the dungeon is sealed): at the far end the slime clings there, nothing
##   to top out onto, until it lets go or climbs back; the wall's `on_held_at_end` says why.
## - **The strike while clinging** (the plan's proposal, for the Colossus's claws; player.gd
##   `_climb_strike`): an attack press thrusts the slime's shape along the face, left or right
##   (`strike_side`); the slime holds still on the face while the strike runs.
## - A hit, a door or death ends it (`cancel`: the slime is put down at the lower end).
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
## The sway across the face while climbing (px, per px climbed).
const SWAY_PX := 2.5
const SWAY_WAVE := 0.06
const ARRIVE_PX := 1.5

var _player: Node
var _body: CharacterBody2D
var _wall: Node2D
var _active := false
var _falling := false
## The climb's line in the slime's feet positions (world).
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _mask := 0
var _fall_from := Vector2.ZERO
var _fall_started_ms := 0.0
var _climbed_px := 0.0
var _next_pull_px := PULL_EVERY_PX
var _claws: Node2D
## Clinging at the far end of a wall that ends on the face (`holds_at_end`).
var _holding := false
## The way the last strike along the face went (RIGHT or LEFT).
var _last_side := Vector2.RIGHT


func is_active() -> bool:
	return _active


func is_falling() -> bool:
	return _active and _falling


func wall() -> Node2D:
	return _wall if _active else null


## On an interact press: the climbable wall whose start zone holds the slime's feet and that it
## faces along the climb (the Feral skin on). True when a climb began.
func try_begin(player: Node, body: CharacterBody2D, facing: Vector2) -> bool:
	if _active or body == null or not SkinState.is_on(player, SkinState.FERAL):
		return false
	for node: Node in player.get_tree().get_nodes_in_group(WALL_GROUP):
		var climb_wall := node as Node2D
		if climb_wall == null or not climb_wall.is_visible_in_tree():
			continue
		if bool(climb_wall.call(&"can_grab", body.global_position, facing)):
			return begin(player, body, climb_wall)
	return false


## Starts climbing `climb_wall` (a climbable wall's `use`). False without the Feral skin, or when a
## climb is on.
func begin(player: Node, body: CharacterBody2D, climb_wall: Node2D) -> bool:
	if _active or body == null or climb_wall == null or not SkinState.is_on(player, SkinState.FERAL):
		return false
	_player = player
	_body = body
	_wall = climb_wall
	_active = true
	_falling = false
	_holding = false
	# Straight along the face from where the slime stands (its offset across the wall kept).
	_from = body.global_position
	var across := body.global_position.x - (climb_wall.call(&"start_feet") as Vector2).x
	_to = (climb_wall.call(&"end_feet", body) as Vector2) + Vector2(across, 0.0)
	_climbed_px = 0.0
	_next_pull_px = PULL_EVERY_PX
	_mask = body.collision_mask
	body.collision_mask = 0
	body.velocity = Vector2.ZERO
	var world := Services.world()
	if world != null and world.elevation != null:
		world.elevation.set_flight(body, maxf(_from.y, _to.y))
	player.call(&"face", _climb_facing())
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
		_finish(false)
		return false
	SkinState.show(_player, SkinState.FERAL)
	if _falling:
		return _fall(now_ms, delta)
	if not held:
		_let_go(now_ms)
		return false
	var along := _to - _from
	var length := along.length()
	if length <= ARRIVE_PX:
		if not _hold_at_end():
			_top_out()
		return false
	var unit := along / length
	var progress := clampf((_body.global_position - _from).dot(unit), 0.0, length)
	# Toward the far end, unless the movement key points back along the climb.
	var heading := 1.0
	if direction != Vector2.ZERO and direction.normalized().dot(unit) < -0.5:
		heading = -1.0
	var speed := SkinState.setting("feral.climbSpeed", 150.0)
	var goal := length if heading > 0.0 else 0.0
	var remaining := absf(goal - progress)
	if remaining <= ARRIVE_PX:
		if heading > 0.0:
			if not _hold_at_end():
				_top_out()
		else:
			_finish(true)
		return false
	_holding = false
	var step_px := minf(speed * delta, remaining)
	var next := progress + heading * step_px
	_climbed_px += step_px
	# On the line, swaying a little across it, hand over hand.
	var across := Vector2(-unit.y, unit.x) * sin(next * SWAY_WAVE) * SWAY_PX
	var target := _from + unit * next + across
	_body.velocity = (target - _body.global_position) / maxf(delta, 0.0001)
	_player.call(&"face", _climb_facing() * heading)
	if _climbed_px >= _next_pull_px:
		_next_pull_px += PULL_EVERY_PX
		_cue(CUE_PULL)
	return true


## A door, a teleport, death: the slime is put down at the lower end at once.
func cancel() -> void:
	if not _active:
		return
	_active = false
	if _body != null and is_instance_valid(_body) and _player != null and is_instance_valid(_player):
		# player.gd `teleport` places the slime by its centre (it cancels nothing more: off already).
		var centre_to_feet: Vector2 = _body.global_position - (_player.call(&"get_centre") as Vector2)
		_player.call(&"teleport", _lower_end() - centre_to_feet)
		_body.velocity = Vector2.ZERO
	_finish(false)


## A hit knocks the slime off the wall: it drops to the lower end (no damage from the fall).
func drop(now_ms: float) -> void:
	if _active and not _falling and _body != null and is_instance_valid(_body):
		_let_go(now_ms)


func _let_go(now_ms: float) -> void:
	_falling = true
	_fall_from = _body.global_position
	_fall_started_ms = now_ms
	_show_claws(false)


func _fall(now_ms: float, delta: float) -> bool:
	var land := _lower_end()
	var length := maxf(1.0, SkinState.setting("feral.dropMs", 320.0))
	var t := clampf((now_ms - _fall_started_ms) / length, 0.0, 1.0)
	# Falling: it speeds up (ease-in), drifting off the face, with a little hop at the start.
	var eased := t * t
	var hop := sin(minf(t * 2.0, 1.0) * PI) * SkinState.setting("feral.dropHopPx", 10.0) * (1.0 - t)
	var target := _fall_from.lerp(land, eased) - Vector2(0.0, hop)
	_body.velocity = (target - _body.global_position) / maxf(delta, 0.0001)
	if t >= 1.0:
		_body.velocity = Vector2.ZERO
		_player.call(&"squash", &"land", true)
		_cue(CUE_LAND)
		_finish(false)
	return true


## At the far end of a wall that ends on the face (climb_wall.gd `holds_at_end`): the slime clings
## there (the wall's `on_held_at_end` the first step of each arrival). False when the wall tops out.
func _hold_at_end() -> bool:
	if _wall == null or not is_instance_valid(_wall) or not _wall.has_method(&"holds_at_end"):
		return false
	if not bool(_wall.call(&"holds_at_end")):
		return false
	_body.velocity = Vector2.ZERO
	_player.call(&"face", _climb_facing())
	if not _holding:
		_holding = true
		if _wall.has_method(&"on_held_at_end"):
			_wall.call(&"on_held_at_end")
	return true


## True while the slime clings at the far end of a wall that ends on the face.
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


func _top_out() -> void:
	_body.velocity = Vector2.ZERO
	var climb_wall := _wall
	var end := _to
	_finish(false)
	if climb_wall != null and is_instance_valid(climb_wall) and climb_wall.has_method(&"on_climbed"):
		climb_wall.call(&"on_climbed", end)


## Ends the climb: the mask back, the level where the feet are, the claws hidden.
func _finish(_at_start: bool) -> void:
	_active = false
	_falling = false
	_holding = false
	_show_claws(false)
	if _body != null and is_instance_valid(_body):
		_body.collision_mask = _mask
		var world := Services.world()
		if world != null and world.elevation != null:
			world.elevation.end_flight(_body)
			world.elevation.track(_body)
	_wall = null


func _lower_end() -> Vector2:
	return _from if _from.y >= _to.y else _to


## The way the slime faces on the wall: up the face going up, down it going down.
func _climb_facing() -> Vector2:
	return Vector2.UP if _to.y < _from.y else Vector2.DOWN


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
		_claws.call(&"set_shown", on, _climb_facing())


static func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)

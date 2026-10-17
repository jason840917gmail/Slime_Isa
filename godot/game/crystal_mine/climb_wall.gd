extends Node2D
class_name ClimbWall
## A climbable wall, the Feral skin's lock (docs/godot/DUNGEONS.md "The Crystal Mine (built)"; the
## look book: thick, living, leafy roots beside rocky handholds on a cliff face; Pearl 3's skin,
## question 132: its first lock is the climb out of the Crystal Colossus's arena). A stand-in until
## the Feral skin's climbing is built (roadmap 7.8): this node stands at the wall's foot.
##
## - **With the Feral skin** (the story flag SKIN_FLAG, set by Pearl 3: game/scripts/pearl.gd
##   `skin_flag`) the interact key (W) climbs: the slime is held and carried up the face to `top`
##   (from this node, world units, its centre there) over `climb_ms`, clinging, and takes the level of
##   the ground there. With `exit_area_id` set the climb goes on out of the world instead (the
##   arena's way out to the Lookout): at the top the slime travels to that world's `exit_marker`.
## - **Without it** the wall is not offered; pushing up against it says `refusal_text` (the clarity
##   rule: a wrong tool is refused with a line), at most every REFUSAL_EVERY_MS.
## - A wall climbed down is a second ClimbWall on the ledge, its `top` the foot below.
##
## When roadmap 7.8 builds the skin's real climbing (hold W, claws, letting go drops the slime), this
## node's flag check is where the wall asks, and the walls keep their places and looks.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const USABLE_GROUP := &"usable"
const GROUP := &"climb_walls"
## The Feral skin's flag (Pearl 3, pearl.gd `skin_flag`).
const SKIN_FLAG := "skin.feral"
const MAIN_GROUP := &"world_main"
const CUE_CLIMB := &"StairsStep"
const CUE_HOLD := &"GulpCatch"
const REFUSAL_EVERY_MS := 2500.0
const TEXT_RISE := 90.0
const TEXT_MS := 2400.0
## How near (centre to this node) the slime must push up to hear the refusal.
const REFUSAL_RADIUS := 70.0
## The roots fill this share of their 256 px picture (the packer leaves a margin).
const ART_FILL := Vector2(0.86, 0.9)

## Where the climb ends, from this node (world units: the slime's centre there).
@export var top: Vector2 = Vector2(0, -192)
@export var climb_ms: float = 1100.0
@export var interact_radius: float = 80.0
@export var badge_rise: float = 64.0
@export var prompt: String = "Climb"
@export var refusal_text: String = "Too steep to climb."
## Climbing out of the world: the world to go to and the marker to arrive at ("" = stay here).
@export var exit_area_id: String = ""
@export var exit_marker: String = ""
## The roots' picture (`Visual`): how much of the face it covers (world units; zero: the scene's
## size), and whether it shows (a climb back down from a ledge shares the face's picture below).
@export var art_size: Vector2 = Vector2.ZERO
@export var show_art: bool = true

## The climb finished. Payload: {"top": Vector2, "exit": String}.
signal climbed(payload: Dictionary)

var _climbing := false
var _from := Vector2.ZERO
var _started_ms := 0.0
var _next_refusal_ms := 0.0
var _mask := 0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(USABLE_GROUP)


func _ready() -> void:
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual == null:
		return
	visual.visible = show_art
	if art_size != Vector2.ZERO and visual.texture != null:
		var picture := visual.texture.get_size() / Vector2(visual.hframes, visual.vframes)
		visual.scale = art_size / (picture * ART_FILL)


func origin() -> Vector2:
	return global_position


static func has_skin() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(SKIN_FLAG)


func can_use() -> bool:
	return has_skin() and not _climbing


func is_climbing() -> bool:
	return _climbing


## Climbs (the interact key). False without the skin.
func use() -> bool:
	if not can_use():
		return false
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return false
	_climbing = true
	# Nothing collides on the way up the face (the rock between the levels); the mask comes back and
	# the level is taken at the top.
	var climbing_body := player.get(&"body") as CharacterBody2D
	if climbing_body != null:
		_mask = climbing_body.collision_mask
		climbing_body.collision_mask = 0
	_from = player.call(&"get_centre")
	_started_ms = Services.now_ms()
	player.call(&"stop_movement")
	player.call(&"face", Vector2.UP if top.y < 0.0 else Vector2.DOWN)
	player.call(&"suppress_movement", climb_ms + 150.0)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HOLD)
	return true


func _physics_process(_delta: float) -> void:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	if _climbing:
		_climb_step(world, player)
		return
	if has_skin():
		return
	# The refusal: pushing up against the wall without the skin.
	var centre: Vector2 = player.call(&"get_centre")
	if centre.distance_to(global_position) > REFUSAL_RADIUS:
		return
	var intent: Vector2 = player.call(&"get_move_intent") if player.has_method(&"get_move_intent") else Vector2.ZERO
	if intent.y >= -0.3:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_refusal_ms:
		return
	_next_refusal_ms = now + REFUSAL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(&"HitBlocked")
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), refusal_text, &"white", false, TEXT_MS)


func _climb_step(world: Node, player: Node) -> void:
	var t := clampf((Services.now_ms() - _started_ms) / maxf(climb_ms, 1.0), 0.0, 1.0)
	# Hand over hand: three pulls, each eased, a little sway.
	var pulls := 3.0
	var eased := (floorf(t * pulls) + _ease(fmod(t * pulls, 1.0))) / pulls if t < 1.0 else 1.0
	var target := global_position + top
	var at := _from.lerp(target, eased) + Vector2(sin(t * TAU * pulls) * 3.0, 0.0)
	player.call(&"teleport", at)
	player.call(&"suppress_movement", 120.0)
	if fmod(t * pulls, 1.0) < 0.05 and t < 0.98:
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_CLIMB)
	if t < 1.0:
		return
	_climbing = false
	var body := player.get(&"body") as CharacterBody2D
	if body != null:
		body.collision_mask = _mask
	if world.elevation != null and body != null:
		world.elevation.track(body)
	climbed.emit({"top": target, "exit": exit_area_id})
	if not exit_area_id.is_empty():
		var main := get_tree().get_first_node_in_group(MAIN_GROUP)
		if main != null and main.has_method(&"travel_to"):
			main.call(&"travel_to", exit_area_id, "", "", exit_marker)


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

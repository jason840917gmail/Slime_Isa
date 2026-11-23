extends Node2D
class_name OreLiftLanding
## One landing of the Crystal Mine's ore lift (docs/godot/DUNGEONS.md "The Crystal Mine (built)"):
## the plank lift of the Great Shaft between its gallery (level 0, `role` "upper") and its floor
## (level -1, "lower"), the shortcut that puts the boss door a short walk from the entrance.
##
## - The lift waits **down**, its crank below: from the gallery it is not offered, and coming near the
##   upper landing says so ("The lift is down. Its crank is down there."), a one-way door's tell seen
##   from the wrong side.
## - On the shaft floor (reached by the Shardback's Den's ledge drop) the interact key (W) works the
##   crank and rides it up: the screen fades (MineTravel) and the slime steps off on the gallery.
##   From then on it runs both ways from either landing.
## - Where the platform stands is drawn (`platform_visual` of the landing that has it).
##
## State: the world's object states `ore-lift:<lift_id>` ("lower" or "upper", where the platform
## is) and `ore-lift:<lift_id>:working` (true once worked from below), so it lasts through a faint,
## a quit and a load.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const MineTravel := preload("res://game/crystal_mine/mine_travel.gd")

const USABLE_GROUP := &"usable"
const GROUP := &"ore_lift_landings"
const STATE_PREFIX := "ore-lift:"
const LOWER := "lower"
const UPPER := "upper"
## The ride's sound (Sound Picker round 13, 2026-11-21; it played the slime's SlamWindup before).
const CUE_RIDE := &"OreLiftRide"
const TEXT_RISE := 64.0
const TEXT_MS := 2600.0
const TELL_RADIUS := 100.0
const TELL_EVERY_MS := 4000.0

@export var lift_id: String = "great-shaft-lift"
@export_enum("lower", "upper") var role: String = "lower"
## Where the slime steps off here, from this node (world units, its centre).
@export var arrival: Vector2 = Vector2(0, 40)
@export var arrival_facing: Vector2 = Vector2.DOWN
@export var interact_radius: float = 96.0
@export var badge_rise: float = 72.0
@export var down_text: String = "The lift is down. Its crank is down there."
@export var platform_visual: Node2D

var prompt: String = "Ride the lift"
var _next_tell_ms: float = 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(USABLE_GROUP)


func _ready() -> void:
	prompt = "Work the crank: ride up" if role == LOWER else "Ride the lift down"
	_show()


func origin() -> Vector2:
	return global_position


## True once the crank was worked from below.
func is_working() -> bool:
	var run := Services.run()
	var world := Services.world()
	return run != null and world != null and bool(run.object_state(world.map_id(), STATE_PREFIX + lift_id + ":working", false))


## Where the platform stands: "lower" (the start) or "upper".
func platform_at() -> String:
	var run := Services.run()
	var world := Services.world()
	if run == null or world == null:
		return LOWER
	return str(run.object_state(world.map_id(), STATE_PREFIX + lift_id, LOWER))


func can_use() -> bool:
	return other() != null and (role == LOWER or is_working())


func other() -> OreLiftLanding:
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node != self and node is OreLiftLanding and (node as OreLiftLanding).lift_id == lift_id:
			return node as OreLiftLanding
	return null


## Rides the lift to the other landing. False when it cannot go.
func use() -> bool:
	var to := other()
	if to == null or not can_use():
		return false
	return MineTravel.warp(to.global_position + to.arrival, to.arrival_facing, CUE_RIDE, func() -> void: _arrived_at(to))


func _arrived_at(to: OreLiftLanding) -> void:
	var run := Services.run()
	var world := Services.world()
	if run != null and world != null:
		run.set_object_state(world.map_id(), STATE_PREFIX + lift_id + ":working", true)
		run.set_object_state(world.map_id(), STATE_PREFIX + lift_id, to.role)
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node is OreLiftLanding and (node as OreLiftLanding).lift_id == lift_id:
			(node as OreLiftLanding)._show()


func _show() -> void:
	if platform_visual != null:
		platform_visual.visible = platform_at() == role


func _physics_process(_delta: float) -> void:
	if role != UPPER or is_working():
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var centre: Vector2 = player.call(&"get_centre")
	if centre.distance_to(global_position) > TELL_RADIUS:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_tell_ms:
		return
	_next_tell_ms = now + TELL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), down_text, &"white", false, TEXT_MS)

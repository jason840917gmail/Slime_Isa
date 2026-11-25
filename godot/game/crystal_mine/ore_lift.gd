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
## **Between two worlds** (`partner_world`; the rebuilt Crystal Mine's rooms, 2026-11-25: the upper
## landing on M4's gallery, the lower on M14, the shaft's floor, each in its own room world): the other
## landing is in the world `partner_world`, and the ride travels there as a door does (main.gd
## `request_exit`, a fade), the slime coming out at the arrival point `partner_door` beside that landing
## (as the travel cart, mine_cart.gd). Both states are then kept under the dungeon's record id
## (DungeonState.record_map_id: `crystal-mine` for every room, as for the one-scene Mine it replaced), so
## both worlds read the same answer. A lift whose other world is not in scene_index.json does not ride.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const MineTravel := preload("res://game/crystal_mine/mine_travel.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const USABLE_GROUP := &"usable"
const GROUP := &"ore_lift_landings"
const WORLD_MAIN_GROUP := &"world_main"
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
## The other landing's world (a lift between two room worlds), and the arrival point there (a node
## with a DoorScript of that `door_id`). Empty: the other landing is in this world.
@export var partner_world: String = ""
@export var partner_door: String = ""

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
	return run != null and world != null and bool(run.object_state(_state_map(), STATE_PREFIX + lift_id + ":working", false))


## Where the platform stands: "lower" (the start) or "upper".
func platform_at() -> String:
	var run := Services.run()
	var world := Services.world()
	if run == null or world == null:
		return LOWER
	return str(run.object_state(_state_map(), STATE_PREFIX + lift_id, LOWER))


## The record the lift's states are kept under: the world's, or (a lift between worlds) the dungeon's.
func _state_map() -> String:
	if not partner_world.is_empty():
		return DungeonState.record_map_id(self)
	var world := Services.world()
	return world.map_id() if world != null else ""


func can_use() -> bool:
	if not partner_world.is_empty():
		return _partner_world_exists() and (role == LOWER or is_working())
	return other() != null and (role == LOWER or is_working())


func _partner_world_exists() -> bool:
	var world := Services.world()
	return world != null and not world.scene_path("world." + partner_world).is_empty()


func other() -> OreLiftLanding:
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node != self and node is OreLiftLanding and (node as OreLiftLanding).lift_id == lift_id:
			return node as OreLiftLanding
	return null


## Rides the lift to the other landing. False when it cannot go.
func use() -> bool:
	if not partner_world.is_empty():
		return _ride_to_other_world()
	var to := other()
	if to == null or not can_use():
		return false
	return MineTravel.warp(to.global_position + to.arrival, to.arrival_facing, CUE_RIDE, func() -> void: _arrived_at(to))


## The ride to the other world's landing (a door's travel, faded). False when it did not ride.
func _ride_to_other_world() -> bool:
	var run := Services.run()
	if run == null or not can_use():
		return false
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	if main == null or not main.has_method(&"request_exit"):
		return false
	var world := Services.world()
	var result: Dictionary = main.call(&"request_exit", {"map_id": world.map_id() if world != null else "",
		"exit_id": "ore-lift:" + lift_id + ":" + role, "target_area_id": partner_world, "entry": "",
		"target_door_id": partner_door, "entry_marker": "", "gate": {}, "transition": "fade", "door_side": "",
		"lead_ms": 0.0})
	if str(result.get("status", "")) != "queued":
		return false
	# worked once from below, it runs both ways; the platform goes with the slime
	run.set_object_state(_state_map(), STATE_PREFIX + lift_id + ":working", true)
	run.set_object_state(_state_map(), STATE_PREFIX + lift_id, UPPER if role == LOWER else LOWER)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_RIDE)
	_show()
	return true


func _arrived_at(to: OreLiftLanding) -> void:
	var run := Services.run()
	var world := Services.world()
	if run != null and world != null:
		run.set_object_state(_state_map(), STATE_PREFIX + lift_id + ":working", true)
		run.set_object_state(_state_map(), STATE_PREFIX + lift_id, to.role)
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

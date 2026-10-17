extends Node2D
class_name MineCartStation
## One station of the Crystal Mine's cart line (docs/godot/DUNGEONS.md "The Crystal Mine (built)";
## the design's "mine cart: the Chasm <-> the Mine Mouth"). The line has two stations with the same
## `line_id`; the cart stands at one of them. At the station that has it, the interact key (W) rides
## it: the slime climbs in, the screen fades (MineTravel), and it gets out at the other station,
## where the cart now stands. Found first at the Chasm (`starts_with_cart`), the ride is the first
## half's shortcut back to the entrance, and a Bow-less slime's quick way out to Burr and back in.
## At the empty station a line says where the cart is (the tell: rails that end at a buffer stop).
##
## Which station holds the cart is the world's object state `mine-cart:<line_id>` (RunState map
## record), so it lasts through a faint, a quit and a load.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const MineTravel := preload("res://game/crystal_mine/mine_travel.gd")

## interaction_controller.gd USABLE_GROUP.
const USABLE_GROUP := &"usable"
const GROUP := &"mine_cart_stations"
const STATE_PREFIX := "mine-cart:"
const CUE_RIDE := &"BreakWood"
const TEXT_RISE := 64.0
const TEXT_MS := 2600.0
## How near the slime must come to the empty station to read its line, and how often (real time).
const EMPTY_TELL_RADIUS := 110.0
const EMPTY_TELL_EVERY_MS := 4000.0

## The line both stations share.
@export var line_id: String = "crystal-mine-cart"
## This station's id on the line ("mouth", "chasm").
@export var station_id: String = ""
## True on the station where the cart stands at first (one per line).
@export var starts_with_cart: bool = false
## Where the slime gets out here, from this node (world units, its centre).
@export var arrival: Vector2 = Vector2(0, 72)
## The way the slime faces when it gets out here.
@export var arrival_facing: Vector2 = Vector2.DOWN
@export var interact_radius: float = 96.0
@export var badge_rise: float = 72.0
@export var prompt: String = "Ride the cart"
@export var empty_text: String = "The cart is at the far end of the line."
## The cart's picture (shown while it stands here).
@export var cart_visual: Node2D

var _next_tell_ms: float = 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(USABLE_GROUP)


func _ready() -> void:
	_show()


func origin() -> Vector2:
	return global_position


## True while the cart stands at this station.
func has_cart() -> bool:
	return holder() == station_id


## The station that holds the cart now.
func holder() -> String:
	var run := Services.run()
	var world := Services.world()
	var fallback := ""
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if str(node.get(&"line_id")) == line_id and bool(node.get(&"starts_with_cart")):
			fallback = str(node.get(&"station_id"))
	if run == null or world == null:
		return fallback
	return str(run.object_state(world.map_id(), STATE_PREFIX + line_id, fallback))


func can_use() -> bool:
	return has_cart() and partner() != null


## The other station of the line, or null.
func partner() -> MineCartStation:
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node != self and node is MineCartStation and (node as MineCartStation).line_id == line_id:
			return node as MineCartStation
	return null


## Rides the cart to the other station. False when the cart is not here.
func use() -> bool:
	var other := partner()
	if not has_cart() or other == null:
		return false
	var target := other.global_position + other.arrival
	return MineTravel.warp(target, other.arrival_facing, CUE_RIDE, func() -> void: _move_cart_to(other))


## Moves the cart to `other` at once (the ride's arrival; the tests).
func _move_cart_to(other: MineCartStation) -> void:
	var run := Services.run()
	var world := Services.world()
	if run != null and world != null:
		run.set_object_state(world.map_id(), STATE_PREFIX + line_id, other.station_id)
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node is MineCartStation and (node as MineCartStation).line_id == line_id:
			(node as MineCartStation)._show()


func _show() -> void:
	if cart_visual != null:
		cart_visual.visible = has_cart()


## The empty station's tell: the line, once per approach.
func _physics_process(_delta: float) -> void:
	if has_cart():
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var centre: Vector2 = player.call(&"get_centre")
	if centre.distance_to(global_position) > EMPTY_TELL_RADIUS:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_tell_ms:
		return
	_next_tell_ms = now + EMPTY_TELL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), empty_text, &"white", false, TEXT_MS)

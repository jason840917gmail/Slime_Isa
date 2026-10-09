extends Node
class_name EssenceScript
## Scene script `game.essence` (owner, 2026-10-08; GAME_GUIDELINES "Signature Mechanic: Gulp"). An
## essence lying on the ground: the slime sucks it in with Q (game/player/gulp/mouth.gd), or
## Interact puts it in the bag (game/interaction/interaction_controller.gd). Walking over it does
## nothing. A placed essence is part of its world scene, so it is back whenever the map is entered
## again; a spawned one (an enemy's drop, a popped or spat-out form) is not saved and, with a
## `fade_ms`, blinks and goes after that long of simulation time.
##
## The root is the essence's ground point; the `Visual` floats above it and bobs.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const GROUP := &"essence"
const SUCKABLE_GROUP := &"suckable"
## The object scene of each essence (scene_index.json).
const SCENE_PREFIX := "object.essence-"
## The bob: height in world px and period; the blink before a spawned essence fades.
const BOB_PX := 4.0
const BOB_PERIOD_S := 1.6
const BLINK_MS := 1500.0
const BLINK_PERIOD_MS := 160.0
## A spawned essence flies from where it came out to where it lands (a short hop).
const FLIGHT_S := 0.32
const FLIGHT_ARC_PX := 26.0

## The short essence id: "stone", "silk" or "swim" (game/player/gulp/gulp_forms.gd `essence`).
@export var essence: String = "stone"
## Simulation ms until a spawned essence fades; 0: it stays until taken.
@export var fade_ms: float = 0.0
## Interact reaches it from this far (the slime's centre to the root).
@export var interact_radius: float = 72.0

var _fade_at_ms: float = -1.0
var _landed: bool = true
var _bob_time: float = 0.0
var _visual_rest: Vector2 = Vector2.ZERO


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(SUCKABLE_GROUP)


func _ready() -> void:
	var visual := _visual()
	if visual != null:
		_visual_rest = visual.position
	_bob_time = randf() * BOB_PERIOD_S
	if fade_ms > 0.0:
		_fade_at_ms = Services.now_ms() + fade_ms


## Spawns essence `kind` ("stone") that flies from `from` to `at` (world points) and fades after
## `fade_ms` (0: never). Returns its script node, or null when the world cannot make it.
static func spawn(kind: String, at: Vector2, from: Vector2, fade: float) -> Node:
	var world := Services.world()
	var parent := world.entities_root() if world != null else null
	var root := world.instantiate_scene(SCENE_PREFIX + kind) as Node2D if world != null else null
	if root == null or parent == null:
		if root != null:
			root.free()
		return null
	var script_node: Node = root.get_node_or_null(^"EssenceScript")
	if script_node == null or not script_node.has_method(&"start_flight"):
		root.free()
		return null
	script_node.set(&"fade_ms", fade)
	root.position = parent.to_local(from)
	parent.add_child(root)
	script_node.call(&"start_flight", parent.to_local(at))
	return script_node


func _physics_process(delta: float) -> void:
	var visual := _visual()
	if visual != null:
		_bob_time += delta
		visual.position = _visual_rest - Vector2(0.0, BOB_PX * (0.5 + 0.5 * sin(_bob_time * TAU / BOB_PERIOD_S)))
	if _fade_at_ms < 0.0:
		return
	var left := _fade_at_ms - Services.now_ms()
	if left <= 0.0:
		_free_owner()
	elif left < BLINK_MS and visual != null:
		visual.visible = int(left / BLINK_PERIOD_MS) % 2 == 0


## The form this essence gives (game/player/gulp/gulp_forms.gd); {} when unknown.
func form() -> Dictionary:
	return GulpForms.for_essence(essence)


## The bag item it becomes (`stone-essence`).
func item_id() -> String:
	return str(form().get("essence_item", ""))


func display_name() -> String:
	return ItemCatalog.item_name(item_id())


## The ground point (the root).
func origin() -> Vector2:
	var root := get_parent() as Node2D
	return root.global_position if root != null else Vector2.ZERO


## What the mouth holds once this is sucked in.
func suck_info() -> Dictionary:
	return {"kind": "essence", "essence": essence}


## Only a landed essence can be sucked in or picked up.
func can_take() -> bool:
	return _landed and is_inside_tree() and not get_parent().is_queued_for_deletion()


## Sucked in or picked up: the essence leaves the world.
func take() -> void:
	_free_owner()


## Interact: into the bag. False when the bag is full.
func pick_up() -> bool:
	var run := Services.run()
	if run == null or not can_take():
		return false
	if run.add_item(item_id(), 1) <= 0:
		var feel := Services.feel()
		if feel != null:
			feel.floating_text(origin() - Vector2(0.0, 40.0), "Inventory full", &"white", true)
		return false
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(origin() - Vector2(0.0, 40.0), "+1 %s" % display_name(), &"yellow", false)
		feel.audio_cue(&"DropPop")
	take()
	return true


## A spawned essence's hop from where it came out to `target` (in its parent's space); it cannot be
## taken until it lands.
func start_flight(target: Vector2) -> void:
	_landed = false
	var root := get_parent() as Node2D
	var visual := _visual()
	if root == null or not root.is_inside_tree():
		_landed = true
		return
	var start := root.position
	var tween := root.create_tween()
	tween.tween_method(func(t: float) -> void:
		root.position = start.lerp(target, t)
		if visual != null:
			visual.position = _visual_rest - Vector2(0.0, 4.0 * FLIGHT_ARC_PX * t * (1.0 - t)), 0.0, 1.0, FLIGHT_S)
	tween.tween_callback(func() -> void: _landed = true)


func _visual() -> Node2D:
	var root := get_parent()
	return root.get_node_or_null(^"Visual") as Node2D if root != null else null


func _free_owner() -> void:
	var root := get_parent()
	if root != null and not root.is_queued_for_deletion():
		root.queue_free()

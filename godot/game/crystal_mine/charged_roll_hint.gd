extends Node2D
class_name ChargedRollHint
## The sign before the Crystal Caverns' first long run of falling slabs (roadmap 12.9: "the slime who
## reaches the maze without the Charged Roll is told what it lacks, near the maze's first long
## run"): while the slime stands near it without the `roll-charge` upgrade, it says so over the sign,
## once per approach. With the Charged Roll learned it says how to cross instead, once a visit.
##
## Owner: world (the Crystal Caverns).

const Services := preload("res://game/shared/services.gd")
const ROLL_CHARGE := "roll-charge"
const TEXT_RISE := 120.0
const TEXT_MS := 4200.0
const EVERY_MS := 6000.0

@export var radius: float = 150.0
@export var lacking_text: String = "No landing out there. Only a Roll that keeps rolling crosses: the Charged Roll, made from four Roll Fragments."
@export var ready_text: String = "Hold the Roll all the way across. No landing out there."

var _next_ms: float = 0.0
var _said_ready := false


func _physics_process(_delta: float) -> void:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var centre: Vector2 = player.call(&"get_centre")
	if centre.distance_to(global_position) > radius:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_ms:
		return
	_next_ms = now + EVERY_MS
	var run := Services.run()
	var has_charge := run != null and run.has_learned_ability(ROLL_CHARGE)
	if has_charge and _said_ready:
		return
	_said_ready = _said_ready or has_charge
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), ready_text if has_charge else lacking_text,
				&"white", false, TEXT_MS)

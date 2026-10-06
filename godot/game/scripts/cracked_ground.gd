extends Node
class_name CrackedGroundScript
## Scene script `game.cracked-ground` (Phaser `features/scripts/CrackedGroundScript.ts`;
## abilities spec 13.3). Weak ground a Heavy slime breaks by landing a jump on it (its centre
## within `radius` of the root at the landing), or by standing on it when `requires_landing` is
## off. Breaking sets the story flag for good (the story variant on the same flag swaps in the
## hole and its door), shakes the screen and says "The ground gives way!". A Heavy slime standing
## on it without jumping gets a hint (at most every 4 s for all cracked grounds).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const CRACK_TEXT := "The ground gives way!"
const CRACK_TEXT_RISE := 60.0
const CRACK_TEXT_MS := 1800.0
const CREAK_TEXT := "It creaks under you... jump on it! (Space)"
const CREAK_TEXT_RISE := 50.0
const CREAK_TEXT_MS := 2200.0
const CREAK_INTERVAL_MS := 4000.0
const CUE_CRACK := &"GroundCrack"
const CUE_CREAK := &"GroundCreak"

## JSON `flagId`.
@export var flag_id: String = ""
## JSON `radius`.
@export var radius: float = 48.0
## JSON `requiresLanding`: only a jump landing breaks it.
@export var requires_landing: bool = true

## The ground broke. Payload: {"flagId"}.
signal cracked(payload: Dictionary)

## One creak hint for every cracked ground (real time, like Phaser's scene time).
static var _next_creak_ms: float = 0.0

var _broken: bool = false
## The landing id seen when this ground first saw the player: older landings never count.
var _seen_landing: Variant = null


func _enter_tree() -> void:
	var run := Services.run()
	_broken = flag_id.is_empty() or (run != null and run.has_flag(flag_id))


func _ready() -> void:
	if not (is_finite(radius) and radius > 0.0):
		radius = 48.0


func is_broken() -> bool:
	return _broken


func _physics_process(_delta: float) -> void:
	if _broken:
		return
	var world := Services.world()
	var player = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var root := get_parent() as Node2D
	if root == null:
		return
	var landing: Dictionary = player.call(&"last_heavy_landing")
	var landing_id: Variant = landing.get("id")
	if _seen_landing == null:
		_seen_landing = landing_id if landing_id != null else 0
		return
	var heavy_here := bool(player.call(&"presses_plates")) \
		and (player.call(&"get_centre") as Vector2).distance_to(root.global_position) <= radius
	if requires_landing:
		if landing_id != null and landing_id != _seen_landing:
			_seen_landing = landing_id
			if Vector2(float(landing["x"]), float(landing["y"])).distance_to(root.global_position) <= radius:
				_crack(root.global_position)
				return
		if heavy_here:
			_creak(root.global_position)
		return
	if heavy_here:
		_crack(root.global_position)


func _crack(at: Vector2) -> void:
	_broken = true
	var run := Services.run()
	if run != null:
		run.set_flag(flag_id)
	var feel := Services.feel()
	if feel != null:
		feel.play(&"ground-crack")
		feel.audio_cue(CUE_CRACK)
		feel.floating_text(at - Vector2(0.0, CRACK_TEXT_RISE), CRACK_TEXT, &"yellow", true, CRACK_TEXT_MS)
	cracked.emit({"flagId": flag_id})


func _creak(at: Vector2) -> void:
	var now := float(Time.get_ticks_msec())
	if now < _next_creak_ms:
		return
	_next_creak_ms = now + CREAK_INTERVAL_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CREAK)
		feel.floating_text(at - Vector2(0.0, CREAK_TEXT_RISE), CREAK_TEXT, &"yellow", true, CREAK_TEXT_MS)

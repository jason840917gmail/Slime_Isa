extends Node
class_name CrackedGroundScript
## Scene script `game.cracked-ground` (Phaser `features/scripts/CrackedGroundScript.ts`;
## abilities spec 13.3). Weak ground a Heavy slime breaks with a Squash Slam on it (its centre
## within `radius` of the root at the impact), or by standing on it when `requires_impact` is off.
## The slam replaced Phaser's jump landing when the jump was removed (owner, 2026-10-08); a Heavy
## jump landing still counts, for the hidden jump's logic. Breaking sets the story flag for good
## (the story variant on the same flag swaps in the hole and its door), shakes the screen and says
## "The ground gives way!". A Heavy slime standing on it gets a hint (at most every 4 s for all
## cracked grounds), naming the slam and its key once the slam is learned. A Clod Stomper's slam
## next to it breaks it too (`break_open`, res://game/scripts/clod_stomper.gd).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const CRACK_TEXT := "The ground gives way!"
const CRACK_TEXT_RISE := 60.0
const CRACK_TEXT_MS := 1800.0
const CREAK_TEXT := "It creaks under you..."
## With the slam learned; "%s" is its key label.
const CREAK_SLAM_TEXT := "It creaks under you... slam it! (%s)"
const CREAK_TEXT_RISE := 50.0
const CREAK_TEXT_MS := 2200.0
const CREAK_INTERVAL_MS := 4000.0
const CUE_CRACK := &"GroundCrack"
const CUE_CREAK := &"GroundCreak"
## Every cracked ground, for the Clod Stomper's slam.
const GROUP := &"cracked_ground"

## JSON `flagId`.
@export var flag_id: String = ""
## JSON `radius`.
@export var radius: float = 48.0
## Phaser's JSON `requiresLanding`: only a Heavy impact (a Squash Slam) breaks it.
@export var requires_impact: bool = true

## The ground broke. Payload: {"flagId"}.
signal cracked(payload: Dictionary)

## One creak hint for every cracked ground (real time, like Phaser's scene time).
static var _next_creak_ms: float = 0.0

var _broken: bool = false
## The impact id seen when this ground first saw the player: older impacts never count.
var _seen_impact: Variant = null


func _enter_tree() -> void:
	add_to_group(GROUP)
	var run := Services.run()
	_broken = flag_id.is_empty() or (run != null and run.has_flag(flag_id))


func _ready() -> void:
	if not (is_finite(radius) and radius > 0.0):
		radius = 48.0


func is_broken() -> bool:
	return _broken


## Something heavy slammed next to it (a Clod Stomper): it gives way as under a Heavy slam.
func break_open() -> void:
	var root := get_parent() as Node2D
	if _broken or root == null:
		return
	_crack(root.global_position)


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
	var impact: Dictionary = player.call(&"last_heavy_impact")
	var impact_id: Variant = impact.get("id")
	if _seen_impact == null:
		_seen_impact = impact_id if impact_id != null else 0
		return
	var heavy_here := bool(player.call(&"presses_plates")) \
		and (player.call(&"get_centre") as Vector2).distance_to(root.global_position) <= radius
	if requires_impact:
		if impact_id != null and impact_id != _seen_impact:
			_seen_impact = impact_id
			if Vector2(float(impact["x"]), float(impact["y"])).distance_to(root.global_position) <= radius:
				_crack(root.global_position)
				return
		if heavy_here:
			_creak(root.global_position, bool(player.call(&"is_learned", AbilityDefinitions.SQUASH_SLAM)))
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


func _creak(at: Vector2, slam_learned: bool) -> void:
	var now := float(Time.get_ticks_msec())
	if now < _next_creak_ms:
		return
	_next_creak_ms = now + CREAK_INTERVAL_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CREAK)
		feel.floating_text(at - Vector2(0.0, CREAK_TEXT_RISE), creak_text(slam_learned), &"yellow", true, CREAK_TEXT_MS)


## The creak hint: the slam and its key once the slam is learned, else only the creak.
static func creak_text(slam_learned: bool) -> String:
	var key := ControlLabels.control_label(AbilityDefinitions.action(AbilityDefinitions.SQUASH_SLAM))
	if not slam_learned or key.is_empty():
		return CREAK_TEXT
	return CREAK_SLAM_TEXT % key

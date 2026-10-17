extends Node
class_name CrackedGroundScript
## Scene script `game.cracked-ground` (Phaser `features/scripts/CrackedGroundScript.ts`;
## abilities spec 13.3). Weak ground that gives way:
## - **A Goo Bomb blast** (roadmap 7.10, built 2026-10-17): a blast whose ellipse holds the root
##   (group `blast_targets`, `receive_blast`; game/player/abilities/goo_blast.gd) breaks it.
## - **A Heavy slime's Squash Slam** on it (its centre within `radius` of the root at the impact),
##   or standing on it when `requires_impact` is off. The slam replaced Phaser's jump landing when
##   the jump was removed (owner, 2026-10-08); a Heavy jump landing still counts, for the hidden
##   jump's logic.
## - **A Clod Stomper's slam** next to it (`break_open`, res://game/scripts/clod_stomper.gd).
## Breaking sets the story flag for good (the story variant on the same flag swaps in the hole and
## its door: a ladder down in `object.cracked-ground`, a one-way fall in `object.cracked-floor`,
## res://game/scripts/cracked_floor.gd), shakes the screen, says "The ground gives way!" and plays
## the secret jingle (`SecretFound`). A slime standing on it gets a creak hint (at most every 4 s
## for all cracked grounds): any slime once the Goo Bomb is learned, naming a blast and its key;
## else only a Heavy one, naming the slam and its key once the slam is learned.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
## The Slam's key (in the body-shapes rework mode the box's `ability_use`).
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")

const CRACK_TEXT := "The ground gives way!"
const CRACK_TEXT_RISE := 60.0
const CRACK_TEXT_MS := 1800.0
const CREAK_TEXT := "It creaks under you..."
## With the slam learned; "%s" is its key label.
const CREAK_SLAM_TEXT := "It creaks under you... slam it! (%s)"
## In the rework mode while another box ability is chosen; the bag key, then the use key.
const CREAK_CHOOSE_TEXT := "It creaks under you... choose the Slam in the bag (%s), then press %s"
## With the Goo Bomb learned: "%s" is its key label (without one, the line ends at "it!").
const CREAK_BLAST_TEXT := "It creaks under you... a blast would break it! (%s)"
const CREAK_BLAST_PLAIN := "It creaks under you... a blast would break it!"
## The bomb learned, another box ability chosen: the bag key, then the use key.
const CREAK_CHOOSE_BOMB_TEXT := "It creaks under you... choose the Goo Bomb in the bag (%s), then press %s"
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
	add_to_group(BlastBarrier.GROUP)
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


## Where a Goo Bomb blast's ellipse must reach (goo_blast.gd): the root, the middle of the patch.
func blast_point() -> Vector2:
	var root := get_parent() as Node2D
	return root.global_position if root != null else Vector2.INF


## A Goo Bomb blast (game/player/abilities/goo_blast.gd) reached it: it gives way for good.
func receive_blast(_hit: Dictionary) -> bool:
	var root := get_parent() as Node2D
	if _broken or root == null:
		return false
	_crack(root.global_position)
	return true


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
	var on_it := (player.call(&"get_centre") as Vector2).distance_to(root.global_position) <= radius
	var heavy_here := on_it and bool(player.call(&"presses_plates"))
	var bomb_learned := bool(player.call(&"is_learned", AbilityDefinitions.GOO_BOMBS))
	if requires_impact:
		if impact_id != null and impact_id != _seen_impact:
			_seen_impact = impact_id
			if Vector2(float(impact["x"]), float(impact["y"])).distance_to(root.global_position) <= radius:
				_crack(root.global_position)
				return
		# The bomb breaks it whatever the slime weighs, so once it is learned any slime hears it.
		if heavy_here or (on_it and bomb_learned):
			_creak(root.global_position, bool(player.call(&"is_learned", AbilityDefinitions.SQUASH_SLAM)), player,
				bomb_learned)
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
		var audio: Node = feel.global_audio()
		var found := audio != null and audio.find_child(String(BlastBarrier.CUE_SECRET), true, false) != null
		feel.audio_cue(BlastBarrier.CUE_SECRET if found else BlastBarrier.SECRET_FALLBACK_CUE)
	cracked.emit({"flagId": flag_id})


func _creak(at: Vector2, slam_learned: bool, player: Node, bomb_learned: bool = false) -> void:
	var now := float(Time.get_ticks_msec())
	if now < _next_creak_ms:
		return
	_next_creak_ms = now + CREAK_INTERVAL_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CREAK)
		feel.floating_text(at - Vector2(0.0, CREAK_TEXT_RISE), creak_text(slam_learned, player, bomb_learned), &"yellow",
			true, CREAK_TEXT_MS)


## The creak hint. With the Goo Bomb learned (`bomb_learned`): a blast and its key; in the
## body-shapes rework mode, while another box ability is chosen (on `player`'s box), it says to
## choose the Goo Bomb in the bag first. Else the slam and its key once the slam is learned (the same
## bag rule), else only the creak.
static func creak_text(slam_learned: bool, player: Node = null, bomb_learned: bool = false) -> String:
	if bomb_learned:
		var bomb_key := ControlLabels.control_label(AbilityBox.key_action(AbilityDefinitions.GOO_BOMBS))
		if bomb_key.is_empty():
			return CREAK_BLAST_PLAIN
		if ReworkMode.is_on() and AbilityBox.selected(player) != AbilityDefinitions.GOO_BOMBS:
			return CREAK_CHOOSE_BOMB_TEXT % [ControlLabels.control_label(&"menu"), bomb_key]
		return CREAK_BLAST_TEXT % bomb_key
	var key := ControlLabels.control_label(AbilityBox.key_action(AbilityDefinitions.SQUASH_SLAM))
	if not slam_learned or key.is_empty():
		return CREAK_TEXT
	if ReworkMode.is_on() and AbilityBox.selected(player) != AbilityDefinitions.SQUASH_SLAM:
		return CREAK_CHOOSE_TEXT % [ControlLabels.control_label(&"menu"), key]
	return CREAK_SLAM_TEXT % key

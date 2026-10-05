extends Node
class_name NpcScript
## Scene script `game.npc` (Phaser `features/scripts/NpcScript.ts` + `features/npcs/NpcWanderPolicy.ts`):
## villagers wandering inside their npc-wander area. World spec section 5.
##
## Lifecycle: `_ready` adds the NPC to groups "npc" and "interactable" and plays "idle". Until
## main.gd calls `configure_wander()` the NPC has no agent and idles forever (world spec 5.3).
## This script is the only caller of `body.move_and_slide()` for its body.
## Coordinates: wander targets and domains are old Phaser root positions (sprite bottom), see
## FeetAnchor; velocity is identical in both spaces.
##
## Owner: world builder.

const NpcWanderPolicy := preload("res://game/world/npc_wander_policy.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

## Wander body bounds relative to the old root, from `content/characters/<id>/character.json`
## `body` (not converted; world spec 5.1): Rect2(minX, minY, width, height).
## village-elder-plop ellipse 34x24 offset (0,10); the other five 36x24 offset (0,10).
const CHARACTER_BODY_BOUNDS := {
	"village-elder-plop": Rect2(-17.0, -2.0, 34.0, 24.0),
	"lili": Rect2(-18.0, -2.0, 36.0, 24.0),
	"red-slime-boy": Rect2(-18.0, -2.0, 36.0, 24.0),
	"yellow-blond-slime-girl": Rect2(-18.0, -2.0, 36.0, 24.0),
	"mossy-scout": Rect2(-18.0, -2.0, 36.0, 24.0),
	"fisherman-slime": Rect2(-18.0, -2.0, 36.0, 24.0),
}
const GROUP_NPC := &"npc"
const GROUP_INTERACTABLE := &"interactable"
const ANIM_IDLE := "idle"
## Authored child names used when a node export did not resolve (converter node_paths, C1).
const VISUAL_NAME := "Visual"
const ANIMATION_NAME := "Animation"

## JSON `body`: the CharacterBody2D root.
@export var body: CharacterBody2D
## JSON `visual`: the Sprite2D.
@export var visual: Sprite2D
## JSON `animation`: the AnimationPlayer (clips idle, walk-down, walk-up, walk-left, walk-right).
@export var animation: AnimationPlayer
## JSON `characterId` (e.g. "village-elder-plop"); default "npc".
@export var character_id: String = "npc"
## JSON `npcDefinitionId`; "" means use character_id.
@export var npc_definition_id: String = ""
## JSON `wanderSpeed` px/s; sanitized to max(0, v).
@export var wander_speed: float = 0.0
## JSON `pauseMinMs`; sanitized to max(0, v).
@export var pause_min_ms: float = 0.0
## JSON `pauseMaxMs`; sanitized to max(pause_min_ms, v).
@export var pause_max_ms: float = 0.0

## Emitted when an interaction lock is taken or released. Payload: {"locked": bool, "lockCount": int}.
signal interaction_lock_changed(payload: Dictionary)

var _has_agent: bool = false
var _domain: Dictionary = {}
var _state: Dictionary = {}
var _simulation_paused: bool = false
var _interaction_locks: int = 0


## Resolve refs, sanitize the exports, add to groups "npc" and "interactable", play "idle".
func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody2D
	if body == null:
		push_error("NpcScript %s: no CharacterBody2D body" % get_path())
		set_physics_process(false)
		return
	if visual == null:
		visual = body.get_node_or_null(NodePath(VISUAL_NAME)) as Sprite2D
	if animation == null:
		animation = body.get_node_or_null(NodePath(ANIMATION_NAME)) as AnimationPlayer
	if npc_definition_id.is_empty():
		npc_definition_id = character_id
	wander_speed = maxf(0.0, wander_speed) if is_finite(wander_speed) else 0.0
	pause_min_ms = maxf(0.0, pause_min_ms) if is_finite(pause_min_ms) else 0.0
	pause_max_ms = maxf(pause_min_ms, pause_max_ms) if is_finite(pause_max_ms) else pause_min_ms
	add_to_group(GROUP_NPC)
	add_to_group(GROUP_INTERACTABLE)
	_play(ANIM_IDLE)


## World spec 5.5: if paused or no agent -> velocity 0, "idle"; else step the wander policy from
## the old root position with `delta * 1000` and `wander_speed`, write `body.velocity`, play the
## returned clip, then on an arrival/stuck/no-domain pause start a fresh random pause
## (world spec 5.3). Always ends with `body.move_and_slide()`.
func _physics_process(delta: float) -> void:
	if body == null:
		return
	if _is_paused() or not _has_agent:
		body.velocity = Vector2.ZERO
		_play(ANIM_IDLE)
	else:
		var result := NpcWanderPolicy.step(_state, get_phaser_position(), delta * 1000.0, wander_speed, _domain)
		var next_state: Dictionary = result["state"]
		var clip: String = result["animation"]
		if clip == ANIM_IDLE and next_state["phase"] == NpcWanderPolicy.PHASE_PAUSE \
				and float(next_state["pause_remaining_ms"]) == 0.0:
			next_state = NpcWanderPolicy.create_state(random_pause(), next_state["facing"])
		_state = next_state
		body.velocity = result["velocity"]
		_play(clip)
	body.move_and_slide()


## Velocity 0 when leaving the tree.
func _exit_tree() -> void:
	if body != null:
		body.velocity = Vector2.ZERO


## Gives the NPC its wander agent from its npc-wander area perimeter (WorldService
## npc_wander_area(...)["perimeter"]); {} = no agent (idle forever). Computes the wander domain
## with NpcWanderPolicy.wander_domain(perimeter, body bounds) and starts with
## `create_state(random_pause())`.
## An area whose domain is empty still makes an agent: it idles through random pauses, as in
## Phaser (sampling fails -> pause 0 -> fresh random pause).
func configure_wander(perimeter: Dictionary) -> void:
	if perimeter.is_empty():
		_has_agent = false
		_domain = {}
		_state = {}
		return
	var bounds: Rect2 = Rect2()
	if CHARACTER_BODY_BOUNDS.has(character_id):
		bounds = CHARACTER_BODY_BOUNDS[character_id]
	else:
		push_warning("NpcScript: no wander body bounds for character '%s'; using a point body" % character_id)
	_domain = NpcWanderPolicy.wander_domain(perimeter, bounds)
	_state = NpcWanderPolicy.create_state(random_pause())
	_has_agent = true


## The authored instance id used to match `data.npcInstanceId`: the body's
## `metadata/instance_id`, falling back to the body's node name.
func get_instance_id_key() -> String:
	var root: Node = body if body != null else get_parent()
	if root == null:
		return ""
	if root.has_meta(&"instance_id"):
		return str(root.get_meta(&"instance_id"))
	return String(root.name)


## Old Phaser root position of the NPC (FeetAnchor.phaser_position(body)).
func get_phaser_position() -> Vector2:
	return FeetAnchor.phaser_position(body)


## Modal pause hook (OUT in the trial): paused NPCs stop and idle.
func set_simulation_paused(paused: bool) -> void:
	_simulation_paused = paused
	if _is_paused() and body != null:
		body.velocity = Vector2.ZERO


## Dialogue hook (OUT in the trial): increments the lock count, stops, idles, emits
## `interaction_lock_changed`; the returned Callable releases the lock once.
func acquire_interaction_lock() -> Callable:
	_interaction_locks += 1
	if body != null:
		body.velocity = Vector2.ZERO
	_play(ANIM_IDLE)
	_emit_lock_changed()
	var released := [false]
	return func() -> void:
		if released[0]:
			return
		released[0] = true
		_interaction_locks = maxi(0, _interaction_locks - 1)
		_emit_lock_changed()


## True while a dialogue holds the NPC.
func is_interaction_locked() -> bool:
	return _interaction_locks > 0


## `pause_min_ms + randf() * max(0, pause_max_ms - pause_min_ms)`.
func random_pause() -> float:
	return pause_min_ms + randf() * maxf(0.0, pause_max_ms - pause_min_ms)


func _is_paused() -> bool:
	return _simulation_paused or _interaction_locks > 0


func _emit_lock_changed() -> void:
	interaction_lock_changed.emit({"locked": _interaction_locks > 0, "lockCount": _interaction_locks})


## `NpcScript.play` (NpcScript.ts:171-178): skip the current clip and unknown clips.
func _play(clip: String) -> void:
	if animation == null:
		return
	if animation.current_animation == clip:
		return
	if not animation.has_animation(clip):
		return
	animation.play(clip)

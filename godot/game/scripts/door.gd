extends Node
class_name DoorScript
## Scene script `game.door` (Phaser `features/scripts/DoorScript.ts`; interaction spec 3.2, 6.1).
## `use()` asks main.gd to travel to `target_area_id`, arriving at `target_door_id`'s arrival point
## there (the door's parent's child named "arrival", else the parent; game/world/area_travel.gd snaps
## it to a tile centre).
##
## **No keys for transitions (owner, 2026-10-14; docs/godot/CONVENTIONS.md "Doors"):** a door is
## never offered to the interact key. The slime goes through by pushing into it, as through a map
## edge in Zelda: its collision rect touches the door's trigger (`walk_area`, else `trigger_rect`
## around the door's parent) while its movement input points into the door for
## `worldNavigation.doorPushMs` of simulation time. "Into the door" is the door's `side` (a north door
## = up; the input's direction within `doorPushAlignment` of it), or for a door without a side
## (a hole, a ladder's foot) toward the trigger's middle from the slime's centre (within
## `holePushAlignment`); in a hole (`is_hole`) any walking counts once the slime's centre is over
## the trigger. A locked door (`gate`, the world exit's lock) refuses with its line once per
## push; with the key the push unlocks it (the key is spent as authored, `GateUnlock` plays) and goes
## through.
##
## Going through plays a lead-in before the iris closes (main.gd `travel_to` waits `lead_ms`, the
## slime frozen), by `kind`:
## - "door": a real door. The leaf swings open over `doorOpenMs` (game/world/door_leaf.gd, built
##   over the house's art: `house_art`, `door_rect`, `door_arch`, `hinge`, `double_leaf`; or a
##   separate leaf picture, `leaf_art_path`), `open_cue` plays. Arriving through it the leaf stands
##   open while the slime walks out, then closes behind it over `doorCloseMs` with `close_cue`. An
##   interior's way out has its own door picture as `house_art` (a Sprite2D in the room). Without
##   leaf art only the cues play and there is no lead-in.
## - "opening": a gap, a cave mouth, a hole in a wall: no lead-in, `use_cue`.
## - "ladder_down": a hole with a ladder: the slime slides to the hole's middle, sinking and shrinking
##   into it over `ladderClimbMs` (`use_cue`).
## - "ladder_up": a ladder's foot: the slime climbs a little up the ladder, fading, over
##   `ladderClimbMs`.
## - "fall": a hole without a ladder into another scene: the slime spins and shrinks into the hole's
##   middle over `holeFallMs` with `fall_cue` (Zelda). Plain pits (elevation holes) are not doors.
##
## Door pairing (owner, 2026-10-14): `side` is the wall the door is in, the way the slime walks to go
## through it. A north door leads to the next scene's south door and back, east pairs with west.
## Arriving at a door with a side the slime stands `arrival_step` inside it facing away from the wall
## (an "arrival" child still wins for the spot); then main.gd moves it into the doorway and it walks
## out (game/player/door_walk_out.gd). A door without a side arrives the old way (the "arrival" child,
## else the parent) and keeps the slime's facing. Travelling through a door plays the iris
## (game/world/iris_transition.gd). A door waits `worldNavigation.edgeTransitionGraceMs` after it
## enters the tree, and never travels while the slime walks out of a door.
##
## Owner: interaction.

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const Services := preload("res://game/shared/services.gd")
const DoorLeaf := preload("res://game/world/door_leaf.gd")

## Contract of game/world/area_travel.gd: doors are found by `door_id` in this group.
const GROUP := &"door"
const MAIN_GROUP := &"world_main"
const SIDES: PackedStringArray = ["north", "south", "east", "west"]
const KINDS: PackedStringArray = ["door", "opening", "ladder_down", "ladder_up", "fall"]
const CUE_GATE_UNLOCK := &"GateUnlock"
const DEFAULT_UNLOCKED_TEXT := "The door unlocks!"
## Played when a door's own cue has no take in the global audio scene yet.
const FALLBACK_CUE := &"DoorUse"
## Closer than this to the trigger's middle, any input counts as pushing into a door without a side.
const CENTRE_SLACK_PX := 4.0
## Turns of the slime falling into a hole.
const FALL_TURNS := 1.5
## How far the slime's art climbs up a ladder (world units) and how small it gets in a hole.
const CLIMB_RISE_PX := 22.0
const SINK_SCALE := 0.35
const SINK_DEPTH_PX := 10.0

## JSON `mapId`.
@export var map_id: String = ""
## JSON `doorId`.
@export var door_id: String = ""
## JSON `targetAreaId`.
@export var target_area_id: String = ""
## JSON `targetDoorId`.
@export var target_door_id: String = ""
## What the door is (see the class notes): its lead-in and look.
@export_enum("door", "opening", "ladder_down", "ladder_up", "fall") var kind: String = "opening"
## The wall the door is in = the way through it ("north": push up into it). "none" = no side (holes,
## ladders: pushed toward the trigger's middle, the "arrival" child, no facing). Its target door
## should be on the opposite side.
@export_enum("none", "north", "south", "east", "west") var side: String = "none"
## The doorway the slime's body must touch, relative to the door's parent (world units); unused
## with a `walk_area`.
@export var trigger_rect: Rect2 = Rect2(-16.0, -20.0, 32.0, 40.0)
## Optional doorway trigger instead of `trigger_rect`: an Area2D (layer trigger, mask player).
@export var walk_area: Area2D
## How far inside a sided door the slime arrives (world units, from the door's parent, away from
## its wall). < 0 = game-constants `worldNavigation.doorArrivalStep`.
@export var arrival_step: float = -1.0
## The global audio cue played going through (not a real door: those play `open_cue`).
@export var use_cue: StringName = &"DoorUse"
@export_group("Door leaf")
## The house sprite the door is painted into (its texture under `door_rect` becomes the leaf).
@export var house_art: Sprite2D
## The painted door, relative to the door's parent (world units).
@export var door_rect: Rect2 = Rect2()
## The arch at the top of `door_rect` (world units; 0 = square).
@export var door_arch: float = 0.0
@export_enum("left", "right") var hinge: String = "left"
## Two leaves meeting in the middle of `door_rect`, hinged on its left and right edges (`hinge`
## unused): the interior timber doors.
@export var double_leaf: bool = false
## Optional separate leaf picture (res:// path) drawn over `door_rect`, closed too (the level-1
## mushroom house: a picture laid over its painted door). Missing or not imported yet (read from the
## file then): only the dark doorway opens.
@export var leaf_art_path: String = ""
@export var open_cue: StringName = &"DoorOpen"
@export var close_cue: StringName = &"DoorClose"
@export var fall_cue: StringName = &"FallDown"
@export_group("Lock")
## A locked door: {"id", "requiredItemId", "consumeOnUnlock", "lockedMessage", "unlockedMessage"?}
## (camelCase, as a world exit's `gate`; without "unlockedMessage" the push that unlocks it says
## `DEFAULT_UNLOCKED_TEXT`). Empty = not locked.
@export var gate: Dictionary = {}

var _simulation_ms: float = 0.0
var _grace_ms: float = 0.0
var _used: bool = false
var _push_ms: float = 0.0
var _refused: bool = false
var _leaf: DoorLeaf
var _leaf_tween: Tween
## Arrived through this door: close the leaf once the slime has walked out.
var _close_pending: bool = false


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_simulation_ms = 0.0
	_used = false
	_push_ms = 0.0
	_grace_ms = _number("edgeTransitionGraceMs", 0.0)
	if not kind in KINDS:
		kind = "opening"
	_build_leaf.call_deferred()


func _physics_process(delta: float) -> void:
	_simulation_ms += delta * 1000.0
	var world := Services.world()
	if world == null or world.player_body == null:
		return
	var player: Node = world.get(&"player")
	if player == null:
		return
	var walking_out := player.has_method(&"is_walking_out") and bool(player.call(&"is_walking_out"))
	if _close_pending and not walking_out and not _player_frozen(player):
		_close_pending = false
		_swing(0.0, _number("doorCloseMs", 250.0))
		_cue(close_cue)
	if _used or _simulation_ms < _grace_ms or walking_out:
		_push_ms = 0.0
		return
	if not is_pushing(player, world.player_body):
		_push_ms = 0.0
		_refused = false
		return
	_push_ms += delta * 1000.0
	if _push_ms < _number("doorPushMs", 200.0) or _refused:
		return
	if map_id.is_empty():
		map_id = world.map_id()
	var status := str(use().get("status", ""))
	_used = status == "queued"
	# A refusal (a locked door) speaks once per push: let go and push again to hear it again.
	_refused = not _used


## True while the player's body touches this door's trigger and its movement input points into the
## door (see the class notes).
func is_pushing(player: Node, player_body: CharacterBody2D) -> bool:
	if player == null or player_body == null or not player.has_method(&"get_move_intent"):
		return false
	var intent: Vector2 = player.call(&"get_move_intent")
	if intent == Vector2.ZERO or not touches(player_body):
		return false
	intent = intent.normalized()
	if has_side():
		return intent.dot(-inward()) >= _number("doorPushAlignment", 0.7)
	var trigger := trigger_global()
	var body_centre := _body_rect(player_body).get_center()
	var to_middle := trigger.get_center() - body_centre
	# In a hole, walking on whichever way counts (it walked in).
	if to_middle.length() <= CENTRE_SLACK_PX or (is_hole() and trigger.has_point(body_centre)):
		return true
	return intent.dot(to_middle.normalized()) >= _number("holePushAlignment", 0.35)


## True when `player_body` touches the doorway (its `walk_area`, else `trigger_rect`).
func touches(player_body: CharacterBody2D) -> bool:
	if walk_area != null and is_instance_valid(walk_area):
		return walk_area.overlaps_body(player_body)
	return trigger_global().intersects(_body_rect(player_body))


## `trigger_rect` in world space.
func trigger_global() -> Rect2:
	var parent := get_parent() as Node2D
	var at := parent.global_position if parent != null else Vector2.ZERO
	return Rect2(at + trigger_rect.position, trigger_rect.size)


## Old Phaser position of the door (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## `WorldSceneLoader.doorArrivals`: the parent's child named "arrival", else (a sided door) the
## parent plus `arrival_step` inward, else the parent; rounded.
func arrival_point() -> Vector2:
	var parent := get_parent() as Node2D
	if parent == null:
		return Vector2.ZERO
	var arrival := parent.get_node_or_null(^"arrival") as Node2D
	var point := (arrival if arrival != null else parent).global_position
	if arrival == null and has_side():
		point += inward() * _arrival_step()
	return Vector2(floorf(point.x + 0.5), floorf(point.y + 0.5))


func has_side() -> bool:
	return side in SIDES


## True for a hole in the ground (with or without a ladder): walked into, not pushed against.
func is_hole() -> bool:
	return kind == "ladder_down" or kind == "fall"


## True for a door with a leaf that swings (a real door with leaf art).
func has_leaf() -> bool:
	return _leaf != null and is_instance_valid(_leaf)


## The way into the room from this door (away from its wall): the facing on arrival. ZERO without
## a side.
func inward() -> Vector2:
	match side:
		"north":
			return Vector2.DOWN
		"south":
			return Vector2.UP
		"east":
			return Vector2.LEFT
		"west":
			return Vector2.RIGHT
	return Vector2.ZERO


## The side a door paired with `door_side` should have ("north" <-> "south", "east" <-> "west").
static func opposite(door_side: String) -> String:
	match door_side:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		"west":
			return "east"
	return ""


## How long going through this door plays before the iris closes (ms; see the class notes).
func lead_ms() -> float:
	match kind:
		"door":
			return _number("doorOpenMs", 250.0) if has_leaf() else 0.0
		"ladder_down", "ladder_up":
			return _number("ladderClimbMs", 450.0)
		"fall":
			return _number("holeFallMs", 550.0)
	return 0.0


## Goes through the door (UniversalSceneWorldController.doorCandidate): main's `request_exit`
## result. Queued, it plays the door's lead-in and cue (the gate's unlock cue first when the push
## unlocked it).
func use() -> Dictionary:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if main == null or not main.has_method(&"request_exit"):
		return {"status": "blocked", "message": "Navigation unavailable"}
	var was_locked := _is_locked()
	var lead := lead_ms()
	var lock := gate.duplicate()
	if not lock.is_empty() and not lock.has("unlockedMessage"):
		lock["unlockedMessage"] = DEFAULT_UNLOCKED_TEXT
	var result: Dictionary = main.call(&"request_exit", {"map_id": map_id, "exit_id": door_id,
		"target_area_id": target_area_id, "entry": "", "target_door_id": target_door_id, "gate": lock,
		"transition": "iris", "door_side": side if has_side() else "", "lead_ms": lead})
	if str(result.get("status", "")) == "queued":
		_used = true
		if was_locked:
			_cue(CUE_GATE_UNLOCK)
		_play_lead(lead)
	return result


## main.gd `_start_arrival`: the slime came in through this door. A real door stands open while it
## walks out, then closes behind it.
func on_arrival() -> void:
	if kind != "door":
		return
	if not has_leaf():
		_build_leaf()
	if not has_leaf():
		return
	_kill_leaf_tween()
	_leaf.progress = 1.0
	_close_pending = true


func _play_lead(lead: float) -> void:
	var world := Services.world()
	var player: Node = world.get(&"player") if world != null else null
	match kind:
		"door":
			_cue(open_cue)
			if has_leaf():
				_swing(1.0, lead)
		"ladder_down":
			_cue(use_cue)
			_sink(player, lead, false)
		"ladder_up":
			_cue(use_cue)
			_climb(player, lead)
		"fall":
			_cue(fall_cue)
			_sink(player, lead, true)
		_:
			_cue(use_cue)


## The slime slides to the hole's middle and shrinks into it (spinning when it falls).
func _sink(player: Node, ms: float, spin: bool) -> void:
	if player == null or not player.has_method(&"effect_tween"):
		return
	var tween: Tween = player.call(&"effect_tween")
	if tween == null:
		return
	var start: Vector2 = player.call(&"get_centre")
	var target := trigger_global().get_center() + Vector2(0.0, SINK_DEPTH_PX)
	var seconds := maxf(ms, 1.0) / 1000.0
	tween.set_parallel(true)
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(player):
			return
		player.call(&"set_effect_offset", (target - start) * t)
		var size := lerpf(1.0, 0.0 if spin else SINK_SCALE, t)
		player.call(&"set_effect_scale", Vector2(size, size))
		player.call(&"set_effect_alpha", 1.0 if spin else lerpf(1.0, 0.0, t * t)), 0.0, 1.0, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var visual: Node2D = player.call(&"get_visual")
	if spin and visual != null:
		tween.tween_property(visual, "rotation", TAU * FALL_TURNS, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## The slime climbs a little up the ladder and fades into the shaft.
func _climb(player: Node, ms: float) -> void:
	if player == null or not player.has_method(&"effect_tween"):
		return
	var tween: Tween = player.call(&"effect_tween")
	if tween == null:
		return
	player.call(&"face", Vector2.UP)
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(player):
			return
		player.call(&"set_effect_offset", Vector2(0.0, -CLIMB_RISE_PX * t))
		player.call(&"set_effect_alpha", lerpf(1.0, 0.0, t * t)), 0.0, 1.0, maxf(ms, 1.0) / 1000.0)


func _swing(to: float, ms: float) -> void:
	if not has_leaf():
		return
	_kill_leaf_tween()
	_leaf_tween = _leaf.create_tween()
	_leaf_tween.tween_property(_leaf, "progress", to, maxf(ms, 1.0) / 1000.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if to > 0.5 else Tween.EASE_IN_OUT)


func _kill_leaf_tween() -> void:
	if _leaf_tween != null and _leaf_tween.is_valid():
		_leaf_tween.kill()
	_leaf_tween = null


## A real door's leaf, built under the house sprite (game/world/door_leaf.gd), when it has a rect
## and art: the painted door's pixels, or the separate leaf picture.
func _build_leaf() -> void:
	if kind != "door" or has_leaf() or not is_inside_tree():
		return
	var parent := get_parent() as Node2D
	var sprite := house_art
	if parent == null or sprite == null or not is_instance_valid(sprite) or door_rect.size.x <= 0.0 or door_rect.size.y <= 0.0:
		return
	var leaf := DoorLeaf.new()
	leaf.name = "DoorLeaf"
	var scale := sprite.global_scale
	if is_zero_approx(scale.x) or is_zero_approx(scale.y):
		return
	var top_left := sprite.to_local(parent.global_position + door_rect.position)
	leaf.rect = Rect2(top_left, door_rect.size / scale.abs())
	leaf.arch = door_arch / absf(scale.y)
	leaf.hinge_left = hinge == "left"
	leaf.double = double_leaf
	if not leaf_art_path.is_empty():
		leaf.texture = _load_texture(leaf_art_path)
		if leaf.texture != null:
			leaf.source = Rect2(Vector2.ZERO, leaf.texture.get_size())
			leaf.draw_closed = true
	elif sprite.texture != null:
		leaf.texture = sprite.texture
		leaf.source = _texture_region(sprite, leaf.rect)
	sprite.add_child(leaf)
	_leaf = leaf


## `local` (the sprite's local space) as texture pixels of the sprite's current frame.
static func _texture_region(sprite: Sprite2D, local: Rect2) -> Rect2:
	var drawn := sprite.get_rect()
	var tex_size := sprite.texture.get_size()
	var frame_size := Vector2(tex_size.x / maxi(1, sprite.hframes), tex_size.y / maxi(1, sprite.vframes))
	var frame_at := Vector2(sprite.frame % maxi(1, sprite.hframes), sprite.frame / maxi(1, sprite.hframes)) * frame_size
	var area := Rect2(frame_at, frame_size)
	if sprite.region_enabled:
		area = sprite.region_rect
	var share_at := (local.position - drawn.position) / drawn.size
	var share_size := local.size / drawn.size
	if sprite.flip_h:
		share_at.x = 1.0 - share_at.x - share_size.x
	return Rect2(area.position + share_at * area.size, share_size * area.size)


## The leaf picture: the imported resource, else (not imported yet: the editor is open) the file
## read as an image, else null.
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


func _is_locked() -> bool:
	if gate.is_empty():
		return false
	var run := Services.run()
	return run != null and not run.is_gate_unlocked(map_id, str(gate.get("id", "")))


func _player_frozen(player: Node) -> bool:
	return player.has_method(&"is_movement_suppressed") and bool(player.call(&"is_movement_suppressed"))


## Plays `cue`, or the placeholder `FALLBACK_CUE` while the global audio scene has no take for it.
func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel == null or cue == &"":
		return
	var audio: Node = feel.global_audio() if feel.has_method(&"global_audio") else null
	if audio != null and audio.find_child(String(cue), true, false) == null:
		cue = FALLBACK_CUE
	feel.audio_cue(cue)


## The player body's collision rect in world space (its first rectangle shape), else a point.
static func _body_rect(player_body: CharacterBody2D) -> Rect2:
	for child: Node in player_body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and not shape_node.disabled and shape_node.shape is RectangleShape2D:
			var size := (shape_node.shape as RectangleShape2D).size
			return Rect2(player_body.global_position + shape_node.position - size * 0.5, size)
	return Rect2(player_body.global_position, Vector2.ZERO)


func _arrival_step() -> float:
	if is_finite(arrival_step) and arrival_step >= 0.0:
		return arrival_step
	return _number("doorArrivalStep", 48.0)


## `worldNavigation.<key>` from game-constants, else `fallback`.
func _number(key: String, fallback: float) -> float:
	var constants := Services.constants()
	return constants.number("worldNavigation." + key) if constants != null else fallback

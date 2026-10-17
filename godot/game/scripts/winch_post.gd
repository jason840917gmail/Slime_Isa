extends StaticBody2D
## Scene script of `object.winch-post-cracked` (game/scenes/objects/winch-post-cracked.tscn; the Weaver
## Hollow's drawbridge, room B2, docs/design/2026-10-16-dungeon-weaver-hollow.md; BODY_SHAPES.md "The
## Goo Bomb"). The old fort's stone winch post that holds a raised drawbridge by an iron chain (not
## silk: the lock is the bomb's alone). It carries the bomb's crack mark on its face (the cracked
## wall's decal, baked into asset/abilities/goo-bomb/winch-post-2x1.webp: intact | broken stump with
## the snapped chain, 2 px a unit, drawn at 0.5; scripts/art/pack-weaver-bomb-art.py).
##
## - **Intact:** it blocks (its body), and every weapon, throw or slam clinks off its hurtbox
##   (`DamageArea`) with `refusal_text` (BlastBarrier: "immune"). An optional chain is drawn from its
##   ring to `chain_end` (a Node2D: the bridge's top), sagging.
## - **Blown** (a Goo Bomb blast whose ellipse holds the root: group `blast_targets`,
##   `receive_blast`): the stump replaces the post, the chain drops, "The chain snaps!", the break
##   cue and the secret jingle (`SecretFound`), and it is saved as the story flag `flag_id`. Then it
##   **triggers its target**: `target_method` (default `trigger`, the dungeon kit's generic hookup:
##   game/dungeon/drawbridge.gd lowers for good and keeps its own record) on the node at
##   `target_path`, called with one Dictionary {"flagId", "instant": false, "source"} when the method
##   takes an argument, else with none; and the `triggered` signal with the same payload, for
##   anything wired in the editor. Only once: a blown post refuses later blasts.
## - **Built again with the flag set** (a load, the room entered again): it stands broken. A target
##   that keeps its own state (the kit's drawbridge) needs nothing more; for one that does not, turn
##   `call_on_load` on: the post then triggers it again (deferred, so the target is ready) with
##   "instant": true. A target can also watch the story flag itself.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")

const BREAK_TEXT := "The chain snaps!"
const STONE_TINT := Color("#b8aa8e")
const BREAK_PEBBLES := 18
const BREAK_PUFFS := 12
const FRAME_INTACT := 0
const FRAME_BROKEN := 1
## The ring on the art the chain leaves from, from the root (world units; mirrored with `flip_h`).
const RING_OFFSET := Vector2(-6.8, -34.2)
## The drawn chain: link length and thickness (world units), its sag (share of its span), colours.
const LINK_PX := 9.0
const LINK_WIDTH := 2.6
const SAG_SHARE := 0.1
const CHAIN_DARK := Color("#2e2421")
const CHAIN_LIGHT := Color("#7a6252")
const REFUSAL_RISE := 60.0

## Story flag set when it is blown (read at load: broken for good).
@export var flag_id: String = ""
## Said (once every BlastBarrier.REFUSAL_INTERVAL_MS) when a weapon, a throw or a slam hits it.
@export var refusal_text: String = "It needs a blast."
## Mirrors the art (the chain's ring and the stump's chain).
@export var flip_h: bool = false:
	set(value):
		flip_h = value
		_look()
@export_group("Target")
## What the broken post sets off: the node, and its method (see the class notes for the arguments).
@export var target_path: NodePath
@export var target_method: StringName = &"trigger"
## Built again already broken: trigger the target again with "instant": true (for a target that does
## not keep its own state).
@export var call_on_load: bool = false
@export_group("Chain")
## Where the drawn chain ends (a Node2D, e.g. the raised bridge's top); empty: no drawn chain.
@export var chain_end: NodePath

## It was blown, or built broken (then "instant" is true). Payload: {"flagId", "instant", "source"}.
signal triggered(payload: Dictionary)

var _broken: bool = false
var _chain_seen: Vector2 = Vector2.INF
## Draws the chain over the post's art (a child after the Visual).
var _chain: Node2D


func _enter_tree() -> void:
	add_to_group(BlastBarrier.GROUP)
	var run := Services.run()
	_broken = not flag_id.is_empty() and run != null and run.has_flag(flag_id)


func _ready() -> void:
	_chain = Node2D.new()
	_chain.name = "Chain"
	add_child(_chain)
	_chain.draw.connect(_draw_chain)
	_look()
	var area := get_node_or_null(^"DamageArea") as Area2D
	if _broken:
		if area != null:
			area.queue_free()
		if call_on_load:
			_trigger.call_deferred(true)
	else:
		BlastBarrier.register(area, self)
	set_process(not _broken and not chain_end.is_empty())


func _exit_tree() -> void:
	BlastBarrier.unregister(get_node_or_null(^"DamageArea") as Area2D)


func is_broken() -> bool:
	return _broken


func blast_point() -> Vector2:
	return global_position


## A Goo Bomb blast (game/player/abilities/goo_blast.gd) reached it: it breaks for good and sets its
## target off.
func receive_blast(_hit: Dictionary) -> bool:
	if _broken:
		return false
	_broken = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	var area := get_node_or_null(^"DamageArea") as Area2D
	BlastBarrier.unregister(area)
	if area != null:
		area.queue_free()
	set_process(false)
	_look()
	BlastBarrier.give_way(global_position - Vector2(0.0, 10.0), BREAK_TEXT, STONE_TINT, BREAK_PEBBLES, BREAK_PUFFS)
	_trigger(false)
	return true


# --- the damage contract (only refusals: blasts come through receive_blast) ----------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _broken}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	return BlastBarrier.refuse(global_position - Vector2(0.0, REFUSAL_RISE), refusal_text)


# --- the target ----------------------------------------------------------------------------------

func _trigger(instant: bool) -> void:
	if not is_inside_tree():
		return
	var payload := {"flagId": flag_id, "instant": instant, "source": self}
	triggered.emit(payload)
	if target_path.is_empty() or target_method == &"":
		return
	var node := get_node_or_null(target_path)
	if node == null or not node.has_method(target_method):
		push_warning("WinchPost '%s': no target '%s' with a method '%s'" % [get_path(), target_path, target_method])
		return
	if node.get_method_argument_count(target_method) > 0:
		node.call(target_method, payload)
	else:
		node.call(target_method)


# --- the look ------------------------------------------------------------------------------------

func _look() -> void:
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		visual.frame = FRAME_BROKEN if _broken else FRAME_INTACT
		visual.flip_h = flip_h
	if _chain != null:
		_chain.queue_redraw()


## The chain end moved (a bridge being lowered by something else): draw again.
func _process(_delta: float) -> void:
	var end := _chain_end_point()
	if end != _chain_seen:
		_chain_seen = end
		if _chain != null:
			_chain.queue_redraw()


func _chain_end_point() -> Vector2:
	var node := get_node_or_null(chain_end) as Node2D if not chain_end.is_empty() else null
	return to_local(node.global_position) if node != null else Vector2.INF


## The old iron chain from the ring to `chain_end`: a sagging run of links, alternately seen face on
## (an oval) and edge on (a bar).
func _draw_chain() -> void:
	if _broken or chain_end.is_empty():
		return
	var end := _chain_end_point()
	if not end.is_finite():
		return
	var start := Vector2(-RING_OFFSET.x if flip_h else RING_OFFSET.x, RING_OFFSET.y)
	var span := start.distance_to(end)
	var count := maxi(2, int(span / LINK_PX))
	var sag := span * SAG_SHARE
	var points := PackedVector2Array()
	for i in count + 1:
		var t := float(i) / float(count)
		points.append(start.lerp(end, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t)))
	for i in count:
		var a := points[i]
		var b := points[i + 1]
		var middle := (a + b) * 0.5
		var along := (b - a).angle()
		if i % 2 == 0:
			_chain.draw_set_transform(middle, along, Vector2(1.0, 0.55))
			_chain.draw_arc(Vector2.ZERO, LINK_PX * 0.55, 0.0, TAU, 12, CHAIN_DARK, LINK_WIDTH)
			_chain.draw_arc(Vector2(0.0, -0.6), LINK_PX * 0.55, PI * 1.1, PI * 1.9, 6, CHAIN_LIGHT, 1.0)
			_chain.draw_set_transform(Vector2.ZERO)
		else:
			_chain.draw_line(a.lerp(b, 0.1), a.lerp(b, 0.9), CHAIN_DARK, LINK_WIDTH + 0.8)
			_chain.draw_line(a.lerp(b, 0.2) + Vector2(0.0, -0.8), a.lerp(b, 0.8) + Vector2(0.0, -0.8), CHAIN_LIGHT, 0.8)

@tool
extends Node2D
class_name BrickedArch
## The bricked arch (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the runaway
## cart"; `object.bricked-arch`): a doorway bricked up with old bricks, the ram's lock. Its bricks
## carry NO crack: a crack is the Goo Bomb's mark, and this is not a bomb lock.
##
## - **Until it is burst it blocks** (its body). A weapon, a throw or a slam on it is refused as
##   `immune` with `refusal_text`; a Goo Bomb's blast does nothing and says `blast_text`.
## - **A ram bursts it for good** (`on_ram_hit(source)`, group `ram_breakable`: the ram's log,
##   game/dungeon/ram.gd; the runaway cart too): half the bricks fall at once, the rest a moment
##   later, bricks fly, dust, a shake, the stone break cue and the secret jingle; rubble lies in the
##   doorway and the way is open. Its record (`arch_id`) keeps it open: built again it stands burst.
##
## **Placing.** As a door object in an interior wall's doorway (docs/godot/INTERIOR_WALLS.md "The
## door objects in the opening"): on the floor line of the room its face looks into, in the middle of
## the passage, `wall` that room's wall. Its picture is its own (the brick panel,
## asset/MAPS/objects/mechanisms/bricked-arch-2x1.webp), laid where the style's door leaf lies in the
## opening (`InteriorWallLayer.leaf_at`), so the wall draws the doorway's frame around it. The whole
## piece turns with `wall`. In step 3 of the dungeons rework the panel becomes a leaf of the
## interior walls' sheets; this script's logic does not depend on where the picture comes from.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PushProbe := preload("res://game/dungeon/push_probe.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const MechanismStrike := preload("res://game/dungeon/mechanism_strike.gd")
const MechanismDebris := preload("res://game/dungeon/mechanism_debris.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")

const BLAST_TARGETS := &"blast_targets"
const WALL_TURNS := {"north": 0.0, "east": PI * 0.5, "south": PI, "west": -PI * 0.5}
## Refuses every weapon (the refusal is the receiver's).
const RULE := {"priority": 0, "damageMultiplier": 0}
const TAGS: Array[String] = ["barrier"]
const REASON_IMMUNE := "immune"
## The door leaf's kind whose place in the opening the panel takes, and the place without a style
## (the cave rock's north leaf: its top-left from the node, its size; world units).
const LEAF_KIND := "shutter"
const PANEL_AT := Vector2(-35.0, -90.5)
const PANEL_SIZE := Vector2(70.5, 66.0)
const FRAME_WHOLE := 0
const FRAME_HALF := 1
const BRICKS := "res://asset/MAPS/objects/mechanisms/bricked-arch-bricks-8x1.webp"
const BRICK_CELLS := 8
const BRICK_CELL_PX := 56.0
## The second half of the bricks falls this long after the first (ms).
const SECOND_WAVE_MS := 110.0
const BRICK_DUST := Color("#c98a5e")
const MORTAR_DUST := Color("#cdb9a2")
const TEXT_RISE := 120.0
## Where a blast must reach: the middle of the bricks' body (its shape's place in the scene).
const BLAST_RISE := -20.0
const TEXT_MS := 2200.0
const CUE_BREAK := &"BreakStone"
const CUE_SECRET := &"SecretFound"
const DUST := &"dust-puff"

## It was burst. Payload: {"archId"}.
signal burst(payload: Dictionary)

## Which wall of its room it stands in (north: the front view).
@export_enum("north", "east", "south", "west") var wall: String = "north":
	set(value):
		wall = value
		_refresh()
## Its id in the record (unique in its world; the node's name when empty).
@export var arch_id: String = ""
## The interior wall style of its doorway (its leaf's place in the opening).
@export var interior_style: String = "cave-rock":
	set(value):
		interior_style = value
		_refresh()
## Said when a weapon, a throw or a slam hits it.
@export var refusal_text: String = "Bricked up, and solid. Only something heavy would break it."
## Said when a Goo Bomb's blast reaches it.
@export var blast_text: String = "Not even a crack to work on."
## The body that blocks the doorway while it stands.
@export var body: StaticBody2D
## The hurtbox that refuses.
@export var damage_area: Area2D
## The brick panel (2 frames: whole, half fallen) and the rubble left on the floor.
@export var panel: Sprite2D
@export var rubble: Sprite2D

var _burst := false
## The burst's moment (the gameplay clock) while it plays; -1 otherwise.
var _burst_at_ms := -1.0
var _second_wave := false
var _jingled := false
var _way := Vector2.UP
var _next_line_ms := 0.0
var _registered: Area2D


func _enter_tree() -> void:
	add_to_group(MechanismStrike.GROUP_BREAKABLE)
	add_to_group(BLAST_TARGETS)


func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	set_physics_process(false)
	var router := Services.router()
	if damage_area != null and router != null:
		router.register_area(damage_area, self, RULE, TAGS)
		_registered = damage_area
	_restore_in_tree.call_deferred()


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func is_burst() -> bool:
	return _burst


## The bricks' rectangle (global): what a ram's head must reach.
func ram_rect() -> Rect2:
	return PushProbe.shapes_box(body)


## A ram's log or a runaway cart struck it: it bursts for good.
func on_ram_hit(source: Node = null) -> void:
	if _burst or Engine.is_editor_hint():
		return
	_burst = true
	DungeonState.mark_done(get_tree(), _record_key())
	_way = Vector2.UP.rotated(rotation)
	if source is Node2D:
		# the way the blow came, snapped to the wall's own line
		var from := (global_position - (source as Node2D).global_position)
		if from.dot(_way) < 0.0:
			_way = -_way
	_open()
	_burst_at_ms = Services.now_ms()
	_second_wave = false
	_jingled = false
	if panel != null:
		panel.frame = FRAME_HALF
	_throw_bricks([0, 2, 4, 6], 1)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_BREAK)
		feel.shake(DungeonState.number("burst.shakeMs", 260.0), DungeonState.number("burst.shakeIntensity", 0.008))
		feel.burst(DUST, _middle(), Vector2.ZERO, MORTAR_DUST, 0.16)
	AbilityFx.debris(global_position, BRICK_DUST, 14, 8, 0.6)
	set_physics_process(true)
	burst.emit({"archId": arch_id})


## The burst's later beats: the second half of the bricks, then the secret jingle.
func _physics_process(_delta: float) -> void:
	if _burst_at_ms < 0.0:
		set_physics_process(false)
		return
	var age := Services.now_ms() - _burst_at_ms
	if not _second_wave and age >= SECOND_WAVE_MS:
		_second_wave = true
		_throw_bricks([1, 3, 5, 7], 2)
		_lie_burst()
		var feel := Services.feel()
		if feel != null:
			feel.burst(&"stone-chip", _middle(), -_way, BRICK_DUST, 1.6)
	if not _jingled and age >= DungeonState.number("burst.jingleDelayMs", 350.0):
		_jingled = true
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_SECRET)
		_burst_at_ms = -1.0


## Half the bricks: most spray back into the room the blow came from, some fly on through.
func _throw_bricks(cells: Array, wave: int) -> void:
	var back := cells.slice(0, 3)
	var on := cells.slice(3)
	MechanismDebris.throw(get_parent(), _middle() - _way * 18.0, {"sheet": BRICKS, "cells": BRICK_CELLS, "cell_px": BRICK_CELL_PX,
		"pieces": back, "direction": -_way, "spread_deg": 150.0, "speed_min": 110.0, "speed_max": 250.0,
		"rise_min": 22.0, "rise_max": 54.0, "air_ms": 460.0, "lie_ms": 1500.0, "fade_ms": 600.0,
		"seed": 31 * wave + get_instance_id() % 97, "from_px": 26.0, "start_rise": 30.0})
	MechanismDebris.throw(get_parent(), _middle() + _way * 30.0, {"sheet": BRICKS, "cells": BRICK_CELLS, "cell_px": BRICK_CELL_PX,
		"pieces": on, "direction": _way, "spread_deg": 30.0, "speed_min": 90.0, "speed_max": 170.0,
		"rise_min": 16.0, "rise_max": 30.0, "air_ms": 380.0, "lie_ms": 1500.0, "fade_ms": 600.0,
		"seed": 57 * wave + get_instance_id() % 89, "from_px": 16.0, "start_rise": 24.0})


## The middle of the doorway's floor under the bricks (global).
func _middle() -> Vector2:
	return global_position + Vector2(0.0, -34.0).rotated(rotation)


# --- refusals -------------------------------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _burst}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	_say(refusal_text)
	return {"accepted": false, "reason": REASON_IMMUNE}


## A Goo Bomb's blast: nothing gives (it has no crack), and it says so.
func receive_blast(_hit: Dictionary) -> bool:
	if not _burst:
		_say(blast_text)
	return false


## The middle of its bricks' body: a bomb laid against either face of the bricks reaches it.
func blast_point() -> Vector2:
	return global_position + Vector2(0.0, BLAST_RISE).rotated(rotation)


## The level and line tests of a throw look at its bricks' body (AbilityWorld `_target_body`), so
## the bricks do not hide their own hurtbox from a throw.
func get_body() -> Node2D:
	return body


## The line, at most once per `burst.lineEveryMs`. Real time, as the kit's doors space theirs
## (game/dungeon/dungeon_door.gd `say`, which key_door.gd uses): the spacing only keeps a floating
## line from stacking, presentation that changes no gameplay (CONVENTIONS: real time only for
## presentation).
func _say(text: String) -> void:
	if _burst or text.is_empty():
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_line_ms:
		return
	_next_line_ms = now + DungeonState.number("burst.lineEveryMs", 1500.0)
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), text, &"white", false, TEXT_MS)


# --- the state and the looks -----------------------------------------------------------------------

func _record_key() -> String:
	return DungeonState.object_key(self, "arch:" + (arch_id if not arch_id.is_empty() else String(name)))


## `_restore`, deferred from `_ready`, only while still in the tree (a world run on its own, F6, is
## the current scene for a moment before it swaps itself for main.tscn).
func _restore_in_tree() -> void:
	if is_inside_tree() and not _burst and DungeonState.is_done(get_tree(), _record_key()):
		_burst = true
		_open()
		_lie_burst()


## The way through opens: the body and the hurtbox go.
func _open() -> void:
	if body != null:
		for child: Node in body.get_children():
			if child is CollisionShape2D:
				(child as CollisionShape2D).set_deferred(&"disabled", true)
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null
	if damage_area != null:
		for child: Node in damage_area.get_children():
			if child is CollisionShape2D:
				(child as CollisionShape2D).set_deferred(&"disabled", true)


## Burst: no panel, the rubble on the floor.
func _lie_burst() -> void:
	if panel != null:
		panel.visible = false
	if rubble != null:
		rubble.visible = true


## The panel in its opening, turned for its wall.
func _refresh() -> void:
	rotation = float(WALL_TURNS.get(wall, 0.0))
	if panel == null:
		return
	# The panel is laid as a north leaf and turns with the node, as the whole piece does.
	var place := InteriorWalls.leaf_at(interior_style, "north", LEAF_KIND) if not interior_style.is_empty() else {}
	var at: Vector2 = place.get("offset", PANEL_AT)
	var size: Vector2 = place.get("size", PANEL_SIZE)
	panel.centered = false
	panel.position = at
	if panel.texture != null and panel.hframes > 0:
		var cell := Vector2(panel.texture.get_width() / float(panel.hframes), panel.texture.get_height())
		panel.scale = Vector2(size.x / maxf(1.0, cell.x), size.y / maxf(1.0, cell.y))
	if not _burst:
		panel.visible = true
		panel.frame = FRAME_WHOLE
		if rubble != null:
			rubble.visible = false

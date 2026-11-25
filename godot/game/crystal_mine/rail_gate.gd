@tool
extends Node2D
class_name RailGate
## The rail gate (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the runaway
## cart"; `object.rail-gate`): timber and iron across a mine's rails, chained shut. The runaway
## cart's lock (game/crystal_mine/ram_cart.gd): only something that rams it opens it.
##
## - **Until it is smashed it blocks** (its planks' body; its two posts always stand and, unless
##   `posts_solid_when_smashed` is off, block). A
##   weapon, a throw, a slam or a blast on it is refused as `immune` with `refusal_text`.
## - **A ram smashes it open for good** (`on_ram_hit(source)`, group `ram_breakable`: the runaway
##   cart runs on through; the ram's log too): the planks fly, splinters and dust, a shake, the wood
##   break cue and the secret jingle; the posts stay, with their stubs and the broken chain. Its
##   record (`gate_id`) keeps it open: built again it stands smashed.
##
## **Placing.** On the rails, the node on the track's middle line where the gate's foot is. `rails`
## is the way the track runs through it: "north-south" (the gate is seen from the front) or
## "east-west" (the front picture turned and foreshortened, as the kit's doors in a side wall).
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PushProbe := preload("res://game/dungeon/push_probe.gd")
const MechanismStrike := preload("res://game/dungeon/mechanism_strike.gd")
const MechanismDebris := preload("res://game/dungeon/mechanism_debris.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")

const BLAST_TARGETS := &"blast_targets"
const RULE := {"priority": 0, "damageMultiplier": 0}
const TAGS: Array[String] = ["barrier"]
const REASON_IMMUNE := "immune"
## Turned for a track across the screen, its picture is drawn this share of its height (the kit's
## doors in a side wall: game/dungeon/dungeon_door.gd SIDE_DEPTH).
const SIDE_DEPTH := 0.55
const FRAME_SHUT := 0
const FRAME_SMASHED := 1
const PLANKS := "res://asset/MAPS/objects/mechanisms/rail-gate-planks-7x1.webp"
const PLANK_CELLS := 7
const PLANK_CELL_PX := 112.0
## The planks' middle over the node (world units).
const PLANKS_RISE := 44.0
const WOOD_DUST := Color("#b98a4e")
const TEXT_RISE := 124.0
const TEXT_MS := 2200.0
const CUE_BREAK := &"BreakWood"
const CUE_SECRET := &"SecretFound"
const SPLINTERS := &"hit-spark"
const DUST := &"dodge-dust"

## It was smashed open. Payload: {"gateId"}.
signal smashed(payload: Dictionary)

## The way the track runs through it.
@export_enum("north-south", "east-west") var rails: String = "north-south":
	set(value):
		rails = value
		_refresh()
## Its id in the record (unique in its world; the node's name when empty).
@export var gate_id: String = ""
## Smashed, its posts still block (the lab's gate on open floor). Off for a gate standing in a side
## doorway (the rebuilt Mine's M1 and M7): there the doorway's jambs block beside the passage, and the
## posts, turned into the passage, would narrow it to the gap between them.
@export var posts_solid_when_smashed: bool = true
## Said when anything but a ram hits it.
@export var refusal_text: String = "Chained shut across the rails."
## Its planks' body (gone once smashed); its posts keep their own.
@export var body: StaticBody2D
## The hurtbox that refuses.
@export var damage_area: Area2D
## Its picture (2 frames: shut, smashed).
@export var look: Sprite2D

var _smashed := false
var _jingle_at_ms := -1.0
var _next_line_ms := 0.0
var _base_scale := Vector2.ZERO
var _registered: Area2D


func _enter_tree() -> void:
	add_to_group(MechanismStrike.GROUP_BREAKABLE)
	add_to_group(BLAST_TARGETS)


func _ready() -> void:
	_refresh()
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
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


func is_smashed() -> bool:
	return _smashed


## The planks' rectangle (global): what a ram must reach.
func ram_rect() -> Rect2:
	return PushProbe.shapes_box(body)


## The runaway cart (or a ram's log) struck it: it is smashed open for good.
func on_ram_hit(source: Node = null) -> void:
	if _smashed or Engine.is_editor_hint():
		return
	_smashed = true
	DungeonState.mark_done(get_tree(), _record_key())
	_open()
	# the way the blow goes: along the track, away from what struck it
	var way := Vector2.DOWN.rotated(rotation)
	if source is Node2D:
		var from: Vector2 = source.call(&"cart_point") if source.has_method(&"cart_point") else (source as Node2D).global_position
		if (global_position - from).dot(way) < 0.0:
			way = -way
	var middle := global_position + Vector2(0.0, -6.0)
	MechanismDebris.throw(get_parent(), middle, {"sheet": PLANKS, "cells": PLANK_CELLS, "cell_px": PLANK_CELL_PX,
		"pieces": [0, 1, 2, 3, 5, 4, 6], "direction": way, "spread_deg": 120.0, "speed_min": 150.0, "speed_max": 330.0,
		"rise_min": 26.0, "rise_max": 62.0, "air_ms": 520.0, "lie_ms": 1800.0, "fade_ms": 700.0,
		"seed": 19 + get_instance_id() % 83, "from_px": 30.0, "start_rise": PLANKS_RISE})
	AbilityFx.debris(global_position, WOOD_DUST, 10, 8, 0.6)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_BREAK)
		feel.shake(DungeonState.number("burst.shakeMs", 260.0), DungeonState.number("burst.shakeIntensity", 0.008))
		feel.burst(SPLINTERS, global_position - Vector2(0.0, PLANKS_RISE), way, WOOD_DUST, 2.2)
		feel.particles(DUST, global_position + Vector2(-34.0, 0.0))
		feel.particles(DUST, global_position + Vector2(34.0, 0.0))
	_jingle_at_ms = Services.now_ms() + DungeonState.number("burst.jingleDelayMs", 350.0)
	set_physics_process(true)
	smashed.emit({"gateId": gate_id})


## The secret jingle, a beat after the smash.
func _physics_process(_delta: float) -> void:
	if _jingle_at_ms < 0.0 or Services.now_ms() < _jingle_at_ms:
		return
	_jingle_at_ms = -1.0
	set_physics_process(false)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SECRET)


# --- refusals -------------------------------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _smashed}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	_say()
	return {"accepted": false, "reason": REASON_IMMUNE}


## A Goo Bomb's blast: the chain holds.
func receive_blast(_hit: Dictionary) -> bool:
	_say()
	return false


func blast_point() -> Vector2:
	return global_position - Vector2(0.0, PLANKS_RISE * 0.5)


## The level and line tests of a throw look at its planks' body (AbilityWorld `_target_body`), so
## the planks do not hide their own hurtbox from a throw along the rails (its posts still stop a
## throw from the side, as a wall does).
func get_body() -> Node2D:
	return body


## The line, at most once per `burst.lineEveryMs`. Real time, as the kit's doors space theirs
## (game/dungeon/dungeon_door.gd `say`, which key_door.gd uses): the spacing only keeps a floating
## line from stacking, presentation that changes no gameplay (CONVENTIONS: real time only for
## presentation).
func _say() -> void:
	if _smashed or refusal_text.is_empty():
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_line_ms:
		return
	_next_line_ms = now + DungeonState.number("burst.lineEveryMs", 1500.0)
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), refusal_text, &"white", false, TEXT_MS)


# --- the state and the looks -----------------------------------------------------------------------

func _record_key() -> String:
	return DungeonState.object_key(self, "rail-gate:" + (gate_id if not gate_id.is_empty() else String(name)))


## `_restore`, deferred from `_ready`, only while still in the tree (a world run on its own, F6, is
## the current scene for a moment before it swaps itself for main.tscn).
func _restore_in_tree() -> void:
	if is_inside_tree() and not _smashed and DungeonState.is_done(get_tree(), _record_key()):
		_smashed = true
		_open()


## The way through opens: the planks' body and the hurtbox go, the posts stay (their collision too,
## unless `posts_solid_when_smashed` is off).
func _open() -> void:
	if look != null:
		look.frame = FRAME_SMASHED
	if body != null:
		for child: Node in body.get_children():
			if child is CollisionShape2D:
				(child as CollisionShape2D).set_deferred(&"disabled", true)
	var posts := get_node_or_null(^"Posts")
	if posts != null and not posts_solid_when_smashed:
		for child: Node in posts.get_children():
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


## Turned for its track; foreshortened when the track runs across the screen.
func _refresh() -> void:
	var across := rails == "east-west"
	rotation = PI * 0.5 if across else 0.0
	if look == null:
		return
	if _base_scale == Vector2.ZERO:
		_base_scale = look.scale
	look.scale = Vector2(_base_scale.x, _base_scale.y * (SIDE_DEPTH if across else 1.0))
	if not _smashed:
		look.frame = FRAME_SHUT

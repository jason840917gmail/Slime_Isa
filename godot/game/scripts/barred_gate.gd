extends Node2D
class_name BarredGateScript
## Scene script `game.barred-gate` (`object.barred-gate`, game/scenes/objects/barred-gate.tscn;
## roadmap 5.22; docs/godot/PROLOGUE.md "The barred gate"): an old Thorn Guard gate, shut and worked
## from the far side. Its iron grate stands between two stone posts; its lever stands one tile behind
## the grate, seen through the bars. Only the Spear's thrust fits between the bars: the Spear's own
## lock, "through bars" (the level-design guide's look book: an old grate, the lever visible just
## behind the bars, in line with a thrust).
##
## - The node stands at the middle of the opening's foot (where the grate meets the ground); the
##   slime walks up to it from the open side (+y, south) and thrusts north.
## - **The bars** (`bars`, a StaticBody2D) block every body. Their hurtbox (`bars_area`, registered
##   with DamageRouter, receiver this script) does two things: the Spear's wall ray passes through
##   a body that owns a hurtbox (game/shapes/shape_strike.gd `wall_reach`), so the thrust reaches
##   past the bars; and every other hit on the bars (a thrown pot breaking against them, a Roll's
##   bonk, another shape) is refused as `immune`, the clink, with the refusal line
##   (`refusal_text`) over the gate, at most once every REFUSAL_EVERY_MS. The Spear's own hit on the
##   bars is refused quietly (`pass`), so only the lever answers it.
## - **The lever** (game/world_objects/barred_gate_lever.gd, the `Lever` child) takes only a hit tagged
##   `spear` (ShapeDefs: the Spear shape's `tags`); it is tagged `resource`, so a throw's blast never
##   reaches it and a hit on it plays no enemy feel. Pulled, it opens the gate.
## - **Opening** (`open`): the lever drops, the grate rises into the beam over `rise_ms` (its picture is
##   cut from the bottom up, so it slides behind the beam) with the gate sound and a little dust and
##   shake, and the bars stop blocking. The gate stays open for good: the map record's unlocked gate
##   `gate_id` (RunState `mark_gate_unlocked`), read when the scene is built (`is_open`). `open_now`
##   opens it at once without a sound and without a record (a gate already opened; the prologue's
##   gate for a run that is not playing the prologue).
##
## Owner: prologue.

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

## Every barred gate joins this group (the prologue's hint finds it).
const GROUP := &"barred_gate"
## The tag a hit must carry to pull the lever (the Spear shape's `tags` in game-constants.json).
const SPEAR_TAG := "spear"
const RULE := {"priority": 0, "damageMultiplier": 1}
const REASON_IMMUNE := "immune"
## The Spear on the bars: refused without a clink (the lever behind takes the thrust).
const REASON_PASS := "pass"
const REASON_DEAD := "dead"
const REFUSAL_EVERY_MS := 1500
const REFUSAL_RISE := 120.0
const CUE_OPEN := &"GateOpen"
const CUE_UNLOCK := &"GateUnlock"
const CUE_REFUSED := &"GateLocked"
const DUST := &"dodge-dust"
const SPARKLE := &"loot-sparkle"
const SHAKE_MS := 260.0
const SHAKE_INTENSITY := 0.004

## Emitted once when the gate opens (not by `open_now`). Payload: {"gateId"}.
signal opened(payload: Dictionary)
## A hit was refused (not the Spear). Payload: {"gateId", "weaponId"}.
signal refused(payload: Dictionary)

## The map whose record keeps the gate open ("" = the world's map id).
@export var map_id: String = ""
## The gate's id in its map record (unlocked gate ids).
@export var gate_id: String = "barred-gate"
## The line over the gate when something else than the Spear hits the bars or the lever.
@export var refusal_text: String = "Barred. Only something long and thin fits between the bars."
## How long the grate takes to rise (ms, real time: presentation).
@export var rise_ms: float = 900.0
## The bars' body (blocks while shut).
@export var bars: StaticBody2D
## The bars' hurtbox (a child of `bars`).
@export var bars_area: Area2D
## The grate's picture (rises into the beam).
@export var grate: Sprite2D

var _open := false
var _rising := false
var _rise_started_ms := 0.0
var _grate_region := Rect2()
var _grate_offset := Vector2.ZERO
var _registered: Area2D
var _next_refusal_ms := 0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if grate != null and grate.texture != null:
		_grate_region = Rect2(Vector2.ZERO, grate.texture.get_size())
		_grate_offset = grate.offset
		grate.region_enabled = true
		grate.region_rect = _grate_region
	var router := Services.router()
	if router != null and bars_area != null:
		router.register_area(bars_area, self, RULE, [])
		_registered = bars_area
	# The world registers after its nodes are ready: its map id is known at the end of the frame.
	_open_if_recorded.call_deferred()


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


## True once the gate is open (it stays open).
func is_open() -> bool:
	return _open


## The lever was pulled (game/world_objects/barred_gate_lever.gd): the grate rises, the gate opens
## for good. Nothing when it is open already.
func open() -> void:
	if _open:
		return
	_set_open()
	_rising = true
	_rise_started_ms = float(Time.get_ticks_msec())
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_UNLOCK)
		feel.audio_cue(CUE_OPEN)
		feel.shake(SHAKE_MS, SHAKE_INTENSITY)
		feel.particles(DUST, global_position + Vector2(-40.0, -4.0))
		feel.particles(DUST, global_position + Vector2(40.0, -4.0))
	opened.emit({"gateId": gate_id})


## Opens the gate at once, quietly (already opened before; the prologue played or skipped).
func open_now() -> void:
	_set_open(false)
	_rising = false
	if grate != null:
		grate.visible = false


## The refusal: the line over the gate (throttled), the locked sound, `refused`.
func refuse(weapon_id: String) -> void:
	refused.emit({"gateId": gate_id, "weaponId": weapon_id})
	var now := Time.get_ticks_msec()
	if now < _next_refusal_ms:
		return
	_next_refusal_ms = now + REFUSAL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REFUSED)
		feel.floating_text(global_position - Vector2(0.0, REFUSAL_RISE), refusal_text, &"white", false, 2200.0)


## The map whose record keeps the gate: `map_id`, else the world's.
func record_map_id() -> String:
	if not map_id.is_empty():
		return map_id
	var world := Services.world()
	return world.map_id() if world != null else ""


func _open_if_recorded() -> void:
	var run := Services.run()
	if not _open and run != null and run.is_gate_unlocked(record_map_id(), gate_id):
		open_now()


func _set_open(record: bool = true) -> void:
	_open = true
	var run := Services.run()
	var record_id := record_map_id()
	if record and run != null and not record_id.is_empty():
		run.mark_gate_unlocked(record_id, gate_id)
	var lever := get_node_or_null(^"Lever")
	if lever != null and lever.has_method(&"show_pulled"):
		lever.call(&"show_pulled")


func _process(_delta: float) -> void:
	if not _rising or grate == null:
		return
	var t := clampf((float(Time.get_ticks_msec()) - _rise_started_ms) / maxf(1.0, rise_ms), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var lift := _grate_region.size.y * eased
	grate.region_rect = Rect2(Vector2(0.0, lift), Vector2(_grate_region.size.x, maxf(0.0, _grate_region.size.y - lift)))
	grate.offset = _grate_offset
	if bars != null and eased >= 0.6:
		_disable_bars()
	if t >= 1.0:
		_rising = false
		grate.visible = false
		_disable_bars()


func _disable_bars() -> void:
	if bars == null:
		return
	for child: Node in bars.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred(&"disabled", true)


# --- the bars' damage receiver (DamageRouter; combat spec 7.2) ---------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": false}


## The Spear passes the bars quietly (`pass`); everything else clinks (`immune`) with the line. Open,
## the bars are gone: every hit passes.
func can_receive_damage(input: Dictionary) -> Dictionary:
	var request: Dictionary = input.get("request", {})
	if _open or is_spear(request):
		return {"accepted": false, "reason": REASON_PASS}
	refuse(str(request.get("weapon_id", "")))
	return {"accepted": false, "reason": REASON_IMMUNE}


func commit_damage(_commit: Dictionary) -> void:
	pass


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


## True when `request` is the Spear's (its tags carry SPEAR_TAG).
static func is_spear(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	return tags is Array and (tags as Array).has(SPEAR_TAG)

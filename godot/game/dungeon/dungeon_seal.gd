@tool
extends "res://game/dungeon/shutter.gd"
class_name DungeonSeal
## The dungeon's seal (`object.dungeon-seal`, game/scenes/objects/dungeon/dungeon-seal.tscn;
## docs/godot/DUNGEONS.md "The seal"; the plan docs/design/2026-10-17-pearl-mid-dungeon.md "The
## seal"): the kit's shutter block risen in a doorway out of the dungeon, bound by a ring of light in
## the boss's colour round a dark pearl that pulses slowly like a heartbeat. It takes no power: only
## the boss's fall breaks it.
##
## - **Placing it:** in every doorway that leads out of the dungeon (the entrance, the way out past
##   the boss) and nowhere else, like a shutter: in the doorway, on the floor line of the room it
##   closes (the room inside), `wall` that room's wall. Nothing to set: it follows its world's
##   Dungeon node (`boss_id`, `seal_color`, `boss_name`). `glimpse` picks it for the take's glimpse
##   (else the seal nearest the entrance marker is shown).
## - **While the dungeon is sealed** (DungeonState.is_sealed: read when its world is built, so after
##   a faint or a quit it is shut from the start) it stands shut and blocks. Walked into, it hums
##   and refuses with the Dungeon's `seal_text` ("Sealed. Fatty One Eye's rage holds it shut."); every
##   hit (the DamageRouter) and a bomb's blast (`blast_targets`) are refused the same way. On the
##   dungeon map it is a red mark (`dungeon_map_mark`, `mark` "seal").
## - **The take** (Dungeon.seal_now): `slam` rises it with a boom, a hard shake and dust (the glimpse
##   shows the entrance's), `shut_quietly` shuts it out of sight, `engage` blocks at once and rises
##   later.
## - **His fall** (Dungeon `_break_seals`): `break_seal` sinks it with a chime, its ring shatters,
##   and it stays down for good (the record is unsealed). A winch, a bell or a room fight never opens
##   it (`trigger`, `open_for_good` and `open` do nothing while sealed).
##
## Owner: dungeon kit.

const PushProbe := preload("res://game/dungeon/push_probe.gd")

const CUE_SLAM := &"SlamImpact"
const CUE_HUM := &"GateLocked"
const CUE_SHATTER := &"BreakGlass"
const HUM_PITCH := 0.55
const SPARKLE := &"loot-sparkle"
const TEXT_RISE := 120.0
const TEXT_MS := 2400.0
## The ring shows once the block is up this far.
const RING_FROM := 0.85
## A heartbeat: two beats a period, the second this far into it and this strong.
const SECOND_BEAT_AT := 0.24
const SECOND_BEAT := 0.65
const BEAT_WIDTH := 0.07
## The ring's flash on the slam (real ms).
const FLASH_MS := 450.0
## With the frame drawn by the wall, the ring is this share of the seal leaf's size.
const RING_IN_LEAF := 0.62
## The ring's light over its colour (it is added).
const RING_BOOST := 1.6
const RULE := {"priority": 0, "damageMultiplier": 1}
const TAGS: Array[String] = []

## A push, a hit or a blast was refused. Payload: {"text"}.
signal refused(payload: Dictionary)

## The take's glimpse shows this seal (else the one nearest the entrance marker).
@export var glimpse: bool = false
## The ring's colour when the world's Dungeon node has none to give (its `seal_color` wins).
@export var ring_color: Color = Color("#d4482e")
## The ring of light over the block's face (added, tinted with the boss's colour).
@export var ring: Sprite2D
## The soft glow round the block (soft_glow.gd), tinted the same.
@export var glow: Node2D
## Takes the hits it refuses.
@export var damage_area: Area2D

## The dungeon map's mark: "seal" while it is shut (DungeonMapDraw.seal_points).
var mark := ""

var _registered := false
var _push_ms := 0.0
var _spoke := false
var _next_line_ms := 0
var _flash_until := 0.0
var _clock := 0.0
var _ring_scale := Vector2.ZERO
var _ring_rest := Vector2.ZERO


func _enter_tree() -> void:
	super._enter_tree()
	if not Engine.is_editor_hint():
		add_to_group(DungeonState.SEAL_GROUP)
		add_to_group(&"dungeon_map_mark")
		add_to_group(&"blast_targets")


func _ready() -> void:
	super._ready()
	if ring != null:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ring.material = additive
		if ring.texture == null:
			ring.texture = ring_texture()
	_show_ring(1.0 if Engine.is_editor_hint() else 0.0)
	if Engine.is_editor_hint():
		# Shown risen in the editor, so it is seen where it stands.
		_place_look(1.0)
		return
	_sync_in_tree.call_deferred()


func leaf_kind() -> String:
	return "seal"


func _exit_tree() -> void:
	_register_hits(false)


func _apply_side_depth() -> void:
	super._apply_side_depth()
	if ring == null:
		return
	if _ring_scale == Vector2.ZERO:
		_ring_scale = ring.scale
		_ring_rest = ring.position
	if frame_drawn_by_wall and look != null and look.region_enabled:
		# the ring lies over the pearl in the middle of the wall-drawn seal leaf
		var size := look.region_rect.size * look.scale
		ring.rotation = look.rotation
		ring.offset = Vector2.ZERO
		ring.centered = true
		if ring.texture != null:
			var k := minf(size.x, size.y) * RING_IN_LEAF / float(ring.texture.get_width())
			ring.scale = Vector2(k, k)
		ring.position = look.position + (size * 0.5).rotated(look.rotation)
		return
	ring.scale = Vector2(_ring_scale.x, _ring_scale.y * (SIDE_DEPTH if wall == "east" or wall == "west" else 1.0))


## Shut from the start when its world is built while the dungeon is sealed (a resume).
func _sync_in_tree() -> void:
	if is_inside_tree() and _dungeon_sealed():
		shut_quietly()


# --- the take and the fall ------------------------------------------------------------------------

## Holds the doorway at once, still down (it rises in the take's glimpse: `slam`).
func engage() -> void:
	_shut = true
	_set_blocking(true)
	_register_hits(true)
	mark = "seal"


## Rises at once, out of sight (a seal the glimpse does not show, a resume, `?sealed`).
func shut_quietly() -> void:
	engage()
	_height = 1.0
	_target = 1.0
	_place_look(1.0)


## Rises with a boom: the hard shake, dust, its ring flaring.
func slam() -> void:
	engage()
	_target = 1.0
	_flash_until = float(Time.get_ticks_msec()) + FLASH_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SLAM)
		feel.shake(DungeonState.number("seal.slamShakeMs", 420.0), DungeonState.number("seal.slamShakeIntensity", 0.01))
		feel.particles(DUST, global_position + Vector2(-40.0, -6.0).rotated(rotation))
		feel.particles(DUST, global_position + Vector2(40.0, -6.0).rotated(rotation))
	moved.emit({"shutterId": shutter_id, "shut": true})


## His fall: it sinks with a chime, its ring shatters; it stays down for good.
func break_seal() -> void:
	mark = ""
	_register_hits(false)
	if not _shut:
		return
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SHATTER)
		feel.particles(SPARKLE, _ring_point())
	super.open()


## Room fights and other pieces call these on shutters: a seal answers only to its boss's fall.
func shut(payload: Variant = null) -> void:
	if _dungeon_sealed():
		slam()
	else:
		super.shut(payload)


func open(payload: Variant = null) -> void:
	if _dungeon_sealed():
		return
	super.open(payload)


func open_for_good(_payload: Variant = null) -> void:
	pass


func trigger(_payload: Variant = null) -> void:
	pass


# --- refusing ---------------------------------------------------------------------------------------

## The refusal: a low hum and the seal's line over it (at most every `dungeon.seal.lineEveryMs`).
func refuse() -> void:
	refused.emit({"text": seal_text()})
	var now := Time.get_ticks_msec()
	if now < _next_line_ms:
		return
	_next_line_ms = now + int(DungeonState.number("seal.lineEveryMs", 1500.0))
	_flash_until = float(now) + FLASH_MS * 0.6
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HUM, {"pitch": HUM_PITCH})
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), seal_text(), &"white", false, TEXT_MS)


## The Dungeon's line ("Sealed. <boss>'s rage holds it shut.").
func seal_text() -> String:
	var dungeon := DungeonState.current(get_tree()) if is_inside_tree() else null
	return str(dungeon.call(&"seal_text")) if dungeon != null and dungeon.has_method(&"seal_text") else "Sealed."


## Goo Bomb blasts (goo_blast.gd `blast_targets`): refused while shut.
func receive_blast(_hit: Dictionary) -> bool:
	if _shut:
		refuse()
	return false


func blast_point() -> Vector2:
	return global_position


func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": not _shut}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	if not _shut:
		return {"accepted": false, "reason": "pass"}
	refuse()
	return {"accepted": false, "reason": "immune"}


func mitigate_damage(_input: Dictionary) -> float:
	return 0.0


func commit_damage(_commit: Dictionary) -> void:
	pass


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


func _register_hits(on: bool) -> void:
	var router := Services.router()
	if router == null or damage_area == null or on == _registered:
		return
	if on:
		router.register_area(damage_area, self, RULE, TAGS)
	else:
		router.unregister_area(damage_area)
	_registered = on


# --- every step -------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if Engine.is_editor_hint() or not _shut:
		return
	var direction := PushProbe.push_direction(PushProbe.shapes_box(body))
	if direction == Vector2.ZERO:
		_push_ms = 0.0
		_spoke = false
		return
	_push_ms += delta * 1000.0
	if _push_ms >= PushProbe.push_ms() and not _spoke:
		_spoke = true
		refuse()


func _process(delta: float) -> void:
	_clock += delta
	_show_ring(_height if not Engine.is_editor_hint() else 1.0)


## The ring and the glow: shown as the block tops out, beating like a heart in the boss's colour.
func _show_ring(height: float) -> void:
	var shown := clampf((height - RING_FROM) / (1.0 - RING_FROM), 0.0, 1.0)
	var beat := _heartbeat()
	var flash := clampf((_flash_until - float(Time.get_ticks_msec())) / FLASH_MS, 0.0, 1.0)
	var tint := _tint()
	if ring != null:
		ring.visible = shown > 0.01
		# Added over the block, a little over full strength so the light reads on pale stone.
		ring.modulate = Color(tint.r * RING_BOOST, tint.g * RING_BOOST, tint.b * RING_BOOST,
			shown * clampf(0.6 + 0.4 * beat + flash, 0.0, 1.0))
	if glow != null:
		glow.visible = shown > 0.01
		glow.set(&"color", Color(tint.r, tint.g, tint.b, shown * (0.22 + 0.25 * beat + 0.4 * flash)))
		glow.queue_redraw()


## 0..1: two quick beats a `dungeon.seal.pulseMs` period, then rest.
func _heartbeat() -> float:
	var period := maxf(0.1, (DungeonState.number("seal.pulseMs", 1300.0) if not Engine.is_editor_hint() else 1300.0) / 1000.0)
	var phase := fmod(_clock, period) / period
	var first := exp(-pow(phase / BEAT_WIDTH, 2.0))
	var second := SECOND_BEAT * exp(-pow((phase - SECOND_BEAT_AT) / BEAT_WIDTH, 2.0))
	var wrap := exp(-pow((phase - 1.0) / BEAT_WIDTH, 2.0))
	return clampf(maxf(maxf(first, second), wrap), 0.0, 1.0)


## The boss's colour: the world's Dungeon node's `seal_color`, else `ring_color`.
func _tint() -> Color:
	if not Engine.is_editor_hint() and is_inside_tree():
		var dungeon := DungeonState.current(get_tree())
		if dungeon != null:
			var color: Variant = dungeon.get(&"seal_color")
			if color is Color:
				return color
	return ring_color


func _ring_point() -> Vector2:
	return ring.to_global(ring.offset) if ring != null else global_position


func _dungeon_sealed() -> bool:
	if Engine.is_editor_hint() or not is_inside_tree():
		return false
	return DungeonState.is_sealed(Services.run(), DungeonState.current_id(get_tree()))


# --- the ring's picture until the art is packed ------------------------------------------------------

## A white ring of light (a soft band with a bright core), tinted by `modulate`: used when the ring
## has no picture (seal-ring.webp missing).
static func ring_texture() -> Texture2D:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var middle := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(middle) / (size * 0.5)
			var band := exp(-pow((distance - 0.72) / 0.09, 2.0))
			var core := exp(-pow((distance - 0.72) / 0.03, 2.0))
			var a := clampf(band * 0.7 + core, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(image)

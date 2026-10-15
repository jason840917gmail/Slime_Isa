extends Node2D
## Scene script of `object.heavy-plate` (game/scenes/objects/heavy-plate.tscn; bomb-lantern-and-secrets
## design section 4; BODY_SHAPES.md "Heavy plates and heavy blocks"; numbers in game-constants.json
## `puzzles.heavyPlate`). A stone plate that only a heavy weight sinks: the Stone slime (a form that
## `presses_plates`, its feet within `playerRadiusPx` of the plate, not in the air) or a heavy block
## (group `heavy_blocks`, its `weight_point()` within `blockRadiusPx`).
##
## - Loaded, it sinks from up to fully down over `sinkMs` (3000); unloaded, it rises back over
##   `riseMs` (5000). Weight coming back while it rises sinks it again from where it is.
## - Its gates (every `gate` with `gate_id`) open only when it is fully down. They stay open while
##   it rises and shut the moment it is fully up again (GateScript.close), unless another heavy
##   plate of the same gate still holds them (`holds_gate_open`). A block left on it keeps it down.
## - It shows its depth (owner, 2026-10-14: only the pressable top moves, never the whole plate):
##   the **base** (a stone socket ring) stays put and the **cap** (a stone slab with a carved weight
##   glyph) slides `sinkPx` down into it as it sinks and back up as it rises, darkening as it goes
##   down; fully down the cap shows its pressed picture (the glyph lit). The ring's front is drawn
##   over the cap, so the cap goes in behind it. The art is
##   asset/MAPS/props/heavy-plate/base-2x1.webp (full, front) and cap-2x1.webp (released, pressed),
##   packed by scripts/art/pack-heavy-plate-art.py; until those files are imported the plate draws
##   a stand-in: the pressure-plate art's pressed frame as the base with a code-drawn cap over it.
##   The shapes' goo charge ring (game/shapes/goo_ring.gd, as the Goo Bomb's cast sets it up) fills
##   as it sinks and drains as it rises, taking the light colour and pulsing while fully down, and a
##   grinding cue ticks every `grindIntervalMs` while it moves (`HeavyPlateGrind`; a placeholder
##   until its take exists).
##
## The gameplay clock (`Services.now_ms()`) drives the depth, so hit-stop and menus hold it.
## Nothing is saved: a world entered again starts with the plate up.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const GooRing := preload("res://game/shapes/goo_ring.gd")
const ShapeVisuals := preload("res://game/shapes/shape_visuals.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")

const GROUP := &"heavy_plates"
const GATE_GROUP := &"gate"
const BLOCK_GROUP := &"heavy_blocks"
const CONSTANTS := "puzzles.heavyPlate"
const CUE_GRIND := &"HeavyPlateGrind"
const CUE_DOWN := &"HeavyPlateDown"
const CUE_UP := &"HeavyPlateUp"
## Cues without a take yet play these instead.
const PLACEHOLDER_CUES := {
	CUE_GRIND: &"GroundCreak",
	CUE_DOWN: &"PlatePress",
	CUE_UP: &"PlateRelease",
}
## The grind's pitch while sinking and while rising (a placeholder's character).
const GRIND_PITCH_SINK := 0.7
const GRIND_PITCH_RISE := 0.85
## The art (2 px per unit, drawn at ART_SCALE): the base sheet's cells (full, front) and the cap
## sheet's (released, pressed), placed from the root (the opening's middle) by the pack script's
## numbers. At rest the cap stands ART_CAP_RAISE of the travel above its seat.
const ART_BASE := "res://asset/MAPS/props/heavy-plate/base-2x1.webp"
const ART_CAP := "res://asset/MAPS/props/heavy-plate/cap-2x1.webp"
const ART_SCALE := 0.5
const ART_BASE_OFFSET := Vector2(-41.5, -24.3)
const ART_CAP_OFFSET := Vector2(-26.6, -18.2)
const ART_CAP_RAISE := 0.8
## The stand-in: the pressure-plate sheet's pressed frame (8 frames of 256 px, its opening at
## STAND_IN_CENTRE) at STAND_IN_SCALE, and a code-drawn cap the size of that opening.
const STAND_IN_SHEET := preload("res://asset/MAPS/props/256x256-tile_8x1-gulp-props.webp")
const STAND_IN_FRAME := 7
const STAND_IN_CENTRE := Vector2(129.5, 190.0)
const STAND_IN_SCALE := 0.62
const STAND_IN_TINT := Color(0.8, 0.82, 0.86, 1.0)
const STAND_IN_CAP_HALF := Vector2(21.0, 11.5)
const STAND_IN_CAP_RAISE := 0.65
const CAP_TOP := Color(0.64, 0.62, 0.58)
const CAP_SIDE := Color(0.4, 0.37, 0.33)
const CAP_LINE := Color(0.24, 0.16, 0.1)
const GLYPH_DARK := Color(0.3, 0.27, 0.24)
const PIT := Color(0.1, 0.08, 0.06, 0.92)
## How dark the cap gets fully down (multiplied into its colour).
const DOWN_SHADE := 0.72
const RING_NAME := "HeavyPlateRing"

## The gates it opens ("" = none).
@export var gate_id: String = ""

## The plate reached the bottom. Payload: {"gateId"}.
signal pressed(payload: Dictionary)
## The plate is fully up again. Payload: {"gateId"}.
signal released(payload: Dictionary)

var _depth: float = 0.0
var _down: bool = false
var _holding_open: bool = false
var _last_ms: float = -1.0
var _next_grind_ms: float = 0.0
var _base_art: Texture2D
var _cap_art: Texture2D
var _ring: GooRing
var _sink_ms: float = 3000.0
var _rise_ms: float = 5000.0
var _sink_px: float = 6.0
var _player_radius: float = 30.0
var _block_radius: float = 24.0
var _grind_ms: float = 420.0


func _ready() -> void:
	add_to_group(GROUP)
	_sink_ms = maxf(1.0, _setting("sinkMs", _sink_ms))
	_rise_ms = maxf(1.0, _setting("riseMs", _rise_ms))
	_sink_px = _setting("sinkPx", _sink_px)
	_player_radius = _setting("playerRadiusPx", _player_radius)
	_block_radius = _setting("blockRadiusPx", _block_radius)
	_grind_ms = maxf(50.0, _setting("grindIntervalMs", _grind_ms))
	if ResourceLoader.exists(ART_BASE) and ResourceLoader.exists(ART_CAP):
		_base_art = load(ART_BASE) as Texture2D
		_cap_art = load(ART_CAP) as Texture2D
	_make_ring()
	_show()


## 0 (up) .. 1 (fully down).
func depth() -> float:
	return _depth


## True from the moment it reached the bottom until it is fully up again (its gates are open).
func holds_gate_open() -> bool:
	return _holding_open


func is_loaded() -> bool:
	return _loaded()


func _physics_process(_delta: float) -> void:
	var now := Services.now_ms()
	if _last_ms < 0.0:
		_last_ms = now
	var step_ms := maxf(0.0, now - _last_ms)
	_last_ms = now
	var before := _depth
	if _loaded():
		_depth = minf(1.0, _depth + step_ms / _sink_ms)
	else:
		_depth = maxf(0.0, _depth - step_ms / _rise_ms)
	if _depth != before:
		_grind(now, _depth > before)
		_show()
	if _depth >= 1.0 and not _down:
		_down = true
		_holding_open = true
		_cue(CUE_DOWN)
		_set_gates(true)
		pressed.emit({"gateId": gate_id})
	elif _depth < 1.0 and _down:
		_down = false
		_show()
	if _depth <= 0.0 and _holding_open:
		_holding_open = false
		_cue(CUE_UP)
		_set_gates(false)
		released.emit({"gateId": gate_id})
	_pulse_ring()


## A heavy block on it, or the Stone slime standing on it.
func _loaded() -> bool:
	var at := global_position
	for block: Node in get_tree().get_nodes_in_group(BLOCK_GROUP):
		if block.has_method(&"weight_point") and (block.call(&"weight_point") as Vector2).distance_to(at) <= _block_radius:
			return true
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player) or not bool(player.call(&"presses_plates")):
		return false
	if bool(player.call(&"is_airborne")):
		return false
	var body := player.get(&"body") as Node2D
	return body != null and body.global_position.distance_to(at) <= _player_radius


func _set_gates(open_now: bool) -> void:
	if gate_id.is_empty():
		return
	if not open_now:
		for plate: Node in get_tree().get_nodes_in_group(GROUP):
			if plate != self and str(plate.get(&"gate_id")) == gate_id and bool(plate.call(&"holds_gate_open")):
				return
	for gate: Node in get_tree().get_nodes_in_group(GATE_GROUP):
		if str(gate.get(&"gate_id")) != gate_id:
			continue
		if open_now:
			gate.call(&"open")
		elif gate.has_method(&"close"):
			gate.call(&"close")


# --- the look ------------------------------------------------------------------------------------

## The plate's art (the base and cap sheets); null draws the stand-in. `_ready` loads it once the
## files are imported.
func set_art(base: Texture2D, cap: Texture2D) -> void:
	_base_art = base
	_cap_art = cap
	queue_redraw()


func uses_art() -> bool:
	return _base_art != null and _cap_art != null


func _draw() -> void:
	if uses_art():
		_draw_art()
	else:
		_draw_stand_in()


## The base, the cap slid down by the depth (its pressed picture at the bottom), the ring's front.
func _draw_art() -> void:
	var base_cell := Vector2(_base_art.get_width() / 2.0, _base_art.get_height())
	var cap_cell := Vector2(_cap_art.get_width() / 2.0, _cap_art.get_height())
	var base_rect := Rect2(ART_BASE_OFFSET, base_cell * ART_SCALE)
	draw_texture_rect_region(_base_art, base_rect, Rect2(Vector2.ZERO, base_cell))
	var cap_at := ART_CAP_OFFSET + Vector2(0.0, _cap_y(ART_CAP_RAISE))
	var pressed := 1.0 if _depth >= 1.0 else 0.0
	draw_texture_rect_region(_cap_art, Rect2(cap_at, cap_cell * ART_SCALE), Rect2(Vector2(cap_cell.x * pressed, 0.0), cap_cell), _shade())
	draw_texture_rect_region(_base_art, base_rect, Rect2(Vector2(base_cell.x, 0.0), base_cell))


## Until the art is imported: the pressure-plate art's pressed frame is the base, its opening is a
## dark pit while the cap is up, and a code-drawn stone cap (side edge, top face, weight glyph)
## slides into it; fully down the base's own pressed tile (the glyph lit) shows.
func _draw_stand_in() -> void:
	var frame := Vector2(256.0, 256.0)
	var region := Rect2(Vector2(frame.x * STAND_IN_FRAME, 0.0), frame)
	draw_texture_rect_region(STAND_IN_SHEET, Rect2(-STAND_IN_CENTRE * STAND_IN_SCALE, frame * STAND_IN_SCALE), region, STAND_IN_TINT)
	if _depth >= 1.0:
		return
	var half := STAND_IN_CAP_HALF
	var grow := Vector2(1.0, 1.0)
	_ellipse(Vector2.ZERO, half + grow, PIT)
	var y := _cap_y(STAND_IN_CAP_RAISE)
	var edge := maxf(0.0, -y) + 1.0
	var shade := _shade()
	_ellipse(Vector2(0.0, y + edge), half + grow, CAP_LINE)
	_ellipse(Vector2(0.0, y + edge), half, CAP_SIDE * shade)
	draw_rect(Rect2(Vector2(-half.x, y), Vector2(half.x * 2.0, edge)), CAP_SIDE * shade)
	_ellipse(Vector2(0.0, y), half + grow, CAP_LINE)
	_ellipse(Vector2(0.0, y), half, CAP_TOP * shade)
	_ellipse(Vector2(-4.0, y - 3.0), half * Vector2(0.6, 0.45), Color(1.0, 0.97, 0.88, 0.12))
	var glyph := PackedVector2Array([Vector2(-2.5, -7.0), Vector2(2.5, -7.0), Vector2(2.5, -4.0), Vector2(6.5, -4.0),
		Vector2(9.0, 5.0), Vector2(-9.0, 5.0), Vector2(-6.5, -4.0), Vector2(-2.5, -4.0)])
	for i in glyph.size():
		glyph[i] = glyph[i] * Vector2(1.1, 0.85) + Vector2(0.0, y)
	draw_colored_polygon(glyph, GLYPH_DARK * shade)


## The cap's offset: `raise` of the travel above its seat at rest, the rest below it fully down.
func _cap_y(raise: float) -> float:
	return _sink_px * (_depth - raise)


func _shade() -> Color:
	var shade := lerpf(1.0, DOWN_SHADE, _depth)
	return Color(shade, shade, shade, 1.0)


func _ellipse(centre: Vector2, half: Vector2, colour: Color) -> void:
	var points := PackedVector2Array()
	for i in 32:
		var angle := TAU * float(i) / 32.0
		points.append(centre + Vector2(cos(angle) * half.x, sin(angle) * half.y))
	draw_colored_polygon(points, colour)


func _show() -> void:
	queue_redraw()
	if _ring != null:
		_ring.visible = _depth > 0.0
		_ring.set_progress(_depth)
		_ring.set_color(_stone_colour().lightened(ShapeVisuals.LIGHT_SHARE) if _depth >= 1.0 else _stone_colour())


## The ring around the plate, set up as the shapes' charge ring (radius `ringRadiusPx`, squashed).
func _make_ring() -> void:
	_ring = GooRing.new()
	_ring.name = RING_NAME
	_ring.radius_px = _setting("ringRadiusPx", 40.0)
	_ring.scale = Vector2(1.0, ShapeVisuals.RING_SQUASH_Y)
	_ring.position = Vector2(0.0, 6.0)
	_ring.set_color(_stone_colour())
	_ring.set_progress(0.0)
	_ring.visible = false
	add_child(_ring)


## Fully down, the ring pulses as a full charge ring does (real time, presentation only).
func _pulse_ring() -> void:
	if _ring == null:
		return
	var pulse := 1.0
	if _depth >= 1.0:
		var age := float(Time.get_ticks_msec()) / 1000.0
		pulse = 1.0 + ShapeVisuals.RING_PULSE * sin(age * TAU * ShapeVisuals.RING_PULSE_HZ)
	_ring.scale = Vector2(pulse, ShapeVisuals.RING_SQUASH_Y * pulse)


static func _stone_colour() -> Color:
	var form := GulpForms.by_id(GulpForms.HEAVY)
	return form.get("color", Color("#c9cfd6"))


func _grind(now: float, sinking: bool) -> void:
	if now < _next_grind_ms:
		return
	_next_grind_ms = now + _grind_ms
	_cue(CUE_GRIND, {"pitch": GRIND_PITCH_SINK if sinking else GRIND_PITCH_RISE})


static func _cue(cue: StringName, payload: Variant = null) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var root: Node = feel.global_audio()
	var play := cue
	if root == null or root.find_child(String(cue), true, false) == null:
		play = PLACEHOLDER_CUES.get(cue, cue)
	feel.audio_cue(play, payload)


static func _setting(key: String, fallback: float) -> float:
	var constants := Services.constants()
	return float(constants.value(CONSTANTS + "." + key, fallback)) if constants != null else fallback

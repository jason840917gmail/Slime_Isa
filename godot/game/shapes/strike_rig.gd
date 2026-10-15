@tool
extends Node2D
## The strike rig (docs/design/2026-10-12-weapon-strike-frames.md, rounds 4 and 5; BODY_SHAPES.md "Editing the
## strike animations"): draws a body shape's weapon on a strike. In the game it is a node of the player scene
## under the slime's Visual (game/characters/player_slime.tscn); the Inspector's strike preview
## (addons/strike_preview) builds the same nodes for each of its views. It draws the rigid weapon from the socket
## along `angle` at `length` (the Axe's and the Hammer's handle and head, or a weapon view; the Spear's spear),
## the code neck over the body and the swoosh along the head's recent path, on three canvas items under the
## Visual, scaled so their px are game px from the Visual's origin (the slime's centre): this node
## (`show_behind_parent`: the `behind` layer, under the body), FRONT_NODE (z 1: a `front` weapon past its neck's
## tip, and the overlay) and NECK_NODE (over the body: the neck). Mirrored (sockets and angles, a -> 180 - a)
## while the Visual is flipped.
##
## What it draws: `animation` (a StrikeAnimation, game/characters/strikes/) in `direction`, `clock_ms` into a step
## of `timing` (StrikeLibrary.state_at); nothing while `clock_ms` < 0. The shape controller sets them every physics
## step (ShapePoses), so a hit-stop freezes the weapon with the body. The rig never changes its Visual: the game's
## strike animation sets the body frame, and the preview sets its own Visual. `show_overlay` draws the step's hit
## area at that time from the direction's hit centre, a ring at the hit's far edge, the hit centre's cross and the
## ring's handle, the body's edge along the aim, the weapon's far tip, the socket and (with `overlay_text`) the
## readouts, in the editor and, with `overlay_in_game`, in captures. A negative `arm_px` pulls the weapon in.
##
## Owner: shapes.

const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapeStrikes := preload("res://game/shapes/shape_strikes.gd")
const ShapeStrike := preload("res://game/shapes/shape_strike.gd")
const StrikeLibrary := preload("res://game/shapes/strike_library.gd")
const AnimationType := preload("res://game/shapes/strike_animation.gd")

const NODE_NAME := "StrikeRig"
const FRONT_NODE := "StrikeRigFront"
const NECK_NODE := "StrikeRigNeck"
const WEAPON_NONE := "none"
const WEAPON_SPEAR := "spear"
const LAYER_BEHIND := 0
const LAYER_FRONT := 1
const VIEW_SIDE := "side"
const DEFAULT_DIRECTION := "side"

## Screen px per texture px of the slime's own sheet: the rig draws in these units so the form skin's
## pattern is as big on the weapon as on the slime (ShapeVisuals uses the same).
const SKIN_UNIT_PX := 0.28125
## The painted weapons (lying horizontal: root left, tip right), the Axe swoosh, and the packer's
## numbers (texture px; shapes.json, ART_FALLBACK where it has none). ShapeVisuals' drawing of the Spin
## reads the axe's here too (`art`).
const SPEAR_TEXTURE := preload("res://asset/characters/shapes/spear.webp")
const AXE_TEXTURE := preload("res://asset/characters/shapes/axe.webp")
const HAMMER_TEXTURE := preload("res://asset/characters/shapes/hammer.webp")
const SWOOSH_TEXTURE := preload("res://asset/MAPS/effects/shape-axe-swoosh.webp")
const ART_DATA_PATH := "res://asset/characters/shapes/shapes.json"
const ART_FALLBACK := {
	"spear": {"shaft_px": 18.0, "root_end": 92.0, "head_start": 417.0},
	"axe": {"head_start": 200.0},
	"hammer": {"head_start": 184.0},
}
## Where the crescent lies in shape-axe-swoosh.webp (texture px), its opacity.
const SWOOSH_CENTRE := Vector2(115.0, 196.0)
const SWOOSH_TAIL_DEG := -118.0
const SWOOSH_LEAD_DEG := 106.0
const SWOOSH_INNER_R := 90.0
const SWOOSH_OUTER_R := 195.0
const SWOOSH_ALPHA := 0.85

## The Axe and the Hammer: the handle's centre row where a weapon block gives no `axis_row`, the head
## texture drawn before `head_start` over the stalk where the Hammer's head turns away (the collar),
## the neck's grow-out share of the length and its least width while it grows, a head this close to
## square with its stalk not cut along the stalk.
const WEAPON_AXIS_ROWS := {"axe": 211.5, "hammer": 232.0}
const HEAD_COLLAR_TX := 16.0
const NECK_GROW_SHARE := 0.25
const NECK_MIN_ACROSS := 0.6
const HEAD_CLIP_DOT := 0.15
## The swoosh: the head's path over the last SWOOSH_TRAIL_MS sampled every SWOOSH_STEP_MS (gameplay ms)
## while the side weapon turned SWOOSH_MIN_TURN deg a ms one way, or a view's head moved
## SWOOSH_MIN_SPEED px a ms; it fades over SWOOSH_FADE_MS once the head slows, runs SWOOSH_IN_PX inside
## the head to SWOOSH_OUT_PX past it, and a step turning SWOOSH_CUT_DEG or moving SWOOSH_CUT_PX is a cut.
const SWOOSH_TRAIL_MS := 120.0
const SWOOSH_STEP_MS := 8.0
const SWOOSH_MIN_TURN := 0.6
const SWOOSH_MIN_SPEED := 0.35
const SWOOSH_FADE_MS := 110.0
const SWOOSH_IN_PX := 5.0
const SWOOSH_OUT_PX := 3.0
const SWOOSH_CUT_DEG := 90.0
const SWOOSH_CUT_PX := 40.0
## The Spear: its hidden end at least `spear_inside`; at least the arrowhead and the neck's fade plus
## SPEAR_MIN_EXTRA_PX showing; the root blob's flare kept clear past `root_end` (texture px).
const SPEAR_MIN_EXTRA_PX := 1.5
const ROOT_FLARE_TX := 20.0

## The editor overlay: colours, the circle's points, the label size (game px).
const HIT_FILL := Color(1.0, 0.25, 0.2, 0.22)
const HIT_LINE := Color(1.0, 0.35, 0.3, 0.9)
const HIT_IDLE := Color(1.0, 0.85, 0.3, 0.55)
const RING_COLOR := Color(0.4, 0.85, 1.0, 0.7)
const EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const TIP_COLOR := Color(0.55, 1.0, 0.45, 0.95)
## The socket's dot (where the weapon leaves the body), game px.
const SOCKET_COLOR := Color(1.0, 0.35, 0.85, 0.95)
const SOCKET_DOT_PX := 1.0
## The hit centre's cross and the ring's handle (the preview drags them), game px; `overlay_hot` values.
const CENTRE_COLOR := Color(1.0, 0.78, 0.25, 0.98)
const HANDLE_COLOR := Color(0.45, 0.9, 1.0, 0.98)
const HANDLE_PX := 3.5
const HOT_NONE := 0
const HOT_CENTRE := 1
const HOT_RING := 2
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const TEXT_SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const CIRCLE_POINTS := 40
const FONT_SIZE := 7

## The strike drawn (a StrikeAnimation) and its direction ("side", "down", "up"): set by the game or the preview.
var animation: AnimationType:
	set(value):
		animation = value
		_changed()
var direction: String = DEFAULT_DIRECTION:
	set(value):
		direction = value
		_changed()
## The overlay (the hit area, the reach ring, the body's edge, the tip, the socket): drawn in the editor, and in the
## game with `overlay_in_game`; `overlay_text` adds its readouts (the preview shows them as text instead).
var show_overlay: bool = true:
	set(value):
		show_overlay = value
		_changed()
var overlay_text: bool = true:
	set(value):
		overlay_text = value
		_changed()
## The overlay handle the preview's pointer is on or drags (HOT_NONE, HOT_CENTRE, HOT_RING): drawn larger.
var overlay_hot: int = HOT_NONE:
	set(value):
		overlay_hot = value
		_changed()

## Runtime state (the shape controller, ShapeVisuals, the preview): the strike's elapsed gameplay ms (< 0: no strike,
## nothing drawn), the step's windup / active / recovery ms (x < 0: the step's own timing from game-constants.json),
## the weapon's colour (white in the form skin, else the form's tint), the Spear's wall-cut reach (< 0: the
## direction's `hit_reach`), and the overlay outside the editor (captures).
var clock_ms: float = -1.0:
	set(value):
		clock_ms = value
		_changed()
var timing: Vector3 = Vector3(-1.0, -1.0, -1.0):
	set(value):
		timing = value
		_changed()
var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_changed()
var reach_override: float = -1.0
var overlay_in_game: bool = false

static var _art_data: Dictionary = {}
static var _textures: Dictionary = {}
static var _images: Dictionary = {}


func _ready() -> void:
	for node_name: String in [FRONT_NODE, NECK_NODE]:
		var node := get_node_or_null(NodePath("../" + node_name)) as CanvasItem
		if node != null:
			var painter := _draw_front if node_name == FRONT_NODE else _draw_neck
			if not node.draw.is_connected(painter):
				node.draw.connect(painter)


func _process(_delta: float) -> void:
	# In the editor (the Inspector's preview) the setters redraw it, so a paused preview lets the editor idle.
	if is_active() and not Engine.is_editor_hint():
		_changed()


## True while the rig draws: a strike is set and its clock runs (`clock_ms` >= 0).
func is_active() -> bool:
	return animation != null and clock_ms >= 0.0


## The slime's Visual (the parent).
func visual() -> Sprite2D:
	return get_parent() as Sprite2D


func _changed() -> void:
	queue_redraw()
	if not is_inside_tree():
		return
	for node_name: String in [FRONT_NODE, NECK_NODE]:
		var node := get_node_or_null(NodePath("../" + node_name)) as CanvasItem
		if node != null:
			node.queue_redraw()


# --- the strike's time and state -----------------------------------------------------------------------

## The step's (windup, active, recovery) ms the strike maps its time with: the game's, else the step's own timing
## from game-constants.json.
func _timing_now() -> Vector3:
	return timing if timing.x >= 0.0 else StrikeLibrary.timing_of(animation)


## What the rig draws now (state_at_ms at `clock_ms`); {} while nothing is drawn.
func state_now() -> Dictionary:
	if animation == null or clock_ms < 0.0:
		return {}
	return state_at_ms(clock_ms, _timing_now())


## The state `elapsed` ms into a step of `step_timing` (StrikeLibrary.state_at), with the weapon's shape, the
## frame's socket (StrikeLibrary.socket: game px from the slime's centre, unmirrored) and its knob's width.
func state_at_ms(elapsed: float, step_timing: Vector3) -> Dictionary:
	var state := StrikeLibrary.state_at(animation, direction, elapsed, step_timing)
	var number := int(state["frame"])
	var socket := StrikeLibrary.socket(animation, direction, number)
	state["weapon"] = animation.shape if animation != null else WEAPON_NONE
	state["socket"] = socket if socket.is_finite() else Vector2.ZERO
	state["knob_w"] = ShapeStrikes.knob_w(StrikeLibrary.strike_of(animation), direction, number)
	return state


## The weapon's socket at the strike's contact (the windup's end: StrikeLibrary.contact_socket); Vector2.INF without one.
func _contact_socket_now() -> Vector2:
	return StrikeLibrary.contact_socket(animation, direction)


## The strike and its direction as a name ("axe-chop-up") for the overlay's readout.
func _label() -> String:
	return "%s-%s" % [StrikeLibrary.strike_of(animation), direction]


# --- drawing ------------------------------------------------------------------------------------------

func _draw() -> void:
	if not is_active():
		return
	if show_overlay and (Engine.is_editor_hint() or overlay_in_game):
		_draw_overlay_fill(self)
	var geometry := geometry_of(state_now())
	if geometry.is_empty():
		return
	if str(geometry["kind"]) == WEAPON_SPEAR:
		_draw_spear(self, geometry, 0.0, float(geometry["split"]))
		return
	var front := int(geometry["layer"]) == LAYER_FRONT
	if not front:
		_draw_swoosh_trail(self)
	_draw_parts(self, geometry, -INF, float(geometry["neck_len"]) if front else INF)


func _draw_front() -> void:
	var node := get_node_or_null(NodePath("../" + FRONT_NODE)) as CanvasItem
	if node == null or not is_active():
		return
	var geometry := geometry_of(state_now())
	if not geometry.is_empty():
		if str(geometry["kind"]) == WEAPON_SPEAR:
			if float(geometry["split"]) < INF:
				_draw_spear(node, geometry, float(geometry["split"]), INF)
		elif int(geometry["layer"]) == LAYER_FRONT:
			_draw_swoosh_trail(node)
			_draw_parts(node, geometry, float(geometry["neck_len"]), INF)
	if show_overlay and (Engine.is_editor_hint() or overlay_in_game):
		_draw_overlay(node, geometry)


func _draw_neck() -> void:
	var node := get_node_or_null(NodePath("../" + NECK_NODE)) as CanvasItem
	if node == null or not is_active():
		return
	var geometry := geometry_of(state_now())
	if not geometry.is_empty() and str(geometry["kind"]) != WEAPON_SPEAR:
		_draw_neck_on(node, geometry)


## The weapon of `state` (state_at_ms) in the rig's px: for the Spear {"kind": "spear", "socket",
## "axis", "inside", "visible", "fade", "head", "scale", "flipped", "split", "color"}; for the Axe and
## the Hammer {"kind", "socket", "axis", "head_axis", "layer", "flipped", "texture", "scale",
## "head_start", "axis_row", "color", "hidden", "handle_from", "joint", "head_depth", "handle_across",
## "neck_texture", "neck_scale", "neck_root_x", "neck_arm", "neck_axis_row", "neck_len", "neck_grow",
## "length", "view" ({} for the side weapon)}; {} for none or without the manifest's numbers.
func geometry_of(state: Dictionary) -> Dictionary:
	var name := str(state.get("weapon", WEAPON_NONE))
	if name == WEAPON_NONE or name.is_empty():
		return {}
	var flipped := visual() != null and visual().flip_h
	var raw_socket: Vector2 = state.get("socket", Vector2.ZERO)
	var at := Vector2(-raw_socket.x, raw_socket.y) if flipped else raw_socket
	var degrees := float(state.get("angle", 0.0))
	var axis := Vector2.from_angle(deg_to_rad(180.0 - degrees if flipped else degrees))
	var amount := clampf(float(state.get("length", 1.0)), 0.0, 1.0)
	if name == WEAPON_SPEAR:
		return _spear_geometry(state, at, axis, amount, flipped)
	var block := ShapeStrikes.weapon_block(name)
	var texture := manifest_texture(str(block.get("texture", "")))
	if texture == null:
		return {}
	# The neck: its root as wide as the knob, its tube stretched by the arm as far as the weapon is out.
	var neck := ShapeStrikes.neck()
	var neck_texture := manifest_texture(str(neck.get("texture", "")))
	var root_px := ShapeDefs.num(neck, "width_px")
	var knob := float(state.get("knob_w", 0.0))
	var neck_scale := knob / root_px if neck_texture != null and knob > 0.0 and root_px > 0.0 else 0.0
	var root_x := ShapeDefs.num(neck, "root_x")
	var neck_own := maxf(0.0, ShapeDefs.num(neck, "tip_x") - root_x) * neck_scale
	# `arm_px`, as far as the weapon is out: positive stretches the neck's tube, negative pulls the weapon back
	# into the jelly by that many px (the tube at its own length).
	var reach_px := float(state.get("arm_px", 0.0)) * amount
	var arm := maxf(0.0, reach_px)
	var pull := maxf(0.0, -reach_px)
	# The weapon: rigid, its handle from its hidden end to `handle_px` past the neck's tip, slid back by
	# the share not out (the arm left out: it pulls in by itself) and by the arm's pull.
	var scale_px := ShapeDefs.num(block, "scale")
	var head_start := ShapeDefs.num(block, "head_start", float(art(name).get("head_start", 0.0)))
	var hidden := maxf(0.0, ShapeDefs.num(block, "hidden_px"))
	var head_depth := maxf(0.0, float(texture.get_width()) - head_start) * scale_px
	var handle_px := ShapeDefs.num(block, "handle_px")
	var joint := neck_own + arm + handle_px
	var slide := (1.0 - amount) * (hidden + neck_own + handle_px + head_depth) + pull
	var head_degrees := float(state.get("head_angle", degrees))
	var gain := ShapeStrikes.gain_of(block)
	var view_state := _view_geometry(name, str(state.get("view", VIEW_SIDE)), int(state.get("view_frame", 1)), at,
		rad_to_deg(axis.angle()), flipped, amount, hidden, neck_own, arm, pull)
	return {
		"kind": name,
		"view": view_state,
		"socket": at,
		"axis": axis,
		"head_axis": Vector2.from_angle(deg_to_rad(180.0 - head_degrees if flipped else head_degrees)),
		"layer": int(state.get("layer", LAYER_BEHIND)),
		"flipped": flipped,
		"texture": texture,
		"scale": scale_px,
		"head_start": head_start,
		"axis_row": ShapeDefs.num(block, "axis_row", float(WEAPON_AXIS_ROWS.get(name, texture.get_height() * 0.5))),
		"color": Color(tint.r * gain.r, tint.g * gain.g, tint.b * gain.b, tint.a),
		"hidden": hidden,
		"handle_from": -hidden - slide,
		"joint": joint - slide,
		"head_depth": head_depth,
		"handle_across": clampf(ShapeDefs.num(block, "handle_across", 1.0), 0.0, 1.0),
		"neck_texture": neck_texture,
		"neck_scale": neck_scale,
		"neck_root_x": root_x,
		"neck_arm": arm,
		"neck_axis_row": ShapeDefs.num(neck, "axis_row", neck_texture.get_height() * 0.5 if neck_texture != null else 0.0),
		"neck_len": neck_own + arm,
		"neck_grow": clampf(amount / NECK_GROW_SHARE, 0.0, 1.0),
		"length": amount,
	}


## The Spear's geometry (see `geometry_of`): spear.webp without its root blob, anchored at its
## arrowhead, `spear_shaft` px wide, from its hidden end `spear_inside` behind the socket; showing the
## arrowhead and `length` of its shaft up to the hit line's end (the reach from the hit centre less the
## contact socket's, along the aim), at least the arrowhead and the neck's fade; `front` splits it at the
## neck's fade end (the root behind the body, the rest over the world).
func _spear_geometry(state: Dictionary, at: Vector2, axis: Vector2, amount: float, flipped: bool) -> Dictionary:
	var spear_art := art(WEAPON_SPEAR)
	if amount <= 0.0 or spear_art.is_empty():
		return {}
	var scale_px := float(state.get("spear_shaft", 5.0)) / maxf(1.0, float(spear_art["shaft_px"]))
	var head := (float(spear_art["width"]) - float(spear_art["head_start"])) * scale_px
	var reach := reach_override if reach_override >= 0.0 else float(state.get("hit_reach", 0.0))
	var line_from := _contact_socket_now()
	if not line_from.is_finite():
		line_from = Vector2(absf(at.x), at.y)
	var centre: Vector2 = state.get("hit_center", Vector2.ZERO)
	if flipped:
		line_from.x = -line_from.x
		centre.x = -centre.x
	var full := maxf(0.0, reach + centre.dot(axis) - line_from.dot(axis))
	var fade := float(state.get("spear_fade", 0.0))
	var visible := head + amount * maxf(0.0, full - head)
	visible = maxf(visible, fade + head + SPEAR_MIN_EXTRA_PX)
	var inside := float(state.get("spear_inside", 0.0))
	var gain := ShapeStrikes.tint_gain()
	return {"kind": WEAPON_SPEAR, "socket": at, "axis": axis, "inside": inside, "visible": visible, "fade": fade,
		"head": head, "scale": scale_px, "flipped": flipped,
		"split": inside + fade if int(state.get("layer", LAYER_BEHIND)) == LAYER_FRONT else INF,
		"color": Color(tint.r * gain.r, tint.g * gain.g, tint.b * gain.b, tint.a)}


## The Spear (`_spear_geometry`) on `canvas` from its hidden end, the part from `clip_from` to
## `clip_to` (game px from the hidden end): spear.webp anchored at its arrowhead's tip and scaled both
## ways, cut at its hidden end; where that is longer than the shaft past the root blob's flare, the
## shaft stretches behind the whole arrowhead; mirrored across the aim when flipped.
static func _draw_spear(canvas: CanvasItem, spear: Dictionary, clip_from: float, clip_to: float) -> void:
	var spear_art := art(WEAPON_SPEAR)
	var texture: Texture2D = spear_art["texture"]
	var width: float = spear_art["width"]
	var height: float = spear_art["height"]
	var head_start: float = spear_art["head_start"]
	var scale_px: float = spear["scale"]
	var head: float = spear["head"]
	var total := float(spear["inside"]) + float(spear["visible"])
	if scale_px <= 0.0 or total <= 0.5:
		return
	var axis: Vector2 = spear["axis"]
	var from := (spear["socket"] as Vector2) - axis * float(spear["inside"])
	var flip: bool = spear["flipped"]
	var color: Color = spear["color"]
	var row := height * 0.5
	var shaft_from := float(spear_art["root_end"]) + ROOT_FLARE_TX
	var cut := width - total / scale_px
	if cut >= shaft_from:
		slice_on_axis(canvas, texture, Rect2(cut, 0.0, width - cut, height), from, axis, 0.0, total, scale_px, flip, color,
			row, clip_from, clip_to)
		return
	var shaft := maxf(0.0, total - head)
	if shaft > 0.0 and head_start > shaft_from:
		slice_on_axis(canvas, texture, Rect2(shaft_from, 0.0, head_start - shaft_from, height), from, axis, 0.0, shaft,
			scale_px, flip, color, row, clip_from, clip_to)
	slice_on_axis(canvas, texture, Rect2(head_start, 0.0, width - head_start, height), from, axis, shaft,
		minf(head, total), scale_px, flip, color, row, clip_from, clip_to)


## The Axe's or the Hammer's weapon between `clip_from` and `clip_to` (game px along its axis from the
## socket; never behind its hidden end): a weapon view while one shows, else the texture's handle (0 to
## `head_start`) stretched from `handle_from` to the joint, `handle_across` as thick, then its head
## from the joint along its own axis (where it turns away from the stalk, its collar overlaps the
## stalk's end), cut along the stalk's axis where the head runs along it, else whole while the joint
## is inside the cut.
static func _draw_parts(canvas: CanvasItem, weapon_state: Dictionary, clip_from: float, clip_to: float) -> void:
	var texture: Texture2D = weapon_state["texture"]
	var origin: Vector2 = weapon_state["socket"]
	var axis: Vector2 = weapon_state["axis"]
	var head_axis: Vector2 = weapon_state["head_axis"]
	var scale_px: float = weapon_state["scale"]
	var head_start: float = weapon_state["head_start"]
	var row: float = weapon_state["axis_row"]
	var flip: bool = weapon_state["flipped"]
	var color: Color = weapon_state["color"]
	var handle_from: float = weapon_state["handle_from"]
	var joint: float = weapon_state["joint"]
	var width := float(texture.get_width())
	var height := float(texture.get_height())
	var low := maxf(clip_from, -float(weapon_state["hidden"]))
	if not (weapon_state["view"] as Dictionary).is_empty():
		_draw_view(canvas, weapon_state, low, clip_to)
		return
	if scale_px <= 0.0 or clip_to <= low:
		return
	if head_start > 0.0 and joint > handle_from:
		slice_on_axis(canvas, texture, Rect2(0.0, 0.0, head_start, height), origin, axis, handle_from, joint - handle_from,
			scale_px * float(weapon_state["handle_across"]), flip, color, row, low, clip_to)
	var along := head_axis.dot(axis)
	var head_low := -INF
	var head_high := INF
	if along > HEAD_CLIP_DOT:
		head_low = (low - joint) / along
		head_high = (clip_to - joint) / along
	elif joint < low or joint >= clip_to:
		return
	var collar := HEAD_COLLAR_TX if along < 0.9998 else 0.0
	var from_tx := maxf(0.0, head_start - collar)
	slice_on_axis(canvas, texture, Rect2(from_tx, 0.0, width - from_tx, height), origin + axis * joint, head_axis,
		(from_tx - head_start) * scale_px, (width - from_tx) * scale_px, scale_px, flip, color, row, head_low, head_high)


## The code neck at the socket along the weapon's axis, over the body: neck.webp with its `root_x` on
## the socket, scaled so its root is as wide as the knob, its tube (`arm_from_x` to `arm_to_x`)
## stretched by the arm (the cap, the fillet, the taper and the run past it keep the knob's scale); it
## grows out (along fully, across from NECK_MIN_ACROSS) over the first NECK_GROW_SHARE of the length.
## In the weapon's colour without its tint: it is the body's jelly.
func _draw_neck_on(canvas: CanvasItem, weapon_state: Dictionary) -> void:
	var texture: Texture2D = weapon_state["neck_texture"]
	var neck_scale: float = weapon_state["neck_scale"]
	var grow: float = weapon_state["neck_grow"]
	if texture == null or neck_scale <= 0.0 or grow <= 0.0 or float(weapon_state["length"]) <= 0.0:
		return
	var neck := ShapeStrikes.neck()
	var width := float(texture.get_width())
	var height := float(texture.get_height())
	var root_x: float = weapon_state["neck_root_x"]
	var arm_from := clampf(ShapeDefs.num(neck, "arm_from_x", root_x), root_x, width)
	var arm_to := clampf(ShapeDefs.num(neck, "arm_to_x", arm_from), arm_from, width)
	var cuts: Array[float] = [0.0, root_x, arm_from, arm_to, width]
	var along := neck_scale * grow
	var across := neck_scale * lerpf(NECK_MIN_ACROSS, 1.0, grow)
	var at := -root_x * along
	for index in cuts.size() - 1:
		var span := (cuts[index + 1] - cuts[index]) * along + (float(weapon_state["neck_arm"]) * grow if index == 2 else 0.0)
		slice_on_axis(canvas, texture, Rect2(cuts[index], 0.0, cuts[index + 1] - cuts[index], height),
			weapon_state["socket"], weapon_state["axis"], at, span, across, weapon_state["flipped"], tint,
			weapon_state["neck_axis_row"])
		at += span


## A weapon view's frame `number` placed (contract note "Round 2"): its `pivot` on the neck's tip
## (`neck_own` + `arm` from `at` along `angle_deg`, screen), turned by the angle less its `dir`, at
## the view's scale, reflected across that axis when flipped, slid back with the length (the arm left
## out) and by `pull` (a negative arm): {"texture", "rect", "head", "xform" (texture px -> the rig's px)};
## {} for the side weapon.
static func _view_geometry(weapon_name: String, view_name: String, number: int, at: Vector2, angle_deg: float,
		flipped: bool, amount: float, hidden: float, neck_own: float, arm: float, pull: float = 0.0) -> Dictionary:
	if view_name == VIEW_SIDE or view_name.is_empty():
		return {}
	var entry := ShapeStrikes.view_frame_of(weapon_name, view_name, number)
	var texture := manifest_texture(str(entry.get("texture", "")))
	var scale_px := ShapeDefs.num(entry, "scale")
	if entry.is_empty() or texture == null or scale_px <= 0.0:
		return {}
	var rect: Rect2 = entry["rect"]
	var pivot: Vector2 = entry["pivot"]
	var basis := Transform2D(deg_to_rad(angle_deg), Vector2.ZERO) \
		* Transform2D(Vector2.RIGHT, Vector2.DOWN if not flipped else Vector2.UP, Vector2.ZERO) \
		* Transform2D(deg_to_rad(-float(entry["dir"])), Vector2.ZERO)
	basis = basis.scaled(Vector2(scale_px, scale_px))
	var dir := Vector2.from_angle(deg_to_rad(float(entry["dir"])))
	var reach := 0.0
	for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end,
			rect.position + Vector2(0.0, rect.size.y)]:
		reach = maxf(reach, (corner - pivot).dot(dir) * scale_px)
	var slide := (1.0 - amount) * (hidden + neck_own + reach) + pull
	var tip := at + Vector2.from_angle(deg_to_rad(angle_deg)) * (neck_own + arm - slide)
	basis.origin = tip - basis.basis_xform(pivot)
	return {"texture": texture, "rect": rect, "head": entry["head"], "xform": basis}


## A weapon view between `clip_from` and `clip_to` (game px along the weapon's axis from the socket):
## its rect as a quad, cut to the band and drawn with its UVs, in the weapon's colour.
static func _draw_view(canvas: CanvasItem, weapon_state: Dictionary, clip_from: float, clip_to: float) -> void:
	var view_state: Dictionary = weapon_state["view"]
	var texture: Texture2D = view_state["texture"]
	var rect: Rect2 = view_state["rect"]
	var xform: Transform2D = view_state["xform"]
	if clip_to <= clip_from:
		return
	var quad := PackedVector2Array([xform * rect.position, xform * (rect.position + Vector2(rect.size.x, 0.0)),
		xform * rect.end, xform * (rect.position + Vector2(0.0, rect.size.y))])
	var origin: Vector2 = weapon_state["socket"]
	var axis: Vector2 = weapon_state["axis"]
	if clip_from > -INF:
		quad = _clip_half(quad, origin, axis, clip_from, 1.0)
	if clip_to < INF:
		quad = _clip_half(quad, origin, axis, clip_to, -1.0)
	if quad.size() < 3:
		return
	var back := xform.affine_inverse()
	var size := texture.get_size()
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for point: Vector2 in quad:
		points.append(point / SKIN_UNIT_PX)
		uvs.append((back * point) / size)
	canvas.draw_set_transform_matrix(Transform2D(0.0, Vector2(SKIN_UNIT_PX, SKIN_UNIT_PX), 0.0, Vector2.ZERO))
	canvas.draw_polygon(points, PackedColorArray([weapon_state["color"]]), uvs, texture)
	canvas.draw_set_transform(Vector2.ZERO)


## `points` (a convex polygon) cut to the side of the line `bound` px along `axis` from `origin` that
## `sense` (+1: beyond it, -1: before it) keeps.
static func _clip_half(points: PackedVector2Array, origin: Vector2, axis: Vector2, bound: float,
		sense: float) -> PackedVector2Array:
	var kept := PackedVector2Array()
	var count := points.size()
	for index in count:
		var a := points[index]
		var b := points[(index + 1) % count]
		var side_a := sense * ((a - origin).dot(axis) - bound)
		var side_b := sense * ((b - origin).dot(axis) - bound)
		if side_a >= 0.0:
			kept.append(a)
		if (side_a >= 0.0) != (side_b >= 0.0):
			kept.append(a.lerp(b, side_a / (side_a - side_b)))
	return kept


## `src` of `texture` drawn on `canvas` from `origin` along `axis` (unit), from `along_from` px for
## `along_len` px, the part inside [`clip_from`, `clip_to`] only (its source cut by the same shares),
## `across` px per texture px across it with the texture row `axis_row` on the axis, mirrored across
## the axis when `flip`, in `color`; in SKIN_UNIT_PX units, so the form skin's pattern keeps the
## slime's size; drawn `offset` from the canvas's origin.
static func slice_on_axis(canvas: CanvasItem, texture: Texture2D, src: Rect2, origin: Vector2, axis: Vector2,
		along_from: float, along_len: float, across: float, flip: bool, color: Color, axis_row: float,
		clip_from: float = -INF, clip_to: float = INF, offset: Vector2 = Vector2.ZERO) -> void:
	if along_len <= 0.01 or across <= 0.0 or src.size.x <= 0.0:
		return
	var start := maxf(along_from, clip_from)
	var end := minf(along_from + along_len, clip_to)
	if end - start <= 0.01:
		return
	var from_share := (start - along_from) / along_len
	var to_share := (end - along_from) / along_len
	var part := Rect2(src.position.x + src.size.x * from_share, src.position.y, src.size.x * (to_share - from_share),
		src.size.y)
	var unit := Vector2(SKIN_UNIT_PX, -SKIN_UNIT_PX if flip else SKIN_UNIT_PX)
	canvas.draw_set_transform_matrix(Transform2D(axis.angle(), unit, 0.0, offset + origin))
	var top := -(axis_row - src.position.y) * across / SKIN_UNIT_PX
	var high := src.size.y * across / SKIN_UNIT_PX
	canvas.draw_texture_rect_region(texture, Rect2(start / SKIN_UNIT_PX, top, (end - start) / SKIN_UNIT_PX, high), part,
		color)
	canvas.draw_set_transform(offset)


# --- the swoosh ---------------------------------------------------------------------------------------

## The painted swoosh along the head's recent path on `canvas`: the animation sampled at the gameplay
## times every SWOOSH_STEP_MS back over SWOOSH_TRAIL_MS (mapped onto it by the step's timing, so a
## hit-stop freezes it), the run of samples, newest first, in which the head swung fast the same way
## (the side weapon turning SWOOSH_MIN_TURN deg a ms, a view's head moving SWOOSH_MIN_SPEED px a ms;
## a step turning SWOOSH_CUT_DEG or moving SWOOSH_CUT_PX is a cut and ends it; a step where the painted
## view or its frame changes never starts one: the head jumps there, it does not swing), fading over
## SWOOSH_FADE_MS from that run's newest sample; bent onto the band from SWOOSH_IN_PX inside the head
## to SWOOSH_OUT_PX past it along the weapon, its thin tail at the oldest sample.
func _draw_swoosh_trail(canvas: CanvasItem) -> void:
	var now := clock_ms
	if animation == null or now < 0.0:
		return
	var step_timing := _timing_now()
	var samples: Array[Dictionary] = []
	var at := now
	var oldest_ms := maxf(0.0, now - SWOOSH_TRAIL_MS)
	while at >= oldest_ms - 0.001:
		var state := state_at_ms(at, step_timing)
		var weapon_state := geometry_of(state)
		if weapon_state.is_empty() or str(weapon_state["kind"]) == WEAPON_SPEAR:
			break
		var axis: Vector2 = weapon_state["axis"]
		samples.append({"t": at, "angle": float(state.get("angle", 0.0)), "axis": axis,
			"half": float(weapon_state["head_depth"]) * 0.5,
			"view": not (weapon_state["view"] as Dictionary).is_empty(), "middle": head_middle(weapon_state),
			"drawing": "%s%d" % [str(state.get("view", VIEW_SIDE)), int(state.get("view_frame", 1))]})
		at -= SWOOSH_STEP_MS
	var newest := -1
	var sense := Vector2.ZERO
	for index in samples.size() - 1:
		if samples[index]["drawing"] != samples[index + 1]["drawing"]:
			continue
		var step := _swoosh_step(samples[index], samples[index + 1])
		if bool(step["cut"]):
			return
		if bool(step["fast"]):
			newest = index
			sense = step["sense"]
			break
	if newest < 0:
		return
	var fade := 1.0 - clampf((now - float(samples[newest]["t"])) / SWOOSH_FADE_MS, 0.0, 1.0)
	if fade <= 0.0:
		return
	var oldest := newest + 1
	while oldest + 1 < samples.size():
		var step := _swoosh_step(samples[oldest], samples[oldest + 1])
		if bool(step["cut"]) or not bool(step["fast"]) or (step["sense"] as Vector2).dot(sense) <= 0.0:
			break
		sense = step["sense"]
		oldest += 1
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for index in range(oldest, newest - 1, -1):
		var axis: Vector2 = samples[index]["axis"]
		var middle: Vector2 = samples[index]["middle"]
		var half: float = samples[index]["half"]
		inner.append(middle - axis * (half + SWOOSH_IN_PX))
		outer.append(middle + axis * (half + SWOOSH_OUT_PX))
	draw_swoosh(canvas, inner, outer, Color(tint, tint.a * SWOOSH_ALPHA * fade))


## One step of the swoosh's samples, `newer` after `older`: {"fast", "cut", "sense"}.
static func _swoosh_step(newer: Dictionary, older: Dictionary) -> Dictionary:
	var ms := maxf(0.001, float(newer["t"]) - float(older["t"]))
	var moved: Vector2 = (newer["middle"] as Vector2) - (older["middle"] as Vector2)
	if not bool(newer["view"]) and not bool(older["view"]):
		var turned := float(newer["angle"]) - float(older["angle"])
		return {"fast": absf(turned) >= SWOOSH_MIN_TURN * ms, "cut": absf(turned) >= SWOOSH_CUT_DEG,
			"sense": Vector2(signf(turned), 0.0)}
	return {"fast": moved.length() >= SWOOSH_MIN_SPEED * ms, "cut": moved.length() >= SWOOSH_CUT_PX,
		"sense": moved.normalized()}


## The head's middle of a weapon (`geometry_of`), the rig's px: a view's `head`, else half the head's
## depth past the joint along the head's axis.
static func head_middle(weapon_state: Dictionary) -> Vector2:
	var view_state: Dictionary = weapon_state["view"]
	if not view_state.is_empty():
		return (view_state["xform"] as Transform2D) * (view_state["head"] as Vector2)
	return (weapon_state["socket"] as Vector2) + (weapon_state["axis"] as Vector2) * float(weapon_state["joint"]) \
		+ (weapon_state["head_axis"] as Vector2) * float(weapon_state["head_depth"]) * 0.5


## shape-axe-swoosh.webp bent onto a band whose edges are `inner` and `outer` (as many points each,
## the tail first) on `canvas`: the crescent's angles run along the band and its radii across it, in
## `color`; in SKIN_UNIT_PX units, `offset` from the canvas's origin. ShapeVisuals' old swings use it.
static func draw_swoosh(canvas: CanvasItem, inner: PackedVector2Array, outer: PackedVector2Array, color: Color,
		offset: Vector2 = Vector2.ZERO) -> void:
	var count := mini(inner.size(), outer.size())
	if count < 2 or color.a <= 0.0:
		return
	var size := SWOOSH_TEXTURE.get_size()
	var inner_uv := PackedVector2Array()
	var outer_uv := PackedVector2Array()
	for i in count:
		var theta := deg_to_rad(lerpf(SWOOSH_TAIL_DEG, SWOOSH_LEAD_DEG, float(i) / float(count - 1)))
		inner_uv.append(_swoosh_uv(theta, SWOOSH_INNER_R, size))
		outer_uv.append(_swoosh_uv(theta, SWOOSH_OUTER_R, size))
	var colors := PackedColorArray([color, color, color, color])
	canvas.draw_set_transform_matrix(Transform2D(0.0, Vector2(SKIN_UNIT_PX, SKIN_UNIT_PX), 0.0, offset))
	for i in count - 1:
		var quad := PackedVector2Array([inner[i] / SKIN_UNIT_PX, outer[i] / SKIN_UNIT_PX, outer[i + 1] / SKIN_UNIT_PX,
			inner[i + 1] / SKIN_UNIT_PX])
		var uvs := PackedVector2Array([inner_uv[i], outer_uv[i], outer_uv[i + 1], inner_uv[i + 1]])
		canvas.draw_primitive(quad, colors, uvs, SWOOSH_TEXTURE)
	canvas.draw_set_transform(offset)


## The swoosh texture's UV (0..1) `radius` texture px from SWOOSH_CENTRE toward `theta`, kept half a
## pixel inside the texture.
static func _swoosh_uv(theta: float, radius: float, size: Vector2) -> Vector2:
	var direction := Vector2.from_angle(theta)
	var reach := radius
	if direction.x > 0.001:
		reach = minf(reach, (size.x - 0.5 - SWOOSH_CENTRE.x) / direction.x)
	elif direction.x < -0.001:
		reach = minf(reach, (0.5 - SWOOSH_CENTRE.x) / direction.x)
	if direction.y > 0.001:
		reach = minf(reach, (size.y - 0.5 - SWOOSH_CENTRE.y) / direction.y)
	elif direction.y < -0.001:
		reach = minf(reach, (0.5 - SWOOSH_CENTRE.y) / direction.y)
	return (SWOOSH_CENTRE + direction * maxf(0.0, reach)) / size


# --- the editor overlay ---------------------------------------------------------------------------

## The step's hit area at the strike's time (filled while it hits, outlined before and after), a ring round the hit
## centre at the hit's far edge, the hit centre's cross and the ring's handle along the aim (the preview drags
## them; `overlay_hot` enlarges one), the body's edge along the aim, the weapon's far tip, the socket, and
## (`overlay_text`) the readouts.
func _draw_overlay(canvas: CanvasItem, geometry: Dictionary) -> void:
	var context := _overlay_context()
	if context.is_empty():
		return
	var hit: Dictionary = context["hit"]
	var aim: Vector2 = context["aim"]
	var live: bool = context["live"]
	var centre: Vector2 = context["centre"]
	for points: PackedVector2Array in _hit_outlines(hit, aim, float(context["reach"]), float(context["progress"])):
		var closed := points.duplicate()
		closed.append(points[0])
		canvas.draw_polyline(closed, HIT_LINE if live else HIT_IDLE, 0.6, true)
	canvas.draw_arc(centre, _hit_far(hit), 0.0, TAU, CIRCLE_POINTS * 2, RING_COLOR, 0.5, true)
	var edge := body_edge(aim)
	canvas.draw_line(aim * edge + aim.orthogonal() * 4.0, aim * edge - aim.orthogonal() * 4.0, EDGE_COLOR, 0.8, true)
	var tip := _weapon_far(geometry, aim)
	if tip.is_finite():
		canvas.draw_circle(tip, 1.2, TIP_COLOR)
	if not geometry.is_empty():
		canvas.draw_circle(geometry["socket"], SOCKET_DOT_PX, SOCKET_COLOR)
	var arm := HANDLE_PX * (1.6 if overlay_hot == HOT_CENTRE else 1.0)
	canvas.draw_line(centre - Vector2(arm, 0.0), centre + Vector2(arm, 0.0), CENTRE_COLOR, 0.9, true)
	canvas.draw_line(centre - Vector2(0.0, arm), centre + Vector2(0.0, arm), CENTRE_COLOR, 0.9, true)
	var handle: Vector2 = context["handle"]
	var size := HANDLE_PX * (1.0 if overlay_hot == HOT_RING else 0.65)
	canvas.draw_colored_polygon(PackedVector2Array([handle + Vector2(0.0, -size), handle + Vector2(size, 0.0),
		handle + Vector2(0.0, size), handle + Vector2(-size, 0.0)]), HANDLE_COLOR)
	if not overlay_text:
		return
	var lines := overlay_lines()
	var font := ThemeDB.fallback_font
	# The readouts away from the aim: under the slime for an up strike, else over it.
	var corner := Vector2(-60.0, 40.0) if aim.y < -0.5 else Vector2(-60.0, -92.0)
	for index in lines.size():
		var at := corner + Vector2(0.0, float(index) * (FONT_SIZE + 2.0))
		canvas.draw_string(font, at + Vector2(0.5, 0.5), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_SHADOW)
		canvas.draw_string(font, at, lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)


## The overlay's numbers now (game px along the aim from the slime's centre): {"edge" (the body's), "tip" (the
## weapon's farthest point; INF without one), "far" (the hit's far edge), "elapsed" (ms), "live" (the hit is on),
## and in the rig's px: "aim", "centre" (the hit centre, as shown), "handle" (the ring's point along the aim),
## "ring" (the far edge's distance from the hit centre)}; {} while nothing is drawn.
func overlay_numbers() -> Dictionary:
	var context := _overlay_context()
	if context.is_empty():
		return {}
	var aim: Vector2 = context["aim"]
	var centre: Vector2 = context["centre"]
	var ring := _hit_far(context["hit"])
	var tip := _weapon_far(geometry_of(state_now()), aim)
	return {"edge": body_edge(aim), "tip": tip.dot(aim) if tip.is_finite() else INF, "far": centre.dot(aim) + ring,
		"elapsed": float(context["elapsed"]), "live": bool(context["live"]), "aim": aim, "centre": centre,
		"handle": context["handle"], "ring": ring}


## The overlay's readouts now: the strike and its time, the body's edge from the slime's centre, the weapon's tip and
## the hit's far edge along the aim, each also past the body's edge; [] while nothing is drawn.
func overlay_lines() -> PackedStringArray:
	var numbers := overlay_numbers()
	if numbers.is_empty():
		return PackedStringArray()
	var edge := float(numbers["edge"])
	var tip := float(numbers["tip"])
	var far := float(numbers["far"])
	return PackedStringArray([
		"%s  t %.0f ms%s" % [_label(), float(numbers["elapsed"]), "  HIT" if bool(numbers["live"]) else ""],
		"body edge %.1f px from the centre" % edge,
		"tip %.1f along the aim (%.1f past the body)" % [tip, tip - edge] if tip < INF else "tip: none",
		"hit edge %.1f (%.1f past the body)" % [far, far - edge],
	])


## The hit area's fill under the weapon (on the rig, behind the body) while the hit is live.
func _draw_overlay_fill(canvas: CanvasItem) -> void:
	var context := _overlay_context()
	if context.is_empty() or not bool(context["live"]):
		return
	for points: PackedVector2Array in _hit_outlines(context["hit"], context["aim"], float(context["reach"]),
			float(context["progress"])):
		canvas.draw_colored_polygon(points, HIT_FILL)


## What the overlay draws now: {"hit" (the step's numbers with the strike's `hit_reach` and `hit_center` in this
## direction and the Spear's contact socket), "aim", "centre" (the hit centre, mirrored with the Visual), "handle"
## (the hit's far edge along the aim from the centre), "reach", "progress" (the arc swept so far), "live" (inside
## the active window), "elapsed"}; {} without a strike animation or its step.
func _overlay_context() -> Dictionary:
	if animation == null:
		return {}
	var data := StrikeLibrary.step_data(animation)
	if data.is_empty():
		return {}
	var flipped := visual() != null and visual().flip_h
	var aim := Vector2.LEFT if flipped else Vector2.RIGHT
	if direction == "down":
		aim = Vector2.DOWN
	elif direction == "up":
		aim = Vector2.UP
	var hit := ShapeStrikes.apply_hit_reach(data, StrikeLibrary.hit_reach(animation, direction)).duplicate()
	var centre := StrikeLibrary.hit_center(animation, direction)
	if flipped:
		centre.x = -centre.x
	hit[ShapeStrikes.HIT_CENTER_KEY] = centre
	if ShapeDefs.area_kind(hit) == ShapeDefs.AREA_LINE:
		var line_from := _contact_socket_now()
		if line_from.is_finite():
			hit[ShapeStrikes.LINE_FROM_KEY] = Vector2(-line_from.x, line_from.y) if flipped else line_from
	var timing_now := _timing_now()
	var elapsed := clock_ms
	var live := elapsed >= timing_now.x and elapsed < timing_now.x + maxf(timing_now.y, 1.0)
	return {"hit": hit, "aim": aim, "centre": centre, "handle": centre + aim * _hit_far(hit),
		"reach": ShapeDefs.num(hit, "reach"), "elapsed": elapsed, "live": live,
		"progress": clampf((elapsed - timing_now.x) / maxf(1.0, timing_now.y), 0.0, 1.0) if live else 1.0}


## The hit area's outlines (ShapeStrike.area_shapes at `progress`), in the rig's px.
static func _hit_outlines(hit: Dictionary, aim: Vector2, reach: float, progress: float) -> Array[PackedVector2Array]:
	var outlines: Array[PackedVector2Array] = []
	for entry: Dictionary in ShapeStrike.area_shapes(hit, Vector2.ZERO, aim, reach, ShapeDefs.sweep_sign(hit, aim),
			progress):
		var points := _shape_points(entry)
		if points.size() >= 3:
			outlines.append(points)
	return outlines


## A query shape's outline points ({"shape", "transform"}), in the rig's px.
static func _shape_points(entry: Dictionary) -> PackedVector2Array:
	var shape: Variant = entry.get("shape")
	var xform: Transform2D = entry.get("transform", Transform2D.IDENTITY)
	var points := PackedVector2Array()
	if shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size * 0.5
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y),
				Vector2(-half.x, half.y)]:
			points.append(xform * corner)
	elif shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		for i in CIRCLE_POINTS:
			points.append(xform * (Vector2.from_angle(TAU * float(i) / float(CIRCLE_POINTS)) * radius))
	elif shape is ConvexPolygonShape2D:
		for point: Vector2 in (shape as ConvexPolygonShape2D).points:
			points.append(xform * point)
	return points


## The hit's far edge from the slime's centre: an arc's radius, a circle's offset plus its radius, a
## line's reach.
static func _hit_far(hit: Dictionary) -> float:
	match ShapeDefs.area_kind(hit):
		ShapeDefs.AREA_ARC:
			return ShapeDefs.num(hit, "radius")
		ShapeDefs.AREA_CIRCLE:
			return ShapeDefs.num(hit, "offset") + ShapeDefs.num(hit, "radius")
		ShapeDefs.AREA_LINE:
			return ShapeDefs.num(hit, "reach")
	return 0.0


## The weapon's point farthest along `aim` (the rig's px): the Spear's tip, a view's rect corners, the
## side head's rect corners; Vector2.INF without one.
static func _weapon_far(geometry: Dictionary, aim: Vector2) -> Vector2:
	if geometry.is_empty():
		return Vector2.INF
	var points: Array[Vector2] = []
	if str(geometry["kind"]) == WEAPON_SPEAR:
		points.append((geometry["socket"] as Vector2) + (geometry["axis"] as Vector2) * float(geometry["visible"]))
	elif not (geometry["view"] as Dictionary).is_empty():
		var view_state: Dictionary = geometry["view"]
		var rect: Rect2 = view_state["rect"]
		var xform: Transform2D = view_state["xform"]
		for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end,
				rect.position + Vector2(0.0, rect.size.y)]:
			points.append(xform * corner)
	else:
		var texture: Texture2D = geometry["texture"]
		var scale_px: float = geometry["scale"]
		var head_axis: Vector2 = geometry["head_axis"]
		var across := head_axis.orthogonal() * (-1.0 if bool(geometry["flipped"]) else 1.0)
		var joint_at: Vector2 = (geometry["socket"] as Vector2) + (geometry["axis"] as Vector2) * float(geometry["joint"])
		var row: float = geometry["axis_row"]
		var depth := float(geometry["head_depth"])
		for along: float in [0.0, depth]:
			for side: float in [-row * scale_px, (float(texture.get_height()) - row) * scale_px]:
				points.append(joint_at + head_axis * along + across * side)
	var best := Vector2.INF
	for point: Vector2 in points:
		if not best.is_finite() or point.dot(aim) > best.dot(aim):
			best = point
	return best


## Where the body's silhouette ends along `aim` (screen) from the slime's centre, game px (negative
## when it ends short of the centre): on the line through the centre along the aim, the far end of the
## run of opaque pixels of the Visual's frame nearest the centre (the body, not the sprout's leaves).
func body_edge(aim: Vector2) -> float:
	var sprite := visual()
	if sprite == null or sprite.texture == null:
		return 0.0
	var image := _image(sprite.texture)
	if image == null:
		return 0.0
	var columns := maxi(1, sprite.hframes)
	var cell := sprite.texture.get_size() / Vector2(columns, maxi(1, sprite.vframes))
	var corner := Vector2(float(sprite.frame % columns) * cell.x, float(sprite.frame / columns) * cell.y)
	var centre := -sprite.offset + (cell * 0.5 if sprite.centered else Vector2.ZERO)
	var ray := Vector2(-aim.x, aim.y) if sprite.flip_h else aim
	var reach_px := int(cell.length())
	var runs: Array[Vector2i] = []
	var start := 0
	var in_run := false
	for step in range(-reach_px, reach_px + 1):
		var at := centre + ray * float(step)
		var inside := at.x >= 0.0 and at.y >= 0.0 and at.x < cell.x and at.y < cell.y
		var opaque := inside and image.get_pixelv(Vector2i(corner + at)).a >= 0.5
		if opaque and not in_run:
			start = step
			in_run = true
		elif not opaque and in_run:
			runs.append(Vector2i(start, step - 1))
			in_run = false
	if in_run:
		runs.append(Vector2i(start, reach_px))
	var best := Vector2i.ZERO
	var best_gap := INF
	for run: Vector2i in runs:
		var gap := 0.0 if run.x <= 0 and run.y >= 0 else float(mini(absi(run.x), absi(run.y)))
		if gap < best_gap:
			best_gap = gap
			best = run
	return float(best.y) * SKIN_UNIT_PX if best_gap < INF else 0.0


# --- data -------------------------------------------------------------------------------------------

## The packed art of `shape` ("spear", "axe", "hammer"): {"texture", "width", "height", "head_start"
## and the Spear's "shaft_px", "root_end"} in texture px, from shapes.json over ART_FALLBACK, read once.
static func art(shape: String) -> Dictionary:
	if _art_data.is_empty():
		var packed: Dictionary = {}
		if FileAccess.file_exists(ART_DATA_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_DATA_PATH))
			if parsed is Dictionary:
				packed = parsed
		var textures := {"spear": SPEAR_TEXTURE, "axe": AXE_TEXTURE, "hammer": HAMMER_TEXTURE}
		for key: String in textures:
			var texture: Texture2D = textures[key]
			var entry: Dictionary = (ART_FALLBACK[key] as Dictionary).duplicate()
			var from_file: Variant = packed.get(key, {})
			if from_file is Dictionary:
				for field: String in ["shaft_px", "root_end", "head_start"]:
					var value: Variant = (from_file as Dictionary).get(field)
					if value is float or value is int:
						entry[field] = float(value)
			entry["texture"] = texture
			entry["width"] = float(texture.get_width())
			entry["height"] = float(texture.get_height())
			_art_data[key] = entry
	var found: Variant = _art_data.get(shape, {})
	return found if found is Dictionary else {}


## A texture the strike manifest names (a weapon block's, the neck's, a view's), loaded once.
static func manifest_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]


static func _image(texture: Texture2D) -> Image:
	var key := texture.resource_path
	if not _images.has(key):
		_images[key] = texture.get_image()
	return _images[key]

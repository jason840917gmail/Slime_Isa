extends Node2D
## The shapes' visuals (body-shapes plan sections 2 "The owner's sketch", 8 "UI" item 2 and 9
## "Effects: drawn or code"; BODY_SHAPES.md "Shapes"): the Spin's painted jelly axe of 2026-10-12
## (asset/Originals/characters/slime-v2/shapes/README.md: `res://asset/characters/shapes/axe.webp`
## with `shapes.json`, lying horizontal with its root on the left at mid height and its tip on the
## right), moved by code; the painted Axe swoosh and Spear glint; and code-drawn speed streaks,
## shock rings and clinks. Every position, angle and timing is the hit's, so the art is where the hit
## is. Each step moves its own way, matching its hit shape in space and time (owner, 2026-10-12):
## - every strike on its strike animation (owner, 2026-10-12, rounds 3 to 5; game/shapes/strike_rig.gd,
##   StrikeLibrary, BODY_SHAPES.md "Editing the strike animations"): the player's StrikeRig, given the
##   strike's resource and direction by the shape controller on the gameplay clock, draws
##   the weapon (the Spear's rigid spear, the Axe's and the Hammer's weapon or weapon view), the code
##   neck and the swoosh; this node draws only the Spear's speed streaks beside it on the lunge frame
##   (the UNDER layer), its pierce glint (shape-spear-glint.webp) at the hit line's end and the
##   finisher's load glint at the body's front (the OVER layer, over the world at STRIKE_OVER_Z), and
##   every strike's hit feel: the chop's short impact (`show_chop`), the Hammer's crack decal
##   (boss-ground-crack-4x1.webp), small dust puffs and a shock ring, all about as wide as the hit
##   (`show_impact`; the BOOM's ring and the Quake's ring of cracks are wider), the clinks. It hands the
##   rig the form's tint (`_apply_skin`) and the Spear's wall-cut reach (`show_step`);
## - the War Axe's Spin, the one strike without a strike animation: axe.webp from its root at the
##   slime's side (HAFT_ROOT_PX), its head's middle where the hit's arc is swept (HEAD_AT_SHARE of the
##   radius) and its tip at the hit radius, the haft stretched between, all round from the aim as the
##   hit's arc sweeps, trailed by the painted swoosh (shape-axe-swoosh.webp bent onto the swept arc, its
##   bright end at the head), mirrored with the swing's direction (its head is double-bladed, so a
##   crescent always leads). The same drawing would swing a narrower arc (a sweep comes DOWN from a
##   raised head, a backswing UP), but every such step plays its strike animation;
## - a white tick of a clink at the tip (`show_clink`);
## - the charge's goo ring (game/shapes/goo_ring.gd) on the ground under the slime, pulsing once full.
## A chain's last step loads first: `art_pose` gives the slime's art its pull-back, squash and hop
## (the shape controller puts it on the player's effects channel; the strike frames place their drawing
## off the live Visual).
## The Spin's axe draws behind the slime on an up aim (this node moves before the slime's Visual, z 0)
## and in front of the world on the others (z 1), so a target lower on screen never covers the tip.
##
## Three canvas items draw each frame, in this order: this node (the speed streaks), its child
## WEAPON_NODE (the swoosh and the weapon, in the slime's Gulp form skin: a ShaderMaterial of its own
## with form_skin.gdshader and the form's `skin`, drawn in the slime sheet's texture px
## (SKIN_UNIT_PX) so the pattern is as big as on the slime; the form's tint where the slime's Visual
## has no skin shader) and OVER_NODE (the glints, the shock rings and the clinks). The strike rig's
## three canvas items (StrikeRig, StrikeRigFront, StrikeRigNeck under the player's Visual) wear the
## same skin material (`_apply_skin`), never the Visual's: its elevation ghost would hide every weapon
## pixel more than a margin below the slime's feet. The textures draw with mipmaps where their import
## makes them (linear otherwise, as the character art).
##
## The shape controller makes one, a child of the player body at the slime's centre, and drives it.
## The strikes follow the gameplay clock (`Services.now_ms()`), so a hit-stop freezes the pose with the
## world; the node processes during pauses (PROCESS_MODE_ALWAYS), so the frozen frame shows the contact
## pose, not the frame before it. Presentation only: nothing here hits or moves anything.
##
## Owner: shapes.

const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapeStrikes := preload("res://game/shapes/shape_strikes.gd")
const GooRing := preload("res://game/shapes/goo_ring.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const StrikeRig := preload("res://game/shapes/strike_rig.gd")
const StrikeLibrary := preload("res://game/shapes/strike_library.gd")
const CRACK_TEXTURE := preload("res://asset/MAPS/effects/boss-ground-crack-4x1.webp")

## The Spear's glint (asset/Originals/characters/slime-v2/shapes/README.md); the painted axe, the swoosh
## and the packer's numbers are the StrikeRig's (`_art`, StrikeRig.draw_swoosh).
const GLINT_TEXTURE := preload("res://asset/MAPS/effects/shape-spear-glint.webp")
## Screen px per texture px of the slime's own sheet (player_slime.tscn's Visual scale): the weapon
## layer draws in these units, so the form skin's pattern (form_skin.gdshader, laid out in texture px)
## is as big on the weapon as on the slime.
const SKIN_UNIT_PX := 0.28125
const SKIN_PARAM := &"skin"
## The canvas items a frame draws on (see the header): this node, then its two children, and the
## strike spear's under the player's Visual.
const LAYER_UNDER := 0
const LAYER_WEAPON := 1
const LAYER_OVER := 2
const WEAPON_NODE := "ShapeWeapon"
const OVER_NODE := "ShapeOver"
## Clean at the textures' small size on screen: mipmaps where the import makes them, else linear.
const TEXTURE_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## The jelly green of the slime sheet's body (page 1), and its light (the full charge ring and the shock
## rings).
const GOO := Color("#97bb3c")
const LIGHT_SHARE := 0.45
const SPEED_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.55)
## The class of the light chain steps (the jabs, the sweeps); every other class (the Spear's finisher
## and its Lunge) draws the Spear's glints and streaks big.
const TAP_CLASS := "tap"

## The speed streaks: how many (the jabs, then the big thrusts), how far beside the shaft the first
## pair runs and how far apart the next ones are, and their length behind the head.
const STREAKS := 4
const STREAKS_BIG := 5
const STREAK_GAP_PX := 2.5
const STREAK_STEP_PX := 4.0
const STREAK_PX := 30.0
const STREAK_BIG_PX := 44.0
## The finisher's load: the painted glint shows at the body's front (GLINT_AHEAD_PX past the full lean's
## socket): from GLINT_FROM_SHARE of the pull it grows to LOAD_GLINT_PX wide at the pull's end, then
## fades in GLINT_FADE_MS as the thrust shoots out.
const GLINT_FROM_SHARE := 0.45
const LOAD_GLINT_PX := 18.0
const GLINT_FADE_MS := 60.0
const GLINT_AHEAD_PX := 4.0
## The pierce glint on every thrust's contact frame: the painted star at the tip with its streaks
## along the aim, PIERCE_GLINT_PX wide (the finisher and the Lunge PIERCE_GLINT_BIG_PX), growing by
## PIERCE_GROWTH as it fades over PIERCE_GLINT_MS (gameplay ms: a hit-stop holds it whole).
## GLINT_PIVOT is the star's middle in shape-spear-glint.webp (texture px).
const PIERCE_GLINT_PX := 26.0
const PIERCE_GLINT_BIG_PX := 34.0
const PIERCE_GROWTH := 0.25
const PIERCE_GLINT_MS := 90.0
const GLINT_PIVOT := Vector2(90.0, 104.0)

## The glints' and the streaks' layer on strike animations (relative z): over the world.
const STRIKE_OVER_Z := 1

## Axe (the Spin's drawing): the haft's root (px from the centre), where the head's middle sits (share of
## the radius; the texture is scaled so its tip reaches AXE_TIP_SHARE of it), the wind-back before a
## swing, a narrower swing's height (a sweep comes down from it, a backswing rises to it; the Spin stays
## level), and the swoosh: the band of the radius it is bent onto, its opacity and how many pieces it
## bends in.
const HAFT_ROOT_PX := 12.0
const HEAD_AT_SHARE := 0.76
const AXE_TIP_SHARE := 1.0
const WINDBACK_RAD := 0.4
const SWING_RAISE_PX := 16.0
const SWOOSH_INNER_SHARE := 0.42
const SWOOSH_OUTER_SHARE := 1.05
const SWOOSH_ALPHA := 0.85
const SWOOSH_POINTS := 28
## The Axe chop's short impact (`show_chop`): a shock ring CHOP_IMPACT_SHARE of the radius wide, where
## the head lands (HEAD_AT_SHARE of the radius along the aim).
const CHOP_IMPACT_SHARE := 0.45

## Impact: the crack decal (4 frames of 96 px, drawn this wide against the hit radius, squashed onto
## the ground, cracking open then fading), the shock ring and the dust: small `dodge-dust` puffs
## (each about DUST_PUFF_REACH_PX across its middle) at the centre and, for a wider hit, on a ring
## DUST_PUFF_REACH_PX inside the hit's edge, one every DUST_ARC_PX of it (at most DUST_PUFFS_MAX: with
## the centre's, the six emitters ParticleFx keeps per preset), so
## the cloud is about the hit's size (the Thud's r48, the BOOM's r72 ring, the Quake's r120 cracks).
const CRACK_FRAMES := 4
const CRACK_FRAME_PX := 96.0
const CRACK_WIDTH_SHARE := 1.1
const CRACK_SQUASH_Y := 0.7
const CRACK_GROW_MS := 300.0
const CRACK_FADE_MS := 900.0
const CRACK_Z := -1
const SHOCK_MS := 220.0
const SHOCK_WIDTH_PX := 4.0
const SHOCK_START_SHARE := 0.35
const SHOCK_POINTS := 40
const DUST_PRESET := &"dodge-dust"
const DUST_PUFF_REACH_PX := 40.0
const DUST_ARC_PX := 48.0
const DUST_PUFFS_MAX := 5
const DUST_COUNT_SCALE := 0.7

## Clink: a white star at the tip.
const CLINK_MS := 80.0
const CLINK_PX := 9.0
const CLINK_COLOR := Color(1.0, 1.0, 1.0, 0.95)

## The charge ring: on the ground under the slime (squashed), the mouth's radius
## (`gulp.rework.ringRadiusPx`), pulsing once full.
const RING_NAME := "ShapeChargeRing"
const RING_RADIUS_PATH := "gulp.rework.ringRadiusPx"
const RING_SQUASH_Y := 0.55
const RING_PULSE_HZ := 3.0
const RING_PULSE := 0.07

var _player: PlayerScript
var _ring: GooRing
var _shape: String = ""
var _data: Dictionary = {}
## The strike frames the running Spear step shows (its `ShapeStrikes.STRIKE_KEY`; "" for none).
var _strike: String = ""
var _aim: Vector2 = Vector2.RIGHT
## The strike's start on the gameplay clock (< 0: none) and its length.
var _started_ms: float = -1.0
var _duration_ms: float = 0.0
var _goo: Color = GOO
var _light: Color = GOO
## Clink stars {"at": global Vector2, "from": ms} and shock rings {"at", "radius", "from"}.
var _clinks: Array[Dictionary] = []
var _shocks: Array[Dictionary] = []
## Real ms the ring became full (< 0: not full).
var _ring_full_since: float = -1.0
## The two child canvas items (WEAPON_NODE, OVER_NODE); the one a paint draws on now, its layer, and
## the strike's art-pose offset it draws with.
var _weapon_layer: Node2D
var _over_layer: Node2D
var _canvas: CanvasItem
var _layer: int = LAYER_UNDER
var _offset: Vector2 = Vector2.ZERO
## The weapon layer's form skin (form_skin.gdshader, the form's `skin`), and the weapon's tint where
## it wears none (the form's tint without the Visual's skin shader, else white).
var _skin: ShaderMaterial
var _weapon_tint: Color = Color.WHITE


## The slime's art pose `t` ms into `data` (a chain step) toward `aim`, from its `anticipation`
## block (ShapeDefs.anticipation: the chain's last step): {"offset": Vector2 (world px: the art only,
## the body never moves for it), "scale": Vector2 (the sprite's x and y)}. Through the pull-back
## (0..`pullMs`) the art eases `pullPx` back from the aim and squashes along it (`squashAlong`,
## `squashAcross`); from `pullMs` to the contact frame (the end of the wind-up) it springs to
## `pushPx` past its rest along the aim, stretching the other way, and a `jumpPx` hop (the War Axe's
## chop) rises and lands on the contact frame; through the active window it eases back to rest. Rest
## ({ZERO, ONE}) for a step without an anticipation. The shape controller puts it on the player's
## effects channel; the drawing below moves with it.
static func art_pose(data: Dictionary, t: float, aim: Vector2) -> Dictionary:
	var pose := {"offset": Vector2.ZERO, "scale": Vector2.ONE}
	var plan := ShapeDefs.anticipation(data)
	if plan.is_empty() or aim == Vector2.ZERO or t < 0.0:
		return pose
	var windup := ShapeDefs.num(data, "windupMs")
	var active := ShapeDefs.num(data, "activeMs")
	var pull_ms := clampf(ShapeDefs.num(plan, "pullMs"), 0.0, windup)
	var pull_px := ShapeDefs.num(plan, "pullPx")
	var push_px := ShapeDefs.num(plan, "pushPx")
	var jump_px := ShapeDefs.num(plan, "jumpPx")
	# The shift along the aim (negative: back), the hop's height, and the squash share (1: the pull's
	# squash, -1: the mirrored stretch of the strike).
	var shift := 0.0
	var lift := 0.0
	var squash := 0.0
	if t < pull_ms:
		var k := _ease_out(t / maxf(1.0, pull_ms))
		shift = -pull_px * k
		squash = k
	elif t < windup:
		var k := clampf((t - pull_ms) / maxf(1.0, windup - pull_ms), 0.0, 1.0)
		shift = lerpf(-pull_px, push_px, _ease_in(k))
		squash = 1.0 - 2.0 * k
		# A parabola: up from the crouch, down onto the contact frame.
		lift = jump_px * 4.0 * k * (1.0 - k)
	elif t < windup + active:
		shift = push_px * (1.0 - _ease_out(clampf((t - windup) / maxf(1.0, active), 0.0, 1.0)))
	var unit := aim.normalized()
	pose["offset"] = unit * shift + Vector2(0.0, -lift)
	pose["scale"] = _squash_scale(unit, squash, ShapeDefs.num(plan, "squashAlong", 1.0),
		ShapeDefs.num(plan, "squashAcross", 1.0))
	return pose


## Makes the two child layers (the weapon in its form skin, then the glints, rings and clinks over
## it), the skin material and the texture filter they inherit.
func _init() -> void:
	_canvas = self
	texture_filter = TEXTURE_FILTER
	_skin = ShaderMaterial.new()
	_skin.shader = PlayerScript.FORM_SKIN_SHADER
	_weapon_layer = _make_layer(WEAPON_NODE, _draw_weapon_layer)
	_over_layer = _make_layer(OVER_NODE, _draw_over_layer)


## Draws during a hit-stop too (the frozen frame is the contact pose; the clock it reads stands still).
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Remembers the player it draws for, puts the charge ring under its body (behind the slime) and the
## strike spear's canvas item under its Visual (drawn behind it).
func setup(player: Node) -> void:
	_player = player as PlayerScript
	_set_colors()
	if _player == null or _player.body == null:
		return
	_ring = GooRing.new()
	_ring.name = RING_NAME
	_ring.visible = false
	_ring.scale = Vector2(1.0, RING_SQUASH_Y)
	var constants := Services.constants()
	if constants != null:
		_ring.radius_px = float(constants.value(RING_RADIUS_PATH, _ring.radius_px))
	_player.body.add_child.call_deferred(_ring)
	_ring_behind.call_deferred()


func _exit_tree() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


## Shows `step` (its numbers; the controller adds the line's wall-cut `reach` and the strike's
## `sweepSign`, and while strike frames show their keys: ShapeStrikes.STRIKE_KEY, DIRECTION_KEY,
## MIRRORED_KEY, the Spear's LINE_FROM_KEY) of shape `shape_id` toward `aim` (unit) for `duration_ms`
## of the gameplay clock.
func show_step(shape_id: StringName, step: Dictionary, aim: Vector2, duration_ms: float) -> void:
	_shape = ShapeDefs.short_name(shape_id)
	_data = step
	_strike = str(step.get(ShapeStrikes.STRIKE_KEY, ""))
	_aim = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	_started_ms = Services.now_ms()
	_duration_ms = maxf(0.0, duration_ms)
	_set_colors()
	# The rig draws the strike's weapon (its strike animation); the Spear's from the wall-cut reach.
	var rig := _rig()
	if rig != null:
		rig.set(&"reach_override", ShapeDefs.num(step, "reach", -1.0) if _shape == "spear" and _is_strike() else -1.0)
	# A strike on its strike frames draws on the layers under the Visual (this node behind it), its
	# glints, rings and clinks over the world; else up and the two up-diagonals only (a left aim snaps
	# to (-1, -0.0...), which is not up).
	_set_behind(_is_strike() or ShapeDefs.snap8(_aim).y < -0.5)
	if _over_layer != null:
		_over_layer.z_index = STRIKE_OVER_Z if _is_strike() else 0
	_redraw()


## The charge ring at `progress` (0..1); `progress` < 0 hides it at once.
func show_charge(_shape_id: StringName, progress: float) -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	if progress < 0.0:
		_ring.set_progress(0.0)
		_ring.hide()
		_ring_full_since = -1.0
		return
	_set_colors()
	_ring.set_color(_light if progress >= 1.0 else _goo)
	_ring.set_progress(progress)
	_ring.show()
	if progress >= 1.0:
		if _ring_full_since < 0.0:
			_ring_full_since = _real_now()
	else:
		_ring_full_since = -1.0
		_ring.scale = Vector2(1.0, RING_SQUASH_Y)


## Empties the charge ring over `duration_ms` of real time (a hold let go early, a cancel).
func drain_charge(duration_ms: float) -> void:
	_ring_full_since = -1.0
	if _ring != null and is_instance_valid(_ring) and _ring.visible:
		_ring.scale = Vector2(1.0, RING_SQUASH_Y)
		_ring.drain(duration_ms)


## The Hammer's (or the Quake's) impact at `world_centre` with a hit radius `radius` and a ring of
## `ring_radius` (0 = none): a crack decal on the ground under it, dust as wide as the hit, and a
## shock ring.
func show_impact(world_centre: Vector2, radius: float, ring_radius: float) -> void:
	var ground := world_centre + _feet_drop()
	var wide := maxf(radius, ring_radius)
	_spawn_crack(ground, wide)
	_shocks.append({"at": ground, "radius": wide, "from": Services.now_ms()})
	_spawn_dust(ground, wide)
	_redraw()


## The War Axe's chop lands (its first contact frame): a short impact on the ground in front where
## its head strikes, a small shock ring and a dust puff (no crack).
func show_chop() -> void:
	var radius := ShapeDefs.num(_data, "radius")
	if radius <= 0.0 or _player == null or not is_instance_valid(_player):
		return
	var ground := _player.get_centre() + _hit_offset() + _aim * radius * HEAD_AT_SHARE + _feet_drop()
	var wide := radius * CHOP_IMPACT_SHARE
	_shocks.append({"at": ground, "radius": wide, "from": Services.now_ms()})
	_spawn_dust(ground, wide)
	_redraw()


## A clink's white tick at `world_point` (the tip).
func show_clink(world_point: Vector2) -> void:
	_clinks.append({"at": world_point, "from": Services.now_ms()})
	_redraw()


## Hides the strike at once (a reset, a switch, death); decals already on the ground stay, and the
## charge ring is left to `show_charge` / `drain_charge` (a reset drains it).
func clear() -> void:
	_started_ms = -1.0
	_data = {}
	_strike = ""
	_clinks.clear()
	_redraw()


func _process(_delta: float) -> void:
	if _ring != null and is_instance_valid(_ring) and _ring.visible and _ring_full_since >= 0.0:
		var pulse := 1.0 + RING_PULSE * sin((_real_now() - _ring_full_since) / 1000.0 * TAU * RING_PULSE_HZ)
		_ring.scale = Vector2(pulse, RING_SQUASH_Y * pulse)
	var now := Services.now_ms()
	_clinks = _younger(_clinks, now, CLINK_MS)
	_shocks = _younger(_shocks, now, SHOCK_MS)
	if _showing(now) or not _clinks.is_empty() or not _shocks.is_empty():
		_redraw()
	elif _started_ms >= 0.0:
		_started_ms = -1.0
		_redraw()


func _draw() -> void:
	_paint(LAYER_UNDER, self)


func _draw_weapon_layer() -> void:
	_paint(LAYER_WEAPON, _weapon_layer)


func _draw_over_layer() -> void:
	_paint(LAYER_OVER, _over_layer)


## One layer of the frame on `canvas` (this node or a child layer, see the header): the strike's part
## on it, moved with the slime's art (the last step's pull-back and hop: `art_pose`; a strike on its
## strike frames reads the art's place off the live Visual itself), then on the OVER layer the shock
## rings and the clinks.
func _paint(layer: int, canvas: CanvasItem) -> void:
	_layer = layer
	_canvas = canvas
	var now := Services.now_ms()
	if _showing(now):
		var t := now - _started_ms
		_offset = Vector2.ZERO if _is_strike() else art_pose(_data, t, _aim).get("offset", Vector2.ZERO)
		canvas.draw_set_transform(_offset)
		# On a strike animation the rig draws the weapon (game/shapes/strike_rig.gd); without one (the
		# Axe's Spin) this node draws the axe. The Spear's glints and streaks are this node's.
		if _is_strike():
			if _shape == "spear":
				_draw_strike_spear(t)
		elif _shape == "axe":
			_draw_axe(t)
		canvas.draw_set_transform(Vector2.ZERO)
	_offset = Vector2.ZERO
	if layer == LAYER_OVER:
		for shock: Dictionary in _shocks:
			_draw_shock(shock, now)
		for clink: Dictionary in _clinks:
			_draw_clink(to_local(clink["at"]))
	_canvas = self
	_layer = LAYER_UNDER


# --- the Spear's streaks and glints ------------------------------------------------------------------

## The speed streaks beside a shaft that runs along the aim from `base` (local): thin lines in pairs
## farther out, of varied length, from `start` px along it at the most to `back` px (the head's base),
## `shaft_half` px off its axis and farther, at `strength`.
func _draw_streaks_along(base: Vector2, start: float, back: float, shaft_half: float, strength: float,
		big: bool) -> void:
	var count := STREAKS_BIG if big else STREAKS
	var length := STREAK_BIG_PX if big else STREAK_PX
	var color := Color(SPEED_LINE_COLOR, SPEED_LINE_COLOR.a * clampf(strength, 0.0, 1.0))
	var normal := Vector2(-_aim.y, _aim.x)
	for i in count:
		var lane := shaft_half + STREAK_GAP_PX + STREAK_STEP_PX * floorf(float(i) * 0.5)
		var across := lane if i % 2 == 0 else -lane
		var reach := length * (1.0 - 0.18 * float(i % 3))
		var from := maxf(start, back - reach)
		var to := back - STREAK_GAP_PX
		if to > from + 1.0:
			_canvas.draw_line(base + _aim * from + normal * across, base + _aim * to + normal * across, color, 1.0, true)


## The painted glint (shape-spear-glint.webp: a star with its streaks pointing along `axis`), its star
## at `at` (local), `width_px` wide, at `alpha`; mirrored for a left `axis` (the art keeps its light).
func _draw_glint(at: Vector2, axis: Vector2, width_px: float, alpha: float) -> void:
	if width_px <= 0.5 or alpha <= 0.0 or axis == Vector2.ZERO:
		return
	var k := width_px / float(GLINT_TEXTURE.get_width())
	var flip := axis.x < 0.0
	_canvas.draw_set_transform_matrix(Transform2D(axis.angle(), Vector2(k, -k if flip else k), 0.0, _offset + at))
	_canvas.draw_texture(GLINT_TEXTURE, -GLINT_PIVOT, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	_canvas.draw_set_transform(_offset)


## The pierce glint's share `t` ms into a thrust whose contact frame is at `windup`: 1 on the contact
## frame, fading to 0 over PIERCE_GLINT_MS; 0 before it.
static func _pierce_share(t: float, windup: float) -> float:
	if t < windup:
		return 0.0
	return 1.0 - clampf((t - windup) / PIERCE_GLINT_MS, 0.0, 1.0)


## The finisher's glint `t` ms into it with a pull-back of `pull_ms`: it grows from GLINT_FROM_SHARE
## of the pull to the pull's end, then fades in GLINT_FADE_MS; 0 for a step without a pull-back.
static func _glint_share(t: float, pull_ms: float) -> float:
	if pull_ms <= 0.0:
		return 0.0
	var from := pull_ms * GLINT_FROM_SHARE
	if t < from:
		return 0.0
	if t < pull_ms:
		return (t - from) / maxf(1.0, pull_ms - from)
	return 1.0 - clampf((t - pull_ms) / GLINT_FADE_MS, 0.0, 1.0)


# --- the Spear on its strike frames ------------------------------------------------------------------

## The Spear `t` ms into a step on its strike animation (the rig draws the spear itself): on the UNDER
## layer the speed streaks beside it on the lunge frame, on the OVER layer the finisher's load glint
## and the pierce glint at the contact point.
func _draw_strike_spear(t: float) -> void:
	if _layer == LAYER_OVER:
		var windup := ShapeDefs.num(_data, "windupMs")
		var pull_ms := clampf(ShapeDefs.num(ShapeDefs.anticipation(_data), "pullMs"), 0.0, windup)
		var glint := _glint_share(t, pull_ms)
		if glint > 0.0:
			# At the body's front on the full lean's socket line (the lean frame's own socket).
			var front := _strike_point(ShapeStrikes.FRAME_LEAN, ShapeStrikes.SOCKET)
			if front.is_finite():
				_draw_glint(front + _aim * GLINT_AHEAD_PX, _aim, LOAD_GLINT_PX * glint, glint)
		var pierce := _pierce_share(t, windup)
		if pierce > 0.0:
			var width := (PIERCE_GLINT_BIG_PX if _is_big() else PIERCE_GLINT_PX) * (1.0 + PIERCE_GROWTH * (1.0 - pierce))
			_draw_glint(_strike_contact(), _aim, width, pierce)
		return
	if _layer != LAYER_UNDER:
		return
	var visual := _strike_visual()
	var rig := _rig()
	if visual == null or rig == null:
		return
	if ShapeStrikes.shown_frame(visual, _strike, _strike_direction(), _strike_flipped()) != ShapeStrikes.FRAME_LUNGE:
		return
	var spear: Dictionary = rig.call(&"geometry_of", rig.call(&"state_now"))
	if spear.is_empty() or str(spear.get("kind", "")) != StrikeRig.WEAPON_SPEAR:
		return
	var back := float(spear["visible"]) - float(spear["head"])
	_draw_streaks_along(to_local(rig.to_global(spear["socket"])), 0.0, back, ShapeStrikes.shaft_px(_strike) * 0.5, 1.0,
		_is_big())


## Where the full lean's spear tip is at full reach (local): the hit line's end, `reach` along the aim
## from the slime's centre on the line from the full lean's socket (ShapeStrikes.LINE_FROM_KEY).
func _strike_contact() -> Vector2:
	return _strike_line_from() + _aim * _strike_full_px()


## The full reach of the spear from its socket: to the hit line's end (ShapeStrike.area_shapes), measured from the
## hit centre.
func _strike_full_px() -> float:
	return maxf(0.0, ShapeDefs.num(_data, "reach") + _hit_offset().dot(_aim) - _strike_line_from().dot(_aim))


## Where the step's hit is measured from, px from the slime's centre (ShapeStrikes.HIT_CENTER_KEY; zero without one).
func _hit_offset() -> Vector2:
	var offset: Variant = _data.get(ShapeStrikes.HIT_CENTER_KEY)
	return offset if offset is Vector2 else Vector2.ZERO


## The full lean's socket in px from the slime's centre (this node's origin), mirrored for left.
func _strike_line_from() -> Vector2:
	var from: Variant = _data.get(ShapeStrikes.LINE_FROM_KEY)
	return from if from is Vector2 else Vector2.ZERO


## The cell-px point `key` of frame `number` of the running strike, where the live Visual draws it
## (this node's local px); Vector2.INF while the slime shows no frame of this strike.
func _strike_point(number: int, key: String) -> Vector2:
	var visual := _strike_visual()
	if visual == null:
		return Vector2.INF
	var direction := _strike_direction()
	if ShapeStrikes.shown_frame(visual, _strike, direction, _strike_flipped()) <= 0:
		return Vector2.INF
	var entry := ShapeStrikes.frame(_strike, direction, number)
	var at := _sprite_point(visual, ShapeStrikes.cell_point(entry, key))
	return to_local(visual.to_global(at)) if at.is_finite() else Vector2.INF


## The running strike's direction ("side", "down", "up"; ShapeStrikes.DIRECTION_KEY) and whether the
## slime shows its strip flipped (a left side strike, a mirrored strip: ShapeStrikes.shown_flipped).
func _strike_direction() -> String:
	return str(_data.get(ShapeStrikes.DIRECTION_KEY, ""))


func _strike_flipped() -> bool:
	var flipped := StrikeLibrary.flip_h(StrikeLibrary.animation(_strike), _strike_direction())
	return ShapeStrikes.shown_flipped(flipped, bool(_data.get(ShapeStrikes.MIRRORED_KEY, false)))


## The player's Visual (null without one).
func _strike_visual() -> Sprite2D:
	if _player == null or not is_instance_valid(_player):
		return null
	var visual := _player.get_visual()
	return visual if visual != null and is_instance_valid(visual) else null


## Where `visual` draws the cell px `cell` of its frame, in its own local px: its offset (less half a
## frame when centred) and its mirror (flip_h mirrors a frame inside its own rect, so about the cell's
## middle). Its transform (the art's effect and swim offsets, the squash) is the canvas's to apply.
## Vector2.INF for a missing point.
static func _sprite_point(visual: Sprite2D, cell: Vector2) -> Vector2:
	if not cell.is_finite() or visual.texture == null:
		return Vector2.INF
	var frame_size := visual.texture.get_size() / Vector2(maxi(1, visual.hframes), maxi(1, visual.vframes))
	var at := cell
	if visual.flip_h:
		at.x = frame_size.x - at.x
	if visual.flip_v:
		at.y = frame_size.y - at.y
	return visual.offset - (frame_size * 0.5 if visual.centered else Vector2.ZERO) + at


# --- the War Axe's Spin ----------------------------------------------------------------------------

## The axe `t` ms into a swing without a strike animation (the Spin: the whole circle from the aim; a
## narrower arc is centred on the aim): wound back through the wind-up, swept linearly with the hit's arc
## through the active window, trailed by the swoosh, held and faded through the recovery.
func _draw_axe(t: float) -> void:
	# The swoosh and the axe are both on the weapon layer.
	if _layer != LAYER_WEAPON:
		return
	var windup := ShapeDefs.num(_data, "windupMs")
	var active := ShapeDefs.num(_data, "activeMs")
	var recovery := ShapeDefs.num(_data, "recoveryMs")
	var radius := ShapeDefs.num(_data, "radius")
	var arc := deg_to_rad(ShapeDefs.num(_data, "arcDeg"))
	var sweep := ShapeDefs.num(_data, "sweepSign", 1.0)
	var full := arc >= TAU - 0.01
	var from := _aim.angle() if full else _aim.angle() - sweep * arc * 0.5
	var to := from + sweep * arc
	# The swing's height: the sweep (`sweep` "cw") comes down from a raised head, the backswing
	# ("ccw") swings up to it; the Spin stays level.
	var rises := str(_data.get("sweep", "")) == ShapeDefs.SWEEP_CCW
	var lift_from := 0.0 if full or rises else SWING_RAISE_PX
	var lift_to := SWING_RAISE_PX if not full and rises else 0.0
	var angle := from
	var lift := lift_from
	var smear_to := from
	var fade := 1.0
	var length := 1.0
	if t < windup:
		var k := t / maxf(1.0, windup)
		angle = from - sweep * WINDBACK_RAD * _ease_out(k)
		lift = lift_from * _ease_out(k)
		length = lerpf(0.6, 1.0, k)
	elif t < windup + active:
		# Linear, as the hit's arc sweeps (ShapeStrike.area_shapes `progress`): the head is where it hits.
		var k := clampf((t - windup) / maxf(1.0, active), 0.0, 1.0)
		angle = lerpf(from, to, k)
		lift = lerpf(lift_from, lift_to, k)
		smear_to = angle
	else:
		var k := clampf((t - windup - active) / maxf(1.0, recovery), 0.0, 1.0)
		angle = to
		smear_to = to
		lift = lift_to * (1.0 - k)
		fade = 1.0 - k
		length = 1.0 - 0.5 * k
	if absf(smear_to - from) > 0.01 and fade > 0.0:
		_draw_swing_swoosh(from, smear_to, to, lift_from, lift_to, radius, fade)
	var out := Vector2.from_angle(angle)
	var head := out * radius * HEAD_AT_SHARE * length + Vector2(0.0, -lift)
	# Mirrored with the swing: a counter-clockwise swing is the clockwise one's mirror image.
	_draw_hafted("axe", out * HAFT_ROOT_PX, head, _axe_scale(radius) * length, sweep < 0.0, _weapon_color(fade))


## The painted swoosh behind a swing from the angle `from` to `smear_to` (of a swing to `to`), bent
## onto the arc between SWOOSH_INNER_SHARE and SWOOSH_OUTER_SHARE of the radius with its thin tail at
## `from` and its bright end at the head (so it mirrors with the swing's direction), lifted as the
## head was (from `lift_from` at `from` to `lift_to` at `to`), at `fade`.
func _draw_swing_swoosh(from: float, smear_to: float, to: float, lift_from: float, lift_to: float, radius: float,
		fade: float) -> void:
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var span := to - from
	for i in SWOOSH_POINTS + 1:
		var a := lerpf(from, smear_to, float(i) / float(SWOOSH_POINTS))
		var share := (a - from) / span if absf(span) > 0.001 else 0.0
		var up := Vector2(0.0, -lerpf(lift_from, lift_to, share))
		inner.append(Vector2.from_angle(a) * radius * SWOOSH_INNER_SHARE + up)
		outer.append(Vector2.from_angle(a) * radius * SWOOSH_OUTER_SHARE + up)
	_draw_swoosh(inner, outer, fade)


## shape-axe-swoosh.webp bent onto a band whose edges are `inner` and `outer` (local, as many points
## each, the tail first): the crescent's angles (its thin tail at SWOOSH_TAIL_DEG round
## SWOOSH_CENTRE to its bright end at SWOOSH_LEAD_DEG) run along the band and its radii
## (SWOOSH_INNER_R to SWOOSH_OUTER_R) across it, at `fade` x SWOOSH_ALPHA. In SKIN_UNIT_PX units on the
## weapon layer, so it wears the form skin as the weapon does.
func _draw_swoosh(inner: PackedVector2Array, outer: PackedVector2Array, fade: float) -> void:
	StrikeRig.draw_swoosh(_canvas, inner, outer, _weapon_color(SWOOSH_ALPHA * fade), _offset)


## Screen px per texture px of the axe for a hit `radius`: with its head's middle at HEAD_AT_SHARE of
## the radius, its tip reaches AXE_TIP_SHARE of it, so haft and head span the hit's reach.
static func _axe_scale(radius: float) -> float:
	var art := _art("axe")
	if art.is_empty():
		return 0.0
	var half_head := (float(art["width"]) - float(art["head_start"])) * 0.5
	return radius * maxf(0.0, AXE_TIP_SHARE - HEAD_AT_SHARE) / maxf(1.0, half_head)


## A hafted weapon (`shape`'s art: the axe) from `root` to its head's middle at `head` (local): the haft
## (texture px 0 to `head_start`) stretched between them and the head (`head_start` to the tip) at
## `scale_px` screen px per texture px, mirrored across its axis when `flip`, in `color`. Pointing up
## from the root while the two meet (the head then covers the root).
func _draw_hafted(shape: String, root: Vector2, head: Vector2, scale_px: float, flip: bool, color: Color) -> void:
	var art := _art(shape)
	if art.is_empty() or scale_px <= 0.0:
		return
	var texture: Texture2D = art["texture"]
	var width: float = art["width"]
	var height: float = art["height"]
	var head_start: float = art["head_start"]
	var along := head - root
	var reach := along.length()
	var axis := along / reach if reach > 0.5 else Vector2.UP
	var depth := (width - head_start) * scale_px
	var head_from := reach - depth * 0.5
	if head_from > 0.0:
		_slice(texture, Rect2(0.0, 0.0, head_start, height), root, axis, 0.0, head_from, scale_px, flip, color)
	_slice(texture, Rect2(head_start, 0.0, width - head_start, height), root, axis, head_from, depth, scale_px, flip,
		color)


# --- impact, shock, clink --------------------------------------------------------------------------

## The crack decal on the ground at `ground` (world), as wide as `radius` asks; it cracks open over
## CRACK_GROW_MS and fades over CRACK_FADE_MS (tweens on the decal: they pause with the world).
func _spawn_crack(ground: Vector2, radius: float) -> void:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null or not is_instance_valid(parent) or radius <= 0.0:
		return
	var crack := Sprite2D.new()
	crack.name = "ShapeCrack"
	crack.texture = CRACK_TEXTURE
	crack.hframes = CRACK_FRAMES
	crack.frame = 0
	crack.z_index = CRACK_Z
	var scale_factor := radius * 2.0 * CRACK_WIDTH_SHARE / CRACK_FRAME_PX
	crack.scale = Vector2(scale_factor, scale_factor * CRACK_SQUASH_Y)
	parent.add_child(crack)
	crack.global_position = ground
	crack.reset_physics_interpolation()
	var tween := crack.create_tween()
	tween.tween_method(func(f: float) -> void: crack.frame = clampi(int(f), 0, CRACK_FRAMES - 1),
		0.0, float(CRACK_FRAMES) - 0.01, CRACK_GROW_MS / 1000.0)
	tween.tween_property(crack, "modulate:a", 0.0, CRACK_FADE_MS / 1000.0)
	tween.tween_callback(crack.queue_free)


## The impact's dust at `ground` (world), about `radius` wide: one small puff at the centre, and for a
## wider hit more on a ring DUST_PUFF_REACH_PX inside its edge (squashed onto the ground).
func _spawn_dust(ground: Vector2, radius: float) -> void:
	var feel := Services.feel()
	if feel == null or radius <= 0.0:
		return
	feel.burst(DUST_PRESET, ground, Vector2.ZERO, Color.WHITE, DUST_COUNT_SCALE)
	var ring := radius - DUST_PUFF_REACH_PX
	if ring <= DUST_PUFF_REACH_PX * 0.5:
		return
	var count := clampi(roundi(TAU * ring / DUST_ARC_PX), 3, DUST_PUFFS_MAX)
	for i in count:
		var around := Vector2.from_angle(TAU * float(i) / float(count)) * ring
		feel.burst(DUST_PRESET, ground + Vector2(around.x, around.y * CRACK_SQUASH_Y), Vector2.ZERO, Color.WHITE,
			DUST_COUNT_SCALE)


func _draw_shock(shock: Dictionary, now: float) -> void:
	var k := clampf((now - float(shock["from"])) / SHOCK_MS, 0.0, 1.0)
	var radius := float(shock["radius"]) * lerpf(SHOCK_START_SHARE, 1.0, _ease_out(k))
	_canvas.draw_set_transform(to_local(shock["at"]), 0.0, Vector2(1.0, CRACK_SQUASH_Y))
	_canvas.draw_arc(Vector2.ZERO, radius, 0.0, TAU, SHOCK_POINTS, Color(_light, 0.8 * (1.0 - k)),
		SHOCK_WIDTH_PX * (1.0 - 0.5 * k), true)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_clink(at: Vector2) -> void:
	_canvas.draw_line(at - Vector2(CLINK_PX, 0.0), at + Vector2(CLINK_PX, 0.0), CLINK_COLOR, 2.0, true)
	_canvas.draw_line(at - Vector2(0.0, CLINK_PX), at + Vector2(0.0, CLINK_PX), CLINK_COLOR, 2.0, true)
	_canvas.draw_circle(at, CLINK_PX * 0.3, CLINK_COLOR)


# --- private ---------------------------------------------------------------------------------------

func _showing(now: float) -> bool:
	return _started_ms >= 0.0 and not _data.is_empty() and now - _started_ms < _duration_ms


## The entries of `list` ({"from": ms, ...}) younger than `max_ms` at `now`.
static func _younger(list: Array[Dictionary], now: float, max_ms: float) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in list:
		if now - float(entry["from"]) < max_ms:
			kept.append(entry)
	return kept


## True for every class but the light chain steps (the finisher, the charges): the bigger glints and
## streaks.
func _is_big() -> bool:
	return str(_data.get("class", "")) != TAP_CLASS


## True while the running step shows its strike frames (its weapon is the StrikeRig's; this node draws
## the Spear's `_draw_strike_spear` and the hit feel).
func _is_strike() -> bool:
	return not _strike.is_empty()


## Draws `src` of `texture` (its middle row on the axis) from `origin` (local, before the art pose's
## offset) along `axis` (unit): from `along_from` px for `along_len` px, `across` screen px per texture
## px across it, mirrored across the axis when `flip`, in `color`. In SKIN_UNIT_PX units, so the form
## skin's pattern keeps the slime's size whatever the weapon's scale.
func _slice(texture: Texture2D, src: Rect2, origin: Vector2, axis: Vector2, along_from: float, along_len: float,
		across: float, flip: bool, color: Color) -> void:
	if along_len <= 0.01 or across <= 0.0 or src.size.x <= 0.0:
		return
	var unit := Vector2(SKIN_UNIT_PX, -SKIN_UNIT_PX if flip else SKIN_UNIT_PX)
	_canvas.draw_set_transform_matrix(Transform2D(axis.angle(), unit, 0.0, _offset + origin))
	var high := src.size.y * across / SKIN_UNIT_PX
	_canvas.draw_texture_rect_region(texture,
		Rect2(along_from / SKIN_UNIT_PX, -high * 0.5, along_len / SKIN_UNIT_PX, high), src, color)
	_canvas.draw_set_transform(_offset)


## The weapon's colour at `alpha`: white in the form skin, else the form's tint (`_weapon_tint`).
func _weapon_color(alpha: float) -> Color:
	return Color(_weapon_tint, _weapon_tint.a * clampf(alpha, 0.0, 1.0))


## The packed art of `shape` (StrikeRig.art: the axe's {"texture", "width", "height", "head_start"} in
## texture px, from shapes.json, read once).
static func _art(shape: String) -> Dictionary:
	return StrikeRig.art(shape)


## Jelly green, or the Gulp form's tint while the slime wears one (the charge ring, the shock rings),
## and the weapon's skin (`_apply_skin`).
func _set_colors() -> void:
	_goo = GOO
	if _player != null and is_instance_valid(_player):
		var tint: Variant = _player.current_form().get("tint")
		if tint is Color:
			_goo = tint
	_light = _goo.lightened(LIGHT_SHARE)
	_apply_skin()


## The weapon layer wears the form the slime wears, as the slime's Visual does (player.gd
## `on_gulp_form_changed`): with the Visual on form_skin.gdshader, the layer's own skin material with
## the form's `skin` (none without a form); else the form's tint. Its own material, not the Visual's,
## so neither the elevation ghost nor the swim waterline cuts the weapon.
func _apply_skin() -> void:
	if _weapon_layer == null:
		return
	var form: Dictionary = {}
	var skinned := false
	if _player != null and is_instance_valid(_player):
		form = _player.current_form()
		var visual := _player.get_visual()
		var visual_material: ShaderMaterial = visual.material as ShaderMaterial if visual != null else null
		skinned = visual_material != null and visual_material.shader == PlayerScript.FORM_SKIN_SHADER
	var skin := int(form.get("skin", 0))
	if skinned:
		_skin.set_shader_parameter(SKIN_PARAM, skin)
		_weapon_layer.material = _skin if skin > 0 else null
		_weapon_tint = Color.WHITE
	else:
		_weapon_layer.material = null
		var tint: Variant = form.get("tint")
		_weapon_tint = tint if tint is Color else Color.WHITE
	# The strike rig's three canvas items (the strike weapons and the neck) wear the weapon's skin.
	for layer: Node2D in _rig_nodes():
		layer.material = _weapon_layer.material
	var rig := _rig()
	if rig != null:
		rig.set(&"tint", _weapon_tint)


## Redraws the canvas items (this node, its two layers and the three strike layers).
func _redraw() -> void:
	queue_redraw()
	if _weapon_layer != null:
		_weapon_layer.queue_redraw()
	if _over_layer != null:
		_over_layer.queue_redraw()
	for layer: Node2D in _rig_nodes():
		layer.queue_redraw()


## The player's strike rig (game/shapes/strike_rig.gd, under its Visual; null without one) and its
## three canvas items (the rig, StrikeRig.FRONT_NODE, StrikeRig.NECK_NODE).
func _rig() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		return null
	var rig := _player.get_strike_rig()
	return rig if rig != null and is_instance_valid(rig) else null


func _rig_nodes() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	var rig := _rig()
	if rig == null:
		return nodes
	nodes.append(rig)
	for node_name: String in [StrikeRig.FRONT_NODE, StrikeRig.NECK_NODE]:
		var node := rig.get_node_or_null(NodePath("../" + node_name)) as Node2D
		if node != null:
			nodes.append(node)
	return nodes


## A child canvas item named `layer_name` that `painter` draws on (its `draw` signal).
func _make_layer(layer_name: String, painter: Callable) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	layer.draw.connect(painter)
	add_child(layer)
	return layer


## Draws behind the slime's Visual (upward strikes, z 0) or in front of the world (z 1: a target lower
## on screen, sorted after the slime, never covers the tip).
func _set_behind(behind: bool) -> void:
	z_index = 0 if behind else 1
	var parent := get_parent()
	if parent == null or _player == null or not is_instance_valid(_player):
		return
	var visual := _player.get_visual()
	if behind and visual != null and visual.get_parent() == parent:
		if get_index() > visual.get_index():
			parent.move_child(self, visual.get_index())
	elif not behind:
		parent.move_child(self, parent.get_child_count() - 1)


func _ring_behind() -> void:
	if _ring != null and is_instance_valid(_ring) and _ring.get_parent() != null:
		_ring.get_parent().move_child(_ring, 0)


## From the slime's centre down to its feet (the ground the impact cracks).
func _feet_drop() -> Vector2:
	if _player == null or _player.body == null:
		return Vector2.ZERO
	return _player.body.global_position - _player.get_centre()


## The sprite's scale for a squash `share` toward `unit` (1: `along` x along the aim and `across` x
## across it; -1: the mirrored stretch; 0: rest), split onto the sprite's x and y.
static func _squash_scale(unit: Vector2, share: float, along: float, across: float) -> Vector2:
	var s := clampf(share, -1.0, 1.0)
	var on_aim := lerpf(1.0, along, s) if s >= 0.0 else 1.0 + (1.0 - along) * -s
	var off_aim := lerpf(1.0, across, s) if s >= 0.0 else 1.0 - (across - 1.0) * -s
	var wx := unit.x * unit.x
	var wy := unit.y * unit.y
	return Vector2(on_aim * wx + off_aim * wy, on_aim * wy + off_aim * wx)


static func _ease_out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)


static func _ease_in(k: float) -> float:
	return k * k


static func _real_now() -> float:
	return float(Time.get_ticks_msec())

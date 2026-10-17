extends "res://game/scripts/prism_eye.gd"
class_name WatcherEyeScript
## Scene script `game.watcher-eye` (the bestiary's row 33, a sentinel of every dungeon; docs/godot/
## BESTIARY.md "Watcher Eye"): a stone eye that levitates and wanders slowly round its area, with the
## Prism Eye's sight, charge and beam (game/scripts/prism_eye.gd). It never chases. It is placed
## where statues and stands give cover: every solid thing stops its sight and its beam.
##
## - **Watch:** it hovers `floatHeightPx` up (a bob, a shadow on the ground under it) and drifts to
##   a spot within `wanderRadiusPx` of its post (kept `arenaInsetPx` inside its pen) at
##   `wanderSpeed` (`wanderMaxMs` at most), rests there `wanderPauseMs`, then picks another. All
##   the while its gaze turns round as the Prism Eye's does (the same `aimDirections` switch: free
##   aim turns smoothly at `turnDegPerS`; line aim holds a line `holdMs`, then turns to the next one
##   left or right at random over `stepMs`), a dim gaze line on the ground showing where it looks.
##   Its iris (drawn on the blank eyeball) follows the gaze; looking up the screen it shows its
##   carved back. Its body is not solid (the slime passes under it) but statues and walls stop it
##   (mask `world`).
## - **Charge** (the tell, `chargeMs`): its gaze meets the slime with nothing solid between: it
##   stops dead (free aim: the aim locks where the slime stood, `trackDegPerS` 0; line aim: down its
##   line), its eye and runes glow and an aim line flickers on; a slime that steps aside is missed.
## - **Fire** (`beamMs`): a long beam (`beamPx`) down that line, stopped by the first solid
##   thing.
## - **Cool** (`coolMs`), then it drifts and turns on.
## - **Its back is open, its front clinks** (`_shields`): a hit from an attacker it is looking away
##   from (`backDot`) lands, any other clinks. The right tool: hide, wait until it looks away, then
##   the Spear from behind (24 health: two jabs). A hit from behind alarms it: for `alertMs` it turns
##   toward the slime (free aim at `alertTurnDegPerS`; line aim: its next turn is to the slime's
##   line, over `alertStepMs`). The back, the alarm and the Bow's hook (`on_arrow_hit`: an arrow into
##   its eye) are the Prism Eye's.
##
## Owner: enemy builder.

const FRAME_FRONT := 0
const FRAME_GLOW := 1
const FRAME_BACK := 2
## The blank eyeball's middle in the sheet cell.
const EYE_PX := Vector2(120.0, 125.0)
## Looking up the screen (the gaze's y under this) it shows its back.
const BACK_GAZE_Y := -0.45
## Presentation: the bob, the shadow, the glow on its back while it charges, the hurtbox over the
## art's middle, the iris and the beam's colours.
const BOB_MS := 520.0
const SHADOW_SIZE := Vector2(18.0, 6.5)
const HURTBOX_RISE_PX := 27.0
const GLOW_TINT := Color(1.45, 1.05, 0.8)
const IRIS_PX := 15.0
const PUPIL_PX := 7.0
const PUPIL_REACH := Vector2(20.0, 13.0)
const IRIS_COLOR := Color("#5b3a1c")
const IRIS_HOT := Color("#ff6a1a")
const BEAM_GLOW_COLOR := Color(1.0, 0.42, 0.12, 0.45)
const BEAM_CORE_COLOR := Color(1.0, 0.95, 0.8, 0.95)
const AIM_LINE_COLOR := Color(1.0, 0.6, 0.3, 0.6)

var _spot: Vector2 = Vector2.INF
var _rest_until: float = 0.0
var _spot_since: float = 0.0
var _lift: float = 0.0


func _look_setup() -> void:
	if _gaze_look != null:
		_gaze_look.line_only = true
	if _pupil != null:
		_pupil.iris_px = IRIS_PX
		_pupil.pupil_px = PUPIL_PX
		_pupil.pupil_reach_px = PUPIL_REACH
		_pupil.iris_color = IRIS_COLOR
		_pupil.iris_hot = IRIS_HOT
	if _beam_look != null:
		_beam_look.beam_glow = BEAM_GLOW_COLOR
		_beam_look.beam_core = BEAM_CORE_COLOR
		_beam_look.aim_color = AIM_LINE_COLOR
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE
	_lift = pattern("floatHeightPx", 40.0)


# --- the Prism Eye's hooks -------------------------------------------------------------------------

## Line aim: its next line, left or right at random; alarmed, the line toward the slime (the Prism
## Eye's).
func _next_line(now: float, slime: Node2D) -> int:
	if slime != null and now < _alert_until:
		return super(now, slime)
	return posmod(_line + (1 if randf() < 0.5 else -1), maxi(1, lines().size()))


## It drifts from spot to spot round its post, resting at each.
func _watch_move(now: float, delta: float) -> void:
	if now < _rest_until:
		body.velocity = Vector2.ZERO
		return
	if _spot == Vector2.INF:
		_spot = _next_spot()
		_spot_since = now
	var velocity := _velocity_toward(_spot, pattern("wanderSpeed", 32.0), delta)
	if velocity == Vector2.ZERO or now - _spot_since > pattern("wanderMaxMs", 5000.0):
		# There (or held up by a statue too long): rest, then on to another spot.
		_spot = Vector2.INF
		_rest_until = now + pattern("wanderPauseMs", 1000.0)
		body.velocity = Vector2.ZERO
		return
	body.velocity = velocity


## A spot within `wanderRadiusPx` of its post, kept inside its pen (an old centre).
func _next_spot() -> Vector2:
	var radius := pattern("wanderRadiusPx", 120.0)
	var angle := randf() * TAU
	var spot := _home + Vector2(cos(angle), sin(angle)) * randf_range(radius * 0.35, radius)
	if _arena.is_empty():
		return spot
	var inset := pattern("arenaInsetPx", 48.0)
	var x := float(_arena.get("x", spot.x))
	var y := float(_arena.get("y", spot.y))
	var w := float(_arena.get("w", 0.0))
	var h := float(_arena.get("h", 0.0))
	return Vector2(clampf(spot.x, x + inset, x + w - inset), clampf(spot.y, y + inset, y + h - inset))


func _frame_now() -> int:
	if Vector2.RIGHT.rotated(_gaze).y < BACK_GAZE_Y:
		return FRAME_BACK
	if _phase == PHASE_CHARGE or _phase == PHASE_FIRE:
		return FRAME_GLOW
	return FRAME_FRONT


func _pupil_shown() -> bool:
	return _frame_now() != FRAME_BACK


func _orb_px() -> Vector2:
	return EYE_PX


## It hovers and bobs; the hurtbox rides with it; the shadow fades as it bobs up.
func _float_look(now: float, charge: float) -> void:
	var bob_px := pattern("bobPx", 4.0)
	var bob := sin(now / BOB_MS) * bob_px
	_lift = pattern("floatHeightPx", 40.0) + bob
	set_look(_lift)
	if damage_area != null:
		damage_area.position = Vector2(0.0, -_lift - HURTBOX_RISE_PX)
	var shadow := ground_shadow()
	if shadow != null:
		shadow.strength = lerpf(0.85, 0.6, (bob + bob_px) / maxf(0.01, 2.0 * bob_px))
	if pose != null:
		pose.modulate = Color.WHITE.lerp(GLOW_TINT, charge) if _frame_now() == FRAME_BACK else Color.WHITE


## A stun holds it in the air where it is.
func _on_stunned(now: float, delta: float) -> void:
	super(now, delta)
	_float_look(now, 0.0)


func _defeat() -> void:
	if is_defeated():
		return
	super()
	if pose != null:
		pose.modulate = Color.WHITE
	# The broken eye drops to the ground.
	set_look(0.0)
	if damage_area != null:
		damage_area.position = Vector2(0.0, -HURTBOX_RISE_PX)

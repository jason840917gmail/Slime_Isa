extends "res://game/enemy/patterned_enemy.gd"
class_name PipeWormScript
## Scene script `game.pipe-worm` (the bestiary's row 12, a turret; docs/godot/BESTIARY.md "Pipe
## Worm"): a banded worm living in an old clay pipe set in a wall, facing `aim_direction`. The wall
## is the world's (the Bestiary pen's is a short fieldstone wall); the scene is the pipe and the
## worm, its feet at the wall's foot.
##
## - **Its view** (owner, 2026-10-19): the half of the world in front of its wall, 180 degrees out
##   of its pipe (`aim_direction`, snapped to the nearest of up, down, left and right): a slime
##   behind the wall, or level with it, is not seen however near (the old circle of
##   `targeting_radius` alone saw it through the wall). It hides while the slime is out of view or
##   within `hideRangePx`, and looks out again `unhideMs` after the slime is back in view.
## - **Hidden:** down in its pipe, two eyes glinting in the dark. Blows never reach it in the pipe
##   (every hit clinks).
## - **Up** (popping up over `riseMs`): it spits on a steady beat, every `spitIntervalMs` (the first
##   `firstSpitMs` after it comes up), at the slime wherever it stands in view (the four-way rule of
##   2026-10-16 is gone): the aim is the slime's hurtbox middle when the charge starts, kept within
##   `aimConeDeg` around the pipe's line (never back along its wall).
## - **Charge** (the tell, `spitWindupMs`): it swells and shakes in its pipe; then it spits a mud
##   glob (`projectile.mud-glob`, game/scripts/mud_glob.gd: the scene's `projectile` and
##   `attributes.projectileSpeed`) along the aim (a slime that moved is missed) and shows its spitting
##   pose for `spitPoseMs`. The worm never leaves its pipe (owner, 2026-10-19): the glob is born off
##   the wall instead, MOUTH_PX out along the pipe's line past the wall's foot (`_mouth`), so it does
##   not hit the wall at once.
## - **The right tool:** the Gulp catches the glob in flight and throws it back: a hit tagged
##   `mud-glob` kills it at once, hidden or not (`_kill_hit`). Anything else the Gulp throws (a pot,
##   a rock: tagged `thrown`) hits it too, hidden or not, for its own damage (owner, 2026-10-19).
## - **Shaken out** (`dazedMs`): a Roll's bonk within `bonkReachPx` of its feet (GroundShake: the
##   slime rolling into the wall under its pipe) jolts it out of the pipe; it lies on the floor in
##   front of it, dazed and open to every hit (the Spear), then wriggles back in.
## - **A pipe up in a deep wall** (a dungeon room's two-cell walls, which collide over their whole
##   cells; 2026-10-19: R6's globs were born inside the wall and stopped at once): how deep it sits
##   is how far past its mouth its line first leaves the world's collision (`_wall_depth`, found once);
##   the glob leaves there, at the wall's foot, and the bonk's reach and the shaken-out worm move out
##   by as much. A pipe at its wall's foot (the Bestiary pen) has no depth: nothing changes.
## - **Thrown things reach it at its wall's face** (owner, 2026-11-21: "can't hit the pipe worm in
##   R6"): a throw strikes only what it has a clear line to (AbilityWorld.hurtboxes_in_reach, "nothing
##   should cross walls"), and its hurtbox's middle is inside its wall, so the line is measured to
##   `reach_point`, just out of the wall's face along its pipe's line.
##
## Owner: enemy builder.

const GlobScript := preload("res://game/scripts/mud_glob.gd")
const GroundShake := preload("res://game/enemy/ground_shake.gd")
const FourWayAim := preload("res://game/enemy/four_way_aim.gd")

const PHASE_HIDDEN := "hidden"
const PHASE_UP := "up"
const PHASE_CHARGE := "charge"
const PHASE_SPIT := "spit"
const PHASE_DAZED := "dazed"
const FRAME_HOLE := 0
const FRAME_UP := 1
const FRAME_SPIT := 2
const FRAME_DAZED := 3
const CUE_RISE := &"DropPop"
const CUE_HIDE := &"HitBlocked"
const CUE_SPIT := &"PipeWormSpit"
const CUE_SHAKEN := &"RollBonk"
const CUE_BACK := &"DropLand"
const MUD := &"dodge-dust"
## Presentation: the pop up, the charge's swell and shake, the breath while up, the daze's sway.
const RISE_SQUASH := 0.7
const CHARGE_SWELL := 0.14
const CHARGE_SHAKE_RAD := 0.05
const CHARGE_SHAKE_MS := 35.0
const BREATH := 0.03
const BREATH_MS := 380.0
const DAZE_SWAY_RAD := 0.06
const DAZE_SWAY_MS := 260.0
## The glob leaves this far along the aim from the pipe's centre (past the wall's foot).
const MOUTH_PX := 38.0
## Shaken out, the worm lies this far below its pipe, and its hurtbox follows it there.
const FALLEN_POSE_PX := 16.0
const FALLEN_HURTBOX_PX := 30.0
## How far past its mouth a pipe's wall is looked for (a room's walls are two cells deep), in steps of
## WALL_STEP_PX; the glob leaves GLOB_CLEAR_PX past the wall (its body's radius and a little more).
const WALL_SEARCH_PX := 192.0
const WALL_STEP_PX := 4.0
const GLOB_CLEAR_PX := 10.0
## A throw reaches it at this far out of its wall's face (`reach_point`).
const REACH_OUT_PX := 2.0
## The empty pipes beaten worms leave (`_leave_empty_pipe`); a worm back on the spot (the
## playground's pens bring one back) takes its pipe's place within this distance.
const EMPTY_PIPE_GROUP := &"pipe_worm_empty_pipe"
const EMPTY_PIPE_SAME_SPOT_PX := 8.0
## The world's layer (the walls) that stops a glob.
const WORLD_MASK := 1

## The way its pipe faces (the wall's open side), snapped to the nearest of up, down, left and
## right: it sees the half of the world in front of it and spits within `aimConeDeg` of it. A placed
## worm gets it from its placed node's rotation (game/enemy/placed_enemy.gd `facing()`).
@export var aim_direction: Vector2 = Vector2.DOWN
## The empty pipe, shown while the worm is out of it.
@export var hole: Sprite2D
## The eyes glinting in the dark while it hides (game/enemy/eye_glint.gd).
@export var glint: Node2D

var _next_spit_at: float = 0.0
var _clear_since: float = 0.0
var _aim: Vector2 = Vector2.DOWN
var _hurtbox_rest: Vector2 = Vector2.ZERO
## How deep its pipe sits in its wall past the mouth (`_wall_depth`); NAN until found.
var _depth: float = NAN
## How far along its line from its centre its wall's face is (found with `_depth`; 0 in the open).
var _face_px: float = 0.0


func _ready() -> void:
	super()
	add_to_group(GroundShake.GROUP)
	if damage_area != null:
		_hurtbox_rest = damage_area.position
	_aim = _pipe_line()
	_hide(Services.now_ms(), false)
	_take_empty_pipe.call_deferred()


func _step_pattern(now: float, _delta: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	engaged = engaged and _in_view(centre, slime)
	var close := engaged and centre.distance_to(slime) <= pattern("hideRangePx", 72.0)
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_HIDDEN:
			set_look(0.0)
			if close or not engaged:
				_clear_since = now
			elif now - _clear_since >= pattern("unhideMs", 500.0):
				_rise(now)
		PHASE_UP:
			var rise := clampf(elapsed / maxf(1.0, pattern("riseMs", 200.0)), 0.0, 1.0)
			var breath := sin(now / BREATH_MS) * BREATH
			set_look(0.0, Vector2(1.0 - breath, lerpf(RISE_SQUASH, 1.0, rise) + breath))
			if close or not engaged:
				_hide(now)
			elif now >= _next_spit_at and rise >= 1.0:
				_aim = _aim_at(_aim_point(target))
				# silent: its one sound is the spit (owner, 2026-10-19)
				_transition(PHASE_CHARGE, now)
		PHASE_CHARGE:
			var t := clampf(elapsed / maxf(1.0, pattern("spitWindupMs", 550.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE * (1.0 + CHARGE_SWELL * t), sin(elapsed / CHARGE_SHAKE_MS) * CHARGE_SHAKE_RAD * t)
			if close or not engaged:
				_hide(now)
			elif t >= 1.0:
				_spit(now)
		PHASE_SPIT:
			set_look(0.0, Vector2(1.06, 0.96))
			if elapsed >= pattern("spitPoseMs", 300.0):
				_transition(PHASE_UP, now - pattern("riseMs", 200.0))
				set_frame(FRAME_UP)
		PHASE_DAZED:
			_fallen_look(sin(elapsed / DAZE_SWAY_MS) * DAZE_SWAY_RAD)
			if elapsed >= pattern("dazedMs", 2600.0):
				_cue(CUE_BACK)
				_hide(now, false)


## The line out of its pipe: `aim_direction` snapped to the nearest cardinal (down when unset).
func _pipe_line() -> Vector2:
	var line := FourWayAim.snap(aim_direction)
	return line if line != Vector2.ZERO else Vector2.DOWN


## True when `point` (the slime's centre) is in the half of the world in front of its wall: past
## the pipe along its line (out of a deep wall, past the wall's foot).
func _in_view(centre: Vector2, point: Vector2) -> bool:
	return (point - centre).dot(_pipe_line()) > _wall_depth()


## The way to `aim_at` from its mouth out of the wall, kept within `aimConeDeg` around the pipe's
## line.
func _aim_at(aim_at: Vector2) -> Vector2:
	var line := _pipe_line()
	var offset := aim_at - _mouth()
	if offset.length() < 1.0:
		return line
	var half := deg_to_rad(pattern("aimConeDeg", 160.0)) * 0.5
	return line.rotated(clampf(line.angle_to(offset), -half, half))


## Where its glob is born: off its wall, MOUTH_PX out along the pipe's line from its centre and past
## the foot of a deep wall (`_out_of_wall`), whatever way it is aimed.
func _mouth() -> Vector2:
	return get_centre() + _out_of_wall() + _pipe_line() * MOUTH_PX


func _rise(now: float) -> void:
	_transition(PHASE_UP, now)
	set_frame(FRAME_UP)
	_show_worm_in_pipe(true)
	_show_glint(false)
	_next_spit_at = maxf(_next_spit_at, now + pattern("firstSpitMs", 400.0))
	_cue(CUE_RISE)


func _hide(now: float, sound: bool = true) -> void:
	_transition(PHASE_HIDDEN, now)
	set_frame(FRAME_HOLE)
	set_look(0.0)
	_show_worm_in_pipe(true)
	_clear_since = now
	_show_glint(true)
	if sound:
		_cue(CUE_HIDE)


func _spit(now: float) -> void:
	_transition(PHASE_SPIT, now)
	set_frame(FRAME_SPIT)
	_next_spit_at = now + pattern("spitIntervalMs", 1700.0)
	var config := _projectile_config()
	# off the wall it is set in
	var mouth := _mouth()
	if not config.is_empty():
		_attack_direction = _aim
		_fire_projectile(mouth, config)
	_cue(CUE_SPIT)
	_puff(MUD, mouth)


## The worm in its pipe (the Visual's pipe frames) or out on the floor (the Visual is the fallen
## worm, the empty pipe shows behind it and the hurtbox follows the worm).
func _show_worm_in_pipe(in_pipe: bool) -> void:
	if hole != null:
		hole.visible = not in_pipe
	if not in_pipe:
		_show_glint(false)
	if damage_area != null:
		damage_area.position = _hurtbox_rest + (Vector2.ZERO if in_pipe else Vector2(0.0, FALLEN_HURTBOX_PX) + _out_of_wall())


## Its fallen look: FALLEN_POSE_PX below its pipe, moved out of a deep wall to the wall's foot.
func _fallen_look(lean: float) -> void:
	set_look(-FALLEN_POSE_PX, Vector2.ONE, lean)
	if pose != null:
		pose.position += _out_of_wall()


## How far it moves out along its line when it is out of a deep wall (zero at a wall's foot).
func _out_of_wall() -> Vector2:
	return _pipe_line() * _wall_depth()


## How much further than its mouth (MOUTH_PX along its line from its centre) its glob must be born
## to start GLOB_CLEAR_PX past the point where the line out of its centre leaves the world's
## collision (its wall's face): 0 when the mouth is that far out already (a pipe at its wall's
## foot). Measured from the centre, not the mouth, so a mouth just outside the face, closer to it
## than the glob's size, moves out too (R6's side walls, 2026-10-19: such globs died at once). Found
## once, from a physics step (the walls collide by then).
func _wall_depth() -> float:
	if not is_nan(_depth):
		return _depth
	if body == null or not body.is_inside_tree():
		return 0.0
	var line := _pipe_line()
	var centre := get_centre()
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = WORLD_MASK
	query.collide_with_bodies = true
	query.exclude = [body.get_rid()]
	var space := body.get_world_2d().direct_space_state
	var walked := 0.0
	var inside := false
	while walked <= MOUTH_PX + WALL_SEARCH_PX:
		query.position = centre + line * walked
		if space.intersect_point(query, 1).is_empty():
			break
		inside = true
		walked += WALL_STEP_PX
	if not inside or walked > MOUTH_PX + WALL_SEARCH_PX:
		_depth = 0.0
		_face_px = 0.0
	else:
		_depth = maxf(0.0, walked + GLOB_CLEAR_PX - MOUTH_PX)
		_face_px = walked
	return _depth


## Where a thrown thing's line must get to reach it (AbilityWorld.reach_point): its centre when its
## pipe is in the open, else REACH_OUT_PX past its wall's face along its line (its hurtbox's middle is
## inside the wall, which cuts every line to it).
func reach_point() -> Vector2:
	_wall_depth()
	var centre := get_centre()
	return centre if _face_px <= 0.0 else centre + _pipe_line() * (_face_px + REACH_OUT_PX)


func _show_glint(on: bool) -> void:
	if glint != null:
		glint.set(&"shown", on)


## A Roll's bonk against the wall under its pipe (any bonk, heavy or not) shakes it out: within
## `bonkReachPx` of its feet, or of the wall's foot in front of a pipe up in a deep wall.
func on_ground_shake(at: Vector2, _radius: float, _heavy: bool) -> void:
	if is_defeated() or _phase == PHASE_DAZED:
		return
	var reach := pattern("bonkReachPx", 60.0)
	var foot := feet() + _out_of_wall()
	if feet().distance_to(at) > reach and foot.distance_to(at) > reach:
		return
	var now := Services.now_ms()
	_transition(PHASE_DAZED, now)
	set_frame(FRAME_DAZED)
	_show_worm_in_pipe(false)
	_fallen_look(0.0)
	_cue(CUE_SHAKEN)
	_puff(MUD, foot)


## True while it lies out of its pipe, shaken out.
func is_shaken_out() -> bool:
	return _phase == PHASE_DAZED


## Blows never reach it in its pipe; shaken out it is open.
func _shields(request: Dictionary) -> bool:
	# a thrown thing (a pot, a rock: the Gulp's throw) always reaches it (owner, 2026-10-19)
	return _phase != PHASE_DAZED and not has_tag(request, THROWN_TAG)


## Its own glob thrown back.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, GlobScript.GLOB_KIND)


## Rooted in its pipe: a knockback does not move it.
func _slides_when_stunned() -> bool:
	return false


func _defeat() -> void:
	if is_defeated():
		return
	_show_worm_in_pipe(false)
	super()
	_fallen_look(0.0)
	_leave_empty_pipe()


## Beaten, its empty pipe stays in the wall (owner, 2026-10-19) while the corpse fades and goes: a
## plain picture of the `hole` frame on the world's entity layer, where the worm stood, until the
## world is built again (and the worm is back). The body's own `hole` hides, so it does not fade.
func _leave_empty_pipe() -> void:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if hole == null or hole.texture == null or parent == null or body == null:
		return
	var pipe := Node2D.new()
	pipe.name = "EmptyPipe"
	var picture := Sprite2D.new()
	picture.texture = hole.texture
	picture.hframes = hole.hframes
	picture.vframes = hole.vframes
	picture.frame = hole.frame
	picture.centered = hole.centered
	picture.offset = hole.offset
	picture.region_enabled = hole.region_enabled
	picture.region_rect = hole.region_rect
	picture.transform = hole.transform
	pipe.add_child(picture)
	pipe.add_to_group(EMPTY_PIPE_GROUP)
	parent.add_child(pipe)
	pipe.global_position = body.global_position
	hole.visible = false


## A worm back where a beaten one left its empty pipe: the pipe goes (the worm's own shows).
func _take_empty_pipe() -> void:
	if body == null or not body.is_inside_tree():
		return
	for pipe: Node in body.get_tree().get_nodes_in_group(EMPTY_PIPE_GROUP):
		if pipe is Node2D and (pipe as Node2D).global_position.distance_to(body.global_position) <= EMPTY_PIPE_SAME_SPOT_PX:
			pipe.queue_free()

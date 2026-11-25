extends "res://game/enemy/patterned_enemy.gd"
class_name PickMoleScript
## Scene script `game.pick-mole` (the bestiary's row 27, a lobber; docs/godot/BESTIARY.md "Pick
## Mole"): a miner mole that hides behind crates and lobs pickaxes over them.
##
## How it aims is `aimDirections` (owner, 2026-10-16: the Pick Mole is eight-way, as the skeletons;
## game/enemy/four_way_aim.gd): 8 (its setting) throws along the slime's row, column or diagonal; 4
## only along rows and columns; 0 at the slime wherever it stands (the first design).
##
## - **Ducked** (`duckMs`): crouched behind its crates, only its helmet up: every hit clinks but a
##   blast's. It stays down while the slime is out of its pen.
## - **Line up** (4 or 8, `shuffleMaxMs` at most): still ducked, it sidesteps along its crates (its
##   lane, `laneHalfPx` either side of its post, at `shuffleSpeed`) to the nearest spot where the
##   slime lies on one of its lines (within `lineTolerancePx`): under it, or on a diagonal through
##   it; or as near as its lane goes.
## - **Pop** (the tell, `popMs`): it pops up and raises a pickaxe over its head. Line aim locks its
##   line here: the line it shares with the slime, else the line nearest the slime's side.
## - **Throw:** `throws` pickaxes, one every `throwEveryMs` (its throwing pose for `throwPoseMs`):
##   each flies in an arc (game/enemy/lobbed_shot.gd, `flightMs`, `arcPx` high), its landing spot
##   darkening on the ground as it comes: free aim to where the slime stands as it lets go; line aim
##   straight along its line to where the slime's row (or column) crosses it (`minThrowPx` to
##   `maxThrowPx` away), so a slime that steps off the line is missed. Landing within `landRadiusPx`
##   of the slime's feet it hits for `pickDamage` with `pickKnockback`.
## - **Reload** (`reloadMs`): arms down, catching its breath, open; then it ducks again.
## Up (pop, throw, reload) it is open: the Spear reaches it from beside its crates (24 health: two
## jabs). A stun while it throws ends the volley.
## - **The right tool:** a Goo Bomb (a hit tagged `blast`) over the crates finishes it at once, even
##   ducked (`_kill_hit`). The Bow's hook: `on_arrow_hit` while it is up.
##
## Owner: enemy builder.

const LobbedShot := preload("res://game/enemy/lobbed_shot.gd")
const FourWayAim := preload("res://game/enemy/four_way_aim.gd")

const PHASE_DUCKED := "ducked"
const PHASE_LINE_UP := "line-up"
const PHASE_POP := "pop"
const PHASE_THROW := "throw"
const PHASE_RELOAD := "reload"
const FRAME_DUCKED := 0
const FRAME_RAISE := 1
const FRAME_THROW := 2
const BLAST_TAG := "blast"
const BOW_TARGETS := &"bow_targets"
const PICKAXE_PATH := "res://asset/MAPS/enemies/64x64-pickaxe.webp"
## The pickaxe's picture (64 px) drawn at this scale; it leaves from over the mole's head.
const PICKAXE_SCALE := 0.8
const HAND_RISE_PX := 40.0
const CUE_POP := &"DropPop"
const CUE_THROW := &"Lash"
const CUE_LAND := &"BreakMetal"
const CUE_DUCK := &"HitBlocked"
const DUST := &"dodge-dust"
## Presentation: the pop's squash, the breath while up.
const POP_SQUASH := Vector2(1.12, 0.82)
const BREATH := 0.03
const BREATH_MS := 300.0

var _thrown: int = 0
var _next_throw_at: float = 0.0
## The line its volley flies along (a cardinal direction).
var _line: Vector2 = Vector2.DOWN


func _ready() -> void:
	super()
	add_to_group(BOW_TARGETS)
	_transition(PHASE_DUCKED, Services.now_ms())
	set_frame(FRAME_DUCKED)


func is_up() -> bool:
	return _phase == PHASE_POP or _phase == PHASE_THROW or _phase == PHASE_RELOAD


## The line its volley flies along.
func get_line() -> Vector2:
	return _line


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var elapsed := _elapsed(now)
	var slime_body := target.get("body") as Node2D
	var slime_feet: Vector2 = slime_body.global_position if slime_body != null else feet()
	match _phase:
		PHASE_DUCKED:
			set_look(0.0)
			if engaged and elapsed >= pattern("duckMs", 1500.0):
				if aim_directions() > 0:
					_transition(PHASE_LINE_UP, now)
				else:
					_pop(now, slime_feet)
		PHASE_LINE_UP:
			set_look(0.0)
			var want_x := _line_up_x(slime_feet)
			var goal := Vector2(want_x, _home.y)
			var tolerance := pattern("lineTolerancePx", 14.0)
			var lined := absf(get_centre().x - want_x) <= tolerance * 0.5
			if not engaged:
				_transition(PHASE_DUCKED, now)
			elif lined or elapsed >= pattern("shuffleMaxMs", 1200.0):
				_pop(now, slime_feet)
			else:
				body.velocity = _velocity_toward(goal, pattern("shuffleSpeed", 80.0), delta)
		PHASE_POP:
			var t := clampf(elapsed / maxf(1.0, pattern("popMs", 450.0)), 0.0, 1.0)
			set_look(0.0, POP_SQUASH.lerp(Vector2.ONE, t))
			if t >= 1.0:
				_thrown = 0
				_next_throw_at = now
				_transition(PHASE_THROW, now)
		PHASE_THROW:
			if now >= _next_throw_at:
				if _thrown >= int(pattern("throws", 3.0)) or not engaged:
					_reload(now)
				else:
					_throw(now, target)
			elif now - (_next_throw_at - pattern("throwEveryMs", 520.0)) >= pattern("throwPoseMs", 200.0):
				set_frame(FRAME_RAISE)
			var breath := sin(now / BREATH_MS) * BREATH
			set_look(0.0, Vector2(1.0 + breath, 1.0 - breath))
		PHASE_RELOAD:
			set_look(0.0)
			if elapsed >= pattern("reloadMs", 800.0):
				_duck(now)


## Where along its lane (an old-centre x) it lines up with the slime at `slime_feet`: under it, or
## (eight-way) where a diagonal through it crosses the lane; the nearest such spot inside its lane,
## else the lane's end nearest the slime's column.
func _line_up_x(slime_feet: Vector2) -> float:
	var lane := pattern("laneHalfPx", 64.0)
	var low := _home.x - lane
	var high := _home.x + lane
	var rise := absf(slime_feet.y - feet().y)
	var spots: Array[float] = [slime_feet.x]
	if aim_directions() == 8:
		spots.append(slime_feet.x - rise)
		spots.append(slime_feet.x + rise)
	var here := get_centre().x
	var best := INF
	for x: float in spots:
		if x >= low and x <= high and absf(x - here) < absf(best - here):
			best = x
	return best if best != INF else clampf(slime_feet.x, low, high)


## How it aims: 0 at the slime, 4 or 8 along lines (`aimDirections`).
func aim_directions() -> int:
	var count := int(pattern("aimDirections", 0.0))
	return count if count == 4 or count == 8 else 0


## Up. Line aim locks its line: the row or column it shares with the slime, else the slime's side
## (8: the nearest of eight lines).
func _pop(now: float, slime_feet: Vector2) -> void:
	_transition(PHASE_POP, now)
	set_frame(FRAME_RAISE)
	var offset := slime_feet - feet()
	var eight := aim_directions() == 8
	_line = FourWayAim.line_direction(feet(), slime_feet, pattern("lineTolerancePx", 14.0), eight)
	if _line == Vector2.ZERO:
		_line = FourWayAim.snap(offset, eight)
	if _line == Vector2.ZERO:
		_line = Vector2.DOWN
	face_x(_line.x if absf(_line.x) > 0.01 else offset.x)
	_cue(CUE_POP)


func _throw(now: float, target: Dictionary) -> void:
	_thrown += 1
	_next_throw_at = now + pattern("throwEveryMs", 520.0)
	set_frame(FRAME_THROW)
	_cue(CUE_THROW)
	var slime_body := target.get("body") as Node2D
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if slime_body == null or parent == null:
		return
	var shot := LobbedShot.new()
	shot.name = "Pickaxe"
	shot.from = feet() - Vector2(0.0, 1.0)
	if aim_directions() == 0:
		shot.to = slime_body.global_position
		face_x(slime_body.global_position.x - feet().x)
	else:
		# Straight along its line, to where the slime's row (or column) crosses it.
		var reach := clampf((slime_body.global_position - feet()).dot(_line), pattern("minThrowPx", 40.0),
			pattern("maxThrowPx", 320.0))
		shot.to = feet() + _line * reach
	shot.flight_ms = pattern("flightMs", 700.0)
	shot.arc_px = pattern("arcPx", 80.0)
	shot.stuck_ms = pattern("stuckMs", 450.0)
	shot.picture_path = PICKAXE_PATH
	shot.picture_scale = PICKAXE_SCALE
	shot.start_lift_px = HAND_RISE_PX
	shot.on_land = _pick_landed
	parent.add_child(shot)
	shot.start()


## A pickaxe came down at the ground point `at`.
func _pick_landed(at: Vector2) -> void:
	_cue(CUE_LAND)
	_puff(DUST, at)
	if is_defeated():
		return
	var target := _primary_target()
	var slime_body := target.get("body") as Node2D
	if slime_body == null or not _is_engaged(target):
		return
	if slime_body.global_position.distance_to(at) > pattern("landRadiusPx", 24.0):
		return
	_route_hit_from(at, target, pattern("pickDamage", 20.0), pattern("pickKnockback", 200.0))


func _reload(now: float) -> void:
	_transition(PHASE_RELOAD, now)
	set_frame(FRAME_RAISE)


func _duck(now: float) -> void:
	_transition(PHASE_DUCKED, now)
	set_frame(FRAME_DUCKED)
	_cue(CUE_DUCK)


## The Bow's hook (bow_arrow.gd): an arrow takes it while it is up. `hit` is the arrow's
## hit (unused). True when it fell.
func on_arrow_hit(_hit: Dictionary) -> bool:
	if is_defeated() or not is_up():
		return false
	_defeat()
	return true


## A stun while it throws ends the volley.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_POP or _phase == PHASE_THROW:
		_reload(now)


## Ducked behind its crates (lining up too) it clinks.
func _shields(_request: Dictionary) -> bool:
	return _phase == PHASE_DUCKED or _phase == PHASE_LINE_UP


## A Goo Bomb's blast reaches it behind its crates.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, BLAST_TAG)


## Its feet stay behind its crates: a knockback does not move it.
func _slides_when_stunned() -> bool:
	return false

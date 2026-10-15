extends RefCounted
## The slime's grab on a heavy block (rework mode only; bomb-lantern-and-secrets design section 4;
## BODY_SHAPES.md "Heavy plates and heavy blocks"; numbers in game-constants.json
## `puzzles.heavyBlock`). Owned by player.gd, which starts it on an interact press and lets it own
## the step while it holds (`_rework_owns_step`).
##
## - **Grab** (`try_begin`): the slime faces a heavy block (group `heavy_blocks`) and touches it
##   (its body within `grabReachPx` of the block's footprint, overlapping it sideways). It latches on
##   with its mouth: it stretches toward the block and slides to stand square on that side.
## - **Hold**: while the interact key stays held (W in keys-only, a held right click in the
##   keyboard + mouse and pointer schemes), walking toward the block pushes it and walking away pulls
##   it, one cell (`cellPx`) per move over `moveMs`, after the walk key has been held `startDelayMs`
##   (a tap does not move it; a held key goes on cell after cell). Walking sideways does nothing.
## - **Only the Stone form moves it** (`presses_plates`). The plain slime strains: it wobbles, the
##   block trembles, a strain cue ticks and the line "Too heavy... I need to be stone." shows (at
##   most every `strainLineMs`). Nothing moves.
## - A move the block cannot make (HeavyBlock.can_move: walls, cliffs, rims, holes, stairs, other
##   blocks, solid objects, deep water) knocks once (`bump`). A pull also needs room behind the slime
##   (its body's test move).
## - **Release**: letting go of the key (a move under way finishes first), a knock or a hit (the
##   player releases it when movement is suppressed), death or a teleport.
##
## The slime moves through player.gd's ArcadeMover step: this only sets its velocity (toward its
## place beside the block, which moves on its own through its script).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const BLOCK_GROUP := &"heavy_blocks"
const CONSTANTS := "puzzles.heavyBlock"
const STRAIN_LINE := "Too heavy... I need to be stone."
const CUE_GRAB := &"HeavyBlockGrab"
const CUE_SLIDE := &"HeavyBlockSlide"
const CUE_BUMP := &"HeavyBlockBump"
const CUE_STRAIN := &"HeavyBlockStrain"
## Cues without a take yet play these instead.
const PLACEHOLDER_CUES := {
	CUE_GRAB: &"GulpCatch",
	CUE_SLIDE: &"GroundCreak",
	CUE_BUMP: &"HitBlocked",
	CUE_STRAIN: &"WebStruggle",
}
const SLIDE_PITCH := 0.6
const STRAIN_CUE_MS := 520.0
## The latch: the slime stretches toward the block and leans this far into it.
const LATCH_STRETCH := 0.06
const LATCH_LEAN_PX := 3.0
## The slime stands this far off the block's footprint while it grabs.
const STAND_GAP_PX := 3.0
## How a held walk key must point along the grab axis to count as a push or a pull.
const AXIS_DOT := 0.5
## Off its place beside an idle block, the slime slides back this fast at most.
const SETTLE_SPEED := 90.0
## The strain line rises this far over the slime's centre.
const LINE_RISE := 46.0

var _player: Node
var _body: CharacterBody2D
var _block: Node2D
## From the slime to the block (a cardinal unit vector).
var _facing: Vector2 = Vector2.ZERO
var _active: bool = false
var _push_since_ms: float = -1.0
var _push_dir: Vector2 = Vector2.ZERO
var _bumped_dir: Vector2 = Vector2.ZERO
var _moving: bool = false
var _move_dir: Vector2 = Vector2.ZERO
var _strain_line_ms: float = -INF
var _strain_cue_ms: float = -INF
var _straining: bool = false


static func setting(key: String, fallback: float) -> float:
	var constants := Services.constants()
	return float(constants.value(CONSTANTS + "." + key, fallback)) if constants != null else fallback


func is_active() -> bool:
	return _active


func block() -> Node2D:
	return _block if _active else null


## From the slime to the grabbed block.
func facing() -> Vector2:
	return _facing


## True while the plain slime strains at the block.
func is_straining() -> bool:
	return _active and _straining


## True while a cell move runs.
func is_moving() -> bool:
	return _active and _moving


## The heavy block the slime faces and touches, or null.
static func block_in_reach(body: CharacterBody2D, facing_dir: Vector2) -> Node2D:
	if body == null or not body.is_inside_tree():
		return null
	var f := cardinal(facing_dir)
	var reach := setting("grabReachPx", 14.0)
	var mine := body_rect(body)
	var best: Node2D = null
	var best_gap := INF
	for node: Node in body.get_tree().get_nodes_in_group(BLOCK_GROUP):
		var candidate := node as Node2D
		if candidate == null or not candidate.has_method(&"footprint"):
			continue
		var theirs: Rect2 = candidate.call(&"footprint")
		var gap: float
		var overlap: float
		if f.x != 0.0:
			gap = theirs.position.x - mine.end.x if f.x > 0.0 else mine.position.x - theirs.end.x
			overlap = minf(mine.end.y, theirs.end.y) - maxf(mine.position.y, theirs.position.y)
		else:
			gap = theirs.position.y - mine.end.y if f.y > 0.0 else mine.position.y - theirs.end.y
			overlap = minf(mine.end.x, theirs.end.x) - maxf(mine.position.x, theirs.position.x)
		if gap < -6.0 or gap > reach or overlap < minf(12.0, mine.size.x * 0.4):
			continue
		if gap < best_gap:
			best_gap = gap
			best = candidate
	return best


## The slime's collision rect in world space (its BodyShape, a rectangle).
static func body_rect(body: CharacterBody2D) -> Rect2:
	var shape_node := body.get_node_or_null(^"BodyShape") as CollisionShape2D
	var rect := shape_node.shape as RectangleShape2D if shape_node != null else null
	var size := rect.size if rect != null else Vector2(30.0, 26.0)
	var centre := body.global_position + (shape_node.position if shape_node != null else Vector2(0.0, -13.0))
	return Rect2(centre - size / 2.0, size)


static func cardinal(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return Vector2.DOWN
	if absf(direction.x) > absf(direction.y):
		return Vector2(signf(direction.x), 0.0)
	return Vector2(0.0, signf(direction.y))


## Latches on to the block in front, if one is in reach. True when the grab started.
func try_begin(player: Node, body: CharacterBody2D, facing_dir: Vector2) -> bool:
	var found := block_in_reach(body, facing_dir)
	if found == null:
		return false
	_player = player
	_body = body
	_block = found
	_facing = cardinal(facing_dir)
	_active = true
	_moving = false
	_push_since_ms = -1.0
	_push_dir = Vector2.ZERO
	_bumped_dir = Vector2.ZERO
	_straining = false
	_player.call(&"face", _facing)
	_latch_look(0.0)
	_cue(CUE_GRAB)
	return true


## Lets go (the look comes back; a running move of the block finishes on its own).
func release() -> void:
	if not _active:
		return
	_active = false
	_moving = false
	_straining = false
	if _body != null and is_instance_valid(_body):
		_body.velocity = Vector2.ZERO
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")
	_block = null


## One physics step of the grab: `held` is the interact key, `direction` the walk keys. Sets the
## slime's velocity. Returns true while the slime walks (a move under way).
func step(now: float, delta: float, held: bool, direction: Vector2) -> bool:
	if not _active:
		return false
	if _block == null or not is_instance_valid(_block) or _body == null or not is_instance_valid(_body):
		release()
		return false
	if _moving and not bool(_block.call(&"is_moving")):
		_moving = false
	if not held and not _moving:
		release()
		return false
	_player.call(&"face", _facing)
	if _moving:
		_follow(delta)
		_latch_look(0.0)
		return true
	var along := 0.0
	if direction != Vector2.ZERO:
		along = direction.normalized().dot(_facing)
	var want := Vector2.ZERO
	if along > AXIS_DOT:
		want = _facing
	elif along < -AXIS_DOT:
		want = -_facing
	if want == Vector2.ZERO or want != _push_dir:
		_push_dir = want
		_push_since_ms = now if want != Vector2.ZERO else -1.0
		_bumped_dir = Vector2.ZERO
		_straining = false
	_settle(delta)
	if want == Vector2.ZERO or now - _push_since_ms < setting("startDelayMs", 180.0):
		_latch_look(0.0)
		return false
	if not bool(_player.call(&"presses_plates")):
		_strain(now)
		return false
	_straining = false
	_latch_look(0.0)
	if _try_move(want):
		_follow(delta)
		return true
	if _bumped_dir != want:
		_bumped_dir = want
		_block.call(&"bump")
		_cue(CUE_BUMP)
	return false


## Starts a cell move of the block (and the slime with it) along `direction`, if both have room.
func _try_move(direction: Vector2) -> bool:
	var ignore: Array[RID] = [_body.get_rid()]
	if direction == -_facing:
		var cell := float(_block.call(&"cell_px"))
		if _body.test_move(_body.global_transform, direction * cell):
			return false
	if not bool(_block.call(&"begin_move", direction, ignore)):
		return false
	_moving = true
	_move_dir = direction
	_cue(CUE_SLIDE, {"pitch": SLIDE_PITCH})
	return true


## Where the slime's feet stand beside the block at `block_at` (square on its side, a small gap).
func _stand_point(block_at: Vector2) -> Vector2:
	var theirs: Rect2 = _block.call(&"footprint")
	var mine := body_rect(_body)
	var half_b := theirs.size / 2.0
	var half_p := mine.size / 2.0
	var to_centre := (mine.position + half_p) - _body.global_position
	var distance := (half_b.x + half_p.x) if _facing.x != 0.0 else (half_b.y + half_p.y)
	var body_centre := block_at - _facing * (distance + STAND_GAP_PX)
	return body_centre - to_centre


## During a move: keep the slime at its place beside the block's next position.
func _follow(delta: float) -> void:
	var cell := float(_block.call(&"cell_px"))
	var speed := cell / maxf(0.001, float(_block.call(&"move_ms")) / 1000.0)
	var remaining := float(_block.call(&"move_remaining_ms")) / 1000.0
	var next_block := _block.global_position + _move_dir * minf(speed * delta, speed * remaining)
	var target := _stand_point(next_block)
	_body.velocity = (target - _body.global_position) / maxf(delta, 0.0001)
	_body.velocity = _body.velocity.limit_length(speed * 2.0)


## While the block stands: slide to the place beside it (squares the slime up after the grab).
func _settle(delta: float) -> void:
	var offset := _stand_point(_block.global_position) - _body.global_position
	if offset.length() < 0.5:
		_body.velocity = Vector2.ZERO
		return
	_body.velocity = (offset / maxf(delta, 0.0001)).limit_length(SETTLE_SPEED)


## The plain slime pulls in vain: it wobbles, the block trembles, the strain cue and the line.
func _strain(now: float) -> void:
	_straining = true
	_block.call(&"strain")
	var hz := setting("strainHz", 7.0)
	_latch_look(sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * hz) * setting("strainWobble", 0.06))
	if now - _strain_cue_ms >= STRAIN_CUE_MS:
		_strain_cue_ms = now
		_cue(CUE_STRAIN)
	if now - _strain_line_ms >= setting("strainLineMs", 2400.0):
		_strain_line_ms = now
		var feel := Services.feel()
		if feel != null:
			var centre: Vector2 = _player.call(&"get_centre")
			feel.floating_text(centre - Vector2(0.0, LINE_RISE), STRAIN_LINE, &"white", false)


## The latch look: stretched toward the block, leaning into it; `wobble` adds the strain's shake.
func _latch_look(wobble: float) -> void:
	var stretch := LATCH_STRETCH + wobble
	var scale := Vector2(1.0 + stretch, 1.0 - stretch) if _facing.x != 0.0 else Vector2(1.0 - stretch, 1.0 + stretch)
	_player.call(&"set_effect_scale", scale)
	_player.call(&"set_effect_offset", _facing * LATCH_LEAN_PX)


func _cue(cue: StringName, payload: Variant = null) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var root: Node = feel.global_audio()
	var play := cue
	if root == null or root.find_child(String(cue), true, false) == null:
		play = PLACEHOLDER_CUES.get(cue, cue)
	feel.audio_cue(play, payload)

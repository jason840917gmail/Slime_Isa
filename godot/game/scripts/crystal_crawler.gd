extends "res://game/enemy/patterned_enemy.gd"
class_name CrystalCrawlerScript
## Scene script `game.crystal-crawler` (the bestiary's row 25, a wall crawler; docs/godot/BESTIARY.md
## "Crystal Crawler"): a centipede with crystal spikes on its back that crawls round and round a
## pillar on a fixed loop.
##
## - **The loop:** the rectangle `loop_size` whose top edge's middle is its post (the pillar stands
##   in the middle of it), corner to corner at `crawlSpeed`, `clockwise` or not. It crawls on the
##   pillar's wall: its body is not solid and nothing stops it (layer and mask 0); the art turns with
##   its way (the sheet is a view from above, head to the right).
## - **Crawl:** every hit on its back clinks (the spikes; shielded).
## - **Turn** (`turnMs`, at every corner; the tell is the twist): it twists round the corner on its
##   side, its soft pale belly showing: open, the Spear's moment (24 health: two jabs; a stun holds
##   the turn's clock, so a chain finishes it).
## - **Spikes:** touching it hurts (`contactDamage`, `knockbackStrength`, within `contactReachPx`,
##   at most every `contactCooldownMs`), crawling or turning, while the slime is in its pen.
## - **The Bow's hook** (`on_arrow_hit`): an arrow from the side (across its way, `bowSideShare`) or
##   in a turn kills it; one along its back clinks. The Feral skin will meet it on the wall later.
##
## Owner: enemy builder.

const PHASE_CRAWL := "crawl"
const PHASE_TURN := "turn"
const FRAME_CRAWL_A := 0
const FRAME_CRAWL_B := 1
const FRAME_TURN := 2
const BOW_TARGETS := &"bow_targets"
const CUE_TURN := &"CrawlerTurn"
const CUE_CLINK := &"HitBlocked"
## Presentation: the legs' step, the art's lift off the ground (its middle over its feet).
const STEP_MS := 120.0
const LIFT_PX := 12.0

## The loop's size (px): its middle runs round this rectangle; the post is its top edge's middle.
@export var loop_size: Vector2 = Vector2(116.0, 88.0)
## The way round (true: right along the top, down the right side, ...).
@export var clockwise: bool = true

## The corner it heads for (0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left).
var _corner: int = 1
var _loop_centre: Vector2 = Vector2.INF
var _heading: float = 0.0
var _turn_from: float = 0.0
var _turn_to: float = 0.0
var _last_ms: float = -1.0


func _ready() -> void:
	super()
	add_to_group(BOW_TARGETS)
	_transition(PHASE_CRAWL, Services.now_ms())
	set_frame(FRAME_CRAWL_A)


## The way it crawls now (a unit vector).
func get_travel() -> Vector2:
	return Vector2.RIGHT.rotated(_heading)


## The loop's middle (the pillar's), Vector2.INF before its first step.
func get_loop_centre() -> Vector2:
	return _loop_centre


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	_last_ms = now
	if _loop_centre == Vector2.INF:
		_loop_centre = _home + Vector2(0.0, loop_size.y * 0.5)
		_corner = 1 if clockwise else 0
		_heading = 0.0 if clockwise else PI
	match _phase:
		PHASE_CRAWL:
			var goal := _corner_point(_corner)
			var speed := pattern("crawlSpeed", 60.0)
			var offset := goal - get_centre()
			if offset.length() <= maxf(1.0, speed * delta):
				body.velocity = offset / maxf(delta, 0.0001)
				_begin_turn(now)
			else:
				body.velocity = offset.normalized() * speed
				_heading = offset.angle()
				set_frame(FRAME_CRAWL_A if int(now / STEP_MS) % 2 == 0 else FRAME_CRAWL_B)
			set_look(LIFT_PX, Vector2.ONE, _heading)
		PHASE_TURN:
			body.velocity = Vector2.ZERO
			var t := clampf(_elapsed(now) / maxf(1.0, pattern("turnMs", 700.0)), 0.0, 1.0)
			_heading = lerp_angle(_turn_from, _turn_to, t)
			set_look(LIFT_PX, Vector2.ONE, _heading)
			if t >= 1.0:
				_heading = _turn_to
				_transition(PHASE_CRAWL, now)
				set_frame(FRAME_CRAWL_A)
	if engaged:
		_contact(target, _attribute("contactDamage"), _attribute("knockbackStrength"), pattern("contactReachPx", 26.0))


func _begin_turn(now: float) -> void:
	var next := posmod(_corner + (1 if clockwise else -1), 4)
	_turn_from = _heading
	_turn_to = (_corner_point(next) - _corner_point(_corner)).angle()
	_corner = next
	_transition(PHASE_TURN, now)
	set_frame(FRAME_TURN)
	_cue(CUE_TURN)


func _corner_point(index: int) -> Vector2:
	var half := loop_size * 0.5
	match index:
		0:
			return _loop_centre + Vector2(-half.x, -half.y)
		1:
			return _loop_centre + Vector2(half.x, -half.y)
		2:
			return _loop_centre + Vector2(half.x, half.y)
		_:
			return _loop_centre + Vector2(-half.x, half.y)


## The Bow's hook (the coming Bow, Chapter 3): an arrow across its way, or in a turn, kills it. `hit`
## may carry the arrow's `direction` (or `knock`). True when it died.
func on_arrow_hit(hit: Dictionary) -> bool:
	if is_defeated():
		return false
	var along: Variant = hit.get("direction", hit.get("knock", Vector2.ZERO))
	var side := _phase == PHASE_TURN
	if not side and along is Vector2 and (along as Vector2) != Vector2.ZERO:
		side = absf((along as Vector2).normalized().dot(get_travel())) < pattern("bowSideShare", 0.5)
	if not side:
		_cue(CUE_CLINK)
		return false
	_defeat()
	return true


## Its spiked back clinks; only its belly in a turn is open.
func _shields(_request: Dictionary) -> bool:
	return _phase != PHASE_TURN


## On its track: a knockback does not move it, and a stun holds the turn's clock.
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(now: float, _delta: float) -> void:
	body.velocity = Vector2.ZERO
	if _last_ms >= 0.0 and _phase == PHASE_TURN:
		_phase_started_at += now - _last_ms
	_last_ms = now


func _defeat() -> void:
	if is_defeated():
		return
	super()
	set_look(LIFT_PX * 0.5, Vector2.ONE, 0.0)

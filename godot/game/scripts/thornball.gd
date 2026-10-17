extends "res://game/enemy/patterned_enemy.gd"
class_name ThornballScript
## Scene script `game.thornball` (the bestiary's row 19, a charger; docs/godot/BESTIARY.md
## "Thornball"): a grumpy hedgehog that curls into a spiked ball and shoots across the ground.
##
## - **Idle:** it faces the slime; while the slime is away it walks home at `homeSpeed`.
## - **Curl** (the tell, `curlMs`): once it sees the slime (a clear line, `rollCooldownMs` after
##   its last roll) it curls up, quills bristling, and shivers.
## - **Roll:** a straight line at the slime's centre at `rollSpeed`, spinning. Its spikes shrug off
##   every hit (a clink), except a Goo Bomb's blast. It bounces off whatever stops it (walls, the
##   pen's fence, the slime: the slime within `rollHitPx` takes `rollDamage` with
##   `rollKnockback`); at the `bounces`th bounce it slows to a stop over `slowMs` and flops onto
##   its back. `rollMaxMs` at most.
## - **Dizzy** (`dizzyMs`): belly up, swaying: every hit there deals `dizzyDamageTaken` times its
##   damage (old-style hits; rework hits: the profile's `states.dizzy`).
## - **Cower:** a Goo Bomb resting within `bombFearPx` of it while it stands or curls: it curls into
##   a tight ball and holds still (spikes out: hits clink) until the bomb is gone.
## - **Right tool:** a Goo Bomb's blast (tag `blast`) flips it onto its back at once, rolling,
##   cowering or not, dizzy for `blastDizzyMs`; then a jab finishes it. Without a bomb: Roll aside,
##   let it bounce itself out, and Spear it while it is dizzy.
##
## Owner: enemy builder.

const PHASE_IDLE := "idle"
const PHASE_CURL := "curl"
const PHASE_ROLL := "roll"
const PHASE_SLOW := "slow"
const PHASE_DIZZY := "dizzy"
const PHASE_COWER := "cower"
const FRAME_STAND := 0
const FRAME_CURL := 1
const FRAME_BALL := 2
const FRAME_FLIPPED := 3
const BLAST_TAG := "blast"
## The Goo Bombs' group (game/scripts/goo_bomb.gd).
const BOMBS_GROUP := &"goo_bombs"
const CUE_CURL := &"SlamWindup"
const CUE_ROLL := &"RollLaunch"
const CUE_BOUNCE := &"HitBlocked"
const CUE_FLOP := &"RollBonk"
const CUE_GET_UP := &"Land"
const DUST := &"dodge-dust"
const SPARKS := &"hit-spark"
## A blocked roll: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.85
## Presentation: the curl's shiver, the ball's spin about its middle (the ball art's radius over
## the feet in pose px), the dust trail, the dizzy sway and the flop's bounce.
const CURL_SHIVER_PX := 1.4
const CURL_SHIVER_MS := 26.0
const BALL_RADIUS_PX := 28.0
const TRAIL_DUST_MS := 110.0
const WADDLE_RAD := 0.05
const WADDLE_MS := 110.0
const DIZZY_SWAY_RAD := 0.07
const DIZZY_SWAY_MS := 180.0
const FLOP_BOUNCE_PX := 12.0
const FLOP_BOUNCE_MS := 240.0

var _dir: Vector2 = Vector2.RIGHT
var _asked: Vector2 = Vector2.ZERO
var _ready_at: float = 0.0
var _dust_at: float = 0.0
var _bounces: int = 0
var _spin: float = 0.0
var _dizzy_ms: float = 0.0


func _ready() -> void:
	super()
	_idle(Services.now_ms())


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	if (_phase == PHASE_IDLE or _phase == PHASE_CURL) and _bomb_near():
		_cower(now)
	match _phase:
		PHASE_COWER:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2(1.05, 0.95))
			if pose != null:
				pose.position.x = sin(now / CURL_SHIVER_MS) * CURL_SHIVER_PX
			if not _bomb_near():
				_idle(now)
				_ready_at = now + pattern("rollCooldownMs", 900.0)
		PHASE_IDLE:
			if engaged:
				body.velocity = Vector2.ZERO
				face_x(slime.x - centre.x)
				set_look(0.0)
				if now >= _ready_at and _sees(target):
					_transition(PHASE_CURL, now)
					set_frame(FRAME_CURL)
					_cue(CUE_CURL)
			else:
				body.velocity = _velocity_toward(_home, pattern("homeSpeed", 45.0), delta)
				face_x(body.velocity.x)
				var walking := body.velocity.length() > WALK_SPEED_THRESHOLD
				set_look(0.0, Vector2.ONE, sin(now / WADDLE_MS) * WADDLE_RAD if walking else 0.0)
		PHASE_CURL:
			body.velocity = Vector2.ZERO
			face_x(slime.x - centre.x)
			var t := clampf(elapsed / maxf(1.0, pattern("curlMs", 700.0)), 0.0, 1.0)
			set_look(0.0, Vector2(1.0 + 0.06 * t, 1.0 - 0.06 * t))
			if pose != null:
				pose.position.x = sin(now / CURL_SHIVER_MS) * CURL_SHIVER_PX * t
			if not engaged:
				_idle(now)
			elif t >= 1.0:
				_dir = (slime - centre).normalized() if slime != centre else Vector2.RIGHT
				_bounces = 0
				_asked = Vector2.ZERO
				_transition(PHASE_ROLL, now)
				set_frame(FRAME_BALL)
				_cue(CUE_ROLL)
				_puff(DUST, feet() - _dir * 12.0)
		PHASE_ROLL:
			if engaged:
				_contact(target, pattern("rollDamage", 22.0), pattern("rollKnockback", 300.0), pattern("rollHitPx", 40.0))
			if _asked != Vector2.ZERO and (_fresh_hit_normal() != Vector2.ZERO \
					or body.velocity.length() < _asked.length() * BLOCKED_SHARE):
				_bounce(now)
				if _phase != PHASE_ROLL:
					return
			if elapsed >= pattern("rollMaxMs", 4000.0):
				_slow_down(now)
				return
			_asked = _dir * pattern("rollSpeed", 280.0)
			body.velocity = _asked
			_roll_look(delta, _asked.length())
			_trail(now)
		PHASE_SLOW:
			var t := clampf(elapsed / maxf(1.0, pattern("slowMs", 500.0)), 0.0, 1.0)
			_asked = _dir * pattern("rollSpeed", 280.0) * 0.45 * (1.0 - t)
			if body.velocity.length() < _asked.length() * BLOCKED_SHARE and elapsed > 0.0:
				_dir = -_dir
			body.velocity = _asked
			_roll_look(delta, _asked.length())
			if t >= 1.0:
				_flip(now, pattern("dizzyMs", 2400.0))
		PHASE_DIZZY:
			body.velocity = Vector2.ZERO
			var bounce := clampf(elapsed / FLOP_BOUNCE_MS, 0.0, 1.0)
			set_look(sin(bounce * PI) * FLOP_BOUNCE_PX, Vector2.ONE, sin(elapsed / DIZZY_SWAY_MS) * DIZZY_SWAY_RAD)
			if elapsed >= _dizzy_ms:
				_cue(CUE_GET_UP)
				_idle(now)
				_ready_at = now + pattern("rollCooldownMs", 900.0)


## A Goo Bomb lies near: it curls into a tight ball and holds still, as a hedgehog does.
func _cower(now: float) -> void:
	_transition(PHASE_COWER, now)
	set_frame(FRAME_BALL)
	set_look(0.0)
	_asked = Vector2.ZERO
	_cue(CUE_CURL)


## A Goo Bomb resting on the ground within `bombFearPx` of its feet.
func _bomb_near() -> bool:
	var reach := pattern("bombFearPx", 120.0)
	for node: Node in get_tree().get_nodes_in_group(BOMBS_GROUP):
		if not is_instance_valid(node) or not node.has_method(&"ground_point") or not node.has_method(&"can_take"):
			continue
		if bool(node.call(&"can_take")) and (node.call(&"ground_point") as Vector2).distance_to(feet()) <= reach:
			return true
	return false


func _idle(now: float) -> void:
	_transition(PHASE_IDLE, now)
	set_frame(FRAME_STAND)
	set_look(0.0)
	_asked = Vector2.ZERO


## Off whatever stopped it, as a ball off a cushion; at the `bounces`th bounce it slows down.
func _bounce(now: float) -> void:
	var normal := _hit_normal()
	_dir = _dir.bounce(normal).normalized() if normal != Vector2.ZERO else -_dir
	_bounces += 1
	_asked = Vector2.ZERO
	_cue(CUE_BOUNCE)
	_puff(SPARKS, get_centre() - normal * 16.0)
	if _bounces >= int(pattern("bounces", 3.0)):
		_slow_down(now)


func _slow_down(now: float) -> void:
	_transition(PHASE_SLOW, now)
	_asked = Vector2.ZERO


## Onto its back, dizzy for `ms`.
func _flip(now: float, ms: float) -> void:
	_dizzy_ms = ms
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	_transition(PHASE_DIZZY, now)
	set_frame(FRAME_FLIPPED)
	set_look(0.0)
	_cue(CUE_FLOP)
	_puff(DUST, feet())
	_ready_at = now + ms + pattern("rollCooldownMs", 900.0)


## The normal of the last thing the mover hit (ArcadeMover's record, rework mode), else the axis
## the mover cut.
func _hit_normal() -> Vector2:
	var fresh := _fresh_hit_normal()
	if fresh != Vector2.ZERO:
		return fresh
	var cut := _asked - body.velocity
	if absf(cut.x) >= absf(cut.y):
		return Vector2(-signf(_asked.x), 0.0)
	return Vector2(0.0, -signf(_asked.y))


## The normal of what the last move hit (ArcadeMover's record of the previous physics frame, in
## the rework mode), else zero.
func _fresh_hit_normal() -> Vector2:
	if not body.has_meta(ArcadeMover.COLLISION_META):
		return Vector2.ZERO
	var record: Variant = body.get_meta(ArcadeMover.COLLISION_META)
	if not record is Dictionary or int((record as Dictionary).get("frame", -10)) < Engine.get_physics_frames() - 1:
		return Vector2.ZERO
	var normal: Variant = (record as Dictionary).get("normal", Vector2.ZERO)
	return normal if normal is Vector2 else Vector2.ZERO


## The ball spins about its middle as it rolls.
func _roll_look(delta: float, speed: float) -> void:
	_spin = wrapf(_spin + speed * delta / BALL_RADIUS_PX * (1.0 if _dir.x >= 0.0 else -1.0), -PI, PI)
	set_look(0.0, Vector2.ONE, _spin)
	if pose != null:
		var middle := Vector2(0.0, -BALL_RADIUS_PX)
		pose.position += middle - middle.rotated(_spin)


func _trail(now: float) -> void:
	if now >= _dust_at:
		_dust_at = now + TRAIL_DUST_MS
		_puff(DUST, feet() - _dir * 14.0)


## A clear line to the slime (walls block it, water does not).
func _sees(target: Dictionary) -> bool:
	var world := Services.world()
	if world == null:
		return true
	var exclude: Array[RID] = [body.get_rid()]
	var player_body := target.get("body") as CollisionObject2D
	if player_body != null:
		exclude.append(player_body.get_rid())
	return world.line_of_sight(get_centre(), target.get("centre", get_centre()), exclude)


## A stun in the curl calls the roll off.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_CURL:
		_idle(now)
		_ready_at = get_hit_stun_until() + pattern("rollCooldownMs", 900.0)


func is_dizzy() -> bool:
	return _phase == PHASE_DIZZY


func bounce_count() -> int:
	return _bounces


## Its spikes refuse every hit while it rolls, but a Goo Bomb's blast.
func _shields(request: Dictionary) -> bool:
	return (_phase == PHASE_ROLL or _phase == PHASE_SLOW or _phase == PHASE_COWER) and not has_tag(request, BLAST_TAG)


## A blast flips it onto its back at once.
func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if not is_defeated() and has_tag(commit.get("request", {}), BLAST_TAG) and _phase != PHASE_DIZZY:
		_flip(Services.now_ms(), pattern("blastDizzyMs", 3000.0))


## Old-style hits on its belly: `dizzyDamageTaken` times; a rework hit gets it from the reaction
## profile's `states.dizzy.damageTaken`.
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	if _phase == PHASE_DIZZY and not ReworkMode.is_rework_request(input.get("request", {})):
		damage *= pattern("dizzyDamageTaken", 2.0)
	return damage


func _defeat() -> void:
	if is_defeated():
		return
	_asked = Vector2.ZERO
	super()

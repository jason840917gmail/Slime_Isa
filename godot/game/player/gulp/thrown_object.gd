extends Node2D
## Something the slime throws with Q (owner, 2026-10-08; GAME_GUIDELINES "Signature Mechanic:
## Gulp"): a liftable (a pot, a rock, a pumpkin, ... game/scripts/liftable.gd) flies from the
## slime's mouth along the aim at `gulp.throwSpeed` for up to `gulp.throwRangePx`, falling in a low
## arc, and breaks at the first hurtbox it meets, at a wall, or where it lands. The break strikes
## every hurtbox in `gulp.throwHitRadiusPx` for `gulp.throwDamage` times its material's
## `gulp.throwDamageByMaterial` (AbilityWorld.strike_area, as the slam does) with
## `gulp.throwKnockback`. Essences are never thrown: the mouth spits them out whole (owner,
## 2026-10-09; mouth.gd).
##
## How it breaks follows its material (owner, 2026-10-09): a liftable bursts into chunks of its own
## picture (break_burst.gd) with that material's particles and sound (BREAK_PARTICLES, BREAK_CUES:
## a pot shatters, a crate splinters, a kettle clangs, a pumpkin splats).
##
## Its feel (gulp_feel.gd, `gulp.feel`): a whoosh streak trails it for its first `throw.streakMs`, and
## the landing puffs dust on the ground and nudges the camera for a heavy material (`land`).
##
## The node sits on the ground point under the flying thing (its shadow is there); the look rides
## above it. Gameplay runs on the physics step, so it pauses with the tree.
##
## Body-shapes rework (docs/godot/BODY_SHAPES.md "The hit"; combat-feel plan section 3; only while
## ReworkMode is on): the break sends each hurtbox in reach one request that carries the contract's
## `hit` (`rework_hit`: class `gulp.throwHit.class` ("thrown": tier 2, never a hold), tag
## `thrown`, the knock along the throw, launch speed `gulp.throwKnockback`, `knock_px`
## from `gulp.throwHit.knockbackPx`) and the `impact` effect instead of the old knockback, so the enemy's
## reaction profile decides what it does (a pot dazes a light enemy, and since it dealt damage the
## daze slides it back `knockbackPx`: EnemyReactions; owner, 2026-11-01). The throw's feel plays once (`gulp.throwHit` through HitJuice.swing_spec and
## GameFeel.play_hit), each target's number at the target; a clink (an immune target) plays
## `combat.chain.clink.hitStopMs` and HitBlocked.
##
## Throw combat (the experiment, docs/godot/THROW_COMBAT.md; only while ThrowMode is on): the thing's
## weight (`gulp.throwCombat.weights`) scales its speed, reach, hit radius and damage
## (`gulp.throwCombat.throwDamage` x material x weight) and picks the hit's class (`thrown`,
## `thrown-medium`, `thrown-heavy`); its effect (`effect_of`: its kind's, else its material's) can
## change the class (freeze: a long stun; sleep: asleep until a damaging hit, even on an invulnerable
## enemy on the ground) or slow the enemy (stick, honey: half pace for `slowMs`; `_show_effect`),
## drawn on the enemy by throw_status_look.gd,
## widen the break (shatter) or fly on through enemies (pierce: it strikes up to `pierceTargets`
## enemies, each once, and breaks on the last, a wall or its end).
##
## What it meets and strikes (rework and throw combat; owner: "nothing should cross walls"): only
## hurtboxes on the height level it was thrown from (the slime's) with no wall between it and them
## (AbilityWorld.hurtboxes_in_reach), each once (`_targets`); so it flies over a lower level's enemy
## and its break never reaches round a wall or up or down a cliff.
##
## The new throw feel (game/throw/throw_feel.gd, `gulp.throwFeel`; owner, 2026-11-16: his Zelda
## reference, "a strong hit and the monster got pushed back with nice effects and sounds"; only while
## ThrowFeel is on, decided once at the launch): the thing flies bigger (`lookPx.<weight>`, its
## shadow and a longer streak with it), faster and further (`throwSpeed`, `throwRangePx`) and hits
## for `throwFeel.throwDamage`. It meets a hurtbox as before (`gulp.throwHitRadiusPx`: no throw
## misses that hit before), but then flies ON until it touches the body (`contactPx` from the
## hurtbox's shape, at most `contactFlightPx` more, or once it is past it: `_fly_to_contact`), so it
## breaks ON the enemy. The blow shows at the contact point, between the thing and the enemy's
## middle (`_contact_point`): the impact star about as wide as the enemy, its ring and streaks
## (game/throw/throw_impact.gd), the sparks along the throw, the weight's hit-stop (+`killStopMs` on
## a kill, up to `hitStopCapMs`), trauma and kick (`hit.<weight>`) and the big yellow number. The
## hit's sound is the thing's own (owner, 2026-11-16: "the hit sound depends on the object that
## hits ... that will give identity to each type of material"): its material's break cue on the hit
## frame (`_play_break_cue`: lower for a heavier thing, `breakPitch.<weight>`; a piercing thing that
## strikes and flies on plays it too), with no impact cue over it, and `cues.kill` (ThrowKill) on top
## when the blow kills, at the pop streak's pitch. The
## shards then fly on along the throw (`shards.hit`: break_burst.gd waits through the freeze, so the
## thing shows whole at the blow meanwhile). A throw that hurt nothing (the ground, a wall, a clink,
## a sleep throw) keeps a smaller, duller break (`shards.miss`, `shards.wall`: off a wall the shards
## fall back) and the old feel numbers, so a hit reads differently from a miss (its break cue plays
## `missVolumeDb` quieter). The hit carries the contract's fields for the enemies' reactions
## (`rework_hit`).
##
## The rebound prototype (ThrowFeel.rebound_on, `gulp.throwFeel.rebound`; owner, 2026-11-16: each
## material its identity): a **sturdy** thing (stone, metal, bone: `rebound.uses.<material>` hits in
## all, carried as `held.uses`) does not shatter while it has a use left. A blow that hurts spends one
## use, shows as any blow (the star, its material's cue: a knock or a clang, a few chips) and the
## thing bounces off, back along the throw toward where it was thrown from (`_rebound`: it lands
## `returnShortPx` short of there, at least `reboundMinPx` and at most `reboundMaxPx` back, over
## `reboundMs`, rising `arcPx`: game/throw/throw_rebound.gd) and lies there as the same thing again.
## A miss spends no use: it hops `missReboundPx` on from where it came down, or back off a wall, and
## lies there. A piercing sturdy thing flies on through its targets (a use each) and lands at the end
## of its flight. The landing is only where a liftable fits (ThrowAmmo.fits, a clear line to it, not
## on the slime), trying shorter spots back along the path; with none it shatters as before, and it
## shatters on its last use. A **hot** throw (`held.hot`: the mouth caught it in the air, mouth.gd
## `snap_catch`) deals x `hotDamageScale`, flies x `hotSpeedScale` and glows (throw_glow.gd).
##
## The enemy-ammo prototype (game/throw/gulpable_enemy.gd; `held.kind` "enemy": a helpless enemy
## the mouth carried): it flies as the enemy's own picture and strikes as any throw, for
## GulpableEnemy.throw_damage with the hit class GulpableEnemy.throw_hit_class and the medium hit
## numbers; it has no effect of its own, is never sturdy and never hot. Where its flight ends the
## enemy is put down (GulpableEnemy.land, which deals its own landing hit): no shards, no break cue.
##
## The Dung Roller's ball (game/enemy/dung_ball.gd; `held.kind` "dung-ball", its picture a frame of
## the beetle's sheet): a light soft thing that breaks only on a blow that struck something. A throw
## that hurt nothing (the ground, a wall, a clink) lays it whole where it came down (`_lay_ball`), and
## its beetle goes for it.
##
## Off a jelly (docs/godot/BESTIARY.md "39. Jelly Bouncer"; owner, 2026-11-22): a thing (no carried
## enemy, no Goo Bomb) that touches a bouncer (an enemy in BouncedThrow.BOUNCERS_GROUP whose
## `bounces_throw()` says yes) does not strike or break: it bounces back at the slime whole
## (game/throw/bounced_throw.gd: it hurts the slime it meets, and the mouth can catch it). A piercing
## thing stops at him too.
##
## Owner: abilities (the rework hit: mouth; the new feel: throw combat's sender).

const Services := preload("res://game/shared/services.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")

## The rework hit's tags (BODY_SHAPES.md "The hit") and its class when `gulp.throwHit` has none.
const REWORK_TAGS: Array[String] = ["thrown"]
const REWORK_FALLBACK_CLASS := "thrown"
const DAMAGE_TYPES: Array[String] = ["physical"]
const CUE_CLINK := &"HitBlocked"
## A cue payload's pitch multiplier (game/feel/game_feel.gd CUE_PITCH_KEY).
const CUE_PITCH_KEY := "pitch"

const LOOK_SIZE_PX := 30.0
## The flight starts at the slime's mouth height and lands on the ground, with a small rise.
const START_HEIGHT_PX := 26.0
const ARC_PX := 14.0
const SPIN_PER_S := 9.0
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const SHADOW_SIZE := Vector2(12.0, 5.0)
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const GooBomb := preload("res://game/scripts/goo_bomb.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowStatusLook := preload("res://game/throw/throw_status_look.gd")
## The new throw feel: its switch and numbers, and the impact star.
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const ThrowImpact := preload("res://game/throw/throw_impact.gd")
## The rebound prototype: the bounce, where a thing may lie, the hot throw's glow.
const ThrowRebound := preload("res://game/throw/throw_rebound.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ThrowGlow := preload("res://game/throw/throw_glow.gd")
## The enemy-ammo prototype: a carried enemy as the thrown thing.
const GulpableEnemy := preload("res://game/throw/gulpable_enemy.gd")
## The Dung Roller's ball: it stays whole on a miss.
const DungBall := preload("res://game/enemy/dung_ball.gd")
## A thing that touches a Jelly Bouncer bounces back whole.
const BouncedThrow := preload("res://game/throw/bounced_throw.gd")
## A sturdy thing's blow knocks a few chips off it (the ParticleFx preset, its tint by material; a
## metal thing only sparks).
const CHIP_PRESET := &"stone-chip"
const CHIP_TINTS := {"stone": Color.WHITE, "bone": Color("#efe6cc")}
## A rebound to a shorter spot takes at least this share of its time.
const REBOUND_MIN_TIME_SHARE := 0.55
## A cue payload's volume offset in dB (game/runtime/sfx_player.gd PAYLOAD_VOLUME_DB).
const CUE_VOLUME_KEY := "volume_db"
## Why a throw broke (the new feel picks its shards by it): it touched a hurtbox, a wall stopped
## it, or it came down at the end of its flight.
enum Cause { TARGET, WALL, GROUND }
## The impact star is at least this share of the flying look across, and the contact point at most
## this share of the look from the thing's middle.
const STAR_MIN_LOOK_SHARE := 1.1
const CONTACT_LOOK_SHARE := 0.32
## Reaction verbs that stun: an effect's look shows while they last (a sleep's while it sleeps).
const STUN_VERBS: Array[String] = ["daze", "knockdown", "stagger", "hold", "sleep"]
## The throw's whoosh streak and the landing's dust and nudge (gulp_feel.gd, `gulp.feel`): the
## streak's colour, its lines this far apart (x their width), the side lines this share of the middle
## one's length, starting this share of the look's size behind its centre.
const GulpFeel := preload("res://game/player/gulp/gulp_feel.gd")
const STREAK_COLOR := Color(1.0, 1.0, 1.0, 0.78)
const STREAK_GAP := 1.7
const STREAK_SIDE_SHARE := 0.65
const STREAK_BEHIND_SHARE := 0.35

## The particles each material adds to its chunks ("essence": a thrown essence's goo).
const BREAK_PARTICLES := {
	"clay": [&"dodge-dust"],
	"glass": [&"hit-spark", &"loot-sparkle"],
	"wood": [&"dodge-dust"],
	"metal": [&"hit-spark"],
	"stone": [&"dodge-dust"],
	"soft": [&"slime-splash"],
	"ice": [&"hit-spark", &"loot-sparkle"],
	"snow": [&"dodge-dust"],
	"crystal": [&"hit-spark", &"loot-sparkle"],
	# A skull or a bone from the skeletons (game/enemy/bone_skull.gd, game/scripts/bone.gd).
	"bone": [&"dodge-dust"],
}
## The global cue each material breaks with (Sound Picker round 5; snow, crystal and bone their own
## since round 11); HitDull until a cue exists. `break_cue` resolves it.
const BREAK_CUES := {
	"clay": &"BreakClay",
	"glass": &"BreakGlass",
	"wood": &"BreakWood",
	"metal": &"BreakMetal",
	"stone": &"BreakStone",
	"soft": &"BreakSoft",
	"ice": &"BreakIce",
	"snow": &"BreakSnow",
	"crystal": &"BreakCrystal",
	"bone": &"BreakBone",
}
const CUE_FALLBACK := &"HitDull"
## The cue a material borrowed before it had its own: played while the global audio scene has no
## node of the new name yet.
const BREAK_CUE_BORROWED := {
	&"BreakSnow": &"BreakSoft",
	&"BreakCrystal": &"BreakGlass",
	&"BreakBone": &"BreakWood",
}

var _player: Node
var _held: Dictionary = {}
var _direction: Vector2 = Vector2.RIGHT
var _range_px: float = 0.0
var _speed: float = 0.0
var _travelled: float = 0.0
var _look: Node2D
var _done: bool = false
## The whoosh streak (GulpFeel.streak) and the flight's age (simulation ms, the physics steps).
var _streak: Dictionary = {}
var _age_ms: float = 0.0
## Throw combat: the thing's weight and effect, the enemies already struck (area instance id ->
## true) and how many more a piercing throw may strike before it breaks.
var _weight: String = ""
var _effect: String = ""
var _struck: Dictionary = {}
var _pierce_left: int = 0
## The height level it was thrown from (the slime's; AbilityWorld.ANY_LEVEL without elevation).
var _level: int = AbilityWorld.ANY_LEVEL
## The new throw feel plays for this throw (ThrowFeel.is_on at the launch; never for a Goo Bomb).
var _feel_on: bool = false
## The flying look's size (LOOK_SIZE_PX, or the feel's `lookPx.<weight>`).
var _look_px: float = LOOK_SIZE_PX
## The new feel: the hurtboxes it met and now flies on to touch, and how far it may still fly for
## that (px).
var _locked: Array[Area2D] = []
var _contact_left: float = 0.0
## The rebound prototype: it is sturdy (it bounces off while a use is left), the hits it has left,
## it is a hot throw, and where it was thrown from (the slime's feet then).
var _sturdy: bool = false
var _uses: int = 0
var _hot: bool = false
var _launch_feet: Vector2 = Vector2.ZERO
## The enemy-ammo prototype: the thing is a carried enemy.
var _enemy: bool = false


## Starts the throw of `held` ({"kind", "essence"}) from the ground point `feet` along `direction`.
func launch(player: Node, held: Dictionary, feet: Vector2, direction: Vector2) -> void:
	_player = player
	_held = held.duplicate()
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_feel_on = ThrowFeel.is_on() and GooBomb.from_held(_held) == null
	_enemy = GulpableEnemy.is_enemy(_held)
	_speed = ThrowFeel.throw_speed() if _feel_on else _constant("gulp.throwSpeed")
	_range_px = ThrowFeel.throw_range_px() if _feel_on else _constant("gulp.throwRangePx")
	_level = AbilityWorld.body_level(player.get(&"body") as Node2D) if player != null else AbilityWorld.ANY_LEVEL
	if ThrowMode.is_on() and GooBomb.from_held(_held) == null:
		_weight = ThrowMode.weight_of_held(_held)
		_effect = "" if _enemy else ThrowMode.effect_of(str(_held.get("kind", "")), HeldLook.material_of(_held))
		_speed *= ThrowMode.weight_number(_weight, "speedScale")
		_range_px *= ThrowMode.weight_number(_weight, "rangeScale")
		if _effect == ThrowMode.PIERCE:
			_pierce_left = int(ThrowMode.effect_row(_effect).get("pierceTargets", 1))
	global_position = feet
	_launch_feet = feet
	z_index = 5
	if _feel_on:
		_look_px = ThrowFeel.look_px(_weight, LOOK_SIZE_PX)
	_look = HeldLook.make(held, _look_px)
	add_child(_look)
	var material := HeldLook.material_of(_held)
	if _enemy:
		GulpableEnemy.thrown(_held, self)
	elif _feel_on and ThrowFeel.uses_of(material) > 0:
		_sturdy = true
		_uses = ThrowFeel.uses_left(_held, material)
		_look.modulate = ThrowFeel.wear_tint(_held, material)
		_hot = bool(_held.get("hot", false))
		if _hot:
			_speed *= ThrowFeel.rebound_number("hotSpeedScale", 1.0)
			ThrowGlow.attach(_look, _look_px * ThrowFeel.rebound_number("glowShare", 1.0))
	_place_look()
	_streak = ThrowFeel.streak() if _feel_on else GulpFeel.streak()
	# It starts here: without this its first frame is drawn on the way from the parent's origin (and
	# its look on the way up from the ground point).
	reset_physics_interpolation()
	queue_redraw()
	# A Goo Bomb flies with the throw, ticking (game/scripts/goo_bomb.gd `ride`).
	var bomb := GooBomb.from_held(_held)
	if bomb != null:
		bomb.call(&"ride", self)


func _physics_process(delta: float) -> void:
	if _done:
		return
	# The streak redraws while it shows, and once more to clear.
	if _age_ms <= float(_streak.get("ms", 0.0)):
		queue_redraw()
	_age_ms += delta * 1000.0
	var step := minf(_speed * delta, _range_px - _travelled)
	var from := _air_point()
	# The new feel: once it met a hurtbox it flies on only as far as the body (`_fly_to_contact`).
	var touching := false
	if not _locked.is_empty():
		var gap := _contact_gap(from)
		if gap <= step or _contact_left <= step:
			step = clampf(minf(gap, _contact_left), 0.0, step)
			touching = true
		_contact_left -= step
	var next_ground := global_position + _direction * step
	var next_air := next_ground - Vector2(0.0, _height(minf(1.0, (_travelled + step) / maxf(1.0, _range_px))))
	var reach := AbilityWorld.line_reach(from, next_air, _player_rids())
	if reach.distance_to(next_air) > AbilityWorld.CLEAR_LINE_SLACK_PX:
		_break(reach, Cause.WALL)
		return
	global_position = next_ground
	_travelled += step
	_place_look()
	if touching or (not _locked.is_empty() and _past_locked(next_air)):
		_break(next_air, Cause.TARGET)
		return
	var met := _targets(next_air, _constant("gulp.throwHitRadiusPx"))
	if not met.is_empty() and _locked.is_empty():
		# Throw combat: a piercing thing strikes what it meets and flies on, up to its count (but it
		# stops at a jelly, which sends it back: `_break`).
		if _pierce_left > 1 and _bouncer_among(met) == null:
			_pierce_left -= 1
			var passing := _strike_rework(next_air, _damage(), str(_held.get("kind", "")), met)
			# The new feel: its blow sounds as the thing itself (it does not break here).
			if bool(passing.get("hurt", false)):
				_play_break_cue(HeldLook.material_of(_held))
				# The rebound prototype: each enemy it goes through spends a use; the last one shatters it.
				if _sturdy:
					_uses -= 1
					if _uses <= 0:
						_done = true
						_finish(next_air, Cause.TARGET, passing, false)
						return
		elif _feel_on and _fly_to_contact(met, next_air):
			pass # It flies on to touch the body it met.
		else:
			_break(next_air, Cause.TARGET)
			return
	if _travelled >= _range_px - 0.01:
		_break(global_position, Cause.GROUND)


func _draw() -> void:
	var points := PackedVector2Array()
	var shadow := SHADOW_SIZE * (_look_px / LOOK_SIZE_PX)
	for i in 16:
		var angle := TAU * i / 16.0
		points.append(Vector2(cos(angle) * shadow.x, sin(angle) * shadow.y))
	draw_colored_polygon(points, SHADOW)
	_draw_streak()


## The whoosh streak behind the look for its first `gulp.feel.throw.streakMs`: lines trailing back
## along the throw, shrinking and fading as it ends.
func _draw_streak() -> void:
	var life := float(_streak.get("ms", 0.0))
	if life <= 0.0 or _age_ms >= life or _look == null:
		return
	var left := 1.0 - _age_ms / life
	var lines := maxi(1, int(_streak.get("lines", 1)))
	var width := float(_streak.get("width", 2.0))
	var length := float(_streak.get("px", 0.0)) * left
	if _feel_on:
		# The long streak grows out of the mouth: never longer than the flight so far.
		length = minf(length, _travelled)
	var back := -_direction
	var across := Vector2(-_direction.y, _direction.x)
	var start := _look.position + back * _look_px * STREAK_BEHIND_SHARE
	for i in lines:
		var offset := (float(i) - float(lines - 1) * 0.5) * width * STREAK_GAP
		var middle := absf(offset) < 0.01
		var reach := length * (1.0 if middle else STREAK_SIDE_SHARE)
		var from := start + across * offset
		var color := Color(STREAK_COLOR, STREAK_COLOR.a * left * (1.0 if middle else 0.7))
		draw_line(from, from + back * reach * 0.5, color, width, true)
		draw_line(from + back * reach * 0.5, from + back * reach, Color(color, color.a * 0.5), width * 0.6, true)


func _place_look() -> void:
	if _look == null:
		return
	var t := _travelled / maxf(1.0, _range_px)
	_look.position = Vector2(0.0, -_height(t))
	_look.rotation = _travelled / maxf(1.0, _speed) * SPIN_PER_S


## Height above the ground at flight fraction `t`: from the mouth down to the ground, with a rise.
func _height(t: float) -> float:
	return START_HEIGHT_PX * (1.0 - t) + 4.0 * ARC_PX * t * (1.0 - t)


func _air_point() -> Vector2:
	return global_position - Vector2(0.0, _height(_travelled / maxf(1.0, _range_px)))


## The new feel: `met` (the hurtboxes the thing just met at `air`) are locked and it flies on until
## it touches one (`_contact_gap`), for at most `contactFlightPx` more. False when it already
## touches (or their shapes cannot be measured): it breaks now, as it always did.
func _fly_to_contact(met: Array[Area2D], air: Vector2) -> bool:
	_locked = met
	_contact_left = ThrowFeel.number("contactFlightPx", 0.0)
	if _contact_left <= 0.0 or _contact_gap(air) <= 0.0 or _past_locked(air):
		return false
	return true


## How far (px) the thing at `air` still is from touching the nearest locked hurtbox: its distance to
## the hurtbox's shape less `contactPx`; 0 when none can be measured (gone, or no plain shape).
func _contact_gap(air: Vector2) -> float:
	var best := INF
	for area: Area2D in _locked:
		if is_instance_valid(area):
			best = minf(best, AbilityWorld.distance_to_area(area, air))
	return maxf(0.0, best - ThrowFeel.number("contactPx", 0.0)) if is_finite(best) else 0.0


## True once the thing at `air` is level with or past every locked hurtbox along the throw (it
## would only fly away from them now).
func _past_locked(air: Vector2) -> bool:
	for area: Area2D in _locked:
		if is_instance_valid(area) and (area.global_position - air).dot(_direction) > 0.0:
			return false
	return true


func _break(at: Vector2, cause: Cause = Cause.GROUND) -> void:
	_done = true
	var kind := str(_held.get("kind", ""))
	# A Goo Bomb never breaks or strikes: it drops whole on the ground under where the throw ended
	# (its end, a wall, the first hurtbox) and ticks on; it blows by its fuse.
	if kind == GooBomb.KIND:
		var bomb := GooBomb.from_held(_held)
		if bomb != null:
			bomb.call(&"land", global_position)
		queue_free()
		return
	# Off a jelly: a thing that touched a bouncer goes back at the slime whole (no strike, no break).
	if cause == Cause.TARGET and not _enemy and _player != null and is_instance_valid(_player):
		var touched := _locked.duplicate()
		touched.append_array(_targets(at, _constant("gulp.throwHitRadiusPx")))
		var bouncer := _bouncer_among(touched)
		if bouncer != null:
			_bounce_off(bouncer, at)
			queue_free()
			return
	var material := HeldLook.material_of(_held)
	# The new feel: what the blow did ({"hurt", "impact"}; {} when it struck nothing).
	var blow: Dictionary = {}
	if _player != null and is_instance_valid(_player):
		if ThrowMode.is_on():
			var targets := _targets(at, _break_radius())
			# The hurtboxes it flew on to touch are struck even if they stepped out of the break.
			for area: Area2D in _locked:
				if is_instance_valid(area) and not targets.has(area) and not _struck.has(area.get_instance_id()):
					targets.append(area)
			blow = _strike_rework(at, _damage(), kind, targets)
		else:
			var damage := _constant("gulp.throwDamage") * _material_damage(material)
			var radius := _constant("gulp.throwHitRadiusPx")
			if ReworkMode.is_on():
				_strike_rework(at, damage, kind, _targets(at, radius))
			else:
				AbilityWorld.strike_area(_player, at, radius, damage, _constant("gulp.throwKnockback"),
					["thrown", kind], "thrown-" + kind)
	# The enemy-ammo prototype: the carried enemy is put down where the flight ended (its own landing
	# hit and dust: GulpableEnemy); nothing breaks.
	if _enemy:
		GulpableEnemy.land(_held, global_position, _direction, _launch_feet, _level, bool(blow.get("hurt", false)))
		queue_free()
		return
	if _sturdy and bool(blow.get("hurt", false)):
		_uses -= 1
	_finish(at, cause, blow, true)


## The end of the flight at `at` after its strike (`blow`): a sturdy thing with a use left bounces off
## (`_rebound`); anything else, or one with nowhere to land, shatters into its own picture. Then the
## material's particles and cue (`play_cue`: false when the strike already played it), a sturdy
## blow's chips, and a miss's dust on the ground.
func _finish(at: Vector2, cause: Cause, blow: Dictionary, play_cue: bool) -> void:
	var material := HeldLook.material_of(_held)
	var hurt := bool(blow.get("hurt", false))
	var rebounds := _sturdy and _uses > 0 and _rebound(at, cause, hurt)
	# The Dung Roller's ball (game/enemy/dung_ball.gd; owner, 2026-11-21: "if you throw it at
	# nothing, the ball stays"): a blow that struck something breaks it; anything else leaves it whole
	# where it came down, for its beetle to fetch (`rebounds`: nothing bursts, nothing breaks).
	var lies := false
	if DungBall.is_ball(_held):
		var struck := hurt or (not _feel_on and not _struck.is_empty())
		lies = not struck and _lay_ball()
		if lies:
			rebounds = true
		else:
			DungBall.broke(_held)
	if not rebounds and _look is Sprite2D:
		BreakBurst.burst(get_parent(), at, _look as Sprite2D, _shard_options(at, cause, hurt))
	var feel := Services.feel()
	if feel != null:
		var impact: Vector2 = blow.get("impact", at)
		for preset: StringName in BREAK_PARTICLES.get(material, [&"dodge-dust"]):
			if hurt:
				# The material's particles fly on along the throw from the blow.
				feel.burst(preset, impact, _direction)
			elif not rebounds:
				feel.particles(preset, at)
		if rebounds and hurt and CHIP_TINTS.has(material):
			feel.burst(CHIP_PRESET, impact, _direction, CHIP_TINTS[material], ThrowFeel.rebound_number("chips", 1.0))
	# A ball that lies whole did not break: its landing has its own thud (dung_ball.gd `lay`).
	if play_cue and not lies:
		_play_break_cue(material, not hurt)
	# The landing's dust on the ground under it, and a heavy thing's nudge (gulp_feel.gd); a blow that
	# hurt has its own kick and no ground under it.
	if not hurt:
		GulpFeel.landed(at, global_position, material, _direction, [] if rebounds else BREAK_PARTICLES.get(material, [&"dodge-dust"]))
	queue_free()


## The rebound prototype: the sturdy thing that ended its flight at `at` (over the ground point it is
## on) bounces off instead of shattering; false when it has nowhere to land. A blow that hurt sends it
## back along the throw toward where it was thrown from (it lands `returnShortPx` short of there, at
## least `reboundMinPx` and at most `reboundMaxPx` back), over `reboundMs` (longer for a long way
## back: at most `reboundSpeed` px/s over the ground), rising `arcPx`, to be caught in the air; a miss hops `missReboundPx` (on along the throw where it came down, back off a
## wall or a target it did not hurt) over `missReboundMs`, rising `missArcPx`. Shorter spots along
## that line are tried (`tries`), and for a miss on the ground the very spot it came down on.
func _rebound(at: Vector2, cause: Cause, hurt: bool) -> bool:
	var ground := global_position
	var along := -_direction
	var far := ThrowFeel.rebound_number("missReboundPx", 0.0)
	var ms := ThrowFeel.rebound_number("missReboundMs", 1.0)
	var arc := ThrowFeel.rebound_number("missArcPx", 0.0)
	if hurt:
		var home := (ground - _launch_feet).dot(_direction) - ThrowFeel.rebound_number("returnShortPx", 0.0)
		far = clampf(home, ThrowFeel.rebound_number("reboundMinPx", 0.0), ThrowFeel.rebound_number("reboundMaxPx", 0.0))
		# A long way back takes longer (never faster than `reboundSpeed` over the ground) and rises more.
		var base_ms := ThrowFeel.rebound_number("reboundMs", 1.0)
		ms = maxf(base_ms, far / maxf(1.0, ThrowFeel.rebound_number("reboundSpeed", 1.0)) * 1000.0)
		arc = ThrowFeel.rebound_number("arcPx", 0.0) * ms / maxf(1.0, base_ms)
	elif cause == Cause.GROUND:
		along = _direction
	var tries := maxi(1, int(ThrowFeel.rebound_number("tries", 1.0)))
	var spot := ground
	var share := 0.0
	for i in tries:
		var reach := float(tries - i) / float(tries)
		if _can_land(ground, ground + along * far * reach):
			share = reach
			spot = ground + along * far * reach
			break
	if share <= 0.0 and (hurt or cause != Cause.GROUND or not _can_land(ground, ground)):
		return false
	var info := _held.duplicate()
	info["uses"] = _uses
	info.erase("hot")
	var spin := SPIN_PER_S * (1.0 if along.x >= 0.0 else -1.0)
	ThrowRebound.launch(get_parent(), info, ground, maxf(0.0, ground.y - at.y), spot, ms * lerpf(REBOUND_MIN_TIME_SHARE, 1.0, share),
		arc * lerpf(REBOUND_MIN_TIME_SHARE, 1.0, share), _look_px, _launch_feet, _level, break_cue(HeldLook.material_of(_held)), hurt, spin)
	return true


## The bouncer (BouncedThrow.BOUNCERS_GROUP: a Jelly Bouncer) whose hurtbox is among `areas` and that
## sends a thrown thing back now; null for none.
func _bouncer_among(areas: Array) -> Node:
	if areas.is_empty() or _enemy or GooBomb.from_held(_held) != null:
		return null
	for node: Node in get_tree().get_nodes_in_group(BouncedThrow.BOUNCERS_GROUP):
		if areas.has(node.get(&"damage_area")) and bool(node.call(&"bounces_throw")):
			return node
	return null


## The thing touched `bouncer` at `at` (over the ground point it is on): it flies back whole at where
## the slime stands (game/throw/bounced_throw.gd), with the hits it has left, and the jelly wobbles.
func _bounce_off(bouncer: Node, at: Vector2) -> void:
	var body := _player.get(&"body") as Node2D
	var aim := body.global_position if body != null else _launch_feet
	var info := _held.duplicate()
	var material := HeldLook.material_of(_held)
	if _sturdy:
		info["uses"] = _uses
	bouncer.call(&"on_throw_bounced", at, -_direction)
	BouncedThrow.launch(get_parent(), info, global_position, maxf(0.0, global_position.y - at.y), aim, _look_px,
		bouncer, _player, break_cue(material), BREAK_PARTICLES.get(material, [&"dodge-dust"]),
		_weight if not _weight.is_empty() else ThrowMode.LIGHT)


## The Dung Roller's ball comes down whole: on the ground point it is over, else the nearest spot
## back toward where it was thrown from that a thing may lie on (`_can_land`; `rebound.tries` spots).
## False when there is none (it breaks then).
func _lay_ball() -> bool:
	var ground := global_position
	var back := _launch_feet - ground
	var tries := maxi(1, int(ThrowFeel.rebound_number("tries", 1.0)))
	for i in tries:
		var spot := ground + back * (float(i) / float(tries))
		if _can_land(ground, spot):
			return DungBall.lay(get_parent(), spot, _held) != null
	return false


## True when the thing may land on `spot` coming from the ground point `from`: a liftable fits there
## (ThrowAmmo.fits: the thrower's height level, walkable, clear of walls and bodies), no wall stands
## between, and the slime does not stand within `clearPx` of it.
func _can_land(from: Vector2, spot: Vector2) -> bool:
	if not ThrowAmmo.fits(spot, _launch_feet, _level):
		return false
	if from != spot and not AbilityWorld.clear_line(from, spot, _player_rids()):
		return false
	var body := _player.get(&"body") as Node2D if _player != null and is_instance_valid(_player) else null
	return body == null or body.global_position.distance_to(spot) >= ThrowFeel.rebound_number("clearPx", 0.0)


## The global cue `material` breaks with (BREAK_CUES; CUE_FALLBACK for an unknown one): its own cue
## when the global audio scene has it, else the one it borrowed before (BREAK_CUE_BORROWED).
static func break_cue(material: String) -> StringName:
	var cue: StringName = BREAK_CUES.get(material, CUE_FALLBACK)
	if not BREAK_CUE_BORROWED.has(cue):
		return cue
	var feel := Services.feel()
	var root := feel.global_audio() if feel != null else null
	if root == null or root.find_child(String(cue), true, false) == null:
		return BREAK_CUE_BORROWED[cue]
	return cue


## The thing's own sound: its material's break cue, now (a break, or a piercing thing's blow as it
## flies on). With the new feel a heavier thing sounds lower (`gulp.throwFeel.breakPitch.<weight>`);
## it is the whole hit sound, at the cue's own strength for a hit, and `missVolumeDb` quieter for a
## `miss` (the ground, a wall, a blow that hurt nothing).
func _play_break_cue(material: String, miss: bool = false) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var payload := {}
	if _feel_on:
		var pitch := ThrowFeel.number("breakPitch." + (_weight if not _weight.is_empty() else ThrowMode.LIGHT), 1.0)
		if pitch > 0.0 and not is_equal_approx(pitch, 1.0):
			payload[CUE_PITCH_KEY] = pitch
		var quieter := ThrowFeel.number("missVolumeDb", 0.0) if miss else 0.0
		if quieter < 0.0:
			payload[CUE_VOLUME_KEY] = quieter
	if payload.is_empty():
		feel.audio_cue(break_cue(material))
	else:
		feel.audio_cue(break_cue(material), payload)


## The new feel's shards (break_burst.gd `options`; {} while it is off: the burst as it always was):
## `shards.hit` for a blow that hurt (they fly on along the throw), `shards.wall` off a wall or a
## target it did not hurt (they fall back), `shards.miss` where it came down; the ground is where
## its shadow is.
func _shard_options(at: Vector2, cause: Cause, hurt: bool) -> Dictionary:
	if not _feel_on:
		return {}
	var key := "hit" if hurt else ("miss" if cause == Cause.GROUND else "wall")
	var options := ThrowFeel.block("shards." + key).duplicate()
	options["direction"] = _direction
	options["floorDrop"] = maxf(BreakBurst.FLOOR_SPREAD, global_position.y - at.y)
	return options


## Throw combat: the damage of this throw (`gulp.throwCombat.throwDamage` x its material x its
## weight's and its effect's `damageScale`).
func _damage() -> float:
	if _enemy:
		return GulpableEnemy.throw_damage()
	var material := HeldLook.material_of(_held)
	return (ThrowFeel.base_damage() if _feel_on else ThrowMode.base_damage()) * _material_damage(material) \
		* ThrowMode.weight_number(_weight, "damageScale") \
		* float(ThrowMode.effect_row(_effect).get("damageScale", 1.0)) \
		* (ThrowFeel.rebound_number("hotDamageScale", 1.0) if _hot else 1.0)


## Throw combat: the break's radius (`gulp.throwHitRadiusPx` x the weight's and a shatter's
## `radiusScale`).
func _break_radius() -> float:
	return _constant("gulp.throwHitRadiusPx") * ThrowMode.weight_number(_weight, "radiusScale") \
		* float(ThrowMode.effect_row(_effect).get("radiusScale", 1.0))


## The hurtboxes within `radius` of `at` this throw reaches (its own height level, no wall between:
## AbilityWorld.hurtboxes_in_reach) and has not struck yet; none without a live player.
func _targets(at: Vector2, radius: float) -> Array[Area2D]:
	var out: Array[Area2D] = []
	if _player == null or not is_instance_valid(_player):
		return out
	for area: Area2D in AbilityWorld.hurtboxes_in_reach(_player, at, radius, _level, _player_rids()):
		if not _struck.has(area.get_instance_id()):
			out.append(area)
	return out


## The slime's bodies (walls are looked for past them).
func _player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if _player != null and is_instance_valid(_player):
		rids = _player.call(&"body_rids")
	return rids


## The `hit` a thrown thing carries in the rework mode, pushing along `direction` (unit); throw
## combat names its class (`hit_class_override`).
## The new throw feel (ThrowFeel on): the knockback numbers come from `gulp.throwFeel.hit.<weight>`
## (`weight` "" = light): `knock_px`, `knock_speed_scale`, `launch_speed`; and the hit carries the
## fields the enemies' reactions read: `"big": true` (it shows as a big hit: the long flash, the big
## number), `"knock_motion": true` (the knocked-back motion), `"kill_sendoff": true` (a kill flies
## off and pops), `"bowl_damage"` (`bowlDamage`), and `"chains": true` when `chains` (its stun slide
## may splat on walls and bowl into other enemies).
static func rework_hit(direction: Vector2, hit_class_override: String = "", weight: String = "") -> Dictionary:
	var block := _throw_hit_block()
	var hit_class := str(block.get("class", REWORK_FALLBACK_CLASS))
	if not hit_class_override.is_empty():
		hit_class = hit_class_override
	var fields := {
		"step": 0,
		"last": true,
		"tags": REWORK_TAGS.duplicate(),
		"knock": direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO,
		"launch_speed": _constant("gulp.throwKnockback"),
		"knock_px": float(block.get("knockbackPx", 0.0)),
		"knock_speed_scale": float(block.get("knockbackSpeedScale", 1.0)),
	}
	# The thing's weight rides on the hit, so an enemy can tell what struck it whatever the effect's
	# class (the Worm Bulwark counts hits by weight: a thrown ice block is a medium hit).
	if not weight.is_empty():
		fields["weight"] = weight
	if ThrowFeel.is_on():
		var strong := ThrowFeel.hit_block(weight)
		fields["launch_speed"] = float(strong.get("launchSpeed", fields["launch_speed"]))
		fields["knock_px"] = float(strong.get("knockbackPx", fields["knock_px"]))
		fields["knock_speed_scale"] = float(strong.get("knockbackSpeedScale", fields["knock_speed_scale"]))
		fields["big"] = true
		fields["knock_motion"] = true
		fields["kill_sendoff"] = true
		fields["bowl_damage"] = ThrowFeel.number("bowlDamage", 0.0)
		if ThrowFeel.flag("chains"):
			fields["chains"] = true
	return HitReaction.build_hit(hit_class, fields)


## Rework mode: each of `targets` (`_targets` around `at`: not the player's, not a resource, in
## reach, not struck yet) gets one request with the throw's `hit`; then the feel from the outcomes,
## one per target: {"receiver", "area", "position", "result"} (route()'s result, with the enemy's
## "reaction"). Returns what the blow did, for the break: {"hurt": it dealt damage, "impact": the
## contact point} with the new feel, else {}.
func _strike_rework(at: Vector2, damage: float, kind: String, targets: Array[Area2D]) -> Dictionary:
	if targets.is_empty() or _player == null or not is_instance_valid(_player):
		return {}
	var router := Services.router()
	var attack_area := _player.call(&"get_slam_area") as Area2D if _player.has_method(&"get_slam_area") else null
	if router == null or attack_area == null:
		return {}
	var outcomes: Array[Dictionary] = []
	var hit := rework_hit(_direction, ThrowMode.hit_class(_weight, _effect) if ThrowMode.is_on() else "", _weight)
	if _enemy:
		hit = rework_hit(_direction, GulpableEnemy.throw_hit_class(), _feel_weight())
	var activation := router.begin_activation(_player, [attack_area])
	for area in targets:
		var request := {
			"activation_id": activation,
			"source": _player,
			"attack_area": attack_area,
			"target_area": area,
			"weapon_id": "thrown-" + kind,
			"weapon_tags": ["thrown", kind],
			"damage_types": DAMAGE_TYPES.duplicate(),
			"base_damage": damage,
			"effects": [],
			"impact": {"position": area.global_position, "knock": hit["knock"]},
		}
		var receiver := router.receiver_for_area(area)
		var point := _target_point(receiver, area)
		_struck[area.get_instance_id()] = true
		var result := router.route(HitReaction.attach(request, hit.duplicate(true)))
		outcomes.append({"receiver": receiver, "area": area, "position": point, "result": result})
		_show_effect(receiver, result)
	router.end_activation(activation)
	if _feel_on:
		return _play_throw_feel(at, hit, outcomes)
	_play_rework_feel(at, hit, outcomes)
	return {}


## The throw's feel once (hit-stop, trauma, sparks at the break), then each target's number; a
## clink when nothing took the hit and a target was immune.
func _play_rework_feel(at: Vector2, hit: Dictionary, outcomes: Array[Dictionary]) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var reactions: Array[Dictionary] = []
	var accepted := 0
	var killed := false
	var clinked := false
	for outcome: Dictionary in outcomes:
		var result: Dictionary = outcome["result"]
		if str(result.get("status", "")) == "accepted":
			accepted += 1
			killed = killed or bool(result.get("defeated", false))
			var reaction: Variant = result.get("reaction")
			if reaction is Dictionary:
				reactions.append(reaction as Dictionary)
		elif str(result.get("reason", "")) == "immune":
			clinked = true
	if accepted == 0:
		if clinked:
			var constants := Services.constants()
			var stop_ms := constants.number("combat.chain.clink.hitStopMs") if constants != null else 0.0
			feel.play_hit({"hit_stop_ms": stop_ms, "sound_cue": CUE_CLINK}, at, _direction)
		return
	var spec := HitJuice.swing_spec(_throw_hit_block(), hit, reactions, 0, accepted, killed)
	spec["number"] = 0
	feel.play_hit(spec, at, _direction)
	for outcome: Dictionary in outcomes:
		var result: Dictionary = outcome["result"]
		var dealt := int(result.get("actual_damage", 0))
		if str(result.get("status", "")) != "accepted" or dealt <= 0:
			continue
		var number := HitJuice.number_spec(dealt, hit)
		number["hit_stop_ms"] = 0.0
		feel.play_hit(number, outcome["position"], _direction)


## The new throw feel's blow (ThrowFeel on), once per strike. A blow that hurt: at the contact point
## (`_contact_point` of the target it hurt most) the weight's feel (`gulp.throwFeel.hit.<weight>`
## through HitJuice.swing_spec: hit-stop, trauma, kick, the big sparks along the throw, the victim's
## material debris), `cues.kill` when it kills without a send-off (at the spec's pitch: a tiny enemy's
## pop streak raises it; a kill whose reaction says `sendoff` plays the cue itself when the corpse
## pops; the hit's own sound is the thing's material cue, `_play_break_cue`), the impact star about as
## wide as that target, and each target's big number; the hit-stop grows by `killStopMs` on a kill, up to
## `hitStopCapMs` (past `combat.chain.hitStop.capMs`, straight through GameFeel.hit_stop). A blow
## that hurt nothing (a clink, a sleep throw) plays the old feel. Returns {"hurt", "impact"}.
func _play_throw_feel(at: Vector2, hit: Dictionary, outcomes: Array[Dictionary]) -> Dictionary:
	var feel := Services.feel()
	var reactions: Array[Dictionary] = []
	var accepted := 0
	var killed := false
	# A kill whose reaction has no send-off: the kill cue plays here, at the hit (a send-off plays it
	# itself, when the corpse pops: EnemyReactions).
	var kill_cue := false
	var most := 0
	var struck: Dictionary = {}
	for outcome: Dictionary in outcomes:
		var result: Dictionary = outcome["result"]
		if str(result.get("status", "")) != "accepted":
			continue
		accepted += 1
		var defeated := bool(result.get("defeated", false))
		killed = killed or defeated
		var reaction: Variant = result.get("reaction")
		if reaction is Dictionary:
			reactions.append(reaction as Dictionary)
		if defeated and not (reaction is Dictionary and bool((reaction as Dictionary).get("sendoff", false))):
			kill_cue = true
		var dealt := int(result.get("actual_damage", 0))
		if dealt > most or struck.is_empty():
			most = dealt
			struck = outcome
	if feel == null or accepted == 0 or most <= 0:
		_play_rework_feel(at, hit, outcomes)
		return {"hurt": false, "impact": at}
	var impact := _contact_point(at, struck["position"])
	var block := ThrowFeel.hit_block(_feel_weight())
	var spec := HitJuice.swing_spec(block, hit, reactions, 0, accepted, killed)
	spec["number"] = 0
	spec["impact_ring"] = false
	spec["sound_cue"] = ThrowFeel.cue("kill") if kill_cue else &""
	feel.play_hit(spec, impact, _direction)
	var stop_ms := float(block.get("hitStopMs", 0.0)) + (ThrowFeel.number("killStopMs", 0.0) if killed else 0.0)
	if feel.juice_layer_on(HitJuice.LAYER_FREEZE):
		feel.hit_stop(minf(stop_ms, ThrowFeel.number("hitStopCapMs", stop_ms)))
	if feel.juice_layer_on(HitJuice.LAYER_SPARKS):
		var numbers := ThrowFeel.block("star")
		var width := maxf(_area_width(struck["area"]) * float(numbers.get("share", 1.0)), _look_px * STAR_MIN_LOOK_SHARE)
		width = minf(width * ThrowFeel.number("star.weightScale." + (_weight if not _weight.is_empty() else ThrowMode.LIGHT), 1.0),
			float(numbers.get("maxPx", width)))
		ThrowImpact.star(get_parent(), impact, _direction, width, numbers)
	for outcome: Dictionary in outcomes:
		var result: Dictionary = outcome["result"]
		var dealt := int(result.get("actual_damage", 0))
		if str(result.get("status", "")) != "accepted" or dealt <= 0:
			continue
		var number := HitJuice.number_spec(dealt, hit)
		number["hit_stop_ms"] = 0.0
		feel.play_hit(number, outcome["position"], _direction)
	return {"hurt": true, "impact": impact}


## The weight whose hit numbers the blow plays (`gulp.throwFeel.hit.<weight>`): the thing's own; a
## carried enemy's is the medium one, whatever it weighs.
func _feel_weight() -> String:
	return ThrowMode.MEDIUM if _enemy else _weight


## Where a blow shows: from the thing's middle `at` toward the target's middle `centre`, at most
## CONTACT_LOOK_SHARE of the flying look away (the thing's rim on the enemy's side).
func _contact_point(at: Vector2, centre: Vector2) -> Vector2:
	return at + (centre - at).limit_length(_look_px * CONTACT_LOOK_SHARE)


## The width (px) of a hurtbox's widest plain shape; 0 when it has none.
static func _area_width(area: Area2D) -> float:
	var width := 0.0
	if not is_instance_valid(area):
		return width
	for child: Node in area.get_children():
		var node := child as CollisionShape2D
		if node == null or node.disabled or node.shape == null:
			continue
		var scale := node.global_transform.get_scale().abs()
		if node.shape is RectangleShape2D:
			width = maxf(width, (node.shape as RectangleShape2D).size.x * scale.x)
		elif node.shape is CircleShape2D:
			width = maxf(width, (node.shape as CircleShape2D).radius * 2.0 * scale.x)
		elif node.shape is CapsuleShape2D:
			width = maxf(width, (node.shape as CapsuleShape2D).radius * 2.0 * scale.x)
	return width


## Throw combat: a freeze or a sleep that stunned `receiver` shows on it while the stun (the sleep)
## lasts; honey (an effect with `slowMs`; owner, 2026-11-01) that struck it and was not shrugged off
## (armor, a kill, a boss: enemy.gd `apply_tempo` refuses) slows it to `slowScale` of its pace for
## `slowMs` and coats it as long.
func _show_effect(receiver: Object, result: Dictionary) -> void:
	if not ThrowMode.is_on() or _effect.is_empty() or str(result.get("status", "")) != "accepted":
		return
	var reaction: Variant = result.get("reaction")
	if not reaction is Dictionary:
		return
	var verb := str((reaction as Dictionary).get("verb", ""))
	var row := ThrowMode.effect_row(_effect)
	var slow_ms := float(row.get("slowMs", 0.0))
	if slow_ms > 0.0:
		if verb == HitReaction.VERB_ARMOR or bool((reaction as Dictionary).get("killed", false)) \
				or receiver == null or not receiver.has_method(&"apply_tempo"):
			return
		if bool(receiver.call(&"apply_tempo", float(row.get("slowScale", 1.0)), slow_ms)):
			ThrowStatusLook.attach(receiver, _effect, slow_ms)
		return
	if not STUN_VERBS.has(verb):
		return
	var ms := float((reaction as Dictionary).get("stun_ms", 0.0))
	if ms <= 0.0:
		ms = float(ThrowMode.effect_row(_effect).get("lookMs", 0.0))
	ThrowStatusLook.attach(receiver, _effect, ms)


## Where a target's number shows: its centre when it has one, else its hurtbox.
static func _target_point(receiver: Object, area: Area2D) -> Vector2:
	if receiver != null and is_instance_valid(receiver) and receiver.has_method(&"get_centre"):
		var centre: Variant = receiver.call(&"get_centre")
		if centre is Vector2:
			return centre
	return area.global_position


## `gulp.throwHit` (the thrown hit's class and feel numbers); {} when missing.
static func _throw_hit_block() -> Dictionary:
	var constants := Services.constants()
	return constants.dictionary("gulp.throwHit") if constants != null else {}


## `gulp.throwDamageByMaterial[material]`, 1 when the material has no entry.
static func _material_damage(material: String) -> float:
	var constants := Services.constants()
	if constants == null:
		return 1.0
	var table := constants.dictionary("gulp.throwDamageByMaterial")
	return float(table.get(material, 1.0))


static func _constant(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0

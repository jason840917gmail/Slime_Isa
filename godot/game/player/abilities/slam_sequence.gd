extends RefCounted
## Squash Slam, improved (body-shapes plan section 4; combat-feel plan section 3 "Abilities as
## impact classes" and section 6 "Juice"; every number in game-constants.json
## `abilities.squashSlam`). In the body-shapes rework mode it replaces the old Slam (Phaser
## `LegacyPlayerAbilityPresentation.ts:236-310`; abilities spec 6), which the classic game keeps
## (classic_slam_sequence.gd; PlayerAbilities picks by ReworkMode).
##
## The body never moves: only the art rises, on the player's effects channel (`set_effect_offset`,
## `set_effect_scale`); the sequence never starts a flight and never changes the body's height
## level, so the slam can never cross a wall, gate, hole or cliff (the reason the jump went).
## The art crouches (0 to `crouchEndMs`), rises `riseUnits` (to `riseEndMs`, cue SlamRise), hangs
## (to `hangEndMs`), dives (cue SlamDive) and hits the ground at `impactMs`; it springs back and the
## slam is done at `doneMs`. Its shadow stays on the ground under it. Today's slam poses play
## (the `squash` clip, then the `hop` clip for the dive).
##
## At the impact it strikes the ground ellipse (`ellipse`: width x height around the slime, its
## inner `innerShare`) on the slime's own height level only (AbilityWorld.hurtboxes_in_ellipse; the
## hurtboxes are tested at the old centre, where every hurtbox sits): the inner half with `inner`
## (class slam: 40, launch 380 with a 16 px hop), the outer ring with `outer` (class ring: 24, a
## bounce held `bounceMs` in place so a chain can follow; 300 where a profile pushes), both
## +`stoneDamageBonus` in the Stone form. In the rework mode each request carries its `hit`
## (HitReaction.build_hit) and the enemies answer with their reaction; without the mode (not used
## today: PlayerAbilities runs the classic Slam then) they would take the old knockback effect of the
## same speeds. Never stone, iron or boulders, never a
## resource (AbilityWorld skips them); in the Stone form cracked ground breaks under it
## (`record_slam`, as before). A refused hit clinks (a spark and a tick).
##
## The feel: `feel` (shake 240 ms x 0.014, hit-stop 110 ms), `stoneFeel` in the Stone form
## (260 x 0.018, 140); in the rework mode through GameFeel.play_hit (the hit-stop by the per-swing
## rule, the trauma), with each target's damage number. Then a shockwave ellipse on the ground, the
## crack at the feet, pebbles and dust in the ground's colour (ability_fx.gd) and the liftables
## within `wobbleRadiusPx` rocking; cue SlamImpact (SlamImpactStone in the Stone form).
## The new cues have no takes yet: a cue the global audio scene lacks plays its placeholder
## (PLACEHOLDER_CUES).
##
## `is_airborne(now)` (no hits on the slime from `airborneFromMs` to `airborneToMs`) and
## `ignores_knockback()` (`ignoresKnockback`, the whole slam) feed PlayerAbilities.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")

## The Slam's tags (a slam is neither a cut nor a crush) on its requests and hits.
const TAGS: Array[String] = ["slam"]
## The cues (body-shapes plan section 4) and, until their takes exist, what plays instead.
const CUE_RISE := &"SlamRise"
const CUE_DIVE := &"SlamDive"
const CUE_IMPACT := &"SlamImpact"
const CUE_IMPACT_STONE := &"SlamImpactStone"
const CUE_CLINK := &"Clink"
const PLACEHOLDER_CUES := {
	CUE_RISE: &"SlamWindup",
	CUE_DIVE: &"Dodge",
	CUE_IMPACT_STONE: CUE_IMPACT,
	CUE_CLINK: &"HitBlocked",
}
## Today's slam poses: the wind-up clip from the start, the hop clip from the dive.
const CLIP_RISE := "squash"
const CLIP_DIVE := "hop"
## The art's shape (x, y scale) at each moment: crouched, stretched rising, stretched diving,
## squashed on the ground (springing back to 1 by the end, an ease-out-back of BACK_OVERSHOOT).
const CROUCH := Vector2(1.18, 0.72)
const RISE_STRETCH := Vector2(0.84, 1.3)
const DIVE_STRETCH := Vector2(0.8, 1.34)
const IMPACT_SQUASH := Vector2(1.4, 0.6)
const BACK_OVERSHOOT := 1.70158
## The shadow lies on the ground under the bodies, shrinks to SHADOW_HIGH_SCALE and fades to
## SHADOW_HIGH_ALPHA at the top of the rise (as the jump's).
const SHADOW_Z := -1
const SHADOW_HIGH_SCALE := 0.55
const SHADOW_HIGH_ALPHA := 0.6
## The landing's look (ability_fx.gd): the crack's size as a share of the ellipse (bigger in the
## Stone form), pebbles and dust puffs, and the sparks on each struck target (rework mode).
const CRACK_SHARE := 0.75
const CRACK_SHARE_STONE := 0.95
const PEBBLES := 10
const PEBBLES_STONE := 16
const DUST_PUFFS := 9
const TARGET_SPARKS := 5
const SPARK_PRESET := &"hit-spark"
const CLINK_SPARK_RISE := 12.0

var _player: Node
var _body: CharacterBody2D
var _started_ms: float = 0.0
var _struck: bool = false
var _done: bool = false
var _rise_cued: bool = false
var _dive_cued: bool = false
var _shadow: Node2D
## The timeline (ms after the press) and the rise, read from the constants at the start.
var _crouch_end: float = 0.0
var _rise_end: float = 0.0
var _hang_end: float = 0.0
var _impact_at: float = 0.0
var _done_at: float = 0.0
var _air_from: float = 0.0
var _air_to: float = 0.0
var _rise_units: float = 0.0
var _ignores_knockback: bool = false
## This impact's outcomes: the hits that landed ({"receiver", "area", "position", "result", "hit"})
## and where hits clinked.
var _landed: Array[Dictionary] = []
var _clinks: Array[Vector2] = []


## `abilities.squashSlam.<key>` as a number (0 without constants).
static func setting(key: String) -> float:
	var constants := Services.constants()
	return constants.number(Definitions.SLAM_CONSTANTS + "." + key) if constants != null else 0.0


## `abilities.squashSlam.<key>` as a Dictionary ({} without constants).
static func section(key: String) -> Dictionary:
	var constants := Services.constants()
	return constants.dictionary(Definitions.SLAM_CONSTANTS + "." + key) if constants != null else {}


## `cue` when the global audio scene has it, else its placeholder (PLACEHOLDER_CUES).
static func cue_or_placeholder(cue: StringName) -> StringName:
	var feel := Services.feel()
	var root: Node = feel.global_audio() if feel != null else null
	if root != null and root.find_child(String(cue), true, false) != null:
		return cue
	return PLACEHOLDER_CUES.get(cue, cue)


func begin(player: Node, _intent: Dictionary, now_ms: float) -> void:
	_player = player
	_body = player.get(&"body") as CharacterBody2D
	_started_ms = now_ms
	_crouch_end = setting("crouchEndMs")
	_rise_end = setting("riseEndMs")
	_hang_end = setting("hangEndMs")
	_impact_at = setting("impactMs")
	_done_at = setting("doneMs")
	_air_from = setting("airborneFromMs")
	_air_to = setting("airborneToMs")
	_rise_units = setting("riseUnits")
	var constants := Services.constants()
	_ignores_knockback = constants != null and bool(constants.value(Definitions.SLAM_CONSTANTS + ".ignoresKnockback", false))
	_player.call(&"play_animation", CLIP_RISE, true)
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_shadow = AbilityFx.jump_shadow(_feet())
	if _shadow != null:
		_shadow.z_index = SHADOW_Z
	_pose(0.0)


func advance(now_ms: float) -> bool:
	if _done:
		return true
	var elapsed := now_ms - _started_ms
	if not _rise_cued and elapsed >= _crouch_end:
		_rise_cued = true
		_cue(CUE_RISE)
	if not _dive_cued and elapsed >= _hang_end:
		_dive_cued = true
		_cue(CUE_DIVE)
		_player.call(&"play_animation", CLIP_DIVE, true)
	if not _struck and elapsed >= _impact_at:
		_impact()
	if elapsed >= _done_at:
		_finish()
		return true
	_pose(elapsed)
	return false


## Teardown: the art back at rest, the shadow gone.
func cancel() -> void:
	_done = true
	_free_shadow()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


## True while the slime is in the air (`airborneFromMs` to `airborneToMs`): no hits land on it.
func is_airborne(now_ms: float) -> bool:
	if _done:
		return false
	var elapsed := now_ms - _started_ms
	return elapsed >= _air_from and elapsed < _air_to


## True for the whole slam when `ignoresKnockback` is set: knockback does not move the slime.
func ignores_knockback() -> bool:
	return not _done and _ignores_knockback


# --- the art -------------------------------------------------------------------------------------

## The art's height and shape `elapsed` ms after the press, and the shadow under it.
func _pose(elapsed: float) -> void:
	var height := 0.0
	var shape := Vector2.ONE
	if elapsed < _crouch_end:
		shape = Vector2.ONE.lerp(CROUCH, _ease_out(_share(elapsed, 0.0, _crouch_end)))
	elif elapsed < _rise_end:
		var t := _share(elapsed, _crouch_end, _rise_end)
		height = _rise_units * _ease_out(t)
		shape = CROUCH.lerp(RISE_STRETCH, t * 2.0) if t < 0.5 else RISE_STRETCH.lerp(Vector2.ONE, (t - 0.5) * 2.0)
	elif elapsed < _hang_end:
		height = _rise_units
	elif elapsed < _impact_at:
		var t := _share(elapsed, _hang_end, _impact_at)
		height = _rise_units * (1.0 - t * t)
		shape = Vector2.ONE.lerp(DIVE_STRETCH, t)
	else:
		shape = IMPACT_SQUASH.lerp(Vector2.ONE, _ease_out_back(_share(elapsed, _impact_at, _done_at)))
	_player.call(&"set_effect_offset", Vector2(0.0, -height))
	_player.call(&"set_effect_scale", shape)
	_place_shadow(height)


func _place_shadow(height: float) -> void:
	if _shadow == null or not is_instance_valid(_shadow):
		return
	var high := clampf(height / _rise_units, 0.0, 1.0) if _rise_units > 0.0 else 0.0
	_shadow.global_position = _feet()
	_shadow.scale = Vector2.ONE * lerpf(1.0, SHADOW_HIGH_SCALE, high)
	_shadow.modulate.a = lerpf(1.0, SHADOW_HIGH_ALPHA, high)


func _finish() -> void:
	_done = true
	_free_shadow()
	_player.call(&"reset_effects")


func _free_shadow() -> void:
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.queue_free()
	_shadow = null


# --- the impact ----------------------------------------------------------------------------------

func _impact() -> void:
	_struck = true
	_free_shadow()
	var centre: Vector2 = _player.call(&"get_centre")
	var feet := _feet()
	var stone := StringName(_player.call(&"current_form_id")) == GulpForms.HEAVY
	var bonus := 1.0 + (setting("stoneDamageBonus") if stone else 0.0)
	var ellipse := section("ellipse")
	var half := Vector2(float(ellipse.get("width", 0.0)), float(ellipse.get("height", 0.0))) * 0.5
	var inner_share := float(ellipse.get("innerShare", 0.0))
	var level := _level()
	var everyone := AbilityWorld.hurtboxes_in_ellipse(_player, centre, half, level)
	var inner := AbilityWorld.hurtboxes_in_ellipse(_player, centre, half * inner_share, level)
	var outer: Array[Area2D] = []
	for area in everyone:
		if not inner.has(area):
			outer.append(area)
	var inner_numbers := section("inner")
	var outer_numbers := section("outer")
	var rework := ReworkMode.is_on()
	var inner_hit := _hit(inner_numbers) if rework else {}
	var outer_hit := _hit(outer_numbers) if rework else {}
	_landed.clear()
	_clinks.clear()
	AbilityWorld.strike_targets(_player, centre, inner, float(inner_numbers.get("damage", 0.0)) * bonus,
		float(inner_numbers.get("launchSpeed", 0.0)), TAGS.duplicate(), String(Definitions.SQUASH_SLAM), inner_hit,
		_on_outcome.bind(inner_hit))
	AbilityWorld.strike_targets(_player, centre, outer, float(outer_numbers.get("damage", 0.0)) * bonus,
		float(outer_numbers.get("launchSpeed", 0.0)), TAGS.duplicate(), String(Definitions.SQUASH_SLAM), outer_hit,
		_on_outcome.bind(outer_hit))
	_player.call(&"record_slam", centre)
	_play_feel(stone, centre, inner_hit)
	_cue(CUE_IMPACT_STONE if stone else CUE_IMPACT)
	var tint := AbilityFx.ground_tint(feet)
	AbilityFx.shockwave(feet, half * 2.0, tint, inner_share)
	AbilityFx.crack_decal(feet, half * 2.0 * (CRACK_SHARE_STONE if stone else CRACK_SHARE))
	AbilityFx.debris(feet, tint, PEBBLES_STONE if stone else PEBBLES, DUST_PUFFS, half.y / half.x if half.x > 0.0 else 1.0)
	AbilityFx.wobble_liftables(feet, setting("wobbleRadiusPx"))


## The rework `hit` of one part of the slam (`inner` or `outer`): its class, launch and hop, and
## for the ring the bounce's hold (`bounceMs`); the knock is filled per target (away from the slime).
func _hit(numbers: Dictionary) -> Dictionary:
	return HitReaction.build_hit(str(numbers.get("class", "")), {
		"step": 0,
		"last": true,
		"shape": "",
		"tags": TAGS.duplicate(),
		"hold_ms": float(numbers.get("bounceMs", 0.0)),
		"launch_speed": float(numbers.get("launchSpeed", 0.0)),
		"hop_px": float(numbers.get("hopPx", 0.0)),
		"knock": Vector2.ZERO,
	})


## One target's outcome (AbilityWorld.strike_targets), with the `hit` it was sent.
func _on_outcome(outcome: Dictionary, hit: Dictionary) -> void:
	var result: Variant = outcome.get("result")
	if not (result is Dictionary):
		return
	if AbilityWorld.is_clink(result):
		_clinks.append(outcome.get("position", Vector2.ZERO))
	elif str((result as Dictionary).get("status", "")) == "accepted":
		var landed := outcome.duplicate()
		landed["hit"] = hit
		_landed.append(landed)


## The slam's feel once, the damage numbers (rework mode; `hit` the inner half's, for the swing's
## spec) and the clinks.
func _play_feel(stone: bool, centre: Vector2, hit: Dictionary) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var numbers := section("stoneFeel" if stone else "feel")
	if ReworkMode.is_on():
		var reactions: Array[Dictionary] = []
		var killed := false
		for landed: Dictionary in _landed:
			var result: Dictionary = landed["result"]
			var reaction: Variant = result.get("reaction")
			if reaction is Dictionary:
				reactions.append(reaction)
			killed = killed or bool(result.get("defeated", false))
		var swing := {"hitStopMs": float(numbers.get("hitStopMs", 0.0)), "trauma": float(numbers.get("trauma", 0.0))}
		# The freeze, the trauma and one material cue at the slime; the debris bursts at each target
		# (`_play_number`), not out of the slime.
		var spec := HitJuice.swing_spec(swing, hit, reactions, 0, _landed.size(), killed)
		spec["debris_preset"] = &""
		feel.play_hit(spec, centre, Vector2.ZERO)
		for landed: Dictionary in _landed:
			_play_number(feel, landed, centre)
	else:
		feel.shake(float(numbers.get("shakeMs", 0.0)), float(numbers.get("intensity", 0.0)))
		feel.hit_stop(float(numbers.get("hitStopMs", 0.0)))
	for at in _clinks:
		feel.particles(SPARK_PRESET, at - Vector2(0.0, CLINK_SPARK_RISE))
	if not _clinks.is_empty():
		_cue(CUE_CLINK)


## One struck target's damage number, its material's tinted sparks and its debris, pushed away from
## the slime's `centre` (no freeze or shake, no material cue: the swing has them).
func _play_number(feel: Node, landed: Dictionary, centre: Vector2) -> void:
	var result: Dictionary = landed["result"]
	var damage := int(result.get("actual_damage", 0))
	if damage <= 0:
		return
	var spec := HitJuice.number_spec(damage, landed.get("hit", {}))
	var reaction: Variant = result.get("reaction")
	if reaction is Dictionary:
		var r: Dictionary = reaction
		var rf: Variant = r.get("feel", {})
		var feel_dict: Dictionary = rf if rf is Dictionary else {}
		var look := HitJuice.material_spec(str(feel_dict.get("material", r.get("material", ""))),
			HitJuice.is_big(landed.get("hit", {})))
		look.erase("material_cue")
		spec.merge(look, true)
	spec.merge({"hit_stop_ms": 0.0, "trauma": 0.0, "kick_px": 0.0, "sparks": TARGET_SPARKS,
		"spark_preset": SPARK_PRESET, "sound_cue": &""}, true)
	var at: Vector2 = landed.get("position", Vector2.ZERO)
	feel.call(&"play_hit", spec, at, (at - centre).normalized())


# --- helpers -------------------------------------------------------------------------------------

func _cue(cue: StringName) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"action_cue", cue_or_placeholder(cue))


## The slime's feet (the body's position; the old centre is 27.56 above).
func _feet() -> Vector2:
	if _body != null and is_instance_valid(_body):
		return _body.global_position
	return _player.call(&"get_centre") if _player != null else Vector2.ZERO


## The slime's height level, or AbilityWorld.ANY_LEVEL without elevation.
func _level() -> int:
	var world := Services.world()
	if world == null or world.elevation == null or _body == null:
		return AbilityWorld.ANY_LEVEL
	return world.elevation.level_of(_body)


## How far `value` is from `from` to `to`, 0..1.
static func _share(value: float, from: float, to: float) -> float:
	return clampf((value - from) / (to - from), 0.0, 1.0) if to > from else 1.0


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


static func _ease_out_back(t: float) -> float:
	var u := t - 1.0
	return 1.0 + (BACK_OVERSHOOT + 1.0) * u * u * u + BACK_OVERSHOOT * u * u

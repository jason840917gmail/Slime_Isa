extends RefCounted
## The juice panel's demos (combat-feel plan section 9 item 6 "Feel switches"; docs/godot/BODY_SHAPES.md
## "Juice"; the owner's playtest of 2026-10-12: "keys 1-0 should play the effect so I can see it").
## While the panel (game/feel/juice_dev_panel.gd) shows, a number key plays its juice layer once on
## the nearest training dummy or enemy whose hurtbox lies within DEMO_REACH_PX of the slime's centre
## (else on the slime itself, at its centre, along its facing; the hit's direction is from the slime
## to the target): first at the current shape's finisher values (its last chain step), then,
## SHOWN_DELAY_MS after that one ends, an exaggerated replay ("shown 4x": lengths and counts x
## SHOWN_SCALE, sizes x SHOWN_SIZE_SCALE), because the real ones are too short to follow. `lines()`
## names what played, for the panel.
##
## Every demo plays through the game's own juice functions (GameFeel, HitFlash, the target's hit
## motion), so what shows is what a hit does now: a layer switched off, reduce motion, the screen-shake
## slider or the Damage numbers setting keep it from showing, and its panel line says so. The freeze,
## the jitter and the slow motion need something moving to be seen: they play a hit motion on the
## target (the hold squash; for the room clear the launch tumble) and freeze or slow it.
##
##   1 freeze   the finisher's hit-stop, holding the target's squash      shown: 4x as long
##   2 flash    the finisher's white-then-tint flash                       shown: 4x as long
##   3 squash   the hold squash the target's weight plays                  shown: 4x as long, 2x as deep
##   4 jitter   the target shaking in the finisher's freeze                shown: 4x as long, 2x as wide
##   5 trauma   the finisher's camera trauma along the hit                 shown: x4 (1 at most)
##   6 kick     the finisher's camera kick along the hit                   shown: 4x as far
##   7 sparks   the finisher's sparks, ring and the target's debris        shown: 4x as many
##   8 pitch    the impact sound at each chain step's pitch, rising        shown: each step's rise x4
##   9 numbers  the finisher's damage number and its pop                   shown: 4x as slow
##   0 slowmo   the room clear: freeze, stutter slow motion, music dip     shown: 4x as long
##
## Presentation and dev only: no damage, no reaction, no gameplay state; the schedule runs on real
## time (`step` from the panel's `_process`, which runs through a freeze).
##
## Owner: juice.

const Services := preload("res://game/shared/services.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const EnemyHitMotion := preload("res://game/feel/enemy_hit_motion.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")

## A dummy or enemy whose hurtbox is this close to the slime's centre is the demo's target (dev).
const DEMO_REACH_PX := 200.0
## The exaggerated replay: lengths and counts x SHOWN_SCALE (the panel's "shown 4x"), sizes (the
## squash's depth, the jitter's width) x SHOWN_SIZE_SCALE; it starts SHOWN_DELAY_MS after the real
## one ends. The three rising hit sounds are PITCH_GAP_MS apart (dev presentation).
const SHOWN_SCALE := 4.0
const SHOWN_SIZE_SCALE := 2.0
const SHOWN_DELAY_MS := 600.0
const PITCH_GAP_MS := 220.0
## The shape whose finisher the demos use when the slime has no shape controller.
const DEFAULT_SHAPE := ShapeDefs.SPEAR
## With no target near, the slime is the target: its weight and material for the demos, and the
## name of the hit motion the demos give its Visual (a child of the player script node).
const SELF_WEIGHT := "light"
const SELF_MATERIAL := "goo"
const SELF_MOTION_NODE := "JuiceDemoMotion"
## The layers that reduce motion turns off (GameFeel: no freeze, shake, kick or stutter; the jitter
## shows only in a freeze).
const REDUCED_LAYERS: Array[StringName] = [HitJuice.LAYER_FREEZE, HitJuice.LAYER_JITTER, HitJuice.LAYER_TRAUMA,
	HitJuice.LAYER_KICK, HitJuice.LAYER_SLOWMO]

## Bumped whenever `lines()` changes (the panel redraws then).
var revision: int = 0

## The schedule: {"at": real ms, "run": Callable}, in time order.
var _queue: Array[Dictionary] = []
var _lines: PackedStringArray = []


## Plays `layer`'s demo (one of HitJuice.LAYERS) on the nearest target; a running schedule is
## dropped first (its effects that already started play out).
func play(layer: StringName) -> void:
	_queue.clear()
	var target := _target()
	if target.is_empty():
		_set_lines(["%s: no slime in this world" % String(layer)])
		return
	var shape_id := _shape_id()
	var finisher := ShapeDefs.step(shape_id, ShapeDefs.step_count(shape_id) - 1)
	var whose := "the %s finisher's" % ShapeDefs.title(shape_id)
	match layer:
		HitJuice.LAYER_FREEZE:
			_demo_freeze(target, finisher, whose)
		HitJuice.LAYER_FLASH:
			_demo_flash(target, finisher, whose)
		HitJuice.LAYER_SQUASH:
			_demo_squash(target)
		HitJuice.LAYER_JITTER:
			_demo_jitter(target, finisher, whose)
		HitJuice.LAYER_TRAUMA:
			_demo_trauma(target, finisher, whose)
		HitJuice.LAYER_KICK:
			_demo_kick(target, finisher, whose)
		HitJuice.LAYER_SPARKS:
			_demo_sparks(target, finisher, whose)
		HitJuice.LAYER_PITCH:
			_demo_pitch(target, shape_id)
		HitJuice.LAYER_NUMBERS:
			_demo_numbers(target, shape_id, finisher, whose)
		HitJuice.LAYER_SLOWMO:
			_demo_slowmo(target)


## Runs the scheduled parts that are due (the panel calls it every frame).
func step() -> void:
	var now := _now()
	while not _queue.is_empty() and float(_queue[0]["at"]) <= now:
		var entry: Dictionary = _queue.pop_front()
		var run: Callable = entry["run"]
		if run.is_valid():
			run.call()


## What the last demo played: its real play, then its shown replay once that started.
func lines() -> PackedStringArray:
	return _lines


## Drops the schedule (what already plays keeps playing).
func cancel() -> void:
	_queue.clear()


# --- the demos ------------------------------------------------------------------------------------

## 1: the finisher's hit-stop holding the target's squash (its own jitter left out: that is key 4).
func _demo_freeze(target: Dictionary, finisher: Dictionary, whose: String) -> void:
	var ms := _stop_ms(finisher)
	var note := _note(HitJuice.LAYER_FREEZE)
	if note.is_empty() and not HitJuice.layer_on(HitJuice.LAYER_SQUASH):
		note = "  [squash is OFF: nothing moves to hold]"
	_squash(target, 1.0, 1.0, false)
	_freeze(ms)
	_set_lines(["1 freeze %d ms (%s), holding %s's squash%s" % [roundi(ms), whose, target["name"], note]])
	_later(ms + _squash_ms(target, 1.0) + SHOWN_DELAY_MS, func() -> void:
		_squash(target, 1.0, 1.0, false)
		_freeze(ms * SHOWN_SCALE)
		_add_line("   then %d ms (shown %s)" % [roundi(ms * SHOWN_SCALE), _times(SHOWN_SCALE)]))


## 2: the finisher's white-then-tint flash, then the same curve SHOWN_SCALE times as long.
func _demo_flash(target: Dictionary, finisher: Dictionary, whose: String) -> void:
	var big := HitJuice.is_big({"class": str(finisher.get("class", ""))})
	var white_ms := HitFlash.BIG_WHITE_MS if big else HitFlash.TAP_WHITE_MS
	var tint_ms := HitFlash.BIG_TINT_MS if big else HitFlash.TAP_TINT_MS
	var feel := Services.feel()
	var visual := _visual(target)
	if feel != null and visual != null:
		feel.flash_hit(visual, big)
	_set_lines(["2 flash: white %d ms, then the hurt tint over %d ms (%s) on %s%s" % [roundi(white_ms),
		roundi(tint_ms), whose, target["name"], _note(HitJuice.LAYER_FLASH)]])
	_later(white_ms + tint_ms + SHOWN_DELAY_MS, func() -> void:
		var shown_visual := _visual(target)
		if shown_visual != null and HitJuice.layer_on(HitJuice.LAYER_FLASH):
			HitFlash.flash_curve(shown_visual, HitFlash.HURT_TINT, big, white_ms * SHOWN_SCALE, tint_ms * SHOWN_SCALE)
		_add_line("   then %d + %d ms (shown %s)" % [roundi(white_ms * SHOWN_SCALE), roundi(tint_ms * SHOWN_SCALE),
			_times(SHOWN_SCALE)]))


## 3: the hold squash the target's weight plays (steps 1-2), then SHOWN_SCALE times as long and
## SHOWN_SIZE_SCALE times as deep.
func _demo_squash(target: Dictionary) -> void:
	var light := EnemyReactions.LIGHT_WEIGHTS.has(str(target["weight"]))
	_squash(target, 1.0, 1.0, true)
	_set_lines(["3 squash: the %s hold squash (%s, %d ms) on %s%s" % [str(target["weight"]),
		"elastic" if light else "%.2f / %.2f" % [EnemyReactions.MEDIUM_ALONG, EnemyReactions.MEDIUM_ACROSS],
		roundi(_squash_ms(target, 1.0)), target["name"], _note(HitJuice.LAYER_SQUASH)]])
	_later(_squash_ms(target, 1.0) + SHOWN_DELAY_MS, func() -> void:
		_squash(target, SHOWN_SCALE, SHOWN_SIZE_SCALE, true)
		_add_line("   then %d ms, %s as deep (shown %s)" % [roundi(_squash_ms(target, SHOWN_SCALE)),
			_times(SHOWN_SIZE_SCALE), _times(SHOWN_SCALE)]))


## 4: the target jitters while the finisher's freeze holds it (the jitter shows only in a freeze),
## then a jitter SHOWN_SIZE_SCALE times as wide through a freeze SHOWN_SCALE times as long.
func _demo_jitter(target: Dictionary, finisher: Dictionary, whose: String) -> void:
	var ms := _stop_ms(finisher)
	var note := _note(HitJuice.LAYER_JITTER)
	if note.is_empty() and not HitJuice.layer_on(HitJuice.LAYER_FREEZE):
		note = "  [it shows only in a freeze: freeze is OFF, Shift+%s]" % OS.get_keycode_string(
			HitJuice.key_for_layer(HitJuice.LAYER_FREEZE))
	_squash(target, 1.0, 1.0, true)
	_freeze(ms)
	_set_lines(["4 jitter: +-%d px while the %d ms freeze (%s) holds %s%s" % [roundi(EnemyHitMotion.JITTER_PX),
		roundi(ms), whose, target["name"], note]])
	_later(ms + _squash_ms(target, 1.0) + SHOWN_DELAY_MS, func() -> void:
		var shown_ms := ms * SHOWN_SCALE
		var motion := _motion(target)
		if motion != null:
			motion.play(EnemyHitMotion.JITTER, _direction(target),
				{"px": EnemyHitMotion.JITTER_PX * SHOWN_SIZE_SCALE, "ms": shown_ms})
		_freeze(shown_ms)
		_add_line("   then +-%d px for %d ms (shown %s)" % [roundi(EnemyHitMotion.JITTER_PX * SHOWN_SIZE_SCALE),
			roundi(shown_ms), _times(SHOWN_SCALE)]))


## 5: the finisher's camera trauma along the hit, then SHOWN_SCALE times it (the camera caps it at 1).
func _demo_trauma(target: Dictionary, finisher: Dictionary, whose: String) -> void:
	var trauma := ShapeDefs.num(finisher, "trauma")
	var shown := minf(1.0, trauma * SHOWN_SCALE)
	var feel := Services.feel()
	if feel != null:
		feel.add_trauma(trauma, _direction(target))
	_set_lines(["5 trauma %.2f (%s): the view shakes up to %.1f px%s" % [trauma, whose, _shake_px(trauma),
		_note(HitJuice.LAYER_TRAUMA)]])
	_later(_trauma_ms(trauma) + SHOWN_DELAY_MS, func() -> void:
		var shown_feel := Services.feel()
		if shown_feel != null:
			shown_feel.add_trauma(shown, _direction(target))
		_add_line("   then %.2f, up to %.1f px (shown %s, 1 at most)" % [shown, _shake_px(shown), _times(SHOWN_SCALE)]))


## 6: the finisher's camera kick along the hit, then SHOWN_SCALE times as far.
func _demo_kick(target: Dictionary, finisher: Dictionary, whose: String) -> void:
	var px := ShapeDefs.num(finisher, "kickPx")
	var feel := Services.feel()
	if feel != null:
		feel.kick(px, _direction(target))
	_set_lines(["6 kick %d px along the hit toward %s (%s)%s" % [roundi(px), target["name"], whose,
		_note(HitJuice.LAYER_KICK)]])
	_later(WorldCamera.KICK_OUT_MS + WorldCamera.KICK_RETURN_MS + SHOWN_DELAY_MS, func() -> void:
		var shown_feel := Services.feel()
		if shown_feel != null:
			shown_feel.kick(px * SHOWN_SCALE, _direction(target))
		_add_line("   then %d px (shown %s)" % [roundi(px * SHOWN_SCALE), _times(SHOWN_SCALE)]))


## 7: the finisher's sparks along the hit in the target's material tint, its impact ring and the
## material's debris (GameFeel.play_hit with every other part off), then SHOWN_SCALE times as many.
func _demo_sparks(target: Dictionary, finisher: Dictionary, whose: String) -> void:
	var sparks := int(ShapeDefs.num(finisher, "sparks"))
	var spec := _sparks_spec(target, finisher, 1.0)
	_play_spec(target, spec)
	var material := str(target["material"])
	_set_lines(["7 sparks: %d (%s) in a cone at %s, %s tint%s%s%s" % [sparks, whose, target["name"], material,
		", a ring" if bool(spec.get("impact_ring", false)) else "",
		", debris" if not str(spec.get("debris_preset", "")).is_empty() else "", _note(HitJuice.LAYER_SPARKS)]])
	var preset := StringName(str(spec.get("spark_preset", HitJuice.DEFAULT_SPARK_PRESET)))
	var life := float((ParticleFx.PRESETS.get(preset, {}) as Dictionary).get("lifespan_ms", 0.0))
	_later(life + SHOWN_DELAY_MS, func() -> void:
		_play_spec(target, _sparks_spec(target, finisher, SHOWN_SCALE))
		_add_line("   then %d (shown %s)" % [roundi(float(sparks) * SHOWN_SCALE), _times(SHOWN_SCALE)]))


## 8: the impact sound once per chain step at that step's pitch, PITCH_GAP_MS apart, rising; then the
## same with each step's rise above 1 x SHOWN_SCALE.
func _demo_pitch(target: Dictionary, shape_id: StringName) -> void:
	var pitches: Array[float] = []
	var cues: Array[StringName] = []
	for i in ShapeDefs.step_count(shape_id):
		var step_data := ShapeDefs.step(shape_id, i)
		pitches.append(ShapeDefs.num(step_data, "pitch", 1.0))
		var cue := StringName(str(step_data.get("soundCue", "")))
		cues.append(cue if not cue.is_empty() else HitJuice.IMPACT_CUE)
	var shown: Array[float] = []
	for pitch: float in pitches:
		shown.append(1.0 + (pitch - 1.0) * SHOWN_SCALE)
	_play_pitches(target, cues, pitches, 0.0)
	var note := _note(HitJuice.LAYER_PITCH)
	if not note.is_empty():
		note = "  [pitch is OFF, Shift+%s: every hit at the cue's own pitch]" % OS.get_keycode_string(
			HitJuice.key_for_layer(HitJuice.LAYER_PITCH))
	_set_lines(["8 pitch: the hit sound at %s (the %s chain's)%s" % [_list(pitches), ShapeDefs.title(shape_id), note]])
	var start := float(pitches.size()) * PITCH_GAP_MS + SHOWN_DELAY_MS
	_play_pitches(target, cues, shown, start)
	_later(start, func() -> void:
		_add_line("   then %s (shown %s)" % [_list(shown), _times(SHOWN_SCALE)]))


## 9: the finisher's damage number, big with its pop, then with its pop and life SHOWN_SCALE times as
## slow.
func _demo_numbers(target: Dictionary, shape_id: StringName, finisher: Dictionary, whose: String) -> void:
	var damage := roundi(ShapeDefs.damage(shape_id, ShapeDefs.num(finisher, "damageScale", 1.0)))
	var big := HitJuice.is_big({"class": str(finisher.get("class", ""))})
	var feel := Services.feel()
	if feel != null:
		feel.show_damage_number(_number_point(target), damage, big)
	var constants := Services.constants()
	var pop_scale := float(constants.value("combat.damageNumbers.popScale", 1.0)) if constants != null else 1.0
	var pop_ms := float(constants.value("combat.damageNumbers.popMs", 0.0)) if constants != null else 0.0
	_set_lines(["9 number %d (%s), %s: pops %.1fx -> 1x in %d ms over %s%s" % [damage, whose,
		"big" if big else "small", pop_scale, roundi(pop_ms), target["name"], _note(HitJuice.LAYER_NUMBERS)]])
	var life := FloatingTextLayer.BIG_DURATION_MS if big else FloatingTextLayer.SMALL_DURATION_MS
	_later(life + SHOWN_DELAY_MS, func() -> void:
		var shown_feel := Services.feel()
		if shown_feel != null:
			shown_feel.show_damage_number_scaled(_number_point(target), damage, big, SHOWN_SCALE)
		_add_line("   then the pop over %d ms (shown %s)" % [roundi(pop_ms * SHOWN_SCALE), _times(SHOWN_SCALE)]))


## 0: the room clear (GameFeel.room_clear: the music drop, the freeze, the stutter slow motion) while
## the target plays the launch tumble, so there is something to freeze and slow; then every length
## SHOWN_SCALE times as long.
func _demo_slowmo(target: Dictionary) -> void:
	var freeze_ms := _number("combat.roomClear.freezeMs")
	var slow_ms := _number("combat.roomClear.slowMs")
	var cycle := maxi(1, int(_number("combat.roomClear.slowCycleSteps")))
	var paused := clampi(int(_number("combat.roomClear.slowPausedSteps")), 0, cycle - 1)
	_tumble(target)
	var feel := Services.feel()
	if feel != null:
		feel.room_clear()
	_set_lines(["0 room clear: %d ms freeze, then %d ms at %d/%d speed, music -%d dB, on %s's tumble%s" % [
		roundi(freeze_ms), roundi(slow_ms), cycle - paused, cycle, roundi(_number("combat.roomClear.musicDropDb")),
		target["name"], _note(HitJuice.LAYER_SLOWMO)]])
	var tumble_ms := _number("combat.verbs.launch.stunMs") + EnemyHitMotion.LANDING_MS
	_later(maxf(freeze_ms + slow_ms, tumble_ms) + SHOWN_DELAY_MS, func() -> void:
		_tumble(target)
		var shown_feel := Services.feel()
		if shown_feel != null:
			shown_feel.room_clear_scaled(SHOWN_SCALE)
		_add_line("   then %d + %d ms (shown %s)" % [roundi(freeze_ms * SHOWN_SCALE), roundi(slow_ms * SHOWN_SCALE),
			_times(SHOWN_SCALE)]))


# --- the parts --------------------------------------------------------------------------------------

## A hit-stop of `ms` through GameFeel (as `play_hit` plays one, with its freeze switch).
func _freeze(ms: float) -> void:
	var feel := Services.feel()
	if feel != null and HitJuice.layer_on(HitJuice.LAYER_FREEZE):
		feel.hit_stop(ms)


## The finisher's per-swing hit-stop on one target, as `play_hit` caps it.
func _stop_ms(finisher: Dictionary) -> float:
	return HitJuice.hit_stop_ms(ShapeDefs.num(finisher, "hitStopMs"), 1, false)


## The target's hold squash (the reactions' numbers for its weight), its length x `length` and its
## depth x `depth`; `jitter`: whether it jitters while a freeze holds it.
func _squash(target: Dictionary, length: float, depth: float, jitter: bool) -> void:
	var motion := _motion(target)
	if motion != null:
		motion.play(EnemyHitMotion.SQUASH, _direction(target), _squash_params(target, length, depth, jitter))


func _squash_params(target: Dictionary, length: float, depth: float, jitter: bool) -> Dictionary:
	var wobble := float(target.get("wobble", 1.0))
	var params := {
		"nudge_px": _number("combat.verbs.hold.nudgePx") * depth,
		"nudge_ms": _number("combat.verbs.hold.nudgeMs") * length,
		"jitter": jitter,
	}
	if EnemyReactions.LIGHT_WEIGHTS.has(str(target["weight"])):
		params["amplitude"] = EnemyReactions.LIGHT_AMPLITUDE * wobble * depth
		params["elastic"] = true
		params["ms"] = EnemyHitMotion.ELASTIC_MS * length
	else:
		params["along"] = EnemyReactions.MEDIUM_ALONG
		params["across"] = EnemyReactions.MEDIUM_ACROSS
		params["amplitude"] = wobble * depth
		params["ms"] = EnemyHitMotion.SQUASH_MS * length
	return params


## How long the target's hold squash lasts at `length` x its own.
func _squash_ms(target: Dictionary, length: float) -> float:
	var params := _squash_params(target, length, 1.0, false)
	return maxf(float(params["ms"]), float(params["nudge_ms"]))


## The launch tumble on the target, as a launch plays it (`combat.verbs.launch`).
func _tumble(target: Dictionary) -> void:
	var motion := _motion(target)
	if motion != null:
		motion.play(EnemyHitMotion.TUMBLE, _direction(target), {"deg": _number("combat.verbs.launch.spinDeg"),
			"hop_px": _number("combat.verbs.launch.hopPx"), "ms": _number("combat.verbs.launch.stunMs")})


## The finisher's particles only (GameFeel.play_hit's sparks, ring and debris; no freeze, camera,
## sound or number), their counts x `count`.
func _sparks_spec(target: Dictionary, finisher: Dictionary, count: float) -> Dictionary:
	var big := HitJuice.is_big({"class": str(finisher.get("class", ""))})
	var spec := HitJuice.whiff_spec({})
	spec["sparks"] = roundi(ShapeDefs.num(finisher, "sparks") * count)
	spec["spark_preset"] = HitJuice.BIG_SPARK_PRESET if big else HitJuice.DEFAULT_SPARK_PRESET
	spec["tint"] = Color.WHITE
	spec["impact_ring"] = bool(finisher.get("impactRing", false))
	spec["dust"] = bool(finisher.get("debris", false))
	spec.merge(HitJuice.material_spec(str(target["material"]), big), true)
	spec["material_cue"] = &""
	spec["debris_scale"] = float(spec.get("debris_scale", 1.0)) * count
	return spec


## Plays `spec` at the target along the hit (GameFeel.play_hit).
func _play_spec(target: Dictionary, spec: Dictionary) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.play_hit(spec, _point(target), _direction(target))


## The impact sounds `cues[i]` at `pitches[i]`, PITCH_GAP_MS apart from `start_ms` on (GameFeel.play_hit's
## sounds: the pitch switch and the +-HitJuice.PITCH_VARIANCE as a hit plays them).
func _play_pitches(target: Dictionary, cues: Array[StringName], pitches: Array[float], start_ms: float) -> void:
	for i in pitches.size():
		var spec := HitJuice.whiff_spec({})
		spec["sound_cue"] = cues[i]
		spec["pitch"] = pitches[i]
		_later(start_ms + float(i) * PITCH_GAP_MS, func() -> void:
			_play_spec(target, spec))


# --- the target -------------------------------------------------------------------------------------

## The nearest training dummy or enemy (a receiver with a sprite, not defeated) whose hurtbox lies
## within DEMO_REACH_PX of the slime's centre, else the slime: {"node", "self", "name", "point" (its
## hurtbox centre when the demo started), "weight", "material", "wobble", "facing"}; {} without a slime.
func _target() -> Dictionary:
	var world := Services.world()
	var player: PlayerScript = world.player if world != null else null
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return {}
	var centre := player.get_centre()
	var facing := player.get_facing()
	if facing == Vector2.ZERO or not facing.is_finite():
		facing = Vector2.DOWN
	var best: Node = null
	var best_point := centre
	var best_distance := INF
	var router := Services.router()
	if router != null:
		for area: Area2D in AbilityWorld.hurtboxes_at(player, centre, DEMO_REACH_PX):
			var receiver := router.receiver_for_area(area) as Node
			if receiver == null or not receiver.has_method(&"get_visual"):
				continue
			if receiver.has_method(&"is_defeated") and bool(receiver.call(&"is_defeated")):
				continue
			var point := area.global_position
			if receiver.has_method(&"get_centre"):
				var at: Variant = receiver.call(&"get_centre")
				if at is Vector2:
					point = at
			var distance := point.distance_to(centre)
			if distance < best_distance:
				best = receiver
				best_point = point
				best_distance = distance
	if best == null:
		return {"node": player, "self": true, "name": "the slime", "point": centre, "weight": SELF_WEIGHT,
			"material": SELF_MATERIAL, "wobble": 1.0, "facing": facing}
	var profile := ReactionProfile.for_enemy(best)
	var wobble_raw: Variant = profile.get("wobbleScale", 1.0)
	return {"node": best, "self": false, "name": _name_of(best), "point": best_point,
		"weight": str(profile.get("weight", "")), "material": str(profile.get("material", "")),
		"wobble": float(wobble_raw) if (wobble_raw is float or wobble_raw is int) else 1.0, "facing": facing}


## "the light dummy" for a training dummy with a preset, else the enemy's type ("slime-spider").
static func _name_of(receiver: Node) -> String:
	var preset: Variant = receiver.get(&"reaction_preset")
	if receiver is TrainingDummyScript:
		return "the %s dummy" % preset if preset is String and not (preset as String).is_empty() else "the dummy"
	var type_id := ReactionProfile.type_of(receiver)
	return type_id if not type_id.is_empty() else String(receiver.name)


## The target's node while it is still in the world (null once it is gone).
func _node(target: Dictionary) -> Node:
	var raw: Variant = target.get("node")
	if not is_instance_valid(raw):
		return null
	var node := raw as Node
	return node if node != null and node.is_inside_tree() else null


## The target's sprite (the slime's Visual for the slime).
func _visual(target: Dictionary) -> Sprite2D:
	var node := _node(target)
	if node == null or not node.has_method(&"get_visual"):
		return null
	return node.call(&"get_visual") as Sprite2D


## The target's hit motion: an enemy's or dummy's own (EnemyReactions.motion_of), or for the slime a
## SELF_MOTION_NODE made on first use under the player script node on its Visual.
func _motion(target: Dictionary) -> EnemyHitMotion:
	var node := _node(target)
	if node == null:
		return null
	if not bool(target.get("self", false)):
		return EnemyReactions.motion_of(node)
	var existing := node.get_node_or_null(NodePath(SELF_MOTION_NODE)) as EnemyHitMotion
	if existing != null:
		return existing
	var visual := _visual(target)
	if visual == null:
		return null
	var motion := EnemyHitMotion.new()
	motion.name = SELF_MOTION_NODE
	node.add_child(motion)
	motion.setup(visual)
	return motion


## Where the target is now (its hurtbox centre; the slime's centre), else where it was.
func _point(target: Dictionary) -> Vector2:
	var node := _node(target)
	if node != null and node.has_method(&"get_centre"):
		var at: Variant = node.call(&"get_centre")
		if at is Vector2:
			return at
	return target.get("point", Vector2.ZERO)


## The hit's direction: from the slime's centre to the target, else the slime's facing.
func _direction(target: Dictionary) -> Vector2:
	var facing: Vector2 = target.get("facing", Vector2.DOWN)
	if bool(target.get("self", false)):
		return facing
	var world := Services.world()
	var player: PlayerScript = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return facing
	var to := _point(target) - player.get_centre()
	return to.normalized() if to.length_squared() > 0.0 else facing


## Where a hit's number starts: above the target as `play_hit` places it.
func _number_point(target: Dictionary) -> Vector2:
	return _point(target) - Vector2(0.0, Services.GameFeelType.HIT_NUMBER_RISE_PX)


## The slime's current shape (DEFAULT_SHAPE without a shape controller).
func _shape_id() -> StringName:
	var world := Services.world()
	var player: PlayerScript = world.player if world != null else null
	if player != null and is_instance_valid(player) and player.get_shapes() != null and is_instance_valid(player.get_shapes()):
		var id := player.get_shapes().current_shape_id()
		if ShapeDefs.is_shape(id):
			return id
	return DEFAULT_SHAPE


# --- text and timing --------------------------------------------------------------------------------

## Why `layer` would not show now ("" when it shows): its switch, reduce motion, the screen-shake
## slider, the Damage numbers setting.
func _note(layer: StringName) -> String:
	if not HitJuice.layer_on(layer):
		return "  [%s is OFF: Shift+%s]" % [String(layer), OS.get_keycode_string(HitJuice.key_for_layer(layer))]
	var feel := Services.feel()
	if feel == null:
		return ""
	if feel.reduce_motion and REDUCED_LAYERS.has(layer):
		return "  [reduce motion is on]"
	if (layer == HitJuice.LAYER_TRAUMA or layer == HitJuice.LAYER_KICK) and feel.screen_shake_scale <= 0.0:
		return "  [the screen-shake setting is 0]"
	if layer == HitJuice.LAYER_NUMBERS and not feel.show_damage_numbers:
		return "  [the Damage numbers setting is off]"
	return ""


## The trauma shake's largest offset (screen px) at `trauma` (`combat.trauma`, the shake slider).
func _shake_px(trauma: float) -> float:
	var feel := Services.feel()
	var slider := feel.screen_shake_scale if feel != null else 1.0
	return pow(minf(1.0, trauma * slider), _number("combat.trauma.exponent")) * _number("combat.trauma.maxOffsetPx")


## How long `trauma` takes to decay away (`combat.trauma.decayPerS`).
func _trauma_ms(trauma: float) -> float:
	var decay := _number("combat.trauma.decayPerS")
	return 1000.0 * trauma / decay if decay > 0.0 else 0.0


static func _times(scale: float) -> String:
	return ("%dx" % roundi(scale)) if is_equal_approx(scale, roundf(scale)) else ("%.1fx" % scale)


static func _list(values: Array[float]) -> String:
	var parts: PackedStringArray = []
	for value: float in values:
		parts.append("%.2f" % value)
	return " / ".join(parts)


func _set_lines(lines: Array) -> void:
	_lines = PackedStringArray(lines)
	revision += 1


func _add_line(line: String) -> void:
	_lines.append(line)
	revision += 1


## Runs `run` `delay_ms` real ms from now (the schedule stays in time order).
func _later(delay_ms: float, run: Callable) -> void:
	var at := _now() + maxf(0.0, delay_ms)
	var index := _queue.size()
	while index > 0 and float(_queue[index - 1]["at"]) > at:
		index -= 1
	_queue.insert(index, {"at": at, "run": run})


static func _number(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0


static func _now() -> float:
	return float(Time.get_ticks_msec())

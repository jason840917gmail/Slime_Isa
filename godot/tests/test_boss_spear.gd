extends RefCounted
## The bosses against the Spear at half damage (one combat, piece 6 of
## docs/design/2026-11-25-weapons-beside-throws.md, "What changes for bosses"): each fight's opening
## still holds the hits it was built for when the Spear's Lunge was a 25-damage energy power. A hit is
## worked out as the game does it: `ShapeDefs.damage` (the weapon scale in it) times the enemy's
## reaction multiplier (`HitReaction.damage_scale`: the part's, the phase's `damageTaken`) and its own
## script's share (the Shardback's brittle shell), rounded once as DamageResolver rounds it. The
## numbers the openings are measured against (health, rounds, the ram's blow) are the fights' own,
## named where they live.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const ReactionState := preload("res://game/combat/reactions/reaction_state.gd")
const PatternedEnemy := preload("res://game/enemy/patterned_enemy.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")

const SPEAR_TAGS := ["weapon", "spear"]
## Fatty One Eye's health (fatty-one-eye.tscn `max_health`) and the share where phase two starts
## (fatty.gd `phase_two_health_share`): each phase is half of it, one hit an opening.
const FATTY_HEALTH := 140.0
const FATTY_PHASE_SHARE := 0.5
## The Matron's ram fight: round 1 from 300 to her floor of 200, round 2 from 200 to 25
## (orb-weaver-matron-rework.tscn, matron.gd `round_floor`), two rams' blows on her in round 2
## (matron_ram.gd `ram_blow_damage`, 20).
const MATRON_ROUND_ONE := 100.0
const MATRON_ROUND_TWO := 175.0
const MATRON_RAM_BLOW := 20.0


## Fatty: a Lunge on his open eye is the 25 it was, so each phase takes three openings as before; a
## thrown thing stays half a Spear base hit (fatty.gd computes it apart from the multiplier).
func test_fattys_eye_takes_the_lunge_it_took(t: TestContext) -> void:
	var profile := ReactionProfile.for_type("fatty-one-eye")
	var lunge := _hit(profile, "charge", _lunge_scale(), "eye", "chase")
	t.equal(lunge, 25, "a Lunge on his open eye")
	t.equal(ceili(FATTY_HEALTH * FATTY_PHASE_SHARE / float(lunge)), 3, "Lunges (openings) a phase")
	t.equal(_hit(profile, "tap", _tap_scale(0), "eye", "chase"), 14, "a jab on his open eye")
	await t.steps(1)


## The Big Squint: one combo an opening (its finisher knocks it back and the visor shuts), three
## openings for its 96 health. A thrown thing hurts it open again (owner, 2026-11-26), lifted by the same
## `open` share: two light throws, one heavy.
func test_the_big_squint_falls_in_three_openings(t: TestContext) -> void:
	var profile := ReactionProfile.for_type("big-squint")
	var combo := _combo(profile, "", "open")
	var health := float(_type_number("big-squint", "maxHp"))
	t.check(combo * 3 >= health, "three combos (%d each) do not beat its %.0f health" % [combo, health])
	t.check(combo * 2 < health, "two combos (%d each) already beat its %.0f health" % [combo, health])
	var light := _throw(profile, "light", "open")
	t.check(light * 2 >= health and light < health, "light throws of %d for %.0f health" % [light, health])
	t.check(_throw(profile, "heavy", "open") >= health, "a heavy throw does not end it")
	t.equal(_throw(profile, "light", "walk"), 0, "a throw on its shut visor")
	await t.steps(1)


## The Matron: round 1 in one open window of three combos (4 s), round 2 still two ram catches.
func test_the_matrons_rounds_keep_their_openings(t: TestContext) -> void:
	var profile := ReactionProfile.for_type("orb-weaver-matron")
	var combo := _combo(profile, "", "fight")
	var jab := _hit(profile, "tap", _tap_scale(0), "", "fight")
	t.check(combo * 3 >= MATRON_ROUND_ONE, "three combos (%d each) do not end round 1" % combo)
	t.check(MATRON_ROUND_TWO - 2.0 * MATRON_RAM_BLOW > combo * 3 + jab, "one catch's window (three combos and a jab) ends round 2")
	await t.steps(1)


## The Brood Warden: a combo in each 1.2 s plant, three plants for his 120 health (two Lunges a plant
## did it before); knocked flat by the ram (`pattern.ramDamage`), two combos and two jabs in its 3 s
## end him.
func test_the_brood_warden_keeps_three_plants(t: TestContext) -> void:
	var profile := ReactionProfile.for_type("brood-warden")
	var health := float(_type_number("brood-warden", "maxHp"))
	var combo := _combo(profile, "", "planted")
	t.check(combo * 3 >= health and combo * 2 < health, "plants for %.0f health at %d a combo" % [health, combo])
	var knocked := _combo(profile, "", "knocked") * 2 + _hit(profile, "tap", _tap_scale(0), "", "knocked") \
		+ _hit(profile, "tap", _tap_scale(1), "", "knocked")
	var ram := float(PatternedEnemy.pattern_block("brood-warden").get("ramDamage", 0.0))
	t.check(ram + knocked >= health, "the ram (%.0f) and a knock's hits (%d) do not end him" % [ram, knocked])
	await t.steps(1)


## The Shardback: brittle, seven jabs (two combos and one) end its 140 health inside a Lantern's
## window; cold, its shell refuses the Spear (a clink at the material gate).
func test_the_brittle_shardback_falls_in_one_window(t: TestContext) -> void:
	var profile := ReactionProfile.for_type("shardback")
	var share := PatternedEnemy.pattern_block("shardback").get("brittleDamageTaken", 1.0) as float
	var taps: Array[int] = []
	for i in 7:
		taps.append(_hit(profile, "tap", _tap_scale(i % 3), "", "brittle", share))
	var total := 0
	for tap: int in taps:
		total += tap
	var health := float(_type_number("shardback", "maxHp"))
	t.check(total >= health, "seven brittle jabs %s do not beat %.0f" % [str(taps), health])
	var jab := HitReaction.build_hit("tap", {"shape": "spear", "tags": SPEAR_TAGS})
	t.equal(HitReaction.material_gate(profile, jab, ""), HitReaction.GATE_CLINK, "a jab on its cold shell")
	await t.steps(1)


# --- helpers ----------------------------------------------------------------------------------------

## A Spear hit of `hit_class` at `scale` on `profile` in `part` and `phase`, times the script's own
## `share`, rounded as DamageResolver rounds it.
static func _hit(profile: Dictionary, hit_class: String, scale: float, part: String, phase: String,
		share: float = 1.0) -> int:
	var hit := HitReaction.build_hit(hit_class, {"shape": "spear", "tags": SPEAR_TAGS})
	var state := ReactionState.new()
	state.part = part
	state.phase = phase
	var multiplier := HitReaction.damage_scale(profile, hit, state, Services.now_ms())
	return roundi(ShapeDefs.damage(ShapeDefs.SPEAR, scale) * multiplier * share)


## A whole Spear combo (jab, jab, lunging jab) on `profile`.
static func _combo(profile: Dictionary, part: String, phase: String) -> int:
	var total := 0
	for i in ShapeDefs.step_count(ShapeDefs.SPEAR):
		total += _hit(profile, "finisher" if i == ShapeDefs.step_count(ShapeDefs.SPEAR) - 1 else "tap",
			_tap_scale(i), part, phase)
	return total


## A thrown clay pot of `weight` on `profile` in `phase`, as the throw deals it (the light throw's damage
## times the weight's share) times the reaction multiplier; 0 through a shut gate.
static func _throw(profile: Dictionary, weight: String, phase: String) -> int:
	var hit_class := "thrown" if weight == "light" else "thrown-" + weight
	var hit := HitReaction.build_hit(hit_class, {"tags": ["thrown", "clay-pot"]})
	var state := ReactionState.new()
	state.phase = phase
	if HitReaction.gate(profile, hit, state) == HitReaction.GATE_CLINK:
		return 0
	var multiplier := HitReaction.damage_scale(profile, hit, state, Services.now_ms())
	return roundi(ThrowFeel.base_damage() * ThrowMode.weight_number(weight, "damageScale") * multiplier)


static func _tap_scale(index: int) -> float:
	return ShapeDefs.num(ShapeDefs.step(ShapeDefs.SPEAR, index), "damageScale", 1.0)


static func _lunge_scale() -> float:
	return ShapeDefs.num(ShapeDefs.charge(ShapeDefs.SPEAR), "damageScale", 1.0)


## A top-level number of `type_id` in enemy-types.json (0 when none).
static func _type_number(type_id: String, key: String) -> float:
	var data: Variant = Services.constants().data_file(PatternedEnemy.ENEMY_TYPES_FILE)
	var types: Variant = (data as Dictionary).get("types", {}) if data is Dictionary else {}
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	return float((entry as Dictionary).get(key, 0.0)) if entry is Dictionary else 0.0

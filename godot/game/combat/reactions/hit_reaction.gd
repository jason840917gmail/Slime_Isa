extends RefCounted
## The one shared reaction function (combat-feel plan section 3 "The hit model", section 5 "Enemy
## reaction profiles" and section 7 "Anti-frustration rules"; contract: docs/godot/BODY_SHAPES.md
## "The hit" and "The reaction").
##
## - `decide(profile, hit, state, now_ms)`: what one rework hit does to an enemy with that reaction
##   profile (ReactionProfile.for_enemy) and memory (ReactionState), in the plan's order:
##   1. clink (an immune class, or a shut hurtbox gate; a gated hit the profile maps to daze or
##      knockdown still lands, with 0 damage: `gate`),
##   2. the wake guard and the break-free armor (damage and a flash only),
##   3. the phase's armor (a hit of that tier or lower is armor),
##   4. the class verb (`byTag`, then the phase's `classes`, then the enemy's `classes`, which hold the
##      weight defaults under the type's own),
##   5. poise (a class's armor drains it, a phase's armor does not; at 0 the `breakVerb`, and the
##      pool fills again),
##   6. the owner's rule (a hit that is not `last` never moves the body: knockback and launch become
##      a hold),
##   7. the hold cap (the hold after `holdCap` holds in a row is the break-free move; the count
##      clears once the enemy has stood free `combat.rules.holdResetFreeMs` after its last hold),
##   8. apply to the memory (the longer stun wins; the wake guard after a launch, a knockback or a
##      break-free; the hold count clears on a launch).
##   It writes the memory (`state`) and never touches the world: EnemyReactions applies the answer
##   (moves, stuns, attack cancels, motions). `preview` decides on a copy of the memory.
## - `gate` and `damage_scale`: the clink and the damage multipliers (part `damageTaken`, the
##   phase's `damageTaken`, a knockdown's `damageTaken`) that `can_receive_damage` and
##   `mitigate_damage` need before the hit is committed.
## - The hit builders every rework sender uses (shapes, the Slam, thrown objects, the Roll):
##   `build_hit` fills a `hit` Dictionary from `combat.hits[class]` with the contract's defaults,
##   `attach` puts it on a DamageRouter request with the `impact` effect (so a 0-damage hit is still
##   accepted and reaches the reaction), `hit_of` reads it back.
##
## Owner: reactions.

const Services := preload("res://game/shared/services.gd")
const ReactionState := preload("res://game/combat/reactions/reaction_state.gd")

## The effect every rework hit carries instead of the old `knockback` (combat-feel plan section 3).
const IMPACT_EFFECT_ID := "impact"
## Verbs (`result.reaction.verb`; combat-feel plan section 3 "What the enemy answers").
const VERB_HOLD := "hold"
const VERB_BOUNCE := "bounce"
const VERB_KNOCKBACK := "knockback"
const VERB_LAUNCH := "launch"
const VERB_STAGGER := "stagger"
const VERB_KNOCKDOWN := "knockdown"
const VERB_DAZE := "daze"
const VERB_ARMOR := "armor"
const VERB_CLINK := "clink"
const VERB_PULLED := "pulled"
const VERB_RESIST := "resist"
const VERB_BOWL := "bowl"
const VERB_BONK := "bonk"
const VERB_BREAK := "break"
const VERB_POP := "pop"
## The hold cap's break-free move (the reaction's `move` names it: push, counter-slash, hop-back,
## skitter, skitter-spit).
const VERB_BREAK_FREE := "break-free"
## What the attacker feels (`result.reaction.slime`).
const SLIME_NONE := "none"
const SLIME_RECOIL := "recoil"
const SLIME_BOUNCE := "bounce"
const SLIME_PASS := "pass"
const SLIME_BREAK := "break"
## `gate` answers: the hit lands; it clinks; the gate is shut but its daze or knockdown lands with 0
## damage.
const GATE_OPEN := "open"
const GATE_CLINK := "clink"
const GATE_ZERO := "zero"
## Break-free moves (profile `breakFree`).
const MOVE_PUSH := "push"
const MOVE_COUNTER := "counter-slash"
const MOVE_HOP_BACK := "hop-back"
const MOVE_SKITTER := "skitter"
const MOVE_SKITTER_SPIT := "skitter-spit"
## Impact classes read by name.
const CLASS_FINISHER := "finisher"
const CLASS_ROLL := "roll"
const CLASS_SUCK := "suck"
## Profile `roll` and `suck` answers.
const ROLL_BOWL := "bowl"
const ROLL_BONK := "bonk"
const ROLL_BREAK := "break"
const SUCK_PULLED := "pulled"
const SUCK_RESIST := "resist"
## The weight whose kills pop.
const WEIGHT_TINY := "tiny"
## `immune` wildcard: every class.
const ANY_CLASS := "*"
## Verbs that move the body (only a `last` hit may send one).
const MOVING_VERBS: Array[String] = [VERB_KNOCKBACK, VERB_LAUNCH, VERB_BOWL]
## Verbs after which the wake guard runs (the enemy always gets a turn).
const WAKE_VERBS: Array[String] = [VERB_KNOCKBACK, VERB_LAUNCH, VERB_BOWL, VERB_BONK]
## Verbs that stop or move the enemy and cancel its attack (everything but armor, clink and the
## suck's resist; the break-free move cancels its own way).
const STUN_VERBS: Array[String] = [VERB_HOLD, VERB_BOUNCE, VERB_KNOCKBACK, VERB_LAUNCH, VERB_STAGGER,
	VERB_KNOCKDOWN, VERB_DAZE, VERB_PULLED, VERB_BOWL, VERB_BONK]


## What `hit` does to an enemy with `profile` (ReactionProfile.for_enemy) and `state` (its
## ReactionState, with `phase` and `part` already set for this hit) at `now_ms`: a reaction
## Dictionary (`reaction()`) plus, when they apply, "move" (the break-free move), "guarded" (the
## wake guard or the break-free armor turned it into armor), "poise_broken", "damage_taken" (a
## knockdown's multiplier), "slide_px" (the suck's resist) and "gate" (GATE_ZERO: it lands with 0
## damage). Writes the memory (see the file comment).
static func decide(profile: Dictionary, hit: Dictionary, state: RefCounted, now_ms: float) -> Dictionary:
	var memory := state as ReactionState
	if memory == null:
		memory = ReactionState.new()
	var rules := _dictionary("combat.rules")
	var hit_class := str(hit.get("class", ""))
	_refill_poise(profile, memory, rules, now_ms)
	memory.last_hit_ms = now_ms
	# A new chain re-arms the wall splat only once the enemy is free (no stun, no wake guard): a chain
	# started in a splat's daze cannot splat it again, and its launch keeps the normal wake guard.
	if int(hit.get("step", 0)) <= 1 and not memory.in_stun(now_ms) and now_ms >= memory.wake_until_ms:
		memory.splats_this_chain = 0
	var phase := phase_entry(profile, memory.phase)
	# 1. Clink.
	var gated := gate(profile, hit, memory)
	if gated == GATE_CLINK:
		return reaction(VERB_CLINK, 0.0, SLIME_RECOIL, _number("combat.chain.clink.recoilPx"))
	# The suck never pulls a live enemy unless its profile says so (owner, 2026-10-11).
	if hit_class == CLASS_SUCK:
		return _suck(profile)
	# 2. The wake guard and the break-free armor: damage and a flash, nothing more.
	if now_ms < memory.wake_until_ms or now_ms < memory.armor_until_ms:
		var guarded := _with_slime(reaction(VERB_ARMOR), hit, profile)
		guarded["guarded"] = true
		return guarded
	# 3. The phase's armor, else 4. the class verb.
	var entry: Dictionary
	var armor := int(phase.get("armor", 0))
	var phase_armor := armor > 0 and int(hit.get("tier", 1)) <= armor
	if phase_armor:
		entry = {"verb": VERB_ARMOR}
	else:
		entry = class_entry(profile, hit, phase)
	var verb := str(entry.get("verb", VERB_HOLD))
	# The Roll's outcome is the profile's `roll` (bowl, bonk or break); armor turns it into a break.
	if hit_class == CLASS_ROLL:
		verb = VERB_BREAK if verb == VERB_ARMOR else str(profile.get("roll", ROLL_BONK))
	# 5. Poise (the class's armor drains it; a phase's armor, such as the Clod's crouch and hop, is
	# all armor and leaves the pool alone).
	var poise_broken := false
	if verb == VERB_ARMOR and not phase_armor:
		var broken := _drain_poise(profile, hit, memory, rules, now_ms)
		if not broken.is_empty():
			entry = broken
			verb = str(entry.get("verb", VERB_STAGGER))
			poise_broken = true
	# 6. The owner's rule: a hit that is not `last` never moves the body.
	if not bool(hit.get("last", true)) and MOVING_VERBS.has(verb):
		verb = VERB_HOLD
		entry = {"verb": VERB_HOLD}
	# 7. The hold cap. Holds in a row count; the count clears once the enemy has stood free for
	# `holdResetFreeMs` after its last counted hold ended (measured from the hold's end, so a hold as
	# long as the gap between spaced jabs cannot hide the lock).
	var move := ""
	var counted := false
	if verb == VERB_HOLD and _counts_hold(hit, phase, memory, now_ms):
		if now_ms > memory.hold_until_ms + float(rules.get("holdResetFreeMs", 0.0)):
			memory.hold_count = 0
		memory.hold_count += 1
		memory.last_hold_ms = now_ms
		counted = true
		if memory.hold_count > int(profile.get("holdCap", rules.get("holdCap", 0))):
			memory.hold_count = 0
			verb = VERB_BREAK_FREE
			move = str(profile.get("breakFree", MOVE_PUSH))
	# 8. Apply to the memory.
	var stun := _stun_ms(verb, entry, hit, profile, rules)
	if counted and verb == VERB_HOLD:
		memory.hold_until_ms = maxf(memory.hold_until_ms, maxf(memory.stun_until_ms, now_ms + stun))
	var answer := _with_slime(reaction(verb, stun), hit, profile)
	if poise_broken:
		answer["poise_broken"] = true
	if gated == GATE_ZERO:
		answer["gate"] = GATE_ZERO
	if verb == VERB_BREAK_FREE:
		answer["move"] = move
		_remember_break_free(memory, move, stun, rules, now_ms)
		return answer
	if stun > 0.0:
		var until := now_ms + stun
		if until >= memory.stun_until_ms or not memory.in_stun(now_ms):
			memory.verb = verb
			memory.stun_until_ms = until
			memory.damage_taken = 1.0
			if verb == VERB_KNOCKDOWN:
				memory.damage_taken = float(entry.get("damageTaken", _number("combat.verbs.knockdown.damageTaken")))
	if verb == VERB_KNOCKDOWN:
		answer["damage_taken"] = memory.damage_taken
	if WAKE_VERBS.has(verb):
		# The guard starts when the stun in force ends (a daze may outlast the launch).
		memory.hold_count = 0
		memory.wake_until_ms = maxf(memory.wake_until_ms,
			maxf(memory.stun_until_ms, now_ms + stun) + float(rules.get("wakeGuardMs", 0.0)))
	if verb == VERB_LAUNCH or verb == VERB_BOWL:
		memory.launched_at_ms = now_ms
		memory.launch_until_ms = now_ms + stun
		memory.bowled.clear()
	return answer


## `decide` on a copy of `state`: the answer without changing the memory.
static func preview(profile: Dictionary, hit: Dictionary, state: RefCounted, now_ms: float) -> Dictionary:
	var memory := state as ReactionState
	return decide(profile, hit, memory.copy() if memory != null else ReactionState.new(), now_ms)


## Whether `hit` gets through: GATE_CLINK when its class is immune (the profile's `immune` or the
## phase's; "*" = all), or the part it landed on (`state.part`, the profile's `parts`) is shut (its
## `tags` must all be on the hit, and its `open` phases must hold the current one) and the class verb
## is neither daze nor knockdown; GATE_ZERO when the part is shut but the verb is daze or knockdown
## (it lands with 0 damage); else GATE_OPEN.
static func gate(profile: Dictionary, hit: Dictionary, state: RefCounted) -> String:
	var memory := state as ReactionState
	var phase_name := memory.phase if memory != null else ""
	var hit_class := str(hit.get("class", ""))
	var phase := phase_entry(profile, phase_name)
	if _listed(profile.get("immune", []), hit_class) or _listed(phase.get("immune", []), hit_class):
		return GATE_CLINK
	var part := part_entry(profile, memory.part if memory != null else "")
	if part.is_empty() or part_open(part, hit, phase_name):
		return GATE_OPEN
	var verb := str(class_entry(profile, hit, phase).get("verb", ""))
	return GATE_ZERO if verb == VERB_DAZE or verb == VERB_KNOCKDOWN else GATE_CLINK


## The damage multiplier of `hit` on the enemy now: 0 through a shut gate (GATE_ZERO), times the
## part's `damageTaken`, the phase's `damageTaken` and, while a knockdown is in force, its
## `damageTaken`.
static func damage_scale(profile: Dictionary, hit: Dictionary, state: RefCounted, now_ms: float) -> float:
	var memory := state as ReactionState
	if memory == null:
		return 1.0
	if gate(profile, hit, memory) == GATE_ZERO:
		return 0.0
	var scale := 1.0
	scale *= _finite(part_entry(profile, memory.part).get("damageTaken", 1.0), 1.0)
	scale *= _finite(phase_entry(profile, memory.phase).get("damageTaken", 1.0), 1.0)
	if memory.in_stun(now_ms, VERB_KNOCKDOWN):
		scale *= memory.damage_taken
	return maxf(0.0, scale)


## The profile's `states[phase]` ({} for the normal phase or an unknown one).
static func phase_entry(profile: Dictionary, phase: String) -> Dictionary:
	if phase.is_empty():
		return {}
	var states: Variant = profile.get("states", {})
	var entry: Variant = (states as Dictionary).get(phase, {}) if states is Dictionary else {}
	return entry if entry is Dictionary else {}


## The profile's `parts[part]` ({} when the hurtbox is no part).
static func part_entry(profile: Dictionary, part: String) -> Dictionary:
	if part.is_empty():
		return {}
	var parts: Variant = profile.get("parts", {})
	var entry: Variant = (parts as Dictionary).get(part, {}) if parts is Dictionary else {}
	return entry if entry is Dictionary else {}


## Whether a part's gate lets `hit` through in `phase`: every tag of its `tags` is on the hit, and
## `phase` is one of its `open` phases (when it lists them).
static func part_open(part: Dictionary, hit: Dictionary, phase: String) -> bool:
	var tags: Variant = part.get("tags", [])
	if tags is Array:
		var hit_tags: Variant = hit.get("tags", [])
		for tag: Variant in tags:
			if not (hit_tags is Array and (hit_tags as Array).has(str(tag))):
				return false
	var open: Variant = part.get("open")
	if open is Array and not (open as Array).has(phase):
		return false
	return true


## The class verb entry ({"verb", "stunMs"?, "damageTaken"?}) of `hit`: `byTag` (a tag's verb, or
## its own class table), then the phase's `classes`, then the enemy's `classes` (weight defaults
## under the type's own); with none, a last hit knocks back and any other holds.
static func class_entry(profile: Dictionary, hit: Dictionary, phase: Dictionary) -> Dictionary:
	var hit_class := str(hit.get("class", ""))
	var by_tag: Variant = profile.get("byTag", {})
	var tags: Variant = hit.get("tags", [])
	if by_tag is Dictionary and tags is Array:
		for tag: Variant in tags:
			if not (by_tag as Dictionary).has(str(tag)):
				continue
			var found := _tag_entry((by_tag as Dictionary)[str(tag)], hit_class)
			if not found.is_empty():
				return found
	for table: Variant in [phase.get("classes", {}), profile.get("classes", {})]:
		if table is Dictionary and (table as Dictionary).has(hit_class):
			var found := _entry((table as Dictionary)[hit_class])
			if not found.is_empty():
				return found
	return {"verb": VERB_KNOCKBACK if bool(hit.get("last", true)) else VERB_HOLD}


## The `result.reaction` Dictionary (BODY_SHAPES.md "The reaction").
static func reaction(verb: String, stun_ms: float = 0.0, slime: String = SLIME_NONE, recoil_px: float = 0.0,
		feel: Dictionary = {}) -> Dictionary:
	return {"verb": verb, "stun_ms": stun_ms, "slime": slime, "recoil_px": recoil_px, "feel": feel}


## A `hit` Dictionary of impact class `hit_class` (tap, finisher, smash, charge, ring, slam, thrown,
## roll, suck): `tier`, `poise` and `counts_as_hold` from `combat.hits[hit_class]`, every other
## field at its contract default, then `fields` on top (a step may override tier and poise).
static func build_hit(hit_class: String, fields: Dictionary = {}) -> Dictionary:
	var constants := Services.constants()
	var row: Variant = constants.value("combat.hits.%s" % hit_class, {}) if constants != null else {}
	var table: Dictionary = row if row is Dictionary else {}
	var hit := {
		"class": hit_class,
		"step": 0,
		"last": true,
		"tier": int(table.get("tier", 1)),
		"poise": int(table.get("poise", 0)),
		"shape": "",
		"tags": [],
		"hold_ms": 0.0,
		"launch_speed": 0.0,
		"hop_px": 0.0,
		"knock": Vector2.ZERO,
		"counts_as_hold": bool(table.get("countsAsHold", true)),
		"attacker": "player",
	}
	hit.merge(fields, true)
	return hit


## The impact effect a rework request carries (potency 1).
static func impact_effect() -> Dictionary:
	return {"effect_id": IMPACT_EFFECT_ID, "potency": 1.0}


## Puts `hit` on `request` (top level, never inside `impact`) and adds the impact effect once;
## returns `request`.
static func attach(request: Dictionary, hit: Dictionary) -> Dictionary:
	request["hit"] = hit
	var effects: Array = []
	var raw: Variant = request.get("effects", [])
	if raw is Array:
		effects = (raw as Array).duplicate()
	for effect: Variant in effects:
		if effect is Dictionary and str((effect as Dictionary).get("effect_id", "")) == IMPACT_EFFECT_ID:
			request["effects"] = effects
			return request
	effects.append(impact_effect())
	request["effects"] = effects
	return request


## The request's `hit` ({} for an old-style request).
static func hit_of(request: Dictionary) -> Dictionary:
	var hit: Variant = request.get("hit")
	return hit if hit is Dictionary else {}


# --- private ---------------------------------------------------------------------------------

## The suck's answer from the profile's `suck`: pulled holds it `combat.verbs.pulled.holdMs`;
## resist slides it back `combat.verbs.resist.slidePx`; "none" (everyone, owner 2026-10-11) is a
## resist that does not move.
static func _suck(profile: Dictionary) -> Dictionary:
	match str(profile.get("suck", "none")):
		SUCK_PULLED:
			return reaction(VERB_PULLED, _number("combat.verbs.pulled.holdMs") * _stun_scale(profile))
		SUCK_RESIST:
			var resisted := reaction(VERB_RESIST)
			resisted["slide_px"] = _number("combat.verbs.resist.slidePx")
			return resisted
	var still := reaction(VERB_RESIST)
	still["slide_px"] = 0.0
	return still


## The finisher's recoil (`combat.chain.finisherRecoilPx`) and the Roll's slime outcome.
static func _with_slime(answer: Dictionary, hit: Dictionary, profile: Dictionary) -> Dictionary:
	var hit_class := str(hit.get("class", ""))
	if hit_class == CLASS_FINISHER:
		answer["slime"] = SLIME_RECOIL
		answer["recoil_px"] = _number("combat.chain.finisherRecoilPx")
	elif hit_class == CLASS_ROLL:
		match str(answer.get("verb", "")):
			VERB_BOWL:
				answer["slime"] = SLIME_PASS
			VERB_BONK:
				answer["slime"] = SLIME_BOUNCE
			VERB_BREAK:
				answer["slime"] = SLIME_BREAK
				answer["recoil_px"] = _number("combat.chain.clink.recoilPx") * _finite(profile.get("rollBounceScale", 1.0), 1.0)
	return answer


## How long `verb` stuns, x the profile's `hitstunScale` (the break-free move's time is its armor).
static func _stun_ms(verb: String, entry: Dictionary, hit: Dictionary, profile: Dictionary, rules: Dictionary) -> float:
	var scale := _stun_scale(profile)
	var given := _finite(entry.get("stunMs", 0.0), 0.0)
	match verb:
		VERB_HOLD, VERB_BOUNCE:
			var hold := _finite(hit.get("hold_ms", 0.0), 0.0)
			if hold <= 0.0:
				hold = given if given > 0.0 else _number("combat.verbs.knockback.stunMs")
			return hold * scale
		VERB_KNOCKBACK, VERB_BONK:
			var bonk_daze := _finite(profile.get("rollDazeMs", 0.0), 0.0) if verb == VERB_BONK else 0.0
			return maxf(bonk_daze, given if given > 0.0 else _number("combat.verbs.knockback.stunMs")) * scale
		VERB_LAUNCH, VERB_BOWL:
			return (given if given > 0.0 else _number("combat.verbs.launch.stunMs")) * scale
		VERB_STAGGER:
			return (given if given > 0.0 else _number("combat.verbs.stagger.stunMs")) * scale
		VERB_KNOCKDOWN:
			return (given if given > 0.0 else _number("combat.verbs.knockdown.stunMs")) * scale
		VERB_DAZE:
			return (given if given > 0.0 else _number("combat.verbs.daze.stunMs")) * scale
		VERB_PULLED:
			return _number("combat.verbs.pulled.holdMs") * scale
		VERB_BREAK_FREE:
			return float(rules.get("breakFreeArmorMs", 0.0))
	return 0.0


## The profile's `hitstunScale` (1 when missing or not positive).
static func _stun_scale(profile: Dictionary) -> float:
	var scale := _finite(profile.get("hitstunScale", 1.0), 1.0)
	return scale if scale > 0.0 else 1.0


## Whether a hold counts toward the cap: it `counts_as_hold` (not a ring, a throw or the suck) and
## it lands outside a daze, a knockdown and an open phase (a phase entry with `open`, or with its own
## `classes`), whose own timers end those holds.
static func _counts_hold(hit: Dictionary, phase: Dictionary, memory: ReactionState, now_ms: float) -> bool:
	if not bool(hit.get("counts_as_hold", true)):
		return false
	if bool(phase.get("open", phase.has("classes"))):
		return false
	return not memory.in_stun(now_ms, VERB_DAZE) and not memory.in_stun(now_ms, VERB_KNOCKDOWN)


## The break-free move's memory: the armor for `stun` ms (`combat.rules.breakFreeArmorMs`), then the
## wake guard; the push, hop-back and skitter stun the enemy while they slide (the counter-slash
## acts at once).
static func _remember_break_free(memory: ReactionState, move: String, stun: float, rules: Dictionary, now_ms: float) -> void:
	memory.armor_until_ms = now_ms + stun
	memory.wake_until_ms = maxf(memory.wake_until_ms, now_ms + stun + float(rules.get("wakeGuardMs", 0.0)))
	if move != MOVE_COUNTER:
		memory.verb = VERB_BREAK_FREE
		memory.stun_until_ms = maxf(memory.stun_until_ms, now_ms + stun)


## Poise refills `combat.rules.poiseRegenPerS` per second after `poiseRegenDelayMs` without a hit;
## the first hit fills it from the profile.
static func _refill_poise(profile: Dictionary, memory: ReactionState, rules: Dictionary, now_ms: float) -> void:
	var pool := _finite(profile.get("poise", 0.0), 0.0)
	if pool <= 0.0:
		return
	if memory.poise < 0.0 or not is_finite(memory.last_hit_ms):
		memory.poise = pool
		return
	var idle_ms := now_ms - memory.last_hit_ms - float(rules.get("poiseRegenDelayMs", 0.0))
	if idle_ms > 0.0:
		memory.poise = minf(pool, memory.poise + idle_ms / 1000.0 * float(rules.get("poiseRegenPerS", 0.0)))


## An armor hit drains the hit's `poise`; at 0 the profile's `breakVerb` (default a stagger of
## `combat.rules.poiseBreakMs`) plays and the pool fills again. Returns that entry, or {} while the
## pool holds (or during a stagger already in force, so a poise break cannot be chained).
static func _drain_poise(profile: Dictionary, hit: Dictionary, memory: ReactionState, rules: Dictionary,
		now_ms: float) -> Dictionary:
	var pool := _finite(profile.get("poise", 0.0), 0.0)
	if pool <= 0.0 or memory.in_stun(now_ms, VERB_STAGGER):
		return {}
	memory.poise -= _finite(hit.get("poise", 0.0), 0.0)
	if memory.poise > 0.0:
		return {}
	memory.poise = pool
	var broken := _entry(profile.get("breakVerb", {}))
	if broken.is_empty():
		broken = {"verb": VERB_STAGGER, "stunMs": float(rules.get("poiseBreakMs", 0.0))}
	return broken


## A class table value as an entry: "verb" -> {"verb": "verb"}; {"verb", ...} -> a copy; else {}.
static func _entry(value: Variant) -> Dictionary:
	if value is String or value is StringName:
		return {"verb": str(value)}
	if value is Dictionary and (value as Dictionary).has("verb"):
		return (value as Dictionary).duplicate()
	return {}


## A `byTag` value: a verb or an entry for every class, or a class table of its own.
static func _tag_entry(value: Variant, hit_class: String) -> Dictionary:
	var entry := _entry(value)
	if not entry.is_empty():
		return entry
	if value is Dictionary and (value as Dictionary).has(hit_class):
		return _entry((value as Dictionary)[hit_class])
	return {}


## True when `hit_class` (or the wildcard) is in `list`.
static func _listed(list: Variant, hit_class: String) -> bool:
	return list is Array and ((list as Array).has(hit_class) or (list as Array).has(ANY_CLASS))


static func _finite(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return number
	return fallback


static func _dictionary(path: String) -> Dictionary:
	var constants := Services.constants()
	var found: Variant = constants.value(path, {}) if constants != null else {}
	return found if found is Dictionary else {}


static func _number(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0

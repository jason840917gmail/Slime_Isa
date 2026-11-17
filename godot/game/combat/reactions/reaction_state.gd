extends RefCounted
## One enemy's reaction memory (combat-feel plan section 5 "How decide picks a verb" and section 7
## "Anti-frustration rules"): the holds in a row, the wake guard, the break-free armor, the poise
## pool and its refill, the stun in force (the longer stun always wins), the knockdown's damage
## multiplier, the launch the wall splat and bowling read, a throw's faster knock slide and its chain
## (what its bowling deals and how far it passes on), the wall splats of the current chain and the
## phase and hurtbox part of the hit being judged.
## EnemyReactions keeps one per enemy (`EnemyReactions.state_of`) and hands it to
## `HitReaction.decide`, which reads and writes it.
## Every time is simulation ms (`Services.now_ms()`).
##
## Owner: reactions.

## Holds in a row (hits whose `counts_as_hold` is true and whose verb was a hold, outside a daze, a
## knockdown or an open phase); the one after `holdCap` becomes the break-free move.
var hold_count: int = 0
## When the last counted hold landed, and when the enemy is free of it (that hold's end, or a longer
## stun's in force then); the count clears once the enemy has stood free for
## `combat.rules.holdResetFreeMs` after that end.
var last_hold_ms: float = -INF
var hold_until_ms: float = -INF
## Hits deal damage and a flash only until then (`combat.rules.wakeGuardMs` after a launch, a
## knockback, a push or a break-free ends).
var wake_until_ms: float = 0.0
## The break-free move's armor (`combat.rules.breakFreeArmorMs`): hits are armor until then.
var armor_until_ms: float = 0.0
## Heavy and boss poise left; < 0 until the profile first fills it.
var poise: float = -1.0
## When the last hit of any kind landed (poise refills after `combat.rules.poiseRegenDelayMs`).
var last_hit_ms: float = -INF
## The verb in force ("" when none) and when its stun ends.
var verb: String = ""
var stun_until_ms: float = 0.0
## Damage taken x this while a knockdown is in force (`combat.verbs.knockdown.damageTaken`, or the
## class entry's `damageTaken`); 1 otherwise.
var damage_taken: float = 1.0
## When the body was last launched, and until when the launch flies (wall splats and bowling happen
## only then); -INF / 0 when never.
var launched_at_ms: float = -INF
var launch_until_ms: float = 0.0
## The launching hit's damage (the wall splat deals `combat.rules.wallSplat.damageShare` of it again).
var launch_damage: float = 0.0
## The body's collision layer when it was launched (bowling looks for bodies on it; a corpse has
## none of its own).
var launch_layer: int = 0
## Instance ids of the bodies this launch has bowled over (each only once per launch).
var bowled: Dictionary = {}
## A throw's knock slide slows the body by `slide_decay` per 60 Hz step until `slide_decay_until_ms`
## (faster than the stun slide's `combat.verbs.slideDecay`: EnemyReactions `slide_decay_of`).
var slide_decay: float = 1.0
var slide_decay_until_ms: float = 0.0
## A throw's chain (the hit's `chains`; EnemyReactions "A throw's new feel"): the knocked body's
## slide is a launch while it is fast (it splats on walls and bowls), a bowling contact deals
## `bowl_damage` (< 0: `combat.rules.bowling.damage`), and the bodies it bowls carry both on,
## `chain_depth` one deeper each (0 = the body the throw struck); a body deeper than
## `combat.rules.bowling.chainPasses` bowls no one.
var chains: bool = false
var chain_depth: int = 0
var bowl_damage: float = -1.0
## The kill in force is a send-off (the hit's `kill_sendoff`): the corpse flies and pops, so the
## death puff waits for the pop; `sendoff_pitch` is the pitch of its pop's cue (the pop streak's).
var sendoff: bool = false
var sendoff_pitch: float = 1.0
## The stun in force is a throw's and leaves the enemy helpless on the ground (a daze, a knockdown,
## a stagger, a sleep; a chain's wall splat and bowl): from `helpless_from_ms` on (its knock's flight
## is over) the slime can gulp it as ammo (EnemyReactions `is_helpless`; game/throw/gulpable_enemy.gd).
var throw_helpless: bool = false
var helpless_from_ms: float = 0.0
## A blow moves the body until then (a knock slide, a launch, a bowl, a sliding corpse, while it is
## fast): the ground's hazards take it (enemy_hazards.gd: a ledge, a hole, deep water, a danger
## zone). The spikes or lava Hazard a blow put it in (its instance id; 0 = none) and when it hurts
## next.
var blown_until_ms: float = 0.0
var zone_hazard: int = 0
var zone_next_ms: float = 0.0
## Wall splats in the current chain (`combat.rules.wallSplat.perChain`); a chain's first step and
## every ability hit that lands on a free enemy (no stun in force, no wake guard) clear it.
var splats_this_chain: int = 0
## The attack whose wind-up armor hits pushed back, and by how much so far
## (`combat.verbs.armor.maxMs` at most per attack).
var windup_sequence: int = -1
var windup_pushed_ms: float = 0.0
## The phase the enemy's script reports ("" = its normal phase; e.g. "windup", "dazed") and the
## hurtbox part the hit landed on ("" = no part), both set before every decision.
var phase: String = ""
var part: String = ""


## True while a stun of `of_verb` (any verb when "") is in force at `now_ms`.
func in_stun(now_ms: float, of_verb: String = "") -> bool:
	return now_ms < stun_until_ms and (of_verb.is_empty() or verb == of_verb)


## A copy to try a decision on without changing this memory (can_receive and mitigate_damage
## preview the verb).
func copy() -> RefCounted:
	var twin: RefCounted = (get_script() as GDScript).new()
	twin.set(&"hold_count", hold_count)
	twin.set(&"last_hold_ms", last_hold_ms)
	twin.set(&"hold_until_ms", hold_until_ms)
	twin.set(&"wake_until_ms", wake_until_ms)
	twin.set(&"armor_until_ms", armor_until_ms)
	twin.set(&"poise", poise)
	twin.set(&"last_hit_ms", last_hit_ms)
	twin.set(&"verb", verb)
	twin.set(&"stun_until_ms", stun_until_ms)
	twin.set(&"damage_taken", damage_taken)
	twin.set(&"launched_at_ms", launched_at_ms)
	twin.set(&"launch_until_ms", launch_until_ms)
	twin.set(&"launch_damage", launch_damage)
	twin.set(&"launch_layer", launch_layer)
	twin.set(&"bowled", bowled.duplicate())
	twin.set(&"slide_decay", slide_decay)
	twin.set(&"slide_decay_until_ms", slide_decay_until_ms)
	twin.set(&"chains", chains)
	twin.set(&"chain_depth", chain_depth)
	twin.set(&"bowl_damage", bowl_damage)
	twin.set(&"sendoff", sendoff)
	twin.set(&"sendoff_pitch", sendoff_pitch)
	twin.set(&"throw_helpless", throw_helpless)
	twin.set(&"helpless_from_ms", helpless_from_ms)
	twin.set(&"blown_until_ms", blown_until_ms)
	twin.set(&"zone_hazard", zone_hazard)
	twin.set(&"zone_next_ms", zone_next_ms)
	twin.set(&"splats_this_chain", splats_this_chain)
	twin.set(&"windup_sequence", windup_sequence)
	twin.set(&"windup_pushed_ms", windup_pushed_ms)
	twin.set(&"phase", phase)
	twin.set(&"part", part)
	return twin


## Forgets everything (a respawn or a reset of the fight).
func reset() -> void:
	hold_count = 0
	last_hold_ms = -INF
	hold_until_ms = -INF
	wake_until_ms = 0.0
	armor_until_ms = 0.0
	poise = -1.0
	last_hit_ms = -INF
	verb = ""
	stun_until_ms = 0.0
	damage_taken = 1.0
	launched_at_ms = -INF
	launch_until_ms = 0.0
	launch_damage = 0.0
	launch_layer = 0
	bowled.clear()
	slide_decay = 1.0
	slide_decay_until_ms = 0.0
	chains = false
	chain_depth = 0
	bowl_damage = -1.0
	sendoff = false
	sendoff_pitch = 1.0
	throw_helpless = false
	helpless_from_ms = 0.0
	blown_until_ms = 0.0
	zone_hazard = 0
	zone_next_ms = 0.0
	splats_this_chain = 0
	windup_sequence = -1
	windup_pushed_ms = 0.0
	phase = ""
	part = ""

extends RefCounted
## One enemy's reaction memory (combat-feel plan section 5 "How decide picks a verb" and section 7
## "Anti-frustration rules"): the holds in a row, the wake guard, the break-free armor, the poise
## pool and its refill, the stun in force (the longer stun always wins), the knockdown's damage
## multiplier, the launch the wall splat and bowling read, the wall splats of the current chain and
## the phase and hurtbox part of the hit being judged. EnemyReactions keeps one per enemy
## (`EnemyReactions.state_of`) and hands it to `HitReaction.decide`, which reads and writes it.
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
	splats_this_chain = 0
	windup_sequence = -1
	windup_pushed_ms = 0.0
	phase = ""
	part = ""

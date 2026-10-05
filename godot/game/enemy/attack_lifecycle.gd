extends RefCounted
class_name EnemyAttackLifecycle
## Enemy attack cooldown lifecycle (Phaser `enemies/enemyCombatLifecycle.ts`). Enemy spec 5.1.
##
## Owner: enemy builder.

var active: bool = false
var ready_at: float = 0.0
var sequence_id: int = 0


## If `active` or `time_ms < ready_at` -> -1; else `sequence_id += 1`, `active = true`,
## `ready_at = time_ms + cooldown_ms`, return the new sequence id.
func try_begin(time_ms: float, cooldown_ms: float) -> int:
	if active or time_ms < ready_at:
		return -1
	sequence_id += 1
	active = true
	ready_at = time_ms + cooldown_ms
	return sequence_id


## If active and `sequence == sequence_id` -> `active = false`.
func finish(sequence: int) -> void:
	if active and sequence == sequence_id:
		active = false


## `active = false`, `sequence_id += 1`; `ready_at` unchanged (a cancelled swing still costs its
## cooldown).
func cancel() -> void:
	active = false
	sequence_id += 1

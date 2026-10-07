extends RefCounted
class_name ComboCounter
## Combo damage multiplier (Phaser `combat/ComboSystem.ts`): hits in a 600 ms chain are x1.0,
## x1.15, then x1.5 with the finisher. Phaser reads the multiplier after counting the hit, so its
## first hit is already x1.15 (a lone sword hit does 28, not 24); the owner chose the intended
## chain for the port on 2026-10-05 (decision O3). Combat spec 9.4. Clock: SimClock ms. The combo
## text is OUT.
##
## Owner: combat builder.

## ComboSystem.ts:9-11.
const WINDOW_MS := 600.0
const DAMAGE_MULTIPLIERS: Array[float] = [1.0, 1.15, 1.5]
const FINISHER_COUNT := 3

var combo: int = 0
var last_hit_at: float = -INF


## Per routed target, before routing: reset when `now - last_hit_at > WINDOW_MS`; combo =
## min(combo + 1, 3); multiplier = DAMAGE_MULTIPLIERS[combo - 1] (the hit's own tier); at 3 ->
## finisher and reset. Returns {"multiplier": float, "finisher": bool}.
func register_hit(now_ms: float) -> Dictionary:
	if now_ms - last_hit_at > WINDOW_MS:
		combo = 0
	combo = mini(combo + 1, FINISHER_COUNT)
	last_hit_at = now_ms
	var multiplier: float = DAMAGE_MULTIPLIERS[clampi(combo - 1, 0, DAMAGE_MULTIPLIERS.size() - 1)]
	var finisher := combo >= FINISHER_COUNT
	if finisher:
		combo = 0
	return {"multiplier": multiplier, "finisher": finisher}


## Each step: combo > 0 and `now - last_hit_at > WINDOW_MS` -> combo = 0.
func update(now_ms: float) -> void:
	if combo > 0 and now_ms - last_hit_at > WINDOW_MS:
		combo = 0


## `ComboSystem.reset` (combat teardown).
func reset() -> void:
	combo = 0
	last_hit_at = -INF

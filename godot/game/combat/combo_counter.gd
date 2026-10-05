extends RefCounted
class_name ComboCounter
## Combo damage multiplier (Phaser `combat/ComboSystem.ts`), ported with its live off-by-one:
## the multiplier is read AFTER the increment, so a lone hit is x1.15 (sword 24 -> 28).
## Combat spec 9.4. Clock: SimClock ms. The combo text is OUT.
##
## Owner: combat builder.

## ComboSystem.ts:9-11.
const WINDOW_MS := 600.0
const DAMAGE_MULTIPLIERS: Array[float] = [1.0, 1.15, 1.5]
const FINISHER_COUNT := 3

var combo: int = 0
var last_hit_at: float = -INF


## Per routed target, before routing: reset when `now - last_hit_at > WINDOW_MS`; combo =
## min(combo + 1, 3); multiplier = DAMAGE_MULTIPLIERS[min(combo, 2)]; at 3 -> finisher and reset.
## Returns {"multiplier": float, "finisher": bool}.
func register_hit(now_ms: float) -> Dictionary:
	if now_ms - last_hit_at > WINDOW_MS:
		combo = 0
	combo = mini(combo + 1, FINISHER_COUNT)
	last_hit_at = now_ms
	var multiplier: float = DAMAGE_MULTIPLIERS[mini(combo, DAMAGE_MULTIPLIERS.size() - 1)]
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

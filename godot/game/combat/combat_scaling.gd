extends RefCounted
class_name CombatScaling
## Attribute scaling (Phaser `combat/CombatScaling.ts:11-32`). Combat spec 4.2.
##
## Owner: combat builder.

## CombatScaling.ts:5 ATTRIBUTE_BASELINE: the neutral attribute value.
const ATTRIBUTE_BASELINE := 10.0


## `sum over attributes ((attr - 10) / 10) * coef` for each `coefs[attribute]`; attributes come
## from game-constants `character.player.initialAttributes` (all 10 in a new run -> 0).
## Non-numeric coefficients are skipped (Phaser `Number.isFinite`); an attribute missing from
## `attributes` counts as the baseline (no contribution).
static func scaling(coefs: Dictionary, attributes: Dictionary) -> float:
	var total := 0.0
	for attribute: Variant in coefs:
		var coef: Variant = coefs[attribute]
		if not (coef is float or coef is int) or not is_finite(float(coef)):
			continue
		var value: Variant = attributes.get(attribute, ATTRIBUTE_BASELINE)
		var attr := float(value) if (value is float or value is int) else ATTRIBUTE_BASELINE
		total += ((attr - ATTRIBUTE_BASELINE) / ATTRIBUTE_BASELINE) * float(coef)
	return total


## `max(minimum, base * max(0, 1 + scaling(coefs, attributes)))`; a non-finite base -> minimum.
static func scaled(base: float, coefs: Dictionary, attributes: Dictionary, minimum: float = 0.0) -> float:
	if not is_finite(base):
		return minimum
	var multiplier := maxf(0.0, 1.0 + scaling(coefs, attributes))
	return maxf(minimum, base * multiplier)

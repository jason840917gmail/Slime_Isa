extends RefCounted
## The body-shapes rework mode (docs/godot/BODY_SHAPES.md; plans:
## docs/design/2026-10-11-body-shapes-plan.md and 2026-10-11-combat-feel-plan.md). The rework is a
## prototype that runs beside the old weapon system: while the mode is off every old code path runs
## exactly as before, because every hook the rework adds to an old file asks `is_on()` first.
##
## main.gd decides it once per world build, before the player acts (`set_on`): on in the playground
## unless the `classic` launch option is given, on in any world with `shapes`. Anything may read it
## at any time. A damage request that carries a top-level `hit` Dictionary is a rework request
## whatever the mode (`is_rework_request`).
##
## Owner: rework wiring (BODY_SHAPES.md "Mode, wiring, testbed").

static var _on: bool = false


## True while the rework mode is on.
static func is_on() -> bool:
	return _on


## main.gd only: once per world build (and off when main leaves the tree).
static func set_on(on: bool) -> void:
	_on = on


## True when `request` (a DamageRouter request) carries a non-empty top-level `hit` Dictionary,
## which only rework attacks send (BODY_SHAPES.md "The hit").
static func is_rework_request(request: Dictionary) -> bool:
	var hit: Variant = request.get("hit")
	return hit is Dictionary and not (hit as Dictionary).is_empty()

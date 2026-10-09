extends Node2D
## The Roll's ground marks (owner, 2026-10-09: "like screeching tires"; roadmap 7.7): while the
## ball spins up in place it lays two dark skid streaks behind it and kicks dust back off the
## ground, and the launch throws a last puff. Marks fade over SKID_FADE_MS, puffs over PUFF_MS
## (real time: presentation only).
##
## One per world, a child of the y-sorted entities root at y 0 like the Goo Trail, so it draws
## right after the ground and under everything standing on it; freed with the world
## (game/player/roll/player_roll.gd makes it).
##
## Owner: abilities.

const SKID_FADE_MS := 1100.0
const SKID_COLOR := Color(0.24, 0.17, 0.1, 0.42)
const SKID_WIDTH := 3.0
## The two streaks sit this far either side of the ball's path and grow this long behind it.
const SKID_GAP_PX := 7.0
const SKID_LENGTH_PX := 22.0
const PUFF_MS := 520.0
const PUFF_COLOR := Color("#d9c8a4")
const PUFF_RADIUS_PX := 5.0
const PUFF_GROWTH := 2.2

## [{"at": Vector2 (the ball's feet), "back": Vector2 (unit, behind the ball), "length": float,
## "born": float}].
var _skids: Array[Dictionary] = []
## [{"at": Vector2, "velocity": Vector2, "born": float}].
var _puffs: Array[Dictionary] = []


func _ready() -> void:
	position = Vector2.ZERO


## Starts (or lengthens, `grow` 0..1) the skid streaks under a ball at `feet` rolling `direction`.
func skid(feet: Vector2, direction: Vector2, grow: float) -> void:
	var back := -direction.normalized()
	if _skids.is_empty() or (_skids[-1]["at"] as Vector2).distance_to(feet) > 1.0:
		_skids.append({"at": feet, "back": back, "length": 0.0, "born": _now()})
	var mark: Dictionary = _skids[-1]
	mark["length"] = maxf(float(mark["length"]), SKID_LENGTH_PX * clampf(grow, 0.0, 1.0))
	mark["born"] = _now()
	queue_redraw()


## A few dust puffs kicked back from `feet`, away from `direction`, at up to `speed` px/s.
func kick(feet: Vector2, direction: Vector2, count: int, speed: float) -> void:
	var back := -direction.normalized()
	for i in count:
		var spread := randf_range(-0.7, 0.7)
		_puffs.append({"at": feet + Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0)),
			"velocity": back.rotated(spread) * randf_range(0.4, 1.0) * speed + Vector2(0.0, -randf_range(6.0, 22.0)),
			"born": _now()})
	queue_redraw()


func _process(delta: float) -> void:
	if _skids.is_empty() and _puffs.is_empty():
		return
	var now := _now()
	_skids = _skids.filter(func(mark: Dictionary) -> bool: return now - float(mark["born"]) < SKID_FADE_MS)
	_puffs = _puffs.filter(func(puff: Dictionary) -> bool: return now - float(puff["born"]) < PUFF_MS)
	for puff: Dictionary in _puffs:
		puff["at"] = (puff["at"] as Vector2) + (puff["velocity"] as Vector2) * delta
		puff["velocity"] = (puff["velocity"] as Vector2) * 0.9
	queue_redraw()


func _draw() -> void:
	var now := _now()
	for mark: Dictionary in _skids:
		var fade := 1.0 - (now - float(mark["born"])) / SKID_FADE_MS
		var back: Vector2 = mark["back"]
		var side := back.orthogonal() * SKID_GAP_PX
		var color := Color(SKID_COLOR, SKID_COLOR.a * fade)
		for offset: Vector2 in [side, -side]:
			var from: Vector2 = (mark["at"] as Vector2) + offset
			draw_line(from, from + back * float(mark["length"]), color, SKID_WIDTH, true)
	for puff: Dictionary in _puffs:
		var age := (now - float(puff["born"])) / PUFF_MS
		draw_circle(puff["at"], PUFF_RADIUS_PX * (1.0 + PUFF_GROWTH * age), Color(PUFF_COLOR, 0.55 * (1.0 - age)))


func _now() -> float:
	return Time.get_ticks_msec()

extends Node2D
## Goo Trail, the passive ability (Phaser `features/feel/SlimeTrail.ts` + `WorldScene
## .updateSlimeTrail`; abilities spec 12). Once `goo-trail` is learned, a living, awake slime that
## is not busy with an ability drops a goo smear every 30 px it moves, at its feet - 3 (a pool of
## 28, oldest reused; each fades over 5 s). Every 100 ms, enemies within 26 px of a smear younger
## than 2.5 s get the slow status (x 0.55) for 400 ms. Nothing in the story teaches it yet.
## A child of the world's y-sorted root at y 0, so it draws right after the ground and under
## everything standing on it (a ground decal); freed with the world.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const ABILITY_ID := "goo-trail"
const POOL_SIZE := 28
const SPACING := 30.0
const LIFETIME_MS := 5000.0
const FRESH_MS := 2500.0
const MARK_ALPHA := 0.5
const SLOW_EVERY_MS := 100.0
const SLOW_RADIUS := 26.0
const SLOW_MULTIPLIER := 0.55
const SLOW_MS := 400.0
const FEET_RISE := 3.0

## player.gd (get_centre, is_dead, is_sleeping, is_ability_busy, body).
var player: Node
## [{"at": Vector2, "born": float, "live": bool, "angle": float}].
var _marks: Array[Dictionary] = []
var _next: int = 0
var _last: Variant = null
var _next_slow_ms: float = 0.0


func _ready() -> void:
	position = Vector2.ZERO
	for i in POOL_SIZE:
		_marks.append({"at": Vector2.ZERO, "born": 0.0, "live": false, "angle": 0.0})


func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var now := Services.now_ms()
	var aged := false
	for mark in _marks:
		if mark["live"] and now - float(mark["born"]) >= LIFETIME_MS:
			mark["live"] = false
			aged = true
	var run := Services.run()
	var grounded := run != null and run.has_learned_ability(ABILITY_ID) and not bool(player.call(&"is_dead")) \
		and not bool(player.call(&"is_sleeping")) and not bool(player.call(&"is_ability_busy"))
	if grounded:
		var body := player.get(&"body") as Node2D
		var at := Vector2((player.call(&"get_centre") as Vector2).x, body.global_position.y - FEET_RISE) if body != null else Vector2.ZERO
		if _last == null or (_last as Vector2).distance_to(at) >= SPACING:
			_last = at
			var mark: Dictionary = _marks[_next]
			mark["at"] = at
			mark["born"] = now
			mark["live"] = true
			mark["angle"] = deg_to_rad(float((_next * 47) % 30 - 15))
			_next = (_next + 1) % POOL_SIZE
			aged = true
	else:
		_last = null
	if aged or _any_live():
		queue_redraw()
	if now >= _next_slow_ms:
		_next_slow_ms = now + SLOW_EVERY_MS
		var fresh := fresh_points(now)
		var main := get_tree().get_first_node_in_group(&"world_main")
		var population: Variant = main.get(&"enemy_population") if main != null else null
		if not fresh.is_empty() and population != null and is_instance_valid(population) and population.has_method(&"slow_enemies_near"):
			population.call(&"slow_enemies_near", fresh, SLOW_RADIUS, SLOW_MULTIPLIER, SLOW_MS)


## Smears young enough to slow enemies.
func fresh_points(now: float) -> Array:
	var points: Array = []
	for mark in _marks:
		if mark["live"] and now - float(mark["born"]) < FRESH_MS:
			points.append(mark["at"])
	return points


## Forget the last position (a teleport or a map change must not draw a streak).
func reset() -> void:
	_last = null


func _any_live() -> bool:
	for mark in _marks:
		if mark["live"]:
			return true
	return false


## `fx-goo-mark` (ProceduralAssetScene.ts:114-121): three nested ellipses, 28 x 16.
func _draw() -> void:
	var now := Services.now_ms()
	for mark in _marks:
		if not mark["live"]:
			continue
		var fade := MARK_ALPHA * maxf(0.0, 1.0 - (now - float(mark["born"])) / LIFETIME_MS)
		draw_set_transform(mark["at"], float(mark["angle"]), Vector2.ONE)
		_ellipse(Vector2(0.0, 0.0), Vector2(13.0, 6.5), Color(Color("#3f9a4a"), 0.55 * fade))
		_ellipse(Vector2(-1.0, -1.0), Vector2(9.0, 4.0), Color(Color("#7be08a"), 0.7 * fade))
		_ellipse(Vector2(-4.0, -3.0), Vector2(3.0, 1.25), Color(Color("#d8ffd8"), 0.6 * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ellipse(centre: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * i / 16.0
		points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)

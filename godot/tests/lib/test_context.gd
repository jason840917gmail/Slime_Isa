extends RefCounted
## Per-test helper handed to every `test_*` function by res://tests/run_tests.gd.
##
## The runner instances a fresh res://game/main.tscn before each test (SimClock reset to 0,
## WorldService cleared) and frees it afterwards, so tests share nothing. Tests drive the game
## only through public APIs, Services and input events, and measure time on the gameplay clock
## (`now()` = `Services.now_ms()`).
##
## Timing model: `await steps(n)` resumes at the start of a physics tick, before SimClock and the
## game scripts run, so what a test reads after it is the state at the end of the previous tick
## and `now()` is that tick's time. Input pushed then is captured with that time and consumed by
## the player in the next tick.
##
## Assertions are soft (`check`, `near`, `between` record a failure and return false); return from
## the test when a failed check makes the rest meaningless. Signal lambdas copy local scalars, so
## keep state that a lambda writes in a Dictionary or Array.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const WorldServiceType := preload("res://game/autoload/world_service.gd")

## One physics step at 60 Hz, in ms.
const STEP_MS := 1000.0 / 60.0
const WORM_SCENE_ID := "character.worm-swordsman"

var tree: SceneTree
var test_name: String
## The res://game/main.tscn instance of this test (main.gd).
var main: Node
var failures: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()
## Set by the runner on timeout; every wait helper then returns at once.
var aborted: bool = false
var _held: Dictionary = {}
var _connections: Array = []


func _init(scene_tree: SceneTree, name: String) -> void:
	tree = scene_tree
	test_name = name


# --- game access -------------------------------------------------------------------------------

func world() -> WorldServiceType:
	return Services.world()


func player() -> PlayerScript:
	var service := world()
	return service.player if service != null else null


func player_body() -> CharacterBody2D:
	var script := player()
	return script.body if script != null else null


## Gameplay clock (SimClock) in ms.
func now() -> float:
	return Services.now_ms()


## Moves the player so its old Phaser centre is `centre` and stops it (test setup only).
func teleport_player(centre: Vector2) -> void:
	var body := player_body()
	if body == null:
		return
	body.velocity = Vector2.ZERO
	FeetAnchor.place_at_phaser_position(body, centre)
	body.reset_physics_interpolation()


## Spawns a worm swordsman whose centre is `offset` from the player centre, the way the camp does
## (`WorldService.spawn_at_phaser_position`), without a camp territory. `passive` sets its
## targeting radius and attack range to 0, so it never chases or attacks (isolates player hits).
func spawn_worm(offset: Vector2, passive: bool = false) -> EnemyScript:
	var service := world()
	var script := player()
	if service == null or script == null:
		fail("spawn_worm: no world or player")
		return null
	var root := service.spawn_at_phaser_position(WORM_SCENE_ID, script.get_centre() + offset)
	if root == null:
		fail("spawn_worm: %s did not spawn" % WORM_SCENE_ID)
		return null
	for child in root.get_children():
		if child is EnemyScript:
			var enemy := child as EnemyScript
			if passive:
				enemy.targeting_radius = 0.0
				enemy.attack_range = 0.0
			return enemy
	fail("spawn_worm: %s has no EnemyScript" % WORM_SCENE_ID)
	return null


## Places a worm so its centre is `centre` and stops it (test setup only).
func place_worm(enemy: EnemyScript, centre: Vector2) -> void:
	if enemy == null or enemy.body == null:
		return
	enemy.body.velocity = Vector2.ZERO
	FeetAnchor.place_at_phaser_position(enemy.body, centre)
	enemy.body.reset_physics_interpolation()


# --- signals -----------------------------------------------------------------------------------

## Connects `callable` to `sig` until the test ends (the runner disconnects it on teardown), for
## signals of objects that outlive the test (autoloads such as DamageRouter).
func listen(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_connections.append([sig, callable])


func disconnect_all() -> void:
	for pair: Array in _connections:
		var sig: Signal = pair[0]
		# The emitter may be gone (a world freed by a travel).
		if not sig.is_null() and is_instance_valid(sig.get_object()) and sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	_connections.clear()


# --- audio -------------------------------------------------------------------------------------

## Stops a cue player before a "did it play?" check. A cue player (SfxPlayer, SfxPlayer2D) also
## forgets its last cue, so its `min_interval_ms` cannot drop the next one: a player shared across
## tests can carry a cue from the previous test that a fast run puts within the interval.
static func silence(player: Node) -> void:
	if player.has_method(&"reset_cue"):
		player.call(&"reset_cue")
	elif player is AudioStreamPlayer:
		(player as AudioStreamPlayer).stop()
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).stop()


# --- input -------------------------------------------------------------------------------------

## Pushes a press of `action` through the root viewport (reaches `_unhandled_input`).
func press(action: StringName) -> void:
	_push(action, true)
	_held[action] = true


func release(action: StringName) -> void:
	_push(action, false)
	_held.erase(action)


## Press and release in the same frame: one buffered press, nothing held.
func tap(action: StringName) -> void:
	press(action)
	release(action)


func release_all() -> void:
	for action: StringName in _held.keys():
		_push(action, false)
	_held.clear()


func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	tree.root.push_input(event)


# --- time --------------------------------------------------------------------------------------

## Waits `count` physics ticks (ticks still pass while the tree is paused by a hit-stop).
func steps(count: int) -> void:
	for _i in count:
		if aborted:
			return
		await tree.physics_frame


## Waits until the gameplay clock advanced by `ms` (hit-stop pauses do not count).
func sim_wait(ms: float) -> void:
	var target := now() + ms
	await until(func() -> bool: return now() >= target - 0.001, ms + 200.0)


## Waits physics ticks until `condition` returns true. Gives up (returns false) once the gameplay
## clock advanced more than `max_sim_ms`, or after `max_real_ms` of real time (default: four
## times the sim budget plus 3 s, for hit-stop pauses and slow frames).
func until(condition: Callable, max_sim_ms: float, max_real_ms: float = -1.0) -> bool:
	var start_sim := now()
	var start_real := float(Time.get_ticks_msec())
	var real_limit := max_real_ms if max_real_ms >= 0.0 else max_sim_ms * 4.0 + 3000.0
	while not aborted:
		if bool(condition.call()):
			return true
		if now() - start_sim > max_sim_ms or float(Time.get_ticks_msec()) - start_real > real_limit:
			return false
		await tree.physics_frame
	return false


# --- assertions --------------------------------------------------------------------------------

func fail(message: String) -> void:
	failures.append(message)


func check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func near(actual: float, expected: float, tolerance: float, label: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s: got %s, expected %s +/- %s" % [label, _num(actual), _num(expected), _num(tolerance)])


func near_vec(actual: Vector2, expected: Vector2, tolerance: float, label: String) -> bool:
	return check(actual.distance_to(expected) <= tolerance,
		"%s: got %s, expected %s +/- %s" % [label, actual, expected, _num(tolerance)])


func between(actual: float, low: float, high: float, label: String) -> bool:
	return check(actual >= low and actual <= high,
		"%s: got %s, expected within [%s, %s]" % [label, _num(actual), _num(low), _num(high)])


func equal(actual: Variant, expected: Variant, label: String) -> bool:
	return check(actual == expected, "%s: got %s, expected %s" % [label, actual, expected])


## Informational line printed under the test result.
func note(message: String) -> void:
	notes.append(message)


static func _num(value: float) -> String:
	return ("%.3f" % value).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")

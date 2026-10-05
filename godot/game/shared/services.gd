extends RefCounted
class_name Services
## Typed access to the autoload singletons registered in project.godot.
##
## Why this exists: the headless `--check-only -s` run does not register autoload names as
## globals ("Identifier not found: DamageRouter"), so gameplay scripts never write the bare
## autoload name. They preload this file and call `Services.router().route(...)` instead.
## Every getter returns null when the tree or the autoload is missing (a scene opened alone in
## the editor); callers must tolerate null.
##
## Owner: world builder. Architect wrote it complete; change only to add a new autoload.

const GameConstantsType := preload("res://game/autoload/game_constants.gd")
const SimClockType := preload("res://game/autoload/sim_clock.gd")
const WorldServiceType := preload("res://game/autoload/world_service.gd")
const DamageRouterType := preload("res://game/combat/damage_router.gd")
const GameFeelType := preload("res://game/feel/game_feel.gd")


## Autoload `GameConstants` (res://generated/data/*.json).
static func constants() -> GameConstantsType:
	return _autoload(&"GameConstants") as GameConstantsType


## Autoload `SimClock` (gameplay simulation time).
static func clock() -> SimClockType:
	return _autoload(&"SimClock") as SimClockType


## Autoload `WorldService` (world, player, camera, areas, scene index, pause reasons).
static func world() -> WorldServiceType:
	return _autoload(&"WorldService") as WorldServiceType


## Autoload `DamageRouter` (receiver registry, attack activations, damage routing).
static func router() -> DamageRouterType:
	return _autoload(&"DamageRouter") as DamageRouterType


## Autoload `GameFeel` (hit-stop, shake, floating text, particles, global audio cues).
static func feel() -> GameFeelType:
	return _autoload(&"GameFeel") as GameFeelType


## Current gameplay simulation time in ms (`SimClock.now_ms`), 0 when the clock is missing.
static func now_ms() -> float:
	var sim_clock: SimClockType = clock()
	return sim_clock.now_ms if sim_clock != null else 0.0


static func _autoload(autoload_name: StringName) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(String(autoload_name)))

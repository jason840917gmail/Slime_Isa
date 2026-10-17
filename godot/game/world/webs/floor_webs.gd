extends RefCounted
class_name FloorWebs
## The rule every web on the floor follows (owner, 2026-10-16, question 131; roadmap 7.9;
## docs/godot/WEBS.md): the painted web cells (WebLayer, web_layer.gd), a single floor web node
## (`object.floor-web`, game/scripts/floor_web.gd) and the Matron's volley patches
## (`effect.matron-web-patch`, game/scripts/web_patch.gd). Web walls (`object.web-wall`,
## game/scripts/web_wall.gd) use the same walk scale the other way round.
##
## - **Without the Silk skin** (`player.crosses_webs()`: the skin's hook, today the Silk Gulp form):
##   a walk whose feet are in a web is scaled by `webs.floorSlowMultiplier` (0.5), and a Roll that
##   enters one sticks: the roll ends there (`player.stop_movement()`: no bonk, no rolling on) and
##   the slime is rooted `webs.rollStickMs` (`player.apply_web`, the web cover), where it is (unlike
##   the web barrier's catch, nothing sets it back).
## - **With it:** full speed, and a Roll crosses.
## - A web wall slows only the Silk slime passing through it (`webs.wallPassMultiplier`, 0.5).
## - Enemies are never slowed: only the player's walk asks (player.gd `_move`).
##
## A web source joins group GROUP and answers `web_walk_multiplier(player: Node, crosses: bool) ->
## float` (1.0 where it does not hold the slime); a floor web calls `stick_roll(player)` from its
## own physics step while the slime is in it. Two webs under the slime do not stack: the lowest
## scale wins. The first step into a floor web plays CUE_ENTER (at most every
## `webs.enterCueIntervalMs` of real time).
##
## Owner: webs (the Weaver Hollow).

const Services := preload("res://game/shared/services.gd")

const GROUP := &"web_slows"
const CUE_ENTER := &"WebStruggle"
const ENTER_PITCH := 1.25
## main.gd joins this group (`is_transitioning`).
const MAIN_GROUP := &"world_main"
## Metadata on the player script: its feet were in a floor web on the last walking step, and the
## real time the enter cue may play again.
const IN_WEB_META := &"floor_web_in"
const CUE_AT_META := &"floor_web_cue_at_ms"


## `webs.<name>` from game-constants.json.
static func setting(name: String) -> float:
	var constants := Services.constants()
	return constants.number("webs." + name) if constants != null else 1.0


## The living, registered player while no travel runs, else null.
static func player() -> Node:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player) or not world.player.is_inside_tree():
		return null
	if world.player.is_dead() or _transitioning():
		return null
	return world.player


## The player's feet (its body's origin; Vector2.INF without a body).
static func feet(target: Node) -> Vector2:
	var body := target.get(&"body") as Node2D if target != null else null
	return body.global_position if body != null else Vector2.INF


## The scale of this walking step for the webs under `target` (1.0 for none), from every source in
## GROUP. Plays the enter cue when its feet step into a floor web. Called by player.gd `_move`.
static func step(target: Node) -> float:
	if target == null or not target.is_inside_tree():
		return 1.0
	var crosses := bool(target.call(&"crosses_webs"))
	var scale := 1.0
	for source: Node in target.get_tree().get_nodes_in_group(GROUP):
		if is_instance_valid(source) and source.has_method(&"web_walk_multiplier"):
			scale = minf(scale, float(source.call(&"web_walk_multiplier", target, crosses)))
	var in_web := scale < 1.0 and not crosses
	if in_web and not bool(target.get_meta(IN_WEB_META, false)):
		_enter_cue(target)
	target.set_meta(IN_WEB_META, in_web)
	return scale


## A Roll that runs into a floor web sticks: the roll ends and the slime is rooted
## `webs.rollStickMs`. Nothing happens unless `target` rolls and does not cross webs. True when it
## stuck.
static func stick_roll(target: Node) -> bool:
	if target == null or not bool(target.call(&"is_rolling")) or bool(target.call(&"crosses_webs")):
		return false
	target.call(&"stop_movement")
	if target.has_method(&"apply_web"):
		target.call(&"apply_web", setting("rollStickMs"))
	elif target.has_method(&"suppress_movement"):
		target.call(&"suppress_movement", setting("rollStickMs"))
	return true


static func _enter_cue(target: Node) -> void:
	var now := float(Time.get_ticks_msec())
	if now < float(target.get_meta(CUE_AT_META, 0.0)):
		return
	target.set_meta(CUE_AT_META, now + setting("enterCueIntervalMs"))
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_ENTER, {"pitch": ENTER_PITCH})


static func _transitioning() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var main := tree.get_first_node_in_group(MAIN_GROUP)
	return main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning"))

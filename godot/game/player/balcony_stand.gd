extends RefCounted
## The slime on a balcony (docs/godot/SKINS.md "Balconies"; the owner, 2026-11-13: "a step out
## balcony where the slime can fall from above"): a rock ledge painted on a cliff's face with the
## vines' layer (game/world/vines/vine_layer.gd, the palette's balcony tile), whose grass is a floor
## part-way up the wall. Owned by player.gd.
##
## - **Getting there.** A drop off the rim above lands on a balcony under it instead of the wall's
##   foot (`catch`; player.gd `_press_ledge`), and so does a let-go from the vines (the layer's
##   `climb_landing`); vines painted right over or under a balcony lead onto it. Wherever the slime's
##   feet come to be on a balcony's floor (a door that leads out there too), it stands on it
##   (`update`).
## - **On it** the slime walks as on any ground, kept on the floor (`confine`: a move is cut to
##   what stays on it, sliding along its edge); nothing else collides up there (player.gd moves it
##   with no collision mask). It is drawn before the wall (Elevation `set_flight` at the depth of
##   the wall's foot).
## - **Off it.** Pushing on against the floor's edge, forward or sideways, for `elevation.dropPushMs`
##   drops the slime to the next balcony under it, else to the wall's foot (`pushes_off`,
##   `drop_from`; player.gd `_press_balcony_edge`): a ledge drop, no damage. Vines take it up or down
##   with the Feral skin.
##
## The layers answer, in the slime's feet (world): `balcony_holds(feet)`, `balcony_step(feet, move)`,
## `balcony_catch(from, to)`, `balcony_drop(feet)`, `balcony_depth(feet)`.
##
## Owner: player.

const Services := preload("res://game/shared/services.gd")

## The vines' layers are in this group in the game (game/player/skins/feral_climb.gd WALL_GROUP).
const LAYER_GROUP := &"climb_walls"
const LEVEL_UNITS := 64.0
## How far ahead a push against the floor's edge is tried (px), and how much of it must be left for
## the push not to count as one off the balcony.
const PUSH_PROBE := 6.0
const PUSH_LEFT := 0.5
## A push up (into the wall behind the balcony) is no push off it.
const PUSH_UP_DOT := -0.3

var _active := false
var _layer: Node2D


func is_active() -> bool:
	return _active and _layer != null and is_instance_valid(_layer)


## Every physics step: the slime stands on the balcony its feet are on. `free`: nothing else owns it
## (no flight, no climb); then leaving the floor hands it back to the ground's levels.
func update(body: CharacterBody2D, free: bool) -> void:
	if body == null or not is_instance_valid(body):
		_active = false
		_layer = null
		return
	var layer: Node2D = layer_under(body.get_tree(), body.global_position) if free else null
	var world := Services.world()
	var elevation: Node = world.elevation if world != null else null
	if layer == null:
		if _active and free and elevation != null:
			elevation.call(&"end_flight", body)
			elevation.call(&"track", body)
		_active = false
		_layer = null
		return
	_active = true
	_layer = layer
	if elevation != null:
		elevation.call(&"set_flight", body, float(layer.call(&"balcony_depth", body.global_position)))


## The body's velocity cut to what keeps its feet on the floor this step.
func confine(body: CharacterBody2D, delta: float) -> void:
	if not is_active() or delta <= 0.0 or body.velocity == Vector2.ZERO:
		return
	var step: Vector2 = _layer.call(&"balcony_step", body.global_position, body.velocity * delta)
	body.velocity = step / delta


## True when walking `unit` from where it stands, the slime is held by the floor's edge (not by the
## wall behind it): a push off the balcony.
func pushes_off(body: CharacterBody2D, unit: Vector2) -> bool:
	if not is_active() or unit.y < PUSH_UP_DOT:
		return false
	var step: Vector2 = _layer.call(&"balcony_step", body.global_position, unit * PUSH_PROBE)
	return step.length() < PUSH_PROBE * PUSH_LEFT


## Where a drop off the balcony lands (feet): the next balcony under it, else before the wall's foot.
func drop_from(body: CharacterBody2D) -> Vector2:
	return _layer.call(&"balcony_drop", body.global_position) if is_active() else body.global_position


## The level a slime on a balcony at `feet` counts as for a flight's depth (JumpSequence): as many
## levels over the wall's foot as it stands rows above it, so it is drawn before the wall.
static func level_at(tree: SceneTree, feet: Vector2) -> int:
	var layer := layer_under(tree, feet)
	if layer == null:
		return 0
	return maxi(0, ceili((float(layer.call(&"balcony_depth", feet)) - feet.y) / LEVEL_UNITS))


## A straight fall from `from` to `to` (feet): where it lands on the first balcony under it, or
## Vector2.INF.
static func catch(tree: SceneTree, from: Vector2, to: Vector2) -> Vector2:
	var best := Vector2.INF
	if tree == null:
		return best
	for node: Node in tree.get_nodes_in_group(LAYER_GROUP):
		var layer := node as Node2D
		if layer == null or not layer.has_method(&"balcony_catch") or not layer.is_visible_in_tree():
			continue
		var land: Vector2 = layer.call(&"balcony_catch", from, to)
		if land.is_finite() and (not best.is_finite() or land.y < best.y):
			best = land
	return best


## The layer whose balcony holds feet at `feet`, or null.
static func layer_under(tree: SceneTree, feet: Vector2) -> Node2D:
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(LAYER_GROUP):
		var layer := node as Node2D
		if layer != null and layer.has_method(&"balcony_holds") and layer.is_visible_in_tree() \
				and bool(layer.call(&"balcony_holds", feet)):
			return layer
	return null

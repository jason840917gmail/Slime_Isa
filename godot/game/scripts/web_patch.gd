extends Node
class_name WebPatchScript
## Scene script `game.web-patch` (Phaser `features/scripts/WebPatchScript.ts`): a web lying on the
## ground (the Matron's volley, `effect.matron-web-patch`). Matron spec 5.1 and 5.5.
##
## A round patch, a floor web, that follows the floor webs' rule (roadmap 7.9: "a Matron volley
## patch behaves like a web"; game/world/webs/floor_webs.gd): a normal slime whose centre is on it
## walks at `webs.floorSlowMultiplier` (half) of its speed, and a Roll that enters it sticks there
## (the roll ends and the slime is rooted `webs.rollStickMs`, where it is; `caught`). Nothing sets
## the slime back any more. A slime that crosses webs (the Silk skin's hook, today the Silk form)
## walks or rolls through at full speed and tears the patch quietly (no message, no flag). Never
## remembered: the effect that owns it fades after its lifetime (effect.gd frees the root). Checked
## every physics step (Phaser: every frame).
##
## Node: `WebPatchScript` under the effect root (no depth anchor: the root is the patch centre).
##
## Owner: boss port (the rule: webs).

const SpiderWebPort := preload("res://game/enemy/spider_web_port.gd")
const FloorWebs := preload("res://game/world/webs/floor_webs.gd")

## WebPatchScript.ts:33: radius when the authored one is missing or not > 0.
const DEFAULT_RADIUS := 48.0

## JSON `radius` (50): the web's circle around the patch centre (the slime's centre inside it).
@export var radius: float = DEFAULT_RADIUS
## JSON `visual`: the web sprite, hidden when torn.
@export var visual: Node2D

## A Roll stuck in the patch. Payload: the zone {"x", "y", "halfWidth", "halfHeight"}.
signal caught(zone: Dictionary)
## The Sticky slime tore the patch (-> TearSfx). Payload: the zone.
signal torn(zone: Dictionary)

var _torn: bool = false


func _enter_tree() -> void:
	add_to_group(FloorWebs.GROUP)


func _ready() -> void:
	if not (is_finite(radius) and radius > 0.0):
		radius = DEFAULT_RADIUS


## True once the Sticky slime tore the patch.
func is_torn() -> bool:
	return _torn


## The patch's box around its centre ({} without a Node2D parent): {"x", "y", "halfWidth": radius,
## "halfHeight": radius}.
func zone() -> Dictionary:
	var root := get_parent() as Node2D
	if root == null:
		return {}
	var origin := root.global_position
	return {"x": origin.x, "y": origin.y, "halfWidth": radius, "halfHeight": radius}


## True when `centre` (the slime's old Phaser centre) is on the patch.
func holds(centre: Vector2) -> bool:
	var root := get_parent() as Node2D
	return not _torn and root != null and centre.is_finite() and centre.distance_to(root.global_position) <= radius


## FloorWebs: a slime on the patch that does not cross webs walks at half speed.
func web_walk_multiplier(player: Node, crosses: bool) -> float:
	if crosses or player == null or not player.has_method(&"get_centre") or not holds(player.call(&"get_centre")):
		return 1.0
	return FloorWebs.setting("floorSlowMultiplier")


## WebPatchScript.ts:50-65, on the floor webs' rule.
func _physics_process(_delta: float) -> void:
	if _torn:
		return
	var player_position: Variant = SpiderWebPort.player_position()
	if player_position == null or not holds(player_position as Vector2):
		return
	var area := zone()
	if SpiderWebPort.player_crosses_webs():
		_torn = true
		if visual != null:
			visual.visible = false
		torn.emit(area)
		return
	if FloorWebs.stick_roll(SpiderWebPort.player()):
		caught.emit(area)

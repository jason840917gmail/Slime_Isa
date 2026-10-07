extends Node
class_name WebPatchScript
## Scene script `game.web-patch` (Phaser `features/scripts/WebPatchScript.ts`): a web lying on the
## ground (the Matron's volley, `effect.matron-web-patch`). Matron spec 5.1.
##
## A round patch that catches a normal slime walking onto it (stuck for a moment and set back
## outside, through res://game/enemy/spider_web_port.gd), while the Sticky form walks through and
## tears it quietly (no message, no flag). Never remembered: the effect that owns it fades after
## its lifetime (effect.gd frees the root). Checked every physics step (Phaser: every frame).
##
## Node: `WebPatchScript` under the effect root (no depth anchor: the root is the patch centre).
##
## Owner: boss port.

const SpiderWebPort := preload("res://game/enemy/spider_web_port.gd")

## WebPatchScript.ts:33: radius when the authored one is missing or not > 0.
const DEFAULT_RADIUS := 48.0

## JSON `radius` (50): the catch circle around the patch centre.
@export var radius: float = DEFAULT_RADIUS
## JSON `visual`: the web sprite, hidden when torn.
@export var visual: Node2D

## The slime was caught. Payload: the zone {"x", "y", "halfWidth", "halfHeight"}.
signal caught(zone: Dictionary)
## The Sticky slime tore the patch (-> TearSfx). Payload: the zone.
signal torn(zone: Dictionary)

var _torn: bool = false


func _ready() -> void:
	if not (is_finite(radius) and radius > 0.0):
		radius = DEFAULT_RADIUS


## True once the Sticky slime tore the patch.
func is_torn() -> bool:
	return _torn


## The catch box around the patch centre ({} without a Node2D parent): {"x", "y", "halfWidth":
## radius, "halfHeight": radius} (the barrier's catch sets the slime back above or below it).
func zone() -> Dictionary:
	var root := get_parent() as Node2D
	if root == null:
		return {}
	var origin := root.global_position
	return {"x": origin.x, "y": origin.y, "halfWidth": radius, "halfHeight": radius}


## WebPatchScript.ts:50-65.
func _physics_process(_delta: float) -> void:
	if _torn:
		return
	var player_position: Variant = SpiderWebPort.player_position()
	if player_position == null:
		return
	var area := zone()
	if area.is_empty():
		return
	if (player_position as Vector2).distance_to(Vector2(float(area["x"]), float(area["y"]))) > radius:
		return
	if SpiderWebPort.player_crosses_webs():
		_torn = true
		if visual != null:
			visual.visible = false
		torn.emit(area)
		return
	SpiderWebPort.catch_player(area)
	caught.emit(area)

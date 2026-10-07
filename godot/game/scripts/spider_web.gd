extends Node
class_name SpiderWebScript
## Scene script `game.spider-web` (Phaser `features/scripts/SpiderWebScript.ts`): a spider-web
## barrier (`object.spider-web`). Matron spec 5.2.
##
## A normal slime that walks into the strands is caught, stuck for a moment and set back on the
## side it came from (res://game/enemy/spider_web_port.gd). The Sticky form pushes through and
## tears it open for good, unless `tears_when_crossed` is off; a torn web is remembered by the
## story flag `web-torn.<placement persistence key>` (RunState). The web has no collision body (its
## two stakes do), so only the catch decides who passes. Checked every physics step (Phaser: every
## frame).
##
## Node: `SpiderWebScript` under the web's root Node2D (no depth anchor).
##
## Owner: boss port.

const Services := preload("res://game/shared/services.gd")
const SpiderWebPort := preload("res://game/enemy/spider_web_port.gd")

## SpiderWebScript.ts:61-62: sizes when the authored ones are missing or not > 0.
const DEFAULT_WIDTH := 200.0
const DEFAULT_DEPTH := 48.0
## `tornWebFlag` (:33-35).
const TORN_FLAG_PREFIX := "web-torn."
## Converter metadata on placed instance roots.
const PERSISTENCE_KEY_META := &"persistence_key"
const INSTANCE_ID_META := &"instance_id"

## JSON `width` (112): the catch box width.
@export var width: float = DEFAULT_WIDTH
## JSON `depth` (56): the catch box depth, just above the root (where the strands hang).
@export var depth: float = DEFAULT_DEPTH
## JSON `tearsWhenCrossed` (default true): the Sticky slime tears the web open.
@export var tears_when_crossed: bool = true
## JSON `visual`: the web sprite, hidden when torn.
@export var visual: Node2D

## The slime was caught. Payload: the zone {"x", "y", "halfWidth", "halfHeight"}.
signal caught(zone: Dictionary)
## The Sticky slime tore the web open. Payload: the zone.
signal torn(zone: Dictionary)

var _torn: bool = false


## Sanitises the sizes; a web whose torn flag is set shows torn (SpiderWebScript.ts:78-81).
func _ready() -> void:
	if not (is_finite(width) and width > 0.0):
		width = DEFAULT_WIDTH
	if not (is_finite(depth) and depth > 0.0):
		depth = DEFAULT_DEPTH
	var run := Services.run()
	if run != null and run.has_flag(torn_flag()):
		_show_torn()


## True once the Sticky slime has torn the web open (now or earlier in the run).
func is_torn() -> bool:
	return _torn


## `web-torn.<key>`: the placement's persistence key, else its instance id, else this node's path.
func torn_flag() -> String:
	return TORN_FLAG_PREFIX + web_key()


## SpiderWebScript.ts:117-123: the first ancestor (this node included) placed as an authored
## instance names the web.
func web_key() -> String:
	var node: Node = self
	while node != null:
		var key: Variant = node.get_meta(PERSISTENCE_KEY_META, "")
		if key is String and not (key as String).is_empty():
			return key
		var instance_id: Variant = node.get_meta(INSTANCE_ID_META, "")
		if instance_id is String and not (instance_id as String).is_empty():
			return instance_id
		node = node.get_parent()
	return str(get_path())


## The catch box (SpiderWebScript.ts:126-131): the web's width, `depth` deep, just above the root.
## {} without a Node2D parent.
func zone() -> Dictionary:
	var root := get_parent() as Node2D
	if root == null:
		return {}
	var origin := root.global_position
	return {"x": origin.x, "y": origin.y - depth / 2.0, "halfWidth": width / 2.0, "halfHeight": depth / 2.0}


## SpiderWebScript.ts:88-101.
func _physics_process(_delta: float) -> void:
	if _torn:
		return
	var player_position: Variant = SpiderWebPort.player_position()
	if player_position == null:
		return
	var area := zone()
	if area.is_empty():
		return
	var at := player_position as Vector2
	if absf(at.x - float(area["x"])) > float(area["halfWidth"]) or absf(at.y - float(area["y"])) > float(area["halfHeight"]):
		return
	if SpiderWebPort.player_crosses_webs():
		if tears_when_crossed:
			_tear(area)
		return
	SpiderWebPort.catch_player(area)
	caught.emit(area)


func _tear(area: Dictionary) -> void:
	_show_torn()
	var run := Services.run()
	if run != null:
		run.set_flag(torn_flag())
	SpiderWebPort.web_torn(area)
	torn.emit(area)


func _show_torn() -> void:
	_torn = true
	if visual != null:
		visual.visible = false

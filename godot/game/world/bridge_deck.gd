@tool
extends Node2D
## A bridge over water (owner, 2026-10-12; docs/godot/specs/water.md §10). The ground cells under its
## deck keep their tiles, so the river stays painted under the bridge, but lose their collision, so
## walkers cross on the deck while the deep-water squares on either side keep them from stepping
## off. A cell is under the deck when its centre is inside `deck`, so the lane is whole cells, like
## the water squares it opens; on those cells the water wake, the footsteps (wood) and swimming
## treat the ground as the deck, not the water.
##
## `WorldService.register_world` hands the cells under every deck of the world to the ground layer
## (`lay`; world_ground.gd drops their collision). In the editor each bridge outlines the cells it
## opens, so moving a bridge shows where the lane goes.
##
## Owner: world (water).

const Self := preload("res://game/world/bridge_deck.gd")
const WorldGround := preload("res://game/world/world_ground.gd")
## The editor outline of the cells the deck opens.
const OUTLINE := Color(1.0, 0.85, 0.2, 0.9)
const OUTLINE_WIDTH := 2.0

## The walkable deck in this node's coordinates. The default is the wooden footbridge's planks
## (frame 3 of 320x256-tile_4x1-level-1-landmarks.webp: 288 units long, its middle 77 above the
## bridge's bottom centre).
@export var deck: Rect2 = Rect2(-144.0, -117.0, 288.0, 80.0):
	set(value):
		deck = value
		queue_redraw()


## Opens the cells under every bridge deck below `root` on `ground` (a world_ground.gd layer).
## Returns how many cells were opened.
static func lay(root: Node, ground: TileMapLayer) -> int:
	var cells: Array[Vector2i] = []
	for node: Node in root.find_children("*", "Node2D", true, false):
		if node.get_script() == Self:
			cells.append_array((node as Self).cells_on(ground))
	var layer := ground as WorldGround
	if layer == null:
		if not cells.is_empty():
			push_warning("BridgeDeck.lay: ground '%s' has no world_ground.gd; bridge decks stay blocked" % ground.name)
		return 0
	layer.set_bridged_cells(cells)
	return cells.size()


## True when `cell` of `ground` is under a bridge deck.
static func is_bridged(ground: TileMapLayer, cell: Vector2i) -> bool:
	var layer := ground as WorldGround
	return layer != null and layer.is_bridged(cell)


## The cells of `ground` whose centre is inside the deck.
func cells_on(ground: TileMapLayer) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if ground == null or ground.tile_set == null:
		return cells
	var to_ground := ground.get_global_transform().affine_inverse() * get_global_transform()
	var area := Rect2(to_ground * deck.position, Vector2.ZERO).expand(to_ground * deck.end)
	var first := ground.local_to_map(area.position)
	var last := ground.local_to_map(area.end)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if area.has_point(ground.map_to_local(cell)):
				cells.append(cell)
	return cells


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var ground := _edited_ground()
	if ground == null:
		draw_rect(deck, OUTLINE, false, OUTLINE_WIDTH)
		return
	var size := Vector2(ground.tile_set.tile_size)
	for cell: Vector2i in cells_on(ground):
		var centre := to_local(ground.to_global(ground.map_to_local(cell)))
		draw_rect(Rect2(centre - size * 0.5, size), OUTLINE, false, OUTLINE_WIDTH)


## The `ground` layer of the world scene open in the editor (null when editing the bridge alone).
func _edited_ground() -> TileMapLayer:
	if not is_inside_tree():
		return null
	var root := get_tree().edited_scene_root
	if root == null or root == self:
		return null
	var ground := root.get_node_or_null(^"ground") as TileMapLayer
	return ground if ground != null and ground.tile_set != null else null

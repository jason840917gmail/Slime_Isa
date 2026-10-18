extends RefCounted
## The plank bridge's shared pieces (docs/godot/DUNGEONS.md "Falling planks over water"): its
## picture, drawn a 64-unit cell at a time, and the lane it opens through deep water. Used by the
## falling plank (falling_plank.gd) and the plank landing (plank_landing.gd).
##
## The sheet (scripts/art/pack-plank-art.py) is two 128 px cells: frame 0 the whole plank (a
## landing), frame 1 the loose, cracked one (a falling plank). Its boards run east-west, across a
## bridge that runs north-south; `east_west` turns them for a bridge that runs east-west.
##
## The lane: each piece adds a bridge deck child (game/world/bridge_deck.gd) over its rectangle when
## the world is built, so the deep-water cells under it lose their collision (docs/godot/specs/water.md
## §10) and stay open after the plank falls: the slime over a fallen plank is not held or pushed by
## the water's collision, and the water hazard under the bridge catches it.
##
## Owner: dungeon kit.

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const BridgeDeck := preload("res://game/world/bridge_deck.gd")

const ART := "res://asset/MAPS/objects/dungeon/plank-2x1.webp"
const CELL := 64.0
const LANE_NODE := "PlankLane"
const WHOLE := 0
const LOOSE := 1
## Without the picture: the wood's colours.
const WOOD := Color("#a8743f")
const WOOD_EDGE := Color("#5b3a1e")


static func picture() -> Texture2D:
	return SheetSprite.load_picture(ART)


## Draws frame `frame` on `canvas` over `box` (its coordinates), one picture per 64-unit cell of
## `size` (the piece's rectangle; `box` is it scaled and moved as it falls).
static func draw(canvas: CanvasItem, texture: Texture2D, box: Rect2, size: Vector2, frame: int, tint: Color, east_west: bool) -> void:
	var cells := Vector2i(maxi(1, roundi(size.x / CELL)), maxi(1, roundi(size.y / CELL)))
	var piece := box.size / Vector2(cells)
	for y in cells.y:
		for x in cells.x:
			var at := Rect2(box.position + piece * Vector2(x, y), piece)
			if texture == null:
				canvas.draw_rect(at, Color(WOOD, tint.a))
				canvas.draw_rect(at.grow(-2.0), Color(WOOD_EDGE, tint.a), false, 2.0)
				if frame == LOOSE:
					canvas.draw_line(at.position + at.size * Vector2(0.15, 0.5), at.position + at.size * Vector2(0.8, 0.42), Color(WOOD_EDGE, tint.a), 2.0)
				continue
			var cell := Vector2(texture.get_width() * 0.5, texture.get_height())
			var region := Rect2(Vector2(cell.x * frame, 0.0), cell)
			if not east_west:
				canvas.draw_texture_rect_region(texture, at, region, tint)
				continue
			# Turned a quarter: the boards run north-south, across an east-west bridge.
			var centre := at.get_center()
			canvas.draw_set_transform(centre, PI * 0.5)
			canvas.draw_texture_rect_region(texture, Rect2(-Vector2(at.size.y, at.size.x) * 0.5, Vector2(at.size.y, at.size.x)), region, tint)
			canvas.draw_set_transform(Vector2.ZERO)


## Gives `piece` (a Node2D) its lane: a bridge deck child over the rectangle `size` from its position.
## In the game only, before the world is registered (the piece's `_ready`).
static func open_lane(piece: Node2D, size: Vector2) -> void:
	if Engine.is_editor_hint() or piece.get_node_or_null(NodePath(LANE_NODE)) != null:
		return
	var lane := Node2D.new()
	lane.name = LANE_NODE
	lane.set_script(BridgeDeck)
	lane.set(&"deck", Rect2(Vector2.ZERO, size))
	piece.add_child(lane)

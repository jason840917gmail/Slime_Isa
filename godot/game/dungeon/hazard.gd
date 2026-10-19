@tool
extends Node2D
class_name Hazard
## One hazard script for the void, spikes, lava and deep water (docs/godot/DUNGEONS.md "The void, slabs
## and spikes", "Falling planks over water"; decisions archive question 70, roadmap 5.14). A hazard is the rectangle `size` from its
## position; the slime is in it when its feet are inside and it is not held up by a deck there
## (hazard_deck.gd: a standing slab, a lowered drawbridge, a landing, a shadow path), or when it
## walks on a lower level than `rim_level` (it dropped into the elevation hole painted under it:
## "the void works like the elevation's holes"). HazardWatch (hazard_watch.gd, made by the first
## hazard of a world) does the rest:
##
## - **void**: the slime falls (it spins and shrinks away over `dungeon.void.fallMs`), loses a little
##   health (`damage`, else `dungeon.void.damage`) and is put back on the rim it fell from: the last
##   safe ground it stood on, or the nearest of `return_points` to it (the bridge's start), or always
##   its `fixed_return` spot when one is set;
## - **spikes** and **lava**: it is hurt each time its invulnerability ends, until it walks out
##   (a stair up to the rim). A slab that falls from under it over a sunken pit drops it in
##   (`pit_depth` levels down);
## - **water**: deep water under a plank bridge (falling_plank.gd): the slime sinks with a splash
##   (`dungeon.water.fallMs`), loses `dungeon.water.damage` and is put back on the bank as from the
##   void. It draws nothing (the world's water shows); a slime whose form swims never falls in.
##
## Paint the void as a hole on the world's `elevation` layer and lay the hazard over the hole; it
## draws its look over it (`draw_look`: the abyss, fading in over `top_fade_px` so the hole's far
## wall sinks into the dark; the spike rows; the glowing lava), or is a flat pit in a world without
## elevation. Keep a hazard above its decks in the tree (they draw over it).
##
## Owner: dungeon kit.

const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const GROUP := &"hazards"
const KINDS: PackedStringArray = ["void", "spikes", "lava", "water"]
const SPIKES_ART := "res://asset/MAPS/objects/dungeon/spikes.webp"
const RETURN_PREFIX := "Return"
const EDITOR_FILL := {"void": Color(0.05, 0.02, 0.1, 0.45), "spikes": Color(0.55, 0.25, 0.15, 0.4),
	"lava": Color(1.0, 0.4, 0.05, 0.4), "water": Color(0.1, 0.4, 0.9, 0.35)}
const EDITOR_EDGE := Color(1.0, 0.3, 0.6, 0.9)
## The abyss: its colour, and the soft edge that fades into it.
const ABYSS := Color("#07050c")
const ABYSS_EDGE_PX := 22.0
const LAVA_DEEP := Color("#c2410c")
const LAVA_GLOW := Color("#fdba74")
## The hazard's look sits on the floor, under every body.
const LOOK_Z := -1
## A pit's cell (units) and the side wall's strip beside a side rim (ELEVATION.md "Side walls").
const PIT_CELL := 64.0
const PIT_SIDE := 24.0
## How far inside its rectangle a point must be to be in the hazard (units): the rim's collision
## stops a body's feet exactly on the hole's edge.
const EDGE_EPSILON := 0.5
## The squares (units) a pit's floor is read in.
const PIT_STEP := 8.0

@export_enum("void", "spikes", "lava", "water") var kind: String = "void":
	set(value):
		kind = value
		queue_redraw()
## The hazard's rectangle (world units from this node's position).
@export var size: Vector2 = Vector2(256, 192):
	set(value):
		size = value
		queue_redraw()
## The elevation level of the ground around it and of its decks (0 without elevation).
@export var rim_level: int = 0
## A sunken spike or lava pit: how many levels below `rim_level` its floor is.
@export var pit_depth: int = 1
## The floor level it covers (one hazard per floor level; it hurts only on its level): -99 (the
## default) takes `rim_level` - `pit_depth`. Set, it also sets the rim (`level` + `pit_depth`). Its
## rectangle may be as big as the room: it catches and draws only on the cells the `elevation`
## layer paints at that level, never on the levels above.
@export var level: int = -99:
	set(value):
		level = value
		queue_redraw()
## Health lost per hit (or per fall); < 0: `dungeon.<kind>.damage`.
@export var damage: float = -1.0
## Draws the abyss, the spikes or the lava itself (over an elevation hole too: the void's dark).
@export var draw_look: bool = true:
	set(value):
		draw_look = value
		queue_redraw()
## The void's dark grows over this much of its top, and spikes and lava start below it (an
## elevation hole's far wall: 64 a level).
@export var top_fade_px: float = 0.0:
	set(value):
		top_fade_px = value
		queue_redraw()
## Where a fall puts the slime back (Node2D markers: their spot is the slime's centre); empty: its
## children named "Return..."; none: the last safe ground the slime stood on.
@export var return_points: Array[NodePath] = []
## A fixed safe spot (any Node2D) every fall from this hazard returns to, wherever the slime fell
## and whatever ground it last stood on; several hazards can share one. Empty: the nearest of
## `return_points` to the last safe ground.
@export var fixed_return: NodePath

var _spikes: Texture2D
## The look's holder inside the elevation drawing (`_attach_look`).
var _look: Node2D


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	z_index = LOOK_Z
	if kind == "spikes" or kind == "lava":
		# drawn again once the elevation is there (the editor's preview too)
		_redraw_with_elevation.call_deferred()
	if Engine.is_editor_hint():
		return
	var watch_script := load("res://game/dungeon/hazard_watch.gd") as GDScript
	watch_script.call(&"ensure", self)


## The hazard in world coordinates.
func rect() -> Rect2:
	return Rect2(global_position, size)


## The floor level the hazard covers (`level`, else `rim_level` - `pit_depth`; a void or water:
## its rim's level, it has no floor).
func floor_level() -> int:
	if level != -99:
		return level
	if kind == "spikes" or kind == "lava":
		return rim_level - pit_depth
	return rim_level


## The level of the ground around it, its decks' level (`rim_level`, or `level` + `pit_depth`).
func rim() -> int:
	return level + pit_depth if level != -99 else rim_level


## True when `point` (world units) is in the hazard: in its rectangle and, for a pit (spikes,
## lava), on a cell the `elevation` layer paints at its `floor_level()` (unpainted cells are level
## 0; stairs never: they lead out). So a pit's hazard follows the painted floor of its level, however
## big its rectangle is drawn. A void or water, or a world without elevation, covers its whole
## rectangle.
func covers(point: Vector2) -> bool:
	# strictly inside: feet held at a rim stop on the hole's edge, which is the rim's, not the hole's
	if not rect().grow(-EDGE_EPSILON).has_point(point):
		return false
	if kind != "spikes" and kind != "lava":
		return true
	var painted := _painted_layer()
	if painted == null:
		return true
	# a point on a cell's edge is in only when the cells on both sides are (a rim's edge is not)
	for d: Vector2 in [Vector2(0.0, -EDGE_EPSILON), Vector2(0.0, EDGE_EPSILON), Vector2(-EDGE_EPSILON, 0.0), Vector2(EDGE_EPSILON, 0.0)]:
		if not _cell_on_floor(painted, painted.local_to_map(painted.to_local(point + d))):
			return false
	return true


## Whether painted cell `cell` is open floor of this hazard's level (not a stair).
func _cell_on_floor(painted: TileMapLayer, cell: Vector2i) -> bool:
	var data := painted.get_cell_tile_data(cell)
	if data == null:
		return floor_level() == 0
	if painted.get_cell_atlas_coords(cell).y > 0:
		return false
	return int(data.get_custom_data(&"elevation_level")) == floor_level()


## The world's painted `elevation` layer (its holes), or null.
func _painted_layer() -> TileMapLayer:
	var elevation := _elevation()
	var layer: Variant = elevation.get(&"layer") if elevation != null else null
	return layer as TileMapLayer


## Health lost per hit or fall.
func hit_damage() -> float:
	if damage >= 0.0:
		return damage
	return DungeonState.number(kind + ".damage", 10.0)


## Its return markers' spots (global).
func return_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for path: NodePath in return_points:
		var node := get_node_or_null(path) as Node2D
		if node != null:
			out.append(node.global_position)
	if out.is_empty():
		for child: Node in get_children():
			if child is Node2D and String(child.name).begins_with(RETURN_PREFIX):
				out.append((child as Node2D).global_position)
	return out


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if Engine.is_editor_hint():
		draw_rect(area, EDITOR_FILL.get(kind, Color(1, 0, 1, 0.3)))
		draw_rect(area, EDITOR_EDGE, false, 2.0)
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, Vector2(8, 22), "hazard: " + kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, EDITOR_EDGE)
	if not draw_look:
		return
	if (kind == "spikes" or kind == "lava") and _attach_look():
		_look.queue_redraw()
		return
	_draw_look_on(self)


## A pit's look (spikes, lava) is the bottom of the pit: it is drawn inside the world's elevation
## drawing, over the pit's ground (Shade) and under every wall, rim, stair and higher floor (Sides
## and after), so only where its floor is open to view do the spikes show; slabs and bodies draw
## over it. The holder ("HazardLook-<name>", the last child of the elevation's Shade, not saved; not
## top_level, which would take it out of that draw order) is
## made again after each rebuild of the elevation drawing. False without an elevation drawing.
func _attach_look() -> bool:
	if _look != null and is_instance_valid(_look) and _look.is_inside_tree():
		_look.global_transform = global_transform
		return true
	var elevation := _elevation()
	var shade := elevation.get_node_or_null(^"Shade") if elevation != null else null
	if shade == null:
		return false
	_look = Node2D.new()
	_look.name = "HazardLook-" + str(name)
	_look.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_look.draw.connect(func() -> void: _draw_look_on(_look))
	_look.tree_exiting.connect(_look_gone)
	shade.add_child(_look)
	_look.global_transform = global_transform
	return true


func _look_gone() -> void:
	_look = null
	if is_inside_tree() and not is_queued_for_deletion():
		_redraw_with_elevation.call_deferred()


func _exit_tree() -> void:
	if _look != null and is_instance_valid(_look):
		_look.tree_exiting.disconnect(_look_gone)
		_look.queue_free()
	_look = null


func _draw_look_on(ci: CanvasItem) -> void:
	var area := Rect2(Vector2.ZERO, size)
	# Spikes and lava lie on a pit's floor, below its far wall (`top_fade_px`).
	var floor_area := Rect2(area.position + Vector2(0.0, top_fade_px), Vector2(area.size.x, maxf(0.0, area.size.y - top_fade_px)))
	var cells := _pit_floor_cells()
	match kind:
		"void":
			_draw_abyss(ci, area)
		"spikes":
			if cells.is_empty() and _painted_layer() == null:
				_draw_spikes(ci, floor_area)
			for cell: Rect2 in cells:
				_draw_spikes(ci, cell)
		"lava":
			if cells.is_empty() and _painted_layer() == null:
				_draw_lava(ci, floor_area)
			for cell: Rect2 in cells:
				_draw_lava(ci, cell)


## The cells of its floor level inside its rectangle (local rects, clipped to it), in runs along each
## row so the spikes tile is drawn in few strips. Empty without the painted elevation layer (the
## whole look is drawn then).
func _pit_floor_cells() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not is_inside_tree():
		return out
	var painted := _painted_layer()
	if painted == null:
		return out
	var area := rect()
	var step := float(painted.tile_set.tile_size.x) if painted.tile_set != null else PIT_CELL
	var first := painted.local_to_map(painted.to_local(area.position))
	var last := painted.local_to_map(painted.to_local(area.end - Vector2(0.01, 0.01)))
	for y in range(first.y, last.y + 1):
		var start := -1
		for x in range(first.x, last.x + 2):
			var on := x <= last.x and _cell_on_floor(painted, Vector2i(x, y))
			if on and start < 0:
				start = x
			elif not on and start >= 0:
				var from := painted.to_global(painted.map_to_local(Vector2i(start, y))) - Vector2(step, step) * 0.5
				var run := Rect2(from, Vector2(float(x - start) * step, step)).intersection(area)
				if run.has_area():
					out.append(Rect2(run.position - global_position, run.size))
				start = -1
	return out


## The world's elevation drawing: the registered world's in the game, else (the editor, a room scene
## on its own) the one mounted under the scene's ground layer (ElevationLayer's preview).
func _elevation() -> Node:
	var world: Variant = Services.world() if not Engine.is_editor_hint() else null
	if world != null and world.elevation != null:
		return world.elevation
	var at: Node = get_parent()
	while at != null:
		var ground := at.get_node_or_null(^"ground")
		if ground != null:
			for child: Node in ground.get_children():
				if child.has_method(&"level_at"):
					return child
		at = at.get_parent()
	return null


func _redraw_with_elevation() -> void:
	for i in 10:
		if not is_inside_tree():
			return
		if _elevation() != null:
			queue_redraw()
			return
		await get_tree().process_frame


## A deep black pit: over its top `top_fade_px` the dark grows out of nothing (an elevation hole's
## far wall shows, sinking into the dark), below it is black; its other edges are soft.
func _draw_abyss(ci: CanvasItem, area: Rect2) -> void:
	var fade := clampf(top_fade_px, 0.0, area.size.y)
	var clear := Color(ABYSS, 0.0)
	if fade > 0.0:
		ci.draw_polygon(PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
			Vector2(area.end.x, area.position.y + fade), Vector2(area.position.x, area.position.y + fade)]),
			PackedColorArray([clear, clear, ABYSS, ABYSS]))
	var body := Rect2(area.position + Vector2(0.0, fade), Vector2(area.size.x, area.size.y - fade))
	var steps := 4
	for i in steps:
		var inset := ABYSS_EDGE_PX * 0.5 * float(i) / float(steps)
		var band := Rect2(body.position + Vector2(inset, 0.0), Vector2(body.size.x - inset * 2.0, body.size.y - inset))
		ci.draw_rect(band, Color(ABYSS, 0.4 + 0.6 * float(i + 1) / float(steps)))


func _draw_spikes(ci: CanvasItem, area: Rect2) -> void:
	if _spikes == null:
		_spikes = SheetSprite.load_picture(SPIKES_ART)
	if _spikes == null:
		ci.draw_rect(area, Color("#3a2a20"))
		var x := 8.0
		while x < area.size.x:
			var y := 8.0
			while y < area.size.y:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, y + 6), Vector2(x, y - 8), Vector2(x + 5, y + 6)]), Color("#8a8f99"))
				y += 22.0
			x += 22.0
		return
	# The tile is 128 px a cell (two pixels a unit); its pattern follows the hazard, so strips join.
	ci.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
	ci.draw_texture_rect_region(_spikes, Rect2(area.position * 2.0, area.size * 2.0), Rect2(area.position * 2.0, area.size * 2.0))
	ci.draw_set_transform(Vector2.ZERO)


func _draw_lava(ci: CanvasItem, area: Rect2) -> void:
	ci.draw_rect(area, LAVA_DEEP)
	ci.draw_rect(area.grow(-10.0), Color(LAVA_GLOW, 0.35))

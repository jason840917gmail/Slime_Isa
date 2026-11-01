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
## Over painted elevation its floor and its rim come from the paint (`_read_paint`): its floor is the
## lowest level painted under its rectangle (a pit's `level` when set), its rim the lowest level
## painted round that floor. It catches only on the cells painted below the rim (a pit: on its floor),
## so a rectangle that also covers rim-level floor catches nothing there; `rim_level`, `pit_depth` and
## a void's `level` that disagree with the paint are warned about and not used. Where nothing under it
## is painted lower (deep water on flat ground), and without elevation, it covers its whole rectangle.
##
## Its `z_index` (LOOK_Z, set in `_ready`) is not stored in the scene (`_validate_property`).
##
## Owner: dungeon kit.

const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")

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
## `level` unset; `_paint_floor` / `_paint_rim` when the paint gives none.
const NO_LEVEL := -99

@export_enum("void", "spikes", "lava", "water") var kind: String = "void":
	set(value):
		kind = value
		queue_redraw()
## The hazard's rectangle (world units from this node's position).
@export var size: Vector2 = Vector2(256, 192):
	set(value):
		size = value
		queue_redraw()
## The elevation level of the ground around it and of its decks (0 without elevation). Over painted
## elevation the paint's rim is used (`rim`).
@export var rim_level: int = 0
## A sunken spike or lava pit: how many levels below `rim_level` its floor is (without painted
## elevation; over it, the paint's floor is used).
@export var pit_depth: int = 1
## A spike or lava pit's floor level (one hazard per floor level; it hurts only on its level): -99
## (the default) takes the lowest level painted under its rectangle (without paint `rim_level` -
## `pit_depth`). Its rectangle may be as big as the room: it catches and draws only on the cells the
## `elevation` layer paints at that level, never on the levels above. A void or deep water ignores it.
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
## Its floor and rim as the `elevation` layer paints them (`_read_paint`), NO_LEVEL when it paints no
## floor lower than the ground round it; read once in the game.
var _paint_floor := NO_LEVEL
var _paint_rim := NO_LEVEL
var _paint_read := false
## Its world's painted `elevation` layer, once looked up (`_painted_layer`).
var _layer: TileMapLayer
var _layer_found := false


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


## `z_index` is LOOK_Z, set in `_ready`: not stored, so opening a world in the editor never writes it.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "z_index":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


## The hazard in world coordinates.
func rect() -> Rect2:
	return Rect2(global_position, size)


## True for a sunken pit (spikes, lava): it hurts on its floor; a void or deep water swallows.
func is_pit() -> bool:
	return kind == "spikes" or kind == "lava"


## The floor level the hazard covers: over painted elevation the paint's (a pit's `level` when set,
## else the lowest level painted under it); without, a pit's `level`, else `rim_level` - `pit_depth`,
## and a void's or water's rim (it has no floor).
func floor_level() -> int:
	if is_pit() and level != NO_LEVEL:
		return level
	_read_paint()
	if _paint_floor != NO_LEVEL:
		return _paint_floor
	if is_pit():
		return rim_level - pit_depth
	return rim_level


## The level of the ground around it, its decks' level: over painted elevation the paint's (the
## lowest level painted round its floor), else `rim_level` (a pit with `level` set: `level` +
## `pit_depth`).
func rim() -> int:
	_read_paint()
	if _paint_rim != NO_LEVEL:
		return _paint_rim
	return level + pit_depth if is_pit() and level != NO_LEVEL else rim_level


## True when `point` (world units) is in the hazard: in its rectangle and, over painted elevation,
## on a cell it covers (`_cell_covered`: a pit's cells painted at its `floor_level()`, a void's or
## water's cells painted below its `rim()`; unpainted cells are level 0, stairs never: they lead out).
## So it follows the painted hole, however big its rectangle is drawn. A void or water with nothing
## painted lower under it (deep water on flat ground), or a world without elevation, covers its whole
## rectangle.
func covers(point: Vector2) -> bool:
	# strictly inside: feet held at a rim stop on the hole's edge, which is the rim's, not the hole's
	if not rect().grow(-EDGE_EPSILON).has_point(point):
		return false
	var painted := _painted_layer()
	if painted == null:
		return true
	if not is_pit():
		_read_paint()
		if _paint_floor == NO_LEVEL:
			return true
	# a point on a cell's edge is in only when the cells on both sides are (a rim's edge is not)
	for d: Vector2 in [Vector2(0.0, -EDGE_EPSILON), Vector2(0.0, EDGE_EPSILON), Vector2(-EDGE_EPSILON, 0.0), Vector2(EDGE_EPSILON, 0.0)]:
		if not _cell_covered(painted, painted.local_to_map(painted.to_local(point + d))):
			return false
	return true


## Whether painted cell `cell` is one it covers: a pit's open floor of its level, a void's or water's
## hole below its rim (never a stair).
func _cell_covered(painted: TileMapLayer, cell: Vector2i) -> bool:
	var at := _painted_level(painted, cell)
	if at == NO_LEVEL:
		return false
	return at == floor_level() if is_pit() else at < rim()


## The level painted on `cell` (unpainted 0; a stair or ramp NO_LEVEL).
static func _painted_level(painted: TileMapLayer, cell: Vector2i) -> int:
	var data := painted.get_cell_tile_data(cell)
	if data == null:
		return 0
	if painted.get_cell_atlas_coords(cell).y > 0:
		return NO_LEVEL
	return int(data.get_custom_data(&"elevation_level"))


## Reads its floor and rim from the `elevation` paint (`_paint_floor`, `_paint_rim`): the floor is a
## pit's `level` when set, else the lowest level painted on the cells under its rectangle; the rim the
## lowest level painted higher than the floor on the cells beside the floor's cells (inside its
## rectangle or out: the ground the hole is dug into, not a higher cliff beside it). Both NO_LEVEL
## when no cell of the floor has higher ground beside it. Once in the game (then warns when its
## settings disagree), every time in the editor.
func _read_paint() -> void:
	if _paint_read and not Engine.is_editor_hint():
		return
	var painted := _painted_layer()
	if painted == null:
		return
	_paint_read = true
	_paint_floor = NO_LEVEL
	_paint_rim = NO_LEVEL
	var first := painted.local_to_map(painted.to_local(global_position))
	var last := painted.local_to_map(painted.to_local(global_position + size - Vector2(0.01, 0.01)))
	var lowest := NO_LEVEL
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var at := _painted_level(painted, Vector2i(x, y))
			if at != NO_LEVEL and (lowest == NO_LEVEL or at < lowest):
				lowest = at
	var floor_at := level if is_pit() and level != NO_LEVEL else lowest
	var around := NO_LEVEL
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if _painted_level(painted, Vector2i(x, y)) != floor_at:
				continue
			for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var beside := _painted_level(painted, Vector2i(x, y) + d)
				if beside != NO_LEVEL and beside > floor_at and (around == NO_LEVEL or beside < around):
					around = beside
	if around == NO_LEVEL:
		return
	_paint_floor = floor_at
	_paint_rim = around
	if not Engine.is_editor_hint():
		_warn_against_paint()


## Warns (once) when its settings say another floor or rim than the paint under it does (the paint is
## used): a pit's `rim_level` - `pit_depth` (or `level` + `pit_depth`), a void's `level`.
func _warn_against_paint() -> void:
	var said_rim := level + pit_depth if level != NO_LEVEL else rim_level
	var said_floor := level if level != NO_LEVEL else rim_level - pit_depth
	var wrong := said_rim != _paint_rim or (is_pit() and said_floor != _paint_floor) \
		or (not is_pit() and level != NO_LEVEL and level != _paint_floor)
	if wrong:
		push_warning("Hazard %s (%s): its settings give floor %d, rim %d (rim_level %d, pit_depth %d, level %d); the elevation paints floor %d, rim %d under it, which it uses" % [
			get_path(), kind, said_floor, said_rim, rim_level, pit_depth, level, _paint_floor, _paint_rim])


## The painted `elevation` layer (its holes) of the world scene it stands in (never another world's:
## it is read before its world is registered), or null when that world paints none. Looked up once in
## the game.
func _painted_layer() -> TileMapLayer:
	if _layer_found and not Engine.is_editor_hint():
		return _layer if is_instance_valid(_layer) else null
	var at: Node = get_parent()
	while at != null:
		var ground := Elevation.find_ground_in(at)
		if ground != null:
			var painted := Elevation.find_layer(ground)
			_layer = painted if painted != null and painted.get_used_rect().has_area() else null
			_layer_found = true
			return _layer
		at = at.get_parent()
	return null


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


## The cells it covers inside its rectangle (`_cell_covered`: a pit's floor; local rects, clipped to
## it), in runs along each row so the spikes tile is drawn in few strips. Empty without the painted
## elevation layer (the whole look is drawn then), and for a void or water with nothing painted lower
## under it (it covers its whole rectangle).
func _pit_floor_cells() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not is_inside_tree():
		return out
	var painted := _painted_layer()
	if painted == null:
		return out
	if not is_pit():
		_read_paint()
		if _paint_floor == NO_LEVEL:
			return out
	var area := rect()
	var step := float(painted.tile_set.tile_size.x) if painted.tile_set != null else PIT_CELL
	var first := painted.local_to_map(painted.to_local(area.position))
	var last := painted.local_to_map(painted.to_local(area.end - Vector2(0.01, 0.01)))
	for y in range(first.y, last.y + 1):
		var start := -1
		for x in range(first.x, last.x + 2):
			var on := x <= last.x and _cell_covered(painted, Vector2i(x, y))
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
		var ground := Elevation.find_ground_in(at)
		var found: Node = Elevation.find_in(ground) if ground != null else null
		if found != null:
			return found
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

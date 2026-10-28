@tool
extends Node2D
## The painted fences (docs/godot/FENCES.md): art, shadows, depth silhouettes and collision.
##
## A world paints every fence on one `fences` TileMapLayer (fence_layer.gd, fence_tileset.tres),
## on flat ground or on any elevation level. Each painted cell is a post in its tile's style, and
## rails join it to the neighbours its tile links to (`connected_links`). Fences never read or
## change cliff rims or stairs; of the elevation they use only a cell's level (ElevationGrid) and
## the depth map (ElevationOcclusion), and draw with its mesh helper and shader includes.
##
## A world mounts one node named "Fences" (under the Elevation node, or beside the ground layer in
## a flat world). The renderer uses the style's kit (scripts/art/build-fence-art.py,
## asset/MAPS/fences/<style>-*.png and <style>.json): one post at each painted cell and rails
## between linked neighbours. Diagonal rails shear with the slope, posts stay upright, and the faces
## are lit consistently. The pieces:
##   - posts and rails are MeshInstance2Ds under "FencePieces", a y-sorted Node2D beside the ground
##     layer (never saved with the scene), so they sort with bodies and props;
##   - their silhouettes go into the terrain's depth map (ElevationOcclusion.add_occluder, only where
##     the art is opaque), so a body behind a fence on a higher level shows as its ghost behind it,
##     and a fence pixel behind nearer terrain is not drawn (fence.gdshader);
##   - soft shadows on the ground, falling to the lower right ("Shadows").
## With `collide`, each level that has fences gets a static body on its physics layer (named
## "level <n>" in project.godot): one thin band per link from post foot to post foot, raised to the
## rails' feet (`bandAbove` to `bandBelow` above the foot line; `sideHalfWidth` each side of a
## north-south link), one post rect per post (the kit's post width), and a lone tile's two posts and
## the band between. `blocks_point` (the tests' probe), `blocks_rect` and `blocks_sweep` test the
## same bands, so hops, drops and landings (Elevation.body_fits, ledge_below) do not pass a fence
## either.
##
## A divider gate's cell (a gate tile, GATE_STYLES) draws no post: the fence layer keeps a divider
## gate object on it (fence_layer.gd `sync_gates`), and the fences join the posts beside it along its
## line (`gate_axis`) to its block: rails from each post up to the block's edge and their bands
## (`_add_gate_links`), so a shut gate closes its whole cell; the gate's own body covers the block.
##
## A cracked tile (the palette's cracked row, data layer `fence_cracked`) is an all-neighbour post
## with a crack drawn over it (docs/godot/FENCES.md "Cracked fences"). In the game it is a Goo Bomb
## target (`CrackedPost`, group `blast_targets`): a blast whose ellipse holds its foot breaks it for
## good (the story flag `crack_flag`), and the fences are built again without it, so its post, the
## rails that joined it and their collision are gone.
##
## Owner: world (fences).

const Self := preload("res://game/world/fences/fences.gd")
const Services := preload("res://game/shared/services.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const ElevationOcclusion := preload("res://game/world/elevation/elevation_occlusion.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const FENCE_SHADER := preload("res://game/world/fences/fence.gdshader")
const DEPTH_SHADER := preload("res://game/world/fences/fence_depth.gdshader")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const DividerGateScript := preload("res://game/dungeon/divider_gate.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
## Gate tiles of a divider style (docs/godot/FENCES.md "Dungeon dividers"): style -> the gate's kind.
const GATE_STYLES := {"lair-divider-eye": "eye", "lair-divider-pen": "pen"}
## How wide (px of the post art) the end of a front run's rails at a gate is (`_add_rail_end`).
const RAIL_END_PX := 6.0

const NODE_NAME := "Fences"
## The y-sorted holder of the pieces, beside the ground layer.
const PIECES_NAME := "FencePieces"
## The fence tile set's data layers: the style a painted cell's fence takes, and the neighbour its
## arrow points to (an index into DIRECTIONS, ALL_NEIGHBORS_DIRECTION for the all-neighbour tile).
const STYLE_DATA_LAYER := "fence_style"
const DIRECTION_DATA_LAYER := "fence_direction"
const CRACKED_DATA_LAYER := "fence_cracked"
## A cracked post's own picture, drawn in place of the post (scripts/art/build-cracked-fence-posts.py,
## 2 px per unit), and its px below the post's foot (the build's FOOT_PAD).
const CRACKED_POST := "res://asset/MAPS/fences/%s-post-cracked.png"
const CRACKED_FOOT_PAD := 6.0
## A broken post's give-way: its line, debris and dust.
const CRACK_BREAK_TEXT := "The fence gives way!"
const CRACK_PEBBLES := 10
const CRACK_PUFFS := 6
const ALL_NEIGHBORS_DIRECTION := -1
## An edge style's corner tiles (fence_direction this plus a diagonal's DIRECTIONS index: 9 north-east,
## 11 south-east, 13 south-west, 15 north-west): the corner block alone in that corner of the cell.
const EDGE_CORNER_DIRECTION := 8
## Direction from a painted cell to a connected neighbor: N, NE, E, SE, S, SW, W, NW.
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1),
		Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]
## The direction a lone all-neighbour tile draws its stub in (east, along the screen).
const LONE_STUB_DIRECTION := 2
## A style's kit: art/<style>-posts.png, -rails.png, -rails-side.png and <style>.json.
const KIT := "res://asset/MAPS/fences/%s%s"
## Gameplay values (game-constants.json `fences`): a band's top and bottom edge above the posts'
## foot line, and the half width of a north-south link's band and of a post's rect.
const DEFAULTS := {"bandAbove": 10.0, "bandBelow": 2.0, "sideHalfWidth": 7.0}
## How far two shapes must overlap to count (a body resting against a band only touches it).
const OVERLAP_EPSILON := 0.05
## Rails shading by link direction (the art is painted facing south).
const SHADE_FRONT := 1.0
const SHADE_SOUTH_WEST := 1.1
const SHADE_SOUTH_EAST := 0.8
const SHADE_TOP := 1.0
## Vertex colour b: which art a vertex samples.
const KIND_POST := 0.0
const KIND_RAILS := 0.5
const KIND_SIDE := 1.0
## Depth occluders tell rails and side rails from posts by UV (fence_depth.gdshader).
const DEPTH_UV_OFFSET := 10000.0
## Shadows: the light's fall on the ground (elevation_cast_shadow.gdshaderinc `fall`), the shadow's length per
## unit of height, how dark it is, and the contact shadow around a post's foot (world units).
const SHADOW_FALL := Vector2(0.94, 0.34)
const SHADOW_PER_HEIGHT := 0.45
const SHADOW_ALPHA := 0.3
const CONTACT_ALPHA := 0.45
const CONTACT_RADIUS := Vector2(10.0, 4.5)
## The `world` physics layer (project.godot layer 1): every walker's mask has it.
const WORLD_LAYER := 1
var grid: ElevationGrid
var ground: TileMapLayer
var cell := 64.0
var _pieces: Node2D
var _cell_offset := Vector2i.ZERO
## Mounted on flat ground (no Elevation): no body is tracked onto a level layer there, so the level-0
## collision goes on the `world` layer (`_build_collision`).
var _flat := false
## style -> its kit (the JSON), or {} when it has no art.
var _kits: Dictionary = {}
var _materials: Dictionary = {}
## level -> Array of collision boxes (this node's space): {"centre": Vector2, "half": Vector2 (half
## length along the box's axis, half thickness across), "axis": Vector2 (unit), "bounds": Rect2}.
## The static bodies and `blocks_*` both use them.
var _boxes: Dictionary = {}
## game-constants.json `fences`, read once per build.
var _band_above := 10.0
var _band_below := 2.0
var _side_half := 7.0
## The depth map the silhouettes went into and the silhouettes (ElevationOcclusion.add_occluder).
var _occlusion: ElevationOcclusion
var _occluders: Array = []
## The last build's inputs, to build again when a cracked post breaks (`_rebuild_after_break`).
var _painted: TileMapLayer
var _collide := false
## level -> its physics layer's bit (`_level_bit`), read from the project settings once.
static var _level_bits := {}
## The painted cells outside the grid already warned about (layer path and cell), once a session.
static var _outside_warned := {}


## Builds the fences from the `fences` layer beside `ground_layer`; null (and old fences removed)
## when there is none. With an Elevation (`elevation`, child of the ground layer) the node goes
## under it and takes its grid's levels, row offset and depth map; in a flat world (`elevation`
## null) it goes beside the ground layer on a level-0 grid of the map's size.
static func mount(ground_layer: TileMapLayer, elevation: Node2D, the_grid: ElevationGrid,
		occlusion: ElevationOcclusion, collide: bool) -> Self:
	if ground_layer == null or ground_layer.get_parent() == null or ground_layer.tile_set == null:
		return null
	var parent: Node = elevation if elevation != null else ground_layer.get_parent()
	var painted := find_layer(ground_layer)
	var existing := find_in(parent)
	if elevation != null:
		# fences mounted on flat ground before the world had an Elevation (only a Fences node)
		var flat_renderer := find_in(ground_layer.get_parent())
		if flat_renderer != null and flat_renderer != existing:
			flat_renderer.queue_free()
	if painted == null or painted.get_used_cells().is_empty():
		if existing != null:
			existing.queue_free()
		return null
	if the_grid == null:
		var used := ground_layer.get_used_rect()
		var columns := int(ground_layer.get_meta("columns", used.end.x))
		var rows := int(ground_layer.get_meta("rows", used.end.y))
		the_grid = ElevationGrid.build(columns, rows, {}, {})
	var fences := existing
	if fences == null:
		fences = Self.new()
		fences.name = NODE_NAME
		parent.add_child(fences)
	else:
		parent.move_child(fences, -1)
	if elevation == null:
		fences.global_transform = ground_layer.global_transform
	var cell_offset := Vector2i.ZERO
	if elevation != null:
		cell_offset = elevation.get("cell_offset")
	fences._flat = elevation == null
	fences.build(ground_layer, painted, the_grid, occlusion, collide, cell_offset)
	return fences


## The fences layer beside `ground_layer` (a sibling TileMapLayer whose tile set has the
## `fence_style` data layer), or null.
static func find_layer(ground_layer: TileMapLayer) -> TileMapLayer:
	var parent := ground_layer.get_parent() if ground_layer != null else null
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var candidate := child as TileMapLayer
		if candidate != null and candidate.name == "fences" and candidate != ground_layer and candidate.tile_set != null \
				and candidate.tile_set.has_custom_data_layer_by_name(STYLE_DATA_LAYER):
			return candidate
	return null


## A gameplay value of game-constants.json `fences` (DEFAULTS without the autoload).
static func setting(key: String) -> float:
	var constants := Services.constants()
	if constants == null:
		return float(DEFAULTS[key])
	return constants.number("fences." + key)


## The line a divider gate painted at `cell` of the `painted` fences layer stands in: east-west
## (Vector2i.RIGHT) when a fence cell (not a gate) is painted east or west of it, else north-south
## (Vector2i.DOWN) when one is painted north or south of it, else east-west. The fences join the gate
## to the cells beside it along that line (`_add_gate_links`) and the gate turns its body with it
## (divider_gate.gd `fit_to_line`).
static func gate_axis(painted: TileMapLayer, cell: Vector2i) -> Vector2i:
	for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
		for side: Vector2i in [-axis, axis]:
			var style := painted_style(painted, cell + side)
			if not style.is_empty() and not GATE_STYLES.has(style):
				return axis
	return Vector2i.RIGHT


## The style painted at `cell` of a fences layer ("" where nothing is).
static func painted_style(painted: TileMapLayer, cell: Vector2i) -> String:
	if painted == null or painted.tile_set == null or not painted.tile_set.has_custom_data_layer_by_name(STYLE_DATA_LAYER):
		return ""
	var data := painted.get_cell_tile_data(cell)
	return str(data.get_custom_data(STYLE_DATA_LAYER)) if data != null else ""


## True when a fence's collision on `level` covers `world_point` (the tests' probe).
func blocks_point(world_point: Vector2, level: int) -> bool:
	var point := world_point - global_position
	for box: Dictionary in _boxes.get(level, []):
		if not (box["bounds"] as Rect2).has_point(point):
			continue
		var local := _to_box(box, point)
		var half: Vector2 = box["half"]
		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			return true
	return false


## True when a fence's collision on `level` overlaps `world_rect` (more than touching it): a body's
## rect fits nowhere a fence stands (Elevation.body_fits).
func blocks_rect(world_rect: Rect2, level: int) -> bool:
	var rect := Rect2(world_rect.position - global_position, world_rect.size)
	var rect_centre := rect.get_center()
	var rect_half := rect.size * 0.5
	for box: Dictionary in _boxes.get(level, []):
		if not (box["bounds"] as Rect2).grow(-OVERLAP_EPSILON).intersects(rect):
			continue
		# Separating axes: the rect's two and the box's two.
		var axis: Vector2 = box["axis"]
		var across := Vector2(-axis.y, axis.x)
		var half: Vector2 = box["half"]
		var offset := rect_centre - (box["centre"] as Vector2)
		var separated := false
		for test: Vector2 in [Vector2.RIGHT, Vector2.DOWN, axis, across]:
			var box_reach := half.x * absf(axis.dot(test)) + half.y * absf(across.dot(test))
			var rect_reach := rect_half.x * absf(test.x) + rect_half.y * absf(test.y)
			if absf(offset.dot(test)) >= box_reach + rect_reach - OVERLAP_EPSILON:
				separated = true
				break
		if not separated:
			return true
	return false


## True when the segment `world_from` -> `world_to` passes through a fence's collision on `level`
## (touching its edge does not count): a ledge probe from a body's side (Elevation.ledge_below).
func blocks_sweep(world_from: Vector2, world_to: Vector2, level: int) -> bool:
	var from := world_from - global_position
	var to := world_to - global_position
	var sweep_bounds := Rect2(from, Vector2.ZERO).expand(to)
	for box: Dictionary in _boxes.get(level, []):
		if not (box["bounds"] as Rect2).grow(OVERLAP_EPSILON).intersects(sweep_bounds, true):
			continue
		# Clip the segment, in the box's frame, to the box shrunk by the epsilon.
		var a := _to_box(box, from)
		var d := _to_box(box, to) - a
		var half: Vector2 = box["half"] - Vector2.ONE * OVERLAP_EPSILON
		var t0 := 0.0
		var t1 := 1.0
		var inside := true
		for i in 2:
			if absf(d[i]) < 0.000001:
				if absf(a[i]) >= half[i]:
					inside = false
					break
				continue
			var near := (-half[i] - a[i]) / d[i]
			var far := (half[i] - a[i]) / d[i]
			if near > far:
				var swap := near
				near = far
				far = swap
			t0 = maxf(t0, near)
			t1 = minf(t1, far)
			if t0 >= t1:
				inside = false
				break
		if inside:
			return true
	return false


## `point` (this node's space) in `box`'s frame: x along its axis, y across, from its centre.
static func _to_box(box: Dictionary, point: Vector2) -> Vector2:
	var axis: Vector2 = box["axis"]
	var offset := point - (box["centre"] as Vector2)
	return Vector2(offset.dot(axis), offset.dot(Vector2(-axis.y, axis.x)))


## The pieces holder and the silhouettes live outside this node: they go when it is freed. Leaving the
## tree keeps them (an editor tab switch takes the whole scene out of the tree for a while, pieces,
## depth map and all, and puts it back: nothing would rebuild them).
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if is_instance_valid(_pieces) and not _pieces.is_queued_for_deletion():
		_pieces.queue_free()
	_pieces = null
	_drop_occluders()


func build(ground_layer: TileMapLayer, painted: TileMapLayer, the_grid: ElevationGrid,
		occlusion: ElevationOcclusion, collide: bool, cell_offset: Vector2i = Vector2i.ZERO) -> void:
	_clear()
	_band_above = setting("bandAbove")
	_band_below = setting("bandBelow")
	_side_half = setting("sideHalfWidth")
	grid = the_grid
	ground = ground_layer
	_cell_offset = cell_offset
	_painted = painted
	_collide = collide
	cell = float(ground.tile_set.tile_size.x)
	_pieces = Node2D.new()
	_pieces.name = PIECES_NAME
	_pieces.y_sort_enabled = true
	ground.get_parent().add_child(_pieces)
	# Vertices use the elevation grid's space, including its offset for rows above the map.
	# This sibling holder must share that origin with the shadows, depth silhouettes and collision.
	_pieces.global_transform = global_transform
	var shadows := MeshData.new()
	var depth := {}
	_add_connected_network(_painted_connections(painted), shadows, depth)
	if not shadows.is_empty():
		var instance := MeshInstance2D.new()
		instance.name = "Shadows"
		instance.mesh = shadows.to_mesh()
		add_child(instance)
	_occlusion = occlusion
	if occlusion != null and occlusion.texture != null:
		for style: String in depth:
			var pieces: Array = depth[style]
			pieces.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			var arrays := MeshData.new()
			for piece: Array in pieces:
				var mesh_data: MeshData = piece[1]
				for i in mesh_data.vertices.size():
					arrays.add(mesh_data.vertices[i], mesh_data.uvs[i], mesh_data.colors[i])
			var occluder := occlusion.add_occluder(arrays.to_mesh(), _depth_material(style))
			if occluder != null:
				_occluders.append(occluder)
		for style: String in _materials:
			var material_of := _materials[style] as ShaderMaterial
			material_of.set_shader_parameter(&"elevation_depth", occlusion.texture)
			material_of.set_shader_parameter(&"elevation_rect", occlusion.rect_uniform(occlusion.world_rect))
	if collide:
		_build_collision()


func _clear() -> void:
	for child: Node in get_children():
		child.free()
	if is_instance_valid(_pieces):
		_pieces.free()
	_pieces = null
	_drop_occluders()
	_boxes.clear()
	_materials.clear()


## Takes this build's silhouettes out of the depth map (a rebuild of the fences alone, or the
## fences removed); a rebuilt depth map has dropped them already.
func _drop_occluders() -> void:
	if _occlusion != null and is_instance_valid(_occlusion):
		for occluder: Variant in _occluders:
			if is_instance_valid(occluder):
				_occlusion.remove_occluder(occluder as MeshInstance2D)
	_occluders.clear()


# --- painted cells and connections ---------------------------------------------------------

## Every painted tile contributes material, direction and elevation. No terrain edge is read. A gate
## tile's cell is {"gate": its kind, "axis": its line (`gate_axis`), "level"}. A cell outside the grid
## is left out, with a warning (once a session).
func _painted_connections(painted: TileMapLayer) -> Dictionary:
	var cells := {}
	if painted == null or painted.tile_set == null or not painted.tile_set.has_custom_data_layer_by_name(STYLE_DATA_LAYER):
		return cells
	for cell_pos: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell_pos)
		if data == null:
			continue
		var at := cell_pos + _cell_offset
		if not grid.has_cell(at):
			_warn_outside(painted, cell_pos)
			continue
		var style := str(data.get_custom_data(STYLE_DATA_LAYER))
		if GATE_STYLES.has(style):
			cells[at] = {"gate": str(GATE_STYLES[style]), "axis": gate_axis(painted, cell_pos), "level": grid.level_of_cell(at)}
			continue
		if style.is_empty() or _kit(style).is_empty():
			continue
		var direction := int(data.get_custom_data(DIRECTION_DATA_LAYER)) if painted.tile_set.has_custom_data_layer_by_name(DIRECTION_DATA_LAYER) else ALL_NEIGHBORS_DIRECTION
		cells[at] = {"style": style, "direction": direction, "level": grid.level_of_cell(at)}
		if painted.tile_set.has_custom_data_layer_by_name(CRACKED_DATA_LAYER) and bool(data.get_custom_data(CRACKED_DATA_LAYER)):
			var flag := crack_flag(world_id(painted), cell_pos)
			if not Engine.is_editor_hint() and _run_has_flag(flag):
				# broken for good: no post, no rails to it (and none across its corner: `_add_connected_network`)
				cells[at] = {"broken": true, "level": grid.level_of_cell(at)}
				continue
			cells[at]["crack_flag"] = flag
	return cells


func _warn_outside(painted: TileMapLayer, cell_pos: Vector2i) -> void:
	var where := str(painted.get_path()) if painted.is_inside_tree() else str(painted.name)
	var key := "%s %s" % [where, cell_pos]
	if _outside_warned.has(key):
		return
	_outside_warned[key] = true
	push_warning("Fences: the fence painted at cell %s of '%s' lies outside the world's grid and is not built" % [cell_pos, where])


## One link per linked neighbouring pair (`_can_link`), in reading order (north to south, west to
## east): {"from", "to", "direction" (index into DIRECTIONS from `from` to `to`)}. A diagonal link
## yields to a two-link cardinal route between the same cells, so dense corners do not draw a
## second brace over the same connection.
static func connected_links(cells: Dictionary) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	var ordered: Array[Vector2i] = []
	for at: Vector2i in cells:
		ordered.append(at)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x
	)
	for at: Vector2i in ordered:
		var entry: Dictionary = cells[at]
		for direction_index in DIRECTIONS.size():
			var delta := DIRECTIONS[direction_index]
			var neighbour := at + delta
			if not cells.has(neighbour) or _cell_key_after(at, neighbour):
				continue
			var other: Dictionary = cells[neighbour]
			if not _can_link(entry, other, direction_index):
				continue
			if absi(delta.x) == 1 and absi(delta.y) == 1 \
					and _has_cardinal_route(cells, at, neighbour, delta):
				continue
			links.append({"from": at, "to": neighbour, "direction": direction_index})
	return links


## Whether two neighbouring painted cells (`to` lies `direction_index` from `from`) are joined by
## rails: never across levels; two all-neighbour tiles always; otherwise only where an arrow points
## (`from`'s arrow at `to`, or `to`'s arrow back at `from`). So an arrow tile refuses every
## neighbour its arrow does not point to and that does not point at it, all-neighbour tiles
## included: paint arrows where two runs pass one cell apart.
static func _can_link(from: Dictionary, to: Dictionary, direction_index: int) -> bool:
	if int(from.get("level", 0)) != int(to.get("level", 0)):
		return false
	var from_direction := int(from.get("direction", ALL_NEIGHBORS_DIRECTION))
	var to_direction := int(to.get("direction", ALL_NEIGHBORS_DIRECTION))
	if from_direction == ALL_NEIGHBORS_DIRECTION and to_direction == ALL_NEIGHBORS_DIRECTION:
		return true
	return from_direction == direction_index or to_direction == posmod(direction_index + 4, 8)


static func _has_cardinal_route(cells: Dictionary, from: Vector2i, to: Vector2i, diagonal: Vector2i) -> bool:
	var horizontal := from + Vector2i(diagonal.x, 0)
	if cells.has(horizontal):
		var horizontal_direction := 2 if diagonal.x > 0 else 6
		var vertical_direction := 4 if diagonal.y > 0 else 0
		if _can_link(cells[from], cells[horizontal], horizontal_direction) \
				and _can_link(cells[horizontal], cells[to], vertical_direction):
			return true
	var vertical := from + Vector2i(0, diagonal.y)
	if cells.has(vertical):
		var vertical_direction := 4 if diagonal.y > 0 else 0
		var horizontal_direction := 2 if diagonal.x > 0 else 6
		if _can_link(cells[from], cells[vertical], vertical_direction) \
				and _can_link(cells[vertical], cells[to], horizontal_direction):
			return true
	return false


static func _cell_key_after(a: Vector2i, b: Vector2i) -> bool:
	return a.y > b.y or (a.y == b.y and a.x > b.x)


## The pieces of every painted cell and link: a post per cell, rails per link (in the style of the
## cell whose arrow asks for the link: `from`'s, unless only `to` points back), the rails joining a
## divider gate to the posts beside it (`_add_gate_links`), and a lone cell's stub (a second post half
## a cell along its arrow, `lone_stub`). Records the collision boxes.
func _add_connected_network(cells: Dictionary, shadows: MeshData, depth: Dictionary) -> void:
	if cells.is_empty():
		return
	# Edge styles draw along a side of their cell and never link (`_add_edge_cell`).
	var linkable := {}
	var edges := {}
	for at: Vector2i in cells:
		var entry: Dictionary = cells[at]
		var edge_kit := _kit(str(entry.get("style", ""))) if not entry.has("gate") and not entry.has("broken") else {}
		if bool(edge_kit.get("edge", false)):
			edges[at] = entry
		else:
			linkable[at] = entry
	for at: Vector2i in edges:
		_add_edge_cell(at, edges[at], edges, shadows, depth)
	cells = linkable
	var posts := {}
	var gates := {}
	var broken := {}
	for at: Vector2i in cells:
		if (cells[at] as Dictionary).has("gate"):
			gates[at] = cells[at]
		elif (cells[at] as Dictionary).has("broken"):
			broken[at] = true
		else:
			posts[at] = cells[at]
	cells = posts
	var links := connected_links(cells)
	# A broken cracked post leaves a gap: the posts beside it never join diagonally across its corner.
	if not broken.is_empty():
		var kept: Array[Dictionary] = []
		for link: Dictionary in links:
			var step: Vector2i = DIRECTIONS[int(link["direction"])]
			var from: Vector2i = link["from"]
			if step.x != 0 and step.y != 0 and (broken.has(from + Vector2i(step.x, 0)) or broken.has(from + Vector2i(0, step.y))):
				continue
			kept.append(link)
		links = kept
	var linked_cells := {}
	var gate_links := _add_gate_links(gates, cells, shadows, depth)
	# cell -> the directions it is joined in (to a post or a gate): a run's end has one
	var joins := {}
	for at: Vector2i in gate_links:
		(joins.get_or_add(at, []) as Array).append_array(gate_links[at])
	for link: Dictionary in links:
		var from: Vector2i = link["from"]
		var to: Vector2i = link["to"]
		var from_entry: Dictionary = cells[from]
		var to_entry: Dictionary = cells[to]
		linked_cells[from] = true
		linked_cells[to] = true
		(joins.get_or_add(from, []) as Array).append(int(link["direction"]))
		(joins.get_or_add(to, []) as Array).append(posmod(int(link["direction"]) + 4, 8))
		var style := str(from_entry["style"])
		# The arrow that asks for the link owns its span; two all-neighbour tiles: `from`'s style.
		if int(to_entry.get("direction", ALL_NEIGHBORS_DIRECTION)) == posmod(int(link["direction"]) + 4, 8) \
				and int(from_entry.get("direction", ALL_NEIGHBORS_DIRECTION)) != int(link["direction"]):
			style = str(to_entry["style"])
		var kit := _kit(style)
		if kit.is_empty():
			continue
		var a := _foot(from)
		var b := _foot(to)
		var level := int(from_entry["level"])
		_add_span(style, kit, level, a, b, _front_normal((b - a).normalized()), shadows, _depth_for(depth, style))
		_add_link_box(level, a, b)
	var ordered: Array[Vector2i] = []
	for at: Vector2i in cells:
		ordered.append(at)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x
	)
	for at: Vector2i in ordered:
		var entry: Dictionary = cells[at]
		var style := str(entry["style"])
		var kit := _kit(style)
		if kit.is_empty():
			continue
		var level := int(entry["level"])
		var foot := _foot(at)
		var post_half := float(kit["posts"]["half_width"])
		var cracked := entry.has("crack_flag")
		_add_post(style, kit, level, foot, shadows, _depth_for(depth, style), not cracked)
		_add_post_box(level, foot, post_half)
		if cracked:
			_add_crack(style, foot, str(entry["crack_flag"]))
		# A run's end against a wall (the cell past it, away from the one join it has, is a room's wall
		# or a built wall) reaches it: a second post at its cell's edge and the rail between, as a
		# lone tile's stub (owner, 2026-10-19: ending on the cell's middle post, a run left a 32-unit
		# gap at the wall's foot the slime walked through).
		var joined: Array = joins.get(at, [])
		if joined.size() == 1:
			var outward := posmod(int(joined[0]) + 4, 8)
			if not cells.has(at + DIRECTIONS[outward]) and _wall_beyond(at, outward):
				var to_wall := foot + lone_stub(outward) * cell
				_add_post(style, kit, level, to_wall, shadows, _depth_for(depth, style))
				_add_post_box(level, to_wall, post_half)
				_add_span(style, kit, level, foot, to_wall, _front_normal((to_wall - foot).normalized()), shadows, _depth_for(depth, style))
				_add_link_box(level, foot, to_wall)
				continue
		if linked_cells.has(at):
			continue
		var direction := int(entry.get("direction", ALL_NEIGHBORS_DIRECTION))
		# A cell joined only to gates keeps its stub when its arrow points away from them (a short
		# fence on the gate's far side, to meet a wall); an all-neighbour tile, or an arrow at its
		# gate, is its post and the rails to the gate.
		if gate_links.has(at) and (direction == ALL_NEIGHBORS_DIRECTION or (gate_links[at] as Array).has(direction)):
			continue
		# A post left alone by a broken cracked post beside it stands as it is (no stub into the gap).
		if DIRECTIONS.any(func(step: Vector2i) -> bool: return broken.has(at + step)):
			continue
		# A lone tile is a short fence of two posts: its own and one at its cell's edge (a diagonal's
		# corner) the way its arrow points (east for an all-neighbour tile), the rail between them;
		# it collides as both posts and that rail's band.
		var far := foot + lone_stub(direction) * cell
		_add_post(style, kit, level, far, shadows, _depth_for(depth, style))
		_add_post_box(level, far, post_half)
		_add_span(style, kit, level, foot, far, _front_normal((far - foot).normalized()), shadows, _depth_for(depth, style))
		_add_link_box(level, foot, far)


## An edge style's cell (its kit's `edge`: lair-ledge; owner, 2026-10-27): its fence lies along one
## side of the cell, the side its arrow names, and never links to its neighbours. North and south:
## the front blocks against that side; east and west: the side's column of blocks against it. A
## diagonal arrow draws both of its sides (a corner), the column taking the corner; the all-neighbour
## tile draws the south side. Both pieces repeat on world coordinates, three blocks a cell, so
## neighbouring cells' pieces join block to block. A column whose cell below (in `edges`, the edge
## cells) carries no column on the same side ends on the end block, its front face showing.
func _add_edge_cell(at: Vector2i, entry: Dictionary, edges: Dictionary, shadows: MeshData, depth: Dictionary) -> void:
	var style := str(entry["style"])
	var kit := _kit(style)
	var level := int(entry["level"])
	var step := _edge_step(entry)
	var rect := Rect2(Vector2(at) * cell, Vector2.ONE * cell)
	var layer := _depth_for(depth, style)
	var direction := int(entry.get("direction", ALL_NEIGHBORS_DIRECTION))
	if direction >= EDGE_CORNER_DIRECTION:
		_add_edge_corner(style, kit, level, rect, DIRECTIONS[direction - EDGE_CORNER_DIRECTION], shadows, layer)
		return
	var column := float(kit["side"]["size"][0]) * 0.5
	if step.x != 0:
		var below: Dictionary = edges.get(at + Vector2i.DOWN, {})
		var continues := not below.is_empty() and int(below["level"]) == level and _edge_step(below).x == step.x
		_add_edge_column(style, kit, level, rect, step.x, not continues, shadows, layer)
	if step.y != 0:
		_add_edge_front(style, kit, level, rect, step.y, column if step.x < 0 else 0.0, column if step.x > 0 else 0.0, shadows, layer)


## The front blocks along the north (`toward` -1) or south (1) side of `rect`, short by `trim_left`
## and `trim_right` where a corner's column stands; they collide as a front run's band does.
func _add_edge_front(style: String, kit: Dictionary, level: int, rect: Rect2, toward: int, trim_left: float,
		trim_right: float, shadows: MeshData, depth: Array) -> void:
	var rails: Dictionary = kit["rails"]
	var top := float(rails["top"])
	var bottom := float(rails["bottom"])
	var strip_h := float(rails["size"][1])
	# South: the blocks stand on the cell's south side; north: their tops meet its north side.
	var foot := rect.end.y if toward > 0 else rect.position.y + top
	var x0 := rect.position.x + trim_left
	var x1 := rect.end.x - trim_right
	var arrays := MeshData.new()
	var silhouette := MeshData.new()
	var corners := [[Vector2(x0, foot - top), 0.0, -top], [Vector2(x1, foot - top), 0.0, -top],
			[Vector2(x1, foot - bottom), strip_h, -bottom], [Vector2(x0, foot - bottom), strip_h, -bottom]]
	for index: int in [0, 1, 2, 0, 2, 3]:
		var point: Vector2 = corners[index][0]
		var uv := Vector2(point.x * 2.0, float(corners[index][1]))
		var dy := float(corners[index][2])
		arrays.add(point, uv, _color(SHADE_FRONT, dy, KIND_RAILS, level))
		silhouette.add(point, uv - Vector2(0.0, DEPTH_UV_OFFSET), ElevationOcclusion.encode(level, dy))
	_add_piece(style, kit, foot - 0.5, arrays)
	depth.append([foot + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])
	var reach := SHADOW_FALL * (top + bottom) * 0.5 * SHADOW_PER_HEIGHT
	_add_fade(shadows, Vector2(x0, foot), Vector2(x1, foot), reach + Vector2(0.0, 3.0), SHADOW_ALPHA * 0.8)
	_add_box(level, Vector2((x0 + x1) * 0.5, foot - (_band_above + _band_below) * 0.5),
			Vector2((x1 - x0) * 0.5, (_band_above - _band_below) * 0.5), Vector2.RIGHT)


## The side the edge cell `entry`'s arrow names (the all-neighbour tile: south; a corner tile: none).
static func _edge_step(entry: Dictionary) -> Vector2i:
	var direction := int(entry.get("direction", ALL_NEIGHBORS_DIRECTION))
	if direction >= EDGE_CORNER_DIRECTION:
		return Vector2i.ZERO
	return Vector2i.DOWN if direction == ALL_NEIGHBORS_DIRECTION else DIRECTIONS[direction]


## The side's column of blocks along the west (`toward` -1) or east (1) side of `rect`, the cell's
## whole height; it collides `sideHalfWidth` each side of its middle, as a north-south run does.
## `capped`: its last block is the end block (the kit's post picture), its front face hanging below
## the cell.
func _add_edge_column(style: String, kit: Dictionary, level: int, rect: Rect2, toward: int, capped: bool,
		shadows: MeshData, depth: Array) -> void:
	var side: Dictionary = kit["side"]
	var half := float(side["size"][0]) * 0.25
	var x := rect.position.x + half if toward < 0 else rect.end.x - half
	var y0 := rect.position.y
	var y1 := rect.end.y
	_add_box(level, Vector2(x, (y0 + y1) * 0.5), Vector2(_side_half, (y1 - y0) * 0.5), Vector2.RIGHT)
	if capped:
		var block := float(side["size"][1]) * 0.5 / float(side.get("blocks", 1))
		y1 -= block
		_add_edge_end(style, kit, level, Vector2(x, y1), shadows, depth)
	var arrays := MeshData.new()
	var silhouette := MeshData.new()
	var corners := [Vector2(x - half, y0), Vector2(x + half, y0), Vector2(x + half, y1), Vector2(x - half, y1)]
	var us := [0.0, float(side["size"][0]), float(side["size"][0]), 0.0]
	for index: int in [0, 1, 2, 0, 2, 3]:
		var point: Vector2 = corners[index]
		var uv := Vector2(float(us[index]), point.y * 2.0)
		var dy := point.y - y0
		arrays.add(point, uv, _color(SHADE_TOP, dy, KIND_SIDE, level))
		silhouette.add(point, uv - Vector2(DEPTH_UV_OFFSET, 0.0), ElevationOcclusion.encode(level, dy))
	_add_piece(style, kit, y0 - 0.5, arrays)
	depth.append([y0 + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])
	var reach := SHADOW_FALL * float(side["top"]) * SHADOW_PER_HEIGHT
	_add_fade(shadows, Vector2(x, y0) + reach, Vector2(x, y1) + reach, Vector2(half * 2.0 + 4.0, 0.0), SHADOW_ALPHA * 0.8)


## A column's end block (the kit's `pieces.end`), its top at `top` (the middle of the column's line),
## its front face below.
func _add_edge_end(style: String, kit: Dictionary, level: int, top: Vector2, shadows: MeshData, depth: Array) -> void:
	var piece: Array = kit["pieces"]["end"]
	var size := Vector2(float(piece[2]), float(piece[3])) * 0.5
	_add_edge_piece(style, kit, level, Rect2(Vector2(top.x - size.x * 0.5, top.y), size), piece, shadows, depth)


## A corner tile (owner, 2026-10-28): the kit's corner block alone in the corner of `rect` toward
## `step` (a diagonal), its top-left or top-right on the cell's top edge for a north corner, its foot on
## the cell's bottom edge for a south one; it collides as a front band the block's width.
func _add_edge_corner(style: String, kit: Dictionary, level: int, rect: Rect2, step: Vector2i,
		shadows: MeshData, depth: Array) -> void:
	var piece: Array = kit["pieces"]["corner"]
	var size := Vector2(float(piece[2]), float(piece[3])) * 0.5
	var x := rect.position.x if step.x < 0 else rect.end.x - size.x
	var y := rect.position.y if step.y < 0 else rect.end.y - size.y
	_add_edge_piece(style, kit, level, Rect2(Vector2(x, y), size), piece, shadows, depth)
	var foot := y + size.y
	_add_box(level, Vector2(x + size.x * 0.5, foot - (_band_above + _band_below) * 0.5),
			Vector2(size.x * 0.5, (_band_above - _band_below) * 0.5), Vector2.RIGHT)


## One piece of the kit's pieces sheet (`piece`: [u, v, width, height] in it) drawn over `place`
## (world units), as a post is drawn; sorted at its foot, the place's lower edge.
func _add_edge_piece(style: String, kit: Dictionary, level: int, place: Rect2, piece: Array,
		shadows: MeshData, depth: Array) -> void:
	var u0 := float(piece[0])
	var v0 := float(piece[1])
	var u1 := u0 + float(piece[2])
	var v1 := v0 + float(piece[3])
	var foot := place.end.y
	var corners := [[place.position, Vector2(u0, v0)], [Vector2(place.end.x, place.position.y), Vector2(u1, v0)],
			[place.end, Vector2(u1, v1)], [Vector2(place.position.x, place.end.y), Vector2(u0, v1)]]
	var arrays := MeshData.new()
	var silhouette := MeshData.new()
	for index: int in [0, 1, 2, 0, 2, 3]:
		var point: Vector2 = corners[index][0]
		var uv: Vector2 = corners[index][1]
		var dy := point.y - foot
		arrays.add(point, uv, _color(SHADE_TOP, dy, KIND_POST, level))
		silhouette.add(point, uv, ElevationOcclusion.encode(level, dy))
	_add_piece(style, kit, foot, arrays)
	depth.append([foot + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])
	_add_contact(shadows, Vector2(place.get_center().x, foot))


## The rails joining each divider gate (`gates`: cell -> {"gate": kind, "axis", "level"}) to the
## posts beside it along its line, whatever their arrows, on its level: from the post up to the
## gate's block (DividerGate.block_half_width), in the post's style, their ends outlined
## (`_add_rail_end`), and their bands from the post's foot to the block's edge, where the gate's own
## body takes over. Returns post cell -> the directions (DIRECTIONS indices) from it to its gates.
func _add_gate_links(gates: Dictionary, posts: Dictionary, shadows: MeshData, depth: Dictionary) -> Dictionary:
	var joined := {}
	for at: Vector2i in gates:
		var gate: Dictionary = gates[at]
		var level := int(gate["level"])
		var axis: Vector2i = gate["axis"]
		var half := DividerGateScript.block_half_width(str(gate["gate"]))
		for side: Vector2i in [-axis, axis]:
			var post_at := at + side
			if not posts.has(post_at) or int((posts[post_at] as Dictionary)["level"]) != level:
				continue
			var style := str((posts[post_at] as Dictionary)["style"])
			var kit := _kit(style)
			if kit.is_empty():
				continue
			var foot := _foot(post_at)
			var edge := _foot(at) + Vector2(side) * half
			_add_span(style, kit, level, foot, edge, _front_normal((edge - foot).normalized()), shadows,
					_depth_for(depth, style), true, false)
			_add_rail_end(style, kit, level, edge, -side, _depth_for(depth, style))
			_add_link_box(level, foot, edge)
			if not joined.has(post_at):
				joined[post_at] = []
			(joined[post_at] as Array).append(DIRECTIONS.find(-side))
	return joined


## The end of the rails at a divider gate's block (`end`: the block's edge on the foot line;
## `facing`: the way the end faces, to the gate), seen when the gate is open, so the wall ends
## outlined as the art does: on a front run a slice of the kit's post side over the rails' height
## (the post's shaded east side or its lit west side, with its outline); on a north-south run the
## end facing south shows a slice of the front rails as its face (the end facing north is hidden
## under the rails' top).
func _add_rail_end(style: String, kit: Dictionary, level: int, end: Vector2, facing: Vector2i, depth: Array) -> void:
	if facing == Vector2i.UP:
		return
	var rails: Dictionary = kit["rails"]
	var bottom := float(rails["bottom"])
	var arrays := MeshData.new()
	var silhouette := MeshData.new()
	if facing == Vector2i.DOWN:
		var side: Dictionary = kit["side"]
		var top := float(side["top"])
		var half := float(side["size"][0]) * 0.25
		# under the north-south rails' strip (fences.gd `_add_span`: along the posts' inner side)
		var x := end.x - float(side["offset"])
		var strip_h := float(rails["size"][1])
		var corners := [[Vector2(x - half, end.y - top), 0.0], [Vector2(x + half, end.y - top), 0.0],
				[Vector2(x + half, end.y - bottom), strip_h], [Vector2(x - half, end.y - bottom), strip_h]]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var point: Vector2 = corners[index][0]
			var uv := Vector2(point.x * 2.0, float(corners[index][1]))
			var dy := point.y - end.y
			arrays.add(point, uv, _color(SHADE_FRONT, dy, KIND_RAILS, level))
			silhouette.add(point, uv - Vector2(0.0, DEPTH_UV_OFFSET), ElevationOcclusion.encode(level, dy))
	else:
		var top := float(rails["top"])
		var centre_px := float(kit["posts"]["cell"][0]) * 0.5
		var side_px := float(kit["posts"]["half_width"]) * 2.0
		var foot_row := float(kit["posts"]["foot_row"])
		var east := facing == Vector2i.RIGHT
		var u0 := centre_px + side_px - RAIL_END_PX if east else centre_px - side_px
		var x0 := end.x - RAIL_END_PX / 2.0 if east else end.x
		var x1 := x0 + RAIL_END_PX / 2.0
		var corners := [
			[Vector2(x0, end.y - top), Vector2(u0, foot_row - top * 2.0)], [Vector2(x1, end.y - top), Vector2(u0 + RAIL_END_PX, foot_row - top * 2.0)],
			[Vector2(x1, end.y - bottom), Vector2(u0 + RAIL_END_PX, foot_row - bottom * 2.0)], [Vector2(x0, end.y - bottom), Vector2(u0, foot_row - bottom * 2.0)],
		]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var point: Vector2 = corners[index][0]
			var uv: Vector2 = corners[index][1]
			var dy := point.y - end.y
			arrays.add(point, uv, _color(SHADE_TOP, dy, KIND_POST, level))
			silhouette.add(point, uv, ElevationOcclusion.encode(level, dy))
	# after the rails, before the gate (which stands in front of their ends)
	_add_piece(style, kit, end.y - 0.5, arrays)
	depth.append([end.y + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])


## Where a lone tile's second post stands from its own, in cells: half a cell along its arrow
## (DIRECTIONS[direction] / 2: a cell's edge, a diagonal's corner); east (LONE_STUB_DIRECTION) for
## an all-neighbour tile.
static func lone_stub(direction: int) -> Vector2:
	if direction < 0 or direction >= DIRECTIONS.size():
		direction = LONE_STUB_DIRECTION
	return Vector2(DIRECTIONS[direction]) * 0.5


## True when the cell past `at` (a painted cell, grid space) going `direction` is a wall a run ends
## against: a dungeon room's wall (an InteriorWallLayer's `is_wall`) or a built wall (a WallLayer
## cell), beside the ground layer.
func _wall_beyond(at: Vector2i, direction: int) -> bool:
	var parent := ground.get_parent() if ground != null else null
	if parent == null:
		return false
	var next := at + DIRECTIONS[direction] - _cell_offset
	for child: Node in parent.get_children():
		var layer := child as TileMapLayer
		if layer == null:
			continue
		if layer.has_method(&"is_wall"):
			if bool(layer.call(&"is_wall", next)):
				return true
		elif layer is WallLayer and layer.get_cell_source_id(next) != -1:
			return true
	return false


## Where a painted cell's post stands (its foot: the cell's centre, this node's space).
func _foot(at: Vector2i) -> Vector2:
	return Vector2(at) * cell + Vector2.ONE * cell * 0.5


func _depth_for(depth: Dictionary, style: String) -> Array:
	if not depth.has(style):
		depth[style] = []
	return depth[style]


static func _front_normal(axis: Vector2) -> Vector2:
	var normal := Vector2(-axis.y, axis.x)
	if normal.y < 0.0 or (is_zero_approx(normal.y) and normal.x < 0.0):
		normal = -normal
	return normal


# --- cracked posts --------------------------------------------------------------------------

## The story flag a cracked post painted at `cell_pos` of world `map_id`'s fences sets when it breaks.
static func crack_flag(map_id: String, cell_pos: Vector2i) -> String:
	return "fence-crack.%s.%d,%d" % [map_id, cell_pos.x, cell_pos.y]


## The world id of the scene a fences layer is painted in: its `world-definition`'s `map_id`, else
## the scene root's name.
static func world_id(painted: TileMapLayer) -> String:
	var room := painted.get_parent() if painted != null else null
	if room == null:
		return ""
	var definition := room.get_node_or_null(^"world-definition")
	if definition != null and not str(definition.get(&"map_id")).is_empty():
		return str(definition.get(&"map_id"))
	return str(room.name)


static func _run_has_flag(flag: String) -> bool:
	var run := Services.run()
	return run != null and bool(run.call(&"has_flag", flag))


## A cracked post's picture (in the editor too, so it shows as you paint) and, in the game, the blast
## target that breaks it.
func _add_crack(style: String, foot: Vector2, flag: String) -> void:
	var post := CrackedPost.new()
	post.name = "CrackedPost-%d-%d" % [roundi(foot.x), roundi(foot.y)]
	post.fences = self
	post.flag = flag
	post.position = foot
	var texture := SheetSprite.load_picture(CRACKED_POST % style) as Texture2D
	if texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * 0.5
		sprite.offset = Vector2(-texture.get_width() * 0.5, CRACKED_FOOT_PAD - texture.get_height())
		post.add_child(sprite)
	_pieces.add_child(post)
	if not Engine.is_editor_hint():
		post.add_to_group(&"blast_targets")


## A cracked post broke: build the fences again (after this frame: the blast is still running) without
## it.
func _rebuild_after_break() -> void:
	if not is_inside_tree() or ground == null:
		return
	build(ground, _painted, grid, _occlusion, _collide, _cell_offset)


## A cracked post's blast target (in `FencePieces`): a Goo Bomb blast whose ellipse holds its foot
## breaks it.
class CrackedPost extends Node2D:
	var fences: Node
	var flag := ""
	var _broken := false

	func blast_point() -> Vector2:
		return global_position

	func receive_blast(_hit: Dictionary) -> bool:
		if _broken:
			return false
		_broken = true
		var run := Services.run()
		if run != null:
			run.call(&"set_flag", flag)
		BlastBarrier.give_way(global_position, CRACK_BREAK_TEXT, Color("#8a6a48"), CRACK_PEBBLES, CRACK_PUFFS)
		if is_instance_valid(fences):
			fences.call_deferred(&"_rebuild_after_break")
		return true


# --- drawing -------------------------------------------------------------------------------

## One post: its sprite at its foot, a contact shadow and a soft shadow towards the lower right.
## `art` false: only its shadows (a cracked post draws its own picture: `_add_crack`).
func _add_post(style: String, kit: Dictionary, level: int, foot: Vector2, shadows: MeshData, depth: Array, art: bool = true) -> void:
	var cell_size := Vector2(float(kit["posts"]["cell"][0]), float(kit["posts"]["cell"][1]))
	var foot_row := float(kit["posts"]["foot_row"])
	var variant := absi(roundi(foot.x) * 73856093 ^ roundi(foot.y) * 19349663) % int(kit["posts"]["count"])
	var half := cell_size.x * 0.25
	var top := foot.y - foot_row * 0.5
	var bottom := foot.y + (cell_size.y - foot_row) * 0.5
	var u0 := float(variant) * cell_size.x
	var corners := [
		[Vector2(foot.x - half, top), Vector2(u0, 0.0)], [Vector2(foot.x + half, top), Vector2(u0 + cell_size.x, 0.0)],
		[Vector2(foot.x + half, bottom), Vector2(u0 + cell_size.x, cell_size.y)], [Vector2(foot.x - half, bottom), Vector2(u0, cell_size.y)],
	]
	var arrays := MeshData.new()
	var silhouette := MeshData.new()
	for index: int in [0, 1, 2, 0, 2, 3]:
		var point: Vector2 = corners[index][0]
		var uv: Vector2 = corners[index][1]
		var dy := point.y - foot.y
		arrays.add(point, uv, _color(SHADE_TOP, dy, KIND_POST, level))
		silhouette.add(point, uv, ElevationOcclusion.encode(level, dy))
	if art:
		_add_piece(style, kit, foot.y, arrays)
		depth.append([foot.y + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])
	var post_width := float(kit["posts"]["half_width"])
	var reach := SHADOW_FALL * float(kit["post_height"]) * SHADOW_PER_HEIGHT
	_add_fade(shadows, foot - Vector2(post_width, 0.0), foot + Vector2(post_width, 0.0), reach, SHADOW_ALPHA)
	_add_contact(shadows, foot)


## The rails between two posts: sheared along a front or diagonal run (they stop at the posts'
## sides), seen from above along an east or west run (the posts cover their ends). `a_post` or
## `b_post` false: no post stands at that end (a divider gate's block: the rail runs to the point).
func _add_span(style: String, kit: Dictionary, level: int, a: Vector2, b: Vector2,
		outward: Vector2, shadows: MeshData, depth: Array, a_post: bool = true, b_post: bool = true) -> void:
	var arrays := MeshData.new()
	var silhouette := MeshData.new()
	var sort_y := 0.0
	var depth_y := 0.0
	if absf(b.x - a.x) < 1.0:
		var side: Dictionary = kit["side"]
		var north := a if a.y < b.y else b
		var south := b if a.y < b.y else a
		var height := float(side["top"])
		var half := float(side["size"][0]) * 0.25
		# The rail runs along the posts' inner side, so posts and rail read apart.
		var x := north.x - outward.x * float(side["offset"])
		var corners := [Vector2(x - half, north.y - height), Vector2(x + half, north.y - height),
				Vector2(x + half, south.y - height), Vector2(x - half, south.y - height)]
		var us := [0.0, float(side["size"][0]), float(side["size"][0]), 0.0]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var point: Vector2 = corners[index]
			var uv := Vector2(float(us[index]), (point.y + height) * 2.0)
			# The rail lies as deep as its north post (in 3D its start would cover the post's foot;
			# the posts stay in front of it, as on front runs).
			var dy := point.y - north.y
			arrays.add(point, uv, _color(SHADE_TOP, dy, KIND_SIDE, level))
			silhouette.add(point, uv - Vector2(DEPTH_UV_OFFSET, 0.0), ElevationOcclusion.encode(level, dy))
		# Before the north post, which covers the rail's start.
		sort_y = north.y - 0.5
		depth_y = north.y
		var reach := SHADOW_FALL * height * SHADOW_PER_HEIGHT
		_add_fade(shadows, Vector2(x, north.y) + reach, Vector2(x, south.y) + reach, Vector2(half * 2.0 + 4.0, 0.0), SHADOW_ALPHA * 0.8)
	else:
		var rails: Dictionary = kit["rails"]
		var left := a if a.x < b.x else b
		var right := b if a.x < b.x else a
		var half_width := float(kit["posts"]["half_width"])
		var x0 := left.x + (half_width - 1.0 if (a_post if a.x < b.x else b_post) else 0.0)
		var x1 := right.x - (half_width - 1.0 if (b_post if a.x < b.x else a_post) else 0.0)
		if x1 <= x0:
			return
		var slope := (right.y - left.y) / (right.x - left.x)
		var y0 := left.y + slope * (x0 - left.x)
		var y1 := left.y + slope * (x1 - left.x)
		var top := float(rails["top"])
		var bottom := float(rails["bottom"])
		var strip_h := float(rails["size"][1])
		var shade := SHADE_FRONT if absf(slope) < 0.01 else (SHADE_SOUTH_WEST if slope > 0.0 else SHADE_SOUTH_EAST)
		var corners := [[Vector2(x0, y0 - top), 0.0, -top], [Vector2(x1, y1 - top), 0.0, -top],
				[Vector2(x1, y1 - bottom), strip_h, -bottom], [Vector2(x0, y0 - bottom), strip_h, -bottom]]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var point: Vector2 = corners[index][0]
			var uv := Vector2(point.x * 2.0, float(corners[index][1]))
			var dy := float(corners[index][2])
			arrays.add(point, uv, _color(shade, dy, KIND_RAILS, level))
			silhouette.add(point, uv - Vector2(0.0, DEPTH_UV_OFFSET), ElevationOcclusion.encode(level, dy))
		# Put the rail at the visible feet of its posts for a consistent depth order.
		sort_y = (maxf(y0, y1) if outward.y >= 0.0 else minf(y0, y1)) - 0.5
		depth_y = (y0 + y1) * 0.5
		var reach := SHADOW_FALL * (top + bottom) * 0.5 * SHADOW_PER_HEIGHT
		_add_fade(shadows, Vector2(x0, y0) + SHADOW_FALL * bottom * SHADOW_PER_HEIGHT, Vector2(x1, y1) + SHADOW_FALL * bottom * SHADOW_PER_HEIGHT,
				reach - SHADOW_FALL * bottom * SHADOW_PER_HEIGHT + Vector2(0.0, 3.0), SHADOW_ALPHA * 0.8)
	_add_piece(style, kit, sort_y, arrays)
	depth.append([depth_y + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])


## A MeshInstance2D under the y-sorted holder, placed at `sort_y` (its vertices made relative).
func _add_piece(style: String, kit: Dictionary, sort_y: float, arrays: MeshData) -> void:
	var anchor := Vector2(arrays.vertices[0].x, sort_y)
	var vertices := arrays.vertices
	for i in vertices.size():
		vertices[i] -= anchor
	arrays.vertices = vertices
	var piece := MeshInstance2D.new()
	piece.position = anchor
	piece.mesh = arrays.to_mesh()
	piece.material = _material(style, kit)
	_pieces.add_child(piece)


## A soft shadow quad from the edge q0 -> q1 to the edge moved by `offset`, fading out.
static func _add_fade(arrays: MeshData, q0: Vector2, q1: Vector2, offset: Vector2, alpha: float) -> void:
	var dark := Color(0.0, 0.0, 0.0, alpha)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	for point_color: Array in [[q0, dark], [q1, dark], [q1 + offset, clear], [q0, dark], [q1 + offset, clear], [q0 + offset, clear]]:
		arrays.add(point_color[0], Vector2.ZERO, point_color[1])


## A soft dark ellipse at a post's foot.
static func _add_contact(arrays: MeshData, foot: Vector2) -> void:
	var steps := 12
	var dark := Color(0.0, 0.0, 0.0, CONTACT_ALPHA)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	var centre := foot + Vector2(2.0, 0.0)
	for i in steps:
		var a0 := TAU * float(i) / steps
		var a1 := TAU * float(i + 1) / steps
		arrays.add(centre, Vector2.ZERO, dark)
		arrays.add(centre + Vector2(cos(a0), sin(a0)) * CONTACT_RADIUS, Vector2.ZERO, clear)
		arrays.add(centre + Vector2(cos(a1), sin(a1)) * CONTACT_RADIUS, Vector2.ZERO, clear)


## Fence vertex data (fence.gdshader): r = shade, g = how far below its foot line
## ((dy + 128) / 512), b = kind, a = level ((level + 4) / 8).
static func _color(shade: float, dy: float, kind: float, level: int) -> Color:
	return Color(shade, clampf((dy + 128.0) / 512.0, 0.0, 1.0), kind, (float(level) + 4.0) / 8.0)


# --- art -----------------------------------------------------------------------------------

## A style's kit (its JSON plus the loaded textures), {} without art.
func _kit(style: String) -> Dictionary:
	if _kits.has(style):
		return _kits[style]
	var kit := {}
	var json_path := KIT % [style, ".json"]
	var textures := {"posts_texture": KIT % [style, "-posts.png"], "rails_texture": KIT % [style, "-rails.png"],
			"side_texture": KIT % [style, "-rails-side.png"]}
	var complete := FileAccess.file_exists(json_path)
	for path: String in textures.values():
		complete = complete and (ResourceLoader.exists(path) or FileAccess.file_exists(path))
	if complete:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			kit = parsed
			for uniform: String in textures:
				# a kit packed after the editor's last import is read from its file
				kit[uniform] = SheetSprite.load_picture(textures[uniform])
	if kit.is_empty():
		push_warning("Fences: no art for the fence style '%s' (%s)" % [style, json_path])
	_kits[style] = kit
	return kit


func _material(style: String, kit: Dictionary) -> ShaderMaterial:
	if _materials.has(style):
		return _materials[style]
	var material_of := ShaderMaterial.new()
	material_of.shader = FENCE_SHADER
	for uniform: String in ["posts_texture", "rails_texture", "side_texture"]:
		var texture := kit[uniform] as Texture2D
		material_of.set_shader_parameter(StringName(uniform), texture)
		material_of.set_shader_parameter(StringName(uniform.trim_suffix("_texture") + "_size"), Vector2(texture.get_size()))
	_materials[style] = material_of
	return material_of


func _depth_material(style: String) -> ShaderMaterial:
	var kit: Dictionary = _kits[style]
	var material_of := ShaderMaterial.new()
	material_of.shader = DEPTH_SHADER
	for uniform: String in ["posts_texture", "rails_texture", "side_texture"]:
		var texture := kit[uniform] as Texture2D
		material_of.set_shader_parameter(StringName(uniform), texture)
		material_of.set_shader_parameter(StringName(uniform.trim_suffix("_texture") + "_size"), Vector2(texture.get_size()))
	material_of.set_shader_parameter(&"uv_offset", DEPTH_UV_OFFSET)
	return material_of


# --- collision -----------------------------------------------------------------------------

## The band of a link from foot `a` to foot `b` (or a lone tile's stub): from `bandAbove` to
## `bandBelow` above the foot line, foot to foot; a north-south one `sideHalfWidth` each side of the
## post column (its ends meet the posts' rects).
func _add_link_box(level: int, a: Vector2, b: Vector2) -> void:
	var raise := Vector2(0.0, -(_band_above + _band_below) * 0.5)
	var half_thickness := (_band_above - _band_below) * 0.5
	if absf(b.x - a.x) < 1.0:
		half_thickness = _side_half
	_add_box(level, a.lerp(b, 0.5) + raise, Vector2(a.distance_to(b) * 0.5, half_thickness), (b - a).normalized())


## A post's rect: `half_width` (its kit's post, `posts.half_width`) each side of its foot, from
## `bandAbove` to `bandBelow` above it.
func _add_post_box(level: int, foot: Vector2, half_width: float) -> void:
	_add_box(level, foot + Vector2(0.0, -(_band_above + _band_below) * 0.5),
			Vector2(half_width, (_band_above - _band_below) * 0.5), Vector2.RIGHT)


func _add_box(level: int, centre: Vector2, half: Vector2, axis: Vector2) -> void:
	var across := Vector2(-axis.y, axis.x)
	var reach := Vector2(half.x * absf(axis.x) + half.y * absf(across.x), half.x * absf(axis.y) + half.y * absf(across.y))
	if not _boxes.has(level):
		_boxes[level] = []
	(_boxes[level] as Array).append({"centre": centre, "half": half, "axis": axis,
			"bounds": Rect2(centre - reach, reach * 2.0)})


## One static body per level with fences, on that level's physics layer, a rectangle per box. On
## flat ground (no Elevation tracks the bodies onto level layers) level 0's body is on the `world`
## layer, as a wall is.
func _build_collision() -> void:
	if _boxes.is_empty():
		return
	var holder := Node2D.new()
	holder.name = "Collision"
	add_child(holder)
	for level_value: Variant in _boxes:
		var level := int(level_value)
		var bit := WORLD_LAYER if _flat and level == 0 else _level_bit(level)
		if bit == 0:
			push_warning("Fences: no physics layer named 'level %d'" % level)
			continue
		var body := StaticBody2D.new()
		body.name = "Level%d" % level
		body.collision_layer = bit
		body.collision_mask = 0
		for box: Dictionary in _boxes[level]:
			var rectangle := RectangleShape2D.new()
			rectangle.size = (box["half"] as Vector2) * 2.0
			var collision := CollisionShape2D.new()
			collision.shape = rectangle
			collision.position = box["centre"]
			collision.rotation = (box["axis"] as Vector2).angle()
			body.add_child(collision)
		holder.add_child(body)


## The physics layer bit project.godot names "level <n>", 0 when none is (looked up once a level).
static func _level_bit(level: int) -> int:
	if _level_bits.has(level):
		return int(_level_bits[level])
	var bit := 0
	for i in range(1, 33):
		if str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % i, "")) == "level %d" % level:
			bit = 1 << (i - 1)
			break
	_level_bits[level] = bit
	return bit

## The fences under `parent`, found by class (a node's name is typed by hand in the editor).
static func find_in(parent: Node) -> Self:
	for child: Node in parent.get_children():
		if child is Self:
			return child as Self
	return null

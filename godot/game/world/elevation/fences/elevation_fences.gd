@tool
extends Node2D
## Painted fence art, shadows, depth silhouettes and collision (docs/godot/FENCES.md).
##
## A world paints all fences on one `fences` layer beside its `elevation` layer, using
## fence_tileset.tres. Painted cells join neighboring cells in the chosen directions and place
## their own art, shadows and collision without changing elevation rims.
##
## A world mounts one node named "Fences" for its painted fence layer. The renderer uses the style's
## kit (scripts/art/build-fence-art.py, asset/MAPS/fences/<style>-*.png and <style>.json): one post
## at each painted cell and rails between connected neighbors. Diagonal rails shear with the slope,
## posts stay upright, and the faces are lit consistently. The pieces:
##   - posts and rails are MeshInstance2Ds under "ElevationFences", a y-sorted Node2D beside the
##     ground layer (never saved with the scene), so they sort with bodies and props;
##   - their silhouettes go into the terrain's depth map (ElevationOcclusion.add_occluder, only where
##     the art is opaque), so a body behind a fence on a higher level shows as its ghost behind it,
##     and a fence pixel behind nearer terrain is not drawn (elevation_fence.gdshader);
##   - soft shadows on the ground, falling to the lower right ("Shadows").
## With `collide`, each level that has fences gets a static body on its physics layer (named
## "level <n>" in project.godot). Connections use a 16-unit-wide rectangular collider centered on
## their rails, and an isolated painted tile uses square, full-cell collision. `blocks_point` also
## keeps drops and hops from bypassing a connected fence.
##
## Owner: world (elevation fences).

const Self := preload("res://game/world/elevation/fences/elevation_fences.gd")
const Services := preload("res://game/shared/services.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const ElevationOcclusion := preload("res://game/world/elevation/elevation_occlusion.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const FENCE_SHADER := preload("res://game/world/elevation/fences/elevation_fence.gdshader")
const DEPTH_SHADER := preload("res://game/world/elevation/fences/elevation_fence_depth.gdshader")

const NODE_NAME := "Fences"
## The y-sorted holder of the pieces, beside the ground layer.
const PIECES_NAME := "ElevationFences"
## The fence tile set's data layer: the style a painted cell's fence takes.
const STYLE_DATA_LAYER := "fence_style"
const DIRECTION_DATA_LAYER := "fence_direction"
const ALL_NEIGHBORS_DIRECTION := -1
## Direction from a painted cell to a connected neighbor: N, NE, E, SE, S, SW, W, NW.
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1),
		Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]
## A style's kit: art/<style>-posts.png, -rails.png, -rails-side.png and <style>.json.
const KIT := "res://asset/MAPS/fences/%s%s"
## Gameplay values (game-constants.json `fences`); clearance is each side of a rail's collision band.
const DEFAULTS := {"clearance": 8.0}
## Rails shading by link direction (the art is painted facing south).
const SHADE_FRONT := 1.0
const SHADE_SOUTH_WEST := 1.1
const SHADE_SOUTH_EAST := 0.8
const SHADE_TOP := 1.0
## Vertex colour b: which art a vertex samples.
const KIND_POST := 0.0
const KIND_RAILS := 0.5
const KIND_SIDE := 1.0
## Depth occluders tell rails and side rails from posts by UV (elevation_fence_depth.gdshader).
const DEPTH_UV_OFFSET := 10000.0
## Shadows: the light's fall on the ground (elevation_cast_shadow.gdshaderinc `fall`), the shadow's length per
## unit of height, how dark it is, and the contact shadow around a post's foot (world units).
const SHADOW_FALL := Vector2(0.94, 0.34)
const SHADOW_PER_HEIGHT := 0.45
const SHADOW_ALPHA := 0.3
const CONTACT_ALPHA := 0.45
const CONTACT_RADIUS := Vector2(10.0, 4.5)
var grid: ElevationGrid
var ground: TileMapLayer
var cell := 64.0
var _pieces: Node2D
var _cell_offset := Vector2i.ZERO
## style -> its kit (the JSON), or {} when it has no art.
var _kits: Dictionary = {}
var _materials: Dictionary = {}
## level -> Array of {"polygons": Array[PackedVector2Array], "box": Rect2}: isolated painted tiles,
## in ground-layer space.
var _bands: Dictionary = {}
## level -> connected fence collision segments, used to keep drops and hops from bypassing rails.
var _connected_collision: Dictionary = {}


## Builds the fences beside `elevation` (the Elevation node, child of the ground layer) from the
## `fences` layer beside the ground; null (and old fences removed) when there is none.
## Mount the same painted fence layer in flat and elevated worlds. Elevated fences live under
## Elevation for depth and row offsets; flat fences use a level-0 grid beside the ground layer.
static func mount(ground_layer: TileMapLayer, elevation: Node2D, the_grid: ElevationGrid,
		occlusion: ElevationOcclusion, collide: bool) -> Self:
	if ground_layer == null or ground_layer.get_parent() == null or ground_layer.tile_set == null:
		return null
	var parent: Node = elevation if elevation != null else ground_layer.get_parent()
	var painted := find_layer(ground_layer)
	var existing := parent.get_node_or_null(NodePath(NODE_NAME)) as Self
	if elevation != null:
		var flat_renderer := ground_layer.get_parent().get_node_or_null(NodePath(NODE_NAME))
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


## True when a painted fence blocks `world_point` to bodies on its elevation level.
func blocks_point(world_point: Vector2, level: int) -> bool:
	var point := world_point - global_position
	for segment: PackedVector2Array in _connected_collision.get(level, []):
		if Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1]).distance_to(point) <= setting("clearance"):
			return true
	for band: Dictionary in _bands.get(level, []):
		if not (band["box"] as Rect2).has_point(point):
			continue
		var inside := false
		for polygon: PackedVector2Array in band["polygons"]:
			if Geometry2D.is_point_in_polygon(point, polygon):
				inside = not inside
		if inside:
			return true
	return false


func _exit_tree() -> void:
	if is_instance_valid(_pieces):
		_pieces.queue_free()
	_pieces = null


func build(ground_layer: TileMapLayer, painted: TileMapLayer, the_grid: ElevationGrid,
		occlusion: ElevationOcclusion, collide: bool, cell_offset: Vector2i = Vector2i.ZERO) -> void:
	_clear()
	grid = the_grid
	ground = ground_layer
	_cell_offset = cell_offset
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
	var segments := {}
	var solid_tiles := {}
	_add_connected_network(_painted_connections(painted), shadows, depth, segments, solid_tiles)
	if not shadows.is_empty():
		var instance := MeshInstance2D.new()
		instance.name = "Shadows"
		instance.mesh = shadows.to_mesh()
		add_child(instance)
	if occlusion != null and occlusion.texture != null:
		for style: String in depth:
			var pieces: Array = depth[style]
			pieces.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			var arrays := MeshData.new()
			for piece: Array in pieces:
				var mesh_data: MeshData = piece[1]
				for i in mesh_data.vertices.size():
					arrays.add(mesh_data.vertices[i], mesh_data.uvs[i], mesh_data.colors[i])
			occlusion.add_occluder(arrays.to_mesh(), _depth_material(style))
		for style: String in _materials:
			var material_of := _materials[style] as ShaderMaterial
			material_of.set_shader_parameter(&"elevation_depth", occlusion.texture)
			material_of.set_shader_parameter(&"elevation_rect", occlusion.rect_uniform(occlusion.world_rect))
	if collide:
		_build_collision(segments, solid_tiles)


func _clear() -> void:
	for child: Node in get_children():
		child.free()
	if is_instance_valid(_pieces):
		_pieces.free()
	_pieces = null
	_bands.clear()
	_connected_collision.clear()
	_materials.clear()


# --- painted cells and connections ---------------------------------------------------------

## Every painted tile contributes material, direction and elevation. No terrain edge is read.
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
			continue
		var style := str(data.get_custom_data(STYLE_DATA_LAYER))
		if style.is_empty() or _kit(style).is_empty():
			continue
		var direction := int(data.get_custom_data(DIRECTION_DATA_LAYER)) if painted.tile_set.has_custom_data_layer_by_name(DIRECTION_DATA_LAYER) else ALL_NEIGHBORS_DIRECTION
		cells[at] = {"style": style, "direction": direction, "level": grid.level_of_cell(at)}
	return cells


## One link per compatible neighboring pair. All-neighbor cells accept every neighbor; an arrow on
## either tile can request a link. A diagonal link yields to an existing compatible two-link
## cardinal route, so dense corners do not draw a second brace over the same connection.
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


static func _can_link(from: Dictionary, to: Dictionary, direction_index: int) -> bool:
	if int(from.get("level", 0)) != int(to.get("level", 0)):
		return false
	var from_direction := int(from.get("direction", ALL_NEIGHBORS_DIRECTION))
	var to_direction := int(to.get("direction", ALL_NEIGHBORS_DIRECTION))
	return from_direction == ALL_NEIGHBORS_DIRECTION or from_direction == direction_index \
			or to_direction == ALL_NEIGHBORS_DIRECTION or to_direction == posmod(direction_index + 4, 8)


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


func _add_connected_network(cells: Dictionary, shadows: MeshData, depth: Dictionary,
		segments: Dictionary, solid_tiles: Dictionary) -> void:
	if cells.is_empty():
		return
	var links := connected_links(cells)
	var linked_cells := {}
	for link: Dictionary in links:
		var from: Vector2i = link["from"]
		var to: Vector2i = link["to"]
		var from_entry: Dictionary = cells[from]
		var to_entry: Dictionary = cells[to]
		linked_cells[from] = true
		linked_cells[to] = true
		var style := str(from_entry["style"])
		# Let a specifically directed endpoint own its outgoing span; otherwise use sorted order.
		if int(to_entry.get("direction", ALL_NEIGHBORS_DIRECTION)) == posmod(int(link["direction"]) + 4, 8) \
				and int(from_entry.get("direction", ALL_NEIGHBORS_DIRECTION)) != int(link["direction"]):
			style = str(to_entry["style"])
		var kit := _kit(style)
		if kit.is_empty():
			continue
		var a := Vector2(from) * cell + Vector2.ONE * cell * 0.5
		var b := Vector2(to) * cell + Vector2.ONE * cell * 0.5
		var outward := _front_normal((b - a).normalized())
		_add_span(style, kit, int(from_entry["level"]), a, b, outward, shadows, _depth_for(depth, style))
		var level := int(from_entry["level"])
		if not segments.has(level):
			segments[level] = []
		(segments[level] as Array).append(a)
		(segments[level] as Array).append(b)
		if not _connected_collision.has(level):
			_connected_collision[level] = []
		(_connected_collision[level] as Array).append(PackedVector2Array([a, b]))
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
		var foot := Vector2(at) * cell + Vector2.ONE * cell * 0.5
		_add_post(style, kit, int(entry["level"]), foot, shadows, _depth_for(depth, style))
		if linked_cells.has(at):
			continue
		# An isolated fence tile still fills its collision tile, keeping the old single-tile behavior.
		var direction_index := int(entry.get("direction", ALL_NEIGHBORS_DIRECTION))
		if direction_index < 0 or direction_index >= DIRECTIONS.size():
			direction_index = 2
		var axis := Vector2(DIRECTIONS[direction_index]).normalized()
		var half_length := cell * 0.5 - float(kit["posts"]["half_width"])
		var a := foot - axis * half_length
		var b := foot + axis * half_length
		_add_span(style, kit, int(entry["level"]), a, b, _front_normal(axis), shadows, _depth_for(depth, style))
		var level := int(entry["level"])
		if not solid_tiles.has(level):
			solid_tiles[level] = []
		(solid_tiles[level] as Array).append(Rect2(foot - Vector2.ONE * cell * 0.5, Vector2.ONE * cell))
		var corners := PackedVector2Array([foot + Vector2(-cell * 0.5, -cell * 0.5),
			foot + Vector2(cell * 0.5, -cell * 0.5), foot + Vector2(cell * 0.5, cell * 0.5),
			foot + Vector2(-cell * 0.5, cell * 0.5)])
		_add_solid_band(level, corners)


func _depth_for(depth: Dictionary, style: String) -> Array:
	if not depth.has(style):
		depth[style] = []
	return depth[style]


static func _front_normal(axis: Vector2) -> Vector2:
	var normal := Vector2(-axis.y, axis.x)
	if normal.y < 0.0 or (is_zero_approx(normal.y) and normal.x < 0.0):
		normal = -normal
	return normal


# --- drawing -------------------------------------------------------------------------------

## One post: its sprite at its foot, a contact shadow and a soft shadow towards the lower right.
func _add_post(style: String, kit: Dictionary, level: int, foot: Vector2, shadows: MeshData, depth: Array) -> void:
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
	_add_piece(style, kit, foot.y, arrays)
	depth.append([foot.y + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])
	var post_width := float(kit["posts"]["half_width"])
	var reach := SHADOW_FALL * float(kit["post_height"]) * SHADOW_PER_HEIGHT
	_add_fade(shadows, foot - Vector2(post_width, 0.0), foot + Vector2(post_width, 0.0), reach, SHADOW_ALPHA)
	_add_contact(shadows, foot)


## The rails between two posts: sheared along a front or diagonal run (they stop at the posts'
## sides), seen from above along an east or west run (the posts cover their ends).
func _add_span(style: String, kit: Dictionary, level: int, a: Vector2, b: Vector2,
		outward: Vector2, shadows: MeshData, depth: Array) -> void:
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
		var x0 := left.x + half_width - 1.0
		var x1 := right.x - half_width + 1.0
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


## Fence vertex data (elevation_fence.gdshader): r = shade, g = how far below its foot line
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
		complete = complete and ResourceLoader.exists(path)
	if complete:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			kit = parsed
			for uniform: String in textures:
				kit[uniform] = load(textures[uniform])
	if kit.is_empty():
		push_warning("ElevationFences: no art for the fence style '%s' (%s)" % [style, json_path])
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

## A single-cell enclosure blocks the full cell for landings and ledge probes too.
func _add_solid_band(level: int, tile: PackedVector2Array) -> void:
	if not _bands.has(level):
		_bands[level] = []
	(_bands[level] as Array).append({"polygons": [tile], "box": _bounds(tile).grow(1.0)})


static func _bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _build_collision(segments: Dictionary, solid_tiles: Dictionary) -> void:
	var levels := {}
	for level: int in segments:
		levels[level] = true
	for level: int in solid_tiles:
		levels[level] = true
	if levels.is_empty():
		return
	var holder := Node2D.new()
	holder.name = "Collision"
	add_child(holder)
	for level_value: Variant in levels:
		var level := int(level_value)
		var bit := _level_bit(level)
		if bit == 0:
			push_warning("ElevationFences: no physics layer named 'level %d'" % level)
			continue
		var body := StaticBody2D.new()
		body.name = "Level%d" % level
		body.collision_layer = bit
		body.collision_mask = 0
		var level_segments: Array = segments.get(level, [])
		for index in range(0, level_segments.size(), 2):
			var from: Vector2 = level_segments[index]
			var to: Vector2 = level_segments[index + 1]
			var collision_shape := RectangleShape2D.new()
			collision_shape.size = Vector2(from.distance_to(to), setting("clearance") * 2.0)
			var collision := CollisionShape2D.new()
			collision.shape = collision_shape
			collision.position = from.lerp(to, 0.5)
			collision.rotation = (to - from).angle()
			body.add_child(collision)
		for tile_rect: Rect2 in solid_tiles.get(level, []):
			var tile_shape := RectangleShape2D.new()
			tile_shape.size = tile_rect.size
			var tile_collision := CollisionShape2D.new()
			tile_collision.shape = tile_shape
			tile_collision.position = tile_rect.get_center()
			body.add_child(tile_collision)
		holder.add_child(body)


## The physics layer bit project.godot names "level <n>", 0 when none is.
static func _level_bit(level: int) -> int:
	for i in range(1, 33):
		if str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % i, "")) == "level %d" % level:
			return 1 << (i - 1)
	return 0

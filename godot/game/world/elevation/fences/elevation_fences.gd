@tool
extends Node2D
## Fences along the rims of hills and holes (docs/godot/FENCES.md).
##
## A world paints fences on a `fences` TileMapLayer beside its `elevation` layer (fence_tileset.tres,
## fence_layer.gd): a fence stands a little inside every rim of a painted cell's top, wherever a body
## could otherwise drop to lower ground (a wall's top, a hill's back and sides, a hole's rims), and
## follows the rim around every corner, on all 8 directions a rim can take. Stairs leave a gap.
##
## Elevation mounts this node as its child "Fences" after the cliffs (`mount`). A fence is drawn
## from its style's kit (scripts/art/build-fence-art.py, art/<style>-*.png and <style>.json): posts
## at every corner and evenly along each straight stretch, rails between them. Front runs (north
## and south rims) show the rails as painted; diagonal runs shear them, so posts stay upright and
## the face looking south-west is lit, the one looking south-east shaded; east and west runs show
## the upper rail from above. The pieces:
##   - posts and rails are MeshInstance2Ds under "ElevationFences", a y-sorted Node2D beside the
##     ground layer (never saved with the scene), so they sort with bodies and props: a rail stretch
##     sorts at its south end on a front run (in front of the hill's top) and at its north end on a
##     back run (behind it);
##   - their silhouettes go into the terrain's depth map (ElevationOcclusion.add_occluder, only where
##     the art is opaque), so a body behind a fence on a higher level shows as its ghost behind it,
##     and a fence pixel behind nearer terrain is not drawn (elevation_fence.gdshader);
##   - soft shadows on the ground, falling to the lower right ("Shadows", drawn with the cliffs).
## With `collide`, each level that has fences gets a static body on its physics layer (named
## "level <n>" in project.godot) along every fence `fences.clearance` inside its line, closed back to
## the rim at a run's ends; `blocks_point` closes the strip between a fence and its rim to landings
## and ledge probes (Elevation.body_fits, ledge_below), so nothing drops or hops over a fence.
##
## Owner: world (elevation fences).

const Self := preload("res://game/world/elevation/fences/elevation_fences.gd")
const Services := preload("res://game/shared/services.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const ElevationRims := preload("res://game/world/elevation/elevation_rims.gd")
const ElevationOcclusion := preload("res://game/world/elevation/elevation_occlusion.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const FENCE_SHADER := preload("res://game/world/elevation/fences/elevation_fence.gdshader")
const DEPTH_SHADER := preload("res://game/world/elevation/fences/elevation_fence_depth.gdshader")

const NODE_NAME := "Fences"
## The y-sorted holder of the pieces, beside the ground layer.
const PIECES_NAME := "ElevationFences"
## The fence tile set's data layer: the style a painted cell's fence takes.
const STYLE_DATA_LAYER := "fence_style"
## A cell painted "auto" takes the style of the ground on top (GROUND_STYLES, else DEFAULT_STYLE).
const AUTO_STYLE := "auto"
const DEFAULT_STYLE := "wood"
## Ground (TerrainMaterials names) -> style, for "auto".
const GROUND_STYLES := {
	"highland": "wood", "frozen": "snow", "sanddessert": "sandstone", "forest-floor": "twig",
	"forest-moss": "twig", "amberleaf": "picket", "cavern-floor": "stone", "crystal-floor": "crystal",
	"town-cobble": "stone",
}
## A style's kit: art/<style>-posts.png, -rails.png, -rails-side.png and <style>.json.
const KIT := "res://game/world/elevation/fences/art/%s%s"
## Gameplay values (game-constants.json `fences`); these defaults serve the editor preview.
const DEFAULTS := {"clearance": 8.0}
## Rails shading by the way a run's face looks (the art is painted facing south).
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
## Shadows: the light's fall on the ground (elevation_cast_shadow.gdshader), the shadow's length per
## unit of height, how dark it is, and the contact shadow around a post's foot (world units).
const SHADOW_FALL := Vector2(0.94, 0.34)
const SHADOW_PER_HEIGHT := 0.45
const SHADOW_ALPHA := 0.3
const CONTACT_ALPHA := 0.45
const CONTACT_RADIUS := Vector2(10.0, 4.5)
## A mitre longer than this many offsets becomes a plain offset (very sharp corners).
const MITRE_LIMIT := 3.0
## A back run (the top south of it) sorts this much further south than its foot line past the
## strip behind the hill (elevation.behindDepth − the fence's inset), so a body walking there, on the
## lower ground behind the fence, sorts before it and the fence covers it; bodies on the top stop
## at least BODY_HEIGHT + clearance past the fence line, so they still sort after it.
const BACK_SORT_MARGIN := 6.0
## The player's collision rect height (player_slime.tscn BodyShape, 26), the margin's upper bound.
const BODY_HEIGHT := 26.0
const ELEVATION_DEFAULTS := {"behindDepth": 32.0}

var grid: ElevationGrid
var ground: TileMapLayer
var cell := 64.0
var _pieces: Node2D
## style -> its kit (the JSON), or {} when it has no art.
var _kits: Dictionary = {}
var _materials: Dictionary = {}
## level -> Array of {"polygons": Array[PackedVector2Array], "box": Rect2}: the strips between a
## fence and its rim (inside an odd number of the polygons = closed), ground-layer space.
var _bands: Dictionary = {}


## Builds the fences beside `elevation` (the Elevation node, child of the ground layer) from the
## `fences` layer beside the ground; null (and old fences removed) when there is none.
static func mount(elevation: Node2D, the_grid: ElevationGrid, occlusion: ElevationOcclusion, collide: bool) -> Self:
	var ground_layer := elevation.get_parent() as TileMapLayer
	var existing := elevation.get_node_or_null(NodePath(NODE_NAME)) as Self
	var painted := find_layer(ground_layer)
	if the_grid == null or painted == null or painted.get_used_cells().is_empty():
		if existing != null:
			existing.free()
		return null
	var fences := existing
	if fences == null:
		fences = Self.new()
		fences.name = NODE_NAME
		elevation.add_child(fences)
	else:
		# After the cliffs' groups, which the elevation rebuilds: the shadows draw over the lips.
		elevation.move_child(fences, -1)
	# The flights of stairs (elevation_stairs.gd; read untyped: that script preloads Elevation).
	var flights: Array = elevation.get("stairs") if "stairs" in elevation else []
	fences.build(ground_layer, painted, the_grid, occlusion, collide, flights)
	return fences


## The fences layer beside `ground_layer` (a sibling TileMapLayer whose tile set has the
## `fence_style` data layer), or null.
static func find_layer(ground_layer: TileMapLayer) -> TileMapLayer:
	var parent := ground_layer.get_parent() if ground_layer != null else null
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var candidate := child as TileMapLayer
		if candidate != null and candidate != ground_layer and candidate.tile_set != null \
				and candidate.tile_set.has_custom_data_layer_by_name(STYLE_DATA_LAYER):
			return candidate
	return null


## A gameplay value of game-constants.json `fences` (DEFAULTS without the autoload).
static func setting(key: String) -> float:
	var constants := Services.constants()
	if constants == null:
		return float(DEFAULTS[key])
	return constants.number("fences." + key)


## True when a fence of `level` closes `world_point` to bodies of that level: it lies between a
## fence's collision line and the rim behind it.
func blocks_point(world_point: Vector2, level: int) -> bool:
	var point := world_point - global_position
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


func build(ground_layer: TileMapLayer, painted: TileMapLayer, the_grid: ElevationGrid, occlusion: ElevationOcclusion, collide: bool, flights: Array = []) -> void:
	_clear()
	grid = the_grid
	ground = ground_layer
	cell = float(ground.tile_set.tile_size.x)
	_pieces = Node2D.new()
	_pieces.name = PIECES_NAME
	_pieces.y_sort_enabled = true
	_pieces.position = ground.position
	ground.get_parent().add_child(_pieces)
	var shadows := MeshData.new()
	var depth := {}
	var segments := {}
	var clearance := setting("clearance")
	for run: Dictionary in _runs(_painted_styles(painted), flights):
		var kit: Dictionary = _kits[run["style"]]
		var rim: PackedVector2Array = run["rim"]
		var loop := bool(run["loop"])
		var level := int(run["level"])
		var inset := float(kit["inset"])
		var line := _offset(rim, loop, inset)
		var stop := _offset(rim, loop, inset + clearance)
		_add_run(run, kit, line, shadows, depth)
		if not segments.has(level):
			segments[level] = []
		_add_stops(segments[level], rim, stop, loop)
		_add_band(level, rim, stop, loop)
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
		_build_collision(segments)


func _clear() -> void:
	for child: Node in get_children():
		child.free()
	if is_instance_valid(_pieces):
		_pieces.free()
	_pieces = null
	_bands.clear()
	_materials.clear()


# --- runs ----------------------------------------------------------------------------------

## Painted cells: Vector2i -> style ("auto" kept as is).
func _painted_styles(painted: TileMapLayer) -> Dictionary:
	var styles := {}
	for cell_pos: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell_pos)
		if data != null:
			styles[cell_pos] = str(data.get_custom_data(STYLE_DATA_LAYER))
	return styles


## Every fenced stretch of rim: {style, level, loop, rim (PackedVector2Array, ground-layer space,
## the top on the left of the way along it)}. A fence leaves a gap where a flight of stairs leaves
## the rim (its landing and railings take the fence line's place).
func _runs(styles: Dictionary, flights: Array) -> Array[Dictionary]:
	var rims := ElevationRims.new()
	rims.grid = grid
	rims.cell = cell
	var fenced: Array[Dictionary] = []
	for edge: Dictionary in rims.boundary_edges():
		var style := _style_of(edge, styles)
		if style == "" or _kit(style).is_empty() or _crosses_stairs(edge, float(_kit(style)["inset"]), flights):
			continue
		edge["style"] = style
		fenced.append(edge)
	var runs: Array[Dictionary] = []
	for chain: Array in _chains(fenced):
		var rim := PackedVector2Array()
		var first: Dictionary = chain[0]
		rim.append((first["from"] as Vector2) * cell)
		for edge: Dictionary in chain:
			var to := (edge["to"] as Vector2) * cell
			if rim.size() >= 2:
				var a := rim[rim.size() - 2]
				var b := rim[rim.size() - 1]
				if absf((b - a).normalized().cross((to - b).normalized())) < 1e-4 and (b - a).dot(to - b) > 0.0:
					rim[rim.size() - 1] = to
					continue
			rim.append(to)
		var loop := chain.size() > 2 and _key(first["from"]) == _key((chain[chain.size() - 1] as Dictionary)["to"])
		if loop:
			rim.remove_at(rim.size() - 1)
			# The start may sit in the middle of a straight stretch: merge across it.
			if rim.size() > 3:
				var before := rim[rim.size() - 1]
				var after := rim[1]
				if absf((rim[0] - before).normalized().cross((after - rim[0]).normalized())) < 1e-4:
					rim.remove_at(0)
		runs.append({"style": first["style"], "level": int(first["level"]), "loop": loop, "rim": rim})
	return runs


## The style of the fence along a boundary edge: the painted cell its top belongs to (for the corner
## triangle a chamfer raised, the painted cell across the corner at its level), "" when unpainted.
func _style_of(edge: Dictionary, styles: Dictionary) -> String:
	var from: Vector2 = edge["from"]
	var to: Vector2 = edge["to"]
	var into := Vector2((to - from).y, -(to - from).x).normalized()
	var middle := (from + to) * 0.5
	var level := int(edge["level"])
	var style := ""
	for reach: float in [0.01, 0.5]:
		var point := middle + into * reach
		var at := Vector2i(floori(point.x), floori(point.y))
		if styles.has(at) and grid.has_cell(at) and grid.cell_level[grid.cell_index(at)] == level:
			style = str(styles[at])
			break
	if style == AUTO_STYLE:
		style = str(GROUND_STYLES.get(str(edge["ground"]), DEFAULT_STYLE))
	return style


## True when the fence line along `edge` (cells) would cross a flight of stairs
## (elevation_stairs.gd `occupies`: its landing, steps, railings or posts).
func _crosses_stairs(edge: Dictionary, inset: float, flights: Array) -> bool:
	if flights.is_empty():
		return false
	var from := (edge["from"] as Vector2) * cell
	var to := (edge["to"] as Vector2) * cell
	var into := _left((to - from).normalized())
	for t: float in [0.25, 0.5, 0.75]:
		var point := from.lerp(to, t) + into * inset
		for flight: RefCounted in flights:
			if bool(flight.call(&"occupies", point)):
				return true
	return false


## Fenced edges joined end to start into chains of one level and style: lines first (no edge ends
## at their start), then loops. At a point with several ways on, the sharpest left turn keeps to the
## same top (as the rims do, elevation_rims.gd).
func _chains(edges: Array[Dictionary]) -> Array:
	var outgoing := {}
	var incoming := {}
	for i in edges.size():
		var from_key := _key(edges[i]["from"])
		var to_key := _key(edges[i]["to"])
		if not outgoing.has(from_key):
			outgoing[from_key] = []
		(outgoing[from_key] as Array).append(i)
		if not incoming.has(to_key):
			incoming[to_key] = []
		(incoming[to_key] as Array).append(i)
	var used := PackedByteArray()
	used.resize(edges.size())
	var chains := []
	for pass_index in 2:
		for i in edges.size():
			if used[i]:
				continue
			if pass_index == 0 and _has_predecessor(edges, incoming, used, i):
				continue
			var chain: Array[Dictionary] = [edges[i]]
			used[i] = 1
			var current := i
			while true:
				var next := _next_edge(edges, outgoing, used, current)
				if next < 0:
					break
				chain.append(edges[next])
				used[next] = 1
				current = next
			chains.append(chain)
	return chains


func _has_predecessor(edges: Array[Dictionary], incoming: Dictionary, used: PackedByteArray, i: int) -> bool:
	for j: int in incoming.get(_key(edges[i]["from"]), []):
		if j != i and not used[j] and _same_run(edges[i], edges[j]):
			return true
	return false


func _next_edge(edges: Array[Dictionary], outgoing: Dictionary, used: PackedByteArray, current: int) -> int:
	var best := -1
	var best_turn := INF
	var dir := _dir(edges[current])
	for j: int in outgoing.get(_key(edges[current]["to"]), []):
		if used[j] or not _same_run(edges[current], edges[j]):
			continue
		var next_dir := _dir(edges[j])
		var turn := atan2(dir.x * next_dir.y - dir.y * next_dir.x, dir.dot(next_dir))
		if turn < best_turn:
			best_turn = turn
			best = j
	return best


static func _same_run(a: Dictionary, b: Dictionary) -> bool:
	return int(a["level"]) == int(b["level"]) and str(a["style"]) == str(b["style"])


static func _key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x * 2.0), roundi(point.y * 2.0))


static func _dir(edge: Dictionary) -> Vector2:
	return ((edge["to"] as Vector2) - (edge["from"] as Vector2)).normalized()


## The polyline moved `distance` to its left (into the top), mitred at its corners.
static func _offset(points: PackedVector2Array, loop: bool, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := points.size()
	for i in count:
		var has_before := loop or i > 0
		var has_after := loop or i < count - 1
		var p := points[i]
		var d_before := (p - points[(i - 1 + count) % count]).normalized() if has_before else Vector2.ZERO
		var d_after := (points[(i + 1) % count] - p).normalized() if has_after else Vector2.ZERO
		if not has_before:
			out.append(p + _left(d_after) * distance)
			continue
		if not has_after:
			out.append(p + _left(d_before) * distance)
			continue
		var a := p + _left(d_before) * distance
		var b := p + _left(d_after) * distance
		var denominator := d_before.cross(d_after)
		if absf(denominator) < 1e-6:
			out.append(a)
			continue
		var t := (b - a).cross(d_after) / denominator
		var mitre := a + d_before * t
		out.append(mitre if mitre.distance_to(p) <= MITRE_LIMIT * distance else (a + b) * 0.5)
	return out


static func _left(direction: Vector2) -> Vector2:
	return Vector2(direction.y, -direction.x)


# --- drawing -------------------------------------------------------------------------------

## Posts and rails of one run along its fence line, their shadows and silhouettes.
func _add_run(run: Dictionary, kit: Dictionary, line: PackedVector2Array, shadows: MeshData, depth: Dictionary) -> void:
	var style := str(run["style"])
	var level := int(run["level"])
	var loop := bool(run["loop"])
	var rim: PackedVector2Array = run["rim"]
	var spacing := float(kit["spacing"])
	var half_width := float(kit["posts"]["half_width"])
	var count := line.size()
	var stretches := count if loop else count - 1
	var back_sort := _back_sort(float(kit["inset"]))
	# Post key -> [foot, true while every stretch it stands on is a back run].
	var placed := {}
	if not depth.has(style):
		depth[style] = []
	for s in stretches:
		var a := line[s]
		var b := line[(s + 1) % count]
		# Posts at a run's open ends stand inside it.
		if not loop and s == 0 and a.distance_to(b) > 2.0 * half_width:
			a += (b - a).normalized() * half_width
		if not loop and s == stretches - 1 and a.distance_to(b) > 2.0 * half_width:
			b -= (b - a).normalized() * half_width
		var rim_dir := (rim[(s + 1) % rim.size()] - rim[s]).normalized()
		var outward := -_left(rim_dir)
		# Evenly spaced on the ground: a diagonal run, foreshortened on screen, gets as many posts as
		# its true length asks.
		var steps := maxi(1, roundi(a.distance_to(b) / spacing))
		var posts: Array[Vector2] = []
		for k in steps + 1:
			posts.append(a.lerp(b, float(k) / steps))
		var back := outward.y < -0.01
		for k in steps:
			_add_span(style, kit, level, posts[k], posts[k + 1], outward, back_sort if back else 0.0, shadows, depth[style])
		for post in posts:
			var key := _key(post / cell * 4.0)
			if placed.has(key):
				placed[key][1] = bool(placed[key][1]) and back
			else:
				placed[key] = [post, back]
	for key: Vector2i in placed:
		var entry: Array = placed[key]
		_add_post(style, kit, level, entry[0], back_sort if bool(entry[1]) else 0.0, shadows, depth[style])


## How much further south than its foot line a back run sorts (BACK_SORT_MARGIN).
func _back_sort(inset: float) -> float:
	var constants := Services.constants()
	var behind := float(ELEVATION_DEFAULTS["behindDepth"]) if constants == null else constants.number("elevation.behindDepth")
	return clampf(behind - inset + BACK_SORT_MARGIN, 0.0, setting("clearance") + BODY_HEIGHT - 2.0)


## One post: its sprite at its foot, a contact shadow and a soft shadow towards the lower right.
func _add_post(style: String, kit: Dictionary, level: int, foot: Vector2, sort_offset: float, shadows: MeshData, depth: Array) -> void:
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
	_add_piece(style, kit, foot.y + sort_offset, arrays)
	depth.append([foot.y + float(level) * ElevationOcclusion.LEVEL_UNITS, silhouette])
	var post_width := float(kit["posts"]["half_width"])
	var reach := SHADOW_FALL * float(kit["post_height"]) * SHADOW_PER_HEIGHT
	_add_fade(shadows, foot - Vector2(post_width, 0.0), foot + Vector2(post_width, 0.0), reach, SHADOW_ALPHA)
	_add_contact(shadows, foot)


## The rails between two posts: sheared along a front or diagonal run (they stop at the posts'
## sides), seen from above along an east or west run (the posts cover their ends).
func _add_span(style: String, kit: Dictionary, level: int, a: Vector2, b: Vector2, outward: Vector2, sort_offset: float, shadows: MeshData, depth: Array) -> void:
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
		# A front run's rails stand in front of the top behind them, a back run's behind the top (and in
		# front of the strip behind the hill: `sort_offset`).
		sort_y = (maxf(y0, y1) if outward.y >= 0.0 else minf(y0, y1) + sort_offset) - 0.5
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

## The collision line of a run, closed back to the rim at an open run's ends (pairs of points).
static func _add_stops(segments: Array, rim: PackedVector2Array, stop: PackedVector2Array, loop: bool) -> void:
	var count := stop.size()
	for i in (count if loop else count - 1):
		segments.append(stop[i])
		segments.append(stop[(i + 1) % count])
	if not loop:
		segments.append(rim[0])
		segments.append(stop[0])
		segments.append(stop[count - 1])
		segments.append(rim[rim.size() - 1])


## The strip between a run's collision line and its rim, for `blocks_point`.
func _add_band(level: int, rim: PackedVector2Array, stop: PackedVector2Array, loop: bool) -> void:
	var polygons: Array[PackedVector2Array] = []
	if loop:
		polygons.append(rim)
		polygons.append(stop)
	else:
		var polygon := rim.duplicate()
		var back := stop.duplicate()
		back.reverse()
		polygon.append_array(back)
		polygons.append(polygon)
	var box := Rect2(rim[0], Vector2.ZERO)
	for polygon in polygons:
		for point in polygon:
			box = box.expand(point)
	if not _bands.has(level):
		_bands[level] = []
	(_bands[level] as Array).append({"polygons": polygons, "box": box.grow(1.0)})


func _build_collision(segments: Dictionary) -> void:
	var holder := Node2D.new()
	holder.name = "Collision"
	add_child(holder)
	for level: int in segments:
		var bit := _level_bit(level)
		if bit == 0:
			push_warning("ElevationFences: no physics layer named 'level %d'" % level)
			continue
		var shape := ConcavePolygonShape2D.new()
		shape.segments = PackedVector2Array(segments[level])
		var body := StaticBody2D.new()
		body.name = "Level%d" % level
		body.collision_layer = bit
		body.collision_mask = 0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
		holder.add_child(body)


## The physics layer bit project.godot names "level <n>", 0 when none is.
static func _level_bit(level: int) -> int:
	for i in range(1, 33):
		if str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % i, "")) == "level %d" % level:
			return 1 << (i - 1)
	return 0

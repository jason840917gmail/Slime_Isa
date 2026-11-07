extends RefCounted
## Ledge dressing (docs/godot/ELEVATION.md "Ledge dressing"; the owner, 2026-11-06, after the terraced
## meadow concept: "not all ledges have to be painted the same", "check the art cause we have a
## bunch of ledges not being used, and create new if necessary"): pieces of the cliff dressing atlas
## (scripts/art/build-cliff-dressing.py) placed at the foot of a chain's walls as ElevationSides builds
## it: rocks, roots, mushrooms, bushes, ice. Only at the foot (the owner, 2026-11-06: pieces go "only
## in the bottom"; then, of the icicles down a snow cliff, "random object on the top ledger like
## those ices, remove them all": the rim pieces and the ivy and icicles hanging down front faces were
## removed, 2026-11-07). Sparse and fixed: the border is cut into SLOT-unit slots of the top edge's u
## (which starts by where the chain lies and is pinned at chunk lines), and each slot's luck comes
## from its number, so repainting another hill moves nothing and two chunks agree along their line.
## Nothing goes on a corner (round arcs, folds), over water, under a ramp's slope or by a flight of
## stairs; a back edge (no wall) gets nothing. The pieces are drawn, not bodies: no collision, under
## every body.
##
## One mesh per level ("<level>|dressing", ElevationSides.build), drawn just after that level's
## walls: higher levels' walls, ramps and stairs cover it. Its vertices: UV = px in the atlas;
## colour r = the light (the wall's shadow at a foot), a = the level channel
## (elevation_light.gdshaderinc), so holes darken it as their ground.
##
## Owner: world (elevation).

const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")

const ATLAS_META := "res://asset/MAPS/elevation/dressing/cliff-dressing.json"
const KEY_SUFFIX := "|dressing"
## World units per atlas px (the art is 2 px a unit).
const UNITS_PER_PX := 0.5
## The border is cut into slots this long (world units along it); each draws its own luck.
const SLOT := 56.0
## A slot's chance of a piece at its foot.
const FOOT_CHANCE := 0.36
## A side wall's foot (east or west: the normal's |x| over 0.9) gets this share of FOOT_CHANCE (the
## owner, 2026-11-06: "a lot fewer in the laterals"; front and 45° feet keep the full chance).
const FOOT_SIDE_SHARE := 0.2
## How far from a corner's arc (world units along the border) nothing is placed.
const CORNER_CLEAR := 36.0
## Sizes (times the atlas piece).
const FOOT_SCALE := Vector2(0.6, 0.95)
## A piece stands this far out past the foot line.
const FOOT_OUT_AT := 3.0
## The light of a piece at a foot (in the wall's shadow).
const FOOT_LIGHT := 0.86
## What grows where, by the lower ground at a foot: atlas piece names. A ground not listed gets
## nothing there. (The golden boulders and sandstone blocks "don't fit well", the owner 2026-11-06:
## gone, with the ivy and icicles, from the atlas too.)
const GRASS_FOOT := ["mossy-rock", "mushroom-rock", "root-rock"]
const FOOT_SETS := {
	"highland": GRASS_FOOT, "gravel-path": GRASS_FOOT, "garden-soil": GRASS_FOOT,
	"forest-floor": ["mushroom-rock", "mossy-rock", "root-rock"], "forest-moss": ["mushroom-rock", "mossy-rock", "root-rock"],
	"amberleaf": ["autumn-rocks", "mushroom-rock", "root-rock"],
	"sanddessert": ["dead-bush", "skull"],
	"frozen": ["snowy-fir", "snowy-rock", "ice-crystals"], "cavern-floor": ["basalt-rocks", "mushroom-rock"],
	"crystal-floor": ["crystals", "basalt-rocks"], "black-ashlands": ["lava-rock", "basalt-rocks"],
	"town-cobble": ["ruins"],
}
## name -> {rect: Rect2 (px), anchor: Vector2 (px in the piece)}.
var _pieces := {}
## level (int) -> pieces [painter's key, PackedVector2Array, PackedVector2Array, PackedColorArray].
var _by_level := {}
## Scales every chance (a world's density; 0 places nothing).
var density := 1.0
## The overworld position of the builder's (0, 0) (ElevationSides.origin: a chunk world's place). The
## slots draw their luck by the chain's `u`, which already holds it (`add_chain`).
var origin := Vector2.ZERO


func _init() -> void:
	if not FileAccess.file_exists(ATLAS_META):
		return
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_META))
	if not meta is Dictionary:
		return
	for name: String in meta:
		var entry: Dictionary = meta[name]
		var r: Array = entry["rect"]
		var a: Array = entry["anchor"]
		_pieces[name] = {"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])), "anchor": Vector2(float(a[0]), float(a[1]))}


func is_ready() -> bool:
	return not _pieces.is_empty() and density > 0.0


## Places one chain's dressing (`ElevationSides._add_chain`'s border and its fibres): `foots` the foot
## line, `depths` the levels each fibre hangs, `fibres` top edge to foot. `under_ramp`, `near_stairs`
## (Callable(point) -> bool, may be invalid): where nothing goes. `u` (world units, per point then at
## the chain's end): the measure along the border the slots are cut by, the top edge's
## (ElevationSides._seed_along): pinned to the chunk lines a chain crosses, so two chunks cut the same
## slots there and place the same pieces.
func add_chain(border: RefCounted, foots: PackedVector2Array, depths: PackedFloat32Array,
		fibres: PackedVector2Array, loop: bool, level: float,
		under_ramp: Callable, near_stairs: Callable, u: PackedFloat32Array = PackedFloat32Array()) -> void:
	var points: PackedVector2Array = border.points
	var normals: PackedVector2Array = border.normals
	var count := points.size()
	if count < 2:
		return
	var along := PackedFloat32Array()
	var length := 0.0
	for i in count:
		if i > 0:
			length += points[i - 1].distance_to(points[i])
		along.append(length)
	var total := length + (points[count - 1].distance_to(points[0]) if loop else 0.0)
	var clear := _corner_clearance(border, along, total, loop)
	# The slots' measure: `u` per point (without it, the length from the chain's start).
	var at_u := along
	if u.size() >= count:
		at_u = u.slice(0, count)
	var first := ceili(at_u[0] / SLOT - 0.5)
	var last := floori(at_u[count - 1] / SLOT - 0.5)
	for slot in range(first, last + 1):
		var i := _index_at(at_u, (slot + 0.5) * SLOT)
		if clear[i] < CORNER_CLEAR:
			continue
		var n := normals[i]
		if ElevationSidesHelpers.backness(n) > 0.5:
			continue
		# Luck by the slot (the same in both chunks at a line) and the level.
		var seed := slot * 73856093 ^ int(level + 8.0) * 19349663
		# A piece at the foot (dry ground, a real foot), far fewer along a side wall.
		var low_ground: String = border.low_ground[i]
		var foot_chance := FOOT_CHANCE * density * (FOOT_SIDE_SHARE if absf(n.x) > 0.9 else 1.0)
		if _hash(seed, 6) < foot_chance and FOOT_SETS.has(low_ground) and border.foot[i] > 0.5 \
				and border.water[i] < 0.5 and depths[i] > 0.25:
			var name := _pick(FOOT_SETS[low_ground], _hash(seed, 7))
			var way := fibres[i].normalized() if fibres[i].length() > 0.01 else n
			var at := foots[i] + way * FOOT_OUT_AT
			if name != "" and not _blocked(at, under_ramp, near_stairs):
				var low := level - float(border.drop[i])
				_add_piece(int(level), name, at, lerpf(FOOT_SCALE.x, FOOT_SCALE.y, _hash(seed, 8)), FOOT_LIGHT, low, at.y)


## The dressing's meshes, one per level: [{key, level, arrays}] (ElevationSides.build adds them after
## each level's walls).
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level: int in _by_level:
		var pieces: Array = _by_level[level]
		pieces.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var arrays := MeshData.new()
		for piece: Array in pieces:
			arrays.vertices.append_array(piece[1])
			arrays.uvs.append_array(piece[2])
			arrays.colors.append_array(piece[3])
		out.append({"key": "%d%s" % [level, KEY_SUFFIX], "level": level, "dressing": true, "arrays": arrays})
	return out


## A piece's quad: its anchor at `at`, `scale` times the atlas piece, drawn by `key` (its screen y).
func _add_piece(mesh_level: int, name: String, at: Vector2, scale: float, light: float, level: float, key: float) -> void:
	var piece: Dictionary = _pieces[name]
	var rect: Rect2 = piece["rect"]
	var anchor: Vector2 = piece["anchor"]
	var size := rect.size * UNITS_PER_PX * scale
	var corner := at - anchor * UNITS_PER_PX * scale
	var quad := [corner, corner + Vector2(size.x, 0.0), corner + size, corner + Vector2(0.0, size.y)]
	var uv := [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)]
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var colour := Color(light, 0.0, 0.0, (level + 4.0) / 8.0)
	for index: int in [0, 1, 2, 0, 2, 3]:
		verts.append(quad[index])
		uvs.append(uv[index])
		colors.append(colour)
	if not _by_level.has(mesh_level):
		_by_level[mesh_level] = []
	(_by_level[mesh_level] as Array).append([key, verts, uvs, colors])


func _pick(names: Array, luck: float) -> String:
	var known: Array[String] = []
	for name: String in names:
		if _pieces.has(name):
			known.append(name)
	if known.is_empty():
		return ""
	return known[mini(int(luck * known.size()), known.size() - 1)]


static func _blocked(point: Vector2, under_ramp: Callable, near_stairs: Callable) -> bool:
	return (under_ramp.is_valid() and bool(under_ramp.call(point))) or (near_stairs.is_valid() and bool(near_stairs.call(point)))


## Per point, the distance along the border to the nearest point on a corner's arc (INF without one).
static func _corner_clearance(border: RefCounted, along: PackedFloat32Array, total: float, loop: bool) -> PackedFloat32Array:
	var corner: PackedInt32Array = border.corner
	var count := along.size()
	var out := PackedFloat32Array()
	out.resize(count)
	out.fill(INF)
	var marks := PackedFloat32Array()
	for i in count:
		if corner[i] >= 0:
			marks.append(along[i])
	if not loop:
		# An open chain's ends are corners too (an open cliff's end, a wall's end).
		marks.append(0.0)
		marks.append(along[count - 1])
	for i in count:
		for m in marks:
			var d := absf(along[i] - m)
			if loop:
				d = minf(d, total - d)
			out[i] = minf(out[i], d)
	return out


## The point nearest `at` along the border (binary search on `along`).
static func _index_at(along: PackedFloat32Array, at: float) -> int:
	var lo := 0
	var hi := along.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if along[mid] < at:
			lo = mid + 1
		else:
			hi = mid
	return lo


## 0 … 1 for a seed and a salt.
static func _hash(seed: int, salt: int) -> float:
	var h := (seed ^ (salt * 83492791)) & 0x7fffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0x7fffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0x7fffffff
	h = (h >> 16) ^ h
	return float(h & 0xffffff) / float(0x1000000)


class ElevationSidesHelpers:
	## The same as ElevationSides.backness (no preload cycle).
	static func backness(n: Vector2) -> float:
		return smoothstep(0.3, 0.7, -n.y)

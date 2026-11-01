extends SceneTree
## Checks the chunk-line rule (docs/design/2026-10-16-level-design.md, rule 11, owner 2026-11-01):
## terrain closes every line two chunk worlds share, except one to three crossings, each inside those
## two chunks and no wider than a road. Every chunk world of the atlas is loaded alone, as the game
## loads it; the slime's circle is tried every SAMPLE units just inside each of its four edges
## (against the bodies on its layers at the level painted there, and solid ground tiles; bridge
## decks open theirs), and each line two touching chunks share is reported by its crossings: the
## stretches open on both sides.
##
##   "<Godot console exe>" --headless --path godot -s res://tools/check_chunk_lines.gd [-- --world=<text>] [--all]
##
## `--world=<text>` keeps the lines of the chunks whose id holds the text; `--all` also lists the
## lines that pass. A line is flagged when:
## - a crossing is wider than a road (MAX_CROSSING) or lies within CORNER_MARGIN of a chunk corner
##   (walking through it would touch a third chunk);
## - two chunks of one region have no crossing, or any two have more than MAX_CROSSINGS;
## - one side is open for at least ONE_SIDED_MIN where the other is closed (the slime would cross
##   into trees, water or a wall, or land elsewhere through an exit's opening back).
## Lines between two regions with no crossing are closed borders and pass.
##
## Owner: world (atlas).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const BridgeDeck := preload("res://game/world/bridge_deck.gd")

const INDEX_PATH := "res://game/scenes/scene_index.json"
const WORLD_PREFIX := "world."
const WORLD_GROUND := "res://game/world/world_ground.gd"
const COLUMNS := "abcdefgh"
const CHUNK := 2048.0
const SAMPLE := 32.0
const INSET := 16.0
## The slime's body radius (player.gd's circle, a little less so a snug lane still counts open).
const RADIUS := 14.0
## Ground tiles nothing walks on (tile custom data `tile_id`).
const SOLID: PackedStringArray = ["deep-water", "rock-wall"]
const MAX_CROSSING := 256.0
const CORNER_MARGIN := 128.0
const MAX_CROSSINGS := 3
const ONE_SIDED_MIN := 64.0
## Physics layers the slime collides with besides its level's (world 1, water 11); levels from 15.
const BASE_MASK := 1 | (1 << 10)
const LEVEL_LAYER_ZERO := 14

## Vector2i(column, row) -> {"id": String, "region": String, "edges": {side: PackedByteArray}}.
var _chunks: Dictionary = {}
var _flagged := 0
var _passed := 0


func _initialize() -> void:
	var filter := ""
	var show_all := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--world="):
			filter = arg.trim_prefix("--world=")
		elif arg == "--all":
			show_all = true
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	var pattern := RegEx.create_from_string("^(.+)-([a-h])([1-8])$")
	var ids: Array[String] = []
	for key: String in index:
		if key.begins_with(WORLD_PREFIX) and pattern.search(key.substr(WORLD_PREFIX.length())) != null:
			ids.append(key.substr(WORLD_PREFIX.length()))
	ids.sort()
	for id in ids:
		var found := pattern.search(id)
		var at := Vector2i(COLUMNS.find(found.get_string(2)), int(found.get_string(3)) - 1)
		var edges := await _sample(str(index[WORLD_PREFIX + id]))
		if not edges.is_empty():
			_chunks[at] = {"id": id, "region": found.get_string(1), "edges": edges}
	for at: Vector2i in _chunks:
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other: Vector2i = at + step
			if not _chunks.has(other):
				continue
			var a: Dictionary = _chunks[at]
			var b: Dictionary = _chunks[other]
			if filter != "" and not (str(a["id"]).contains(filter) or str(b["id"]).contains(filter)):
				continue
			var a_side := "east" if step == Vector2i.RIGHT else "south"
			var b_side := "west" if step == Vector2i.RIGHT else "north"
			_check_line(a, b, (a["edges"] as Dictionary)[a_side], (b["edges"] as Dictionary)[b_side],
					"|" if step == Vector2i.RIGHT else "/", show_all)
	print("chunk lines: %d flagged, %d pass" % [_flagged, _passed])
	quit(0)


## Loads one chunk world alone and returns which sample points just inside each edge are open:
## {"north"|"south"|"west"|"east": PackedByteArray (1 = open)}; {} when it does not load.
func _sample(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var scene := load(path) as PackedScene
	if scene == null:
		return {}
	var world := scene.instantiate() as Node2D
	if world == null:
		return {}
	root.add_child(world)
	var ground: TileMapLayer = null
	var elevation: TileMapLayer = null
	for child: Node in world.get_children():
		var layer := child as TileMapLayer
		if layer == null:
			continue
		var script := layer.get_script() as Script
		if script != null and script.resource_path == WORLD_GROUND:
			ground = layer
		elif layer.name == "elevation":
			elevation = layer
	if ground != null:
		Elevation.mount(ground, true)
		BridgeDeck.lay(world, ground)
	for i in 4:
		await physics_frame
	var space := world.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collide_with_areas = false
	var count := int(CHUNK / SAMPLE)
	var edges := {}
	for side: String in ["north", "south", "west", "east"]:
		var open := PackedByteArray()
		open.resize(count)
		for i in count:
			var along := (i + 0.5) * SAMPLE
			var at := Vector2(along, INSET) if side == "north" else Vector2(along, CHUNK - INSET) if side == "south" \
					else Vector2(INSET, along) if side == "west" else Vector2(CHUNK - INSET, along)
			open[i] = 1 if _is_open(world, ground, elevation, space, query, at) else 0
		edges[side] = open
	world.queue_free()
	await process_frame
	return edges


func _is_open(world: Node2D, ground: TileMapLayer, elevation: TileMapLayer, space: PhysicsDirectSpaceState2D,
		query: PhysicsShapeQueryParameters2D, at: Vector2) -> bool:
	var global := world.to_global(at)
	query.transform = Transform2D(0.0, global)
	var free := false
	for level: int in _levels_at(elevation, global):
		query.collision_mask = BASE_MASK | (1 << (LEVEL_LAYER_ZERO + level))
		if space.intersect_shape(query, 1).is_empty():
			free = true
			break
	if not free:
		return false
	if ground == null:
		return true
	var cell := ground.local_to_map(ground.to_local(global))
	var tile := ground.get_cell_tile_data(cell)
	if tile == null:
		return false
	return BridgeDeck.is_bridged(ground, cell) or not SOLID.has(str(tile.get_custom_data("tile_id")))


## The levels the slime may stand on at `global`: the level painted there (0 unpainted); on a flight
## of stairs (a tile with no level) the levels of the cells around it, the two it joins.
func _levels_at(elevation: TileMapLayer, global: Vector2) -> Array[int]:
	if elevation == null:
		return [0]
	var cell := elevation.local_to_map(elevation.to_local(global))
	var level: Variant = _level_of(elevation, cell)
	if level != null:
		return [int(level)]
	var out: Array[int] = []
	for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var near: Variant = _level_of(elevation, cell + step)
		if near != null and not out.has(int(near)):
			out.append(int(near))
	return out if not out.is_empty() else [0]


## The level painted on `cell` (0 when unpainted), null for a stairs tile.
func _level_of(elevation: TileMapLayer, cell: Vector2i) -> Variant:
	var data := elevation.get_cell_tile_data(cell)
	if data == null:
		return 0
	var level: Variant = data.get_custom_data("elevation_level")
	return int(level) if level is int and not str(data.get_custom_data("elevation_kind")).begins_with("stairs") else null


func _check_line(a: Dictionary, b: Dictionary, a_open: PackedByteArray, b_open: PackedByteArray, mark: String,
		show_all: bool) -> void:
	var both := PackedByteArray()
	var a_only := PackedByteArray()
	var b_only := PackedByteArray()
	for i in a_open.size():
		both.append(1 if a_open[i] == 1 and b_open[i] == 1 else 0)
		a_only.append(1 if a_open[i] == 1 and b_open[i] == 0 else 0)
		b_only.append(1 if a_open[i] == 0 and b_open[i] == 1 else 0)
	# A gap of one sample lies between two blocked points: narrower than the slime, no crossing.
	var crossings := _runs(both).filter(func(run: Vector2) -> bool: return run.y - run.x > SAMPLE)
	var problems: Array[String] = []
	var same_region := str(a["region"]) == str(b["region"])
	if crossings.is_empty() and same_region:
		problems.append("no crossing")
	if crossings.size() > MAX_CROSSINGS:
		problems.append("%d crossings" % crossings.size())
	for run: Vector2 in crossings:
		if run.y - run.x > MAX_CROSSING:
			problems.append("%s wider than a road" % _span(run))
		if run.x < CORNER_MARGIN or run.y > CHUNK - CORNER_MARGIN:
			problems.append("%s at a corner" % _span(run))
	for pair: Array in [[a_only, str(a["id"])], [b_only, str(b["id"])]]:
		for run: Vector2 in _runs(pair[0]):
			if run.y - run.x >= ONE_SIDED_MIN:
				problems.append("%s open on %s's side only" % [_span(run), pair[1]])
	var name := "%s %s %s" % [a["id"], mark, b["id"]]
	var listed := ", ".join(crossings.map(func(run: Vector2) -> String: return _span(run))) if not crossings.is_empty() else "none"
	if problems.is_empty():
		_passed += 1
		if show_all:
			print("  ok  %s: crossings %s" % [name, listed])
	else:
		_flagged += 1
		print("  !!  %s: crossings %s; %s" % [name, listed, "; ".join(problems)])


## Runs of 1s: Vector2(start, end) in units along the line.
func _runs(flags: PackedByteArray) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var first := -1
	for i in flags.size() + 1:
		var on := i < flags.size() and flags[i] == 1
		if on and first < 0:
			first = i
		elif not on and first >= 0:
			out.append(Vector2(first * SAMPLE, i * SAMPLE))
			first = -1
	return out


func _span(run: Vector2) -> String:
	return "%d-%d" % [int(run.x), int(run.y)]

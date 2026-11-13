extends SceneTree
## Puts the West town's villagers and animals (docs/godot/VILLAGERS.md) on a patch of grass in a
## row, lets them live for a while (wander circles, routes, follows, idles) and saves frames of it,
## so their art and moves can be checked without a world. Needs a window (not --headless):
##
##   "<Godot console exe>" --path godot -s res://tools/capture_villagers.gd -- --out=<dir>
##       [--only=penny,pig] [--villagers | --animals | --cave] [--seconds=8] [--every=4] [--zoom=2] [--per-row=6]
##
## Frames go to <dir>/frame-0000.png ...; the cast's names to <dir>/cast.txt. `--cave` films the
## cave animals (docs/godot/VILLAGERS.md "Cave animals") on a cavern-floor colour instead.
##
## With `--scene=res://...tscn --center=<x>,<y>` it films that world instead (a town chunk, a room),
## the camera at that point, its villagers and animals living as placed: the world's areas are
## registered as main.gd does (their `npc-wander` areas count), but there is no player.

const VILLAGER_DIR := "res://game/scenes/characters/villagers/"
const ANIMAL_DIR := "res://game/scenes/objects/animals/"
const CAVE_DIR := "res://game/scenes/objects/cave-animals/"
const GRASS := Color(0.41, 0.52, 0.27)
const CAVE_FLOOR := Color(0.27, 0.25, 0.31)
const SPACING := 140.0
const ROW_GAP := 200.0
## Who follows whom in the capture (in a world the owner sets `follow` in the Inspector).
const FOLLOWS := {"dany": "isa", "dan": "gavy", "biscuit": "old-sedge", "piglet": "pig", "chick": "hen",
	"duckling": "duck"}

var _out := ""
var _per_row := 6
var _dirs: PackedStringArray = PackedStringArray([VILLAGER_DIR, ANIMAL_DIR])
var _floor := GRASS
var _only: PackedStringArray = PackedStringArray()
var _seconds := 8.0
var _every := 4
var _zoom := 2.0
var _scene := ""
var _center := Vector2.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--every="):
			_every = int(arg.trim_prefix("--every="))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--per-row="):
			_per_row = maxi(1, int(arg.trim_prefix("--per-row=")))
		elif arg == "--villagers":
			_dirs = PackedStringArray([VILLAGER_DIR])
		elif arg == "--animals":
			_dirs = PackedStringArray([ANIMAL_DIR])
		elif arg == "--cave":
			_dirs = PackedStringArray([CAVE_DIR])
			_floor = CAVE_FLOOR
		elif arg.begins_with("--scene="):
			_scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--center="):
			var parts := arg.trim_prefix("--center=").split(",")
			_center = Vector2(float(parts[0]), float(parts[1])) if parts.size() == 2 else Vector2.ZERO
	if _out.is_empty():
		push_error("capture_villagers: pass --out=<dir>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	if _scene.is_empty():
		_run.call_deferred()
	else:
		_run_scene.call_deferred()


## Films the world `_scene` around `_center`.
func _run_scene() -> void:
	var packed := load(_scene) as PackedScene
	if packed == null:
		push_error("capture_villagers: cannot load %s" % _scene)
		quit(1)
		return
	var world_root := packed.instantiate() as Node2D
	root.add_child(world_root)
	var camera := Camera2D.new()
	camera.zoom = Vector2(_zoom, _zoom)
	camera.position = _center
	root.add_child(camera)
	camera.make_current()
	await process_frame
	# The world's areas, as main.gd's bootstrap registers them: the npc-wander areas villagers and
	# animals wander in.
	var world := Services.world()
	var registered: bool = world != null and world.register_world(world_root)
	for node in get_nodes_in_group(&"npc"):
		if node.has_method(&"configure_wander"):
			var key := str(node.call(&"get_instance_id_key")) if node.has_method(&"get_instance_id_key") else ""
			node.call(&"configure_wander", world.npc_wander_area(key).get("perimeter", {}) if registered else {})
	await _film()


func _run() -> void:
	var world := Node2D.new()
	world.y_sort_enabled = true
	root.add_child(world)
	var paths := _scenes()
	var rows := ceili(paths.size() / float(_per_row))
	var size := Vector2(_per_row * SPACING + SPACING, rows * ROW_GAP + ROW_GAP)
	var grass := ColorRect.new()
	grass.color = _floor
	grass.size = size
	grass.position = -size / 2.0
	grass.z_index = -10
	root.add_child(grass)
	root.move_child(grass, 0)
	var names := PackedStringArray()
	for index in paths.size():
		var node := (load(paths[index]) as PackedScene).instantiate() as Node2D
		node.position = Vector2((index % _per_row - (_per_row - 1) / 2.0) * SPACING,
			(index / _per_row - (rows - 1) / 2.0) * ROW_GAP + ROW_GAP * 0.3)
		world.add_child(node)
		names.append(paths[index].get_file().get_basename())
	var camera := Camera2D.new()
	camera.zoom = Vector2(_zoom, _zoom)
	root.add_child(camera)
	camera.make_current()
	for follower: String in FOLLOWS:
		var node := world.get_node_or_null(NodePath(follower))
		var leader := world.get_node_or_null(NodePath(FOLLOWS[follower]))
		if node == null or leader == null:
			continue
		var holder: Node = node.get_node_or_null(^"NpcScript") if node.has_node(^"NpcScript") else node
		holder.set(&"follow", holder.get_path_to(leader))
	await process_frame
	for node in get_nodes_in_group(&"npc"):
		if node.has_method(&"configure_wander"):
			node.call(&"configure_wander", {})
	var file := FileAccess.open(_out.path_join("cast.txt"), FileAccess.WRITE)
	file.store_string("\n".join(names) + "\n")
	await _film()


## Saves a frame every `_every` physics ticks for `_seconds`, then quits.
func _film() -> void:
	var frames := int(_seconds * Engine.physics_ticks_per_second)
	var saved := 0
	for frame in frames:
		await physics_frame
		if frame % _every != 0:
			continue
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("frame-%04d.png" % saved))
		saved += 1
	print("capture_villagers: %d frames in %s" % [saved, _out])
	quit()


func _scenes() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in _dirs:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tscn") and (_only.is_empty() or _only.has(file.get_basename())):
				out.append(dir + file)
	return out

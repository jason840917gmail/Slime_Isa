extends SceneTree
## Lists the joints between levels that are drawn with the plain join instead of the fold
## (docs/godot/ELEVATION.md "Side walls", "The joint folds"): places to repaint if they show. Where a
## lower top's straight side meets a higher wall's south face, or its south wall a higher wall's
## straight side, and that wall runs on at least 2 cells past it, the two fold into one rock face;
## everywhere else the lower wall just ends against the higher one. Every world of game/scenes/scene_index.json that paints elevation is built from its
## painting (no cache read, none written) and each such place is listed by its cell in the scene:
##
##   "<Godot console exe>" --headless --path godot -s res://tools/check_cliff_joints.gd [-- --world=<text>] [--all]
##
## `--world=<text>` keeps the worlds whose id holds the text; `--all` also lists the joints that fold.
## Listed:
## - a wall that ends against another level's wall with a 45° edge at its end or within 2 cells of it;
## - a ledge's side against a wall that is no straight south face there (a 45° face, or the wall
##   turns at that very place);
## - a ledge's side against a wall that runs on less than 2 cells past it (a slot a cell wide).
## - a ledge's south wall against a taller wall's side that runs on too short below it for a fold.
##
## Owner: world (elevation).

const Services := preload("res://game/shared/services.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const SCENE_INDEX := "res://game/scenes/scene_index.json"


func _initialize() -> void:
	var filter := ""
	var show_all := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--world="):
			filter = arg.trim_prefix("--world=")
		elif arg == "--all":
			show_all = true
	await process_frame
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE_INDEX))
	Elevation.ignore_cache = true
	var plain := 0
	var folded := 0
	var worlds := 0
	for id: String in index:
		if not id.begins_with("world."):
			continue
		var world_id := id.trim_prefix("world.")
		if filter != "" and not world_id.contains(filter):
			continue
		var packed := load(str(index[id])) as PackedScene
		if packed == null:
			continue
		var world := packed.instantiate() as Node2D
		var ground := Elevation.find_ground_in(world)
		var painted := Elevation.find_layer(ground) if ground != null else null
		if painted == null or (painted.get_used_cells().is_empty() and not Elevation.paints_past_edges(ground)):
			world.free()
			continue
		root.add_child(world)
		Services.world().register_world(world)
		var elevation: Elevation = Services.world().elevation
		worlds += 1
		var lines: Array[String] = []
		for joint: Dictionary in (elevation.side_joints if elevation != null else []):
			var kind := str(joint["kind"])
			if kind == "fold":
				folded += 1
				if not show_all:
					continue
			else:
				plain += 1
			var cell: Vector2 = joint["cell"]
			lines.append("  cell (%s, %s)  level %d against level %d: %s" % [_number(cell.x), _number(cell.y),
					int(joint["level"]), int(joint["against"]), _what(joint)])
		lines.sort()
		if not lines.is_empty():
			print(world_id)
			for line in lines:
				print(line)
		world.queue_free()
		await process_frame
	print("cliff joints: %d with the plain join, %d that fold, in %d worlds" % [plain, folded, worlds])
	quit(0)


## What a joint is, in words.
static func _what(joint: Dictionary) -> String:
	match str(joint["kind"]):
		"fold":
			return "folds"
		"diagonal":
			var run := float(joint.get("run", 0.0))
			if run < 0.01:
				return "a 45° edge ends against the wall"
			return "the wall ends against it and turns 45° only %s cell(s) on (2 needed)" % _number(run)
		"front-short":
			return "the wall ends against a taller wall's side that runs on only %s cell(s) below it (%s needed)" % [
					_number(float(joint.get("run", 0.0))), _number(float(joint.get("needed", 2.0)))]
		"ledge-short":
			return "the ledge's wall runs only %s cell(s) straight out from the taller wall's side (%s needed)" % [
					_number(float(joint.get("run", 0.0))), _number(float(joint.get("needed", 1.0)))]
		"short":
			return "the ledge's side meets a wall that runs on only %s cell(s) past it (2 needed)" % _number(float(joint.get("run", 0.0)))
		_:
			return "the ledge's side meets the wall where it is no straight south face (a 45° face, or it turns there)"


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value

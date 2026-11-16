extends SceneTree
## Renders painted vines (docs/godot/SKINS.md "Painting vines"; game/world/vines/vine_layer.gd) with
## the game's own drawing: by default the playground's Feral plateau.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_vines.gd -- --out=<dir>
## Writes <dir>/vines.png. `--scene=<res path>` renders another world, `--cells=<x>,<y>,<w>,<h>` that
## rectangle of cells, at `--zoom=<n>` (2). `--probe` also prints what every VineLayer of the world
## answers the climb (feral_climb.gd) along each of its painted rectangles: where the slime takes
## hold from the foot and from the lip, where it gets off, where it lands.
## `--place=<scene res path>@<x>,<y>` (any number of them) stands an object in the world for the
## picture only (a doorway on a wall, say), and `--hide=<node name>` hides the world's nodes of that
## name (the vines, to see the bare wall): nothing is saved.

const Services := preload("res://game/shared/services.gd")
const VineLayerScript := preload("res://game/world/vines/vine_layer.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const SCENE := "res://game/scenes/worlds/playground.tscn"
const DEFAULT_OUT := "user://vines"
const CELL := 64.0
## The Feral plateau and the ground before it, in cells.
const PLATEAU := Rect2(108, 28, 12, 11)


func _initialize() -> void:
	var out := DEFAULT_OUT
	var scene := SCENE
	var cells := PLATEAU
	var zoom := 2.0
	var probe := false
	var placed: Array = []
	var hidden := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--cells="):
			var parts := arg.trim_prefix("--cells=").split_floats(",")
			if parts.size() == 4:
				cells = Rect2(parts[0], parts[1], parts[2], parts[3])
		elif arg.begins_with("--zoom="):
			zoom = maxf(0.25, arg.trim_prefix("--zoom=").to_float())
		elif arg == "--probe":
			probe = true
		elif arg.begins_with("--hide="):
			hidden.append(arg.trim_prefix("--hide="))
		elif arg.begins_with("--place="):
			var place := arg.trim_prefix("--place=").split("@")
			var at := place[1].split_floats(",") if place.size() == 2 else PackedFloat64Array()
			if at.size() == 2:
				placed.append([place[0], Vector2(at[0], at[1])])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	# The playground's skins corner (the Feral plateau's vines) stays only in the body-shapes mode.
	ReworkMode.set_on(true)
	var world := (load(scene) as PackedScene).instantiate() as Node2D
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	for place: Array in placed:
		var object := (load(str(place[0])) as PackedScene).instantiate() as Node2D
		object.position = place[1]
		world.add_child(object)
	for node_name: String in hidden:
		for node: Node in world.find_children(node_name, "CanvasItem", true, false):
			(node as CanvasItem).visible = false
	viewport.add_child(world)
	# As the game does: water, terrain edges and the elevation with its collision.
	Services.world().register_world(world)
	for i in 6:
		await physics_frame
	camera.zoom = Vector2(zoom, zoom)
	viewport.size = Vector2i(cells.size * CELL * zoom)
	camera.position = cells.position * CELL
	for i in 6:
		await process_frame
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join("vines.png")))
	print("saved to ", ProjectSettings.globalize_path(out))
	if probe:
		for node: Node in world.find_children("*", "TileMapLayer", true, false):
			if node is VineLayerScript:
				_probe(node as VineLayerScript)
	quit(0)


## Prints what `layer` answers the climb along each painted rectangle's middle column.
func _probe(layer: VineLayerScript) -> void:
	for patch: Rect2i in layer.patches():
		var x := (patch.position.x + patch.size.x * 0.5) * CELL
		var rim := patch.position.y * CELL
		var foot := patch.end.y * CELL
		var below := layer.to_global(Vector2(x, foot + 40.0))
		var above := layer.to_global(Vector2(x, rim - 30.0))
		var from_foot: Vector2 = layer.call(&"_hold_from", below, Vector2.UP)
		var from_lip: Vector2 = layer.call(&"_hold_from", above, Vector2.DOWN)
		print("vines %s (cells): rim y %s, foot y %s" % [patch, rim, foot])
		print("  hold from the foot %s -> %s; from the lip %s -> %s" % [below, from_foot, above, from_lip])
		var top_feet := layer.to_global(Vector2(x, rim + 4.0 + VineLayerScript.FEET_BELOW_CENTRE))
		print("  off over the rim from %s -> %s; off at the foot from %s -> %s" % [top_feet, layer.climb_exit(top_feet, Vector2.UP),
			from_foot, layer.climb_exit(from_foot, Vector2.DOWN)])
		var mid := layer.to_global(Vector2(x, (rim + foot) * 0.5 + VineLayerScript.FEET_BELOW_CENTRE))
		var past_side := layer.to_global(Vector2(patch.position.x * CELL - 30.0, layer.to_local(mid).y))
		print("  midway %s allowed %s, lands %s; off the side %s lets go %s, lands %s" % [mid, layer.climb_allows(mid),
			layer.climb_landing(mid), past_side, layer.climb_lets_go(past_side), layer.climb_landing(past_side)])

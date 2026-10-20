extends SceneTree
## Renders the dungeon dividers' gates in Fatty's Lair's rooms with the game's own drawing, shut and
## open, for checking that a gate closes its whole cell and sorts at its foot (docs/godot/FENCES.md
## "Dungeon dividers"). Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_divider_gates.gd -- --out=<dir>
## For each gate it writes <dir>/<room>-<gate>-shut.png and -open.png (close-ups at 2x), and the same
## without slimes (-shut-clean.png, -open-clean.png). In the first two three test
## slimes walk north into the gate with the player's collision rect (at its middle and on each side
## of it, where a shut gate used to leave a hole) and stand where they stop, and one
## stands just north of the shut gate (drawn behind it). It prints where each walk stopped. The
## Weigh House also gets a gate painted into its north-south divider (in memory, never saved), which
## the slimes walk into from the west.
## The rooms are built as the game builds them (Elevation.mount with collision); the scenes are not
## changed.

const Elevation := preload("res://game/world/elevation/elevation.gd")
const SLIME := preload("res://asset/characters/256x256-tile_8x8-slime-v2-page-1.webp")
const ROOMS := "res://game/scenes/worlds/rooms/fatty-lair/%s.tscn"
const GATE_SCENE := "res://game/scenes/objects/dungeon/divider-gate.tscn"
const DEFAULT_OUT := "user://divider-gates"
const CELL := 64.0
## Room -> its gates (node names under Objects).
const GATES := {
	"r7-bell-bridge": ["r7-gate"],
	"old-armoury": ["armoury-door"],
	"c2-weigh-house": ["c2-east-door", "c2-west-door", "north-south-gate"],
	"r5-eye-hall": ["r5-inner-door", "r5-alcove-door"],
}
## The gate painted into the Weigh House's north-south divider (x = 6) for the picture: its cell.
const NORTH_SOUTH_CELL := Vector2i(6, 10)
## The fence palette's eye gate tile.
const EYE_TILE := Vector2i(8, 0)
## Where the walks start (from the gate's foot, across its line) and how far they go; how far
## beside the middle the side walks go (the middle of the hole a shut gate used to leave: between
## its old 52-unit body and the post's 14-unit rect, 31 units wide).
const WALK_START := 64.0
const WALK_LENGTH := 128.0
const SIDE_WALK := 41.5
## The close-up around a gate's foot (units).
const VIEW := Rect2(-160.0, -128.0, 320.0, 224.0)
## The player's collision rect.
const BODY := Vector2(30.0, 26.0)


func _initialize() -> void:
	var out := DEFAULT_OUT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	for room_name: String in GATES:
		await _render_room(room_name, GATES[room_name], out)
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


func _render_room(room_name: String, gate_names: Array, out: String) -> void:
	var room := (load(ROOMS % room_name) as PackedScene).instantiate() as Node2D
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(VIEW.size * 2.0)
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.zoom = Vector2(2, 2)
	viewport.add_child(camera)
	viewport.add_child(room)
	if gate_names.has("north-south-gate"):
		_paint_north_south_gate(room)
	var ground := room.get_node("ground") as TileMapLayer
	var elevation := Elevation.mount(ground, true)
	for i in 3:
		await physics_frame
	for gate_name: String in gate_names:
		var gate := room.get_node_or_null(NodePath("Objects/" + gate_name)) as Node2D
		if gate == null:
			print("%s: no gate %s" % [room_name, gate_name])
			continue
		var level := elevation.level_at(gate.global_position) if elevation != null else 0
		var across := Vector2.RIGHT if gate_name == "north-south-gate" else Vector2.DOWN
		var along := Vector2(across.y, across.x)
		var slimes: Array[Node2D] = []
		await _shoot(viewport, camera, gate.global_position, out.path_join("%s-%s-shut-clean.png" % [room_name, gate_name]))
		# shut: three walks into the line, and one slime standing right behind the gate
		for offset: float in [0.0, -SIDE_WALK, SIDE_WALK]:
			var stop := await _walk(room, gate.global_position + along * offset + across * WALK_START, -across * WALK_LENGTH, level)
			print("%s %s shut, walk at %+.0f: stops at %s (%s)" % [room_name, gate_name, offset, stop,
					"through" if (stop - gate.global_position).dot(across) < -8.0 else "held"])
			slimes.append(_slime(room, stop))
		slimes.append(_slime(room, gate.global_position - across * 12.0))
		await _shoot(viewport, camera, gate.global_position, out.path_join("%s-%s-shut.png" % [room_name, gate_name]))
		for slime in slimes:
			slime.free()
		slimes.clear()
		# open: the gate's own opening, then the same walks
		var gate_script := gate.get_node("GateScript")
		gate_script.call(&"open")
		for i in 60:
			await physics_frame
		await _shoot(viewport, camera, gate.global_position, out.path_join("%s-%s-open-clean.png" % [room_name, gate_name]))
		for offset: float in [0.0, -SIDE_WALK, SIDE_WALK]:
			var stop := await _walk(room, gate.global_position + along * offset + across * WALK_START, -across * WALK_LENGTH, level)
			print("%s %s open, walk at %+.0f: stops at %s (%s)" % [room_name, gate_name, offset, stop,
					"through" if (stop - gate.global_position).dot(across) < -8.0 else "held"])
			slimes.append(_slime(room, stop))
		await _shoot(viewport, camera, gate.global_position, out.path_join("%s-%s-open.png" % [room_name, gate_name]))
		for slime in slimes:
			slime.free()
	viewport.queue_free()
	await process_frame


## Paints an eye gate into the Weigh House's north-south divider and lets the fence layer make its
## gate object, as painting it in the editor does (in memory only).
func _paint_north_south_gate(room: Node2D) -> void:
	var layer := room.get_node("fences") as TileMapLayer
	layer.set_cell(NORTH_SOUTH_CELL, 0, EYE_TILE)
	var arguments := [true] if layer.get_method_argument_count(&"sync_gates") > 0 else []
	layer.callv(&"sync_gates", arguments)
	var objects := room.get_node("Objects")
	var made := objects.get_node_or_null("divider-gate-%d-%d" % [NORTH_SOUTH_CELL.x, NORTH_SOUTH_CELL.y])
	if made != null:
		made.name = "north-south-gate"


## Moves a body with the player's collision rect (its feet at `from`) by `motion` and returns where
## its feet stop.
func _walk(room: Node2D, from: Vector2, motion: Vector2, level: int) -> Vector2:
	var body := CharacterBody2D.new()
	body.collision_layer = 0
	body.collision_mask = 1 | Elevation.level_bit(level)
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = BODY
	shape.shape = rectangle
	shape.position = Vector2(0.0, -BODY.y * 0.5)
	body.add_child(shape)
	body.position = from
	room.add_child(body)
	await physics_frame
	body.move_and_collide(motion)
	var stop := body.global_position
	body.free()
	return stop


## A test slime's picture standing with its feet at `feet`, sorted with the room's objects.
func _slime(room: Node2D, feet: Vector2) -> Node2D:
	var holder := Node2D.new()
	holder.position = feet
	var sprite := Sprite2D.new()
	sprite.texture = SLIME
	sprite.hframes = 8
	sprite.vframes = 8
	sprite.frame = 7
	sprite.centered = false
	sprite.offset = Vector2(-128, -128)
	sprite.scale = Vector2(0.28125, 0.28125)
	sprite.position = Vector2(0, -27.56)
	holder.add_child(sprite)
	var objects := room.get_node_or_null("Objects")
	(objects if objects != null else room).add_child(holder)
	return holder


func _shoot(viewport: SubViewport, camera: Camera2D, foot: Vector2, path: String) -> void:
	# (the camera moves on physics frames: physics interpolation)
	camera.position = foot + VIEW.position
	camera.reset_physics_interpolation()
	for i in 2:
		await physics_frame
	for i in 4:
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))

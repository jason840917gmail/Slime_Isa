extends SceneTree
## Renders the Fence Park (game/scenes/worlds/fence-park.tscn, scripts/maps/build-fence-park.py)
## with the game's own drawing, for checking the fences along hill rims (docs/godot/FENCES.md).
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_fence_park.gd -- --out=<dir>
## Writes <dir>/fence-park.png (the whole park at 1x) and close-ups at 2x, with test slimes placed
## where fences must hide them (behind a fence on a hilltop, in the strip behind a hill, beside a
## side fence, in a hole under its near rim) and where they must stand in front.

const Elevation := preload("res://game/world/elevation/elevation.gd")
const Services := preload("res://game/shared/services.gd")
const SLIME := preload("res://asset/characters/256x256-tile_8x8-slime-v2-page-1.webp")
const SCENE := "res://game/scenes/worlds/fence-park.tscn"
const DEFAULT_OUT := "user://fence-park"
const CELL := 64.0
## Close-ups: name -> rect in cells.
const CLOSE_UPS := {
	"square": Rect2(1, 0, 12, 11),
	"diamond": Rect2(14, 0, 12, 13),
	"octagon": Rect2(25, 0, 14, 13),
	"holes": Rect2(2, 12, 24, 11),
	"south-only": Rect2(26, 12, 13, 10),
	"half-diamond-and-block": Rect2(3, 22, 26, 12),
	"plot-snow": Rect2(0, 34, 10, 13),
	"plot-sand": Rect2(10, 34, 10, 13),
	"plot-forest": Rect2(20, 34, 10, 13),
	"plot-moss": Rect2(30, 34, 10, 13),
	"plot-autumn": Rect2(0, 48, 10, 14),
	"plot-cavern": Rect2(10, 48, 10, 14),
	"plot-crystal": Rect2(20, 48, 10, 14),
	"plot-cobble": Rect2(30, 48, 10, 14),
}
## Test slimes: [feet (world units), level].
const SLIMES: Array = [
	[Vector2(200, 556), 1],   # on the square hill, right behind its south fence
	[Vector2(420, 172), 1],   # on the square hill, just inside its north fence
	[Vector2(330, 152), 0],   # in the strip behind the square hill's north rim
	[Vector2(788, 330), 0],   # beside the square hill's east side, at the gap
	[Vector2(788, 470), 0],   # beside the square hill's east side, by its fence
	[Vector2(560, 668), 0],   # at the foot of the square hill's wall
	[Vector2(1184, 531), 2],  # on the diamond, inside its south-west face
	[Vector2(1312, 150), 0],  # behind the diamond's north tip
	[Vector2(1960, 214), 1],  # on the octagon ring, inside its north face
	[Vector2(1056, 3290), 0], # behind the cavern block's north wall, in the strip behind it
	[Vector2(1150, 3316), 1], # on the cavern block, inside its north wall
	[Vector2(1792, 246), 0],  # behind the octagon's north-west fence, in the strip behind the hill
	[Vector2(1700, 352), 0],  # behind the octagon's north-west fence, near its west corner
	[Vector2(420, 1300), -1], # in the square hole, under its near rim
	[Vector2(600, 1310), 0],  # south of the square hole, outside its near-rim fence
]
## Collision probes: [start feet, motion, level, what it shows]; the player's body rect.
const PROBES: Array = [
	[Vector2(200, 450), Vector2(0, 200), 1, "square top -> south fence"],
	[Vector2(420, 300), Vector2(0, -200), 1, "square top -> north fence"],
	[Vector2(600, 470), Vector2(300, 0), 1, "square top -> east fence"],
	[Vector2(600, 330), Vector2(300, 0), 1, "square top -> east gap (no fence: rim)"],
	[Vector2(1312, 416), Vector2(-300, 300), 2, "diamond top -> south-west fence"],
	[Vector2(500, 1400), Vector2(0, -300), 0, "south of the square hole -> near-rim fence"],
	[Vector2(352, 450), Vector2(0, 200), 1, "square top -> the south flight's landing (gap)"],
]


func _initialize() -> void:
	var out := DEFAULT_OUT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var world := (load(SCENE) as PackedScene).instantiate() as Node2D
	var size := Vector2i(int(world.get_node("world-definition").get("columns")), int(world.get_node("world-definition").get("rows")))
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(size) * int(CELL)
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	viewport.add_child(world)
	# As the game does: water, terrain edges, the elevation with its fences and collision.
	Services.world().register_world(world)
	var elevation := Services.world().elevation
	await physics_frame
	await physics_frame
	_probe(world, elevation)
	for slime: Array in SLIMES:
		var body := CharacterBody2D.new()
		body.collision_layer = 2
		body.position = slime[0]
		var sprite := Sprite2D.new()
		sprite.texture = SLIME
		sprite.hframes = 8
		sprite.vframes = 8
		sprite.frame = 7
		sprite.centered = false
		sprite.offset = Vector2(-128, -128)
		sprite.scale = Vector2(0.28125, 0.28125)
		sprite.position = Vector2(0, -27.56)
		body.add_child(sprite)
		world.add_child(body)
		elevation.track(body, int(slime[1]))
		print("slime at ", slime[0], " level ", elevation.level_of(body), " fits ", elevation.body_fits(slime[0], int(slime[1])))
	for i in 10:
		await physics_frame
		await process_frame
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join("fence-park.png")))
	camera.zoom = Vector2(2.0, 2.0)
	for name: String in CLOSE_UPS:
		var area: Rect2 = CLOSE_UPS[name]
		viewport.size = Vector2i(area.size * CELL * 2.0)
		camera.position = area.position * CELL
		for i in 4:
			await process_frame
		viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join(name + ".png")))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


## Moves a body with the player's collision rect into each probe's fence and prints where it stops,
## and asks the elevation for ledge drops and hops there.
func _probe(world: Node2D, elevation: Elevation) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(30, 26)
	for probe: Array in PROBES:
		var body := CharacterBody2D.new()
		body.collision_layer = 2
		body.collision_mask = Elevation.level_bit(int(probe[2]))
		body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = Vector2(0, -13)
		body.add_child(collision)
		body.position = probe[0]
		world.add_child(body)
		var motion: Vector2 = probe[1]
		var hit := body.move_and_collide(motion)
		var feet := body.position
		var direction := motion.normalized()
		var drop := elevation.drop_target(feet, int(probe[2]), direction)
		var hop := elevation.hop_target(feet, int(probe[2]), direction, 60.0)
		print("%s: stops at %s (%s), drop %s, hop %s" % [probe[3], feet, "hit" if hit != null else "free",
				drop.get("feet", "none"), hop["feet"]])
		body.queue_free()

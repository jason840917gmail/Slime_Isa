extends SceneTree
## Renders the Gulp's art with the game's own scenes on one meadow-green sheet, for checking sizes
## and placement side by side (roadmap 7.5, 7.7, 8.12, 8.13): the player's idle beside its suck,
## spit, full and ball clips, the Clod Stomper's five poses, Tom, his web (trapped and torn), a
## sample of the liftables (game/data/liftables.json) and the essences. Scripts are stripped; each scene draws one pose.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_gulp_art.gd -- --out=<dir>
## Writes <dir>/gulp-art.png at 2x.

const Mouth := preload("res://game/player/gulp/mouth.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")
const DEFAULT_OUT := "user://gulp-art"
const SCALE := 2.0
const COLUMN_PX := 96.0
const ROW_PX := 110.0
const GROUND := Color("#4f6b3a")
const PLAYER := "res://game/characters/player_slime.tscn"
## [scene, clip or "", seconds into the clip, frame override (-1 = none), held thing to draw inside
## (optional, as the mouth draws it: game/player/gulp/mouth.gd)] per row.
const ROWS: Array = [
	[[PLAYER, "idle-down", 0.0, -1], [PLAYER, "suck-down", 0.1, -1], [PLAYER, "suck-up", 0.1, -1], [PLAYER, "suck-side", 0.1, -1],
		[PLAYER, "spit-down", 0.15, -1], [PLAYER, "spit-up", 0.15, -1], [PLAYER, "spit-side", 0.15, -1]],
	[[PLAYER, "idle-side", 0.0, -1], [PLAYER, "full-down", 0.3, -1, {"kind": "rock", "essence": "", "variant": 0}],
		[PLAYER, "full-up", 0.3, -1, {"kind": "essence", "essence": "silk"}],
		[PLAYER, "full-side", 0.3, -1, {"kind": "pinecone", "essence": "", "variant": 0}],
		[PLAYER, "ball-side", 0.1, -1], [PLAYER, "ball-down", 0.1, -1], [PLAYER, "ball-up", 0.1, -1]],
	[["res://game/scenes/characters/clod-stomper.tscn", "", 0.0, 0], ["res://game/scenes/characters/clod-stomper.tscn", "", 0.0, 1],
		["res://game/scenes/characters/clod-stomper.tscn", "", 0.0, 2], ["res://game/scenes/characters/clod-stomper.tscn", "", 0.0, 3],
		["res://game/scenes/characters/clod-stomper.tscn", "", 0.0, 4], ["res://game/scenes/characters/tom.tscn", "", 0.0, -1],
		["res://game/scenes/objects/tom-web.tscn", "", 0.0, -1]],
	[["res://game/scenes/objects/liftable.tscn", "", 0.0, 0], ["res://game/scenes/objects/liftable.tscn", "", 0.0, 8],
		["res://game/scenes/objects/liftable.tscn", "", 0.0, 20], ["res://game/scenes/objects/liftable.tscn", "", 0.0, 29],
		["res://game/scenes/objects/liftable.tscn", "", 0.0, 40], ["res://game/scenes/objects/liftable.tscn", "", 0.0, 52],
		["res://game/scenes/objects/liftable-rock.tscn", "", 0.0, 64]],
	[["res://game/scenes/objects/essence-stone.tscn", "", 0.0, -1], ["res://game/scenes/objects/essence-silk.tscn", "", 0.0, -1],
		["res://game/scenes/objects/essence-swim.tscn", "", 0.0, -1], ["res://game/scenes/objects/liftable.tscn", "", 0.0, 13],
		["res://game/scenes/objects/liftable.tscn", "", 0.0, 45], ["res://game/scenes/objects/liftable.tscn", "", 0.0, 63],
		["res://game/scenes/objects/liftable-puffball.tscn", "", 0.0, 66]],
]
const SCRIPT_NODES: Array[String] = ["PlayerScript", "EnemyScript", "NpcScript", "LiftableScript", "EssenceScript",
	"TomWebScript", "StoryVariantScript", "HurtSfx", "DeathSfx"]


func _initialize() -> void:
	var out := DEFAULT_OUT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var columns := 0
	for row: Array in ROWS:
		columns = maxi(columns, row.size())
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(int(columns * COLUMN_PX * SCALE), int(ROWS.size() * ROW_PX * SCALE))
	root.add_child(viewport)
	var stage := Node2D.new()
	stage.scale = Vector2.ONE * SCALE
	viewport.add_child(stage)
	var ground := ColorRect.new()
	ground.color = GROUND
	ground.size = Vector2(columns * COLUMN_PX, ROWS.size() * ROW_PX)
	stage.add_child(ground)
	for r in ROWS.size():
		var row: Array = ROWS[r]
		for c in row.size():
			var spec: Array = row[c]
			var node := (load(spec[0]) as PackedScene).instantiate()
			for child_name: String in SCRIPT_NODES:
				var child := node.get_node_or_null(child_name)
				if child != null:
					node.remove_child(child)
					child.free()
			stage.add_child(node)
			# Feet on the row's baseline, centred in the column.
			(node as Node2D).position = Vector2((c + 0.5) * COLUMN_PX, (r + 1) * ROW_PX - 14.0)
			_pose(node, str(spec[1]), float(spec[2]), int(spec[3]))
			if spec.size() > 4:
				var inside := HeldLook.make(spec[4], Mouth.INSIDE_LOOK_PX)
				inside.position = Vector2(0.0, -Mouth.INSIDE_RISE)
				inside.modulate = Color(1.0, 1.0, 1.0, Mouth.INSIDE_ALPHA)
				node.add_child(inside)
	for i in 4:
		await process_frame
	var image := viewport.get_texture().get_image()
	var path := ProjectSettings.globalize_path(out.path_join("gulp-art.png"))
	image.save_png(path)
	print("render_gulp_art: wrote %s" % path)
	quit(0)


func _pose(node: Node, clip: String, at: float, frame: int) -> void:
	var player := node.get_node_or_null(^"Animation") as AnimationPlayer
	if player != null:
		player.stop()
		if not clip.is_empty() and player.has_animation(clip):
			player.play(clip)
			player.seek(at, true)
			player.pause()
	var visual := node.get_node_or_null(^"Visual") as Sprite2D
	if visual == null:
		visual = node.get_node_or_null(^"Trapped/Visual") as Sprite2D
		var freed := node.get_node_or_null(^"Freed") as Node2D
		if freed != null:
			freed.position.x = 48.0
	if visual != null and frame >= 0:
		visual.frame = frame

extends SceneTree
## Gives every placed tree scene (game/scenes/objects/tree-*.tscn) its big tree of the region sets
## (docs/godot/FORESTS.md): the `Visual` becomes that tree's atlas region standing on its foot at
## 2 px per unit (swaying in tree_sway.gdshader when the tree sways), a `Shadow` is added, and the
## old frame animations go (the frame sheets are gone; a resource tree's idle and on-hit clips are
## cleared). Collision is kept. Run once per change of TREES; then fix the worlds' Visual overrides
## (scale and offset were per instance against the old art).
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/retree_scenes.gd

const BigTrees := preload("res://game/world/forest/big_trees.gd")
const DIR := "res://game/scenes/objects/"
## Scene (without "tree-" and ".tscn") -> its big tree.
const TREES := {
	"forest-wall--green-tree-05": "oak-a-medium",
	"forest-wall--green-tree-06": "beech-a-medium",
	"forest-wall--green-tree-07": "oak-b-medium",
	"forest-wall--pine-02": "pine-a-medium",
	"forest-wall--pine-03": "pine-b-medium",
	"forest-wall--pine-04": "pine-a-tall",
	"forest-wall--pine-06": "pine-b-tall",
	"forest-wall--pine-07": "pine-b-medium",
	"world-solid": "pine-a-tall",
	"world-solid--green-tree-01": "oak-a-medium",
	"world-solid--green-tree-02": "beech-a-medium",
	"world-solid--green-tree-03": "oak-b-medium",
	"world-solid--green-tree-04": "beech-b-medium",
	"world-solid--green-tree-05": "birch-a-medium",
	"world-solid--green-tree-06": "oak-a-tall",
	"world-solid--green-tree-07": "beech-a-tall",
	"world-solid--grove-tree-01": "birch-a-medium",
	"world-solid--grove-tree-02": "birch-b-medium",
	"world-solid--grove-tree-03": "birch-a-tall",
	"world-solid--grove-tree-04": "birch-b-tall",
	"world-solid--grove-tree-05": "oak-a-medium",
	"world-solid--grove-tree-06": "oak-b-medium",
	"world-solid--grove-tree-07": "birch-a-medium",
	"world-solid--grove-tree-08": "oak-a-tall",
	"world-solid--grove-tree-09": "birch-b-medium",
	"world-solid--grove-tree-10": "oak-b-tall",
	"world-solid--grove-tree-11": "birch-b-tall",
	"world-solid--pine-01": "pine-a-medium",
	"world-solid--pine-02": "pine-b-medium",
	"world-solid--pine-03": "pine-a-tall",
	"world-solid--pine-04": "pine-b-tall",
	"world-solid--pine-05": "pine-a-medium",
	"world-solid--pine-06": "pine-b-medium",
	"world-solid--pine-07": "pine-a-tall",
	"world-solid--shadow-pine-02": "pine-b-tall",
	"world-solid--snow-pine": "fir-a-medium",
	"world-solid--frost-bare": "frost-a-medium",
	"world-solid--autumn-tree-01": "maple-a-medium",
	"world-solid--autumn-tree-02": "maple-b-medium",
	"world-solid--autumn-tree-03": "maple-a-tall",
	"world-solid--autumn-tree-04": "maple-b-tall",
	"world-solid--autumn-tree-05": "maple-a-medium",
	"world-solid--tree-autumn-01": "maple-b-medium",
	"world-solid--golden-tree-01": "ginkgo-a-medium",
	"world-solid--golden-tree-02": "ginkgo-b-medium",
	"world-solid--red-tree": "maple-b-tall",
	"world-solid--ancient-bare-01": "gnarled-a-medium",
	"world-solid--ancient-bare-02": "gnarled-b-medium",
	"world-solid--ancient-bare-03": "gnarled-a-tall",
	"world-solid--ancient-bare-04": "gnarled-b-tall",
	"world-solid--ancient-bare-05": "gnarled-a-medium",
	"world-solid--ancient-bare-06": "gnarled-b-medium",
	"world-solid--ancient-blossom": "cherry-a-tall",
	"world-solid--ancient-green": "oak-b-tall",
	"world-solid--ancient-dark": "beech-b-tall",
}


func _initialize() -> void:
	var done := 0
	for scene_name: String in TREES:
		var path := DIR + "tree-" + scene_name + ".tscn"
		if not FileAccess.file_exists(path):
			push_warning("retree_scenes: no %s" % path)
			continue
		var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		var visual := root.get_node(^"Visual") as Sprite2D
		if not BigTrees.configure(visual, TREES[scene_name]):
			root.free()
			continue
		for child in root.get_children():
			if child is AnimationPlayer or child.name == &"Shadow":
				root.remove_child(child)
				child.free()
		var resource := root.get_node_or_null(^"ResourceNodeScript")
		if resource != null:
			resource.set(&"idle_animation_id", "")
			resource.set(&"on_hit_animation_id", "")
			resource.set(&"animation", null)
		var shadow := BigTrees.shadow_for(visual)
		root.add_child(shadow)
		root.move_child(shadow, 0)
		shadow.owner = root
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, path)
		root.free()
		if err != OK:
			push_error("retree_scenes: %s: %s" % [path, error_string(err)])
			continue
		done += 1
	print("retree_scenes: %d of %d scenes" % [done, TREES.size()])
	quit(0)

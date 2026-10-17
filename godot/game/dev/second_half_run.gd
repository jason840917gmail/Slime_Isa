extends Node
## Dev only (game/dev/ stays out of the release export): F6 on a dungeon's second half with its Pearl's
## skin lent. `game/dev/weaver-hollow-second-half.tscn` runs `weaver-hollow-crown` (C1, C4 the
## Spinning Loft, the Matron) as F6 on that world does (main `direct_world_run`: the floor's
## `dungeon.devPowers`, the Spear, the Roll, the Heavy skin and the Goo Bomb), and lends `skins` for
## the session (SkinState.lend, worn), since the Silk skin is won mid-dungeon, from Pearl 2 in the
## Hoard (docs/godot/DUNGEONS.md "The Weaver Hollow (built)"). On the web or a desktop launch,
## `?map=weaver-hollow-crown&skins=silk` does the same (`-- --map=... --skins=silk`).
##
## Owner: dungeons (the Weaver Hollow).

const Services := preload("res://game/shared/services.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const MAIN_SCENE := "res://game/main.tscn"
const SELF_PATH := "res://game/dev/second_half_run.gd"

## The world the run starts in.
@export var map_id: String = "weaver-hollow-crown"
## The skins lent for the session once its world is built (the last one worn).
@export var skins: PackedStringArray = ["silk"]


func _ready() -> void:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map_id)
	main.set(&"direct_world_run", true)
	var world := Services.world()
	if world != null:
		# On the script, not this node: the scene change frees this node before the world is built.
		world.world_registered.connect(Callable(get_script(), &"lend").bind(skins), CONNECT_ONE_SHOT)
	get_tree().change_scene_to_node.call_deferred(main)


## The world is built: on the next frame (after main has lent the floor's dev powers, whose last skin
## it wears) lends `ids`.
static func lend(_payload: Dictionary, ids: PackedStringArray) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.process_frame.connect(Callable(load(SELF_PATH), &"lend_now").bind(ids), CONNECT_ONE_SHOT)


## Lends `ids` (SkinState.lend), the last one worn.
static func lend_now(ids: PackedStringArray) -> void:
	for id: String in ids:
		var skin := StringName(id)
		SkinState.lend(skin)
		SkinState.set_look(skin)

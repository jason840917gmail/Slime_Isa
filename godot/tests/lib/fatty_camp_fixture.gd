extends RefCounted
## Fatty's old overworld camp, put back for the boss-camp tests (test_boss.gd, test_audio.gd,
## test_chest_window.gd). Fatty left level-1-d4's clearing for his Lair on 2026-10-17 (his camp is
## `encounter.fatty-lair-boss` in world.fatty-lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)";
## the Lair's gate, first by the clearing, moved to level-1-d5's hill the same day),
## but the boss camp's rules these tests measure (the activation and arena circles, the leash, the
## 180 s respawn, the guarded chest, the boss music) are the camp's, and the clearing they were
## measured in is still there: `ensure` instances `encounter.level-1-fatty-camp` at its old spot,
## (480, 1472) in D4, when the test's world has none, and binds the HUD's boss bar to it at once, as
## a camp loaded with its world is bound before any fight (the bar binds new camps only on its next
## frame). A test that steps the music director by hand calls `ensure` before its first `advance`.

const Services := preload("res://game/shared/services.gd")
const BossCampScript := preload("res://game/scripts/boss_camp.gd")

const CAMP_SCENE := "res://game/scenes/encounters/level-1-fatty-camp.tscn"
const CAMP_ID := "level-1-fatty-one-eye-camp"
const MAP_ID := "level-1-d4"
const AT := Vector2(480.0, 1472.0)


## The camp (its BossCampScript), placed now when the world is D4 and has none; null elsewhere.
static func ensure(tree: SceneTree) -> BossCampScript:
	for node: Node in tree.get_nodes_in_group(BossCampScript.GROUP):
		if node is BossCampScript and (node as BossCampScript).camp_id == CAMP_ID:
			return node as BossCampScript
	var world := Services.world()
	if world == null or world.world_root == null or world.map_id() != MAP_ID:
		return null
	var packed := load(CAMP_SCENE) as PackedScene
	if packed == null:
		return null
	var camp := packed.instantiate() as Node2D
	camp.name = CAMP_ID
	camp.position = AT
	camp.set_meta(&"instance_id", CAMP_ID)
	camp.set_meta(&"persistence_key", CAMP_ID)
	var script := camp.get_node_or_null(^"BossCampScript")
	if script != null:
		script.set(&"map_id", MAP_ID)
	var chest := camp.get_node_or_null(^"GuardedChest/ChestScript")
	if chest != null:
		chest.set(&"map_id", MAP_ID)
	world.world_root.add_child(camp)
	var hud := tree.root.find_child("Hud", true, false)
	var bar: Node = hud.call(&"get_boss_bar") if hud != null and hud.has_method(&"get_boss_bar") else null
	if bar != null and script != null:
		bar.call(&"bind_camp", script)
	return script as BossCampScript

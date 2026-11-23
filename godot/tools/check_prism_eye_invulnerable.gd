extends SceneTree
## Checks the Prism Eye's invulnerability (2026-11-21; docs/godot/BESTIARY.md "Prism Eye") in the
## playground, headless: a Prism Eye and a Watcher Eye each looking down, the slime standing behind
## them (above), and the questions their hit gate answers for a thrown hit from there, from in front
## and the Bow's arrow into the eye. Prints one line per check and quits with 1 when one fails.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/check_prism_eye_invulnerable.gd

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const MAIN_SCENE := "res://game/main.tscn"
const GAP_PX := 90.0

var _failed := 0


func _initialize() -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", "playground")
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 60:
		await process_frame
	var world := Services.world()
	var stage: Vector2 = world.player_spawn_point() + Vector2(300.0, -40.0)
	for type_id: String in ["prism-eye", "watcher-eye"]:
		var eye := _spawn(type_id, stage)
		for i in 4:
			await physics_frame
		eye.set(&"_gaze", PI * 0.5)
		var invulnerable := type_id == "prism-eye"
		_place_slime(stage + Vector2(0.0, -GAP_PX))
		_check("%s: a throw from behind %s" % [type_id, "clinks" if invulnerable else "lands"],
			_accepted(eye) != invulnerable)
		_place_slime(stage + Vector2(0.0, GAP_PX))
		_check("%s: a throw from in front clinks" % type_id, not _accepted(eye))
		eye.set(&"_gaze", PI * 0.5)
		var broke := bool(eye.call(&"on_arrow_hit", {"direction": Vector2.UP}))
		_check("%s: an arrow into its eye %s" % [type_id, "does nothing" if invulnerable else "breaks it"],
			broke != invulnerable)
		stage += Vector2(260.0, 0.0)
	print("check_prism_eye_invulnerable: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _spawn(type_id: String, centre: Vector2) -> Node:
	var world := Services.world()
	var root_node := world.instantiate_scene("character." + type_id) as Node2D
	var enemy: Node = root_node.get_node(^"EnemyScript")
	var parent := world.entities_root() as Node2D
	root_node.position = parent.get_global_transform().affine_inverse() * FeetAnchor.global_for_phaser_position(root_node, centre)
	parent.add_child(root_node)
	var no_zones: Array[Dictionary] = []
	enemy.call(&"configure_navigation", {}, no_zones)
	enemy.call(&"configure_arena", {"shape": "circle", "x": centre.x, "y": centre.y, "radius": 1.0})
	return enemy


func _place_slime(centre: Vector2) -> void:
	var world := Services.world()
	world.player.call(&"teleport", centre)
	world.player_body.velocity = Vector2.ZERO


## The eye's hit gate for a thrown pot's request from the slime where it stands.
func _accepted(eye: Node) -> bool:
	var world := Services.world()
	var request := {"source": world.player, "weapon_tags": ["thrown", "clay-pot"], "base_damage": 40.0,
		"impact": {"position": eye.call(&"get_centre")}}
	var answer: Dictionary = eye.call(&"can_receive_damage", {"request": request})
	return bool(answer.get("accepted", false))


func _check(what: String, ok: bool) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1

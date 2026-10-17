extends SceneTree
## Renders the Orb-Weaver Matron's cocoon fight (docs/godot/specs/matron.md section 8) in the running
## game, for tuning its look without playing to the top of the Weaver Hollow: it starts the Crown
## (`weaver-hollow-crown`), mounts `encounter.weaver-hollow-matron` at the room's floor centre when
## the world has none, and stages each moment: the cocoon in round 1, a Goo Bomb blast tearing it,
## her on the floor, the respin, rounds 2 (the ring of webs) and 3 (the egg sacs), her retreat and
## the rewards, then takes them (Pearl 2, the full heart) and cuts and takes her thread. Her spit and
## volleys are held off, so the slime is not knocked about between shots.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_matron.gd -- --out=<dir> [--map=<world id>]
## Writes <dir>/matron-<nn>-<moment>.png.

const Services := preload("res://game/shared/services.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")
const BossCampScript := preload("res://game/scripts/boss_camp.gd")
const MatronScript := preload("res://game/scripts/matron.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://matron-render"
const CAMP_ID := "weaver-hollow-matron"
const CAMP_AT := Vector2(512.0, 544.0)
## Where the slime watches from (its centre), south of her shadow.
const WATCH_AT := Vector2(512.0, 700.0)

var _out: String = DEFAULT_OUT
var _shot: int = 0


func _initialize() -> void:
	var map := "weaver-hollow-crown"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(Vector2i(1024, 1024))
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 60:
		await process_frame
	var camp := _camp()
	if camp == null:
		var encounter := Services.world().instantiate_scene("encounter.weaver-hollow-matron") as Node2D
		Services.world().entities_root().add_child(encounter)
		encounter.global_position = CAMP_AT
		await physics_frame
		camp = _camp()
	_place_slime(WATCH_AT)
	var waited := 0
	while camp.get_live_boss() == null and waited < 300:
		await physics_frame
		waited += 1
	var matron := camp.get_live_boss() as MatronScript
	if matron == null:
		push_error("render_matron: no Matron spawned")
		quit(1)
		return
	_hold_fire(matron)
	await _wait_ms(1300.0)
	await _save("round-1-cocoon")
	var feet := matron.body.global_position
	GooBlast.detonate(feet + Vector2(0.0, 30.0), false)
	await _wait_ms(120.0)
	await _save("blast")
	await _wait_ms(700.0)
	await _save("torn-dazed")
	await _wait_ms(matron.open_ms - 820.0 + matron.respin_ms * 0.5)
	await _save("respin")
	# Round 2: her first hundred is gone.
	matron.set(&"_hp", 200.0)
	await _wait_ms(matron.respin_ms)
	await _wait_ms(600.0)
	await _save("round-2-ring")
	matron.receive_blast({})
	matron.set(&"_hp", 100.0)
	matron.call(&"_begin_respin", Services.now_ms())
	await _wait_ms(matron.respin_ms + 200.0)
	_hold_fire(matron)
	await _wait_ms(1500.0)
	await _save("round-3-sacs")
	matron.receive_blast({})
	await _wait_ms(400.0)
	matron.take_reaction_damage(1000.0)
	await _wait_ms(700.0)
	await _save("beaten-retreat")
	await _wait_ms(2200.0)
	await _save("rewards")
	# The rewards taken: Pearl 2 (the Silk skin), the full heart, then her thread cut and taken.
	var encounter := camp.get_parent() as Node2D
	var pearl := encounter.get_node_or_null(^"Pearl") as Node2D
	var heart := encounter.get_node_or_null(^"FullHeart") as Node2D
	var thread := encounter.get_node_or_null(^"MatronThread") as Node2D
	var player: Node = Services.world().player
	print("render_matron: max hp %d, max energy %d, crosses webs %s" % [player.call(&"get_max_hp"), player.call(&"get_max_energy"), player.call(&"crosses_webs")])
	for reward: Node2D in [pearl, heart]:
		if reward != null:
			_place_slime(reward.global_position)
			await _wait_ms(200.0)
	print("render_matron: max hp %d, max energy %d, crosses webs %s" % [player.call(&"get_max_hp"), player.call(&"get_max_energy"), player.call(&"crosses_webs")])
	if thread != null:
		_place_slime(thread.global_position + Vector2(0.0, 40.0))
		await _wait_ms(300.0)
		await _save("thread-caught")
		_cut(thread, player)
		await _wait_ms(160.0)
		await _save("thread-falling")
		await _wait_ms(400.0)
		_place_slime(thread.global_position)
		await _wait_ms(200.0)
		print("render_matron: thread %s, in the bag %d" % [thread.call(&"get_state"), Services.run().item_count("matron-thread")])
	quit(0)


## A Spear hit on the thread's strand, as the game routes it.
func _cut(thread: Node2D, player: Node) -> void:
	var router := Services.router()
	var area := thread.get_node_or_null(^"DamageArea") as Area2D
	var own := player.call(&"get_damage_area") as Area2D
	if router == null or area == null or own == null:
		print("render_matron: the thread has no hurtbox")
		return
	var areas: Array[Area2D] = [own]
	var activation := router.begin_activation(player, areas)
	var result := router.route({"activation_id": activation, "source": player, "attack_area": own,
		"target_area": area, "weapon_id": "render", "weapon_tags": ["weapon", "spear"],
		"damage_types": ["physical"], "base_damage": 24.0, "effects": [],
		"impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	print("render_matron: the cut ", result)


func _camp() -> BossCampScript:
	for node: Node in root.get_tree().get_nodes_in_group(BossCampScript.GROUP):
		var camp := node as BossCampScript
		if camp != null and camp.camp_id == CAMP_ID and camp.is_inside_tree():
			return camp
	return null


## Her spit and her volleys wait, so the slime stays put between shots.
func _hold_fire(matron: MatronScript) -> void:
	(matron.get(&"_lifecycle") as Object).set(&"ready_at", INF)
	matron.set(&"_next_volley_at", INF)
	matron.cancel_attack()


func _place_slime(centre: Vector2) -> void:
	var body := Services.world().player_body
	body.global_position = centre + Vector2(0.0, 27.56)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	if Services.world().elevation != null:
		Services.world().elevation.call(&"track", body)


func _wait_ms(ms: float) -> void:
	var started := Services.now_ms()
	while Services.now_ms() - started < ms:
		await physics_frame


func _save(moment: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var file := "matron-%02d-%s.png" % [_shot, moment]
	_shot += 1
	var path := ProjectSettings.globalize_path(_out.path_join(file))
	root.get_texture().get_image().save_png(path)
	print("render_matron: ", path)

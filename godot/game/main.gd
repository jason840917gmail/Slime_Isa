extends Node2D
## Trial bootstrap on res://game/main.tscn (Phaser `MapLoadScene` + `WorldScene.create` +
## `UniversalSceneWorldController` mounting). World spec 1.2.
##
## main.tscn children (static): World (Node2D, the world is instanced under it), WorldCamera
## (world_camera.gd), Hud (hud.gd, CanvasLayer 10), FpsReadout (fps_readout.gd, CanvasLayer 100).
## Runtime children: ArrivalFade (CanvasLayer 5 + ColorRect), EnemyPopulation.
##
## `_ready()` order (world spec 1.2):
##  1. apply_viewport_scale() and connect `get_tree().root.size_changed` to it
##  2. map id: resolve_map_id() ("level-1")
##  3. load_world(): instance `world.<map id>` (scene index) under $World;
##     `Services.world().register_world(world_root)`; abort with push_error on failure
##  4. WorldBounds.build(world_root, world_rect)
##  5. spawn_player(): `spawn_at_phaser_position("character.player-slime",
##     Services.world().player_spawn_point(), world_root)`; register_player(PlayerScript node)
##  6. equip_trial_weapon(): PlayerCombat child "PlayerCombat" of the player root, setup, set_combat,
##     equip(TRIAL_WEAPON_ID)
##  7. start_enemy_population(): EnemyPopulation with the enemy-spawn areas, safe zones,
##     entities_root, allowed_types = TRIAL_ENEMY_TYPES, seed_initial()
##  7b. warm_runtime_scenes(): cache the PackedScenes spawned mid-game (camp enemy types, the
##     weapon's hit effect) and mount the global audio cue scene, so none of them is loaded on
##     a gameplay frame (Phaser loads everything in MapLoadScene before the world starts)
##  8. configure_npcs(): for every node in group "npc": configure_wander(npc_wander_area(
##     npc.get_instance_id_key()).get("perimeter", {}))
##  9. setup_camera(): $WorldCamera.setup(world_rect, camera_mode); start_follow(player root);
##     register_camera; connect player.respawned -> _on_player_respawned
## 10. start_arrival_fade()
## 11. setup_ui(): $Hud.bind_player(player), $FpsReadout.bind_camera($WorldCamera)
##
## Owner: world builder.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const WorldBounds := preload("res://game/world/world_bounds.gd")
const WorldCamera := preload("res://game/world/world_camera.gd")
const GameHud := preload("res://game/ui/hud.gd")
const FpsReadout := preload("res://game/ui/fps_readout.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const NpcScript := preload("res://game/scripts/npc.gd")
const PlayerCombat := preload("res://game/combat/player_combat.gd")
const EnemyPopulation := preload("res://game/enemy/enemy_population.gd")

## `STARTING_AREA_ID` (world/Area.ts:22).
const TRIAL_MAP_ID := "level-1"
## Trial settings (player spec 14 Q3, combat spec 3): sword equipped from the start; only the
## worm swordsman spawns.
const TRIAL_WEAPON_ID := "basic-sword"
const TRIAL_ENEMY_TYPES: PackedStringArray = ["worm-swordsman"]
const PLAYER_SCENE_ID := "character.player-slime"
## `AREA_ARRIVE_FADE_MS` (WorldScene.ts:128) and the fade colour #0b1020.
const ARRIVAL_FADE_MS := 400.0
const FADE_COLOR := Color("#0b1020")
## Layer of the arrival fade: above the world, below the HUD (10).
const FADE_LAYER := 5
const WORLD_SCENE_PREFIX := "world."
const PLAYER_SCRIPT_NODE := "PlayerScript"
const NPC_GROUP := &"npc"

## World to load when no launch option names one ("" = level-1). res://game/dev/playground.tscn
## inherits this scene with "playground" so the testbed runs with F6 (Run Current Scene).
@export var map_id: String = ""

@onready var world_container: Node2D = $World
@onready var world_camera: WorldCamera = $WorldCamera
@onready var hud: GameHud = $Hud
@onready var fps_readout: FpsReadout = $FpsReadout

var world_root: Node2D
var player: PlayerScript
var player_root: CharacterBody2D
var player_combat: PlayerCombat
var enemy_population: EnemyPopulation


## Runs the bootstrap steps above.
func _ready() -> void:
	apply_viewport_scale()
	get_tree().root.size_changed.connect(apply_viewport_scale)
	var world_service := Services.world()
	if world_service == null:
		push_error("Main: the WorldService autoload is missing")
		return
	var map_id := resolve_map_id()
	world_root = load_world(map_id)
	if world_root == null:
		push_error("Main: could not load world '%s'; the trial cannot start" % map_id)
		fps_readout.bind_camera(world_camera)
		return
	WorldBounds.build(world_root, world_service.world_rect())
	player = spawn_player()
	if player == null:
		push_error("Main: could not spawn the player")
	else:
		equip_trial_weapon()
	start_enemy_population()
	warm_runtime_scenes()
	configure_npcs()
	setup_camera()
	start_arrival_fade()
	setup_ui()


## World spec 1.2 "Viewport scale": 1 game px = 1 CSS px. Sets
## `get_tree().root.content_scale_size = Vector2i(root.size / dpr)` with
## `dpr = DisplayServer.screen_get_scale()` on web and 1.0 elsewhere (stretch mode stays
## canvas_items + expand in project.godot).
func apply_viewport_scale() -> void:
	var root := get_tree().root
	var dpr := 1.0
	if OS.has_feature("web"):
		dpr = DisplayServer.screen_get_scale()
		if not is_finite(dpr) or dpr <= 0.0:
			dpr = 1.0
	var window_size := Vector2(root.size)
	var base := Vector2i(maxi(1, roundi(window_size.x / dpr)), maxi(1, roundi(window_size.y / dpr)))
	if root.content_scale_size != base:
		root.content_scale_size = base


## "level-1"; overrides, strongest first: web `?map=` (JavaScriptBridge) or desktop user arg
## `--map=<id>` (after `--` on the command line), then the `map_id` export (set by
## res://game/dev/playground.tscn, which runs the playground with F6). An unknown id falls back to
## "level-1" with a warning.
func resolve_map_id() -> String:
	var requested := launch_option("map")
	if requested.is_empty():
		requested = map_id.strip_edges()
	if requested.is_empty() or requested == TRIAL_MAP_ID:
		return TRIAL_MAP_ID
	var world_service := Services.world()
	if world_service != null and not world_service.scene_path(WORLD_SCENE_PREFIX + requested).is_empty():
		return requested
	push_warning("Main: unknown map '%s'; loading '%s'" % [requested, TRIAL_MAP_ID])
	return TRIAL_MAP_ID


## A launch option: the web page's `?<option>=` query value, or the desktop user
## argument `--<option>=<value>` (after `--`). Empty when absent.
func launch_option(option: String) -> String:
	if OS.has_feature("web"):
		var from_query: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % option, true)
		return (from_query as String).strip_edges() if from_query is String else ""
	var prefix := "--%s=" % option
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).strip_edges()
	return ""


## Test aid for the trial: `?spawn=<x>,<y>` / `--spawn=<x>,<y>` starts the player at
## that old-Phaser (centre) world position instead of the world's spawn point.
## Returns `fallback` when the option is absent or malformed.
func spawn_override(fallback: Vector2) -> Vector2:
	var option := launch_option("spawn")
	var parts := option.split(",")
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		if not option.is_empty():
			push_warning("Main: ignoring malformed spawn option '%s'" % option)
		return fallback
	var position := Vector2(parts[0].to_float(), parts[1].to_float())
	print("Main: spawn option places the player at %s" % position)
	return position


## Instances `world.<map_id>` under $World and registers it. Null on failure.
func load_world(map_id: String) -> Node2D:
	var world_service := Services.world()
	var instance := world_service.instantiate_scene(WORLD_SCENE_PREFIX + map_id)
	if instance == null:
		return null
	var root := instance as Node2D
	if root == null:
		push_error("Main: world scene '%s' root is not a Node2D" % map_id)
		instance.free()
		return null
	world_container.add_child(root)
	if not world_service.register_world(root):
		root.queue_free()
		return null
	return root


## Spawns and registers the player (world spec 2.2, feet = P + depth_anchor). Null on failure.
func spawn_player() -> PlayerScript:
	var world_service := Services.world()
	var spawn_point := spawn_override(world_service.player_spawn_point())
	var root := world_service.spawn_at_phaser_position(PLAYER_SCENE_ID, spawn_point, world_root)
	if root == null:
		return null
	player_root = root as CharacterBody2D
	var script_node := _find_player_script(root)
	if script_node == null:
		push_error("Main: '%s' has no PlayerScript node" % PLAYER_SCENE_ID)
		return null
	world_service.register_player(script_node)
	return script_node


func _find_player_script(root: Node) -> PlayerScript:
	var direct := root.get_node_or_null(NodePath(PLAYER_SCRIPT_NODE)) as PlayerScript
	if direct != null:
		return direct
	for child: Node in root.get_children():
		if child.get_script() == PlayerScript:
			return child as PlayerScript
	return null


## Creates PlayerCombat under the player root and equips TRIAL_WEAPON_ID.
func equip_trial_weapon() -> void:
	if player == null or player_root == null:
		return
	player_combat = PlayerCombat.new()
	player_combat.name = "PlayerCombat"
	player_root.add_child(player_combat)
	player_combat.setup(player)
	player.set_combat(player_combat)
	if not player_combat.equip(TRIAL_WEAPON_ID):
		push_warning("Main: could not equip '%s'" % TRIAL_WEAPON_ID)


## Creates and seeds the EnemyPopulation (enemy spec 3).
func start_enemy_population() -> void:
	var world_service := Services.world()
	enemy_population = EnemyPopulation.new()
	enemy_population.name = "EnemyPopulation"
	add_child(enemy_population)
	enemy_population.setup(world_service.areas(world_service.AREA_ENEMY_SPAWN), world_service.safe_zones(), world_service.entities_root())
	enemy_population.allowed_types = TRIAL_ENEMY_TYPES
	enemy_population.seed_initial()


## Preloads what the trial spawns during play (Phaser MapLoadScene.ts:56-67 loads all world
## media before WorldScene starts): `character.<type>` for every allowed enemy type, the
## equipped weapon's `effect.<on_hit_effect_id>`, and GameFeel's global audio cue scene
## (otherwise mounted on the first dodge / crit / respawn cue).
func warm_runtime_scenes() -> void:
	var world_service := Services.world()
	if world_service == null:
		return
	if enemy_population != null:
		for type_id: String in enemy_population.allowed_types:
			world_service.packed_scene("character." + type_id)
	if player_combat != null:
		var weapon := player_combat.get_weapon()
		if weapon != null and not weapon.on_hit_effect_id.is_empty():
			world_service.packed_scene("effect." + weapon.on_hit_effect_id)
	var feel := Services.feel()
	if feel != null:
		feel.warm_up()


## Gives every NPC its wander perimeter (world spec 5.3).
func configure_npcs() -> void:
	var world_service := Services.world()
	for node: Node in get_tree().get_nodes_in_group(NPC_GROUP):
		var npc := node as NpcScript
		if npc == null:
			continue
		var record := world_service.npc_wander_area(npc.get_instance_id_key())
		var perimeter: Dictionary = record.get("perimeter", {})
		npc.configure_wander(perimeter)


## Camera setup and follow (world spec 4).
func setup_camera() -> void:
	var world_service := Services.world()
	world_camera.setup(world_service.world_rect(), world_service.camera_mode())
	if player_root != null:
		world_camera.start_follow(player_root, true)
	world_service.register_camera(world_camera)
	if player != null and not player.respawned.is_connected(_on_player_respawned):
		player.respawned.connect(_on_player_respawned)


## Full-screen #0b1020 ColorRect on a CanvasLayer (layer 5, mouse_filter IGNORE), alpha 1 -> 0
## linearly over ARRIVAL_FADE_MS, freed at the end (world spec 4.7). Runs on real time (Phaser
## camera effects are not frozen by hit-stop).
func start_arrival_fade() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ArrivalFade"
	layer.layer = FADE_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.name = "Fade"
	rect.color = FADE_COLOR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	add_child(layer)
	var tween := layer.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(rect, "color:a", 0.0, ARRIVAL_FADE_MS / 1000.0).from(1.0)
	tween.tween_callback(layer.queue_free)


## Binds the HUD and the FPS readout.
func setup_ui() -> void:
	if player != null:
		hud.bind_player(player)
	fps_readout.bind_camera(world_camera)


## Respawn camera (WorldScene.respawnPlayer, WorldScene.ts:1975-1979):
## `world_camera.pan_to(Vector2(payload.x, payload.y), PlayerScript.RESPAWN_PAN_MS)`, then
## `world_camera.reset_zoom()` (zoom back to 1 in follow mode; re-holds a fixed camera, where
## pan_to is a no-op). Following resumes when the pan ends.
func _on_player_respawned(payload: Dictionary) -> void:
	if not payload.has("x") or not payload.has("y"):
		return
	world_camera.pan_to(Vector2(float(payload["x"]), float(payload["y"])), PlayerScript.RESPAWN_PAN_MS)
	world_camera.reset_zoom()

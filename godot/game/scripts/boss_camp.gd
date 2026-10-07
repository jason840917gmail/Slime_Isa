extends Node
class_name BossCampScript
## Scene script `game.boss-camp` (Phaser `features/scripts/BossCampScript.ts` plus the world side
## of `UniversalSceneWorldController`: `evaluateCamps`, `spawnBoss`, `removeBoss`,
## `finishDefeatedBosses`, `resetActiveFights`). Implements docs/godot/specs/boss.md section 4.
##
## Node: `BossCampScript`, a child of the encounter root (`Level1FattyCamp` at (2528, 1472) in
## level-1). Every physics step it tests the player centre against its activation area and spawns
## its boss (`boss_scene`) at the encounter origin + `spawn` when eligible; the boss goes under
## `WorldService.entities_root()` (the y-sorted world root, Phaser's top level) and gets the arena
## perimeter (`EnemyScript.configure_arena`). The camp watches its boss's `defeated` (defeat
## bookkeeping, deferred to the end of the step like Phaser's after-step pass) and the player's
## `defeated` (the fight resets, synchronously like `WorldScene.onPlayerDeath`).
##
## Progress lives in RunState (`Services.run()`, Phaser WorldProgress): the respawn timer in
## `map_record(map_id)["boss_camps"][camp_id] = {"respawn_ready_at_epoch_ms": wall-clock ms}`
## (`bossCampRespawnReadyAt`) and the boss id in `world["defeated_boss_ids"]` (`defeatBoss`), so
## both survive world travel; writing them to disk is the save phase. Everything the camp mounts
## (the boss, its telegraph) lives under the world root and goes with it on a world teardown.
## Camps join the group `boss_camp`: the boss health bar
## (res://game/ui/boss_health_bar.gd) binds to them, and a later quest system listens to
## `boss_defeated` there (Phaser `gameEvents 'boss.defeated'`).
##
## Owner: boss port.

const Services := preload("res://game/shared/services.gd")
const BossArena := preload("res://game/bosses/boss_arena.gd")
const AreaShapes := preload("res://game/bosses/area_shapes.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")

const GROUP := &"boss_camp"
## UniversalSceneWorldController.ts:2025-2033: defeat burst and text above the boss position.
const DEFEAT_BURST := &"boss-burst"
const DEFEAT_BURST_RISE_PX := 30.0
const DEFEAT_TEXT_RISE_PX := 84.0
const DEFEAT_TEXT_COLOR := &"yellow"
## `markBossDefeated` (UniversalSceneWorldController.ts:596-600) and AudioEventBridge.ts:101.
const DEFEAT_FEEL := &"boss-defeated"
const VICTORY_CUE := &"Victory"
## No respawn timer.
const NO_RESPAWN := -1.0

## JSON `mapId` ("level-1").
@export var map_id: String = ""
## JSON `campId` ("level-1-fatty-one-eye-camp").
@export var camp_id: String = ""
## JSON `bossId` ("fatty-one-eye").
@export var boss_id: String = ""
## JSON `bossScene`: the boss scene id ("character.fatty-one-eye").
@export var boss_scene: String = ""
## JSON `activationArea`: entering its shapes spawns the boss.
@export var activation_area: Area2D
## JSON `arenaArea`: the boss does not pursue the player beyond its first shape.
@export var arena_area: Area2D
## JSON `activeBosses`: required container (Phaser throws without it); the boss itself is mounted
## at the world's top level, as in Phaser.
@export var active_bosses: Node2D
## JSON `guardedChest` (not read at run time; chests are OUT).
@export var guarded_chest: Node
## JSON `guardedChestInstanceId` ("level-1-fatty-guarded-chest").
@export var guarded_chest_instance_id: String = ""
## JSON `respawnMs` (180000): wall-clock delay before a defeated boss may return.
@export var respawn_ms: float = 0.0
## JSON `spawn`: boss spawn offset from the encounter origin ((0, 0)).
@export var spawn: Vector2 = Vector2.ZERO

## -> RoarSfx.play_cue. Payload {"sceneId", "campId", "bossId", "parentRuntimeId", "spawn": {"x", "y"}}.
signal boss_spawn_requested(payload: Dictionary)
## The quest hook (Phaser `gameEvents 'boss.defeated' {bossId}`). Payload {"campId", "bossId"}.
signal boss_defeated(payload: Dictionary)
## Payload {"instanceId": String, "guarded": bool} (the guarded chest; chests OUT).
signal guard_changed(payload: Dictionary)
## Phaser `gameEvents 'boss.engaged'` (the bar shows). Payload {"campId", "bossId"}.
signal boss_engaged(payload: Dictionary)
## Phaser `gameEvents 'boss.disengaged'` (the bar hides). Payload {"campId", "defeated": bool}.
signal boss_disengaged(payload: Dictionary)

var _live_boss: bool = false
var _observed_outside_after_defeat: bool = true
var _suppress_spawn_until_outside: bool = false
## Fallback progress when no RunState autoload exists (a scene run outside the game).
var _local_respawn_ready_at: float = NO_RESPAWN
var _local_defeated: bool = false
## The live boss's root and script (null when none).
var _boss_root: Node2D
var _boss: EnemyScript
## Instance id of the player whose `defeated` the camp listens to (0 = none).
var _player_bound_id: int = 0


## Joins GROUP, applies `observedOutsideAfterDefeat = no respawn timer` (BossCampScript.ts:64-75),
## warms the boss scene and listens for the player's defeat.
func _ready() -> void:
	add_to_group(GROUP)
	_observed_outside_after_defeat = get_respawn_ready_at() < 0.0
	var world := Services.world()
	if world == null:
		return
	if not boss_scene.is_empty() and not world.scene_path(boss_scene).is_empty():
		world.packed_scene(boss_scene)
	if not world.player_registered.is_connected(_on_player_registered):
		world.player_registered.connect(_on_player_registered)
	_bind_player(world.player)


## Removes the boss and hides the bar (BossCampScript.ts:70-74).
func _exit_tree() -> void:
	var was_live := _live_boss
	_remove_boss()
	_live_boss = false
	if was_live:
		boss_disengaged.emit({"campId": camp_id, "defeated": false})


## Phaser `evaluateCamps` (UniversalSceneWorldController.ts:1989-1996), before the boss and the
## player step (tree order): the player centre (alive or not) against the activation shapes.
func _physics_process(_delta: float) -> void:
	var world := Services.world()
	if world == null:
		return
	var target := world.primary_target()
	if target.is_empty():
		return
	evaluate_activation(contains_activation_point(target["centre"]), epoch_now_ms())


# --- Phaser BossCampScript API ----------------------------------------------------------------

## True while the camp's boss lives.
func has_live_boss() -> bool:
	return _live_boss


## The live boss's script, or null.
func get_live_boss() -> EnemyScript:
	return _boss if _live_boss and is_instance_valid(_boss) else null


## Wall-clock epoch ms of the next allowed spawn (RunState `boss_camps`), NO_RESPAWN (-1) when
## none (WorldProgress.bossCampRespawnReadyAt).
func get_respawn_ready_at() -> float:
	var run := Services.run()
	if run == null:
		return _local_respawn_ready_at
	var maps: Dictionary = run.world.get("maps", {})
	var record: Dictionary = maps.get(map_id, {})
	var camps: Dictionary = record.get("boss_camps", {})
	var entry: Dictionary = camps.get(camp_id, {})
	var ready_at: Variant = entry.get("respawn_ready_at_epoch_ms", NO_RESPAWN)
	return float(ready_at) if (ready_at is float or ready_at is int) else NO_RESPAWN


## True once this camp's boss was defeated in this run (WorldProgress.isBossDefeated).
func is_boss_defeated() -> bool:
	var run := Services.run()
	if run == null:
		return _local_defeated
	return boss_id in (run.world.get("defeated_boss_ids", []) as Array)


## Activation shapes contain the point (inclusive; BossCampScript.ts:79-81).
func contains_activation_point(point: Vector2) -> bool:
	return AreaShapes.contains_point(AreaShapes.of_area(activation_area), point)


## World perimeter of the first activation shape ({} when none).
func activation_perimeter() -> Dictionary:
	return BossArena.first_perimeter(activation_area)


## World perimeter the live boss may pursue within ({} when none).
func arena_perimeter() -> Dictionary:
	return BossArena.first_perimeter(arena_area)


## BossCampScript.ts:106-121 (boss spec 4.1). Returns true when it spawned the boss.
func evaluate_activation(inside_activation: bool, epoch_now: float) -> bool:
	var suppression := BossArena.spawn_suppression(_suppress_spawn_until_outside, inside_activation)
	_suppress_spawn_until_outside = bool(suppression["suppress_spawn_until_outside"])
	if bool(suppression["blocks_spawn_this_update"]):
		return false
	var respawn_ready_at := get_respawn_ready_at()
	if respawn_ready_at >= 0.0 and not inside_activation:
		_observed_outside_after_defeat = true
	if not BossArena.spawn_eligible(_live_boss, inside_activation, respawn_ready_at,
			_observed_outside_after_defeat, epoch_now):
		return false
	return _spawn()


## BossCampScript.ts:123-132 (boss spec 4.4): the progress, feel and cue of `markBossDefeated`,
## the respawn timer, hide the bar, `boss_defeated`, guard off.
func on_boss_defeated(epoch_now: float) -> void:
	if not _live_boss:
		return
	_live_boss = false
	_observed_outside_after_defeat = false
	_mark_boss_defeated()
	_set_respawn_ready_at(epoch_now + respawn_ms)
	boss_disengaged.emit({"campId": camp_id, "defeated": true})
	boss_defeated.emit({"campId": camp_id, "bossId": boss_id})
	_emit_guard_changed(false)


## BossCampScript.ts:134-141 (boss spec 4.5): the player died: remove the boss, hide the bar, and
## spawn again only after the player has left the activation area.
func reset_active_fight() -> void:
	if not _live_boss:
		return
	_remove_boss()
	boss_disengaged.emit({"campId": camp_id, "defeated": false})
	_live_boss = false
	_suppress_spawn_until_outside = true
	_emit_guard_changed(false)


## BossCampScript.ts:143-146.
func is_chest_guarded(instance_id: String) -> bool:
	return _live_boss and not guarded_chest_instance_id.is_empty() and guarded_chest_instance_id == instance_id


## `bossDisplayName` (UniversalSceneWorldController.ts:337-340): the boss's `display_name`, else
## the boss id in title case.
static func display_name_for(boss: Object, fallback_id: String) -> String:
	if boss != null and is_instance_valid(boss):
		var authored: Variant = boss.get(&"display_name")
		if authored is String and not (authored as String).is_empty():
			return authored
	var words := PackedStringArray()
	for word: String in fallback_id.replace("_", "-").replace(".", "-").split("-", false):
		words.append(word.substr(0, 1).to_upper() + word.substr(1))
	return " ".join(words)


## Wall-clock epoch ms (Phaser `Date.now()`; the respawn timer is save-backed there).
static func epoch_now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0


# --- spawner and world side ------------------------------------------------------------------

## BossCampScript.ts:148-163 + spawnBoss (UniversalSceneWorldController.ts:1998-2012).
func _spawn() -> bool:
	if active_bosses == null:
		push_error("BossCampScript '%s': camp '%s' has no active-boss container." % [get_path(), camp_id])
		return false
	var origin_node := get_parent() as Node2D
	var origin := origin_node.global_position if origin_node != null else Vector2.ZERO
	_live_boss = true
	_observed_outside_after_defeat = false
	_set_respawn_ready_at(NO_RESPAWN)
	var request := {
		"sceneId": boss_scene,
		"campId": camp_id,
		"bossId": boss_id,
		"parentRuntimeId": str(active_bosses.get_path()),
		"spawn": {"x": spawn.x, "y": spawn.y},
	}
	_spawn_boss(origin + spawn)
	boss_engaged.emit({"campId": camp_id, "bossId": boss_id})
	boss_spawn_requested.emit(request)
	_emit_guard_changed(true)
	return true


## Removes any previous boss, spawns `boss_scene` at `point` (old Phaser position) under the
## world entities root and hands it the arena.
func _spawn_boss(point: Vector2) -> void:
	_remove_boss()
	var world := Services.world()
	if world == null:
		return
	var root := world.spawn_at_phaser_position(boss_scene, point)
	if root == null:
		push_error("BossCampScript '%s': boss scene '%s' did not spawn." % [get_path(), boss_scene])
		return
	var script := _find_enemy_script(root)
	if script == null:
		push_error("BossCampScript '%s': boss scene '%s' has no enemy receiver script." % [get_path(), boss_scene])
		root.queue_free()
		return
	_boss_root = root
	_boss = script
	script.configure_arena(arena_perimeter())
	script.defeated.connect(_on_boss_defeated_signal.bind(script), CONNECT_DEFERRED | CONNECT_ONE_SHOT)


## Phaser `removeBoss`: frees the live boss's root (if still there). A pending defeat callback of
## the removed boss is ignored (it is no longer `_boss`).
func _remove_boss() -> void:
	if _boss_root != null and is_instance_valid(_boss_root) and not _boss_root.is_queued_for_deletion():
		_boss_root.queue_free()
	_boss_root = null
	_boss = null


## `finishDefeatedBosses` (UniversalSceneWorldController.ts:2021-2037), at the end of the step the
## boss died: burst, `on_boss_defeated`, "<name> defeated!". The body frees itself after its
## death clip (boss spec 4.4, Godot deviation).
func _on_boss_defeated_signal(_payload: Dictionary, boss_ref: Variant) -> void:
	if not is_instance_valid(boss_ref) or boss_ref != _boss:
		return
	var boss := boss_ref as EnemyScript
	var at := boss.get_centre()
	var name_text := display_name_for(boss, boss_id)
	var feel := Services.feel()
	if feel != null:
		feel.particles(DEFEAT_BURST, at - Vector2(0.0, DEFEAT_BURST_RISE_PX))
	on_boss_defeated(epoch_now_ms())
	if feel != null:
		feel.floating_text(at - Vector2(0.0, DEFEAT_TEXT_RISE_PX), "%s defeated!" % name_text, DEFEAT_TEXT_COLOR, true)
	_boss_root = null
	_boss = null


## `progress.markBossDefeated` (UniversalSceneWorldController.ts:596-600): `defeatBoss` (the
## boss id joins RunState `defeated_boss_ids` once), the 'boss.defeated' listeners that are ported
## (the Victory cue), the boss-defeated feel.
func _mark_boss_defeated() -> void:
	var run := Services.run()
	if run == null:
		_local_defeated = true
	else:
		var defeated_ids: Array = run.world.get_or_add("defeated_boss_ids", [])
		if not boss_id in defeated_ids:
			defeated_ids.append(boss_id)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(VICTORY_CUE)
		feel.play(DEFEAT_FEEL)


## `setBossCampRespawnReadyAt` (WorldProgress.ts:524-533): NO_RESPAWN removes the camp's entry,
## a finite epoch >= 0 stores it, anything else is ignored.
func _set_respawn_ready_at(epoch_ms: float) -> void:
	var run := Services.run()
	if run == null:
		_local_respawn_ready_at = epoch_ms if epoch_ms >= 0.0 else NO_RESPAWN
		return
	var camps: Dictionary = run.map_record(map_id)["boss_camps"]
	if epoch_ms < 0.0:
		camps.erase(camp_id)
	elif is_finite(epoch_ms):
		camps[camp_id] = {"respawn_ready_at_epoch_ms": epoch_ms}


func _emit_guard_changed(guarded: bool) -> void:
	guard_changed.emit({"instanceId": guarded_chest_instance_id, "guarded": guarded})


func _on_player_registered(payload: Dictionary) -> void:
	_bind_player(payload.get("player"))


## Listens to the player's `defeated` (WorldScene.onPlayerDeath -> resetActiveFights).
func _bind_player(player: Variant) -> void:
	# typeof + is_instance_valid first: `is` on a freed player (a stale WorldService.player while a
	# new world is built) raises a script error.
	if typeof(player) != TYPE_OBJECT or not is_instance_valid(player):
		return
	var player_object := player as Object
	if player_object.get_instance_id() == _player_bound_id or not player_object.has_signal(&"defeated"):
		return
	_player_bound_id = player_object.get_instance_id()
	var on_defeated := Callable(self, &"_on_player_defeated")
	if not player_object.is_connected(&"defeated", on_defeated):
		player_object.connect(&"defeated", on_defeated)


func _on_player_defeated(_payload: Dictionary) -> void:
	reset_active_fight()


static func _find_enemy_script(root: Node) -> EnemyScript:
	for child: Node in root.get_children():
		if child is EnemyScript:
			return child as EnemyScript
	for node: Node in root.find_children("*", "Node", true, false):
		if node is EnemyScript:
			return node as EnemyScript
	return null

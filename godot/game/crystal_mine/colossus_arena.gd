extends Node2D
class_name ColossusArena
## The Crystal Colossus's arena (roadmap 12.4; docs/godot/DUNGEONS.md "The Crystal Mine (built)";
## decisions archive questions 59, 69, 94 and 132): a round crystal cavern at the bottom of the mine,
## dark (its DarkRoom lists the four braziers, so it fades to lit while all four burn), its north wall
## the one he climbs, under a crack of daylight.
##
## - **The fight starts** when the slime's centre walks into `arena_rect` and he is not beaten: crystal
##   grows over the way in behind it (`seal_cells`: no leaving until he falls, roadmap 5.9), the four
##   braziers are cold, he stands at `post` and wakes after `wake_ms`.
## - **The four braziers** (`braziers`, candle.gd with `burn_ms` -1: they burn until a stomp puts them
##   out, `stomp_puts_out`): while all four burn his weak spot is open (`set_exposed`), else shut.
## - **Fainting** or leaving the arena some other way while he lives resets the fight: he goes, his
##   mites go, the braziers go out, the crystal over the way in shrinks back (the slime resumes at
##   the dungeon's entrance, the kit's Dungeon node).
## - **His fall:** he joins RunState `defeated_boss_ids` (and the dungeon's beaten bosses), so Pearl 3
##   (game/scripts/pearl.gd, `pearl`) rises where he fell; the four braziers burn for good and the
##   cavern is lit; the way in stays shut: the way out is the climb up the wall he climbed
##   (`climb_wall`, the Feral skin's first lock, question 132). Built again later (he is beaten),
##   the way in is open and the braziers burn.
##
## It is a boss camp for the HUD's boss bar and the boss music (the group `boss_camp`: `boss_engaged`,
## `boss_disengaged`, `get_live_boss`, `arena_perimeter`, `camp_id`, `boss_id`), and the compass's
## boss mark on the dungeon map until he falls (the kit's group `dungeon_map_mark`, `mark` "boss").
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const GROUP := &"boss_camp"
const MAP_MARK_GROUP := &"dungeon_map_mark"
const CLUSTER := "res://game/scenes/objects/crystal-cluster-wall--%02d.tscn"
const CUE_SEAL := &"BreakGlass"

## Payload {"campId", "bossId"}.
signal boss_engaged(payload: Dictionary)
## Payload {"campId", "bossId", "defeated": bool}.
signal boss_disengaged(payload: Dictionary)
## Payload {"bossId"}: he fell.
signal boss_defeated(payload: Dictionary)

@export var camp_id: String = "crystal-mine-colossus"
@export var boss_id: String = "crystal-colossus"
@export var boss_scene_id: String = "character.crystal-colossus"
## The fight's floor (world coordinates): his arena and where the slime's centre starts the fight.
@export var arena_rect: Rect2 = Rect2()
## Where he stands at the start, from this node (his old centre).
@export var post: Vector2 = Vector2(0, -150)
@export var wake_ms: float = 1200.0
@export var braziers: Array[NodePath] = []
@export var climb_wall: NodePath
@export var pearl: NodePath
## The cells (world coordinates of their middles) the crystal grows over to shut the way in.
@export var seal_cells: PackedVector2Array = PackedVector2Array()
## The spots on the north wall's foot he climbs from (old centres, world coordinates).
@export var climb_spots: PackedVector2Array = PackedVector2Array()

var _boss_root: Node2D
var _boss: Node
var _seal: Array[Node] = []
var _wake_at := -1.0
var _victory_shown := false
## The dungeon map's mark: "boss" until he falls (DungeonMapDraw.boss_points).
var mark := "boss"


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(MAP_MARK_GROUP)


func _ready() -> void:
	if is_beaten():
		_after_victory(false)


func is_beaten() -> bool:
	var run := Services.run()
	return run != null and boss_id in (run.world.get("defeated_boss_ids", []) as Array)


func is_fighting() -> bool:
	return _boss != null and is_instance_valid(_boss) and not bool(_boss.call(&"is_defeated"))


func get_live_boss() -> Object:
	return _boss if is_fighting() else null


func arena_perimeter() -> Dictionary:
	return {"shape": "rectangle", "x": arena_rect.position.x, "y": arena_rect.position.y,
		"w": arena_rect.size.x, "h": arena_rect.size.y}


## True when all four braziers burn.
func all_lit() -> bool:
	if braziers.is_empty():
		return false
	for path in braziers:
		var node := get_node_or_null(path)
		if node == null or not bool(node.call(&"is_lit")):
			return false
	return true


func _physics_process(_delta: float) -> void:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var centre: Vector2 = player.call(&"get_centre")
	var inside := arena_rect.has_point(centre)
	if is_beaten():
		return
	if _boss == null and inside:
		_start()
		return
	if _boss == null or not is_instance_valid(_boss):
		return
	if bool(_boss.call(&"is_defeated")):
		return
	if not inside:
		_reset()
		return
	if _wake_at >= 0.0 and Services.now_ms() >= _wake_at:
		_wake_at = -1.0
		_boss.call(&"wake")
	_boss.call(&"set_exposed", all_lit())


## Starts the fight (the slime walked in): the seal, the cold braziers, the boss at his post.
func _start() -> void:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	_boss_root = world.instantiate_scene(boss_scene_id) as Node2D
	if _boss_root == null:
		push_warning("ColossusArena: no '%s' scene" % boss_scene_id)
		return
	for child: Node in _boss_root.get_children():
		if child.has_method(&"configure_arena"):
			_boss = child
			break
	if _boss == null:
		_boss_root.free()
		_boss_root = null
		return
	parent.add_child(_boss_root)
	FeetAnchor.place_at_phaser_position(_boss_root, global_position + post)
	var no_zones: Array[Dictionary] = []
	_boss.call(&"configure_navigation", {}, no_zones)
	_boss.call(&"configure_arena", arena_perimeter())
	var spots: Array[Vector2] = []
	for spot in climb_spots:
		spots.append(spot)
	_boss.set(&"climb_spots", spots)
	_boss.connect(&"defeated", _on_defeated)
	for path in braziers:
		var node := get_node_or_null(path)
		if node != null and node.has_method(&"put_out"):
			node.call(&"put_out")
	_set_sealed(true)
	_wake_at = Services.now_ms() + wake_ms
	boss_engaged.emit({"campId": camp_id, "bossId": boss_id})


## The slime fainted (or left): the fight starts over next time.
func _reset() -> void:
	if _boss != null and is_instance_valid(_boss) and _boss.has_method(&"clear_mites"):
		_boss.call(&"clear_mites")
	if _boss_root != null and is_instance_valid(_boss_root):
		_boss_root.queue_free()
	_boss_root = null
	_boss = null
	_wake_at = -1.0
	for path in braziers:
		var node := get_node_or_null(path)
		if node != null and node.has_method(&"put_out"):
			node.call(&"put_out")
	_set_sealed(false)
	boss_disengaged.emit({"campId": camp_id, "bossId": boss_id, "defeated": false})


func _on_defeated(_payload: Dictionary = {}) -> void:
	var run := Services.run()
	if run != null:
		var ids: Array = run.world.get_or_add("defeated_boss_ids", [])
		if not boss_id in ids:
			ids.append(boss_id)
		var dungeon_id := DungeonState.current_id(get_tree())
		if not dungeon_id.is_empty():
			DungeonState.mark_boss_beaten(run, dungeon_id, boss_id)
		run.world_progress_changed.emit({"map_id": Services.world().map_id() if Services.world() != null else ""})
	var fell_at := Vector2.ZERO
	var body := _boss_root as Node2D
	if body != null and is_instance_valid(body):
		fell_at = body.global_position
	var pearl_node := get_node_or_null(pearl) as Node2D
	if pearl_node != null and fell_at != Vector2.ZERO:
		pearl_node.global_position = fell_at + Vector2(0, 20)
	boss_disengaged.emit({"campId": camp_id, "bossId": boss_id, "defeated": true})
	boss_defeated.emit({"bossId": boss_id})
	_after_victory(true)


## After his fall: the braziers burn for good (the cavern lit); the seal stays until the world is
## built again (the way out is the climb).
func _after_victory(now: bool) -> void:
	if _victory_shown:
		return
	_victory_shown = true
	mark = ""
	for path in braziers:
		var node := get_node_or_null(path)
		if node != null and node.has_method(&"keep_lit"):
			node.call(&"keep_lit")
	if now:
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(&"Victory")


func _set_sealed(on: bool) -> void:
	for node in _seal:
		if is_instance_valid(node):
			node.queue_free()
	_seal.clear()
	if not on:
		return
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	var i := 0
	for at in seal_cells:
		var path := CLUSTER % (3 + (i % 5) * 2)
		if ResourceLoader.exists(path):
			var cluster := (load(path) as PackedScene).instantiate() as Node2D
			cluster.name = "ArenaSeal%d" % i
			parent.add_child(cluster)
			cluster.global_position = at
			_seal.append(cluster)
		i += 1
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SEAL)
		feel.shake(260.0, 0.006)

@tool
extends Node2D
class_name RoomFight
## A room fight (docs/godot/DUNGEONS.md "Shutters and room fights"): the shutters close when the
## slime steps into the room, and open when no living enemy is left in it (Zelda's shutter rooms,
## the ambush rooms, the mini-boss and boss rooms as trap gates).
##
## - Its room is the rectangle `size` from its position (drawn in the editor). The fight starts
##   once the slime's centre is `dungeon.shutter.insetPx` inside it and as far from each of its
##   shutters (never in a doorway) while a living enemy stands in it.
## - **Its enemies are whatever lives in its room now** (game/enemy/live_enemies.gd; owner,
##   2026-11-21): every enemy whose centre is in the rectangle and that is not beaten, asked each
##   step, never a count of kills or a list made with the scene. Enemies added to the room scene or
##   taken out of it in the editor change nothing to wire; one hatched or called in during the fight
##   (an egg sac's Broodlings) holds the shutters too, and one the slime carries in its mouth still
##   lives.
## - Its shutters: every Shutter (shutter.gd) whose `fight_id` is this `fight_id`.
## - Won (no living enemy in the room): after `dungeon.shutter.openDelayMs` the shutters open,
##   `reward` (a hidden chest, a drawbridge, a shutter...) is set off (DungeonState.fire), `cleared`
##   fires. Its shutters shut from the start (`starts_shut`, R4) in a room with no living enemy open
##   the same way once the slime is in the room (won without a fight): such a room is never stuck.
## - `once`: an ambush that never repeats (template rule 8): cleared, it is recorded, and the placed
##   enemies of its room are taken out of the world for good (they never come back on re-entry). A
##   fight that is not `once` runs again each time its room is entered with its enemies back.
## - `boss_id`: a boss (or mini-boss) fight, once by itself: won, the boss is recorded beaten
##   (DungeonState.mark_boss_beaten, RunState `defeated_boss_ids`) and never comes back; the
##   map marks its room until then, once the map is held (only the dungeon's boss when its Dungeon
##   node names one: dungeon_map_draw.gd `boss_points`).
## - The slime fainting or leaving the room (a fall, a respawn) ends the fight unwon: the shutters
##   open, and its beaten enemies come back with the room.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PlacedEnemy := preload("res://game/enemy/placed_enemy.gd")
const LiveEnemies := preload("res://game/enemy/live_enemies.gd")
const Shutter := preload("res://game/dungeon/shutter.gd")

const GROUP := &"room_fight"
const OUTLINE := Color(1.0, 0.45, 0.25, 0.85)

## The shutters closed. Payload: {"fightId"}.
signal started(payload: Dictionary)
## Won. Payload: {"fightId"}.
signal cleared(payload: Dictionary)
## Ended unwon (the slime left or fainted). Payload: {"fightId"}.
signal reset(payload: Dictionary)

## The room (world units from this node's position).
@export var size: Vector2 = Vector2(1024, 896):
	set(value):
		size = value
		queue_redraw()
## Its shutters' `fight_id` and its record id.
@export var fight_id: String = ""
## An ambush: won once, never again.
@export var once: bool = false
## A boss fight: the boss's id (recorded beaten when won; never comes back).
@export var boss_id: String = ""
## Called when won (`appear()` or `trigger()`).
@export var reward: NodePath

var _active := false
## When the room was last found with no living enemy in it (-1: it holds one).
var _won_at_ms := -1.0
## The placed enemies standing in its room when it was built: the ones a won `once` or boss fight
## takes out of the world for good. Never what wins it (that is the living enemies in the room).
var _placed: Array[Node] = []


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_placed = _find_placed()
	# Won before (an ambush, a boss): its enemies never stand again. Taken out of the placed
	# enemies' group now, before the world's population collects them (main.gd builds it after).
	if _is_done_now():
		_retire_placed()
		if not boss_id.is_empty():
			_reward_if_beaten_elsewhere.call_deferred()


## Its boss fell, but never in this fight (in another world of his dungeon: a save from a dungeon's
## retired worlds, RunState RETIRED_WORLDS; the Warden beaten in the four-floor Weaver Hollow, the
## Shardback in the one-scene Mine): its reward was never given here (the Hoard's shutter, the Den's
## rim shutters stayed shut). Given now, once, and the fight recorded as won.
func _reward_if_beaten_elsewhere() -> void:
	if not is_inside_tree() or DungeonState.is_done(get_tree(), _record_key()):
		return
	DungeonState.mark_done(get_tree(), _record_key())
	for shutter: Shutter in _shutters():
		shutter.open()
	if not reward.is_empty():
		DungeonState.fire(get_node_or_null(reward), {"fightId": fight_id})


## The room in world coordinates.
func rect() -> Rect2:
	return Rect2(global_position, size)


func is_active() -> bool:
	return _active


## True once an ambush or a boss fight was won (it never runs again).
func is_done() -> bool:
	return _is_done_now()


## The living enemies in its room now (game/enemy/live_enemies.gd).
func members() -> Array[Node]:
	return LiveEnemies.in_rect(get_tree(), rect())


## How many living enemies stand in its room now.
func standing_count() -> int:
	return members().size()


## True while a living enemy stands in its room.
func is_held() -> bool:
	return LiveEnemies.any_in_rect(get_tree(), rect())


## Ends it as won without the fight (the `?sealed` dev option: the Pearl's guard already beaten):
## recorded like a won `once` or boss fight, its room's enemies taken away, its shutters open.
func finish_quietly() -> void:
	_active = false
	_won_at_ms = -1.0
	DungeonState.mark_done(get_tree(), _record_key())
	# The enemies living in its room go with it.
	for enemy: Node in members():
		var root := enemy.get_parent()
		if root != null and root != get_tree().root:
			root.queue_free()
	_retire_placed()
	for shutter: Shutter in _shutters():
		shutter.open()


func _physics_process(_delta: float) -> void:
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	var centre: Vector2 = world.player.get_centre()
	var dead := bool(world.player.call(&"is_dead"))
	if _active:
		if dead or not rect().has_point(centre):
			_reset()
			return
		_win_when_clear()
		return
	var inside := rect().grow(-DungeonState.number("shutter.insetPx", 80.0)).has_point(centre)
	if dead or not inside:
		_won_at_ms = -1.0
		return
	if is_held():
		_won_at_ms = -1.0
		if not _is_done_now() and _clear_of_shutters(centre):
			_start()
		return
	# The slime is in the room and nothing lives in it: shutters shut from the start open.
	if _shut_shutters().is_empty():
		_won_at_ms = -1.0
		return
	if _is_done_now():
		for shutter: Shutter in _shut_shutters():
			shutter.open()
		return
	_win_when_clear()


## Won `dungeon.shutter.openDelayMs` after its room was last seen with no living enemy in it; a
## living enemy in it (one that came back or hatched) starts the wait again.
func _win_when_clear() -> void:
	if is_held():
		_won_at_ms = -1.0
		return
	if _won_at_ms < 0.0:
		_won_at_ms = Services.now_ms()
	if Services.now_ms() - _won_at_ms >= DungeonState.number("shutter.openDelayMs", 600.0):
		_win()


## True when the slime stands `dungeon.shutter.insetPx` or more from each of its shutters (none
## shuts on it).
func _clear_of_shutters(centre: Vector2) -> bool:
	var inset := DungeonState.number("shutter.insetPx", 80.0)
	for shutter: Shutter in _shutters():
		if shutter.global_position.distance_to(centre) < inset:
			return false
	return true


func _start() -> void:
	_active = true
	_won_at_ms = -1.0
	for shutter: Shutter in _shutters():
		shutter.shut()
	started.emit({"fightId": fight_id})


func _reset() -> void:
	_active = false
	_won_at_ms = -1.0
	for shutter: Shutter in _shutters():
		shutter.open()
	reset.emit({"fightId": fight_id})


func _win() -> void:
	_active = false
	_won_at_ms = -1.0
	var run := Services.run()
	var dungeon_id := DungeonState.current_id(get_tree())
	if not boss_id.is_empty():
		DungeonState.mark_boss_beaten(run, dungeon_id, boss_id)
	if once or not boss_id.is_empty():
		DungeonState.mark_done(get_tree(), _record_key())
		_retire_placed()
	for shutter: Shutter in _shutters():
		shutter.open()
	if not reward.is_empty():
		DungeonState.fire(get_node_or_null(reward), {"fightId": fight_id})
	cleared.emit({"fightId": fight_id})


func _is_done_now() -> bool:
	if not boss_id.is_empty() and DungeonState.is_boss_beaten(Services.run(), DungeonState.current_id(get_tree()), boss_id):
		return true
	return (once or not boss_id.is_empty()) and DungeonState.is_done(get_tree(), _record_key())


func _record_key() -> String:
	return DungeonState.object_key(self, "fight:" + (fight_id if not fight_id.is_empty() else String(name)))


## The placed enemies of its room leave the world for good: out of the placed enemies' group (so a
## population built later never collects them) and freed (one built already skips freed ones).
func _retire_placed() -> void:
	for node: Node in _placed:
		if is_instance_valid(node) and node is PlacedEnemy:
			node.remove_from_group(PlacedEnemy.GROUP)
			node.queue_free()


## Every placed enemy standing in its room.
func _find_placed() -> Array[Node]:
	var out: Array[Node] = []
	var area := rect()
	for node: Node in get_tree().get_nodes_in_group(PlacedEnemy.GROUP):
		if node is Node2D and area.has_point((node as Node2D).global_position):
			out.append(node)
	return out


func _shutters() -> Array[Shutter]:
	var out: Array[Shutter] = []
	if fight_id.is_empty():
		return out
	for node: Node in get_tree().get_nodes_in_group(Shutter.GROUP):
		if node is Shutter and (node as Shutter).fight_id == fight_id:
			out.append(node as Shutter)
	return out


func _shut_shutters() -> Array[Shutter]:
	var out: Array[Shutter] = []
	for shutter: Shutter in _shutters():
		if shutter.is_shut():
			out.append(shutter)
	return out


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(Vector2.ZERO, size), OUTLINE, false, 3.0)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := "room fight: %s%s%s" % [fight_id, " (once)" if once else "", (" boss " + boss_id) if not boss_id.is_empty() else ""]
		draw_string(font, Vector2(12, size.y - 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, OUTLINE)

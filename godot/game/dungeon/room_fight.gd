@tool
extends Node2D
class_name RoomFight
## A room fight (docs/godot/DUNGEONS.md "Shutters and room fights"): the shutters close when the
## slime steps into the room, and open when the room's enemies are beaten (Zelda's shutter rooms,
## the ambush rooms, the mini-boss and boss rooms as trap gates).
##
## - Its room is the rectangle `size` from its position (drawn in the editor). The fight starts
##   once the slime's centre is `dungeon.shutter.insetPx` inside it and as far from each of its
##   shutters (never in a doorway) while one of its enemies stands.
## - Its enemies: the PlacedEnemy nodes in `enemies` (or anything with `is_standing()`, or
##   `is_defeated()`); when `enemies` is empty, every placed enemy standing in its rectangle.
## - Its shutters: every Shutter (shutter.gd) whose `fight_id` is this `fight_id`.
## - Won (no enemy stands): after `dungeon.shutter.openDelayMs` the shutters open, `reward` (a
##   hidden chest, a drawbridge, a shutter...) is set off (DungeonState.fire), `cleared` fires.
## - `once`: an ambush that never repeats (template rule 8): cleared, it is recorded, and its
##   placed enemies are taken out of the world for good (they never come back on re-entry). A fight
##   that is not `once` runs again each time its room is entered with its enemies back.
## - `boss_id`: a boss (or mini-boss) fight, once by itself: won, the boss is recorded beaten
##   (DungeonState.mark_boss_beaten, RunState `defeated_boss_ids`) and never comes back; the
##   compass marks its room until then.
## - The slime fainting or leaving the room (a fall, a respawn) ends the fight unwon: the shutters
##   open, and its beaten enemies come back with the room.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PlacedEnemy := preload("res://game/enemy/placed_enemy.gd")
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
## Its enemies (PlacedEnemy nodes); empty: every placed enemy standing in the room.
@export var enemies: Array[NodePath] = []
## Called when won (`appear()` or `trigger()`).
@export var reward: NodePath

var _active := false
var _won_at_ms := -1.0
var _members: Array[Node] = []


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_members = _find_members()
	# Won before (an ambush, a boss): its enemies never stand again. Taken out of the placed
	# enemies' group now, before the world's population collects them (main.gd builds it after).
	if _is_done_now():
		_retire_members()


## The room in world coordinates.
func rect() -> Rect2:
	return Rect2(global_position, size)


func is_active() -> bool:
	return _active


## True once an ambush or a boss fight was won (it never runs again).
func is_done() -> bool:
	return _is_done_now()


## Its enemies (PlacedEnemy nodes, or anything with `is_standing()` / `is_defeated()`).
func members() -> Array[Node]:
	var out: Array[Node] = []
	for member: Node in _members:
		if is_instance_valid(member):
			out.append(member)
	return out


## Ends it as won without the fight (the `?sealed` dev option: the Pearl's guard already beaten):
## recorded like a won `once` or boss fight, its enemies taken away, its shutters open.
func finish_quietly() -> void:
	_active = false
	_won_at_ms = -1.0
	DungeonState.mark_done(get_tree(), _record_key())
	# Its enemies spawned already: they go with it.
	for member: Node in _members:
		var enemy: Node = member.call(&"get_enemy") if is_instance_valid(member) and member.has_method(&"get_enemy") else null
		if enemy != null and is_instance_valid(enemy) and enemy.get_parent() != null:
			enemy.get_parent().queue_free()
	_retire_members()
	for shutter: Shutter in _shutters():
		shutter.open()


## How many of its enemies stand.
func standing_count() -> int:
	var count := 0
	for member: Node in _members:
		if not is_instance_valid(member):
			continue
		if member.has_method(&"is_standing"):
			if bool(member.call(&"is_standing")):
				count += 1
		elif member.has_method(&"is_defeated"):
			if not bool(member.call(&"is_defeated")):
				count += 1
	return count


func _physics_process(_delta: float) -> void:
	if _is_done_now() and not _active:
		return
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	var centre: Vector2 = world.player.get_centre()
	var dead := bool(world.player.call(&"is_dead"))
	var inside := rect().grow(-DungeonState.number("shutter.insetPx", 80.0)).has_point(centre)
	if not _active:
		if inside and not dead and standing_count() > 0 and _clear_of_shutters(centre):
			_start()
		return
	if dead or not rect().has_point(centre):
		_reset()
		return
	if standing_count() > 0:
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
		_retire_members()
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


## Its placed enemies leave the world for good: out of the placed enemies' group (so a population
## built later never collects them) and freed (one built already skips freed ones).
func _retire_members() -> void:
	for member: Node in _members:
		if is_instance_valid(member) and member is PlacedEnemy:
			member.remove_from_group(PlacedEnemy.GROUP)
			member.queue_free()


func _find_members() -> Array[Node]:
	var out: Array[Node] = []
	for path: NodePath in enemies:
		var node := get_node_or_null(path)
		if node != null:
			out.append(node)
	if not enemies.is_empty():
		return out
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


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(Vector2.ZERO, size), OUTLINE, false, 3.0)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := "room fight: %s%s%s" % [fight_id, " (once)" if once else "", (" boss " + boss_id) if not boss_id.is_empty() else ""]
		draw_string(font, Vector2(12, size.y - 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, OUTLINE)

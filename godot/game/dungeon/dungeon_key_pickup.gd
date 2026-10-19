@tool
extends Node2D
class_name DungeonKeyPickup
## A dungeon item lying on the floor (docs/godot/DUNGEONS.md "Keys and the map";
## `object.dungeon-key`): a small key (or the big key, the map, the compass) that bobs and glints.
## The slime walks over it and takes it (DungeonItems.give); its id is recorded (DungeonState
## mark_done), so it never comes back. `drop(item, at, id)` makes one at run time (an enemy that
## spits out the key it swallowed: the Weaver Hollow's Cocoon Mimic).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonItems := preload("res://game/dungeon/dungeon_items.gd")

const SIZE_PX := 30.0
const BOB_PX := 3.0
const BOB_S := 1.4
const SHADOW := Color(0, 0, 0, 0.28)
const CUE_DROP := &"DropLand"

## Taken. Payload: {"item", "pickupId"}.
signal taken(payload: Dictionary)

## "small-key", "big-key", "map" or "compass".
@export_enum("small-key", "big-key", "map", "compass") var item: String = "small-key":
	set(value):
		item = value
		_picture = null
		queue_redraw()
## Its id in the record (unique in its world; the node's name when empty).
@export var pickup_id: String = ""

var _picture: Texture2D
var _taken := false


## Drops `item` at `at` (global, on the floor) under the world's entity layer, with record id `id`.
## Null without a world, or when that id was taken before.
static func drop(drop_item: String, at: Vector2, id: String) -> Node2D:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null or DungeonState.is_done(parent.get_tree(), DungeonState.object_key(parent, "key:" + id)):
		return null
	var pickup: Node2D = (load("res://game/dungeon/dungeon_key_pickup.gd") as GDScript).new()
	pickup.set(&"item", drop_item)
	pickup.set(&"pickup_id", id)
	parent.add_child.call_deferred(pickup)
	pickup.set_deferred(&"global_position", at)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_DROP)
	return pickup


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	if DungeonState.is_done(get_tree(), _record_key()):
		queue_free()
		return
	_check_record.call_deferred()


func _check_record() -> void:
	if is_inside_tree() and DungeonState.is_done(get_tree(), _record_key()):
		queue_free()


func _record_key() -> String:
	return DungeonState.object_key(self, "key:" + (pickup_id if not pickup_id.is_empty() else String(name)))


func _physics_process(_delta: float) -> void:
	if _taken:
		return
	var world := Services.world()
	if world == null or world.player_body == null or world.player == null or bool(world.player.call(&"is_dead")):
		return
	var reach := DungeonState.number("refill.pickupRadiusPx", 22.0)
	if world.player_body.global_position.distance_to(global_position) > reach + 12.0:
		return
	if not DungeonState.on_level_of(self):
		return
	_taken = true
	DungeonState.mark_done(get_tree(), _record_key())
	DungeonItems.give(get_tree(), item)
	taken.emit({"item": item, "pickupId": pickup_id})
	queue_free()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _picture == null:
		_picture = DungeonItems.icon(item)
	var bob := sin(Time.get_ticks_msec() / 1000.0 * TAU / BOB_S) * BOB_PX if not Engine.is_editor_hint() else 0.0
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, SIZE_PX * 0.32, SHADOW)
	draw_set_transform(Vector2.ZERO)
	if _picture != null:
		var size := Vector2(SIZE_PX, SIZE_PX * _picture.get_size().y / maxf(1.0, _picture.get_size().x))
		draw_texture_rect(_picture, Rect2(Vector2(-size.x * 0.5, -size.y - 6.0 + bob), size), false)

extends DoorScript
## The travel of a room door (`object.room-door`, game/dungeon/room_door.gd; docs/godot/DUNGEON_ROOMS.md
## "Room doors"): the game's door (game/scripts/door.gd: pushed into, its trigger in the doorway's
## passage) that goes to another room's world with the screen scroll (main.gd `request_exit`,
## transition "scroll") instead of the iris. Its parent, the RoomDoor, sets it up when the room is
## built (`map_id`, `door_id`, `target_area_id`, `target_door_id`, `side`, `trigger_rect`) and says
## whether it may go (`refusal`: a record not set yet, such as the bolt on the far side).
##
## Owner: dungeon kit.

const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const CUE_REFUSED := &"GateLocked"
## How far over the slime its refusal shows (presentation).
const REFUSAL_RISE := 70.0


func use() -> Dictionary:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if main == null or not main.has_method(&"request_exit"):
		return {"status": "blocked", "message": "Navigation unavailable"}
	var room_door := get_parent()
	if room_door != null and room_door.has_method(&"is_blocked") and bool(room_door.call(&"is_blocked")):
		var refusal := str(room_door.call(&"refusal"))
		if not refusal.is_empty():
			_say(refusal)
		return {"status": "blocked", "message": refusal}
	var at := (room_door as Node2D).global_position if room_door is Node2D else Vector2.ZERO
	var result: Dictionary = main.call(&"request_exit", {"map_id": map_id, "exit_id": door_id,
		"target_area_id": target_area_id, "entry": "", "target_door_id": target_door_id,
		"transition": _transition(room_door), "door_side": side if has_side() else "", "door_at": at, "lead_ms": 0.0})
	if str(result.get("status", "")) == "queued":
		_used = true
		_cue(use_cue)
	return result


## The RoomDoor's `transition` ("scroll" or "iris").
func _transition(room_door: Node) -> String:
	var asked := str(room_door.get(&"transition")) if room_door != null else ""
	return asked if asked == "iris" else "scroll"


func _say(text: String) -> void:
	var feel := Services.feel()
	var world := Services.world()
	if feel == null or world == null or world.player == null or not is_instance_valid(world.player):
		return
	feel.audio_cue(CUE_REFUSED)
	feel.floating_text(world.player.call(&"get_centre") - Vector2(0.0, REFUSAL_RISE), text, &"white", false,
			DungeonState.number("door.lineMs", 2000.0))

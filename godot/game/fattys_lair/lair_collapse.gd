extends Node
## The Lair's way in once it has caved in (owner, 2026-10-19: once Fatty falls the Lair is done for
## good, as a Zelda dungeon; docs/godot/DUNGEONS.md "Fatty's Lair (built)"): with `boss_id` beaten in
## `dungeon_id`'s record, `rubble` shows and `door` (a DoorScript) is locked for good with
## `buried_text` (its `gate`, a key nobody has). Before, the rubble is hidden. On the mouth in
## Fatty's Hollow (D5) and on R1's way out to it.
##
## Owner: Fatty's Lair.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

@export var dungeon_id: String = "fatty-lair"
@export var boss_id: String = "fatty-one-eye"
## The DoorScript the rubble shuts.
@export var door: Node
## The rubble's look (hidden until the cave-in).
@export var rubble: CanvasItem
@export var buried_text: String = "Rubble buries the way. The Lair has caved in."


func _ready() -> void:
	var buried := DungeonState.is_boss_beaten(Services.run(), dungeon_id, boss_id)
	if rubble != null:
		rubble.visible = buried
	if buried and door != null:
		door.set(&"gate", {"id": dungeon_id + "-buried", "lockedMessage": buried_text, "requiredItemId": dungeon_id + "-rubble"})

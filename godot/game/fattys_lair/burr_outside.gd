extends Node2D
## Burr outside the Lair (level-1-d4, by the bolt-hole's mouth near the Verdant Gate; docs/godot/DUNGEONS.md
## "Fatty's Lair (built)"; the design's "After Fatty"): once Burr is freed (game/fattys_lair/lair_director.gd
## FLAG_FREED) and Fatty is beaten (`boss_id` in RunState `defeated_boss_ids`), he waits here in
## daylight. Talked to (the interact key: it joins the interaction's `usable` group) he says that the
## town must see the Pearl, then waves and walks off home; the story flag FLAG_TALKED keeps him gone.
## Until then, and after, he is not here. Home is his house in Slimeshire's C4: the flag puts him there
## (`burr` in game/scenes/worlds/rooms/c4/slimeshire-burr-house.tscn, its BurrHome story variant).
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")
const LairDirector := preload("res://game/fattys_lair/lair_director.gd")
const BurrActor := preload("res://game/fattys_lair/burr_actor.gd")

const USABLE_GROUP := &"usable"
const FLAG_TALKED := "fatty-lair.burr-outside"
const SPEAKER := "Burr"
const LINES: Array[String] = [
	"Daylight! And you came up through the old bolt-hole, as I hoped.",
	"Is that... a Pearl of the Wellspring? Out of Fatty's own hoard!",
	"The whole town must see this. Go show Plop, lad. I'm off home to my boy; come and find me there.",
]

## Burr himself (a BurrActor).
@export var actor: BurrActor
## Which way he looks while he waits (-1 left, 1 right).
@export var facing_x: float = -1.0
## Where he walks off to after the talk (local to this node).
@export var walk_off: Vector2 = Vector2(-300.0, 60.0)
@export var boss_id: String = "fatty-one-eye"
## The interaction's prompt, reach and badge height.
@export var prompt: String = "Talk to Burr"
@export var interact_radius: float = 80.0
@export var badge_rise: float = 110.0

var _talking := false
## The slime his talk holds still (`_hold_player`).
var _held_player: Node


func _ready() -> void:
	if actor != null:
		actor.face(facing_x)
	_refresh()


## True while he waits here: freed, Fatty beaten, not talked to yet.
func is_waiting() -> bool:
	var run := Services.run()
	if run == null or not run.has_flag(LairDirector.FLAG_FREED) or run.has_flag(FLAG_TALKED):
		return false
	return boss_id in (run.world.get("defeated_boss_ids", []) as Array)


func origin() -> Vector2:
	return global_position


func can_use() -> bool:
	return is_waiting() and not _talking


func use() -> bool:
	if not can_use():
		return false
	_talk()
	return true


func _refresh() -> void:
	var waiting := is_waiting()
	visible = waiting
	if waiting and not is_in_group(USABLE_GROUP):
		add_to_group(USABLE_GROUP)
	elif not waiting and is_in_group(USABLE_GROUP):
		remove_from_group(USABLE_GROUP)
	if actor != null:
		actor.set_blocking(waiting)


func _talk() -> void:
	_talking = true
	var world := Services.world()
	_held_player = world.player if world != null else null
	# A method of this node, not a lambda: freed mid-speech, the tree drops the connection with it.
	get_tree().physics_frame.connect(_hold_player)
	if actor != null:
		actor.wave(1.2)
	await PrologueScene.say(get_tree(), SPEAKER, LINES)
	if get_tree().physics_frame.is_connected(_hold_player):
		get_tree().physics_frame.disconnect(_hold_player)
	var run := Services.run()
	if run != null:
		run.set_flag(FLAG_TALKED)
	if actor != null and is_inside_tree():
		actor.set_blocking(false)
		await actor.walk_to(global_position + walk_off, 90.0)
		await actor.fade_out(0.5)
	_talking = false
	_refresh()


## Each physics frame while he talks: the slime stands still.
func _hold_player() -> void:
	PrologueScene.hold(_held_player)

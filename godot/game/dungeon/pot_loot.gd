extends Node
class_name PotLoot
## What a pot hides (docs/godot/DUNGEONS.md "Refills that grow back"): put a PotLoot node under a
## liftable's root (a clay pot, a crate: game/scripts/liftable.gd) in a world. When the pot leaves
## its spot (the slime sucks it up), what it hid is left where it stood, as Zelda's pots show a heart
## under them: `loot` "heart", "energy", "coins", or "random" (a heart, energy, coins or nothing,
## by `weights`). In a dungeon the pot comes back when its room is entered again (the Dungeon node's
## room resets), and so does what it hides.
##
## Owner: dungeon kit.

const DungeonPickup := preload("res://game/dungeon/dungeon_pickup.gd")

const KINDS: PackedStringArray = ["heart", "energy", "coins", "none"]

## "heart", "energy", "coins", "random" or "none".
@export_enum("random", "heart", "energy", "coins", "none") var loot: String = "random"
## The chances of a heart, energy, coins and nothing for "random".
@export var weights: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])

var _root: Node2D


func _ready() -> void:
	_root = get_parent() as Node2D
	if _root != null and not _root.tree_exiting.is_connected(_on_root_leaving):
		_root.tree_exiting.connect(_on_root_leaving)


## The kind it leaves now ("none" for nothing).
func pick() -> String:
	if loot != "random":
		return loot
	var total := 0.0
	for weight: float in weights:
		total += maxf(0.0, weight)
	if total <= 0.0:
		return "none"
	var roll := randf() * total
	for i in mini(weights.size(), KINDS.size()):
		roll -= maxf(0.0, weights[i])
		if roll <= 0.0:
			return KINDS[i]
	return "none"


## Taken away (queued for deletion by the mouth, not its whole world going): the loot appears.
func _on_root_leaving() -> void:
	if _root == null or not _root.is_queued_for_deletion():
		return
	var kind := pick()
	if kind == "none":
		return
	DungeonPickup.spawn(kind, _root.global_position)

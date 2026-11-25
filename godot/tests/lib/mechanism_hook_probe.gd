extends Node2D
## A stand-in for a boss in the mechanism tests (tests/test_mechanisms.gd): a body with a hurtbox
## that answers `on_mechanism_hit(kind, source)`, the hook a dungeon mechanism calls instead of
## dealing damage (game/dungeon/mechanism_strike.gd). It records the calls and any damage that
## reached it through the damage router (there should be none).

const Services := preload("res://game/shared/services.gd")

const RULE := {"priority": 0, "damageMultiplier": 1}
const SIZE := Vector2(48.0, 48.0)

## Its hurtbox's size, standing on its feet (set before it enters the tree; the film tool matches it
## to the training dummy's picture).
var size := SIZE

## Every hook call: [kind, source].
var calls: Array = []
## Damage commits that reached it (a mechanism must send none).
var commits := 0
var _area: Area2D


func _ready() -> void:
	_area = Area2D.new()
	_area.collision_layer = 8
	_area.collision_mask = 16
	_area.monitoring = false
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector2(0.0, -size.y * 0.5)
	_area.add_child(shape)
	add_child(_area)
	var router := Services.router()
	if router != null:
		router.register_area(_area, self, RULE, [])


func _exit_tree() -> void:
	var router := Services.router()
	if router != null and _area != null:
		router.unregister_area(_area)


func on_mechanism_hit(kind: StringName, source: Node) -> void:
	calls.append([kind, source])


func get_damage_state() -> Dictionary:
	return {"hp": 100.0, "max_hp": 100.0, "dead": false}


func commit_damage(_commit: Dictionary) -> void:
	commits += 1

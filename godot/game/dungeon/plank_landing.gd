@tool
extends "res://game/dungeon/hazard_deck.gd"
class_name PlankLanding
## A plank landing (docs/godot/DUNGEONS.md "Falling planks over water"; `object.plank-landing`): a
## whole, nailed plank of a bridge over deep water that never falls: safe ground over the water
## hazard, where a Roll may end on a bridge of falling planks (falling_plank.gd), as a slab bridge's
## landing (a HazardDeck). It opens the deep water's collision under it like the planks
## (plank_look.gd `open_lane`). `east_west` turns the boards for a bridge that runs east-west.
##
## Owner: dungeon kit.

const PlankLook := preload("res://game/dungeon/plank_look.gd")

## The bridge runs east-west (the boards are turned a quarter).
@export var east_west: bool = false:
	set(value):
		east_west = value
		queue_redraw()

var _picture: Texture2D


func _init() -> void:
	draw_floor = false


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		PlankLook.open_lane(self, size)


func _draw() -> void:
	super()
	if _picture == null:
		_picture = PlankLook.picture()
	PlankLook.draw(self, _picture, Rect2(Vector2.ZERO, size), size, PlankLook.WHOLE, Color.WHITE, east_west)

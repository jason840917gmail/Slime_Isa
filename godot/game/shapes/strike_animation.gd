@tool
class_name StrikeAnimation
extends Resource
## One strike of the body shapes: its three directions, and what plays it (`shape` and `step`, the chain step
## or charge id in game-constants.json, which gives the timing). Select the file to see it play above these
## fields; edit, then press Ctrl+S. Files: res://game/characters/strikes/<strike>.tres.

const DirectionScript := preload("res://game/shapes/strike_direction.gd")

## "spear", "axe" or "hammer".
@export var shape: String = ""
## jab, jab-2, lunging-jab, lunge, sweep, backswing, chop, thud, boom or quake.
@export var step: String = ""
@export var side: DirectionScript
@export var down: DirectionScript
@export var up: DirectionScript


## The direction `name` ("side", "down" or "up"); null for any other name.
func of(name: String) -> DirectionScript:
	match name:
		"side":
			return side
		"down":
			return down
		"up":
			return up
	return null

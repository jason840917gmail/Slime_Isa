extends Resource
class_name SlimeTypeResource

@export var id: StringName
@export var display_name := "Slime"
@export var max_health := 3
@export var speed := 180.0
@export var sprite_sheet: Texture2D
@export var abilities: Array[StringName] = []

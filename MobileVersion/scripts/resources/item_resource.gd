extends Resource
class_name ItemResource

@export var id: StringName
@export var display_name := "Item"
@export_enum("coin", "berry", "key_item") var item_type := "coin"
@export var value := 1
@export var icon: Texture2D

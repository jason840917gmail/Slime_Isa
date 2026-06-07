extends Resource
class_name LevelResource

@export var id: StringName
@export var display_name := "Level"
@export_file("*.tscn") var scene_path := ""
@export var music: AudioStream
@export var recommended_level := 1

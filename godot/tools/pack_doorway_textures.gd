extends SceneTree
## Saves the packed doorway art as native textures without running an editor import.
const DIRECTORY := "res://asset/MAPS/objects/dungeon/doorways/"
func _initialize() -> void:
	var failed := 0
	for file: String in DirAccess.get_files_at(DIRECTORY):
		if not file.ends_with(".webp"):
			continue
		var image := Image.load_from_file(DIRECTORY + file)
		if image == null:
			failed += 1
			continue
		var texture := ImageTexture.create_from_image(image)
		var error := ResourceSaver.save(texture, DIRECTORY + file.get_basename() + ".res", ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			failed += 1
	print("doorway textures: ", failed, " failures")
	quit(1 if failed > 0 else 0)

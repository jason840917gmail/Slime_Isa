extends RefCounted
## Saving a world scene from a headless tool without losing its uids: Godot's headless save drops
## the scene's own uid and its external resources' uids; `save` puts them back from the file as it
## was (and a script's from its .uid file). Writes are retried: on Windows a file just written can
## stay locked for a moment (virus scan, indexing), which fails a save with "Can't open".

## How many times a write is tried, and the wait between tries (ms).
const TRIES := 10
const RETRY_MS := 300


## Packs `root` into `path` and restores the uids `before` (the file's text before) had. OK or the
## error.
static func save(root: Node, path: String, before: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return err
	for attempt in TRIES:
		err = ResourceSaver.save(packed, path)
		if err == OK:
			break
		OS.delay_msec(RETRY_MS)
	if err == OK:
		err = restore_uids(path, before)
	return err


static func restore_uids(path: String, before: String) -> Error:
	var uids := {}
	var with_uid := RegEx.create_from_string("\\[ext_resource type=\"([^\"]+)\" uid=\"([^\"]+)\" path=\"([^\"]+)\" id=\"([^\"]+)\"\\]")
	for found in with_uid.search_all(before):
		uids[found.get_string(1) + "|" + found.get_string(3)] = found.get_string(2)
	var text := FileAccess.get_file_as_string(path)
	var bare := RegEx.create_from_string("\\[ext_resource type=\"([^\"]+)\" path=\"([^\"]+)\" id=\"([^\"]+)\"\\]")
	var matches := bare.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var found := matches[i]
		var uid: Variant = uids.get(found.get_string(1) + "|" + found.get_string(2))
		if uid == null and found.get_string(2).ends_with(".gd") and FileAccess.file_exists(found.get_string(2) + ".uid"):
			uid = FileAccess.get_file_as_string(found.get_string(2) + ".uid").strip_edges()
		if uid != null:
			text = text.substr(0, found.get_start()) + "[ext_resource type=\"%s\" uid=\"%s\" path=\"%s\" id=\"%s\"]" % [
					found.get_string(1), uid, found.get_string(2), found.get_string(3)] + text.substr(found.get_end())
	var own := RegEx.create_from_string("^\\[gd_scene [^\\]]*uid=\"([^\"]+)\"").search(before)
	var header := text.get_slice("\n", 0)
	if own != null and header.begins_with("[gd_scene") and header.find("uid=") < 0:
		text = header.trim_suffix("]") + " uid=\"%s\"]" % own.get_string(1) + text.substr(header.length())
	return write_text(path, text)


## Writes `text` to `path`, retrying while the file is locked. OK or the last error.
static func write_text(path: String, text: String) -> Error:
	for attempt in TRIES:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
			return OK
		OS.delay_msec(RETRY_MS)
	return FileAccess.get_open_error()

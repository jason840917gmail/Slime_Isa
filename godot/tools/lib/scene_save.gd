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


## `text` (a scene Godot just saved) written as the scene's file `before` was, so a scene saved again
## differs only where it changed: the external resources keep their ids (Godot makes new ones for a
## scene saved from another file) and their uids, sorted as Godot sorts them; the sub-resources keep
## their ids (by the node property that uses them); every node keeps its unique_id (by its path; none
## when it had none); the scene keeps its uid; the lines end as most of before's do (CRLF or LF; a stray CR is dropped).
static func match_saved(text: String, before: String) -> String:
	text = text.replace("\r", "")
	var old := before.replace("\r", "")
	var declared := RegEx.create_from_string("^\\[ext_resource type=\"([^\"]+)\"( uid=\"[^\"]+\")? path=\"([^\"]+)\" id=\"([^\"]+)\"\\]$")
	var old_ids := {}
	var old_uids := {}
	for line in old.split("\n"):
		var found := declared.search(line)
		if found != null:
			old_ids[found.get_string(3)] = found.get_string(4)
			old_uids[found.get_string(3)] = found.get_string(2)
	var lines := text.split("\n")
	var renames := {}
	# A resource the old file did not use gets an id made from its path and its first use, not
	# Godot's random one, so the same scene saved twice reads the same.
	var number := 0
	for id: String in old_ids.values():
		number = maxi(number, int(id.get_slice("_", 0)) if id.get_slice("_", 0).is_valid_int() else 0)
	var fresh := []
	for i in lines.size():
		var found := declared.search(lines[i])
		if found != null and not old_ids.has(found.get_string(3)):
			fresh.append([text.find("ExtResource(\"%s\")" % found.get_string(4)), found.get_string(3)])
	fresh.sort()
	var made := {}
	for entry: Array in fresh:
		number += 1
		made[entry[1]] = "%d_%s" % [number, str(entry[1]).md5_text().left(5)]
	var first := -1
	var last := -1
	for i in lines.size():
		var found := declared.search(lines[i])
		if found == null:
			continue
		first = i if first < 0 else first
		last = i
		var path := found.get_string(3)
		var id := found.get_string(4)
		var uid := found.get_string(2)
		if uid.is_empty() and not str(old_uids.get(path, "")).is_empty():
			uid = old_uids[path]
		var wanted: String = old_ids.get(path, made.get(path, id))
		renames[id] = wanted
		id = wanted
		lines[i] = "[ext_resource type=\"%s\"%s path=\"%s\" id=\"%s\"]" % [found.get_string(1), uid, path, id]
	if first >= 0:
		var block := Array(lines.slice(first, last + 1))
		block.sort_custom(func(a: String, b: String) -> bool:
			return a.get_slice(" id=\"", 1).naturalnocasecmp_to(b.get_slice(" id=\"", 1)) < 0)
		for i in block.size():
			lines[first + i] = block[i]
	text = "\n".join(lines)
	# The new ids replace the ones Godot made (two passes, so an id swapped with another stays right).
	var marks := {}
	for id: String in renames:
		if renames[id] != id:
			var mark := "\u0001%d\u0001" % marks.size()
			marks[mark] = renames[id]
			text = text.replace("ExtResource(\"%s\")" % id, "ExtResource(\"%s\")" % mark)
	for mark: String in marks:
		text = text.replace(mark, marks[mark])
	text = _keep_sub_ids(text, old)
	text = _keep_unique_ids(text, old)
	var own := RegEx.create_from_string("^\\[gd_scene [^\\]]*uid=\"([^\"]+)\"").search(old)
	var header := text.get_slice("\n", 0)
	if own != null and header.begins_with("[gd_scene") and header.find("uid=") < 0:
		text = header.trim_suffix("]") + " uid=\"%s\"]" % own.get_string(1) + text.substr(header.length())
	return text.replace("\n", "\r\n") if before.count("\r\n") * 2 > before.count("\n") else text


## `text` with each sub-resource's id as `old` had it for the one the same node property uses (Godot
## makes a new id when two scenes joined into one had the same one, and it stays after the cut); a
## sub-resource the old file did not have gets an id made from its type and its first use.
static func _keep_sub_ids(text: String, old: String) -> String:
	var was := _sub_uses(old)
	var now := _sub_uses(text)
	var old_ids := {}
	for key: String in was:
		old_ids[was[key]] = true
	var types := {}
	for line in text.split("\n"):
		if line.begins_with("[sub_resource type=\""):
			types[line.get_slice(" id=\"", 1).get_slice("\"", 0)] = line.get_slice("\"", 1)
	var renames := {}
	for key: String in now:
		if renames.has(now[key]):
			continue
		if was.has(key):
			if was[key] != now[key]:
				renames[now[key]] = was[key]
		elif not old_ids.has(now[key]) and types.has(now[key]):
			renames[now[key]] = "%s_%s" % [types[now[key]], key.md5_text().left(5)]
	# An old id that the new text gives another sub-resource (not renamed itself) would clash.
	for id: String in renames.keys():
		if not renames.has(renames[id]) and text.contains("SubResource(\"%s\")" % renames[id]):
			renames.erase(id)
	var marks := {}
	for id: String in renames:
		var mark := "\u0002%d\u0002" % marks.size()
		marks[mark] = renames[id]
		text = text.replace("SubResource(\"%s\")" % id, "SubResource(\"%s\")" % mark)
		text = text.replace(" id=\"%s\"]" % id, " id=\"%s\"]" % mark)
	for mark: String in marks:
		text = text.replace(mark, marks[mark])
	return text


## Where each sub-resource is used in a scene's text: {"<node path>|<property>": its id}.
static func _sub_uses(text: String) -> Dictionary:
	var uses := {}
	var at := ""
	for line in text.split("\n"):
		if line.begins_with("["):
			at = node_path(line)
		elif not at.is_empty() and line.contains(" = SubResource(\""):
			uses[at + "|" + line.get_slice(" = ", 0)] = line.get_slice("SubResource(\"", 1).get_slice("\")", 0)
	return uses


## `text` with each node's unique_id as `old` had it for the node at the same path; a node `old`
## added without one (written into the file by a script or by hand) stays without: Godot gives such
## a node a new random id on every load, so the same scene saved twice would never read the same.
static func _keep_unique_ids(text: String, old: String) -> String:
	var ids := {}
	var bare := {}
	for line in old.split("\n"):
		var path := node_path(line)
		if path == "":
			continue
		if line.contains(" unique_id="):
			ids[path] = line.get_slice(" unique_id=", 1).get_slice(" ", 0).get_slice("]", 0)
		elif line.contains(" type=\"") or line.contains(" instance="):
			bare[path] = true
	var lines := text.split("\n")
	for i in lines.size():
		var path := node_path(lines[i])
		if path == "" or not lines[i].contains(" unique_id="):
			continue
		var id := lines[i].get_slice(" unique_id=", 1).get_slice(" ", 0).get_slice("]", 0)
		if ids.has(path):
			if id != ids[path]:
				lines[i] = lines[i].replace(" unique_id=%s" % id, " unique_id=%s" % ids[path])
		elif bare.has(path):
			lines[i] = lines[i].replace(" unique_id=%s" % id, "")
	return "\n".join(lines)


## The path of the node a `[node ...]` line declares ("." for the root), "" for any other line.
static func node_path(line: String) -> String:
	if not line.begins_with("[node name=\""):
		return ""
	var node_name := line.get_slice("\"", 1)
	if not line.contains(" parent=\""):
		return "."
	var parent := line.get_slice(" parent=\"", 1).get_slice("\"", 0)
	return node_name if parent == "." else parent + "/" + node_name


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

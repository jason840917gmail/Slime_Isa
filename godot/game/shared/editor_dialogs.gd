extends RefCounted
## The notices and questions the editor tools pop over the editor (EditorInterface's
## popup_dialog_centered), freed when they close.
##
## A dialog must never be freed while it holds the editor's progress popup. From Godot 4.4 that
## popup (ProgressDialog) moves itself into the last exclusive window open when a task starts (a
## scene save, the "Scanning actions..." after files change on disk) and stays there after the task;
## a dialog freed with it inside frees it too, and the editor's next save or scan crashes
## (Node::add_child on the freed popup; the editor crashes of 2026-11-01 to 11-11). `close` moves it
## back to the editor's window first. No editor class is named, so the scripts that use this still
## load in exported builds.
##
## Owner: shared.

## The editor's progress popup, by its class name (an editor class GDScript cannot name).
const PROGRESS_CLASS := "ProgressDialog"


## Pops `dialog` centred over the editor (`editor`: the EditorInterface) and frees it (with `close`)
## when it is confirmed, cancelled or closed.
static func popup(editor: Object, dialog: AcceptDialog) -> void:
	dialog.confirmed.connect(func() -> void: close(dialog))
	dialog.canceled.connect(func() -> void: close(dialog))
	editor.call(&"popup_dialog_centered", dialog)


## A notice over the editor: `text` under `title`, with an OK button.
static func notice(editor: Object, title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	popup(editor, dialog)


## Frees `dialog` (shown over the editor), the editor's progress popup moved out of it first.
static func close(dialog: Window) -> void:
	if not is_instance_valid(dialog) or dialog.is_queued_for_deletion():
		return
	if dialog.is_inside_tree():
		var home := dialog.get_tree().root
		for progress: Node in progress_popups(dialog):
			progress.reparent(home, false)
	dialog.queue_free()


## The editor's progress popups inside `node`, at any depth (internal children too).
static func progress_popups(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children(true):
		if child.get_class() == PROGRESS_CLASS:
			out.append(child)
		else:
			out.append_array(progress_popups(child))
	return out

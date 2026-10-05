extends "res://game/shell/shell_menu.gd"
## The save slots window (Phaser `features/shell/SaveSlotsSurfacePort.ts`, `ui/save-slots.scene.json`):
## three named slots ("Slot 1" to "Slot 3" = RunState slots 1-3) and, when loading, the recovery
## autosave (slot 0) first. A shell window on the Shell's layer (surface "save-slots", pauses the
## game, Escape closes it), mounted once by `install(shell)`, which also registers the Shell's
## "save" and "load" actions: the pause menu's Save opens it to save, Load (pause menu, title, game
## over) opens it to load.
##
## Save mode: an empty slot saves at once ("Saved to Slot 2."); a slot that holds a save asks first
## ("Slot 2 already holds a save. Overwrite it?" with Overwrite / Cancel). Load mode: an empty slot
## is disabled; a slot loads its run: in a running game main rebuilds the saved world in place
## (`Main.load_run`), from the title the run is installed and main.tscn starts. A slot whose file
## cannot be read says why instead of "Empty".
##
## Slot labels: "Slot 1  ·  Slimeshire Meadow  ·  0:42 played  ·  2026-10-05 21:14" (two spaces each
## side of the dot); the autosave: "Autosave (latest)  ·  <place>  ·  <played>".
##
## Owner: saves.

const Services := preload("res://game/shared/services.gd")
const AreaTitles := preload("res://game/shell/area_titles.gd")

const SCENE_PATH := "res://game/saves/save_slots_menu.tscn"
const SLOT_COUNT := 3
const AUTOSAVE_SLOT := 0
const MAIN_SCENE := "res://game/main.tscn"
const WORLD_MAIN_GROUP := &"world_main"
const SEPARATOR := "  ·  "
const SAVE_FAILED := "Could not save."
const LOAD_FAILED := "That save could not be loaded."

## "save" or "load".
var mode: StringName = &"save"
## The Shell (closing its windows, changing scenes); set by `install`.
var shell: Node

var _confirm_slot: int = 0
var _status: String = ""

@onready var _title: Label = $Panel/Title
@onready var _autosave: Button = $Panel/Autosave
@onready var _status_label: Label = $Panel/Status
@onready var _confirm: Button = $Panel/Confirm
@onready var _cancel: Button = $Panel/Cancel
@onready var _close: Button = $Panel/Close


## Mounts the window on `shell` (once) and registers the "save" / "load" actions; null when the
## Shell cannot mount feature windows.
static func install(shell_node: Node) -> Node:
	if shell_node == null or not shell_node.has_method(&"mount_menu"):
		return null
	for child: Node in shell_node.find_children("*", "", true, false):
		if child.scene_file_path == SCENE_PATH:
			return child
	var menu: Node = shell_node.call(&"mount_menu", load(SCENE_PATH))
	if menu == null:
		return null
	menu.set(&"shell", shell_node)
	shell_node.call(&"set_action", &"save", Callable(menu, &"open_for").bind(&"save"))
	shell_node.call(&"set_action", &"load", Callable(menu, &"open_for").bind(&"load"))
	return menu


func _ready() -> void:
	super()
	for slot in range(1, SLOT_COUNT + 1):
		slot_button(slot).pressed.connect(_on_slot.bind(slot))
	_autosave.pressed.connect(_on_autosave)
	_confirm.pressed.connect(_on_confirm)
	_cancel.pressed.connect(_on_cancel)
	_close.pressed.connect(close)


## Opens the window to save or to load (`openFor`); refreshes it when already open.
func open_for(new_mode: StringName) -> void:
	mode = new_mode
	_confirm_slot = 0
	_status = ""
	if is_open():
		refresh()
	else:
		open()


func slot_button(slot: int) -> Button:
	return get_node("Panel/Slot%d" % slot) as Button


func status_text() -> String:
	return _status_label.text


func refresh() -> void:
	var run := Services.run()
	var confirming := _confirm_slot > 0
	_title.text = "Save game" if mode == &"save" else "Load game"
	_status_label.text = ("%s already holds a save. Overwrite it?" % slot_name(_confirm_slot)) if confirming else _status
	_confirm.visible = confirming
	_cancel.visible = confirming
	var autosave := _slot_record(AUTOSAVE_SLOT) if mode == &"load" else {}
	_autosave.visible = not autosave.is_empty()
	_autosave.disabled = autosave.is_empty()
	_autosave.text = (SEPARATOR.join(["Autosave (latest)", _place(autosave), play_time_text(_play_time(autosave))])) \
		if not autosave.is_empty() else "Autosave  ·  None yet"
	for slot in range(1, SLOT_COUNT + 1):
		var button := slot_button(slot)
		var inspected: Dictionary = run.inspect_slot(slot) if run != null else {"exists": false, "record": {}, "problem": ""}
		var record: Dictionary = inspected["record"]
		if not record.is_empty():
			button.text = SEPARATOR.join([slot_name(slot), _place(record), play_time_text(_play_time(record)), _when(record)])
		elif bool(inspected["exists"]):
			button.text = "%s%sCan't be loaded: %s" % [slot_name(slot), SEPARATOR, inspected["problem"]]
		else:
			button.text = "%s%sEmpty" % [slot_name(slot), SEPARATOR]
		button.disabled = mode == &"load" and record.is_empty()


static func slot_name(slot: int) -> String:
	return "Slot %d" % slot


## `formatPlayTime`: "h:mm played".
static func play_time_text(ms: float) -> String:
	var minutes := floori(maxf(0.0, ms) / 60000.0)
	return "%d:%02d played" % [floori(minutes / 60.0), minutes % 60]


func _on_slot(slot: int) -> void:
	var run := Services.run()
	if run == null or slot < 1 or slot > SLOT_COUNT:
		return
	var record := _slot_record(slot)
	if mode == &"save":
		if not record.is_empty():
			_confirm_slot = slot
			refresh()
			return
		_report(run.save_slot(slot), slot)
		return
	if not record.is_empty():
		_load(slot)


func _on_autosave() -> void:
	if mode == &"load" and not _slot_record(AUTOSAVE_SLOT).is_empty():
		_load(AUTOSAVE_SLOT)


func _on_confirm() -> void:
	var slot := _confirm_slot
	_confirm_slot = 0
	var run := Services.run()
	if slot > 0 and run != null:
		_report(run.save_slot(slot), slot)
	else:
		refresh()


func _on_cancel() -> void:
	_confirm_slot = 0
	refresh()


func _report(saved: bool, slot: int) -> void:
	_status = ("Saved to %s." % slot_name(slot)) if saved else SAVE_FAILED
	refresh()


## In a running game main rebuilds the saved world in place; from the title the run is installed
## and main.tscn starts in it.
func _load(slot: int) -> void:
	var run := Services.run()
	if run == null:
		return
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	if main != null and main.has_method(&"load_run"):
		_close_shell_windows()
		if not bool(main.call(&"load_run", slot)):
			open_for(&"load")
			_status = LOAD_FAILED
			refresh()
		return
	if not run.load_slot(slot):
		_status = LOAD_FAILED
		refresh()
		return
	_close_shell_windows()
	if shell != null and shell.has_method(&"go_to_scene"):
		shell.call(&"go_to_scene", MAIN_SCENE)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)


func _close_shell_windows() -> void:
	if shell == null or not shell.has_method(&"top_menu"):
		close()
		return
	var guard := 16
	var top: Node = shell.call(&"top_menu")
	while top != null and guard > 0:
		guard -= 1
		top.call(&"close")
		top = shell.call(&"top_menu")


func _slot_record(slot: int) -> Dictionary:
	var run := Services.run()
	return run.inspect_slot(slot)["record"] if run != null else {}


static func _place(record: Dictionary) -> String:
	var data: Dictionary = record.get("data", {})
	var location: Dictionary = data.get("location", {})
	return AreaTitles.area_name(str(location.get("map_id", "")))


static func _play_time(record: Dictionary) -> float:
	return float((record.get("data", {}) as Dictionary).get("play_time_ms", 0.0))


## The save time in local time, "YYYY-MM-DD HH:MM".
static func _when(record: Dictionary) -> String:
	var unix := floori(float(record.get("saved_at", 0.0)) / 1000.0) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var parts := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d %02d:%02d" % [parts["year"], parts["month"], parts["day"], parts["hour"], parts["minute"]]

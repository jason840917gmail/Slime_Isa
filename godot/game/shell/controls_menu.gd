extends "res://game/shell/shell_menu.gd"
## The read-only controls list, opened from Settings (Phaser `features/shell/ControlsSurfacePort.ts`,
## `ui/controls.scene.json`). Rebuilt from the InputMap each time it opens (ControlLabels), so it
## never disagrees with the bindings. One row per control (key in bold accent, then what it does);
## unlike the Phaser window, a wrapped description keeps its key on the same row.
##
## Owner: shell.

const ControlLabels := preload("res://game/shell/control_labels.gd")

## The key column; the rest of the row is the description, wrapping under itself.
const KEY_COLUMN_WIDTH := 124.0
## One size under the theme's 14 px so the fifteen rows fit without scrolling.
const LIST_FONT_SIZE := 13

@onready var rows: GridContainer = $Panel/Margin/Rows/Scroll/List
@onready var close_button: Button = $Panel/Margin/Rows/Bottom/Close


func _ready() -> void:
	super()
	close_button.pressed.connect(close)


func refresh() -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for row: PackedStringArray in ControlLabels.control_rows():
		var key := Label.new()
		key.theme_type_variation = &"KeyLabel"
		key.text = row[0]
		key.custom_minimum_size = Vector2(KEY_COLUMN_WIDTH, 0.0)
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		key.add_theme_font_size_override(&"font_size", LIST_FONT_SIZE)
		rows.add_child(key)
		var action := Label.new()
		action.text = row[1]
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		action.custom_minimum_size = Vector2(200.0, 0.0)
		action.add_theme_font_size_override(&"font_size", LIST_FONT_SIZE)
		rows.add_child(action)

extends ShellMenu
class_name AbilityCarousel
## The ability carousel (throw combat, owner's request 2026-10-23): E opens it instead of stepping
## the Ability Box. A quick menu: every learned box ability as a big card in a matrix, and nothing
## else. The game pauses while it is open (Shell, `shell:` pause reason). The chosen ability is lit
## to start; the arrows move the lit card, Space or Enter makes it the box's choice and closes the
## window, and Escape closes it with no change (Shell routes Escape to the top window).
## Shell.open_ability_carousel opens it.
##
## The arrows are read in `_input`, before the player's `_unhandled_input`: the player's movement
## actions are the arrow keys, and it would take them first. While the window is open the arrows,
## Space and Enter are consumed here, presses and releases both.
##
## Owner: Ability Box and HUD.

const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const BodyCards := preload("res://game/ui/body_cards.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const SURFACE_ID := &"ability_carousel"
## Cards per row of the matrix, one card's size (screen pixels) and the gap between cards.
const COLUMNS := 4
const CARD_SIZE := Vector2(184.0, 176.0)
const CARD_GAP := 18
const ICON_SIZE := 96.0
const PANEL_RADIUS := 14
const PANEL_MARGIN := 16
const CARD_RADIUS := 12
const CARD_MARGIN := 10
const BORDER_WIDTH := 2
const BORDER_WIDTH_LIT := 4
const UNLIT_ALPHA := 0.55
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const TITLE_TEXT := "Abilities"
const HINT_TEXT := "Arrows: choose     Space or Enter: use it     Esc: close"
const EMPTY_TEXT := "No abilities yet. Learn one and it goes in the box."
## The arrows' steps through the matrix (column, row).
const STEPS := {
	&"ui_left": Vector2i(-1, 0),
	&"ui_right": Vector2i(1, 0),
	&"ui_up": Vector2i(0, -1),
	&"ui_down": Vector2i(0, 1),
}

var _ids: Array[StringName] = []
var _index: int = 0
var _cards: Array[PanelContainer] = []
var _matrix_panel: PanelContainer
var _grid: GridContainer
var _empty_label: Label


func _init() -> void:
	surface_id = SURFACE_ID


func _ready() -> void:
	super()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(column)

	var title := _label(UiTokens.FONT_SIZE_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = TITLE_TEXT
	column.add_child(title)

	_matrix_panel = PanelContainer.new()
	_matrix_panel.add_theme_stylebox_override(&"panel", _panel_style())
	_matrix_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_matrix_panel)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", CARD_GAP)
	_grid.add_theme_constant_override("v_separation", CARD_GAP)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_matrix_panel.add_child(_grid)

	_empty_label = _label(UiTokens.FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_empty_label.text = EMPTY_TEXT
	column.add_child(_empty_label)

	var hint := _label(UiTokens.FONT_SIZE_SMALL, HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = HINT_TEXT
	hint.modulate = UiTokens.TEXT_MUTED
	column.add_child(hint)


## Fills the matrix from the learned box abilities and lights the chosen one.
func refresh() -> void:
	var player := BodyCards.world_player()
	_ids = AbilityBox.box_ids(player)
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	for id: StringName in _ids:
		var card := _make_card(id)
		_grid.add_child(card)
		_cards.append(card)
	_matrix_panel.visible = not _ids.is_empty()
	_empty_label.visible = _ids.is_empty()
	_index = maxi(0, _ids.find(AbilityBox.selected(player)))
	_highlight()


## Runs before the player's `_unhandled_input` (see the class notes): while open, the arrows, Space
## and Enter are this window's, presses and releases both.
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action(&"ui_accept"):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			_choose()
		return
	for action: StringName in STEPS:
		if event.is_action(action):
			get_viewport().set_input_as_handled()
			if event.is_pressed():
				_move(STEPS[action])
			return


## One step through the matrix: the column and the row move, clamped to the matrix (the last row may
## be short, so the step stops at the last ability).
func _move(step: Vector2i) -> void:
	if _ids.is_empty():
		return
	var column := clampi(_index % COLUMNS + step.x, 0, COLUMNS - 1)
	var last_row := floori((_ids.size() - 1) / float(COLUMNS))
	var row := clampi(floori(_index / float(COLUMNS)) + step.y, 0, last_row)
	_index = mini(row * COLUMNS + column, _ids.size() - 1)
	_highlight()


## The box's choice becomes the lit ability; the window closes either way (nothing to choose when
## no ability is learned).
func _choose() -> void:
	var player := BodyCards.world_player()
	if player != null and not _ids.is_empty():
		AbilityBox.choose(player, _ids[_index])
	close()


## A card: the ability's icon and its name, nothing else.
func _make_card(id: StringName) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var icon := TextureRect.new()
	icon.texture = BodyCards.ability_icon(id)
	icon.custom_minimum_size = Vector2.ONE * ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)

	var name_label := _label(UiTokens.FONT_SIZE_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.text = AbilityBox.title(id)
	column.add_child(name_label)
	return card


## Lights the lit card; the others are dimmed.
func _highlight() -> void:
	for i: int in _cards.size():
		var lit := i == _index
		_cards[i].add_theme_stylebox_override(&"panel", _card_style(lit))
		_cards[i].modulate.a = 1.0 if lit else UNLIT_ALPHA


static func _card_style(lit: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.SURFACE_RAISED
	style.border_color = UiTokens.ACCENT if lit else UiTokens.BORDER
	style.set_border_width_all(BORDER_WIDTH_LIT if lit else BORDER_WIDTH)
	style.set_corner_radius_all(CARD_RADIUS)
	style.set_content_margin_all(CARD_MARGIN)
	return style


static func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.SURFACE_BASE
	style.border_color = UiTokens.BORDER
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(PANEL_RADIUS)
	style.set_content_margin_all(PANEL_MARGIN)
	return style


static func _label(font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label

extends RefCounted
## Small look helpers for game windows built in code (the quest journal, the chest window): the
## per-window details Phaser's CSS sets on top of the theme roles (corner radii, line heights).
##
## Owner: UI (game windows).

const BUTTON_STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]


## Gives `control` copies of its theme's button boxes with `radius` corners. Call it once the
## control is in the tree (its theme variation resolves then).
static func round_corners(control: Control, radius: int) -> void:
	for state: StringName in BUTTON_STATES:
		var box := control.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			var rounded := (box as StyleBoxFlat).duplicate() as StyleBoxFlat
			rounded.set_corner_radius_all(radius)
			control.add_theme_stylebox_override(state, rounded)


## Sets `line_spacing` so lines of `font_size` px sit `pitch` px apart (a CSS line-height).
static func set_line_pitch(label: Label, font_size: int, pitch: float) -> void:
	var font := label.get_theme_font(&"font")
	if font != null:
		label.add_theme_constant_override(&"line_spacing", maxi(0, roundi(pitch - font.get_height(font_size))))


## The bold font of modal window buttons (theme `BoldButton`), null when the theme has none.
static func bold_font(control: Control) -> Font:
	return control.get_theme_font(&"font", &"BoldButton")

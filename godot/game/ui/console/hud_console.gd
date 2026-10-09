extends Control
class_name HudConsole
## The HUD console along the bottom of the screen (roadmap 4.12; the approved mockup is
## docs/design/2026-10-07-hud-console-mockup.md): 128 units (2 tiles) tall, centred, under the
## 16 x 14 tile play area (the WorldCamera's `bottom_inset`, set by main.gd from HEIGHT).
##
## Left to right: the minimap (MapUi's, docked here by hud.gd), the life orb, the weapon in hand
## (WeaponHotbar, placed by hud.gd), the ability buttons (AbilityBar, placed by hud.gd; as many as
## `ability_definitions.gd` BAR_SLOTS lists), the energy orb (with the Gulp form's badge while the
## slime is in a form) and the menu buttons (bag, journal, map, pause menu). The weapon and the
## abilities sit on one wooden bar whose ends tuck behind the orbs; a soft shade under the console
## separates it from the ground. `layout(viewport, ability_count)` gives every rect, in canvas units.
##
## Built by hud.gd as a full-screen child of the HUD layer (it lays itself out on every resize);
## only the menu buttons take the mouse.
##
## Owner: UI (HUD console).

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const ConsoleStyle := preload("res://game/ui/console/console_style.gd")
const GooOrb := preload("res://game/ui/console/goo_orb.gd")

const HEIGHT := 128.0
## The orbs: ring width (GooOrb.RING_SIZE), their centres this far below the console's top.
const ORB_D := 144.0
const ORB_CY := 56.0
## The bar's dark panel (it holds the slots): its centre below the console's top and its height.
const BAR_CY := 66.0
const PANEL_H := 62.0
## console-bar.webp (scripts/art/pack-hud-console.py): 256 px tall, the panel's rows 70-185, the
## unstretched ends 216 px wide; the bar reaches this far past each orb's centre.
const BAR_TEXTURE := "res://asset/UI/hud-console/console-bar.webp"
const BAR_TEXTURE_HEIGHT := 256.0
const BAR_PANEL_TOP := 70.0
const BAR_PANEL_BOTTOM := 185.0
const BAR_END_PX := 216
const BAR_TUCK := 20.0
const WEAPON_SLOT := 54.0
const ABILITY_SLOT := 46.0
const SLOT_GAP := 4.0
## Between the weapon and the abilities, and between an orb's ring and the nearest slot.
const GROUP_GAP := 18.0
const BAR_MARGIN := 14.0
## The minimap is never bigger than the orbs (owner, 2026-10-08).
const MINIMAP := 128.0
const BUTTON := 52.0
const BUTTON_GAP := 4.0
const BUTTONS := BUTTON * 2.0 + BUTTON_GAP
const SIDE_GAP := 8.0
## The shade starts this far above the console and darkens to SHADE_ALPHA at the bottom edge.
const SHADE_RISE := 24.0
const SHADE_ALPHA := 0.59
const SHADE_COLOR := Color(0.04, 0.055, 0.04)
const MENU_ICON := "res://asset/UI/hud-console/menu-%s.webp"
## The menu buttons: icon, action whose key labels it, tooltip.
const MENU_BUTTONS := [
	[&"bag", &"menu", "Bag"],
	[&"journal", &"journal", "Journal"],
	[&"map", &"map", "World map"],
	[&"menu", &"pause", "Menu"],
]
const MENU_WINDOWS_GROUP := &"menu_windows"
const MAP_UI_GROUP := &"map_ui"
## The Gulp form's badge on the energy orb (the 3 x 1 form sheet, `current_form()["badge_frame"]`).
const FORM_SHEET := "res://asset/UI/ui-gulp-form-icons-3x1.webp"
const FORM_CELL := 128
const FORM_BADGE := 40.0
const FORM_BADGE_OFFSET := Vector2(48.0, -50.0)
## Goo colours (top, bottom, rim) of the life and energy orbs.
const LIFE_COLORS := [Color("#ff8078"), Color("#961830"), Color("#ffc4ba")]
const ENERGY_COLORS := [Color("#ffe080"), Color("#c87412"), Color("#fff2c4")]

var life_orb: GooOrb
var energy_orb: GooOrb
var menu_buttons: Array[Button] = []
## The player whose Gulp form the badge follows (set by hud.gd).
var player: Node

var _shade: TextureRect
var _bar: NinePatchRect
var _form_badge: TextureRect
var _key_badges: Array[Label] = []
var _ability_count := 5


func _init() -> void:
	name = "HudConsole"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if theme == null:
		theme = UiTokens.theme()
	_build()
	get_viewport().size_changed.connect(relayout)
	relayout()


## How many ability buttons the bar holds (hud.gd, from the ability bar).
func set_ability_count(count: int) -> void:
	_ability_count = maxi(0, count)
	relayout()


## Every rect of the console for a `viewport` (canvas units) and `ability_count` buttons:
## {"console", "shade", "bar", "weapon", "abilities", "life_orb", "energy_orb", "minimap",
## "buttons"}. The console is centred on the bottom edge.
static func layout(viewport: Vector2, ability_count: int) -> Dictionary:
	var abilities_w := ability_count * ABILITY_SLOT + maxf(0.0, ability_count - 1.0) * SLOT_GAP
	var slots_w := WEAPON_SLOT + (GROUP_GAP + abilities_w if ability_count > 0 else 0.0)
	var orb_dx := (slots_w + 2.0 * BAR_MARGIN + ORB_D) * 0.5
	var cx := viewport.x * 0.5
	var top := viewport.y - HEIGHT
	var bar_cy := top + BAR_CY
	var orb_size := GooOrb.RING_SIZE
	var left := cx - orb_dx - ORB_D * 0.5 - SIDE_GAP - MINIMAP
	var right := cx + orb_dx + ORB_D * 0.5 + SIDE_GAP + BUTTONS
	var bar_scale := PANEL_H / (BAR_PANEL_BOTTOM - BAR_PANEL_TOP)
	var bar_h := BAR_TEXTURE_HEIGHT * bar_scale
	var bar_top := bar_cy - (BAR_PANEL_TOP + BAR_PANEL_BOTTOM) * 0.5 * bar_scale
	var slots_left := cx - slots_w * 0.5
	return {
		"console": Rect2(left, top, right - left, HEIGHT),
		"shade": Rect2(0.0, top - SHADE_RISE, viewport.x, HEIGHT + SHADE_RISE),
		"bar": Rect2(cx - orb_dx - BAR_TUCK, bar_top, (orb_dx + BAR_TUCK) * 2.0, bar_h),
		"weapon": Rect2(slots_left, bar_cy - WEAPON_SLOT * 0.5, WEAPON_SLOT, WEAPON_SLOT),
		"abilities": Rect2(slots_left + WEAPON_SLOT + GROUP_GAP, bar_cy - ABILITY_SLOT * 0.5, abilities_w, ABILITY_SLOT),
		"life_orb": Rect2(Vector2(cx - orb_dx, top + ORB_CY) - orb_size * 0.5, orb_size),
		"energy_orb": Rect2(Vector2(cx + orb_dx, top + ORB_CY) - orb_size * 0.5, orb_size),
		"minimap": Rect2(left, bar_cy - MINIMAP * 0.5, MINIMAP, MINIMAP),
		"buttons": Rect2(right - BUTTONS, bar_cy - BUTTONS * 0.5, BUTTONS, BUTTONS),
	}


## This frame's rects (layout() for the current viewport).
func rects() -> Dictionary:
	return layout(get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1024.0, 1024.0), _ability_count)


func relayout() -> void:
	if not is_inside_tree() or _bar == null:
		return
	var r := rects()
	var shade: Rect2 = r["shade"]
	_shade.position = shade.position
	_shade.size = shade.size
	var bar: Rect2 = r["bar"]
	var bar_scale := bar.size.y / BAR_TEXTURE_HEIGHT
	_bar.position = bar.position
	_bar.scale = Vector2(bar_scale, bar_scale)
	_bar.size = bar.size / bar_scale
	for pair: Array in [[life_orb, r["life_orb"]], [energy_orb, r["energy_orb"]]]:
		var orb: GooOrb = pair[0]
		orb.position = (pair[1] as Rect2).position
	var buttons: Rect2 = r["buttons"]
	for index in menu_buttons.size():
		menu_buttons[index].position = buttons.position + Vector2(index % 2, floori(index / 2.0)) * (BUTTON + BUTTON_GAP)
	_form_badge.position = energy_orb.position + GooOrb.HOLE_CENTRE + FORM_BADGE_OFFSET - Vector2.ONE * FORM_BADGE * 0.5
	_refresh_keys()


func _process(_delta: float) -> void:
	_update_form_badge()


func _build() -> void:
	_shade = TextureRect.new()
	_shade.name = "Shade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(SHADE_COLOR, 0.0))
	gradient.set_color(1, Color(SHADE_COLOR, SHADE_ALPHA))
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.fill_from = Vector2(0.5, 0.0)
	shade_texture.fill_to = Vector2(0.5, 1.0)
	shade_texture.width = 4
	shade_texture.height = 64
	_shade.texture = shade_texture
	add_child(_shade)

	_bar = NinePatchRect.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BAR_TEXTURE):
		_bar.texture = load(BAR_TEXTURE) as Texture2D
	_bar.patch_margin_left = BAR_END_PX
	_bar.patch_margin_right = BAR_END_PX
	add_child(_bar)

	life_orb = GooOrb.new()
	life_orb.name = "LifeOrb"
	add_child(life_orb)
	life_orb.configure(LIFE_COLORS[0], LIFE_COLORS[1], LIFE_COLORS[2], 3.0)
	energy_orb = GooOrb.new()
	energy_orb.name = "EnergyOrb"
	add_child(energy_orb)
	energy_orb.configure(ENERGY_COLORS[0], ENERGY_COLORS[1], ENERGY_COLORS[2], 7.0)

	_form_badge = TextureRect.new()
	_form_badge.name = "FormBadge"
	_form_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_form_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_form_badge.size = Vector2.ONE * FORM_BADGE
	_form_badge.visible = false
	if ResourceLoader.exists(FORM_SHEET):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(FORM_SHEET) as Texture2D
		atlas.region = Rect2(0, 0, FORM_CELL, FORM_CELL)
		_form_badge.texture = atlas
	add_child(_form_badge)

	for entry: Array in MENU_BUTTONS:
		var button := Button.new()
		button.name = "%sButton" % str(entry[0]).capitalize()
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.size = Vector2(BUTTON, BUTTON)
		button.tooltip_text = str(entry[2])
		ConsoleStyle.style_slot_button(button)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(BUTTON * 0.17, BUTTON * 0.13)
		icon.size = Vector2(BUTTON * 0.66, BUTTON * 0.66)
		var icon_path := MENU_ICON % str(entry[0])
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path) as Texture2D
		button.add_child(icon)
		var key := ConsoleStyle.make_key_badge()
		key.set_meta(&"action", entry[1])
		button.add_child(key)
		_key_badges.append(key)
		button.pressed.connect(_on_menu_button.bind(entry[0]))
		add_child(button)
		menu_buttons.append(button)


## A key badge in the bottom-right corner of each menu button, read from the InputMap.
func _refresh_keys() -> void:
	for key: Label in _key_badges:
		ConsoleStyle.place_key(key, ControlLabels.control_label(key.get_meta(&"action")), Vector2(BUTTON, BUTTON))


func _update_form_badge() -> void:
	var form: Dictionary = {}
	if player != null and is_instance_valid(player) and player.has_method(&"current_form"):
		form = player.call(&"current_form")
	var in_form := not form.is_empty() and str(form.get("id", "")) != ""
	_form_badge.visible = in_form and _form_badge.texture != null
	if _form_badge.visible:
		(_form_badge.texture as AtlasTexture).region = Rect2(int(form.get("badge_frame", 0)) * FORM_CELL, 0, FORM_CELL, FORM_CELL)


func _on_menu_button(id: StringName) -> void:
	match id:
		&"bag":
			var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP)
			if menu != null:
				menu.call(&"toggle_menu")
		&"journal":
			var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP)
			if menu != null:
				menu.call(&"toggle_journal")
		&"map":
			var map_ui := get_tree().get_first_node_in_group(MAP_UI_GROUP)
			if map_ui == null:
				return
			if bool(map_ui.call(&"is_world_map_open")) or bool(map_ui.call(&"can_open_from_key")):
				map_ui.call(&"toggle_world_map")
		&"menu":
			var shell := Services.shell()
			if shell != null:
				shell.call(&"open_pause")


extends Control
## The weapon in hand on the HUD console (roadmap 4.12, docs/design/2026-10-07-hud-console-mockup.md;
## it replaced the four belt cells of Phaser's `WeaponHotbarSurfacePort.ts`, crafting spec 8.6, on
## 2026-10-08). One slot shows the weapon in hand (its name is the tooltip; "Empty" when the hand
## is empty), with the weapon scroll's key in its corner (E, `weapon_next`'s key). A click puts the
## next belt weapon in hand, like a scroll (InventoryActions.switch_weapon_slot: "<name> equipped",
## or "Finish the attack first" mid-swing) and plays the select cue; it never takes keyboard focus
## and never attacks.
##
## The carousel: when the weapon in hand changes, the belt's weapons appear in a row above the
## slot, the one now in hand in the middle with its name, its neighbours fading to the sides; the
## row slides in from the side the scroll went, holds, then fades away (presentation, real time).
##
## Built by hud.gd as a child of the HUD layer and placed on the console's weapon rect
## (HudConsole.layout); refreshes on RunState `inventory_changed`, `weapon_loadout_changed` and
## `weapon_equipped`. The model (`snapshot()`) still lists the four belt slots.
##
## Body-shapes rework mode (game/shapes/rework_mode.gd; body-shapes plan section 8.1, BODY_SHAPES.md
## "Ability Box and HUD"): the slot is the **Shape slot**. It shows the current shape (its icon,
## `BodyCards.shape_icon`, game/ui/body_cards.gd), E in its corner and its charge's energy cost in a
## chip at the top left; it is hidden until a second shape is learned (`slot_shown`, which the
## console's layout follows). A click takes the next learned shape (ShapeController.cycle). The
## carousel shows the learned shapes (their icons) when the shape changes. It follows the controller by polling (cheap: the shape and
## the learned list), and goes back to the belt as soon as the mode is off.
##
## Owner: crafting / inventory (UI); the rework's Shape slot: Ability Box and HUD.

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const SfxPlayer := preload("res://game/runtime/sfx_player.gd")
const ConsoleStyle := preload("res://game/ui/console/console_style.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const BodyCards := preload("res://game/ui/body_cards.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const SLOT_SIZE := 54.0
const ICON_SHARE := 0.8
const EMPTY_FONT_PX := 10
## The carousel: cell sizes, distance between cells, how far above the slot its centre is.
const CAROUSEL_CELL := 48.0
const CAROUSEL_SIDE_CELL := 40.0
const CAROUSEL_STEP := 54.0
const CAROUSEL_RISE := 84.0
const CAROUSEL_NAME_RISE := 42.0
## Opacity by distance from the middle (0, 1, 2).
const CAROUSEL_OPACITY: Array[float] = [1.0, 0.6, 0.25]
## Slide in, hold, fade out (ms, real time).
const SLIDE_MS := 160.0
const HOLD_MS := 900.0
const FADE_MS := 300.0
const BACKING_COLOR := Color(UiTokens.SURFACE_BASE, 0.82)
const INVENTORY_ACTIONS_GROUP := &"inventory_actions"
const SELECT_STREAM := "res://asset/audio/sfx/library/ui/hover.ogg"
const SELECT_VOLUME_DB := -1.9382
## Rework: the charge-cost chip's text colour (the energy orb's goo) and its shortfall colour.
const COST_CHIP_COLOR := Color("#ffe080")
const COST_SHORT_COLOR := UiTokens.WARNING

var slot: Button
var icon: TextureRect
var key_badge: Label
var carousel: Control
var select_sfx: AudioStreamPlayer
## Rework: the charge's energy cost, top left of the slot.
var cost_chip: Label
var _model: Dictionary = {}
var _in_hand: String = ""
## Carousel state: when it opened (-1 = closed), and the slide's direction (+1 from the right).
var _shown_at_ms: float = -1.0
var _slide_from: float = 0.0
## Rework: true while the slot shows the shape; the shape and learned list it last showed.
var _rework: bool = false
var _rework_signature: String = ""


func _init() -> void:
	name = "WeaponHotbar"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(SLOT_SIZE, SLOT_SIZE)


func _ready() -> void:
	if theme == null:
		theme = UiTokens.theme()
	slot = Button.new()
	slot.name = "Slot"
	slot.focus_mode = Control.FOCUS_NONE
	slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.clip_text = true
	slot.add_theme_font_size_override(&"font_size", EMPTY_FONT_PX)
	ConsoleStyle.style_slot_button(slot)
	slot.pressed.connect(_on_slot_pressed)
	add_child(slot)
	icon = TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var inset := SLOT_SIZE * (1.0 - ICON_SHARE) * 0.5
	icon.position = Vector2(inset, inset)
	icon.size = Vector2.ONE * SLOT_SIZE * ICON_SHARE
	slot.add_child(icon)
	key_badge = ConsoleStyle.make_key_badge()
	slot.add_child(key_badge)
	carousel = Control.new()
	carousel.name = "Carousel"
	carousel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carousel.visible = false
	carousel.draw.connect(_draw_carousel)
	add_child(carousel)
	select_sfx = SfxPlayer.new()
	select_sfx.name = "SelectSfx"
	select_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	select_sfx.bus = &"Effects"
	select_sfx.volume_db = SELECT_VOLUME_DB
	select_sfx.set(&"min_interval_ms", 40.0)
	if ResourceLoader.exists(SELECT_STREAM):
		select_sfx.stream = load(SELECT_STREAM) as AudioStream
	add_child(select_sfx)
	var run := Services.run()
	if run != null:
		for changed: Signal in [run.inventory_changed, run.weapon_loadout_changed, run.weapon_equipped]:
			if not changed.is_connected(_on_run_changed):
				changed.connect(_on_run_changed)
	refresh()


func _exit_tree() -> void:
	var run := Services.run()
	if run != null:
		for changed: Signal in [run.inventory_changed, run.weapon_loadout_changed, run.weapon_equipped]:
			if changed.is_connected(_on_run_changed):
				changed.disconnect(_on_run_changed)


## The model (WeaponHotbarSurfacePort.snapshot): {"weapons": [{"id" "slot-N", "label", "item_id",
## "disabled"}], "selected_index"}.
static func snapshot() -> Dictionary:
	var run := Services.run()
	var belt := run.weapon_slots()
	var in_hand: Variant = run.equipped_weapon_id()
	var weapons: Array = []
	var selected := -1
	for index in belt.size():
		var entry: Variant = belt[index]
		var owned := WeaponLoadout.owns_weapon(entry)
		weapons.append({"id": "slot-%d" % (index + 1),
			"label": ItemCatalog.item_name(str(entry)) if entry != null else "Empty",
			"item_id": str(entry) if owned else "", "disabled": not owned})
		if owned and entry == in_hand and selected < 0:
			selected = index
	return {"weapons": weapons, "selected_index": selected}


## Rework: the Shape slot's model, shaped like `snapshot()` so the carousel reads it: {"weapons":
## [{"id": shape id, "label": title, "item_id": "" (a shape is no item), "shape_id" (its icon is
## `BodyCards.shape_icon`), "disabled": false}] (the learned shapes), "selected_index" (the current
## one)}.
static func rework_snapshot() -> Dictionary:
	var current := BodyCards.current_shape(BodyCards.world_player())
	var shapes: Array = []
	var selected := -1
	for id: StringName in BodyCards.learned_shapes():
		if id == current:
			selected = shapes.size()
		shapes.append({"id": String(id), "label": ShapeDefs.title(id), "item_id": "", "shape_id": String(id),
			"disabled": false})
	return {"weapons": shapes, "selected_index": selected}


## Whether the slot shows: always, except in the rework mode until a second shape is learned (the
## console's layout leaves it out then, HudConsole.layout).
static func slot_shown() -> bool:
	return not ReworkMode.is_on() or BodyCards.learned_shapes().size() >= 2


func model() -> Dictionary:
	return _model


## True while the carousel shows (tests).
func is_carousel_open() -> bool:
	return carousel != null and carousel.visible


func refresh() -> void:
	if ReworkMode.is_on():
		_refresh_rework()
		return
	if _rework:
		_leave_rework()
	var before := _model
	_model = snapshot()
	var selected := int(_model["selected_index"])
	var weapons: Array = _model["weapons"]
	var entry: Dictionary = weapons[selected] if selected >= 0 else {}
	var in_hand := str(entry.get("item_id", ""))
	slot.text = "" if not in_hand.is_empty() else "Empty"
	slot.tooltip_text = str(entry.get("label", "")) if not in_hand.is_empty() else ""
	icon.texture = ItemIcons.icon(in_hand) if not in_hand.is_empty() else null
	ConsoleStyle.place_key(key_badge, ConsoleStyle.key_of(&"weapon_next"), slot.size)
	if not before.is_empty() and in_hand != _in_hand and not in_hand.is_empty() and _owned_count() > 1:
		_open_carousel(int(before.get("selected_index", -1)), selected)
	_in_hand = in_hand


## Rework: the Shape slot (the current shape, E, the charge's cost; hidden with fewer than two
## shapes) and the carousel when the shape changes.
func _refresh_rework() -> void:
	_rework = true
	var before := _model
	_model = rework_snapshot()
	_rework_signature = _rework_key()
	var selected := int(_model["selected_index"])
	var shapes: Array = _model["weapons"]
	var entry: Dictionary = shapes[selected] if selected >= 0 else {}
	var shape_id := StringName(str(entry.get("shape_id", "")))
	visible = slot_shown()
	slot.text = ""
	icon.texture = BodyCards.shape_icon(shape_id) if not shape_id.is_empty() else null
	ConsoleStyle.place_key(key_badge, ConsoleStyle.key_of(&"weapon_next"), slot.size)
	var cost := BodyCards.charge_energy(shape_id) if not shape_id.is_empty() else 0
	_show_cost(cost)
	slot.tooltip_text = "" if shape_id.is_empty() else "%s · %s to attack, hold to charge (%d energy) · %s next shape" % [
		str(entry.get("label", "")), ControlLabels.control_label(&"attack"), cost, ControlLabels.control_labels(&"weapon_next")]
	var in_hand := String(shape_id)
	if not before.is_empty() and in_hand != _in_hand and not in_hand.is_empty() and _owned_count() > 1:
		_open_carousel(int(before.get("selected_index", -1)), selected)
	_in_hand = in_hand


## Rework: the charge's cost in the top-left chip (warning-coloured while the energy is short).
func _show_cost(cost: int) -> void:
	if cost_chip == null:
		cost_chip = ConsoleStyle.make_key_badge()
		cost_chip.name = "Cost"
		slot.add_child(cost_chip)
	ConsoleStyle.place_key(cost_chip, str(cost) if cost > 0 else "", slot.size)
	cost_chip.position = Vector2.ONE * ConsoleStyle.KEY_INSET
	var player := BodyCards.world_player()
	var energy := float(player.call(&"get_energy")) if player != null and player.has_method(&"get_energy") else INF
	cost_chip.add_theme_color_override(&"font_color", COST_SHORT_COLOR if energy < cost else COST_CHIP_COLOR)


## The mode went off: the slot is the belt's again.
func _leave_rework() -> void:
	_rework = false
	_rework_signature = ""
	visible = true
	if cost_chip != null:
		cost_chip.visible = false
	_model = {}
	_in_hand = ""


## Rework: what the slot shows, to notice a change (the shape, the learned shapes, the energy being
## short of the charge).
func _rework_key() -> String:
	var player := BodyCards.world_player()
	var shape_id := BodyCards.current_shape(player)
	var short := false
	if player != null and player.has_method(&"get_energy"):
		short = float(player.call(&"get_energy")) < BodyCards.charge_energy(shape_id)
	return "%s|%s|%s" % [shape_id, BodyCards.learned_shapes(), short]


func _process(_delta: float) -> void:
	if ReworkMode.is_on() != _rework or (_rework and _rework_key() != _rework_signature):
		refresh()
	if _shown_at_ms < 0.0:
		return
	var age := float(Time.get_ticks_msec()) - _shown_at_ms
	if age >= SLIDE_MS + HOLD_MS + FADE_MS:
		_shown_at_ms = -1.0
		carousel.visible = false
		return
	carousel.modulate.a = 1.0 - clampf((age - SLIDE_MS - HOLD_MS) / FADE_MS, 0.0, 1.0)
	carousel.queue_redraw()


func _owned_count() -> int:
	var count := 0
	for entry: Dictionary in _model["weapons"]:
		if not bool(entry["disabled"]):
			count += 1
	return count


## Opens (or restarts) the carousel; it slides from the side the hand moved toward.
func _open_carousel(from_index: int, to_index: int) -> void:
	var forward := true
	if from_index >= 0:
		var count := (_model["weapons"] as Array).size()
		forward = posmod(to_index - from_index, count) <= count / 2.0
	_slide_from = CAROUSEL_STEP if forward else -CAROUSEL_STEP
	_shown_at_ms = float(Time.get_ticks_msec())
	carousel.visible = true
	carousel.modulate.a = 1.0
	carousel.queue_redraw()


## The owned belt weapons (rework: the learned shapes) around the one in hand, in belt order,
## wrapping, each once (at most two on each side): [offset, its model entry].
func _carousel_entries() -> Array:
	var owned: Array[int] = []
	var weapons: Array = _model["weapons"]
	for index in weapons.size():
		if not bool((weapons[index] as Dictionary)["disabled"]):
			owned.append(index)
	var middle := owned.find(int(_model["selected_index"]))
	if middle < 0:
		return []
	var entries: Array = []
	var before := mini(2, floori((owned.size() - 1) / 2.0))
	var after := mini(2, floori(owned.size() / 2.0))
	for offset in range(-before, after + 1):
		var index: int = owned[posmod(middle + offset, owned.size())]
		entries.append([offset, weapons[index] as Dictionary])
	return entries


## A carousel entry's icon: the shape's (rework), else the belt weapon's.
static func _entry_icon(entry: Dictionary) -> Texture2D:
	var shape_id := str(entry.get("shape_id", ""))
	if not shape_id.is_empty():
		return BodyCards.shape_icon(StringName(shape_id))
	return ItemIcons.icon(str(entry["item_id"]))


func _draw_carousel() -> void:
	var age := float(Time.get_ticks_msec()) - _shown_at_ms
	var slide := _slide_from * (1.0 - ease(clampf(age / SLIDE_MS, 0.0, 1.0), 0.4))
	var centre := Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5 - CAROUSEL_RISE)
	var entries := _carousel_entries()
	var reach := 0
	for entry: Array in entries:
		reach = maxi(reach, absi(int(entry[0])))
	var half_width := CAROUSEL_STEP * reach + CAROUSEL_CELL * 0.5 + 10.0
	var backing := StyleBoxFlat.new()
	backing.bg_color = BACKING_COLOR
	backing.set_corner_radius_all(int(CAROUSEL_CELL * 0.5 + 6.0))
	carousel.draw_style_box(backing, Rect2(centre - Vector2(half_width, CAROUSEL_CELL * 0.5 + 6.0),
		Vector2(half_width * 2.0, CAROUSEL_CELL + 12.0)))
	var frame := ConsoleStyle.slot_style()
	# Sides first, the middle on top.
	entries.sort_custom(func(a: Array, b: Array) -> bool: return absi(int(a[0])) > absi(int(b[0])))
	for entry: Array in entries:
		var offset := int(entry[0])
		var cell := CAROUSEL_CELL if offset == 0 else CAROUSEL_SIDE_CELL
		var opacity: float = CAROUSEL_OPACITY[mini(absi(offset), CAROUSEL_OPACITY.size() - 1)]
		var at := centre + Vector2(offset * CAROUSEL_STEP + slide, 0.0)
		var rect := Rect2(at - Vector2.ONE * cell * 0.5, Vector2.ONE * cell)
		var entry_icon := _entry_icon(entry[1] as Dictionary)
		carousel.draw_style_box(frame, rect)
		if entry_icon != null:
			carousel.draw_texture_rect(entry_icon, rect.grow(-cell * 0.12), false, Color(1.0, 1.0, 1.0, opacity))
		if opacity < 1.0:
			carousel.draw_rect(rect.grow(-2.0), Color(BACKING_COLOR, 1.0 - opacity))
		if offset == 0:
			carousel.draw_rect(rect.grow(1.0), UiTokens.WARNING, false, 2.5)
	var font := get_theme_default_font()
	var label := _carousel_label() if _rework else ItemCatalog.item_name(_in_hand_after_refresh())
	if font != null and not label.is_empty():
		var font_size := 13
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var baseline := centre + Vector2(-width * 0.5, -CAROUSEL_NAME_RISE + font_size * 0.5)
		carousel.draw_string_outline(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, ConsoleStyle.OUTLINE)
		carousel.draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, UiTokens.TEXT)


func _in_hand_after_refresh() -> String:
	var selected := int(_model.get("selected_index", -1))
	var weapons: Array = _model.get("weapons", [])
	return str((weapons[selected] as Dictionary)["item_id"]) if selected >= 0 and selected < weapons.size() else ""


## Rework: the carousel's name, the current shape's title.
func _carousel_label() -> String:
	var selected := int(_model.get("selected_index", -1))
	var shapes: Array = _model.get("weapons", [])
	return str((shapes[selected] as Dictionary)["label"]) if selected >= 0 and selected < shapes.size() else ""


## A click puts the next belt weapon in hand (like a scroll); in the rework mode it takes the next
## learned shape.
func _on_slot_pressed() -> void:
	if select_sfx != null and select_sfx.has_method(&"play_cue"):
		select_sfx.call(&"play_cue")
	if ReworkMode.is_on():
		var shapes := BodyCards.shapes_of(BodyCards.world_player())
		if shapes != null and shapes.has_method(&"cycle"):
			shapes.call(&"cycle", 1)
		refresh()
		return
	var next := WeaponLoadout.cycle_slot(1)
	if next >= 0:
		var actions := get_tree().get_first_node_in_group(INVENTORY_ACTIONS_GROUP)
		if actions != null:
			actions.call(&"switch_weapon_slot", next)
	# A refused equip leaves the real selection in place.
	refresh()


func _on_run_changed(_payload: Dictionary) -> void:
	refresh()

extends Control
## The HUD's ability buttons (Phaser `features/ui/AbilityBarSurfacePort.ts` + `ui.ability-bar`;
## abilities spec 2.6), drawn since 2026-10-08 as the HUD console's icon slots (roadmap 4.12,
## docs/design/2026-10-07-hud-console-mockup.md): one 46-unit wooden slot per ability in a row,
## 4 apart, placed on the console by hud.gd. The abilities and their order come from
## `ability_definitions.gd` BAR_SLOTS (key order; Jump left the interface on 2026-10-08); a slot
## shows the ability's icon (`asset/UI/hud-console/ability-<id>.webp`, its name
## while there is none) and its key in a corner badge.
##
## Each slot reads the player's `ability_status(id)` every frame. Its label (the tooltip; tests read
## it), first match:
## - locked → "<earnedBy>\n<name>" (the icon greyed);
## - cooling down → "<s>s\n<name>" (s = ceil(ms / 100) / 10 with one decimal: 1234 ms → "1.3s";
##   a dark sweep over the slot shrinks as the cooldown runs out, the seconds in the middle);
## - too little energy → "Need <cost>E\n<name>" (the icon dimmed, the cost in the badge);
## - busy or action-locked → "Busy\n<name>" (the icon dimmed);
## - else "<key label>\n<name>" ("2\nLash").
## A slot is disabled unless the game is playing (no menu pause, not dead) and the ability can run.
## A click on an enabled slot runs the ability through `player.activate_ability_from_ui` (ClickSfx
## plays first). The slots never take keyboard focus.
##
## Body-shapes rework mode (game/shapes/rework_mode.gd; body-shapes plan section 8.1, BODY_SHAPES.md
## "Ability Box and HUD"): the bar holds at most two slots (`rework_slots`), and no Swallow, Lash,
## Slam or Teleport slot of their own:
## - the **Ability slot** (`BOX_SLOT`): the box ability chosen in the bag window
##   (game/player/abilities/ability_box.gd): its icon, the `ability_use` key in the badge (F; S in
##   keys-only), its energy cost in a chip at the top left (warning-coloured while the energy is
##   short) and the cooldown sweep; hidden while the box is empty. A click opens the bag window, where
##   the box is (body-shapes plan section 6);
## - the **Roll slot** (`dodge`), as before, only once the Roll is learned.
## The bar rebuilds its slots when that set changes or the mode goes on or off (the console's layout
## follows, HudConsole). A box ability learned while the mode is on (not quietly) becomes the choice
## (`AbilityBox.on_learned`, on `RunState.ability_learned`).
##
## Owner: abilities (the look: UI, HUD console); the rework's slots: Ability Box and HUD.

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
const ConsoleStyle := preload("res://game/ui/console/console_style.gd")
const SfxPlayer := preload("res://game/runtime/sfx_player.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const BodyCards := preload("res://game/ui/body_cards.gd")

const SLOT_SIZE := 46.0
const SLOT_GAP := 4.0
const ICON_SHARE := 0.8
const ICON_PATH := "res://asset/UI/hud-console/ability-%s.webp"
const NAME_FONT_SIZE := 10
const COOLDOWN_FONT_SIZE := 15
const SWEEP_COLOR := Color(0.03, 0.05, 0.08, 0.6)
const LOCKED_MODULATE := Color(0.5, 0.5, 0.5, 0.6)
const DIM_MODULATE := Color(1.0, 1.0, 1.0, 0.5)
## `sfx.ui.click` (min interval 40 ms), played through the converter's cue player.
const CLICK_STREAM := "res://asset/audio/sfx/library/ui/click.ogg"
const CLICK_MIN_INTERVAL_MS := 40.0
## Rework: the Ability slot's id in `slots()` and the model (it shows the box's chosen ability), its
## node name, the cost chip's colour (the energy orb's goo), and where the bag window lives.
const BOX_SLOT := &"ability-box"
const BOX_SLOT_NAME := "Ability"
const COST_CHIP_COLOR := Color("#ffe080")
const MENU_WINDOWS_GROUP := &"menu_windows"

## The player script (ability_status, activate_ability_from_ui, is_dead), or null.
var player: Node
var _slots: Array[StringName] = []
## id -> {"button": Button, "icon": TextureRect, "key": Label, "sweep": Control}; rework slots also
## "cost": Label (the chip) and "icon_id": String (the ability whose icon shows).
var _views: Dictionary = {}
var _model: Dictionary = {}
var _signature: String = ""
var _click: AudioStreamPlayer
## True while the slots are the rework's.
var _rework: bool = false


## The bar's abilities in order (`ability_definitions.gd` BAR_SLOTS); in the rework mode the
## rework's slots shown now (`rework_slots`).
static func slots() -> Array[StringName]:
	if ReworkMode.is_on():
		return rework_slots(BodyCards.world_player())
	var ids: Array[StringName] = []
	for id: Variant in Definitions.BAR_SLOTS:
		ids.append(StringName(id))
	return ids


## Rework: the Ability slot while the box holds a learned ability, then the Roll once it is learned
## (`player`'s abilities; RunState's when `player` is null).
static func rework_slots(target: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	if not AbilityBox.box_ids(target).is_empty():
		ids.append(BOX_SLOT)
	var learned := false
	if target != null and is_instance_valid(target) and target.has_method(&"is_learned"):
		learned = bool(target.call(&"is_learned", Definitions.DODGE))
	else:
		var run := Services.run()
		learned = run != null and run.has_learned_ability(String(Definitions.DODGE))
	if learned:
		ids.append(Definitions.DODGE)
	return ids


## The row's size for `count` slots.
static func row_size(count: int) -> Vector2:
	return Vector2(count * SLOT_SIZE + maxf(0.0, count - 1.0) * SLOT_GAP, SLOT_SIZE)


func _ready() -> void:
	name = "AbilityBar"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots = slots()
	size = row_size(_slots.size())
	for index in _slots.size():
		_make_slot(_slots[index], index)
	_click = AudioStreamPlayer.new()
	_click.name = "ClickSfx"
	_click.set_script(SfxPlayer)
	_click.set(&"min_interval_ms", CLICK_MIN_INTERVAL_MS)
	_click.max_polyphony = 4
	_click.bus = &"Effects"
	_click.process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(CLICK_STREAM):
		_click.stream = load(CLICK_STREAM)
	add_child(_click)
	var run := Services.run()
	if run != null and not run.ability_learned.is_connected(_on_ability_learned):
		run.ability_learned.connect(_on_ability_learned)
	refresh()


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.ability_learned.is_connected(_on_ability_learned):
		run.ability_learned.disconnect(_on_ability_learned)


func _process(_delta: float) -> void:
	refresh()


## Rebuilds the slots from the player (cheap; skips unchanged models).
func refresh() -> void:
	if ReworkMode.is_on() or _rework:
		_sync_slots()
	_model = snapshot()
	var signature := str(_model)
	if signature == _signature:
		return
	_signature = signature
	for id in _slots:
		_show(id, _model[id])


## {id: {"label", "disabled", "state", "key", "cooldown"}} per slot; `state` is "locked",
## "cooldown", "energy", "busy" or "ready"; `cooldown` the share of the cooldown left (tests read it).
func snapshot() -> Dictionary:
	if ReworkMode.is_on():
		return _rework_snapshot()
	var live := player != null and is_instance_valid(player)
	var interactive := live and not bool(player.call(&"is_dead")) and not _menu_paused()
	var constants := Services.constants()
	var model := {}
	for id in (_slots if not _slots.is_empty() else slots()):
		var name_text := str(Definitions.BAR_NAMES.get(id, id))
		var status: Dictionary = player.call(&"ability_status", id) if live else {}
		var state := _state(status)
		var cooldown := float(status.get("cooldownRemainingMs", 0.0))
		var total := Definitions.cooldown_ms(id, constants) if constants != null else 0.0
		model[id] = {
			"label": _label(id, name_text, status),
			"disabled": not interactive or not bool(status.get("canActivate", false)),
			"state": state,
			"key": ControlLabels.control_label(Definitions.action(id)),
			"cooldown": clampf(cooldown / total, 0.0, 1.0) if total > 0.0 else (1.0 if cooldown > 0.0 else 0.0),
			"cost": roundi(Definitions.energy_cost(id)),
			"seconds": ceilf(cooldown / 100.0) / 10.0,
		}
	return model


## Rework: {slot id: the classic keys plus "ability_id" (the ability the slot shows) and
## "interactive" (the game is playing)} for `rework_slots()`; the Ability slot's key is
## `ability_use`'s.
func _rework_snapshot() -> Dictionary:
	var live := player != null and is_instance_valid(player)
	var interactive := live and not bool(player.call(&"is_dead")) and not _menu_paused()
	var model := {}
	for id: StringName in (_slots if _rework else rework_slots(player)):
		var ability_id := AbilityBox.selected(player) if id == BOX_SLOT else id
		var name_text := str(Definitions.BAR_NAMES.get(ability_id, Definitions.title(ability_id)))
		var status: Dictionary = player.call(&"ability_status", ability_id) if live and not ability_id.is_empty() else {}
		var cooldown := float(status.get("cooldownRemainingMs", 0.0))
		var total := AbilityBox.cooldown_ms(ability_id)
		var key := ControlLabels.control_label(AbilityBox.USE_ACTION if id == BOX_SLOT else Definitions.action(id))
		var cost := roundi(AbilityBox.energy_cost(ability_id))
		model[id] = {
			"label": _rework_label(name_text, status, key, cost),
			"disabled": not interactive or not bool(status.get("canActivate", false)),
			"state": _state(status),
			"key": key,
			"cooldown": clampf(cooldown / total, 0.0, 1.0) if total > 0.0 else (1.0 if cooldown > 0.0 else 0.0),
			"cost": cost,
			"seconds": ceilf(cooldown / 100.0) / 10.0,
			"ability_id": String(ability_id),
			"interactive": interactive,
		}
	return model


## Clicks a slot (the button's `pressed`; tests call it): runs the ability when it can run now. In
## the rework mode the Ability slot runs the box's chosen ability.
func activate(id: StringName) -> bool:
	if id == BOX_SLOT:
		id = AbilityBox.selected(player)
		if id.is_empty():
			return false
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")) or _menu_paused():
		return false
	var status: Dictionary = player.call(&"ability_status", id)
	if not bool(status.get("canActivate", false)):
		return false
	var used := bool(player.call(&"activate_ability_from_ui", id))
	_signature = ""
	return used


static func _state(status: Dictionary) -> String:
	if not bool(status.get("unlocked", false)):
		return "locked"
	if float(status.get("cooldownRemainingMs", 0.0)) > 0.0:
		return "cooldown"
	if bool(status.get("insufficientEnergy", false)):
		return "energy"
	if bool(status.get("busy", false)) or bool(status.get("actionLocked", false)):
		return "busy"
	return "ready"


static func _label(id: StringName, name_text: String, status: Dictionary) -> String:
	if not bool(status.get("unlocked", false)):
		return "%s\n%s" % [str(status.get("earnedBy", Definitions.entry(id).get("earned_by", ""))), name_text]
	var cooldown := float(status.get("cooldownRemainingMs", 0.0))
	if cooldown > 0.0:
		return "%.1fs\n%s" % [ceilf(cooldown / 100.0) / 10.0, name_text]
	if bool(status.get("insufficientEnergy", false)):
		return "Need %dE\n%s" % [roundi(Definitions.energy_cost(id)), name_text]
	if bool(status.get("busy", false)) or bool(status.get("actionLocked", false)):
		return "Busy\n%s" % name_text
	return "%s\n%s" % [ControlLabels.control_label(Definitions.action(id)), name_text]


## Rework: `_label`'s rules with the slot's own key label (`ability_use`'s for the Ability slot).
static func _rework_label(name_text: String, status: Dictionary, key: String, cost: int) -> String:
	if not bool(status.get("unlocked", false)):
		return "%s\n%s" % [str(status.get("earnedBy", "")), name_text]
	var cooldown := float(status.get("cooldownRemainingMs", 0.0))
	if cooldown > 0.0:
		return "%.1fs\n%s" % [ceilf(cooldown / 100.0) / 10.0, name_text]
	if bool(status.get("insufficientEnergy", false)):
		return "Need %dE\n%s" % [cost, name_text]
	if bool(status.get("busy", false)) or bool(status.get("actionLocked", false)):
		return "Busy\n%s" % name_text
	return "%s\n%s" % [key, name_text]


## Phaser's `interactive` is "not paused": a menu or window pause, not a hit-stop.
func _menu_paused() -> bool:
	if not is_inside_tree() or not get_tree().paused:
		return false
	var world := Services.world()
	return world == null or world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL) \
		or not world.has_pause_reason(Services.WorldServiceType.PAUSE_HIT_STOP)


func _make_slot(id: StringName, index: int) -> void:
	var button := Button.new()
	button.name = BOX_SLOT_NAME if id == BOX_SLOT else str(Definitions.BAR_NAMES.get(id, id))
	button.position = Vector2(index * (SLOT_SIZE + SLOT_GAP), 0.0)
	button.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	ConsoleStyle.style_slot_button(button)
	button.pressed.connect(_on_pressed.bind(id))
	add_child(button)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var inset := SLOT_SIZE * (1.0 - ICON_SHARE) * 0.5
	icon.position = Vector2(inset, inset)
	icon.size = Vector2.ONE * SLOT_SIZE * ICON_SHARE
	var path := ICON_PATH % str(id)
	if ResourceLoader.exists(path):
		icon.texture = load(path) as Texture2D
	elif id != BOX_SLOT:
		button.text = str(Definitions.BAR_NAMES.get(id, id))
	button.add_child(icon)
	var sweep := Control.new()
	sweep.name = "Cooldown"
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.size = button.size
	sweep.draw.connect(_draw_sweep.bind(id, sweep))
	button.add_child(sweep)
	var key := ConsoleStyle.make_key_badge()
	button.add_child(key)
	_views[id] = {"button": button, "icon": icon, "key": key, "sweep": sweep}
	if ReworkMode.is_on():
		var cost := ConsoleStyle.make_key_badge()
		cost.name = "Cost"
		cost.visible = false
		button.add_child(cost)
		_views[id]["cost"] = cost
		_views[id]["icon_id"] = str(id) if icon.texture != null else ""


func _show(id: StringName, entry: Dictionary) -> void:
	var view: Dictionary = _views[id]
	var button: Button = view["button"]
	var icon: TextureRect = view["icon"]
	var key: Label = view["key"]
	var state := str(entry["state"])
	button.disabled = bool(entry["disabled"])
	button.tooltip_text = str(entry["label"]).replace("\n", " · ")
	match state:
		"locked":
			icon.modulate = LOCKED_MODULATE
		"energy", "busy":
			icon.modulate = DIM_MODULATE
		_:
			icon.modulate = Color.WHITE
	var badge := "%dE" % int(entry["cost"]) if state == "energy" else str(entry["key"])
	ConsoleStyle.place_key(key, badge, button.size)
	key.add_theme_color_override(&"font_color", UiTokens.WARNING if state == "energy" else UiTokens.TEXT)
	if entry.has("ability_id"):
		_show_rework(id, view, entry)
	(view["sweep"] as Control).queue_redraw()


## Rework: the slot's icon follows the ability it shows; the key badge always shows the key and the
## cost sits in its own chip (top left); the Ability slot stays clickable while the game plays (a
## click opens the bag window).
func _show_rework(id: StringName, view: Dictionary, entry: Dictionary) -> void:
	var button: Button = view["button"]
	var icon: TextureRect = view["icon"]
	var ability_id := str(entry["ability_id"])
	if str(view.get("icon_id", "")) != ability_id:
		view["icon_id"] = ability_id
		var texture := BodyCards.ability_icon(StringName(ability_id))
		icon.texture = texture
		button.text = "" if texture != null else str(Definitions.BAR_NAMES.get(StringName(ability_id), ability_id))
	var state := str(entry["state"])
	ConsoleStyle.place_key(view["key"] as Label, str(entry["key"]), button.size)
	(view["key"] as Label).add_theme_color_override(&"font_color", UiTokens.TEXT)
	var chip: Label = view.get("cost")
	if chip != null:
		var cost := int(entry["cost"])
		ConsoleStyle.place_key(chip, str(cost) if cost > 0 else "", button.size)
		chip.position = Vector2.ONE * ConsoleStyle.KEY_INSET
		chip.add_theme_color_override(&"font_color", UiTokens.WARNING if state == "energy" else COST_CHIP_COLOR)
	if id == BOX_SLOT:
		button.disabled = not bool(entry["interactive"])
		button.tooltip_text += " · click to choose in the bag"


## The cooldown: a dark sweep over the share of the cooldown left, and the seconds.
func _draw_sweep(id: StringName, sweep: Control) -> void:
	var entry: Dictionary = _model.get(id, {})
	if str(entry.get("state", "")) != "cooldown":
		return
	var share := float(entry["cooldown"])
	var centre := sweep.size * 0.5
	var radius := sweep.size.x * 0.62
	var points := PackedVector2Array([centre])
	var steps := 24
	for step in steps + 1:
		var angle := -PI * 0.5 + TAU * share * step / steps
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	var clip := Rect2(Vector2.ONE * 4.0, sweep.size - Vector2.ONE * 8.0)
	var box := PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)])
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(points, box):
		sweep.draw_colored_polygon(piece, SWEEP_COLOR)
	var font := sweep.get_theme_default_font()
	if font == null:
		return
	var text := "%.1f" % float(entry["seconds"])
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COOLDOWN_FONT_SIZE).x
	var baseline := centre + Vector2(-width * 0.5, COOLDOWN_FONT_SIZE * 0.35)
	sweep.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COOLDOWN_FONT_SIZE, 4, ConsoleStyle.OUTLINE)
	sweep.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COOLDOWN_FONT_SIZE, UiTokens.TEXT)


func _on_pressed(id: StringName) -> void:
	if _click != null and _click.stream != null:
		_click.call(&"play_cue")
	if id == BOX_SLOT:
		_open_box()
		return
	activate(id)


## Rework: the slots follow `slots()` (the box filling up, the Roll learned) and the mode going on
## or off; the row is rebuilt when they change.
func _sync_slots() -> void:
	var on := ReworkMode.is_on()
	var wanted := slots()
	if on == _rework and wanted == _slots:
		return
	_rework = on
	for view: Dictionary in _views.values():
		var button: Button = view["button"]
		remove_child(button)
		button.queue_free()
	_views.clear()
	_slots = wanted
	size = row_size(_slots.size())
	for index in _slots.size():
		_make_slot(_slots[index], index)
	_signature = ""


## Rework: a box ability learned now (not quietly) becomes the choice (body-shapes plan section 6
## "Rules").
func _on_ability_learned(payload: Dictionary) -> void:
	if not ReworkMode.is_on():
		return
	var target: Node = player if player != null and is_instance_valid(player) else BodyCards.world_player()
	AbilityBox.on_learned(target, StringName(str(payload.get("ability_id", ""))))
	_signature = ""


## Rework: a click on the Ability slot opens the bag window, whose top band is the Ability Box.
func _open_box() -> void:
	var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP) if is_inside_tree() else null
	if menu != null and menu.has_method(&"toggle_menu"):
		menu.call(&"toggle_menu")

extends Control
class_name BossHealthBar
## The boss health bar (Phaser `ui/boss-health-bar.scene.json` + `features/ui/BossHealthSurfacePort.ts`).
## Boss spec 2.5 and 5. Built by hand on the HUD layer (hud.gd adds it): a card at the bottom
## centre with the boss name (16 px bold, danger tone) and a bar "Boss health <hp> / <max>".
## Styled by the UI theme (docs/godot/UI_THEME.md): the card is `BossPanel` (red border, radius 12;
## the CSS gradient drawn flat), the name `BossName`, the bar `BossBar` (inset well, radius 5,
## danger fill).
##
## Layout (ui/boss-health-bar.scene.json + styles.css:3396-3410, measured in the Phaser DOM): the
## card is 548 px wide (at most the screen width - 24 px) and its bottom edge sits 192 px above the
## screen's bottom, where Phaser stacks it above the weapon hotbar (116-172 px) and the ability bar
## (12-84 px). The card follows the CSS rule's intent: 12 px side padding and a 16 px bar under the
## 28 px name row, so it is 58 px tall instead of the authored 72 (Phaser's inline layout overrides
## that rule and stretches the bar to 38 px). On a view shorter than the 720 px reference the card
## never rises above `view centre + PLAYER_CLEARANCE`, so it stays below the player.
##
## Data (BossHealthSurfacePort): every camp in the `boss_camp` group is bound once (checked each
## frame, so camps of a newly loaded world bind themselves); `boss_engaged` stores
## {name, boss} for the camp, `boss_disengaged` removes it. Each frame the bar shows the LAST
## stored camp: name, hp = max(0, hp), max = max(1, max_hp), visible while any is stored.
## PROCESS_MODE_ALWAYS (HUD), real-time presentation; mouse_filter IGNORE.
##
## Owner: boss port.

const BossCampScript := preload("res://game/scripts/boss_camp.gd")
const HudBar := preload("res://game/ui/hud_bar.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

## ui/boss-health-bar.scene.json: 548 px wide, bottom edge 192 px above the screen bottom.
const CARD_WIDTH := 548.0
const BOTTOM_GAP := 192.0
## `max-width: calc(100% - 24px)`.
const SCREEN_MARGIN := 24.0
const NAME_HEIGHT := 28.0
const BAR_TOP := 34.0
## src/styles.css:3396-3410: padding 0 12 px, bar 16 px tall; 8 px under the bar.
const PADDING_X := 12.0
const BAR_HEIGHT := 16.0
const CARD_HEIGHT := BAR_TOP + BAR_HEIGHT + 8.0
## The card's top stays this far below the view centre (where the camera keeps the player).
const PLAYER_CLEARANCE := 96.0
## Field-kit danger tone (the bar's fill).
const TONE_DANGER := UiTokens.DANGER
const BAR_LABEL := "Boss health"

## camp_id -> {"name": String, "boss": WeakRef} in show order.
var _active: Dictionary = {}
## Instance ids of bound camps.
var _bound: Dictionary = {}
var _name_label: Label
var _bar: HudBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	theme_type_variation = &"BossPanel"

	_name_label = Label.new()
	_name_label.name = "BossName"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.anchor_right = 1.0
	_name_label.offset_left = PADDING_X
	_name_label.offset_right = -PADDING_X
	_name_label.offset_bottom = NAME_HEIGHT
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.theme_type_variation = &"BossName"
	add_child(_name_label)

	_bar = HudBar.new()
	_bar.name = "Health"
	_bar.anchor_right = 1.0
	_bar.offset_left = PADDING_X
	_bar.offset_right = -PADDING_X
	_bar.offset_top = BAR_TOP
	_bar.offset_bottom = BAR_TOP + BAR_HEIGHT
	_bar.theme_type_variation = &"BossBar"
	_bar.configure(BAR_LABEL, TONE_DANGER)
	add_child(_bar)
	visible = false
	place(get_viewport_rect().size)


func _process(_delta: float) -> void:
	_bind_new_camps()
	_render(snapshot())
	if visible:
		place(get_viewport_rect().size)


## Puts the card for a view of `view_size` (see the layout notes above).
func place(view_size: Vector2) -> void:
	var rect := card_rect(view_size)
	offset_left = rect.position.x - view_size.x * 0.5
	offset_right = rect.end.x - view_size.x * 0.5
	offset_top = rect.position.y - view_size.y
	offset_bottom = rect.end.y - view_size.y


## The card's screen rectangle in a view of `view_size`.
static func card_rect(view_size: Vector2) -> Rect2:
	var width := minf(CARD_WIDTH, maxf(120.0, view_size.x - SCREEN_MARGIN))
	var top := maxf(view_size.y - BOTTOM_GAP - CARD_HEIGHT, view_size.y * 0.5 + PLAYER_CLEARANCE)
	top = minf(top, view_size.y - CARD_HEIGHT - 8.0)
	return Rect2(roundf((view_size.x - width) * 0.5), roundf(top), roundf(width), CARD_HEIGHT)


## Binds `camp` (a BossCampScript): its `boss_engaged` / `boss_disengaged` drive this bar.
func bind_camp(camp: Node) -> void:
	if camp == null or _bound.has(camp.get_instance_id()):
		return
	_bound[camp.get_instance_id()] = true
	camp.connect(&"boss_engaged", _on_boss_engaged.bind(camp))
	camp.connect(&"boss_disengaged", _on_boss_disengaged)
	# A boss already alive when the bar binds (e.g. the HUD came after the camp spawned it).
	if camp.has_method(&"get_live_boss") and camp.call(&"get_live_boss") != null:
		_on_boss_engaged({"campId": camp.get(&"camp_id"), "bossId": camp.get(&"boss_id")}, camp)


## `BossHealthSurfacePort.showBoss` for a camp's live boss.
func show_boss(camp_id: String, boss_name: String, boss: Object) -> void:
	if boss == null:
		return
	_active[camp_id] = {"name": boss_name, "boss": weakref(boss)}
	_render(snapshot())


## `BossHealthSurfacePort.hideBoss`.
func hide_boss(camp_id: String, _defeated: bool) -> void:
	_active.erase(camp_id)
	_render(snapshot())


## `BossHealthSurfacePort.snapshot`: {"name", "hp", "maxHp", "visible"} of the last shown boss.
func snapshot() -> Dictionary:
	var source: Dictionary = {}
	for camp_id: Variant in _active:
		source = _active[camp_id]
	var hp := 0.0
	var max_hp := 1.0
	if not source.is_empty():
		var boss: Object = (source["boss"] as WeakRef).get_ref()
		if boss != null and boss.has_method(&"get_damage_state"):
			var state: Dictionary = boss.call(&"get_damage_state")
			hp = float(state.get("hp", 0.0))
			max_hp = float(state.get("max_hp", 1.0))
	return {
		"name": str(source.get("name", "")),
		"hp": maxf(0.0, hp),
		"maxHp": maxf(1.0, max_hp),
		"visible": not source.is_empty(),
	}


func _draw() -> void:
	get_theme_stylebox(&"panel").draw(get_canvas_item(), Rect2(Vector2.ZERO, size))


func _render(model: Dictionary) -> void:
	visible = bool(model["visible"])
	if _name_label == null:
		return
	_name_label.text = str(model["name"])
	_bar.set_values(float(model["hp"]), float(model["maxHp"]))


func _bind_new_camps() -> void:
	if not is_inside_tree():
		return
	for camp: Node in get_tree().get_nodes_in_group(BossCampScript.GROUP):
		bind_camp(camp)


func _on_boss_engaged(payload: Dictionary, camp: Node) -> void:
	if not is_instance_valid(camp):
		return
	var boss: Object = camp.call(&"get_live_boss")
	var boss_id := str(payload.get("bossId", ""))
	show_boss(str(payload.get("campId", "")), BossCampScript.display_name_for(boss, boss_id), boss)


func _on_boss_disengaged(payload: Dictionary) -> void:
	hide_boss(str(payload.get("campId", "")), bool(payload.get("defeated", false)))

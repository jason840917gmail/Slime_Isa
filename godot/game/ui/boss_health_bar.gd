extends Control
class_name BossHealthBar
## The boss health bar (Phaser `ui/boss-health-bar.scene.json` + `features/ui/BossHealthSurfacePort.ts`).
## Boss spec 2.5 and 5. Built by hand on the HUD layer (hud.gd adds it): a 548 x 72 panel anchored
## bottom-centre at offsets (-274, -264) .. (274, -192), the boss name (16 px bold, danger tone)
## and a bar "Boss health <hp> / <max>". Styling is minimal (the CSS gradient is a flat colour).
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

## ui/boss-health-bar.scene.json layout.
const OFFSET_LEFT := -274.0
const OFFSET_TOP := -264.0
const OFFSET_RIGHT := 274.0
const OFFSET_BOTTOM := -192.0
const NAME_HEIGHT := 28.0
const BAR_TOP := 34.0
## src/styles.css:3396-3410: padding 0 12 px, bar 16 px tall, border #8b2f2f radius 12,
## background #261727 -> #101a31 (flat #101a31 here).
const PADDING_X := 12.0
const BAR_HEIGHT := 16.0
const BORDER_COLOR := Color("#8b2f2f")
const BACKGROUND := Color("#101a31")
const CORNER_RADIUS := 12
const NAME_FONT_SIZE := 16
## Field-kit danger tone (hud.gd TONE_DANGER).
const TONE_DANGER := Color("#ff6f88")
const SHADOW_COLOR := Color("#081022")
const BAR_LABEL := "Boss health"

## camp_id -> {"name": String, "boss": WeakRef} in show order.
var _active: Dictionary = {}
## Instance ids of bound camps.
var _bound: Dictionary = {}
var _panel_box: StyleBoxFlat
var _name_label: Label
var _bar: HudBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = OFFSET_LEFT
	offset_top = OFFSET_TOP
	offset_right = OFFSET_RIGHT
	offset_bottom = OFFSET_BOTTOM
	_panel_box = StyleBoxFlat.new()
	_panel_box.bg_color = BACKGROUND
	_panel_box.border_color = BORDER_COLOR
	_panel_box.set_border_width_all(1)
	_panel_box.set_corner_radius_all(CORNER_RADIUS)
	_panel_box.anti_aliasing = true

	_name_label = Label.new()
	_name_label.name = "BossName"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.position = Vector2(PADDING_X, 0.0)
	_name_label.size = Vector2(OFFSET_RIGHT - OFFSET_LEFT - PADDING_X * 2.0, NAME_HEIGHT)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var settings := LabelSettings.new()
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.7
	settings.font = bold
	settings.font_size = NAME_FONT_SIZE
	settings.font_color = TONE_DANGER
	settings.shadow_color = SHADOW_COLOR
	settings.shadow_offset = Vector2(0.0, 1.0)
	settings.shadow_size = 2
	_name_label.label_settings = settings
	add_child(_name_label)

	_bar = HudBar.new()
	_bar.name = "Health"
	_bar.position = Vector2(PADDING_X, BAR_TOP)
	_bar.size = Vector2(OFFSET_RIGHT - OFFSET_LEFT - PADDING_X * 2.0, BAR_HEIGHT)
	_bar.configure(BAR_LABEL, TONE_DANGER)
	add_child(_bar)
	visible = false


func _process(_delta: float) -> void:
	_bind_new_camps()
	_render(snapshot())


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
	_panel_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))


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

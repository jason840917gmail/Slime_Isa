extends CanvasLayer
## The ceremony (owner, 2026-10-09: "the slime rise the new learn ability or something original but
## exciting"; roadmap 4.13): when the slime gets something permanent, the game stops for a moment
## that is the slime's own. It plays for every ability learned (`request`), the first time each
## permanent item comes into the bag (`request_item`: a weapon, a tool, a key; RunState
## `permanent_item_gained`, so once per item, kept in saves) and for every Goo Heart
## (`request_heart`).
##
## 1. **Spotlight** (DIM_IN_S): the world dims around the slime; the slime squashes, then stretches
##    up as if something is welling up inside it. The fanfare plays (cue `Ceremony`).
## 2. **The bubble rises** (RISE_S): a glossy goo bubble carrying the thing's icon (an ability's
##    HUD console icon, an item's bag icon, the heart's own picture) swells out of the top of the slime and floats above it, wobbling, with turning
##    light rays behind it and sparkles drifting off it (ceremony_stage.gd).
## 3. **The card** slides up from below: what it is ("New ability", "New weapon", "New tool", "Key
##    item", "Goo Heart"), its name, one line of what it does and how to use it with its key (an
##    ability's AbilityDefinitions.CEREMONY, an item's description), then "Press any key".
## 4. **Gulp** (on any key after MIN_SHOW_S): the bubble sinks back into the slime, which gulps it
##    down with a squash (cue `GulpCatch`) and a burst of sparkles; the card and the dim go and the
##    game goes on. The slime keeps all of what it learned (owner, 2026-10-09).
##
## The world is paused the whole time (pause reason `ceremony`); this layer runs on real time.
## Requests wait while a window is open (pause reason `modal`, so a crafted axe plays once the
## crafting window closes) and queue up. Nothing plays while main's `ability_ceremonies` is off
## (the test runner; `enabled`). Made by `request` under the tree's root, once. Every key and click belongs
## to the ceremony while it plays. godot/tools/render_ceremony.gd renders it for tuning.
##
## Owner: ui.

const Services := preload("res://game/shared/services.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
## The key an ability's card names (in the body-shapes rework mode a box ability's is `ability_use`).
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const CeremonyStage := preload("res://game/ui/ceremony/ceremony_stage.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const WeaponCatalog := preload("res://game/inventory/weapon_catalog.gd")

const NODE_NAME := "AbilityCeremony"
const WORLD_MAIN_GROUP := &"world_main"
## What a tool harvests, in the card's how-to.
const HARVEST_TARGETS := {"wood": "trees", "stone": "rocks", "iron": "iron ore"}
const LAYER := 95
const PAUSE_REASON := &"ceremony"
const CUE_FANFARE := &"Ceremony"
const CUE_GULP := &"GulpCatch"
const DIM_IN_S := 0.3
const RISE_S := 0.8
const CARD_AT_S := 0.9
const CARD_SLIDE_S := 0.35
const MIN_SHOW_S := 1.6
const HINT_AT_S := 1.8
const GULP_S := 0.4
const DIM_OUT_S := 0.3
const DIM_ALPHA := 0.7
## The spotlight around the slime, in world px (scaled by the camera's zoom on screen).
const SPOT_RADIUS := 130.0
const ICON_SIZE := 60.0
const SPARKLE_EVERY_S := 0.08
const BURST_SPARKLES := 24
const CARD_BOTTOM_PX := 170.0
const CARD_WIDTH_PX := 420.0

const DIM_SHADER := """
shader_type canvas_item;
uniform vec2 centre;
uniform vec2 size;
uniform float radius;
uniform float alpha;
void fragment() {
	float d = distance(UV * size, centre);
	float hole = smoothstep(radius * 0.55, radius, d);
	COLOR = vec4(0.02, 0.04, 0.03, alpha * hole);
}
"""

enum Step { IDLE, SHOW, GULP }

## Entries waiting: {"kicker", "name", "line", "how", "icon": Texture2D or null}.
var _queue: Array[Dictionary] = []
var _entry: Dictionary = {}
var _step: Step = Step.IDLE
var _age: float = 0.0
var _gulp_age: float = 0.0
var _dim: ColorRect
var _dim_material: ShaderMaterial
var _stage: CeremonyStage
var _icon: Sprite2D
var _icon_scale: Vector2 = Vector2.ONE
var _card: PanelContainer
var _hint: Label
var _next_sparkle: float = 0.0


## True while main's `ability_ceremonies` is on (off in the test runner).
static func enabled(tree: SceneTree) -> bool:
	var main := tree.get_first_node_in_group(WORLD_MAIN_GROUP) if tree != null else null
	return main != null and bool(main.get(&"ability_ceremonies"))


## Queues the ceremony of the ability `ability_id`; it plays as soon as no window is open.
static func request(tree: SceneTree, ability_id: StringName) -> void:
	_enqueue(tree, ability_entry(ability_id))


## Queues the ceremony of the permanent item `item_id`.
static func request_item(tree: SceneTree, item_id: String) -> void:
	_enqueue(tree, item_entry(item_id))


## Queues a Goo Heart's ceremony: `bonus` more max HP, `icon` its picture.
static func request_heart(tree: SceneTree, bonus: int, icon: Texture2D) -> void:
	_enqueue(tree, {"kicker": "Goo Heart", "name": "+%d max HP" % bonus,
		"line": "Your goo grows tougher: you can take more hits, and you are healed in full.", "how": "", "icon": icon})


static func ability_entry(ability_id: StringName) -> Dictionary:
	var key := ControlLabels.control_label(AbilityBox.key_action(ability_id))
	return {"kicker": "New ability", "name": AbilityDefinitions.title(ability_id),
		"line": AbilityDefinitions.ceremony_line(ability_id),
		"how": AbilityDefinitions.ceremony_how(ability_id, key) if not key.is_empty() else "",
		"icon": AbilityDefinitions.icon(ability_id)}


## A weapon ("New weapon"), a tool (a weapon that harvests: "New tool") or a key ("Key item").
static func item_entry(item_id: String) -> Dictionary:
	var definition := ItemCatalog.definition(item_id)
	var entry := {"kicker": "New item", "name": ItemCatalog.item_name(item_id), "line": str(definition.get("description", "")),
		"how": "", "icon": ItemIcons.icon(item_id)}
	match str(definition.get("category", "")):
		"weapon":
			var attack := ControlLabels.control_label(&"attack")
			var harvest: Variant = WeaponCatalog.find(item_id).get("harvestCapabilities")
			if harvest is Dictionary and not (harvest as Dictionary).is_empty():
				var targets: Array[String] = []
				for resource: Variant in harvest:
					targets.append(str(HARVEST_TARGETS.get(str(resource), str(resource))))
				entry["kicker"] = "New tool"
				entry["how"] = "It goes on your belt: swing it with %s at %s" % [attack, " and ".join(targets)]
			else:
				entry["kicker"] = "New weapon"
				entry["how"] = "It goes on your belt: swing it with %s" % attack
		"key":
			entry["kicker"] = "Key item"
			entry["how"] = "Keep it safe: it opens a lock somewhere."
	return entry


static func _enqueue(tree: SceneTree, entry: Dictionary) -> void:
	if tree == null or tree.root == null:
		return
	var ceremony := tree.root.get_node_or_null(NODE_NAME)
	if ceremony == null:
		ceremony = new()
		ceremony.name = NODE_NAME
		tree.root.add_child(ceremony)
	ceremony.call(&"enqueue", entry)


func enqueue(entry: Dictionary) -> void:
	_queue.append(entry)


## True while a ceremony plays.
func is_playing() -> bool:
	return _step != Step.IDLE


## The entry playing ({} when idle).
func current() -> Dictionary:
	return _entry


## How many entries wait for their turn.
func waiting() -> int:
	return _queue.size()


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = DIM_SHADER
	_dim_material.shader = shader
	_dim.material = _dim_material
	add_child(_dim)
	_stage = CeremonyStage.new()
	add_child(_stage)
	_icon = Sprite2D.new()
	_stage.add_child(_icon)
	_build_card()
	_hide_all()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.theme_type_variation = &"BannerPanel"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 4)
	_card.add_child(box)
	for spec: Array in [["Kicker", &"AccentLabel"], ["Name", &"AreaTitle"], ["Line", &""], ["How", &"CaptionLabel"],
			["Hint", &"CaptionLabel"]]:
		var label := Label.new()
		label.name = spec[0]
		label.theme_type_variation = spec[1]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(CARD_WIDTH_PX, 0.0)
		box.add_child(label)
	_hint = box.get_node("Hint") as Label


func _process(delta: float) -> void:
	if _step == Step.IDLE:
		_try_start()
		return
	_age += delta
	var player := _player()
	_stage.age = _age
	_stage.position = _slime_on_screen(player)
	_stage.scale = Vector2.ONE * _zoom()
	match _step:
		Step.SHOW:
			_show(delta, player)
		Step.GULP:
			_gulp(delta, player)
	_stage.age_sparkles(delta)
	_stage.queue_redraw()


func _try_start() -> void:
	if _queue.is_empty():
		return
	var world := Services.world()
	if world == null or world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL) or _player() == null:
		return
	var entry: Dictionary = _queue.pop_front()
	_entry = entry
	_step = Step.SHOW
	_age = 0.0
	_stage.sparkles.clear()
	_stage.rise = 0.0
	world.set_pause_reason(PAUSE_REASON, true)
	var player := _player()
	player.call(&"clear_input")
	player.call(&"face", Vector2.DOWN)
	player.call(&"play_animation", "idle", true)
	(_card.get_node("Box/Kicker") as Label).text = str(entry.get("kicker", ""))
	(_card.get_node("Box/Name") as Label).text = str(entry.get("name", ""))
	(_card.get_node("Box/Line") as Label).text = str(entry.get("line", ""))
	var how := _card.get_node("Box/How") as Label
	how.text = str(entry.get("how", ""))
	how.visible = not how.text.is_empty()
	_hint.text = "Press any key"
	_icon.texture = entry.get("icon") as Texture2D
	_icon_scale = Vector2.ONE
	if _icon.texture != null:
		_icon_scale = Vector2.ONE * ICON_SIZE / maxf(1.0, maxf(_icon.texture.get_width(), _icon.texture.get_height()))
	_icon.scale = _icon_scale
	_dim.visible = true
	_stage.visible = true
	_card.visible = false
	_hint.modulate.a = 0.0
	_cue(CUE_FANFARE)


func _show(delta: float, player: Node) -> void:
	_set_dim(clampf(_age / DIM_IN_S, 0.0, 1.0) * DIM_ALPHA, player)
	# The slime squashes, then stretches up as the bubble wells out of it, then settles.
	var swell := clampf(_age / (DIM_IN_S + RISE_S), 0.0, 1.0)
	var stretch := sin(swell * PI)
	_effect(player, Vector2(1.0 - 0.12 * stretch, 1.0 + 0.16 * stretch) if _age > DIM_IN_S * 0.5 else Vector2(1.1, 0.9))
	var rise := clampf((_age - DIM_IN_S) / RISE_S, 0.0, 1.0)
	_stage.rise = rise
	_icon.position = _stage.bubble_centre(rise)
	_icon.visible = rise > 0.05
	_icon.scale = _icon_scale * (0.4 + 0.6 * rise)
	_icon.rotation = sin(_age * 2.4) * 0.08
	_next_sparkle -= delta
	if rise >= 1.0 and _next_sparkle <= 0.0:
		_next_sparkle = SPARKLE_EVERY_S
		_stage.spawn_sparkle(_stage.bubble_centre(1.0), randf_range(20.0, 60.0))
	if _age >= CARD_AT_S:
		_place_card(clampf((_age - CARD_AT_S) / CARD_SLIDE_S, 0.0, 1.0))
	if _age >= HINT_AT_S:
		_hint.modulate.a = 0.55 + 0.45 * sin((_age - HINT_AT_S) * 4.0)


func _gulp(delta: float, player: Node) -> void:
	_gulp_age += delta
	var t := clampf(_gulp_age / GULP_S, 0.0, 1.0)
	_stage.rise = 1.0 - t
	_icon.position = _stage.bubble_centre(1.0 - t)
	_icon.scale = _icon_scale * (1.0 - t)
	_set_dim((1.0 - clampf((_gulp_age - GULP_S * 0.5) / DIM_OUT_S, 0.0, 1.0)) * DIM_ALPHA, player)
	_place_card(1.0 - t)
	# The gulp: a squash as the bubble goes in, a wobble back.
	var squash := sin(clampf((_gulp_age - GULP_S * 0.6) / (GULP_S * 0.7), 0.0, 1.0) * PI)
	_effect(player, Vector2(1.0 + 0.18 * squash, 1.0 - 0.16 * squash))
	if t >= 1.0 and _gulp_age >= GULP_S + DIM_OUT_S:
		_finish(player)


func _input(event: InputEvent) -> void:
	if _step == Step.IDLE:
		return
	var device := event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton
	if not device:
		return
	get_viewport().set_input_as_handled()
	if event.is_pressed() and not event.is_echo() and _step == Step.SHOW and _age >= MIN_SHOW_S:
		_step = Step.GULP
		_gulp_age = 0.0
		_hint.modulate.a = 0.0
		_cue(CUE_GULP)
		for i in BURST_SPARKLES:
			_stage.spawn_sparkle(_stage.bubble_centre(1.0), randf_range(80.0, 180.0))


func _finish(player: Node) -> void:
	_step = Step.IDLE
	_entry = {}
	_effect(player, Vector2.ONE)
	_hide_all()
	if player != null and is_instance_valid(player):
		player.call(&"clear_input")
	var world := Services.world()
	if world != null:
		world.set_pause_reason(PAUSE_REASON, false)


func _hide_all() -> void:
	_dim.visible = false
	_stage.visible = false
	_card.visible = false


func _place_card(shown: float) -> void:
	_card.visible = shown > 0.0
	var screen := get_viewport().get_visible_rect().size
	_card.reset_size()
	var size := _card.get_combined_minimum_size()
	var rest_y := screen.y - size.y - CARD_BOTTOM_PX
	_card.position = Vector2((screen.x - size.x) * 0.5, lerpf(screen.y + 8.0, rest_y, ease(shown, 0.3)))
	_card.modulate.a = shown


func _set_dim(alpha: float, player: Node) -> void:
	_dim_material.set_shader_parameter(&"alpha", alpha)
	_dim_material.set_shader_parameter(&"radius", SPOT_RADIUS * _zoom())
	_dim_material.set_shader_parameter(&"centre", _slime_on_screen(player))
	_dim_material.set_shader_parameter(&"size", get_viewport().get_visible_rect().size)


## The slime's centre on screen.
func _slime_on_screen(player: Node) -> Vector2:
	if player == null or not is_instance_valid(player):
		return get_viewport().get_visible_rect().size * 0.5
	var centre: Vector2 = player.call(&"get_centre")
	return get_viewport().get_canvas_transform() * centre


func _zoom() -> float:
	return get_viewport().get_canvas_transform().get_scale().x


func _effect(player: Node, factor: Vector2) -> void:
	if player != null and is_instance_valid(player):
		player.call(&"set_effect_scale", factor)


func _player() -> Node:
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	return player if player is Node and is_instance_valid(player) else null


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)

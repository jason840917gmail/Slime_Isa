extends CanvasLayer
## First-time control hints (Phaser `features/hints/ControlHints.ts` + `WorldScene.createControlHints`
## / `updateControlHints`, `ui.control-hint`): one pill near the bottom centre that tells the
## player a control while it would help and they have not used it yet. Using the control learns it
## for the run (story flag `hint.<id>`, saved with the run), and that hint never shows again.
##
## Hints in priority order (the first one not learned and useful now shows):
## | id | text | useful while |
## |---|---|---|
## | move | "Move with WASD" | always |
## | interact | "Right-click to talk, open or use" | the interact button has a target |
## | attack | "Left-click to attack" | a weapon is in hand |
## | dodge | "Press 1 to roll out of danger" | the dodge is learned and an enemy is within 360 px |
## | inventory | "Press E to open your bag" | the bag holds something |
## | crafting | "Press E, then Crafting, to craft" | the bag holds 40 wood |
## | weapon-switch | "Use the mouse wheel to switch weapons: tools only work in hand" | two owned weapons on the belt |
## | sprint | "Hold Shift to sprint" | `move` was learned |
## | map | "Press M for the map" | `inventory` was learned |
## | pause | "Press Esc to pause, save or change settings" | `inventory` was learned |
##
## Learning: moving (move), sprinting while moving (sprint), a swing starting (attack), a roll
## starting (dodge), the interact button running a target (interact, InteractionController
## `interacted`), the bag / crafting / world map / pause menu opening (inventory, crafting, map,
## pause), and the hand changing while two belt weapons are owned (weapon-switch; Phaser learns it
## only on a wheel or hotbar switch). Hidden (fading out) while the game is paused by a menu, the
## slime is dead or asleep, or there is no player.
##
## Look (styles.css .game-ui--control-hint): `HintPanel` pill, offsets (-230, -218)-(230, -180)
## from (0.5, 1), 16 px bold label with a dark shadow; opacity fades over 320 ms (none under
## reduce motion).
##
## Owner: interaction (hints).

const Services := preload("res://game/shared/services.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const LAYER := 10
const FLAG_PREFIX := "hint."
## WorldScene.ts:133-135.
const DODGE_ENEMY_RANGE_PX := 360.0
const CRAFTING_WOOD := 40
const FADE_MS := 320.0
const OFFSET_MIN := Vector2(-230.0, -218.0)
const OFFSET_MAX := Vector2(230.0, -180.0)
const FONT_SIZE := 16
const MAIN_GROUP := &"world_main"

## In priority order (CONTROL_HINTS).
const HINT_IDS: Array[StringName] = [&"move", &"interact", &"attack", &"dodge", &"inventory", &"crafting",
	&"weapon-switch", &"sprint", &"map", &"pause"]
## Game windows and shell menus whose opening learns a hint.
const MENU_HINTS := {&"inventory": &"inventory", &"crafting": &"crafting", &"world-map": &"map", &"pause-menu": &"pause"}

## The hint showing now (&"" when none).
var current: StringName = &""

var _panel: PanelContainer
var _label: Label
var _sprinting: bool = false
var _attacking: bool = false
var _rolling: bool = false
var _opacity: float = 0.0
var _bound_windows: Node
var _bound_shell: Node
var _bound_interaction: Node


func _init() -> void:
	name = "ControlHints"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Hint"
	_panel.theme_type_variation = &"HintPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = OFFSET_MIN.x
	_panel.offset_top = OFFSET_MIN.y
	_panel.offset_right = OFFSET_MAX.x
	_panel.offset_bottom = OFFSET_MAX.y
	_panel.modulate.a = 0.0
	add_child(_panel)
	_label = Label.new()
	_label.name = "Text"
	_label.theme_type_variation = &"HudLabel"
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	var run := Services.run()
	if run != null:
		run.weapon_equipped.connect(_on_weapon_equipped)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.weapon_equipped.is_connected(_on_weapon_equipped):
		run.weapon_equipped.disconnect(_on_weapon_equipped)


func _process(delta: float) -> void:
	_bind_sources()
	var player := _player()
	if player == null or _menu_paused() or bool(player.call(&"is_dead")) or bool(player.call(&"is_sleeping")):
		_show(&"")
	else:
		_learn_from_play(player)
		_show(_pick(player))
	_fade(delta)


## `learn`: the player used control `id`; its hint never returns in this run.
func learn(id: StringName) -> void:
	var run := Services.run()
	if run == null or is_learned(id):
		return
	run.set_flag(FLAG_PREFIX + String(id))
	if current == id:
		_show(&"")


func is_learned(id: StringName) -> bool:
	var run := Services.run()
	return run != null and run.has_flag(FLAG_PREFIX + String(id))


## The text of hint `id`, from the current key bindings.
static func hint_text(id: StringName) -> String:
	match id:
		&"move":
			return "Move with %s" % ControlLabels.movement_label()
		&"interact":
			return "%s to talk, open or use" % ControlLabels.control_verb(&"interact")
		&"attack":
			return "%s to attack" % ControlLabels.control_verb(&"attack")
		&"dodge":
			return "Press %s to roll out of danger" % ControlLabels.control_label(&"dodge")
		&"inventory":
			return "Press %s to open your bag" % ControlLabels.control_label(&"menu")
		&"crafting":
			return "Press %s, then Crafting, to craft" % ControlLabels.control_label(&"menu")
		&"weapon-switch":
			return "Use the %s to switch weapons: tools only work in hand" % ControlLabels.control_label(&"weapon_next").to_lower()
		&"sprint":
			return "Hold %s to sprint" % ControlLabels.control_label(&"sprint")
		&"map":
			return "Press %s for the map" % ControlLabels.control_label(&"map")
		&"pause":
			return "Press %s to pause, save or change settings" % ControlLabels.control_label(&"pause")
	return ""


## The text on the pill (kept while it fades out).
func text() -> String:
	return _label.text


## `isRelevant`.
func is_relevant(id: StringName, player: Node) -> bool:
	var run := Services.run()
	match id:
		&"move":
			return true
		&"interact":
			var main := get_tree().get_first_node_in_group(MAIN_GROUP)
			var interaction: Variant = main.get(&"interaction") if main != null else null
			return interaction != null and is_instance_valid(interaction) and bool((interaction as Node).call(&"has_candidate"))
		&"attack":
			return run != null and run.equipped_weapon_id() != null
		&"dodge":
			return bool(player.call(&"is_learned", &"dodge")) and _nearest_enemy_distance(player) < DODGE_ENEMY_RANGE_PX
		&"inventory":
			return run != null and not run.slots().is_empty()
		&"crafting":
			return run != null and run.item_count("wood") >= CRAFTING_WOOD
		&"weapon-switch":
			return _owned_belt_weapons() >= 2
		&"sprint":
			return is_learned(&"move")
		&"map", &"pause":
			return is_learned(&"inventory")
	return false


func _pick(player: Node) -> StringName:
	for id in HINT_IDS:
		if not is_learned(id) and is_relevant(id, player):
			return id
	return &""


func _show(id: StringName) -> void:
	current = id
	if id != &"":
		_label.text = hint_text(id)


func _fade(delta: float) -> void:
	var target := 1.0 if current != &"" else 0.0
	var shell := Services.shell()
	var instant := shell != null and shell.get_settings() != null and shell.get_settings().reduce_motion()
	_opacity = target if instant else move_toward(_opacity, target, delta * 1000.0 / FADE_MS)
	_panel.modulate.a = _opacity
	_panel.visible = _opacity > 0.0


## Controls used while playing that no other hook reports.
func _learn_from_play(player: Node) -> void:
	var moving := false
	for action: StringName in [&"move_up", &"move_down", &"move_left", &"move_right"]:
		moving = moving or bool(player.call(&"is_action_held", action))
	if moving:
		learn(&"move")
	var sprinting := moving and bool(player.call(&"is_action_held", &"sprint"))
	if sprinting and not _sprinting:
		learn(&"sprint")
	_sprinting = sprinting
	var combat: Variant = player.call(&"get_combat") if player.has_method(&"get_combat") else null
	var attacking := combat != null and is_instance_valid(combat) and bool((combat as Node).call(&"is_attacking"))
	if attacking and not _attacking:
		learn(&"attack")
	_attacking = attacking
	var rolling := bool(player.call(&"is_rolling"))
	if rolling and not _rolling:
		learn(&"dodge")
	_rolling = rolling


func _bind_sources() -> void:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	var windows: Variant = main.get(&"game_windows") if main != null else null
	if windows != null and windows != _bound_windows and (windows as Node).has_signal(&"window_opened"):
		_bound_windows = windows
		(windows as Node).connect(&"window_opened", _on_menu_opened)
	var interaction: Variant = main.get(&"interaction") if main != null else null
	if interaction != null and interaction != _bound_interaction and (interaction as Node).has_signal(&"interacted"):
		_bound_interaction = interaction
		(interaction as Node).connect(&"interacted", func(_payload: Dictionary) -> void: learn(&"interact"))
	var shell := Services.shell()
	if shell != null and shell != _bound_shell:
		_bound_shell = shell
		shell.menu_opened.connect(_on_menu_opened)


func _on_menu_opened(surface_id: StringName) -> void:
	if MENU_HINTS.has(surface_id):
		learn(MENU_HINTS[surface_id])


func _on_weapon_equipped(_payload: Dictionary) -> void:
	if _owned_belt_weapons() >= 2:
		learn(&"weapon-switch")


func _player() -> Node:
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	return player if player != null and is_instance_valid(player) else null


func _menu_paused() -> bool:
	if not get_tree().paused:
		return false
	var world := Services.world()
	return world == null or world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL) \
		or not world.has_pause_reason(Services.WorldServiceType.PAUSE_HIT_STOP)


func _nearest_enemy_distance(player: Node) -> float:
	var centre: Vector2 = player.call(&"get_centre")
	var best := INF
	for enemy: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not enemy.has_method(&"get_centre") or not enemy.is_inside_tree():
			continue
		var state: Dictionary = enemy.call(&"get_damage_state") if enemy.has_method(&"get_damage_state") else {}
		if bool(state.get("dead", false)):
			continue
		best = minf(best, centre.distance_to(enemy.call(&"get_centre")))
	return best


func _owned_belt_weapons() -> int:
	var run := Services.run()
	if run == null:
		return 0
	var owned := 0
	for weapon_id: Variant in run.weapon_slots():
		if weapon_id is String and run.item_count(weapon_id) > 0:
			owned += 1
	return owned

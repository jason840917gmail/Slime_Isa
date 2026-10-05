extends CanvasLayer
class_name GameHud
## Minimal top-left HUD for the trial (Phaser `ui.hud` scene + `HudSurfacePort.ts`). World spec 6.2.
## Built by hand: `Coins` label, `Health` bar ("HP %d / %d"), `Energy` bar ("Energy %d / %d") at
## (16,16), 284 x 68 CSS px, styles per the spec. Also owns the floating PlayerHealthBar (world
## spec 6.3), the BossHealthBar (boss spec 5) and the AbilityBar (abilities spec 2.6, bottom
## centre). layer = 10, PROCESS_MODE_ALWAYS, every Control `mouse_filter = IGNORE` except the
## ability bar's buttons.
##
## Data: `player.get_hud_snapshot()` once on bind, then on every `player.health_changed` and
## `player.energy_changed`; coins also follow `RunState.coins_changed`. Renders new-run defaults (hp/energy at their maxima from
## game-constants, coins 50) when no player is bound or the snapshot lacks a key.
##
## Owner: world builder.

const Services := preload("res://game/shared/services.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const PlayerHealthBar := preload("res://game/ui/player_health_bar.gd")
const HudBar := preload("res://game/ui/hud_bar.gd")
const BossHealthBar := preload("res://game/ui/boss_health_bar.gd")
const AbilityBar := preload("res://game/ui/ability_bar.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

## Layout (CSS px; `offsetMin [16,16]`, `offsetMax [300,84]` in ui/hud.scene.json).
const ROOT_POSITION := Vector2(16.0, 16.0)
const ROOT_SIZE := Vector2(284.0, 68.0)
const COINS_RECT := Rect2(0.0, 0.0, 284.0, 22.0)
const HEALTH_RECT := Rect2(0.0, 28.0, 284.0, 18.0)
const ENERGY_RECT := Rect2(0.0, 50.0, 284.0, 18.0)
## Field-kit theme tones (src/styles.css; res://game/ui/theme/ui_tokens.gd). The look of the coins
## label and the bars comes from the UI theme's `HudLabel` / `HudBar` variations (docs/godot/UI_THEME.md).
const TONE_DANGER := UiTokens.DANGER
const TONE_WARNING := UiTokens.WARNING
## Coins of a new run (content/initial-state/InitialRun.ts:15), shown until RunState has a run.
const NEW_RUN_COINS := 50.0

var _player: PlayerScript
var _snapshot: Dictionary = {}
var _root: Control
var _coins_label: Label
var _health_bar: HudBar
var _energy_bar: HudBar
var _floating_bar: PlayerHealthBar
var _boss_bar: BossHealthBar
var _ability_bar: AbilityBar


## Builds the controls and the PlayerHealthBar child; layer 10; PROCESS_MODE_ALWAYS.
func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	refresh(_default_snapshot())
	var run := Services.run()
	if run != null and not run.coins_changed.is_connected(_on_coins_changed):
		run.coins_changed.connect(_on_coins_changed)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.coins_changed.is_connected(_on_coins_changed):
		run.coins_changed.disconnect(_on_coins_changed)


## The player's energy changed (GameState `energy.changed`): {"energy", "maxEnergy", "delta"}.
func _on_energy_changed(payload: Dictionary) -> void:
	refresh({"energy": payload.get("energy", 0.0), "maxEnergy": payload.get("maxEnergy", 0.0)})


## RunState coins changed (GameState `coins.changed`): {"coins", "delta"}.
func _on_coins_changed(payload: Dictionary) -> void:
	refresh({"coins": payload.get("coins", 0)})


## The boss health bar (res://game/ui/boss_health_bar.gd).
func get_boss_bar() -> BossHealthBar:
	return _boss_bar


## The ability bar (res://game/ui/ability_bar.gd).
func get_ability_bar() -> AbilityBar:
	return _ability_bar


## Subscribes to `player.health_changed` and `player.respawned`, reads the snapshot, binds the
## floating health bar.
func bind_player(player: PlayerScript) -> void:
	if _player != null and is_instance_valid(_player):
		if _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.disconnect(_on_health_changed)
		if _player.respawned.is_connected(_on_respawned):
			_player.respawned.disconnect(_on_respawned)
		if _player.energy_changed.is_connected(_on_energy_changed):
			_player.energy_changed.disconnect(_on_energy_changed)
	_player = player
	if player == null:
		return
	player.health_changed.connect(_on_health_changed)
	player.respawned.connect(_on_respawned)
	player.energy_changed.connect(_on_energy_changed)
	refresh(player.get_hud_snapshot())
	if _floating_bar != null:
		_floating_bar.bind_player(player)
	if _ability_bar != null:
		_ability_bar.player = player


## Applies a snapshot {"hp", "maxHp", "energy", "maxEnergy", "coins"} (Phaser keys) to the
## three controls. Missing keys keep their previous value (new-run defaults at first).
func refresh(snapshot: Dictionary) -> void:
	if _snapshot.is_empty():
		_snapshot = _default_snapshot()
	for key: String in ["hp", "maxHp", "energy", "maxEnergy", "coins"]:
		if snapshot.has(key) and (typeof(snapshot[key]) == TYPE_INT or typeof(snapshot[key]) == TYPE_FLOAT):
			_snapshot[key] = float(snapshot[key])
	if _coins_label == null:
		return
	_coins_label.text = "Coins " + format_count(_snapshot["coins"])
	_health_bar.set_values(_snapshot["hp"], _snapshot["maxHp"])
	_energy_bar.set_values(_snapshot["energy"], _snapshot["maxEnergy"])


## `formatHudCount` (world spec 6.2): < 10000 -> integer with "," separators; < 1e6 ->
## "%.1fk" % min(999.9, n/1000); < 1e9 -> "%.1fm"; else "999m+"; negative/fraction -> max(0, floor(n)).
static func format_count(value: float) -> String:
	var count := maxf(0.0, floorf(value)) if is_finite(value) else 0.0
	if count < 10000.0:
		var digits := str(int(count))
		if digits.length() > 3:
			digits = digits.substr(0, digits.length() - 3) + "," + digits.substr(digits.length() - 3)
		return digits
	if count < 1000000.0:
		return "%.1fk" % minf(999.9, count / 1000.0)
	if count < 1000000000.0:
		return "%.1fm" % minf(999.9, count / 1000000.0)
	return "999m+"


func _on_health_changed(payload: Dictionary) -> void:
	refresh(payload)


func _on_respawned(_payload: Dictionary) -> void:
	if _player != null and is_instance_valid(_player):
		refresh(_player.get_hud_snapshot())


func _default_snapshot() -> Dictionary:
	var max_hp := 0.0
	var max_energy := 0.0
	var constants := Services.constants()
	if constants != null and constants.is_loaded():
		max_hp = constants.number("character.player.stats.maxHp")
		max_energy = constants.number("character.player.stats.maxEnergy")
	return {"hp": max_hp, "maxHp": max_hp, "energy": max_energy, "maxEnergy": max_energy, "coins": NEW_RUN_COINS}


func _build() -> void:
	_root = Control.new()
	_root.name = "HudRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.position = ROOT_POSITION
	_root.size = ROOT_SIZE
	# Until the theme is the project theme (gui/theme/custom) every HUD Control gets it explicitly.
	_root.theme = UiTokens.theme()
	add_child(_root)

	_coins_label = Label.new()
	_coins_label.name = "Coins"
	_coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_label.position = COINS_RECT.position
	_coins_label.size = COINS_RECT.size
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins_label.theme_type_variation = &"HudLabel"
	_coins_label.add_theme_color_override(&"font_color", TONE_WARNING)
	_root.add_child(_coins_label)

	_health_bar = _make_bar("Health", HEALTH_RECT, "HP", TONE_DANGER)
	_energy_bar = _make_bar("Energy", ENERGY_RECT, "Energy", TONE_WARNING)

	_floating_bar = PlayerHealthBar.new()
	_floating_bar.name = "PlayerHealthBar"
	_floating_bar.theme = _root.theme
	add_child(_floating_bar)

	# The boss health bar (boss spec 5); it binds itself to every camp in the "boss_camp" group.
	_boss_bar = BossHealthBar.new()
	_boss_bar.name = "BossHealthBar"
	_boss_bar.theme = _root.theme
	add_child(_boss_bar)

	# The ability bar, bottom centre (abilities spec 2.6).
	_ability_bar = AbilityBar.new()
	_ability_bar.theme = _root.theme
	add_child(_ability_bar)
	# The minimap and the world map window (res://game/ui/map/, docs/godot/specs/map.md).
	add_child(preload("res://game/ui/map/map_ui.gd").new())


func _make_bar(node_name: String, rect: Rect2, label: String, tone: Color) -> HudBar:
	var bar := HudBar.new()
	bar.name = node_name
	bar.position = rect.position
	bar.size = rect.size
	bar.configure(label, tone)
	_root.add_child(bar)
	return bar

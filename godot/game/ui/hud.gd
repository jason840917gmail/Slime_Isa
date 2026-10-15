extends CanvasLayer
class_name GameHud
## The game HUD (Phaser `ui.hud` scene + `HudSurfacePort.ts`, world spec 6.2; since 2026-10-08 the
## HUD console of roadmap 4.12, docs/design/2026-10-07-hud-console-mockup.md). layer = 10,
## PROCESS_MODE_ALWAYS.
##
## - The console along the bottom (game/ui/console/hud_console.gd): the minimap (MapUi's, docked),
##   the life and energy orbs (they replaced the HP and energy bars), the weapon in hand
##   (WeaponHotbar, crafting spec 8.6), the AbilityBar (abilities spec 2.6) and the menu buttons.
##   This node places the WeaponHotbar, the AbilityBar and the minimap on the console's rects on
##   every resize and on the console's `layout_changed` (body-shapes rework mode: the Shape slot
##   showing or hiding, the ability slots changing); main.gd gives the WorldCamera the console's
##   HEIGHT as its `bottom_inset`.
## - Top left: the coin chip (`Coins`, HudLabel), and the QuestTracker under it (quests spec 4.4).
## - The floating PlayerHealthBar (world spec 6.3) and the BossHealthBar (boss spec 5).
## Every Control ignores the mouse except the console's buttons, the weapon slot, the ability
## buttons and the tracker's quest buttons.
##
## Data: `player.get_hud_snapshot()` once on bind, then on every `player.health_changed` and
## `player.energy_changed`; coins also follow `RunState.coins_changed`. The orbs show their number
## only when a value changes after the bind (GooOrb). The life orb's heart pips: one whole heart per
## Goo Heart found (`RunState.player["goo_hearts"]`) until heart quarters are built (roadmap 5.3).
## Renders new-run defaults (hp/energy at their maxima from game-constants, coins 50) when no
## player is bound or the snapshot lacks a key.
##
## Owner: world builder (the console: UI).

const Services := preload("res://game/shared/services.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const PlayerHealthBar := preload("res://game/ui/player_health_bar.gd")
const BossHealthBar := preload("res://game/ui/boss_health_bar.gd")
const AbilityBar := preload("res://game/ui/ability_bar.gd")
const HudConsole := preload("res://game/ui/console/hud_console.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

## The coin chip, top left (canvas units).
const COIN_CHIP := Rect2(14.0, 12.0, 78.0, 28.0)
const COIN_SIZE := 18.0
const TONE_WARNING := UiTokens.WARNING
## Coins of a new run (content/initial-state/InitialRun.ts:15), shown until RunState has a run.
const NEW_RUN_COINS := 50.0
## Quarters per Goo Heart on the life orb (a Goo Heart counts as a whole heart until 5.3).
const QUARTERS_PER_HEART := 4

var _player: PlayerScript
var _snapshot: Dictionary = {}
var _root: Control
var _coins_label: Label
var _console: HudConsole
var _hotbar: Control
var _map_ui: Node
var _floating_bar: PlayerHealthBar
var _boss_bar: BossHealthBar
var _ability_bar: AbilityBar


## Builds the controls; layer 10; PROCESS_MODE_ALWAYS.
func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	refresh(_default_snapshot(), false)
	var run := Services.run()
	if run != null and not run.coins_changed.is_connected(_on_coins_changed):
		run.coins_changed.connect(_on_coins_changed)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


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


## The HUD console (res://game/ui/console/hud_console.gd).
func get_console() -> HudConsole:
	return _console


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
	if _console != null:
		_console.player = player
	if player == null:
		return
	player.health_changed.connect(_on_health_changed)
	player.respawned.connect(_on_respawned)
	player.energy_changed.connect(_on_energy_changed)
	refresh(player.get_hud_snapshot(), false)
	if _floating_bar != null:
		_floating_bar.bind_player(player)
	if _ability_bar != null:
		_ability_bar.player = player


## Applies a snapshot {"hp", "maxHp", "energy", "maxEnergy", "coins"} (Phaser keys) to the coin
## chip and the orbs. Missing keys keep their previous value (new-run defaults at first). With
## `announce` an orb whose value changed shows its number for a moment.
func refresh(snapshot: Dictionary, announce: bool = true) -> void:
	if _snapshot.is_empty():
		_snapshot = _default_snapshot()
	for key: String in ["hp", "maxHp", "energy", "maxEnergy", "coins"]:
		if snapshot.has(key) and (typeof(snapshot[key]) == TYPE_INT or typeof(snapshot[key]) == TYPE_FLOAT):
			_snapshot[key] = float(snapshot[key])
	if _coins_label == null:
		return
	_coins_label.text = format_count(_snapshot["coins"])
	_console.life_orb.set_value(_snapshot["hp"], _snapshot["maxHp"], announce)
	_console.energy_orb.set_value(_snapshot["energy"], _snapshot["maxEnergy"], announce)
	_console.life_orb.set_heart_quarters(_heart_quarters())


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
		refresh(_player.get_hud_snapshot(), false)


func _default_snapshot() -> Dictionary:
	var max_hp := 0.0
	var max_energy := 0.0
	var constants := Services.constants()
	if constants != null and constants.is_loaded():
		max_hp = constants.number("character.player.stats.maxHp")
		max_energy = constants.number("character.player.stats.maxEnergy")
	return {"hp": max_hp, "maxHp": max_hp, "energy": max_energy, "maxEnergy": max_energy, "coins": NEW_RUN_COINS}


## The hearts on the life orb in quarters: a whole heart per Goo Heart found (until 5.3).
func _heart_quarters() -> Array[int]:
	var hearts: Array[int] = []
	var run := Services.run()
	if run != null:
		for index in int(run.player.get("goo_hearts", 0)):
			hearts.append(QUARTERS_PER_HEART)
	return hearts


## Places the weapon slot, the ability bar and the minimap on the console's rects.
func _layout() -> void:
	if _console == null or not _console.is_inside_tree():
		return
	_console.set_ability_count(AbilityBar.slots().size())
	var rects := _console.rects()
	_hotbar.position = (rects["weapon"] as Rect2).position
	_ability_bar.position = (rects["abilities"] as Rect2).position
	var minimap: Control = _map_ui.get(&"minimap") if _map_ui != null else null
	if minimap != null:
		minimap.set(&"dock", rects["minimap"])


func _build() -> void:
	_root = Control.new()
	_root.name = "HudRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.position = COIN_CHIP.position
	_root.size = COIN_CHIP.size
	# Until the theme is the project theme (gui/theme/custom) every HUD Control gets it explicitly.
	_root.theme = UiTokens.theme()
	add_child(_root)

	var chip := Panel.new()
	chip.name = "CoinChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size = COIN_CHIP.size
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(UiTokens.SURFACE_BASE, 0.78)
	chip_style.border_color = Color(UiTokens.BORDER, 0.8)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(int(COIN_CHIP.size.y * 0.5))
	chip.add_theme_stylebox_override(&"panel", chip_style)
	_root.add_child(chip)
	var coin := Control.new()
	coin.name = "Coin"
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.position = Vector2(6.0, (COIN_CHIP.size.y - COIN_SIZE) * 0.5)
	coin.size = Vector2(COIN_SIZE, COIN_SIZE)
	coin.draw.connect(_draw_coin.bind(coin))
	_root.add_child(coin)

	_coins_label = Label.new()
	_coins_label.name = "Coins"
	_coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_label.position = Vector2(COIN_SIZE + 12.0, 0.0)
	_coins_label.size = Vector2(COIN_CHIP.size.x - COIN_SIZE - 16.0, COIN_CHIP.size.y)
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins_label.theme_type_variation = &"HudLabel"
	_coins_label.add_theme_color_override(&"font_color", UiTokens.TEXT)
	_root.add_child(_coins_label)

	# The console along the bottom (roadmap 4.12); the pieces below are placed on it by _layout().
	_console = HudConsole.new()
	_console.theme = _root.theme
	add_child(_console)
	_console.layout_changed.connect(_layout)

	_floating_bar = PlayerHealthBar.new()
	_floating_bar.name = "PlayerHealthBar"
	_floating_bar.theme = _root.theme
	add_child(_floating_bar)

	# The boss health bar (boss spec 5); it binds itself to every camp in the "boss_camp" group.
	_boss_bar = BossHealthBar.new()
	_boss_bar.name = "BossHealthBar"
	_boss_bar.theme = _root.theme
	add_child(_boss_bar)

	# The ability buttons, on the console (abilities spec 2.6).
	_ability_bar = AbilityBar.new()
	_ability_bar.theme = _root.theme
	add_child(_ability_bar)

	# The weapon in hand and its carousel, on the console (res://game/ui/weapon_hotbar.gd).
	_hotbar = preload("res://game/ui/weapon_hotbar.gd").new()
	_hotbar.theme = _root.theme
	add_child(_hotbar)

	# The minimap (docked in the console) and the world map window (res://game/ui/map/).
	_map_ui = preload("res://game/ui/map/map_ui.gd").new()
	add_child(_map_ui)

	# The quest tracker under the coin chip (quests spec 4.4, res://game/ui/quest_tracker.gd).
	add_child(preload("res://game/ui/quest_tracker.tscn").instantiate())


## A gold coin: rim, face, inner ring and a glint.
func _draw_coin(coin: Control) -> void:
	var r := COIN_SIZE * 0.5
	var c := Vector2(r, r)
	coin.draw_circle(c, r, Color("#966014"))
	coin.draw_circle(c, r * 0.84, Color("#fac446"))
	coin.draw_arc(c, r * 0.52, 0.0, TAU, 24, Color("#c4821e"), 1.5, true)
	coin.draw_circle(c + Vector2(-r * 0.38, -r * 0.42), r * 0.2, Color("#fff0be", 0.8))

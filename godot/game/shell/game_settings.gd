extends RefCounted
class_name GameSettings
## Per-device player preferences: the sound mix, screen shake, reduce motion and the attack aim
## (Phaser `infrastructure/persistence/GameSettingsStore.ts` + `features/settings/
## GameSettingsService.ts`; docs/godot/specs/shell.md section 3). Deliberately separate from save
## slots: loading a save or starting a new game never changes how loud the game is or how much
## the screen moves.
##
## Stored in user://settings.cfg (ConfigFile: `[meta] version=1`, `[settings]` one key per
## setting). Every change is clamped, saved, applied and announced with `changed`.
## Applied to: the audio buses through `MusicDirector.apply_mix` (Master volume + mute, Effects,
## Ambience = effects, Music; linear gains like Phaser's WebAudio) and GameFeel
## (`screen_shake_scale`, `reduce_motion`).
## `attack_aim` is stored only (Phaser changes it from the dev panel; the port aims at the pointer).
## `control_scheme` is read by the player (game/player/mouse/control_scheme.gd) when it handles a
## mouse button; the Settings window and F2 change it; the keys-only scheme also rebinds the
## InputMap (`apply_to_input`).
##
## Owner: shell.

const Services := preload("res://game/shared/services.gd")
const MusicDirector := preload("res://game/audio/music_director.gd")

## Emitted after every change, with `values()`.
signal changed(values: Dictionary)

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "settings"
const META_SECTION := "meta"
## StoredGameSettings.version (GameSettingsStore.ts:37); another version reads as defaults.
const VERSION := 1
## DEFAULT_GAME_SETTINGS (GameSettingsStore.ts:27-35), snake_case.
const DEFAULTS := {
	"master": 0.8,
	"effects": 1.0,
	"music": 0.7,
	"muted": false,
	"screen_shake": 1.0,
	"reduce_motion": false,
	"attack_aim": "pointer",
	"control_scheme": "keyboard",
}
## How the mouse drives the slime (game/player/mouse/control_scheme.gd): the keyboard scheme (WASD
## walks), click to move (Diablo), right-click to move (MOBA), face the pointer (W walks toward it)
## or keys only (no mouse: the arrows walk, A attacks, W interacts).
const CONTROL_SCHEMES: PackedStringArray = ["keyboard", "click", "moba", "pointer", "keys"]
const KEYS_ONLY_SCHEME := "keys"
const KeyBindings := preload("res://game/player/mouse/key_bindings.gd")
## Settings in [0, 1] (`unitInterval`).
const UNIT_KEYS: PackedStringArray = ["master", "effects", "music", "screen_shake"]
const ATTACK_AIM_FACING := "facing"
const ATTACK_AIM_POINTER := "pointer"

var path: String
var _values: Dictionary = DEFAULTS.duplicate()


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path


## A copy of every setting (snake_case keys, DEFAULTS' types).
func values() -> Dictionary:
	return _values.duplicate()


func value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func master() -> float:
	return float(_values["master"])


func effects() -> float:
	return float(_values["effects"])


func music() -> float:
	return float(_values["music"])


func muted() -> bool:
	return bool(_values["muted"])


func screen_shake() -> float:
	return float(_values["screen_shake"])


func reduce_motion() -> bool:
	return bool(_values["reduce_motion"])


## `GameSettingsService.shakeScale`: the slider, or 0 with reduce motion.
func shake_scale() -> float:
	return 0.0 if reduce_motion() else screen_shake()


## Loads the file; missing, unreadable or another version -> defaults (returns false then).
func read() -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK or int(config.get_value(META_SECTION, "version", 0)) != VERSION:
		_values = DEFAULTS.duplicate()
		return false
	var raw := {}
	for key: String in DEFAULTS:
		if config.has_section_key(SECTION, key):
			raw[key] = config.get_value(SECTION, key)
	_values = parse(raw)
	return true


## Saves the file. False when it cannot be written (the settings still apply this session).
func write() -> bool:
	var config := ConfigFile.new()
	config.set_value(META_SECTION, "version", VERSION)
	for key: String in DEFAULTS:
		config.set_value(SECTION, key, _values[key])
	return config.save(path) == OK


## `GameSettingsService.update`: merges `change`, clamps, saves, applies and emits `changed`.
func update(change: Dictionary) -> void:
	var merged := _values.duplicate()
	merged.merge(change, true)
	_values = parse(merged)
	write()
	apply()
	changed.emit(values())


## The Settings window's "Defaults" button (`settings.update(DEFAULT_GAME_SETTINGS)`).
func reset() -> void:
	update(DEFAULTS)


## Applies the mix to the buses and the motion settings to GameFeel.
func apply() -> void:
	apply_to_buses()
	apply_to_feel()
	apply_to_input()


## `applyMix` (SettingsSurfacePort.ts:81-87): Master = master volume and mute; Effects and
## Ambience = effects; Music = music (MusicDirector.apply_mix, static, no autoload needed).
func apply_to_buses() -> void:
	MusicDirector.apply_mix(master(), effects(), music(), muted())


## The keys-only control scheme rebinds the InputMap (game/player/mouse/key_bindings.gd); any other
## scheme puts it back.
func apply_to_input() -> void:
	KeyBindings.apply(str(_values["control_scheme"]) == KEYS_ONLY_SCHEME)


## GameFeel scales camera shake by `screen_shake` and skips shake and hit-stop under reduce motion.
func apply_to_feel() -> void:
	var feel := Services.feel()
	if feel == null:
		return
	feel.screen_shake_scale = screen_shake()
	feel.reduce_motion = reduce_motion()


## `parse()` (GameSettingsStore.ts:42-52): unit values clamped to [0, 1] (not a finite number ->
## default), booleans true only when exactly true, attack aim "facing" or "pointer".
static func parse(raw: Dictionary) -> Dictionary:
	var parsed := {}
	for key: String in UNIT_KEYS:
		var number: Variant = raw.get(key)
		var is_number := typeof(number) == TYPE_FLOAT or typeof(number) == TYPE_INT
		parsed[key] = clampf(float(number), 0.0, 1.0) if is_number and is_finite(float(number)) else float(DEFAULTS[key])
	parsed["muted"] = typeof(raw.get("muted")) == TYPE_BOOL and bool(raw["muted"])
	parsed["reduce_motion"] = typeof(raw.get("reduce_motion")) == TYPE_BOOL and bool(raw["reduce_motion"])
	parsed["attack_aim"] = ATTACK_AIM_FACING if str(raw.get("attack_aim", "")) == ATTACK_AIM_FACING else ATTACK_AIM_POINTER
	var scheme := str(raw.get("control_scheme", ""))
	parsed["control_scheme"] = scheme if CONTROL_SCHEMES.has(scheme) else str(DEFAULTS["control_scheme"])
	return parsed


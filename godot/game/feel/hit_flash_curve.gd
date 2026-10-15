extends Node
## Drives one sprite's hit flash along the rework's white-then-tint curve (combat-feel plan section 6
## "Flash": taps white for 1 frame (17 ms), then the hurt tint fades over 90 ms; finishers white for
## 50 ms, then the tint over 120 ms). Made by `HitFlash.flash_curve` as a child named
## `HitFlash.CURVE_NODE` of the flashed CanvasItem, reused for every later flash of it.
##
## PROCESS_MODE_ALWAYS and real time (presentation): the white shows while a hit-stop freezes the
## tree. Each frame it writes the hit-flash material's `flash_color` and `flash_amount`; at the end
## it leaves `flash_amount` at 0 and stops processing. A new `start` restarts the curve.
##
## Owner: juice.

## How strongly the white and the tint cover the sprite at their peak (flash_amount), so the
## victim's painted detail still shows through (art pass, 2026-10-12: a full fill turned the
## dummies into flat white and pink silhouettes for the whole hit-stop).
const WHITE_STRENGTH := 0.8
const TINT_STRENGTH := 0.55

var _material: ShaderMaterial
var _white: Color = Color.WHITE
var _tint: Color = Color.WHITE
var _white_ms: float = 0.0
var _tint_ms: float = 0.0
var _started_ms: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts the curve on `material` (a hit-flash ShaderMaterial): `white` at full strength for
## `white_ms`, then `tint` from full strength down to none over `tint_ms` (real ms).
func start(material: ShaderMaterial, white: Color, tint: Color, white_ms: float, tint_ms: float) -> void:
	_material = material
	_white = white
	_tint = tint
	_white_ms = maxf(0.0, white_ms)
	_tint_ms = maxf(0.0, tint_ms)
	_started_ms = float(Time.get_ticks_msec())
	set_process(true)
	_apply(0.0)


## True while the curve still shows a colour.
func is_running() -> bool:
	return is_processing()


func _process(_delta: float) -> void:
	_apply(float(Time.get_ticks_msec()) - _started_ms)


func _apply(elapsed_ms: float) -> void:
	if _material == null:
		set_process(false)
		return
	if elapsed_ms < _white_ms:
		_material.set_shader_parameter(&"flash_color", _white)
		_material.set_shader_parameter(&"flash_amount", WHITE_STRENGTH)
		return
	var fade := elapsed_ms - _white_ms
	if fade >= _tint_ms:
		_material.set_shader_parameter(&"flash_amount", 0.0)
		set_process(false)
		return
	_material.set_shader_parameter(&"flash_color", _tint)
	_material.set_shader_parameter(&"flash_amount", TINT_STRENGTH * (1.0 - fade / maxf(1.0, _tint_ms)))

extends RefCounted
## Turns raw mouse-wheel scrolling into single weapon steps (Phaser
## `features/player/WheelStepper.ts`). Scrolling adds up per direction until one notch (50 px);
## after a step the wheel must stay still for `input.weaponWheelStepLockMs` (150 ms) before the
## next one, and any scroll during that lock extends it, so a free-spinning wheel or a trackpad
## swipe moves one weapon. Times are event (real) time in ms. Crafting spec 8.5.
##
## Owner: crafting / inventory (used by player.gd).

const Services := preload("res://game/shared/services.gd")

## `WHEEL_NOTCH_PX` (WheelStepper.ts:2).
const NOTCH_PX := 50.0
const LOCK_PATH := "input.weaponWheelStepLockMs"

var _direction: StringName = &""
var _accumulated_px: float = 0.0
var _quiet_until_ms: float = -INF
## The step lock in ms (game-constants `input.weaponWheelStepLockMs`), read once.
var _lock_ms: float = -1.0


## True when this scroll of `delta_px` in `direction` completes a step at `t_ms`.
func step(direction: StringName, delta_px: float, t_ms: float) -> bool:
	if t_ms < _quiet_until_ms:
		_quiet_until_ms = t_ms + lock_ms()
		_accumulated_px = 0.0
		return false
	if direction != _direction:
		_direction = direction
		_accumulated_px = 0.0
	_accumulated_px += maxf(0.0, delta_px)
	if _accumulated_px < NOTCH_PX:
		return false
	_accumulated_px = 0.0
	_quiet_until_ms = t_ms + lock_ms()
	return true


func reset() -> void:
	_direction = &""
	_accumulated_px = 0.0
	_quiet_until_ms = -INF


func lock_ms() -> float:
	if _lock_ms < 0.0:
		var constants := Services.constants()
		_lock_ms = constants.number(LOCK_PATH) if constants != null else 0.0
	return _lock_ms

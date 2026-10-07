extends Node
## Autoload `SimClock`: the one gameplay simulation clock, in milliseconds.
##
## Phaser keeps per-script `simulationTimeMs` accumulators plus a world clock, all advanced only
## by fixed physics steps (player spec section 3, combat spec 7.1 / 17, enemy spec 4.1). The port
## uses one clock for every gameplay timer: roll, i-frames, knockback, cooldowns, input buffer,
## enemy stun/flash/attack/search/sight throttle, despawn, spawn intervals, weapon windows,
## combo window, and the router's `simulation_time`.
##
## - Advanced by `delta * 1000` in `_physics_process` (60 Hz). `process_physics_priority` is
##   set very low so it ticks before every other node in the same physics step; all scripts read
##   the same `now_ms` during a step.
## - PROCESS_MODE_PAUSABLE: it stops while the tree is paused (hit-stop and modal pause), which
##   is exactly Phaser's "simulation clock frozen during hit-stop".
## - Never use Time.get_ticks_msec() for gameplay timers; real time is only for presentation that
##   Phaser ran on scene time (player hit flash, floating text, health-bar visibility, camera).
## Access: `Services.clock().now_ms` or `Services.now_ms()`.
##
## Owner: world builder.

## Current simulation time in ms (starts at 0 when the game starts).
var now_ms: float = 0.0
## Number of physics steps advanced so far.
var step_count: int = 0
## Length of the last step in ms (16.667 at 60 Hz).
var last_step_ms: float = 0.0


## Sets `process_mode = PROCESS_MODE_PAUSABLE` and `process_physics_priority = -1000`.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -1000


## `now_ms += delta * 1000.0`, `step_count += 1`, `last_step_ms = delta * 1000.0`.
func _physics_process(delta: float) -> void:
	last_step_ms = delta * 1000.0
	now_ms += last_step_ms
	step_count += 1


## Resets the clock to 0 (world reload). Not used by the trial.
func reset() -> void:
	now_ms = 0.0
	step_count = 0
	last_step_ms = 0.0

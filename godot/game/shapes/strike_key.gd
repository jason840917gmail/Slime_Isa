@tool
class_name StrikeKey
extends Resource
## One moment of a strike direction's timeline. Its time is `phase` + `share`: windup 0-1, active 1-2,
## recovery 2-3 (the game stretches that over the step's milliseconds). From this key on, `frame`, `layer`,
## `view` and `view_frame` hold until the next key; `angle`, `length` and `head_angle` slide straight to the
## next key, or snap there when that key has `jump`. Keep the keys in time order.

enum Phase { WINDUP, ACTIVE, RECOVERY }
enum Layer { BEHIND, FRONT }

@export var phase: Phase = Phase.WINDUP
@export_range(0.0, 1.0, 0.001) var share: float = 0.0
## The body's frame on the strip (1 to 6; 1 is the rest frame and never shows).
@export_range(1, 6) var frame: int = 1
## The weapon's direction on screen in degrees: 0 right, 90 down.
@export var angle: float = 0.0
## How far the weapon is out: 0 inside the jelly, 1 full.
@export_range(0.0, 1.0, 0.01) var length: float = 0.0
## Behind the body, or in front of it (over the world).
@export var layer: Layer = Layer.BEHIND
## The Axe's and the Hammer's painted front or back view; "side" draws the side weapon.
@export_enum("side", "toward", "away") var view: String = "side"
@export_range(1, 4) var view_frame: int = 1
## The Hammer's head in degrees (the handle's angle when the head turns with it).
@export var head_angle: float = 0.0
## Snap to this key's angle, length and head angle at its moment instead of sliding there.
@export var jump: bool = false


## The key's time on the strike's 0-3 clock.
func unit() -> float:
	return float(phase) + clampf(share, 0.0, 1.0)

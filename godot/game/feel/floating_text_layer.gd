extends CanvasLayer
class_name FloatingTextLayer
## Pooled floating texts (Phaser `features/ui/FloatingTextSurfacePort.ts`). Combat spec 12.
## Screen-space Labels projected every frame from their world point
## (`get_viewport().get_canvas_transform() * world_point`). Created by GameFeel.
## layer 8 (above the world and the arrival fade on 5, below the HUD on 10), PROCESS_MODE_ALWAYS.
## Body-shapes rework (combat-feel plan section 6 "Number"; docs/godot/BODY_SHAPES.md "Juice"):
## `spawn_pop` shows a number that pops from `pop_scale` down to 1.0 over `pop_ms` (real time,
## ease-out), then rises and fades as usual at scale 1.0 (the finisher's big yellow number).
## `spawn` is unchanged. `set_picture_speed(speed)` (GameFeel, every frame: `GameFeel.picture_speed()`)
## runs the texts' clock at that speed: in the rework mode a hit-stop holds the numbers with the
## frozen world (a finisher's pop shows at its full size until the freeze ends) and the room clear's
## stutter slows them; it stays 1 with the mode off, so the clock is real time as before.
##
## Owner: combat builder (the pop: juice).

const POOL_SIZE := 24
const BIG_DURATION_MS := 900.0
const SMALL_DURATION_MS := 700.0
const BIG_RISE_PX := 48.0
const SMALL_RISE_PX := 34.0
const BIG_FONT_SIZE := 22
const SMALL_FONT_SIZE := 15
## Fallback styling (ui/FloatingText.ts): outline #0b1020, 4 px.
const OUTLINE_COLOR := Color("#0b1020")
const OUTLINE_SIZE := 4


## FloatingTextSurfacePort.ts:62-63: the surface box per size (the label is centred in it).
const BIG_BOX := Vector2(320.0, 48.0)
const SMALL_BOX := Vector2(240.0, 34.0)
const LAYER := 8
## floating-text.scene.json Message `fontWeight 700`: approximated by emboldening the default font.
const BOLD_EMBOLDEN := 0.6

## One entry per pooled label: {"label": Label, "world": Vector2, "big": bool,
## "started_at": float (real ms), "duration_ms": float, "pop_scale": float, "pop_ms": float
## (0 = no pop, the old scale curve)}.
var _entries: Array[Dictionary] = []
var _font: Font
## The texts' clock: real time minus `_held_ms`, which grows while the picture speed is below 1
## (`set_picture_speed`); `_last_real_ms` is the real ms of the last frame (< 0 before the first).
var _picture_speed: float = 1.0
var _held_ms: float = 0.0
var _last_real_ms: float = -1.0


## Builds the label pool (mouse_filter IGNORE, outline), layer 8, PROCESS_MODE_ALWAYS.
func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = BOLD_EMBOLDEN
	_font = variation
	for i in POOL_SIZE:
		var label := Label.new()
		label.name = "FloatingText%d" % i
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override(&"font", _font)
		label.add_theme_color_override(&"font_outline_color", OUTLINE_COLOR)
		label.add_theme_constant_override(&"outline_size", OUTLINE_SIZE)
		label.visible = false
		add_child(label)
		_entries.append({"label": label, "world": Vector2.ZERO, "big": false,
			"started_at": -INF, "duration_ms": 0.0, "pop_scale": 1.0, "pop_ms": 0.0})


## Reuses the first expired label (pool full -> drop). p = elapsed / duration (real time):
## position (x, y - rise * p), alpha 1 - p, scale 1.1 + 0.2p (big) / 0.9 + 0.1p (small).
func spawn(world_position: Vector2, text: String, color: Color, big: bool, duration_ms: float = -1.0) -> void:
	_spawn(world_position, text, color, big, duration_ms, 1.0, 0.0)


## Rework: as `spawn`, but the label pops from `pop_scale` to 1.0 over `pop_ms` (real ms), then keeps
## scale 1.0 while it rises and fades. `pop_ms <= 0` is a plain `spawn`.
func spawn_pop(world_position: Vector2, text: String, color: Color, big: bool, pop_scale: float,
		pop_ms: float, duration_ms: float = -1.0) -> void:
	_spawn(world_position, text, color, big, duration_ms, pop_scale, pop_ms)


## Rework: the texts' clock runs at `speed` (0..1) from now on (GameFeel passes `picture_speed()`).
func set_picture_speed(speed: float) -> void:
	_picture_speed = clampf(speed, 0.0, 1.0) if is_finite(speed) else 1.0


func _spawn(world_position: Vector2, text: String, color: Color, big: bool, duration_ms: float,
		pop_scale: float, pop_ms: float) -> void:
	var now := _clock_ms()
	for entry in _entries:
		if now < float(entry["started_at"]) + float(entry["duration_ms"]):
			continue
		var label: Label = entry["label"]
		var box := BIG_BOX if big else SMALL_BOX
		entry["world"] = world_position
		entry["big"] = big
		entry["started_at"] = now
		entry["duration_ms"] = duration_ms if duration_ms >= 0.0 else (BIG_DURATION_MS if big else SMALL_DURATION_MS)
		entry["pop_scale"] = pop_scale if is_finite(pop_scale) and pop_scale > 0.0 else 1.0
		entry["pop_ms"] = pop_ms if is_finite(pop_ms) and pop_ms > 0.0 else 0.0
		label.text = text
		label.add_theme_color_override(&"font_color", color)
		label.add_theme_font_size_override(&"font_size", BIG_FONT_SIZE if big else SMALL_FONT_SIZE)
		label.size = box
		label.pivot_offset = box / 2.0
		_update_entry(entry, now)
		return
	# Pool full: drop the request (FloatingTextSurfacePort.ts:40).


## Advances the texts' clock (held back while the picture speed is below 1), then advances and
## projects every live label.
func _process(_delta: float) -> void:
	var real_ms := float(Time.get_ticks_msec())
	if _last_real_ms >= 0.0 and _picture_speed < 1.0:
		_held_ms += maxf(0.0, real_ms - _last_real_ms) * (1.0 - _picture_speed)
	_last_real_ms = real_ms
	var now := _clock_ms()
	for entry in _entries:
		var label: Label = entry["label"]
		if label.visible or now < float(entry["started_at"]) + float(entry["duration_ms"]):
			_update_entry(entry, now)


## The texts' clock (real ms, minus what the picture speed held back).
func _clock_ms() -> float:
	return float(Time.get_ticks_msec()) - _held_ms


func _update_entry(entry: Dictionary, now: float) -> void:
	var label: Label = entry["label"]
	var duration := float(entry["duration_ms"])
	var elapsed := maxf(0.0, now - float(entry["started_at"]))
	if elapsed >= duration:
		label.visible = false
		return
	var big: bool = entry["big"]
	var progress := clampf(elapsed / maxf(1.0, duration), 0.0, 1.0)
	var world: Vector2 = entry["world"]
	var rise := BIG_RISE_PX if big else SMALL_RISE_PX
	var screen := get_viewport().get_canvas_transform() * Vector2(world.x, world.y - rise * progress)
	var box := BIG_BOX if big else SMALL_BOX
	var viewport_size := get_viewport().get_visible_rect().size
	var on_screen := screen.x > -box.x and screen.x < viewport_size.x + box.x 		and screen.y > -box.y and screen.y < viewport_size.y + box.y
	label.visible = on_screen
	if not on_screen:
		return
	label.position = Vector2(roundf(screen.x - box.x / 2.0), roundf(screen.y - box.y / 2.0))
	label.modulate.a = maxf(0.0, 1.0 - progress)
	var scale_value := (1.1 + 0.2 * progress) if big else (0.9 + 0.1 * progress)
	var pop_ms := float(entry.get("pop_ms", 0.0))
	if pop_ms > 0.0:
		# Rework pop: pop_scale -> 1.0 with an ease-out, then 1.0.
		var pop := clampf(elapsed / pop_ms, 0.0, 1.0)
		scale_value = lerpf(float(entry.get("pop_scale", 1.0)), 1.0, 1.0 - (1.0 - pop) * (1.0 - pop))
	label.scale = Vector2(scale_value, scale_value)

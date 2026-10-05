extends Control
## The banner that names an area when its world loads, also used for "ability learned" lines
## (Phaser `features/ui/AreaTitleSurfacePort.ts` + `ui/area-title-card.scene.json`;
## docs/godot/specs/shell.md section 4). A 440 x 64 card at the top centre: it slides down 18 px
## and fades in over 320 ms (cubic ease-out), holds 1200 ms, then fades and slides back over 320 ms.
## Runs on real time (Phaser's scene clock, which hit-stop does not freeze) and takes no input.
##
## Owner: shell.

const ENTER_MS := 320.0
const HOLD_MS := 1200.0
const EXIT_MS := 320.0
## Card top at progress 0 and how far it slides (`top = round(54 + eased * 18)`).
const TOP_START := 54.0
const SLIDE := 18.0
const CARD_SIZE := Vector2(440.0, 64.0)
## `#ffd277`, used when the colour given is not opaque RGB.
const DEFAULT_COLOR := Color("#ffd277")

## Milliseconds of real time; tests replace it.
var clock: Callable = func() -> float: return float(Time.get_ticks_msec())

var _title: String = ""
var _color: Color = DEFAULT_COLOR
var _started_ms: float = -INF

@onready var label: Label = $Card/Title


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply(state_at(INF))


## Starts the banner with `title` in `color` (restarts it when one is showing).
func show_title(title: String, color: Color = DEFAULT_COLOR) -> void:
	_title = title
	_color = Color(color, 1.0) if color.a > 0.0 else DEFAULT_COLOR
	_started_ms = float(clock.call())
	label.text = _title
	label.add_theme_color_override(&"font_color", _color)
	_fit_width()
	_apply(state_at(0.0))


## True from `show_title` until the exit ends.
func is_showing() -> bool:
	return bool(state_at(float(clock.call()) - _started_ms)["visible"])


func current_title() -> String:
	return _title


func current_color() -> Color:
	return _color


func _process(_delta: float) -> void:
	_apply(state_at(float(clock.call()) - _started_ms))


## `AreaTitleSurfacePort.snapshot` at `elapsed_ms` after the start: {visible, opacity, top}.
static func state_at(elapsed_ms: float) -> Dictionary:
	var duration := ENTER_MS + HOLD_MS + EXIT_MS
	var visible_now := elapsed_ms >= 0.0 and elapsed_ms < duration
	var progress := 1.0
	if elapsed_ms < ENTER_MS:
		progress = maxf(0.0, elapsed_ms / ENTER_MS)
	elif elapsed_ms >= ENTER_MS + HOLD_MS:
		progress = maxf(0.0, 1.0 - (elapsed_ms - ENTER_MS - HOLD_MS) / EXIT_MS)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	return {
		"visible": visible_now,
		"opacity": eased if visible_now else 0.0,
		"top": roundf(TOP_START + eased * SLIDE),
	}


## 440 px wide, wider for a long line (an ability banner), never wider than the screen - 24 px.
func _fit_width() -> void:
	var font := label.get_theme_font(&"font")
	var text_width := 0.0
	if font != null:
		text_width = font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			label.get_theme_font_size(&"font_size")).x + 48.0
	var screen_width := get_viewport_rect().size.x if is_inside_tree() else CARD_SIZE.x + 24.0
	var width := minf(maxf(CARD_SIZE.x, text_width), maxf(120.0, screen_width - 24.0))
	offset_left = -roundf(width * 0.5)
	offset_right = roundf(width * 0.5)


func _apply(state: Dictionary) -> void:
	visible = bool(state["visible"])
	modulate.a = float(state["opacity"])
	offset_top = float(state["top"])
	offset_bottom = offset_top + CARD_SIZE.y

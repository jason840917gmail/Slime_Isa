extends CanvasLayer
class_name IrisTransition
## The Zelda door iris (owner, 2026-10-14): a black screen with a round hole centred on the player
## closes over the picture (`close`), stays black while main.gd frees the world and builds the next
## one, then opens again from the player's new spot (`open`). One full-screen ColorRect with
## iris_transition.gdshader on its own CanvasLayer (main.gd puts it on the travel fade's layer:
## above the world, under the HUD). Runs on real time and through pause (PROCESS_MODE_ALWAYS,
## tweens that process while paused), like the fades.
##
## The hole follows `subject` every frame: a Callable returning a world position (the player's
## centre); its screen spot is the viewport's canvas transform times that point. While the subject
## is gone (the world is being swapped) the hole keeps its last spot.
##
## Durations come from the caller (game-constants `worldNavigation.irisCloseMs`, `irisHoldMs`,
## `irisOpenMs`). Owner: world objects.

const SHADER := preload("res://game/world/iris_transition.gdshader")
const COLOUR := Color(0.0, 0.0, 0.0, 1.0)
## Anti-aliased rim width (screen units); the closed radius sits past it, so closed is fully black.
const SOFTNESS := 1.5

var subject: Callable = Callable()
## 0 = closed (all black), 1 = open (the hole reaches past every corner).
var progress: float = 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply()

var _rect: ColorRect
var _material: ShaderMaterial
var _centre: Vector2 = Vector2.ZERO
var _tween: Tween


func _init() -> void:
	name = "IrisTransition"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"colour", COLOUR)
	_material.set_shader_parameter(&"softness", SOFTNESS)
	_rect = ColorRect.new()
	_rect.name = "Iris"
	_rect.color = Color.WHITE
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _ready() -> void:
	_track()
	_apply()


func _process(_delta: float) -> void:
	_track()
	_apply()


## Closes from open to black over `ms`, then calls `done`.
func close(ms: float, done: Callable = Callable()) -> void:
	_track()
	progress = 1.0
	_run(0.0, ms, 0.0, done, Tween.EASE_IN)


## Opens from black after `hold_ms` of black over `ms`, then frees itself (and calls `done`).
func open(hold_ms: float, ms: float, done: Callable = Callable()) -> void:
	_track()
	progress = 0.0
	_run(1.0, ms, hold_ms, done, Tween.EASE_OUT, true)


func is_closed() -> bool:
	return progress <= 0.0


func _run(to: float, ms: float, hold_ms: float, done: Callable, easing: Tween.EaseType, free_at_end: bool = false) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if hold_ms > 0.0:
		_tween.tween_interval(hold_ms / 1000.0)
	_tween.tween_property(self, "progress", to, maxf(ms, 1.0) / 1000.0).set_trans(Tween.TRANS_SINE).set_ease(easing)
	if done.is_valid():
		_tween.tween_callback(done)
	if free_at_end:
		_tween.tween_callback(queue_free)


func _track() -> void:
	if not subject.is_valid() or not is_inside_tree():
		return
	var point: Variant = subject.call()
	if point is Vector2 and (point as Vector2).is_finite():
		_centre = get_viewport().get_canvas_transform() * (point as Vector2)


func _apply() -> void:
	if _rect == null:
		return
	var size := _rect.size
	if size.x <= 0.0 or size.y <= 0.0:
		size = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1024.0, 1024.0)
	var far := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
		far = maxf(far, _centre.distance_to(corner))
	var closed := -SOFTNESS * 2.0
	var opened := far + SOFTNESS * 2.0
	_material.set_shader_parameter(&"centre", _centre)
	_material.set_shader_parameter(&"rect_size", size)
	_material.set_shader_parameter(&"radius", lerpf(closed, opened, progress))

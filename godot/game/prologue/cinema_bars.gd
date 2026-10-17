extends CanvasLayer
## Letterbox bars for the prologue's scripted scenes (the birth, Yoi's fight; roadmap 5.18 and 5.19):
## a black bar slides in from the top and one from the bottom (over the HUD console) while a scene
## plays, and out when the player has the slime back. Above the HUD (10), under the game windows
## (40), so the dialogue box shows over them. Real time.
##
## Owner: prologue.

const LAYER := 20
const BAR_HEIGHT := 96.0
## The bottom bar also covers the HUD console's strip (128 units) and a little more.
const BOTTOM_BAR_HEIGHT := 168.0
const SLIDE_S := 0.45

var _top: ColorRect
var _bottom: ColorRect
var _shown := false


func _init() -> void:
	name = "CinemaBars"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_top = _bar(true)
	_bottom = _bar(false)


## True while the bars are in (or sliding in).
func is_shown() -> bool:
	return _shown


## Slides the bars in (`instant`: at once, the birth's first frame).
func show_bars(instant: bool = false) -> void:
	_shown = true
	_slide(1.0, instant)


func hide_bars(instant: bool = false) -> void:
	_shown = false
	_slide(0.0, instant)


func _slide(amount: float, instant: bool) -> void:
	for bar: ColorRect in [_top, _bottom]:
		var target := (BAR_HEIGHT if bar == _top else BOTTOM_BAR_HEIGHT) * amount
		if instant:
			_place(target, bar)
			continue
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var from := float(bar.get_meta(&"height", 0.0))
		tween.tween_method(_place.bind(bar), from, target, SLIDE_S).set_trans(Tween.TRANS_SINE)


func _bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = "Top" if top else "Bottom"
	bar.color = Color(0, 0, 0, 1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0 if top else 1.0
	bar.anchor_bottom = 0.0 if top else 1.0
	bar.set_meta(&"top", top)
	add_child(bar)
	_place(0.0, bar)
	return bar


func _place(height: float, bar: ColorRect) -> void:
	var top := bool(bar.get_meta(&"top", true))
	bar.set_meta(&"height", height)
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0 if top else -height
	bar.offset_bottom = height if top else 0.0

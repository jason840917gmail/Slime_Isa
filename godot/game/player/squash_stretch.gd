extends RefCounted
class_name SquashStretch
## Jelly squash on the slime's Visual (Phaser `features/feel/SquashStretch.ts:122-185`).
## Player spec section 8. Presentation literals are kept here (as in Phaser).
##
## The event snaps the Visual's extra scale to the preset, then tweens back to 1 with the preset's
## ease (Back.Out by default); a new event replaces the running tween. While an ability runs
## (`busy`) events are skipped unless forced (the jump's landing). Effective scale = authored
## Visual scale (0.28125) * extra. Reduce motion (OUT, default off) would keep 35 %. The pivot is
## the Visual node position (old sprite centre), same as Phaser.
##
## Owner: player builder.

## event -> {"scale": Vector2, "ms": float}
const PRESETS := {
	&"move-start": {"scale": Vector2(0.9, 1.12), "ms": 170.0},
	&"hit": {"scale": Vector2(1.22, 0.8), "ms": 190.0},
	# SquashStretch.ts:16-27 (abilities spec 16).
	&"jump": {"scale": Vector2(0.82, 1.35), "ms": 200.0, "trans": Tween.TRANS_QUAD},
	&"land": {"scale": Vector2(1.32, 0.72), "ms": 220.0},
	&"gulp": {"scale": Vector2(1.24, 0.86), "ms": 320.0, "trans": Tween.TRANS_ELASTIC},
}

## Skips non-forced events while it returns true (player.gd: an ability is running).
var busy: Callable = Callable()

var _visual: Node2D
var _base_scale: Vector2 = Vector2.ONE
var _tween: Tween


## Remembers the Visual and its authored scale.
func setup(visual: Node2D) -> void:
	_visual = visual
	if _visual != null:
		_base_scale = _visual.scale


## Plays a preset (unknown events are ignored). The tween is created on the Visual
## (`visual.create_tween()`), so it pauses with the tree during hit-stop like Phaser tweens.
func play(event: StringName, force: bool = false) -> void:
	if _visual == null or not is_instance_valid(_visual) or not PRESETS.has(event):
		return
	if not force and busy.is_valid() and bool(busy.call()):
		return
	var preset: Dictionary = PRESETS[event]
	var start: Vector2 = preset["scale"]
	var duration_s: float = float(preset["ms"]) / 1000.0
	_kill_tween()
	_visual.scale = _base_scale * start
	if not _visual.is_inside_tree():
		_visual.scale = _base_scale
		return
	_tween = _visual.create_tween()
	_tween.set_trans(int(preset.get("trans", Tween.TRANS_BACK))).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_visual, "scale", _base_scale, duration_s)


## Stops any running tween and restores the authored scale.
func reset() -> void:
	_kill_tween()
	if _visual != null and is_instance_valid(_visual):
		_visual.scale = _base_scale


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

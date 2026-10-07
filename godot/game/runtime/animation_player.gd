extends AnimationPlayer
## AnimationPlayer helper the scene converter attaches to every converted
## AnimationPlayer (runtime spec sections 6.4 to 6.6).
##
## Phaser clip semantics that Godot lacks:
## - `play_clip(name)` always restarts, even the clip already playing.
## - Switching or stopping a clip restores every property the outgoing clip
##   animated to the value captured when it started (its baseline); a
##   non-loop clip that completes on its own keeps its last frame. Weapon
##   sprites rely on this: their base alpha is 0, so an interrupted swing hides
##   them again.
## Gameplay code calls `play_clip` / `stop_clip`, never `play` / `stop`.
##
## Animation events are method-track keys calling `emit_animation_event`;
## they re-emit as `animation_event(event)` with the keys `animation`, `at`,
## `event_id`, `payload` and `gameplay`.
##
## `autoplay` stays Godot's property (the converter writes it); `_ready` starts
## it through `play_clip` so its baseline is captured, then applies
## `randomize_start` (a random whole frame, no events). Godot's own autoplay,
## which runs right after `_ready`, finds the clip already playing and
## continues it.
##
## Owner: converter builder.

signal animation_event(event: Dictionary)

@export var randomize_start: bool = false

## The clip started by `play_clip` and still running ("" when none).
var current_clip: StringName = &""

## "<node path>:<property path>" → { node, property, value } for the current clip.
var _baselines: Dictionary = {}

var _paused: bool = false


func _init() -> void:
	# Connected before the scene's own connections so a completion handler
	# that starts the next clip finds the finished clip already settled.
	animation_finished.connect(_on_animation_finished)


func _ready() -> void:
	var start := StringName(autoplay)
	if start == &"" or not has_animation(start):
		return
	play_clip(start)
	if randomize_start:
		var animation := get_animation(start)
		if animation.loop_mode != Animation.LOOP_NONE:
			var frames := _frame_count(animation)
			seek(randi_range(0, frames - 1) * _frame_seconds(animation), true)


## Starts `clip` from frame 0 with Phaser semantics (see the class comment).
func play_clip(clip: StringName) -> void:
	if not has_animation(clip):
		push_warning("%s: no clip '%s'" % [get_path(), clip])
		return
	stop_clip()
	_capture_baselines(get_animation(clip))
	current_clip = clip
	_paused = false
	stop()
	play(clip)
	seek(0.0, true)


## Stops the current clip and restores its baselines.
func stop_clip() -> void:
	if current_clip != &"" and not is_playing() and not _paused and _completed(current_clip):
		_forget_baselines()
	stop()
	_restore_baselines()
	current_clip = &""
	_paused = false


## Seeks the current clip to a whole timeline frame without firing events.
func seek_frame(frame: int) -> void:
	if current_clip == &"":
		return
	seek(frame * _frame_seconds(get_animation(current_clip)), true)


func pause_clip() -> void:
	if current_clip != &"" and is_playing():
		_paused = true
		pause()


func resume_clip() -> void:
	if current_clip != &"" and _paused:
		_paused = false
		play()


func has_clip(clip: StringName) -> bool:
	return has_animation(clip)


## Clip length in milliseconds (N frames / fps).
func clip_length_ms(clip: StringName) -> float:
	if not has_animation(clip):
		return 0.0
	return get_animation(clip).length * 1000.0


## Called by method-track keys written by the converter.
func emit_animation_event(event_id: String, payload: Dictionary = {}, gameplay: bool = false, at: int = 0) -> void:
	animation_event.emit({
		"animation": String(current_animation),
		"at": at,
		"event_id": event_id,
		"payload": payload,
		"gameplay": gameplay,
	})


func _exit_tree() -> void:
	if current_clip != &"":
		stop_clip()


func _on_animation_finished(clip: StringName) -> void:
	if clip != current_clip:
		return
	# Natural completion keeps the last frame: forget, do not restore.
	_forget_baselines()
	current_clip = &""


func _completed(clip: StringName) -> bool:
	var animation := get_animation(clip)
	return animation != null and animation.loop_mode == Animation.LOOP_NONE


func _capture_baselines(animation: Animation) -> void:
	_baselines.clear()
	var root := get_node_or_null(root_node)
	if root == null:
		return
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_VALUE:
			continue
		var path := animation.track_get_path(track)
		var target := root.get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null:
			continue
		var property := NodePath(path.get_concatenated_subnames())
		_baselines[String(path)] = {"node": target, "property": property, "value": target.get_indexed(property)}


func _restore_baselines() -> void:
	for entry: Dictionary in _baselines.values():
		var target: Node = entry["node"]
		if is_instance_valid(target):
			target.set_indexed(entry["property"], entry["value"])
	_baselines.clear()


func _forget_baselines() -> void:
	_baselines.clear()


func _frame_seconds(animation: Animation) -> float:
	return animation.step if animation.step > 0.0 else animation.length


func _frame_count(animation: Animation) -> int:
	return maxi(1, roundi(animation.length / _frame_seconds(animation)))

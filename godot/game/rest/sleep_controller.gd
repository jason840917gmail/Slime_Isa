extends RefCounted
## Sleeping in a bed (Phaser `features/rest/SleepController.ts`; interaction spec 3.5). Owned by
## the player script. The body lies at the bed's wake point while the art shows on the mattress
## (an art offset); the player dozes (the `doze` clip), then sleeps (`sleep`, looping), healing
## `rest.sleepHpRegenPerSec` (2) HP per second in whole points with the fraction carried, with a
## "z" floating up every 900 ms. Any action press or a held direction wakes it once 400 ms have
## passed (presses made during that grace are drained); damage and death wake it too. Falling
## asleep makes the bed the respawn point. Sleep never pauses the world. Simulation time
## throughout.
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")

const ZZZ_INTERVAL_MS := 900.0
## The press that started sleep cannot wake it (WAKE_INPUT_GRACE_MS).
const WAKE_INPUT_GRACE_MS := 400.0
const CLIP_DOZE := "doze"
const CLIP_SLEEP := "sleep"
## Presentation literals (WorldScene onFellAsleep / SleepController): texts relative to the sleep point.
const RESPAWN_TEXT_RISE := 48.0
const RESTED_TEXT_RISE := 36.0
const ZZZ_OFFSET := Vector2(14.0, -24.0)
const ZZZ_DRIFT := Vector2(18.0, -38.0)
const ZZZ_DRIFT_MS := 1400.0
const ZZZ_FADE_MS := 700.0
const ZZZ_COLOR := Color("#e7fff5")
const ZZZ_OUTLINE := Color("#101a31")

## The sleeper (player.gd): play_animation, clip_length_ms_of, teleport, set_art_offset,
## set_action_locked, stop_movement, heal, get_hp, get_max_hp.
var _player: Node
var _phase: String = ""
var _request: Dictionary = {}
var _phase_ends_at: float = 0.0
var _started_at: float = 0.0
var _next_zzz_at: float = 0.0
var _pending_heal: float = 0.0
var _announced_rested: bool = false


func _init(player: Node) -> void:
	_player = player


func is_sleeping() -> bool:
	return not _phase.is_empty()


## True once deep sleep began (after the doze).
func is_asleep() -> bool:
	return _phase == "sleeping"


## `request` = {"bed_id", "sleep_point", "wake_point"} (old Phaser world points). False when
## already asleep.
func sleep(request: Dictionary) -> bool:
	if is_sleeping():
		return false
	_request = request
	_started_at = Services.now_ms()
	_pending_heal = 0.0
	_announced_rested = false
	_player.call(&"stop_movement")
	_player.call(&"set_action_locked", true)
	var wake_point: Vector2 = request["wake_point"]
	var sleep_point: Vector2 = request["sleep_point"]
	_player.call(&"teleport", wake_point)
	_player.call(&"set_art_offset", sleep_point - wake_point)
	_phase = "dozing"
	_phase_ends_at = _started_at + float(_player.call(&"clip_length_ms_of", CLIP_DOZE))
	_player.call(&"play_animation", CLIP_DOZE, true)
	_next_zzz_at = _phase_ends_at
	_on_fell_asleep(request)
	return true


## One physics step while sleeping. `wake_requested`: an action was pressed (drained) or a direction
## is held this step.
func update(delta_ms: float, wake_requested: bool) -> void:
	if not is_sleeping():
		return
	var now := Services.now_ms()
	if wake_requested and now - _started_at >= WAKE_INPUT_GRACE_MS:
		wake("input")
		return
	if _phase == "dozing":
		if now < _phase_ends_at:
			return
		_phase = "sleeping"
		_player.call(&"play_animation", CLIP_SLEEP, true)
	_restore_health(delta_ms)
	if now >= _next_zzz_at:
		_next_zzz_at = now + ZZZ_INTERVAL_MS
		_spawn_zzz(_request["sleep_point"])


## "input" | "damage" | "death" | "teardown". The art comes back to the body; except on teardown the
## body is put at the wake point and unlocked, and (not on death) plays idle.
func wake(reason: String) -> void:
	if not is_sleeping():
		return
	var request := _request
	_phase = ""
	_request = {}
	_player.call(&"set_art_offset", Vector2.ZERO)
	if reason == "teardown":
		return
	_player.call(&"teleport", request["wake_point"])
	_player.call(&"set_action_locked", false)
	if reason != "death":
		_player.call(&"play_animation", "idle", true)


## `onFellAsleep` (WorldScene): the bed becomes the respawn point, "Respawn point set" (cyan).
func _on_fell_asleep(request: Dictionary) -> void:
	var run := Services.run()
	var world := Services.world()
	var wake_point: Vector2 = request["wake_point"]
	var sleep_point: Vector2 = request["sleep_point"]
	if run != null and world != null:
		var map_id := world.map_id()
		run.set_respawn_point({"area_id": map_id, "map_id": map_id, "x": roundf(wake_point.x),
			"y": roundf(wake_point.y), "bed_id": str(request.get("bed_id", ""))})
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(sleep_point - Vector2(0.0, RESPAWN_TEXT_RISE), "Respawn point set", &"cyan", false)


func _restore_health(delta_ms: float) -> void:
	if int(_player.call(&"get_hp")) >= int(_player.call(&"get_max_hp")):
		_pending_heal = 0.0
		if not _announced_rested:
			_announced_rested = true
			var feel := Services.feel()
			if feel != null:
				var at: Vector2 = _request["sleep_point"]
				feel.floating_text(at - Vector2(0.0, RESTED_TEXT_RISE), "Fully rested", &"green", false)
		return
	var constants := Services.constants()
	var rate := constants.number("rest.sleepHpRegenPerSec") if constants != null else 0.0
	_pending_heal += rate * delta_ms / 1000.0
	var whole := floori(_pending_heal)
	if whole <= 0:
		return
	_pending_heal -= whole
	_player.call(&"heal", whole)


## A "z" (12-18 px, bold) that drifts up and right over 1400 ms, fading in then out.
func _spawn_zzz(anchor: Vector2) -> void:
	var world := Services.world()
	var parent := world.entities_root() if world != null else null
	if parent == null:
		return
	var holder := Node2D.new()
	holder.name = "Zzz"
	holder.z_index = 1
	var label := Label.new()
	label.text = "z"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font_size = 12 + randi_range(0, 6)
	settings.font_color = ZZZ_COLOR
	settings.outline_color = ZZZ_OUTLINE
	settings.outline_size = 3
	label.label_settings = settings
	holder.add_child(label)
	parent.add_child(holder)
	holder.global_position = anchor + ZZZ_OFFSET
	label.position = -label.get_minimum_size() / 2.0
	holder.modulate.a = 0.0
	var drift := holder.create_tween()
	drift.tween_property(holder, "position", holder.position + ZZZ_DRIFT, ZZZ_DRIFT_MS / 1000.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	drift.tween_callback(holder.queue_free)
	var fade := holder.create_tween()
	fade.tween_property(holder, "modulate:a", 1.0, ZZZ_FADE_MS / 1000.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(holder, "modulate:a", 0.0, ZZZ_FADE_MS / 1000.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

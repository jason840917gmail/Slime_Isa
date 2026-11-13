extends RefCounted
## Soaking in a bath (owner, 2026-11-12: "similar to the sleep functionality make a new one for bath
## where the slime can take a relax bath on any house bath"). Built on the bed's pattern
## (sleep_controller.gd) and owned by the player script. The body waits at the bath's way-out point
## while the art sits in the water at the soak point (an art offset), behind the tub's front layer,
## which is raised over it for the soak. The slime settles (the `doze` clip: a yawn, the eyes close),
## then soaks (`sleep`, looping: closed eyes and a blush), healing `rest.bathHpRegenPerSec` HP per
## second in whole points with the fraction carried. Soap bubbles rise from the water and pop, and
## steam drifts up. One sound only, the water's loop (`BathSoak`, the owner's pick, Sound Picker
## round 9: "make sure to only use the one i chose"): it plays from the step in to the step out;
## the splash, the bubbles and full health are silent. Any action press or a held direction ends it once `WAKE_INPUT_GRACE_MS` have
## passed; damage and death end it too. A bath never moves the respawn point (a bed does) and never
## pauses the world. Simulation time throughout.
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")

## The press that started the bath cannot end it.
const WAKE_INPUT_GRACE_MS := 400.0
const CLIP_SETTLE := "doze"
const CLIP_SOAK := "sleep"
## The water's loop, the bath's only sound.
const CUE_SOAK := &"BathSoak"
## Presentation literals, relative to the soak point.
const FRESH_TEXT_RISE := 44.0
const FRESH_TEXT := "Fresh and clean"
const SPLASH_PRESET := &"slime-splash"
const BUBBLE_INTERVAL_MS := 650.0
const BUBBLE_SPREAD := Vector2(26.0, 6.0)
const BUBBLE_RISE := Vector2(0.0, -34.0)
const BUBBLE_SWAY := 7.0
const BUBBLE_MS := 1300.0
const BUBBLE_SIZES := Vector2(0.45, 0.95)
const STEAM_INTERVAL_MS := 900.0
const STEAM_RISE := Vector2(6.0, -46.0)
const STEAM_MS := 2200.0
const STEAM_ALPHA := 0.4
const STEAM_START := Vector2(0.0, -30.0)
## Over the tub's front layer, which is itself raised over the bather.
const FRONT_Z := 1
const EFFECT_Z := 2
const TEXTURE_PX := 24

## The bather (player.gd): play_animation, clip_length_ms_of, teleport, set_art_offset,
## set_action_locked, stop_movement, face, heal, get_hp, get_max_hp.
var _player: Node
var _phase: String = ""
var _request: Dictionary = {}
var _phase_ends_at: float = 0.0
var _started_at: float = 0.0
var _next_bubble_at: float = 0.0
var _next_steam_at: float = 0.0
var _pending_heal: float = 0.0
var _announced_fresh: bool = false
var _front_z_before: int = 0

static var _bubble_texture: Texture2D
static var _steam_texture: Texture2D


func _init(player: Node) -> void:
	_player = player


func is_bathing() -> bool:
	return not _phase.is_empty()


## True once the slime has settled and soaks.
func is_soaking() -> bool:
	return _phase == "soaking"


## `request` = {"bath_id", "soak_point", "out_point", "front"} (BathScript.bath_request; the points
## as a bed's, old Phaser world points; "front" the tub's front layer or null). False when already
## in a bath.
func bathe(request: Dictionary) -> bool:
	if is_bathing():
		return false
	_request = request
	_started_at = Services.now_ms()
	_pending_heal = 0.0
	_announced_fresh = false
	_player.call(&"stop_movement")
	_player.call(&"set_action_locked", true)
	var out_point: Vector2 = request["out_point"]
	var soak_point: Vector2 = request["soak_point"]
	_player.call(&"teleport", out_point)
	_player.call(&"set_art_offset", soak_point - out_point)
	# The settle and soak clips face the viewer only, as the bed's.
	_player.call(&"face", Vector2.DOWN)
	var front := _front()
	if front != null:
		_front_z_before = front.z_index
		front.z_index = FRONT_Z
	_phase = "settling"
	_phase_ends_at = _started_at + float(_player.call(&"clip_length_ms_of", CLIP_SETTLE))
	_player.call(&"play_animation", CLIP_SETTLE, true)
	_next_bubble_at = _started_at + BUBBLE_INTERVAL_MS
	_next_steam_at = _started_at + STEAM_INTERVAL_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SOAK)
		feel.particles(SPLASH_PRESET, soak_point)
	return true


## One physics step in the bath. `wake_requested`: an action was pressed (drained) or a direction is
## held this step.
func update(delta_ms: float, wake_requested: bool) -> void:
	if not is_bathing():
		return
	var now := Services.now_ms()
	if wake_requested and now - _started_at >= WAKE_INPUT_GRACE_MS:
		leave("input")
		return
	if _phase == "settling" and now >= _phase_ends_at:
		_phase = "soaking"
		_player.call(&"play_animation", CLIP_SOAK, true)
	if _phase == "soaking":
		_restore_health(delta_ms)
	var soak_point: Vector2 = _request["soak_point"]
	if now >= _next_bubble_at:
		_next_bubble_at = now + BUBBLE_INTERVAL_MS
		_spawn_bubble(soak_point)
	if now >= _next_steam_at:
		_next_steam_at = now + STEAM_INTERVAL_MS
		_spawn_steam(soak_point)


## "input" | "damage" | "death" | "teardown". The art comes back to the body and the tub's front
## layer goes back down; except on teardown the body is put at the way-out point and unlocked, and
## (not on death) plays idle.
func leave(reason: String) -> void:
	if not is_bathing():
		return
	var request := _request
	var front := _front()
	_phase = ""
	_request = {}
	var feel := Services.feel()
	if feel != null:
		feel.stop_audio_cue(CUE_SOAK)
	if front != null:
		front.z_index = _front_z_before
	_player.call(&"set_art_offset", Vector2.ZERO)
	if reason == "teardown":
		return
	_player.call(&"teleport", request["out_point"])
	_player.call(&"set_action_locked", false)
	if reason != "death":
		_player.call(&"play_animation", "idle", true)
		if feel != null:
			feel.particles(SPLASH_PRESET, request["soak_point"])


func _front() -> CanvasItem:
	var front: Variant = _request.get("front")
	return front as CanvasItem if is_instance_valid(front) else null


func _restore_health(delta_ms: float) -> void:
	if int(_player.call(&"get_hp")) >= int(_player.call(&"get_max_hp")):
		_pending_heal = 0.0
		if not _announced_fresh:
			_announced_fresh = true
			var feel := Services.feel()
			if feel != null:
				var at: Vector2 = _request["soak_point"]
				feel.floating_text(at - Vector2(0.0, FRESH_TEXT_RISE), FRESH_TEXT, &"green", false)
		return
	var constants := Services.constants()
	var rate := constants.number("rest.bathHpRegenPerSec") if constants != null else 0.0
	_pending_heal += rate * delta_ms / 1000.0
	var whole := floori(_pending_heal)
	if whole <= 0:
		return
	_pending_heal -= whole
	_player.call(&"heal", whole)


## A soap bubble that rises from the water with a sway, swells a little and pops.
func _spawn_bubble(soak_point: Vector2) -> void:
	var at := soak_point + Vector2(randf_range(-BUBBLE_SPREAD.x, BUBBLE_SPREAD.x), randf_range(-BUBBLE_SPREAD.y, BUBBLE_SPREAD.y))
	var bubble := _floater(_bubble(), at, randf_range(BUBBLE_SIZES.x, BUBBLE_SIZES.y))
	if bubble == null:
		return
	var rise := bubble.create_tween()
	rise.tween_property(bubble, "position", bubble.position + BUBBLE_RISE + Vector2(randf_range(-BUBBLE_SWAY, BUBBLE_SWAY), 0.0),
			BUBBLE_MS / 1000.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rise.tween_property(bubble, "scale", bubble.scale * 1.5, 0.08)
	rise.parallel().tween_property(bubble, "modulate:a", 0.0, 0.08)
	rise.tween_callback(bubble.queue_free)


## A wisp of steam that drifts up from the water, spreading and fading.
func _spawn_steam(soak_point: Vector2) -> void:
	var at := soak_point + STEAM_START + Vector2(randf_range(-BUBBLE_SPREAD.x, BUBBLE_SPREAD.x), 0.0)
	var wisp := _floater(_steam(), at, 1.0)
	if wisp == null:
		return
	wisp.modulate.a = 0.0
	var drift := wisp.create_tween()
	drift.tween_property(wisp, "position", wisp.position + STEAM_RISE, STEAM_MS / 1000.0)
	drift.parallel().tween_property(wisp, "scale", wisp.scale * 2.2, STEAM_MS / 1000.0)
	drift.tween_callback(wisp.queue_free)
	var fade := wisp.create_tween()
	fade.tween_property(wisp, "modulate:a", STEAM_ALPHA, STEAM_MS * 0.3 / 1000.0)
	fade.tween_property(wisp, "modulate:a", 0.0, STEAM_MS * 0.7 / 1000.0)


func _floater(texture: Texture2D, at: Vector2, size: float) -> Sprite2D:
	var world := Services.world()
	var parent := world.entities_root() if world != null else null
	if parent == null:
		return null
	var sprite := Sprite2D.new()
	sprite.name = "BathFloater"
	sprite.texture = texture
	sprite.z_index = EFFECT_Z
	sprite.scale = Vector2(size, size)
	parent.add_child(sprite)
	sprite.global_position = at
	return sprite


## A soap bubble drawn once: a thin pale ring, a faint fill and a highlight.
static func _bubble() -> Texture2D:
	if _bubble_texture == null:
		var image := Image.create(TEXTURE_PX, TEXTURE_PX, false, Image.FORMAT_RGBA8)
		var middle := Vector2(TEXTURE_PX, TEXTURE_PX) / 2.0 - Vector2(0.5, 0.5)
		var radius := TEXTURE_PX / 2.0 - 2.0
		for y in TEXTURE_PX:
			for x in TEXTURE_PX:
				var from := Vector2(x, y) - middle
				var edge := absf(from.length() - radius)
				var alpha := clampf(1.3 - edge, 0.0, 1.0) * 0.95
				if from.length() < radius:
					alpha = maxf(alpha, 0.16)
				if from.distance_to(Vector2(-radius, -radius) * 0.4) < radius * 0.28:
					alpha = maxf(alpha, 0.9)
				image.set_pixel(x, y, Color(0.9, 1.0, 1.0, alpha))
		_bubble_texture = ImageTexture.create_from_image(image)
	return _bubble_texture


## A soft white puff.
static func _steam() -> Texture2D:
	if _steam_texture == null:
		var image := Image.create(TEXTURE_PX, TEXTURE_PX, false, Image.FORMAT_RGBA8)
		var middle := Vector2(TEXTURE_PX, TEXTURE_PX) / 2.0 - Vector2(0.5, 0.5)
		for y in TEXTURE_PX:
			for x in TEXTURE_PX:
				var near := clampf(1.0 - (Vector2(x, y) - middle).length() / (TEXTURE_PX / 2.0), 0.0, 1.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, near * near))
		_steam_texture = ImageTexture.create_from_image(image)
	return _steam_texture

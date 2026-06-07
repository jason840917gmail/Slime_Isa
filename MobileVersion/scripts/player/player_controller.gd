extends CharacterBody2D

signal interaction_requested(player_position: Vector2)

const WALK_SPEED := 230.0
const BOOST_SPEED := 360.0
const DEFAULT_TELEPORT_DISTANCE := 280.0
const DEFAULT_TELEPORT_COOLDOWN := 2.0
const TELEPORT_ADJUST_STEP := 4.0
const SLIME_SHEET := "res://assets/spritesheets/slime/slime_normalized.png"
const CELL_SIZE := 256

const ANIMS := {
	"slime-idle": {"frames": [0, 1, 2, 1, 4, 5, 4, 2], "fps": 6.0, "loop": true},
	"slime-walk": {"frames": [9, 10, 11, 12, 13, 14, 15, 14, 13, 12], "fps": 10.0, "loop": true},
	"slime-hop": {"frames": [17, 18, 19, 20, 21, 22, 23, 22, 21], "fps": 11.0, "loop": true},
	"slime-squash": {"frames": [24, 25, 26, 27, 28, 29, 30, 31], "fps": 12.0, "loop": true},
	"slime-stretch": {"frames": [32, 33, 34, 35, 36, 37, 38, 39], "fps": 12.0, "loop": true},
	"slime-roll": {"frames": [43, 44], "fps": 14.0, "loop": true},
	"slime-trick": {"frames": [48, 49, 50, 51, 52, 53, 52, 51], "fps": 10.0, "loop": false},
	"slime-teleport": {"frames": [56, 57, 58, 59, 60, 61, 60, 59], "fps": 12.0, "loop": false},
	"slime-eat": {"frames": [47, 40], "fps": 12.0, "loop": false},
}

@onready var animated: AnimatedSprite2D = $AnimatedSprite2D
@onready var slime_body: Polygon2D = $SlimeBody
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D

@export var teleport_distance := DEFAULT_TELEPORT_DISTANCE
@export var teleport_cooldown := DEFAULT_TELEPORT_COOLDOWN

var boost_bonus := 0.0
var _current_animation := ""
var _action_lock_time := 0.0
var _last_move_direction := Vector2.DOWN
var _teleport_cooldown_remaining := 0.0
var _teleport_direction := Vector2.DOWN

func _ready() -> void:
	_setup_slime_frames()
	_last_move_direction = GameState.player_facing_direction
	_apply_facing(_last_move_direction)
	_play_animation("slime-idle")


func _physics_process(delta: float) -> void:
	GameState.player_position = global_position

	if _teleport_cooldown_remaining > 0.0:
		_teleport_cooldown_remaining = maxf(0.0, _teleport_cooldown_remaining - delta)

	if _action_lock_time > 0.0:
		_action_lock_time -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		if _action_lock_time <= 0.0:
			_current_animation = ""
			_play_animation("slime-idle")
		return

	var direction := InputManager.get_movement_vector()
	if _handle_action_input(direction):
		return

	_move_player(direction)


func play_pickup_animation() -> void:
	_play_action_animation("slime-eat")


func _move_player(direction: Vector2) -> void:
	var wants_boost := InputManager.is_action_pressed(&"roll")
	var current_speed := WALK_SPEED
	if wants_boost:
		current_speed = BOOST_SPEED + boost_bonus

	var movement := Vector2.ZERO
	if direction.length_squared() > 0.0:
		movement = direction.normalized()

	velocity = movement * current_speed
	move_and_slide()

	if movement == Vector2.ZERO:
		_apply_facing(_last_move_direction)
		_play_animation("slime-idle")
		return

	_last_move_direction = movement
	GameState.set_player_facing_direction(_last_move_direction)
	_apply_facing(_last_move_direction)

	if wants_boost:
		_play_animation("slime-roll")
	elif absf(movement.y) > absf(movement.x):
		if movement.y < 0.0:
			_play_animation("slime-stretch")
		else:
			_play_animation("slime-hop")
	else:
		_play_animation("slime-walk")


func _apply_facing(direction: Vector2) -> void:
	if absf(direction.x) >= absf(direction.y):
		animated.flip_h = direction.x > 0.0
	else:
		animated.flip_h = false


func _handle_action_input(direction: Vector2) -> bool:
	if InputManager.consume_action_just_pressed(&"interact"):
		interaction_requested.emit(global_position)
		return true

	if InputManager.consume_action_just_pressed(&"jump"):
		GameState.use_ability(&"jump")
		AudioManager.play_sfx(&"ability")
		_play_action_animation("slime-hop")
		return true

	if direction == Vector2.ZERO and InputManager.consume_action_just_pressed(&"roll"):
		_play_action_animation("slime-roll")
		return true

	if InputManager.consume_action_just_pressed(&"trick") or InputManager.consume_action_just_pressed(&"ability_1"):
		AudioManager.play_sfx(&"ability")
		_play_action_animation("slime-trick")
		return true

	if InputManager.consume_action_just_pressed(&"stretch"):
		_play_action_animation("slime-stretch")
		return true

	if InputManager.consume_action_just_pressed(&"squash") or InputManager.consume_action_just_pressed(&"ability_2"):
		_play_action_animation("slime-squash")
		return true

	if InputManager.consume_action_just_pressed(&"teleport"):
		_try_teleport()
		return true

	return false


func get_ability_cooldown_state() -> Dictionary:
	return {
		"teleport": {
			"remaining": _teleport_cooldown_remaining,
			"duration": teleport_cooldown,
		},
	}


func _try_teleport() -> void:
	if _teleport_cooldown_remaining > 0.0:
		GameState.show_message("Teleport ready in %.1fs" % _teleport_cooldown_remaining)
		return

	_teleport_direction = Vector2.DOWN
	if _last_move_direction.length_squared() > 0.0:
		_teleport_direction = _last_move_direction.normalized()

	var start_position := global_position
	var target_position := global_position + _teleport_direction * teleport_distance
	var safe_position := _get_safe_teleport_position(target_position, _teleport_direction)
	if safe_position == start_position:
		GameState.show_message("Teleport path is blocked.")
		return

	global_position = safe_position
	GameState.player_position = global_position
	_teleport_cooldown_remaining = teleport_cooldown
	velocity = Vector2.ZERO
	_apply_facing(_teleport_direction)
	_play_action_animation("slime-teleport")
	AudioManager.play_sfx(&"ability")


func _get_safe_teleport_position(target_position: Vector2, teleport_direction: Vector2) -> Vector2:
	var fallback_position := global_position
	var distance := teleport_distance

	while distance > 0.0:
		var candidate := target_position - teleport_direction * (teleport_distance - distance)
		if _is_position_in_level_bounds(candidate) and not _has_body_collision_at(candidate):
			return candidate

		distance -= TELEPORT_ADJUST_STEP

	return fallback_position


func _has_body_collision_at(candidate_position: Vector2) -> bool:
	if body_collision_shape.shape == null:
		return false

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_collision_shape.shape
	query.transform = Transform2D(global_rotation, candidate_position + body_collision_shape.position.rotated(global_rotation))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _is_position_in_level_bounds(candidate_position: Vector2) -> bool:
	var level := get_tree().get_first_node_in_group("level")
	if level != null and level.has_method("is_position_in_bounds"):
		return bool(level.call("is_position_in_bounds", candidate_position))

	return true


func _play_action_animation(animation_name: String) -> void:
	var clip := ANIMS.get(animation_name, {}) as Dictionary
	var frames := clip.get("frames", []) as Array
	var fps := float(clip.get("fps", 10.0))
	_action_lock_time = maxf(0.12, float(frames.size()) / fps)
	velocity = Vector2.ZERO
	_play_animation(animation_name)


func _play_animation(animation_name: String) -> void:
	if _current_animation == animation_name:
		return

	_current_animation = animation_name
	if animated.sprite_frames != null and animated.sprite_frames.has_animation(animation_name):
		animated.play(animation_name)


func _setup_slime_frames() -> void:
	var sheet := load(SLIME_SHEET) as Texture2D
	if sheet == null:
		animated.visible = false
		slime_body.visible = true
		push_warning("Missing slime sprite sheet: %s" % SLIME_SHEET)
		return

	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")

	for animation_name in ANIMS.keys():
		var clip := ANIMS[animation_name] as Dictionary
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, float(clip["fps"]))
		frames.set_animation_loop(animation_name, bool(clip["loop"]))

		for frame_index in clip["frames"]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(
				float(int(frame_index) % 8) * CELL_SIZE,
				float(int(int(frame_index) / 8)) * CELL_SIZE,
				CELL_SIZE,
				CELL_SIZE
			)
			frames.add_frame(animation_name, atlas)

	animated.sprite_frames = frames
	animated.visible = true
	slime_body.visible = false

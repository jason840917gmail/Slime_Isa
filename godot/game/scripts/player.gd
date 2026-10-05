extends Node
class_name PlayerScript
## Scene script `game.player` (Phaser `PlayerScript`, `PlayerController`, `PlayerHealthController/
## Service`, `PlayerAbilityController` (dodge only) and the player part of
## `WorldScene.updateGameplay`). Implements the player spec end to end.
##
## Node: `PlayerScript` (plain Node child of the `PlayerSlime` CharacterBody2D root). The root is
## re-anchored to the feet (`metadata/depth_anchor = (0, 27.56)`); everything Phaser did on the
## body position uses `get_centre()` (player spec section 11).
## This script is the only code that moves the player body (`ArcadeMover.move`, never
## `move_and_slide()`).
##
## Process model:
## - `process_mode = PROCESS_MODE_ALWAYS` (set in `_ready`) so `_unhandled_input` keeps capturing
##   presses during hit-stop (they are stamped with the frozen SimClock time) and the real-time
##   hit flash / defeat delay keep running. `_physics_process` returns immediately while
##   `get_tree().paused` (hit-stop or modal), which freezes the state machine like Phaser.
## - Every gameplay timer uses `Services.now_ms()` (SimClock).
## - Per physics step: state machine (player spec 4.1) at the top, then `ArcadeMover.move()`
##   (Arcade-style resolution; velocity persists between steps; a roll/knockback velocity is
##   only rewritten when it ends, apart from a blocked axis being zeroed).
##
## Collaborators: PlayerCombat (res://game/combat/player_combat.gd, set by main.gd through
## `set_combat`) for the attack; DamageRouter (receiver registration); GameFeel (feel presets,
## floating text, particles, audio cues); HitFlash (Visual fill shader); SquashStretch.
##
## Owner: player builder.

const Services := preload("res://game/shared/services.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const Directions := preload("res://game/shared/directions.gd")
const PlayerInputBuffer := preload("res://game/player/player_input_buffer.gd")
const PointerAim := preload("res://game/player/pointer_aim.gd")
const SquashStretch := preload("res://game/player/squash_stretch.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const PlayerCombat := preload("res://game/combat/player_combat.gd")

## Phaser code literals (not in game-constants.json), named with their source.
## PlayerHealthController.ts:134 (and :172).
const KNOCKBACK_DURATION_MS := 160.0
## PlayerHealthController.ts:171 (direct applyDamage path only; unused by the trial).
const FALLBACK_KNOCKBACK_STRENGTH := 220.0
## PlayerStats.ts:71.
const DAMAGE_TAKEN_MULTIPLIER := 1.0
## WorldScene.ts:1912-1913 (real time).
const HIT_FLASH_COLOR := Color("#ff6f88")
const HIT_FLASH_MS := 120.0
## WorldScene.ts:1932 (real time) - defeat screen is OUT, the trial respawns directly.
const DEFEAT_RESPAWN_DELAY_MS := 1400.0
## WorldScene.ts:908 (move-start squash after this long standing still).
const MOVE_START_IDLE_MS := 150.0
## Floating text heights above the old centre (WorldScene).
const TEXT_RISE_PX := 30.0
const DEFEAT_TEXT_RISE_PX := 40.0
## Respawn camera pan (WorldScene.respawnPlayer).
const RESPAWN_PAN_MS := 350.0
## PlayerScript.ts:73-91 receiver rule (camelCase like scene damageRule dictionaries).
const DAMAGE_RULE := {"priority": 0, "damageMultiplier": 1}
## Router target tags of the player hurtbox.
const RECEIVER_TAGS: Array[String] = ["player"]

## JSON `body`: the PlayerSlime CharacterBody2D root.
@export var body: CharacterBody2D
## JSON `visual`: the slime Sprite2D (authored scale 0.28125; hit flash + squash target).
@export var visual: Sprite2D
## JSON `animation`: the AnimationPlayer. Clips from the three-quarter top-down sheet come per
## direction (`idle-down`, `roll-side`, `attack-1-up`, ...; see `_directional_clip`); the rest
## (knockback, die, ... - player spec 1.1) still draw the old side-view sheet.
@export var animation: AnimationPlayer
## JSON `damageArea`: the hurtbox Area2D (layer hurtbox, mask hitbox).
@export var damage_area: Area2D
## JSON `playerName` ("bob"; the name tag is OUT/optional).
@export var player_name: String = ""
## Trial setting (not in JSON): the dodge counts as learned (player spec 5.1 trial note).
@export var dodge_learned: bool = true
## Player spec 9.1 [QUIRK]: aim origin height above the OLD CENTRE. 28 = literal Phaser parity
## (feet - 55.56), kept by the owner (decision O2, 2026-10-05); 0.44 would give "feet - 28".
@export var aim_rise_px: float = 28.0

## Phaser `health_changed`. Payload: {"hp": int, "maxHp": int}.
signal health_changed(payload: Dictionary)
## Phaser `damaged` -> HurtSfx.play_cue. Payload: the router commit (see DamageRouter).
signal damaged(commit: Dictionary)
## Phaser `defeated` -> DeathSfx.play_cue. Payload: {"receiverNodeId": String}.
signal defeated(payload: Dictionary)
## Phaser `damage_feedback` (no scene listener). Payload: the commit.
signal damage_feedback(commit: Dictionary)
## Godot-only: emitted after a respawn. Payload: {"x": float, "y": float} (old centre). main.gd
## pans the camera on it.
signal respawned(payload: Dictionary)

var _input: PlayerInputBuffer = PlayerInputBuffer.new()
var _squash: SquashStretch = SquashStretch.new()
var _combat: PlayerCombat
var _facing: Vector2 = Vector2(0.0, 1.0)
## The Visual's authored offset and skew. The attack clips key both for their lunge; a clip that
## replaces one mid-swing starts from these (`_play_clip`).
var _visual_rest_offset: Vector2 = Vector2.ZERO
var _visual_rest_skew: float = 0.0
var _hp: int = 0
var _max_hp: int = 0
var _dead: bool = false
var _action_locked: bool = false
## Simulation-time deadlines (ms).
var _dodge_until_ms: float = 0.0
var _roll_until_ms: float = 0.0
var _movement_suppressed_until_ms: float = 0.0
var _knockback_anim_until_ms: float = 0.0
var _iframe_until_ms: float = 0.0
var _dodge_cooldown_until_ms: float = 0.0
## Real-time deadlines (Time.get_ticks_msec()).
var _flash_until_real_ms: float = 0.0
var _respawn_at_real_ms: float = -1.0
## Move-start squash bookkeeping.
var _was_moving: bool = false
var _still_since_ms: float = 0.0
var _pointer_seen: bool = false

## Clip names (player spec 1.1). Every clip resolves to its directional version when the scene
## has one (`_directional_clip`).
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_ROLL := "roll"
const CLIP_KNOCKBACK := "knockback"
const CLIP_DIE := "die"
## InitialRun.ts:15 new-run coins (coins are OUT; the HUD snapshot shows the new-run value).
const NEW_RUN_COINS := 50
## Global audio cues (AudioEventBridge.ts:31-42).
const CUE_DODGE := &"Dodge"
const CUE_ABILITY_DENIED := &"AbilityDenied"
const CUE_RESPAWN := &"Respawn"
## Feel / particle / squash event ids.
const FEEL_PLAYER_HURT := &"player-hurt"
const FEEL_PLAYER_DEFEATED := &"player-defeated"
const PARTICLES_SLIME_SPLASH := &"slime-splash"
const PARTICLES_DODGE_DUST := &"dodge-dust"
const SQUASH_HIT := &"hit"
const SQUASH_MOVE_START := &"move-start"
## Router effect id carrying the knockback strength (combat spec 7.4).
const EFFECT_KNOCKBACK := "knockback"

## Values from game-constants.json (`character.player.*`, `input.*`), cached in `_ready`.
var _base_speed: float = 0.0
var _boost_speed: float = 0.0
var _speed_cap: float = 0.0
var _dodge_speed: float = 0.0
var _dodge_duration_ms: float = 0.0
var _dodge_iframes_ms: float = 0.0
var _dodge_cooldown_ms: float = 0.0
var _hit_iframes_ms: float = 0.0
var _defense: float = 0.0
var _max_energy: int = 0
var _buffer_ms: float = 0.0
## The hurtbox currently registered with the router (null when not registered).
var _registered_area: Area2D
## True while a modal pause reason is active (input was cleared when it began).
var _modal_paused: bool = false


## Sets PROCESS_MODE_ALWAYS; reads hp/maxHp from `character.player.stats.maxHp`; registers
## `damage_area` with `Services.router().register_area(damage_area, self, DAMAGE_RULE,
## RECEIVER_TAGS)`; joins groups "player" and "damage-target"; installs HitFlash on `visual`;
## sets up SquashStretch; `body.motion_mode = MOTION_MODE_FLOATING`; plays "idle".
## (Registration and groups also happen in `_enter_tree`, like Phaser, so a re-parented player
## re-registers; `_ready` does the one-time setup.)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_constants()
	_hp = _max_hp
	if visual != null:
		HitFlash.install(visual)
		_squash.setup(visual)
		_visual_rest_offset = visual.offset
		_visual_rest_skew = visual.skew
	if body != null:
		body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_register_receiver()
	_play_idle()
	_still_since_ms = _real_now_ms()


func _enter_tree() -> void:
	add_to_group(&"player")
	add_to_group(&"damage-target")
	_register_receiver()


## Unregisters the hurtbox and clears input (scene exit).
func _exit_tree() -> void:
	_unregister_receiver()
	clear_input()


## Window focus lost: no release events arrive for keys held at that moment, so forget them
## (otherwise the slime keeps walking after alt-tab or a click outside the web canvas).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_input()


## Player spec 7.2: feeds PlayerInputBuffer with the SimClock time; tracks
## `InputEventMouseMotion` to set `_pointer_seen`; marks captured events handled.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_seen = true
		return
	if event is InputEventMouseButton:
		_pointer_seen = true
	if _input.capture(event, Services.now_ms()):
		get_viewport().set_input_as_handled()


## Returns while the tree is paused. Otherwise runs the per-step state machine of player spec
## 4.1 in this order: dead -> stop; read direction; movement suppressed (roll/knockback) -> keep
## velocity; action locked (weapon swing) -> velocity 0; handle_action_input() consumed ->
## keep last velocity this step; else move-start squash + move(direction) (player spec 4.3,
## 4.5). Then `ArcadeMover.move(body, delta)`.
func _physics_process(delta: float) -> void:
	if get_tree().paused or body == null:
		return
	if _dead:
		# No input is consumed while dead; pending presses simply age out.
		body.velocity = Vector2.ZERO
	else:
		var direction: Vector2 = _input.movement_vector()
		if is_movement_suppressed():
			pass # Roll / knockback own the body: their velocity persists, presses stay buffered.
		elif _action_locked:
			body.velocity = Vector2.ZERO
		elif _handle_action_input():
			pass # An action was used this step: velocity keeps the last step's value once.
		else:
			_squash_on_move_start(direction)
			_move(direction)
	# Arcade-style step (player spec 5.2): a wall hit zeroes the blocked velocity component, which
	# then stays zero for the rest of a roll or knockback (CharacterBody2DNode.ts:61-66).
	ArcadeMover.move(body, delta)


## Real-time work (runs during hit-stop): ends the 120 ms hit flash; after a death, respawns
## once DEFEAT_RESPAWN_DELAY_MS have passed.
func _process(_delta: float) -> void:
	var now_real: float = _real_now_ms()
	if _flash_until_real_ms > 0.0 and now_real >= _flash_until_real_ms:
		_flash_until_real_ms = 0.0
		if visual != null:
			HitFlash.clear(visual)
	if _respawn_at_real_ms >= 0.0 and now_real >= _respawn_at_real_ms:
		_respawn_at_real_ms = -1.0
		respawn()
	_update_modal_pause()


# --- queries used by other systems -------------------------------------------------------------

## Old Phaser body position (sprite centre) = feet - (0, 27.56). Enemies, camera and texts use it.
func get_centre() -> Vector2:
	if body == null:
		return Vector2.ZERO
	return FeetAnchor.phaser_position(body)


## Unit facing vector (initial (0,1)); 8-way from movement, cardinal after attack/dodge.
func get_facing() -> Vector2:
	return _facing


## `PlayerController.face` (player spec 4.4): ignores zero; sets facing (normalized) and the flip
## for the clip on screen (`_flip_for`; `Directions.slime_flip_h(dir)` for the old side-view art).
## The clip itself changes with the next play: facing down mid-swing keeps the swing's row.
func face(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	_facing = direction.normalized()
	if visual == null:
		return
	if animation != null:
		visual.flip_h = _flip_for(String(animation.assigned_animation))
	else:
		visual.flip_h = Directions.slime_flip_h(direction)


## True from the killing blow until respawn.
func is_dead() -> bool:
	return _dead


## Current and maximum HP (integers, GameState semantics).
func get_hp() -> int:
	return _hp


func get_max_hp() -> int:
	return _max_hp


## HUD data in Phaser keys: {"hp", "maxHp", "energy", "maxEnergy", "coins"}. Energy is
## `character.player.stats.maxEnergy` (full; energy is OUT); coins = new-run 50
## (InitialRun.ts:15, coins are OUT).
func get_hud_snapshot() -> Dictionary:
	return {
		"hp": _hp,
		"maxHp": _max_hp,
		"energy": _max_energy,
		"maxEnergy": _max_energy,
		"coins": NEW_RUN_COINS,
	}


## The hurtbox Area2D (enemy damage requests target it).
func get_damage_area() -> Area2D:
	return damage_area


## The slime Sprite2D.
func get_visual() -> Sprite2D:
	return visual


## Called once by main.gd after it created and set up PlayerCombat.
func set_combat(combat: PlayerCombat) -> void:
	_combat = combat


## The PlayerCombat set by main.gd (null before `set_combat`).
func get_combat() -> PlayerCombat:
	return _combat


## Weapon swing lock (CombatController onAttackStarted/Finished): while locked the state machine
## zeroes velocity every step and consumes no input (presses stay buffered).
func set_action_locked(locked: bool) -> void:
	_action_locked = locked


func is_action_locked() -> bool:
	return _action_locked


## `sim < movement_suppressed_until or sim < roll_until` (PlayerScript.ts:135-137).
func is_movement_suppressed() -> bool:
	var now: float = Services.now_ms()
	return now < _movement_suppressed_until_ms or now < _roll_until_ms


## Freezes walking and buffered actions for `ms` of simulation time (the area travel's leave fade).
func suppress_movement(ms: float) -> void:
	_movement_suppressed_until_ms = maxf(_movement_suppressed_until_ms, Services.now_ms() + ms)


## What RunState keeps of the player when it leaves a world: {"hp", "facing", "x", "y"}, x/y the
## old Phaser (centre) position, facing "up"|"down"|"left"|"right".
func run_snapshot() -> Dictionary:
	var centre: Vector2 = get_centre()
	return {"hp": _hp, "facing": Directions.cardinal_name(_facing), "x": centre.x, "y": centre.y}


## Takes the run's HP (`RunState.player`, GameState semantics: max HP grows with Goo Hearts).
## HP is clamped to the maximum; a dead or missing value starts full (Phaser revives on load).
func restore_run_state(state: Dictionary) -> void:
	var run := Services.run()
	if run != null:
		_max_hp = run.max_hp()
	var hp := int(state.get("hp", _max_hp))
	_hp = clampi(hp, 1, _max_hp) if hp > 0 else _max_hp
	health_changed.emit({"hp": _hp, "maxHp": _max_hp})


## `sim < dodge_until` (dodge i-frames).
func is_dodging() -> bool:
	return Services.now_ms() < _dodge_until_ms


## `sim < roll_until`: the whole roll, including the vulnerable tail after the i-frames.
func is_rolling() -> bool:
	return Services.now_ms() < _roll_until_ms


## Sets `body.velocity = Vector2.ZERO`.
func stop_movement() -> void:
	if body != null:
		body.velocity = Vector2.ZERO


## `WorldScene.playAnimation` gate (player spec 4.3 "Other rules"): while dead only "die"
## passes; while `sim < knockback_anim_until` only "die" and a forced "knockback" pass; otherwise
## skip if it is the current clip and not forced. `force` restarts the clip (stop + play).
## `clip` plays as its directional version when the scene has one (`_directional_clip`).
## Returns false when the clip was refused or does not exist.
func play_animation(clip: String, force: bool = false) -> bool:
	if animation == null or not animation.has_animation(_directional_clip(clip)):
		return false
	if _dead and clip != CLIP_DIE:
		return false
	var knockback_has_priority: bool = Services.now_ms() < _knockback_anim_until_ms
	var forced_knockback: bool = force and clip == CLIP_KNOCKBACK
	if knockback_has_priority and clip != CLIP_DIE and not forced_knockback:
		return false
	_play_clip(clip, force)
	return true


## Player spec 6.4: knockback_anim_until and movement_suppressed_until = max(old, sim +
## duration_ms); `body.velocity = direction.normalized() * strength` (constant, no decay);
## force-play "knockback". Ignored for a zero direction or strength <= 0.
func apply_knockback(direction: Vector2, strength: float, duration_ms: float) -> void:
	if direction == Vector2.ZERO or strength <= 0.0 or duration_ms < 0.0:
		return
	var now: float = Services.now_ms()
	_knockback_anim_until_ms = maxf(_knockback_anim_until_ms, now + duration_ms)
	_movement_suppressed_until_ms = maxf(_movement_suppressed_until_ms, now + duration_ms)
	if body != null:
		body.velocity = direction.normalized() * strength
	play_animation(CLIP_KNOCKBACK, true)


## Empties held keys and pending presses (pause / scene exit).
func clear_input() -> void:
	_input.clear()


## `PlayerScript.consumeActionPress` (player spec 7.3): uses a pending press of `action` if it is
## at most `input.bufferMs` old (older presses are dropped).
func consume_action_press(action: StringName) -> bool:
	return _input.consume(action, Services.now_ms(), _buffer_ms)


## `PlayerScript.isActionPressed`: true while `action` is held.
func is_action_held(action: StringName) -> bool:
	return _input.is_held(action)


## Player spec 6.7 (trial: no defeat screen): hp = maxHp, alive, i-frames cleared,
## knockback window cleared, teleport to the spawn (old centre -> FeetAnchor), force "idle",
## clear the flash, floating "Respawned" green at spawn - (0, 40), audio cue "Respawn", emit
## `health_changed` and `respawned`.
## Spawn point: Phaser `respawnPlayer` uses `findSpawnPoint(level spawn marker)` (the centre of
## the first free tile around the marker, e.g. (672, 736) for level-1's (640, 704)), which this
## port keeps: `world.find_spawn_point(world.player_spawn_marker())`.
func respawn() -> void:
	_respawn_at_real_ms = -1.0
	_hp = _max_hp
	_dead = false
	_iframe_until_ms = 0.0
	_audio_cue(CUE_RESPAWN)
	var spawn: Vector2 = _respawn_point()
	if body != null:
		body.velocity = Vector2.ZERO
		FeetAnchor.place_at_phaser_position(body, spawn)
		body.reset_physics_interpolation()
	_knockback_anim_until_ms = 0.0
	_play_idle(true)
	_flash_until_real_ms = 0.0
	if visual != null:
		HitFlash.clear(visual)
		visual.modulate = Color.WHITE
	_floating_text(spawn - Vector2(0.0, DEFEAT_TEXT_RISE_PX), "Respawned", &"green", true)
	health_changed.emit({"hp": _hp, "maxHp": _max_hp})
	respawned.emit({"x": spawn.x, "y": spawn.y})


# --- damage receiver API (called by DamageRouter; combat spec 7.1 / 7.4) --------------------------

## {"hp": float, "max_hp": float, "dead": bool} (`dead` also when hp <= 0).
func get_damage_state() -> Dictionary:
	return {"hp": float(_hp), "max_hp": float(_max_hp), "dead": _dead or _hp <= 0}


## Player spec 6.2: dodging -> {"accepted": false, "reason": "state-blocked"}; sim < iframe_until
## -> same; else {"accepted": true, "reason": ""}. "state-blocked" is retryable.
func can_receive_damage(input: Dictionary) -> Dictionary:
	if is_dodging():
		return {"accepted": false, "reason": "state-blocked"}
	var sim: float = float(input.get("simulation_time", Services.now_ms()))
	if sim < _iframe_until_ms:
		return {"accepted": false, "reason": "state-blocked"}
	return {"accepted": true, "reason": ""}


## `scaled == 0 -> 0`; else `max(1, scaled - defense) * DAMAGE_TAKEN_MULTIPLIER`
## (defense = `character.player.stats.defense`); true damage (OUT; request key `true_damage`)
## skips the defense.
func mitigate_damage(input: Dictionary) -> float:
	var scaled: float = float(input.get("scaled_damage", 0.0))
	if scaled == 0.0:
		return 0.0
	var request: Dictionary = _dict(input.get("request"))
	var true_damage: bool = bool(request.get("true_damage", false))
	var after_defense: float = scaled if true_damage else maxf(1.0, scaled - _defense)
	return after_defense * DAMAGE_TAKEN_MULTIPLIER


## Player spec 6.3 and 6.6: hp -= actual (clamped at 0); on reaching 0 run the death
## sequence synchronously (die forced, stop, feel "player-defeated", "DEFEATED" text, schedule
## the respawn); else if actual > 0 set i-frames `commit.simulation_time + hitInvulnerabilityMs`;
## emit health_changed, damaged(commit) (also for a 0-damage effect-only hit), and defeated when dead.
func commit_damage(commit: Dictionary) -> void:
	var result: Dictionary = _dict(commit.get("result"))
	var actual: int = int(result.get("actual_damage", 0))
	# GameState.damage: ignores amount <= 0 or an already dead player; clamps at 0; reaching 0
	# runs the death synchronously.
	if actual > 0 and not _dead:
		_hp = maxi(0, _hp - actual)
		if _hp <= 0:
			_die()
	if bool(result.get("defeated", false)):
		_die()
	elif actual > 0:
		var sim: float = float(commit.get("simulation_time", Services.now_ms()))
		_iframe_until_ms = sim + _hit_iframes_ms
	health_changed.emit({"hp": _hp, "maxHp": _max_hp})
	damaged.emit(commit)
	if _dead:
		var receiver_id: String = str(body.get_path()) if body != null and body.is_inside_tree() else str(get_path())
		defeated.emit({"receiverNodeId": receiver_id})


## Player spec 6.4 / 6.5: emit damage_feedback; if actual > 0 the hit presentation (feel
## "player-hurt", squash "hit", "slime-splash" particles at the centre, red "-N" text at
## centre - 30, real-time flash unless one is running); return if defeated; knockback with the
## applied "knockback" potency along `request.impact.knock` for KNOCKBACK_DURATION_MS.
## Order follows PlayerScript.publishDamageFeedback: health feedback first, then the signal.
func publish_damage_feedback(commit: Dictionary) -> void:
	var result: Dictionary = _dict(commit.get("result"))
	var actual: int = int(result.get("actual_damage", 0))
	if actual > 0:
		_present_hit(actual)
	if not bool(result.get("defeated", false)):
		var strength: float = _applied_potency(result, EFFECT_KNOCKBACK)
		if strength > 0.0:
			var request: Dictionary = _dict(commit.get("request"))
			var impact: Dictionary = _dict(request.get("impact"))
			var knock_value: Variant = impact.get("knock", Vector2.ZERO)
			var knock: Vector2 = knock_value if knock_value is Vector2 else Vector2.ZERO
			if knock.length_squared() > 0.0:
				apply_knockback(knock.normalized(), strength, KNOCKBACK_DURATION_MS)
	damage_feedback.emit(commit)


## Built-in `PickupArea.area_entered` handler wired by the converter. Pickups are OUT: no-op.
func on_pickup_area_entered(_area: Node) -> void:
	pass


# --- private steps -------------------------------------------------------------------------------

## Player spec 5.1 / 9: consume buffered presses in Phaser's order (dodge, then attack); the first
## consumed press wins and ends the step. Returns true when an action was consumed.
func _handle_action_input() -> bool:
	var now: float = Services.now_ms()
	if _input.consume(&"dodge", now, _buffer_ms):
		_try_dodge()
		return true
	if _input.consume(&"attack", now, _buffer_ms):
		_attack()
		return true
	return false


## Player spec 4.3: walk/sprint speed from `character.player.movement` (baseSpeed, boostSpeed,
## movementSpeedCap via resolve_movement_speed), normalized direction, facing/flip, clip choice.
## Boost bonus items, status speed multipliers, roots and Gulp forms are OUT (0 / 1 / none / 1).
func _move(direction: Vector2) -> void:
	if body == null or is_movement_suppressed():
		return
	var sprinting: bool = _input.is_held(&"sprint")
	var base: float = _boost_speed if sprinting else _resolve_movement_speed(_base_speed)
	var speed: float = _resolve_movement_speed(base)
	if direction == Vector2.ZERO:
		body.velocity = Vector2.ZERO
		_play_direct(CLIP_IDLE)
		return
	var unit: Vector2 = direction.normalized()
	body.velocity = unit * speed
	_facing = unit
	_play_direct(CLIP_WALK)


## Idle for the current facing; `force` restarts it (respawn).
func _play_idle(force: bool = false) -> void:
	play_animation(CLIP_IDLE, force)


## `<clip>-down`, `-up` or `-side` for the current facing when the scene has it (the
## three-quarter top-down sheet, docs/assets/slime-sheet-guide.md), else `clip` itself.
## Mostly vertical facings pick down/up; diagonals and horizontals pick side, or `<clip>-left`
## when facing left and the scene has one (a clip whose keyed motion has a direction, such as the
## attack lunge: flip_h mirrors the art but not a keyed offset).
func _directional_clip(clip: String) -> String:
	if animation == null:
		return clip
	var suffix := "side"
	if absf(_facing.y) > absf(_facing.x):
		suffix = "down" if _facing.y > 0.0 else "up"
	elif _facing.x < 0.0 and animation.has_animation("%s-left" % clip):
		suffix = "left"
	var directional := "%s-%s" % [clip, suffix]
	return directional if animation.has_animation(directional) else clip


## Horizontal flip for `clip` at the current facing. The top-down side art faces right, so it
## mirrors for left (always, in a `-left` clip); its down/up art never mirrors, and it keeps the
## last facing when idle (owner decision O4). Old side-view clips keep their rule (that art faces
## left and mirrors for right, `Directions.slime_flip_h`), except its idle, which always showed
## its default facing.
func _flip_for(clip: String) -> bool:
	if clip.ends_with("-side"):
		return _facing.x < 0.0
	if clip.ends_with("-left"):
		return true
	if clip.ends_with("-down") or clip.ends_with("-up") or clip == CLIP_IDLE:
		return false
	return Directions.slime_flip_h(_facing)


## Player spec 5.1 / 5.2: dodge rules (learned, cooldown 500+250 ms from roll start) and the roll
## (pointer aim snapped to a cardinal, else facing; 380 px/s for 500 ms, i-frames 400 ms),
## "roll" clip, audio cue "Dodge", "dodge-dust" at the feet, cyan "DODGE" at centre - 30.
## Returns true when the roll started.
func _try_dodge() -> bool:
	var aim: Vector2 = _pointer_aim()
	var toward: Vector2 = aim if aim != Vector2.ZERO else _facing
	# PlayerAbilityService order: busy (OUT) -> locked -> cooldown (silent) -> action-locked.
	if not dodge_learned:
		_floating_text(get_centre() - Vector2(0.0, TEXT_RISE_PX), "Not learned yet", &"red", false)
		_audio_cue(CUE_ABILITY_DENIED)
		return false
	var now: float = Services.now_ms()
	if now < _dodge_cooldown_until_ms:
		return false
	if _action_locked:
		_audio_cue(CUE_ABILITY_DENIED)
		return false
	# PlayerAbilityDefinitions.ts:214: cooldown = roll duration + post-roll cooldown, from now.
	_dodge_cooldown_until_ms = now + _dodge_duration_ms + _dodge_cooldown_ms
	return _begin_roll(Directions.snap_to_cardinal(toward))


## `PlayerController.tryDodge` + `PlayerScript.beginDodge` (player spec 5.2).
func _begin_roll(direction: Vector2) -> bool:
	if body == null:
		return false
	var roll_direction: Vector2 = direction
	if roll_direction == Vector2.ZERO:
		roll_direction = _facing
	if roll_direction == Vector2.ZERO:
		roll_direction = Vector2.RIGHT
	roll_direction = roll_direction.normalized()
	if is_movement_suppressed() or _dodge_duration_ms <= 0.0 or _dodge_iframes_ms < 0.0:
		return false
	var now: float = Services.now_ms()
	_dodge_until_ms = maxf(_dodge_until_ms, now + minf(_dodge_iframes_ms, _dodge_duration_ms))
	_roll_until_ms = maxf(_roll_until_ms, now + _dodge_duration_ms)
	# Set once; persists for the whole roll (a wall hit zeroes the blocked axis via ArcadeMover.move).
	body.velocity = roll_direction * _resolve_movement_speed(_dodge_speed)
	# Phaser plays the clip, then faces; facing first picks the roll's directional row.
	face(roll_direction)
	_play_direct(CLIP_ROLL)
	_audio_cue(CUE_DODGE)
	var centre: Vector2 = get_centre()
	var feel := Services.feel()
	if feel != null:
		# Phaser resolveBodyBottom = the feet = the Godot root origin.
		feel.particles(PARTICLES_DODGE_DUST, Vector2(centre.x, body.global_position.y))
	_floating_text(centre - Vector2(0.0, TEXT_RISE_PX), "DODGE", &"cyan", false)
	return true


## Player spec 9.1: face the pointer aim (snapped) when there is one, then `_combat.try_attack()`.
## The facing changes even if the swing is then refused. (`attackAim: facing` is a dev-panel
## setting and OUT: the default `pointer` mode is always used.)
func _attack() -> bool:
	var aim: Vector2 = _pointer_aim()
	if aim != Vector2.ZERO:
		face(Directions.snap_to_cardinal(aim))
	if _combat == null or not is_instance_valid(_combat):
		return false
	return _combat.try_attack()


## `resolveMovementSpeed(base, flat, mult) = min(cap, max(0, (base + flat) * max(0, mult)))`
## (PlayerStats.ts:53-56) with cap = `character.player.movement.movementSpeedCap`.
func _resolve_movement_speed(base: float, flat: float = 0.0, multiplier: float = 1.0) -> float:
	return minf(_speed_cap, maxf(0.0, (base + flat) * maxf(0.0, multiplier)))


## Aim origin: `get_centre() - Vector2(0, aim_rise_px)`; pointer = `body.get_global_mouse_position()`.
## Vector2.ZERO when there is no aim (pointer never seen, or within the dead zone).
func _pointer_aim() -> Vector2:
	if body == null or not body.is_inside_tree():
		return Vector2.ZERO
	var origin: Vector2 = get_centre() - Vector2(0.0, aim_rise_px)
	return PointerAim.aim(origin, body.get_global_mouse_position(), _pointer_seen)


## `WorldScene.squashOnMoveStart` (player spec 4.5), on scene (real) time like Phaser.
func _squash_on_move_start(direction: Vector2) -> void:
	var moving: bool = direction != Vector2.ZERO
	var now_real: float = _real_now_ms()
	if moving and not _was_moving and now_real - _still_since_ms >= MOVE_START_IDLE_MS:
		_squash.play(SQUASH_MOVE_START)
	if not moving and _was_moving:
		_still_since_ms = now_real
	_was_moving = moving


## Player spec 6.6 (`WorldScene.onPlayerDeath`); idempotent. Runs synchronously inside the
## commit, before the `damaged` / `defeated` signals and the hit presentation.
## Phaser's `resetActiveFights` has no call here: enemies disengage through
## `primary_target().active` (enemy spec).
func _die() -> void:
	if _dead:
		return
	_dead = true
	_knockback_anim_until_ms = 0.0
	play_animation(CLIP_DIE, true)
	stop_movement()
	var feel := Services.feel()
	if feel != null:
		feel.play(FEEL_PLAYER_DEFEATED)
	_floating_text(get_centre() - Vector2(0.0, DEFEAT_TEXT_RISE_PX), "DEFEATED", &"red", true)
	_respawn_at_real_ms = _real_now_ms() + DEFEAT_RESPAWN_DELAY_MS


## `WorldScene.onPlayerHit` (player spec 6.5), only for `actual > 0`.
func _present_hit(actual: int) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.play(FEEL_PLAYER_HURT)
	_squash.play(SQUASH_HIT)
	var centre: Vector2 = get_centre()
	if feel != null:
		feel.particles(PARTICLES_SLIME_SPLASH, centre)
	_floating_text(centre - Vector2(0.0, TEXT_RISE_PX), "-%d" % actual, &"red", true)
	# Real-time 120 ms flash; a hit during a running flash does not extend it.
	if _flash_until_real_ms <= 0.0 and visual != null:
		_flash_until_real_ms = _real_now_ms() + HIT_FLASH_MS
		HitFlash.flash(visual, HIT_FLASH_COLOR)


## Phaser port rule (`PlayerNodePorts.play`, used directly by `PlayerScript.move` / `beginDodge`):
## no gate; restarts only when the clip differs from the assigned one.
func _play_direct(clip: String) -> void:
	if animation == null or not animation.has_animation(_directional_clip(clip)):
		return
	_play_clip(clip, false)


## `force` restarts the clip from its first frame. Otherwise the clip starts only when it is not
## the assigned one; an assigned looping clip that was stopped is resumed, and a finished one-shot
## clip keeps holding its last frame (Phaser behaviour).
## A (re)started clip shows its first key on the same step (Phaser `AnimationClock.start`
## dispatches frame 0 synchronously, clock.ts:104-120): `seek(0.0, true)` applies it at once, so a
## hit-stop that pauses the tree right after still shows the new pose. No `stop()` before a forced
## restart: it would snap the outgoing clip to its own frame 0 first.
## `base_clip` resolves to its directional version (`_directional_clip`) and sets the flip for it.
## A (re)started clip starts from the Visual's rest offset and skew, so one that cuts a swing's
## lunge short does not keep it.
func _play_clip(base_clip: String, force: bool) -> void:
	var clip := _directional_clip(base_clip)
	if visual != null:
		visual.flip_h = _flip_for(clip)
	if force or animation.assigned_animation != clip:
		if visual != null:
			visual.offset = _visual_rest_offset
			visual.skew = _visual_rest_skew
		animation.play(clip)
		animation.seek(0.0, true)
	elif not animation.is_playing() and _is_looping(clip):
		animation.play(clip)


func _is_looping(clip: String) -> bool:
	var anim: Animation = animation.get_animation(clip)
	return anim != null and anim.loop_mode != Animation.LOOP_NONE


func _respawn_point() -> Vector2:
	var world := Services.world()
	if world == null:
		return get_centre()
	return world.find_spawn_point(world.player_spawn_marker())


## Modal pause (OUT in the trial, handled for parity): when a modal reason becomes active the held
## input is cleared and the body stops (`setPaused -> clearInput`, `stopMovingBodies`).
func _update_modal_pause() -> void:
	var world := Services.world()
	var modal: bool = world != null and world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL)
	if modal and not _modal_paused:
		clear_input()
		stop_movement()
	_modal_paused = modal


func _register_receiver() -> void:
	if damage_area == null or _registered_area == damage_area:
		return
	var router := Services.router()
	if router == null:
		return
	router.register_area(damage_area, self, DAMAGE_RULE, RECEIVER_TAGS)
	_registered_area = damage_area


func _unregister_receiver() -> void:
	if _registered_area == null:
		return
	var router := Services.router()
	if router != null and is_instance_valid(_registered_area):
		router.unregister_area(_registered_area)
	_registered_area = null


func _load_constants() -> void:
	_base_speed = _number("character.player.movement.baseSpeed")
	_boost_speed = _number("character.player.movement.boostSpeed")
	_speed_cap = _number("character.player.movement.movementSpeedCap")
	_dodge_speed = _number("character.player.movement.dodgeSpeed")
	_dodge_duration_ms = _number("character.player.movement.dodgeDurationMs")
	_dodge_iframes_ms = _number("character.player.movement.dodgeInvulnerabilityMs")
	_dodge_cooldown_ms = _number("character.player.movement.dodgeCooldownMs")
	_hit_iframes_ms = _number("character.player.hitInvulnerabilityMs")
	_defense = _number("character.player.stats.defense")
	_max_hp = roundi(_number("character.player.stats.maxHp"))
	_max_energy = roundi(_number("character.player.stats.maxEnergy"))
	_buffer_ms = _number("input.bufferMs")


func _number(path: String) -> float:
	var store := Services.constants()
	if store == null:
		push_error("PlayerScript: GameConstants autoload missing (reading %s)." % path)
		return 0.0
	return store.number(path)


## Potency of the applied effect `effect_id` in a router result (0 when absent).
func _applied_potency(result: Dictionary, effect_id: String) -> float:
	var effects: Variant = result.get("applied_effects", [])
	if not effects is Array:
		return 0.0
	for effect: Variant in effects:
		if effect is Dictionary and str((effect as Dictionary).get("effect_id", "")) == effect_id:
			return float((effect as Dictionary).get("potency", 0.0))
	return 0.0


func _floating_text(world_position: Vector2, text: String, color: StringName, big: bool) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(world_position, text, color, big)


func _audio_cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _real_now_ms() -> float:
	return float(Time.get_ticks_msec())

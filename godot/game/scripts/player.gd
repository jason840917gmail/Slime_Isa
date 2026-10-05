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
const GulpWheel := preload("res://game/player/gulp/gulp_wheel.gd")
const SquashStretch := preload("res://game/player/squash_stretch.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const PlayerCombat := preload("res://game/combat/player_combat.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")
const SleepController := preload("res://game/rest/sleep_controller.gd")
const PlayerAbilities := preload("res://game/player/abilities/player_abilities.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const GulpController := preload("res://game/player/gulp/gulp_controller.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const GulpHud := preload("res://game/player/gulp/gulp_hud.gd")
const StatusEffects := preload("res://game/player/status_effects.gd")
const GooTrail := preload("res://game/player/goo_trail.gd")

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
## Energy changed (GameState `energy.changed`). Payload: {"energy", "maxEnergy", "delta"}.
signal energy_changed(payload: Dictionary)
## A jump landed. Payload: {"x", "y" (old centre), "heavy": bool, "id": int}.
signal jump_landed(payload: Dictionary)

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
## Simulation time an action clip (`play_action_clip`) ends and unlocks; < 0 when none.
var _action_clip_until_ms: float = -1.0
## Sleeping in a bed (game/rest/sleep_controller.gd).
var _sleep: SleepController = SleepController.new(self)
var _art_rest_position: Vector2 = Vector2.ZERO
var _art_rest_position_known: bool = false
## Abilities (game/player/abilities/): rules, cooldowns and the running sequence.
var _abilities: PlayerAbilities = PlayerAbilities.new(self)
## The art's offsets in world px: sleeping on a mattress, and the ability effects channel
## (Phaser `visual.effects`: offset, scale and alpha on top of the authored values).
var _art_offset: Vector2 = Vector2.ZERO
var _effect_offset: Vector2 = Vector2.ZERO
var _visual_base_scale: Vector2 = Vector2.ONE
## Energy (GameState): spent by abilities, refilled 8 per second.
var _energy: float = 0.0
var _energy_regen: float = 0.0
## The last jump landing in a plate-pressing (Heavy) form: {} or {"x", "y", "id"}.
var _heavy_landing: Dictionary = {}
var _landing_id: int = 0
## Squash Slam's attack area for the router (no shape needed: the strike queries physics).
var _slam_area: Area2D
## Eating and the Gulp form (game/player/gulp/).
var _gulp: GulpController = GulpController.new(self)
var _gulp_hud: GulpHud
## The eat press waits for its release (a tap eats; WorldScene.updateEatHold): simulation ms of
## the press and of the last step that saw it held; < 0 when no press is pending.
var _eat_since_ms: float = -1.0
var _eat_last_seen_ms: float = -1.0
## The quick wheel of the current eat hold: open, or found nothing to show (`empty`).
var _eat_wheel_open: bool = false
var _eat_wheel_empty: bool = false
var _eat_wheel_pointer_start: Vector2 = Vector2.ZERO
var _gulp_wheel: GulpWheel
## Status effects (game/player/status_effects.gd): sticky roots the slime, slow scales walking.
var _status: StatusEffects = StatusEffects.new(_status_damage)
## The world's interaction controller (group "interaction"), looked up on the first press.
var _interaction: Node
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
## Presses that wake a sleeper (SleepController consumeWakeInput).
const WAKE_ACTIONS: Array[StringName] = [&"interact", &"attack", &"jump", &"dodge", &"stretch_lash",
	&"squash_slam", &"teleport", &"eat"]
const INTERACTION_GROUP := &"interaction"
## InitialRun.ts:15 new-run coins (coins are OUT; the HUD snapshot shows the new-run value).
const NEW_RUN_COINS := 50
## Global audio cues (AudioEventBridge.ts:31-42).
const CUE_DODGE := &"Dodge"
const CUE_ABILITY_DENIED := &"AbilityDenied"
const CUE_RESPAWN := &"Respawn"
const CUE_ENERGY_RESTORE := &"EnergyRestore"
const CUE_EAT := &"Eat"
const EFFECT_WEB := "web"
const WEB_COVER_SCENE := "effect.spider-web-cover"
## Gulp form texts (WorldScene.ts:1093-1100): centre - 56.
const GULP_TEXT_RISE_PX := 56.0
## An eat press older than this without a step seeing it held is dropped (WorldScene.ts:913-969).
const EAT_HOLD_DROP_MS := 600.0
## Gulp messages over the slime (GulpController `showMessage`: centre - 56).
const GULP_MESSAGE_RISE := 56.0
## The pointer picks a wheel slot once it moved this far, aimed from the centre - 28.
const GULP_WHEEL_POINTER_SLACK := 10.0
const GULP_WHEEL_POINTER_RISE := 28.0
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
		_squash.busy = is_ability_busy
		_visual_rest_offset = visual.offset
		_visual_rest_skew = visual.skew
		_art_rest_position = visual.position
		_art_rest_position_known = true
		_visual_base_scale = visual.scale
	_energy = float(_max_energy)
	_make_slam_area()
	_make_gulp_hud()
	_make_goo_trail.call_deferred()
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
	_sleep.wake("teardown")
	_abilities.cancel()
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
	if _action_clip_until_ms >= 0.0 and Services.now_ms() >= _action_clip_until_ms:
		_action_clip_until_ms = -1.0
		set_action_locked(false)
		if not _dead:
			_play_idle()
	_abilities.advance(Services.now_ms())
	_gulp.update()
	_status.update(delta * 1000.0)
	if not _dead:
		_regen_energy(delta * 1000.0)
	if _dead:
		# No input is consumed while dead; pending presses simply age out.
		body.velocity = Vector2.ZERO
	elif _sleep.is_sleeping():
		# Sleep replaces player control (WorldScene.updateGameplay): presses only wake.
		body.velocity = Vector2.ZERO
		_sleep.update(delta * 1000.0, _wake_input())
	else:
		var direction: Vector2 = _input.movement_vector()
		if is_movement_suppressed():
			pass # Roll / knockback own the body: their velocity persists, presses stay buffered.
		elif _action_locked:
			body.velocity = Vector2.ZERO
		elif _update_eat_hold():
			body.velocity = Vector2.ZERO
		elif _handle_action_input():
			pass # An action was used this step: velocity keeps the last step's value once.
		else:
			_squash_on_move_start(direction)
			_move(direction)
	# Arcade-style step (player spec 5.2): a wall hit zeroes the blocked velocity component, which
	# then stays zero for the rest of a roll or knockback (CharacterBody2DNode.ts:61-66). The lash
	# pull places the body itself.
	if not _abilities.owns_body():
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
## `character.player.stats.maxEnergy` (full; energy is OUT); coins = RunState's (new run: 50).
func get_hud_snapshot() -> Dictionary:
	return {
		"hp": _hp,
		"maxHp": _max_hp,
		"energy": _energy,
		"maxEnergy": _max_energy,
		"coins": Services.run().coins() if Services.run() != null else NEW_RUN_COINS,
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
	return {"hp": _hp, "energy": _energy, "facing": Directions.cardinal_name(_facing), "x": centre.x, "y": centre.y}


## Takes the run's HP (`RunState.player`, GameState semantics: max HP grows with Goo Hearts).
## HP is clamped to the maximum; a dead or missing value starts full (Phaser revives on load).
func restore_run_state(state: Dictionary) -> void:
	var run := Services.run()
	if run != null:
		_max_hp = run.max_hp()
	var hp := int(state.get("hp", _max_hp))
	_hp = clampi(hp, 1, _max_hp) if hp > 0 else _max_hp
	health_changed.emit({"hp": _hp, "maxHp": _max_hp})
	_energy = clampf(float(state.get("energy", _max_energy)), 0.0, float(_max_energy))
	energy_changed.emit({"energy": _energy, "maxEnergy": _max_energy, "delta": 0.0})


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
	# The Heavy form shrugs knockback off entirely (WorldScene.ts:341-350).
	if bool(_gulp.form.get("knockback_immune", false)):
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
	# A menu or window closes the eat hold too (Phaser closes it while paused).
	_close_eat_hold()


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
	# The last bed is in another world: main rebuilds that world with the slime at the bed
	# (Phaser `navigateToRespawnPoint` reloads into it).
	var run := Services.run()
	var world := Services.world()
	var bed: Dictionary = run.respawn_point() if run != null else {}
	if not bed.is_empty() and world != null and str(bed.get("map_id", "")) != world.map_id():
		var main := get_tree().get_first_node_in_group(&"world_main")
		if main != null and main.has_method(&"respawn_in_world") and bool(main.call(&"respawn_in_world", bed)):
			return
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
	# GameState.revive: energy full; the refill plays EnergyRestore (delta >= 20), as in Phaser.
	_energy = float(_max_energy)
	energy_changed.emit({"energy": _energy, "maxEnergy": _max_energy, "delta": float(_max_energy)})
	_audio_cue(CUE_ENERGY_RESTORE)
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
		# A web hit roots the slime first (PlayerHealthController.ts:130-131).
		var web_ms: float = _applied_potency(result, EFFECT_WEB)
		if web_ms > 0.0:
			apply_web(web_ms)
		var strength: float = _applied_potency(result, EFFECT_KNOCKBACK)
		if strength > 0.0:
			var request: Dictionary = _dict(commit.get("request"))
			var impact: Dictionary = _dict(request.get("impact"))
			var knock_value: Variant = impact.get("knock", Vector2.ZERO)
			var knock: Vector2 = knock_value if knock_value is Vector2 else Vector2.ZERO
			if knock.length_squared() > 0.0:
				apply_knockback(knock.normalized(), strength, KNOCKBACK_DURATION_MS)
	damage_feedback.emit(commit)


## `PickupArea.area_entered` (PlayerScript.ts:52-56, world-objects spec 7.2): the first
## CollectibleScript among the entered area's siblings gets a pickup request from this player's
## PickupArea. Edge-triggered: standing on a pile does not retry.
func on_pickup_area_entered(area: Node) -> void:
	var root := area.get_parent() if area != null else null
	if root == null:
		return
	for child: Node in root.get_children():
		if child is CollectibleScript:
			(child as CollectibleScript).request_pickup(get_pickup_area())
			return


## The body's `PickupArea` (layer 32, monitoring the collectibles' layer 64).
func get_pickup_area() -> Area2D:
	return body.get_node_or_null(^"PickupArea") as Area2D if body != null else null


## `WorldScene.useAbility` (abilities spec 3.2): the jump goes where the movement keys point (in
## place without keys); the lash, slam and teleport toward the pointer aim or the facing; the
## teleport as far as the pointer (from the aim origin), at most its range.
func use_ability(id: StringName) -> bool:
	if body == null:
		return false
	var aim := _pointer_aim_with_distance()
	var toward: Vector2 = aim["direction"] if aim["direction"] != Vector2.ZERO else _facing
	var request := {"position": get_centre(), "direction": toward, "facing": _facing}
	# A rooted (webbed) slime cannot jump, dodge or teleport; the press is spent silently.
	if _status.is_rooted() and id in [AbilityDefinitions.JUMP, AbilityDefinitions.DODGE, AbilityDefinitions.TELEPORT]:
		return false
	match id:
		AbilityDefinitions.JUMP:
			request["direction"] = _input.movement_vector()
			return _abilities.try_begin(id, request)
		AbilityDefinitions.DODGE:
			return _try_dodge()
		AbilityDefinitions.TELEPORT:
			if aim["direction"] != Vector2.ZERO:
				request["reach"] = aim["distance"]
			return _abilities.try_begin(id, request)
		AbilityDefinitions.STRETCH_LASH, AbilityDefinitions.SQUASH_SLAM:
			return _abilities.try_begin(id, request)
	return false


## The ability bar's click (`activateAbilityFromUi`): refused while dead or rolling/knocked back.
func activate_ability_from_ui(id: StringName) -> bool:
	if _dead or is_movement_suppressed() or get_tree().paused:
		return false
	return use_ability(id)


## The ability bar's model of `id` (PlayerAbilityController.status, camelCase keys).
func ability_status(id: StringName) -> Dictionary:
	return _abilities.status(id)


func is_ability_busy() -> bool:
	return _abilities.is_busy()


func is_learned(id: StringName) -> bool:
	return _abilities.is_learned(id)


func get_abilities() -> PlayerAbilities:
	return _abilities


func get_energy() -> float:
	return _energy


func get_max_energy() -> float:
	return float(_max_energy)


## GameState.useEnergy: false (and nothing taken) when there is too little.
func spend_energy(amount: float) -> bool:
	if _energy < amount:
		return false
	_energy -= amount
	energy_changed.emit({"energy": _energy, "maxEnergy": _max_energy, "delta": -amount})
	return true


## Test and dev aid: sets energy (clamped) and reports it.
func set_energy(value: float) -> void:
	var before := _energy
	_energy = clampf(value, 0.0, float(_max_energy))
	energy_changed.emit({"energy": _energy, "maxEnergy": _max_energy, "delta": _energy - before})


## The Phaser `player.action` audio cue of an ability step (Jump, Land, SlamImpact, ...).
func action_cue(cue: StringName) -> void:
	_audio_cue(cue)


## A squash preset; `force` plays it even while an ability runs (the landing).
func squash(preset: StringName, force: bool = false) -> void:
	_squash.play(preset, force)


## The ability effects channel on the art (offset in world px, scale and alpha multiplied).
func set_effect_offset(offset: Vector2) -> void:
	_effect_offset = offset
	_place_art()


func set_effect_scale(factor: Vector2) -> void:
	if visual != null:
		visual.scale = _visual_base_scale * factor


func set_effect_alpha(alpha: float) -> void:
	if visual != null:
		visual.modulate.a = alpha


func reset_effects() -> void:
	_effect_offset = Vector2.ZERO
	_place_art()
	if visual != null:
		visual.scale = _visual_base_scale
		visual.modulate.a = 1.0


## A tween on the art (it pauses with the tree, like Phaser's scene tweens); null without art.
func effect_tween() -> Tween:
	return visual.create_tween() if visual != null and visual.is_inside_tree() else null


## A jump landed at `centre`: `jump_landed`, and the Heavy landing record cracked ground reads.
func record_landing(centre: Vector2) -> void:
	_landing_id += 1
	var heavy := presses_plates()
	if heavy:
		_heavy_landing = {"x": centre.x, "y": centre.y, "id": _landing_id}
	jump_landed.emit({"x": centre.x, "y": centre.y, "heavy": heavy, "id": _landing_id})


## {} or {"x", "y", "id"} of the last jump landing made in a Heavy form.
func last_heavy_landing() -> Dictionary:
	return _heavy_landing


## The current form presses plates and cracks ground (Heavy). Set by the Gulp forms.
func presses_plates() -> bool:
	return bool(_gulp.form.get("presses_plates", false))


## The current form walks through spider webs (Sticky).
func crosses_webs() -> bool:
	return bool(_gulp.form.get("crosses_webs", false))


func is_sticky_form() -> bool:
	return current_form_id() == GulpForms.STICKY


## {} or the form row (game/player/gulp/gulp_forms.gd).
func current_form() -> Dictionary:
	return _gulp.form


## &"" when none, else &"heavy" / &"sticky".
func current_form_id() -> StringName:
	return _gulp.form.get("id", &"")


func form_remaining_ms() -> float:
	return _gulp.remaining_ms()


func get_gulp() -> GulpController:
	return _gulp


## The nearest Gulp spot in reach, or null.
func nearest_gulp_spot() -> Node:
	return _gulp.nearest_spot()


## A tap of Q (or a right click on a spot): eat, and the eat clip when something happened.
func eat() -> String:
	var result := _gulp.eat()
	if result != "nothing":
		play_action_clip("eat")
	return result


## A Goo Heart (WorldScene.collectGooHeart): max HP grows for the run and HP fills.
func grant_goo_heart() -> void:
	var run := Services.run()
	if run != null:
		run.add_goo_heart()
		_max_hp = run.max_hp()
	_hp = _max_hp
	health_changed.emit({"hp": _hp, "maxHp": _max_hp})


## Rooted by a spider web (the `sticky` status).
func is_rooted() -> bool:
	return _status.is_rooted()


## `WorldScene.applyWeb`: roots the slime for `duration_ms` (the longer of two webs wins) and, when
## it was not stuck yet, covers it with the web effect, which follows it.
func apply_web(duration_ms: float) -> void:
	var already := _status.is_rooted()
	_status.apply(&"sticky", duration_ms)
	if already or body == null:
		return
	var world := Services.world()
	var cover := world.instantiate_scene(WEB_COVER_SCENE) as Node2D if world != null else null
	if cover == null:
		return
	cover.position = Vector2(0.0, -FeetAnchor.depth_anchor(body).y) if FeetAnchor.depth_anchor(body) != Vector2.ZERO else Vector2(0.0, -27.56)
	cover.z_index = 1
	body.add_child(cover)


## A status effect on the player ("burn", "poison", "slow", "sticky", "bouncy", "frenzy").
func apply_status(kind: StringName, duration_ms: float = -1.0) -> void:
	_status.apply(kind, duration_ms)


func get_status() -> StatusEffects:
	return _status


## Damage over time from a status (GameState.damage): HP down, death at 0.
func _status_damage(amount: float, _kind: StringName) -> void:
	if _dead or amount <= 0.0:
		return
	_hp = maxi(0, _hp - roundi(amount))
	health_changed.emit({"hp": _hp, "maxHp": _max_hp})
	if _hp <= 0:
		_die()


## The Gulp controller's form change (WorldScene.ts:1093-1100): the tint, the gulp squash and
## the floating text.
func on_gulp_form_changed(form: Dictionary, reason: String) -> void:
	if visual != null:
		visual.self_modulate = form.get("tint", Color.WHITE)
	if reason == "started" or reason == "refreshed":
		_squash.play(&"gulp")
	var text := ""
	var color := &"white"
	match reason:
		"started":
			text = "%s!" % str(form["name"]).to_upper()
			color = &"cyan"
		"refreshed":
			text = "%s refreshed" % str(form["name"])
			color = &"cyan"
		"burp":
			text = "Burp!"
		"expired":
			text = "The form wore off"
	if not text.is_empty():
		_floating_text(get_centre() - Vector2(0.0, GULP_TEXT_RISE_PX), text, color, true)


## Physics RIDs of the player's own bodies (excluded from ability queries).
func body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if body != null:
		rids.append(body.get_rid())
	return rids


func get_slam_area() -> Area2D:
	return _slam_area


## `WorldScene.playActionAnimation` (WorldScene.ts:1855-1877), e.g. the purple berry's `eat`:
## skipped while dead or while knockback has priority; otherwise action lock, stop, play the clip,
## and after its length (simulation time) unlock and go back to idle.
func play_action_clip(clip: String) -> void:
	if _dead or Services.now_ms() < _knockback_anim_until_ms or animation == null:
		return
	if not animation.has_animation(_directional_clip(clip)):
		return
	set_action_locked(true)
	stop_movement()
	# `player.action {anim}`: the eat clip's Eat cue (AudioEventBridge).
	if clip == "eat":
		_audio_cue(CUE_EAT)
	play_animation(clip, true)
	var length_ms := 0.0
	if animation.has_method(&"clip_length_ms"):
		length_ms = float(animation.call(&"clip_length_ms", StringName(_directional_clip(clip))))
	else:
		length_ms = animation.get_animation(_directional_clip(clip)).length * 1000.0
	_action_clip_until_ms = Services.now_ms() + length_ms


# --- private steps -------------------------------------------------------------------------------

## Player spec 5.1 / 9: consume buffered presses in Phaser's order (dodge, then attack); the first
## consumed press wins and ends the step. Returns true when an action was consumed.
func _handle_action_input() -> bool:
	var now: float = Services.now_ms()
	# Interact comes first (WorldScene.handleActionInput, interaction spec 2.7) and ends the step
	# even without a target.
	if _input.consume(&"interact", now, _buffer_ms):
		var interaction := _interaction_controller()
		if interaction != null and bool(interaction.call(&"has_candidate")):
			interaction.call(&"handle_interact")
		return true
	# Abilities in Phaser's dispatch order: jump, dodge, stretch-lash, squash-slam, teleport.
	for id: StringName in AbilityDefinitions.DISPATCH_ORDER:
		if _input.consume(AbilityDefinitions.action(id), now, _buffer_ms):
			use_ability(id)
			return true
	if _input.consume(&"attack", now, _buffer_ms):
		_attack()
		return true
	if _input.consume(&"eat", now, _buffer_ms):
		_eat_since_ms = now
		_eat_last_seen_ms = now
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
	# A Gulp form scales the capped speed (PlayerController.ts:69-70): Heavy 0.6, Sticky 0.9.
	var speed: float = _resolve_movement_speed(base, 0.0, _status.speed_multiplier()) * float(_gulp.form.get("speed", 1.0))
	if direction == Vector2.ZERO:
		body.velocity = Vector2.ZERO
		_play_direct(CLIP_IDLE)
		return
	# Rooted (a web): no walking, the slime idles (PlayerController.ts:72-77).
	if _status.is_rooted():
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
	# The shared ability rules (busy silent, locked, cooldown silent, action-locked, energy); the
	# cooldown (roll duration + post-roll cooldown) runs from now.
	if not _abilities.try_instant(AbilityDefinitions.DODGE):
		return false
	_dodge_cooldown_until_ms = _abilities.cooldown_until(AbilityDefinitions.DODGE)
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


## Sleeping in a bed: `request` from `BedScript.sleep_request()`. Refused (false) while dead,
## action-locked or already asleep (WorldScene.requestSleep; the pause and travel checks are the
## interaction controller's).
func sleep_in(request: Dictionary) -> bool:
	if _dead or _action_locked or _sleep.is_sleeping():
		return false
	return _sleep.sleep(request)


func is_sleeping() -> bool:
	return _sleep.is_sleeping()


## The sleep controller (tests read its phase).
func get_sleep() -> SleepController:
	return _sleep


## Quiet healing (rest): adds up to `amount` HP; 0 when dead or full. Emits `health_changed`.
func heal(amount: int) -> int:
	if _dead or amount <= 0 or _hp >= _max_hp:
		return 0
	var healed := mini(amount, _max_hp - _hp)
	_hp += healed
	health_changed.emit({"hp": _hp, "maxHp": _max_hp})
	return healed


## Puts the player's old Phaser centre at `centre` and stops it.
func teleport(centre: Vector2) -> void:
	if body == null:
		return
	body.velocity = Vector2.ZERO
	FeetAnchor.place_at_phaser_position(body, centre)
	body.reset_physics_interpolation()


## Draws the art `offset` world px away from the body without moving it (sleeping on a mattress).
func set_art_offset(offset: Vector2) -> void:
	_art_offset = offset
	_place_art()


func _place_art() -> void:
	if visual == null:
		return
	if not _art_rest_position_known:
		_art_rest_position = visual.position
		_art_rest_position_known = true
	visual.position = _art_rest_position + _art_offset + _effect_offset


## A clip's length in ms (its directional version when the scene has one); 0 when missing.
func clip_length_ms_of(clip: String) -> float:
	var resolved := _directional_clip(clip)
	if animation == null or not animation.has_animation(resolved):
		return 0.0
	return animation.get_animation(resolved).length * 1000.0


## Player spec 6.6 (`WorldScene.onPlayerDeath`); idempotent. Runs synchronously inside the
## commit, before the `damaged` / `defeated` signals and the hit presentation.
## Phaser's `resetActiveFights` has no call here: enemies disengage through
## `primary_target().active` (enemy spec).
func _die() -> void:
	if _dead:
		return
	_sleep.wake("death")
	_gulp.clear()
	_status.clear()
	_close_eat_hold()
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
	_sleep.wake("damage")
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


## Where a defeated slime wakes: the last bed slept in when it is in this world (its wake point,
## `RunState.respawn_point`), else the spawn marker's open tile. A bed in another world is not
## travelled to yet (Phaser reloads into the bed's world).
func _respawn_point() -> Vector2:
	var world := Services.world()
	if world == null:
		return get_centre()
	var run := Services.run()
	var bed: Dictionary = run.respawn_point() if run != null else {}
	if not bed.is_empty() and str(bed.get("map_id", "")) == world.map_id():
		var at := Vector2(float(bed.get("x", 0.0)), float(bed.get("y", 0.0)))
		if at.is_finite():
			return at
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
	_energy_regen = _number("character.player.stats.energyRegenPerSecond")
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


## The eat press (WorldScene.updateEatHold; abilities spec 11.4). A release before 250 ms is a tap
## (`eat()`: a spot's form, a burp, or a message). Held 250 ms, the quick wheel opens with the
## carried Gulp materials ("No Gulp materials carried" when none, and the release then does
## nothing); while it is open the slime stands still, a movement direction (else the pointer, once
## it moved 10 px) picks a slot, and the release eats that material from the bag. Returns true
## while the wheel is open.
func _update_eat_hold() -> bool:
	if _eat_since_ms < 0.0:
		return false
	var now: float = Services.now_ms()
	if now - _eat_last_seen_ms > EAT_HOLD_DROP_MS:
		_close_eat_hold()
		return false
	_eat_last_seen_ms = now
	if not _input.is_held(&"eat"):
		var was_open := _eat_wheel_open
		var empty := _eat_wheel_empty
		var item_id := ""
		if was_open and _gulp_wheel != null and _gulp_wheel.selected >= 0 and _gulp_wheel.selected < _gulp_wheel.entries.size():
			item_id = str(_gulp_wheel.entries[_gulp_wheel.selected]["item_id"])
		_close_eat_hold()
		if was_open:
			if not item_id.is_empty() and _gulp.eat_material(item_id) != "nothing":
				play_action_clip("eat")
		elif not empty:
			eat()
		return false
	if not _eat_wheel_open and not _eat_wheel_empty and now - _eat_since_ms >= GulpWheel.HOLD_MS:
		var entries := _gulp.wheel_entries()
		if entries.is_empty():
			_eat_wheel_empty = true
			var feel := Services.feel()
			if feel != null:
				feel.floating_text(get_centre() - Vector2(0.0, GULP_MESSAGE_RISE), "No Gulp materials carried", &"white", false)
		else:
			_eat_wheel_open = true
			_eat_wheel_pointer_start = body.get_global_mouse_position() if body != null and body.is_inside_tree() else Vector2.ZERO
			var chosen := 0
			var preferred := _gulp.preferred_material()
			for index in entries.size():
				if str(entries[index]["item_id"]) == preferred:
					chosen = index
			_ensure_gulp_wheel()
			_gulp_wheel.open(entries, chosen)
	if not _eat_wheel_open or _gulp_wheel == null:
		return false
	var pick := GulpWheel.pick_slot(_input.movement_vector(), _gulp_wheel.entries.size())
	if pick < 0 and body != null and body.is_inside_tree():
		var pointer := body.get_global_mouse_position()
		if pointer.distance_to(_eat_wheel_pointer_start) > GULP_WHEEL_POINTER_SLACK:
			pick = GulpWheel.pick_slot(pointer - (get_centre() - Vector2(0.0, GULP_WHEEL_POINTER_RISE)), _gulp_wheel.entries.size())
	_gulp_wheel.follow(get_centre(), pick if pick >= 0 else _gulp_wheel.selected)
	return true


## The Gulp quick wheel (null until the first long hold).
func get_gulp_wheel() -> GulpWheel:
	return _gulp_wheel


## Ends the eat hold and hides the quick wheel.
func _close_eat_hold() -> void:
	_eat_since_ms = -1.0
	_eat_wheel_open = false
	_eat_wheel_empty = false
	if _gulp_wheel != null:
		_gulp_wheel.close()


## The quick wheel lives beside the Gulp HUD under the body (drawn top-level over everything).
func _ensure_gulp_wheel() -> void:
	if _gulp_wheel != null or body == null:
		return
	_gulp_wheel = GulpWheel.new()
	_gulp_wheel.name = "GulpWheel"
	body.add_child(_gulp_wheel)


## The Goo Trail passive (game/player/goo_trail.gd) in the world, where its smears stay.
func _make_goo_trail() -> void:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null or not is_inside_tree():
		return
	var trail := GooTrail.new()
	trail.name = "GooTrail"
	trail.player = self
	parent.add_child(trail)


func _make_gulp_hud() -> void:
	if body == null or _gulp_hud != null:
		return
	_gulp_hud = GulpHud.new()
	_gulp_hud.name = "GulpHud"
	_gulp_hud.player = self
	body.add_child.call_deferred(_gulp_hud)


## Energy regen (WorldScene.ts:833-837): `energyRegenPerSecond` per second of simulation, capped.
func _regen_energy(delta_ms: float) -> void:
	if _energy >= float(_max_energy) or delta_ms <= 0.0:
		return
	var before := _energy
	_energy = minf(float(_max_energy), _energy + _energy_regen * delta_ms / 1000.0)
	energy_changed.emit({"energy": _energy, "maxEnergy": _max_energy, "delta": _energy - before})


## The pointer aim as {"direction": unit or ZERO, "distance": from the aim origin}.
func _pointer_aim_with_distance() -> Dictionary:
	var direction := _pointer_aim()
	if direction == Vector2.ZERO or body == null or not body.is_inside_tree():
		return {"direction": Vector2.ZERO, "distance": 0.0}
	var origin: Vector2 = get_centre() - Vector2(0.0, aim_rise_px)
	return {"direction": direction, "distance": origin.distance_to(body.get_global_mouse_position())}


func _make_slam_area() -> void:
	if body == null or _slam_area != null:
		return
	_slam_area = Area2D.new()
	_slam_area.name = "SlamArea"
	_slam_area.collision_layer = 0
	_slam_area.collision_mask = 0
	_slam_area.monitoring = false
	_slam_area.monitorable = false
	_slam_area.position = Vector2(0.0, -27.56)
	body.add_child.call_deferred(_slam_area)


## Sleep's wake input (SleepController `consumeWakeInput`): drains every action press and reports
## whether one was pressed or a direction is held.
func _wake_input() -> bool:
	var now: float = Services.now_ms()
	var pressed := false
	for action: StringName in WAKE_ACTIONS:
		if _input.consume(action, now, INF):
			pressed = true
	return pressed or _input.movement_vector() != Vector2.ZERO


func _interaction_controller() -> Node:
	if _interaction == null or not is_instance_valid(_interaction):
		_interaction = get_tree().get_first_node_in_group(INTERACTION_GROUP)
	return _interaction


func _audio_cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _real_now_ms() -> float:
	return float(Time.get_ticks_msec())

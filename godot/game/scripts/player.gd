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
## Body-shapes rework (docs/godot/BODY_SHAPES.md), only while ReworkMode is on (with it off every
## path below runs as before): attacks and the shape switch go to the ShapeController main.gd hands
## over (`set_shapes`), Q to the MouthHold (`get_mouth_hold`), `ability_use` to the Ability Box; the
## number-key Swallow is ignored; a running ability may make the slime untouchable or deaf to
## knockback (PlayerAbilities `is_invulnerable`, `ignores_knockback`); while a shape's charge ring
## fills the slime stands and walks in the shape's held pose (`_locomotion_clip`). See
## `_handle_rework_action_input` and `_rework_owns_step`.
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
## The Visual's material: Gulp form skins + the hit flash (owner decision 2026-10-05).
const FORM_SKIN_SHADER := preload("res://game/player/gulp/form_skin.gdshader")
const PlayerCombat := preload("res://game/combat/player_combat.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")
const SleepController := preload("res://game/rest/sleep_controller.gd")
const PlayerAbilities := preload("res://game/player/abilities/player_abilities.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const GulpController := preload("res://game/player/gulp/gulp_controller.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const GulpHud := preload("res://game/player/gulp/gulp_hud.gd")
const PlayerSwimming := preload("res://game/player/gulp/player_swimming.gd")
const Mouth := preload("res://game/player/gulp/mouth.gd")
const PlayerRoll := preload("res://game/player/roll/player_roll.gd")
const StatusEffects := preload("res://game/player/status_effects.gd")
const GooTrail := preload("res://game/player/goo_trail.gd")
## Steps, wading and swimming sounds (game/audio/footsteps.gd).
const FootstepsScene := preload("res://game/scenes/audio/footsteps.tscn")
const WheelStepper := preload("res://game/player/wheel_stepper.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
## The mouse control schemes (click to move, right-click to move): game/player/mouse/.
const ControlScheme := preload("res://game/player/mouse/control_scheme.gd")
const ClickOrders := preload("res://game/player/mouse/click_orders.gd")
const PointerTargets := preload("res://game/player/mouse/pointer_targets.gd")
const ClickMarker := preload("res://game/player/mouse/click_marker.gd")
## The body-shapes rework (docs/godot/BODY_SHAPES.md): the mode, the shape controller, the mouth's Q
## state machine and the Ability Box.
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const ShapeController := preload("res://game/shapes/shape_controller.gd")
const MouthHold := preload("res://game/player/gulp/mouth_hold.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const HeavyGrab := preload("res://game/player/heavy_grab.gd")
## The walk out of a door with a side on arrival (input locked; docs/godot/CONVENTIONS.md "Doors").
const DoorWalkOut := preload("res://game/player/door_walk_out.gd")

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
## What the slime holds changed (the Gulp mouth). Payload: {} or {"kind":
## <liftable kind>|"essence", "essence": "stone"|"silk"|"swim"|"", "variant"}.
signal held_changed(payload: Dictionary)

var _input: PlayerInputBuffer = PlayerInputBuffer.new()
## Mouse-wheel notches -> single weapon steps (crafting spec 8.5).
var _wheel: WheelStepper = WheelStepper.new()
## The bag / belt glue (game/inventory/inventory_actions.gd, group "inventory_actions").
var _inventory_actions: Node
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
## Pushing against a rim (docs/godot/ELEVATION.md): since when, last seen, which way. A push that
## stops for longer than LEDGE_PUSH_GAP_MS starts over.
var _ledge_push_since_ms: float = -1.0
var _ledge_push_seen_ms: float = -1.0
var _ledge_push_dir: Vector2 = Vector2.ZERO
const LEDGE_PUSH_GAP_MS := 120.0
## The art's offsets in world px: sleeping on a mattress, and the ability effects channel
## (Phaser `visual.effects`: offset, scale and alpha on top of the authored values).
var _art_offset: Vector2 = Vector2.ZERO
var _effect_offset: Vector2 = Vector2.ZERO
## How far the art sinks while swimming (player_swimming.gd).
var _swim_offset: Vector2 = Vector2.ZERO
var _visual_base_scale: Vector2 = Vector2.ONE
## Energy (GameState): spent by abilities, refilled 8 per second.
var _energy: float = 0.0
var _energy_regen: float = 0.0
## The last Heavy impact (a Squash Slam, or a jump landing, made in a plate-pressing form): {} or
## {"x", "y", "id"}. Cracked ground reads it.
var _heavy_impact: Dictionary = {}
var _impact_id: int = 0
## Squash Slam's attack area for the router (no shape needed: the strike queries physics).
var _slam_area: Area2D
## The Gulp form and the mouth that sucks, holds and throws (game/player/gulp/).
var _gulp: GulpController = GulpController.new(self)
var _mouth: Mouth = Mouth.new(self)
## The Roll on key 2 (the `dodge` ability, roadmap 7.7).
var _roll: PlayerRoll = PlayerRoll.new(self)
## The hit being committed popped the form: its feedback skips the knockback and the web.
var _hit_popped: bool = false
## Swimming in deep water with a Gulp form that swims (the Frog).
var _swim: PlayerSwimming = PlayerSwimming.new(self)
var _gulp_hud: GulpHud
## Status effects (game/player/status_effects.gd): sticky roots the slime, slow scales walking.
var _status: StatusEffects = StatusEffects.new(_status_damage)
## The world's interaction controller (group "interaction"), looked up on the first press.
var _interaction: Node
## Furniture placement (game/building/furniture_placement.gd, group "furniture_placement").
var _furniture: Node
## The interact press on a target with a hold action (a placed bench): its start (sim ms), -1 = none.
var _interact_hold_since_ms: float = -1.0
## The walk out of a door (`walk_out_of_door`).
var _walk_out: DoorWalkOut = DoorWalkOut.new()
## Simulation-time deadlines (ms).
var _movement_suppressed_until_ms: float = 0.0
var _knockback_anim_until_ms: float = 0.0
var _iframe_until_ms: float = 0.0
## Real-time deadlines (Time.get_ticks_msec()).
var _flash_until_real_ms: float = 0.0
var _respawn_at_real_ms: float = -1.0
## Move-start squash bookkeeping.
var _was_moving: bool = false
var _still_since_ms: float = 0.0
var _pointer_seen: bool = false
## The mouse control schemes (game/player/mouse/control_scheme.gd): the click order, whether its
## button is down, a press waiting for the next physics step (seeing what was clicked needs
## physics; simulation ms, < 0 when none), the same for the click scheme's use button (and whether
## the order came from it), the ground marks, the cursor shape shown.
var _orders: ClickOrders = ClickOrders.new()
var _order_button_down: bool = false
var _order_press_ms: float = -1.0
var _use_button_down: bool = false
var _use_press_ms: float = -1.0
var _order_from_use: bool = false
var _click_marker: ClickMarker
var _cursor_shape: Input.CursorShape = Input.CURSOR_ARROW
var _pick_radius_px: float = 0.0
var _melee_fallback_px: float = 0.0
var _ledge_push_extra_ms: float = 0.0
## Rework mode only: the shape controller main.gd hands over (`set_shapes`; null otherwise) and the
## mouth's Q state machine (made on first use, `get_mouth_hold`).
var _shapes: ShapeController
var _mouth_hold: MouthHold
## Rework: the grab on a heavy block (game/player/heavy_grab.gd), and the walk keys of this step it reads.
var _grab := HeavyGrab.new()
var _grab_direction: Vector2 = Vector2.ZERO
## The way the slime was told to walk on its last free step (keys, a click order's steering), ZERO
## when it did not walk under control (frozen, swinging, walking out of a door). Doors read it: a
## push into one goes through (game/scripts/door.gd).
var _move_intent: Vector2 = Vector2.ZERO
## Rework mode only: a Roll press waiting for its key's release or the hold (`_due_roll`; simulation
## ms, < 0: none), and when that key was seen let go (< 0: still held, or not seen yet).
enum RollPress { NONE, QUICK, CHARGED }
var _roll_press_ms: float = -1.0
var _roll_release_ms: float = -1.0

## Clip names (player spec 1.1). Every clip resolves to its directional version when the scene
## has one (`_directional_clip`).
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
## Swimming replaces idle and walk (page 3 of the slime sheet).
const CLIP_SWIM := "swim"
## The Gulp (page 4 and 5 of the slime sheet): sucking, the spit of a throw, and the full slime's
## idle sway and walking waddle while it holds something.
const CLIP_SUCK := "suck"
const CLIP_SPIT := "spit"
const CLIP_FULL_IDLE := "full-idle"
const CLIP_FULL_WALK := "full"
const CLIP_KNOCKBACK := "knockback"
const CLIP_DIE := "die"
## The AnimationPlayer library of the body shapes' strike animations (rework mode), and the suffix of a
## strike's hold, its first frame held while a charge ring fills (ShapeStrikes.ANIMATION_LIBRARY, HOLD_SUFFIX).
const STRIKE_LIBRARY := "strikes"
const STRIKE_HOLD_SUFFIX := "-hold"
## Presses that wake a sleeper (SleepController consumeWakeInput).
const WAKE_ACTIONS: Array[StringName] = [&"interact", &"attack", &"jump", &"dodge", &"stretch_lash",
	&"squash_slam", &"teleport", &"eat", &"swallow"]
const INTERACTION_GROUP := &"interaction"
const INVENTORY_ACTIONS_GROUP := &"inventory_actions"
const FURNITURE_GROUP := &"furniture_placement"
## INTERACT_HOLD_MS (WorldScene.ts:151): holding interact this long runs the target's hold action.
const INTERACT_HOLD_MS := 450.0
## Presses placement mode throws away (WorldScene.ts:1773-1786).
const PLACEMENT_DROPPED_ACTIONS: Array[StringName] = [&"jump", &"dodge", &"stretch_lash", &"squash_slam", &"teleport", &"eat", &"swallow"]
## InitialRun.ts:15 new-run coins (coins are OUT; the HUD snapshot shows the new-run value).
const NEW_RUN_COINS := 50
## Global audio cues (AudioEventBridge.ts:31-42).
const CUE_ABILITY_DENIED := &"AbilityDenied"
const CUE_RESPAWN := &"Respawn"
const CUE_ENERGY_RESTORE := &"EnergyRestore"
const CUE_EAT := &"Eat"
const CUE_GULP_BURP := &"GulpBurp"
const CUE_WEB_STRUGGLE := &"WebStruggle"
const EFFECT_WEB := "web"
const WEB_COVER_SCENE := "effect.spider-web-cover"
## Gulp form texts (WorldScene.ts:1093-1100): centre - 56.
const GULP_TEXT_RISE_PX := 56.0
## Gulp messages over the slime (GulpController `showMessage`: centre - 56).
const GULP_MESSAGE_RISE := 56.0
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
var _hit_iframes_ms: float = 0.0
var _defense: float = 0.0
var _max_energy: int = 0
var _buffer_ms: float = 0.0
## `character.player.rework.*`, read only while the body-shapes rework mode is on: the energy
## regen (0: energy is scarce, shards bring it back), the Roll's tap length and the quick roll's
## energy. (The walk's scale while a shape charges is the ShapeController's `walk_scale`.)
var _rework_energy_regen: float = 0.0
var _rework_roll_tap_ms: float = 0.0
var _rework_quick_roll_energy: float = 0.0
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
		var skin_material := ShaderMaterial.new()
		skin_material.shader = FORM_SKIN_SHADER
		skin_material.set_meta(&"hit_flash", true)
		visual.material = skin_material
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
	_make_footsteps()
	_orders.configure(_number)
	_orders.path.bind(body)
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
	_set_cursor(Input.CURSOR_ARROW)


## Window focus lost: no release events arrive for keys held at that moment, so forget them
## (otherwise the slime keeps walking after alt-tab or a click outside the web canvas).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_input()


## Player spec 7.2: feeds PlayerInputBuffer with the SimClock time; tracks
## `InputEventMouseMotion` to set `_pointer_seen`; marks captured events handled. F2 switches the
## control scheme; a mouse scheme's buttons go to `_capture_order_buttons` first.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_seen = true
		return
	if event is InputEventMouseButton:
		_pointer_seen = true
	if event.is_action_pressed(&"control_scheme_next"):
		_cycle_control_scheme()
		get_viewport().set_input_as_handled()
		return
	if _capture_order_buttons(event):
		get_viewport().set_input_as_handled()
		return
	if _capture_wheel(event):
		get_viewport().set_input_as_handled()
		return
	if _input.capture(event, Services.now_ms()):
		get_viewport().set_input_as_handled()


## An order scheme's buttons (game/player/mouse/control_scheme.gd), mouse events only (an
## `attack` / `interact` InputEventAction keeps its keyboard-scheme job). The order button's press
## and the click scheme's use button's wait for the next physics step (`_issue_click_order`); a
## release lets the order that button gave go. Shift + the order button in the click scheme, and
## the moba scheme's swing button, is an `attack` press (a swing in place toward the pointer).
## Placing furniture keeps the keyboard scheme's buttons. True when the event was one of these
## buttons.
func _capture_order_buttons(event: InputEvent) -> bool:
	var mouse := event as InputEventMouseButton
	if mouse == null:
		return false
	var scheme := ControlScheme.current()
	if not ControlScheme.uses_orders(scheme):
		return false
	var furniture := _furniture_placement()
	if furniture != null and bool(furniture.call(&"is_active")):
		return false
	var now := Services.now_ms()
	if mouse.button_index == ControlScheme.order_button(scheme):
		if not mouse.pressed:
			_order_button_down = false
			if not _order_from_use:
				_orders.release()
		elif mouse.shift_pressed and scheme == ControlScheme.CLICK:
			_input.mark_pressed(&"attack", now)
		else:
			_order_button_down = true
			_order_press_ms = now
		return true
	if mouse.button_index == ControlScheme.use_button(scheme):
		if not mouse.pressed:
			_use_button_down = false
			if _order_from_use:
				_orders.release()
		else:
			_use_button_down = true
			_use_press_ms = now
		return true
	if mouse.button_index == ControlScheme.swing_button(scheme):
		if mouse.pressed:
			_input.mark_pressed(&"attack", now)
		return true
	return false


## F2 (`control_scheme_next`): the next control scheme, saved with the settings and named over
## the slime.
func _cycle_control_scheme() -> void:
	var scheme := ControlScheme.next(ControlScheme.current())
	ControlScheme.store(scheme)
	clear_input()
	if body != null and body.is_inside_tree():
		_floating_text(get_centre() - Vector2(0.0, GULP_MESSAGE_RISE), "Controls: %s" % ControlScheme.display_name(scheme), &"white", false)


## The mouse wheel switches weapons (crafting spec 8.5): `weapon_next` (wheel down) and
## `weapon_previous` (wheel up), as mouse buttons or InputEventActions (tests). Each scroll adds a
## notch (× the event's factor) to the WheelStepper; a completed step is a buffered press at the
## simulation time, consumed by `_handle_action_input`. True when the event was a wheel action.
func _capture_wheel(event: InputEvent) -> bool:
	var action := &""
	if event.is_action(&"weapon_next"):
		action = &"weapon_next"
	elif event.is_action(&"weapon_previous"):
		action = &"weapon_previous"
	else:
		return false
	if not event.is_pressed():
		return true
	var delta_px := WheelStepper.NOTCH_PX
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.factor > 0.0:
		delta_px *= mouse.factor
	if _wheel.step(action, delta_px, _real_now_ms()):
		_input.mark_pressed(action, Services.now_ms())
	return true


## Returns while the tree is paused. Otherwise runs the per-step state machine of player spec
## 4.1 in this order: dead -> stop; read direction; movement suppressed (roll/knockback) -> keep
## velocity; action locked (weapon swing) -> velocity 0; handle_action_input() consumed ->
## keep last velocity this step; else move-start squash + move(direction) (player spec 4.3,
## 4.5). Then `ArcadeMover.move(body, delta)`.
## The mouse schemes slot in: a pending order press becomes an order first; a movement key cancels
## it; after the buffered actions the order may swing at or use its target (`_run_click_order`);
## without movement keys it steers the walk (`_steer_click_order`). In the pointer scheme the slime
## turns to the pointer first (`_face_pointer`) and only W walks (`_movement_input`).
func _physics_process(delta: float) -> void:
	if get_tree().paused or body == null:
		return
	_move_intent = Vector2.ZERO
	# Rework: a window that closed this frame drops its stray Roll press before any press is used;
	# an armed Roll press notes when its key was let go (`_due_roll` drops a stale release).
	if ReworkMode.is_on():
		_update_modal_pause()
		if _grab.is_active() and (_dead or is_movement_suppressed()):
			_grab.release()
		if _roll_press_ms >= 0.0 and _roll_release_ms < 0.0 and not _input.is_held(&"dodge"):
			_roll_release_ms = Services.now_ms()
	if _action_clip_until_ms >= 0.0 and Services.now_ms() >= _action_clip_until_ms:
		_action_clip_until_ms = -1.0
		set_action_locked(false)
		if not _dead:
			_play_idle()
	_abilities.advance(Services.now_ms())
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes) and not _dead:
		_shapes.update(Services.now_ms(), delta)
	if not _dead:
		if ReworkMode.is_on():
			get_mouth_hold().step(Services.now_ms(), _input.is_held(&"eat"))
		else:
			_mouth.update(Services.now_ms(), _input.is_held(&"eat"), _gulp_aim())
	_swim.update()
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
	elif _walk_out.active:
		# Walking out of a door: no input is read or consumed (presses stay buffered).
		_step_walk_out(delta)
	else:
		var scheme := ControlScheme.current()
		if ControlScheme.faces_pointer(scheme):
			_face_pointer()
		var direction: Vector2 = _movement_input(scheme)
		_grab_direction = direction
		_issue_click_order()
		if direction != Vector2.ZERO:
			_orders.cancel() # The movement keys take over from a click order.
		if _roll.is_active():
			_roll.update(Services.now_ms(), delta, _input.is_held(&"dodge"))
		if is_movement_suppressed():
			pass # Roll / knockback own the body: their velocity persists, presses stay buffered.
		elif ReworkMode.is_on() and _rework_owns_step():
			pass # Rework: the mouth's hold or a shape step owns the slime this step.
		elif _action_locked:
			body.velocity = Vector2.ZERO
		elif _mouth.is_sucking():
			body.velocity = Vector2.ZERO # The slime stands still while it sucks.
			_play_direct(CLIP_SUCK)
		elif _handle_action_input():
			pass # An action was used this step: velocity keeps the last step's value once.
		elif _run_click_order():
			pass # The click order swung at or used its target this step.
		else:
			if direction == Vector2.ZERO:
				direction = _steer_click_order()
			_move_intent = direction
			_squash_on_move_start(direction)
			_move(direction)
	if _dead:
		_orders.cancel()
		if _walk_out.active:
			_walk_out.finish()
	_update_pointer_hover()
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
	# A respawn in another world takes the slime out of the tree.
	if not is_inside_tree():
		return
	# Menus and windows: the plain cursor over them (physics, which picks it, is paused). Hit-stop
	# keeps it, so it does not flicker on every hit.
	var world := Services.world()
	var hit_stop_only := world != null and world.has_pause_reason(Services.WorldServiceType.PAUSE_HIT_STOP) \
		and not world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL)
	if get_tree().paused and not hit_stop_only and _cursor_shape != Input.CURSOR_ARROW:
		_set_cursor(Input.CURSOR_ARROW)


# --- queries used by other systems -------------------------------------------------------------

## Old Phaser body position (sprite centre) = feet - (0, 27.56). Enemies, camera and texts use it.
func get_centre() -> Vector2:
	if body == null:
		return Vector2.ZERO
	return FeetAnchor.phaser_position(body)


## Unit facing vector (initial (0,1)); 8-way from movement, cardinal after attack/dodge.
func get_facing() -> Vector2:
	return _facing


## True while a click order walks the slime (the move hint learns from it).
func is_click_moving() -> bool:
	return _orders.is_active() and _orders.direction != Vector2.ZERO


## The mouse schemes' current order (game/player/mouse/click_orders.gd).
func get_click_orders() -> ClickOrders:
	return _orders


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


## Rework mode: called once by main.gd after it made and set up the ShapeController.
func set_shapes(shapes: ShapeController) -> void:
	_shapes = shapes


## The ShapeController set by main.gd (null outside the rework mode).
func get_shapes() -> ShapeController:
	return _shapes


## Rework mode: the mouth's Q state machine (game/player/gulp/mouth_hold.gd), made on first use.
func get_mouth_hold() -> MouthHold:
	if _mouth_hold == null:
		_mouth_hold = MouthHold.new()
		_mouth_hold.setup(self, _mouth, _gulp)
	return _mouth_hold


## Where the mouth sucks and throws: the pointer's aim in the mouse schemes, else the facing.
func get_gulp_aim() -> Vector2:
	return _gulp_aim()


## Rework mode: the pointer's aim from the slime's centre, where the shapes strike from (their
## areas, the Spear's wall ray and their drawing all start at `get_centre()`), with the pointer aim's
## dead zone; ZERO without one (pointer never seen, in the dead zone, or the keys-only scheme). The
## old aim (`_pointer_aim`) rises `aim_rise_px` first, a Phaser parity quirk the 4-way weapons hide.
func get_strike_aim() -> Vector2:
	if body == null or not body.is_inside_tree() or not ControlScheme.uses_mouse(ControlScheme.current()):
		return Vector2.ZERO
	return PointerAim.aim(get_centre(), body.get_global_mouse_position(), _pointer_seen)


## Weapon swing lock (CombatController onAttackStarted/Finished): while locked the state machine
## zeroes velocity every step and consumes no input (presses stay buffered).
func set_action_locked(locked: bool) -> void:
	_action_locked = locked


func is_action_locked() -> bool:
	return _action_locked


## `sim < movement_suppressed_until` (PlayerScript.ts:135-137), or a Roll on (its spin-up too).
func is_movement_suppressed() -> bool:
	return Services.now_ms() < _movement_suppressed_until_ms or _roll.is_active()


## Freezes walking and buffered actions for `ms` of simulation time (the area travel's leave fade).
func suppress_movement(ms: float) -> void:
	_movement_suppressed_until_ms = maxf(_movement_suppressed_until_ms, Services.now_ms() + ms)


## Arriving at a door with a side (main.gd `_start_arrival`): from the doorway, where the feet
## stand now, the slime walks `direction` (into the room) at `worldNavigation.doorWalkOutSpeedShare`
## of its walking speed, the walk clip playing and the input locked, until it is clear of the
## doorway's wall or building plus `doorWalkOutMarginPx` (game/player/door_walk_out.gd). It waits
## while the movement is suppressed (the iris's black hold). False when it cannot walk.
func walk_out_of_door(direction: Vector2) -> bool:
	if body == null or _dead or direction == Vector2.ZERO:
		return false
	clear_input()
	face(direction)
	return _walk_out.start(body, direction, _number("worldNavigation.doorWalkOutMarginPx"),
		_number("worldNavigation.doorWalkOutMaxPx"), _number("worldNavigation.doorWalkOutProbeWidthPx"))


## The way the slime was told to walk on its last free step (see `_move_intent`); doors read it.
func get_move_intent() -> Vector2:
	return _move_intent


## True while the slime walks out of a door (its input is locked).
func is_walking_out() -> bool:
	return _walk_out.active


## One step of the walk out of a door: wait while suppressed, else walk until the walker says stop
## or the next step would run into something.
func _step_walk_out(delta: float) -> void:
	if is_movement_suppressed():
		body.velocity = Vector2.ZERO
		return
	var direction := _walk_out.next_direction()
	if direction != Vector2.ZERO:
		_move(direction)
		if not _walk_out.blocked_ahead(body.velocity * delta):
			return
	_walk_out.finish()
	body.velocity = Vector2.ZERO
	_play_direct(_locomotion_clip(CLIP_IDLE))


## What RunState keeps of the player when it leaves a world: {"hp", "energy", "facing", "x", "y",
## "gulp_form", "held"}, x/y the old Phaser (centre) position, facing "up"|"down"|"left"|"right".
func run_snapshot() -> Dictionary:
	var centre: Vector2 = get_centre()
	return {"hp": _hp, "energy": _energy, "facing": Directions.cardinal_name(_facing), "x": centre.x, "y": centre.y,
		"gulp_form": String(current_form_id()), "held": _mouth.held.duplicate()}


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
	# The Gulp form and what the mouth holds go through doors and saves (owner, 2026-10-08).
	_gulp.restore(str(state.get("gulp_form", "")))
	var held_state: Variant = state.get("held", {})
	if held_state is Dictionary:
		_mouth.restore(held_state)


## The Roll's i-frames (`rollInvulnerabilityMs` from its launch).
func is_dodging() -> bool:
	return _roll.is_invulnerable(Services.now_ms())


## A Roll is on: the spin-up, the launch and rolling on, including the vulnerable part after the
## i-frames.
func is_rolling() -> bool:
	return _roll.is_active()


## The Roll (game/player/roll/player_roll.gd).
func get_roll() -> PlayerRoll:
	return _roll


## Sets `body.velocity = Vector2.ZERO`, and ends a Roll (a door's leave fade, a window, death). In
## the rework mode it also ends the shape chain.
func stop_movement() -> void:
	_roll.cancel()
	_drop_roll_press()
	if body != null:
		body.velocity = Vector2.ZERO
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes):
		_shapes.reset_chain("stopped")


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


## Rework mode: the strike animation `strikes/<animation_name>` of the AnimationPlayer's `strikes`
## library (BODY_SHAPES.md "Editing the strike animations"); null when the scene lacks it.
func strike_animation(animation_name: String) -> Animation:
	var full := "%s/%s" % [STRIKE_LIBRARY, animation_name]
	if animation == null or not animation.has_animation(full):
		return null
	return animation.get_animation(full)


## Rework mode: shows the strike animation `strikes/<animation_name>` at `seconds` (the shape
## controller maps the step's gameplay time onto it every physics step, ShapePoses): assigned and held
## paused the first time (from the Visual's rest offset, its flip by the facing as `_flip_for` reads
## a `-side` name), then sought with an immediate update, so the body frame and the StrikeRig's
## weapon follow the gameplay clock (a hit-stop freezes them). The same gate as `play_animation`.
## False when refused or missing.
func seek_strike_animation(animation_name: String, seconds: float) -> bool:
	var full := "%s/%s" % [STRIKE_LIBRARY, animation_name]
	if animation == null or not animation.has_animation(full) or _dead:
		return false
	if Services.now_ms() < _knockback_anim_until_ms:
		return false
	if String(animation.assigned_animation) != full or animation.is_playing():
		if visual != null:
			visual.flip_h = _flip_for(full)
			visual.offset = _visual_rest_offset
			visual.skew = _visual_rest_skew
		animation.play(full)
		animation.pause()
	animation.seek(seconds, true)
	return true


## Rework mode: the StrikeRig under the Visual (game/shapes/strike_rig.gd; null without one).
func get_strike_rig() -> Node2D:
	return visual.get_node_or_null(^"StrikeRig") as Node2D if visual != null else null


## Player spec 6.4: knockback_anim_until and movement_suppressed_until = max(old, sim +
## duration_ms); `body.velocity = direction.normalized() * strength` (constant, no decay);
## force-play "knockback". Ignored for a zero direction or strength <= 0.
func apply_knockback(direction: Vector2, strength: float, duration_ms: float) -> void:
	if direction == Vector2.ZERO or strength <= 0.0 or duration_ms < 0.0:
		return
	# Rework: an ability that shrugs knockback off (the improved Slam).
	if ReworkMode.is_on() and _abilities.ignores_knockback():
		return
	# The Heavy form shrugs knockback off entirely (WorldScene.ts:341-350).
	if bool(_gulp.form.get("knockback_immune", false)):
		return
	if ReworkMode.is_on() and _mouth_hold != null:
		_mouth_hold.cancel("knockback")
	_roll.cancel()
	_drop_roll_press()
	var now: float = Services.now_ms()
	_knockback_anim_until_ms = maxf(_knockback_anim_until_ms, now + duration_ms)
	_movement_suppressed_until_ms = maxf(_movement_suppressed_until_ms, now + duration_ms)
	if body != null:
		body.velocity = direction.normalized() * strength
	play_animation(CLIP_KNOCKBACK, true)


## Rework mode: the slime's own recoil (a clink, an armor bounce, a reaction's recoil; the shape
## controller): `apply_knockback`'s movement (`direction` x `strength` for `duration_ms`, walking and
## buffered actions held that long) and its shrug-offs (the improved Slam, the Heavy form), and it
## ends a Roll, but without the hurt clip or its priority window, so it never reads as being hit and
## the strike's clip plays on.
func recoil(direction: Vector2, strength: float, duration_ms: float) -> void:
	if direction == Vector2.ZERO or strength <= 0.0 or duration_ms < 0.0:
		return
	if ReworkMode.is_on() and _abilities.ignores_knockback():
		return
	if bool(_gulp.form.get("knockback_immune", false)):
		return
	_roll.cancel()
	_movement_suppressed_until_ms = maxf(_movement_suppressed_until_ms, Services.now_ms() + duration_ms)
	if body != null:
		body.velocity = direction.normalized() * strength


## Empties held keys and pending presses (pause / scene exit), and the wheel's partial notch.
func clear_input() -> void:
	_input.clear()
	_wheel.reset()
	_interact_hold_since_ms = -1.0
	# And ends a click order (a window it opened, alt-tab, a scheme switch).
	_orders.cancel()
	_order_button_down = false
	_order_press_ms = -1.0
	_use_button_down = false
	_use_press_ms = -1.0
	_order_from_use = false
	_drop_roll_press()
	# Rework: a burst or a hold ring ends with the input (focus loss, a window, a door), and an Attack
	# press not let go yet is forgotten (its cleared key must not read as a release that taps).
	if ReworkMode.is_on() and _mouth_hold != null:
		_mouth_hold.cancel("input-cleared")
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes):
		_shapes.drop_press()


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
	# Rework: an ability that makes the slime untouchable (the improved Slam in the air).
	if ReworkMode.is_on() and _abilities.is_invulnerable():
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
	_hit_popped = false
	if actual > 0 and not _dead:
		_hp = maxi(0, _hp - actual)
		if _hp <= 0:
			_die()
		else:
			# A hit pops the Gulp form out (it takes the hit's knockback and web) and makes the slime
			# drop what it holds (owner, 2026-10-08).
			_hit_popped = _gulp.pop()
			_mouth.drop()
			# Rework: a hit ends the mouth's burst or ring and the shape chain.
			if ReworkMode.is_on():
				get_mouth_hold().cancel("hit")
				if _shapes != null and is_instance_valid(_shapes):
					_shapes.reset_chain("hurt")
				# A hit cancels the Goo Bomb's cast (no energy spent; PlayerAbilities.on_hurt).
				_abilities.on_hurt()
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
## applied "knockback" potency along `request.impact.knock` for KNOCKBACK_DURATION_MS. A hit that
## popped the Gulp form has neither knockback nor web (the pop took them).
## Order follows PlayerScript.publishDamageFeedback: health feedback first, then the signal.
func publish_damage_feedback(commit: Dictionary) -> void:
	var result: Dictionary = _dict(commit.get("result"))
	var actual: int = int(result.get("actual_damage", 0))
	if actual > 0:
		_present_hit(actual)
	var popped := _hit_popped
	_hit_popped = false
	if not bool(result.get("defeated", false)) and not popped:
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
			# Without movement keys, a click order's walk is the way the jump goes; the order
			# re-plans from the landing.
			var keys := _movement_input(ControlScheme.current())
			request["direction"] = keys if keys != Vector2.ZERO else _orders.direction
			_orders.invalidate()
			return _abilities.try_begin(id, request)
		AbilityDefinitions.DODGE:
			return _try_dodge()
		AbilityDefinitions.TELEPORT:
			if aim["direction"] != Vector2.ZERO:
				request["reach"] = aim["distance"]
			return _abilities.try_begin(id, request)
		AbilityDefinitions.STRETCH_LASH, AbilityDefinitions.SQUASH_SLAM:
			return _abilities.try_begin(id, request)
		AbilityDefinitions.GOO_BOMBS:
			return _abilities.try_begin(id, request)
		AbilityDefinitions.LANTERN:
			return _abilities.try_begin(id, request)
		AbilityDefinitions.SWALLOW:
			return _swallow()
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


## GameState.regenEnergy (a Fizzy Brew, a Berry Basket): adds up to `amount`, capped at the
## maximum; reports the gain on `energy_changed` (when there is one) and returns it.
func restore_energy(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := _energy
	_energy = minf(float(_max_energy), _energy + amount)
	var gained := _energy - before
	if gained > 0.0:
		energy_changed.emit({"energy": _energy, "maxEnergy": _max_energy, "delta": gained})
	return gained


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


## In the air (a jump or a ledge drop): plates do not feel the slime.
func is_airborne() -> bool:
	return _abilities.is_airborne()


## A jump landed at `centre`: `jump_landed`; in a Heavy form it is also a Heavy impact. (The jump
## is hidden since 2026-10-08: nothing teaches it and no key runs it; ledge drops do not land here.)
func record_landing(centre: Vector2) -> void:
	_impact_id += 1
	var heavy := presses_plates()
	if heavy:
		_heavy_impact = {"x": centre.x, "y": centre.y, "id": _impact_id}
	jump_landed.emit({"x": centre.x, "y": centre.y, "heavy": heavy, "id": _impact_id})


## A Squash Slam struck at `centre` (slam_sequence.gd); in a Heavy form it is a Heavy impact.
func record_slam(centre: Vector2) -> void:
	_impact_id += 1
	if presses_plates():
		_heavy_impact = {"x": centre.x, "y": centre.y, "id": _impact_id}


## {} or {"x", "y", "id"} of the last Heavy impact: a Squash Slam (or a jump landing) made in a
## Heavy form. Cracked ground breaks under one.
func last_heavy_impact() -> Dictionary:
	return _heavy_impact


## The current form presses plates and cracks ground (Heavy). Set by the Gulp forms.
func presses_plates() -> bool:
	return bool(_gulp.form.get("presses_plates", false))


## The current form walks through spider webs (Sticky).
func crosses_webs() -> bool:
	return bool(_gulp.form.get("crosses_webs", false))


func is_sticky_form() -> bool:
	return current_form_id() == GulpForms.STICKY


## True while the slime swims (a form that swims, its feet in deep water).
func is_swimming() -> bool:
	return _swim.swimming


## True when any part of the body is over deep water (a swimming form does not end there).
func overlaps_deep_water() -> bool:
	return _swim.overlaps_deep_water()


## Sinks the art by `offset` while swimming (player_swimming.gd).
func set_swim_offset(offset: Vector2) -> void:
	_swim_offset = offset
	_place_art()


## {} or the form row (game/player/gulp/gulp_forms.gd).
func current_form() -> Dictionary:
	return _gulp.form


## &"" when none, else &"heavy" (Stone) / &"sticky" (Silk) / &"frog" (Swim).
func current_form_id() -> StringName:
	return _gulp.form.get("id", &"")


## Forms have no timer since 2026-10-08: always 0.
func form_remaining_ms() -> float:
	return _gulp.remaining_ms()


func get_gulp() -> GulpController:
	return _gulp


func get_mouth() -> Mouth:
	return _mouth


## {} or what the mouth holds: {"kind": <liftable kind>|"essence", "essence", "variant"}.
func held() -> Dictionary:
	return _mouth.held


## The thing a suck would take now (the HUD's "[Q] Suck" hint), or null.
func nearest_suckable() -> Node:
	if _dead or _mouth.is_holding():
		return null
	return _mouth.find_target(_gulp_aim())


## The bag's "Use" on an essence: into the mouth. False when the mouth is busy.
func take_into_mouth(item_id: String) -> bool:
	if _dead:
		return false
	return _mouth.take_item(item_id)


## The mouth's change: `held_changed`. The full slime's clips (`_locomotion_clip`) take over on the
## next step.
func on_held_changed(state: Dictionary) -> void:
	held_changed.emit(state.duplicate())


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


## The Gulp controller's form change (WorldScene.ts:1093-1100): the skin (or tint), the gulp
## squash, the cue and the floating text. Reasons: started, switched (an essence swallowed), popped
## (a hit), spat (Swallow with nothing held), cleared (death), restored (a door or a load: the skin
## only).
func on_gulp_form_changed(form: Dictionary, reason: String) -> void:
	if visual != null:
		# The form's skin is painted by the Visual's shader; the tint is the fallback without it.
		var skin_material := visual.material as ShaderMaterial
		if skin_material != null and skin_material.shader == FORM_SKIN_SHADER:
			skin_material.set_shader_parameter(&"skin", int(form.get("skin", 0)))
			visual.self_modulate = Color.WHITE
		else:
			visual.self_modulate = form.get("tint", Color.WHITE)
	if reason == "started" or reason == "switched":
		_squash.play(&"gulp")
		var transform_cue := StringName(form.get("transform_cue", &""))
		if not transform_cue.is_empty():
			_audio_cue(transform_cue)
	elif reason == "popped" or reason == "spat":
		_audio_cue(CUE_GULP_BURP)
	var text := ""
	var color := &"white"
	match reason:
		"started", "switched":
			text = "%s!" % str(form["name"]).to_upper()
			color = &"cyan"
		"popped":
			text = "Pop!"
		"spat":
			text = "Ptoo!"
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
	# Placing furniture comes first (furniture spec 5): left click places, the wheel switches the
	# variant, right click cancels, other actions are dropped; the step goes on (the slime walks).
	var furniture := _furniture_placement()
	if furniture != null and bool(furniture.call(&"is_active")):
		if _input.consume(&"attack", now, _buffer_ms):
			furniture.call(&"press_place")
		if _input.consume(&"weapon_next", now, _buffer_ms):
			furniture.call(&"cycle_variant", 1)
		if _input.consume(&"weapon_previous", now, _buffer_ms):
			furniture.call(&"cycle_variant", -1)
		if _input.consume(&"interact", now, _buffer_ms):
			furniture.call(&"cancel")
		for action in PLACEMENT_DROPPED_ACTIONS:
			_input.consume(action, now, _buffer_ms)
		if ReworkMode.is_on():
			_input.consume(&"ability_use", now, _buffer_ms)
		return false
	# Rework: the shapes, the box ability and the mouth's Q (the furniture rules above stay).
	if ReworkMode.is_on():
		return _handle_rework_action_input(now, false)
	# The wheel's weapon steps come next and do not end the step (WorldScene.ts:1788-1793): the
	# slime keeps walking and an attack can follow in the same step.
	for step: Array in [[&"weapon_next", 1], [&"weapon_previous", -1]]:
		if _input.consume(step[0], now, _buffer_ms):
			_switch_weapon(int(step[1]))
	if _update_interact_hold(now):
		return true
	# Interact comes first (WorldScene.handleActionInput, interaction spec 2.7) and ends the step
	# even without a target. A target with a hold action (a placed bench: "Hold: Pick up") waits
	# for the release (its main action) or 450 ms held (the hold action).
	if _input.consume(&"interact", now, _buffer_ms):
		_orders.cancel()
		var interaction := _interaction_controller()
		if interaction != null and bool(interaction.call(&"has_candidate")):
			if bool(interaction.call(&"has_secondary")):
				_interact_hold_since_ms = now
			else:
				interaction.call(&"handle_interact")
		return true
	# Swallow (the Gulp, owner 2026-10-08): what the mouth holds becomes the form.
	if _input.consume(&"swallow", now, _buffer_ms):
		_orders.cancel()
		use_ability(AbilityDefinitions.SWALLOW)
		return true
	# A swimming slime, or one holding something in its mouth, neither attacks nor uses abilities:
	# those presses are dropped (Q still throws).
	if _swim.swimming or _mouth.is_holding():
		for id: StringName in AbilityDefinitions.DISPATCH_ORDER:
			_input.consume(AbilityDefinitions.action(id), now, _buffer_ms)
		_input.consume(&"attack", now, _buffer_ms)
	# Abilities in Phaser's dispatch order: jump, dodge, stretch-lash, squash-slam, teleport. Each
	# but the jump ends a click order (the slime jumps along its walk and walks on).
	for id: StringName in AbilityDefinitions.DISPATCH_ORDER:
		if _input.consume(AbilityDefinitions.action(id), now, _buffer_ms):
			if id != AbilityDefinitions.JUMP:
				_orders.cancel()
			use_ability(id)
			return true
	if _input.consume(&"attack", now, _buffer_ms):
		_orders.cancel()
		_attack()
		return true
	# Q, the mouth: a press throws what the slime holds, else starts a suck that lasts while Q is
	# held (game/player/gulp/mouth.gd).
	if _input.consume(&"eat", now, _buffer_ms):
		_orders.cancel()
		if _mouth.is_holding():
			var aim := _gulp_aim()
			face(aim)
			if _mouth.throw(aim):
				play_action_clip(CLIP_SPIT)
		else:
			_mouth.begin_suck()
		return true
	return false


## The rework mode's `_handle_action_input` (docs/godot/BODY_SHAPES.md "Controls in the rework
## mode"; body-shapes plan section 6): E and the wheel switch shapes (ShapeController.cycle; the
## slime keeps walking and an attack can follow in the same step); interact as before (not while
## `busy`, a shape step owning the slime); Swallow is ignored (it is a Q hold) and the old ability
## keys (jump, lash, slam, teleport) are dropped; then the Roll, the chosen box ability
## (`ability_use`, AbilityBox.use), the attack (the shape) and Q (the MouthHold), each ending the
## step. The Roll fires on its key's release, or on a hold with the `roll-charge` upgrade
## (`_due_roll`; its press only arms it); the attack press goes to the controller, which strikes on
## the release or charges while held (it reads the hold every physics step in `update`). The Roll,
## a box ability that starts, and Q end the shape chain. A swimming slime, or one holding something
## in its mouth, drops its Roll, ability and attack presses, as before (Q still throws). Returns true
## when an action was consumed.
func _handle_rework_action_input(now: float, busy: bool) -> bool:
	var shapes := _shapes if _shapes != null and is_instance_valid(_shapes) else null
	for step: Array in [[&"weapon_next", 1], [&"weapon_previous", -1]]:
		if _input.consume(step[0], now, _buffer_ms) and shapes != null:
			shapes.cycle(int(step[1]))
	if not busy:
		if _update_interact_hold(now):
			return true
		if _input.consume(&"interact", now, _buffer_ms):
			_orders.cancel()
			# A heavy block the slime faces and touches takes the press first (a held interact grabs).
			if not _mouth.is_holding() and _grab.try_begin(self, body, _facing):
				return true
			var interaction := _interaction_controller()
			if interaction != null and bool(interaction.call(&"has_candidate")):
				if bool(interaction.call(&"has_secondary")):
					_interact_hold_since_ms = now
				else:
					interaction.call(&"handle_interact")
			return true
	_input.consume(&"swallow", now, _buffer_ms)
	for id: StringName in AbilityDefinitions.DISPATCH_ORDER:
		if id != AbilityDefinitions.DODGE:
			_input.consume(AbilityDefinitions.action(id), now, _buffer_ms)
	if _swim.swimming or _mouth.is_holding():
		for action: StringName in [&"dodge", &"ability_use", &"attack"]:
			_input.consume(action, now, _buffer_ms)
		_drop_roll_press()
	# The Roll fires on the release (`_due_roll`): a press only arms it, and the slime walks on.
	if _input.consume(&"dodge", now, _buffer_ms):
		_roll_press_ms = now
		_roll_release_ms = -1.0
	var roll := _due_roll(now)
	if roll != RollPress.NONE:
		_orders.cancel()
		if _rework_roll(roll == RollPress.CHARGED) and shapes != null:
			shapes.reset_chain("roll")
		return true
	if _input.consume(&"ability_use", now, _buffer_ms):
		_orders.cancel()
		if AbilityBox.use(self) and shapes != null:
			shapes.reset_chain("ability")
		return true
	if _input.consume(&"attack", now, _buffer_ms):
		_orders.cancel()
		# A step that starts owns the body from this physics step on (not one step later).
		if _attack() and shapes != null and shapes.is_busy():
			body.velocity = shapes.step_velocity()
		return true
	if _input.consume(&"eat", now, _buffer_ms):
		_orders.cancel()
		if shapes != null:
			shapes.reset_chain("mouth")
		get_mouth_hold().press()
		return true
	return false


## Rework mode: true when the mouth's hold or a shape step owns this physics step (the slime does
## not walk). While the MouthHold roots the slime (a suck burst or a hold ring) it stands, its attack,
## ability and Roll presses are dropped and Q presses still reach the mouth; while the
## ShapeController `is_busy()` the step's velocity drives the body (`step_velocity`) and presses
## still reach the controller (a press during a step waits for its cancel point). False otherwise,
## and under an action lock (the old branch handles that).
func _rework_owns_step() -> bool:
	if _action_locked:
		return false
	var now := Services.now_ms()
	if _grab.is_active():
		return _step_grab(now)
	var hold := get_mouth_hold()
	if hold.roots_player():
		body.velocity = Vector2.ZERO
		for action: StringName in [&"attack", &"dodge", &"ability_use"]:
			_input.consume(action, now, _buffer_ms)
		_drop_roll_press()
		if _input.consume(&"eat", now, _buffer_ms):
			hold.press()
		_play_direct(CLIP_SUCK if _mouth.is_sucking() else _locomotion_clip(CLIP_IDLE))
		return true
	if _shapes != null and is_instance_valid(_shapes) and _shapes.is_busy():
		body.velocity = _shapes.step_velocity()
		_handle_rework_action_input(now, true)
		return true
	return false


## Rework: the grab on a heavy block owns the step (game/player/heavy_grab.gd): the other presses
## are dropped, the walk keys push or pull, and the slime walks or idles facing the block.
func _step_grab(now: float) -> bool:
	for action: StringName in [&"attack", &"dodge", &"ability_use", &"eat", &"interact", &"weapon_next", &"weapon_previous"]:
		_input.consume(action, now, _buffer_ms)
	_drop_roll_press()
	var walking := _grab.step(now, get_physics_process_delta_time(), _input.is_held(&"interact"), _grab_direction)
	if not _grab.is_active():
		_play_direct(_locomotion_clip(CLIP_IDLE))
		return true
	_play_direct(_locomotion_clip(CLIP_WALK if walking else CLIP_IDLE))
	return true


## Rework: the heavy block the slime grabs, or null.
func get_grabbed_block() -> Node2D:
	return _grab.block()


## Rework mode (owner, 2026-10-12): which Roll an armed press (`_roll_press_ms`) asks for now. Its
## key let go: the quick roll (QUICK), unless the release is older than `input.bufferMs` (the slime
## was busy meanwhile: dropped, like a stale press). Still held past
## `character.player.rework.rollTapMs` with the `roll-charge` upgrade learned: the charged roll
## (CHARGED, the spin-up while held); without the upgrade a hold waits for the release. NONE while
## nothing is due. A due press is used up.
func _due_roll(now: float) -> RollPress:
	if _roll_press_ms < 0.0:
		return RollPress.NONE
	if _input.is_held(&"dodge"):
		if now - _roll_press_ms < _rework_roll_tap_ms or not _abilities.is_learned(PlayerRoll.CHARGE_UPGRADE_ID):
			return RollPress.NONE
		_drop_roll_press()
		return RollPress.CHARGED
	var stale := _roll_release_ms >= 0.0 and now - _roll_release_ms > _buffer_ms
	_drop_roll_press()
	return RollPress.NONE if stale else RollPress.QUICK


## Rework mode: the Roll `_due_roll` asked for, on the dodge's rules (a web roots it, as in
## `use_ability`; `_try_dodge`): the charged roll, else the quick roll. True when it started.
func _rework_roll(charged: bool) -> bool:
	if body == null or _status.is_rooted():
		return false
	return _try_dodge(charged)


## Forgets an armed Roll press (a knockback, a door or window, death, input cleared, the mouth's
## root, swimming or a full mouth).
func _drop_roll_press() -> void:
	_roll_press_ms = -1.0
	_roll_release_ms = -1.0


## Player spec 4.3: walk/sprint speed from `character.player.movement` (baseSpeed, boostSpeed,
## movementSpeedCap via resolve_movement_speed), normalized direction, facing/flip, clip choice.
## Boost bonus items, status speed multipliers, roots and Gulp forms are OUT (0 / 1 / none / 1).
func _move(direction: Vector2) -> void:
	if body == null or is_movement_suppressed():
		return
	var sprinting: bool = _input.is_held(&"sprint")
	var base: float = _boost_speed if sprinting else _resolve_movement_speed(_base_speed)
	# A Gulp form scales the capped speed (PlayerController.ts:69-70): Heavy 0.6, Sticky 0.9; a full
	# mouth slows the slime to `gulp.holdingSpeedMultiplier` (owner, 2026-10-09: 70%).
	var speed: float = _resolve_movement_speed(base, 0.0, _status.speed_multiplier()) * float(_gulp.form.get("speed", 1.0))
	if _mouth.is_holding():
		speed *= _number("gulp.holdingSpeedMultiplier")
	# Rework: while the shape's charge ring fills or waits for the release the slime walks at
	# ShapeController.walk_scale() (`combat.chain.chargeWalkScale`; owner, 2026-10-12: half speed).
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes):
		speed *= _shapes.walk_scale()
	if _walk_out.active:
		speed *= _number("worldNavigation.doorWalkOutSpeedShare")
	if direction == Vector2.ZERO:
		body.velocity = Vector2.ZERO
		_play_direct(_locomotion_clip(CLIP_IDLE))
		return
	# Rooted (a web): no walking, the slime idles (PlayerController.ts:72-77); pushing struggles
	# (the cue's own minimum interval spaces the sound out).
	if _status.is_rooted():
		body.velocity = Vector2.ZERO
		_play_direct(_locomotion_clip(CLIP_IDLE))
		_audio_cue(CUE_WEB_STRUGGLE)
		return
	var unit: Vector2 = direction.normalized()
	body.velocity = unit * speed
	_facing = unit
	_play_direct(_locomotion_clip(CLIP_WALK))
	_press_ledge(unit)


## A rim holds the slime, as in Zelda, until it insists: pushing against one for
## `elevation.dropPushMs` drops it over, whatever the rim's shape (`Elevation.ledge_below`, then
## `drop_target`: down a south face, behind a back rim, down beside a side rim; jump_sequence.gd
## flies it there).
func _press_ledge(unit: Vector2) -> void:
	var world := Services.world()
	var elevation: Elevation = world.elevation if world != null else null
	if elevation == null or body == null or _abilities.is_busy():
		_ledge_push_since_ms = -1.0
		return
	var level := elevation.level_of(body)
	if elevation.ledge_below(body.global_position, level, unit) == Elevation.NO_LEDGE:
		_ledge_push_since_ms = -1.0
		return
	var now := Services.now_ms()
	if _ledge_push_since_ms < 0.0 or now - _ledge_push_seen_ms > LEDGE_PUSH_GAP_MS or unit.dot(_ledge_push_dir) < 0.95:
		_ledge_push_since_ms = now
		_ledge_push_dir = unit
	_ledge_push_seen_ms = now
	if now - _ledge_push_since_ms < Elevation.setting("dropPushMs"):
		return
	_ledge_push_since_ms = -1.0
	var target := elevation.drop_target(body.global_position, level, unit)
	if target.is_empty():
		return
	var to_centre := get_centre() - body.global_position
	_abilities.begin_drop(get_centre(), (target["feet"] as Vector2) + to_centre, level, int(target["level"]))


## Idle for the current facing; `force` restarts it (respawn).
func _play_idle(force: bool = false) -> void:
	play_animation(_locomotion_clip(CLIP_IDLE), force)


## Idle or walk, the swim clip while swimming, the full slime's sway and waddle while the mouth
## holds something, or (rework mode) the shape's held pose while its charge ring fills or waits full
## (ShapeController.held_pose_clip: its charge's strike hold, or the Axe's `load` pose, a base clip
## played in the facing's version).
func _locomotion_clip(clip: String) -> String:
	if _swim.swimming:
		return CLIP_SWIM
	if _mouth.is_holding():
		return CLIP_FULL_WALK if clip == CLIP_WALK else CLIP_FULL_IDLE
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes):
		var held := _shapes.held_pose_clip()
		if not held.is_empty():
			return held
	return clip


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
## its default facing. A body shape's strike hold `strikes/<strike>-<direction>-hold` (the charge
## ring's held frame, StrikeLibrary) flips as its `strikes/<strike>-<direction>` does.
func _flip_for(clip: String) -> bool:
	clip = clip.trim_suffix(STRIKE_HOLD_SUFFIX)
	if clip.ends_with("-side"):
		return _facing.x < 0.0
	if clip.ends_with("-left"):
		return true
	if clip.ends_with("-down") or clip.ends_with("-up") or clip == CLIP_IDLE:
		return false
	return Directions.slime_flip_h(_facing)


## The Roll (roadmap 7.7, game/player/roll/player_roll.gd) on the dodge's rules: learned, not
## busy, its cooldown (`AbilityDefinitions.cooldown_ms`) and the last roll's own pause after it.
## It rolls toward the pointer aim, else the held movement keys, else the facing. Returns true
## when the spin-up started.
## Rework mode: the quick roll (PlayerRoll.begin_quick; it costs `character.player.rework.
## quickRollEnergy`, "Low energy" when short), or with `charged` the spin-up that launches at the
## key's release (`_due_roll`); the ability bar's click is a quick roll.
func _try_dodge(charged: bool = false) -> bool:
	if not _roll.can_begin(Services.now_ms()) or body == null:
		return false
	var toward: Vector2 = _pointer_aim()
	if toward == Vector2.ZERO:
		toward = _movement_input(ControlScheme.current())
	if toward == Vector2.ZERO:
		toward = _facing
	var quick := ReworkMode.is_on() and not charged
	var cost := _rework_quick_roll_energy if quick else 0.0
	if cost > 0.0 and _energy < cost:
		_abilities.notify_rejected(AbilityDefinitions.DODGE, "energy")
		return false
	# The shared ability rules (busy silent, locked, cooldown silent, action-locked, energy); the
	# cooldown runs from now.
	if not _abilities.try_instant(AbilityDefinitions.DODGE):
		return false
	if quick:
		if cost > 0.0:
			spend_energy(cost)
		return _roll.begin_quick(toward, Services.now_ms())
	return _roll.begin(toward, Services.now_ms(), ReworkMode.is_on())


## Player spec 9.1: face the pointer aim (snapped) when there is one, then `_combat.try_attack()`.
## The facing changes even if the swing is then refused. (`attackAim: facing` is a dev-panel
## setting and OUT: the default `pointer` mode is always used.)
## Rework mode: the press goes to the ShapeController with the strike aim (`get_strike_aim`, from
## the slime's centre; ZERO without one); the controller faces and aims.
func _attack() -> bool:
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes):
		return _shapes.press_attack(get_strike_aim())
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
## Vector2.ZERO when there is no aim (pointer never seen, or within the dead zone), and always in
## the keys-only control scheme (everything aimed then goes where the slime faces).
func _pointer_aim() -> Vector2:
	if body == null or not body.is_inside_tree() or not ControlScheme.uses_mouse(ControlScheme.current()):
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
	if ReworkMode.is_on() and _mouth_hold != null:
		_mouth_hold.cancel("sleep")
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
	_orders.cancel()
	_grab.release()
	_walk_out.finish()
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
	visual.position = _art_rest_position + _art_offset + _effect_offset + _swim_offset


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
	_roll.cancel()
	_gulp.clear()
	_mouth.clear()
	if ReworkMode.is_on():
		get_mouth_hold().cancel("death")
		if _shapes != null and is_instance_valid(_shapes):
			_shapes.reset_chain("death")
	_status.clear()
	_orders.cancel()
	_dead = true
	_knockback_anim_until_ms = 0.0
	# The top-down defeat faces the viewer only (die-down): the slime turns to the camera as it falls.
	face(Vector2.DOWN)
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
## Rework mode: when the modal reason ends (a dialogue, the quest offer, the bag closes) a pending
## Roll press is dropped. Space is the Roll there, the slime keeps capturing input while a window is
## open, and the clock stands still, so a Space press the window did not take would still be fresh
## and roll the slime the moment it closes. Held keys stay (a walk key held through the close walks).
func _update_modal_pause() -> void:
	var world := Services.world()
	var modal: bool = world != null and world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL)
	if modal and not _modal_paused:
		clear_input()
		stop_movement()
	elif ReworkMode.is_on() and _modal_paused and not modal:
		_input.drop_press(&"dodge")
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
	_hit_iframes_ms = _number("character.player.hitInvulnerabilityMs")
	_defense = _number("character.player.stats.defense")
	_max_hp = roundi(_number("character.player.stats.maxHp"))
	_max_energy = roundi(_number("character.player.stats.maxEnergy"))
	_energy_regen = _number("character.player.stats.energyRegenPerSecond")
	_rework_energy_regen = _number("character.player.rework.energyRegenPerSecond")
	_rework_roll_tap_ms = _number("character.player.rework.rollTapMs")
	_rework_quick_roll_energy = _number("character.player.rework.quickRollEnergy")
	_buffer_ms = _number("input.bufferMs")
	_pick_radius_px = _number("input.mouse.pickRadiusPx")
	_melee_fallback_px = _number("input.mouse.meleeFallbackPx")
	_ledge_push_extra_ms = _number("input.mouse.ledgePushExtraMs")


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


## Where the mouth sucks and throws: the pointer's aim in the mouse schemes, else the facing.
func _gulp_aim() -> Vector2:
	var aim := _pointer_aim()
	return aim if aim != Vector2.ZERO else _facing


## The Swallow ability (the shared rules: learned, not busy; no cost). Holding an essence, the slime
## swallows it and takes its form (the old form pops out); holding a liftable, it cannot;
## holding nothing, its form drops out whole.
func _swallow() -> bool:
	if not _abilities.try_instant(AbilityDefinitions.SWALLOW):
		return false
	var holding := _mouth.held
	if not holding.is_empty():
		if str(holding.get("kind", "")) != "essence":
			_floating_text(get_centre() - Vector2(0.0, GULP_MESSAGE_RISE), "Too big to swallow", &"white", false)
			return false
		var form := GulpForms.for_essence(str(holding.get("essence", "")))
		if _gulp.swallow(str(form.get("essence_item", ""))) == "nothing":
			return false
		_mouth.clear_held()
		play_action_clip("eat")
		return true
	if _gulp.spit_out() != "nothing":
		_squash.play(&"gulp")
		return true
	_floating_text(get_centre() - Vector2(0.0, GULP_MESSAGE_RISE), "Nothing to swallow", &"white", false)
	return false


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


func _make_footsteps() -> void:
	var footsteps := FootstepsScene.instantiate()
	footsteps.set(&"player", self)
	add_child(footsteps)


func _make_gulp_hud() -> void:
	if body == null or _gulp_hud != null:
		return
	_gulp_hud = GulpHud.new()
	_gulp_hud.name = "GulpHud"
	_gulp_hud.player = self
	body.add_child.call_deferred(_gulp_hud)


## Energy regen (WorldScene.ts:833-837): `energyRegenPerSecond` per second of simulation, capped.
## Rework mode: `character.player.rework.energyRegenPerSecond` instead (0, owner 2026-10-12: energy
## is scarce; energy shards, items and a respawn bring it back).
func _regen_energy(delta_ms: float) -> void:
	var regen := _rework_energy_regen if ReworkMode.is_on() else _energy_regen
	if regen <= 0.0 or _energy >= float(_max_energy) or delta_ms <= 0.0 or _roll.is_active():
		return
	var before := _energy
	_energy = minf(float(_max_energy), _energy + regen * delta_ms / 1000.0)
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
	if ReworkMode.is_on() and _input.consume(&"ability_use", now, INF):
		pressed = true
	if _order_press_ms >= 0.0 or _use_press_ms >= 0.0:
		_order_press_ms = -1.0
		_use_press_ms = -1.0
		pressed = true
	return pressed or _input.movement_vector() != Vector2.ZERO


func _interaction_controller() -> Node:
	if _interaction == null or not is_instance_valid(_interaction):
		_interaction = get_tree().get_first_node_in_group(INTERACTION_GROUP)
	return _interaction


func _furniture_placement() -> Node:
	if _furniture == null or not is_instance_valid(_furniture):
		_furniture = get_tree().get_first_node_in_group(FURNITURE_GROUP)
	return _furniture


## `updateInteractHold` (WorldScene.ts:1836-1853): true while the hold owns the step.
func _update_interact_hold(now: float) -> bool:
	if _interact_hold_since_ms < 0.0:
		return false
	var interaction := _interaction_controller()
	if interaction == null or not bool(interaction.call(&"has_secondary")):
		_interact_hold_since_ms = -1.0
		return false
	if now - _interact_hold_since_ms >= INTERACT_HOLD_MS:
		_interact_hold_since_ms = -1.0
		interaction.call(&"handle_secondary")
		return true
	if _input.is_held(&"interact") or _order_button_down or _use_button_down:
		return true
	_interact_hold_since_ms = -1.0
	interaction.call(&"handle_interact")
	return true


# --- mouse control schemes (game/player/mouse/) ------------------------------------------------

## A pending order-button press (`_capture_order_buttons`) becomes an order for what is under the
## pointer (PointerTargets.at): an enemy or a resource -> walk into reach and swing; something
## usable -> walk to it and use it (the interaction controller keeps it chosen meanwhile); the
## ground -> walk there. A pending use-button press (the click scheme's right button) becomes the
## use order when something usable is under the pointer, else an `interact` press (the target in
## reach, as in the keyboard scheme; holding the button runs its hold action). A press older than
## `input.bufferMs` is dropped, like any buffered press.
func _issue_click_order() -> void:
	# A release over the HUD never reaches `_unhandled_input`: let go when the button is up.
	var scheme := ControlScheme.current()
	if _order_button_down and _order_press_ms < 0.0 and not Input.is_mouse_button_pressed(ControlScheme.order_button(scheme)):
		_order_button_down = false
		if not _order_from_use:
			_orders.release()
	if _use_button_down and _use_press_ms < 0.0 and not Input.is_mouse_button_pressed(ControlScheme.use_button(scheme)):
		_use_button_down = false
		if _order_from_use:
			_orders.release()
	_issue_use()
	if _order_press_ms < 0.0:
		return
	var pressed_at := _order_press_ms
	_order_press_ms = -1.0
	if Services.now_ms() - pressed_at > _buffer_ms or body == null or not body.is_inside_tree():
		return
	var pointer := body.get_global_mouse_position()
	var target := _pointer_target(pointer)
	var kind := str(target.get("kind", PointerTargets.KIND_GROUND))
	var mark_at := pointer
	match kind:
		PointerTargets.KIND_ATTACK:
			var node: Node = target["node"]
			_orders.attack(node, func() -> Vector2: return PointerTargets.feet_of(node),
				func() -> int: return PointerTargets.level_of(node))
			mark_at = PointerTargets.feet_of(node)
		PointerTargets.KIND_USE:
			_orders.interact(target["key"], target["stand_at"])
			mark_at = target["ring_at"]
		_:
			_orders.move_to(pointer)
	_orders.held = _order_button_down
	_order_from_use = false
	_ping(mark_at, kind)


## The use button's pending press (`_issue_click_order`).
func _issue_use() -> void:
	if _use_press_ms < 0.0:
		return
	var pressed_at := _use_press_ms
	_use_press_ms = -1.0
	if Services.now_ms() - pressed_at > _buffer_ms or body == null or not body.is_inside_tree():
		return
	var target := _pointer_target(body.get_global_mouse_position())
	if str(target.get("kind", "")) != PointerTargets.KIND_USE:
		_input.mark_pressed(&"interact", pressed_at)
		return
	_orders.interact(target["key"], target["stand_at"])
	_orders.held = _use_button_down
	_order_from_use = true
	_ping(target["ring_at"], PointerTargets.KIND_USE)


## The fading ring where an order was given (`kind`: PointerTargets' kinds, for its colour).
func _ping(at: Vector2, kind: String) -> void:
	var marker := _click_marker_node()
	if marker != null:
		marker.ping(at, ClickMarker.color_for(kind))


## The walking direction the keys ask for: the movement keys; in the pointer scheme W (`move_up`)
## alone, toward the pointer (the facing until the pointer has been seen; nothing while the pointer
## is within the aim's dead zone, so the slime stops under it).
func _movement_input(scheme: String) -> Vector2:
	if not ControlScheme.faces_pointer(scheme):
		return _input.movement_vector()
	if not _input.is_held(&"move_up"):
		return Vector2.ZERO
	if not _pointer_seen:
		return _facing
	return _pointer_aim()


## The pointer scheme: the slime turns to the pointer whenever it is free to (not rolling or
## knocked back, swinging or striking with a shape, or busy with an ability, which set their own
## facing).
func _face_pointer() -> void:
	if is_movement_suppressed() or _action_locked or _abilities.is_busy():
		return
	# Rework: a shape strike keeps the facing it set (ShapeController._set_aim), so a side pose stays
	# mirrored like its drawn weapon while the pointer moves.
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes) and _shapes.is_busy():
		return
	var aim := _pointer_aim()
	if aim != Vector2.ZERO:
		face(aim)


## The order's own action once its target is in reach: the swing or the use. True when it owned
## the step (the slime stands).
func _run_click_order() -> bool:
	match _orders.kind:
		ClickOrders.Kind.ATTACK:
			return _click_attack()
		ClickOrders.Kind.INTERACT:
			return _click_interact()
	return false


## The attack order: once a swing toward the target's side would reach its hurtbox
## (PlayerCombat.reaches), or the slime stands within `input.mouse.meleeFallbackPx` of it, face that
## side and swing; while the button is held, swing again as the weapon allows. Ends when the target
## falls, after the swing once the button is up, or when there is no weapon.
## Rework mode: the shape's reach and press instead (`_rework_click_attack`).
func _click_attack() -> bool:
	if ReworkMode.is_on() and _shapes != null and is_instance_valid(_shapes):
		return _rework_click_attack()
	var target := _orders.target
	if not PointerTargets.is_alive(target) or _swim.swimming:
		_orders.cancel()
		return false
	if _orders.swung and not _orders.held:
		_orders.cancel()
		return false
	var at := PointerTargets.hurtbox_centre(target)
	var side := Directions.snap_to_cardinal(at - (get_centre() - Vector2(0.0, aim_rise_px)))
	var combat_ready := _combat != null and is_instance_valid(_combat)
	var area := target.get(&"damage_area") as Area2D
	var in_reach := combat_ready and _combat.reaches(Directions.cardinal_name(side), area)
	if not in_reach and get_centre().distance_to(at) > _melee_fallback_px:
		return false
	face(side)
	body.velocity = Vector2.ZERO
	if not combat_ready or _combat.get_weapon() == null:
		_orders.cancel()
		return true
	if _combat.try_attack():
		_orders.swung = true
	else:
		_play_direct(_locomotion_clip(CLIP_IDLE))
	return true


## Rework mode's attack order: as `_click_attack`, with the current shape's reach
## (ShapeController.reaches along the aim at the target's hurtbox) and its press
## (`press_attack`); ends when the target falls, after the press once the button is up, or when no
## shape is learned.
func _rework_click_attack() -> bool:
	var target := _orders.target
	if not PointerTargets.is_alive(target) or _swim.swimming:
		_orders.cancel()
		return false
	if _orders.swung and not _orders.held:
		_orders.cancel()
		return false
	var at := PointerTargets.hurtbox_centre(target)
	# From the slime's centre, where the shapes strike from (not the old aim's raised origin).
	var toward := at - get_centre()
	var aim := toward.normalized() if toward != Vector2.ZERO else _facing
	var area := target.get(&"damage_area") as Area2D
	if not _shapes.reaches(aim, area) and get_centre().distance_to(at) > _melee_fallback_px:
		return false
	face(aim)
	body.velocity = Vector2.ZERO
	if _shapes.current_shape_id().is_empty():
		_orders.cancel()
		return true
	if _shapes.press_attack(aim):
		_orders.swung = true
	else:
		_play_direct(_locomotion_clip(CLIP_IDLE))
	return true


## The use order: once the interaction controller offers the target (in reach), use it; a target
## with a hold action ("Hold: Pick up") still held runs the hold path (`_update_interact_hold`).
func _click_interact() -> bool:
	var interaction := _interaction_controller()
	if interaction == null:
		_orders.cancel()
		return false
	if not bool(interaction.call(&"is_current", _orders.interact_key)):
		return false
	var held := _orders.held
	_orders.cancel()
	body.velocity = Vector2.ZERO
	_play_direct(_locomotion_clip(CLIP_IDLE))
	if held and bool(interaction.call(&"has_secondary")):
		_interact_hold_since_ms = Services.now_ms()
	else:
		interaction.call(&"handle_interact")
	return true


## This step's walking direction from the click order (ZERO: stand).
func _steer_click_order() -> Vector2:
	if not _orders.is_active() or body == null or not body.is_inside_tree():
		return Vector2.ZERO
	var push_ms := Elevation.setting("dropPushMs") + _ledge_push_extra_ms
	return _orders.steer(body, body.get_global_mouse_position(), Services.now_ms(), push_ms)


## What the pointer is over (PointerTargets.at). Physics step only.
func _pointer_target(pointer: Vector2) -> Dictionary:
	if body == null or not body.is_inside_tree():
		return {"kind": PointerTargets.KIND_GROUND}
	return PointerTargets.at(get_tree(), body.get_world_2d().direct_space_state, pointer, _pick_radius_px, _interaction_controller())


## Each physics step in a mouse scheme: the cursor (a cross over an enemy or a resource, a hand
## over something usable), the ring under that target and under the order's target; the order's
## usable target stays the interaction controller's preferred one. The keyboard scheme shows none.
func _update_pointer_hover() -> void:
	var interaction := _interaction_controller()
	if interaction != null:
		interaction.call(&"set_preferred", _orders.interact_key if _orders.kind == ClickOrders.Kind.INTERACT else null)
	var scheme := ControlScheme.current()
	var hover := {}
	var hovered_control := get_viewport().gui_get_hovered_control()
	var over_gui := hovered_control != null and hovered_control.mouse_filter == Control.MOUSE_FILTER_STOP
	if ControlScheme.uses_orders(scheme) and _pointer_seen and not _dead and not over_gui and body != null and body.is_inside_tree():
		hover = _pointer_target(body.get_global_mouse_position())
	var kind := str(hover.get("kind", PointerTargets.KIND_GROUND))
	match kind:
		PointerTargets.KIND_ATTACK:
			_set_cursor(Input.CURSOR_CROSS)
		PointerTargets.KIND_USE:
			_set_cursor(Input.CURSOR_POINTING_HAND)
		_:
			_set_cursor(Input.CURSOR_ARROW)
	var marker := _click_marker_node() if ControlScheme.uses_orders(scheme) else _click_marker
	if marker == null or not is_instance_valid(marker):
		return
	var hover_at: Variant = null
	if kind == PointerTargets.KIND_ATTACK:
		hover_at = PointerTargets.feet_of(hover["node"])
	elif kind == PointerTargets.KIND_USE:
		hover_at = hover["ring_at"]
	marker.show_hover(hover_at, ClickMarker.color_for(kind))
	var target_at: Variant = null
	if _orders.kind == ClickOrders.Kind.ATTACK and PointerTargets.is_alive(_orders.target):
		target_at = PointerTargets.feet_of(_orders.target)
	elif _orders.kind == ClickOrders.Kind.MOVE and not _orders.held:
		target_at = _orders.goal
	marker.show_target(target_at, ClickMarker.color_for(PointerTargets.KIND_ATTACK if _orders.kind == ClickOrders.Kind.ATTACK else PointerTargets.KIND_GROUND))


## The ground marks in the current world (made on first use, again after a world swap).
func _click_marker_node() -> ClickMarker:
	if _click_marker != null and is_instance_valid(_click_marker) and _click_marker.is_inside_tree():
		return _click_marker
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null or not is_inside_tree():
		return null
	_click_marker = ClickMarker.new()
	_click_marker.name = "ClickMarker"
	parent.add_child(_click_marker)
	return _click_marker


func _set_cursor(shape: Input.CursorShape) -> void:
	if shape == _cursor_shape:
		return
	_cursor_shape = shape
	Input.set_default_cursor_shape(shape)


## The belt's next (+1) or previous (-1) weapon into the hand (`WeaponLoadout.cycle_slot`, then
## `InventoryActions.switch_weapon_slot`); nothing when no other weapon is on the belt.
func _switch_weapon(step: int) -> void:
	var slot := WeaponLoadout.cycle_slot(step)
	if slot < 0:
		return
	if _inventory_actions == null or not is_instance_valid(_inventory_actions):
		_inventory_actions = get_tree().get_first_node_in_group(INVENTORY_ACTIONS_GROUP)
	if _inventory_actions != null:
		_inventory_actions.call(&"switch_weapon_slot", slot)


func _audio_cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _real_now_ms() -> float:
	return float(Time.get_ticks_msec())

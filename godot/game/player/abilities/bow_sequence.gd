extends RefCounted
## The Bow's draw and shot (owner, 2026-11-20; decisions archive 2026-11-20; BODY_SHAPES.md "The Bow";
## every number in game-constants.json `abilities.bow`). Run by PlayerAbilities for the `bow` box
## ability.
##
## The Bow is shaped from the slime's own body, as the Spear is, and its arrows are goo it pinches off:
## no ammo, no counter, a little energy an arrow.
##
## - **The draw** (the press): the slime turns to the aim (player.gd `use_ability`: the movement keys,
##   else its facing; never the pointer), stands still (the sequence locks actions) and its whole body
##   bends into the bow (owner, 2026-11-20: "B, the body bends"): the clip `bow-draw-<direction>`
##   (page 7, scripts/characters/pack-slime-bow.py) stretches it into two horns, then bends it with the
##   belly and the face toward the aim, the horns swept back and the goo string pulled behind, the goo
##   arrow's tip out of the front; the drawn frame holds while the use key is held
##   (`player.is_action_held(&"ability_use")`, which the input tracks while actions are locked), at
##   least `drawMs`. Down, up and side by the player's three-way facing rule (a left aim mirrors the
##   side). A hit with damage while it is drawn (`interrupted_by_hit`, from PlayerAbilities.on_hurt)
##   ends it: no energy is spent and the cooldown is cleared.
## - **The shot** (the release, or `drawMs` after a tap): the energy (`energy`, 6) is spent now
##   (PlayerAbilities only checked it at the press); too little by now refuses with "Low energy" and
##   nothing flies. The arrow (bow_arrow.gd) leaves the front of the body along the aim and flies
##   straight; `bow-shot-<direction>` snaps the string and springs the body back toward its blob over
##   `recoverMs`, and the sequence ends.
##
## Cues have no takes yet: PLACEHOLDER_CUES plays instead (as goo_bomb_sequence.gd).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
const BowArrow := preload("res://game/player/abilities/bow_arrow.gd")

## The action whose hold keeps the bow drawn (AbilityBox.USE_ACTION).
const USE_ACTION := &"ability_use"
## The body-bow clips (player.gd plays their `-down`, `-up`, `-side` or `-left` version).
const CLIP_DRAW := "bow-draw"
const CLIP_SHOT := "bow-shot"
## How far ahead of the slime's centre the arrow leaves (the bent body's front).
const BOW_AHEAD_PX := 26.0

const CUE_DRAW := &"BowDraw"
const CUE_SHOOT := &"BowShoot"
const PLACEHOLDER_CUES := {
	CUE_DRAW: &"Lash",
	CUE_SHOOT: &"ThrowToss",
}

var ability_id: StringName = Definitions.BOW
var _player: Node
var _body: CharacterBody2D
var _direction: Vector2 = Vector2.RIGHT
var _started_ms: float = 0.0
var _draw_ms: float = 140.0
var _recover_ms: float = 140.0
var _shot_at: float = -1.0
var _done: bool = false


static func setting(key: String, fallback: float) -> float:
	var constants := Services.constants()
	var raw: Variant = constants.value(Definitions.BOW_CONSTANTS + "." + key) if constants != null else null
	return float(raw) if (raw is float or raw is int) else fallback


static func cue_or_placeholder(cue: StringName) -> StringName:
	var feel := Services.feel()
	var root: Node = feel.global_audio() if feel != null else null
	if root != null and root.find_child(String(cue), true, false) != null:
		return cue
	return PLACEHOLDER_CUES.get(cue, cue)


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_body = player.get(&"body") as CharacterBody2D
	_started_ms = now_ms
	var direction: Vector2 = intent.get("direction", Vector2.ZERO)
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_draw_ms = maxf(0.0, setting("drawMs", _draw_ms))
	_recover_ms = maxf(0.0, setting("recoverMs", _recover_ms))
	_player.call(&"face", _direction)
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_player.call(&"play_animation", CLIP_DRAW, true)
	_cue(CUE_DRAW)


func advance(now_ms: float) -> bool:
	if _done:
		return true
	if _shot_at < 0.0:
		var elapsed := now_ms - _started_ms
		if elapsed < _draw_ms or bool(_player.call(&"is_action_held", USE_ACTION)):
			return false
		if not _shoot(now_ms):
			_finish()
			return true
		_player.call(&"play_animation", CLIP_SHOT, true)
		return false
	var after := now_ms - _shot_at
	if after >= _recover_ms:
		_finish()
		return true
	return false


## A hit while the bow is drawn: the body lets go, nothing was spent; true (PlayerAbilities then
## clears the cooldown and unlocks). After the shot a hit changes nothing (false).
func interrupted_by_hit() -> bool:
	if _shot_at >= 0.0 or _done:
		return false
	_done = true
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")
	return true


## True while the bow is drawn (before the shot).
func is_drawing() -> bool:
	return _shot_at < 0.0 and not _done


## The way the arrow will fly (and flew).
func aim() -> Vector2:
	return _direction


## Teardown: the art back at rest.
func cancel() -> void:
	_done = true
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


# --- the shot ------------------------------------------------------------------------------------

## Spends the energy and looses the arrow; false (and "Low energy") when there is too little now.
func _shoot(now_ms: float) -> bool:
	_shot_at = now_ms
	var cost := Definitions.energy_cost(ability_id)
	if cost > 0.0 and not bool(_player.call(&"spend_energy", cost)):
		var abilities: Variant = _player.call(&"get_abilities")
		if abilities is Object:
			(abilities as Object).call(&"notify_rejected", ability_id, "energy")
		return false
	_cue(CUE_SHOOT)
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null or _body == null:
		return true
	var arrow := BowArrow.new()
	arrow.name = "BowArrow"
	parent.add_child(arrow)
	arrow.launch(_player, _body.global_position, _direction, BOW_AHEAD_PX)
	return true


func _finish() -> void:
	_done = true
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


func _cue(cue: StringName) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"action_cue", cue_or_placeholder(cue))

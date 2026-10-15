extends RefCounted
## The Goo Bomb's cast and spit (bomb-lantern-and-secrets design section 1; BODY_SHAPES.md "Goo
## Bomb"; every number in game-constants.json `abilities.gooBomb`). Run by PlayerAbilities for the
## `goo-bombs` box ability (rework mode; the classic game has no F action).
##
## - **The cast** (`castMs`, 2000): the slime stands still (the sequence locks actions) and swells
##   in `castPulses` slow pulses on the effects channel (`set_effect_scale`, up to `castSwell`
##   wider), while a small glowing bomb grows inside its jelly (a sprite on the body, drawn over the
##   art see-through, as the mouth shows what it holds). Under the slime the shapes' charge ring
##   (game/shapes/goo_ring.gd, set up as ShapeVisuals sets up its own: the same radius, squash,
##   colours and place behind the body) fills over the cast (owner, 2026-10-14: "the same loading
##   circle"); when it is full it takes the light colour, chimes (ShapeController.RING_FULL_CUE) and
##   pulses as a full charge ring does, and the spit follows at once. A hit with damage cancels the
##   cast (`interrupted_by_hit`, from PlayerAbilities.on_hurt): the bomb shrinks away, the ring drains
##   (`gulp.rework.ringCancelMs`), no energy is spent and the cooldown is cleared.
## - **The spit**: the energy (`energy`, 20) is spent now (PlayerAbilities only checked it at the
##   press); too little by now refuses with "Low energy". The `spit-<direction>` clip plays in the
##   facing, and the bomb (goo-bomb.tscn, goo_bomb.gd) pops out of the mouth and hops `hopPx` along
##   the aim, stopping short of walls and deep water. Its fuse starts as it leaves the mouth. The
##   sequence ends `spitMs` later.
##
## Cues have no takes yet: PLACEHOLDER_CUES plays instead (as slam_sequence.gd).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
## Loaded at the spit (a preload would make a load cycle through the player script).
const GOO_BOMB_SCENE := "res://game/scenes/objects/goo-bomb.tscn"
const GooBomb := preload("res://game/scripts/goo_bomb.gd")
const GooRing := preload("res://game/shapes/goo_ring.gd")
## The charge ring's look and chime, shared with the shapes (ShapeVisuals, ShapeController).
const ShapeVisuals := preload("res://game/shapes/shape_visuals.gd")
const RING_FULL_CUE := &"Heal"
const RING_CANCEL_PATH := "gulp.rework.ringCancelMs"
const RING_NAME := "GooBombRing"

const CUE_CAST := &"GooBombCast"
const CUE_SPIT := &"GooBombSpit"
const PLACEHOLDER_CUES := {
	CUE_CAST: &"SlamWindup",
	CUE_SPIT: &"GulpSpit",
}
const CLIP_CAST := "idle"
const CLIP_SPIT := "spit"
## The bomb inside: its size as a share of the bomb's art at the cast's start and end, how high
## over the feet it sits (the slime's belly, as Mouth.INSIDE_RISE), how see-through.
const INSIDE_START_SCALE := 0.04
const INSIDE_END_SCALE := 0.3
const INSIDE_RISE := 17.0
const INSIDE_ALPHA := 0.82
const INSIDE_SHRINK_S := 0.2
## The glow around the growing bomb: its size over the bomb's, and its pulse.
const GLOW_SCALE := 0.9
const GLOW_ALPHA := Vector2(0.25, 0.7)
## The swell is wider than tall (a jelly filling up).
const SWELL_TALL_SHARE := 0.55

var ability_id: StringName = Definitions.GOO_BOMBS
var _player: Node
var _body: CharacterBody2D
var _started_ms: float = 0.0
var _direction: Vector2 = Vector2.DOWN
var _cast_ms: float = 0.0
var _spit_ms: float = 0.0
var _pulses: float = 4.0
var _swell: float = 0.07
var _spat: bool = false
var _spat_at: float = 0.0
var _done: bool = false
var _inside: Node2D
var _inside_bomb: Sprite2D
var _inside_glow: Sprite2D
var _ring: GooRing
var _ring_full_real_ms: float = -1.0


static func setting(key: String) -> float:
	var constants := Services.constants()
	return constants.number(Definitions.GOO_BOMB_CONSTANTS + "." + key) if constants != null else 0.0


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
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.DOWN
	_cast_ms = setting("castMs")
	_spit_ms = setting("spitMs")
	_pulses = maxf(1.0, setting("castPulses"))
	_swell = setting("castSwell")
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_player.call(&"play_animation", CLIP_CAST, true)
	_make_inside()
	_make_ring()
	_cue(CUE_CAST)
	_pose(0.0)


func advance(now_ms: float) -> bool:
	if _done:
		return true
	var elapsed := now_ms - _started_ms
	if not _spat:
		if elapsed >= _cast_ms:
			if not _spit(now_ms):
				_finish()
				return true
		else:
			_pose(elapsed)
			return false
	_pulse_full_ring()
	if now_ms - _spat_at >= _spit_ms:
		_finish()
		return true
	return false


## A hit during the cast: the bomb shrinks away, the slime is itself again; true (PlayerAbilities
## then clears the cooldown and unlocks). After the spit a hit changes nothing (false).
func interrupted_by_hit() -> bool:
	if _spat or _done:
		return false
	_done = true
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")
	if _inside != null and is_instance_valid(_inside):
		var node := _inside
		_inside = null
		var tween := node.create_tween()
		tween.tween_property(node, "scale", Vector2.ZERO, INSIDE_SHRINK_S).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(node, "modulate:a", 0.0, INSIDE_SHRINK_S)
		tween.tween_callback(node.queue_free)
	_drain_ring()
	return true


## True before the spit (the cast is what a hit cancels).
func is_casting() -> bool:
	return not _spat and not _done


## Teardown: the art back at rest, the inside bomb gone.
func cancel() -> void:
	_done = true
	_free_inside()
	_free_ring()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


# --- the cast ------------------------------------------------------------------------------------

## The swell and the growing bomb `elapsed` ms into the cast: `_pulses` breaths, each a little
## bigger than the last, the bomb growing (ease in) and its glow breathing with them.
func _pose(elapsed: float) -> void:
	var t := clampf(elapsed / _cast_ms, 0.0, 1.0) if _cast_ms > 0.0 else 1.0
	var breath := 0.5 - 0.5 * cos(t * _pulses * TAU)
	var swell := _swell * breath * (0.45 + 0.55 * t)
	_player.call(&"set_effect_scale", Vector2(1.0 + swell, 1.0 + swell * SWELL_TALL_SHARE))
	if _inside != null and is_instance_valid(_inside):
		var grow := lerpf(INSIDE_START_SCALE, INSIDE_END_SCALE, t * t * (3.0 - 2.0 * t))
		_inside_bomb.scale = Vector2.ONE * grow * (1.0 + 0.12 * breath)
		_inside_glow.scale = Vector2.ONE * grow * GLOW_SCALE * (1.0 + 0.3 * breath)
		_inside_glow.modulate.a = lerpf(GLOW_ALPHA.x, GLOW_ALPHA.y, breath) * (0.5 + 0.5 * t)
	if _ring != null and is_instance_valid(_ring):
		_ring.set_progress(t)


func _make_inside() -> void:
	if _body == null:
		return
	_inside = Node2D.new()
	_inside.name = "BombInside"
	_inside.position = Vector2(0.0, -INSIDE_RISE)
	_inside.z_index = 1
	_inside_glow = Sprite2D.new()
	_inside_glow.texture = GooBomb.glow_texture()
	_inside_glow.material = GooBomb.additive_material()
	_inside_glow.modulate = Color(GooBomb.CORE_COLOR, 0.0)
	_inside.add_child(_inside_glow)
	_inside_bomb = Sprite2D.new()
	_inside_bomb.texture = GooBomb.bomb_texture()
	_inside_bomb.modulate = Color(1.0, 1.0, 1.0, INSIDE_ALPHA)
	_inside.add_child(_inside_bomb)
	_body.add_child(_inside)


## The charge ring under the slime, as ShapeVisuals.setup makes the shapes' one.
func _make_ring() -> void:
	if _body == null:
		return
	_ring = GooRing.new()
	_ring.name = RING_NAME
	_ring.scale = Vector2(1.0, ShapeVisuals.RING_SQUASH_Y)
	var constants := Services.constants()
	if constants != null:
		_ring.radius_px = float(constants.value(ShapeVisuals.RING_RADIUS_PATH, _ring.radius_px))
	_ring.set_color(_goo_colour())
	_ring.set_progress(0.0)
	_body.add_child(_ring)
	_body.move_child(_ring, 0)


## The shapes' goo colour (the form's tint when the slime wears one), as ShapeVisuals picks it.
func _goo_colour() -> Color:
	var form: Variant = _player.call(&"current_form") if _player != null else {}
	var tint: Variant = (form as Dictionary).get("tint") if form is Dictionary else null
	return tint if tint is Color else ShapeVisuals.GOO


## The full ring: the light colour, the chime, and its pulse from now on.
func _fill_ring() -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	_ring.set_progress(1.0)
	_ring.set_color(_goo_colour().lightened(ShapeVisuals.LIGHT_SHARE))
	_ring_full_real_ms = float(Time.get_ticks_msec())
	_player.call(&"action_cue", RING_FULL_CUE)


## The full ring's pulse (ShapeVisuals' RING_PULSE at RING_PULSE_HZ, real time) until the spit ends.
func _pulse_full_ring() -> void:
	if _ring == null or not is_instance_valid(_ring) or _ring_full_real_ms < 0.0:
		return
	var age := (float(Time.get_ticks_msec()) - _ring_full_real_ms) / 1000.0
	var pulse := 1.0 + ShapeVisuals.RING_PULSE * sin(age * TAU * ShapeVisuals.RING_PULSE_HZ)
	_ring.scale = Vector2(pulse, ShapeVisuals.RING_SQUASH_Y * pulse)


## Empties the ring over `gulp.rework.ringCancelMs` and frees it.
func _drain_ring() -> void:
	if _ring == null or not is_instance_valid(_ring):
		_ring = null
		return
	var ring := _ring
	_ring = null
	var constants := Services.constants()
	var drain_ms := float(constants.value(RING_CANCEL_PATH, 150.0)) if constants != null else 150.0
	ring.scale = Vector2(1.0, ShapeVisuals.RING_SQUASH_Y)
	ring.drain(drain_ms)
	var tree := ring.get_tree()
	if tree != null:
		tree.create_timer(drain_ms / 1000.0 + 0.05, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(ring):
				ring.queue_free())
	else:
		ring.queue_free()


func _free_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


func _free_inside() -> void:
	if _inside != null and is_instance_valid(_inside):
		_inside.queue_free()
	_inside = null


# --- the spit ------------------------------------------------------------------------------------

## Spends the energy and spits the bomb out; false (and "Low energy") when there is too little now.
func _spit(now_ms: float) -> bool:
	_spat = true
	_spat_at = now_ms
	_free_inside()
	_player.call(&"reset_effects")
	var cost := Definitions.energy_cost(ability_id)
	if cost > 0.0 and not bool(_player.call(&"spend_energy", cost)):
		var abilities: Variant = _player.call(&"get_abilities")
		if abilities is Object:
			(abilities as Object).call(&"notify_rejected", ability_id, "energy")
		return false
	_fill_ring()
	_player.call(&"face", _direction)
	_player.call(&"play_animation", CLIP_SPIT, true)
	_cue(CUE_SPIT)
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null or _body == null:
		return true
	var scene := load(GOO_BOMB_SCENE) as PackedScene
	if scene == null:
		return true
	var bomb := scene.instantiate() as Node2D
	parent.add_child(bomb)
	bomb.call(&"spit_from", _player, _body.global_position, _direction)
	return true


func _finish() -> void:
	_done = true
	_free_inside()
	_drain_ring()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


func _cue(cue: StringName) -> void:
	if _player != null and is_instance_valid(_player):
		_player.call(&"action_cue", cue_or_placeholder(cue))

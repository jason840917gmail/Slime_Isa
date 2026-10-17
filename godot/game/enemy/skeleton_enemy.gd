extends "res://game/enemy/patterned_enemy.gd"
class_name SkeletonEnemyScript
## The base of the bestiary's skeletons (rows 30 to 32: the Bone Leaper, the Bone Thrower and the
## Bone Marcher; docs/godot/BESTIARY.md "The skeletons"): the great war's fallen, found only in the
## dungeons. On top of the patterned enemy it adds **the bone pile**:
##
## - **Collapse:** beaten (its health at 0), a skeleton does not die: it falls into a pile of bones
##   (`pile`) with its skull on top. The pile is not a live enemy: it never moves, attacks or blocks
##   (not solid), and it gives no rewards yet.
## - **Stands up:** `reassembleMs` after the collapse it stands up whole (full health) where it lies;
##   for the last `reassembleTellMs` the bones rattle (`reassemble`, the tell: finish it now).
##   `reassembleMs` 0 turns the trait off: a beaten skeleton dies at once, as any enemy.
## - **Scattered:** any hit with damage on the pile scatters it for good (`commit_damage` marks it a
##   kill; the pile keeps its full health only so the hit's own damage shows): the final death, with
##   the rewards and the energy shard (the base enemy's `_defeat`).
## - **The skull:** the Gulp (Q) takes the skull from the pile (game/enemy/bone_skull.gd, in the
##   mouth's `suckable` group, with its own picture); thrown, it hits like a pot (tags `thrown` and
##   `skull`). Without its skull the pile never stands up: it crumbles `headlessMs` later (the final
##   death).
##
## Subclasses implement `_step_skeleton` (their pattern while standing), `_on_collapse` (drop what
## they were doing: a landing mark, a bone in flight), `_on_stand_up` (their first phase again), and
## `_skeleton_shields` / `_skeleton_slides` in place of `_shields` / `_slides_when_stunned`.
## The pile's look is the scene's `pile_texture` and `skull_texture`, made in code under the body.
##
## Owner: enemy builder.

const BoneSkullScript := preload("res://game/enemy/bone_skull.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")

const PHASE_PILE := "pile"
const PHASE_REASSEMBLE := "reassemble"
const CUE_COLLAPSE := &"BreakWood"
const CUE_SCATTER := &"BreakStone"
const CUE_RATTLE := &"GroundCreak"
const CUE_STAND := &"DropPop"
const DUST := &"dodge-dust"
const CHIPS := &"stone-chip"
const PILE_NAME := "BonePile"
const SKULL_NAME := "Skull"
## Presentation: the reassembly's rattle (it grows over the tell), the skull's hop at its end, the
## stand-up's stretch, the scattered heap's spread.
const RATTLE_RAD := 0.14
const RATTLE_MS := 26.0
const SKULL_HOP_PX := 5.0
const STAND_SQUASH := Vector2(0.9, 1.12)
const SCATTER_SQUASH := Vector2(1.35, 0.55)

## The bone pile's picture (centred), its centre from the feet, its scale.
@export_file("*.webp", "*.png") var pile_texture: String = "res://asset/MAPS/enemies/128x128-bone-pile.webp"
@export var pile_offset: Vector2 = Vector2(0.0, -10.0)
@export var pile_scale: float = 0.44
## The skull's picture (what the Gulp takes from the pile), where it lies on the pile, its scale.
@export_file("*.webp", "*.png") var skull_texture: String = "res://asset/MAPS/enemies/64x64-skull.webp"
@export var skull_offset: Vector2 = Vector2(7.0, -20.0)
@export var skull_scale: float = 0.38

var _pile: Sprite2D
var _skull: BoneSkullScript
var _has_skull: bool = true
## When a headless pile crumbles (simulation ms; < 0: it has its skull).
var _crumble_at: float = -1.0


func _ready() -> void:
	super()
	_make_pile_look()


## True while it lies as a pile of bones (the pile and its reassembly tell).
func is_pile() -> bool:
	return _phase == PHASE_PILE or _phase == PHASE_REASSEMBLE


## False once the Gulp took the skull off its pile (it never stands up again).
func has_skull() -> bool:
	return _has_skull


## The skull node on its pile (null before the look is made).
func get_skull() -> BoneSkullScript:
	return _skull


# --- the step ----------------------------------------------------------------------------------------

func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	if is_pile():
		_step_pile(now)
		return
	_step_skeleton(now, delta, target, engaged)


## The subclass's pattern while it stands (sets `body.velocity`).
func _step_skeleton(_now: float, _delta: float, _target: Dictionary, _engaged: bool) -> void:
	body.velocity = Vector2.ZERO


func _step_pile(now: float) -> void:
	body.velocity = Vector2.ZERO
	if not _has_skull:
		_pile_look(0.0)
		if now >= _crumble_at:
			_defeat()
		return
	var elapsed := _elapsed(now)
	var tell_ms := maxf(1.0, pattern("reassembleTellMs", 700.0))
	match _phase:
		PHASE_PILE:
			_pile_look(0.0)
			if elapsed >= maxf(0.0, pattern("reassembleMs", 3000.0) - tell_ms):
				_transition(PHASE_REASSEMBLE, now)
				_cue(CUE_RATTLE)
		PHASE_REASSEMBLE:
			var t := clampf(elapsed / tell_ms, 0.0, 1.0)
			_pile_look(t, elapsed)
			if t >= 1.0:
				_stand_up(now)


# --- the pile ----------------------------------------------------------------------------------------

## Beaten: the pile (the trait on), else the final death.
func _defeat() -> void:
	if is_defeated():
		return
	if not is_pile() and pattern("reassembleMs", 3000.0) > 0.0:
		_collapse(Services.now_ms())
		return
	_scatter()
	super()


func _collapse(now: float) -> void:
	cancel_attack()
	_on_collapse(now)
	_transition(PHASE_PILE, now)
	# Full health while it lies, so a hit's own damage shows; any hit with damage scatters it
	# all the same (`commit_damage`).
	_hp = max_health
	set_death_slide(Vector2.ZERO)
	set_hit_stun_until(0.0)
	body.velocity = Vector2.ZERO
	set_solid(false)
	set_look(0.0)
	_show_pile(true)
	if _skull != null:
		_skull.show_on_pile(_has_skull)
	_cue(CUE_COLLAPSE)
	_puff(DUST, feet())
	_puff(CHIPS, feet() + pile_offset)


func _stand_up(now: float) -> void:
	_show_pile(false)
	if _skull != null:
		_skull.show_on_pile(false)
	set_solid(true)
	_restore_health(max_health)
	_cue(CUE_STAND)
	_puff(DUST, feet())
	_on_stand_up(now)
	set_look(0.0, STAND_SQUASH)


## The final death's look: the pile (with its skull, if it still has it) bursts into bones and the
## heap left spreads flat as it fades (corpseMs, corpseFadeMs).
func _scatter() -> void:
	if not is_pile():
		_on_collapse(Services.now_ms())
	_show_pile(true)
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if _pile != null and parent != null:
		BreakBurst.burst(parent, _pile.global_position, _pile)
	if _skull != null and _skull.is_on_pile() and parent != null:
		BreakBurst.burst(parent, _skull.global_position, _skull)
	if _skull != null:
		_skull.show_on_pile(false)
	if _pile != null:
		_pile.rotation = 0.0
		_pile.scale = Vector2.ONE * pile_scale * SCATTER_SQUASH
	_cue(CUE_SCATTER)
	_puff(DUST, feet())
	_puff(CHIPS, feet() + pile_offset)


## The Gulp took the skull: the pile can never stand up; it crumbles `headlessMs` later.
func _on_skull_taken() -> void:
	_has_skull = false
	_crumble_at = Services.now_ms() + pattern("headlessMs", 1200.0)


func _show_pile(on: bool) -> void:
	if pose != null:
		pose.visible = not on
	if _pile != null:
		_pile.visible = on
		_pile.rotation = 0.0
		_pile.position = pile_offset
		_pile.scale = Vector2.ONE * pile_scale
	if _shadow != null:
		_shadow.visible = not on


## The pile at rest (`t` 0) or rattling as it gets ready to stand up (`t` up to 1; `elapsed` the
## tell's ms).
func _pile_look(t: float, elapsed: float = 0.0) -> void:
	if _pile == null:
		return
	var shake := sin(elapsed / RATTLE_MS) * RATTLE_RAD * t
	_pile.rotation = shake
	_pile.position = pile_offset + Vector2(shake * 6.0, 0.0)
	if _skull != null:
		_skull.rotation = -shake * 1.5
		_skull.position = skull_offset - Vector2(0.0, SKULL_HOP_PX * t * t * absf(sin(elapsed / (RATTLE_MS * 3.0))))


func _make_pile_look() -> void:
	if body == null:
		return
	_pile = Sprite2D.new()
	_pile.name = PILE_NAME
	_pile.centered = true
	_pile.texture = SheetSprite.load_picture(pile_texture)
	_pile.z_index = -1
	_pile.z_as_relative = true
	_pile.visible = false
	_pile.position = pile_offset
	_pile.scale = Vector2.ONE * pile_scale
	_skull = BoneSkullScript.new()
	_skull.name = SKULL_NAME
	_skull.centered = true
	_skull.picture_path = skull_texture
	_skull.texture = SheetSprite.load_picture(skull_texture)
	_skull.z_index = -1
	_skull.z_as_relative = true
	_skull.position = skull_offset
	_skull.scale = Vector2.ONE * skull_scale
	_skull.show_on_pile(false)
	_skull.taken.connect(_on_skull_taken)
	for node: Node2D in [_pile, _skull]:
		if body.is_node_ready():
			body.add_child(node)
		else:
			body.add_child.call_deferred(node)


# --- hooks -------------------------------------------------------------------------------------------

## It falls into a pile (or dies without one): drop what it was doing.
func _on_collapse(_now: float) -> void:
	pass


## It stood up whole: its first phase again.
func _on_stand_up(_now: float) -> void:
	pass


## True when its standing phase cannot be hurt by `request` (a pile never shields).
func _skeleton_shields(_request: Dictionary) -> bool:
	return false


## Whether a stun slides it while it stands (a pile never slides).
func _skeleton_slides() -> bool:
	return true


func _shields(request: Dictionary) -> bool:
	return not is_pile() and _skeleton_shields(request)


func _slides_when_stunned() -> bool:
	return not is_pile() and _skeleton_slides()


## On the pile every hit with damage is the killing blow: it scatters (the sender gets a kill).
func commit_damage(commit: Dictionary) -> void:
	if is_pile() and not is_defeated():
		var result: Variant = commit.get("result")
		if result is Dictionary and int((result as Dictionary).get("actual_damage", 0)) > 0:
			(result as Dictionary)["defeated"] = true
	super(commit)

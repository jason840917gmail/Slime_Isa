extends StaticBody2D
## Scene script of `object.blast-keg` (game/scenes/objects/blast-keg.tscn; the Weaver Hollow's optional
## room B6, docs/design/2026-10-16-dungeon-weaver-hollow.md "B6 the Pillar" and open point 5; BODY_SHAPES.md
## "The Goo Bomb"). An old Thorn Guard blast keg: squat, iron-hooped, lying in an iron cradle bolted
## onto a flagstone block (fixed: the Gulp cannot take it, it is in no `suckable` group, and it blocks
## as a wall does), carrying the bomb's crack mark on its belly (asset/abilities/goo-bomb/
## blast-keg-2x1.webp: intact | burst, 2 px a unit, drawn at 0.5; scripts/art/pack-weaver-bomb-art.py).
##
## - **Hits** of weapons, throws and slams clink off its hurtbox (`DamageArea`) with `refusal_text`
##   (BlastBarrier: "immune").
## - **A Goo Bomb blast** whose ellipse holds its root (group `blast_targets`, `receive_blast`) lights
##   it: it flashes and swells for `puzzles.blastKeg.delayMs` (game-constants.json; about the bomb's
##   own chain delay), then **blows as a real blast** at its root (GooBlast.detonate: enemies, the
##   slime, every blast target and bomb in that ellipse), and lies burst. So a line of kegs each within
##   a blast's ellipse of the next (176 x 120: up to about 80 units apart side by side, 50 one above
##   the other) goes off one after another, and the last one breaks a cracked target beside it.
## - **Nothing is saved:** a world built again has every keg back (a failed chain is tried again);
##   what they blew keeps its own flag.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")

## Every blast keg.
const GROUP := &"blast_kegs"
const CONSTANTS := "puzzles.blastKeg"
const FRAME_INTACT := 0
const FRAME_BURST := 1
## The lit keg's look: it blinks this bright this often and swells this much (presentation).
const LIT_BRIGHT := 2.2
const LIT_BLINK_MS := 60.0
const LIT_SWELL := 0.08
const REFUSAL_RISE := 46.0
const CUE_LIT := &"GroundCreak"

@export var refusal_text: String = "It needs a blast."

## It blew. Payload: {"position": Vector2 (its root)}.
signal set_off(payload: Dictionary)

var _lit_at_ms: float = -1.0
var _blow_at_ms: float = -1.0
var _spent: bool = false


func _enter_tree() -> void:
	add_to_group(BlastBarrier.GROUP)
	add_to_group(GROUP)


func _ready() -> void:
	BlastBarrier.register(get_node_or_null(^"DamageArea") as Area2D, self)
	set_physics_process(false)


func _exit_tree() -> void:
	BlastBarrier.unregister(get_node_or_null(^"DamageArea") as Area2D)


## True once it blew.
func is_spent() -> bool:
	return _spent


## True while it is lit and about to blow.
func is_lit() -> bool:
	return _blow_at_ms >= 0.0 and not _spent


func blast_point() -> Vector2:
	return global_position


## A blast reached it: it goes off `puzzles.blastKeg.delayMs` from now. False once lit or spent.
func receive_blast(_hit: Dictionary) -> bool:
	if _spent or _blow_at_ms >= 0.0:
		return false
	var constants := Services.constants()
	var delay := constants.number(CONSTANTS + ".delayMs") if constants != null else 0.0
	_lit_at_ms = Services.now_ms()
	_blow_at_ms = _lit_at_ms + maxf(0.0, delay)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_LIT)
	set_physics_process(true)
	return true


func _physics_process(_delta: float) -> void:
	if _spent or _blow_at_ms < 0.0:
		set_physics_process(false)
		return
	var now := Services.now_ms()
	if now >= _blow_at_ms:
		_blow()
		return
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		var t := clampf((now - _lit_at_ms) / maxf(1.0, _blow_at_ms - _lit_at_ms), 0.0, 1.0)
		var blink := fmod((now - _lit_at_ms) / LIT_BLINK_MS, 2.0) < 1.0
		var bright := LIT_BRIGHT if blink else 1.0 + (LIT_BRIGHT - 1.0) * 0.4
		visual.modulate = Color(bright, bright, bright, 1.0)
		visual.scale = _rest_scale(visual) * (1.0 + LIT_SWELL * t)


## It blows: a real Goo Bomb blast at its root, then it lies burst (its cradle and block still block).
func _blow() -> void:
	_spent = true
	set_physics_process(false)
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		visual.frame = FRAME_BURST
		visual.modulate = Color.WHITE
		visual.scale = _rest_scale(visual)
	var area := get_node_or_null(^"DamageArea") as Area2D
	BlastBarrier.unregister(area)
	if area != null:
		area.queue_free()
	GooBlast.detonate(global_position, false, null)
	set_off.emit({"position": global_position})


func _rest_scale(visual: Sprite2D) -> Vector2:
	if not visual.has_meta(&"keg_rest_scale"):
		visual.set_meta(&"keg_rest_scale", visual.scale)
	return visual.get_meta(&"keg_rest_scale")


# --- the damage contract (only refusals: blasts come through receive_blast) ----------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _spent}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	return BlastBarrier.refuse(global_position - Vector2(0.0, REFUSAL_RISE), refusal_text)

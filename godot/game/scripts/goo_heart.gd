extends Node
class_name GooHeartScript
## Scene script `game.goo-heart` (Phaser `features/scripts/GooHeartScript.ts`; abilities spec
## 13.7). A hidden Goo Heart that bobs until the living player's centre comes within `radius`:
## then it vanishes, max HP grows by `character.player.gooHeart.maxHpBonus` (10) for the rest of
## the run, HP fills, "+10 max HP" shows and `collected` fires. The story flag
## "goo-heart.<heart_id>" keeps it gone everywhere (heart ids are unique across maps).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const UNASSIGNED := "unassigned"
const FLAG_PREFIX := "goo-heart."
const BOB_RATE := 3.0
const TEXT_RISE := 40.0
const TEXT_MS := 2000.0
const CUE := &"Heal"

## JSON `heartId`.
@export var heart_id: String = ""
## JSON `radius`.
@export var radius: float = 36.0
## JSON `bobPx`.
@export var bob_px: float = 4.0
## JSON `visual`: the heart Sprite2D (optional).
@export var visual: Sprite2D

## The heart was taken. Payload: {"heartId"}.
signal collected(payload: Dictionary)

var _taken: bool = false
var _elapsed: float = 0.0
var _rest_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not (is_finite(radius) and radius >= 0.0):
		radius = 36.0
	if not (is_finite(bob_px) and bob_px >= 0.0):
		bob_px = 4.0
	if visual != null:
		_rest_offset = visual.offset
	if heart_id.is_empty() or heart_id == UNASSIGNED:
		push_warning("GooHeartScript: a Goo Heart has no heartId; it cannot be collected")
		_taken = true
		return
	var run := Services.run()
	if run != null and run.has_flag(FLAG_PREFIX + heart_id):
		_vanish()


func is_taken() -> bool:
	return _taken


func _process(delta: float) -> void:
	if _taken:
		return
	_elapsed += delta
	if visual != null:
		visual.offset = Vector2(_rest_offset.x, _rest_offset.y + roundf(sin(_elapsed * BOB_RATE) * bob_px))


func _physics_process(_delta: float) -> void:
	if _taken:
		return
	var world := Services.world()
	var player = world.player if world != null else null
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		return
	var root := get_parent() as Node2D
	if root == null or (player.call(&"get_centre") as Vector2).distance_to(root.global_position) > radius:
		return
	_vanish()
	_collect(player, root.global_position)
	collected.emit({"heartId": heart_id})


func _vanish() -> void:
	_taken = true
	var root := get_parent() as CanvasItem
	if root != null:
		root.visible = false


## `WorldScene.collectGooHeart`: the flag, one more heart (max HP + 10, HP full), the text.
func _collect(player: Node, at: Vector2) -> void:
	var run := Services.run()
	if run == null or run.has_flag(FLAG_PREFIX + heart_id):
		return
	run.set_flag(FLAG_PREFIX + heart_id)
	player.call(&"grant_goo_heart")
	var feel := Services.feel()
	if feel != null:
		var constants := Services.constants()
		var bonus := constants.integer("character.player.gooHeart.maxHpBonus") if constants != null else 0
		feel.audio_cue(CUE)
		feel.floating_text(at - Vector2(0.0, TEXT_RISE), "+%d max HP" % bonus, &"green", true, TEXT_MS)

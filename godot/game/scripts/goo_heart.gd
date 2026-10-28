extends Node
class_name GooHeartScript
## Scene script `game.goo-heart` (Phaser `features/scripts/GooHeartScript.ts`; abilities spec
## 13.7): a **heart quarter** since 2026-10-26 (roadmap 5.3; it was a +10 Goo Heart). A hidden
## quarter that bobs until the living player's centre comes within `radius`: then it vanishes and
## counts toward the next heart (`RunState.heart_quarters`). A quarter alone adds no HP; the fourth
## (`character.player.heartQuarter.perHeart`) completes a heart: max HP grows by `heartMaxHpBonus`
## (20) for the run and HP fills. "Heart quarter 2 of 4" or "Heart complete! +20 max HP" shows and
## `collected` fires. The story flag "goo-heart.<heart_id>" keeps it gone everywhere (heart ids are
## unique across maps). Every quarter plays the ceremony (game/ui/ceremony/, roadmap 4.13) while
## main's `ability_ceremonies` is on. Only a beaten boss gives a full heart (full_heart.gd).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")

const UNASSIGNED := "unassigned"
const FLAG_PREFIX := "goo-heart."
const BOB_RATE := 3.0
const TEXT_RISE := 40.0
const TEXT_MS := 2000.0
const CUE := &"Heal"
## The quarter's picture (owner pick 2026-10-27): a glass heart filling with goo, frame N the vessel
## N+1 quarters full (scripts/props/pack-heart-quarter.py). A pickup shows the level its quarters
## would bring the next heart to; the chest's rising quarter and the ceremony show the level reached.
const QUARTER_SHEET := "res://asset/MAPS/props/256x256-tile_4x1-heart-quarter.webp"
const QUARTER_CELL := 256
const QUARTER_LEVELS := 4

## JSON `heartId`.
@export var heart_id: String = ""
## JSON `radius`.
@export var radius: float = 36.0
## JSON `bobPx`.
@export var bob_px: float = 4.0
## JSON `visual`: the heart Sprite2D (optional).
@export var visual: Sprite2D
## How many heart quarters it gives.
@export_range(1, 4) var quarters: int = 1

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
		# The level taking it would bring the next heart to (it follows quarters taken meanwhile).
		if visual.hframes == QUARTER_LEVELS:
			visual.frame = clampi(level_after(quarters), 1, QUARTER_LEVELS) - 1


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


## `WorldScene.collectGooHeart`: the flag, its quarters, the text.
func _collect(player: Node, at: Vector2) -> void:
	# No icon: `celebrate` shows the level the quarters reached.
	grant(get_tree() if is_inside_tree() else null, player, heart_id, quarters, at, null)


## Grants the heart quarter `id` (`count` quarters) to `player` as its pickup does: the flag
## "goo-heart.<id>", the quarters (the fourth of a heart raises max HP and fills HP) and the cue,
## then (unless `celebrate_now` is false) its text and ceremony (`celebrate`). False (and nothing
## given) when the flag is already set. Also used by chests that hold a quarter (chest.gd celebrates
## it itself once the quarter has risen, so a load or a travel meanwhile, which frees the chest,
## skips it).
static func grant(tree: SceneTree, player: Node, id: String, count: int, at: Vector2, icon: Texture2D, celebrate_now: bool = true) -> bool:
	var run := Services.run()
	if run == null or id.is_empty() or id == UNASSIGNED or run.has_flag(FLAG_PREFIX + id):
		return false
	run.set_flag(FLAG_PREFIX + id)
	for i in maxi(1, count):
		if player != null and player.has_method(&"grant_heart_quarter"):
			player.call(&"grant_heart_quarter")
		else:
			run.add_heart_quarter()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE)
	if celebrate_now:
		celebrate(tree, count, at, icon)
	return true


## The text over `at` for the `count` quarters just granted ("Heart quarter 2 of 4", or "Heart
## complete! +20 max HP" when they completed a heart) and its ceremony (with `icon`) while main's
## `ability_ceremonies` is on.
static func celebrate(tree: SceneTree, count: int, at: Vector2, icon: Texture2D) -> void:
	var run := Services.run()
	var constants := Services.constants()
	var per := run.quarters_per_heart() if run != null else 4
	var found := run.heart_quarters() if run != null else 0
	var completed := found / per > maxi(0, found - maxi(1, count)) / per
	var bonus := constants.integer("character.player.heartQuarter.heartMaxHpBonus") if constants != null else 0
	var filled := per if completed else found % per
	if icon == null:
		icon = level_icon(filled)
	var text := "Heart complete! +%d max HP" % bonus if completed else "Heart quarter %d of %d" % [filled, per]
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at - Vector2(0.0, TEXT_RISE), text, &"green", true, TEXT_MS)
	if tree != null and AbilityCeremony.enabled(tree):
		AbilityCeremony.request_heart(tree, filled, per, bonus if completed else 0, icon)


## True when the Goo Heart `id` was taken (its flag is set).
static func is_heart_taken(id: String) -> bool:
	var run := Services.run()
	return run != null and run.has_flag(FLAG_PREFIX + id)


## The quarters toward the next heart after `count` more (1..per: a completed heart is `per`).
static func level_after(count: int) -> int:
	var run := Services.run()
	if run == null:
		return clampi(count, 1, QUARTER_LEVELS)
	var per := run.quarters_per_heart()
	var level := (run.heart_quarters() + maxi(0, count)) % per
	return per if level == 0 else level


## The vessel `filled` quarters full (1..4), as the sheet draws it.
static func level_icon(filled: int) -> Texture2D:
	var sheet := load(QUARTER_SHEET) as Texture2D
	if sheet == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = sheet
	icon.region = Rect2((clampi(filled, 1, QUARTER_LEVELS) - 1) * QUARTER_CELL, 0, QUARTER_CELL, QUARTER_CELL)
	return icon


## The quarter's picture at the level reached now (a chest asks right after granting it).
static func default_icon() -> Texture2D:
	return level_icon(level_after(0))

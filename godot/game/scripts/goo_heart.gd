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
## would bring the next heart to; the chest's rising quarter and the ceremony show the level reached
## (RunState `heart_level_after`; a heart of `perHeart` quarters is drawn on the sheet's frames).
const QUARTER_SHEET := "res://asset/MAPS/props/256x256-tile_4x1-heart-quarter.webp"
const QUARTER_CELL := 256
## The sheet's frames: the vessel a quarter full, up to full.
const QUARTER_FRAMES := 4

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
		var run := Services.run()
		if visual.hframes == QUARTER_FRAMES and run != null:
			visual.frame = level_frame(run.heart_level_after(quarters))


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
	grant(get_tree() if is_inside_tree() else null, player, heart_id, quarters, at)


## Grants the heart quarter `id` (`count` quarters) to `player` as its pickup does: the flag
## "goo-heart.<id>", the quarters (player.gd `grant_heart_quarter`, RunState `add_heart_quarter`:
## the fourth of a heart raises max HP and fills HP) and the cue, then (unless `celebrate_now` is
## false) its text and ceremony (`celebrate`). Returns what it gave: {"completed": true when the
## quarters completed a heart (RunState's answer), "filled": how full the next heart is now (1..per;
## per when completed), "per": quarters a heart, "icon": the vessel that full}; {} (nothing given)
## when the flag is already set. Also used by chests that hold a quarter (chest.gd lifts the icon out
## and celebrates it itself once the quarter has risen, so a load or a travel meanwhile, which frees
## the chest, skips it).
static func grant(tree: SceneTree, player: Node, id: String, count: int, at: Vector2, celebrate_now: bool = true) -> Dictionary:
	var run := Services.run()
	if run == null or id.is_empty() or id == UNASSIGNED or run.has_flag(FLAG_PREFIX + id):
		return {}
	run.set_flag(FLAG_PREFIX + id)
	var completed := false
	for i in maxi(1, count):
		var made := false
		if player != null and player.has_method(&"grant_heart_quarter"):
			made = bool(player.call(&"grant_heart_quarter"))
		else:
			made = run.add_heart_quarter()
		completed = completed or made
	var per := run.quarters_per_heart()
	var filled := per if completed else run.heart_level_after()
	var heart := {"completed": completed, "filled": filled, "per": per, "icon": level_icon(filled)}
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE)
	if celebrate_now:
		celebrate(tree, heart, at)
	return heart


## The text over `at` for a `grant` (`heart`, what it returned): "Heart quarter 2 of 4", or "Heart
## complete! +20 max HP" when it completed a heart, and its ceremony while main's
## `ability_ceremonies` is on.
static func celebrate(tree: SceneTree, heart: Dictionary, at: Vector2) -> void:
	var constants := Services.constants()
	var completed := bool(heart.get("completed", false))
	var filled := int(heart.get("filled", 0))
	var per := int(heart.get("per", 0))
	var bonus := constants.integer("character.player.heartQuarter.heartMaxHpBonus") if constants != null else 0
	var text := "Heart complete! +%d max HP" % bonus if completed else "Heart quarter %d of %d" % [filled, per]
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at - Vector2(0.0, TEXT_RISE), text, &"green", true, TEXT_MS)
	if tree != null and AbilityCeremony.enabled(tree):
		AbilityCeremony.request_heart(tree, filled, per, bonus if completed else 0, heart.get("icon") as Texture2D)


## True when the Goo Heart `id` was taken (its flag is set).
static func is_heart_taken(id: String) -> bool:
	var run := Services.run()
	return run != null and run.has_flag(FLAG_PREFIX + id)


## The sheet's frame of a heart `filled` quarters full (RunState `heart_level_after`; 1..perHeart).
static func level_frame(filled: int) -> int:
	var run := Services.run()
	var per := run.quarters_per_heart() if run != null else QUARTER_FRAMES
	return clampi(ceili(float(clampi(filled, 1, per)) * QUARTER_FRAMES / per), 1, QUARTER_FRAMES) - 1


## The vessel `filled` quarters full, as the sheet draws it.
static func level_icon(filled: int) -> Texture2D:
	var sheet := load(QUARTER_SHEET) as Texture2D
	if sheet == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = sheet
	icon.region = Rect2(level_frame(filled) * QUARTER_CELL, 0, QUARTER_CELL, QUARTER_CELL)
	return icon

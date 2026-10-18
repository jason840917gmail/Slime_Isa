extends Node
class_name GooHeartScript
## Scene script `game.goo-heart` (Phaser `features/scripts/GooHeartScript.ts`; abilities spec
## 13.7). A hidden Goo Heart that bobs until the living player's centre comes within `radius`:
## then it vanishes, max HP grows by `character.player.gooHeart.maxHpBonus` (10) for the rest of
## the run, HP fills, "+10 max HP" shows and `collected` fires. The story flag
## "goo-heart.<heart_id>" keeps it gone everywhere (heart ids are unique across maps). Every heart
## plays the ceremony (game/ui/ceremony/, roadmap 4.13) while main's `ability_ceremonies` is on.
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
## The heart's picture: the heart painted in frame 5 of the gulp props sheet (goo-heart.tscn's
## frame), its pixels in that sheet.
const HEART_SHEET := "res://asset/MAPS/props/256x256-tile_8x1-gulp-props.webp"
const HEART_REGION := Rect2(5 * 256 + 70, 130, 116, 126)

## JSON `heartId`.
@export var heart_id: String = ""
## JSON `radius`.
@export var radius: float = 36.0
## JSON `bobPx`.
@export var bob_px: float = 4.0
## JSON `visual`: the heart Sprite2D (optional).
@export var visual: Sprite2D
## How many Goo Hearts' worth it gives: a boss's full heart is two (+20 max HP, question 17;
## Fatty's Lair, docs/godot/DUNGEONS.md), until the heart quarters' work (roadmap 5.3) replaces it.
@export_range(1, 4) var hearts: int = 1

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
	grant(get_tree() if is_inside_tree() else null, player, heart_id, hearts, at, _heart_icon())


## Grants the Goo Heart `id` (`count` hearts' worth) to `player` as its pickup does: the flag
## "goo-heart.<id>", max HP + `gooHeart.maxHpBonus` each (HP full), the cue, "+10 max HP" over `at`
## and the ceremony (`ceremony_delay_s` of real time later: a chest's heart rises first). False (and
## nothing given) when the flag is already set. Also used by chests that hold a heart (chest.gd).
static func grant(tree: SceneTree, player: Node, id: String, count: int, at: Vector2, icon: Texture2D, ceremony_delay_s: float = 0.0) -> bool:
	var run := Services.run()
	if run == null or id.is_empty() or id == UNASSIGNED or run.has_flag(FLAG_PREFIX + id):
		return false
	run.set_flag(FLAG_PREFIX + id)
	for i in maxi(1, count):
		player.call(&"grant_goo_heart")
	var constants := Services.constants()
	var bonus := (constants.integer("character.player.gooHeart.maxHpBonus") if constants != null else 0) * maxi(1, count)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE)
		if tree == null or ceremony_delay_s <= 0.0:
			feel.floating_text(at - Vector2(0.0, TEXT_RISE), "+%d max HP" % bonus, &"green", true, TEXT_MS)
		else:
			var player_ref: WeakRef = weakref(player)
			tree.create_timer(ceremony_delay_s, true, false, true).timeout.connect(func() -> void:
				if player_ref.get_ref() != null:
					var current_feel := Services.feel()
					if current_feel != null:
						current_feel.floating_text(at - Vector2(0.0, TEXT_RISE), "+%d max HP" % bonus, &"green", true, TEXT_MS))
	if tree != null and AbilityCeremony.enabled(tree):
		if ceremony_delay_s <= 0.0:
			AbilityCeremony.request_heart(tree, bonus, icon)
		else:
			tree.create_timer(ceremony_delay_s, true, false, true).timeout.connect(
				func() -> void: AbilityCeremony.request_heart(tree, bonus, icon))
	return true


## True when the Goo Heart `id` was taken (its flag is set).
static func is_heart_taken(id: String) -> bool:
	var run := Services.run()
	return run != null and run.has_flag(FLAG_PREFIX + id)


## The Goo Heart's picture (the gulp props sheet's heart, as the pickup's scene shows it).
static func default_icon() -> Texture2D:
	var sheet := load(HEART_SHEET) as Texture2D
	if sheet == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = sheet
	icon.region = HEART_REGION
	return icon


## The heart's first frame, for the ceremony's bubble.
func _heart_icon() -> Texture2D:
	if visual == null or visual.texture == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = visual.texture
	var frame := visual.texture.get_size() / Vector2(maxi(1, visual.hframes), maxi(1, visual.vframes))
	icon.region = Rect2(Vector2.ZERO, frame)
	return icon

extends Node2D
class_name EnragedLook
## A boss's rage once his dungeon's Pearl is taken (docs/godot/DUNGEONS.md "The seal"; the plan
## docs/design/2026-10-17-pearl-mid-dungeon.md "Enraged, same strength"): presentation only, his
## numbers stay the built ones. The Dungeon node (game/dungeon/dungeon.gd) attaches it when his
## fight starts while the dungeon is sealed (`attach`):
##
## - a slow red pulse over his art: every big Sprite2D of his body (his `visual`, his pose sprites)
##   gets an added copy of its frame in the rage's `tint` (the Dungeon's `seal_color`), its alpha
##   swelling and fading over `dungeon.enraged.pulseMs` up to `strength`;
## - puffs of steam or dust from his top every `puffEveryMs`;
## - his name on the boss bar in red (game/ui/boss_health_bar.gd reads the meta `enraged_look` on
##   the boss's script).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const SELF_PATH := "res://game/bosses/enraged_look.gd"
const NODE_NAME := "EnragedLook"
## Set on the boss's script and body: the boss bar shows his name in red.
const META := &"enraged_look"
## Sprites smaller than this (a frame's longest side, px) are not his art (shadows, marks).
const MIN_FRAME_PX := 96.0
const OVERLAY_NAME := "EnragedGlow"
const PUFF := &"dodge-dust"

## The rage's colour (the boss's: the Dungeon's `seal_color`).
var tint: Color = Color("#d4482e")

var _body: Node2D
var _clock := 0.0
var _next_puff_ms := 0.0
var _overlays: Dictionary = {}
var _material: CanvasItemMaterial


## Attaches the rage to `boss` (his EnemyScript or his body) once; returns it.
static func attach(boss: Node, color: Color) -> Node2D:
	if boss == null or not is_instance_valid(boss):
		return null
	var body := _body_of(boss)
	if body == null:
		return null
	var existing := body.get_node_or_null(NODE_NAME) as Node2D
	if existing != null:
		existing.set(&"tint", color)
		return existing
	var look := (load(SELF_PATH) as GDScript).new() as Node2D
	look.name = NODE_NAME
	look.set(&"tint", color)
	body.add_child(look)
	boss.set_meta(META, true)
	body.set_meta(META, true)
	return look


## True when `boss` (his script or body) shows his rage.
static func is_on(boss: Object) -> bool:
	return boss != null and is_instance_valid(boss) and boss.has_meta(META)


## His body: the script's parent when the script is a plain Node (EnemyScript), else itself.
static func _body_of(boss: Node) -> Node2D:
	if boss is Node2D:
		return boss as Node2D
	return boss.get_parent() as Node2D


func _ready() -> void:
	_body = get_parent() as Node2D
	_material = CanvasItemMaterial.new()
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func _exit_tree() -> void:
	for overlay: Variant in _overlays.values():
		if is_instance_valid(overlay):
			(overlay as Node).queue_free()
	_overlays.clear()


func _process(delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	_clock += delta
	var period := maxf(0.05, DungeonState.number("enraged.pulseMs", 1600.0) / 1000.0)
	var swell := 0.5 - 0.5 * cos(_clock * TAU / period)
	var strength := DungeonState.number("enraged.strength", 0.45)
	var alpha := strength * (0.35 + 0.65 * swell)
	for sprite: Sprite2D in _art():
		var overlay := _overlay_for(sprite)
		_mirror(sprite, overlay)
		overlay.modulate = Color(tint.r, tint.g, tint.b, alpha)
	var now := float(Time.get_ticks_msec())
	if now >= _next_puff_ms:
		_next_puff_ms = now + DungeonState.number("enraged.puffEveryMs", 900.0)
		_puff()


## His art: the big Sprite2Ds under his body (not this look's own copies).
func _art() -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for node: Node in _body.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if sprite.name == OVERLAY_NAME or sprite.texture == null:
			continue
		var frame := sprite.texture.get_size() / Vector2(maxi(1, sprite.hframes), maxi(1, sprite.vframes))
		if sprite.region_enabled:
			frame = sprite.region_rect.size
		if maxf(frame.x, frame.y) < MIN_FRAME_PX:
			continue
		out.append(sprite)
	return out


func _overlay_for(sprite: Sprite2D) -> Sprite2D:
	var id := sprite.get_instance_id()
	var overlay: Sprite2D = _overlays.get(id)
	if overlay != null and is_instance_valid(overlay):
		return overlay
	overlay = Sprite2D.new()
	overlay.name = OVERLAY_NAME
	overlay.material = _material
	overlay.show_behind_parent = false
	sprite.add_child(overlay)
	_overlays[id] = overlay
	return overlay


## The copy shows the sprite's frame exactly where the sprite draws it (it is the sprite's child:
## its position, scale, rotation and skew follow, and its alpha fades with it).
static func _mirror(sprite: Sprite2D, overlay: Sprite2D) -> void:
	overlay.texture = sprite.texture
	overlay.hframes = sprite.hframes
	overlay.vframes = sprite.vframes
	overlay.frame = sprite.frame
	overlay.centered = sprite.centered
	overlay.offset = sprite.offset
	overlay.flip_h = sprite.flip_h
	overlay.flip_v = sprite.flip_v
	overlay.region_enabled = sprite.region_enabled
	overlay.region_rect = sprite.region_rect
	overlay.visible = sprite.visible


## A puff of steam or dust from his top.
func _puff() -> void:
	var feel := Services.feel()
	if feel == null:
		return
	feel.particles(PUFF, _body.global_position - Vector2(randf_range(-24.0, 24.0), DungeonState.number("enraged.puffRisePx", 110.0)))

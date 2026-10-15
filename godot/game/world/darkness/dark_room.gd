@tool
extends Node2D
## A dark room (bomb-lantern-and-secrets design section 2; docs/godot/DARKNESS.md): placed in a world
## scene, it darkens the rectangle `size` from its position (drawn as an outline in the editor) with
## ONE shader overlay (dark_room.gdshader) that has a soft hole around every light source near it,
## no 2D lights (too slow on WebGL 2 with the Compatibility renderer).
##
## - **Light sources**: nodes in group `light_sources` with `light_circle() -> Vector3` (global x,
##   global y, radius; <= 0 is off; game/world/fire/fire_targets.gd): the slime with the Lantern
##   learned (lantern_glow.gd), lit candles, flames in flight, the Goo Bomb's bombs and blasts. The
##   `abilities.lantern.darkness.maxLights` nearest to the slime (16) that reach the room are drawn.
## - **The darkness**: `abilities.lantern.darkness.alpha` (0.92) where no light reaches, a soft
##   edge of `softPx` inside each light's radius.
## - **Lit by its candles**: while every candle in `candles` burns, the room fades to lit over
##   `litFadeMs`; when one goes out (candles burn 60 s by default, candle.gd) it fades dark again.
## - **Lit for good** (`lit_for_good_when_all_lit`, off by default): once all its candles burn, it
##   stays lit and keeps them lit: the story flag `lit_flag` (default
##   `dark-room-lit.<persistence key or path>`).
## - The slime glows (its ember shows, its light circle is on) only inside a dark room that is
##   still dark (`is_dark_at`).
##
## Owner: world (fire and darkness).

const Services := preload("res://game/shared/services.gd")
const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const LanternGlow := preload("res://game/player/abilities/lantern_glow.gd")
const SHADER := preload("res://game/world/darkness/dark_room.gdshader")

const GROUP := &"dark_rooms"
const FLAG_PREFIX := "dark-room-lit."
const PERSISTENCE_KEY_META := &"persistence_key"
const INSTANCE_ID_META := &"instance_id"
## Above every sprite of the world (thrown things 5, flames 6), below the ability effects over the
## world (50) and the particles (100); the HUD is a CanvasLayer above it all.
const OVERLAY_Z := 45
const SHADER_MAX_LIGHTS := 16
## The editor outline.
const OUTLINE_COLOR := Color(0.55, 0.35, 1.0, 0.9)
const FILL_COLOR := Color(0.05, 0.03, 0.12, 0.25)

## The darkened rectangle's size from this node's position (px).
@export var size: Vector2 = Vector2(512, 384):
	set(value):
		size = value
		queue_redraw()
		_fit_overlay()
## The candles that light the room for good when they all burn (none: it never lights).
@export var candles: Array[NodePath] = []
## Once all its candles burn, the room stays lit for good (saved) and keeps them lit.
@export var lit_for_good_when_all_lit: bool = false
## The story flag a room lit for good sets ("" = `dark-room-lit.<key>`).
@export var lit_flag: String = ""

var _overlay: ColorRect
var _material: ShaderMaterial
var _lit: bool = false
var _for_good: bool = false
var _fade: float = 1.0
var _last_ms: float = -1.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	var run := Services.run()
	_for_good = lit_for_good_when_all_lit and run != null and run.has_flag(room_flag())
	_lit = _for_good
	_fade = 0.0 if _lit else 1.0
	if _for_good:
		_light_candles_for_good()
		return
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_overlay = ColorRect.new()
	_overlay.name = "Darkness"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = _material
	_overlay.color = Color.WHITE
	_overlay.z_index = OVERLAY_Z
	_overlay.z_as_relative = false
	add_child(_overlay)
	_fit_overlay()
	_material.set_shader_parameter(&"darkness", FireTargets.lantern_number("darkness.alpha", 0.92))
	_material.set_shader_parameter(&"soft_px", FireTargets.lantern_number("darkness.softPx", 40.0))


## The room's rectangle in global coordinates.
func rect() -> Rect2:
	return Rect2(global_position, size)


## True while the room is dark (its candles do not all burn, and it is not lit for good).
func is_dark() -> bool:
	return not _lit


## True when the global `point` lies in a dark room that is still dark.
static func is_dark_at(tree: SceneTree, point: Vector2) -> bool:
	if tree == null:
		return false
	for room: Node in tree.get_nodes_in_group(GROUP):
		if room.has_method(&"rect") and bool(room.call(&"is_dark")) and (room.call(&"rect") as Rect2).has_point(point):
			return true
	return false


## The story flag of a lit room.
func room_flag() -> String:
	if not lit_flag.is_empty():
		return lit_flag
	var node: Node = self
	while node != null:
		var key: Variant = node.get_meta(PERSISTENCE_KEY_META, "")
		if key is String and not (key as String).is_empty():
			return FLAG_PREFIX + key
		var instance_id: Variant = node.get_meta(INSTANCE_ID_META, "")
		if instance_id is String and not (instance_id as String).is_empty():
			return FLAG_PREFIX + instance_id
		node = node.get_parent()
	return FLAG_PREFIX + str(get_path())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _overlay == null:
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player != null and is_instance_valid(player):
		LanternGlow.ensure(player)
	var all_lit := _all_candles_lit()
	if all_lit and lit_for_good_when_all_lit and not _for_good:
		_light_for_good()
	if all_lit != _lit and not _for_good:
		_lit = all_lit
		_cue_change()
	_lit = _lit or _for_good
	var now := Services.now_ms()
	var step := now - _last_ms if _last_ms >= 0.0 else 0.0
	_last_ms = now
	var fade_ms := maxf(1.0, FireTargets.lantern_number("darkness.litFadeMs", 1500.0))
	_fade = move_toward(_fade, 0.0 if _lit else 1.0, step / fade_ms)
	if _for_good and _fade <= 0.0:
		_overlay.queue_free()
		_overlay = null
		return
	_overlay.visible = _fade > 0.0
	_material.set_shader_parameter(&"fade", _fade)
	_push_lights(player)


## The nearest light sources that reach the room, in the overlay's local pixels.
func _push_lights(player: Node) -> void:
	var area := rect()
	var focus := area.get_center()
	if player != null and is_instance_valid(player) and player.has_method(&"get_centre"):
		focus = player.call(&"get_centre")
	var found: Array[Vector4] = []
	for node: Node in get_tree().get_nodes_in_group(FireTargets.LIGHT_GROUP):
		if not node.has_method(&"light_circle"):
			continue
		var circle: Variant = node.call(&"light_circle")
		if not (circle is Vector3):
			continue
		var light := circle as Vector3
		if light.z <= 0.0:
			continue
		var at := Vector2(light.x, light.y)
		if not area.grow(light.z).has_point(at):
			continue
		found.append(Vector4(at.x, at.y, light.z, at.distance_squared_to(focus)))
	found.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w < b.w)
	var cap := mini(SHADER_MAX_LIGHTS, int(FireTargets.lantern_number("darkness.maxLights", SHADER_MAX_LIGHTS)))
	var lights := PackedVector4Array()
	var origin := global_position
	for i in mini(cap, found.size()):
		lights.append(Vector4(found[i].x - origin.x, found[i].y - origin.y, found[i].z, 0.0))
	var count := lights.size()
	while lights.size() < SHADER_MAX_LIGHTS:
		lights.append(Vector4.ZERO)
	_material.set_shader_parameter(&"lights", lights)
	_material.set_shader_parameter(&"light_count", count)


func _all_candles_lit() -> bool:
	if candles.is_empty():
		return false
	for path in candles:
		var candle := get_node_or_null(path)
		if candle == null or not candle.has_method(&"is_lit") or not bool(candle.call(&"is_lit")):
			return false
	return true


## Every candle burns in a room set to stay lit: lit for good (saved), its candles kept lit.
func _light_for_good() -> void:
	_for_good = true
	var run := Services.run()
	if run != null:
		run.set_flag(room_flag())
	_light_candles_for_good()


## The room turned lit (its candles all burn) or dark again (one went out).
func _cue_change() -> void:
	var feel := Services.feel()
	if feel != null and _lit:
		feel.audio_cue(&"GateOpen")


func _light_candles_for_good() -> void:
	for path in candles:
		var candle := get_node_or_null(path)
		if candle != null and candle.has_method(&"keep_lit"):
			candle.call(&"keep_lit")


func _fit_overlay() -> void:
	if _overlay == null:
		return
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	if _material != null:
		_material.set_shader_parameter(&"size", size)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(Vector2.ZERO, size), FILL_COLOR, true)
	draw_rect(Rect2(Vector2.ZERO, size), OUTLINE_COLOR, false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(8, 22), "Dark room", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, OUTLINE_COLOR)

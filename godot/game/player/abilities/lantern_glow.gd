extends Node2D
## The Lantern's ember inside the slime (bomb-lantern-and-secrets design section 2; BODY_SHAPES.md
## "The Lantern"): once the Lantern is learned, inside a dark room that is still dark
## (DarkRoom.is_dark_at) a warm ember shows through the slime's jelly and the slime is a light
## source of `abilities.lantern.glow.radiusPx` (160 px, flickering a little). Outside dark rooms
## nothing shows, but every flame thrown flares the ember for `glow.flareMs` (`flare`).
##
## The ember is a child of the slime's Visual (so it squashes, rises and hides with the body),
## scaled back to world pixels: an additive soft glow and the flame art small, pointing up. It is
## made on demand (`ensure`) by a dark room near the slime or by the Lantern's use, and lives as long
## as the player does. The flicker and the flare are presentation (real time).
##
## Owner: abilities.

const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

const NODE_NAME := &"LanternEmber"
## The dark rooms' group (game/world/darkness/dark_room.gd).
const DARK_ROOM_GROUP := &"dark_rooms"
const LANTERN := &"lantern"
const FLAME_SHEET := preload("res://asset/abilities/lantern/flame-4x1.webp")
const FLAME_FRAMES := 4
const FLAME_FRAME_MS := 85.0
## Where the ember sits in the body: world px from the Visual's origin (the old centre).
const EMBER_AT := Vector2(0.0, 9.0)
## The glow's and the small flame's sizes (world px) and colours.
const GLOW_PX := 30.0
const GLOW_COLOR := Color(1.0, 0.55, 0.15, 0.7)
const HALO_PX := 64.0
const HALO_COLOR := Color(1.0, 0.45, 0.1, 0.12)
const FLAME_SCALE := 0.24
const FLAME_ALPHA := 0.78
## How bright a flare gets over the dark-room glow, and how fast the glow follows the room.
const FLARE_BOOST := 0.7
const FOLLOW_PER_S := 5.0

var _player: Node
var _visual: Sprite2D
var _rest_offset: Vector2 = Vector2.ZERO
var _glow: Sprite2D
var _halo: Sprite2D
var _flame: Sprite2D
var _level: float = 0.0
var _flare_at_ms: float = -100000.0
var _seed: float = 0.0


## The ember of `player`, made under its Visual the first time; null without a Visual.
static func ensure(player: Node) -> Node2D:
	if player == null or not is_instance_valid(player) or not player.has_method(&"get_visual"):
		return null
	var visual := player.call(&"get_visual") as Sprite2D
	if visual == null:
		return null
	var existing := visual.get_node_or_null(NodePath(String(NODE_NAME))) as Node2D
	if existing != null:
		return existing
	var ember := (load("res://game/player/abilities/lantern_glow.gd") as GDScript).new() as Node2D
	ember.name = NODE_NAME
	ember.call(&"_setup", player, visual)
	visual.add_child(ember)
	return ember


## Flares the ember (a flame thrown), in or out of a dark room.
func flare() -> void:
	_flare_at_ms = float(Time.get_ticks_msec())


## Light source: the slime's centre and its glow, while it glows in a dark room.
func light_circle() -> Vector3:
	if _player == null or not is_instance_valid(_player) or _level <= 0.01:
		return Vector3.ZERO
	var at: Vector2 = _player.call(&"get_centre")
	var radius := FireTargets.lantern_number("glow.radiusPx", 160.0)
	return Vector3(at.x, at.y, FireTargets.flicker(radius, _seed) * clampf(_level, 0.0, 1.0))


func _setup(player: Node, visual: Sprite2D) -> void:
	_player = player
	_visual = visual
	_rest_offset = visual.offset
	_seed = randf() * 100.0
	var back := 1.0 / maxf(0.001, absf(visual.scale.x))
	scale = Vector2.ONE * back
	add_to_group(FireTargets.LIGHT_GROUP)
	_halo = _glow_sprite(HALO_PX, HALO_COLOR)
	_glow = _glow_sprite(GLOW_PX, GLOW_COLOR)
	_flame = Sprite2D.new()
	_flame.texture = FLAME_SHEET
	_flame.hframes = FLAME_FRAMES
	_flame.rotation = PI / 2.0
	_flame.offset = Vector2(-24.0, 0.0)
	_flame.scale = Vector2.ONE * FLAME_SCALE
	add_child(_flame)
	visible = false


func _glow_sprite(px: float, color: Color) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = FireFx.glow_texture()
	sprite.material = FireFx.additive()
	sprite.modulate = color
	sprite.scale = Vector2.ONE * (px / 128.0)
	add_child(sprite)
	return sprite


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _visual == null:
		return
	var learned := bool(_player.call(&"is_learned", LANTERN))
	var in_dark := learned and _in_dark_room(_player.call(&"get_centre"))
	var target := 1.0 if in_dark else 0.0
	_level = move_toward(_level, target, FOLLOW_PER_S * delta)
	var flare_ms := FireTargets.lantern_number("glow.flareMs", 260.0)
	var since := float(Time.get_ticks_msec()) - _flare_at_ms
	var flare := 0.0 if since >= flare_ms else 1.0 - since / flare_ms
	var show := maxf(_level, 0.0) + flare * FLARE_BOOST
	visible = show > 0.01
	if not visible:
		return
	# Follow the art's keyed offset (a clip that moves the drawing moves the ember with it).
	position = (_visual.offset - _rest_offset) + EMBER_AT * scale.x
	var breathe := FireTargets.flicker(1.0, _seed)
	_glow.modulate.a = GLOW_COLOR.a * clampf(show, 0.0, 1.0)
	_glow.scale = Vector2.ONE * (GLOW_PX / 128.0) * breathe * (1.0 + flare * 0.6)
	_halo.modulate.a = HALO_COLOR.a * clampf(show, 0.0, 1.0)
	_halo.scale = Vector2.ONE * (HALO_PX / 128.0) * breathe * (1.0 + flare * 0.4)
	_flame.modulate.a = FLAME_ALPHA * clampf(show, 0.0, 1.0)
	_flame.scale = Vector2.ONE * FLAME_SCALE * (1.0 + flare * 0.5)
	_flame.frame = int(float(Time.get_ticks_msec()) / FLAME_FRAME_MS) % FLAME_FRAMES


## True when `point` lies in a dark room that is still dark (DarkRoom.is_dark_at, without a preload
## cycle: the dark room preloads this script).
func _in_dark_room(point: Vector2) -> bool:
	for room: Node in get_tree().get_nodes_in_group(DARK_ROOM_GROUP):
		if room.has_method(&"rect") and bool(room.call(&"is_dark")) and (room.call(&"rect") as Rect2).has_point(point):
			return true
	return false

extends Node2D
## A boulder the Rock Chucker (game/scripts/rock_chucker.gd, docs/godot/BESTIARY.md "Rock Chucker")
## throws down a cliff's face (the owner, 2026-11-13: rocks "that come down bouncing on the walls
## from one side to the other"): it hops down the face from bounce to bounce, each bounce on the
## other side of its lane, and shatters at the wall's foot.
##
## The thrower sets the fields, adds it to the world's entities and calls `start()`. Each hop takes
## `hop_ms` of gameplay time (Services.now_ms(): it holds in hit-stop); the boulder bulges
## `arc_px` up from the straight line and grows by `swell` at the hop's middle (off the wall, toward
## the camera), spinning. Every bounce puffs dust and taps. While it flies, the slime's centre
## within `hit_px` of it takes a hit from the thrower (`thrower._route_hit_from`) and the boulder
## shatters there. It shatters harmless when its thrower is gone or beaten.
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const Hearing := preload("res://game/audio/hearing.gd")

const ROCK_PICTURE := "res://asset/MAPS/enemies/64x64-tile_2x1-climb-rock.webp"
const SHARDS_PICTURE := "res://asset/MAPS/enemies/128x128-climb-rock-shards.webp"
const CUE_BOUNCE := &"HeavyBlockBump"
const CUE_SHATTER := &"BreakStone"
const DUST := &"dodge-dust"
const SHARDS_MS := 420.0
const SHARDS_SCALE := 0.42

## The bounce points (world), the first where it leaves the thrower's hands, the last at the foot.
var points: PackedVector2Array = PackedVector2Array()
var hop_ms: float = 380.0
var arc_px: float = 34.0
var swell: float = 0.3
var spin_per_s: float = 1.6
var picture_scale: float = 0.8
var hit_px: float = 26.0
var damage: float = 14.0
var knockback: float = 220.0
## The enemy that threw it (its `_route_hit_from` lands the hit).
var thrower: Node = null

var _started_at: float = -1.0
var _shattered_at: float = -1.0
var _bounced: int = 0
var _sprite: Sprite2D


func start() -> void:
	_started_at = Services.now_ms()
	global_position = points[0] if not points.is_empty() else global_position
	_sprite = Sprite2D.new()
	_sprite.texture = SheetSprite.load_picture(ROCK_PICTURE)
	_sprite.hframes = 2
	_sprite.scale = Vector2.ONE * picture_scale
	add_child(_sprite)


func is_shattered() -> bool:
	return _shattered_at >= 0.0


func _physics_process(_delta: float) -> void:
	if _started_at < 0.0:
		return
	var now := Services.now_ms()
	if _shattered_at >= 0.0:
		var since := now - _shattered_at
		modulate.a = clampf(1.0 - since / SHARDS_MS, 0.0, 1.0)
		if since >= SHARDS_MS:
			queue_free()
		return
	if points.size() < 2 or not _thrower_live():
		_shatter(now)
		return
	var hops := points.size() - 1
	var flown := (now - _started_at) / maxf(1.0, hop_ms)
	var hop := mini(int(flown), hops - 1)
	var t := clampf(flown - float(hop), 0.0, 1.0)
	if hop > _bounced:
		_bounced = hop
		_bounce(points[hop])
	var bulge := sin(PI * t)
	global_position = points[hop].lerp(points[hop + 1], t) - Vector2(0.0, bulge * arc_px)
	_sprite.scale = Vector2.ONE * picture_scale * (1.0 + swell * bulge)
	_sprite.rotation = TAU * spin_per_s * (now - _started_at) / 1000.0
	_sprite.frame = hop % 2
	if _hits_slime():
		_shatter(now)
		return
	if flown >= float(hops):
		global_position = points[hops]
		_bounce(points[hops])
		_shatter(now)


func _thrower_live() -> bool:
	return thrower != null and is_instance_valid(thrower) and not bool(thrower.call(&"is_defeated"))


## The slime's centre near the boulder: a hit from its thrower, from here, knocking it down the face.
func _hits_slime() -> bool:
	var world := Services.world()
	var target: Dictionary = world.primary_target() if world != null else {}
	var centre: Variant = target.get("centre")
	if not centre is Vector2 or (centre as Vector2).distance_to(global_position) > hit_px:
		return false
	thrower.call(&"_route_hit_from", global_position, target, damage, knockback, Vector2.DOWN)
	return true


func _bounce(at: Vector2) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.particles(DUST, at)
		if Hearing.heard(at):
			feel.audio_cue(CUE_BOUNCE)


## It breaks into shards that fade where it is.
func _shatter(now: float) -> void:
	_shattered_at = now
	if _sprite != null:
		_sprite.texture = SheetSprite.load_picture(SHARDS_PICTURE)
		_sprite.hframes = 1
		_sprite.frame = 0
		_sprite.rotation = 0.0
		_sprite.scale = Vector2.ONE * SHARDS_SCALE
	var feel := Services.feel()
	if feel != null:
		feel.particles(DUST, global_position)
		if Hearing.heard(global_position):
			feel.audio_cue(CUE_SHATTER)

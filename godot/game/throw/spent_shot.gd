extends Node2D
## A spent enemy shot lying on the ground (throw-combat experiment, docs/godot/THROW_COMBAT.md;
## owner, 2026-10-19: "enemies whose attacks bounce and stay on the floor make ammo"). An arrow
## that missed (game/scripts/projectile.gd `expire`) lands here and stays for `life_ms`: the Gulp
## sucks it in like a pot (the mouth's `suckable` contract: `origin`, `can_take`, `suck_info`,
## `take`) and throws it back; its kind picks its effect (`gulp.throwCombat.kindEffects`: an arrow
## pierces). Its last `FADE_MS` it fades, then it is gone. It goes with the world.
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const SUCKABLE_GROUP := &"suckable"
const SELF_PATH := "res://game/throw/spent_shot.gd"
const FADE_MS := 1500.0
## It lies this far under where the shot flew (the shot flies at the shooter's middle height).
const DROP_PX := 10.0

var kind: String = ""
var shot_material: String = "wood"
var texture_path: String = ""
var art_px: float = 64.0
var _until_ms: float = 0.0
var _taken := false
var _sprite: Sprite2D


## Lays a spent shot under `parent` at `at` (where the shot ended), its picture `path` (`picture_px`
## across, drawn at `scale_by`, turned `angle`), for `life_ms` of gameplay time. Returns it, or null.
static func spawn(parent: Node, at: Vector2, path: String, picture_px: float, scale_by: float, angle: float,
		shot_kind: String, material_name: String, life_ms: float) -> Node2D:
	if parent == null or not is_instance_valid(parent) or path.is_empty():
		return null
	var shot := (load(SELF_PATH) as GDScript).new() as Node2D
	shot.name = "SpentShot"
	shot.call(&"setup", path, picture_px, scale_by, angle, shot_kind, material_name, life_ms)
	parent.add_child(shot)
	shot.global_position = at + Vector2(0.0, DROP_PX)
	return shot


func setup(path: String, picture_px: float, scale_by: float, angle: float, shot_kind: String,
		shot_material_arg: String, life_ms: float) -> void:
	texture_path = path
	art_px = picture_px
	kind = shot_kind
	shot_material = shot_material_arg
	_until_ms = Services.now_ms() + life_ms
	_sprite = Sprite2D.new()
	_sprite.name = "Visual"
	_sprite.texture = SheetSprite.load_picture(path)
	_sprite.scale = Vector2.ONE * scale_by
	_sprite.rotation = angle
	_sprite.position = Vector2(0.0, -4.0)
	add_child(_sprite)


func _enter_tree() -> void:
	add_to_group(SUCKABLE_GROUP)


func _process(_delta: float) -> void:
	var left := _until_ms - Services.now_ms()
	if left <= 0.0:
		queue_free()
		return
	modulate.a = clampf(left / FADE_MS, 0.0, 1.0)


func origin() -> Vector2:
	return global_position


func can_take() -> bool:
	return not _taken and is_inside_tree() and not is_queued_for_deletion()


func suck_info() -> Dictionary:
	return {"kind": kind, "essence": "", "variant": 0, "texture": texture_path, "art_px": art_px,
		"material": shot_material}


## Sucked in: it leaves the world.
func take() -> void:
	_taken = true
	remove_from_group(SUCKABLE_GROUP)
	queue_free()

extends Node2D
## The Dung Roller's ball as a thing the Gulp takes (owner, 2026-11-21: "you can suck the dung and
## they get furious and charge at you. The dung is a throwable: you can throw it at him or at other
## monsters. If you throw it at nothing, the ball stays and the beetle forgets about you and goes for
## it"; docs/godot/BESTIARY.md "Dung Roller"; game/scripts/dung_roller.gd). As the skull on a bone
## pile (bone_skull.gd), it is in the mouth's `suckable` group (game/player/gulp/mouth.gd) and brings
## its own picture, so the mouth, the held look and the throw are the ones every pot uses.
##
## One script, two places:
## - **On its roller** (`ride`): a child of the roller's body, drawing nothing (the roller's scene
##   draws the ball it pushes); takeable while the roller says so (`set_takeable`).
## - **Lying on the ground** (`lay`): under the world's entities root, drawing the ball, in the group
##   GROUP; it is there until it is sucked in again, its roller takes it back, or the world is built
##   again. It blocks nothing.
##
## Taken (`take`), the mouth holds {"kind": KIND, "texture", "hframes", "frame", "art_px",
## "material", ROLLER_KEY: its roller's instance id} (held_look.gd) and its roller is told
## (`ball_taken`). What happens to it afterwards is told through the static calls below, by the ones
## that end a held thing: the throw (thrown_object.gd `_finish`: a blow that hurt something breaks
## it, `broke`; anything else leaves it lying where it came down, `lay`) and a hit on the slime
## (mouth.gd `drop`: it falls whole behind the slime, `lay`). Its throw's hit carries the tags
## `thrown` and KIND.
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const SUCKABLE_GROUP := &"suckable"
## Every ball lying on the ground.
const GROUP := &"dung-ball"
## The held kind and the tag its throw carries.
const KIND := "dung-ball"
## It breaks as a soft thing (a splat, `BreakSoft`).
const MATERIAL := "soft"
## The held Dictionary's key of its roller's instance id.
const ROLLER_KEY := "roller"
const SELF_PATH := "res://game/enemy/dung_ball.gd"
## The lying ball's look: its landing squash (presentation, real time).
const LAND_SQUASH := Vector2(1.2, 0.78)
const LAND_SECONDS := 0.22
const DUST := &"dodge-dust"
const CUE_LAND := &"Land"

## Its roller (game/scripts/dung_roller.gd), by instance id (0: none, a ball of nobody).
var roller_id: int = 0
## Its picture: the sheet, its columns, the ball's frame, the ball's drawn width in a frame (px) and
## the width it is drawn on the ground (px).
var sheet_path: String = ""
var sheet_hframes: int = 1
var sheet_frame: int = 0
var art_px: float = 64.0
var ground_px: float = 46.0
var _takeable: bool = false
var _lying: bool = false


# --- made by the roller, and by what ends a held ball ------------------------------------------------

## The ball on its roller: a child of `body`, takeable when the roller says so.
static func ride(body: Node2D, roller: Node, picture: Dictionary) -> Node2D:
	var ball := (load(SELF_PATH) as GDScript).new() as Node2D
	ball.name = "DungBall"
	ball.call(&"_setup", roller.get_instance_id(), picture)
	if body.is_node_ready():
		body.add_child(ball)
	else:
		body.add_child.call_deferred(ball)
	return ball


## True when `held` (the mouth's) is a dung ball.
static func is_ball(held: Dictionary) -> bool:
	return str(held.get("kind", "")) == KIND


## The roller `held` belongs to (its script), or null when it is gone.
static func roller_of(held: Dictionary) -> Node:
	var id: Variant = held.get(ROLLER_KEY)
	if not (id is int or id is float) or not is_instance_id_valid(int(id)):
		return null
	var roller := instance_from_id(int(id)) as Node
	return roller if roller != null and roller.has_method(&"ball_taken") else null


## The ball of `held` lies whole on the ground point `spot` under `parent` from now on; its roller is
## told (`ball_lies`). Returns it (null when it cannot be made).
static func lay(parent: Node, spot: Vector2, held: Dictionary) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		broke(held)
		return null
	var ball := (load(SELF_PATH) as GDScript).new() as Node2D
	ball.name = "DungBallLying"
	var roller := roller_of(held)
	ball.call(&"_setup", roller.get_instance_id() if roller != null else 0, {
		"texture": str(held.get("texture", "")), "hframes": int(held.get("hframes", 1)),
		"frame": int(held.get("frame", 0)), "art_px": float(held.get("art_px", 64.0)),
		"ground_px": float(held.get("ground_px", 46.0)),
	})
	ball.call(&"_lie")
	parent.add_child(ball)
	ball.global_position = spot
	ball.reset_physics_interpolation()
	var feel := Services.feel()
	if feel != null:
		feel.particles(DUST, spot)
		feel.audio_cue(CUE_LAND)
	if roller != null:
		roller.call(&"ball_lies", ball)
	return ball


## The ball of `held` is no more (it broke on something); its roller is told (`ball_broke`).
static func broke(held: Dictionary) -> void:
	var roller := roller_of(held)
	if roller != null:
		roller.call(&"ball_broke")


func _setup(roller: int, picture: Dictionary) -> void:
	roller_id = roller
	sheet_path = str(picture.get("texture", ""))
	sheet_hframes = maxi(1, int(picture.get("hframes", 1)))
	sheet_frame = int(picture.get("frame", 0))
	art_px = maxf(1.0, float(picture.get("art_px", 64.0)))
	ground_px = maxf(1.0, float(picture.get("ground_px", 46.0)))


## It lies on the ground: its own picture (its foot on the node), takeable.
func _lie() -> void:
	_lying = true
	_takeable = true
	y_sort_enabled = false
	var sprite := Sprite2D.new()
	sprite.name = "Visual"
	sprite.texture = SheetSprite.load_picture(sheet_path)
	sprite.hframes = sheet_hframes
	sprite.frame = clampi(sheet_frame, 0, sheet_hframes - 1)
	sprite.centered = true
	var size := ground_px / art_px
	sprite.scale = Vector2.ONE * size
	sprite.position = Vector2(0.0, -ground_px * 0.5)
	add_child(sprite)
	# It lands with a squash (presentation).
	sprite.scale = Vector2.ONE * size * LAND_SQUASH
	var tween := sprite.create_tween()
	tween.tween_property(sprite, ^"scale", Vector2.ONE * size, LAND_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _enter_tree() -> void:
	add_to_group(SUCKABLE_GROUP)
	if _lying:
		add_to_group(GROUP)


## The roller's switch while the ball is on it (a lying ball is always takeable).
func set_takeable(on: bool) -> void:
	_takeable = on


func is_lying() -> bool:
	return _lying


## Its roller took it back (dung_roller.gd): the lying ball goes.
func picked_up() -> void:
	_takeable = false
	if is_in_group(SUCKABLE_GROUP):
		remove_from_group(SUCKABLE_GROUP)
	queue_free()


# --- the mouth's suckable contract (game/player/gulp/mouth.gd) -------------------------------------

## The ground point under it: the roller's root (the ball stands on it), or where it lies.
func origin() -> Vector2:
	if _lying:
		return global_position
	var body := get_parent() as Node2D
	return body.global_position if body != null else global_position


func can_take() -> bool:
	return _takeable and is_inside_tree() and not is_queued_for_deletion()


func suck_info() -> Dictionary:
	return {"kind": KIND, "essence": "", "variant": 0, "texture": sheet_path, "hframes": sheet_hframes,
		"frame": sheet_frame, "art_px": art_px, "ground_px": ground_px, "material": MATERIAL,
		ROLLER_KEY: roller_id}


## Sucked in: its roller is told; a lying ball leaves the world.
func take() -> void:
	if not _takeable:
		return
	_takeable = false
	var roller := instance_from_id(roller_id) as Node if roller_id != 0 and is_instance_id_valid(roller_id) else null
	if roller != null and roller.has_method(&"ball_taken"):
		roller.call(&"ball_taken")
	if _lying:
		remove_from_group(SUCKABLE_GROUP)
		queue_free()

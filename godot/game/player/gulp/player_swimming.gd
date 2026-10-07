extends RefCounted
## Swimming (owner, 2026-10-06; abilities spec 11.7). A Gulp form that `swims` (the Frog,
## game/player/gulp/gulp_forms.gd) lets the slime into deep water: without one, deep water blocks
## it (its tiles' collision on the `water` physics layer); with one, the slime's body stops
## colliding with that layer. In deep water the slime swims:
## - the swim clips (`swim-down`, `-up`, `-side`, page 3 of the slime sheet) replace idle and walk;
## - its art sinks under a waterline (form_skin.gdshader's `waterline`, the art lowered by as much,
##   so the waterline sits on its feet, where the water wake's swim ripple is);
## - it cannot attack or use abilities (game/scripts/player.gd drops those presses).
## The form does not wear off (or burp) while any part of the body is over deep water: it ends once
## the slime is out (game/player/gulp/gulp_controller.gd).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
## Physics layer "water" (project.godot layer_names/2d_physics/layer_11): deep water's tile collision.
const WATER_LAYER_BIT := 1 << 10
const TILE_ID_DATA_LAYER := "tile_id"
const DEEP_TILE_ID := "deep-water"
## Cell pixels of the slime's 256 px frames that stay above water: the eyes of the flattest swim
## frames sit about 50 px above the baseline.
const WATERLINE_PX := 30.0
## The feet cell is read this far up, inside the body (as the water wake does).
const FEET_PROBE := 2.0

var _player: Node
## True while the slime swims: a swimming form, its feet on deep water.
var swimming: bool = false


func _init(player: Node) -> void:
	_player = player


## Every physics step: the water layer in the body's mask, then whether the slime swims.
func update() -> void:
	var body := _body()
	if body == null:
		return
	if can_swim():
		body.collision_mask &= ~WATER_LAYER_BIT
	else:
		body.collision_mask |= WATER_LAYER_BIT
	var now_swimming := can_swim() and _deep_at(body.global_position - Vector2(0.0, FEET_PROBE))
	if now_swimming != swimming:
		swimming = now_swimming
		_apply_look()


## True when the current form swims.
func can_swim() -> bool:
	return bool((_player.call(&"current_form") as Dictionary).get("swims", false))


## True when any corner of the body's collision rectangle is over deep water (where it would be
## stuck if deep water blocked it again).
func overlaps_deep_water() -> bool:
	var body := _body()
	if body == null:
		return false
	var rect := _body_rect(body)
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		if _deep_at(corner):
			return true
	return false


func _apply_look() -> void:
	var visual := _player.call(&"get_visual") as Sprite2D
	if visual == null:
		return
	var material := visual.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"waterline", WATERLINE_PX if swimming else 0.0)
	_player.call(&"set_swim_offset", Vector2(0.0, WATERLINE_PX * absf(visual.scale.y)) if swimming else Vector2.ZERO)


func _deep_at(point: Vector2) -> bool:
	var world := Services.world()
	var ground: TileMapLayer = world.ground_layer if world != null else null
	if ground == null or not is_instance_valid(ground):
		return false
	var data := ground.get_cell_tile_data(ground.local_to_map(ground.to_local(point)))
	return data != null and str(data.get_custom_data(TILE_ID_DATA_LAYER)) == DEEP_TILE_ID


## The body's collision rectangle in world space, slightly inset (its first rectangle shape).
func _body_rect(body: CharacterBody2D) -> Rect2:
	for child: Node in body.get_children():
		var holder := child as CollisionShape2D
		if holder != null and holder.shape is RectangleShape2D:
			var size := (holder.shape as RectangleShape2D).size - Vector2(2.0, 2.0)
			return Rect2(holder.global_position - size * 0.5, size)
	return Rect2(body.global_position - Vector2(1.0, 2.0), Vector2(2.0, 2.0))


func _body() -> CharacterBody2D:
	return _player.get(&"body") as CharacterBody2D

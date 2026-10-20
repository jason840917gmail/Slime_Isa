@tool
extends Node2D
class_name PlacedEnemy
## A world enemy placed by hand (roadmap 5.25, owner 2026-10-16: the enemies of a world are "a
## fixed quantity placed ... in the map" with a wandering area, and "they come back when the player
## reloads a chunk, like in Zelda"). Drop res://game/scenes/encounters/placed-enemy.tscn into a world
## (the Scenery dock's **Enemies** category puts it under the world's `Enemies` node with its type
## set), pick its `enemy_type`, and give it a wander area: a camp's shared `enemy-wander` world area
## named by `wander_area_id`, or its own circle of `wander_radius` around where it stands.
##
## The node's position is where the enemy's feet (its scene root) stand when the world is built.
## In the game it draws nothing: EnemyPopulation (game/enemy/enemy_population.gd) spawns
## `character.<enemy_type>` there once per build of the world, with `overrides` set on its
## EnemyScript before it enters the tree and its camp territory from the wander area (enemy spec 3
## and 4.3: it wanders there, chases within its leash, searches, gives up and walks home healing).
## A beaten one stays beaten until the world is built again (the chunk entered again, a load, a
## door back out). In the editor it shows the enemy's picture, its type and its wander outline, and
## warns when the type or the wander area is unknown.
##
## **Facing** (owner, 2026-10-19): an enemy that faces one way (its EnemyScript has `aim_direction`:
## the Pipe Worm's pipe) faces the way this node is turned: rotate it with the editor's rotate tool,
## as a collision shape. Unturned it faces down; the facing snaps to the nearest of down, left, up
## and right (`facing()`), and the editor draws the half of the world it sees that way (its
## `targeting_radius`) with an arrow, the picture and the label staying upright. An `aim_direction`
## in `overrides` still wins over the rotation.
##
## Owner: enemy builder.

const Perimeter := preload("res://game/shared/perimeter.gd")
const WorldAreaScript := preload("res://game/scripts/world_area.gd")
const FourWayAim := preload("res://game/enemy/four_way_aim.gd")

## Every placed enemy joins this group (the population and the quest waypoint find them by it).
const GROUP := &"placed_enemy"
const ENEMY_TYPES_PATH := "res://game/data/enemy-types.json"
const SCENE_INDEX_PATH := "res://game/scenes/scene_index.json"
const SCENE_PREFIX := "character."
## The enemy scenes' sprite (the first Sprite2D when none has this name).
const VISUAL_NAME := "Visual"
## What a record of a wander circle of its own is called (EnemyScript.get_spawn_area()["kind"]).
const KIND_OWN_WANDER := "enemy-wander"
## Editor drawing: the wander outline (own circle, shared area), the picture's tint, the marker of
## an unknown type, the label.
const OWN_OUTLINE := Color(1.0, 0.55, 0.3, 0.85)
const SHARED_OUTLINE := Color(1.0, 0.8, 0.3, 0.75)
const MISSING := Color(1.0, 0.15, 0.55, 0.95)
const PICTURE_TINT := Color(1.0, 1.0, 1.0, 0.92)
const LABEL_COLOR := Color(1.0, 0.95, 0.85, 0.95)
const LABEL_SIZE := 12
const OUTLINE_WIDTH := 2.0
const MARKER_RADIUS := 10.0
## The EnemyScript property a facing enemy faces by (set from this node's rotation).
const FACING_PROPERTY := &"aim_direction"
## Editor drawing of a facing enemy's view: the half it sees and the arrow out.
const VIEW_FILL := Color(0.35, 0.75, 1.0, 0.12)
const VIEW_EDGE := Color(0.35, 0.75, 1.0, 0.8)
const VIEW_ARROW_PX := 56.0
const VIEW_ARROW_HEAD_PX := 12.0
const VIEW_SEGMENTS := 32
## Editor: how often a wander area name that found nothing is looked for again (ms).
const SEARCH_AGAIN_MS := 1000

## The `enemy-types.json` id; the enemy's scene is `character.<enemy_type>` (scene_index.json).
@export var enemy_type: String = "":
	set(value):
		enemy_type = value
		_changed()
## The `area_id` of the `enemy-wander` world area (world_area.gd) this enemy wanders in, shared by
## the enemies of a camp. Empty: it wanders within `wander_radius` of where it stands.
@export var wander_area_id: String = "":
	set(value):
		wander_area_id = value
		_shared_area = null
		_search_again_at = 0
		_changed()
## Its own wander circle's radius (world units), when it names no wander area.
@export_range(16.0, 2048.0, 1.0, "or_greater") var wander_radius: float = 160.0:
	set(value):
		wander_radius = value
		_changed()
## EnemyScript properties set before the enemy enters the tree, e.g. `{"max_health": 120,
## "attributes": {"leashRange": 700}}`: an `attributes` dictionary is merged into the scene's.
@export var overrides: Dictionary = {}

## The spawned EnemyScript (set by EnemyPopulation), null before.
var _enemy: Node = null
## Its wander perimeter (set by EnemyPopulation), {} before.
var _wander: Dictionary = {}
## Editor: the shared area's Area2D and the signature of its outline last drawn.
var _shared_area: Node = null
var _drawn_outline: Variant = null
var _search_again_at: int = 0

## Parsed enemy-types.json ids and scene_index.json, and each type's picture, read once.
static var _type_ids: PackedStringArray = PackedStringArray()
static var _scene_index: Dictionary = {}
static var _pictures: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint():
		set_notify_transform(true)
	queue_redraw()


## Editor: turned, its view and its upright picture are drawn again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()


## Editor only: redraws when the shared wander area moved or changed size.
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	var outline: Variant = _shared_outline()
	if outline != _drawn_outline:
		queue_redraw()


# --- the game (EnemyPopulation) -----------------------------------------------------------------

## The scene id of its enemy ("character.<enemy_type>").
func scene_id() -> String:
	return SCENE_PREFIX + enemy_type


## The record EnemyScript.configure_navigation gets: the `enemy-wander` area named by
## `wander_area_id` among `wander_areas` (WorldService.areas("enemy-wander")), else (and with a
## push_error when the name is unknown) its own circle of `wander_radius` around its feet:
## `{"id": "", "kind": "enemy-wander", "data": {}, "perimeter": circle, "stay_perimeter": circle}`.
func wander_record(wander_areas: Array[Dictionary]) -> Dictionary:
	if not wander_area_id.is_empty():
		for area: Dictionary in wander_areas:
			if str(area.get("id", "")) == wander_area_id:
				var record := area.duplicate()
				if not record.get("stay_perimeter") is Dictionary:
					record["stay_perimeter"] = record.get("perimeter", {})
				return record
		push_error("PlacedEnemy '%s': no enemy-wander area '%s'; it wanders around its spot" % [get_path(), wander_area_id])
	var circle := {"shape": Perimeter.SHAPE_CIRCLE, "x": Perimeter.js_round(global_position.x),
		"y": Perimeter.js_round(global_position.y), "radius": maxf(1.0, Perimeter.js_round(wander_radius))}
	return {"id": "", "kind": KIND_OWN_WANDER, "data": {}, "perimeter": circle, "stay_perimeter": circle}


## The way a facing enemy faces: down turned by this node's rotation, snapped to the nearest of
## down, left, up and right.
func facing() -> Vector2:
	var way := FourWayAim.snap(Vector2.DOWN.rotated(global_rotation))
	return way if way != Vector2.ZERO else Vector2.DOWN


## Sets the facing (`facing()`, on an enemy that has `aim_direction`) and then `overrides` on
## `enemy` (its EnemyScript, before it enters the tree). An unknown property is a push_error.
func apply_overrides(enemy: Node) -> void:
	if FACING_PROPERTY in enemy:
		enemy.set(FACING_PROPERTY, facing())
	for key: Variant in overrides:
		var property := str(key)
		if not property in enemy:
			push_error("PlacedEnemy '%s': the enemy has no property '%s'" % [get_path(), property])
			continue
		var value: Variant = overrides[key]
		if property == "attributes" and value is Dictionary and enemy.get(&"attributes") is Dictionary:
			var merged: Dictionary = (enemy.get(&"attributes") as Dictionary).duplicate(true)
			merged.merge(value as Dictionary, true)
			value = merged
		enemy.set(property, value)


## Called by EnemyPopulation once it spawned this enemy: its EnemyScript and wander perimeter.
func bind(enemy: Node, wander: Dictionary) -> void:
	_enemy = enemy
	_wander = wander


## The spawned EnemyScript (null before the spawn or once it is freed).
func get_enemy() -> Node:
	return _enemy if is_instance_valid(_enemy) else null


## True while its enemy stands: spawned, not defeated, not freed.
func is_standing() -> bool:
	if not is_instance_valid(_enemy) or _enemy.is_queued_for_deletion():
		return false
	return not bool(_enemy.call(&"is_defeated"))


## Where it wanders: its wander perimeter's centre once spawned, else its spot.
func wander_centre() -> Vector2:
	return Perimeter.centre(_wander) if not _wander.is_empty() else global_position


# --- the editor ----------------------------------------------------------------------------------

func _validate_property(property: Dictionary) -> void:
	if property["name"] == "enemy_type":
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(known_types())


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if enemy_type.is_empty():
		warnings.append("Pick its enemy_type.")
	elif not known_types().has(enemy_type):
		warnings.append("'%s' is not an enemy type with a scene (enemy-types.json, character.<type>)." % enemy_type)
	if not wander_area_id.is_empty() and Engine.is_editor_hint() and _find_shared_area() == null:
		warnings.append("No enemy-wander area '%s' in this world." % wander_area_id)
	return warnings


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var outline: Variant = _shared_outline()
	_drawn_outline = outline
	if outline is Dictionary:
		_draw_perimeter(outline, SHARED_OUTLINE)
	elif wander_area_id.is_empty():
		draw_arc(Vector2.ZERO, wander_radius, 0.0, TAU, 64, OWN_OUTLINE, OUTLINE_WIDTH)
	# the rest upright in the world, whatever this node's rotation (it is the facing)
	var upright := Transform2D(-global_rotation, Vector2.ZERO)
	draw_set_transform_matrix(upright)
	var picture := picture_of(enemy_type)
	if bool(picture.get("faces", false)):
		_draw_view(float(picture.get("view_radius", 0.0)))
	if picture.is_empty():
		draw_circle(Vector2.ZERO, MARKER_RADIUS, MISSING, false, OUTLINE_WIDTH)
		draw_line(Vector2(-MARKER_RADIUS, -MARKER_RADIUS), Vector2(MARKER_RADIUS, MARKER_RADIUS), MISSING, OUTLINE_WIDTH)
		draw_line(Vector2(MARKER_RADIUS, -MARKER_RADIUS), Vector2(-MARKER_RADIUS, MARKER_RADIUS), MISSING, OUTLINE_WIDTH)
	else:
		var sprite: Transform2D = picture["transform"]
		draw_set_transform_matrix(upright * sprite)
		draw_texture_rect_region(picture["texture"], picture["rect"], picture["region"], (picture["modulate"] as Color) * PICTURE_TINT)
		draw_set_transform_matrix(upright)
	var font := ThemeDB.fallback_font
	if font != null:
		var text := enemy_type if not enemy_type.is_empty() else "(no type)"
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		draw_string(font, Vector2(-width / 2.0, LABEL_SIZE + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
				LABEL_COLOR if picture.size() > 0 else MISSING)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The half of the world a facing enemy sees (`radius` around it, in world orientation: the
## current draw transform is upright) and an arrow the way it faces.
func _draw_view(radius: float) -> void:
	var way := facing()
	var points := PackedVector2Array([Vector2.ZERO])
	var start := way.angle() - PI * 0.5
	for i in VIEW_SEGMENTS + 1:
		points.append(Vector2.from_angle(start + PI * float(i) / float(VIEW_SEGMENTS)) * maxf(radius, VIEW_ARROW_PX))
	draw_colored_polygon(points, VIEW_FILL)
	points.append(Vector2.ZERO)
	draw_polyline(points, VIEW_EDGE, OUTLINE_WIDTH)
	var tip := way * VIEW_ARROW_PX
	draw_line(Vector2.ZERO, tip, VIEW_EDGE, OUTLINE_WIDTH * 1.5)
	draw_line(tip, tip - way.rotated(0.5) * VIEW_ARROW_HEAD_PX, VIEW_EDGE, OUTLINE_WIDTH * 1.5)
	draw_line(tip, tip - way.rotated(-0.5) * VIEW_ARROW_HEAD_PX, VIEW_EDGE, OUTLINE_WIDTH * 1.5)


func _changed() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		update_configuration_warnings()


## The shared wander area's outline in this node's space ({"shape", ...} as Perimeter, local), null
## when it names none or the area is not in the edited world.
func _shared_outline() -> Variant:
	if wander_area_id.is_empty() or not is_inside_tree():
		return null
	var area := _find_shared_area()
	if area == null:
		return null
	for child: Node in area.get_children():
		if not child is CollisionShape2D or (child as CollisionShape2D).shape == null:
			continue
		var shape_node := child as CollisionShape2D
		var at := to_local(shape_node.global_position)
		if shape_node.shape is CircleShape2D:
			return {"shape": Perimeter.SHAPE_CIRCLE, "x": at.x, "y": at.y,
				"radius": (shape_node.shape as CircleShape2D).radius * absf(shape_node.global_scale.x)}
		if shape_node.shape is RectangleShape2D:
			var size := (shape_node.shape as RectangleShape2D).size * shape_node.global_scale.abs()
			return {"shape": Perimeter.SHAPE_RECTANGLE, "x": at.x - size.x / 2.0, "y": at.y - size.y / 2.0,
				"w": size.x, "h": size.y}
	return null


## Editor: the Area2D of the edited world's `enemy-wander` area named `wander_area_id` (null when
## none). Kept until the name changes or the node goes.
func _find_shared_area() -> Node:
	if is_instance_valid(_shared_area) and _shared_area.is_inside_tree():
		return _shared_area
	_shared_area = null
	# A name that finds nothing is looked for again at most every SEARCH_AGAIN_MS.
	var now := Time.get_ticks_msec()
	if now < _search_again_at:
		return null
	_search_again_at = now + SEARCH_AGAIN_MS
	var root: Node = get_tree().edited_scene_root if is_inside_tree() else null
	if root == null or not (root == self or root.is_ancestor_of(self)):
		root = owner
	if root == null:
		return null
	for node: Node in root.find_children("*", "Node", true, false):
		if node.get_script() == WorldAreaScript and str(node.get(&"area_id")) == wander_area_id \
				and str(node.get(&"area_kind")) == WorldAreaScript.KIND_ENEMY_WANDER:
			_shared_area = node.get_parent()
			_search_again_at = 0
			return _shared_area
	return null


func _draw_perimeter(outline: Dictionary, color: Color) -> void:
	if outline["shape"] == Perimeter.SHAPE_CIRCLE:
		draw_arc(Vector2(outline["x"], outline["y"]), float(outline["radius"]), 0.0, TAU, 64, color, OUTLINE_WIDTH)
	else:
		draw_rect(Rect2(outline["x"], outline["y"], outline["w"], outline["h"]), color, false, OUTLINE_WIDTH)


# --- types and pictures (also the Scenery dock's Enemies category) -------------------------------

## Every `enemy-types.json` id that has a `character.<id>` scene, sorted.
static func known_types() -> PackedStringArray:
	if not _type_ids.is_empty():
		return _type_ids
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENEMY_TYPES_PATH))
	var types: Variant = (parsed as Dictionary).get("types", {}) if parsed is Dictionary else {}
	var ids: Array = (types as Dictionary).keys() if types is Dictionary else []
	ids.sort()
	for id: Variant in ids:
		if not _scene_path(str(id)).is_empty():
			_type_ids.append(str(id))
	return _type_ids


## `type_id`'s picture for the editor, read once from its scene's sprite (first frame): {"texture",
## "region" (in the texture), "rect" (in the sprite's space), "transform" (the sprite's in the
## enemy root's), "modulate", "faces" (its EnemyScript has `aim_direction`), "view_radius" (its
## `targeting_radius`)}; {} when the type has no scene or sprite.
static func picture_of(type_id: String) -> Dictionary:
	if type_id.is_empty():
		return {}
	if _pictures.has(type_id):
		return _pictures[type_id]
	var picture := {}
	var path := _scene_path(type_id)
	var packed := load(path) as PackedScene if not path.is_empty() and ResourceLoader.exists(path) else null
	var instance := packed.instantiate() if packed != null else null
	if instance != null:
		var sprite := instance.get_node_or_null(NodePath(VISUAL_NAME)) as Sprite2D
		if sprite == null:
			var found := instance.find_children("*", "Sprite2D", true, false)
			sprite = found[0] as Sprite2D if not found.is_empty() else null
		if sprite != null and sprite.texture != null:
			var region := Rect2(Vector2.ZERO, sprite.texture.get_size())
			if sprite.region_enabled:
				region = sprite.region_rect
			var frame_size := region.size / Vector2(maxi(1, sprite.hframes), maxi(1, sprite.vframes))
			var frame_region := Rect2(region.position + Vector2(sprite.frame_coords) * frame_size, frame_size)
			var origin := sprite.offset - (frame_size / 2.0 if sprite.centered else Vector2.ZERO)
			var to_root := Transform2D.IDENTITY
			var node: Node = sprite
			while node != null and node != instance:
				if node is Node2D:
					to_root = (node as Node2D).transform * to_root
				node = node.get_parent()
			picture = {"texture": sprite.texture, "region": frame_region, "rect": Rect2(origin, frame_size),
				"transform": to_root, "modulate": sprite.modulate * sprite.self_modulate}
			var script_node := instance.get_node_or_null(^"EnemyScript")
			if script_node != null and FACING_PROPERTY in script_node:
				picture["faces"] = true
				picture["view_radius"] = float(script_node.get(&"targeting_radius"))
		instance.free()
	_pictures[type_id] = picture
	return picture


## `type_id`'s picture as one texture (the Scenery dock's list), null when none.
static func picture_texture(type_id: String) -> Texture2D:
	var picture := picture_of(type_id)
	if picture.is_empty():
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = picture["texture"]
	atlas.region = picture["region"]
	return atlas


## Forgets the types and pictures read (the Scenery dock's Reload).
static func reload() -> void:
	_type_ids = PackedStringArray()
	_scene_index = {}
	_pictures = {}


static func _scene_path(type_id: String) -> String:
	if _scene_index.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENE_INDEX_PATH))
		_scene_index = parsed if parsed is Dictionary else {}
	return str(_scene_index.get(SCENE_PREFIX + type_id, ""))

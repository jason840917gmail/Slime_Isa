extends Node
class_name LiftableScript
## Scene script `game.liftable` (owner, 2026-10-08/09; GAME_GUIDELINES "Signature Mechanic: Gulp"). A
## light thing the slime sucks in with Q and throws (game/player/gulp/mouth.gd); it breaks where it
## lands, in a way that fits what it is made of (game/player/gulp/thrown_object.gd).
##
## There are 67 kinds for every kind of place (owner, 2026-10-09: "at least 8 by 8 ... stuff for
## dungeons, different terrains, interiors like pots"): home and kitchen, dungeon, forest, cave and
## crystal, snow and ice, desert, beach and swamp, garden and lava. game/data/liftables.json lists
## each kind's name, material, frames on the liftables sheet and art size (written by
## scripts/props/pack-gulp-art.py, where the kinds are authored).
##
## One scene serves every kind (`object.liftable`): set `kind` on the placed instance (and its
## Visual's frame, so the editor shows it); on `_ready` the frame and the body's footprint follow the
## kind. The rock, the puffball and the pinecone have two looks: with `variant` -1 one is picked from
## the root's position, so a row of rocks is not all alike. `object.liftable-rock`, `-puffball` and
## `-pinecone` are the same scene with the kind preset.
##
## It is part of its world scene, so it is back whenever the map is entered again. A `heavy` one
## needs a lift upgrade (not built yet) and cannot be sucked in. The root is a StaticBody2D (the
## slime walks around it); its ground point is the root.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const GROUP := &"liftable"
const SUCKABLE_GROUP := &"suckable"
const CATALOG_FILE := "liftables.json"
const DEFAULT_KIND := "rock"
## The body: this share of the drawn art's width, this deep (world px).
const FOOTPRINT_SHARE := 0.7
const FOOTPRINT_DEPTH := 12.0
const FOOTPRINT_MIN_WIDTH := 10.0

## A kind id of game/data/liftables.json ("clay-pot", "rock", "ice-block", ...).
@export var kind: String = DEFAULT_KIND
## Which look of a kind with several; -1 picks one from the root's position.
@export var variant: int = -1
## Needs a lift upgrade (Planned, 2026-10-08): the slime cannot suck it in yet.
@export var heavy: bool = false


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(SUCKABLE_GROUP)


func _ready() -> void:
	var root := get_parent() as Node2D
	if root == null:
		return
	if entry(kind).is_empty():
		push_warning("LiftableScript: unknown kind '%s' at %s" % [kind, root.get_path()])
	var looks := frames_of(kind).size()
	if variant < 0:
		variant = absi(roundi(root.global_position.x) * 7 + roundi(root.global_position.y) * 13) % maxi(1, looks)
	var visual := root.get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		visual.frame = frame_of(kind, variant)
	var body_shape := root.get_node_or_null(^"BodyShape") as CollisionShape2D
	if body_shape != null and visual != null:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(maxf(FOOTPRINT_MIN_WIDTH, art_size(kind).x * absf(visual.scale.x) * FOOTPRINT_SHARE), FOOTPRINT_DEPTH)
		body_shape.shape = rect
		body_shape.position = Vector2(0.0, -FOOTPRINT_DEPTH * 0.5)


## The catalog (game/data/liftables.json): {"sheet", "cell", "columns", "rows", "kinds": {id: {"name",
## "material", "frames", "art"}}}; {} when it cannot be read.
static func catalog() -> Dictionary:
	var constants := Services.constants()
	var data: Variant = constants.data_file(CATALOG_FILE) if constants != null else null
	return data if data is Dictionary else {}


## Every kind id, in sheet order.
static func kinds() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in (catalog().get("kinds", {}) as Dictionary):
		ids.append(str(id))
	return ids


static func entry(look_kind: String) -> Dictionary:
	var found: Variant = (catalog().get("kinds", {}) as Dictionary).get(look_kind)
	return found if found is Dictionary else {}


## The sheet frames of `look_kind` (one per look).
static func frames_of(look_kind: String) -> Array:
	var frames: Variant = entry(look_kind).get("frames")
	return frames if frames is Array and not (frames as Array).is_empty() else [0]


## The liftables sheet frame of `look_kind` and `look_variant`.
static func frame_of(look_kind: String, look_variant: int) -> int:
	var frames := frames_of(look_kind)
	return int(frames[clampi(look_variant, 0, frames.size() - 1)])


## "clay", "glass", "wood", "metal", "stone", "soft", "ice", "snow" or "crystal".
static func material_of(look_kind: String) -> String:
	return str(entry(look_kind).get("material", "stone"))


static func display_name(look_kind: String) -> String:
	return str(entry(look_kind).get("name", look_kind.capitalize()))


## The drawn art's size in sheet px.
static func art_size(look_kind: String) -> Vector2:
	var art: Variant = entry(look_kind).get("art")
	return Vector2(float(art[0]), float(art[1])) if art is Array and (art as Array).size() == 2 else Vector2(120.0, 120.0)


func origin() -> Vector2:
	var root := get_parent() as Node2D
	return root.global_position if root != null else Vector2.ZERO


func suck_info() -> Dictionary:
	return {"kind": kind, "essence": "", "variant": maxi(variant, 0)}


func can_take() -> bool:
	return not heavy and is_inside_tree() and not get_parent().is_queued_for_deletion()


## Sucked in: the thing leaves the world.
func take() -> void:
	var root := get_parent()
	if root == null or root.is_queued_for_deletion():
		return
	var body := root as CollisionObject2D
	if body != null:
		body.set_deferred(&"collision_layer", 0)
	root.queue_free()

extends Node
## The player slime's steps, wading and swimming (owner, 2026-10-06; docs/godot/specs/audio.md §10).
##
## Instanced by the player (`res://game/scenes/audio/footsteps.tscn`, a child of the player node).
## Each surface is one child AudioStreamPlayer (`sfx_player.gd`, bus Effects) holding its takes in
## an AudioStreamRandomizer; the scene is where volumes and takes are tuned.
##
## - A step plays each time the walk clip starts or loops: frame 0 of every walk row is the slime's
##   squash, the moment it lands. Its surface is the ground tile under the feet (`tile_id` of the
##   world's ground layer, mapped by `surface_by_ground`); shallow `water` wades.
## - While swimming (player_swimming.gd) and moving, a stroke plays as the slime starts to move and
##   at each loop of the swim clip (floating still plays none: the swim clip also loops then).
## - Crossing into shallow water splashes, starting to swim plunges, and climbing out of either
##   drips (`enter_water`, `enter_swim`, `leave_water`).
## - Nothing plays in the air (the jump) or on a tile with no surface (a missing tile, rock walls are
##   mapped to the cave floor).
##
## Owner: audio.

const Services := preload("res://game/shared/services.gd")
const TILE_ID_DATA_LAYER := "tile_id"
## The feet cell is read this far up, inside the body (as the water wake does).
const FEET_PROBE := 2.0
const WALK_CLIP_PREFIX := "walk"
const SWIM_CLIP_PREFIX := "swim"
## Slower than this a swimmer floats (units per second; as the water wake).
const MOVING_SPEED := 8.0

## Ground `tile_id` -> the child player that steps on it.
@export var surface_by_ground: Dictionary = {
	"grass-a": &"Grass",
	"grass-b": &"Grass",
	"forest-floor": &"Forest",
	"forest-moss": &"Forest",
	"amberleaf-ground": &"Leaves",
	"sanddessert-ground": &"Sand",
	"frozen-ground": &"Snow",
	"town-cobble": &"Stone",
	"cavern-floor": &"Cave",
	"rock-wall": &"Cave",
	"crystal-floor": &"Crystal",
	"wood-floor": &"Wood",
	"mushroom-earth-floor": &"Soft",
	"mushroom-plain-floor": &"Soft",
	"mushroom-clover-floor": &"Soft",
	"water": &"Shallow",
	"deep-water": &"Shallow",
}
## The child player for a stroke while swimming.
@export var swim_surface: StringName = &"Swim"
## The surface that counts as being in shallow water (for the splash in and the drip out).
@export var shallow_surface: StringName = &"Shallow"
## One-shots for crossing the waterline (child player names; empty plays nothing).
@export var enter_water: StringName = &"WaterEnter"
@export var enter_swim: StringName = &"SwimEnter"
@export var leave_water: StringName = &"WaterExit"

## The player script node (game/scripts/player.gd), set before the node enters the tree.
var player: Node
## Steps and strokes played since the node entered the tree (tests and the sound audition read it).
var steps_played: int = 0
## The last surface a step or stroke played on.
var last_surface: StringName = &""

var _clip: String = ""
var _clip_position: float = 0.0
var _was_swimming_on: bool = false
## Where the feet are: &"" on land, the shallow surface, or the swim surface.
var _water: StringName = &""
var _water_known: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var animation: AnimationPlayer = player.get(&"animation")
	var body: CharacterBody2D = player.get(&"body")
	if animation == null or body == null:
		return
	var airborne := bool(player.call(&"is_airborne"))
	var swimming := bool(player.call(&"is_swimming"))
	var surface := surface_at(body.global_position - Vector2(0.0, FEET_PROBE))
	if not airborne:
		_cross_waterline(swim_surface if swimming else (surface if surface == shallow_surface else &""))
	var clip := String(animation.current_animation)
	var stepping := clip.begins_with(SWIM_CLIP_PREFIX) if swimming else clip.begins_with(WALK_CLIP_PREFIX)
	if not stepping or airborne:
		_clip = ""
		return
	var position := animation.current_animation_position
	var looped := clip != _clip or position < _clip_position
	_clip = clip
	_clip_position = position
	if not swimming:
		_was_swimming_on = false
		if looped:
			play_step(surface)
		return
	var moving := body.velocity.length() > MOVING_SPEED
	if moving and (looped or not _was_swimming_on):
		play_step(swim_surface)
	_was_swimming_on = moving


## The surface child for the ground under `world_point` (&"" when none).
func surface_at(world_point: Vector2) -> StringName:
	var world := Services.world()
	var ground: TileMapLayer = world.ground_layer if world != null else null
	if ground == null or not is_instance_valid(ground) or ground.tile_set == null:
		return &""
	if not ground.tile_set.has_custom_data_layer_by_name(TILE_ID_DATA_LAYER):
		return &""
	var tile_data := ground.get_cell_tile_data(ground.local_to_map(ground.to_local(world_point)))
	if tile_data == null:
		return &""
	return StringName(surface_by_ground.get(str(tile_data.get_custom_data(TILE_ID_DATA_LAYER)), &""))


## Plays one step (or stroke) on `surface`.
func play_step(surface: StringName) -> void:
	if _cue(surface):
		steps_played += 1
		last_surface = surface


func _cross_waterline(water: StringName) -> void:
	if not _water_known:
		_water_known = true
		_water = water
		return
	if water == _water:
		return
	if water == swim_surface:
		_cue(enter_swim)
	elif water == shallow_surface and _water == &"":
		_cue(enter_water)
	elif water == &"":
		_cue(leave_water)
	_water = water


func _cue(child_name: StringName) -> bool:
	if child_name.is_empty():
		return false
	var cue := get_node_or_null(NodePath(String(child_name)))
	if cue == null:
		return false
	if cue.has_method(&"play_cue"):
		cue.call(&"play_cue")
	elif cue is AudioStreamPlayer:
		(cue as AudioStreamPlayer).play()
	return true

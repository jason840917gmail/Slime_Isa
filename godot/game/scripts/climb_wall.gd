extends Node2D
## Scene script `game.climb-wall` (`object.climb-wall`, game/scenes/objects/climb-wall.tscn;
## docs/godot/SKINS.md "Feral"): a climbable wall, the Feral skin's lock (the look book: thick,
## living, leafy roots beside rocky handholds on a cliff face; never beside a heavy block, never
## the root-rock wall style; questions 86, 91 and 129). Place it at a wall's foot, its `top` where
## the slime's centre ends the climb (on the ledge above, or with `top.y` > 0 at the foot below: a
## wall climbed down from its lip). Its picture (`Visual`) covers the face.
##
## - **With the Feral skin** (SkinState, Pearl 3's) the slime clings to it while the interact key is
##   held and the movement keys move it over the face (game/player/skins/feral_climb.gd, whose
##   climbable surface this is: `climb_start`, `climb_allows`, `climb_exit`, `climb_landing`): the
##   press at its start zone facing along the climb (`can_grab`: within `grab_width` across and
##   `skins.feral.grabReachPx` of this node), or its prompt `prompt` (`use`). The slime moves in the
##   strip `grab_width` wide between this node and `top`, and gets off at either end by pushing on.
##   Letting go midway drops the slime to the lower end; a fall costs
##   nothing. At the top `climbed` fires, and with `exit_area_id` set the climb goes on out of the
##   world (the Colossus arena's way out to the Lookout): the slime travels to that world's
##   `exit_door`. While its dungeon is sealed (the Pearl taken, the boss standing) such a climb
##   out is not offered and refuses with the seal's line (`sealed_text`; DUNGEONS.md "The seal").
## - **Without it** it is not offered; pushing along the climb at its foot says `refusal_text` (the
##   clarity rule: a wrong tool is refused with a line), at most every `skins.feral.refusalEveryMs`.
##
## Owner: skins (placed by the dungeons).

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const USABLE_GROUP := &"usable"
const GROUP := &"climb_walls"
const MAIN_GROUP := &"world_main"
const TEXT_RISE := 90.0
const TEXT_MS := 2400.0
## How near (feet to this node) the slime must push along the climb to hear the refusal.
const REFUSAL_RADIUS := 70.0
## The grab zone's width without `grab_width` or `art_size`.
const DEFAULT_WIDTH := 96.0
## How square the slime must face along the climb to grab with a press.
const FACING_DOT := 0.5
## The roots fill this share of their 256 px picture (the packer leaves a margin).
const ART_FILL := Vector2(0.86, 0.9)
## The slime's feet below its centre (its `metadata/depth_anchor`), when the body gives none.
const FEET_BELOW_CENTRE := 27.56
## How near an end (the slime's feet) counts as being there.
const END_PX := 6.0
## Letting go this near the upper end, where there is ground, the slime stands there (no fall).
const UPPER_END_PX := 20.0

## Where the climb ends, from this node (world units: the slime's centre there).
@export var top: Vector2 = Vector2(0, -192)
## Unused since roadmap 7.8 (the climb's speed is `skins.feral.climbSpeed`); kept for old scenes.
@export var climb_ms: float = 0.0
@export var interact_radius: float = 80.0
@export var badge_rise: float = 64.0
@export var prompt: String = "Climb (hold)"
@export var refusal_text: String = "Thick roots and handholds... too steep for a slime. Something wilder could climb them."
## The grab zone's width across the climb (0: the picture's `art_size`, else DEFAULT_WIDTH).
@export var grab_width: float = 0.0
## Climbing out of the world: the world to go to ("" = stay here) and the end there the slime comes
## out of (a door's `door_id`: an arrival point, game/scripts/door.gd; "" = that world's spawn).
@export var exit_area_id: String = ""
@export var exit_door: String = ""
## The roots' picture (`Visual`): how much of the face it covers (world units; zero: the scene's
## size), and whether it shows (a climb back down from a ledge shares the face's picture below).
@export var art_size: Vector2 = Vector2.ZERO
@export var show_art: bool = true
## The climb ends on the face, with nothing to stand on at `top` (roots beside the Colossus's climb
## spots, docs/godot/DUNGEONS.md "The Crystal Colossus"): the slime clings there until it lets go
## or climbs back (game/player/skins/feral_climb.gd), and `hold_text` shows as it gets there ("" =
## nothing). Added by the dungeons (the Crystal Mine), 2026-10-17.
@export var holds_at_top: bool = false
@export var hold_text: String = ""

## The climb finished at the far end. Payload: {"top": Vector2 (the feet there), "exit": String}.
signal climbed(payload: Dictionary)
## The slime took hold. Payload: {}.
signal grabbed(payload: Dictionary)

var _next_refusal_ms := 0.0
## Where the slime stood (its feet's y) as it last took hold: the strip reaches there, so it gets
## off, and lands, where it stood (NAN before the first hold).
var _held_from_y := NAN


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(USABLE_GROUP)


func _ready() -> void:
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual == null:
		return
	visual.visible = show_art
	if art_size != Vector2.ZERO and visual.texture != null:
		var picture := visual.texture.get_size() / Vector2(visual.hframes, visual.vframes)
		visual.scale = art_size / (picture * ART_FILL)


# --- the climb (game/player/skins/feral_climb.gd) ------------------------------------------------

## The slime's feet where the climb starts: this node.
func start_feet() -> Vector2:
	return global_position


## The slime's feet where the climb ends (`top` is its centre there).
func end_feet(body: Node2D = null) -> Vector2:
	var anchor := FeetAnchor.depth_anchor(body) if body != null else Vector2.ZERO
	if anchor == Vector2.ZERO:
		anchor = Vector2(0.0, FEET_BELOW_CENTRE)
	return global_position + top + anchor


## The way along the climb (UP for a wall climbed up).
func climb_direction() -> Vector2:
	return Vector2.DOWN if top.y > 0.0 else Vector2.UP


## True when feet at `feet`, facing `facing`, can take hold: the Feral skin on, inside the start
## zone, facing along the climb.
func can_grab(feet: Vector2, facing: Vector2) -> bool:
	if not has_skin() or not is_visible_in_tree() or not sealed_text().is_empty():
		return false
	if facing == Vector2.ZERO or facing.normalized().dot(climb_direction()) < FACING_DOT:
		return false
	return _in_zone(feet)


func _in_zone(feet: Vector2) -> bool:
	var half := _width() * 0.5
	var reach := SkinState.setting("feral.grabReachPx", 44.0)
	var offset := feet - global_position
	return absf(offset.x) <= half and absf(offset.y) <= reach


func _width() -> float:
	if grab_width > 0.0:
		return grab_width
	return art_size.x if art_size.x > 0.0 else DEFAULT_WIDTH


func on_grabbed() -> void:
	grabbed.emit({})


# --- the climbable surface (feral_climb.gd): a strip between this node and `top` ------------------

## Where the slime takes hold from `feet`: in the strip, as near as it stands.
func climb_start(feet: Vector2, _facing: Vector2 = Vector2.ZERO) -> Vector2:
	_held_from_y = feet.y
	var strip := _strip()
	return Vector2(clampf(feet.x, strip.position.x, strip.end.x), clampf(feet.y, strip.position.y, strip.end.y))


## True when the slime's feet may be at `feet` while it clings: inside the strip.
func climb_allows(feet: Vector2) -> bool:
	return _strip().grow(0.5).has_point(feet)


## Pushing `way` at an end of the strip: where the slime stands when it gets off there, or
## Vector2.INF (it is not at an end, or the far end has nothing to stand on: `holds_at_top`).
func climb_exit(feet: Vector2, way: Vector2) -> Vector2:
	var push := way.dot(climb_direction())
	var far := end_feet().y
	if push > FACING_DOT and absf(feet.y - far) <= END_PX and not holds_at_top:
		return Vector2(feet.x, far)
	if push < -FACING_DOT and absf(feet.y - _start_y()) <= END_PX:
		return Vector2(feet.x, _start_y())
	return Vector2.INF


## Where a let-go from `feet` lands: the lower end under the slime, or the upper end when it is
## already there and there is ground to stand on.
func climb_landing(feet: Vector2) -> Vector2:
	var strip := _strip()
	var upper_stands := top.y > 0.0 or not holds_at_top
	if upper_stands and feet.y - strip.position.y <= UPPER_END_PX:
		return Vector2(feet.x, strip.position.y)
	return Vector2(feet.x, strip.end.y)


## True when the slime clings at the far end of a climb that ends on the face (`holds_at_top`).
func climb_holds(feet: Vector2) -> bool:
	return holds_at_top and absf(feet.y - end_feet().y) <= END_PX


## The climb ended with the slime standing at `feet`: at the far end it is climbed (`on_climbed`).
func climb_left(feet: Vector2) -> void:
	if not holds_at_top and absf(feet.y - end_feet().y) <= END_PX:
		on_climbed(feet)


## The strip's near end (the slime's feet's y): this node, or past it where the slime stood as it
## took hold (within reach of the node, before the face's foot or back from the lip).
func _start_y() -> float:
	var own := start_feet().y
	if is_nan(_held_from_y):
		return own
	return minf(own, _held_from_y) if top.y > 0.0 else maxf(own, _held_from_y)


## The strip the slime's feet move in (world): `_width()` across, from its near end to the far end.
func _strip() -> Rect2:
	var from := _start_y()
	var to := end_feet().y
	var half := _width() * 0.5
	return Rect2(global_position.x - half, minf(from, to), half * 2.0, absf(to - from))


## The slime got to the far end of a climb that ends on the face: `hold_text` over it.
func on_held_at_end() -> void:
	if hold_text.is_empty():
		return
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position + top - Vector2(0.0, TEXT_RISE * 0.5), hold_text, &"white", false, TEXT_MS)


## The slime reached the far end (`feet`): `climbed`, and out of the world with `exit_area_id`.
func on_climbed(feet: Vector2) -> void:
	climbed.emit({"top": feet, "exit": exit_area_id})
	if not exit_area_id.is_empty():
		var main := get_tree().get_first_node_in_group(MAIN_GROUP)
		if main != null and main.has_method(&"travel_to"):
			main.call(&"travel_to", exit_area_id, "", exit_door, "" if not exit_door.is_empty() else "player-spawn")


# --- the interact prompt (game/interaction/interaction_controller.gd USABLE_GROUP) -------------

func origin() -> Vector2:
	return global_position


static func has_skin() -> bool:
	return SkinState.is_on(null, SkinState.FERAL)


func can_use() -> bool:
	if not has_skin() or not sealed_text().is_empty():
		return false
	var player := _player()
	return player != null and not bool(player.call(&"is_climbing"))


## Starts the climb (the prompt): the slime takes hold and clings while the key stays held.
func use() -> bool:
	var player := _player()
	if player == null or not can_use():
		return false
	return bool(player.call(&"start_climb", self))


func is_climbing() -> bool:
	var player := _player()
	if player == null or not bool(player.call(&"is_climbing")):
		return false
	var climb: Variant = player.call(&"get_climb")
	return climb != null and (climb as Object).call(&"wall") == self


## A climb out of a sealed dungeon (its `exit_area_id` outside it) refuses with the seal's line
## (docs/godot/DUNGEONS.md "The seal"); "" when it may go.
func sealed_text() -> String:
	if exit_area_id.is_empty() or not is_inside_tree():
		return ""
	return DungeonState.exit_refusal(get_tree(), exit_area_id)


func _physics_process(_delta: float) -> void:
	var sealed := sealed_text()
	if has_skin() and sealed.is_empty():
		return
	var player := _player()
	if player == null:
		return
	# The refusal: pushing along the climb at the foot without the skin (or out of a sealed dungeon).
	var body := player.get(&"body") as Node2D
	var feet: Vector2 = body.global_position if body != null else player.call(&"get_centre")
	if feet.distance_to(global_position) > REFUSAL_RADIUS:
		return
	var intent: Vector2 = player.call(&"get_move_intent") if player.has_method(&"get_move_intent") else Vector2.ZERO
	if intent == Vector2.ZERO or intent.normalized().dot(climb_direction()) < 0.7:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_refusal_ms:
		return
	_next_refusal_ms = now + SkinState.setting("feral.refusalEveryMs", 2500.0)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(&"HitBlocked")
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), sealed if not sealed.is_empty() else refusal_text,
			&"white", false, TEXT_MS)


static func _player() -> Node:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	return player if player != null and is_instance_valid(player) else null

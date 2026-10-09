extends RefCounted
## The Gulp form (abilities spec 11; redesigned 2026-10-08, GAME_GUIDELINES "Signature Mechanic:
## Gulp"). Owned by player.gd. Swallowing an essence (`swallow`, from what the mouth holds) gives
## its form, one at a time and with no timer. The form ends when:
## - a hit pops it out (`pop`): its essence falls beside the slime and fades after
##   `gulp.popGrabMs`, so the slime can suck it back in for a moment;
## - another essence is swallowed: the old one pops out the same way;
## - the slime presses Swallow with nothing held (`spit_out`): the essence drops out whole in front
##   of it and stays until taken;
## - it dies (`clear`), without a trace.
## A door or a save keeps it (`restore`). A form that swims holds while any part of the slime is
## over deep water (abilities spec 11.7): it cannot be spat out, popped or swapped for one that does
## not swim until the slime is out.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const EssenceScript := preload("res://game/scripts/essence.gd")

const MESSAGE_RISE := 56.0
const SWIM_MESSAGE := "Swim back to the shallows first"
## A spat-out essence lands this far in front of the slime; a popped one beside it.
const SPIT_PX := 44.0
const POP_PX := 34.0

## {} or the form row (gulp_forms.gd).
var form: Dictionary = {}
## The slime (player.gd): get_centre, get_facing, body, on_gulp_form_changed(form, reason).
var _player: Node


func _init(player: Node) -> void:
	_player = player


## Swallows essence item `item_id`: "started" | "switched" | "nothing". The old form pops out.
func swallow(item_id: String) -> String:
	var next := GulpForms.for_item(item_id)
	if next.is_empty():
		return "nothing"
	if _held_by_water() and not bool(next.get("swims", false)):
		_message(SWIM_MESSAGE)
		return "nothing"
	var previous := form
	form = next
	if not previous.is_empty():
		_drop_essence(str(previous["essence"]), _side_point(), _constant("gulp.popGrabMs"))
		_player.call(&"on_gulp_form_changed", next, "switched")
		return "switched"
	_player.call(&"on_gulp_form_changed", next, "started")
	return "started"


## A hit: the form pops out as its essence beside the slime, there for `gulp.popGrabMs`. False when
## there was no form (or a swimming form held by deep water).
func pop() -> bool:
	if form.is_empty() or _held_by_water():
		return false
	var essence := str(form["essence"])
	form = {}
	_player.call(&"on_gulp_form_changed", {}, "popped")
	_drop_essence(essence, _side_point(), _constant("gulp.popGrabMs"))
	return true


## Swallow with nothing held: the form drops out whole in front of the slime and stays.
## "spat" | "nothing".
func spit_out() -> String:
	if form.is_empty():
		return "nothing"
	if _held_by_water():
		_message(SWIM_MESSAGE)
		return "nothing"
	var essence := str(form["essence"])
	form = {}
	_player.call(&"on_gulp_form_changed", {}, "spat")
	var facing: Vector2 = _player.call(&"get_facing")
	_drop_essence(essence, _feet() + facing.normalized() * SPIT_PX, 0.0)
	return "spat"


## Death: the form goes without a word.
func clear() -> void:
	if not form.is_empty():
		form = {}
		_player.call(&"on_gulp_form_changed", {}, "cleared")


## A door or a load: the form `form_id` comes back quietly.
func restore(form_id: String) -> void:
	var next := GulpForms.by_id(StringName(form_id))
	if next.is_empty() or (not form.is_empty() and form["id"] == next["id"]):
		return
	form = next
	_player.call(&"on_gulp_form_changed", next, "restored")


## Forms have no timer since 2026-10-08 (the HUD reads 0).
func remaining_ms() -> float:
	return 0.0


## True while a form that swims keeps the slime afloat: some of its body is over deep water.
func _held_by_water() -> bool:
	return bool(form.get("swims", false)) and bool(_player.call(&"overlaps_deep_water"))


func _drop_essence(essence: String, at: Vector2, fade_ms: float) -> void:
	EssenceScript.spawn(essence, at, _player.call(&"get_centre"), fade_ms)


func _feet() -> Vector2:
	var body := _player.get(&"body") as Node2D
	return body.global_position if body != null else _player.call(&"get_centre")


## Beside the slime, across its facing.
func _side_point() -> Vector2:
	var facing: Vector2 = _player.call(&"get_facing")
	var side := Vector2(-facing.y, facing.x).normalized()
	return _feet() + (side if side != Vector2.ZERO else Vector2.RIGHT) * POP_PX


func _message(text: String) -> void:
	var feel := Services.feel()
	if feel != null:
		var centre: Vector2 = _player.call(&"get_centre")
		feel.floating_text(centre - Vector2(0.0, MESSAGE_RISE), text, &"white", false)


static func _constant(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0

extends RefCounted
## Eating and the Gulp form (Phaser `features/gulp/GulpController.ts`; abilities spec 11.2).
## Owned by player.gd. A tap of Q next to a Gulp spot (within its radius of the slime's centre)
## takes the spot's form for free; spots never run out. Away from spots a form burps; with no form
## the slime says why nothing happened. Eating the form it already has refreshes the timer. The
## form wears off after 60 s of simulation time, and is lost on death and on a map change.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const SPOT_GROUP := &"gulp-spot"
const MESSAGE_RISE := 56.0

## {} or the form row (gulp_forms.gd).
var form: Dictionary = {}
var ends_at: float = 0.0
var last_material: String = "stone"
## The slime (player.gd): get_centre, on_gulp_form_changed(form, reason).
var _player: Node


func _init(player: Node) -> void:
	_player = player


## One tap: "spot" | "burp" | "nothing".
func eat() -> String:
	var spot := nearest_spot()
	if spot != null:
		var spot_form := GulpForms.for_material(str(spot.get(&"material_item_id")))
		if spot_form.is_empty():
			return "nothing"
		_become(spot_form)
		return "spot"
	if not form.is_empty():
		end("burp")
		return "burp"
	var carried := not preferred_material().is_empty()
	_message("No Gulp spot here. Hold Q to eat what you carry" if carried else "Nothing to gulp here")
	return "nothing"


## The quick wheel's release (wheel OUT): eats one `item_id` from the bag. "inventory" | "nothing".
func eat_material(item_id: String) -> String:
	var material_form := GulpForms.for_material(item_id)
	var run := Services.run()
	if material_form.is_empty() or run == null or run.item_count(item_id) < 1 or not run.remove_item(item_id, 1):
		return "nothing"
	_become(material_form)
	return "inventory"


## Ends an expired form (every step).
func update() -> void:
	if not form.is_empty() and Services.now_ms() >= ends_at:
		end("expired")


## Death: the form goes without a word.
func clear() -> void:
	if not form.is_empty():
		end("cleared")


func end(reason: String) -> void:
	form = {}
	ends_at = 0.0
	_player.call(&"on_gulp_form_changed", {}, reason)


func remaining_ms() -> float:
	return maxf(0.0, ends_at - Services.now_ms()) if not form.is_empty() else 0.0


## The nearest Gulp spot in reach of the slime's centre; null when none.
func nearest_spot() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var at: Vector2 = _player.call(&"get_centre")
	var best: Node = null
	var best_distance := INF
	for spot: Node in tree.get_nodes_in_group(SPOT_GROUP):
		if str(spot.get(&"material_item_id")).is_empty():
			continue
		var distance := at.distance_to(spot.call(&"origin"))
		if distance <= float(spot.get(&"radius")) and distance < best_distance:
			best = spot
			best_distance = distance
	return best


## The last eaten material if carried, else the first carried in table order; "" when none.
func preferred_material() -> String:
	var run := Services.run()
	if run == null:
		return ""
	if run.item_count(last_material) > 0:
		return last_material
	for entry in GulpForms.FORMS:
		if run.item_count(entry["material"]) > 0:
			return entry["material"]
	return ""


func _become(next: Dictionary) -> void:
	var previous := form
	if not previous.is_empty() and previous["id"] != next["id"]:
		_player.call(&"on_gulp_form_changed", {}, "switched")
	form = next
	var constants := Services.constants()
	ends_at = Services.now_ms() + (constants.number("gulp.formDurationMs") if constants != null else 0.0)
	last_material = next["material"]
	var refreshed: bool = not previous.is_empty() and previous["id"] == next["id"]
	_player.call(&"on_gulp_form_changed", next, "refreshed" if refreshed else "started")


func _message(text: String) -> void:
	var feel := Services.feel()
	if feel != null:
		var centre: Vector2 = _player.call(&"get_centre")
		feel.floating_text(centre - Vector2(0.0, MESSAGE_RISE), text, &"white", false)

extends RefCounted
## The Frog Gulp form and swimming (abilities spec 11.7; game/player/gulp/player_swimming.gd).
## - Gulping the frog spot gives the Frog form: its skin, and a body that no longer collides with
##   the `water` layer (deep water's tile collision).
## - The frog swims into deep water: the swim clip, the waterline, the art sunk, the swim ripple.
## - The frog walks from the shallows into deep water: the tiles' collision no longer stops it.
## - The form holds over deep water: it neither wears off nor burps there, and ends once the slime
##   is back in the shallows (then deep water blocks it again).
## - No abilities while swimming.
##
## level-1's lake, row 46: shallow water at x = 3..5, deep water at x = 6..11 (open water, south of
## the island in the middle of the lake).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const PlayerSwimming := preload("res://game/player/gulp/player_swimming.gd")
const WaterWake := preload("res://game/world/water_wake.gd")
const FROG_SPOT := "res://game/scenes/objects/gulp-spot-frog.tscn"

const MAP_ID := "level-1"
const CELL := 64.0
const ROW := 46
const SHALLOW := Vector2i(4, ROW)
const DEEP := Vector2i(8, ROW)
## Long enough to walk about two cells (walk speed 200).
const WALK_MS := 700.0


func test_gulping_the_frog_gives_the_frog_form(t: TestContext) -> void:
	var player := t.player()
	await _gulp_frog(t)
	t.equal(player.current_form_id(), GulpForms.FROG, "the frog form")
	var material := player.get_visual().material as ShaderMaterial
	t.equal(int(material.get_shader_parameter(&"skin")), 3, "the frog skin")
	t.equal(t.player_body().collision_mask & PlayerSwimming.WATER_LAYER_BIT, 0, "the frog ignores the water layer")


func test_the_frog_swims_in_deep_water(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	await _gulp_frog(t)
	t.teleport_player(_centre(DEEP))
	await t.steps(3)
	t.check(player.is_swimming(), "swimming in deep water")
	var material := player.get_visual().material as ShaderMaterial
	t.equal(float(material.get_shader_parameter(&"waterline")), PlayerSwimming.WATERLINE_PX, "the waterline is on")
	t.press(&"move_right")
	await t.steps(4)
	t.release_all()
	t.check(str(player.animation.current_animation).begins_with("swim-"), "the swim clip plays (%s)" % player.animation.current_animation)
	var wake := t.world().ground_layer.get_node(^"WaterWake") as WaterWake
	t.equal(wake.row_of(body), WaterWake.SWIM_ROW, "the swim ripple")
	t.teleport_player(_centre(SHALLOW))
	await t.steps(3)
	t.check(not player.is_swimming(), "wading, not swimming, in shallow water")
	t.equal(float(material.get_shader_parameter(&"waterline")), 0.0, "the waterline is off")


func test_the_frog_walks_from_the_shallows_into_deep_water(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	await _gulp_frog(t)
	t.teleport_player(_centre(SHALLOW))
	await t.steps(2)
	t.press(&"move_right")
	await t.sim_wait(WALK_MS)
	t.release_all()
	await t.steps(2)
	# Deep water starts at x = 6 cells; without the form the body stops at that cell side.
	var x := body.global_position.x
	t.check(x > 6.5 * CELL, "the frog crossed into the deep water (x = %.1f)" % x)
	t.check(player.is_swimming(), "swimming after walking in")


func test_the_form_holds_over_deep_water(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	await _gulp_frog(t)
	t.teleport_player(_centre(DEEP))
	await t.steps(3)
	var gulp := player.get_gulp()
	gulp.ends_at = Services.now_ms() - 1.0
	await t.steps(3)
	t.equal(player.current_form_id(), GulpForms.FROG, "the form does not wear off over deep water")
	t.equal(player.eat(), "nothing", "no burp over deep water")
	t.equal(player.current_form_id(), GulpForms.FROG, "still a frog")
	t.teleport_player(_centre(SHALLOW))
	await t.steps(3)
	t.equal(player.current_form_id(), &"", "the form wears off once out of deep water")
	t.check(body.collision_mask & PlayerSwimming.WATER_LAYER_BIT != 0, "deep water blocks the slime again")


func test_no_abilities_while_swimming(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("jump", true)
	await _gulp_frog(t)
	t.teleport_player(_centre(DEEP))
	await t.steps(3)
	t.tap(&"jump")
	await t.steps(6)
	t.check(not player.is_airborne() and not player.is_ability_busy(), "no jump while swimming")


## Puts a frog Gulp spot at the slime and gulps it.
func _gulp_frog(t: TestContext) -> void:
	var spot := (load(FROG_SPOT) as PackedScene).instantiate() as Node2D
	t.main.add_child(spot)
	spot.global_position = t.player().get_centre() + Vector2(24.0, 0.0)
	await t.steps(1)
	t.equal(t.player().eat(), "spot", "gulped the frog")
	spot.queue_free()
	# The gulp plays the eat clip, which holds the slime for a moment.
	await t.sim_wait(300.0)


func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL

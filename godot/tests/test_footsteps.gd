extends RefCounted
## Steps, wading and swimming sounds (game/audio/footsteps.gd; audio spec §10) and the new global
## cue players (Sound Picker round 3).
## - Walking plays a step per walk cycle on the ground under the feet; standing plays none.
## - Walking into the shallows splashes once, then each step wades.
## - The Frog form slipping into deep water plunges, then strokes play with the swim cycle.
## - Gulping plays the form's own transform cue; burping plays the burp.
##
## level-1's lake, row 46: land at x = 2, shallow water at x = 3..5, deep water at x = 6..11 (as
## tests/test_frog_form.gd).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const FROG_SPOT := "res://game/scenes/objects/gulp-spot-frog.tscn"

const MAP_ID := "level-1"
const CELL := 64.0
const ROW := 46
const LAND := Vector2i(2, ROW)
const DEEP := Vector2i(8, ROW)
## Global players added with rounds 3 and 4 (game/scenes/audio/global.tscn, Effects). A lash miss stays
## silent (owner's pick).
const NEW_CUES: Array[StringName] = [&"GulpTransformHeavy", &"GulpTransformSticky", &"GulpTransformFrog",
	&"GulpWearOff", &"GulpBurp", &"LashCatch",
	&"FallDown", &"PlatePress", &"PlateRelease", &"GateOpen", &"GateUnlock", &"GateLocked", &"DoorUse",
	&"DummyHit", &"GroundCreak", &"TalkBlip", &"DropPop", &"DropLand", &"PotionDrink", &"WebStruggle",
	&"HitDull", &"HitBlocked", &"Save", &"Toast"]


func test_walking_steps_once_per_walk_cycle(t: TestContext) -> void:
	var footsteps := _footsteps(t)
	if not t.check(footsteps != null, "the player has Footsteps"):
		return
	await t.steps(30)
	var before: int = footsteps.steps_played
	await t.steps(30)
	t.equal(footsteps.steps_played, before, "no steps while standing")
	t.press(&"move_right")
	await t.sim_wait(1000.0)
	t.release_all()
	# The walk cycle is about 0.55 s and steps on its first frame: 2 or 3 steps in a second.
	t.between(float(footsteps.steps_played - before), 2.0, 3.0, "steps in one second of walking")
	var surface: StringName = footsteps.surface_at(t.player_body().global_position)
	t.check(not String(surface).is_empty(), "the spawn ground has a surface")
	t.equal(footsteps.last_surface, surface, "the step sounds the ground under the feet")


func test_walking_into_the_shallows_splashes_then_wades(t: TestContext) -> void:
	var footsteps := _footsteps(t)
	if not t.check(footsteps != null, "the player has Footsteps"):
		return
	t.teleport_player(_centre(LAND))
	await t.steps(5)
	var splash := footsteps.get_node(^"WaterEnter")
	splash.reset_cue()
	t.press(&"move_right")
	var waded := await t.until(func() -> bool: return footsteps.last_surface == &"Shallow", 1500.0)
	t.release_all()
	t.check(waded, "a step in the shallows wades")
	t.equal(splash.cues_played, 1, "one splash walking in")


func test_the_frog_plunges_and_strokes(t: TestContext) -> void:
	var footsteps := _footsteps(t)
	var global := Services.feel().global_audio()
	if not t.check(footsteps != null and global != null, "Footsteps and the global audio"):
		return
	var transform := global.find_child("GulpTransformFrog", true, false)
	transform.reset_cue()
	await _gulp_frog(t)
	t.equal(transform.cues_played, 1, "gulping the frog transforms with the frog's sound")
	t.check(global.find_child("LashMiss", true, false) == null, "a lash miss has no player")
	var plunge := footsteps.get_node(^"SwimEnter")
	plunge.reset_cue()
	t.teleport_player(_centre(DEEP))
	await t.steps(3)
	t.check(t.player().is_swimming(), "swimming in deep water")
	t.equal(plunge.cues_played, 1, "slipping into deep water plunges")
	var before: int = footsteps.steps_played
	await t.sim_wait(1200.0)
	t.equal(footsteps.steps_played, before, "no strokes while floating still")
	t.press(&"move_right")
	await t.sim_wait(700.0)
	t.release_all()
	t.check(footsteps.steps_played > before, "strokes while swimming")
	t.equal(footsteps.last_surface, &"Swim", "the stroke is a swim stroke")


func test_burping_plays_the_burp(t: TestContext) -> void:
	var burp := Services.feel().global_audio().find_child("GulpBurp", true, false)
	await _gulp_frog(t)
	burp.reset_cue()
	t.equal(t.player().eat(), "burp", "a tap away from a spot burps")
	t.equal(burp.cues_played, 1, "the burp sounds")


func test_the_new_cues_have_players(t: TestContext) -> void:
	var global := Services.feel().global_audio()
	if not t.check(global != null, "the global audio"):
		return
	for cue: StringName in NEW_CUES:
		var player := global.find_child(String(cue), true, false) as AudioStreamPlayer
		t.check(player != null and player.stream != null, "a player with takes for %s" % cue)


func _footsteps(t: TestContext) -> Node:
	return t.player().get_node_or_null(^"Footsteps")


func _gulp_frog(t: TestContext) -> void:
	var spot := (load(FROG_SPOT) as PackedScene).instantiate() as Node2D
	t.main.add_child(spot)
	spot.global_position = t.player().get_centre() + Vector2(24.0, 0.0)
	await t.steps(1)
	t.equal(t.player().eat(), "spot", "gulped the frog")
	spot.queue_free()
	await t.sim_wait(300.0)


func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL

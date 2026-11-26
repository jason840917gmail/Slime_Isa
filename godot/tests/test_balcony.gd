extends RefCounted
## Balconies on a cliff's face (docs/godot/SKINS.md "Balconies"; game/world/vines/vine_layer.gd's
## balcony tile, game/player/balcony_stand.gd), in the climb lab (tools/build_climb_lab.gd), whose
## sheer wall (level 12, cells 3-12, wall rows 5-16) has two: row 11, cells 6-9, with vines from
## the foot to it (column 7) and from it to the rim (column 8); row 8, cells 10-12, under the rim.
## - a drop off the rim over a balcony lands on it, not at the wall's foot;
## - on it the slime walks and stays on its floor; a push off its edge drops it to the foot, unhurt;
## - vines lead from the foot onto a balcony and from it on up to the rim (the Feral skin).
## The lab's climb monsters are taken out first (they knock the slime off).

const TestContext := preload("res://tests/lib/test_context.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const Services := preload("res://game/shared/services.gd")

const MAP_ID := "climb-lab"
const CENTRE_RISE := 27.56
const CELL := 64.0
## The sheer wall's rim and foot (world y).
const RIM_Y := 5.0 * CELL
const FOOT_Y := 17.0 * CELL
## The upper balcony: its middle, its back edge, and how far its floor reaches (0.34 of its width,
## 0.2 deep: VineLayer FLOOR_HALF, FLOOR_DEPTH).
const UPPER_X := 11.5 * CELL
const UPPER_BACK := 8.0 * CELL
const UPPER_WIDTH := 3.0 * CELL
## The lower balcony's back edge, and its vines' columns: from the foot, and on up to the rim.
const LOWER_BACK := 11.0 * CELL
const LOWER_WIDTH := 4.0 * CELL
const UP_TO_IT_X := 7.5 * CELL
const ON_UP_X := 8.5 * CELL


func _enter(t: TestContext) -> bool:
	if not t.in_world(MAP_ID):
		t.main.call(&"travel_to", MAP_ID)
	var arrived := await t.until(func() -> bool: return t.in_world(MAP_ID) and t.player_body() != null, 10000.0)
	await t.steps(8)
	if not t.check(arrived, "could not travel to " + MAP_ID):
		return false
	# The lab's climb monsters (placed 2026-11-16: the Rock Chucker on the rim, a Spiny Caterpillar on
	# the vines from the lower balcony up, the Ledge Raven round the upper balcony) hit and knock the
	# slime off what these tests stand it on: they go first.
	for enemy: Node in t.tree.get_nodes_in_group(&"enemy"):
		var holder := enemy.get_parent()
		if holder != null:
			holder.queue_free()
	await t.steps(2)
	return t.check(t.tree.get_nodes_in_group(&"enemy").is_empty(), "the climb lab's enemies are still there")


## An interact press as a key gives it (held a few frames, then let up): the climb is a toggle
## since 2026-11-24, one press clings and the next lets go; a press let up in the frame it was
## pushed reaches the placed wall but not always the painted vines.
func _tap_interact(t: TestContext) -> void:
	t.press(&"interact")
	await t.steps(3)
	t.release(&"interact")
	await t.steps(1)


func _stand(t: TestContext, feet: Vector2, facing: Vector2) -> void:
	t.release_all()
	t.teleport_player(feet - Vector2(0.0, CENTRE_RISE))
	t.player().face(facing)
	t.world().elevation.track(t.player_body())
	await t.steps(3)


func test_a_drop_off_the_rim_lands_on_the_balcony_under_it(t: TestContext) -> void:
	if not await _enter(t):
		return
	var player := t.player()
	var body := t.player_body()
	var hp := player.get_hp()
	await _stand(t, Vector2(UPPER_X, RIM_Y - 24.0), Vector2.DOWN)
	t.press(&"move_down")
	var landed := await t.until(func() -> bool: return player.is_on_balcony(), 4000.0)
	t.release(&"move_down")
	if not t.check(landed, "the drop off the rim did not land on the balcony (feet %s)" % body.global_position):
		return
	await t.steps(4)
	var feet := body.global_position
	t.check(feet.y > UPPER_BACK and feet.y < UPPER_BACK + UPPER_WIDTH * 0.2 + 1.0, "the slime is not on the balcony's floor (feet %s)" % feet)
	t.equal(player.get_hp(), hp, "the drop onto the balcony cost health")
	# It walks on the floor and stays on it: a walk four fifths of the way to the floor's side edge (a
	# longer one pushes on against the edge for `elevation.dropPushMs` and drops off, as built).
	var speed := Services.constants().number("character.player.movement.baseSpeed")
	t.press(&"move_right")
	await t.sim_wait(UPPER_WIDTH * 0.34 * 0.8 / speed * 1000.0)
	t.release(&"move_right")
	t.check(player.is_on_balcony(), "walking sideways took the slime off the balcony")
	t.check(body.global_position.x > UPPER_X + 10.0, "the slime did not walk on the balcony (feet %s)" % body.global_position)
	t.check(body.global_position.x <= UPPER_X + UPPER_WIDTH * 0.34 + 1.0, "the slime walked past the floor's edge (feet %s)" % body.global_position)
	# A push off its front edge drops it to the wall's foot, unhurt.
	await _stand(t, Vector2(UPPER_X, UPPER_BACK + 20.0), Vector2.DOWN)
	t.check(player.is_on_balcony(), "the slime put on the balcony does not stand on it")
	t.press(&"move_down")
	var down := await t.until(func() -> bool: return not player.is_on_balcony() and body.global_position.y > FOOT_Y, 4000.0)
	t.release(&"move_down")
	await t.steps(6)
	t.check(down, "pushing off the balcony's front did not drop the slime to the wall's foot (feet %s)" % body.global_position)
	t.equal(t.world().elevation.level_of(body), 0, "the level after the drop off the balcony")
	t.check(body.collision_mask != 0, "the slime's collision did not come back")
	t.equal(player.get_hp(), hp, "the drop off the balcony cost health")


func test_vines_lead_onto_a_balcony_and_on_up_from_it(t: TestContext) -> void:
	if not await _enter(t):
		return
	var player := t.player()
	var body := t.player_body()
	SkinState.lend(SkinState.FERAL)
	# From the foot up the vines under the lower balcony: off them onto its floor.
	await _stand(t, Vector2(UP_TO_IT_X, FOOT_Y + 30.0), Vector2.UP)
	await _tap_interact(t)
	if not t.check(await t.until(func() -> bool: return player.is_climbing(), 300.0), "an interact press at the vines' foot did not take hold"):
		t.release_all()
		return
	t.press(&"move_up")
	var on := await t.until(func() -> bool: return player.is_on_balcony(), 6000.0)
	t.release_all()
	await t.steps(4)
	if not t.check(on, "the vines under the balcony did not lead onto it (feet %s)" % body.global_position):
		return
	t.check(body.global_position.y > LOWER_BACK and body.global_position.y < LOWER_BACK + LOWER_WIDTH * 0.2 + 1.0,
		"the slime is not on the lower balcony's floor (feet %s)" % body.global_position)
	# On up: the vines over the balcony, from its floor to the rim.
	await _stand(t, Vector2(ON_UP_X, LOWER_BACK + 24.0), Vector2.UP)
	t.check(player.is_on_balcony(), "the slime put under the upper vines does not stand on the balcony")
	await _tap_interact(t)
	if not t.check(await t.until(func() -> bool: return player.is_climbing(), 300.0), "an interact press on the balcony under the vines did not take hold"):
		t.release_all()
		return
	# Clinging over the balcony it is drawn before the wall (at the depth of the wall's foot), not at
	# the balcony's own, which is behind the wall's face: the wall hid the slime there (2026-11-13).
	await t.steps(4)
	t.check(float(t.world().elevation.flights.get(body, 0.0)) >= FOOT_Y, "the slime clinging over the balcony is drawn behind the wall (depth %s)" % t.world().elevation.flights.get(body, 0.0))
	# A let-go right away (the second press: the climb is a toggle since 2026-11-24) sets it back on
	# the balcony, not at the wall's foot.
	t.press(&"move_up")
	await t.sim_wait(600.0)
	t.release_all()
	await _tap_interact(t)
	t.check(await t.until(func() -> bool: return player.is_on_balcony(), 2000.0), "a let-go over the balcony did not land on it (feet %s)" % body.global_position)
	await _tap_interact(t)
	await t.until(func() -> bool: return player.is_climbing(), 300.0)
	t.press(&"move_up")
	var up := await t.until(func() -> bool: return not player.is_climbing() and body.global_position.y < RIM_Y, 8000.0)
	t.release_all()
	await t.steps(4)
	t.check(up, "the vines over the balcony did not lead up to the rim (feet %s)" % body.global_position)
	t.equal(t.world().elevation.level_of(body), 12, "the slime's level on the top")


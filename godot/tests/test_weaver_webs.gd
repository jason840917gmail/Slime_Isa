extends RefCounted
## The Weaver Hollow's webs (docs/godot/WEBS.md; owner, 2026-10-16, question 131; roadmap 7.9),
## tried in level-1's village chunk, where the ground right of OPEN is open:
## - floor webs (a WebLayer painted here): a walk in them is halved (`webs.floorSlowMultiplier`), a
##   Roll that enters them sticks (rooted `webs.rollStickMs`, where it is), the Silk skin (lent:
##   SkinState, `crosses_webs()`; roadmap 7.8) walks and rolls through at full speed; enemies are not
##   slowed;
## - web walls (`object.web-wall`): solid to a walk and a Roll without the skin, passed at
##   `webs.wallPassMultiplier` with it; a weapon's or shape's hit cuts one open for good only with
##   the skin (a story flag, the secret jingle when it hides a nook), anything else clinks;
## - silk parcels (`object.silk-parcel`): freed only with the skin and a weapon's hit, paying their
##   coins and spilling their items as loot piles, open for good.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const WebLayerScript := preload("res://game/world/webs/web_layer.gd")
const FloorWebsScript := preload("res://game/world/webs/floor_webs.gd")
const WebWallScript := preload("res://game/scripts/web_wall.gd")
const SilkParcelScript := preload("res://game/scripts/silk_parcel.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const WALK_SPEED := 200.0
## Where the checks start (old Phaser centre), as test_player_movement.gd's.
const OPEN := Vector2(640.0, 764.0)
## The old Phaser centre is this far above the feet.
const CENTRE_RISE := 27.56
const PARCEL_COINS := 30
const PARCEL_ITEM := "hp-potion"


## A walk at full speed up to painted web cells, at half speed once the feet are in them.
func test_a_floor_web_halves_a_walk(t: TestContext) -> void:
	t.teleport_player(OPEN)
	await t.steps(2)
	var layer := await _paint(t, OPEN + Vector2(0.0, CENTRE_RISE), Vector2i(2, -1), Vector2i(5, 1))
	t.check(not layer.has_web_at(t.player_body().global_position), "a web under the slime before the field")
	t.press(&"move_right")
	await t.steps(4)
	t.near(t.player_body().velocity.x, WALK_SPEED, 0.01, "walk speed before the webs")
	if not t.check(await t.until(func() -> bool: return layer.has_web_at(t.player_body().global_position), 1500.0),
			"the walk never reached the webs"):
		t.release_all()
		return
	await t.steps(2)
	t.near(t.player_body().velocity.x, WALK_SPEED * _setting("floorSlowMultiplier"), 0.01, "walk speed in a floor web")
	t.release_all()


## An enemy walking in floor webs keeps its speed: only the slime's walk asks the webs.
func test_enemies_are_not_slowed_by_floor_webs(t: TestContext) -> void:
	t.teleport_player(OPEN)
	await t.steps(2)
	await _paint(t, OPEN + Vector2(0.0, CENTRE_RISE), Vector2i(-2, -2), Vector2i(6, 2))
	var worm := t.spawn_worm(Vector2(220.0, 0.0))
	if not t.check(worm != null and worm.movement_speed > 0.0, "no walking worm"):
		return
	var fastest := {"speed": 0.0}
	await t.until(func() -> bool:
		fastest["speed"] = maxf(float(fastest["speed"]), worm.body.velocity.length())
		return float(fastest["speed"]) >= worm.movement_speed - 0.5, 2500.0)
	t.check(float(fastest["speed"]) >= worm.movement_speed - 0.5,
		"the worm walked at %.1f in the webs, its speed is %.1f" % [float(fastest["speed"]), worm.movement_speed])


## A Roll that runs into a floor web sticks there: the roll is over, the slime rooted and still,
## where the web caught it (not set back). With the Silk skin the roll crosses the web and the walk
## keeps its speed.
func test_a_roll_sticks_in_a_floor_web_and_the_silk_slime_crosses(t: TestContext) -> void:
	var player := t.player()
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	var layer := await _paint(t, OPEN + Vector2(0.0, CENTRE_RISE), Vector2i(2, -1), Vector2i(3, 1))
	var events := {"stuck": []}
	layer.roll_stuck.connect(func(payload: Dictionary) -> void: (events["stuck"] as Array).append(payload))
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the roll press did not start a roll"):
		return
	if not t.check(await t.until(func() -> bool: return not (events["stuck"] as Array).is_empty(), 1500.0), "the roll never stuck in the web"):
		return
	t.check(not player.is_rolling(), "the roll goes on in the web")
	t.check(player.is_rooted(), "the rolling slime is not stuck in the web")
	t.check(layer.has_web_at(t.player_body().global_position), "the stuck slime is not in the web (set back?)")
	var stuck_at := player.get_centre()
	await t.steps(3)
	t.check(not player.get_roll().is_bouncing(), "the web bonked the roll")
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.001, "the stuck slime's velocity")
	t.near_vec(player.get_centre(), stuck_at, 1.0, "the stuck slime moved")
	await t.sim_wait(_setting("rollStickMs") + 100.0)
	t.check(not player.is_rooted(), "still rooted after webs.rollStickMs")
	# The Silk skin crosses webs: its walk keeps its speed in them.
	if not await _silk(t):
		return
	t.teleport_player(OPEN)
	await t.steps(2)
	t.press(&"move_right")
	await t.steps(4)
	var silk_walk := t.player_body().velocity.x
	if t.check(await t.until(func() -> bool: return layer.has_web_at(t.player_body().global_position), 1500.0),
			"the Silk slime's walk never reached the webs"):
		await t.steps(2)
		t.near(t.player_body().velocity.x, silk_walk, 0.01, "the Silk slime's walk in a floor web")
	t.release_all()
	await t.steps(2)
	# Its Roll (held, so it rolls on) crosses the whole field without sticking.
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	var before := (events["stuck"] as Array).size()
	var far_edge := layer.to_global(layer.map_to_local(layer.cell_at(OPEN + Vector2(0.0, CENTRE_RISE)) + Vector2i(3, 0))).x + 32.0
	t.press(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the Silk roll did not start"):
		t.release_all()
		return
	var crossed := await t.until(func() -> bool:
		return t.player_body().global_position.x > far_edge or not player.is_rolling(), 3000.0)
	t.check(crossed and t.player_body().global_position.x > far_edge,
		"the Silk roll did not cross the web (feet %s, the web ends at x %.0f)" % [t.player_body().global_position, far_edge])
	t.release_all()
	t.equal((events["stuck"] as Array).size(), before, "the Silk roll stuck in the web")
	t.check(not player.is_rooted(), "the web stuck the Silk slime")


## A web wall in an east door (orientation "side") is solid without the Silk skin: a walk and a Roll
## stop against it.
func test_a_web_wall_blocks_a_walk_and_a_roll(t: TestContext) -> void:
	var player := t.player()
	var wall := await _web_wall(t, OPEN + Vector2(110.0, CENTRE_RISE), "side")
	if wall == null:
		return
	var face := wall.global_position.x - wall.thickness / 2.0
	t.press(&"move_right")
	await t.sim_wait(900.0)
	t.release_all()
	t.check(player.get_centre().x < face, "the walk went into the web wall (%.1f, its face at %.1f)" % [player.get_centre().x, face])
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the roll press did not start a roll"):
		return
	var furthest := {"x": -INF}
	await t.until(func() -> bool:
		furthest["x"] = maxf(float(furthest["x"]), player.get_centre().x)
		return not player.is_rolling(), 2500.0)
	t.check(float(furthest["x"]) < face, "the roll went into the web wall (%.1f, its face at %.1f)" % [float(furthest["x"]), face])
	t.check(not wall.is_cut(), "the web wall is cut")


## With the Silk skin the slime walks through a web wall at half its walk, and on at full speed.
func test_the_silk_slime_passes_a_web_wall_at_half_speed(t: TestContext) -> void:
	var player := t.player()
	if not await _silk(t):
		return
	var wall := await _web_wall(t, OPEN + Vector2(110.0, CENTRE_RISE), "side")
	if wall == null:
		return
	t.teleport_player(OPEN)
	await t.steps(2)
	t.press(&"move_right")
	await t.steps(4)
	var silk_walk := t.player_body().velocity.x
	t.check(silk_walk > 0.0, "the Silk slime does not walk")
	var inside := await t.until(func() -> bool: return wall.in_passage(t.player_body().global_position), 1500.0)
	if t.check(inside, "the Silk slime never reached the web wall"):
		await t.steps(2)
		t.near(t.player_body().velocity.x, silk_walk * _setting("wallPassMultiplier"), 0.01, "the Silk slime's walk through a web wall")
	var through := await t.until(func() -> bool: return t.player_body().global_position.x > wall.global_position.x + wall.thickness + 24.0, 3000.0)
	t.check(through, "the Silk slime did not get through the web wall (feet %s, the wall at %s)" % [
		t.player_body().global_position, wall.global_position])
	await t.steps(3)
	t.near(t.player_body().velocity.x, silk_walk, 0.01, "the Silk slime's walk past the web wall")
	t.release_all()
	t.check(not wall.is_cut(), "passing cut the web wall")


## A weapon's hit clinks without the Silk skin; with it a throw still clinks and a weapon's hit cuts
## the wall open for good: its flag set, the secret jingle when it hides a nook, the solid gone,
## and the same wall built again is cut.
func test_a_spear_cuts_a_web_wall_for_good_only_with_the_silk_skin(t: TestContext) -> void:
	var wall := await _web_wall(t, OPEN + Vector2(0.0, -120.0), "across", "web-wall.test-nook")
	if wall == null:
		return
	wall.hides_secret = true
	var area := wall.get_node_or_null(^"DamageArea") as Area2D
	if not t.check(area != null, "the web wall has no hurtbox"):
		return
	var refused := {"count": 0}
	wall.refused.connect(func(_payload: Dictionary) -> void: refused["count"] = int(refused["count"]) + 1)
	var result := _hit(t, area, ["weapon", "spear"])
	t.equal(str(result.get("reason", "")), "immune", "a spear hit without the Silk skin")
	t.check(not wall.is_cut(), "a spear cut the web wall without the Silk skin")
	t.equal(int(refused["count"]), 1, "refusals of the web wall")
	if not await _silk(t):
		return
	result = _hit(t, area, ["thrown", "rock"])
	t.equal(str(result.get("reason", "")), "immune", "a thrown rock with the Silk skin")
	t.check(not wall.is_cut(), "a throw cut the web wall")
	var secret := _global_cue("SecretFound")
	if secret != null:
		TestContext.silence(secret)
	result = _hit(t, area, ["weapon", "spear"])
	t.equal(str(result.get("status", "")), "accepted", "a spear hit with the Silk skin")
	t.check(wall.is_cut(), "a spear hit with the Silk skin did not cut the web wall")
	t.check(Services.run().has_flag("web-wall.test-nook"), "the cut web wall's flag is not set")
	t.check(wall.get_node_or_null(^"Solid") == null or (wall.get_node(^"Solid") as Node).is_queued_for_deletion(), "the cut web wall is still solid")
	if secret != null:
		await t.steps(2)
		t.check(TestContext.played(secret), "no secret jingle for a web wall that hides a nook")
	t.check(bool(wall.get_damage_state().get("dead", false)), "a cut web wall still takes hits")
	var again := await _web_wall(t, OPEN + Vector2(0.0, -120.0), "across", "web-wall.test-nook")
	if again != null:
		t.check(again.is_cut(), "a cut web wall is whole again")
		t.check(again.get_node_or_null(^"Solid") == null, "a cut web wall built again is solid")


## A silk parcel clinks without the Silk skin; with it a weapon's hit frees it: its coins paid,
## its item spilled as a loot pile, its flag set, and it stays open.
func test_a_silk_parcel_frees_its_coins_and_items_only_with_the_silk_skin(t: TestContext) -> void:
	var run := Services.run()
	var parcel := await _parcel(t, OPEN + Vector2(0.0, -120.0))
	if parcel == null:
		return
	var area := parcel.get_node_or_null(^"DamageArea") as Area2D
	if not t.check(area != null, "the parcel has no hurtbox"):
		return
	var coins := run.coins()
	var result := _hit(t, area, ["weapon", "spear"])
	t.equal(str(result.get("reason", "")), "immune", "a spear hit on a parcel without the Silk skin")
	t.check(not parcel.is_open(), "a parcel opened without the Silk skin")
	t.equal(run.coins(), coins, "coins after a refused hit")
	if not await _silk(t):
		return
	result = _hit(t, area, ["thrown", "rock"])
	t.check(not parcel.is_open(), "a throw freed the parcel")
	var events := {"freed": []}
	parcel.freed.connect(func(payload: Dictionary) -> void: (events["freed"] as Array).append(payload))
	result = _hit(t, area, ["weapon", "spear"])
	t.equal(str(result.get("status", "")), "accepted", "a spear hit on a parcel with the Silk skin")
	t.check(parcel.is_open(), "the parcel did not open")
	t.equal(run.coins(), coins + PARCEL_COINS, "coins after freeing the parcel")
	t.check(run.has_flag("silk-parcel.test"), "the freed parcel's flag is not set")
	t.equal((events["freed"] as Array).size(), 1, "freed signals")
	await t.steps(2)
	var spilled := run.inventory_drops(t.world().map_id()).filter(func(record: Dictionary) -> bool:
		return str(record.get("item_id", "")) == PARCEL_ITEM)
	t.check(not spilled.is_empty() or run.item_count(PARCEL_ITEM) > 0, "the parcel's %s was not spilled" % PARCEL_ITEM)
	var again := await _parcel(t, OPEN + Vector2(96.0, -120.0))
	if again != null:
		t.check(again.is_open(), "a freed parcel is closed again")
		t.check(again.get_node_or_null(^"DamageArea") == null, "a freed parcel built again takes hits")


# --- helpers -----------------------------------------------------------------------------------------

## A WebLayer under the world root with the cells `from` to `to` (inclusive, relative to the cell
## of `at`) painted with the auto web.
func _paint(t: TestContext, at: Vector2, from: Vector2i, to: Vector2i) -> WebLayerScript:
	var layer := WebLayerScript.new()
	layer.name = "webs"
	layer.tile_set = load(WebLayerScript.TILESET)
	t.world().world_root.add_child(layer)
	var origin := layer.cell_at(at)
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			layer.set_cell(origin + Vector2i(x, y), 0, Vector2i(0, 0))
	await t.steps(2)
	return layer


## An `object.web-wall` at `at` (its root), built before it enters the world.
func _web_wall(t: TestContext, at: Vector2, orientation: String, flag: String = "") -> WebWallScript:
	var wall := t.world().instantiate_scene("object.web-wall") as WebWallScript
	if not t.check(wall != null, "object.web-wall did not instantiate"):
		return null
	wall.orientation = orientation
	wall.flag_id = flag
	wall.position = at
	t.world().world_root.add_child(wall)
	await t.steps(2)
	return wall


func _parcel(t: TestContext, at: Vector2) -> SilkParcelScript:
	var parcel := t.world().instantiate_scene("object.silk-parcel") as SilkParcelScript
	if not t.check(parcel != null, "object.silk-parcel did not instantiate"):
		return null
	parcel.coins = PARCEL_COINS
	parcel.contents = {PARCEL_ITEM: 1}
	parcel.flag_id = "silk-parcel.test"
	parcel.position = at
	t.world().world_root.add_child(parcel)
	await t.steps(2)
	return parcel


## Lends the Silk skin (SkinState, roadmap 7.8: `crosses_webs()`).
func _silk(t: TestContext) -> bool:
	var player := t.player()
	await t.sim_wait(50.0)
	SkinState.lend(SkinState.SILK)
	await t.steps(1)
	return t.check(player.crosses_webs(), "the Silk skin did not make the slime cross webs")


## A hit with `tags` routed to `target_area` from a stand-in weapon (its knockback makes a 0-damage
## hit land); the result.
func _hit(t: TestContext, target_area: Area2D, tags: Array) -> Dictionary:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	var result := router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": target_area,
		"weapon_id": "test-spear", "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 10.0,
		"effects": [{"effect_id": "knockback", "potency": 100.0}],
		"impact": {"position": target_area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
	return result


static func _global_cue(cue: String) -> Node:
	var feel := Services.feel()
	var audio: Node = feel.global_audio() if feel != null else null
	return audio.find_child(cue, true, false) if audio != null else null


static func _setting(name: String) -> float:
	return FloorWebsScript.setting(name)

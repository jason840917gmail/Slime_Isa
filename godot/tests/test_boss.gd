extends RefCounted
## Fatty One Eye and the level-1 boss camp (docs/godot/specs/boss.md).
## Camp `level-1-fatty-one-eye-camp` at (2528, 1472): activation circle r 440, arena circle r 420,
## boss spawned at the camp origin (old Phaser position; feet 42 px lower). Fatty: 140 hp,
## spear-only, knockback immune; contact hop (impact +250 ms -> 18 - 3 = 15, hop ends +300 ms,
## cooldown 1000); leap 5000 ms after spawn: small hops 1080 ms, airborne 1000 ms, landing 360 ms
## (32 - 3 = 29 on a hurtbox in the splash), recovery 700 ms; state-blocked while hopping or airborne.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const BossCampScript := preload("res://game/scripts/boss_camp.gd")
const FattyScript := preload("res://game/scripts/fatty.gd")
const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")
const EffectScript := preload("res://game/scripts/effect.gd")

const CAMP_ID := "level-1-fatty-one-eye-camp"
const BOSS_ID := "fatty-one-eye"
const CAMP := Vector2(2528.0, 1472.0)
const ACTIVATION_RADIUS := 440.0
const ARENA_RADIUS := 420.0
const FATTY_DEPTH_ANCHOR := Vector2(0.0, 42.0)
const MAX_HP := 140.0
## Inside the arena, 380 px south of the camp: far enough that 5 s of chasing at 42 px/s
## (210 px) never brings the contact area onto the player.
const FAR_INSIDE := Vector2(2528.0, 1852.0)
## Outside the arena (r 420) but inside the activation circle (r 440).
const OUTSIDE_ARENA := Vector2(2528.0, 1902.0)
## Player centre relative to Fatty: inside the contact ellipse (centre (1, -25), radii
## 83.5 x 52) with the hurtbox, clear of Fatty's body box.
const CONTACT_OFFSET := Vector2(75.0, -40.0)
const PLAYER_DEFENSE_HIT_CONTACT := 15
const PLAYER_DEFENSE_HIT_LANDING := 29
## A world without boss camps, reachable from level-1 (test_travel.gd).
const TRAVEL_MAP := "gloop-forest"
const STEP := TestContext.STEP_MS
const SLACK := TestContext.STEP_MS + 0.01


func test_camp_geometry_spawn_and_health_bar(t: TestContext) -> void:
	var camp := _camp(t)
	if not t.check(camp != null, "level-1 has no boss camp '%s'" % CAMP_ID):
		return
	var activation := camp.activation_perimeter()
	var arena := camp.arena_perimeter()
	t.equal(str(activation.get("shape", "")), "circle", "activation shape")
	t.near_vec(Vector2(float(activation.get("x", 0)), float(activation.get("y", 0))), CAMP, 0.01, "activation centre")
	t.near(float(activation.get("radius", 0)), ACTIVATION_RADIUS, 0.01, "activation radius")
	t.near_vec(Vector2(float(arena.get("x", 0)), float(arena.get("y", 0))), CAMP, 0.01, "arena centre")
	t.near(float(arena.get("radius", 0)), ARENA_RADIUS, 0.01, "arena radius")
	_check_open_ground(t, [FAR_INSIDE, OUTSIDE_ARENA, CAMP])
	# The player starts far away: nothing spawns.
	await t.steps(10)
	t.check(not camp.has_live_boss(), "the boss spawned with the player outside the activation circle")
	var bar := _bar(t)
	if not t.check(bar != null, "the HUD has no boss health bar"):
		return
	t.equal(bool(bar.snapshot()["visible"]), false, "boss bar visible before the fight")
	var events := {"spawn": [], "engaged": []}
	camp.boss_spawn_requested.connect(func(payload: Dictionary) -> void: (events["spawn"] as Array).append(payload))
	camp.boss_engaged.connect(func(payload: Dictionary) -> void: (events["engaged"] as Array).append(payload))

	t.teleport_player(FAR_INSIDE)
	var spawned := await t.until(func() -> bool: return camp.has_live_boss(), 200.0)
	if not t.check(spawned, "no boss spawned after entering the activation circle"):
		return
	var fatty := camp.get_live_boss() as FattyScript
	if not t.check(fatty != null, "the live boss is not a FattyScript"):
		return
	t.near_vec(fatty.get_centre(), CAMP, 1.0, "boss position (old Phaser centre)")
	t.near_vec(fatty.body.global_position, CAMP + FATTY_DEPTH_ANCHOR, 1.0, "boss feet")
	t.equal(fatty.get_phase(), FattyScript.PHASE_CHASE, "phase after spawn")
	t.equal(fatty.get_arena().get("radius", 0.0), ARENA_RADIUS, "arena handed to the boss")
	t.equal((events["spawn"] as Array).size(), 1, "boss_spawn_requested emissions")
	if not (events["spawn"] as Array).is_empty():
		var request: Dictionary = events["spawn"][0]
		t.equal(request.get("sceneId", ""), "character.fatty-one-eye", "spawn request scene")
		t.equal(request.get("bossId", ""), BOSS_ID, "spawn request boss")
	t.equal((events["engaged"] as Array).size(), 1, "boss_engaged emissions")
	t.equal(Services.router().tags_for_area(fatty.damage_area), ["enemy", "boss"], "boss hurtbox target tags")
	await t.steps(2)
	var model: Dictionary = bar.snapshot()
	t.equal(bool(model["visible"]), true, "boss bar visible during the fight")
	t.equal(str(model["name"]), "Fatty One Eye", "boss bar name")
	t.near(float(model["hp"]), MAX_HP, 0.01, "boss bar hp")
	t.near(float(model["maxHp"]), MAX_HP, 0.01, "boss bar max")
	t.check(bar.visible, "boss bar Control is hidden")


func test_spear_only_no_stun_and_bar_follows_hp(t: TestContext) -> void:
	var fight := await _start_fight(t, FAR_INSIDE)
	if fight.is_empty():
		return
	var fatty: FattyScript = fight["fatty"]
	var sword := _hit(t, fatty, 24.0, ["weapon"], 140.0)
	t.equal(sword.get("reason", ""), "source-blocked", "sword hit on Fatty")
	t.near(_hp(fatty), MAX_HP, 0.01, "hp after a sword hit")
	var spear := _hit(t, fatty, 30.0, ["spear"], 200.0)
	t.equal(spear.get("status", ""), "accepted", "spear hit status")
	t.equal(int(spear.get("actual_damage", 0)), 30, "spear hit damage")
	t.equal(spear.get("applied_effects", []), [], "applied effects (knockback immune)")
	t.equal(spear.get("rejected_effects", []), [{"effect_id": "knockback", "reason": "immune"}], "rejected effects")
	t.near(_hp(fatty), MAX_HP - 30.0, 0.01, "hp after a spear hit")
	await t.steps(2)
	# No stun, no shove, the phase flow goes on: still chasing toward the player.
	t.equal(fatty.get_phase(), FattyScript.PHASE_CHASE, "phase after a hit")
	t.equal(fatty.get_runtime_state(), "chase", "AI state after a hit")
	var toward := (FAR_INSIDE - fatty.get_centre()).normalized() * fatty.movement_speed
	t.near_vec(fatty.body.velocity, toward, 0.5, "chase velocity after a hit")
	t.near(float(_bar(t).snapshot()["hp"]), MAX_HP - 30.0, 0.01, "boss bar hp after a hit")


func test_contact_hop_timing_damage_and_immunity(t: TestContext) -> void:
	var camp := _camp(t)
	if not t.check(camp != null, "no boss camp"):
		return
	t.teleport_player(CAMP + CONTACT_OFFSET)
	var phase_log: Array = []
	var hits: Array = []
	var player := t.player()
	player.damaged.connect(func(commit: Dictionary) -> void:
		hits.append({"now": t.now(), "damage": int((commit["result"] as Dictionary).get("actual_damage", 0))}))
	var spawned := await t.until(func() -> bool: return camp.has_live_boss(), 200.0)
	if not t.check(spawned, "no boss spawned"):
		return
	var fatty := camp.get_live_boss() as FattyScript
	fatty.phase_changed.connect(func(payload: Dictionary) -> void: phase_log.append(payload))
	var hopped := await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_CONTACT_HOP, 200.0)
	if not t.check(hopped, "no contact hop with the player inside the contact area (phases %s)" % [phase_log]):
		return
	var hop_at := fatty.get_phase_started_at()
	var boss_at := fatty.get_centre()
	# Telegraph: the contact ellipse (centre (1, -25), radii 83.5 x 52) and a shadow at Fatty.
	var telegraph := AttackTelegraph.of(fatty)
	if t.check(telegraph != null, "no telegraph during the contact hop"):
		t.near_vec(telegraph.shadow_point(), boss_at, 0.5, "contact-hop shadow")
		var outlines := telegraph.world_outlines()
		if t.equal(outlines.size(), 1, "contact-hop telegraph shapes"):
			var box := _bounds(outlines[0])
			t.near_vec(box.get_center(), boss_at + Vector2(1.0, -25.0), 1.0, "contact telegraph centre")
			t.near_vec(box.size, Vector2(167.0, 104.0), 1.0, "contact telegraph size")
	t.equal(fatty.can_receive_damage({}).get("reason", ""), "state-blocked", "damage during the contact hop")
	t.equal(fatty.body.collision_layer, 0, "body collision during the hop")
	var crack_count_before := _effects(t, "boss-ground-crack").size()
	await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_CHASE, 500.0)
	t.between(fatty.get_phase_started_at() - hop_at, 300.0, 300.0 + SLACK, "contact hop length (ms)")
	t.check(AttackTelegraph.of(fatty) == null, "the contact telegraph outlived the hop")
	t.check(fatty.body.collision_layer != 0, "body collision not restored after the hop")
	var cracks := _effects(t, "boss-ground-crack")
	if t.equal(cracks.size(), crack_count_before + 1, "ground cracks after the hop"):
		var crack_root := (cracks[cracks.size() - 1] as Node).get_parent() as Node2D
		t.near_vec(crack_root.global_position, boss_at, 1.0, "crack position (Fatty's old position)")
	if t.check(not hits.is_empty(), "the contact hop never hit the player"):
		t.equal(int(hits[0]["damage"]), PLAYER_DEFENSE_HIT_CONTACT, "contact hop damage to the player")
		t.between(float(hits[0]["now"]) - hop_at, 250.0, 250.0 + SLACK, "contact hop impact time (ms)")
	# The next hop waits for the 1000 ms cooldown (attack cooldown and hop cooldown).
	t.teleport_player(fatty.get_centre() + CONTACT_OFFSET)
	var second := await t.until(func() -> bool:
		return fatty.get_phase() == FattyScript.PHASE_CONTACT_HOP and fatty.get_phase_started_at() > hop_at, 1600.0)
	if t.check(second, "no second contact hop"):
		t.between(fatty.get_phase_started_at() - hop_at, 1000.0, 1000.0 + 2.0 * SLACK, "contact hop cadence (ms)")


func test_leap_telegraph_flight_landing_and_cadence(t: TestContext) -> void:
	var fight := await _start_fight(t, FAR_INSIDE)
	if fight.is_empty():
		return
	var fatty: FattyScript = fight["fatty"]
	var spawned_at := t.now()
	var phase_log: Array = []
	fatty.phase_changed.connect(func(payload: Dictionary) -> void: phase_log.append(payload))
	var hits: Array = []
	t.player().damaged.connect(func(commit: Dictionary) -> void:
		hits.append({"now": t.now(), "damage": int((commit["result"] as Dictionary).get("actual_damage", 0))}))
	var crack_count_before := _effects(t, "boss-ground-crack").size()
	var hopping := await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_SMALL_HOP, 5600.0)
	if not t.check(hopping, "no leap within 5.6 s of the spawn (phases %s)" % [phase_log]):
		return
	t.between(fatty.get_phase_started_at() - spawned_at, 5000.0 - SLACK, 5000.0 + 2.0 * SLACK, "first leap after spawn (ms)")
	t.check(hits.is_empty(), "the player was hit before the leap (place the player further away)")
	var hop_at := fatty.get_phase_started_at()
	t.near_vec(fatty.body.velocity, Vector2.ZERO, 0.01, "velocity during the small hops")
	await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_AIRBORNE, 1300.0)
	if not t.equal(fatty.get_phase(), FattyScript.PHASE_AIRBORNE, "phase after the small hops"):
		return
	var airborne_at := fatty.get_phase_started_at()
	t.between(airborne_at - hop_at, 1080.0, 1080.0 + SLACK, "small hops length (ms)")
	var from := fatty.get_leap_from()
	var target := fatty.get_leap_target()
	t.near_vec(target, t.player().get_centre(), 0.5, "leap target = player centre (inside the arena)")
	t.equal(fatty.can_receive_damage({}).get("reason", ""), "state-blocked", "damage while airborne")
	var telegraph := AttackTelegraph.of(fatty)
	if t.check(telegraph != null, "no landing telegraph while airborne"):
		t.near_vec(telegraph.shadow_point(), target, 0.5, "landing shadow")
		var outlines := telegraph.world_outlines()
		if t.equal(outlines.size(), 1, "landing telegraph shapes"):
			var box := _bounds(outlines[0])
			t.near_vec(box.get_center(), target, 1.0, "landing telegraph centre (the zone moved onto the target)")
			t.near_vec(box.size, Vector2(221.0, 121.0), 1.0, "landing telegraph size")
	# Mid-flight: a straight line from the take-off point to the target.
	await t.until(func() -> bool: return t.now() - airborne_at >= 500.0, 600.0)
	var progress := minf(1.0, (t.now() - airborne_at) / 1000.0)
	t.near_vec(fatty.get_centre(), from + (target - from) * progress, 1.5, "airborne position at %.0f ms" % (t.now() - airborne_at))
	await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_LANDING, 700.0)
	if not t.equal(fatty.get_phase(), FattyScript.PHASE_LANDING, "phase after the flight"):
		return
	var landed_at := fatty.get_phase_started_at()
	t.between(landed_at - airborne_at, 1000.0, 1000.0 + SLACK, "flight length (ms)")
	t.check(AttackTelegraph.of(fatty) == null, "the landing telegraph outlived the landing")
	var world := t.world()
	t.check(world.camera != null and world.camera.is_shaking(), "no camera shake on landing")
	var landing_hits := hits.filter(func(hit: Dictionary) -> bool: return absf(float(hit["now"]) - landed_at) < 0.01)
	if t.equal(landing_hits.size(), 1, "landing hits on the player"):
		t.equal(int(landing_hits[0]["damage"]), PLAYER_DEFENSE_HIT_LANDING, "landing damage to the player")
	var cracks := _effects(t, "boss-ground-crack")
	if t.equal(cracks.size(), crack_count_before + 1, "ground cracks after the landing"):
		var crack_root := (cracks[cracks.size() - 1] as Node).get_parent() as Node2D
		t.near_vec(crack_root.global_position, target, 1.0, "landing crack position")
	await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_RECOVERY, 500.0)
	t.between(fatty.get_phase_started_at() - landed_at, 360.0, 360.0 + SLACK, "landing length (ms)")
	var recovery_at := fatty.get_phase_started_at()
	await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_CHASE, 900.0)
	t.between(fatty.get_phase_started_at() - recovery_at, 700.0, 700.0 + SLACK, "recovery length (ms)")
	t.near(fatty.get_next_leap_at(), fatty.get_phase_started_at() + 5000.0, 0.01, "next leap = recovery end + 5000")
	var phases: Array = phase_log.map(func(entry: Dictionary) -> String: return str(entry["phase"]))
	t.equal(phases, ["small-hop", "airborne", "landing", "recovery", "chase"], "phase sequence")


func test_arena_leash_return_and_full_heal(t: TestContext) -> void:
	var fight := await _start_fight(t, FAR_INSIDE)
	if fight.is_empty():
		return
	var fatty: FattyScript = fight["fatty"]
	_hit(t, fatty, 50.0, ["spear"], 0.0)
	t.near(_hp(fatty), MAX_HP - 50.0, 0.01, "hp after the test hit")
	# Shorten the 60 s recovery for the test (the authored value is checked separately).
	t.near(fatty.arena_recovery_ms, 60000.0, 0.01, "authored arenaRecoveryMs")
	fatty.arena_recovery_ms = 400.0
	await t.steps(30)
	t.teleport_player(OUTSIDE_ARENA)
	var left_at := t.now()
	var returning := await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_RETURN, 200.0)
	if not t.check(returning, "Fatty did not start returning when the player left the arena"):
		return
	t.check(fatty.is_returning_to_arena(), "is_returning_to_arena() during the return")
	var to_centre := CAMP - fatty.get_centre()
	if to_centre.length() > 2.0:
		t.near_vec(fatty.body.velocity, to_centre.normalized() * fatty.movement_speed, 0.5, "return velocity")
	await t.until(func() -> bool: return _hp(fatty) >= MAX_HP, 600.0)
	t.near(_hp(fatty), MAX_HP, 0.01, "hp after %.0f ms outside the arena" % (t.now() - left_at))
	t.check(t.now() - left_at >= 400.0 - SLACK, "healed before arena_recovery_ms")
	await t.until(func() -> bool: return fatty.get_centre().distance_to(CAMP) < 0.5, 3000.0)
	t.near_vec(fatty.get_centre(), CAMP, 0.5, "Fatty back at the arena centre")
	t.near_vec(fatty.body.velocity, Vector2.ZERO, 0.01, "velocity at the arena centre")
	await t.steps(2)
	t.near(float(_bar(t).snapshot()["hp"]), MAX_HP, 0.01, "boss bar after the heal")
	t.teleport_player(FAR_INSIDE)
	var resumed := await t.until(func() -> bool: return fatty.get_phase() == FattyScript.PHASE_CHASE, 200.0)
	t.check(resumed, "Fatty did not resume the chase when the player came back")


func test_defeat_death_clip_rewards_and_respawn_rule(t: TestContext) -> void:
	var fight := await _start_fight(t, FAR_INSIDE)
	if fight.is_empty():
		return
	var camp: BossCampScript = fight["camp"]
	var fatty: FattyScript = fight["fatty"]
	var root_id := fatty.body.get_instance_id()
	var events := {"defeated": [], "disengaged": [], "guard": []}
	camp.boss_defeated.connect(func(payload: Dictionary) -> void: (events["defeated"] as Array).append(payload))
	camp.boss_disengaged.connect(func(payload: Dictionary) -> void: (events["disengaged"] as Array).append(payload))
	camp.guard_changed.connect(func(payload: Dictionary) -> void: (events["guard"] as Array).append(payload))
	var hits := 0
	while not fatty.is_defeated() and hits < 6:
		_hit(t, fatty, 30.0, ["spear"], 0.0)
		hits += 1
	if not t.check(fatty.is_defeated(), "Fatty survived %d spear hits" % hits):
		return
	t.equal(hits, 5, "spear hits (30) to defeat 140 hp")
	var died_at := t.now()
	t.equal(fatty.get_phase(), FattyScript.PHASE_DEAD, "phase after defeat")
	t.equal(String(fatty.animation.current_animation), "death", "clip after defeat")
	await t.steps(2)
	t.check(not camp.has_live_boss(), "the camp still has a live boss after the defeat")
	t.check(camp.is_boss_defeated(), "the camp did not record the defeat")
	t.equal(events["defeated"], [{"campId": CAMP_ID, "bossId": BOSS_ID}], "boss_defeated payloads")
	t.equal(events["disengaged"], [{"campId": CAMP_ID, "defeated": true}], "boss_disengaged payloads")
	t.equal(events["guard"], [{"instanceId": "level-1-fatty-guarded-chest", "guarded": false}], "guard_changed payloads")
	t.equal(bool(_bar(t).snapshot()["visible"]), false, "boss bar after the defeat")
	var ready_at := camp.get_respawn_ready_at()
	t.near(ready_at, BossCampScript.epoch_now_ms() + 180000.0, 5000.0, "respawn ready (epoch ms)")
	# Progress lives in RunState (Phaser WorldProgress), so it outlives the world.
	var run := Services.run()
	if t.check(run != null, "no RunState autoload"):
		t.check(BOSS_ID in (run.world["defeated_boss_ids"] as Array), "RunState defeated_boss_ids lacks the boss")
		var camps: Dictionary = run.map_record("level-1")["boss_camps"]
		t.near(float((camps.get(CAMP_ID, {}) as Dictionary).get("respawn_ready_at_epoch_ms", -1.0)), ready_at, 0.01,
			"RunState boss_camps respawn time")
	# The body stays 2 s (owner decision: the death clip, then its last frame), fades out over the
	# last 0.3 s, then frees itself.
	var corpse := instance_from_id(root_id) as CanvasItem
	if corpse != null:
		await t.until(func() -> bool: return not is_instance_id_valid(root_id) or t.now() - died_at >= 1850.0, 2500.0)
		if is_instance_id_valid(root_id):
			t.check(corpse.modulate.a < 0.99, "the dead boss is not fading out near the end")
	await t.until(func() -> bool: return not is_instance_id_valid(root_id), 1000.0)
	t.check(not is_instance_id_valid(root_id), "the defeated boss was never freed")
	t.between(t.now() - died_at, 2000.0 - SLACK, 2000.0 + 2.0 * SLACK, "dead body lifetime (ms)")
	# Respawn: never while the player stays inside; needs a visit outside and the 180 s timer.
	await t.steps(10)
	t.check(not camp.has_live_boss(), "the boss respawned with the player still inside")
	t.check(not camp.evaluate_activation(true, ready_at + 1.0), "respawned without the player leaving first")
	t.teleport_player(t.world().player_spawn_marker())
	await t.steps(3)
	t.teleport_player(FAR_INSIDE)
	await t.steps(3)
	t.check(not camp.has_live_boss(), "respawned before the 180 s timer")
	t.check(camp.evaluate_activation(true, ready_at + 1.0), "no respawn once the timer passed after a visit outside")
	var fresh := camp.get_live_boss()
	if t.check(fresh != null, "no fresh boss after the respawn"):
		t.near(_hp(fresh), MAX_HP, 0.01, "respawned boss hp")


func test_player_death_resets_the_fight(t: TestContext) -> void:
	var fight := await _start_fight(t, FAR_INSIDE)
	if fight.is_empty():
		return
	var camp: BossCampScript = fight["camp"]
	var fatty: FattyScript = fight["fatty"]
	var root_id := fatty.body.get_instance_id()
	_hit(t, fatty, 60.0, ["spear"], 0.0)
	var disengaged: Array = []
	camp.boss_disengaged.connect(func(payload: Dictionary) -> void: disengaged.append(payload))
	# Kill the player outright (any hostile source).
	var player := t.player()
	var router := Services.router()
	var areas: Array[Area2D] = [fatty.attack_area]
	var activation := router.begin_activation(fatty, areas)
	router.route({"activation_id": activation, "source": fatty, "attack_area": fatty.attack_area,
		"target_area": player.get_damage_area(), "weapon_id": "test", "weapon_tags": ["test"],
		"damage_types": ["physical"], "base_damage": 1000.0, "effects": [],
		"impact": {"position": fatty.get_centre(), "knock": Vector2.ZERO}})
	router.end_activation(activation)
	if not t.check(player.is_dead(), "the player survived 1000 damage"):
		return
	t.check(not camp.has_live_boss(), "the fight did not reset when the player died")
	t.equal(disengaged, [{"campId": CAMP_ID, "defeated": false}], "boss_disengaged on reset")
	await t.steps(2)
	t.check(not is_instance_id_valid(root_id), "the boss was not removed on reset")
	t.equal(bool(_bar(t).snapshot()["visible"]), false, "boss bar after the reset")
	t.check(camp.get_respawn_ready_at() < 0.0, "a reset set a respawn timer")
	# The dead player still stands inside: no spawn until they have been outside.
	await t.steps(20)
	t.check(not camp.has_live_boss(), "the boss spawned again while the dead player stayed inside")
	var respawned := await t.until(func() -> bool: return not player.is_dead(), 3000.0)
	if not t.check(respawned, "the player did not respawn"):
		return
	await t.steps(3)
	t.check(not camp.has_live_boss(), "the boss spawned with the player at the spawn point")
	t.teleport_player(FAR_INSIDE)
	var again := await t.until(func() -> bool: return camp.has_live_boss(), 200.0)
	if t.check(again, "no fresh boss after walking back in"):
		t.near(_hp(camp.get_live_boss()), MAX_HP, 0.01, "fresh boss hp after the reset")


## World travel frees the world root with the camp and its live boss: nothing dangles, the bar hides.
func test_world_travel_removes_the_fight(t: TestContext) -> void:
	var fight := await _start_fight(t, FAR_INSIDE)
	if fight.is_empty():
		return
	var fatty: FattyScript = fight["fatty"]
	var fatty_id := fatty.get_instance_id()
	await t.steps(5)
	t.equal(bool(_bar(t).snapshot()["visible"]), true, "boss bar before travelling")
	if not t.check(t.main.travel_to(TRAVEL_MAP, "west"), "travel to %s was refused" % TRAVEL_MAP):
		return
	var travelled := await t.until(func() -> bool: return t.world().map_id() == TRAVEL_MAP and t.player() != null, 3000.0, 6000.0)
	if not t.check(travelled, "the player did not reach %s" % TRAVEL_MAP):
		return
	await t.steps(3)
	t.check(not is_instance_id_valid(fatty_id), "the boss outlived its world")
	t.equal(bool(_bar(t).snapshot()["visible"]), false, "boss bar after travelling")
	t.check(_camp(t) == null, "a level-1 boss camp outlived its world")


# --- helpers ------------------------------------------------------------------------------------

static func _camp(t: TestContext) -> BossCampScript:
	for node: Node in t.tree.get_nodes_in_group(BossCampScript.GROUP):
		var camp := node as BossCampScript
		if camp != null and camp.camp_id == CAMP_ID:
			return camp
	return null


static func _bar(t: TestContext) -> Node:
	var hud: Node = t.main.get_node_or_null(^"Hud") if t.main != null else null
	return hud.call(&"get_boss_bar") if hud != null and hud.has_method(&"get_boss_bar") else null


## Puts the player at `player_centre` (inside the activation circle) and waits for the boss.
static func _start_fight(t: TestContext, player_centre: Vector2) -> Dictionary:
	var camp := _camp(t)
	if not t.check(camp != null, "level-1 has no boss camp '%s'" % CAMP_ID):
		return {}
	t.teleport_player(player_centre)
	var spawned := await t.until(func() -> bool: return camp.has_live_boss(), 200.0)
	if not t.check(spawned, "no boss spawned with the player at %s" % player_centre):
		return {}
	var fatty := camp.get_live_boss() as FattyScript
	if not t.check(fatty != null, "the live boss is not a FattyScript"):
		return {}
	return {"camp": camp, "fatty": fatty}


## One weapon hit on Fatty's eye through the damage router, from the player (its own activation).
static func _hit(t: TestContext, fatty: FattyScript, damage: float, tags: Array, knockback: float) -> Dictionary:
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [player.get_damage_area()]
	var activation := router.begin_activation(player, areas)
	var effects: Array = []
	if knockback > 0.0:
		effects.append({"effect_id": "knockback", "potency": knockback})
	var result := router.route({"activation_id": activation, "source": player,
		"attack_area": player.get_damage_area(), "target_area": fatty.damage_area,
		"weapon_id": "test-" + str(tags[0]), "weapon_tags": tags, "damage_types": ["physical"],
		"base_damage": damage, "effects": effects,
		"impact": {"position": fatty.get_centre(), "knock": Vector2(1.0, 0.0)}})
	router.end_activation(activation)
	return result


static func _hp(enemy: Object) -> float:
	return float((enemy.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


static func _effects(t: TestContext, effect_id: String) -> Array:
	var found: Array = []
	for node: Node in t.world().entities_root().find_children("*", "Node", true, false):
		if node is EffectScript and (node as EffectScript).effect_id == effect_id and not node.is_queued_for_deletion():
			found.append(node)
	return found


static func _bounds(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		box = box.expand(point)
	return box


static func _check_open_ground(t: TestContext, points: Array) -> void:
	var world := t.world()
	var tile := float(world.dimensions()["tile_size"])
	for point: Vector2 in points:
		t.check(not world.is_solid_tile(floori(point.x / tile), floori(point.y / tile)), "%s is on a solid tile" % point)

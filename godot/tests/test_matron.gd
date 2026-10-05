extends RefCounted
## The Orb-Weaver Matron, her gloop-forest nest camp, web patches and web barriers
## (docs/godot/specs/matron.md).
## Camp `gloop-matron-nest` at (3120, 940): activation circle r 460, arena circle r 320, the Matron
## spawned at the camp origin (old Phaser position; feet 30 px lower). The Matron: 300 hp, knockback
## immune, never staggered; slime-spider AI spitting `spider-web` (18 - 3 = 15, web 900 ms); the
## first volley 3500 ms after the spawn (or right after the spit then running): 4 marks (the slime
## and three 170 px away, 120 degrees apart), telegraph 900 ms, landing 20 - 3 = 17 on a hurtbox in
## a mark, a web patch (r 50) on every mark, rest 1300 ms, next volley 6500 ms after the rest.
## Every test starts in gloop-forest (MAP_ID); the torn-web test travels into it once more. The
## Sticky tears need player.gd's Gulp form (silk) and are skipped with a note without it.

## run_tests.gd starts every test of this file in gloop-forest.
const MAP_ID := "gloop-forest"

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const BossCampScript := preload("res://game/scripts/boss_camp.gd")
const MatronScript := preload("res://game/scripts/matron.gd")
const ProjectileScript := preload("res://game/scripts/projectile.gd")
const EffectScript := preload("res://game/scripts/effect.gd")
const SpiderWebScript := preload("res://game/scripts/spider_web.gd")
const WebPatchScript := preload("res://game/scripts/web_patch.gd")
const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")
const BossArena := preload("res://game/bosses/boss_arena.gd")
const EnemyPopulation := preload("res://game/enemy/enemy_population.gd")

const MAP := "gloop-forest"
const CAMP_ID := "gloop-matron-nest"
const BOSS_ID := "orb-weaver-matron"
const CAMP := Vector2(3120.0, 940.0)
const ACTIVATION_RADIUS := 460.0
const ARENA_RADIUS := 320.0
const MATRON_DEPTH_ANCHOR := Vector2(0.0, 30.0)
const MAX_HP := 300.0
## Open ground in the nest clearing, inside the arena, 160 px south of the camp.
const INSIDE := Vector2(3120.0, 1100.0)
## Open ground outside the arena (r 320) but inside the activation circle (r 460).
const OUTSIDE_ARENA := Vector2(2740.0, 800.0)
const VOLLEY_HIT := 17
const VOLLEY_RADIUS := 56.0
const VOLLEY_SPREAD := 170.0
const PATCH_RADIUS := 50.0
const SPIT_HIT := 15
## The nook web barrier: root (800, 1280), width 112, depth 56 -> box centre (800, 1252), 56 x 28.
const NOOK_WEB_KEY := "gloop-forest.gloop-ch2-nook-web"
const NOOK_ZONE := Vector2(800.0, 1252.0)
const STEP := TestContext.STEP_MS
const SLACK := TestContext.STEP_MS + 0.01


func test_nest_camp_spawns_the_matron_with_bar_and_arena(t: TestContext) -> void:
	var camp := await _enter_gloop(t)
	if camp == null:
		return
	var activation := camp.activation_perimeter()
	var arena := camp.arena_perimeter()
	t.near_vec(Vector2(float(activation.get("x", 0)), float(activation.get("y", 0))), CAMP, 0.01, "activation centre")
	t.near(float(activation.get("radius", 0)), ACTIVATION_RADIUS, 0.01, "activation radius")
	t.near(float(arena.get("radius", 0)), ARENA_RADIUS, 0.01, "arena radius")
	t.check(not camp.has_live_boss(), "the Matron spawned with the player at the west entry")
	var events := {"spawn": [], "guard": []}
	camp.boss_spawn_requested.connect(func(payload: Dictionary) -> void: (events["spawn"] as Array).append(payload))
	camp.guard_changed.connect(func(payload: Dictionary) -> void: (events["guard"] as Array).append(payload))
	t.teleport_player(INSIDE)
	if not t.check(await t.until(func() -> bool: return camp.has_live_boss(), 200.0), "no Matron after entering the activation circle"):
		return
	var matron := camp.get_live_boss() as MatronScript
	if not t.check(matron != null, "the live boss is not a MatronScript"):
		return
	t.near_vec(matron.get_centre(), CAMP, 1.0, "Matron position (old Phaser centre)")
	t.near_vec(matron.body.global_position, CAMP + MATRON_DEPTH_ANCHOR, 1.0, "Matron feet")
	t.equal(matron.get_phase(), MatronScript.PHASE_FIGHT, "phase after spawn")
	t.near(float(matron.get_arena().get("radius", 0.0)), ARENA_RADIUS, 0.01, "arena handed to the Matron")
	t.equal(Services.router().tags_for_area(matron.damage_area), ["enemy", "boss"], "Matron hurtbox target tags")
	t.equal(matron.patch_effect_id, "matron-web-patch", "authored patch effect")
	if t.equal((events["spawn"] as Array).size(), 1, "boss_spawn_requested emissions"):
		t.equal(events["spawn"][0].get("sceneId"), "character.orb-weaver-matron", "spawn request scene")
	t.equal(events["guard"], [{"instanceId": "gloop-matron-guarded-chest", "guarded": true}], "guard_changed on spawn")
	await t.steps(2)
	var model: Dictionary = _bar(t).snapshot()
	t.equal(bool(model["visible"]), true, "boss bar visible")
	t.equal(str(model["name"]), "Orb-Weaver Matron", "boss bar name")
	t.near(float(model["hp"]), MAX_HP, 0.01, "boss bar hp")


func test_spits_then_volley_marks_land_and_patches_catch(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var matron: MatronScript = fight["matron"]
	var first_volley_at := matron.get_next_volley_at()
	var started: Array = []
	matron.attack_started.connect(func(payload: Dictionary) -> void: started.append({"now": t.now(), "payload": payload}))
	var phases: Array = []
	matron.phase_changed.connect(func(payload: Dictionary) -> void: phases.append(payload))
	var hits: Array = []
	t.player().damaged.connect(func(commit: Dictionary) -> void:
		hits.append({"now": t.now(), "commit": commit}))
	# The spit: the common ranged attack (slime-spider AI, 160 px is inside 90..300).
	var spat := await t.until(func() -> bool: return not _projectiles(t).is_empty(), 1200.0)
	if t.check(spat and not started.is_empty(), "the Matron never spat"):
		t.equal(started[0]["payload"], {"ranged": true, "windupMs": 700.0}, "spit attack_started")
		var web: ProjectileScript = _projectiles(t)[0]
		t.equal(web.projectile_id, "spider-web", "spit projectile")
		t.near(web.body.velocity.length(), 240.0, 0.5, "spit speed (projectileSpeed)")
		t.equal(web.get_damage_payload().get("effects"), [{"effect_id": "web", "potency": 900.0}], "spit web effect")
	# The first volley: 3500 ms after the spawn, but never while a spit runs.
	var volley := await t.until(func() -> bool: return matron.get_phase() == MatronScript.PHASE_VOLLEY_TELEGRAPH, 5200.0)
	if not t.check(volley, "no volley within 5.2 s (phases %s)" % [phases]):
		return
	var volley_at := matron.get_phase_started_at()
	t.check(volley_at >= first_volley_at - SLACK, "the volley came %.0f ms before its time" % (first_volley_at - volley_at))
	t.check(volley_at <= first_volley_at + 1350.0 + 2.0 * SLACK, "the volley came %.0f ms late (more than one spit)" % (volley_at - first_volley_at))
	t.check(not matron.is_attacking(), "a spit runs during the volley")
	# No surprises during the telegraph: the webs in flight go, the slime stands on the first mark.
	for projectile: ProjectileScript in _projectiles(t):
		projectile.expire()
	var marks := matron.get_volley()
	if not t.equal(marks.size(), 4, "volley marks"):
		return
	t.teleport_player(marks[0])
	var arena := matron.get_arena()
	for index in range(1, 4):
		var angle := fmod(0.0 * 0.9, TAU) + float(index - 1) / 3.0 * TAU
		var expected := BossArena.clamp_point(arena, marks[0] + Vector2(cos(angle), sin(angle)) * VOLLEY_SPREAD)
		t.near_vec(marks[index], expected, 0.5, "mark %d (170 px at %.0f degrees, clamped into the arena)" % [index, rad_to_deg(angle)])
		t.check(marks[index].distance_to(CAMP) <= ARENA_RADIUS + 0.01, "mark %d outside the arena" % index)
	var telegraph := AttackTelegraph.of(matron)
	if t.check(telegraph != null, "no volley telegraph"):
		t.equal(telegraph.world_outlines().size(), 4, "telegraph circles")
		t.near_vec(telegraph.shadow_point(), marks[0], 0.5, "telegraph shadow (the slime at the volley start)")
	t.near_vec(matron.body.velocity, Vector2.ZERO, 0.01, "velocity during the telegraph")
	# Landing: 900 ms later; the slime on the first mark takes 17; a patch on every mark.
	var hits_before := hits.size()
	await t.until(func() -> bool: return matron.get_phase() == MatronScript.PHASE_VOLLEY_REST, 1200.0)
	if not t.equal(matron.get_phase(), MatronScript.PHASE_VOLLEY_REST, "phase after the telegraph"):
		return
	var landed_at := matron.get_phase_started_at()
	t.between(landed_at - volley_at, 900.0, 900.0 + SLACK, "telegraph length (ms)")
	t.check(AttackTelegraph.of(matron) == null, "the volley telegraph outlived the landing")
	var landing_hits := hits.slice(hits_before).filter(func(hit: Dictionary) -> bool: return absf(float(hit["now"]) - landed_at) < 0.01)
	if t.equal(landing_hits.size(), 1, "volley hits on the slime"):
		var result: Dictionary = landing_hits[0]["commit"]["result"]
		t.equal(int(result.get("actual_damage", 0)), VOLLEY_HIT, "volley damage")
		t.equal(result.get("applied_effects"), [{"effect_id": "knockback", "potency": 120.0}], "volley knockback")
	t.check(t.world().camera != null and t.world().camera.is_shaking(), "no camera shake on the landing")
	await t.steps(1)
	var patches := _effects(t, "matron-web-patch")
	if t.equal(patches.size(), 4, "web patches"):
		for index in 4:
			var root := (patches[index] as Node).get_parent() as Node2D
			t.check(marks.any(func(mark: Vector2) -> bool: return mark.distance_to(root.global_position) < 0.5), "a patch at %s, not on a mark" % root.global_position)
	# The patch under the slime catches it: set back 50 + 26 above or 50 + 30 below the patch.
	var caught := await t.until(func() -> bool: return t.player().get_centre().distance_to(marks[0]) > PATCH_RADIUS, 300.0)
	if t.check(caught, "the web patch under the slime never caught it"):
		var centre := t.player().get_centre()
		t.near(centre.x, marks[0].x, 40.0, "caught slime x")
		t.check(absf(centre.y - (marks[0].y - PATCH_RADIUS - 26.0)) <= 2.0 or absf(centre.y - (marks[0].y + PATCH_RADIUS + 30.0)) <= 2.0,
			"caught slime y %.1f (patch y %.1f)" % [centre.y, marks[0].y])
	# Rest, then the next volley 6500 ms after it.
	await t.until(func() -> bool: return matron.get_phase() == MatronScript.PHASE_FIGHT, 1600.0)
	t.between(matron.get_phase_started_at() - landed_at, 1300.0, 1300.0 + SLACK, "rest length (ms)")
	t.near(matron.get_next_volley_at(), matron.get_phase_started_at() + 6500.0, 0.01, "next volley = rest end + 6500")
	var names: Array = phases.map(func(entry: Dictionary) -> String: return str(entry["phase"]))
	t.equal(names, ["volley-telegraph", "volley-rest", "fight"], "phase sequence")


func test_hits_flash_but_never_stagger_or_cancel_a_volley(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var matron: MatronScript = fight["matron"]
	var result := _hit(t, matron, 24.0, 140.0)
	t.equal(result.get("status"), "accepted", "a sword-like hit is accepted (every weapon hurts her)")
	t.equal(result.get("rejected_effects"), [{"effect_id": "knockback", "reason": "immune"}], "knockback immune")
	t.near(_hp(matron), MAX_HP - 24.0, 0.01, "hp after the hit")
	await t.steps(2)
	t.near(float(_bar(t).snapshot()["hp"]), MAX_HP - 24.0, 0.01, "boss bar after the hit")
	t.check(matron.get_runtime_state() != "idle", "the hit stunned the Matron")
	# Force the volley now: a hit during the telegraph does not cancel it.
	if not t.check(matron.begin_volley(t.now(), t.player().get_centre()), "the volley could not begin"):
		return
	_hit(t, matron, 24.0, 0.0)
	await t.steps(2)
	t.equal(matron.get_phase(), MatronScript.PHASE_VOLLEY_TELEGRAPH, "phase after a hit during the telegraph")
	matron.apply_slow(0.5, 1000.0)
	t.check(not matron.is_slowed(), "the Matron (a boss) was slowed")


func test_arena_leash_return_and_full_heal(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var matron: MatronScript = fight["matron"]
	_hit(t, matron, 50.0, 0.0)
	t.near(matron.arena_recovery_ms, 60000.0, 0.01, "authored arenaRecoveryMs")
	matron.arena_recovery_ms = 400.0
	t.teleport_player(OUTSIDE_ARENA)
	var left_at := t.now()
	var returning := await t.until(func() -> bool: return matron.is_returning_to_arena(), 300.0)
	if not t.check(returning, "the Matron did not start returning when the player left the arena"):
		return
	await t.until(func() -> bool: return _hp(matron) >= MAX_HP, 700.0)
	t.near(_hp(matron), MAX_HP, 0.01, "hp after %.0f ms outside the arena" % (t.now() - left_at))
	# No volley while the player stays outside, however late it is.
	matron.set(&"_next_volley_at", t.now())
	await t.sim_wait(300.0)
	t.equal(matron.get_phase(), MatronScript.PHASE_FIGHT, "phase while the player is outside the arena")
	t.teleport_player(INSIDE)
	var volley := await t.until(func() -> bool: return matron.get_phase() == MatronScript.PHASE_VOLLEY_TELEGRAPH, 2000.0)
	t.check(volley, "no volley after the player came back")


func test_defeat_records_and_respawn_rule(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var camp: BossCampScript = fight["camp"]
	var matron: MatronScript = fight["matron"]
	var root_id := matron.body.get_instance_id()
	var events := {"defeated": [], "disengaged": []}
	camp.boss_defeated.connect(func(payload: Dictionary) -> void: (events["defeated"] as Array).append(payload))
	camp.boss_disengaged.connect(func(payload: Dictionary) -> void: (events["disengaged"] as Array).append(payload))
	var hits := 0
	while not matron.is_defeated() and hits < 12:
		_hit(t, matron, 30.0, 0.0)
		hits += 1
	if not t.check(matron.is_defeated(), "the Matron survived %d hits of 30" % hits):
		return
	t.equal(hits, 10, "hits of 30 to defeat 300 hp")
	var died_at := t.now()
	t.equal(matron.get_phase(), MatronScript.PHASE_DEAD, "phase after defeat")
	t.check(String(matron.animation.current_animation).begins_with("die-"), "clip after defeat: %s" % matron.animation.current_animation)
	t.check(AttackTelegraph.of(matron) == null, "a telegraph outlived the defeat")
	await t.steps(2)
	t.check(not camp.has_live_boss(), "the camp still has a live boss")
	t.equal(events["defeated"], [{"campId": CAMP_ID, "bossId": BOSS_ID}], "boss_defeated payloads")
	t.equal(events["disengaged"], [{"campId": CAMP_ID, "defeated": true}], "boss_disengaged payloads")
	t.equal(bool(_bar(t).snapshot()["visible"]), false, "boss bar after the defeat")
	var run := Services.run()
	if t.check(run != null, "no RunState"):
		t.check(BOSS_ID in (run.world["defeated_boss_ids"] as Array), "RunState defeated_boss_ids lacks the Matron")
		var camps: Dictionary = run.map_record(MAP)["boss_camps"]
		t.near(float((camps.get(CAMP_ID, {}) as Dictionary).get("respawn_ready_at_epoch_ms", -1.0)),
			BossCampScript.epoch_now_ms() + 300000.0, 5000.0, "RunState respawn time (300 s)")
	await t.until(func() -> bool: return not is_instance_id_valid(root_id), 1000.0)
	t.check(not is_instance_id_valid(root_id), "the defeated Matron was never freed")
	t.between(t.now() - died_at, 285.7 - SLACK, 285.7 + 2.0 * SLACK, "dead body lifetime (the die clip, ms)")
	t.check(not camp.evaluate_activation(true, camp.get_respawn_ready_at() + 1.0), "respawned without the player leaving first")


func test_player_death_resets_the_fight(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var camp: BossCampScript = fight["camp"]
	var matron: MatronScript = fight["matron"]
	var root_id := matron.body.get_instance_id()
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [matron.attack_area]
	var activation := router.begin_activation(matron, areas)
	router.route({"activation_id": activation, "source": matron, "attack_area": matron.attack_area,
		"target_area": player.get_damage_area(), "weapon_id": "test", "weapon_tags": ["test"],
		"damage_types": ["physical"], "base_damage": 1000.0, "effects": [],
		"impact": {"position": matron.get_centre(), "knock": Vector2.ZERO}})
	router.end_activation(activation)
	if not t.check(player.is_dead(), "the player survived 1000 damage"):
		return
	t.check(not camp.has_live_boss(), "the fight did not reset when the player died")
	await t.steps(2)
	t.check(not is_instance_id_valid(root_id), "the Matron was not removed on reset")
	t.equal(bool(_bar(t).snapshot()["visible"]), false, "boss bar after the reset")


func test_web_barrier_catches_and_remembers_a_torn_web(t: TestContext) -> void:
	var camp := await _enter_gloop(t)
	if camp == null:
		return
	var web := _nook_web(t)
	if not t.check(web != null, "gloop-forest has no nook web"):
		return
	t.equal(web.torn_flag(), "web-torn." + NOOK_WEB_KEY, "torn flag name")
	var zone := web.zone()
	t.near_vec(Vector2(float(zone["x"]), float(zone["y"])), NOOK_ZONE, 0.01, "catch box centre")
	t.equal([zone["halfWidth"], zone["halfHeight"]], [56.0, 28.0], "catch box half extents")
	var caught: Array = []
	web.caught.connect(func(payload: Dictionary) -> void: caught.append(payload))
	# From above: set back 26 px above the box.
	t.teleport_player(NOOK_ZONE + Vector2(10.0, -10.0))
	await t.steps(2)
	t.equal(caught.size(), 1, "catches from above")
	t.near_vec(t.player().get_centre(), Vector2(NOOK_ZONE.x + 10.0, NOOK_ZONE.y - 28.0 - 26.0), 0.5, "set back above the web")
	# From below: 30 px below the box.
	await t.sim_wait(1000.0)
	t.teleport_player(NOOK_ZONE + Vector2(-10.0, 10.0))
	await t.steps(2)
	t.equal(caught.size(), 2, "catches from below")
	t.near_vec(t.player().get_centre(), Vector2(NOOK_ZONE.x - 10.0, NOOK_ZONE.y + 28.0 + 30.0), 0.5, "set back below the web")
	# The Sticky form (player.gd, abilities port) tears the web open for good.
	var gulp: Object = t.player().call(&"get_gulp") if t.player().has_method(&"get_gulp") else null
	if gulp != null and gulp.has_method(&"eat_material"):
		Services.run().add_item("silk-clump", 1)
		gulp.call(&"eat_material", "silk-clump")
		if t.check(t.player().crosses_webs() and t.player().is_sticky_form(), "eating silk did not give the Sticky form"):
			var torn: Array = []
			web.torn.connect(func(payload: Dictionary) -> void: torn.append(payload))
			await t.sim_wait(1000.0)
			var before := t.player().get_centre()
			t.teleport_player(NOOK_ZONE)
			await t.steps(2)
			t.equal(torn.size(), 1, "tears by the Sticky slime")
			t.equal(caught.size(), 2, "catches while Sticky")
			t.check(web.is_torn(), "the web is not torn")
			t.check(web.visual == null or not web.visual.visible, "the torn web is still drawn")
			t.check(Services.run().has_flag(web.torn_flag()), "the torn flag is not set")
			t.near_vec(t.player().get_centre(), NOOK_ZONE, 0.5, "the Sticky slime was set back (from %s)" % before)
	else:
		t.note("player.gd has no Sticky form yet: the tear is untested")
	# A torn web stays torn: the story flag set, the world rebuilt, nothing catches.
	Services.run().set_flag(web.torn_flag())
	var old_world := t.world().world_root.get_instance_id()
	if not t.check(t.main.travel_to(MAP, "west"), "travelling to %s again was refused" % MAP):
		return
	var rebuilt := await t.until(func() -> bool:
		return t.world().world_root != null and t.world().world_root.get_instance_id() != old_world and t.player() != null, 3000.0, 6000.0)
	if not t.check(rebuilt, "%s was not rebuilt" % MAP):
		return
	await t.steps(2)
	var again := _nook_web(t)
	if not t.check(again != null, "no nook web after coming back"):
		return
	t.check(again.is_torn(), "the torn web is whole again")
	t.check(again.visual == null or not again.visual.visible, "the torn web is still drawn")
	var caught_again: Array = []
	again.caught.connect(func(payload: Dictionary) -> void: caught_again.append(payload))
	t.teleport_player(NOOK_ZONE)
	await t.steps(2)
	t.equal(caught_again.size(), 0, "a torn web caught the slime")


func test_web_patch_catches_a_slime_and_tears_quietly_for_the_sticky_one(t: TestContext) -> void:
	var at := t.player().get_centre() + Vector2(0.0, 120.0)
	var root := t.world().spawn_at_phaser_position("effect.matron-web-patch", at)
	if not t.check(root != null, "effect.matron-web-patch did not spawn"):
		return
	var patch := root.get_node_or_null(^"WebPatchScript") as WebPatchScript
	if not t.check(patch != null, "the patch effect has no WebPatchScript"):
		return
	t.near(patch.radius, PATCH_RADIUS, 0.01, "patch radius")
	var events := {"caught": [], "torn": []}
	patch.caught.connect(func(zone: Dictionary) -> void: (events["caught"] as Array).append(zone))
	patch.torn.connect(func(zone: Dictionary) -> void: (events["torn"] as Array).append(zone))
	# A normal slime 40 px inside, coming from above: set back 50 + 26 above the centre.
	t.teleport_player(at + Vector2(0.0, -40.0))
	await t.steps(2)
	if t.equal((events["caught"] as Array).size(), 1, "catches"):
		t.equal(events["caught"][0], {"x": at.x, "y": at.y, "halfWidth": PATCH_RADIUS, "halfHeight": PATCH_RADIUS}, "caught zone")
	# Set back to at.y - 50 - 26 (the exact point is checked on open ground in the volley test;
	# here a prop may push the body a little).
	var back := t.player().get_centre()
	t.check(back.distance_to(at) > PATCH_RADIUS and back.y < at.y, "the caught slime was not set back above the patch (%s)" % back)
	if not t.player().has_method(&"apply_web"):
		t.check(t.player().is_movement_suppressed(), "the caught slime can still walk (fallback root)")
	# The Sticky slime walks through and tears it quietly.
	var gulp: Object = t.player().call(&"get_gulp") if t.player().has_method(&"get_gulp") else null
	if gulp == null or not gulp.has_method(&"eat_material"):
		t.note("player.gd has no Sticky form yet: the tear is untested")
		return
	await t.sim_wait(1000.0)
	Services.run().add_item("silk-clump", 1)
	gulp.call(&"eat_material", "silk-clump")
	t.teleport_player(at)
	await t.steps(2)
	t.equal((events["torn"] as Array).size(), 1, "tears by the Sticky slime")
	t.equal((events["caught"] as Array).size(), 1, "catches of the Sticky slime")
	t.check(patch.is_torn() and not patch.visual.visible, "the torn patch is still drawn")
	t.near_vec(t.player().get_centre(), at, 0.5, "the Sticky slime was moved")


func test_gloop_forest_orb_weavers_spawn_from_their_areas(t: TestContext) -> void:
	var camp := await _enter_gloop(t)
	if camp == null:
		return
	var population := t.main.get("enemy_population") as EnemyPopulation
	if not t.check(population != null, "main has no enemy_population"):
		return
	population.allowed_types = PackedStringArray()
	var areas := t.world().areas("enemy-spawn")
	t.equal(areas.size(), 3, "gloop-forest enemy-spawn areas")
	for area: Dictionary in areas:
		var root := population.spawn_one(area)
		if not t.check(root != null, "'%s' spawned nothing" % area["id"]):
			continue
		t.equal(root.scene_file_path.get_file().get_basename(), "orb-weaver", "type spawned by '%s'" % area["id"])
	t.equal(population.alive_count(str(areas[0]["id"])), 1, "alive orb weavers in the first area")


# --- helpers ------------------------------------------------------------------------------------

## Travels to gloop-forest (west entry) unless the test already runs there; returns the Matron's
## camp (null on failure).
static func _enter_gloop(t: TestContext) -> BossCampScript:
	if t.world().map_id() != MAP:
		if not t.check(t.main.travel_to(MAP, "west"), "travel to %s was refused" % MAP):
			return null
		var arrived := await t.until(func() -> bool: return t.world().map_id() == MAP and t.player() != null, 3000.0, 6000.0)
		if not t.check(arrived, "the player did not reach %s" % MAP):
			return null
	await t.steps(2)
	var camp := _camp(t)
	t.check(camp != null, "%s has no boss camp '%s'" % [MAP, CAMP_ID])
	return camp


## gloop-forest, the player inside the arena, the Matron spawned: {"camp", "matron"} or {}.
static func _start_fight(t: TestContext) -> Dictionary:
	var camp := await _enter_gloop(t)
	if camp == null:
		return {}
	t.teleport_player(INSIDE)
	if not t.check(await t.until(func() -> bool: return camp.has_live_boss(), 200.0), "no Matron with the player at %s" % INSIDE):
		return {}
	var matron := camp.get_live_boss() as MatronScript
	if not t.check(matron != null, "the live boss is not a MatronScript"):
		return {}
	return {"camp": camp, "matron": matron}


static func _camp(t: TestContext) -> BossCampScript:
	for node: Node in t.tree.get_nodes_in_group(BossCampScript.GROUP):
		var camp := node as BossCampScript
		if camp != null and camp.camp_id == CAMP_ID and camp.is_inside_tree():
			return camp
	return null


static func _nook_web(t: TestContext) -> SpiderWebScript:
	for node: Node in t.world().entities_root().find_children("SpiderWebScript", "Node", true, false):
		var web := node as SpiderWebScript
		if web != null and web.web_key() == NOOK_WEB_KEY:
			return web
	return null


static func _bar(t: TestContext) -> Node:
	var hud: Node = t.main.get_node_or_null(^"Hud") if t.main != null else null
	return hud.call(&"get_boss_bar") if hud != null and hud.has_method(&"get_boss_bar") else null


## One player hit on the Matron through the router (its own activation), knock to the right.
static func _hit(t: TestContext, matron: MatronScript, damage: float, knockback: float) -> Dictionary:
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [player.get_damage_area()]
	var activation := router.begin_activation(player, areas)
	var effects: Array = []
	if knockback > 0.0:
		effects.append({"effect_id": "knockback", "potency": knockback})
	var result := router.route({"activation_id": activation, "source": player,
		"attack_area": player.get_damage_area(), "target_area": matron.damage_area,
		"weapon_id": "test", "weapon_tags": ["weapon"], "damage_types": ["physical"],
		"base_damage": damage, "effects": effects,
		"impact": {"position": matron.get_centre(), "knock": Vector2(1.0, 0.0)}})
	router.end_activation(activation)
	return result


static func _hp(enemy: Object) -> float:
	return float((enemy.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


static func _projectiles(t: TestContext) -> Array:
	var found: Array = []
	for node: Node in t.world().entities_root().find_children("ProjectileScript", "Node", true, false):
		if node is ProjectileScript and (node as ProjectileScript).is_launched() and not node.is_queued_for_deletion():
			found.append(node)
	return found


static func _effects(t: TestContext, effect_id: String) -> Array:
	var found: Array = []
	for node: Node in t.world().entities_root().find_children("*", "Node", true, false):
		if node is EffectScript and (node as EffectScript).effect_id == effect_id and not node.is_queued_for_deletion():
			found.append(node)
	return found

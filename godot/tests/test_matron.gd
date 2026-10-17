extends RefCounted
## The Orb-Weaver Matron, her gloop-forest nest camp, web patches and web barriers
## (docs/godot/specs/matron.md).
## gloop-forest is cut into chunk worlds (docs/godot/WORLD_ATLAS.md "Chunk worlds"): the nest was in
## chunk F4 (`gloop-forest-f4`, its origin at the forest's (2048, 0)), so the places here are F4's.
## Since 2026-10-17 the Matron lives in the Weaver Hollow's Crown and F4 is the Hollow's forecourt
## (the Watch Oak's root gate, docs/godot/DUNGEONS.md "The Weaver Hollow"): the nest's camp
## (`encounter.gloop-matron-nest`, her own fight: spit, volleys, arena) is mounted by these tests
## where it stood, on the forecourt's open ground south of the oak.
## Camp `gloop-matron-nest` at (1072, 940): activation circle r 460, arena circle r 320, the Matron
## spawned at the camp origin (old Phaser position; feet 30 px lower). The Matron: 300 hp, knockback
## immune, never staggered; slime-spider AI spitting `spider-web` (18 - 3 = 15, web 900 ms); the
## first volley 3500 ms after the spawn (or right after the spit then running): 4 marks (the slime
## and three 170 px away, 120 degrees apart), telegraph 900 ms, landing 20 - 3 = 17 on a hurtbox in
## a mark, a web patch (r 50) on every mark, rest 1300 ms, next volley 6500 ms after the rest.
## Every test starts in the nest's chunk (MAP_ID); the torn-web test runs in E4 (the silk nook) and
## travels into it once more, the camps test in F5 (its two camps are placed enemies since
## 2026-10-16, roadmap 5.25). The Sticky tears need player.gd's Gulp form
## (silk) and are skipped with a note without it.
##
## The Weaver Hollow's fight (matron spec section 8, 2026-10-17): `encounter.weaver-hollow-matron`
## stands in the Crown (`weaver-hollow-crown`, its shutter wired there: test_weaver_hollow.gd), but
## these tests mount it where the nest was, its origin 144 px below the nest centre so her cocoon's
## shadow hangs over the clearing:
## the cocoon (every hit clinks), a blast on her shadow tears it, the 4 s window, the 1.5 s respin,
## three rounds of 100 (round 2's ring of webs, round 3's egg sacs), no respawn, and the rewards
## (Pearl 2 -> `crosses_webs()`, the full heart +20 once, her thread only with the Silk skin).

## run_tests.gd starts every test of this file in the nest's chunk of gloop-forest.
const MAP_ID := "gloop-forest-f4"

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
const PlacedEnemyScript := preload("res://game/enemy/placed_enemy.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const Perimeter := preload("res://game/shared/perimeter.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")
const EggSacScript := preload("res://game/scripts/egg_sac.gd")
const PearlScript := preload("res://game/scripts/pearl.gd")
const FullHeartScript := preload("res://game/scripts/full_heart.gd")
const MatronThreadScript := preload("res://game/scripts/matron_thread.gd")
const CocoonLook := preload("res://game/bosses/matron_cocoon_look.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
## F5's camps (their old spawn areas' maxPopulation): their placed enemies by type.
const AREAS_CAMPS := {"gloop-clod-stompers-hollow": {"clod-stomper": 1}, "gloop-orb-weavers-south": {"orb-weaver": 2}}

const MAP := "gloop-forest-f4"
## The chunks with the silk nook's web and with two camps (a Clod Stompers' and an orb weavers').
const NOOK_MAP := "gloop-forest-e4"
const AREAS_MAP := "gloop-forest-f5"
const CAMP_ID := "gloop-matron-nest"
const BOSS_ID := "orb-weaver-matron"
const CAMP := Vector2(1072.0, 940.0)
const ACTIVATION_RADIUS := 460.0
const ARENA_RADIUS := 320.0
const MATRON_DEPTH_ANCHOR := Vector2(0.0, 30.0)
const MAX_HP := 300.0
## Open ground in the nest clearing, inside the arena, 160 px south of the camp.
const INSIDE := Vector2(1072.0, 1100.0)
## Open ground outside the arena (r 320) but inside the activation circle (r 460).
const OUTSIDE_ARENA := Vector2(692.0, 800.0)
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
## The Weaver Hollow's camp, mounted 144 px below the nest centre: her centre (the camp's spawn
## (0, -144)) is the nest centre, her shadow (feet) 30 px lower. The slime watches from 250 px south of
## her, outside round 2's ring of webs (130 + 50).
const HOLLOW_CAMP_ID := "weaver-hollow-matron"
const HOLLOW_MAP := "weaver-hollow-crown"
const HOLLOW_ORIGIN := Vector2(1072.0, 1084.0)
const HOLLOW_WATCH := Vector2(1072.0, 1190.0)
const OPEN_MS := 4000.0
const RESPIN_MS := 1500.0
const RING_PATCHES := 8
const RING_RADIUS := 130.0
const ROUND_FLOORS: Array[float] = [200.0, 100.0, 0.0]
const CLINK_TEXT := "Woven too thick. It would take a blast."
const SILK_FLAG := "skin.silk"
const PEARL_FLAG := "pearl.orb-weaver-matron"
const HEART_FLAG := "full-heart.orb-weaver-matron"
const THREAD_FLAG := "matron-thread.taken"
const THREAD_ITEM := "matron-thread"
const FULL_HEART_HP := 20
const BOSS_ENERGY := 20.0
## Open ground in the nest clearing where the reward tests set the Pearl, the heart and the thread.
const REWARD_SPOT := Vector2(1072.0, 1060.0)


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
	# The patches are floor webs (spec 5.5, since 2026-10-17): the one under the slime neither roots
	# it nor sets it back; it halves a walk and sticks a Roll (test_web_patch_slows_a_walk_...).
	await t.steps(3)
	t.check(not t.player().is_rooted(), "the web patch under the standing slime rooted it")
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
	await t.until(func() -> bool: return not is_instance_id_valid(root_id), 3000.0)
	t.check(not is_instance_id_valid(root_id), "the defeated Matron was never freed")
	t.between(t.now() - died_at, 2000.0 - SLACK, 2000.0 + 2.0 * SLACK, "dead body lifetime (2 s, owner decision, ms)")
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
	if not await _travel(t, NOOK_MAP):
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
	if gulp != null and gulp.has_method(&"swallow"):
		gulp.call(&"swallow", "silk-essence")
		if t.check(t.player().crosses_webs() and t.player().is_sticky_form(), "swallowing silk did not give the Silk form"):
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
	if not t.check(t.main.travel_to(NOOK_MAP, "west"), "travelling to %s again was refused" % NOOK_MAP):
		return
	var rebuilt := await t.until(func() -> bool:
		return t.world().world_root != null and t.world().world_root.get_instance_id() != old_world and t.player() != null, 3000.0, 6000.0)
	if not t.check(rebuilt, "%s was not rebuilt" % NOOK_MAP):
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


## A web patch is a floor web (spec 5.5; game/world/webs/floor_webs.gd, since 2026-10-17): a slime
## walking on it walks at `webs.floorSlowMultiplier` of its speed and nothing catches it; a Roll
## into it sticks where it is (`caught`, rooted); the Sticky slime walks through and tears it.
func test_web_patch_slows_a_walk_sticks_a_roll_and_tears_for_the_sticky_one(t: TestContext) -> void:
	# Open ground right of the spawn for the walk, the roll and the Sticky slime (120 px straight
	# below the spawn a fieldstone wall row stands since the chunk worlds).
	var at := t.player().get_centre() + Vector2(120.0, 40.0)
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
	# A normal slime walking on it: half its walk, not caught, not rooted, not moved off it.
	var walk := Services.constants().number("character.player.movement.baseSpeed")
	t.teleport_player(at + Vector2(-30.0, 0.0))
	await t.steps(2)
	t.press(&"move_right")
	await t.steps(4)
	t.near(t.player_body().velocity.x, walk * Services.constants().number("webs.floorSlowMultiplier"), 0.01, "walk speed on a web patch")
	t.release_all()
	await t.steps(2)
	t.equal((events["caught"] as Array).size(), 0, "catches of a walking slime")
	t.check(not t.player().is_rooted(), "the web patch rooted a walking slime")
	t.check(t.player().get_centre().distance_to(at) <= PATCH_RADIUS, "the walking slime was moved off the patch")
	# A Roll into it sticks where it is.
	t.teleport_player(at + Vector2(-100.0, 0.0))
	t.player().face(Vector2.RIGHT)
	await t.steps(2)
	t.tap(&"dodge")
	if t.check(await t.until(func() -> bool: return not (events["caught"] as Array).is_empty(), 1500.0), "the roll never stuck in the patch"):
		t.equal(events["caught"][0], {"x": at.x, "y": at.y, "halfWidth": PATCH_RADIUS, "halfHeight": PATCH_RADIUS}, "caught zone")
		t.check(not t.player().is_rolling(), "the roll goes on in the patch")
		t.check(t.player().is_rooted(), "the rolling slime is not stuck in the patch")
		t.check(t.player().get_centre().distance_to(at) <= PATCH_RADIUS + 2.0, "the stuck slime is not on the patch (%s)" % t.player().get_centre())
	# The Sticky slime walks through and tears it quietly.
	var gulp: Object = t.player().call(&"get_gulp") if t.player().has_method(&"get_gulp") else null
	if gulp == null or not gulp.has_method(&"swallow"):
		t.note("player.gd has no Silk form yet: the tear is untested")
		return
	await t.sim_wait(1000.0)
	gulp.call(&"swallow", "silk-essence")
	t.teleport_player(at)
	await t.steps(2)
	t.equal((events["torn"] as Array).size(), 1, "tears by the Sticky slime")
	t.equal((events["caught"] as Array).size(), 1, "catches of the Sticky slime")
	t.check(patch.is_torn() and not patch.visual.visible, "the torn patch is still drawn")
	t.near_vec(t.player().get_centre(), at, 0.5, "the Sticky slime was moved")


func test_gloop_forest_camps_are_placed_enemies(t: TestContext) -> void:
	if not await _travel(t, AREAS_MAP):
		return
	var population := t.main.get("enemy_population") as EnemyPopulation
	if not t.check(population != null, "main has no enemy_population"):
		return
	# Chunk F5: gloop-clod-stompers-hollow (roadmap 8.12) and gloop-orb-weavers-south (the forest's
	# other three camps are in F4 and E5), wander areas of placed enemies; no spawn area, no table.
	t.equal(t.world().areas("enemy-spawn").size(), 0, "gloop-forest F5 enemy-spawn areas")
	t.equal(t.world().definition.metadata.get("spawns"), null, "gloop-forest F5's spawns table")
	var areas := t.world().areas("enemy-wander")
	t.equal(areas.size(), AREAS_CAMPS.size(), "gloop-forest F5 enemy-wander areas")
	for area: Dictionary in areas:
		var camp_id := str(area["id"])
		var counts := {}
		for placed: PlacedEnemyScript in population.placed_enemies():
			if placed.wander_area_id != camp_id or not t.check(placed.is_standing(), "%s does not stand" % placed.name):
				continue
			counts[placed.enemy_type] = int(counts.get(placed.enemy_type, 0)) + 1
			var enemy := placed.get_enemy() as EnemyScript
			t.equal(str(enemy.get_spawn_area().get("id", "")), camp_id, "%s's territory" % placed.name)
			t.check(Perimeter.distance_outside(area["perimeter"], enemy.get_centre()) <= 2.0, "%s stands outside '%s'" % [placed.name, camp_id])
		t.equal(counts, AREAS_CAMPS.get(camp_id, {}), "'%s' placed enemies by type" % camp_id)
		t.equal(population.alive_placed_count(camp_id), (AREAS_CAMPS.get(camp_id, {}) as Dictionary).values().reduce(func(a: int, b: int) -> int: return a + b, 0),
			"standing enemies of '%s'" % camp_id)


# --- the Weaver Hollow's fight (matron spec section 8) ------------------------------------------

func test_hollow_matron_hangs_in_her_cocoon_and_every_hit_clinks(t: TestContext) -> void:
	var fight := await _mount_hollow(t)
	if fight.is_empty():
		return
	var camp: BossCampScript = fight["camp"]
	var matron: MatronScript = fight["matron"]
	var encounter: Node2D = fight["encounter"]
	t.equal([camp.camp_id, camp.boss_id, camp.map_id], [HOLLOW_CAMP_ID, BOSS_ID, HOLLOW_MAP], "the Hollow's camp ids")
	t.check(camp.never_returns(), "the Hollow's camp would bring her back once beaten")
	t.check(matron.cocoon_enabled, "the camp's boss_overrides did not turn the cocoon on")
	t.near(matron.arena_recovery_ms, 0.0, 0.01, "no full heal after a while outside the arena")
	t.equal(str(matron.get_arena().get("shape", "")), "rectangle", "her arena (the room's floor)")
	t.near_vec(matron.get_centre(), CAMP, 1.0, "her centre (the camp's spawn (0, -144))")
	t.equal(matron.get_shell(), MatronScript.SHELL_COCOONED, "shell after the spawn")
	t.equal(matron.get_round(), 1, "round at full health")
	t.check(matron.is_in_group(&"blast_targets"), "she is not a blast target")
	t.near_vec(matron.blast_point(), matron.body.global_position, 0.01, "blast point (her shadow: the feet)")
	var look := matron.cocoon_look as CocoonLook
	if t.check(look != null, "the Matron has no cocoon look"):
		t.equal(look.state, CocoonLook.STATE_COCOONED, "the look's state")
		t.near(look.hang_px, matron.round_hang_px[0], 0.01, "round 1's cocoon hangs low")
	# She never leaves her thread, though her AI wants to.
	var feet := matron.body.global_position
	await t.sim_wait(600.0)
	t.near_vec(matron.body.global_position, feet, 0.5, "her cocoon moved")
	# Every weapon hit clinks, however many: no blast, no damage.
	for index in 12:
		var result := _hit(t, matron, 100.0, 0.0)
		if index == 0:
			t.equal(result.get("status"), "rejected", "a weapon hit on the cocoon")
			t.equal(result.get("reason"), "immune", "the cocoon's refusal (a clink)")
	t.near(_hp(matron), MAX_HP, 0.01, "hp after twelve hits on the cocoon")
	t.equal(matron.clink_text, CLINK_TEXT, "the clink's line")
	# Her rewards wait for her fall.
	t.check(not (encounter.get_node(^"Pearl") as PearlScript).is_shown(), "Pearl 2 shows while she lives")
	t.check(not (encounter.get_node(^"FullHeart/FullHeartScript") as FullHeartScript).is_shown(), "the full heart shows while she lives")


func test_a_blast_on_her_shadow_tears_the_cocoon_for_a_window(t: TestContext) -> void:
	var fight := await _mount_hollow(t)
	if fight.is_empty():
		return
	var matron: MatronScript = fight["matron"]
	# A blast whose ellipse (176 x 120) misses her shadow does nothing.
	GooBlast.detonate(matron.blast_point() + Vector2(150.0, 0.0), false)
	await t.steps(2)
	t.equal(matron.get_shell(), MatronScript.SHELL_COCOONED, "shell after a blast 150 px from her shadow")
	await t.sim_wait(300.0)
	# One whose ellipse holds it tears the cocoon: she drops to the floor, open.
	GooBlast.detonate(matron.blast_point() + Vector2(50.0, 20.0), false)
	await t.steps(1)
	if not t.equal(matron.get_shell(), MatronScript.SHELL_TORN, "shell after a blast on her shadow"):
		return
	var torn_at := matron.get_shell_started_at()
	t.check(matron.is_open(), "torn but not open")
	t.near(_hp(matron), MAX_HP, 0.01, "hp after the blast (it only tears the cocoon)")
	var result := _hit(t, matron, 30.0, 0.0)
	t.equal(result.get("status"), "accepted", "a weapon hit while she is open")
	t.near(_hp(matron), MAX_HP - 30.0, 0.01, "hp after a hit in the window")
	# About 4 s on the floor, then she climbs her thread and spins (about 1.5 s): hits clink again.
	await t.until(func() -> bool: return matron.get_shell() == MatronScript.SHELL_RESPIN, OPEN_MS + 500.0)
	if not t.equal(matron.get_shell(), MatronScript.SHELL_RESPIN, "shell after the window"):
		return
	t.between(matron.get_shell_started_at() - torn_at, OPEN_MS, OPEN_MS + SLACK, "the open window (ms)")
	t.equal(_hit(t, matron, 30.0, 0.0).get("reason"), "immune", "a hit while she spins")
	var respin_at := matron.get_shell_started_at()
	await t.until(func() -> bool: return matron.get_shell() == MatronScript.SHELL_COCOONED, RESPIN_MS + 500.0)
	if not t.equal(matron.get_shell(), MatronScript.SHELL_COCOONED, "shell after the respin"):
		return
	t.between(matron.get_shell_started_at() - respin_at, RESPIN_MS, RESPIN_MS + SLACK, "the respin (ms)")
	t.equal(matron.get_round(), 1, "round at 270 hp")
	t.equal(_hit(t, matron, 30.0, 0.0).get("reason"), "immune", "a hit on the new cocoon")
	t.near(_hp(matron), MAX_HP - 30.0, 0.01, "hp after a hit on the new cocoon")


func test_three_rounds_of_a_hundred_with_webs_then_egg_sacs(t: TestContext) -> void:
	var fight := await _mount_hollow(t)
	if fight.is_empty():
		return
	var matron: MatronScript = fight["matron"]
	var look := matron.cocoon_look as CocoonLook
	for index in 3:
		var round_number := index + 1
		t.equal(matron.get_round(), round_number, "round at %.0f hp" % _hp(matron))
		if look != null:
			t.near(look.hang_px, matron.round_hang_px[index], 0.01, "round %d's hang" % round_number)
		if round_number == 2:
			await t.steps(1)
			t.equal(_ring_patches(t, matron), RING_PATCHES, "round 2's floor webs %.0f px round her shadow" % RING_RADIUS)
		if round_number == 3:
			var sacs := matron.get_egg_sacs()
			if t.equal(sacs.size(), 2, "round 3's egg sacs"):
				for i in sacs.size():
					var sac := sacs[i] as EggSacScript
					if not t.check(sac != null, "egg sac %d is not an EggSacScript" % i):
						continue
					t.near_vec(sac.get_centre(), matron.blast_point() + matron.egg_sac_offsets[i], 1.0, "egg sac %d by her shadow" % i)
					t.equal(sac.get_arena(), matron.get_arena(), "egg sac %d's arena (hers)" % i)
		t.equal(_hit(t, matron, 500.0, 0.0).get("reason"), "immune", "round %d: a hit on the cocoon" % round_number)
		t.check(matron.receive_blast({}), "round %d: the blast did not tear the cocoon" % round_number)
		var result := _hit(t, matron, 500.0, 0.0)
		t.equal(int(result.get("actual_damage", 0)), 100, "round %d: one big hit takes her round's hundred, no more" % round_number)
		t.near(_hp(matron), ROUND_FLOORS[index], 0.01, "round %d: hp after the hit" % round_number)
		if round_number == 3:
			break
		t.equal(matron.get_shell(), MatronScript.SHELL_RESPIN, "round %d: she climbs as soon as her round's share is gone" % round_number)
		await t.until(func() -> bool: return matron.get_shell() == MatronScript.SHELL_COCOONED, RESPIN_MS + 500.0)
		_hold_fire(matron)
	t.check(matron.is_defeated(), "she survived her third round")
	t.equal(matron.get_phase(), MatronScript.PHASE_DEAD, "phase after her fall")


func test_beaten_she_never_comes_back_and_her_brood_bursts(t: TestContext) -> void:
	var fight := await _mount_hollow(t)
	if fight.is_empty():
		return
	var camp: BossCampScript = fight["camp"]
	var matron: MatronScript = fight["matron"]
	var root_id := matron.body.get_instance_id()
	var events := {"defeated": [], "disengaged": []}
	camp.boss_defeated.connect(func(payload: Dictionary) -> void: (events["defeated"] as Array).append(payload))
	camp.boss_disengaged.connect(func(payload: Dictionary) -> void: (events["disengaged"] as Array).append(payload))
	if not await _beat(t, matron):
		return
	await t.steps(2)
	t.equal(events["defeated"], [{"campId": HOLLOW_CAMP_ID, "bossId": BOSS_ID}], "boss_defeated payloads (the shutters' hook)")
	t.equal(events["disengaged"], [{"campId": HOLLOW_CAMP_ID, "defeated": true}], "boss_disengaged payloads")
	var run := Services.run()
	t.check(BOSS_ID in (run.world["defeated_boss_ids"] as Array), "RunState defeated_boss_ids lacks the Matron")
	t.check(not (run.map_record(HOLLOW_MAP)["boss_camps"] as Dictionary).has(HOLLOW_CAMP_ID), "a respawn time was stored for a boss that never returns")
	for sac: Node in matron.get_egg_sacs():
		t.check(bool(sac.call(&"is_defeated")), "an egg sac outlived her")
	await t.until(func() -> bool: return not is_instance_id_valid(root_id), 3000.0)
	t.check(not is_instance_id_valid(root_id), "the beaten Matron was never freed")
	# Leaving and coming back, however late: never again.
	t.check(not camp.evaluate_activation(false, BossCampScript.epoch_now_ms()), "she spawned with the slime outside")
	t.check(not camp.evaluate_activation(true, BossCampScript.epoch_now_ms() + 1.0e9), "she came back after the slime left and returned")
	# Nor in a camp built again (the room entered again).
	(fight["encounter"] as Node).queue_free()
	await t.steps(2)
	var again := await _mount_hollow(t, false)
	if again.is_empty():
		return
	await t.sim_wait(300.0)
	t.check(not (again["camp"] as BossCampScript).has_live_boss(), "a camp built again spawned her once more")


func test_pearl_two_grants_the_silk_skin(t: TestContext) -> void:
	var won := await _mount_won_hollow(t)
	if won.is_empty():
		return
	var pearl := (won["encounter"] as Node).get_node_or_null(^"Pearl") as PearlScript
	if not t.check(pearl != null, "the Hollow's encounter has no Pearl"):
		return
	t.check(pearl.is_shown(), "Pearl 2 is not shown after her fall")
	t.equal([pearl.number, pearl.skin_flag], [2, SILK_FLAG], "Pearl 2's number and skin")
	t.check(not t.player().crosses_webs(), "the slime crossed webs before the Pearl")
	pearl.global_position = REWARD_SPOT
	t.teleport_player(REWARD_SPOT)
	await t.until(func() -> bool: return pearl.is_taken(), 300.0)
	if not t.check(pearl.is_taken(), "walking into Pearl 2 did not take it"):
		return
	var run := Services.run()
	t.check(run.has_flag(PEARL_FLAG), "Pearl 2's flag is not set")
	t.check(run.has_flag(SILK_FLAG), "the Silk skin's flag is not set")
	t.check(t.player().crosses_webs(), "crosses_webs() is false with the Silk skin (its stand-in flag)")
	t.check(not t.player().is_sticky_form(), "the Pearl gave the Silk Gulp form instead of the skin")


func test_her_full_heart_adds_twenty_max_hp_once(t: TestContext) -> void:
	var won := await _mount_won_hollow(t)
	if won.is_empty():
		return
	var heart_root := (won["encounter"] as Node).get_node_or_null(^"FullHeart") as Node2D
	var heart := heart_root.get_node_or_null(^"FullHeartScript") as FullHeartScript if heart_root != null else null
	if not t.check(heart != null, "the Hollow's encounter has no full heart"):
		return
	t.check(heart.is_shown(), "the full heart is not shown after her fall")
	var run := Services.run()
	var max_hp := t.player().get_max_hp()
	var max_energy := t.player().get_max_energy()
	t.equal(FULL_HEART_HP, Services.constants().integer("character.player.fullHeart.maxHpBonus"), "fullHeart.maxHpBonus")
	heart_root.global_position = REWARD_SPOT
	t.teleport_player(REWARD_SPOT)
	await t.until(func() -> bool: return heart.is_taken(), 300.0)
	if not t.check(heart.is_taken(), "walking into the full heart did not take it"):
		return
	t.equal(t.player().get_max_hp(), max_hp + FULL_HEART_HP, "the slime's max HP after the full heart")
	t.equal(t.player().get_hp(), max_hp + FULL_HEART_HP, "HP filled")
	t.equal(run.max_hp(), max_hp + FULL_HEART_HP, "RunState max HP")
	t.equal(int(run.player.get("full_hearts", 0)), 1, "RunState full hearts")
	t.check(run.has_flag(HEART_FLAG), "the full heart's flag is not set")
	t.near(t.player().get_max_energy(), max_energy + BOSS_ENERGY, 0.01, "max energy after a boss's heart (question 19)")
	t.near(float(run.max_energy()), max_energy + BOSS_ENERGY, 0.01, "RunState max energy")
	# Once: the room built again shows no heart, and standing there grants nothing more.
	(won["encounter"] as Node).queue_free()
	await t.steps(2)
	var again := await _mount_hollow(t, false)
	if again.is_empty():
		return
	var heart_again := (again["encounter"] as Node).get_node_or_null(^"FullHeart/FullHeartScript") as FullHeartScript
	if t.check(heart_again != null, "no full heart in the camp built again"):
		t.check(heart_again.is_taken() and not heart_again.is_shown(), "the taken heart is back")
		((again["encounter"] as Node).get_node(^"FullHeart") as Node2D).global_position = REWARD_SPOT
	t.teleport_player(REWARD_SPOT)
	await t.sim_wait(200.0)
	t.equal(run.max_hp(), max_hp + FULL_HEART_HP, "max HP after standing where the heart was again")
	# Saved: through a save and a load the heart stays.
	var saved := run.serialize()
	t.equal(int((saved["player"] as Dictionary).get("full_hearts", 0)), 1, "full hearts in the save")
	if t.check(run.install(saved), "the saved run did not install"):
		t.equal(run.max_hp(), max_hp + FULL_HEART_HP, "max HP after a load")
		t.near(float(run.max_energy()), max_energy + BOSS_ENERGY, 0.01, "max energy after a load")


func test_her_thread_is_taken_only_with_the_silk_skin(t: TestContext) -> void:
	var won := await _mount_won_hollow(t)
	if won.is_empty():
		return
	var thread := (won["encounter"] as Node).get_node_or_null(^"MatronThread") as MatronThreadScript
	if not t.check(thread != null, "the Hollow's encounter has no thread"):
		return
	thread.global_position = REWARD_SPOT
	await t.steps(2)
	t.equal(thread.get_state(), MatronThreadScript.STATE_CAUGHT, "the spool before a hit")
	var area := thread.get_node_or_null(^"DamageArea") as Area2D
	if not t.check(area != null, "the thread has no hurtbox"):
		return
	var refused: Array = []
	thread.refused.connect(func(payload: Dictionary) -> void: refused.append(payload))
	# Without the Silk skin: a clink (and its line), the spool stays.
	var result := _strike(t, area, 24.0, ["weapon", "spear"])
	t.equal([result.get("status"), result.get("reason")], ["rejected", "immune"], "a Spear hit without the Silk skin")
	t.equal(refused, [{"crosses": false}], "refusals without the skin")
	t.equal(thread.get_state(), MatronThreadScript.STATE_CAUGHT, "the spool after a hit without the skin")
	t.check(not thread.refusal_text.contains("Silk"), "the refusal names the skin: %s" % thread.refusal_text)
	# With it, the Spear cuts the strand and the spool drops; walking into it takes it, once.
	Services.run().set_flag(SILK_FLAG)
	t.check(t.player().crosses_webs(), "crosses_webs() is false with the Silk skin")
	result = _strike(t, area, 24.0, ["weapon", "spear"])
	t.equal(result.get("status"), "accepted", "a Spear hit with the Silk skin")
	t.equal(thread.get_state(), MatronThreadScript.STATE_FALLING, "the spool after the cut")
	await t.until(func() -> bool: return thread.get_state() == MatronThreadScript.STATE_DROPPED, 800.0)
	t.equal(thread.get_state(), MatronThreadScript.STATE_DROPPED, "the spool after its fall")
	var run := Services.run()
	t.equal(run.item_count(THREAD_ITEM), 0, "the thread was taken before the slime reached it")
	t.teleport_player(REWARD_SPOT)
	await t.until(func() -> bool: return thread.is_taken(), 300.0)
	t.check(thread.is_taken(), "walking into the dropped spool did not take it")
	t.equal(run.item_count(THREAD_ITEM), 1, "Matron's Thread in the bag")
	t.equal(str(ItemCatalog.definition(THREAD_ITEM).get("category", "")), "story", "the thread is a story item")
	t.check(run.has_flag(THREAD_FLAG), "the thread's flag is not set")
	# Once, and saved: the room built again has no spool.
	(won["encounter"] as Node).queue_free()
	await t.steps(2)
	var again := await _mount_hollow(t, false)
	if again.is_empty():
		return
	var thread_again := (again["encounter"] as Node).get_node_or_null(^"MatronThread") as MatronThreadScript
	if t.check(thread_again != null, "no thread in the camp built again"):
		t.check(thread_again.is_taken() and not thread_again.visible, "the taken thread is back")
	t.equal(run.item_count(THREAD_ITEM), 1, "Matron's Thread in the bag after the room is built again")
	t.check(((run.serialize()["story"] as Dictionary).get("world_flags", []) as Array).has(THREAD_FLAG), "the thread's flag is not in the save")


# --- helpers ------------------------------------------------------------------------------------

## Travels to the nest's chunk (west entry) unless the test already runs there and mounts the nest's
## camp where it stood (F4 has none since the Weaver Hollow took the Matron); returns the Matron's
## camp (null on failure).
static func _enter_gloop(t: TestContext) -> BossCampScript:
	if not await _travel(t, MAP):
		return null
	var camp := _camp(t)
	if camp == null:
		camp = await _mount_nest(t)
	t.check(camp != null, "the nest's camp '%s' could not be mounted in %s" % [CAMP_ID, MAP])
	return camp


## `encounter.gloop-matron-nest` at CAMP in the nest's chunk, recorded under the chunk (as it stood
## there until 2026-10-17). Null when it does not instance.
static func _mount_nest(t: TestContext) -> BossCampScript:
	var nest := t.world().instantiate_scene("encounter.gloop-matron-nest") as Node2D
	if nest == null:
		return null
	var camp := nest.get_node_or_null(^"BossCampScript") as BossCampScript
	var chest := nest.get_node_or_null(^"GuardedChest/ChestScript")
	if camp != null:
		camp.set(&"map_id", MAP)
	if chest != null:
		chest.set(&"map_id", MAP)
	nest.set_meta(&"instance_id", "gloop-ch2-matron-nest")
	nest.set_meta(&"persistence_key", "gloop-forest.gloop-ch2-matron-nest")
	var parent := t.world().entities_root()
	nest.position = CAMP - parent.global_position
	parent.add_child(nest)
	await t.steps(2)
	return camp


## Travels to chunk world `map` (west entry) unless the test already runs there. False on failure.
static func _travel(t: TestContext, map: String) -> bool:
	if t.world().map_id() != map:
		if not t.check(t.main.travel_to(map, "west"), "travel to %s was refused" % map):
			return false
		var arrived := await t.until(func() -> bool: return t.world().map_id() == map and t.player() != null, 3000.0, 6000.0)
		if not t.check(arrived, "the player did not reach %s" % map):
			return false
	await t.steps(2)
	return true


## The nest's chunk, the player inside the arena, the Matron spawned: {"camp", "matron"} or {}.
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


# --- helpers: the Weaver Hollow's camp ------------------------------------------------------------

## The Weaver Hollow's camp mounted at HOLLOW_ORIGIN in the nest's chunk (the nest's own camp freed
## first, the slime at HOLLOW_WATCH). With `fight` it waits for her spawn and holds her spit and her
## volleys, so the slime is not knocked about: {"camp", "encounter", "matron"}; without it
## {"camp", "encounter"}. {} on failure.
static func _mount_hollow(t: TestContext, fight: bool = true) -> Dictionary:
	if not await _travel(t, MAP):
		return {}
	var nest := _camp(t)
	if nest != null:
		nest.get_parent().queue_free()
		await t.steps(2)
	t.teleport_player(HOLLOW_WATCH)
	var encounter := t.world().instantiate_scene("encounter.weaver-hollow-matron") as Node2D
	if not t.check(encounter != null, "encounter.weaver-hollow-matron did not instance"):
		return {}
	t.world().entities_root().add_child(encounter)
	encounter.global_position = HOLLOW_ORIGIN
	var camp := encounter.get_node_or_null(^"BossCampScript") as BossCampScript
	if not t.check(camp != null, "the Hollow's encounter has no BossCampScript"):
		return {}
	var mounted := {"camp": camp, "encounter": encounter}
	if not fight:
		await t.steps(2)
		return mounted
	if not t.check(await t.until(func() -> bool: return camp.has_live_boss(), 300.0), "the Hollow's camp spawned no Matron"):
		return {}
	var matron := camp.get_live_boss() as MatronScript
	if not t.check(matron != null, "the Hollow's boss is not a MatronScript"):
		return {}
	await t.steps(2)
	_hold_fire(matron)
	mounted["matron"] = matron
	return mounted


## The Hollow's camp after her fall (her id in RunState `defeated_boss_ids` before the camp is
## built): no Matron, the rewards out. {"camp", "encounter"} or {}.
static func _mount_won_hollow(t: TestContext) -> Dictionary:
	if not await _travel(t, MAP):
		return {}
	var defeated: Array = Services.run().world.get_or_add("defeated_boss_ids", [])
	if not BOSS_ID in defeated:
		defeated.append(BOSS_ID)
	var mounted := await _mount_hollow(t, false)
	if mounted.is_empty():
		return {}
	await t.sim_wait(200.0)
	t.check(not (mounted["camp"] as BossCampScript).has_live_boss(), "a beaten Matron spawned again")
	return mounted


## Her spit and her volleys wait (the tests drive her rounds themselves).
static func _hold_fire(matron: MatronScript) -> void:
	(matron.get(&"_lifecycle") as Object).set(&"ready_at", INF)
	matron.set(&"_next_volley_at", INF)
	matron.cancel_attack()


## Her three rounds, each torn by a blast and ended by one big hit. True once she is beaten.
static func _beat(t: TestContext, matron: MatronScript) -> bool:
	for index in 3:
		if not t.check(matron.receive_blast({}), "round %d: the blast did not tear the cocoon" % (index + 1)):
			return false
		_hit(t, matron, 500.0, 0.0)
		if matron.is_defeated():
			return true
		await t.until(func() -> bool: return matron.get_shell() == MatronScript.SHELL_COCOONED, RESPIN_MS + 500.0)
		_hold_fire(matron)
	return t.check(matron.is_defeated(), "she survived three rounds")


## Web patches `RING_RADIUS` (within 2 px) from her shadow.
static func _ring_patches(t: TestContext, matron: MatronScript) -> int:
	var count := 0
	for patch: Node in _effects(t, "matron-web-patch"):
		var root := patch.get_parent() as Node2D
		if root != null and absf(root.global_position.distance_to(matron.blast_point()) - RING_RADIUS) <= 2.0:
			count += 1
	return count


## One player hit on `area` through the router with `tags` (its own activation).
static func _strike(t: TestContext, area: Area2D, damage: float, tags: Array) -> Dictionary:
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [player.get_damage_area()]
	var activation := router.begin_activation(player, areas)
	var result := router.route({"activation_id": activation, "source": player,
		"attack_area": player.get_damage_area(), "target_area": area,
		"weapon_id": "test", "weapon_tags": tags, "damage_types": ["physical"],
		"base_damage": damage, "effects": [],
		"impact": {"position": area.global_position, "knock": Vector2(1.0, 0.0)}})
	router.end_activation(activation)
	return result

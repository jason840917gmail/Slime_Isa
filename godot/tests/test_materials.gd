extends RefCounted
## What a hit meets (one combat, piece 4 of docs/design/2026-11-25-weapons-beside-throws.md; BESTIARY.md
## "Materials"): every non-boss enemy type has a hit material, `combat.materials` says which weapons it
## refuses (a clink; only weapons are ever refused: the owner, 2026-11-26), the gate
## applies it (HitReaction.gate, `material_gate`), the first refusal of a run shows its line
## (HitMaterials.on_refused), and the folds (the Squint's visor, the Worm Bulwark's clink tags) and the
## Shardback's brittle shell hold.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitMaterials := preload("res://game/combat/reactions/hit_materials.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const ReactionState := preload("res://game/combat/reactions/reaction_state.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")

const MAP_ID := "playground"
const RANGE_FROM_SPAWN := Vector2(0.0, -260.0)
## The owner's table of 2026-11-25: material -> the weapon tags it refuses (nothing else is ever refused:
## the owner, 2026-11-26).
const TABLE := {
	"flesh": [], "shell": ["spear"], "bone": ["spear"], "crystal": ["cut"], "silk": ["crush"],
	"plant": ["spear", "crush"], "untouchable": ["spear", "cut", "crush"], "bark": ["spear", "crush"],
	"iron": ["spear", "cut"], "eye": ["cut", "crush"],
}
## The owner's picks and the plan's first pass (enemy type -> material).
const PICKS := {
	"worm-swordsman": "flesh", "worm-bulwark": "shell", "shardback": "shell", "bone-marcher": "bone",
	"crystal-crawler": "crystal", "egg-sac": "silk", "spitcap": "plant", "jelly-bouncer": "untouchable",
	"carnivore-plant": "untouchable", "thorn-guard": "bark", "clod-stomper": "iron", "squint": "eye",
	"big-squint": "eye",
}
const WEAPON_TAGS := {"spear": ["weapon", "spear"], "cut": ["weapon", "cut"], "crush": ["weapon", "crush"]}


func test_the_gate_by_material(t: TestContext) -> void:
	for material: String in TABLE:
		var profile := {"hitMaterial": material, "weight": "medium"}
		var refuses: Array = TABLE[material]
		for tag: String in WEAPON_TAGS:
			var hit := HitReaction.build_hit("tap", {"shape": tag, "tags": WEAPON_TAGS[tag]})
			var want := HitReaction.GATE_CLINK if refuses.has(tag) else HitReaction.GATE_OPEN
			t.equal(HitReaction.gate(profile, hit, ReactionState.new()), want, "%s against %s" % [material, tag])
		var thrown := HitReaction.build_hit("thrown", {"tags": ["thrown", "clay-pot"]})
		t.equal(HitReaction.gate(profile, thrown, ReactionState.new()), HitReaction.GATE_OPEN, "%s against a throw" % material)
		for tag: String in refuses:
			t.check(not HitMaterials.line(material, tag).is_empty(), "no line for %s refusing %s" % [material, tag])
	# A slam, an arrow or the Roll is no weapon: untouchable lets it reach its own rules.
	var slam := HitReaction.build_hit("slam", {"tags": ["slam"]})
	t.equal(HitReaction.gate({"hitMaterial": "untouchable"}, slam, ReactionState.new()), HitReaction.GATE_OPEN, "a slam")


## The one-weapon materials (bark, iron, eye: one of the three weapons hurts them) refuse only the two other
## weapons, with their lines; everything else hurts them as it hurts flesh (the owner, 2026-11-26: "the
## rule is only for weapons, spear axe and hammer"; of the abilities: "Yes, they hurt", "until i decide
## otherwise").
func test_a_one_weapon_material_refuses_only_weapons(t: TestContext) -> void:
	var others := {
		"an arrow": HitReaction.build_hit("arrow", {"tags": ["arrow", "bow"]}),
		"a blast": HitReaction.build_hit("slam", {"tags": ["blast"]}),
		"the flame": HitReaction.build_hit("tap", {"tags": ["fire", "lantern"]}),
		"the Roll": HitReaction.build_hit("roll", {"tags": ["roll"]}),
		"a slam": HitReaction.build_hit("slam", {"tags": ["slam"]}),
		"the Heavy Roll (old style)": {"class": "", "tags": ["roll", "heavy"]},
		"a mechanism's blow": HitReaction.build_hit("thrown-heavy", {"tags": ["cart"], "true_blow": true}),
		"the suck": HitReaction.build_hit("suck", {"tags": ["suck"]}),
		"a pot": HitReaction.build_hit("thrown", {"tags": ["thrown", "clay-pot"]}),
		"a medium throw": HitReaction.build_hit("thrown-medium", {"tags": ["thrown", "clay-pot"]}),
		"a heavy throw": HitReaction.build_hit("thrown-heavy", {"tags": ["thrown", "clay-pot"]}),
	}
	var weapon_of := {"bark": "cut", "iron": "crush", "eye": "spear"}
	for material: String in weapon_of:
		var profile := {"hitMaterial": material, "weight": "heavy"}
		for tag: String in WEAPON_TAGS:
			var weapon := HitReaction.build_hit("tap", {"shape": tag, "tags": WEAPON_TAGS[tag]})
			if tag == weapon_of[material]:
				t.equal(HitReaction.material_gate(profile, weapon), "", "%s against its weapon" % material)
			else:
				t.equal(HitReaction.material_gate(profile, weapon), HitReaction.GATE_CLINK, "%s against %s" % [material, tag])
				t.check(not HitMaterials.line(material, tag).is_empty(), "no line for %s refusing %s" % [material, tag])
		for name: String in others:
			t.equal(HitReaction.material_gate(profile, others[name]), "", "%s against %s" % [material, name])
		t.equal(HitMaterials.row(material).keys().filter(func(key: Variant) -> bool: return not ["refuses", "lines"].has(str(key))),
			[], "%s's row keeps only refuses and lines" % material)
	# An open Squint takes an arrow and a blast now; shut, its visor still clinks them.
	var squint := ReactionProfile.for_type("squint")
	for name: String in ["an arrow", "a blast", "the flame", "the Roll"]:
		t.equal(HitReaction.gate(squint, others[name], _in_phase("open")), HitReaction.GATE_OPEN, "an open Squint against %s" % name)
		t.equal(HitReaction.gate(squint, others[name], _in_phase("walk")), HitReaction.GATE_CLINK, "a shut Squint against %s" % name)


## The Thorn Guard's own kill comes back: asleep, every hit clinks but the Heavy Roll (its `_kill_hit`), which
## its bark no longer refuses; an old-style Spear blow on it still clinks with the bark's line.
func test_the_heavy_roll_kills_a_sleeping_thorn_guard_again(t: TestContext) -> void:
	await _enter(t)
	var guard := await _spawn(t, "thorn-guard", Vector2(200.0, 0.0))
	if not t.check(guard != null, "no Thorn Guard"):
		return
	t.equal(str(guard.get(&"_phase")), "asleep", "the Thorn Guard's phase")
	var heavy_roll := {"source": t.player(), "weapon_id": "roll-bonk", "weapon_tags": ["roll", "heavy"],
		"damage_types": ["physical"], "base_damage": 20.0}
	var answer: Dictionary = guard.call(&"can_receive_damage", {"request": heavy_roll})
	t.check(bool(answer.get("accepted", false)), "the Heavy Roll was refused: %s" % str(answer))
	var roll := heavy_roll.duplicate()
	roll["weapon_tags"] = ["roll"]
	t.check(not bool((guard.call(&"can_receive_damage", {"request": roll}) as Dictionary).get("accepted", false)),
		"a plain Roll got through the sleeping statue")
	var spear := heavy_roll.duplicate()
	spear["weapon_tags"] = ["weapon", "spear"]
	t.check(not bool((guard.call(&"can_receive_damage", {"request": spear}) as Dictionary).get("accepted", false)),
		"an old-style Spear blow got through bark")


func test_every_enemy_type_has_a_material_of_the_table(t: TestContext) -> void:
	var types: Dictionary = {}
	_collect(_read_types(), types)
	t.check(types.size() >= 30, "found only %d enemy types" % types.size())
	for type: String in types:
		var profile := ReactionProfile.for_type(type)
		if str(profile.get("weight", "")) == "boss":
			continue
		var material := HitMaterials.of(profile)
		t.check(TABLE.has(material), "%s has the material '%s', not in the table" % [type, material])
		t.check(str(types[type]).length() > 0, "%s names no hitMaterial" % type)
	for type: String in PICKS:
		t.equal(HitMaterials.of(ReactionProfile.for_type(type)), PICKS[type], "%s's material" % type)
	var brittle := HitMaterials.of(ReactionProfile.for_type("shardback"), "brittle")
	t.equal(brittle, "flesh", "the Shardback's brittle shell")


func test_a_refused_weapon_clinks_with_its_line_and_the_right_one_hurts(t: TestContext) -> void:
	await _enter(t)
	var clod := await _spawn(t, "clod-stomper", Vector2(62.0, 0.0))
	if not t.check(clod != null, "no Clod Stomper"):
		return
	var before := _hp(clod)
	t.player().get_shapes().set_current(ShapeDefs.SPEAR)
	t.tap(&"attack")
	await t.sim_wait(700.0)
	t.near(_hp(clod), before, 0.01, "the Spear on iron")
	t.check(Services.run().has_flag(HitMaterials.FLAG_PREFIX + "iron.spear"), "the iron's line for the Spear did not show")
	t.check(clod.body.find_child(HitMaterials.CUE_NAME, true, false) != null, "no pointer flashes the Clod")
	_place(t, clod, Vector2(62.0, 0.0))
	await t.steps(2)
	t.player().get_shapes().set_current(ShapeDefs.HAMMER)
	t.tap(&"attack")
	await t.sim_wait(700.0)
	t.check(_hp(clod) < before, "the Hammer did not hurt iron")


## A thrown thing hurts the one-weapon materials as it hurts flesh (owner, 2026-11-26: "the rule is only
## for weapons, spear axe and hammer"): a light pot takes its full damage off an iron Clod Stomper and a
## bark Thorn Guard, with no line (nothing was refused).
func test_a_throw_hurts_the_one_weapon_enemies(t: TestContext) -> void:
	await _enter(t)
	ThrowMode.set_dev_level(3)
	for case: Array in [["clod-stomper", "iron"], ["thorn-guard", "bark"]]:
		var enemy := await _spawn(t, str(case[0]), Vector2(150.0, 0.0))
		if not t.check(enemy != null, "no %s" % case[0]):
			return
		if enemy.has_method(&"wake"):
			enemy.call(&"wake", t.now())
			await t.until(func() -> bool: return not ["asleep", "wake"].has(str(enemy.get(&"_phase"))), 4000.0)
		var before := await _throw_pot_at(t, enemy, Vector2(150.0, 0.0))
		await t.sim_wait(900.0)
		t.near(_hp(enemy), before - ThrowFeel.base_damage(), 0.5, "a light pot on %s (%s)" % [case[1], case[0]])
		t.check(not Services.run().has_flag(HitMaterials.FLAG_PREFIX + str(case[1]) + ".thrown"),
			"a line for a throw on %s showed" % case[1])
		var body := enemy.get(&"body") as Node2D
		if body != null:
			body.global_position += Vector2(0.0, 1200.0)
		await t.steps(2)


func test_the_folds_the_squint_and_the_bulwark(t: TestContext) -> void:
	await _enter(t)
	# The Squint's own rule is now only its visor: open, the eye decides.
	var squint := ReactionProfile.for_type("squint")
	var cut := HitReaction.build_hit("tap", {"shape": "axe", "tags": WEAPON_TAGS["cut"]})
	var spear := HitReaction.build_hit("tap", {"shape": "spear", "tags": WEAPON_TAGS["spear"]})
	var pot := HitReaction.build_hit("thrown", {"tags": ["thrown", "clay-pot"]})
	t.equal(HitReaction.material_gate(squint, cut, "open"), HitReaction.GATE_CLINK, "an open Squint against the Axe")
	t.equal(HitReaction.material_gate(squint, spear, "open"), "", "an open Squint against the Spear")
	t.equal(HitReaction.material_gate(squint, pot, "open"), "", "an open Squint against a pot")
	t.equal(HitReaction.gate(squint, pot, _in_phase("walk")), HitReaction.GATE_CLINK, "a shut Squint against a pot")
	# The Bulwark's clink tags keep only what a material cannot say; the shell refuses the Spear.
	var bulwark := ReactionProfile.for_type("worm-bulwark")
	var tags: Array = (bulwark.get("hits", {}) as Dictionary).get("clinkTags", []) if bulwark.get("hits", {}) is Dictionary else []
	if tags.is_empty():
		tags = _bulwark_clink_tags()
	t.check(not tags.has("spear"), "the Bulwark still lists the Spear: %s" % str(tags))
	t.equal(HitReaction.material_gate(bulwark, spear), HitReaction.GATE_CLINK, "the Bulwark's shell against the Spear")


func test_the_shardbacks_brittle_shell_takes_the_spear(t: TestContext) -> void:
	var shardback := ReactionProfile.for_type("shardback")
	var spear := HitReaction.build_hit("tap", {"shape": "spear", "tags": WEAPON_TAGS["spear"]})
	t.equal(HitReaction.material_gate(shardback, spear, ""), HitReaction.GATE_CLINK, "a cold shell against the Spear")
	t.equal(HitReaction.material_gate(shardback, spear, "brittle"), "", "a brittle shell against the Spear")


# --- helpers ----------------------------------------------------------------------------------------

func _enter(t: TestContext) -> void:
	ThrowMode.set_assist(false)
	t.main.call(&"travel_to", MAP_ID)
	await t.until(func() -> bool: return ReworkMode.is_on() and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")), 3000.0)
	await t.steps(3)
	ThrowMode.set_dev_level(1)
	var run := Services.run()
	for id: StringName in ShapeDefs.IDS:
		run.learn_session_ability(String(id))
	t.player().get_shapes().sync_learned()
	t.teleport_player(Services.world().player_spawn_point() + RANGE_FROM_SPAWN)
	t.player().face(Vector2.RIGHT)
	await t.steps(2)


## A `type` enemy whose centre stands `offset` from the slime's, calm (it neither chases nor stomps).
func _spawn(t: TestContext, type: String, offset: Vector2) -> Node:
	var root := Services.world().spawn_at_phaser_position("character." + type, t.player().get_centre() + offset)
	if root == null:
		return null
	for child: Node in root.get_children():
		if child.has_method(&"get_damage_state"):
			for property: StringName in [&"targeting_radius", &"attack_range"]:
				if property in child:
					child.set(property, 0.0)
			if &"_next_stomp_at" in child:
				child.set(&"_next_stomp_at", INF)
			await t.steps(3)
			return child
	return null


func _in_phase(phase: String) -> ReactionState:
	var state := ReactionState.new()
	state.phase = phase
	return state


func _place(t: TestContext, enemy: Node, offset: Vector2) -> void:
	var body := enemy.get(&"body") as Node2D
	if body != null:
		body.velocity = Vector2.ZERO
		body.global_position = t.player().body.global_position + offset
		body.reset_physics_interpolation()


func _hp(enemy: Node) -> float:
	return float((enemy.call(&"get_damage_state") as Dictionary).get("hp", 0.0))


func _catch(t: TestContext, kind: String) -> void:
	var player := t.player()
	ThrowAmmo.spawn_liftable(kind, player.body.global_position + Vector2(0.0, 30.0))
	await t.steps(2)
	player.face(Vector2.DOWN)
	t.tap(&"eat")
	await t.until(func() -> bool: return not player.held().is_empty(), 900.0)
	await t.sim_wait(350.0)


## A clay pot sucked in and thrown right at `enemy` (placed `offset` from the slime); its health just
## as the throw leaves.
func _throw_pot_at(t: TestContext, enemy: Node, offset: Vector2) -> float:
	await _catch(t, "clay-pot")
	t.check(not t.player().held().is_empty(), "the pot was not sucked in")
	_place(t, enemy, offset)
	await t.steps(2)
	var before := _hp(enemy)
	t.player().face(Vector2.RIGHT)
	t.tap(&"eat")
	return before


func _read_types() -> Dictionary:
	var file := FileAccess.open("res://game/data/enemy-types.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else {}
	return parsed if parsed is Dictionary else {}


## Every type with a `reactions` block: type id -> its `hitMaterial` ("" when it names none).
func _collect(node: Variant, out: Dictionary) -> void:
	if not node is Dictionary:
		return
	for key: Variant in (node as Dictionary):
		var value: Variant = (node as Dictionary)[key]
		if value is Dictionary and (value as Dictionary).has("reactions"):
			out[str(key)] = str(((value as Dictionary)["reactions"] as Dictionary).get("hitMaterial", ""))
		else:
			_collect(value, out)


func _bulwark_clink_tags() -> Array:
	var types := _read_types()
	var found: Array = []
	var stack: Array = [types]
	while not stack.is_empty():
		var node: Variant = stack.pop_back()
		if not node is Dictionary:
			continue
		if (node as Dictionary).has("clinkTags"):
			found = (node as Dictionary)["clinkTags"]
		for value: Variant in (node as Dictionary).values():
			stack.append(value)
	return found

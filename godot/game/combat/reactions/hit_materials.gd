extends RefCounted
## What a hit meets (one combat, piece 4 of docs/design/2026-11-25-weapons-beside-throws.md; the owner's
## table of 2026-11-25; docs/godot/BESTIARY.md "Materials"): each enemy type has a hit material
## (`reactions.hitMaterial` in enemy-types.json; `flesh` when none), and `combat.materials.<material>` in
## game-constants.json says which of the three weapons it refuses (`refuses`: the weapon tags every weapon
## hit carries, `spear` the Spear, `cut` the War Axe, `crush` the Hammer). The table is only for the
## weapons (the owner, 2026-11-26: "the rule is only for weapons, spear axe and hammer"; of the abilities:
## "Yes, they hurt", "until i decide otherwise"): a thrown thing, an arrow, the Goo Bomb's blast, the Lantern's flame, the Roll and a
## slam are never refused, on bark, iron and eye (one weapon of the three hurts them) as on flesh. A refused
## weapon clinks (HitReaction.gate through `material_gate`: the clink's feel, the slime's recoil, the combo
## broken).
##
## It reads. The first refusal of a material by a weapon in a run (story flag
## `hint.material.<material>.<weapon tag>`) floats that material's line for it (`lines.<spear|cut|crush>`)
## over the slime and flashes the enemy (game/feel/hint_cue.gd): `on_refused`.
##
## The old `material` key (worm, chitin, goo, stone...) stays what it was: the puffs, sparks and sounds.
##
## Owner: reactions.

const Services := preload("res://game/shared/services.gd")
const HintCue := preload("res://game/feel/hint_cue.gd")

const KEY := "hitMaterial"
const TABLE_PATH := "combat.materials"
const FLESH := "flesh"
## The weapon tags the table names (ShapeDefs `tags`: the Spear, the War Axe, the Hammer).
const WEAPON_TAGS: Array[String] = ["spear", "cut", "crush"]
const FLAG_PREFIX := "hint.material."
## The line's lift over the slime and how long it and the pointer last; the pointer's flashes and how
## high its arrow stands over the enemy (presentation).
const LIFT_PX := 96.0
const HINT_MS := 4500.0
const FLASHES := 3
const ARROW_RISE_PX := 56.0
const CUE_NAME := "MaterialHint"


## The hit material of `profile` (ReactionProfile.for_enemy) in `phase` (its `states.<phase>.hitMaterial`
## when that phase has one: the Shardback's brittle shell is flesh), else its `hitMaterial`, `flesh` when
## none.
static func of(profile: Dictionary, phase: String = "") -> String:
	if not phase.is_empty():
		var states: Variant = profile.get("states", {})
		var entry: Variant = (states as Dictionary).get(phase, {}) if states is Dictionary else {}
		if entry is Dictionary and (entry as Dictionary).has(KEY):
			return str((entry as Dictionary)[KEY])
	var material := str(profile.get(KEY, ""))
	return material if not material.is_empty() else FLESH


## `combat.materials.<material>` ({} when the table has no such row).
static func row(material: String) -> Dictionary:
	var constants := Services.constants()
	var raw: Variant = constants.value("%s.%s" % [TABLE_PATH, material], {}) if constants != null else {}
	return raw if raw is Dictionary else {}


## The weapon tag of `hit` that `material` refuses (the key of its line), "" when it takes it: a hit
## carries one of the three weapons' tags only when a weapon struck (a thrown thing, an ability, a
## mechanism never does).
static func refused_tag(material: String, hit: Dictionary) -> String:
	var tags: Variant = hit.get("tags", [])
	var refuses: Variant = row(material).get("refuses", [])
	if not tags is Array or not refuses is Array:
		return ""
	for tag: String in WEAPON_TAGS:
		if (tags as Array).has(tag) and (refuses as Array).has(tag):
			return tag
	return ""


## The line `material` says for `key` (a weapon tag); "" when the data has none.
static func line(material: String, key: String) -> String:
	var lines: Variant = row(material).get("lines", {})
	return str((lines as Dictionary).get(key, "")) if lines is Dictionary else ""


## `enemy` (of `material`) refused `key` (a weapon tag): the first time in the run its line
## floats over the slime and a pointer flashes the enemy. True when it showed.
static func on_refused(enemy: Node, material: String, key: String) -> bool:
	var text := line(material, key)
	var run := Services.run()
	if text.is_empty() or run == null or enemy == null or not is_instance_valid(enemy):
		return false
	var flag := "%s%s.%s" % [FLAG_PREFIX, material, key]
	if run.has_flag(flag):
		return false
	run.set_flag(flag)
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var feel := Services.feel()
	if feel != null and player != null:
		feel.hint_text(player, LIFT_PX, text, &"orange", HINT_MS)
	var body: Variant = enemy.call(&"get_body") if enemy.has_method(&"get_body") else enemy
	if not body is Node2D or not (body as Node2D).is_inside_tree():
		return true
	var old := (body as Node2D).get_node_or_null(CUE_NAME)
	if old != null:
		old.queue_free()
	var cue := HintCue.new()
	cue.name = CUE_NAME
	cue.set(&"flashes", FLASHES)
	cue.set(&"life_ms", HINT_MS)
	cue.set(&"arrow_rise", ARROW_RISE_PX)
	(body as Node2D).add_child(cue)
	var centre: Variant = enemy.call(&"get_centre") if enemy.has_method(&"get_centre") else null
	cue.global_position = centre if centre is Vector2 else (body as Node2D).global_position
	return true

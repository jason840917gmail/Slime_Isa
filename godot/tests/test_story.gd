extends RefCounted
## Story flags and story variants (game/scripts/story_flag.gd, story_variant.gd; Phaser
## StoryFlagScript.ts, StoryVariantScript.ts). level-1's `chapter-1-villagers-variant` keeps the
## `chapter-1-villagers` subtree (two NPCs) only while `chapter-1-complete` is unset.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const FLAG := "chapter-1-complete"
const VILLAGERS := "chapter-1-villagers"


func test_level1_villagers_leave_when_chapter_1_completes(t: TestContext) -> void:
	var villagers := t.world().world_root.find_child(VILLAGERS, true, false)
	if not t.check(villagers != null, "level-1 has no %s subtree" % VILLAGERS):
		return
	t.check(villagers.is_inside_tree(), "the villagers are not in the tree before the flag")
	t.check(Services.run().set_flag(FLAG), "set_flag(%s) reported already set" % FLAG)
	await t.steps(1)
	t.check(is_instance_valid(villagers) and not villagers.is_inside_tree(), "the villagers stayed after the flag was set")
	t.check(not Services.run().set_flag(FLAG), "setting the flag twice reported a change")


## A world built after the flag is set starts with the variant already swapped (one deferred frame).
func test_variant_follows_a_flag_set_before_the_world_loads(t: TestContext) -> void:
	Services.run().set_flag(FLAG)
	t.check(t.main.travel_to("level-1", "south"), "travel back into level-1 was refused")
	var arrived := await t.until(func() -> bool: return not t.main.is_transitioning() and t.player() != null, 3000.0, 6000.0)
	if not t.check(arrived, "the rebuilt level-1 never finished loading"):
		return
	await t.steps(2)
	var villagers := t.world().world_root.find_child(VILLAGERS, true, false)
	t.check(villagers == null, "the villagers are in the rebuilt level-1 although %s is set" % FLAG)

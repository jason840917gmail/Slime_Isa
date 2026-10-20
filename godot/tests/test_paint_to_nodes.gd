extends RefCounted
## tools/paint_to_nodes.gd's `--group` folders (docs/godot/PROPS.md "Painted props to nodes"): a
## ground detail or water life prop goes in the folder of a whole word of its name (or its plural),
## never of a word hidden inside another, and every other prop goes straight under `Scenery` ("").
## The tool is not run: only its sorting.

const TestContext := preload("res://tests/lib/test_context.gd")
const PaintToNodes := preload("res://tools/paint_to_nodes.gd")

const FLOOR := "interiors/mushroom-floor/interior-mushroom-floor-%s.tscn"


func test_ground_details_are_sorted_by_whole_words(t: TestContext) -> void:
	for pair: Array in [
		["stepping-stone-1", "Rocks"], ["pebbles-2", "Rocks"], ["rock-half-buried", "Rocks"],
		["twigs", "Twigs"], ["root-3", "Twigs"],
		["flowers-white-clover", "Flowers"], ["flowers-forget-me-not", "Flowers"], ["petals", "Flowers"],
		["mushrooms-red", "Mushrooms"], ["chanterelles", "Mushrooms"], ["toadstool-tiny", "Mushrooms"],
		["acorns-leaves", "Leaves"], ["leaf-big", "Leaves"],
		["grass-moss-1", "Plants"], ["clover-4", "Plants"], ["fern-frond", "Plants"],
		["seeds", "Mushroom Floor"],
	]:
		t.equal(PaintToNodes._group_of(FLOOR % pair[0]), pair[1], "the folder of %s" % pair[0])
	for pair: Array in [
		["water-life--reeds-rushes.tscn", "Water life"], ["water-life--fish-koi-lane.tscn", "Water life"],
		["water-life--waterweed-bushy.tscn", "Water life"], ["water-life--kelp-teal.tscn", "Water life"],
	]:
		t.equal(PaintToNodes._group_of(pair[0]), pair[1], "the folder of %s" % pair[0])
	# Words inside other words, and props that are no ground detail.
	t.equal(PaintToNodes._group_of(FLOOR % "gravestone"), "Mushroom Floor", "a gravestone is no stone")
	t.equal(PaintToNodes._group_of(FLOOR % "candlestick"), "Mushroom Floor", "a candlestick is no stick")
	t.equal(PaintToNodes._group_of(FLOOR % "brush"), "Mushroom Floor", "a brush is no rush")
	t.equal(PaintToNodes._group_of("interiors/decor/interior-decor-candlestick-lit.tscn"), "", "an interior candlestick")
	t.equal(PaintToNodes._group_of("decoration-world-solid--village-well.tscn"), "", "the village well")
	t.equal(PaintToNodes._group_of("rock-world-wall-solid--field-03.tscn"), "", "a rock wall")

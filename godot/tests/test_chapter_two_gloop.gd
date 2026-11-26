extends RefCounted
## Gloop Forest's Silk gate to the Crystal Caverns: the web-wall maze south of the Watch Oak's glade
## in chunk F4 (docs/design/2026-11-21-gloop-river-roads.md, "The main path" step 8: "With the Silk
## skin: the web-wall maze south of the glade, then east to the Caverns"). Its four web walls
## (`object.web-wall`, `RiverRoads/maze-1..4`: maze-1 at (1216, 1216) and maze-2 at (768, 1536)
## "across", maze-3 at (1088, 1728) and maze-4 at (1536, 1728) "side") stand uncut and are solid to a
## walk without the Silk skin (docs/godot/WEBS.md).
## Rewritten 2026-11-20: the quests A Harder Pick and Beyond the Verdant Gate are retired, with their
## tests (the reinforced pickaxe on the iron nodes, the weavers and fangs counted).
## Rewritten 2026-11-25: River Roads (2026-11-21) took out the old web lane (`web-lane/web-lane-1..3`)
## for the maze.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const WebWallScript := preload("res://game/scripts/web_wall.gd")

const MAP_ID := "gloop-forest-f4"
const WALLS := {
	"RiverRoads/maze-1": "across", "RiverRoads/maze-2": "across",
	"RiverRoads/maze-3": "side", "RiverRoads/maze-4": "side",
}
## The side wall walked into from the west.
const WALKED := "RiverRoads/maze-3"


func test_web_walls_close_the_maze_to_the_caverns_without_the_silk_skin(t: TestContext) -> void:
	var root := t.world().world_root
	var walls: Dictionary[String, WebWallScript] = {}
	for path: String in WALLS:
		var wall := root.get_node_or_null(path) as WebWallScript
		t.check(wall != null, "no web wall %s in F4" % path)
		if wall != null:
			walls[path] = wall
			t.equal(wall.orientation, str(WALLS[path]), "%s's orientation" % path)
			t.check(not wall.is_cut(), "%s starts cut" % path)
	t.check(not Services.run().has_skin("silk"), "the run starts with the Silk skin")
	if not walls.has(WALKED):
		return
	# Walking east from west of the maze's side wall stops at its face.
	var wall := walls[WALKED]
	var face := wall.global_position.x - wall.thickness / 2.0
	t.teleport_player(Vector2(face - 90.0, wall.global_position.y - 27.56))
	await t.steps(3)
	t.press(&"move_right")
	await t.sim_wait(1200.0)
	t.release_all()
	t.check(t.player().get_centre().x < face, "the walk went through %s (%.1f, its face at %.1f)"
		% [WALKED, t.player().get_centre().x, face])

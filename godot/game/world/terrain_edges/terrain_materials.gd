extends RefCounted
## The grounds that get hand-made edge tiles (docs/godot/TERRAIN_LAB.md) and how they stack.
##
## A ground is the authored tile set's transition material
## (src/game/content/scenes/authored/resources/terrain/terrain.tile-set.resource.json); several
## tile ids can share one (grass-a and grass-b are both `highland`). `water` and `deep-water` are
## one water ground here: the water surface itself blends shallow into deep. Tiles that are not
## listed (rock-wall, wood-floor, the mushroom floors) keep hard edges, as in Phaser.
##
## Owner: world (terrain edges).

## Bottom to top: where grounds meet, the higher one's edge tiles are drawn over the lower one.
## Phaser's transition priorities (water 4-5 < the natural grounds 10 < town-cobble 12 < forest-moss,
## crystal-floor 20), with the ties broken so the more "lying on top" ground wins: grass grows over
## sand and soil, fallen leaves and snow lie on top of everything at their priority.
const ORDER: PackedStringArray = [
	"water", "cavern-floor", "forest-floor", "sanddessert", "highland", "amberleaf", "frozen",
	"town-cobble", "forest-moss", "crystal-floor",
]
## The water ground: no edge art of its own, filled with the animated water.
const WATER := "water"
## Terrain tile id -> ground.
const TILE_GROUNDS := {
	"amberleaf-ground": "amberleaf",
	"cavern-floor": "cavern-floor",
	"crystal-floor": "crystal-floor",
	"deep-water": "water",
	"forest-floor": "forest-floor",
	"forest-moss": "forest-moss",
	"frozen-ground": "frozen",
	"grass-a": "highland",
	"grass-b": "highland",
	"sanddessert-ground": "sanddessert",
	"town-cobble": "town-cobble",
	"water": "water",
}
## Edge art, built by scripts/art/build-terrain-edge-tiles.py.
const ART_DIR := "res://game/world/terrain_edges/art/"


## The ground of terrain tile `tile_id`, or "" when it keeps hard edges.
static func ground_of(tile_id: String) -> String:
	return str(TILE_GROUNDS.get(tile_id, ""))


## Stacking order of `ground` (higher draws on top), -1 when it has no edges.
static func order_of(ground: String) -> int:
	return ORDER.find(ground)


## The 16-tile edge sheet of `ground` and its rim weights.
static func edges_path(ground: String) -> String:
	return ART_DIR + ground + "-edges.png"


static func rim_path(ground: String) -> String:
	return ART_DIR + ground + "-edges-rim.png"

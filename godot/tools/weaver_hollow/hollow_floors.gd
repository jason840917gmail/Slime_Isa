extends RefCounted
## The Weaver Hollow's four floors (docs/design/2026-10-16-dungeon-weaver-hollow.md "Room by room";
## docs/godot/DUNGEONS.md "The Weaver Hollow"): the Trunk (the entrance and the hub), the Roots, the
## Boughs and the Crown, each a world `weaver-hollow-<floor>`. Rooms are camera rooms of 16 x 14
## cells carved out of the rock (hollow_canvas.gd); cell coordinates below are the floor's.
##
## Doors between the floors (door.gd; a north door pairs with a south one, east with west):
## - trunk-entrance (T1, south) <-> the forecourt's root gate (gloop-forest-f4, built last);
## - trunk-east-stair (T2, east) <-> boughs-from-trunk (B1, west);
## - trunk-gallery-stair (T2's gallery, north) <-> boughs-hoard-stair (the Hoard, south);
## - trunk-crown-door (T2's gallery, north) <-> crown-from-trunk (C1, south);
## - trunk-hatch (T2, a ladder down) <-> roots-ladder (R3, a ladder up);
## - the Well Room's blown floor (T4, a fall) -> the marker roots-landing (R1; nothing leads back);
## - crown-bough-drop (C3, a fall) -> the forecourt (built last).
##
## The shared dungeon kit (docs/godot/DUNGEONS.md, `object.<kind>` under `Objects`): a Dungeon node
## in every floor (one dungeon, resumed at T1's `dungeon-entrance`; its boss the Matron, whose fall
## breaks the seal), the key doors, the chests (the map, two small keys, the big key), the shutters
## and room fights, the drawbridges, the voids' hazards, the pots and the energy flower, the dark
## cellar's glint, and the two seals (`object.dungeon-seal`: T1's way out, C2's east doorway).
##
## The Pearl inside the dungeon (owner, 2026-10-17; docs/design/2026-10-17-pearl-mid-dungeon.md
## "The Weaver Hollow"): the first half is the Goo Bomb's, up to the Brood Warden (B4 the Nursery and
## B6 the Pillar an optional wing); Pearl 2 lies in the Hoard beside the big key, guarded by the
## Warden's fight; taking it seals the dungeon. The second half teaches the Silk skin: the Hoard's
## stair (a web wall), the gallery (the calm room), the Crown Door, C1 (webs wall to wall, a web wall
## on the straight way, the K3 door), C4 the Spinning Loft (rows of web walls under Slime Spider
## fire, small key 3 in a silk parcel), then the Matron's fight, the Silk skin's exam.
##
## Owner: world (dungeons).

const HollowCanvas := preload("res://tools/weaver_hollow/hollow_canvas.gd")
const HollowScene := preload("res://tools/weaver_hollow/hollow_scene.gd")

const FLOORS: PackedStringArray = ["trunk", "roots", "boughs", "crown"]
const WORLD := "weaver-hollow-%s"
const C := HollowCanvas
const S := HollowScene

const CRACKED_WALL := "res://game/scenes/objects/cracked-wall.tscn"
const CRACKED_FLOOR := "res://game/scenes/objects/cracked-floor.tscn"
const LANDING := "res://game/scenes/objects/landing.tscn"
const WINCH_POST := "res://game/scenes/objects/winch-post-cracked.tscn"
const BLAST_KEG := "res://game/scenes/objects/blast-keg.tscn"
const WEB_WALL := "res://game/scenes/objects/web-wall.tscn"
const DROP_GATE := "res://game/scenes/objects/drop-gate.tscn"
const GATE_WINCH := "res://game/scenes/objects/gate-winch.tscn"
const MATRON_CAMP := "res://game/scenes/encounters/weaver-hollow-matron.tscn"
## C4's dressing (game/scenes/objects/weaver-hollow/<name>.tscn): [name, x, y] (cells).
const LOFT_PROP := "res://game/scenes/objects/weaver-hollow/%s.tscn"
const LOFT_DRESSING := [
	["loft-rafter", 20.2, 17], ["loft-peg-rail", 24.6, 17], ["loft-rafter", 28.4, 17],
	["loft-spool", 17.9, 22.8], ["loft-spinning-wheel", 29.5, 26.2],
]
const SILK_PARCEL := "res://game/scenes/objects/silk-parcel.tscn"
const LIFTABLE := "res://game/scenes/objects/liftable.tscn"
const KIT := "res://game/scenes/objects/dungeon/%s.tscn"
const CHEST := "res://game/scenes/objects/dungeon/dungeon-chest.tscn"
const BIG_CHEST := "res://game/scenes/objects/dungeon/dungeon-big-chest.tscn"
const GOO_HEART := "res://game/scenes/objects/goo-heart.tscn"
const PEARL_TWO := "res://game/scenes/objects/pearl-two.tscn"
## The brood's altar in the Hoard (art: asset/Originals/weaver-hollow/loft/, scripts/art/pack-loft-art.py).
const PEARL_ALTAR := "res://game/scenes/objects/weaver-hollow/brood-altar.tscn"
const DUNGEON_ID := "weaver-hollow"
const DUNGEON_NAME := "Weaver Hollow"
## The seal (Dungeon node, docs/godot/DUNGEONS.md "The seal"): the Matron's fight breaks it.
const BOSS_ID := "orb-weaver-matron"
const BOSS_NAME := "The Orb-Weaver Matron"
const SEAL_COLOR := Color("#9a5ad8")
const SEAL_DUST := Color("#efe6d6")
const ROAR_SOUND := "res://asset/audio/sfx/synth/enemy/spider-hiss.wav"
const ROAR_PITCH := 0.4
## The Brood Warden's room fight: Pearl 2's guard.
const WARDEN_BOSS_ID := "weaver-hollow-brood-warden"
const PEARL_FLAG := "pearl.orb-weaver-matron"
const PEARL_GLINT := Color(0.86, 0.8, 1.0)
## The Node2D in T1 where a faint or a quit resumes (the Dungeon node's `entrance_marker`).
const ENTRANCE_MARKER := "dungeon-entrance"
const CAVE_LADDER := "res://game/scenes/objects/cave-ladder.tscn"
const DEADTHORN := "res://game/scenes/objects/deadthorn-hedge.tscn"
const CANDLE_SCRIPT := "res://game/world/fire/candle.gd"
const CANDLE_UNLIT := "res://game/scenes/objects/interiors/decor/interior-decor-candlestick-unlit.tscn"
const CANDLE_LIT := "res://game/scenes/objects/interiors/decor/interior-decor-candlestick-lit.tscn"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const STORY_VARIANT := "res://game/scripts/story_variant.gd"
const LATCHED_HATCH := "res://game/scripts/latched_hatch.gd"
const PROP_PALETTES := "res://game/world/props/prop_palettes.json"
const ROOT := "interior-mushroom-floor-root-"
const PILLAR := "interior-structure-pillar-stone"
const HANGING_ROOTS := "interior-mushroom-structure-wall-hanging-roots"
const GLOW := "interior-mushroom-decor-glow-mushroom-"
const MOSS := "interior-mushroom-floor-moss-"
const PEBBLES := "interior-mushroom-floor-pebbles-"
## Doorway triggers (world units, around the door node): across a two-cell gap.
const TRIGGER_NS := Rect2(-64.0, -20.0, 128.0, 40.0)
const TRIGGER_EW := Rect2(-20.0, -64.0, 40.0, 128.0)
## C4 the Spinning Loft: the floor lines (cell rows) of its two rows of web walls, south to north.
const C4_ROWS: Array[float] = [24.0, 20.6]


## Scenery props by the base name of their scene (game/world/props/prop_palettes.json), placed
## under `Scenery`: decoration only. Kept out of the Hollow for the clarity rule: decorative ground
## webs, cocoons and egg sacs (the floor webs, the Cocoon Mimic and the egg sacs are real), unlit
## candles (the Lantern's lock), cracked floor tiles (the Goo Bomb's), grates (the Spear's), baskets,
## crates and barrels (the Gulp's liftables, the blast kegs), armour statues (heavy blocks).
static var _prop_paths: Dictionary = {}
static var _prop_count: int = 0


static func _prop_path(base: String) -> String:
	if _prop_paths.is_empty():
		var palettes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROP_PALETTES))
		for kind: String in palettes:
			for palette: Dictionary in palettes[kind]:
				for scene_path: String in palette["scenes"]:
					_prop_paths[scene_path.get_file().get_basename()] = scene_path
	return _prop_paths.get(base, "")


static func _prop(root: Node2D, base: String, x: float, y: float, flip: bool = false) -> Node2D:
	var path := _prop_path(base)
	if path.is_empty():
		push_error("hollow_floors: no prop %s" % base)
		return null
	_prop_count += 1
	var node := S.place(root, "Scenery", "%s-%d" % [base.trim_prefix("interior-").trim_prefix("mushroom-"), _prop_count],
			path, _at(x, y))
	if flip:
		node.scale = Vector2(-1.0, 1.0)
	return node


## Props strewn along the inside of a floor rect (cells): every `step` cells along each wall, one
## of `kinds` picked by place, skipping the cells in `keep_clear` (door gaps and paths).
static func _strew(root: Node2D, rect: Rect2i, kinds: Array, step: int, keep_clear: Array = [], inset: float = 0.6) -> void:
	var spots: Array[Vector2] = []
	for x in range(rect.position.x + 1, rect.end.x - 1, step):
		spots.append(Vector2(x + 0.5, rect.end.y - inset))
		spots.append(Vector2(x + 1.0, rect.position.y + 2.6))
	for y in range(rect.position.y + 3, rect.end.y - 1, step):
		spots.append(Vector2(rect.position.x + inset, y + 0.5))
		spots.append(Vector2(rect.end.x - inset, y + 1.0))
	var i := 0
	for spot in spots:
		var blocked := false
		for clear: Rect2 in keep_clear:
			if clear.has_point(spot):
				blocked = true
		if blocked:
			continue
		var kind: String = kinds[absi(int(spot.x * 7.0 + spot.y * 13.0) + i) % kinds.size()]
		_prop(root, kind, spot.x, spot.y, (int(spot.x + spot.y) % 2) == 0)
		i += 1


## A scatter of props: [base, x, y] or [base, x, y, flip].
static func _props(root: Node2D, list: Array) -> void:
	for entry: Array in list:
		_prop(root, entry[0], entry[1], entry[2], entry.size() > 3 and bool(entry[3]))


static func build(floor_name: String) -> Node2D:
	match floor_name:
		"trunk":
			return _trunk()
		"roots":
			return _roots()
		"boughs":
			return _boughs()
		"crown":
			return _crown()
	return null


static func world_id(floor_name: String) -> String:
	return WORLD % floor_name


static func _at(x: float, y: float) -> Vector2:
	return S.at(x, y)


static func _pot(root: Node2D, node_name: String, x: float, y: float, kind: String = "clay-pot") -> void:
	S.place(root, "Objects", node_name, LIFTABLE, _at(x, y), {"LiftableScript:kind": kind})


## A clay pot of the kit (`object.dungeon-pot`) that hides `loot` ("heart", "energy", "coins",
## "random"); it and its loot come back when its room is entered again.
static func _dungeon_pot(root: Node2D, node_name: String, x: float, y: float, loot: String) -> void:
	_kit(root, node_name, "dungeon-pot", x, y, {"PotLoot:loot": loot})


## A dungeon chest (the kit's wooden chest, or the big chest), its record id its world and name; the
## dungeon items in `contents` ("dungeon-small-key", "dungeon-big-key", "dungeon-map") go straight to
## the dungeon. `hidden`: it rises when set off (a room fight's reward).
static func _chest(root: Node2D, node_name: String, x: float, y: float, contents: Dictionary, big: bool = false,
		hidden: bool = false) -> Node2D:
	var chest := S.place(root, "Objects", node_name, BIG_CHEST if big else CHEST, _at(x, y))
	var script_node := chest.get_node_or_null("ChestScript")
	S.editable(root, chest)
	if script_node != null:
		script_node.set(&"map_id", str(root.name))
		script_node.set(&"instance_id", "%s-%s" % [str(root.name), node_name])
		script_node.set(&"initial_contents", contents)
		script_node.set(&"hidden", hidden)
	return chest


## A piece of the shared dungeon kit (`object.<kind>`, docs/godot/DUNGEONS.md) under `Objects`, at cell
## point (x, y), its properties `props` (S.place).
static func _kit(root: Node2D, node_name: String, kind: String, x: float, y: float, props: Dictionary = {}) -> Node2D:
	return S.place(root, "Objects", node_name, KIT % kind, _at(x, y), props)


## The floor's Dungeon node (`object.dungeon`): the four floors are one dungeon, resumed at T1's
## entrance marker; and, in the Trunk, that marker.
static func _dungeon(root: Node2D, x: float, y: float) -> void:
	var trunk := world_id("trunk")
	_kit(root, "dungeon", "dungeon", x, y, {"dungeon_id": DUNGEON_ID, "display_name": DUNGEON_NAME,
			"entrance_marker": ENTRANCE_MARKER, "entrance_map_id": "" if str(root.name) == trunk else trunk,
			"boss_id": BOSS_ID, "boss_name": BOSS_NAME, "seal_color": SEAL_COLOR, "dust_color": SEAL_DUST,
			"roar_sound": load(ROAR_SOUND), "roar_pitch": ROAR_PITCH})


## A void (an elevation hole at level -2) the slime falls into: the kit's hazard over the cells
## `rect`, drawn by the hole itself; a fall puts the slime back on the rim it fell from.
static func _void(root: Node2D, node_name: String, rect: Rect2i) -> void:
	_kit(root, node_name, "hazard", rect.position.x, rect.position.y, {"kind": "void",
			"size": Vector2(rect.size) * float(S.CELL), "rim_level": 0, "draw_look": false})


## Where the dev launch option `room=<name>` starts the slime in `room` (a camera room whose middle
## is not floor): its `RoomEntry` child at cell point (x, y) of the floor.
static func _room_entry(room: Node2D, x: float, y: float) -> void:
	var entry := S.marker("RoomEntry", _at(x, y) - room.position)
	room.add_child(entry)


## A cracked wall on the north face whose foot is at cell row `foot_row`, centred on cell column
## `x` (the left of its two cells + 1): blown, the passage opens up to `top_row` for level 0.
static func _crack(root: Node2D, node_name: String, x: float, foot_row: int, top_row: int, flag: String) -> Node2D:
	var foot := _at(x, foot_row)
	var crack := S.place(root, "Objects", node_name, CRACKED_WALL, foot, {
		"flag_id": flag,
		"refusal_text": "It needs a blast.",
		"passage": Rect2(-64.0, float(top_row - foot_row) * 64.0, 128.0, float(foot_row - top_row) * 64.0 + 8.0),
		"passage_level": 0,
	})
	return crack


## The Trunk (the ground floor): T4 Well Room (0,0), T3 Larder (0,1), T2 the Hollow Heart (1,0)-(2,1),
## T1 Root Door (1,2), and the nook behind T1's web wall (2,2).
static func _trunk() -> Node2D:
	var canvas := HollowCanvas.new(world_id("trunk"), 3, 3)
	var cobble := C.TOWN_COBBLE
	# T4 Well Room: its floor in the east, a sealed pocket (the map nook, T3a) in the west.
	canvas.fill(Rect2i(5, 1, 10, 12), 0, cobble)
	canvas.fill(Rect2i(1, 7, 3, 6), 0, cobble)
	# T3 Larder: the brood's larder, dry leaves on the floor.
	canvas.carve_room(0, 1, 1, 1, C.AMBERLEAF)
	# T2 the Hollow Heart: the gallery (level 1) along its north under two rows of rock (the Crown
	# Door's arch stands in them, as the kit's doors do), four rows deep so the door shows from the
	# top of the hub's floor; the floor below, a front flight of stairs down from the gallery's east
	# end.
	canvas.carve_room(1, 0, 2, 2, cobble)
	canvas.rock(Rect2i(17, 1, 30, 1))
	canvas.fill(Rect2i(17, 2, 30, 4), 1, cobble)
	canvas.paint_stairs(44, 6, "s")
	# T1 Root Door: dry leaves blown in, moss along the walls.
	canvas.carve_room(1, 2, 1, 1, C.AMBERLEAF)
	canvas.paint_ground(Rect2i(17, 31, 3, 10), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(26, 38, 5, 3), C.FOREST_MOSS)
	# S3: the nook behind T1's east web wall.
	canvas.fill(Rect2i(33, 31, 5, 8), 0, C.FOREST_MOSS)
	# Doors through the bands: T3-hub, hub-T1, T1-nook; the gaps to other worlds: the entrance (T1
	# south), the hub's east stair, the Crown Door and the Hoard's stair (the gallery's north).
	canvas.door_east_west(15, 21, cobble)
	canvas.door_north_south(23, 27, cobble)
	canvas.door_east_west(31, 35, C.FOREST_MOSS)
	canvas.fill(Rect2i(23, 41, 2, 1), 0, C.FOREST_MOSS)
	canvas.fill(Rect2i(47, 19, 1, 4), 0, cobble)
	canvas.fill(Rect2i(31, 0, 2, 2), 1, cobble)
	canvas.fill(Rect2i(18, 0, 2, 2), 1, cobble)
	# Every wall is the oak's root rock (the fort's stone shows in its floors and pillars). Moss and
	# leaves creep over the old flagstones along the walls.
	canvas.paint_ground(Rect2i(17, 10, 2, 17), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(19, 25, 9, 2), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(42, 22, 5, 5), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(43, 7, 4, 3), C.AMBERLEAF)
	canvas.paint_ground(Rect2i(17, 3, 3, 3), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(5, 11, 3, 2), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(12, 3, 3, 2), C.FOREST_MOSS)

	# Floor webs: T1's band with its lane at the west end; the hub's patches; the Larder's bands.
	canvas.paint_webs(Rect2i(19, 34, 12, 2))
	canvas.paint_webs(Rect2i(27, 17, 3, 2))
	canvas.paint_webs(Rect2i(36, 22, 3, 2))
	canvas.paint_webs(Rect2i(3, 19, 6, 1))
	canvas.paint_webs(Rect2i(8, 23, 5, 1))
	# The Hoard's stair is choked with old silk (its web wall in the Boughs): the silk spills down the
	# gallery's west end, seen from the hub's floor on the first visit.
	canvas.paint_webs(Rect2i(18, 0, 2, 2), 1)
	canvas.paint_webs(Rect2i(17, 2, 5, 4), 1)
	canvas.paint_webs(Rect2i(22, 3, 1, 2), 1)
	var root := S.build(canvas, _at(24, 38))
	S.camera_room(root, "T4-well-room", 0, 0)
	S.camera_room(root, "T3-larder", 0, 1)
	S.camera_room(root, "T2-hollow-heart", 1, 0, 2, 2)
	S.camera_room(root, "T1-root-door", 1, 2)
	S.camera_room(root, "S3-nook", 2, 2)
	# Doors to the other worlds.
	S.door(root, "entrance", _at(24, 41.65), {"door_id": "trunk-entrance", "target_area_id": "gloop-forest-f4",
			"target_door_id": "weaver-hollow-root-gate", "side": "south", "kind": "opening", "trigger_rect": TRIGGER_NS})
	S.door(root, "east-stair", _at(47.65, 22), {"door_id": "trunk-east-stair", "target_area_id": world_id("boughs"),
			"target_door_id": "boughs-from-trunk", "side": "east", "kind": "opening", "trigger_rect": TRIGGER_EW})
	S.door(root, "crown-door", _at(32, 0.35), {"door_id": "trunk-crown-door", "target_area_id": world_id("crown"),
			"target_door_id": "crown-from-trunk", "side": "north", "kind": "opening", "trigger_rect": TRIGGER_NS})
	S.door(root, "gallery-stair", _at(19, 0.35), {"door_id": "trunk-gallery-stair", "target_area_id": world_id("boughs"),
			"target_door_id": "boughs-hoard-stair", "side": "north", "kind": "opening", "trigger_rect": TRIGGER_NS})
	_hatch(root)
	# T3 Larder: the way on (a crack in the north wall into T4) and the map nook (a second crack).
	_crack(root, "larder-crack-well", 8, 17, 12, "weaver-hollow.larder-crack-well")
	_crack(root, "larder-crack-nook", 3, 17, 12, "weaver-hollow.larder-crack-nook")
	S.enemy(root, "larder-orb-weaver-1", "orb-weaver", _at(5, 22), 200.0)
	S.enemy(root, "larder-orb-weaver-2", "orb-weaver", _at(11, 24), 200.0)
	_pot(root, "larder-pot-1", 2, 25)
	_pot(root, "larder-pot-2", 13.5, 25.5)
	# T3a the map nook: the dungeon map in its chest (north of where the blown crack comes up).
	_chest(root, "nook-map-chest", 2.5, 9.9, {"dungeon-map": 1})
	# T4 Well Room: the well and the first cracked floor, which drops into the Roots.
	S.place(root, "Objects", "well-floor", CRACKED_FLOOR, _at(8.5, 9.5), {"flag_id": "weaver-hollow.well-floor",
			"door_id": "trunk-well-floor", "target_area_id": world_id("roots"), "target_door_id": "roots-landing"})
	# T2 the Hollow Heart. Its east door (small key 1) to the Boughs; on the gallery (level 1, the calm
	# room after the Pearl, before the Crown) the Crown Door (the big key; the rock's face hangs one
	# course over row 2), pots that hide a heart or energy and an energy flower; the gallery's stair
	# down to the hub's floor is shut at its foot by a stone block that the winch on the gallery lowers
	# for good (the short way back from the entrance after a faint, inside the seal).
	_kit(root, "east-key-door", "key-door", 47, 22, {"door_id": "trunk-east-door", "wall": "east", "keyholes": 1})
	_kit(root, "crown-boss-door", "boss-door", 32, 3, {"door_id": "trunk-crown-door-lock", "wall": "north", "lock": "big"})
	_kit(root, "gallery-stair-block", "shutter", 45, 7, {"wall": "north", "starts_shut": true,
			"shutter_id": "trunk-gallery-stair-block"})
	var stair_block: Array[NodePath] = [NodePath("../gallery-stair-block")]
	_kit(root, "gallery-winch", "winch", 42.2, 4.6, {"winch_id": "trunk-gallery-winch", "targets": stair_block,
			"done_text": "The stair is open."})
	S.enemy(root, "hub-orb-weaver", "orb-weaver", _at(32, 18), 260.0)
	for i in 4:
		_dungeon_pot(root, "gallery-pot-%d" % i, 21 + i * 2.2, 4.2, ["heart", "energy"][i % 2])
	_kit(root, "gallery-flower", "energy-flower", 36, 4.4)
	_pot(root, "hub-pot-1", 18, 25.5)
	_pot(root, "hub-pot-2", 45.5, 25.5)
	# T1 Root Door: the dungeon's entrance (a faint or a quit inside resumes here) and S3's web wall.
	root.get_node("Doors").add_child(S.marker(ENTRANCE_MARKER, _at(24, 38)))
	_dungeon(root, 24, 39.5)
	# The seal in T1's south doorway, the way out (the blown root gate outside stays blown): shut from
	# Pearl 2's take until the Matron falls.
	_kit(root, "entrance-seal", "dungeon-seal", 24, 41, {"wall": "south", "glimpse": true})
	S.place(root, "Objects", "s3-web-wall", WEB_WALL, _at(32, 36), {"orientation": "side", "span": 128.0,
			"hides_secret": true, "flag_id": "weaver-hollow.s3-web-wall"})
	S.place(root, "Objects", "s3-parcel", SILK_PARCEL, _at(35.5, 37.6), {"coins": 30, "contents": {},
			"flag_id": "weaver-hollow.s3-parcel"})
	_pot(root, "root-door-pot-1", 18, 39.5)
	_pot(root, "root-door-pot-2", 29.5, 39.5)
	_dress_trunk(root)
	S.own(root, root)
	return root


## The Roots (below ground): R1 Root Fall (0,0), R2 the Bone Cellar (1,0)-(2,0), R3 the Drop Gate
## (3,0), D1 the Old Cellar (1,1, dark).
static func _roots() -> Node2D:
	var canvas := HollowCanvas.new(world_id("roots"), 4, 2)
	var cobble := C.TOWN_COBBLE
	# R1 Root Fall: the floor, a ledge (level 1) in its north-west where the slime lands, a front
	# flight down from the ledge's east end.
	canvas.carve_room(0, 0, 1, 1, C.AMBERLEAF)
	canvas.fill(Rect2i(1, 1, 8, 5), 1, C.FOREST_MOSS)
	canvas.paint_stairs(7, 6, "s")
	# R2 the Bone Cellar: the fort's barracks; a block of rock in its north-east holds a sealed
	# pocket (small key 1) behind a cracked face.
	canvas.carve_room(1, 0, 2, 1, cobble)
	canvas.rock(Rect2i(35, 1, 7, 6))
	canvas.fill(Rect2i(36, 1, 5, 4), 0, cobble)
	# R3 the Drop Gate: a band of rock across the room with the gate's gap (Fatty's Lair's old Thorn
	# Guard drop gate, the Roll's lock), the ladder up beyond it in the north.
	canvas.carve_room(3, 0, 1, 1, cobble)
	canvas.rock(Rect2i(49, 5, 14, 2))
	canvas.fill(Rect2i(55, 5, 2, 2), 0, cobble)
	# D1 the Old Cellar (dark): a rock tongue closing the chest's corner.
	canvas.carve_room(1, 1, 1, 1, C.FOREST_MOSS)
	canvas.rock(Rect2i(27, 21, 1, 6))
	canvas.paint_ground(Rect2i(17, 3, 3, 10), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(42, 10, 5, 3), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(59, 9, 4, 4), C.FOREST_MOSS)
	# Doors: R1-R2, R2-R3, R2-D1.
	canvas.door_east_west(15, 7, cobble)
	canvas.door_east_west(47, 10, cobble)
	canvas.door_north_south(23, 13, C.FOREST_MOSS)
	# Floor webs: R3's patches round the lane from the worm lever east to the gate (row 9 and the
	# gate's mouth stay clear), a few in R1.
	canvas.paint_webs(Rect2i(49, 10, 6, 3))
	canvas.paint_webs(Rect2i(57, 9, 6, 4))
	canvas.paint_webs(Rect2i(55, 11, 2, 2))
	canvas.paint_webs(Rect2i(9, 10, 3, 1))
	var root := S.build(canvas, _at(3, 3.5))
	S.camera_room(root, "R1-root-fall", 0, 0)
	S.camera_room(root, "R2-bone-cellar", 1, 0, 2, 1)
	S.camera_room(root, "R3-drop-gate", 3, 0)
	S.camera_room(root, "D1-old-cellar", 1, 1)
	# The landing: the Well Room's blown floor drops the slime here (object.landing; nothing leads back up).
	S.place(root, "Doors", "roots-landing", LANDING, _at(3, 3.5), {"door_id": "roots-landing"})
	# The ladder up to the hub's hatch, at R3's east end.
	var ladder := S.place(root, "Doors", "ladder", CAVE_LADDER, _at(60.5, 3.2))
	var ladder_door := ladder.get_node_or_null("DoorScript")
	S.editable(root, ladder)
	if ladder_door != null:
		ladder_door.set(&"map_id", world_id("roots"))
		ladder_door.set(&"door_id", "roots-ladder")
		ladder_door.set(&"target_area_id", world_id("trunk"))
		ladder_door.set(&"target_door_id", "trunk-hatch")
	# R1: the first egg sac, below the ledge.
	S.enemy(root, "root-fall-egg-sac", "egg-sac", _at(5, 9.5), 360.0)
	# R2: the Watcher Eye among the pillars, two Bone Throwers at their posts in the east end, small
	# key 1 in the sealed pocket behind the crack (the cover pillar stands two cells in front of it).
	S.enemy(root, "cellar-watcher-eye", "watcher-eye", _at(28, 8), 200.0)
	S.enemy(root, "cellar-bone-thrower-1", "bone-thrower", _at(44, 4.5), 96.0)
	S.enemy(root, "cellar-bone-thrower-2", "bone-thrower", _at(44, 7.6), 96.0)
	_crack(root, "cellar-crack-key", 38.5, 9, 4, "weaver-hollow.cellar-crack-key")
	_chest(root, "cellar-key-chest", 38.5, 3.7, {"dungeon-small-key": 1})
	# R3: the old Thorn Guard drop gate (object.drop-gate) at the gap's foot, its worm lever in the
	# open west of it: pull it, then Roll along the clear row. Beyond, the gatehouse winch holds the
	# gate up for good, so a later trip (D1, with the Lantern) does not race it again.
	S.place(root, "Objects", "drop-gate", DROP_GATE, _at(56, 9), {"map_id": world_id("roots"),
			"gate_id": "weaver-hollow-drop-gate"})
	S.place(root, "Objects", "gate-winch", GATE_WINCH, _at(52.5, 3.8), {"gate_id": "weaver-hollow-drop-gate",
			"map_id": world_id("roots")})
	# D1 the Old Cellar: dark; the dry roots close the corner where the war journal page lies.
	S.place(root, "Objects", "old-cellar-roots", DEADTHORN, _at(29.5, 21.4))
	# Its prize is a page of the Thorn Guard's war journal, not an item yet: coins until then.
	_chest(root, "old-cellar-chest", 29.5, 25.5, {"coins": 40})
	_kit(root, "old-cellar-glint", "prize-glint", 29.5, 24.7, {"only_in_dark": true})
	_dark_room(root, "D1-old-cellar", 1, 1, [], "")
	_dungeon(root, 3, 4.5)
	_dress_roots(root)
	S.own(root, root)
	return root


## The Boughs (the upper floor): D2 the Dark Bough (0,0), the Hoard (1,0: the Pearl room), B5 the
## Warden's Den (2,0), B6 the Pillar (3,0), B1 the Bough Stair (0,1), B2 the Drawbridge (1,1)-(2,1),
## B4 the Nursery (3,1), B3 the Mimic's Pantry (2,2). B4 and B6 are an optional bomb wing.
static func _boughs() -> Node2D:
	var canvas := HollowCanvas.new(world_id("boughs"), 4, 3)
	var moss := C.FOREST_MOSS
	var leaves := C.AMBERLEAF
	canvas.carve_room(0, 0, 1, 1, moss)
	# The Hoard: a small vault, the Pearl room. Its stair down to the gallery is a well between two
	# blocks of rock at its south end, choked with old silk (a web wall across its mouth).
	canvas.fill(Rect2i(24, 3, 7, 10), 0, C.TOWN_COBBLE)
	canvas.rock(Rect2i(24, 11, 3, 2))
	canvas.rock(Rect2i(29, 11, 2, 2))
	canvas.carve_room(2, 0, 1, 1, C.TOWN_COBBLE)
	# B6 the Pillar: a small near rim in the south-west, the void (level -2, dark) across the room and
	# down its east side, the far shore along the north (the big chest, the raised bridge's post), and
	# the broken parapet (level 0, cut off by the void) where the blast kegs stand in a line east to the
	# post of the second bridge... the post at its end is out of a throw's reach from the rim.
	canvas.carve_room(3, 0, 1, 1, moss)
	canvas.fill(Rect2i(49, 5, 14, 4), -2, C.CAVERN_FLOOR)
	canvas.fill(Rect2i(54, 9, 9, 4), -2, C.CAVERN_FLOOR)
	canvas.fill(Rect2i(54, 7, 6, 1), 0, moss)
	canvas.carve_room(0, 1, 1, 1, leaves)
	# B2 the Drawbridge: the old tower's flagstones; the void (level -2) runs north-south across its
	# middle.
	canvas.carve_room(1, 1, 2, 1, C.TOWN_COBBLE)
	canvas.paint_ground(Rect2i(17, 23, 6, 4), moss)
	canvas.paint_ground(Rect2i(40, 17, 7, 3), moss)
	canvas.paint_ground(Rect2i(26, 17, 4, 2), leaves)
	canvas.fill(Rect2i(30, 15, 4, 12), -2, C.CAVERN_FLOOR)
	canvas.carve_room(3, 1, 1, 1, leaves)
	canvas.paint_ground(Rect2i(33, 9, 4, 4), C.AMBERLEAF)
	canvas.paint_ground(Rect2i(43, 3, 4, 3), C.FOREST_MOSS)
	canvas.paint_ground(Rect2i(24, 3, 2, 4), C.FOREST_MOSS)
	# B3 the Mimic's Pantry, with its west alcove behind a web wall.
	canvas.carve_room(2, 2, 1, 1, leaves)
	canvas.rock(Rect2i(36, 29, 1, 12))
	canvas.fill(Rect2i(36, 33, 1, 4), 0, leaves)
	# Doors: the stair from the Trunk (B1 west), B1-D2, B1-B2, B2-B5 (the double door), B2-B4,
	# B2-B3, B4-B6, B5-Hoard.
	canvas.fill(Rect2i(0, 19, 1, 4), 0, leaves)
	canvas.door_north_south(7, 13, moss)
	canvas.door_east_west(15, 21, moss)
	canvas.door_north_south(39, 13, C.TOWN_COBBLE)
	canvas.door_east_west(47, 21, leaves)
	canvas.door_north_south(39, 27, leaves)
	canvas.door_north_south(50, 13, moss)
	canvas.door_east_west(31, 7, C.TOWN_COBBLE)
	# Floor webs: B1's patches, B4's rings round the egg sacs, a few on B6's slabs (painted by the kit's
	# slabs later), the Mimic's Pantry.
	canvas.paint_webs(Rect2i(3, 19, 3, 2))
	canvas.paint_webs(Rect2i(10, 23, 3, 2))
	for corner: Vector2i in [Vector2i(50, 17), Vector2i(58, 17), Vector2i(58, 22)]:
		canvas.paint_webs(Rect2i(corner.x, corner.y, 4, 4))
		canvas.clear_webs(Rect2i(corner.x + 1, corner.y + 1, 2, 2))
	canvas.paint_webs(Rect2i(40, 37, 4, 2))
	var root := S.build(canvas, _at(2, 22))
	S.camera_room(root, "D2-dark-bough", 0, 0)
	S.camera_room(root, "Hoard", 1, 0)
	S.camera_room(root, "B5-wardens-den", 2, 0)
	_room_entry(S.camera_room(root, "B6-the-pillar", 3, 0), 51, 11)
	S.camera_room(root, "B1-bough-stair", 0, 1)
	_room_entry(S.camera_room(root, "B2-drawbridge", 1, 1, 2, 1), 24, 22)
	S.camera_room(root, "B4-nursery", 3, 1)
	S.camera_room(root, "B3-mimics-pantry", 2, 2)
	S.door(root, "from-trunk", _at(0.35, 22), {"door_id": "boughs-from-trunk", "target_area_id": world_id("trunk"),
			"target_door_id": "trunk-east-stair", "side": "west", "kind": "opening", "trigger_rect": TRIGGER_EW})
	S.door(root, "hoard-stair", _at(28, 12.7), {"door_id": "boughs-hoard-stair", "target_area_id": world_id("trunk"),
			"target_door_id": "trunk-gallery-stair", "side": "south", "kind": "opening", "trigger_rect": TRIGGER_NS})
	# B1: a Silk Lurker over the landing; D2's dark doorway in the north wall.
	S.enemy(root, "stair-silk-lurker", "silk-lurker", _at(8, 21), 64.0)
	_pot(root, "stair-pot-1", 2, 25.5)
	_pot(root, "stair-pot-2", 13.5, 25.5)
	# B2: the void across the room's middle; its drawbridge stands raised on the far (east) rim and
	# drops west across the gap (rows 21-22) when a bomb thrown over the void breaks the cracked winch
	# post beside it. The Warden's door (small key 2: one keyhole since the Pearl moved inside, small
	# key 3 lies in the Crown's C4) in the north wall east of the void.
	_void(root, "b2-void", Rect2i(30, 15, 4, 12))
	_kit(root, "b2-drawbridge", "drawbridge", 34, 22, {"toward": "west", "length": 4, "width": 128.0,
			"bridge_id": "b2-drawbridge"})
	S.place(root, "Objects", "winch-post", WINCH_POST, _at(34.6, 20.4), {"flag_id": "weaver-hollow.winch-post",
			"target_path": NodePath("../b2-drawbridge")})
	_kit(root, "den-door", "key-door", 40, 17, {"door_id": "boughs-den-door", "wall": "north", "keyholes": 1})
	# B3: the Cocoon Mimic swallowed small key 2: beaten, it spits it out (the kit's floor key). The
	# parcels behind the alcove's web wall.
	S.enemy(root, "pantry-cocoon-mimic", "cocoon-mimic", _at(42, 33), 120.0, {"swallowed_flag": "weaver-hollow.b3-mimic-key",
			"swallowed_scene_id": "object.dungeon-key", "swallowed_settings": {"item": "small-key", "pickup_id": "b3-mimic-key"}})
	S.place(root, "Objects", "s2-web-wall", WEB_WALL, _at(36.5, 36), {"orientation": "side", "span": 128.0,
			"hides_secret": true, "flag_id": "weaver-hollow.s2-web-wall"})
	var pantry: Array = [[{"hp-potion": 1}, 0], [{"energy-potion": 1}, 0], [{}, 40]]
	for i in 3:
		S.place(root, "Objects", "s2-parcel-%d" % i, SILK_PARCEL, _at(34.5, 33.6 + i * 2.2), {"coins": pantry[i][1],
				"contents": pantry[i][0], "flag_id": "weaver-hollow.s2-parcel-%d" % i})
	# B4 the Nursery (the optional wing with B6): an ambush (shutters once), three egg sacs on islands
	# ringed by webs, an orb-weaver.
	for i in 3:
		var corner: Vector2i = [Vector2i(50, 17), Vector2i(58, 17), Vector2i(58, 22)][i]
		S.enemy(root, "nursery-egg-sac-%d" % i, "egg-sac", _at(corner.x + 2, corner.y + 2.6), 420.0)
	S.enemy(root, "nursery-orb-weaver", "orb-weaver", _at(53, 24), 220.0)
	# Shutters close both its doorways once the slime is in; every enemy of the room beaten (the
	# sacs and the orb-weaver), they open and a chest rises with coins and a potion. Won once, for good.
	_kit(root, "nursery-shutter-west", "shutter", 49, 22, {"wall": "west", "fight_id": "b4-nursery"})
	_kit(root, "nursery-shutter-north", "shutter", 51, 17, {"wall": "north", "fight_id": "b4-nursery"})
	_chest(root, "nursery-chest", 56, 22.2, {"coins": 30, "hp-potion": 1}, false, true)
	_kit(root, "nursery-fight", "room-fight", 48, 14, {"size": Vector2(16, 14) * float(S.CELL), "fight_id": "b4-nursery",
			"once": true, "reward": NodePath("../nursery-chest")})
	# B5 the Warden's Den: the mini-boss, the first half's last test (a room fight with a boss: its
	# shutter closes the key door's doorway behind the slime); one egg sac by the back wall. The
	# Hoard's doorway is shut from the start and opens when the Warden falls: the big chest with the
	# big key and, on the brood's altar beside it, Pearl 2, risen with the Warden's fall.
	S.enemy(root, "den-brood-warden", "brood-warden", _at(40, 8), 300.0)
	S.enemy(root, "den-egg-sac", "egg-sac", _at(44.5, 4.5), 360.0)
	_kit(root, "den-shutter", "shutter", 40, 13, {"wall": "south", "fight_id": "b5-warden"})
	_kit(root, "hoard-shutter", "shutter", 33, 8, {"wall": "west", "starts_shut": true, "shutter_id": "boughs-hoard-shutter"})
	var warden: Array[NodePath] = [NodePath("../../Enemies/den-brood-warden")]
	_kit(root, "den-fight", "room-fight", 32, 0, {"size": Vector2(16, 14) * float(S.CELL), "fight_id": "b5-warden",
			"boss_id": WARDEN_BOSS_ID, "enemies": warden, "reward": NodePath("../hoard-shutter")})
	_hoard(root)
	for i in 4:
		_dungeon_pot(root, "den-pot-%d" % i, [34.0, 45.5, 34.0, 45.5][i], [4.5, 9.0, 11.5, 11.5][i], "random")
	# B6 the Pillar: a bomb thrown onto the first keg sets off the line along the parapet; the last
	# breaks the cracked winch post on the pillar's top (out of a throw's reach), and the pillar's
	# bridge drops to the rim: the big chest.
	for i in 4:
		S.place(root, "Objects", "keg-%d" % i, BLAST_KEG, _at(54.5 + i * 1.25, 7.6))
	# The second bridge stands raised on the far shore and drops south across the void (cols 51-52)
	# to the rim; the far shore's prize is a Goo Heart (the heart quarter's stand-in until the heart
	# quarters are built, roadmap 5.3).
	_void(root, "b6-void", Rect2i(49, 5, 14, 4))
	_void(root, "b6-void-east", Rect2i(54, 9, 9, 4))
	_kit(root, "b6-drawbridge", "drawbridge", 52, 5, {"toward": "south", "length": 4, "width": 128.0,
			"bridge_id": "b6-drawbridge"})
	S.place(root, "Objects", "pillar-post", WINCH_POST, _at(59.6, 7.6), {"flag_id": "weaver-hollow.pillar-post",
			"target_path": NodePath("../b6-drawbridge")})
	S.place(root, "Objects", "pillar-heart", GOO_HEART, _at(51.5, 3.2), {"GooHeartScript:heart_id": "weaver-hollow-pillar-heart"})
	# D2 the Dark Bough: dark; three candles that, all lit, light it for good and bring the chest.
	var candles: Array[NodePath] = []
	for i in 3:
		var candle := Node2D.new()
		candle.name = "dark-bough-candle-%d" % i
		candle.position = _at(4.5 + i * 3.5, 6.5)
		candle.y_sort_enabled = true
		candle.set_script(load(CANDLE_SCRIPT))
		candle.set(&"unlit_scene", load(CANDLE_UNLIT))
		candle.set(&"lit_scene", load(CANDLE_LIT))
		candle.set(&"flame_offset", Vector2(0, -60))
		root.get_node("Objects").add_child(candle)
		candles.append(NodePath("../../Objects/" + candle.name))
	var dark := _dark_room(root, "D2-dark-bough", 0, 0, candles, "weaver-hollow.dark-bough-lit")
	# Its prize is the Silkspun Stew campfire recipe, not an item yet: a potion and coins until then.
	_variant_chest(root, "dark-bough-chest", 8, 10, {"hp-potion": 1, "coins": 20}, "weaver-hollow.dark-bough-lit")
	_dungeon(root, 2, 23.5)
	_dress_boughs(root)
	S.own(root, root)
	return root


## The Hoard, the Pearl room (the plan's "The Pearl room: the Hoard"): the big chest with the big key
## and, on the brood's altar beside it, Pearl 2 (`object.pearl-two`, its guard the Warden's fight:
## it rises when she falls; taking it grants the Silk skin and seals the dungeon). Its glow
## twinkles over the altar and at the shutter's gap in the den, seen through the fight, until the
## Pearl is taken. The stair down to the gallery is choked with old silk: a web wall across the
## well's mouth, the Silk skin's first lock (passed at half speed, or cut for good with the Spear).
static func _hoard(root: Node2D) -> void:
	_chest(root, "hoard-big-chest", 28.6, 6.6, {"dungeon-big-key": 1}, true)
	S.place(root, "Scenery", "hoard-altar", PEARL_ALTAR, _at(25.4, 7.0))
	# Taken from any side of the altar (its base is solid): a wide reach.
	S.place(root, "Objects", "pearl-two", PEARL_TWO, _at(25.4, 5.5), {"boss_id": WARDEN_BOSS_ID, "take_radius": 90.0})
	_pearl_glow(root, [Vector2(25.4, 4.6), Vector2(33.4, 6.9)])
	S.place(root, "Objects", "hoard-stair-web", WEB_WALL, _at(28, 11.2), {"orientation": "across", "span": 128.0,
			"height": 120.0, "flag_id": "weaver-hollow.hoard-stair-web"})


## Pearl 2's glow: a pale violet glint at each point (cells), drawn over the dark (prize_glint.gd),
## gone once the Pearl is taken (a StoryVariant on its flag keeps them only while it is unset).
static func _pearl_glow(root: Node2D, points: Array) -> void:
	var holder := Node2D.new()
	holder.name = "pearl-glow-variant"
	holder.y_sort_enabled = true
	root.get_node("Objects").add_child(holder)
	var glow := Node2D.new()
	glow.name = "pearl-glow"
	glow.y_sort_enabled = true
	holder.add_child(glow)
	for i in points.size():
		var point: Vector2 = points[i]
		var glint := (load(KIT % "prize-glint") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		glint.name = "pearl-glint-%d" % i
		glint.position = _at(point.x, point.y)
		glint.set(&"tint", PEARL_GLINT)
		glint.set(&"lit_strength", 0.9)
		glint.set(&"phase", 0.6 * i)
		glow.add_child(glint)
	var variant := Node.new()
	variant.name = "StoryVariantScript"
	variant.set_script(load(STORY_VARIANT))
	variant.set(&"flag_id", PEARL_FLAG)
	holder.add_child(variant)
	variant.set(&"when_unset", glow)


## The Crown (the top): C2 the Crown (0,0), C3 the Outer Bough (1,0), C1 the Crown Stair (0,1), C4
## the Spinning Loft (1,1).
static func _crown() -> Node2D:
	var canvas := HollowCanvas.new(world_id("crown"), 2, 2)
	var moss := C.FOREST_MOSS
	var leaves := C.AMBERLEAF
	canvas.carve_room(0, 0, 1, 1, leaves)
	canvas.paint_ground(Rect2i(1, 1, 3, 12), moss)
	canvas.paint_ground(Rect2i(12, 9, 3, 4), moss)
	canvas.carve_room(1, 0, 1, 1, leaves)
	# C1 the Crown Stair (the Silk skin's test): a band of rock across the stair (row 21, its face
	# over rows 22-23) whose one gap, on the stair's straight way up, is choked by a web wall; the
	# floor webbed from wall to wall below the calm top, where the K3 door leads up into the Crown.
	canvas.carve_room(0, 1, 1, 1, leaves)
	canvas.paint_ground(Rect2i(1, 22, 5, 5), moss)
	canvas.rock(Rect2i(1, 21, 14, 1))
	canvas.fill(Rect2i(7, 21, 2, 1), 0, leaves)
	# C4 the Spinning Loft (the Silk skin's twist): the old watch's store loft, its boards, where the
	# brood spins; two rows of web walls across it (C4_ROWS), the Slime Spiders between them.
	canvas.carve_room(1, 1, 1, 1, C.WOOD_FLOOR)
	# Doors: the stair from the Trunk (C1 south), C1-C2 (the K3 door, the boss shutter), C2-C3 (the
	# seal, the web wall), C1-C4 (C1's south part, C4's south corridor).
	canvas.fill(Rect2i(7, 27, 2, 1), 0, moss)
	canvas.door_north_south(7, 13, moss)
	canvas.door_east_west(15, 7, leaves)
	canvas.door_east_west(15, 25, leaves)
	canvas.paint_style(Rect2i(0, 0, 32, 28), "mossy-rock")
	# Floor webs: C1 from wall to wall below its top (the gap and the doorway to C4 too, never under
	# the band's face, rows 22-23, which they would draw over); C4's middle corridor, the west of its
	# north corridor and the east of its south corridor.
	canvas.paint_webs(Rect2i(1, 19, 14, 2))
	canvas.paint_webs(Rect2i(7, 21, 2, 3))
	canvas.paint_webs(Rect2i(1, 24, 16, 3))
	canvas.paint_webs(Rect2i(17, 21, 14, 3))
	canvas.paint_webs(Rect2i(17, 17, 5, 3))
	canvas.paint_webs(Rect2i(25, 24, 6, 3))
	var root := S.build(canvas, _at(8, 25))
	S.camera_room(root, "C2-the-crown", 0, 0)
	S.camera_room(root, "C3-outer-bough", 1, 0)
	S.camera_room(root, "C1-crown-stair", 0, 1)
	S.camera_room(root, "C4-spinning-loft", 1, 1)
	S.door(root, "from-trunk", _at(8, 27.65), {"door_id": "crown-from-trunk", "target_area_id": world_id("trunk"),
			"target_door_id": "trunk-crown-door", "side": "south", "kind": "opening", "trigger_rect": TRIGGER_NS})
	S.door(root, "bough-drop", _at(29.5, 8), {"door_id": "crown-bough-drop", "target_area_id": "gloop-forest-f4",
			"target_door_id": "weaver-hollow-silk-drop", "side": "none", "kind": "fall",
			"trigger_rect": Rect2(-48.0, -96.0, 96.0, 192.0)})
	# C1: the web wall across the stair's straight way (pass it at half speed, or cut it for good and
	# every climb after a faint is quick), the K3 door at the top and its pots, the calm spot.
	S.place(root, "Objects", "stair-web-wall", WEB_WALL, _at(8, 23.6), {"orientation": "across", "span": 128.0,
			"height": 128.0, "flag_id": "weaver-hollow.crown-stair-web"})
	_kit(root, "crown-key-door", "key-door", 8, 17, {"door_id": "crown-k3-door", "wall": "north", "keyholes": 1})
	for i in 4:
		_dungeon_pot(root, "stair-pot-%d" % i, [2.4, 4.2, 11.8, 13.6][i], 18.4, ["heart", "energy"][i % 2])
	_loft(root)
	# The Matron's camp (encounter.weaver-hollow-matron): her cocoon fight (the Silk skin's exam), then
	# her full heart and her thread in the web (Pearl 2 lies in the Hoard now). The boss shutter in C2's
	# south doorway rises when she engages and sinks when she falls (her camp's signals).
	var camp := S.place(root, "Objects", "matron-camp", MATRON_CAMP, _at(8, 8.5))
	var shutter := _kit(root, "crown-shutter", "shutter", 8, 13, {"wall": "south", "shutter_id": "crown-boss-shutter"})
	S.editable(root, camp)
	var camp_script := camp.get_node("BossCampScript")
	camp_script.connect(&"boss_engaged", Callable(shutter, &"shut"), CONNECT_PERSIST)
	camp_script.connect(&"boss_defeated", Callable(shutter, &"open"), CONNECT_PERSIST)
	_dungeon(root, 8, 25.5)
	# C2's east doorway, the way out to C3's drop: the seal stands in it from the Pearl's take until she
	# falls (with the Silk skin in hand her web wall alone would let the slime out); beyond it, in
	# C3, her web wall (pass or cut).
	_kit(root, "crown-east-seal", "dungeon-seal", 15, 8, {"wall": "east"})
	S.place(root, "Objects", "exit-web-wall", WEB_WALL, _at(16.7, 8), {"orientation": "side", "span": 128.0,
			"flag_id": "weaver-hollow.crown-web-wall"})
	_dress_crown(root)
	S.own(root, root)
	return root


## C4 the Spinning Loft (the plan's twist: "silk under fire"): two rows of web walls across the loft,
## wall to wall (C4_ROWS), part it into three corridors; the slime comes in at the south corridor's
## west end and crosses them north. A Slime Spider in each corridor ahead lines up and shoots while
## the slime wades a row at half speed (its body above the silk), so it wades under fire or stops
## and cuts a lane with the Spear (then Rolls through). Small key 3 lies wrapped in a silk parcel at
## the north corridor's east end; the Spear frees it.
static func _loft(root: Node2D) -> void:
	for row in C4_ROWS.size():
		for i in 7:
			S.place(root, "Objects", "loft-web-%d-%d" % [row, i], WEB_WALL, _at(18 + i * 2, C4_ROWS[row]), {
				"orientation": "across", "span": 128.0, "height": 104.0,
				"flag_id": "weaver-hollow.loft-web-%d-%d" % [row, i]})
	S.enemy(root, "loft-slime-spider-1", "slime-spider", _at(27, 22.4), 120.0)
	S.enemy(root, "loft-slime-spider-2", "slime-spider", _at(21, 18.6), 120.0)
	S.place(root, "Objects", "loft-key-parcel", SILK_PARCEL, _at(29.4, 18.9), {"coins": 0,
			"contents": {"dungeon-small-key": 1}, "flag_id": "weaver-hollow.loft-key-parcel"})


## The hub's hatch (game/scripts/latched_hatch.gd): the ladder down to the Roots' R3, latched from
## below until the slime climbs up through it.
static func _hatch(root: Node2D) -> void:
	var hatch := Node2D.new()
	hatch.name = "hatch"
	hatch.y_sort_enabled = true
	hatch.position = _at(20.5, 12.5)
	hatch.set_script(load(LATCHED_HATCH))
	hatch.set(&"flag_id", "weaver-hollow.hatch-open")
	root.get_node("Doors").add_child(hatch)
	var looks := []
	for look_name in ["closed", "open"]:
		var look := (load(_prop_path("interior-structure-hatch-" + look_name)) as PackedScene).instantiate(
				PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		look.name = look_name
		hatch.add_child(look)
		looks.append(look)
	var script_node := Node.new()
	script_node.name = "DoorScript"
	script_node.set_script(load(S.DOOR))
	script_node.set(&"map_id", str(root.name))
	script_node.set(&"door_id", "trunk-hatch")
	script_node.set(&"target_area_id", world_id("roots"))
	script_node.set(&"target_door_id", "roots-ladder")
	# A south door (push down onto it): the cave ladder below is a north one (door.gd pairing).
	script_node.set(&"side", "south")
	script_node.set(&"kind", "ladder_down")
	script_node.set(&"trigger_rect", Rect2(-40.0, -30.0, 80.0, 60.0))
	hatch.add_child(script_node)
	hatch.set(&"door", script_node)
	hatch.set(&"closed_look", looks[0])
	hatch.set(&"open_look", looks[1])


## A dark room over the camera room at room cell (x, y): its candles light it, for good when it has a
## flag.
static func _dark_room(root: Node2D, room_name: String, x: int, y: int, candles: Array[NodePath], lit_flag: String) -> Node2D:
	var rect := HollowCanvas.room_world_rect(x, y, 1, 1, S.CELL)
	var dark := Node2D.new()
	dark.name = room_name
	dark.position = rect.position
	dark.set_script(load(DARK_ROOM))
	dark.set(&"size", rect.size)
	if not candles.is_empty():
		dark.set(&"candles", candles)
		dark.set(&"lit_for_good_when_all_lit", true)
		dark.set(&"lit_flag", lit_flag)
	root.get_node("DarkRooms").add_child(dark)
	return dark


## A chest that appears once `flag` is set (a StoryVariant with the chest as its `when_set`).
static func _variant_chest(root: Node2D, node_name: String, x: float, y: float, contents: Dictionary, flag: String) -> void:
	var holder := Node2D.new()
	holder.name = node_name + "-variant"
	holder.y_sort_enabled = true
	root.get_node("Objects").add_child(holder)
	var chest := _chest(root, node_name, x, y, contents)
	chest.reparent(holder)
	var variant := Node.new()
	variant.name = "StoryVariantScript"
	variant.set_script(load(STORY_VARIANT))
	variant.set(&"flag_id", flag)
	holder.add_child(variant)
	variant.set(&"when_set", chest)


const STREW_ROOTS := ["interior-mushroom-floor-root-1", "interior-mushroom-floor-root-2", "interior-mushroom-floor-root-4",
		"interior-mushroom-floor-root-6", "interior-mushroom-floor-root-8", "interior-mushroom-structure-root-hump",
		"interior-mushroom-floor-moss-1", "interior-mushroom-floor-moss-3", "interior-mushroom-floor-pebbles-mossy",
		"interior-mushroom-floor-rock-mossy-small", "interior-mushroom-floor-mushrooms-brown",
		"interior-mushroom-decor-glow-mushroom-small"]
const STREW_LEAVES := ["interior-mushroom-floor-leaves-fallen", "interior-mushroom-floor-twigs",
		"interior-mushroom-floor-leaf-big", "interior-mushroom-floor-root-3", "interior-mushroom-floor-root-5",
		"interior-mushroom-floor-moss-2", "interior-mushroom-floor-pebbles-1", "interior-mushroom-floor-mushrooms-cream"]
const STREW_STONE := ["interior-mushroom-floor-pebbles-2", "interior-mushroom-floor-pebbles-3",
		"interior-mushroom-floor-moss-4", "interior-mushroom-floor-root-7", "interior-mushroom-floor-rock-half-buried",
		"interior-mushroom-decor-glow-mushroom-cluster"]


static func _dress_trunk(root: Node2D) -> void:
	_strew(root, Rect2i(17, 29, 14, 12), STREW_LEAVES, 3, [Rect2(22, 28, 4, 4), Rect2(22, 38, 4, 4), Rect2(29, 33, 3, 5)])
	_strew(root, Rect2i(1, 15, 14, 12), STREW_LEAVES, 3, [Rect2(13, 19, 3, 5), Rect2(1, 15, 10, 4)])
	_strew(root, Rect2i(17, 7, 30, 20), STREW_STONE, 4, [Rect2(16, 19, 3, 5), Rect2(21, 24, 5, 4), Rect2(44, 19, 4, 5),
			Rect2(42, 6, 6, 3), Rect2(18, 10, 5, 5)])
	_strew(root, Rect2i(5, 1, 10, 12), STREW_STONE, 4, [Rect2(6, 10, 4, 4), Rect2(7, 8, 4, 3), Rect2(10, 4, 4, 5)])
	_props(root, [
		# T4 Well Room: the old well, flagstones, a glow in the map nook.
		["decoration-world-solid--village-well", 11.5, 6.5], ["interior-structure-floor-stone-large", 7, 5.5],
		["interior-structure-floor-stone-mossy", 13, 11.5], [PEBBLES + "1", 6, 11.5], [GLOW + "small", 1.6, 9.6],
		# T3 Larder: the brood's store of leaves, seeds and twigs.
		["interior-mushroom-floor-leaves-fallen", 3, 24.5], ["interior-mushroom-floor-leaves-fallen", 12, 20],
		["interior-mushroom-floor-seeds", 5.5, 25.5], ["interior-mushroom-floor-twigs", 10, 25.5],
		["interior-mushroom-decor-acorn-pile", 13.2, 18.2], [HANGING_ROOTS, 11.6, 17],
		[ROOT + "3", 1.6, 21],
		# T2 the Hollow Heart: the hall's pillars, banners on the gallery's wall, the closed hatch.
		[PILLAR, 25, 14], [PILLAR, 39, 14], [PILLAR, 25, 21.5], [PILLAR, 39, 21.5],
		["interior-decor-banner-red-narrow", 22.5, 4], ["interior-decor-banner-red-narrow", 41.5, 4],
		["interior-structure-floor-stone-large", 32, 16], ["interior-structure-floor-stone-large-b", 32, 23.5],
[GLOW + "cluster", 17.8, 25.6], [GLOW + "tall", 46.2, 10.2],
		[HANGING_ROOTS, 28, 7], [HANGING_ROOTS, 37, 7, true], [MOSS + "2", 45.5, 25.5], [ROOT + "5", 17.6, 16],
		# T1 Root Door: hanging roots, roots on the floor, moss and a glow.
		[HANGING_ROOTS, 19.5, 31], [HANGING_ROOTS, 28.5, 31, true], [ROOT + "1", 18, 38.5], [ROOT + "6", 29.4, 32.5],
		[MOSS + "1", 26, 39.6], [GLOW + "cluster", 18.2, 32.4], [PEBBLES + "2", 21, 40],
		# S3's nook.
		[MOSS + "3", 34.5, 38.2],
	])


static func _dress_roots(root: Node2D) -> void:
	_strew(root, Rect2i(1, 1, 14, 12), STREW_ROOTS, 3, [Rect2(12, 5, 4, 5), Rect2(6, 5, 4, 3), Rect2(1, 1, 8, 6)])
	_strew(root, Rect2i(17, 1, 30, 12), STREW_STONE, 4, [Rect2(16, 5, 3, 5), Rect2(42, 3, 6, 10), Rect2(22, 10, 4, 4),
			Rect2(34, 1, 9, 12)])
	_strew(root, Rect2i(17, 15, 14, 12), STREW_ROOTS, 3, [Rect2(22, 14, 4, 4), Rect2(26, 20, 5, 7)])
	_props(root, [
		# R1 Root Fall: roots everywhere, the ledge's moss.
		[ROOT + "2", 10, 11.5], [ROOT + "4", 13.5, 7], [ROOT + "7", 2, 11], ["interior-mushroom-structure-root-hump", 12.6, 10],
		[HANGING_ROOTS, 12, 3], [GLOW + "small", 13.6, 4.2], [MOSS + "4", 3, 2.6], [GLOW + "cluster", 1.6, 7.6],
		# R2 the Bone Cellar: stone pillars to hide behind (the Watcher Eye's beam and the throwers' bones
		# stop at them), the cover pillar in front of the crack, the fort's banners.
		[PILLAR, 20.5, 6], [PILLAR, 20.5, 10.6], [PILLAR, 25.5, 6], [PILLAR, 25.5, 10.6], [PILLAR, 30.5, 10.6],
		[PILLAR, 31.5, 5.4], [PILLAR, 38.5, 10.9],
		["interior-decor-banner-red-narrow", 23, 3], ["interior-decor-banner-red-narrow", 29, 3],
		["interior-structure-floor-stone-mossy", 34, 11.5], [PEBBLES + "3", 18, 11.6],
		# R3 the Drop Gate: flagstones by the gate.
		[PEBBLES + "1", 61.4, 3.6], [GLOW + "small", 49.6, 3.6],
		# D1 the Old Cellar: roots in the dark.
		[ROOT + "1", 19, 18.5], [ROOT + "5", 23, 22], [ROOT + "8", 20, 25], ["interior-mushroom-structure-root-hump", 25, 18.4],
	])


static func _dress_boughs(root: Node2D) -> void:
	_strew(root, Rect2i(1, 15, 14, 12), STREW_LEAVES, 3, [Rect2(0, 19, 3, 5), Rect2(6, 14, 4, 4), Rect2(12, 19, 4, 5)])
	_strew(root, Rect2i(17, 15, 30, 12), STREW_STONE, 4, [Rect2(16, 19, 3, 5), Rect2(29, 14, 6, 13), Rect2(38, 14, 4, 4),
			Rect2(44, 19, 4, 5), Rect2(38, 24, 4, 4)])
	_strew(root, Rect2i(49, 15, 14, 12), STREW_LEAVES, 4, [Rect2(48, 19, 3, 5), Rect2(49, 14, 4, 4)])
	_props(root, [
		# B1 the Bough Stair.
		[HANGING_ROOTS, 11.5, 17], [ROOT + "2", 2, 25.5], [MOSS + "1", 12.5, 24], [GLOW + "small", 1.6, 17.6],
		# B2 the Drawbridge: moss and roots along the void.
		[MOSS + "2", 21, 18], [MOSS + "3", 41, 25], [ROOT + "4", 28.6, 25], [ROOT + "6", 35.4, 18.2, true],
		[GLOW + "cluster", 17.8, 25.4], [GLOW + "tall", 46, 17.6],
		# B3 the Mimic's Pantry: the brood's store.
		["interior-mushroom-decor-acorn-pile", 45.5, 30.6], ["interior-mushroom-floor-seeds", 44, 39.6],
		["interior-mushroom-floor-leaves-fallen", 39, 38],
		# B4 the Nursery.
		[ROOT + "3", 62, 25], ["interior-mushroom-floor-leaves-fallen", 54, 18],
		# B5 the Warden's Den and the Hoard.
		["interior-decor-banner-red-narrow", 36.5, 3], ["interior-decor-banner-red-narrow", 43.5, 3],
		["interior-structure-stairs-stone-down", 28, 12.2], ["interior-decor-banner-blue", 27.5, 5],
		# B6 the Pillar: moss on the far shore.
		[MOSS + "4", 58, 3.4], [GLOW + "small", 61.6, 3.6],
	])


static func _dress_crown(root: Node2D) -> void:
	_strew(root, Rect2i(1, 15, 14, 12), STREW_LEAVES, 3, [Rect2(6, 24, 4, 4), Rect2(6, 14, 4, 4), Rect2(6, 17, 4, 4),
			Rect2(0, 20.4, 16, 3.6), Rect2(1, 17, 14, 2.2), Rect2(13, 24, 3, 3)])
	_strew(root, Rect2i(1, 1, 14, 12), STREW_LEAVES, 4, [Rect2(6, 10, 4, 4), Rect2(12, 5, 4, 5)])
	_strew(root, Rect2i(17, 1, 14, 12), STREW_LEAVES, 3, [Rect2(16, 5, 3, 5), Rect2(27, 5, 4, 6)])
	_props(root, [
		# C1 the Crown Stair: roots and leaves on the climb, a glow by the top.
		[ROOT + "2", 2, 25.5], [ROOT + "6", 13.5, 25.8], [GLOW + "tall", 14.2, 19.6],
		["interior-mushroom-floor-leaves-fallen", 4, 25], ["interior-mushroom-floor-leaves-fallen", 11, 19.8],
		# C2 the Crown: leaves at its edges.
		["interior-mushroom-floor-leaves-fallen", 2.5, 11.5], ["interior-mushroom-floor-leaves-fallen", 13, 4.2],
		["interior-mushroom-floor-leaf-big", 3, 4], ["interior-mushroom-floor-leaf-big", 13.5, 11],
		# C3 the Outer Bough.
		["interior-mushroom-floor-leaf-big", 20, 11], ["interior-mushroom-floor-leaves-fallen", 25, 4],
	])
	_dress_loft(root)


## C4's dressing: silk-hung rafters over its north wall, spools and skeins of the brood's silk in the
## corridors' corners (game/scenes/objects/weaver-hollow/, art asset/Originals/weaver-hollow/loft/).
static func _dress_loft(root: Node2D) -> void:
	for entry: Array in LOFT_DRESSING:
		S.place(root, "Scenery", "%s-%d" % [str(entry[0]), _prop_count], LOFT_PROP % str(entry[0]), _at(entry[1], entry[2]))
		_prop_count += 1

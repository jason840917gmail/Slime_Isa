extends "res://tools/film_matron.gd"
## Films the Orb-Weaver Matron's ram fight in the rebuilt Weaver Hollow's Crown (C2,
## `world.weaver-hollow-c2-crown`, step 3 of the dungeons rework: her lab's arena at the lab's own
## coordinates, docs/godot/DUNGEONS.md "The Crown"), with tools/film_matron.gd's films and staging as
## they are: only the world differs, and the Silk skin is lent (the lab lends it as a dev power; in the
## Hollow it is Pearl 2's). Run windowed, one film at a time (or through `scripts/godot/film-matron.sh
## <name> --film=<film> --tool=film_crown`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_crown.gd -- \
##         --out=<dir> --film=<name> [--every=<n>] [--zoom=<z>] [--tail=<frames>]
## One staging differs: the Spear and the pot after a tear are made from beside her, facing her (as
## ram-catch makes them; `_spear_and_pot`). Every film of film_matron.gd runs; three say PASS or FAIL
## (`verdict` in film.json, and the last line printed):
##   round1     a Goo Bomb under her low cocoon tears it (her shell "torn"), and after the Spear and a pot
##              she climbs to hang (round 2)
##   ram-catch  a pot thrown at the second ram's target as she dives on its lane: the log flings her
##              ("flung") and she crashes open ("torn")
##   round3     her last hit: the ram knocks her high cocoon down, a bomb tears it, one Spear thrust
##              finishes her (defeated)

const SkinState := preload("res://game/player/skins/skin_state.gd")
const CROWN_MAP_ID := "weaver-hollow-c2-crown"


func _initialize() -> void:
	# the parent sets the lab's world on the game before adding it to the tree: the Crown's instead, set
	# as it enters (before its _ready reads the world)
	root.child_entered_tree.connect(_crown_world)
	super()


func _crown_world(node: Node) -> void:
	if node == _main:
		node.set(&"map_id", CROWN_MAP_ID)
		root.child_entered_tree.disconnect(_crown_world)


## Called once the world stands, before any film: the Silk skin lent (ram-catch wades a web ring).
func _hide_hints() -> void:
	SkinState.lend(&"silk")
	_notes["world"] = Services.world().map_id() if Services.world() != null else ""
	super()


func _film_round1() -> void:
	await super()
	_verdict(str(_notes.get("torn", "")) == "torn" and str(_notes.get("after_round1", "")) == "hanging",
		"a blast tears her cocoon (shell %s); after the Spear and a pot she climbs to hang (%s)" \
		% [_notes.get("torn", "-"), _notes.get("after_round1", "-")])


func _film_ram_catch() -> void:
	await super()
	_verdict(str(_notes.get("flung", "")) == "flung" and str(_notes.get("crashed", "")) == "torn",
		"the ram's log catches her dive (%s) and she crashes open (%s)" % [_notes.get("flung", "-"), _notes.get("crashed", "-")])


func _film_round3() -> void:
	await super()
	_verdict(bool(_notes.get("defeated", false)) and str(_notes.get("downed", "")) == "downed" \
		and str(_notes.get("torn", "")) == "torn",
		"round 3's end: the ram knocks her cocoon down (%s), a bomb tears it (%s), one thrust: defeated %s" \
		% [_notes.get("downed", "-"), _notes.get("torn", "-"), _notes.get("defeated", false)])


## The Spear and the pot made from beside her, facing her along `way` (as ram-catch stages them):
## round1's thrust from where the slime backed off reaches her only when she spills toward it (the
## Spear aims where the slime last moved, away from her), so it missed when her lane was not the lab's.
func _spear_and_pot(way: Vector2, spears: int = 3) -> Array:
	_place_slime(_shadow() - way * 78.0 + Vector2(0.0, 4.0), way)
	_push(&"move_left" if way.x < 0.0 else &"move_right", true)
	await _run(2)
	_push(&"move_left" if way.x < 0.0 else &"move_right", false)
	await _run(2)
	_notes["spear_staged_beside_her"] = true
	return await super(way, spears)


func _verdict(ok: bool, what: String) -> void:
	_notes["verdict"] = "PASS" if ok and str(_notes.get("world", "")) == CROWN_MAP_ID else "FAIL"
	_notes["checked"] = what
	print("film_crown: %s %s in %s: %s" % [_film, _notes["verdict"], _notes.get("world", "-"), what])

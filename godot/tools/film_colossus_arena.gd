extends "res://tools/film_colossus.gd"
## Films the Crystal Colossus's crystal fight in the rebuilt Crystal Mine's arena (M15,
## `world.crystal-mine-m15-colossus-arena`, wing 4 of the dungeons rework: his lab's world carried into
## the room at the lab's own coordinates, docs/godot/DUNGEONS.md "Wing 4"), with
## tools/film_colossus.gd's films and staging as they are: only the world differs, and the Feral skin is
## lent (the lab lends it as a dev power; in the mine it is Pearl 3's, which the room's F6 powers do not
## give). Run windowed, one film at a time (or through `scripts/godot/film-colossus.sh <name>
## --film=<film> --tool=film_colossus_arena`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_colossus_arena.gd -- \
##         --out=<dir> --film=<name> [--every=<n>] [--zoom=<z>] [--tail=<frames>]
## Every film of film_colossus.gd runs; these say PASS or FAIL (`verdict` in film.json, and the last
## line printed), and only in the Mine's arena:
##   burst   in the lit brazier's ring the lower line's cart bursts his first plate (L), and he kicks
##           the cart back home
##   clang   the same cold: the cart clangs off his first plate (none bursts), and he kicks it home
##   wall    the last phase: up the roots, his claws struck loose, he crashes across the west line, and
##           its cart bursts his breastplate
##   poses, phase1, phase2, phase3, fight   as in film_colossus.gd

const SkinState := preload("res://game/player/skins/skin_state.gd")
const ARENA_MAP_ID := "crystal-mine-m15-colossus-arena"


func _initialize() -> void:
	# the parent sets the lab's world on the game before adding it to the tree: the arena's instead, set
	# as it enters (before its _ready reads the world)
	root.child_entered_tree.connect(_arena_world)
	super()


func _arena_world(node: Node) -> void:
	if node == _main:
		node.set(&"map_id", ARENA_MAP_ID)
		root.child_entered_tree.disconnect(_arena_world)


## Called once the world stands, before any film: the Feral skin lent (the wall films climb the roots).
func _hide_hints() -> void:
	SkinState.lend(&"feral")
	_notes["world"] = Services.world().map_id() if Services.world() != null else ""
	super()


func _film_cart(hot: bool, all_lit: bool = false) -> void:
	await super(hot, all_lit)
	if all_lit:
		return
	var bursts := _events("burst")
	var clangs := _events("clang")
	var home := str(_notes.get("cart_home", "")) == "held"
	if hot:
		_verdict(bursts == ["L"] and home, "in the ring the cart bursts his first plate (%s) and he kicks it home (%s)"
			% [bursts, _notes.get("cart_home", "-")])
	else:
		_verdict(bursts.is_empty() and clangs == ["L"] and home, "cold, the cart clangs off his first plate (%s; bursts %s) and he kicks it home (%s)"
			% [clangs, bursts, _notes.get("cart_home", "-")])


func _film_wall() -> void:
	await super()
	var plates := str(_notes.get("plates_after", ""))
	var bare := plates == "-"
	_verdict(int(_notes.get("claw_hits", 0)) > 0 and bare, "up the roots, his claws struck (%d), across the west line: its cart bursts his breastplate (plates after: %s)"
		% [int(_notes.get("claw_hits", 0)), plates])


## The verdict, PASS only in the Mine's arena.
func _verdict(ok: bool, what: String) -> void:
	_notes["verdict"] = "PASS" if ok and str(_notes.get("world", "")) == ARENA_MAP_ID else "FAIL"
	_notes["checked"] = what
	print("film_colossus_arena: %s %s in %s: %s" % [_film, _notes["verdict"], _notes.get("world", "-"), what])

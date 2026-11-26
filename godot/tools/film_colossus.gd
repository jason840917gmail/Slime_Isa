extends SceneTree
## Films the Crystal Colossus's crystal fight (docs/godot/DUNGEONS.md "The Crystal Colossus (roadmap
## 12.4)", "The crystal fight", "The Colossus lab") in its lab (world.colossus-lab,
## game/dev/bosses/colossus-lab.tscn), frame by frame, the camera still. Run windowed (it renders) with
## a fixed frame time, one film at a time, from the repo (or through `scripts/godot/film-colossus.sh
## <name> --film=<film>`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_colossus.gd -- ##         --out=<dir> --film=<name> [--every=<n>] [--zoom=<z>] [--tail=<frames>]
## Films (what the tool stages is said; the rest is the game playing). poses, phase1, phase2, phase3 and
## fight say PASS or FAIL (`verdict` in film.json, and the last line printed):
##   look      the lab before the fight (the slime in the lobby), then the slime walks in: he wakes
##   poses     every animation's every frame with his plates and crystals five ways (L hot, the others
##             cold; L gone, its crystal live; L dead, R gone and live; both shoulders dead, the chest
##             gone and live; all dead), the side walk both ways: the tool sets each pose on the look (he
##             stands frozen), for checking the plates and crystals sit on him; PASS when every bare
##             crystal the art has for a frame shows
##   walks     he walks down, right, up and left after the slime (the tool moves it round him; his
##             stomps held off), with three plates, then again with his first shoulder dead and bare
##   glow      the slime lights the lower-west brazier with the Lantern (cast by the tool as its key
##             does) and baits him into its ring: his first plate glows hot; then it lets him close in:
##             his stomp leaves the brazier lit (he is not dousing: one brazier lit, nobody hurt him)
##   hop       his leap: the slime keeps far from him (put there by the tool, his stomps held): he
##             crouches, a ring marks where he lands, he leaps and lands short of it; twice
##   quake     his quake twice (made due by the tool, his stomps and leap held, the camera over the whole
##             arena): the warning (reared, trembling, the floor cracking, the roots lit), then five
##             seconds of pounding; the slime stays on the floor through the first (hurt), and climbs
##             the roots west of the middle in the second's warning (put at their foot by the tool):
##             unhurt
##   rocks     his falling rocks as ammo: every pot taken away (staged); two stomps shake rocks down
##             (noted: none by the rails); one dropped on the slime by the tool hurts it; the slime
##             sucks a rock up and throws it at the lower target as he walks the rails in the lit
##             brazier's ring (put there by the tool): the cart bursts his first plate
##   douse     every brazier lit by the tool, then `burst`'s cart bursts his hot first plate: hurt with
##             all four lit he douses, and each stomp by the slime puts out the lit brazier nearest him
##             until none burns; two lit again restart the long wait (`douseAfterMs`, most of it staged
##             as gone first) and survive a stomp; the wait staged as over, the next stomp puts one
##             out, which restarts the wait, and the stomp after leaves the other
##   burst     round 1: the lower-west brazier lit (by the tool), he walks east along the lower line in
##             its ring (put there by the tool as the pot leaves); the slime throws a pot at the lower
##             target: the cart runs west, stops against him and bursts his first plate (L, the one
##             that glows, though the cart meets his front); staggered, then furious, he kicks the cart
##             back home up its line
##   clang     the same with every brazier cold: the cart clangs off his cold first plate, he staggers
##             and kicks it back; the first clang's hint: the line over him, the nearest unlit brazier
##             flickering
##   heat      his heat cues: one brazier lit, him held outside its ring, inside it on the lower line
##             (embers, a flash, the lower target glowing), outside again (steam); then all four lit,
##             him held far from every ring: brittle all the same
##   dip       mid-fight the slime walks off the floor into the west void dip: it falls, is hurt and put
##             back where it stepped off; the fight goes on
##   pass      a pot at the lower target with him off the rails (held away by the tool): the cart comes
##             out of the east tunnel, rolls over the dips and the floor into the west tunnel and is
##             gone; the next comes out of the east tunnel, its target rearmed
##   wall      the last phase (both shoulders dead, staged): he leaps onto his wall at the west spot
##             and throws two mites (then taken away by the tool); the slime climbs the roots west of
##             him and strikes his claws three times from the face; he crashes across the west down
##             line, on his back; the slime (taken off the wall by the tool) throws a pot at the west
##             target: the cart comes down out of the north wall and bursts his breastplate; getting
##             up he kicks it back into its tunnel
##   phase1    phase 1 from the wake (nothing staged on his crystals): a Spear hit on his front clinks
##             (the phase's line, his first plate flashing); the slime lights the lower-west brazier
##             with the Lantern; he is put on the lower line in its ring as the pot leaves for the
##             lower target (as `burst`): the cart bursts plate L; staggered, he kicks it home; the
##             slime strikes the bare crystal (a pot while he staggers, then the Spear from his front,
##             its own side or his back: put there by the tool each time, his steps his own) until it
##             is destroyed: the beat, phase 2
##   phase2    phase 2 (L dead and bare, staged): the same, but he is turned to face north on the line
##             as the pot leaves (held still until the cart meets him: staged), so the cart meets him
##             on his dead shoulder's side: the spark there, plate R bursts; the slime strikes crystal R
##             until it is destroyed: the beat, and he makes for his wall (the slime put by the west
##             roots, so he takes the west spot)
##   phase3    phase 3 (both shoulders dead, staged): up his wall at the west spot; the slime climbs the
##             west roots (his mites and rocks held while it climbs: staged) and strikes his claws loose;
##             on his back across the west line, a pot at the west target: the cart bursts his
##             breastplate; the Spear on his chest twice (the tool stops there), he gets up, kicks the
##             cart home and goes back up; the claws again, the second fall, the Spear on the bare chest
##             until it goes dark: his fall for good, the small golem
##   fight     the three phases in a row, nothing staged on his crystals or plates (only where he
##             stands when each pot leaves, and his turn north in phase 2, as above)
## Every film holds his quake off (staged: the films run longer than its first wait), the phases again
## at each phase's start; the quake film lets it go.
## Writes <dir>/f<nnn>.png and <dir>/film.json: per saved frame its time (ms of the game's clock since
## the film began), his phase, plates, crystals, health, brittleness and facing, the slime's health;
## and the notes (what struck what, health before and after).

const Services := preload("res://game/shared/services.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ColossusLook := preload("res://game/bosses/colossus_look.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "colossus-lab"
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 420.0
## The longer films' watchdogs (the phase on his wall, the whole fight).
const WATCHDOG_LONG_S := {"phase3": 900.0, "fight": 1800.0}
const SPEAR := &"shape-spear"
const LANTERN := &"lantern"
## Where a thing to throw is put: behind the slime's feet, so the suck faces away and the throw turns
## round (as tools/film_mechanisms.gd does).
const AMMO_BEHIND_PX := 34.0
## Long enough that a staged hold (a stomp held off, a stagger) outlasts the shot.
const HOLD_MS := 60000.0
const PLATES: Array[String] = ["L", "C", "R"]
## His phases where a hit can land (not up his wall, in the air or asleep).
const HITTABLE: Array[String] = ["walk", "raise", "stomp", "recover", "stagger", "kick", "hop-crouch", "quake-warn",
	"quake", "stunned"]
## Where the slime stands to strike him: this far from his feet in front or behind, beside him.
const STRIKE_FRONT_PX := 74.0
const STRIKE_SIDE_PX := 118.0

var _main: Node
var _out := "user://colossus"
var _film := "look"
var _every := 2
var _zoom := 1.2
var _tail := 60
var _index := 0
var _step := 0
var _start_ms := 0.0
var _rows: Array = []
var _notes: Dictionary = {}
var _caption: Label
## A second caption line (the poses film's pose).
var _caption_extra := ""
var _boss: Node
var _arena: Node


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--film="):
			_film = arg.trim_prefix("--film=")
		elif arg.begins_with("--every="):
			_every = maxi(1, int(arg.trim_prefix("--every=")))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--tail="):
			_tail = maxi(0, int(arg.trim_prefix("--tail=")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_fresh_colossus_pictures()
	var watchdog := float(WATCHDOG_LONG_S.get(_film, WATCHDOG_S))
	create_timer(watchdog, true, false, true).timeout.connect(func() -> void:
		push_error("film_colossus: gave up after %d s" % int(watchdog))
		quit(1))
	DisplayServer.window_set_size(WINDOW)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", MAP_ID)
	_main.set(&"ability_ceremonies", false)
	# as F6 on the lab: the run gets the lab's powers (dungeon.devPowers)
	_main.set(&"direct_world_run", true)
	root.add_child(_main)
	for i in 90:
		await process_frame
	if Services.feel() != null:
		Services.feel().frame_clock_ms = 1000.0 / 60.0
	_hide_hints()
	_make_caption()
	_arena = _piece("ColossusArena")
	_start_ms = Services.now_ms()
	match _film:
		"look":
			await _film_look()
		"poses":
			await _film_poses()
		"walks":
			await _film_walks()
		"glow":
			await _film_glow()
		"hop":
			await _film_hop()
		"douse":
			await _film_douse()
		"quake":
			await _film_quake()
		"rocks":
			await _film_rocks()
		"heat":
			await _film_heat()
		"climb":
			await _film_climb()
		"last":
			await _film_last()
		"burst":
			await _film_cart(true)
		"clang":
			await _film_cart(false)
		"dip":
			await _film_dip()
		"pass":
			await _film_pass()
		"wall":
			await _film_wall()
		"phase1":
			await _film_phase1()
		"phase2":
			await _film_phase2()
		"phase3":
			await _film_phase3()
		"fight":
			await _film_fight()
		_:
			push_error("film_colossus: no film '%s'" % _film)
	_notes["slime_hp_at_end"] = _slime_health()
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"film": _film, "frames": _index, "notes": _notes, "rows": _rows}, "\t"))
	file.close()
	print("film_colossus: ", _film, " ", JSON.stringify(_notes))
	quit()


# --- the films ---------------------------------------------------------------------------------------

## The lab, then the fight's start.
func _film_look() -> void:
	_still_camera(_arena_rect().get_center() - Vector2(0.0, 40.0))
	await _settle()
	await _run(20)
	await _start_fight()
	await _run(_tail + 60)


## Every animation's every frame, five plate and crystal states, on the frozen boss; PASS when every
## bare crystal the frame's art has shows (live or dead as asked).
func _film_poses() -> void:
	if not await _start_fight():
		return
	var middle := _floor_rect().get_center()
	var body := _boss_body()
	_boss.set_physics_process(false)
	_boss.set_process(false)
	body.global_position = middle
	body.reset_physics_interpolation()
	# the slime out of the picture, still in the arena
	_place_slime(_floor_rect().end - Vector2(60.0, 60.0), Vector2.LEFT)
	_still_camera(middle - Vector2(0.0, 80.0))
	var look: Node2D = _boss.call(&"plate_look")
	var gone := ColossusLook.GONE
	var cold := ColossusLook.COLD
	var live := ColossusLook.LIVE
	var dead := ColossusLook.DEAD
	# [plates, crystals]: L hot (the one that glows); L bare and live; L dead, R bare and live; both
	# shoulders dead, the chest bare and live; all dead
	var states: Array = [
		[{"L": ColossusLook.HOT, "C": cold, "R": cold}, {"L": live, "C": live, "R": live}],
		[{"L": gone, "C": cold, "R": cold}, {"L": live, "C": live, "R": live}],
		[{"L": gone, "C": cold, "R": gone}, {"L": dead, "C": live, "R": live}],
		[{"L": gone, "C": gone, "R": gone}, {"L": dead, "C": live, "R": dead}],
		[{"L": gone, "C": gone, "R": gone}, {"L": dead, "C": dead, "R": dead}],
	]
	var shown := 0
	var missing: Array = []
	for key: String in ["walk-down", "walk-side", "walk-up", "stomp", "leap-cling", "fall"]:
		var anim := ColossusLook.entry(key)
		var frames := int(anim.get("frames", 0))
		var crystals_art: Array = anim.get("crystals", [])
		for mirrored: bool in ([false, true] if key == "walk-side" else [false]):
			for state: Array in states:
				var plates: Dictionary = state[0]
				var crystals: Dictionary = state[1]
				for index in frames:
					look.call(&"show_pose", key, index, mirrored, plates, crystals)
					_caption_extra = "%s %d%s  plates L %s C %s R %s  crystals L %s C %s R %s" % [key, index,
						" mirrored" if mirrored else "", _state_name(int(plates["L"])), _state_name(int(plates["C"])),
						_state_name(int(plates["R"])), _crystal_name(int(crystals["L"])), _crystal_name(int(crystals["C"])),
						_crystal_name(int(crystals["R"]))]
					await _tick(true)
					shown += 1
					# every crystal whose plate is gone and whose piece the frame's art has must show
					var art: Dictionary = crystals_art[index] if index < crystals_art.size() and crystals_art[index] is Dictionary else {}
					for crystal: String in PLATES:
						var piece := crystal
						if mirrored and crystal != "C":
							piece = "R" if crystal == "L" else "L"
						if int(plates[crystal]) == gone and art.has(piece) 								and (look.call(&"crystal_point", crystal) as Vector2) == Vector2.INF:
							missing.append("%s %d%s %s" % [key, index, " M" if mirrored else "", crystal])
	_notes["poses"] = shown
	_notes["crystals_missing"] = missing
	_verdict(shown > 0 and missing.is_empty(), "%d poses shown, every bare crystal drawn (missing: %s)" % [shown, missing])


## He walks after the slime four ways, three plates and then his first shoulder dead and bare.
func _film_walks() -> void:
	if not await _start_fight():
		return
	var middle := _floor_rect().get_center()
	_still_camera(middle - Vector2(0.0, 60.0))
	for plates: Array in [["L", "C", "R"], ["C", "R"]]:
		_boss.call(&"stage_crystals", plates, {} if plates.size() == 3 else {"L": 0.0})
		_put_boss(middle)
		for way: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]:
			_hold_stomps()
			_boss.call(&"_transition", "walk", Services.now_ms())
			var inside := _floor_rect().grow(-60.0)
			_place_slime((_boss_feet() + way * 300.0).clamp(inside.position, inside.end), -way)
			await _run(84)
			_notes["facing_after_%s_%s" % [_way_name(way), "".join(plates)]] = _way_name(_boss.call(&"facing"))
	await _run(_tail)


## The slime lights a brazier with the Lantern (its flame flies a short line); he walks into the
## brazier's ring and his plates glow; then he stomps by the slime and puts it out: they go cold.
func _film_glow() -> void:
	if not await _start_fight():
		return
	var brazier := _piece("lower-brazier-west")
	var at := brazier.global_position
	_still_camera(at + Vector2(80.0, -110.0))
	_hold_stomps()
	_put_boss(at + Vector2(182.0, -116.0))
	# the Lantern, from just west of the brazier, facing it
	_place_slime(at + Vector2(-64.0, 4.0), Vector2.RIGHT)
	await _run(8)
	_notes["lantern"] = await _cast_lantern(Vector2.RIGHT)
	await _run(20)
	_notes["lit_by_the_lantern"] = bool(brazier.call(&"is_lit"))
	# the bait: the slime south-west of the ring, beyond it
	_place_slime(at + Vector2(-168.0, 64.0), Vector2.RIGHT)
	var glowed := -1
	for i in 240:
		await _tick()
		if glowed < 0 and bool(_boss.call(&"is_brittle")):
			glowed = _index
	_notes["brittle_from_frame"] = glowed
	_notes["brittle_in_ring"] = bool(_boss.call(&"is_brittle"))
	# now it lets him close in: he stomps and puts the brazier out
	_boss.set(&"_stomp_ready_at", Services.now_ms())
	_place_slime(_boss_feet() + Vector2(-60.0, 90.0), Vector2.UP)
	await _wait_phase("stomp", 160)
	await _run(30)
	_notes["brazier_lit_after_stomp"] = bool(brazier.call(&"is_lit"))
	_notes["brittle_after_stomp"] = bool(_boss.call(&"is_brittle"))
	_notes["dousing"] = bool(_boss.call(&"is_dousing"))
	await _run(_tail)


## His leap: the slime keeps far from him; he crouches, a ring marks where he lands, he leaps and lands
## short of it. Twice: the slime walks away again after the first.
func _film_hop() -> void:
	if not await _start_fight():
		return
	var floor := _floor_rect()
	_listen()
	_boss.set(&"_stomp_ready_at", Services.now_ms() + HOLD_MS)
	_boss.set(&"_hop_ready_at", 0.0)
	_put_boss(floor.get_center() + Vector2(-250.0, -120.0))
	_still_camera(floor.get_center())
	var hops: Array = []
	for spot: Vector2 in [floor.get_center() + Vector2(280.0, 220.0), floor.get_center() + Vector2(-330.0, 200.0)]:
		_place_slime(spot, Vector2.LEFT)
		var hp := _slime_health()
		var far_at := Services.now_ms()
		var phase := await _wait_phase("hop-crouch", 300)
		var crouched_after := int(Services.now_ms() - far_at)
		var from := _boss_feet()
		var aim: Vector2 = _boss.get(&"_hop_to")
		await _wait_phase("hop", 60)
		await _wait_phase("stomp", 90)
		var feet := _boss_feet()
		var slime_feet := Services.world().player_body.global_position
		hops.append({"phase": phase, "crouched_after_ms": crouched_after, "from": str(from.snappedf(1.0)),
			"landed": str(feet.snappedf(1.0)), "aimed": str(aim.snappedf(1.0)), "leapt_px": int(from.distance_to(feet)),
			"slime_left_px": int(feet.distance_to(slime_feet)), "slime_hurt": hp - _slime_health()})
		_restore_slime()
		await _run(40)
	_notes["hops"] = hops
	await _run(_tail)


## His dousing: every brazier lit (by the tool), a cart bursts his hot breastplate (as `burst`); hurt
## with all four lit he starts dousing, and each stomp by him puts out the lit brazier nearest him until
## none burns. Then the long wait (`douseAfterMs`): two lit again start it over; once it is staged as
## over his next stomp puts one out, which starts it over, so the stomp after leaves the other.
func _film_douse() -> void:
	await _film_cart(true, true)
	_notes["dousing_after_burst"] = bool(_boss.call(&"is_dousing"))
	var lit: Array = []
	for i in 6:
		if _lit_braziers() == 0:
			break
		# his last stomp over (he walks again), then the next
		await _wait_phase("walk", 120)
		_boss.set(&"_stomp_ready_at", Services.now_ms())
		_boss.set(&"_hop_ready_at", Services.now_ms() + HOLD_MS)
		_place_slime(_boss_feet() + Vector2(-60.0, 120.0), Vector2.UP)
		await _wait_phase("stomp", 200)
		await _run(20)
		lit.append(_lit_braziers())
		_restore_slime()
	_notes["lit_after_each_stomp"] = lit
	_notes["dousing_when_all_out"] = bool(_boss.call(&"is_dousing"))
	# two lit again (most of the long wait staged as gone first): lighting starts the wait again, so a
	# stomp leaves them both
	var douse_ms := float(_boss.call(&"pattern", "douseAfterMs", 45000.0))
	_boss.set(&"_douse_clock_from", Services.now_ms() - douse_ms + 5000.0)
	_piece("lower-brazier-west").call(&"light")
	_piece("lower-brazier-east").call(&"light")
	await _tick()
	await _tick()
	_notes["wait_left_after_lighting_s"] = snappedf(float(_boss.call(&"douse_wait_left")) / 1000.0, 0.1)
	await _stomp_by_the_slime()
	_notes["lit_after_a_stomp"] = _lit_braziers()
	# the long wait staged as over: his next stomp puts one out, and that starts the wait again, so the
	# stomp after it leaves the other
	await _wait_phase("walk", 120)
	_boss.set(&"_douse_clock_from", Services.now_ms() - douse_ms)
	await _stomp_by_the_slime(false)
	_notes["lit_after_the_long_wait"] = _lit_braziers()
	_notes["wait_left_after_the_put_out_s"] = snappedf(float(_boss.call(&"douse_wait_left")) / 1000.0, 0.1)
	await _stomp_by_the_slime()
	_notes["lit_after_the_next_stomp"] = _lit_braziers()
	await _run(_tail)


## The slime below him (out of the stomp's ring), his stomp let go: one stomp (after his last is over:
## he walks again, unless `wait_walk` is false), the slime made whole after it. He is put back in the
## floor's middle first (staged: else each stomp draws him further south, and the slime put below
## him would end in the lobby, which starts the fight over).
func _stomp_by_the_slime(wait_walk: bool = true) -> void:
	if wait_walk:
		await _wait_phase("walk", 120)
	_put_boss(_floor_rect().get_center())
	_boss.set(&"_stomp_ready_at", Services.now_ms())
	_boss.set(&"_hop_ready_at", Services.now_ms() + HOLD_MS)
	_place_slime(_boss_feet() + Vector2(-60.0, 120.0), Vector2.UP)
	await _wait_phase("stomp", 200)
	await _run(20)
	_restore_slime()


## His quake, twice (made due by the tool): the slime stays on the floor through the first (it takes the
## shaking's harm); in the second's warning it goes to the roots west of the middle (put at their foot
## by the tool, as if it ran there) and climbs them: no harm.
func _film_quake() -> void:
	if not await _start_fight():
		return
	_listen()
	_zoom = 0.85
	_still_camera(_arena_rect().get_center() - Vector2(0.0, 130.0))
	var middle := _floor_rect().get_center()
	var rounds: Array = []
	for climb: bool in [false, true]:
		_hold_stomps()
		_put_boss(middle + Vector2(0.0, -60.0))
		_place_slime(middle + Vector2(-60.0, 260.0), Vector2.UP)
		_restore_slime()
		await _run(6)
		_boss.set(&"_quake_ready_at", 0.0)
		var hp := _slime_health()
		var warned := await _wait_phase("quake-warn", 90)
		var warn_at := Services.now_ms()
		var roots_used := false
		if climb:
			await _run(20)
			var roots := _piece("claw-roots-2")
			_place_slime(roots.global_position, Vector2.UP)
			await _run(3)
			_push(&"interact", true)
			roots_used = bool(roots.call(&"use"))
			_push(&"move_up", true)
			for i in 120:
				await _tick()
				if bool(Services.world().player.call(&"get_climb").call(&"is_holding")):
					break
			_push(&"move_up", false)
		var quaked := await _wait_phase("quake", 200)
		var quake_at := Services.now_ms()
		var climbing_at_start := bool(Services.world().player.call(&"is_climbing"))
		await _wait_phase("recover", 400)
		var ended_at := Services.now_ms()
		rounds.append({"climbed": climb, "warned": warned, "quaked": quaked, "warn_ms": int(quake_at - warn_at),
			"quake_ms": int(ended_at - quake_at), "roots_used": roots_used, "climbing_at_start": climbing_at_start,
			"hits": int(_boss.call(&"quake_hits")), "slime_hurt": hp - _slime_health()})
		if climb:
			await _let_go()
		await _run(40)
	_notes["quakes"] = rounds
	await _run(_tail)


## His falling rocks as ammo: every pot taken away (staged, noted); two stomps by the slime shake
## rocks down (none on the rails); one dropped on the slime by the tool hurts it; the slime sucks up a
## rock and throws it at the lower target while he walks the rails in the lit brazier's ring (put
## there by the tool, as `burst`): the cart bursts his plate.
func _film_rocks() -> void:
	if not await _start_fight():
		return
	_listen()
	var removed := 0
	for node: Node in get_nodes_in_group(&"liftable"):
		(node.get_parent() as Node).queue_free()
		removed += 1
	_notes["pots_removed_by_the_tool"] = removed
	_zoom = 0.85
	_still_camera(_arena_rect().get_center() + Vector2(0.0, -40.0))
	var brazier := _piece("lower-brazier-west")
	brazier.call(&"light")
	var cart := _piece("lower-cart")
	var target := _piece("lower-target")
	var spot := Vector2(brazier.global_position.x + 42.0, cart.global_position.y)
	var hold := Services.now_ms() + HOLD_MS
	_boss.set(&"_quake_ready_at", hold)
	for i in 2:
		await _stomp_by_the_slime()
		await _run(60)
	var rocks: Array = _boss.call(&"get_debris")
	var spots: Array = []
	var on_rails := false
	for rock: Node2D in rocks:
		spots.append(str(rock.global_position.snappedf(1.0)))
		on_rails = on_rails or bool(_boss.call(&"_near_rails", rock.global_position, 72.0))
	_notes["rocks_after_two_stomps"] = rocks.size()
	_notes["rock_spots"] = spots
	_notes["a_rock_by_the_rails"] = on_rails
	# one dropped on the slime
	var hp := _slime_health()
	var feet := Services.world().player_body.global_position
	_boss.call(&"_fall_at", feet, 0.0)
	await _run(60)
	_notes["hurt_by_a_rock"] = hp - _slime_health()
	_restore_slime()
	# a rock sucked up, then thrown at the lower target as he walks the rails in the ring
	rocks = _boss.call(&"get_debris")
	var nearest: Node2D = null
	for rock: Node2D in rocks:
		if nearest == null or rock.global_position.distance_to(target.global_position) < nearest.global_position.distance_to(target.global_position):
			nearest = rock
	if nearest == null:
		_notes["no_rock_to_throw"] = true
		await _run(_tail)
		return
	_hold_stomps()
	_place_slime(nearest.global_position + Vector2(0.0, 40.0), Vector2.UP)
	await _run(6)
	var mouth: RefCounted = Services.world().player.call(&"get_mouth")
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 50:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	_notes["holding_a_rock"] = bool(mouth.call(&"is_holding"))
	_place_slime(target.global_position + Vector2(-150.0, 12.0), Vector2.RIGHT)
	_put_boss(spot)
	_boss.call(&"_transition", "walk", Services.now_ms())
	await _run(8)
	_hold_stomps()
	_put_boss(spot)
	Services.world().player.call(&"face", Vector2.RIGHT)
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	await _wait_state(cart, "bump", 300)
	await _run(40)
	_notes["plates_after"] = _plates_now()
	await _run(_tail)


## His heat cues: the lower-west brazier lit (by the tool), he is held (put back every step: staged)
## outside its ring, then on the lower line inside it (his plates heat: embers, a flash, the sound; the
## lower target glows), then outside again (they cool: steam); then all four braziers lit, him held in
## the floor's middle far from every ring: brittle all the same.
func _film_heat() -> void:
	if not await _start_fight():
		return
	_hold_stomps()
	var brazier := _piece("lower-brazier-west")
	var cart := _piece("lower-cart")
	brazier.call(&"light")
	var line_y := cart.global_position.y
	var inside := Vector2(brazier.global_position.x + 42.0, line_y)
	var outside := Vector2(brazier.global_position.x + 320.0, line_y)
	_zoom = 0.85
	_still_camera(_arena_rect().get_center() + Vector2(0.0, 60.0))
	_place_slime(_piece("lower-target").global_position + Vector2(-150.0, 12.0), Vector2.LEFT)
	var stages: Array = []
	for stage: Array in [["outside", outside, 30], ["inside", inside, 90], ["outside again", outside, 60]]:
		for i in int(stage[2]):
			_put_boss(stage[1])
			await _tick()
		var glow: Variant = _boss.get(&"_target_glow")
		stages.append({"where": stage[0], "brittle": bool(_boss.call(&"is_brittle")),
			"target_glowing": glow is Sprite2D and is_instance_valid(glow) and (glow as Sprite2D).visible})
	for name: String in ["west-brazier", "east-brazier", "lower-brazier-east"]:
		_piece(name).call(&"light")
	var middle := _floor_rect().get_center()
	for i in 70:
		_put_boss(middle)
		await _tick()
	stages.append({"where": "the middle, all four lit", "brittle": bool(_boss.call(&"is_brittle")),
		"in_a_ring": bool(_boss.call(&"in_fire_ring"))})
	_notes["stages"] = stages
	await _run(_tail)


## The roots as a refuge (2026-11-24): he stands under the west roots (put there by the tool, his quake
## held) while the slime climbs them: he walks off to the middle of his floor; Roll presses on the wall
## do nothing; letting go, the slime drops onto the floor in front of the wall, unhurt.
func _film_climb() -> void:
	if not await _start_fight():
		return
	_listen()
	var roots := _piece("claw-roots-1")
	var middle := _floor_rect().get_center()
	_zoom = 0.85
	_still_camera(Vector2(middle.x - 150.0, 520.0))
	_put_boss(Vector2(roots.global_position.x + 90.0, roots.global_position.y + 90.0))
	_place_slime(roots.global_position, Vector2.UP)
	await _run(3)
	var player: Node = Services.world().player
	_push(&"interact", true)
	_notes["roots_used"] = bool(roots.call(&"use"))
	_push(&"move_up", true)
	for i in 160:
		await _tick()
		if bool(player.call(&"get_climb").call(&"is_holding")):
			break
	_push(&"move_up", false)
	_notes["holding_at_top"] = bool(player.call(&"get_climb").call(&"is_holding"))
	# the cling is a toggle: the key let up, the slime stays on the wall
	_push(&"interact", false)
	await _run(20)
	_notes["still_on_the_wall_with_the_key_up"] = bool(player.call(&"is_climbing"))
	# the chosen box ability's key strikes with the Spear on the wall
	_notes["spear_chosen"] = AbilityBox.select(player, SPEAR)
	_push(&"ability_use", true)
	await _tick()
	_push(&"ability_use", false)
	var struck := false
	for i in 20:
		await _tick()
		struck = struck or bool(player.call(&"_climb_strike_running"))
	_notes["spear_struck_on_the_wall"] = struck
	var hp := _slime_health()
	var from := _boss_feet()
	await _run(150)
	_notes["boss_walked_px"] = int(from.distance_to(_boss_feet()))
	_notes["boss_from_middle_px"] = int(_boss_feet().distance_to(middle))
	# Roll presses on the wall
	for i in 3:
		_push(&"dodge", true)
		await _tick()
		_push(&"dodge", false)
		await _run(8)
	var roll: RefCounted = player.get(&"_roll")
	_notes["rolled_on_the_wall"] = roll != null and bool(roll.call(&"is_active"))
	_notes["still_climbing"] = bool(player.call(&"is_climbing"))
	# letting go (a second press: the cling is a toggle): the slime drops in front of the wall
	await _let_go()
	await _run(70)
	var feet := Services.world().player_body.global_position
	var wall_foot := float(_arena.get(&"wall_rect").end.y) - 40.0
	_notes["slime_feet_after_drop"] = str(feet.snappedf(1.0))
	_notes["slime_in_front_of_the_wall"] = feet.y >= wall_foot
	_notes["slime_hurt_while_climbing_and_dropping"] = hp - _slime_health()
	await _run(_tail)


## His last phase (both shoulders dead, staged): on his feet he leaps straight up his wall; up there a rock
## every 5 s at the slime: on the floor (it lies there after, a rock to throw), then up the roots
## beside him (it hits it on the vines and shatters); a quake made due (by the tool): he leaps down to
## the middle, quakes, and goes back up. His mites held (staged: they knock a climber off), noted.
func _film_last() -> void:
	if not await _start_fight():
		return
	_listen()
	_boss.call(&"stage_crystals", ["C"], {"L": 0.0, "R": 0.0})
	_boss.set(&"_thrown", 99)
	_notes["mites_held_by_the_tool"] = true
	var middle := _floor_rect().get_center()
	_zoom = 0.85
	_still_camera(Vector2(middle.x - 120.0, 520.0))
	_put_boss(middle)
	_place_slime(middle + Vector2(-150.0, 120.0), Vector2.UP)
	_notes["went_up"] = await _wait_phase("cling", 200)
	_boss.set(&"_thrown", 99)
	var spot_x := _boss_feet().x
	# the slime below him on the floor: a rock comes at it and lies there after
	_place_slime(Vector2(spot_x - 170.0, 560.0), Vector2.UP)
	var hp := _slime_health()
	var rocks_before := (_boss.call(&"get_debris") as Array).size()
	for i in 200:
		await _tick()
		if float(_boss.get(&"_next_rock_at")) > Services.now_ms() + 4000.0 and (_boss.get(&"_debris_due") as Array).is_empty():
			break
	await _run(10)
	_notes["floor_rock_hurt"] = hp - _slime_health()
	_notes["floor_rock_left_lying"] = (_boss.call(&"get_debris") as Array).size() - rocks_before
	_restore_slime()
	# up the roots beside him: the next rock hits it on the vines and shatters
	var roots: Node2D = null
	for name: String in ["claw-roots-1", "claw-roots-2", "claw-roots-3", "claw-roots-4"]:
		var r := _piece(name)
		if roots == null or absf(r.global_position.x - spot_x) < absf(roots.global_position.x - spot_x):
			roots = r
	_place_slime(roots.global_position, Vector2.UP)
	await _run(3)
	var player: Node = Services.world().player
	_push(&"interact", true)
	roots.call(&"use")
	_push(&"move_up", true)
	for i in 120:
		await _tick()
		if bool(player.call(&"get_climb").call(&"is_holding")):
			break
	_push(&"move_up", false)
	_push(&"interact", false)
	_boss.set(&"_next_rock_at", Services.now_ms() + 300.0)
	hp = _slime_health()
	rocks_before = (_boss.call(&"get_debris") as Array).size()
	await _run(80)
	_notes["vine_rock_hurt"] = hp - _slime_health()
	_notes["vine_rock_left_lying"] = (_boss.call(&"get_debris") as Array).size() - rocks_before
	_notes["knocked_off_by_it"] = not bool(player.call(&"is_climbing"))
	_restore_slime()
	# back up the roots (the rock's hit knocked it off), then a quake due: down, quake, back up
	_push(&"interact", false)
	_place_slime(roots.global_position, Vector2.UP)
	await _run(3)
	_push(&"interact", true)
	roots.call(&"use")
	_push(&"move_up", true)
	for i in 120:
		await _tick()
		if bool(player.call(&"get_climb").call(&"is_holding")):
			break
	_push(&"move_up", false)
	_push(&"interact", false)
	_boss.set(&"_next_rock_at", INF)
	_boss.set(&"_quake_ready_at", Services.now_ms())
	var seen: Array = []
	for i in 900:
		var phase := str(_boss.call(&"get_phase"))
		if seen.is_empty() or seen[-1] != phase:
			seen.append(phase)
		if seen.size() > 2 and phase == "cling":
			break
		await _tick()
	_notes["quake_round_trip"] = seen
	_notes["quake_hits_on_the_slime_up_the_roots"] = int(_boss.call(&"quake_hits"))
	_notes["still_climbing_after_the_quake"] = bool(player.call(&"is_climbing"))
	await _run(_tail)


func _lit_braziers() -> int:
	var lit := 0
	for name: String in ["west-brazier", "east-brazier", "lower-brazier-west", "lower-brazier-east"]:
		if bool(_piece(name).call(&"is_lit")):
			lit += 1
	return lit


## Round 1 on the lower line: the cart at him, his plates hot (`hot`) or cold; then, furious, he kicks
## it back up its line. `all_lit`: every brazier lit first (the douse film).
func _film_cart(hot: bool, all_lit: bool = false) -> void:
	if not await _start_fight():
		return
	var cart := _piece("lower-cart")
	var target := _piece("lower-target")
	var brazier := _piece("lower-brazier-west")
	if hot:
		brazier.call(&"light")
	if all_lit:
		for name: String in ["west-brazier", "east-brazier", "lower-brazier-east"]:
			_piece(name).call(&"light")
		_notes["lit_before"] = _lit_braziers()
		_notes["dousing_before"] = bool(_boss.call(&"is_dousing"))
	_listen()
	var line_y := cart.global_position.y
	var spot := Vector2(brazier.global_position.x + 42.0, line_y)
	_still_camera(Vector2((spot.x + cart.global_position.x) * 0.5, line_y - 60.0))
	# the slime by the lower target, to throw east at it
	_place_slime(target.global_position + Vector2(-150.0, 12.0), Vector2.RIGHT)
	_hold_stomps()
	_put_boss(spot)
	await _run(16)
	_notes["hp_before"] = _boss_hp()
	_notes["brittle_before"] = bool(_boss.call(&"is_brittle"))
	await _throw(Vector2.RIGHT, func() -> void:
		# the bait: he walks east along the rails in the ring as the pot leaves
		_hold_stomps()
		_put_boss(spot)
		_boss.call(&"_transition", "walk", Services.now_ms()))
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	await _wait_state(cart, "bump", 300)
	var bumped := Services.now_ms()
	_notes["cart_stopped_at"] = str((cart.call(&"cart_point") as Vector2).snappedf(1.0))
	_notes["boss_feet_at_bump"] = str(_boss_feet().snappedf(1.0))
	_notes["clang_hint_given"] = bool(_boss.get(&"_clang_hinted"))
	# the stagger, then the kick: the cart rolls home
	_notes["phase_before_kick"] = await _wait_phase("kick", 200)
	_notes["kick_after_ms"] = int(Services.now_ms() - bumped)
	_notes["cart_after_kick"] = await _wait_state(cart, "return", 80)
	var kicked := Services.now_ms()
	_notes["cart_home"] = await _wait_state(cart, "held", 160)
	_notes["home_after_ms"] = int(Services.now_ms() - kicked)
	_notes["target_rearmed"] = bool(target.call(&"is_armed")) or str(target.call(&"state_name")) == "rearm"
	_notes["hp_after"] = _boss_hp()
	_notes["plates_after"] = _plates_now()
	await _run(_tail)


## A cart that meets nothing: out of the east tunnel, over the dips and the floor, into the west tunnel;
## then the next one comes out.
func _film_pass() -> void:
	if not await _start_fight():
		return
	var cart := _piece("lower-cart")
	var target := _piece("lower-target")
	_listen()
	# him held well off the rails, north of them, his step held
	_put_boss(Vector2(_floor_rect().get_center().x, cart.global_position.y - 260.0))
	_hold_still(Vector2.DOWN)
	_still_camera(Vector2(_arena_rect().get_center().x, cart.global_position.y - 40.0))
	_place_slime(target.global_position + Vector2(-150.0, 12.0), Vector2.RIGHT)
	await _run(10)
	await _throw(Vector2.RIGHT)
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	_notes["cart_rolling"] = await _wait_state(cart, "roll", 60)
	var rolled := Services.now_ms()
	_notes["cart_gone"] = await _wait_state(cart, "gone", 400)
	_notes["crossed_ms"] = int(Services.now_ms() - rolled)
	_notes["next_cart"] = await _wait_state(cart, "appear", 160)
	_notes["held_again"] = await _wait_state(cart, "held", 80)
	await _run(20)
	_notes["target_rearmed"] = bool(target.call(&"is_armed"))
	_notes["boss_hit"] = (_notes.get("plate_events", []) as Array).size()
	await _run(_tail)


## A void dip mid-fight: the slime walks off the floor into the west dip, falls, is hurt and put back
## where it stepped off; the fight goes on.
func _film_dip() -> void:
	if not await _start_fight():
		return
	var floor := _floor_rect()
	var edge := Vector2(floor.position.x + 30.0, floor.get_center().y + 60.0)
	_still_camera(edge + Vector2(140.0, -60.0))
	_hold_stomps()
	_place_slime(edge, Vector2.LEFT)
	await _run(10)
	var hp := _slime_health()
	var body := Services.world().player_body
	var track: Array = []
	# the held key as the game reads a walk (its state, besides the event)
	_push(&"move_left", true)
	Input.action_press(&"move_left")
	for i in 70:
		await _tick()
		if i % 10 == 0:
			track.append(str(body.global_position.snappedf(1.0)))
	Input.action_release(&"move_left")
	_push(&"move_left", false)
	_notes["slime_track"] = track
	await _run(120)
	var feet := body.global_position
	_notes["slime_hurt"] = hp - _slime_health()
	_notes["slime_back_at"] = str(feet.snappedf(1.0))
	_notes["slime_on_his_floor"] = floor.has_point(feet)
	_notes["fight_goes_on"] = _arena.call(&"get_live_boss") == _boss
	await _run(_tail)


## The last phase: the wall, the claws, the crash across the west down line under his spot, the cart
## bursting his breastplate.
func _film_wall() -> void:
	if not await _start_fight():
		return
	_boss.call(&"stage_crystals", ["C"], {"L": 0.0, "R": 0.0})
	_listen()
	var roots := _piece("claw-roots-1")
	var target := _piece("west-target")
	var cart := _piece("west-cart")
	var spot_x := cart.global_position.x
	_put_boss(Vector2(spot_x + 60.0, 560.0))
	# the slime waits below his west spot, beside the line, while he leaps and throws
	_place_slime(Vector2(spot_x + 110.0, 700.0), Vector2.UP)
	_still_camera(Vector2(spot_x + 20.0, 400.0))
	await _run(10)
	_boss.call(&"_leap_up", Services.now_ms(), Vector2(spot_x, 640.0))
	await _wait_phase("cling", 120)
	# two mites rain down
	var mites_by := Services.now_ms() + 2600.0
	while Services.now_ms() < mites_by:
		await _tick()
	_notes["mites_thrown"] = int(_boss.get(&"_thrown"))
	# a mite freed while he still counts it (it died: the crash the owner hit, 2026-11-24): the count
	# still reads
	var thrown: Array = _boss.get(&"_mites")
	if not thrown.is_empty() and is_instance_valid(thrown[0]):
		((thrown[0] as Node).get_parent() as Node).free()
	_notes["live_mites_after_one_freed"] = int(_boss.call(&"live_mites"))
	# no more while the slime climbs (a mite knocks a climber off), and the two thrown are taken away
	# (staged: they would hound the slime at the target)
	_boss.set(&"_next_throw_at", INF)
	_boss.call(&"clear_mites")
	_boss.set(&"_phase_started_at", Services.now_ms())
	var player: Node = Services.world().player
	_place_slime(roots.global_position, Vector2.UP)
	await _run(4)
	_push(&"interact", true)
	_notes["roots_used"] = bool(roots.call(&"use"))
	_push(&"move_up", true)
	for i in 200:
		await _tick()
		if bool(player.call(&"get_climb").call(&"is_holding")):
			break
	_push(&"move_up", false)
	_notes["holding_at_top"] = bool(player.call(&"get_climb").call(&"is_holding"))
	# three strikes at his claws (he clings right of these roots)
	var strikes := 0
	for i in 3:
		_push(&"move_right", true)
		# the climb strike is the attack (A) since the one combat (2026-11-25; Q before it)
		_push(&"attack", true)
		await _tick()
		await _tick()
		_push(&"attack", false)
		for k in 40:
			await _tick()
			if int(_boss.call(&"claw_hits")) > strikes or str(_boss.call(&"get_phase")) == "fall":
				break
		strikes = int(_boss.call(&"claw_hits"))
		_push(&"move_right", false)
		await _run(10)
		if str(_boss.call(&"get_phase")) in ["fall", "stunned"]:
			break
	_notes["claw_hits"] = strikes
	_notes["phase_after_claws"] = str(_boss.call(&"get_phase"))
	await _let_go()
	await _wait_phase("stunned", 60)
	_notes["lies_at"] = str(_boss_feet().snappedf(1.0))
	_notes["crash_line_x"] = (cart as Node2D).global_position.x
	_notes["hp_on_his_back"] = _boss_hp()
	# off the wall and to the west target with a pot, thrown at it from its outer side
	_place_slime(target.global_position + Vector2(-150.0, 6.0), Vector2.RIGHT)
	await _tick()
	await _throw(Vector2.RIGHT)
	_notes["target_after_throw"] = await _wait_state(target, "spin", 60)
	await _wait_state(cart, "bump", 200)
	_notes["cart_stopped_at"] = str((cart.call(&"cart_point") as Vector2).snappedf(1.0))
	await _run(80)
	_notes["plates_after"] = _plates_now()
	_notes["hp_after"] = _boss_hp()
	# getting up, he kicks it back into its tunnel
	_notes["phase_after_he_lay"] = await _wait_phase("kick", 300)
	_notes["cart_after_kick"] = await _wait_state(cart, "return", 80)
	_notes["cart_home"] = await _wait_state(cart, "held", 160)
	await _run(_tail)


## Phase 1 from the wake: nothing staged on his crystals (see the head).
func _film_phase1() -> void:
	if not await _start_fight():
		return
	_listen()
	var ok := await _arm_phase("L", false)
	_notes["phase_at_end"] = int(_boss.call(&"crystal_phase"))
	_verdict(ok and int(_notes["phase_at_end"]) == 2, "phase 1: the cart burst %s without harm (%s), its crystal destroyed in %s strikes, phase now %d"
		% [_notes.get("L_burst", "-"), _notes.get("L_burst_harmless", "-"), _notes.get("L_struck_by", "-"), int(_notes["phase_at_end"])])


## Phase 2: his first shoulder dead and bare (staged), then as phase 1 with the cart on his dead side.
func _film_phase2() -> void:
	if not await _start_fight():
		return
	_boss.call(&"stage_crystals", ["C", "R"], {"L": 0.0})
	_listen()
	var ok := await _arm_phase("R", true)
	_notes["went_up_his_wall"] = await _wait_phase("cling", 400) == "cling"
	_verdict(ok and bool(_notes["went_up_his_wall"]), "phase 2: the cart met him %s (his dead side east), burst %s, its crystal destroyed, up his wall %s"
		% [_notes.get("R_cart_side", "-"), _notes.get("R_burst", "-"), _notes["went_up_his_wall"]])


## Phase 3: both shoulders dead (staged); the wall, the claws, the falls, the chest.
func _film_phase3() -> void:
	if not await _start_fight():
		return
	_boss.call(&"stage_crystals", ["C"], {"L": 0.0, "R": 0.0})
	_listen()
	_send_him_west()
	var ok := await _chest_phase(2)
	_verdict(ok, "phase 3: the breastplate burst on his back (%s), he got up %d time(s) before the chest died, defeated %s"
		% [_notes.get("C_burst_lying", "-"), int(_notes.get("got_up", 0)), _notes.get("defeated", false)])


## The whole fight: the three phases in a row, nothing staged on his crystals or plates.
func _film_fight() -> void:
	if not await _start_fight():
		return
	_listen()
	var one := await _arm_phase("L", false)
	_notes["phase_after_one"] = int(_boss.call(&"crystal_phase"))
	var two := false
	if one:
		two = await _arm_phase("R", true)
	_notes["phase_after_two"] = int(_boss.call(&"crystal_phase"))
	var three := false
	if two:
		three = await _chest_phase(2)
	var order := _events("crystal_broken")
	_notes["crystals_broken"] = order
	_verdict(three and order == ["L", "R", "C"], "the whole fight: crystals broken %s, defeated %s" % [order, _notes.get("defeated", false)])


## One shoulder's phase (`crystal`, L or R): the phase's first clink (a Spear hit on his front: the
## line, the plate flashing); the lower-west brazier lit by the Lantern if it is out; the pot at the
## lower target as he is put on the line in its ring (turned north and held still till the cart meets
## him when `dead_side`: the cart then meets his dead first shoulder); the burst (no harm), the kick
## home; the bare crystal struck until it is destroyed. True when it was.
func _arm_phase(crystal: String, dead_side: bool) -> bool:
	var cart := _piece("lower-cart")
	var target := _piece("lower-target")
	var brazier := _piece("lower-brazier-west")
	var line_y := cart.global_position.y
	var spot := Vector2(brazier.global_position.x + 42.0, line_y)
	_still_camera(Vector2((spot.x + cart.global_position.x) * 0.5, line_y - 60.0))
	_hold_stomps()
	# his quake held off for the phase (as `_start_fight` holds it: the films run longer than its wait)
	_boss.set(&"_quake_ready_at", Services.now_ms() + HOLD_MS)
	# the phase's first clink: the Spear on his plated front
	await _wait_hittable(240)
	var facing: Vector2 = _boss.call(&"facing")
	_place_slime(_boss_feet() + facing * STRIKE_FRONT_PX, -facing)
	await _tick()
	var hp := _boss_hp()
	_notes["%s_first_spear" % crystal] = _spear()
	await _run(40)
	_notes["%s_first_spear_clinked" % crystal] = is_equal_approx(_boss_hp(), hp)
	_notes["%s_line_given" % crystal] = int(_boss.get(&"_clink_hinted_phase")) == int(_boss.call(&"crystal_phase"))
	await _run(60)
	_restore_slime()
	# the brazier lit with the Lantern (from just west of it, facing it) when it is out
	if not bool(brazier.call(&"is_lit")):
		_place_slime(brazier.global_position + Vector2(-64.0, 4.0), Vector2.RIGHT)
		await _run(6)
		_notes["%s_lantern" % crystal] = await _cast_lantern(Vector2.RIGHT)
		await _run(20)
	_notes["%s_brazier_lit" % crystal] = bool(brazier.call(&"is_lit"))
	# the slime by the lower target, to throw east at it; he is put on the line as the pot leaves
	_notes["%s_cart_ready" % crystal] = await _wait_state(cart, "held", 400)
	_place_slime(target.global_position + Vector2(-150.0, 12.0), Vector2.RIGHT)
	_hold_stomps()
	_put_boss(spot)
	await _run(10)
	var bursts_before := _events("burst").size()
	await _throw(Vector2.RIGHT, func() -> void:
		_hold_stomps()
		_put_boss(spot)
		if dead_side:
			# turned north and held still (staged): the cart from the east meets his dead shoulder
			_hold_still(Vector2.UP)
		else:
			_boss.call(&"_transition", "walk", Services.now_ms()))
	_notes["%s_target_after_throw" % crystal] = await _wait_state(target, "spin", 90)
	var hp_before := _boss_hp()
	await _wait_state(cart, "bump", 300)
	_boss.set_physics_process(true)
	await _run(4)
	var bursts := _events("burst")
	_notes["%s_burst" % crystal] = bursts[bursts.size() - 1] if bursts.size() > bursts_before else "-"
	# the way he faced as the cart met him (the burst's own record: the stagger turns him to the viewer)
	for event: Variant in _notes.get("plate_events", []):
		if event is Dictionary and (event as Dictionary).has("burst"):
			_notes["%s_cart_side" % crystal] = "facing %s" % (event as Dictionary).get("facing", "-")
	_notes["%s_burst_harmless" % crystal] = is_equal_approx(_boss_hp(), hp_before)
	# staggered, he kicks it home; the slime strikes the bare crystal meanwhile
	var dead := await _strike_crystal(crystal, 16)
	_notes["%s_cart_after" % crystal] = str(cart.call(&"state_name"))
	if crystal == "R":
		# he makes for his wall: the slime by the west roots, so he takes the west spot
		_send_him_west()
	# the beat
	await _run(100)
	return dead and str(_notes["%s_burst" % crystal]) == crystal and bool(_notes["%s_burst_harmless" % crystal])


## The slime by the west roots' foot: his next leap onto his wall takes the west spot.
func _send_him_west() -> void:
	var roots := _piece("claw-roots-1")
	_place_slime(roots.global_position + Vector2(40.0, 90.0), Vector2.UP)


## The chest's phase: up his wall (at the west spot), the slime up the roots striking his claws (his
## mites and rocks held while it climbs: staged), his crash across the nearest crash line; on his back
## a pot at that line's target while his breastplate is on (the cart bursts it), and the Spear on his
## chest while he lies, at most `first_strikes` strikes the first time (he gets up, kicks the cart home
## and goes back up); again until the chest goes dark and he falls for good. True when he fell after
## getting up at least once.
func _chest_phase(first_strikes: int) -> bool:
	_zoom = 0.85
	# his quake held off for the phase (it would bring him down while the slime climbs)
	_boss.set(&"_quake_ready_at", Services.now_ms() + HOLD_MS)
	var falls := 0
	_notes["got_up"] = 0
	for round in 4:
		if bool(_boss.call(&"is_defeated")):
			break
		var phase := await _wait_phase("cling", 900)
		if phase != "cling":
			_notes["no_climb_in_round_%d" % round] = phase
			break
		_still_camera(Vector2(_boss_feet().x + 20.0, 420.0))
		# his mites and rocks held while the slime climbs (a hit knocks a climber off); the thrown taken away
		_boss.set(&"_next_throw_at", INF)
		_boss.set(&"_next_rock_at", INF)
		_boss.call(&"clear_mites")
		_boss.set(&"_phase_started_at", Services.now_ms())
		if not await _strike_claws():
			_notes["claws_failed_in_round_%d" % round] = str(_boss.call(&"get_phase"))
			break
		await _let_go()
		if await _wait_phase("stunned", 90) != "stunned":
			break
		falls += 1
		_still_camera(_boss_feet() + Vector2(60.0, -80.0))
		if bool(_boss.call(&"has_plate", "C")):
			await _cart_on_his_back()
		await _strike_crystal("C", first_strikes if falls == 1 else 12, true)
		if bool(_boss.call(&"is_defeated")):
			break
		# up again: he kicks the cart home and goes back up; the slime by the west roots for the west spot
		_send_him_west()
		var up := await _wait_phase("leap-up", 500)
		if up in ["leap-up", "cling"]:
			_notes["got_up"] = int(_notes["got_up"]) + 1
	_notes["falls"] = falls
	_notes["defeated"] = bool(_boss.call(&"is_defeated"))
	if bool(_notes["defeated"]):
		# his fall plays on
		_place_slime(_boss_feet() + Vector2(0.0, 200.0), Vector2.UP)
		await _run(_tail + 150)
	return bool(_notes["defeated"]) and int(_notes["got_up"]) >= 1


## The slime climbs the roots nearest his spot and strikes his claws (from the roots' side of him)
## until he loses his grip. True when he falls.
func _strike_claws() -> bool:
	var spot_x := _boss_feet().x
	var roots: Node2D = null
	for name: String in ["claw-roots-1", "claw-roots-2", "claw-roots-3", "claw-roots-4"]:
		var r := root.find_child(name, true, false) as Node2D
		if r != null and (roots == null or absf(r.global_position.x - spot_x) < absf(roots.global_position.x - spot_x)):
			roots = r
	if roots == null:
		return false
	var player: Node = Services.world().player
	_place_slime(roots.global_position, Vector2.UP)
	await _run(4)
	_push(&"interact", true)
	roots.call(&"use")
	_push(&"move_up", true)
	for i in 200:
		await _tick()
		if bool(player.call(&"get_climb").call(&"is_holding")):
			break
	_push(&"move_up", false)
	var toward := &"move_right" if spot_x > roots.global_position.x else &"move_left"
	for i in 4:
		_push(toward, true)
		# the climb strike is the attack (A) since the one combat (2026-11-25; Q before it)
		_push(&"attack", true)
		await _tick()
		await _tick()
		_push(&"attack", false)
		for k in 40:
			await _tick()
			if str(_boss.call(&"get_phase")) == "fall":
				break
		_push(toward, false)
		await _run(10)
		if str(_boss.call(&"get_phase")) in ["fall", "stunned"]:
			break
	_notes["claw_hits"] = int(_notes.get("claw_hits", 0)) + int(_boss.call(&"claw_hits"))
	return str(_boss.call(&"get_phase")) in ["fall", "stunned"]


## On his back: a pot at the target of the crash line he lies across, from its outer side; the cart
## comes down and bursts his breastplate.
func _cart_on_his_back() -> void:
	var cart: Node2D = null
	var nearest := INF
	for node: Variant in _boss.get(&"crash_carts"):
		var line := node as Node2D
		if line != null and is_instance_valid(line) and line.global_position.distance_to(_boss_feet()) < nearest:
			nearest = line.global_position.distance_to(_boss_feet())
			cart = line
	if cart == null or not cart.has_method(&"get_knock_target"):
		_notes["no_crash_cart"] = true
		return
	var target := cart.call(&"get_knock_target") as Node2D
	var bursts_before := _events("burst").size()
	_place_slime(target.global_position + Vector2(-150.0, 6.0), Vector2.RIGHT)
	await _tick()
	await _throw(Vector2.RIGHT)
	await _wait_state(cart, "bump", 200)
	await _run(4)
	var bursts := _events("burst")
	_notes["C_burst_lying"] = bursts[bursts.size() - 1] if bursts.size() > bursts_before else "-"


## The slime strikes `crystal` (bare) until it is destroyed, at most `tries` strikes: a pot thrown from
## his front while he staggers (once), else the Spear from his front, the crystal's own side or his
## back by turns (the sides it shows on; the chest: his front and sides; lying, from below), put there
## by the tool each time, his steps his own (`while_lying`: only while he lies on his back). True when
## it was destroyed.
func _strike_crystal(crystal: String, tries: int, while_lying: bool = false) -> bool:
	var strikes: Array = []
	var potted := false
	for i in tries:
		if bool(_boss.call(&"is_defeated")) or bool(_boss.call(&"is_crystal_dead", crystal)):
			break
		if while_lying and str(_boss.call(&"get_phase")) != "stunned":
			break
		if not while_lying:
			await _wait_hittable(300)
		var phase := str(_boss.call(&"get_phase"))
		var facing: Vector2 = _boss.call(&"facing")
		var right := Vector2(-facing.y, facing.x)
		var own := right if crystal == "L" else -right
		var spots: Array = [facing * STRIKE_FRONT_PX, own * STRIKE_SIDE_PX, -facing * STRIKE_FRONT_PX]
		if crystal == "C":
			spots = [facing * STRIKE_FRONT_PX, right * STRIKE_SIDE_PX, -right * STRIKE_SIDE_PX]
		var offset: Vector2 = Vector2(0.0, STRIKE_FRONT_PX) if phase == "stunned" else spots[i % spots.size()]
		var before := _boss_hp()
		var clinks_before := int(_boss.call(&"clinks"))
		var how := "spear"
		var answer := ""
		if not potted and phase == "stagger" and not while_lying:
			potted = true
			how = "pot"
			_place_slime(_boss_feet() + facing * 170.0, -facing)
			await _tick()
			await _throw(-facing)
			await _run(30)
		else:
			_place_slime(_boss_feet() + offset, -offset.normalized())
			await _tick()
			# the Lunge's own answer: "" struck, "busy" while its last strike runs (the tool strikes
			# faster than a player)
			answer = _spear()
			await _run(30)
		var landed := "hurt" if _boss_hp() < before else ("clinked" if int(_boss.call(&"clinks")) > clinks_before else "missed")
		strikes.append({"how": how, "phase": phase, "from": _way_name(offset), "hp_before": before, "hp_after": _boss_hp(),
			"left": float(_boss.call(&"crystal_left", crystal)), "landed": landed, "lunge": answer})
		_restore_slime()
	_notes["%s_strikes" % crystal] = (_notes.get("%s_strikes" % crystal, []) as Array) + strikes
	var dead := bool(_boss.call(&"is_crystal_dead", crystal)) or bool(_boss.call(&"is_defeated"))
	if dead:
		_notes["%s_struck_by" % crystal] = (_notes["%s_strikes" % crystal] as Array).size()
	return dead


## Steps until he can be hit (on his feet or his back, not up his wall or in the air), at most `frames`.
func _wait_hittable(frames: int) -> void:
	for i in frames:
		if str(_boss.call(&"get_phase")) in HITTABLE:
			return
		await _tick()


## The plate events of one kind ("burst", "clang", "crystal_broken"): their plate or crystal.
func _events(kind: String) -> Array:
	var found: Array = []
	for event: Variant in _notes.get("plate_events", []):
		if event is Dictionary and (event as Dictionary).has(kind):
			found.append((event as Dictionary)[kind])
	return found


## The film's verdict (PASS or FAIL) and what was checked, into the notes and the last line printed.
func _verdict(ok: bool, what: String) -> void:
	_notes["verdict"] = "PASS" if ok else "FAIL"
	_notes["checked"] = what
	print("film_colossus: %s %s: %s" % [_film, _notes["verdict"], what])


# --- staging -----------------------------------------------------------------------------------------

## The slime walks into the arena: the fight starts and he wakes. False when he never comes.
func _start_fight() -> bool:
	_place_slime(Vector2(_floor_rect().get_center().x, _arena_rect().end.y - 110.0), Vector2.UP)
	for i in 240:
		await _tick()
		_boss = _arena.call(&"get_live_boss") if _arena != null else null
		if _boss != null and str(_boss.call(&"get_phase")) == "walk":
			break
	if _boss == null:
		push_error("film_colossus: the fight did not start")
		return false
	# his quake held off (the films run longer than its first wait); the quake film lets it go
	_boss.set(&"_quake_ready_at", Services.now_ms() + HOLD_MS)
	return true


## The fight (the arena's `arena_rect`) and his floor (its `floor_rect`: the fight less the void dips).
func _arena_rect() -> Rect2:
	return _arena.get(&"arena_rect") as Rect2


func _floor_rect() -> Rect2:
	var floor := _arena.get(&"floor_rect") as Rect2
	return floor if floor.has_area() else _arena_rect()


## The Lantern chosen in the Ability Box and cast facing `way` (its key's press). Returns "cast" when a
## flame left, else why not.
func _cast_lantern(way: Vector2) -> String:
	var player: Node = Services.world().player
	if not AbilityBox.select(player, LANTERN):
		return "the Lantern is not in the Ability Box"
	player.call(&"face", way)
	await _tick()
	_push(&"ability_use", true)
	await _tick()
	await _tick()
	_push(&"ability_use", false)
	await _run(16)
	return "cast"


func _boss_body() -> CharacterBody2D:
	return _boss.call(&"get_body") as CharacterBody2D


func _boss_feet() -> Vector2:
	return _boss_body().global_position


func _boss_hp() -> float:
	return float((_boss.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


func _put_boss(feet: Vector2) -> void:
	var body := _boss_body()
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()


## Lets go of the wall: the cling is a toggle (player.gd `_step_climb`), so the held key goes up and a
## second press lets go.
func _let_go() -> void:
	_push(&"interact", false)
	await _tick()
	_push(&"interact", true)
	await _tick()
	_push(&"interact", false)


## His stomps and his leap held off for the shot (he still walks).
func _hold_stomps() -> void:
	_boss.set(&"_stomp_ready_at", Services.now_ms() + HOLD_MS)
	_boss.set(&"_hop_ready_at", Services.now_ms() + HOLD_MS)


## He stands still facing `way` (his walk's standing frame), his step held: the hits he takes are the
## game's (the router), only his moving is staged away.
func _hold_still(way: Vector2) -> void:
	_boss.call(&"_set_facing", way)
	_boss.call(&"_transition", "walk", Services.now_ms())
	_boss_body().velocity = Vector2.ZERO
	_boss.set_physics_process(false)


## His crystals' health now, in their order ("L60 R60 C60"; a dead one "L-").
func _crystals_now() -> String:
	var out: Array[String] = []
	for crystal: String in ["L", "R", "C"]:
		var left := float(_boss.call(&"crystal_left", crystal))
		out.append(crystal + ("-" if left <= 0.0 else str(int(left))))
	return " ".join(out)


func _plates_now() -> String:
	var on := ""
	for plate: String in PLATES:
		if bool(_boss.call(&"has_plate", plate)):
			on += plate
	return on if not on.is_empty() else "-"


## His plate signals into the notes.
func _listen() -> void:
	var events: Array = []
	_notes["plate_events"] = events
	_boss.connect(&"plate_burst", func(payload: Dictionary) -> void:
		events.append({"burst": payload.get("plate"), "by": payload.get("by"), "hp": payload.get("hp"), "frame": _index,
			"facing": _way_name(_boss.call(&"facing"))}))
	_boss.connect(&"plate_clanged", func(payload: Dictionary) -> void:
		events.append({"clang": payload.get("plate"), "by": payload.get("by"), "frame": _index,
			"facing": _way_name(_boss.call(&"facing"))}))
	_boss.connect(&"crystal_broken", func(payload: Dictionary) -> void:
		events.append({"crystal_broken": payload.get("crystal"), "by": payload.get("by"), "hp": payload.get("hp"),
			"phase": payload.get("phase"), "frame": _index}))
	Services.world().player.connect(&"damaged", func(commit: Dictionary) -> void:
		var request: Dictionary = commit.get("request", {})
		var result: Dictionary = commit.get("result", {})
		var source: Variant = request.get("source")
		events.append({"slime_hurt": int(result.get("actual_damage", 0)), "by": str(request.get("weapon_id", "")),
			"from": str((source as Node).name) if source is Node else "", "frame": _index}))
	_boss.connect(&"damaged", func(commit: Dictionary) -> void:
		var request: Dictionary = commit.get("request", {})
		var result: Dictionary = commit.get("result", {})
		events.append({"damaged": int(result.get("actual_damage", 0)), "by": str(request.get("weapon_id", "reaction")),
			"tags": str(request.get("weapon_tags", [])), "frame": _index}))


func _piece(node_name: String) -> Node2D:
	var node := root.find_child(node_name, true, false) as Node2D
	if node == null:
		push_error("film_colossus: the lab has no '%s'" % node_name)
	return node


func _place_slime(feet: Vector2, facing: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var body := world.player_body
	player.call(&"teleport", feet + ((player.call(&"get_centre") as Vector2) - body.global_position))
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	player.call(&"face", facing)


## Full health and energy again (a stomp or his touch may have hurt it while it was staged).
func _restore_slime() -> void:
	var player: Node = Services.world().player
	player.call(&"restore_run_state", {"hp": player.call(&"get_max_hp")})
	if player.has_method(&"set_energy"):
		player.call(&"set_energy", 100.0)


## The Spear's charge (its Lunge, ShapeController.fire_charge) the way the slime faces.
func _spear() -> String:
	var shapes: Node = _main.get(&"shapes")
	return str(shapes.call(&"fire_charge", SPEAR)) if shapes != null else "no shapes"


## A clay pot put behind the slime, sucked in and thrown along `way`. `as_it_leaves` runs on the step
## the throw is asked for.
func _throw(way: Vector2, as_it_leaves: Callable = Callable()) -> void:
	var world := Services.world()
	var player: Node = world.player
	var mouth: RefCounted = player.call(&"get_mouth")
	var feet := world.player_body.global_position
	player.call(&"face", -way)
	ThrowAmmo.spawn_liftable("clay-pot", feet - way * AMMO_BEHIND_PX, {"pop": false})
	await _tick()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	for i in 50:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	for i in 6:
		await _tick()
	player.call(&"face", way)
	await _tick()
	if as_it_leaves.is_valid():
		as_it_leaves.call()
	_push(&"eat", true)
	await _tick()
	await _tick()
	_push(&"eat", false)
	_notes["throw_frame"] = _index


## The camera stands still over `at` at the film's zoom.
func _still_camera(at: Vector2) -> void:
	var camera: Node = Services.world().camera
	if camera == null:
		return
	camera.call(&"stop_follow")
	camera.set(&"use_bounds", false)
	camera.set(&"center", at)
	camera.set(&"target_zoom", _zoom)
	if camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", _zoom)


## The control hints' bar and the lab's note: off for the film.
## His packed pictures read straight from disk (the films only): a strip or atlas packed since the
## editor last imported it would show its old import (the crystal pieces, packed 2026-11-25, lie past
## the old atlases' end); the game shows the new ones once the editor has imported them.
func _fresh_colossus_pictures() -> void:
	var animations: Variant = ColossusLook.manifest().get("animations", {})
	if not animations is Dictionary:
		return
	var fresh := 0
	for anim: Variant in (animations as Dictionary).values():
		for key: String in ["file", "plates_file"]:
			var file := str((anim as Dictionary).get(key, ""))
			if file.is_empty():
				continue
			var image := Image.load_from_file(ProjectSettings.globalize_path(ColossusLook.FOLDER + file))
			if image != null and not image.is_empty():
				ColossusLook._pictures[file] = ImageTexture.create_from_image(image)
				fresh += 1
	_notes["pictures_from_disk"] = fresh


func _hide_hints() -> void:
	for child: Node in _main.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("control_hints.gd"):
			child.set(&"visible", false)
			child.set_process(false)
	for label: Node in root.find_children("*-note", "Label", true, false):
		(label as Label).visible = false


func _make_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(10.0, 8.0)
	_caption.add_theme_font_size_override(&"font_size", 16)
	_caption.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.6))
	_caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override(&"outline_size", 5)
	layer.add_child(_caption)


# --- running -----------------------------------------------------------------------------------------

## Steps that are not filmed.
func _settle(frames: int = 60) -> void:
	for i in frames:
		await physics_frame
	_start_ms = Services.now_ms()


func _run(frames: int) -> void:
	for i in frames:
		await _tick()


## Steps until his phase is `phase`, at most `frames`. Returns the phase it ended in.
func _wait_phase(phase: String, frames: int) -> String:
	for i in frames:
		if _boss != null and str(_boss.call(&"get_phase")) == phase:
			break
		await _tick()
	return str(_boss.call(&"get_phase")) if _boss != null else ""


## Steps until `node`'s `state_name()` is `state`, at most `frames`. Returns the state it ended in.
func _wait_state(node: Node, state: String, frames: int) -> String:
	for i in frames:
		if str(node.call(&"state_name")) == state:
			break
		await _tick()
	return str(node.call(&"state_name"))


## One physics step (`still`: a frame only, the game held); every `_every`-th one (each with `still`)
## is saved as a picture and a row.
func _tick(still: bool = false) -> void:
	await (process_frame if still else physics_frame)
	_step += 1
	if not still and _step % _every != 0:
		return
	var ms := Services.now_ms() - _start_ms
	var row := {"ms": int(ms), "step": _step, "slime_hp": _slime_health()}
	var line := "%s   %d ms" % [_film, int(ms)]
	if _boss != null and is_instance_valid(_boss):
		row["phase"] = str(_boss.call(&"get_phase"))
		row["plates"] = _plates_now()
		row["crystals"] = _crystals_now()
		row["hp"] = _boss_hp()
		row["brittle"] = bool(_boss.call(&"is_brittle"))
		row["facing"] = _way_name(_boss.call(&"facing"))
		line += "   %s  plates %s  crystals %s  hp %d%s  facing %s" % [row["phase"], row["plates"],
			row["crystals"], int(row["hp"]), "  HOT" if row["brittle"] else "", row["facing"]]
	if not _caption_extra.is_empty():
		line += "\n" + _caption_extra
		row["pose"] = _caption_extra
	_caption.text = line
	await RenderingServer.frame_post_draw
	# what his look drew in the picture
	var look: Node = _boss.call(&"plate_look") if _boss != null and is_instance_valid(_boss) else null
	if look != null:
		row["look"] = "%s %d%s" % [look.call(&"shown_key"), int(look.call(&"shown_index")), " M" if bool(look.call(&"is_mirrored")) else ""]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	_rows.append(row)
	_index += 1


func _slime_health() -> float:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not player.has_method(&"get_damage_state"):
		return -1.0
	return float((player.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


static func _way_name(way: Variant) -> String:
	if not way is Vector2:
		return "?"
	var v := way as Vector2
	if v == Vector2.ZERO:
		return "-"
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "down" if v.y > 0.0 else "up"


static func _state_name(state: int) -> String:
	return ["gone", "cold", "hot"][clampi(state, 0, 2)]


static func _crystal_name(state: int) -> String:
	return "dead" if state == ColossusLook.DEAD else "live"


## The key as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

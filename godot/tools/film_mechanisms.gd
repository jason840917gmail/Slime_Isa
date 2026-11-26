extends SceneTree
## Films the dungeon mechanisms (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the
## runaway cart") in their lab (world.mechanism-lab, game/dev/mechanisms/mechanism-lab.tscn), frame
## by frame, with the camera still over the lane. Run windowed (it renders) with a fixed frame time,
## one film at a time, from the repo (or through `scripts/godot/film-mechanisms.sh <name>
## --film=<film>`):
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_mechanisms.gd -- \
##         --out=<dir> --film=<name> [--every=<n>] [--slow-every=<n>] [--zoom=<z>] [--tail=<frames>]
## Films:
##   ram-arch       lane A: the slime throws a pot over the pit at the target; the ram swings north
##                  and bursts the bricked arch; it swings back and winds itself up (the whole 8 s)
##   ram-enemies    lane B: the pen's three enemies stand on the lane; a pot at the target; the ram
##                  flings them
##   ram-slime      lane B, twice: the slime on the lane's middle line halfway down it, then north of
##                  the line near its far end; the target is knocked (by the tool, as a thrown thing
##                  does): the ram shoves the slime across the lane, clear of it before the head
##                  arrives (south the first time, north the second), and winds back in between
##   target-refuse  lane B: the Spear on the target, then the slime's body pushing its post: it
##                  only knocks, and the line shows; then a pot at it
##   target-arrow   lane A: the Bow's arrow (made by the tool as the Bow makes it) flies over the pit
##                  and knocks the target
##   target-blast   lane B: the slime casts a Goo Bomb and spits it beside the target, backs off; the
##                  blast trips the target and the ram swings
##   target-roll    lane B: the slime Rolls into the target's post: a wooden knock and the line, the
##                  target stays armed and the ram ready
##   arch-refuse    lane A: the Spear on the bricked arch (its line), then a Goo Bomb beside it (its
##                  other line); it stands
##   gate-refuse    lane C: the Spear on the rail gate, a pot thrown at it along the rails, a Goo Bomb
##                  beside it: one line each, and it stands
##   ram-south      lane B's ram turned to swing south (staged by the tool: moved and turned, its
##                  target beside it), a Worm Brawler on its lane, a pot at the target
##   ram-west       the same, swinging west
##   cart-hook      lane C: a standing dummy that answers `on_mechanism_hit` (tests/lib/
##                  mechanism_hook_probe.gd, given the training dummy's picture) on the second cart's
##                  rails: the cart stops against it; then lane B: the dummy on the ram's lane, the
##                  log swings on through it
##   cart-gate      lane C: a pot at the brake's target; the cart runs down, smashes the rail gate
##                  and stops at its buffer for good (seen from the front: the rattle, the ore, sparks)
##   cart-enemy     lane C: the pen's enemy stands on the second cart's rails; a pot at its target
##   cart-return    lane C: the second cart runs, bumps its buffer and is hauled back (the whole 8 s)
##   look           nothing staged: the camera over `--stage=<x>,<y>`
## Writes <dir>/f<nnn>.png and <dir>/film.json: per saved frame its time (ms of the game's clock
## since the film began), the mechanisms' states and the slime's health, and the notes (what was
## hit, health before and after, which cue players the global audio scene has).
## Frames are saved every `--every`-th step (2) while things happen and every `--slow-every`-th (12)
## through a slow winch back.

const Services := preload("res://game/shared/services.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const BowArrow := preload("res://game/player/abilities/bow_arrow.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const HookProbe := preload("res://tests/lib/mechanism_hook_probe.gd")
const CELL := 64.0
const GOO_BOMBS := &"goo-bombs"
## The hook probe's look: the training dummy (game/scenes/objects/training-dummy.tscn's Visual).
const DUMMY_ART := "res://asset/MAPS/objects/256x256-tile_1x1-training-dummy.webp"
const DUMMY_SCALE := 0.42
const DUMMY_OFFSET := Vector2(-128.0, -256.0)
## The dummy picture's reach at that scale (its arms' span, its height): the probe's hurtbox.
const DUMMY_BODY := Vector2(66.0, 104.0)
## A ram's lane is this wide (ram.gd `width`): half of it either side of its middle line.
const LANE_HALF := 64.0
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "mechanism-lab"
const WINDOW := Vector2i(1024, 768)
const WATCHDOG_S := 420.0
## Where a thing to throw is put: behind the slime's feet, so the suck faces away and the throw
## turns round (as tools/film_worm_bulwark.gd does).
const AMMO_BEHIND_PX := 34.0
## How far ahead of the slime the Bow's arrow leaves (bow_sequence.gd BOW_AHEAD_PX).
const BOW_AHEAD_PX := 26.0
## How long a staged enemy holds still where the tool put it.
const HOLD_STILL_MS := 1500.0
const CUES: Array[StringName] = [&"KnockTargetHit", &"KnockTargetTap", &"KnockTargetRearm", &"RamWindup", &"RamSwing",
	&"RamThud", &"RamRatchet", &"CartBrake", &"CartRoll", &"CartBump", &"BreakStone", &"BreakWood", &"SecretFound"]

var _main: Node
var _out := "user://mechanisms"
var _film := "ram-arch"
var _every := 2
var _fast_every := 2
var _slow_every := 12
var _zoom := 1.3
var _tail := 60
var _stage := Vector2(576.0, 768.0)
var _index := 0
var _step := 0
var _start_ms := 0.0
var _rows: Array = []
var _notes: Dictionary = {}
var _caption: Label
## What each row records: name -> node.
var _watched: Dictionary = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--film="):
			_film = arg.trim_prefix("--film=")
		elif arg.begins_with("--every="):
			_fast_every = maxi(1, int(arg.trim_prefix("--every=")))
		elif arg.begins_with("--slow-every="):
			_slow_every = maxi(1, int(arg.trim_prefix("--slow-every=")))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--tail="):
			_tail = maxi(0, int(arg.trim_prefix("--tail=")))
		elif arg.begins_with("--stage="):
			var place := arg.trim_prefix("--stage=").split(",")
			if place.size() == 2:
				_stage = Vector2(float(place[0]), float(place[1]))
	_every = _fast_every
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_mechanisms: gave up after %d s" % int(WATCHDOG_S))
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
	_start_ms = Services.now_ms()
	_note_cues()
	match _film:
		"ram-arch":
			await _film_ram_arch()
		"ram-enemies":
			await _film_ram_enemies()
		"ram-slime":
			await _film_ram_slime()
		"target-refuse":
			await _film_target_refuse()
		"target-arrow":
			await _film_target_arrow()
		"cart-gate":
			await _film_cart_gate()
		"cart-enemy":
			await _film_cart_enemy()
		"cart-return":
			await _film_cart_return()
		"target-blast":
			await _film_target_blast()
		"target-roll":
			await _film_target_roll()
		"arch-refuse":
			await _film_arch_refuse()
		"gate-refuse":
			await _film_gate_refuse()
		"ram-south":
			await _film_ram_turned("south")
		"ram-west":
			await _film_ram_turned("west")
		"cart-hook":
			await _film_cart_hook()
		"look":
			# the slime stands there: a camera room shows only while the slime is in it
			_place_slime(_stage + Vector2(0.0, 200.0), Vector2.DOWN)
			await _settle()
			_still_camera(_stage)
			await _run(_tail)
		_:
			push_error("film_mechanisms: no film '%s'" % _film)
	_notes["slime_hp_at_end"] = _slime_health()
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"film": _film, "frames": _index, "notes": _notes, "rows": _rows}, "\t"))
	file.close()
	print("film_mechanisms: ", _film, " ", JSON.stringify(_notes))
	quit()


# --- the films ---------------------------------------------------------------------------------------

## Lane A: a pot over the pit at the target; the ram bursts the arch and winds back.
func _film_ram_arch() -> void:
	var target := _piece("a-target")
	var ram := _piece("a-ram")
	var arch := _piece("a-arch")
	_watch({"target": target, "ram": ram})
	_place_slime(target.global_position + Vector2(270.0, 0.0), Vector2.LEFT)
	await _settle()
	_still_camera(Vector2(420.0, 700.0))
	await _run(20)
	await _throw(Vector2.LEFT)
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	await _wait_state(ram, "hold", 120)
	_notes["arch_burst"] = bool(arch.call(&"is_burst"))
	await _wait_state(ram, "rewind", 120)
	_every = _slow_every
	_notes["ready_again"] = await _wait_state(ram, "ready", 620)
	_every = _fast_every
	_notes["target_rearmed"] = bool(target.call(&"is_armed")) or str(target.call(&"state_name")) == "rearm"
	await _run(_tail)


## Lane B: the pen's enemies on the lane; a pot at the target.
func _film_ram_enemies() -> void:
	var target := _piece("b-target")
	var ram := _piece("b-ram")
	_watch({"target": target, "ram": ram})
	_place_slime(target.global_position + Vector2(170.0, 14.0), Vector2.LEFT)
	await _settle()
	_calm_enemies()
	_still_camera(ram.global_position + Vector2(190.0, 40.0))
	await _run(10)
	var enemies := _enemies_near(ram.global_position + Vector2(160.0, 0.0), 520.0)
	_notes["enemies"] = enemies.size()
	var before: Array = []
	for enemy: Node in enemies:
		before.append(_health_of(enemy))
	_notes["enemy_hp_before"] = before
	var types: Array = []
	var phases: Array = []
	for enemy: Node in enemies:
		types.append(str(enemy.get(&"enemy_type")))
		phases.append(str(enemy.call(&"reaction_phase")) if enemy.has_method(&"reaction_phase") else "")
	_notes["enemy_types"] = types
	_notes["enemy_phases_before"] = phases
	var hits := _record_hits(enemies)
	var from: Array[Vector2] = []
	await _throw(Vector2.LEFT, func() -> void:
		# the bait: each enemy stands on the grooves as the pot leaves; the Thorn Guard awake (asleep
		# it is a rooted statue: thorn_guard.gd `_slides_when_stunned`), put in its march by the tool
		# since its wake step does not run while the staging holds it still
		for enemy: Node in enemies:
			if enemy.has_method(&"is_asleep") and bool(enemy.call(&"is_asleep")):
				enemy.call(&"_transition", "march", Services.now_ms())
				# thorn_guard.gd FRAME_MARCH_A: its eyes lit, on its legs
				enemy.call(&"set_frame", 1)
		_notes["guard_staged"] = "put in its march by the tool"
		var spots: Array[Vector2] = [Vector2(70.0, -18.0), Vector2(150.0, 22.0), Vector2(235.0, -6.0)]
		for i in mini(enemies.size(), spots.size()):
			_put_enemy(enemies[i], ram.global_position + spots[i])
		for enemy: Node in enemies:
			from.append(enemy.call(&"get_centre") as Vector2))
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	var far := await _run_tracking(120, enemies, from, func() -> bool: return str(ram.call(&"state_name")) == "hold")
	far = _merge_far(far, await _run_tracking(110, enemies, from))
	var after: Array = []
	for enemy: Node in enemies:
		after.append(_health_of(enemy))
	_notes["enemy_hp_after"] = after
	_notes["enemy_hits"] = _hit_rows(hits)
	_notes["enemy_farthest_px"] = far
	await _run(_tail)


## Lane B, twice: the slime on the lane's middle line halfway down it, then north of the line near
## its far end; each time the target is knocked as a thrown thing knocks it.
func _film_ram_slime() -> void:
	var target := _piece("b-target")
	var ram := _piece("b-ram")
	_watch({"target": target, "ram": ram})
	_place_slime(ram.global_position + Vector2(160.0, 0.0), Vector2.LEFT)
	await _settle()
	_clear_enemies()
	_still_camera(ram.global_position + Vector2(190.0, 40.0))
	await _run(20)
	_notes["knocked_by"] = "the tool called the target's strike(), as a thrown thing's hit does"
	_notes["middle"] = await _ram_slime_shot(ram, target, Vector2(160.0, 0.0))
	_every = _slow_every
	await _wait_state(ram, "ready", 620)
	_every = _fast_every
	await _run(16)
	_notes["far_end"] = await _ram_slime_shot(ram, target, Vector2(290.0, -24.0))
	await _run(_tail)


## One swing at the slime standing at `spot` from lane B's ram: what it took, where it went, and how
## far outside the lane its feet were when the head reached the place it stood (negative: still in
## the lane), and in how many saved frames the log's head was within its body's reach of it.
func _ram_slime_shot(ram: Node2D, target: Node2D, spot: Vector2) -> Dictionary:
	_place_slime(ram.global_position + spot, Vector2.LEFT)
	await _run(14)
	var body := Services.world().player_body
	var hp := _slime_health()
	var from := body.global_position
	target.call(&"strike")
	var clear_at_head := -999.0
	var touching := 0
	for i in 160:
		await _tick()
		var head: Vector2 = ram.call(&"head_point")
		var feet := body.global_position
		var off_lane := absf(feet.y - ram.global_position.y) - LANE_HALF
		if clear_at_head < -900.0 and head.x >= from.x:
			clear_at_head = off_lane
		if off_lane < 0.0 and absf(head.x - feet.x) < 30.0:
			touching += 1
		if str(ram.call(&"state_name")) == "return":
			break
	return {"spot": str(spot), "hurt": hp - _slime_health(), "moved": str((body.global_position - from).snappedf(1.0)),
		"feet_off_lane_when_head_passed_px": snappedf(clear_at_head, 0.1), "steps_head_on_slime_in_lane": touching}


## Every `damaged` signal of `enemies` from now on, as {type, by, damage, verb} in the returned array.
func _record_hits(enemies: Array[Node]) -> Array:
	var hits: Array = []
	for enemy: Node in enemies:
		var type := str(enemy.get(&"enemy_type"))
		enemy.connect(&"damaged", func(commit: Dictionary) -> void:
			var result: Dictionary = commit.get("result", {})
			var request: Dictionary = commit.get("request", {})
			# the reaction is written into the same result after the signal: read at the end (`_hit_rows`)
			hits.append({"type": type, "by": str(request.get("weapon_id", "")), "damage": int(result.get("actual_damage", 0)),
				"result": result}))
	return hits


## `_record_hits`' rows for the notes, with each hit's reaction verb.
func _hit_rows(hits: Array) -> Array:
	var out: Array = []
	for hit: Dictionary in hits:
		var result: Dictionary = hit.get("result", {})
		var reaction: Variant = result.get("reaction", {})
		out.append({"type": hit["type"], "by": hit["by"], "damage": hit["damage"],
			"verb": str((reaction as Dictionary).get("verb", "")) if reaction is Dictionary else ""})
	return out


## `frames` steps (until `stop` answers true, when given), noting how far each of `enemies` got from
## where it stood (`from`) at most. Returns those distances (units).
func _run_tracking(frames: int, enemies: Array[Node], from: Array[Vector2], stop: Callable = Callable()) -> Array:
	var far: Array = []
	for i in enemies.size():
		far.append(0.0)
	for step in frames:
		if stop.is_valid() and bool(stop.call()):
			break
		await _tick()
		for i in mini(enemies.size(), from.size()):
			if is_instance_valid(enemies[i]) and enemies[i].has_method(&"get_centre"):
				far[i] = maxf(float(far[i]), (enemies[i].call(&"get_centre") as Vector2).distance_to(from[i]))
	return far


func _merge_far(a: Array, b: Array) -> Array:
	var out: Array = []
	for i in a.size():
		out.append(snappedf(maxf(float(a[i]), float(b[i]) if i < b.size() else 0.0), 0.1))
	return out


## Lane B: the Spear and a push only knock on the target (the line shows); then a pot trips it.
func _film_target_refuse() -> void:
	var target := _piece("b-target")
	var ram := _piece("b-ram")
	_watch({"target": target, "ram": ram})
	_place_slime(target.global_position + Vector2(62.0, 10.0), Vector2.LEFT)
	await _settle()
	_clear_enemies()
	_still_camera(target.global_position + Vector2(60.0, -110.0))
	await _run(20)
	var shapes: Node = _main.get(&"shapes")
	_notes["spear"] = str(shapes.call(&"fire_charge", &"shape-spear")) if shapes != null else "no shapes"
	await _run(70)
	_notes["after_spear"] = str(target.call(&"state_name"))
	# its body: a walk into the post
	_place_slime(target.global_position + Vector2(40.0, 4.0), Vector2.LEFT)
	_push(&"move_left", true)
	await _run(36)
	_push(&"move_left", false)
	_notes["after_push"] = str(target.call(&"state_name"))
	await _run(30)
	# and what does trip it
	_place_slime(target.global_position + Vector2(150.0, 14.0), Vector2.LEFT)
	await _run(10)
	await _throw(Vector2.LEFT)
	_notes["after_pot"] = await _wait_state(target, "spin", 90)
	await _wait_state(ram, "hold", 120)
	await _run(_tail)


## Lane A: the Bow's arrow over the pit at the target (the arch is burst by then or not: the ram
## swings either way).
func _film_target_arrow() -> void:
	var target := _piece("a-target")
	var ram := _piece("a-ram")
	_watch({"target": target, "ram": ram})
	_place_slime(target.global_position + Vector2(270.0, 0.0), Vector2.LEFT)
	await _settle()
	_still_camera(Vector2(420.0, 700.0))
	await _run(20)
	var world := Services.world()
	var arrow := BowArrow.new()
	arrow.name = "BowArrow"
	world.entities_root().add_child(arrow)
	arrow.launch(world.player, world.player_body.global_position, Vector2.LEFT, BOW_AHEAD_PX)
	_notes["loosed_by"] = "the tool made the Bow's arrow (bow_arrow.gd) and launched it from the slime, as bow_sequence.gd does"
	_notes["target_after_arrow"] = await _wait_state(target, "spin", 60)
	_notes["ram_after_arrow"] = await _wait_state(ram, "hold", 120)
	await _run(_tail)


## Lane C: the first cart, through its gate to its buffer.
func _film_cart_gate() -> void:
	var target := _piece("c-target")
	var cart := _piece("c-cart")
	var gate := _piece("c-gate")
	_watch({"target": target, "cart": cart})
	_place_slime(target.global_position + Vector2(-150.0, 14.0), Vector2.RIGHT)
	await _settle()
	_clear_enemies()
	_still_camera(cart.global_position + Vector2(-60.0, 190.0))
	await _run(20)
	await _throw(Vector2.RIGHT)
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	await _wait_state(cart, "bump", 240)
	_notes["gate_smashed"] = bool(gate.call(&"is_smashed"))
	await _wait_state(cart, "spent", 120)
	_notes["cart_state"] = str(cart.call(&"state_name"))
	await _run(_tail + 60)


## Lane C: the second cart with the pen's enemy on its rails.
func _film_cart_enemy() -> void:
	var target := _piece("c-target-2")
	var cart := _piece("c-cart-2")
	_watch({"target": target, "cart": cart})
	_place_slime(target.global_position + Vector2(-150.0, 14.0), Vector2.RIGHT)
	await _settle()
	_calm_enemies()
	_still_camera(cart.global_position + Vector2(-170.0, 40.0))
	await _run(10)
	var enemies := _enemies_near(cart.global_position + Vector2(-160.0, 0.0), 300.0)
	_notes["enemies"] = enemies.size()
	var before := _health_of(enemies[0]) if not enemies.is_empty() else -1.0
	var from := (enemies[0].call(&"get_centre") as Vector2) if not enemies.is_empty() else Vector2.ZERO
	await _throw(Vector2.RIGHT, func() -> void:
		if not enemies.is_empty():
			_put_enemy(enemies[0], cart.global_position + Vector2(-190.0, -4.0)))
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	await _wait_state(cart, "bump", 240)
	await _run(70)
	if not enemies.is_empty() and is_instance_valid(enemies[0]):
		_notes["enemy_hp"] = [before, _health_of(enemies[0])]
		_notes["enemy_moved"] = str(((enemies[0].call(&"get_centre") as Vector2) - from).snappedf(1.0))
	await _run(_tail)


## Lane C: the second cart out and hauled home.
func _film_cart_return() -> void:
	var target := _piece("c-target-2")
	var cart := _piece("c-cart-2")
	_watch({"target": target, "cart": cart})
	_place_slime(target.global_position + Vector2(-150.0, 14.0), Vector2.RIGHT)
	await _settle()
	_clear_enemies()
	_still_camera(cart.global_position + Vector2(-170.0, 40.0))
	await _run(10)
	await _throw(Vector2.RIGHT)
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	await _wait_state(cart, "bump", 240)
	await _wait_state(cart, "return", 200)
	_every = _slow_every
	_notes["held_again"] = await _wait_state(cart, "held", 620)
	_every = _fast_every
	await _run(30)
	_notes["target_rearmed"] = bool(target.call(&"is_armed"))
	await _run(_tail)


## Lane B: a Goo Bomb spat beside the target; its blast trips the target and the ram swings.
func _film_target_blast() -> void:
	var target := _piece("b-target")
	var ram := _piece("b-ram")
	_watch({"target": target, "ram": ram})
	_place_slime(target.global_position + Vector2(112.0, 6.0), Vector2.LEFT)
	await _settle()
	_clear_enemies()
	_still_camera(target.global_position + Vector2(150.0, -90.0))
	await _run(16)
	# the cast is 2 s and the fuse 3 s: filmed slower until the blast is near
	_every = 4
	_notes["bomb"] = await _spit_bomb(Vector2.LEFT)
	await _run(16)
	# it backs off out of the blast while the fuse burns
	_push(&"move_right", true)
	await _run(26)
	_push(&"move_right", false)
	var fuse_ms := Services.constants().number("abilities.gooBomb.fuseMs") if Services.constants() != null else 3000.0
	var waited := 0
	while waited < int(fuse_ms / 1000.0 * 60.0) - 90 and str(target.call(&"state_name")) == "armed":
		await _tick()
		waited += 1
	_every = _fast_every
	_notes["target_after_blast"] = await _wait_state(target, "spin", 140)
	_notes["ram_after_blast"] = await _wait_state(ram, "hold", 120)
	await _run(_tail)


## Lane B: a Roll into the target's post only knocks on it.
func _film_target_roll() -> void:
	var target := _piece("b-target")
	var ram := _piece("b-ram")
	_watch({"target": target, "ram": ram})
	_place_slime(target.global_position + Vector2(150.0, 4.0), Vector2.LEFT)
	await _settle()
	_clear_enemies()
	_still_camera(target.global_position + Vector2(90.0, -100.0))
	await _run(20)
	_push(&"move_left", true)
	await _run(4)
	_push(&"dodge", true)
	await _run(2)
	_push(&"dodge", false)
	await _run(40)
	_push(&"move_left", false)
	await _run(60)
	_notes["target_after_roll"] = str(target.call(&"state_name"))
	_notes["ram_after_roll"] = str(ram.call(&"state_name"))
	await _run(_tail)


## Lane A: the Spear and a Goo Bomb on the bricked arch: its two lines; it stands.
func _film_arch_refuse() -> void:
	var arch := _piece("a-arch")
	var ram := _piece("a-ram")
	_watch({"ram": ram})
	_notes["arch_burst_at_start"] = bool(arch.call(&"is_burst"))
	_place_slime(arch.global_position + Vector2(0.0, 60.0), Vector2.UP)
	await _settle()
	_clear_enemies()
	_still_camera(arch.global_position + Vector2(0.0, 80.0))
	await _run(16)
	_notes["spear"] = _spear()
	await _run(80)
	# the arch's line throttle is set when a line is said
	_notes["line_after_spear"] = float(arch.get(&"_next_line_ms")) > 0.0
	var said := float(arch.get(&"_next_line_ms"))
	# a pot thrown at it
	_place_slime(arch.global_position + Vector2(0.0, 170.0), Vector2.UP)
	await _run(10)
	await _throw(Vector2.UP)
	await _run(90)
	_notes["line_after_pot"] = float(arch.get(&"_next_line_ms")) > said
	said = float(arch.get(&"_next_line_ms"))
	# back for the bomb: spat up against the bricks, then away down the lane
	_place_slime(arch.global_position + Vector2(0.0, 92.0), Vector2.UP)
	await _run(10)
	_every = 4
	_notes["bomb"] = await _spit_bomb(Vector2.UP)
	await _run(10)
	var bombs := get_nodes_in_group(&"goo_bombs")
	if not bombs.is_empty():
		_notes["bomb_at_from_arch"] = str(((bombs[0] as Node2D).global_position - arch.global_position).snappedf(1.0))
	_push(&"move_down", true)
	await _run(30)
	_push(&"move_down", false)
	await _run(120)
	_every = _fast_every
	await _run(60)
	_notes["line_after_bomb"] = float(arch.get(&"_next_line_ms")) > said
	_notes["arch_burst_at_end"] = bool(arch.call(&"is_burst"))
	await _run(_tail)


## Lane C: the Spear, a pot and a Goo Bomb on the rail gate: its line; it stands.
func _film_gate_refuse() -> void:
	var gate := _piece("c-gate")
	var cart := _piece("c-cart")
	_watch({"cart": cart})
	_place_slime(gate.global_position + Vector2(74.0, 10.0), Vector2.LEFT)
	await _settle()
	_clear_enemies()
	_still_camera(gate.global_position + Vector2(60.0, -40.0))
	await _run(16)
	_notes["spear"] = _spear()
	await _run(110)
	_notes["line_after_spear"] = float(gate.get(&"_next_line_ms")) > 0.0
	var said := float(gate.get(&"_next_line_ms"))
	# a pot thrown along the rails (from the side its posts stop a throw, as a wall does)
	_place_slime(gate.global_position + Vector2(0.0, 170.0), Vector2.UP)
	await _run(10)
	await _throw(Vector2.UP)
	await _run(110)
	_notes["line_after_pot"] = float(gate.get(&"_next_line_ms")) > said
	said = float(gate.get(&"_next_line_ms"))
	_place_slime(gate.global_position + Vector2(116.0, 0.0), Vector2.LEFT)
	await _run(10)
	_every = 4
	_notes["bomb"] = await _spit_bomb(Vector2.LEFT)
	await _run(10)
	# away down the screen (the second cart's buffer stop stands behind it)
	_push(&"move_down", true)
	await _run(40)
	_push(&"move_down", false)
	await _run(120)
	_every = _fast_every
	await _run(60)
	_notes["line_after_bomb"] = float(gate.get(&"_next_line_ms")) > said
	_notes["gate_smashed_at_end"] = bool(gate.call(&"is_smashed"))
	await _run(_tail)


## Lane B's ram turned to swing `way` (south or west): moved and turned by the tool with its target
## beside it, a Worm Brawler on its lane, a pot thrown at the target.
func _film_ram_turned(way: String) -> void:
	var target := _piece("b-target")
	var ram := _piece("b-ram")
	_watch({"target": target, "ram": ram})
	var south := way == "south"
	var ram_at := Vector2(24.5, 11.6) * CELL if south else Vector2(25.8, 12.0) * CELL
	var target_at := Vector2(21.2, 14.8) * CELL if south else Vector2(27.6, 14.4) * CELL
	# south: thrown from its west; west: from below it
	var throw_way := Vector2.RIGHT if south else Vector2.UP
	ram.global_position = ram_at
	ram.set(&"length", 4 if south else 5)
	ram.set(&"toward", way)
	target.global_position = target_at
	target.call(&"_redraw_rope")
	_place_slime(target_at - throw_way * 150.0 + Vector2(0.0, 12.0 if south else 0.0), throw_way)
	await _settle()
	_calm_enemies()
	# only the Worm Brawler stays
	for enemy: Node in get_nodes_in_group(&"enemy"):
		if str(enemy.get(&"enemy_type")) != "worm-brawler":
			enemy.get_parent().queue_free()
	await _run_unfilmed(4)
	var enemies := _enemies_near(ram_at, 900.0)
	_notes["enemies"] = enemies.size()
	# the whole gantry, the lane and the target in the picture
	# (south: the gantry's top to the lane's end is taller than a screen at the default zoom: film it
	# with --zoom=1.1)
	_still_camera(Vector2(23.4 * CELL, ram_at.y + 30.0) if south else Vector2(24.2, 13.2) * CELL)
	await _run(10)
	var lane_spot := ram_at + (Vector2(0.0, 150.0) if way == "south" else Vector2(-170.0, 6.0))
	var from: Array[Vector2] = []
	var hits := _record_hits(enemies)
	await _throw(throw_way, func() -> void:
		if not enemies.is_empty():
			_put_enemy(enemies[0], lane_spot)
			from.append(enemies[0].call(&"get_centre") as Vector2))
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	var far := await _run_tracking(120, enemies, from, func() -> bool: return str(ram.call(&"state_name")) == "hold")
	far = _merge_far(far, await _run_tracking(60, enemies, from))
	_notes["enemy_hits"] = _hit_rows(hits)
	_notes["enemy_farthest_px"] = far
	await _wait_state(ram, "rewind", 60)
	await _run(_tail)


## Lane C then lane B: a standing dummy that answers `on_mechanism_hit`; the cart stops against it,
## the ram's log swings on through it.
func _film_cart_hook() -> void:
	var target := _piece("c-target-2")
	var cart := _piece("c-cart-2")
	_watch({"target": target, "cart": cart})
	var probe := _dummy_probe(cart.global_position + Vector2(-160.0, 12.0))
	var stops: Array = []
	cart.connect(&"bumped", func(payload: Dictionary) -> void:
		# the gap from the cart's front (its side picture's bumper, ram_cart.gd CONTACT_SIDE ahead; it runs
		# west) to the dummy's hurtbox's near edge: 0 is the touch, below 0 an overlap
		var point: Vector2 = cart.call(&"cart_point")
		var front_x := point.x - float(cart.get(&"CONTACT_SIDE"))
		var edge_x := probe.global_position.x + DUMMY_BODY.x * 0.5
		stops.append({"by": str(payload.get("by").name) if payload.get("by") is Node else "", "at": str(point.snappedf(1.0)),
			"front_to_hurtbox_px": snappedf(front_x - edge_x, 0.1), "hook_calls_at_bump": (probe.get(&"calls") as Array).size()}))
	_place_slime(target.global_position + Vector2(-150.0, 14.0), Vector2.RIGHT)
	await _settle()
	_clear_enemies()
	_still_camera(cart.global_position + Vector2(-170.0, 40.0))
	await _run(10)
	await _throw(Vector2.RIGHT)
	_notes["target_after_throw"] = await _wait_state(target, "spin", 90)
	await _wait_state(cart, "bump", 240)
	await _run(60)
	_notes["cart_stops"] = stops
	_notes["probe_calls_after_cart"] = _probe_calls(probe)
	_notes["cart_line_end"] = str((cart.global_position - Vector2(float(cart.call(&"line_length")), 0.0)).snappedf(1.0))
	# the ram: the dummy on its lane, a pot at its target
	var ram_target := _piece("b-target")
	var ram := _piece("b-ram")
	_watch({"target": ram_target, "ram": ram})
	probe.global_position = ram.global_position + Vector2(200.0, 10.0)
	_place_slime(ram_target.global_position + Vector2(170.0, 14.0), Vector2.LEFT)
	# the camera follows the slime again, so lane B's room is found and shown (its scroll); the room
	# brings its pen back when the slime enters it: calmed, then taken out
	var camera: Node = Services.world().camera
	if camera != null:
		camera.call(&"start_follow", Services.world().player_body)
	for i in 100:
		if i % 10 == 0:
			_calm_enemies()
		await physics_frame
	_clear_enemies()
	await _run_unfilmed(4)
	_still_camera(ram.global_position + Vector2(190.0, 40.0))
	await _run(10)
	await _throw(Vector2.LEFT)
	_notes["ram_target_after_throw"] = await _wait_state(ram_target, "spin", 90)
	_notes["ram_state_after_swing"] = await _wait_state(ram, "hold", 120)
	await _run(50)
	_notes["probe_calls"] = _probe_calls(probe)
	_notes["probe_damage_commits"] = probe.get(&"commits")
	await _run(_tail)


## The hook probe standing at `at` (global) with the training dummy's picture.
func _dummy_probe(at: Vector2) -> Node2D:
	var probe := HookProbe.new()
	probe.name = "HookDummy"
	probe.set(&"size", DUMMY_BODY)
	var look := Sprite2D.new()
	look.name = "Visual"
	look.texture = load(DUMMY_ART) as Texture2D
	look.centered = false
	look.scale = Vector2.ONE * DUMMY_SCALE
	look.offset = DUMMY_OFFSET
	probe.add_child(look)
	var objects := root.find_child("Objects", true, false)
	objects.add_child(probe)
	probe.global_position = at
	return probe


func _probe_calls(probe: Node) -> Array:
	var out: Array = []
	for entry: Array in probe.get(&"calls"):
		out.append([str(entry[0]), str((entry[1] as Node).name) if entry[1] is Node else ""])
	return out


# --- the slime's moves -----------------------------------------------------------------------------

## The Spear's strike the way the slime faces. Returns the shapes' answer.
func _spear() -> String:
	var shapes: Node = _main.get(&"shapes")
	return str(shapes.call(&"fire_charge", &"shape-spear")) if shapes != null else "no shapes"


## The Goo Bomb chosen in the Ability Box and cast facing `way`: the cast, then the spit. Returns
## what happened ("spat", or why not).
func _spit_bomb(way: Vector2) -> String:
	var world := Services.world()
	var player: Node = world.player
	if not AbilityBox.select(player, GOO_BOMBS):
		return "the Goo Bomb is not in the Ability Box"
	player.call(&"face", way)
	await _tick()
	_push(&"ability_use", true)
	await _tick()
	await _tick()
	_push(&"ability_use", false)
	var cast_ms := Services.constants().number("abilities.gooBomb.castMs") if Services.constants() != null else 2000.0
	var spit_ms := Services.constants().number("abilities.gooBomb.spitMs") if Services.constants() != null else 320.0
	await _run(int((cast_ms + spit_ms) / 1000.0 * 60.0) + 6)
	return "spat" if not get_nodes_in_group(&"goo_bombs").is_empty() else "no bomb in the world after the cast"

## A clay pot put behind the slime, sucked in and thrown along `way`. `as_it_leaves` runs on the
## step the throw is asked for.
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
	_notes["held_%d" % _index] = (mouth.get(&"held") as Dictionary).get("kind", "")
	for i in 8:
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


# --- staging ---------------------------------------------------------------------------------------

func _piece(name: String) -> Node2D:
	var node := root.find_child(name, true, false) as Node2D
	if node == null:
		push_error("film_mechanisms: the lab has no '%s'" % name)
	return node


func _watch(nodes: Dictionary) -> void:
	_watched = nodes


## The living enemies within `radius` of `at`, nearest first.
func _enemies_near(at: Vector2, radius: float) -> Array[Node]:
	var out: Array[Node] = []
	for enemy: Node in get_nodes_in_group(&"enemy"):
		if not enemy.has_method(&"get_centre") or bool(enemy.call(&"is_defeated")):
			continue
		if (enemy.call(&"get_centre") as Vector2).distance_to(at) <= radius:
			out.append(enemy)
	out.sort_custom(func(a: Node, b: Node) -> bool:
		return (a.call(&"get_centre") as Vector2).distance_squared_to(at) < (b.call(&"get_centre") as Vector2).distance_squared_to(at))
	return out


## Puts `enemy`'s feet at `at`, standing.
func _put_enemy(enemy: Node, at: Vector2) -> void:
	var body := enemy.call(&"get_body") as CharacterBody2D
	if body == null:
		return
	body.global_position = at
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	# it holds still there until the blow (its own step does nothing while stunned)
	if enemy.has_method(&"set_hit_stun_until"):
		enemy.call(&"set_hit_stun_until", Services.now_ms() + HOLD_STILL_MS)


## The enemies stop looking for the slime (they still wander), so the film's staging holds.
func _calm_enemies() -> void:
	for enemy: Node in get_nodes_in_group(&"enemy"):
		enemy.set(&"targeting_radius", 0.0)
		enemy.set(&"attack_range", 0.0)


## Takes every enemy out of the film.
func _clear_enemies() -> void:
	for enemy: Node in get_nodes_in_group(&"enemy"):
		var owner := enemy.get_parent()
		if owner != null:
			owner.queue_free()


func _health_of(enemy: Variant) -> float:
	if not is_instance_valid(enemy):
		return 0.0
	var value: Variant = (enemy as Node).get(&"_hp")
	return float(value) if value is float or value is int else -1.0


func _place_slime(feet: Vector2, facing: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var body := world.player_body
	player.call(&"teleport", feet + ((player.call(&"get_centre") as Vector2) - body.global_position))
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	player.call(&"face", facing)


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


## The control hints' bar (game/hints/control_hints.gd) lies over the lanes' lower part, and the lab's
## help labels (`a-note`, `b-note`, `c-note`) over the lanes: off for the film.
func _hide_hints() -> void:
	for child: Node in _main.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("control_hints.gd"):
			child.set(&"visible", false)
			child.set_process(false)
	for label: Node in root.find_children("*-note", "Label", true, false):
		(label as Label).visible = false


## A line of text in the picture's corner: the film, the time and what the mechanisms are doing.
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


## Which of the mechanisms' cue players the global audio scene has, with a stream each.
func _note_cues() -> void:
	var feel := Services.feel()
	var audio: Node = feel.global_audio() if feel != null else null
	var have: Array = []
	var missing: Array = []
	for cue: StringName in CUES:
		var player := audio.find_child(String(cue), true, false) as AudioStreamPlayer if audio != null else null
		var ready := player != null and player.stream != null
		if ready and player.stream is AudioStreamRandomizer:
			# every take of a cue with several
			var takes := player.stream as AudioStreamRandomizer
			for i in takes.streams_count:
				ready = ready and takes.get_stream(i) != null
		if ready:
			have.append(String(cue))
		else:
			missing.append(String(cue))
	_notes["cues_ready"] = have
	_notes["cues_missing"] = missing


# --- running -----------------------------------------------------------------------------------------

## Steps that are not filmed, with the camera still following the slime: a slime put in another
## camera room is found there by the camera (the room's scroll), and only then is that room shown.
func _settle(frames: int = 100) -> void:
	for i in frames:
		if i % 10 == 0:
			_calm_enemies()
		await physics_frame
	_start_ms = Services.now_ms()


func _run(frames: int) -> void:
	for i in frames:
		await _tick()


## Steps that are not filmed (the camera still follows the slime).
func _run_unfilmed(frames: int) -> void:
	for i in frames:
		await physics_frame


## Steps until `node`'s `state_name()` is `state`, at most `frames`. Returns the state it ended in.
func _wait_state(node: Node, state: String, frames: int) -> String:
	for i in frames:
		if str(node.call(&"state_name")) == state:
			break
		await _tick()
	return str(node.call(&"state_name"))


## One physics step; every `_every`-th one is saved as a picture and a row.
func _tick() -> void:
	await physics_frame
	_step += 1
	if _step % _every != 0:
		return
	var ms := Services.now_ms() - _start_ms
	var states := {}
	for key: String in _watched:
		var node: Node = _watched[key]
		if is_instance_valid(node) and node.has_method(&"state_name"):
			states[key] = str(node.call(&"state_name"))
	var line := "%s   %d ms" % [_film, int(ms)]
	for key: String in states:
		line += "   %s: %s" % [key, states[key]]
	_caption.text = line
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	_rows.append({"ms": int(ms), "step": _step, "states": states, "slime_hp": _slime_health()})
	_index += 1


func _slime_health() -> float:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not player.has_method(&"get_damage_state"):
		return -1.0
	return float((player.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


## The key as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

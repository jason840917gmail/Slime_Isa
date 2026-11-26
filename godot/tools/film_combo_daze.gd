extends SceneTree
## Films piece 3 of the one combat (docs/design/2026-11-25-weapons-beside-throws.md; THROW_COMBAT.md
## "Enemies as ammo"): a combo sets up the throw. In the playground's enemy pen, frame by frame, with the
## game's camera, HUD and keys (each press sent as the key's action), six checks with a PASS or FAIL:
##   finisher  the Gulp at level 2: A A A on the Worm Swordsman (medium); its finisher's knock lands it
##             dazed and helpless (the first time: the Gulp's hint and the flashing pointer); Q sucks it
##             up, Q throws it at the Worm Brawler, who is hurt
##   taps      three plain taps (each a new chain's first jab) never leave it helpless
##   charge    the Spear's Lunge (A held through the ring) leaves it helpless
##   hammer    the Hammer: a lone thud never; thud, BOOM (the combo's last step) leaves it helpless
##   heavy     the Gulp at level 3: Axe combos on a Thorn Guard (heavy, bark) leave it helpless only once
##             the chop breaks its poise (the Clod Stomper is iron since piece 4: only the Hammer, whose
##             smash staggers a heavy enemy without draining its poise)
##   boss      a combo on the boss-preset training dummy (the playground has no boss): never a daze
##   heavy-for-the-gulp  the Gulp at level 1: the finisher dazes the Swordsman (medium) but Q refuses
##             it with the mouth's "Too heavy" line
## Run windowed (it renders), one game window at a time:
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_combo_daze.gd -- \
##         --out=<dir> [--every=<n>]
## Writes <dir>/f<nnn>.png and <dir>/film.json (the checks with their notes); then
## `python scripts/godot/one-combat-sheet.py <dir>` makes the strip and the GIF.

const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const KeyBindings := preload("res://game/player/mouse/key_bindings.gd")
const TrainingDummyScript := preload("res://game/scripts/training_dummy.gd")
const WeaponDazeHint := preload("res://game/throw/weapon_daze_hint.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const WINDOW := Vector2i(1280, 800)
const WATCHDOG_S := 500.0
const SWORDSMAN := "worm-swordsman"
const BRAWLER := "worm-brawler"
const CLOD := "clod-stomper"
const KEEP_TYPES: Array[String] = [SWORDSMAN, BRAWLER, CLOD]
const BOSS_DUMMY := "shapes-dummy-boss"
## Frames between taps in rhythm (inside the link window) and between plain taps (past it: a new chain).
const RHYTHM_FRAMES := 15
const PLAIN_GAP_FRAMES := 45
## How long a check watches for the daze after its blow (frames).
const WATCH_FRAMES := 110
const TOO_HEAVY_WORDS := "Too heavy"

var _main: Node
var _out := "user://combo-daze"
var _every := 2
var _index := 0
var _step := 0
var _check := ""
var _rows: Array = []
var _checks: Array = []
var _testbed: Node = null
var _shapes: Node = null
var _caption: Label = null
var _enemies: Dictionary = {}
## `--only=<id,...>`: the checks to film (all when empty).
var _only: PackedStringArray = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--every="):
			_every = maxi(1, int(arg.trim_prefix("--every=")))
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_combo_daze: gave up after %d s" % int(WATCHDOG_S))
		quit(1))
	DisplayServer.window_set_size(WINDOW)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", MAP_ID)
	_main.set(&"ability_ceremonies", false)
	root.add_child(_main)
	for i in 90:
		await process_frame
	if Services.feel() != null:
		Services.feel().frame_clock_ms = 1000.0 / 60.0
	if not await _setup():
		quit(1)
		return
	for film: Array in [["finisher", _film_finisher], ["too-heavy", _film_too_heavy], ["taps", _film_taps],
			["charge", _film_charge], ["hammer", _film_hammer], ["heavy", _film_heavy], ["boss", _film_boss]]:
		if _only.is_empty() or _only.has(str(film[0])):
			await (film[1] as Callable).call()
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": _index, "every": _every, "checks": _checks, "rows": _rows}, "\t"))
	file.close()
	for check: Dictionary in _checks:
		print("film_combo_daze: ", "PASS " if bool(check["pass"]) else "FAIL ", check["id"], " ", JSON.stringify(check["notes"]))
	quit()


func _setup() -> bool:
	if not KeyBindings.is_applied():
		KeyBindings.apply(true)
	_testbed = root.find_child("ShapesTestbed", true, false)
	_shapes = _main.get(&"shapes")
	if _testbed == null or _shapes == null:
		push_error("film_combo_daze: no testbed or no shapes")
		return false
	_testbed.set(&"pen_respawn_ms", 1.0e9)
	for i in 30:
		await physics_frame
	if not await _fresh_pen():
		return false
	var layer := CanvasLayer.new()
	layer.layer = 100
	_caption = Label.new()
	_caption.position = Vector2(24.0, 18.0)
	_caption.add_theme_font_size_override(&"font_size", 26)
	_caption.add_theme_color_override(&"font_color", Color.WHITE)
	_caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(_caption)
	root.add_child(layer)
	return true


## The pen anew (the testbed's F4) with the Swordsman, the Brawler and the Clod Stomper; the others go.
func _fresh_pen() -> bool:
	_enemies.clear()
	_testbed.call(&"respawn_pen")
	for i in 6:
		await physics_frame
	for slot: Dictionary in _testbed.get(&"pen"):
		var enemy: Variant = slot.get("enemy")
		var type := str(slot.get("type", ""))
		if not is_instance_valid(enemy):
			continue
		if KEEP_TYPES.has(type):
			_enemies[type] = enemy
		else:
			var root_node: Variant = slot.get("root")
			if is_instance_valid(root_node):
				(root_node as Node).queue_free()
	if not _enemies.has(SWORDSMAN) or not _enemies.has(BRAWLER):
		push_error("film_combo_daze: the pen has no swordsman or brawler")
		return false
	return true


# --- the checks -------------------------------------------------------------------------------------

func _film_finisher() -> void:
	_begin("finisher", "1  Gulp 2:  A A A on the Swordsman,  it lands dazed,  Q sucks it,  Q throws it")
	ThrowMode.set_dev_level(2)
	_restore_slime()
	_shapes.call(&"set_current", ShapeDefs.SPEAR)
	var worm: Node = _enemies[SWORDSMAN]
	var brawler: Node = _enemies[BRAWLER]
	var spot := _pen_point(0.5, 0.55)
	_place_enemy(worm, spot + Vector2(78.0, 0.0))
	_place_enemy(brawler, spot + Vector2(-170.0, 0.0))
	_remove(CLOD)
	_place_slime(spot, Vector2.RIGHT)
	await _run(10)
	var watch := await _combo(worm, true)
	var helpless_at := int(watch.get("helpless_frame", -1))
	var hinted := worm.call(&"get_body") != null and (worm.call(&"get_body") as Node).find_child(WeaponDazeHint.CUE_NAME, true, false) != null
	var hint_text := _texts_with("Dazed!")
	# Q sucks it up: the slime walks up to it, faces it, presses Q.
	var feet := _feet_of(worm)
	_place_slime(feet + Vector2(-60.0, 0.0), Vector2.RIGHT)
	await _run(2)
	var player: Node = Services.world().player
	var mouth: RefCounted = player.call(&"get_mouth")
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	var held_kind := ""
	for i in 60:
		await _tick()
		_hold(brawler)
		if bool(mouth.call(&"is_holding")):
			held_kind = str((player.call(&"held") as Dictionary).get("kind", ""))
			break
	await _run(10)
	# Q throws it at the Brawler (to the left).
	_place_enemy(brawler, Services.world().player_body.global_position + Vector2(-170.0, 0.0))
	player.call(&"face", Vector2.LEFT)
	await _tick()
	var brawler_before := _hp(brawler)
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	for i in 80:
		await _tick()
		_hold(brawler)
	var dealt := brawler_before - _hp(brawler)
	await _end(helpless_at >= 0 and held_kind == "enemy" and dealt > 0.0, {"helpless_after_finisher_frames": helpless_at,
		"held": held_kind, "brawler_hurt": snappedf(dealt, 0.1), "hint_pointer": hinted, "hint_line": hint_text,
		"window_ms": Services.constants().number("combat.rules.weaponDaze.windowMs")})


func _film_taps() -> void:
	_begin("taps", "3  Three plain taps on the Swordsman:  A  .  A  .  A  (never liftable)")
	ThrowMode.set_dev_level(2)
	await _fresh_pen()
	_restore_slime()
	var worm: Node = _enemies[SWORDSMAN]
	var spot := _pen_point(0.5, 0.55)
	_place_enemy(worm, spot + Vector2(78.0, 0.0))
	_park(BRAWLER)
	_remove(CLOD)
	_place_slime(spot, Vector2.RIGHT)
	await _run(10)
	var ever_helpless := false
	var ever_pending := false
	var steps: Array = []
	for tap in 3:
		_push(&"attack", true)
		await _run(2)
		_push(&"attack", false)
		# The step that tap started (a tap waits out a finisher's rest before it strikes).
		for i in 30:
			await _tick()
			if bool(_shapes.call(&"is_busy")):
				break
		steps.append(int(_shapes.get(&"_index")))
		for i in PLAIN_GAP_FRAMES:
			await _tick()
			_hold(worm, spot + Vector2(78.0, 0.0))
			ever_helpless = ever_helpless or EnemyReactions.is_helpless(worm)
			ever_pending = ever_pending or EnemyReactions.state_of(worm).weapon_daze_ms > 0.0
	for i in 90:
		await _tick()
		ever_helpless = ever_helpless or EnemyReactions.is_helpless(worm)
	await _end(not ever_helpless and not ever_pending and steps == [0, 0, 0], {"chain_steps": steps,
		"ever_helpless": ever_helpless, "ever_pending": ever_pending})


func _film_charge() -> void:
	_begin("charge", "4  The Lunge on the Swordsman:  hold A through the ring, let go")
	ThrowMode.set_dev_level(2)
	await _fresh_pen()
	_restore_slime()
	_shapes.call(&"set_current", ShapeDefs.SPEAR)
	var worm: Node = _enemies[SWORDSMAN]
	var spot := _pen_point(0.35, 0.55)
	_place_enemy(worm, spot + Vector2(110.0, 0.0))
	_park(BRAWLER)
	_remove(CLOD)
	_place_slime(spot, Vector2.RIGHT)
	await _run(10)
	var hold_ms := ShapeDefs.chain_number("chargeStartMs") + ShapeDefs.num(ShapeDefs.charge(ShapeDefs.SPEAR), "ringMs") + 200.0
	_push(&"attack", true)
	for i in int(hold_ms / 1000.0 * 60.0):
		await _tick()
		_hold(worm, spot + Vector2(110.0, 0.0))
	_push(&"attack", false)
	var helpless_at := -1
	for i in WATCH_FRAMES:
		await _tick()
		if helpless_at < 0 and EnemyReactions.is_helpless(worm):
			helpless_at = i
	await _run(20)
	await _end(helpless_at >= 0, {"helpless_after_release_frames": helpless_at})


func _film_hammer() -> void:
	_begin("hammer", "5  The Hammer:  a lone thud (A) never,  thud BOOM (A A) does")
	ThrowMode.set_dev_level(2)
	await _fresh_pen()
	_restore_slime()
	_shapes.call(&"set_current", ShapeDefs.HAMMER)
	var worm: Node = _enemies[SWORDSMAN]
	var spot := _pen_point(0.5, 0.55)
	var post := spot + Vector2(68.0, 0.0)
	_place_enemy(worm, post)
	# A thud and a BOOM (18 + 27) kill a 40-health swordsman outright: it gets more for this check.
	worm.set(&"max_health", 200.0)
	worm.call(&"_restore_health", 200.0)
	_remove(BRAWLER)
	_remove(CLOD)
	_place_slime(spot, Vector2.RIGHT)
	await _run(10)
	var state := EnemyReactions.state_of(worm)
	_push(&"attack", true)
	await _run(2)
	_push(&"attack", false)
	var thud_set_up := false
	for i in 90:
		await _tick()
		thud_set_up = thud_set_up or EnemyReactions.is_helpless(worm) or state.weapon_daze_ms > 0.0
	_place_enemy(worm, post)
	_place_slime(spot, Vector2.RIGHT)
	await _run(10)
	_push(&"attack", true)
	await _run(2)
	_push(&"attack", false)
	for i in 24:
		await _tick()
	_push(&"attack", true)
	await _run(2)
	_push(&"attack", false)
	var helpless_at := -1
	for i in WATCH_FRAMES + 30:
		await _tick()
		if helpless_at < 0 and EnemyReactions.is_helpless(worm):
			helpless_at = i
	await _end(not thud_set_up and helpless_at >= 0, {"lone_thud_set_up": thud_set_up,
		"helpless_after_boom_frames": helpless_at})


func _film_heavy() -> void:
	_begin("heavy", "6  Gulp 3:  Spear combos on the Clod Stomper (heavy):  liftable only once its poise breaks")
	# Since piece 4 the Clod is iron (only the Hammer hurts it, and the Hammer's smash staggers a heavy
	# enemy without draining its poise): the heavy check strikes the Thorn Guard (bark) with the Axe.
	await _film_heavy_guard()


func _film_heavy_guard() -> void:
	_checks[_checks.size() - 1]["caption"] = "6  Gulp 3:  Axe combos on the Thorn Guard (heavy):  liftable only once its poise breaks"
	_caption.text = str(_checks[_checks.size() - 1]["caption"])
	ThrowMode.set_dev_level(3)
	_restore_slime()
	_shapes.call(&"set_current", ShapeDefs.AXE)
	var spot := _pen_point(0.5, 0.55)
	var spawned := Services.world().spawn_at_phaser_position("character.thorn-guard", spot + Vector2(58.0, -28.0))
	var guard: Node = null
	if spawned != null:
		for child: Node in spawned.get_children():
			if child.has_method(&"wake"):
				guard = child
	if guard == null:
		await _end(false, {"error": "no Thorn Guard"})
		return
	# Enough health to live through every combo the check gives it.
	guard.set(&"max_health", 1000.0)
	guard.call(&"_restore_health", 1000.0)
	_remove(SWORDSMAN)
	_remove(BRAWLER)
	_remove(CLOD)
	_place_slime(spot, Vector2.RIGHT)
	guard.call(&"wake", Services.now_ms())
	for i in 180:
		await _tick()
		if not ["asleep", "wake"].has(str(guard.get(&"_phase"))):
			break
	var post := spot + Vector2(58.0, 0.0)
	var state := EnemyReactions.state_of(guard)
	var breaks: Array = []
	var helpless_before_break := false
	var helpless_after_break := false
	for combo in 4:
		_place_enemy(guard, post)
		_place_slime(spot, Vector2.RIGHT)
		await _run(4)
		for tap in 3:
			var poise_before := state.poise
			_push(&"attack", true)
			await _run(2)
			_push(&"attack", false)
			for i in (RHYTHM_FRAMES if tap < 2 else 70):
				await _tick()
				if state.poise > poise_before + 0.5 and poise_before >= 0.0:
					breaks.append({"combo": combo, "step": tap})
					poise_before = state.poise
				var helpless := EnemyReactions.is_helpless(guard)
				helpless_before_break = helpless_before_break or (helpless and breaks.is_empty())
				helpless_after_break = helpless_after_break or (helpless and not breaks.is_empty())
		if helpless_after_break:
			break
	var finisher_broke := false
	for entry: Dictionary in breaks:
		finisher_broke = finisher_broke or int(entry["step"]) == 2
	await _run(30)
	await _end(helpless_after_break and not helpless_before_break and finisher_broke, {"enemy": "thorn-guard",
		"weapon": "axe", "breaks": breaks, "helpless_before_break": helpless_before_break,
		"helpless_after_break": helpless_after_break})


func _film_boss() -> void:
	_begin("boss", "7  A combo on the boss-preset dummy:  never dazed")
	_restore_slime()
	var dummy := _dummy(BOSS_DUMMY)
	if dummy == null:
		await _end(false, {"error": "no boss dummy"})
		return
	var body := dummy.call(&"get_body") as Node2D
	var feet := body.global_position
	_place_slime(feet + Vector2(-78.0, 0.0), Vector2.RIGHT)
	await _run(10)
	var state := EnemyReactions.state_of(dummy)
	var pending := false
	var dazed := false
	for tap in 3:
		_push(&"attack", true)
		await _run(2)
		_push(&"attack", false)
		for i in (RHYTHM_FRAMES if tap < 2 else 90):
			await _tick()
			pending = pending or state.weapon_daze_ms > 0.0
			dazed = dazed or (state.verb == "daze" and state.throw_helpless)
	var profile_weight := str(dummy.get(&"reaction_preset"))
	await _end(not pending and not dazed and profile_weight == "boss", {"preset": profile_weight, "pending": pending,
		"dazed": dazed})


func _film_too_heavy() -> void:
	_begin("too-heavy", "2  Gulp 1:  A A A on the Swordsman (medium):  dazed,  but Q refuses it")
	ThrowMode.set_dev_level(1)
	await _fresh_pen()
	_restore_slime()
	_shapes.call(&"set_current", ShapeDefs.SPEAR)
	var worm: Node = _enemies[SWORDSMAN]
	var spot := _pen_point(0.5, 0.55)
	_place_enemy(worm, spot + Vector2(78.0, 0.0))
	_park(BRAWLER)
	_remove(CLOD)
	_place_slime(spot, Vector2.RIGHT)
	await _run(10)
	var watch := await _combo(worm, false)
	var dazed := int(watch.get("helpless_frame", -1)) >= 0
	var gulpable: Node = (worm.call(&"get_body") as Node).get_node_or_null("GulpableEnemy") if worm.call(&"get_body") != null else null
	var too_heavy := gulpable != null and bool(gulpable.call(&"is_too_heavy"))
	var feet := _feet_of(worm)
	_place_slime(feet + Vector2(-60.0, 0.0), Vector2.RIGHT)
	await _run(2)
	var player: Node = Services.world().player
	var mouth: RefCounted = player.call(&"get_mouth")
	var found := mouth.call(&"find_too_heavy", Vector2.RIGHT) != null
	var hp_before := float((player.call(&"get_damage_state") as Dictionary).get("hp", 0.0))
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	var sucked := false
	var line := ""
	var seen: Array = []
	for i in 70:
		await _tick()
		sucked = sucked or bool(mouth.call(&"is_sucking"))
		for text: String in _all_texts():
			if not seen.has(text):
				seen.append(text)
		if line.is_empty():
			line = _texts_with(TOO_HEAVY_WORDS)
	var held := bool(mouth.call(&"is_holding"))
	await _run(20)
	await _end(dazed and too_heavy and not held and not line.is_empty(), {"dazed": dazed, "too_heavy": too_heavy,
		"held": held, "line": line, "texts_seen": seen, "gulp_level": ThrowMode.gulp_level(),
		"still_helpless": EnemyReactions.is_helpless(worm), "found_before_press": found, "sucked": sucked,
		"slime_hurt": hp_before - float((player.call(&"get_damage_state") as Dictionary).get("hp", 0.0))})


## A Spear combo in rhythm on `worm` (held at its spot until the finisher), then watching for the daze.
## Returns {"helpless_frame": frames after the finisher's press until it was helpless (-1: never)}.
func _combo(worm: Node, _first: bool) -> Dictionary:
	var at := _feet_of(worm)
	for tap in 3:
		_push(&"attack", true)
		await _run(2)
		_push(&"attack", false)
		if tap < 2:
			for i in RHYTHM_FRAMES:
				await _tick()
				_hold(worm, at)
	var helpless_frame := -1
	for i in WATCH_FRAMES:
		await _tick()
		if helpless_frame < 0 and EnemyReactions.is_helpless(worm):
			helpless_frame = i
			break
	return {"helpless_frame": helpless_frame}


# --- staging ----------------------------------------------------------------------------------------

func _begin(id: String, caption: String) -> void:
	_camera_zoom()
	_shapes.call(&"reset_chain", "film")
	_check = id
	_caption.text = caption
	_checks.append({"id": id, "caption": caption, "from_frame": _index, "pass": false, "notes": {}})


func _end(ok: bool, notes: Dictionary) -> void:
	var check: Dictionary = _checks[_checks.size() - 1]
	check["pass"] = ok
	check["notes"] = notes
	check["to_frame"] = _index
	_caption.text += "      %s" % ("PASS" if ok else "FAIL")
	await _run(24)


func _pen_point(x_share: float, y_share: float) -> Vector2:
	var rect: Rect2 = _testbed.get(&"_pen_rect")
	return rect.position + rect.size * Vector2(x_share, y_share)


func _feet_of(enemy: Variant) -> Vector2:
	if not is_instance_valid(enemy):
		return Vector2.ZERO
	var body: Variant = (enemy as Object).call(&"get_body") if (enemy as Object).has_method(&"get_body") else enemy
	return (body as Node2D).global_position


func _place_enemy(enemy: Variant, feet: Vector2) -> void:
	if not is_instance_valid(enemy):
		return
	var body: Variant = (enemy as Object).call(&"get_body")
	if not body is Node2D:
		return
	(body as Node2D).global_position = feet
	(body as Node2D).reset_physics_interpolation()
	if (enemy as Object).has_method(&"set_home"):
		(enemy as Object).call(&"set_home", (enemy as Object).call(&"get_centre"))


## Keeps `enemy` near `feet` (it would walk at the slime); its reactions play (a knock is let be).
func _hold(enemy: Variant, feet: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(enemy):
		return
	var at := feet if feet != Vector2.INF else _feet_of(enemy)
	if _feet_of(enemy).distance_to(at) > 60.0 and not EnemyReactions.state_of(enemy as Node).in_stun(Services.now_ms()):
		_place_enemy(enemy, at)


## An enemy out of the film (it would walk into the throws): taken out of the pen until `_fresh_pen`.
func _remove(type: String) -> void:
	for slot: Dictionary in _testbed.get(&"pen"):
		if str(slot.get("type", "")) == type and is_instance_valid(slot.get("root")):
			(slot.get("root") as Node).queue_free()
	_enemies.erase(type)


## An enemy out of the way: far in the pen's corner.
func _park(type: String) -> void:
	if _enemies.has(type):
		_place_enemy(_enemies[type], _pen_point(0.92, 0.12) if type != CLOD else _pen_point(0.08, 0.12))


func _restore_slime() -> void:
	var player: Node = Services.world().player
	player.call(&"restore_run_state", {"hp": player.call(&"get_max_hp")})
	player.call(&"set_energy", 100.0)


func _place_slime(feet: Vector2, facing: Vector2) -> void:
	var world := Services.world()
	var player: Node = world.player
	var body := world.player_body
	player.call(&"teleport", feet + ((player.call(&"get_centre") as Vector2) - body.global_position))
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	player.call(&"face", facing)


func _camera_zoom() -> void:
	var camera: Node = Services.world().camera
	if camera != null and camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", 2.0)


func _hp(enemy: Variant) -> float:
	if not is_instance_valid(enemy) or not (enemy as Object).has_method(&"get_damage_state"):
		return 0.0
	return float(((enemy as Object).call(&"get_damage_state") as Dictionary).get("hp", 0.0))


func _dummy(name: String) -> Node:
	var dummy_root := root.find_child(name, true, false)
	if dummy_root == null:
		return null
	for node: Node in dummy_root.find_children("*", "", true, false):
		if node.get_script() == TrainingDummyScript:
			return node
	return null


func _all_texts() -> Array:
	var out: Array = []
	var feel := Services.feel()
	var layer: Node = feel.get_node_or_null(^"FloatingTextLayer") if feel != null else null
	if layer != null:
		for child: Node in layer.find_children("*", "Label", true, false):
			out.append((child as Label).text)
	return out


## The first floating text that holds `words` ("" for none).
func _texts_with(words: String) -> String:
	var feel := Services.feel()
	var layer: Node = feel.get_node_or_null(^"FloatingTextLayer") if feel != null else null
	if layer == null:
		return ""
	for child: Node in layer.find_children("*", "Label", true, false):
		var text := (child as Label).text
		if text.contains(words):
			return text
	return ""


# --- running ----------------------------------------------------------------------------------------

func _run(frames: int) -> void:
	for i in frames:
		await _tick()


func _tick() -> void:
	await physics_frame
	_step += 1
	if _step % _every != 0:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	_rows.append({"check": _check})
	_index += 1


func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

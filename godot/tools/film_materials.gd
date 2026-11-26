extends SceneTree
## Films piece 4 of the one combat (docs/design/2026-11-25-weapons-beside-throws.md; BESTIARY.md
## "Materials"): what a hit meets. In the playground's Bestiary pens, frame by frame, with the game's camera
## and HUD and the keys (each press sent as the key's action), one check per material, each with a PASS or
## FAIL: every weapon its material refuses clinks (the enemy unhurt) with its line the first time; one
## weapon it takes hurts; and for the three one-weapon materials (bark, iron, eye) a thrown pot hurts it
## too (the owner, 2026-11-26: the rule is only for weapons) and the right weapon kills what is left.
## Run windowed (it renders), one game window at a time:
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_materials.gd -- \
##         --out=<dir> [--every=<n>] [--only=<material,...>]
## Writes <dir>/f<nnn>.png and <dir>/film.json; `scripts/godot/one-combat-sheet.py <dir>` lays it out.

const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const HitMaterials := preload("res://game/combat/reactions/hit_materials.gd")
const KeyBindings := preload("res://game/player/mouse/key_bindings.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const WINDOW := Vector2i(1280, 800)
const WATCHDOG_S := 900.0
## One case per material: the enemy type filmed (in its Bestiary pen), the weapon it takes (a tag), and the
## phase it is held in while struck (`hold`: its own rule shields it in its others, which the film is not
## about; "" for none); `one_weapon` for the three one-weapon materials (one of the three weapons hurts
## them), which also take a pot and are killed by their weapon.
const CASES: Array[Dictionary] = [
	{"material": "flesh", "type": "worm-swordsman", "hurt": "spear", "hold": ""},
	{"material": "shell", "type": "shardback", "hurt": "crush", "hold": ""},
	{"material": "bone", "type": "bone-marcher", "hurt": "cut", "hold": ""},
	{"material": "crystal", "type": "rock-chucker", "hurt": "spear", "hold": "", "spawn_in": "crystal-mite"},
	{"material": "silk", "type": "silk-lurker", "hurt": "cut", "hold": "down"},
	{"material": "plant", "type": "thornball", "hurt": "cut", "hold": "idle"},
	{"material": "untouchable", "type": "carnivore-plant", "hurt": "thrown", "hold": ""},
	{"material": "bark", "type": "thorn-guard", "hurt": "cut", "hold": "", "one_weapon": true},
	{"material": "iron", "type": "clod-stomper", "hurt": "crush", "hold": "", "one_weapon": true},
	{"material": "eye", "type": "squint", "hurt": "spear", "hold": "open", "one_weapon": true},
]
const SHAPE_OF := {"spear": ShapeDefs.SPEAR, "cut": ShapeDefs.AXE, "crush": ShapeDefs.HAMMER}
## How far ahead of the slime's feet the enemy stands for each weapon (inside its reach).
const AHEAD_OF := {"spear": 80.0, "cut": 58.0, "crush": 70.0, "thrown": 90.0}
## The phases that count as hurt where the health does not drop (the Bone Marcher falls to a pile).
const FALLEN_PHASES: Array[String] = ["pile"]
## Frames a single strike is watched for, and the frames between taps in rhythm.
const STRIKE_FRAMES := 40
const RHYTHM_FRAMES := 15
## How many combos the right weapon gets to kill a one-weapon enemy.
const KILL_COMBOS := 14
const POT := "clay-pot"
const AMMO_BEHIND_PX := 34.0

var _main: Node
var _out := "user://materials"
var _every := 2
var _only: PackedStringArray = []
var _index := 0
var _step := 0
var _check := ""
var _rows: Array = []
var _checks: Array = []
var _shapes: Node = null
var _caption: Label = null
## The enemy held in a phase while the film strikes it, and that phase ("" for none).
var _held: Node = null
var _hold_phase := ""


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
		push_error("film_materials: gave up after %d s" % int(WATCHDOG_S))
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
	if not KeyBindings.is_applied():
		KeyBindings.apply(true)
	_shapes = _main.get(&"shapes")
	var layer := CanvasLayer.new()
	layer.layer = 100
	_caption = Label.new()
	_caption.position = Vector2(24.0, 18.0)
	_caption.add_theme_font_size_override(&"font_size", 24)
	_caption.add_theme_color_override(&"font_color", Color.WHITE)
	_caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(_caption)
	root.add_child(layer)
	ThrowMode.set_dev_level(3)
	for case: Dictionary in CASES:
		if _only.is_empty() or _only.has(str(case["material"])):
			await _film_case(case)
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": _index, "every": _every, "checks": _checks, "rows": _rows}, "\t"))
	file.close()
	for check: Dictionary in _checks:
		print("film_materials: ", "PASS " if bool(check["pass"]) else "FAIL ", check["id"], " ", JSON.stringify(check["notes"]))
	quit()


# --- one material -----------------------------------------------------------------------------------

func _film_case(case: Dictionary) -> void:
	var material := str(case["material"])
	var type := str(case["type"])
	var refuses: Array = HitMaterials.row(material).get("refuses", [])
	var one_weapon := bool(case.get("one_weapon", false))
	var hurt := str(case["hurt"])
	var words := "%s (%s):  %s clink%s,  %s hurts" % [material, type, ", ".join(refuses.map(_weapon_name)),
		"" if refuses.size() == 1 else "", _weapon_name(hurt)]
	if refuses.size() == 3:
		words = "%s (%s):  %s clink;  a throw meets its own rule" % [material, type, ", ".join(refuses.map(_weapon_name))]
	if refuses.is_empty():
		words = "%s (%s):  every weapon hurts" % [material, type]
	if one_weapon:
		words += ",  a pot hurts it,  %s kills it" % _weapon_name(hurt)
	_begin(material, "%d  %s" % [CASES.find(case) + 1, words])
	# A type with no pen of its own (the Rock Chucker stands on rims) is spawned in another's.
	var host := str(case.get("spawn_in", type))
	var pen := _pen_of(host)
	if pen == null:
		await _end(false, {"error": "no pen for %s" % host})
		return
	pen.call(&"respawn")
	await _run(6)
	var enemy: Node = null
	if host != type:
		for other: Node in pen.call(&"living"):
			_park_away(other)
		var rect_in: Rect2 = pen.call(&"pen_rect")
		var spawned := Services.world().spawn_at_phaser_position("character." + type, rect_in.get_center())
		if spawned != null:
			for child: Node in spawned.get_children():
				if child.has_method(&"get_damage_state"):
					enemy = child
		await _run(6)
	else:
		enemy = _enemy_of(pen, type)
	if enemy == null:
		await _end(false, {"error": "no %s in its pen" % type})
		return
	var rect: Rect2 = pen.call(&"pen_rect")
	var spot := rect.position + rect.size * Vector2(0.35, 0.55)
	var post := spot + Vector2(AHEAD_OF["spear"], 0.0)
	_hold_phase = str(case.get("hold", ""))
	_held = enemy
	# A sleeping statue is woken first (asleep or waking it is shielded: its own rule).
	if type == "thorn-guard":
		_place_enemy(enemy, post)
		_place_slime(spot, Vector2.RIGHT)
		enemy.call(&"wake", Services.now_ms())
		for i in 150:
			await _tick()
			if not ["asleep", "wake"].has(str(enemy.get(&"_phase"))):
				break
	_calm(enemy)
	var found_material := HitMaterials.of(ReactionProfile.for_enemy(enemy))
	var notes := {"type": type, "hit_material": found_material}
	var ok := found_material == material
	# Every weapon the material refuses: a clink, the enemy unhurt, its line the first time.
	var clinks := {}
	for tag: String in refuses:
		var flag := "%s%s.%s" % [HitMaterials.FLAG_PREFIX, material, tag]
		var result := await _strike_once(enemy, tag, spot, post)
		# A blow that missed a moving enemy (no clink, no line) is tried again, twice at most.
		for again in 2:
			if Services.run().has_flag(flag) or bool(result["hurt"]):
				break
			result = await _strike_once(enemy, tag, spot, post)
		var line := HitMaterials.line(material, tag)
		var said := Services.run().has_flag(flag)
		clinks[tag] = {"hurt": result["hurt"], "line_shown": said, "line": line}
		ok = ok and not bool(result["hurt"]) and said
	notes["clinks"] = clinks
	# One weapon (or, untouchable, a throw) it takes.
	if refuses.size() < 3:
		var result := await _strike_once(enemy, hurt, spot, post)
		# A blow that missed a moving enemy (a marching Thorn Guard) is tried again, twice at most, as above.
		for again in 2:
			if bool(result["hurt"]):
				break
			result = await _strike_once(enemy, hurt, spot, post)
		result["phase"] = str(enemy.get(&"_phase")) if is_instance_valid(enemy) else "gone"
		notes["takes_" + hurt] = result
		ok = ok and bool(result["hurt"])
	if not one_weapon and refuses.size() == 3:
		# What a throw does is the enemy's own rule here (the Carnivore Plant dozes off and only fire kills
		# her; a throw bounces off the Jelly): reported, not judged.
		var thrown := await _throw_pot(enemy, spot, post)
		notes["thrown_info"] = thrown
		notes["phase_after_throw"] = str(enemy.get(&"_phase")) if is_instance_valid(enemy) else "gone"
	if one_weapon:
		var thrown := await _throw_pot(enemy, spot, post)
		notes["pot"] = thrown
		ok = ok and bool(thrown["hurt"])
		# A pot may end a small one (a Squint's 32): then there is nothing left for the weapon.
		if _alive(enemy):
			var killed := await _kill_with(enemy, hurt, spot, post)
			notes["killed_by_" + hurt] = killed
			ok = ok and bool(killed["dead"])
		else:
			notes["killed_by_pot"] = true
			_caption.text = _caption.text.replace("%s kills it" % _weapon_name(hurt), "the pot kills it")
			_checks[_checks.size() - 1]["caption"] = _caption.text
	_held = null
	_hold_phase = ""
	await _end(ok, notes)


## One tap of `tag`'s weapon on `enemy` standing at `post`, the slime at `spot` facing it. {"hurt",
## "hp_before", "hp_after"}.
func _strike_once(enemy: Node, tag: String, spot: Vector2, post: Vector2) -> Dictionary:
	_restore_slime()
	_shapes.call(&"reset_chain", "film")
	_shapes.call(&"set_current", SHAPE_OF[tag])
	_place_enemy(enemy, spot + Vector2(AHEAD_OF[tag], 0.0))
	_place_slime(spot, Vector2.RIGHT)
	await _run(14)
	var before := _hp(enemy)
	_push(&"attack", true)
	await _run(2)
	_push(&"attack", false)
	var fell := false
	for i in STRIKE_FRAMES:
		await _tick()
		fell = fell or (is_instance_valid(enemy) and FALLEN_PHASES.has(str(enemy.get(&"_phase"))))
	var after := _hp(enemy)
	return {"hurt": after < before - 0.01 or fell or not _alive(enemy), "fell": fell, "hp_before": before,
		"hp_after": after}


## A clay pot sucked in behind the slime and thrown at `enemy`. {"hurt", "stunned" (a daze, knockdown or
## stagger in force after it), "liftable" (helpless for the Gulp), "hp_before", "hp_after"}.
func _throw_pot(enemy: Node, spot: Vector2, post: Vector2) -> Dictionary:
	_restore_slime()
	_place_enemy(enemy, post + Vector2(60.0, 0.0))
	_place_slime(spot, Vector2.LEFT)
	var player: Node = Services.world().player
	var mouth: RefCounted = player.call(&"get_mouth")
	ThrowAmmo.spawn_liftable(POT, Services.world().player_body.global_position + Vector2.LEFT * AMMO_BEHIND_PX,
		{"pop": false})
	await _run(6)
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	for i in 50:
		await _tick()
		if bool(mouth.call(&"is_holding")):
			break
	await _run(8)
	player.call(&"face", Vector2.RIGHT)
	await _tick()
	var before := _hp(enemy)
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	var stunned := false
	var liftable := false
	for i in 60:
		await _tick()
		if not is_instance_valid(enemy):
			break
		var state := EnemyReactions.state_of(enemy)
		stunned = stunned or (["daze", "knockdown", "stagger"].has(state.verb) and state.in_stun(Services.now_ms()))
		liftable = liftable or EnemyReactions.is_helpless(enemy)
	var after := _hp(enemy)
	return {"hurt": after < before - 0.01, "stunned": stunned, "liftable": liftable, "hp_before": before,
		"hp_after": after}


## Combos of `tag`'s weapon until `enemy` dies (at most KILL_COMBOS). {"dead", "combos"}.
func _kill_with(enemy: Node, tag: String, spot: Vector2, post: Vector2) -> Dictionary:
	_restore_slime()
	_shapes.call(&"reset_chain", "film")
	_shapes.call(&"set_current", SHAPE_OF[tag])
	var combos := 0
	for combo in KILL_COMBOS:
		if not _alive(enemy):
			break
		combos += 1
		_place_enemy(enemy, spot + Vector2(AHEAD_OF[tag], 0.0))
		_place_slime(spot, Vector2.RIGHT)
		await _run(6)
		for tap in ShapeDefs.step_count(SHAPE_OF[tag]):
			_push(&"attack", true)
			await _run(2)
			_push(&"attack", false)
			for i in RHYTHM_FRAMES:
				await _tick()
		for i in 50:
			await _tick()
			if not _alive(enemy):
				break
	await _run(20)
	return {"dead": not _alive(enemy), "combos": combos}


# --- staging ----------------------------------------------------------------------------------------

func _weapon_name(tag: Variant) -> String:
	return {"spear": "Spear", "cut": "Axe", "crush": "Hammer", "thrown": "a throw"}.get(str(tag), str(tag))


func _pen_of(type: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		if node.has_method(&"living") and node.has_method(&"pen_rect"):
			var types: Variant = node.get(&"enemy_types")
			if types is PackedStringArray and (types as PackedStringArray).has(type):
				return node
	return null


func _enemy_of(pen: Node, type: String) -> Node:
	for enemy: Node in pen.call(&"living"):
		if ReactionProfile.type_of(enemy) == type:
			return enemy
	var all: Array = pen.call(&"living")
	return all[0] if not all.is_empty() else null


## An enemy that is not filmed: out of the way, far off.
func _park_away(enemy: Node) -> void:
	var body: Variant = enemy.call(&"get_body") if enemy.has_method(&"get_body") else null
	if body is Node2D:
		(body as Node2D).global_position += Vector2(0.0, 2000.0)
		enemy.set_physics_process(false)


## The enemy stands and fights nothing (the film strikes it on its post).
func _calm(enemy: Node) -> void:
	for property: StringName in [&"targeting_radius", &"attack_range"]:
		if property in enemy:
			enemy.set(property, 0.0)
	if &"_next_stomp_at" in enemy:
		enemy.set(&"_next_stomp_at", INF)


func _alive(enemy: Variant) -> bool:
	return is_instance_valid(enemy) and not bool((enemy as Object).call(&"is_defeated"))


func _begin(id: String, caption: String) -> void:
	var camera: Node = Services.world().camera
	if camera != null and camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", 2.0)
	_check = id
	_caption.text = caption
	_checks.append({"id": id, "caption": caption, "from_frame": _index, "pass": false, "notes": {}})


func _end(ok: bool, notes: Dictionary) -> void:
	var check: Dictionary = _checks[_checks.size() - 1]
	check["pass"] = ok
	check["notes"] = notes
	check["to_frame"] = _index
	_caption.text += "      %s" % ("PASS" if ok else "FAIL")
	await _run(20)


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
	# The camera snaps to the slime (it would glide over from the last pen and show the wrong one).
	var camera: Node = world.camera
	if camera != null and camera.has_method(&"start_follow"):
		camera.call(&"start_follow", body, true)


func _hp(enemy: Variant) -> float:
	if not is_instance_valid(enemy) or not (enemy as Object).has_method(&"get_damage_state"):
		return 0.0
	return float(((enemy as Object).call(&"get_damage_state") as Dictionary).get("hp", 0.0))


func _run(frames: int) -> void:
	for i in frames:
		await _tick()


func _tick() -> void:
	if _held != null and is_instance_valid(_held) and not _hold_phase.is_empty() and _alive(_held) \
			and not EnemyReactions.state_of(_held).in_stun(Services.now_ms()):
		_held.set(&"_phase", _hold_phase)
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

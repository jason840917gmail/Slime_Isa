extends SceneTree
## Films the one combat (docs/design/2026-11-25-weapons-beside-throws.md piece 2; THROW_COMBAT.md "One
## combat") in the playground's enemy pen, frame by frame, with the game's own camera, HUD and keys
## (the keys-only layout), each press sent as the key's action. Five checks, each with a PASS or FAIL:
##   combo   A A A: the Spear's combo on the Worm Swordsman, each hit the weapon's scaled damage
##           (ShapeDefs.damage: base x attack / 10 x the step's scale x `shapes.weaponDamageScale`)
##   throw   Q, Q: a clay pot sucked up and thrown at the Worm Brawler (the throw rules: its weight's
##           damage, untouched by the weapon scale)
##   switch  E: the weapon goes from the Spear to the War Axe, and the HUD's weapon slot shows the Axe
##   charge  A held through the ring with no energy at all, then let go: the Spin fires, energy stays 0
##   ability B, a pick in the bag's Abilities row (its name floats over the slime), B, then D: it is used
## Then four stills for the owner: the HUD, the bag (the Weapons and Abilities rows with their keys), the
## Controls list and the Settings window (no scheme row since piece 5). Run windowed (it renders), one game window at a time:
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_one_combat.gd -- \
##         --out=<dir> [--every=<n>] [--zoom=<z>]
## Writes <dir>/f<nnn>.png (frames), <dir>/hud.png, bag.png, controls.png, settings.png and <dir>/film.json (the checks,
## their notes, and per frame the check running). `scripts/godot/one-combat-sheet.py` makes the strip and
## the GIFs.

const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const BodyCards := preload("res://game/ui/body_cards.gd")
const KeyBindings := preload("res://game/player/mouse/key_bindings.gd")
const ShapeControllerScript := preload("res://game/shapes/shape_controller.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const WINDOW := Vector2i(1280, 800)
const WATCHDOG_S := 400.0
## The pen's enemies kept for the film; the others leave (they would join the fight).
const KEEP_TYPES: Array[String] = ["worm-swordsman", "worm-brawler"]
const SWORDSMAN := "worm-swordsman"
const BRAWLER := "worm-brawler"
## Where a thing to throw is put, behind the slime's feet.
const AMMO_BEHIND_PX := 34.0
## The ability picked in the bag (one the playground lends, not the first in the box).
const PICK_ORDER: Array[StringName] = [&"goo-bombs", &"squash-slam", &"lantern", &"bow"]
## The training dummy the charge strikes (the shapes testbed's).
const DUMMY_NAME := "shapes-dummy-medium"
const TrainingDummyScript := preload("res://game/scripts/training_dummy.gd")

var _main: Node
var _out := "user://one-combat"
var _every := 2
var _zoom := 2.0
var _index := 0
var _step := 0
var _check := ""
var _rows: Array = []
var _checks: Array = []
var _testbed: Node = null
var _shapes: Node = null
var _caption: Label = null
var _swordsman: Node = null
var _brawler: Node = null


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--every="):
			_every = maxi(1, int(arg.trim_prefix("--every=")))
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_one_combat: gave up after %d s" % int(WATCHDOG_S))
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
	await _film_combo()
	await _film_throw()
	await _film_switch()
	await _film_charge()
	await _film_ability()
	await _stills()
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": _index, "every": _every, "checks": _checks, "rows": _rows}, "\t"))
	file.close()
	for check: Dictionary in _checks:
		print("film_one_combat: ", "PASS " if bool(check["pass"]) else "FAIL ", check["id"], " ", JSON.stringify(check["notes"]))
	quit()


func _setup() -> bool:
	# The keys-only layout (the owner's scheme), so the badges and the Controls list read as he plays.
	if not KeyBindings.is_applied():
		KeyBindings.apply(true)
	_testbed = root.find_child("ShapesTestbed", true, false)
	_shapes = _main.get(&"shapes")
	if _testbed == null or _shapes == null:
		push_error("film_one_combat: no testbed or no shapes")
		return false
	_testbed.set(&"pen_respawn_ms", 1.0e9)
	for i in 30:
		await physics_frame
	if not await _fresh_pen():
		return false
	_shapes.call(&"set_current", ShapeDefs.SPEAR)
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
	_camera_zoom()
	return true


## The pen anew (the testbed's F4), with only the Swordsman and the Brawler kept.
func _fresh_pen() -> bool:
	_swordsman = null
	_brawler = null
	_testbed.call(&"respawn_pen")
	for i in 6:
		await physics_frame
	for slot: Dictionary in _testbed.get(&"pen"):
		var enemy: Variant = slot.get("enemy")
		var type := str(slot.get("type", ""))
		if not is_instance_valid(enemy):
			continue
		if type == SWORDSMAN:
			_swordsman = enemy
		elif type == BRAWLER:
			_brawler = enemy
		elif not KEEP_TYPES.has(type):
			var root_node: Variant = slot.get("root")
			if is_instance_valid(root_node):
				(root_node as Node).queue_free()
	if _swordsman == null or _brawler == null:
		push_error("film_one_combat: the pen has no swordsman or brawler")
		return false
	return true


# --- the checks -------------------------------------------------------------------------------------

func _film_combo() -> void:
	_begin("combo", "1  Spear combo on the Worm Swordsman:  A  A  A")
	_restore_slime()
	_hold_enemy(_brawler, _pen_point(0.85, 0.8))
	var feet := _feet_of(_swordsman)
	_place_slime(feet + Vector2(-78.0, 0.0), Vector2.RIGHT)
	_hold_enemy(_swordsman, feet)
	await _run(10)
	var hp_before := _hp(_swordsman)
	var drops: Array = []
	var last := hp_before
	# Taps in rhythm: each one as the step before reaches its cancel point (the link window is open).
	for tap in 3:
		_push(&"attack", true)
		await _run(2)
		_push(&"attack", false)
		var frames := 15 if tap < 2 else 50
		for i in frames:
			await _tick()
			var now_hp := _hp(_swordsman)
			if now_hp < last:
				drops.append(snappedf(last - now_hp, 0.1))
				last = now_hp
			_hold_enemy(_swordsman, feet)
	await _run(30)
	var expected: Array = []
	for step_index in 3:
		expected.append(snappedf(ShapeDefs.damage(ShapeDefs.SPEAR, ShapeDefs.num(ShapeDefs.step(ShapeDefs.SPEAR, step_index),
			"damageScale", 1.0)), 0.1))
	var crit := _crit_multiplier()
	var ok := drops.size() == 3
	for i in mini(drops.size(), 3):
		var want: float = expected[i]
		var got: float = drops[i]
		if absf(got - want) > 0.6 and absf(got - want * crit) > 0.6:
			ok = false
	await _end(ok, {"hp_before": hp_before, "hp_after": _hp(_swordsman), "hits": drops, "expected": expected,
		"crit_multiplier": crit, "weapon_scale": ShapeDefs.weapon_damage_scale(),
		"unscaled": expected.map(func(value: float) -> float: return snappedf(value / ShapeDefs.weapon_damage_scale(), 0.1))})


func _film_throw() -> void:
	_begin("throw", "2  A pot thrown at the Worm Brawler:  Q (suck)  Q (throw)")
	await _fresh_pen()
	_restore_slime()
	_hold_enemy(_swordsman, _pen_point(0.15, 0.2))
	var feet := _feet_of(_brawler)
	_place_slime(feet + Vector2(-150.0, 0.0), Vector2.LEFT)
	_hold_enemy(_brawler, feet)
	var player: Node = Services.world().player
	var mouth: RefCounted = player.call(&"get_mouth")
	ThrowAmmo.spawn_liftable("clay-pot", Services.world().player_body.global_position + Vector2.LEFT * AMMO_BEHIND_PX,
		{"pop": false})
	await _run(6)
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	for i in 50:
		await _tick()
		_hold_enemy(_brawler, feet)
		if bool(mouth.call(&"is_holding")):
			break
	var held := bool(mouth.call(&"is_holding"))
	await _run(8)
	player.call(&"face", Vector2.RIGHT)
	await _tick()
	var hp_before := _hp(_brawler)
	_push(&"eat", true)
	await _run(2)
	_push(&"eat", false)
	await _run(70)
	var dealt := hp_before - _hp(_brawler)
	await _end(held and dealt >= 30.0, {"held": held, "hp_before": hp_before, "hp_after": _hp(_brawler), "dealt": snappedf(dealt, 0.1)})


func _film_switch() -> void:
	_begin("switch", "3  E: the weapon goes to the War Axe")
	_restore_slime()
	_place_slime(_pen_point(0.5, 0.95), Vector2.RIGHT)
	await _run(12)
	var before := String(_shapes.call(&"current_shape_id"))
	_push(&"weapon_next", true)
	await _run(2)
	_push(&"weapon_next", false)
	await _run(50)
	var after := String(_shapes.call(&"current_shape_id"))
	var hud_shape := _hud_shape()
	await _end(before == String(ShapeDefs.SPEAR) and after == String(ShapeDefs.AXE) and hud_shape == String(ShapeDefs.AXE),
		{"before": before, "after": after, "hud_slot": hud_shape})


func _film_charge() -> void:
	_begin("charge", "4  Axe charge with NO energy:  hold A through the ring, let go")
	_restore_slime()
	var player: Node = Services.world().player
	# On the testbed's training dummy, outside the pen (a blow from a pen enemy would break the hold, as
	# any hit does in play).
	var dummy := _dummy(DUMMY_NAME)
	if dummy == null:
		await _end(false, {"error": "no %s" % DUMMY_NAME})
		return
	var dummy_body := dummy.call(&"get_body") as Node2D
	var feet := dummy_body.global_position
	var blows: Array = []
	var on_hit := func(payload: Dictionary) -> void: blows.append(snappedf(float(payload.get("damage", 0.0)), 0.1))
	dummy.connect(&"hit", on_hit)
	_place_slime(feet + Vector2(-60.0, 0.0), Vector2.RIGHT)
	player.call(&"set_energy", 0.0)
	await _run(16)
	var charge := ShapeDefs.charge(ShapeDefs.AXE)
	var hold_ms := ShapeDefs.chain_number("chargeStartMs") + ShapeDefs.num(charge, "ringMs") + 250.0
	_push(&"attack", true)
	var ring := 0.0
	for i in int(hold_ms / 1000.0 * 60.0):
		await _tick()
		player.call(&"set_energy", 0.0)
		ring = maxf(ring, float(_shapes.call(&"charge_progress")))
	var fired := false
	_push(&"attack", false)
	for i in 60:
		await _tick()
		player.call(&"set_energy", 0.0)
		if int(_shapes.get(&"_phase")) == ShapeControllerScript.Phase.CHARGE:
			fired = true
	await _run(30)
	dummy.disconnect(&"hit", on_hit)
	var energy := float(player.call(&"get_energy"))
	var spin := snappedf(ShapeDefs.damage(ShapeDefs.AXE, ShapeDefs.num(charge, "damageScale")), 0.1)
	var crit := _crit_multiplier()
	var dealt: float = blows[0] if not blows.is_empty() else 0.0
	var right := absf(dealt - spin) <= 0.6 or absf(dealt - spin * crit) <= 0.6
	await _end(fired and ring >= 1.0 and right, {"ring_seen": snappedf(ring, 0.01), "fired": fired,
		"energy_held_at": 0.0, "energy_after": snappedf(energy, 0.01), "blows": blows, "spin_damage": spin,
		"spin_unscaled": snappedf(spin / ShapeDefs.weapon_damage_scale(), 0.1)})


func _film_ability() -> void:
	_begin("ability", "5  B: pick an ability in the bag,  B,  then D uses it")
	_restore_slime()
	var player: Node = Services.world().player
	_place_slime(_pen_point(0.3, 0.6), Vector2.RIGHT)
	await _run(10)
	var before := AbilityBox.selected(player)
	var pick: StringName = &""
	for id: StringName in PICK_ORDER:
		if AbilityBox.box_ids(player).has(id) and id != before:
			pick = id
			break
	var menu := root.get_tree().get_first_node_in_group(&"menu_windows")
	var opened := menu != null and bool(menu.call(&"open_bag"))
	for i in 20:
		await _frame()
	var bag := _bag()
	if bag != null:
		bag.call(&"choose_ability", pick)
	for i in 30:
		await _frame()
	await _save_still("bag.png")
	if menu != null:
		menu.call(&"toggle_menu")
	var uses_before := AbilityBox.use_count()
	for i in 24:
		await _tick()
	_push(&"ability_use", true)
	await _run(2)
	_push(&"ability_use", false)
	await _run(80)
	var chosen := AbilityBox.selected(player)
	await _end(opened and chosen == pick and AbilityBox.use_count() > uses_before,
		{"before": String(before), "picked": String(pick), "chosen": String(chosen), "bag_opened": opened,
			"used": AbilityBox.use_count() - uses_before})


## The HUD (cut from the window), the Controls list and the Settings window.
func _stills() -> void:
	_check = ""
	_caption.text = ""
	_restore_slime()
	_shapes.call(&"set_current", ShapeDefs.SPEAR)
	await _run(20)
	await _save_still("hud.png")
	var shell := Services.shell()
	if shell != null:
		shell.call(&"open_controls")
		for i in 30:
			await _frame()
		await _save_still("controls.png")
		shell.call(&"close_all_menus")
		for i in 10:
			await _frame()
		shell.call(&"open_settings")
		for i in 30:
			await _frame()
		await _save_still("settings.png")
		shell.call(&"close_all_menus")
		for i in 10:
			await _frame()


# --- staging ----------------------------------------------------------------------------------------

func _begin(id: String, caption: String) -> void:
	_camera_zoom()
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


func _feet_of(enemy: Node) -> Vector2:
	var body: Variant = enemy.call(&"get_body") if enemy.has_method(&"get_body") else enemy
	return (body as Node2D).global_position


## Keeps `enemy` standing at `feet` (it would walk at the slime and spoil the framing); its reactions play.
func _hold_enemy(enemy: Variant, feet: Vector2) -> void:
	if not is_instance_valid(enemy):
		return
	var body: Variant = (enemy as Object).call(&"get_body") if (enemy as Object).has_method(&"get_body") else null
	if not body is Node2D:
		return
	if (body as Node2D).global_position.distance_to(feet) > 40.0:
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


func _camera_zoom() -> void:
	var camera: Node = Services.world().camera
	if camera == null:
		return
	camera.set(&"target_zoom", _zoom)
	if camera.has_method(&"apply_zoom"):
		camera.call(&"apply_zoom", _zoom)


## An enemy's health; 0 once it is gone (killed and freed).
func _hp(enemy: Variant) -> float:
	if not is_instance_valid(enemy) or not (enemy as Object).has_method(&"get_damage_state"):
		return 0.0
	return float(((enemy as Object).call(&"get_damage_state") as Dictionary).get("hp", 0.0))


func _crit_multiplier() -> float:
	var constants := Services.constants()
	return constants.number(ShapeDefs.STAT_CRIT_MULTIPLIER) if constants != null else 1.0


## The HUD's weapon slot's shape (its model's selected entry).
func _hud_shape() -> String:
	var slot := root.find_child("WeaponHotbar", true, false)
	if slot == null:
		for node: Node in root.find_children("*", "Control", true, false):
			if node.has_method(&"model") and node.has_method(&"is_carousel_open"):
				slot = node
				break
	if slot == null:
		return "no slot"
	var model: Dictionary = slot.call(&"model")
	var weapons: Array = model.get("weapons", [])
	var selected := int(model.get("selected_index", -1))
	return str((weapons[selected] as Dictionary).get("shape_id", "")) if selected >= 0 and selected < weapons.size() else ""


## The training dummy's script node under the testbed's dummy `name`.
func _dummy(name: String) -> Node:
	var dummy_root := root.find_child(name, true, false)
	if dummy_root == null:
		return null
	for node: Node in dummy_root.find_children("*", "", true, false):
		if node.get_script() == TrainingDummyScript:
			return node
	return null


func _bag() -> Node:
	for node: Node in root.find_children("*", "", true, false):
		if node.has_method(&"choose_ability") and node.has_method(&"choose_skin"):
			return node
	return null


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
	_save_frame()


## One rendered frame while the game is paused (a window open): a frame of the film too.
func _frame() -> void:
	await process_frame
	_step += 1
	if _step % _every != 0:
		return
	await RenderingServer.frame_post_draw
	_save_frame()


func _save_frame() -> void:
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	_rows.append({"check": _check})
	_index += 1


func _save_still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(name)))


func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

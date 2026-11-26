extends Node
## The throw yard (docs/godot/THROW_COMBAT.md): in the playground main.gd adds it under the world root
## beside the ShapesTestbed. It lays two columns of liftables inside the shapes testbed's enemy pen (its
## top stays open to walk in), so there is always something to throw at its enemies (the pen has the
## Worm Archer and the Worm Brawler too):
## - **the left column**, light things (Gulp 1): a pot, a jar of honey (stick), a puffball (sleep),
##   a snowball (freeze), a glass float (shatter), a rock (sturdy: with the rebound prototype it
##   bounces off and can be caught; it stood in for the toadstool, a second sleep thing, on
##   2026-11-16);
## - **the right column**: a crate, an ice block (freeze), a kettle (pierce), a crystal cluster
##   (shatter) (medium, Gulp 2), then a keg and an iron ball (pierce) (heavy, Gulp 3).
## Each thing comes back at its spot `respawn_ms` after it is taken (if the spot is clear). A label
## under the pen names the keys and the state:
## - **F6** steps the Gulp's level 1, 2, 3, 1 (ThrowMode.cycle_dev_level; the session only);
## - **Shift+F6** turns the aim help on or off (ThrowMode.toggle_assist);
## - **F1** flips the new throw feel on or off for the session (ThrowFeel.toggle: "Throw feel:
##   new" / "old" over the slime), to compare the two live; what the slime holds is redrawn at
##   once at the feel's size;
## - **Shift+F1** flips the rebound prototype (ThrowFeel.toggle_rebound: sturdy things bounce off
##   and can be caught, "Rebound: on" / "off");
## - **Ctrl+F1** flips the enemy-ammo prototype (GulpableEnemy.toggle: helpless enemies can be
##   gulped and thrown, "Enemy ammo: on" / "off").
## (F4 respawns the pen and F5 fills the energy: shapes_testbed.gd.) Everything goes with the world.
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ShapesTestbed := preload("res://game/shapes/shapes_testbed.gd")
const GulpController := preload("res://game/player/gulp/gulp_controller.gd")

## Dev keys (checked free on 2026-10-20: F2 control scheme, F3 FPS, F4 pen, F5 energy, F7/F8 sound
## audition, F9 juice panel, shift+F10 chest menu; F1 checked free on 2026-11-16).
const LEVEL_KEY := KEY_F6
const FEEL_KEY := KEY_F1
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const GulpableEnemy := preload("res://game/throw/gulpable_enemy.gd")
const LIGHT_ROW: Array[String] = ["clay-pot", "honey-jar", "puffball", "snowball", "glass-float", "rock"]
const HEAVY_ROW: Array[String] = ["crate", "ice-block", "kettle", "crystal-cluster", "keg", "iron-ball"]
const TITLE_TEXT := "Throw yard: left light (Gulp 1), right medium then heavy (Gulp 2, 3)\nF6: Gulp level %d (lifts %s)  ·  Shift+F6: aim help %s  ·  F1: throw feel %s  ·  Shift+F1: rebound %s  ·  Ctrl+F1: enemy ammo %s"
const LEVEL_TEXT := "Gulp level %d: lifts %s things"
const ASSIST_TEXT := "Aim help %s"
const FEEL_TEXT := "Throw feel: %s"
const FEEL_NEW := "new"
const FEEL_OLD := "old"
const REBOUND_TEXT := "Rebound: %s"
const ENEMY_AMMO_TEXT := "Enemy ammo: %s"
const TEXT_COLOR := &"cyan"
const TEXT_RISE_PX := 56.0
const LABEL_FONT_SIZE := 14
const LABEL_WIDTH := 520.0
## The shapes testbed's pen (its default numbers when there is no ShapesTestbed sibling).
const TESTBED_NAME := "ShapesTestbed"

## The columns' first spot from the pen's top corners (top-left for the light column, top-right for
## the other), and the step between spots.
@export var light_row_offset: Vector2 = Vector2(26.0, 30.0)
@export var heavy_row_offset: Vector2 = Vector2(-26.0, 30.0)
@export var row_step: Vector2 = Vector2(0.0, 46.0)
## A thing taken comes back this long after (simulation ms).
@export var respawn_ms: float = 4000.0
## A spot counts as clear when no body stands within this of it.
@export var clear_px: float = 26.0

## {"kind": String, "spot": Vector2, "root": Node2D or null, "respawn_at": float}.
var slots: Array[Dictionary] = []
var _title: Label
var _pen_rect := Rect2()


func _ready() -> void:
	_spawn_yard.call_deferred()


func _spawn_yard() -> void:
	if not slots.is_empty():
		return
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	var spawn := world.player_spawn_point()
	var testbed := get_parent().get_node_or_null(TESTBED_NAME) if get_parent() != null else null
	var offset: Vector2 = testbed.get(&"pen_offset") if testbed != null else ShapesTestbed.DEFAULT_PEN_OFFSET
	var size: Vector2 = testbed.get(&"pen_size") if testbed != null else ShapesTestbed.DEFAULT_PEN_SIZE
	_pen_rect = Rect2(spawn + offset, size)
	var light_from := _pen_rect.position + light_row_offset
	for index in LIGHT_ROW.size():
		slots.append({"kind": LIGHT_ROW[index], "spot": light_from + row_step * index, "root": null, "respawn_at": -1.0})
	var heavy_from := _pen_rect.position + Vector2(_pen_rect.size.x, 0.0) + heavy_row_offset
	for index in HEAVY_ROW.size():
		slots.append({"kind": HEAVY_ROW[index], "spot": heavy_from + row_step * index, "root": null, "respawn_at": -1.0})
	for slot: Dictionary in slots:
		_fill(slot)
	_make_labels(parent)


func _physics_process(_delta: float) -> void:
	if slots.is_empty():
		return
	var now := Services.now_ms()
	for slot: Dictionary in slots:
		var root: Variant = slot.get("root")
		# Validity first: `is` on a freed instance (a thing just sucked up) is an error.
		if is_instance_valid(root) and root is Node and not (root as Node).is_queued_for_deletion():
			continue
		if float(slot["respawn_at"]) < 0.0:
			slot["respawn_at"] = now + respawn_ms
		elif now >= float(slot["respawn_at"]) and _clear(slot["spot"]):
			_fill(slot)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or (key.keycode != LEVEL_KEY and key.keycode != FEEL_KEY):
		return
	get_viewport().set_input_as_handled()
	if key.keycode == FEEL_KEY and key.ctrl_pressed:
		_say(ENEMY_AMMO_TEXT % ("on" if GulpableEnemy.toggle() else "off"))
	elif key.keycode == FEEL_KEY and key.shift_pressed:
		_say(REBOUND_TEXT % ("on" if ThrowFeel.toggle_rebound() else "off"))
	elif key.keycode == FEEL_KEY:
		_say(FEEL_TEXT % (FEEL_NEW if ThrowFeel.toggle() else FEEL_OLD))
		# What the slime holds follows the feel's size at once.
		var world := Services.world()
		var slime: Node = world.player if world != null else null
		if slime != null and slime.has_method(&"get_mouth"):
			(slime.call(&"get_mouth") as RefCounted).call(&"refresh_inside")
	elif key.shift_pressed:
		var on := ThrowMode.toggle_assist()
		_say(ASSIST_TEXT % ("on" if on else "off"))
	else:
		var level := ThrowMode.cycle_dev_level()
		_say(LEVEL_TEXT % [level, ThrowMode.level_weight(level)])
	_refresh_title()


func _fill(slot: Dictionary) -> void:
	slot["respawn_at"] = -1.0
	slot["root"] = ThrowAmmo.spawn_liftable(str(slot["kind"]), slot["spot"])


## No body (the slime, an enemy, a thing) stands on `spot`.
func _clear(spot: Vector2) -> bool:
	var world := Services.world()
	var player_body: Node2D = world.player_body if world != null else null
	if player_body != null and is_instance_valid(player_body) and player_body.global_position.distance_to(spot) < clear_px:
		return false
	var tree := get_tree()
	for node: Node in tree.get_nodes_in_group(ThrowMode.ENEMY_GROUP):
		var centre: Variant = node.call(&"get_centre") if node.has_method(&"get_centre") else null
		if centre is Vector2 and (centre as Vector2).distance_to(spot) < clear_px * 1.5:
			return false
	return true


func _make_labels(parent: Node) -> void:
	_title = _label("ThrowYardTitle", LABEL_FONT_SIZE, _pen_rect.position + Vector2(0.0, _pen_rect.size.y + 8.0))
	parent.add_child(_title)
	_refresh_title()


func _label(node_name: String, font_size: int, at: Vector2) -> Label:
	var label := Label.new()
	label.name = node_name
	label.size = Vector2(LABEL_WIDTH, 0.0)
	label.position = at
	label.z_index = 4
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override(&"outline_size", 4)
	return label


func _refresh_title() -> void:
	if _title == null or not is_instance_valid(_title):
		return
	var level := ThrowMode.gulp_level()
	_title.text = TITLE_TEXT % [level, ThrowMode.level_weight(level), "on" if ThrowMode.assist_on() else "off",
		FEEL_NEW if ThrowFeel.is_on() else FEEL_OLD, "on" if ThrowFeel.rebound_on() else "off",
		"on" if GulpableEnemy.is_on() else "off"]


func _say(text: String) -> void:
	var world := Services.world()
	GulpController.say_over(world.player if world != null else null, text, TEXT_COLOR, TEXT_RISE_PX)

extends Node
## The shapes testbed (BODY_SHAPES.md "Running it"; combat-feel plan section 5, "Training dummy:
## switchable preset", and section 9 "What to try first"). In the playground's rework mode main.gd
## adds it under the world root (never in the classic game); it puts on the open grass south-west of
## the player spawn, clear of the playground's own content (the feel yard's dummies, the liftable
## gallery, the gulp yard, the web nook):
## - **The dummies**: one training dummy per reaction preset (light, medium, heavy, boss) in a column
##   west of the spawn, each with its preset's name over it, placed by its feet. Each is the
##   training-dummy scene's parts on a CharacterBody2D root on the enemy layer (TrainingDummyScript
##   `body`), so the reactions move it: holds stop it, knockbacks and launches slide it, it splats on
##   walls and bowls the next dummy, and once the stun is over it walks back to its post. The dummies
##   answer rework hits through EnemyReactions with their preset's profile (TrainingDummyScript
##   `reaction_preset`, ReactionProfile.for_preset).
## - **The enemy pen**: a rectangle east of the dummies (outlined on the ground, its name and key
##   over it) with one real enemy per weight the game has: the slime spider (light), the worm
##   swordsman (medium) and the Clod Stomper (heavy); no tiny type exists yet, so none stands in for
##   the Broodling. Each is spawned as EnemyPopulation spawns (`character.<type>` placed at its old
##   centre, `configure_navigation`, here with no camp and no safe zones) with its `enemy-types.json`
##   `maxHp` when that is higher than the scene's (the level-1 swordsman scene has 8, which a jab
##   kills before any reaction shows). They fight only while the slime's centre is inside the pen
##   (their arena, `configure_arena`); while it is outside, each one's arena is its own post, so it
##   walks back there and never shoots at the slime by the dummies or at the spawn. Each one comes
##   back `pen_respawn_ms` after it dies; PEN_RESPAWN_KEY (F4) brings the whole pen back at once.
## - **Energy** (owner, 2026-10-12): it no longer refills by itself in the rework mode, so
##   ENERGY_REFILL_KEY (F5) fills it to full, to keep testing the charges and the Slam.
## - **The Roll's upgrade**: it lends the `roll-charge` upgrade for the session (quietly, never saved,
##   like main.gd's shapes), so a tap rolls the quick roll and a hold the charged one.
## Everything goes with the world.
##
## Owner: rework wiring (BODY_SHAPES.md "Mode, wiring, testbed").

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const ShapeStrike := preload("res://game/shapes/shape_strike.gd")
const TrainingDummyScript := preload("res://game/scripts/training_dummy.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const PlayerRoll := preload("res://game/player/roll/player_roll.gd")

const DUMMY_SCENE_ID := "object.training-dummy"
## One dummy per weight preset (`combat.weights`), in this order.
const PRESETS: Array[String] = ["light", "medium", "heavy", "boss"]
const DUMMY_NAME_PREFIX := "shapes-dummy-"
const LABEL_NAME := "PresetLabel"
const LABEL_WIDTH := 96.0
const LABEL_FONT_SIZE := 14
## Physics layer names (project.godot): the dummies' bodies sit on the enemy layer (the slime bumps
## them, the Spear's wall ray passes them, bowling finds them) and collide as enemies do.
const LAYER_ENEMY := "enemy"
const MASK_LAYERS: Array[String] = ["world", "player", "water"]

## The pen's enemies, one per weight, in this order (`pen_posts` gives each its spot).
const PEN_TYPES: Array[String] = ["slime-spider", "worm-swordsman", "clod-stomper"]
const ENEMY_SCENE_PREFIX := "character."
const ENEMY_TYPES_FILE := "enemy-types.json"
const PEN_NAME := "ShapesPen"
const PEN_AREA_PREFIX := "shapes-pen-"
## Dev key (rework mode, playground; checked free on 2026-10-11: F2 is the control scheme, F3 the FPS
## panel, F7/F8 the sound audition, F9 the juice panel, shift+F10 the chest menu): every pen enemy
## comes back at once.
const PEN_RESPAWN_KEY := KEY_F4
## Dev key (rework mode, playground; checked free on 2026-10-12, as above, F4 being the pen): the
## slime's energy to full. A floating line over the slime confirms it.
const ENERGY_REFILL_KEY := KEY_F5
const PEN_TITLE := "Enemy pen  (F4: respawn, F5: full energy)"
const ENERGY_REFILL_TEXT := "Energy full"
const ENERGY_REFILL_COLOR := &"cyan"
const ENERGY_REFILL_RISE_PX := 56.0
## The pen's outline on the ground and its title (presentation).
const PEN_LINE_COLOR := Color(1.0, 0.95, 0.7, 0.45)
const PEN_LINE_PX := 2.0
const PEN_Z := -1
const PEN_TITLE_RISE_PX := 22.0
const PEN_TITLE_WIDTH := 320.0
## The arena a pen enemy gets while the slime is outside the pen: a dot at its post it walks to.
const POST_ARENA_RADIUS := 1.0

## Where the first dummy's feet stand, from the slime's feet at the spawn (the spawn point plus the
## slime's depth anchor): playground layout, the open grass west of the spawn (1280, 1536), clear of
## the test chest (1120, 1440) and the web nook (x 224-576).
@export var first_offset: Vector2 = Vector2(-320.0, -60.0)
## From one dummy's feet to the next.
@export var spacing: Vector2 = Vector2(0.0, 120.0)
## How high over a dummy's root its preset's name shows.
@export var label_rise_px: float = 124.0
## How fast a moved dummy walks back to its post once its stun is over (px/s).
@export var dummy_return_speed: float = 90.0
## The enemy pen, in old centre positions: its top-left from the player spawn point, and its size
## (playground layout: south of the spawn, east of the dummies, west of the liftable gallery at
## x 1600, north of the hill at y 1984, whose wall is there for splats).
@export var pen_offset: Vector2 = Vector2(-200.0, 128.0)
@export var pen_size: Vector2 = Vector2(460.0, 280.0)
## Each pen enemy's post (its old centre) from the pen's top-left, in PEN_TYPES order.
@export var pen_posts: Array[Vector2] = [Vector2(90.0, 90.0), Vector2(230.0, 190.0), Vector2(370.0, 90.0)]
## A pen enemy comes back this long after it died (simulation ms).
@export var pen_respawn_ms: float = 3000.0
## The pen's enemies take their `enemy-types.json` maxHp when it is higher than their scene's.
@export var pen_type_health: bool = true

## The dummies spawned, in PRESETS order.
var dummies: Array[Node2D] = []
## The pen's slots, in PEN_TYPES order: {"type": String, "post": Vector2 (old centre), "root":
## Node2D or null, "enemy": EnemyScript or null, "respawn_at": float (simulation ms, < 0: none due)}.
var pen: Array[Dictionary] = []

var _pen_rect: Rect2 = Rect2()
var _player_in_pen: bool = false
var _outline: Line2D


func _ready() -> void:
	_lend_roll_upgrade()
	_spawn_testbed.call_deferred()


## The Roll's `roll-charge` upgrade, learned quietly for this session only (RunState
## `learn_session_ability`: left out of every save), so the owner can try both rolls.
func _lend_roll_upgrade() -> void:
	var run := Services.run()
	if ReworkMode.is_on() and run != null:
		run.learn_session_ability(String(PlayerRoll.CHARGE_UPGRADE_ID))


## Spawns the dummies and the pen once (the world and the player must be registered).
func _spawn_testbed() -> void:
	if not ReworkMode.is_on() or not dummies.is_empty():
		return
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	var spawn := world.player_spawn_point()
	var feet := spawn + FeetAnchor.depth_anchor(world.player_body)
	for index: int in PRESETS.size():
		var dummy := _make_dummy(PRESETS[index])
		if dummy == null:
			break
		_place(dummy, parent, feet + first_offset + spacing * float(index))
		dummies.append(dummy)
	_pen_rect = Rect2(spawn + pen_offset, pen_size)
	_draw_pen(parent)
	for index: int in PEN_TYPES.size():
		var post := _pen_rect.position + (pen_posts[index] if index < pen_posts.size() else _pen_rect.size * 0.5)
		pen.append({"type": PEN_TYPES[index], "post": post, "root": null, "enemy": null, "respawn_at": -1.0})
		world.packed_scene(ENEMY_SCENE_PREFIX + PEN_TYPES[index])
	_player_in_pen = _pen_has_player()
	respawn_pen()


## Every pen enemy anew (the dev key): the living ones go, a fresh one stands at each post.
func respawn_pen() -> void:
	for slot: Dictionary in pen:
		var root: Variant = slot.get("root")
		if root is Node and is_instance_valid(root) and not (root as Node).is_queued_for_deletion():
			(root as Node).queue_free()
		_spawn_slot(slot)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not ReworkMode.is_on():
		return
	if key.keycode == PEN_RESPAWN_KEY and not pen.is_empty():
		get_viewport().set_input_as_handled()
		respawn_pen()
	elif key.keycode == ENERGY_REFILL_KEY:
		get_viewport().set_input_as_handled()
		refill_energy()


## The slime's energy to full (the dev key), with a floating line over it.
func refill_energy() -> void:
	var world := Services.world()
	var player: PlayerScript = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	player.set_energy(player.get_max_energy())
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(player.get_centre() - Vector2(0.0, ENERGY_REFILL_RISE_PX), ENERGY_REFILL_TEXT, ENERGY_REFILL_COLOR, false)


## The pen's upkeep: a dead or freed enemy comes back `pen_respawn_ms` later; the arenas follow the
## slime (the pen while it is inside, each one's post while it is outside).
func _physics_process(_delta: float) -> void:
	if pen.is_empty() or not ReworkMode.is_on():
		return
	var now := Services.now_ms()
	for slot: Dictionary in pen:
		if _slot_alive(slot):
			continue
		if float(slot["respawn_at"]) < 0.0:
			slot["respawn_at"] = now + pen_respawn_ms
		elif now >= float(slot["respawn_at"]):
			_spawn_slot(slot)
	var inside := _pen_has_player()
	if inside != _player_in_pen:
		_player_in_pen = inside
		for slot: Dictionary in pen:
			if _slot_alive(slot):
				_set_arena(slot)


# --- the dummies -----------------------------------------------------------------------------------

## A training dummy with `preset`: the training-dummy scene's parts (its BodyShape, Visual, DamageArea
## and script) moved onto a CharacterBody2D root on the enemy layer, the script's `body` set before
## it enters the tree, and its name label.
func _make_dummy(preset: String) -> CharacterBody2D:
	var world := Services.world()
	var source := world.instantiate_scene(DUMMY_SCENE_ID) as Node2D if world != null else null
	if source == null:
		push_warning("ShapesTestbed: no '%s' scene" % DUMMY_SCENE_ID)
		return null
	var root := CharacterBody2D.new()
	root.name = DUMMY_NAME_PREFIX + preset
	root.y_sort_enabled = true
	root.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	root.collision_layer = ShapeStrike.layer_bit(LAYER_ENEMY)
	var mask := 0
	for layer_name: String in MASK_LAYERS:
		mask |= ShapeStrike.layer_bit(layer_name)
	root.collision_mask = mask
	for child: Node in source.get_children():
		source.remove_child(child)
		child.owner = null
		root.add_child(child)
		if child is TrainingDummyScript:
			var dummy_script := child as TrainingDummyScript
			dummy_script.reaction_preset = preset
			dummy_script.body = root
			dummy_script.return_speed = dummy_return_speed
	source.free()
	var label := Label.new()
	label.name = LABEL_NAME
	label.text = preset
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(LABEL_WIDTH, 0.0)
	label.position = Vector2(-LABEL_WIDTH / 2.0, -label_rise_px)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", LABEL_FONT_SIZE)
	root.add_child(label)
	return root


# --- the pen ---------------------------------------------------------------------------------------

## Spawns `slot`'s enemy at its post as EnemyPopulation does (the type's scene placed by its old
## centre before it enters the tree, then `configure_navigation`), with the type's health and the
## arena the slime's place asks for.
func _spawn_slot(slot: Dictionary) -> void:
	slot["root"] = null
	slot["enemy"] = null
	slot["respawn_at"] = -1.0
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	var type_id := str(slot["type"])
	var root := world.instantiate_scene(ENEMY_SCENE_PREFIX + type_id) as Node2D
	if root == null:
		push_warning("ShapesTestbed: no '%s%s' scene" % [ENEMY_SCENE_PREFIX, type_id])
		return
	var enemy: EnemyScript = null
	for child: Node in root.get_children():
		if child is EnemyScript:
			enemy = child as EnemyScript
			break
	if enemy == null:
		push_warning("ShapesTestbed: '%s%s' has no EnemyScript" % [ENEMY_SCENE_PREFIX, type_id])
		root.free()
		return
	if pen_type_health:
		enemy.max_health = maxf(enemy.max_health, _type_health(type_id))
	_place(root, parent, FeetAnchor.global_for_phaser_position(root, slot["post"]))
	# No camp (the arena keeps it in the pen) and no safe zones (the spawn's would push it out).
	var no_zones: Array[Dictionary] = []
	enemy.configure_navigation({}, no_zones)
	slot["root"] = root
	slot["enemy"] = enemy
	_set_arena(slot)


## The pen while the slime is inside it, else a dot at the enemy's post (it walks back there and
## leaves the slime alone).
func _set_arena(slot: Dictionary) -> void:
	var enemy := slot.get("enemy") as EnemyScript
	if enemy == null or not is_instance_valid(enemy):
		return
	if _player_in_pen:
		enemy.configure_arena({"shape": "rectangle", "x": _pen_rect.position.x, "y": _pen_rect.position.y,
			"w": _pen_rect.size.x, "h": _pen_rect.size.y})
	else:
		var post: Vector2 = slot["post"]
		enemy.configure_arena({"shape": "circle", "x": post.x, "y": post.y, "radius": POST_ARENA_RADIUS})


## True while the slime's centre (old position) is inside the pen.
func _pen_has_player() -> bool:
	var world := Services.world()
	var target: Dictionary = world.primary_target() if world != null else {}
	var centre: Variant = target.get("centre")
	return centre is Vector2 and _pen_rect.has_point(centre as Vector2)


func _slot_alive(slot: Dictionary) -> bool:
	var root: Variant = slot.get("root")
	var enemy: Variant = slot.get("enemy")
	if not (root is Node) or not is_instance_valid(root) or (root as Node).is_queued_for_deletion():
		return false
	return enemy is EnemyScript and is_instance_valid(enemy) and not (enemy as EnemyScript).is_defeated()


## The type's `maxHp` in enemy-types.json (0 when it has none).
static func _type_health(type_id: String) -> float:
	var constants := Services.constants()
	var data: Variant = constants.data_file(ENEMY_TYPES_FILE) if constants != null else null
	var types: Variant = (data as Dictionary).get("types", {}) if data is Dictionary else {}
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	var hp: Variant = (entry as Dictionary).get("maxHp", 0.0) if entry is Dictionary else 0.0
	return float(hp) if (hp is float or hp is int) else 0.0


## The pen's outline on the ground and its title over its top-left corner.
func _draw_pen(parent: Node) -> void:
	_outline = Line2D.new()
	_outline.name = PEN_NAME
	_outline.z_index = PEN_Z
	_outline.width = PEN_LINE_PX
	_outline.default_color = PEN_LINE_COLOR
	_outline.closed = true
	var top_left := _pen_rect.position
	var size := _pen_rect.size
	_outline.points = PackedVector2Array([top_left, top_left + Vector2(size.x, 0.0), top_left + size,
		top_left + Vector2(0.0, size.y)])
	var title := Label.new()
	title.name = "PenTitle"
	title.text = PEN_TITLE
	title.size = Vector2(PEN_TITLE_WIDTH, 0.0)
	title.position = top_left - Vector2(0.0, PEN_TITLE_RISE_PX)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override(&"font_size", LABEL_FONT_SIZE)
	_outline.add_child(title)
	parent.add_child(_outline)


# --- helpers ---------------------------------------------------------------------------------------

## Puts `node` (not yet in the tree) at the world point `global_target` under `parent`, then adds it.
static func _place(node: Node2D, parent: Node, global_target: Vector2) -> void:
	var parent_item := parent as CanvasItem
	node.position = parent_item.get_global_transform().affine_inverse() * global_target \
		if parent_item != null and parent_item.is_inside_tree() else global_target
	parent.add_child(node)
	node.reset_physics_interpolation()

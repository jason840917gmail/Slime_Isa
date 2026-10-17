@tool
extends Node2D
## One pen of the playground's Bestiary corner (docs/godot/BESTIARY.md "The Bestiary corner"):
## a fenced rectangle `size` px with its top-left at this node, a sign over it naming its enemy
## (`number`, `enemy_name`, `kind`, `right_tool`), and, in the game's rework mode, its enemies.
##
## - **The enemies** (`enemy_types`, one `character.<type>` scene per post): spawned as the shapes
##   testbed spawns its pen (the scene placed by its old centre before it enters the tree,
##   `configure_navigation` with no camp and no safe zones, the type's `enemy-types.json` maxHp when
##   it is higher than the scene's), each at its post (`posts`, old centres from the pen's top-left;
##   none: spread along the pen's middle), with `enemy_properties` set on its EnemyScript first (the
##   Thorn Guards' `guard_group`). The pen is every enemy's arena (`configure_arena`): it fights
##   while the slime's centre is inside and leaves it alone outside. Each one comes back
##   `respawn_ms` after it died; `respawn` brings them all back (the corner's key).
## - **The fence:** posts and a rope, and a StaticBody2D round the pen on the `stairs` physics layer
##   (19), the layer every walking body but the slime collides with (docs/godot/ELEVATION.md "Stairs
##   walk"): the enemies stay in, the slime walks through, and a charging boar hits it.
## - **Supplies** (`supplies`: {"scene": an object scene id, "kind"?: a liftable kind, "at": a
##   point from the pen's top-left}): things the pen's right tool needs (pots to throw, a stone
##   essence for the Heavy Roll), each put back `supply_respawn_ms` after it was taken; a pickup (a
##   collectible: the Gloomling's key) gets a new instance id each time.
## - **A box ability** (`box_ability`, the Goo Bomb's pens): walking in makes it the Ability Box's
##   choice, so F uses it (it stays chosen outside, until the bag changes it).
## - An empty pen (no `enemy_types`) says "coming next" on its sign.
## The editor shows the fence and the sign (`@tool`); nothing is spawned there.
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const ElevationScript := preload("res://game/world/elevation/elevation.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")

const ENEMY_SCENE_PREFIX := "character."
const ENEMY_TYPES_FILE := "enemy-types.json"
const COMING_NEXT := "coming next"
const SIGN_NAME := "Sign"
const FENCE_NAME := "Fence"
## Presentation: the fence's posts and rope, the pen's floor tint, the sign board.
const POST_EVERY_PX := 64.0
const POST_SIZE := Vector2(6.0, 14.0)
const POST_COLOR := Color("#7a5232")
const POST_EDGE := Color("#3e2a1a")
const ROPE_COLOR := Color("#d9c08a")
const ROPE_PX := 2.0
const ROPE_RISE_PX := 9.0
const FLOOR_COLOR := Color(0.95, 0.85, 0.55, 0.07)
const EMPTY_FLOOR_COLOR := Color(0.2, 0.2, 0.2, 0.08)
const SIGN_SIZE := Vector2(300.0, 64.0)
const SIGN_RISE_PX := 74.0
const SIGN_COLOR := Color("#e9d3a1")
const SIGN_EDGE := Color("#6b4a2b")
const SIGN_EMPTY_COLOR := Color("#cfc6b4")
const SIGN_TEXT := Color("#3b2a1c")
const SIGN_FONT_SIZE := 13
const SIGN_PAD := Vector2(8.0, 4.0)
## The fence's collision: this thick, on the stairs layer only.
const FENCE_THICKNESS := 8.0
## The lent box ability's name rises this far over the slime's centre.
const BOX_TEXT_RISE_PX := 56.0

## The bestiary's row number.
@export var number: int = 0:
	set(value):
		number = value
		_refresh()
@export var enemy_name: String = "":
	set(value):
		enemy_name = value
		_refresh()
## Its kind (Chaser, Burrower, ...).
@export var kind: String = "":
	set(value):
		kind = value
		_refresh()
## The right tool, as the sign says it.
@export var right_tool: String = "":
	set(value):
		right_tool = value
		_refresh()
## The enemy types it holds (`character.<type>` scenes), one per post; empty: a "coming next" pen.
@export var enemy_types: PackedStringArray = PackedStringArray():
	set(value):
		enemy_types = value
		_refresh()
## Each enemy's post (its old centre) from the pen's top-left; missing ones are spread along the
## pen's middle.
@export var posts: PackedVector2Array = PackedVector2Array()
## The pen's size (px).
@export var size: Vector2 = Vector2(512.0, 448.0):
	set(value):
		size = value
		_refresh()
## An enemy comes back this long after it died (simulation ms).
@export var respawn_ms: float = 3000.0
## Properties set on each spawned EnemyScript before it enters the tree (only those it has).
@export var enemy_properties: Dictionary = {}
## Things its right tool needs, put back when taken: [{"scene", "kind"?, "at"}].
@export var supplies: Array[Dictionary] = []
@export var supply_respawn_ms: float = 2500.0
## The Ability Box ability its right tool is (the Goo Bomb's "goo-bombs"; "" = none): when the
## slime's centre comes into the pen it becomes the box's choice (F; S in keys-only), named over the
## slime, and stays chosen after it walks out (a bomb can be cast at the fence); the bag (B) changes
## it back.
@export var box_ability: StringName = &""

## In PEN order: {"type", "post" (old centre), "root", "enemy", "respawn_at"}.
var slots: Array[Dictionary] = []
## {"spec", "node", "respawn_at"} per supply.
var _supplies: Array[Dictionary] = []
var _sign: Label
var _started: bool = false
## `box_ability` was put on the box this visit (the slime is in the pen).
var _box_lent: bool = false
## Pickups placed so far (each gets an instance id of its own).
var _pickup_serial: int = 0


func _ready() -> void:
	# Under everything that stands in the pen (the ground is -2).
	z_index = -1
	_make_sign()
	queue_redraw()
	if Engine.is_editor_hint():
		return
	set_physics_process(false)
	_start.call_deferred()


## The pen's rectangle in world coordinates.
func pen_rect() -> Rect2:
	return Rect2(global_position, size)


## Every enemy of the pen anew (the corner's key): the living ones go, a fresh one stands at each
## post.
func respawn() -> void:
	for slot: Dictionary in slots:
		var root: Variant = slot.get("root")
		if is_instance_valid(root) and root is Node and not (root as Node).is_queued_for_deletion():
			(root as Node).queue_free()
		_spawn(slot)


## The enemies alive now.
func living() -> Array[EnemyScript]:
	var found: Array[EnemyScript] = []
	for slot: Dictionary in slots:
		if _alive(slot):
			found.append(slot["enemy"] as EnemyScript)
	return found


func _start() -> void:
	if _started or not ReworkMode.is_on():
		return
	_started = true
	_make_fence()
	var world := Services.world()
	for index: int in enemy_types.size():
		var post := posts[index] if index < posts.size() else _spread_post(index)
		slots.append({"type": enemy_types[index], "post": global_position + post, "root": null, "enemy": null,
			"respawn_at": -1.0})
		if world != null:
			world.packed_scene(ENEMY_SCENE_PREFIX + enemy_types[index])
	for spec: Dictionary in supplies:
		_supplies.append({"spec": spec, "node": null, "respawn_at": 0.0})
	respawn()
	for supply: Dictionary in _supplies:
		_place_supply(supply)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	var now := Services.now_ms()
	for slot: Dictionary in slots:
		if _alive(slot):
			continue
		if float(slot["respawn_at"]) < 0.0:
			slot["respawn_at"] = now + respawn_ms
		elif now >= float(slot["respawn_at"]):
			_spawn(slot)
	for supply: Dictionary in _supplies:
		var node: Variant = supply.get("node")
		if is_instance_valid(node) and node is Node and not (node as Node).is_queued_for_deletion():
			continue
		if float(supply["respawn_at"]) <= 0.0:
			supply["respawn_at"] = now + supply_respawn_ms
		elif now >= float(supply["respawn_at"]):
			_place_supply(supply)
	_lend_box_ability()


## `box_ability` onto the box when the slime walks into the pen (see the export).
func _lend_box_ability() -> void:
	if box_ability.is_empty():
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var inside := pen_rect().has_point(player.call(&"get_centre"))
	if inside and not _box_lent:
		if AbilityBox.selected(player) == box_ability or AbilityBox.select(player, box_ability):
			_box_lent = true
			var feel := Services.feel()
			if feel != null:
				var text := "%s: %s" % [ControlLabels.control_labels(AbilityBox.USE_ACTION), AbilityDefinitions.title(box_ability)]
				feel.floating_text(player.call(&"get_centre") - Vector2(0.0, BOX_TEXT_RISE_PX), text, &"cyan", false)
	elif not inside:
		_box_lent = false


func _spread_post(index: int) -> Vector2:
	var count := maxi(1, enemy_types.size())
	return Vector2(size.x * float(index + 1) / float(count + 1), size.y * 0.5)


## The type's scene at its post, as EnemyPopulation spawns (see the file comment).
func _spawn(slot: Dictionary) -> void:
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
		push_warning("BestiaryPen %d: no '%s%s' scene" % [number, ENEMY_SCENE_PREFIX, type_id])
		return
	var enemy: EnemyScript = null
	for child: Node in root.get_children():
		if child is EnemyScript:
			enemy = child as EnemyScript
			break
	if enemy == null:
		push_warning("BestiaryPen %d: '%s' has no EnemyScript" % [number, type_id])
		root.free()
		return
	enemy.max_health = maxf(enemy.max_health, _type_health(type_id))
	for key: Variant in enemy_properties:
		if str(key) in enemy:
			enemy.set(StringName(str(key)), enemy_properties[key])
	_place(root, parent, FeetAnchor.global_for_phaser_position(root, slot["post"]))
	var no_zones: Array[Dictionary] = []
	enemy.configure_navigation({}, no_zones)
	var rect := pen_rect()
	enemy.configure_arena({"shape": "rectangle", "x": rect.position.x, "y": rect.position.y,
		"w": rect.size.x, "h": rect.size.y})
	slot["root"] = root
	slot["enemy"] = enemy


func _alive(slot: Dictionary) -> bool:
	var root: Variant = slot.get("root")
	var enemy: Variant = slot.get("enemy")
	if not is_instance_valid(root) or not (root is Node) or (root as Node).is_queued_for_deletion():
		return false
	return is_instance_valid(enemy) and enemy is EnemyScript and not (enemy as EnemyScript).is_defeated()


func _place_supply(supply: Dictionary) -> void:
	supply["node"] = null
	supply["respawn_at"] = 0.0
	var spec: Dictionary = supply["spec"]
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	var root := world.instantiate_scene(str(spec.get("scene", ""))) as Node2D if world != null else null
	if root == null or parent == null:
		if root != null:
			root.free()
		return
	var liftable_kind := str(spec.get("kind", ""))
	if not liftable_kind.is_empty():
		for child: Node in root.get_children():
			if "kind" in child:
				child.set(&"kind", liftable_kind)
	# A pickup (the Gloomling's key) comes back as a new pile with an id of its own: the run keeps a
	# taken pile's record, which would free the next one at once.
	for child: Node in root.get_children():
		if child is CollectibleScript:
			_pickup_serial += 1
			(child as CollectibleScript).instance_id = "bestiary-pen-%d-pickup-%d" % [number, _pickup_serial]
	var at: Vector2 = spec.get("at", Vector2.ZERO)
	_place(root, parent, global_position + at)
	supply["node"] = root


## The fence's body: four thin walls round the pen on the stairs layer.
func _make_fence() -> void:
	var fence := StaticBody2D.new()
	fence.name = FENCE_NAME
	fence.collision_layer = ElevationScript.STAIRS_LAYER
	fence.collision_mask = 0
	var half := FENCE_THICKNESS * 0.5
	var sides: Array[Rect2] = [
		Rect2(0.0, -half, size.x, FENCE_THICKNESS), Rect2(0.0, size.y - half, size.x, FENCE_THICKNESS),
		Rect2(-half, 0.0, FENCE_THICKNESS, size.y), Rect2(size.x - half, 0.0, FENCE_THICKNESS, size.y),
	]
	for side: Rect2 in sides:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = side.size
		shape.shape = rect
		shape.position = side.get_center()
		fence.add_child(shape)
	add_child(fence)


func _make_sign() -> void:
	if _sign != null and is_instance_valid(_sign):
		_sign.queue_free()
	_sign = Label.new()
	_sign.name = SIGN_NAME
	_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign.position = Vector2(0.0, -SIGN_RISE_PX) + SIGN_PAD
	_sign.size = SIGN_SIZE - SIGN_PAD * 2.0
	_sign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sign.add_theme_font_size_override(&"font_size", SIGN_FONT_SIZE)
	_sign.add_theme_color_override(&"font_color", SIGN_TEXT)
	_sign.add_theme_constant_override(&"line_spacing", -2)
	_sign.text = sign_text()
	add_child(_sign)


## "5  Popworm (Burrower)" over the right tool, or "coming next".
func sign_text() -> String:
	var title := "%d  %s" % [number, enemy_name]
	if not kind.is_empty():
		title += "  (%s)" % kind
	var tool := right_tool if not right_tool.is_empty() else "-"
	var status := "" if not enemy_types.is_empty() else "\n" + COMING_NEXT
	return "%s\nRight tool: %s%s" % [title, tool, status]


func _refresh() -> void:
	if _sign != null and is_instance_valid(_sign):
		_sign.text = sign_text()
	queue_redraw()


func _draw() -> void:
	var empty := enemy_types.is_empty()
	draw_rect(Rect2(Vector2.ZERO, size), EMPTY_FLOOR_COLOR if empty else FLOOR_COLOR)
	# The rope, then the posts along it.
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y), Vector2.ZERO])
	var rope := PackedVector2Array()
	for point: Vector2 in corners:
		rope.append(point - Vector2(0.0, ROPE_RISE_PX))
	draw_polyline(rope, ROPE_COLOR, ROPE_PX)
	for edge: int in 4:
		var from := corners[edge]
		var to := corners[edge + 1]
		var steps := maxi(1, int(round(from.distance_to(to) / POST_EVERY_PX)))
		for i: int in steps:
			var at := from.lerp(to, float(i) / float(steps))
			var post := Rect2(at - Vector2(POST_SIZE.x * 0.5, POST_SIZE.y), POST_SIZE)
			draw_rect(post, POST_COLOR)
			draw_rect(post, POST_EDGE, false, 1.0)
	# The sign board.
	var board := Rect2(Vector2(0.0, -SIGN_RISE_PX), SIGN_SIZE)
	draw_rect(board, SIGN_EMPTY_COLOR if empty else SIGN_COLOR)
	draw_rect(board, SIGN_EDGE, false, 2.0)


## The type's `maxHp` in enemy-types.json (0 when it has none).
static func _type_health(type_id: String) -> float:
	var constants := Services.constants()
	var data: Variant = constants.data_file(ENEMY_TYPES_FILE) if constants != null else null
	var types: Variant = (data as Dictionary).get("types", {}) if data is Dictionary else {}
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	var hp: Variant = (entry as Dictionary).get("maxHp", 0.0) if entry is Dictionary else 0.0
	return float(hp) if (hp is float or hp is int) else 0.0


## Puts `node` (not yet in the tree) at the world point `global_target` under `parent`, then adds it.
static func _place(node: Node2D, parent: Node, global_target: Vector2) -> void:
	var parent_item := parent as CanvasItem
	node.position = parent_item.get_global_transform().affine_inverse() * global_target \
		if parent_item != null and parent_item.is_inside_tree() else global_target
	parent.add_child(node)
	node.reset_physics_interpolation()

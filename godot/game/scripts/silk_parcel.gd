@tool
extends Node2D
class_name SilkParcelScript
## Scene script of `object.silk-parcel` (docs/godot/WEBS.md; roadmap 7.9, question 55: "frees what
## is wrapped in silk"; question 129): something small wrapped in silk, lying flat on the floor.
## It glints now and then, and it never breathes or stands up (the Cocoon Mimic stands upright and
## breathes; `object.cocoon-prize` is the Mimic's look).
##
## - **Without the Silk skin** (`player.crosses_webs()`: SkinState, docs/godot/SKINS.md) every hit clinks
##   with `refusal_text`, which says something is needed and never names the skin.
## - **With it** a shape's hit (request tags in CUT_TAGS: the Spear, and the old weapons) frees it:
##   it tears open, pays `coins` at once ("+30c", as an enemy's coins) and spills `contents`
##   ({item_id: count}, as a chest's `initial_contents`) as loot piles around it (EnemyLoot.drop_loot:
##   they stay on the floor, saved, until picked up; an item with no ground look goes into the bag);
##   a dungeon item ("dungeon-small-key", ...: a key wrapped in silk) drops in front of it as the
##   kit's floor key (DungeonKeyPickup), there again after a world rebuild until it is taken,
##   with the web tear cue, a sparkle and "Freed from the silk!". It stays torn open for good: the
##   story flag `save_key()`. Other hits (throws, blasts) clink without a line.
##
## Place it with its root where the parcel's front edge meets the floor. Set `flag_id` to name its
## flag (default: `silk-parcel.<world scene>:<node path>`).
##
## Owner: webs (the Weaver Hollow).

const SkinState := preload("res://game/player/skins/skin_state.gd")
const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const SpiderWebPort := preload("res://game/enemy/spider_web_port.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonKeyPickup := preload("res://game/dungeon/dungeon_key_pickup.gd")

const ART := "res://asset/MAPS/webs/silk-parcel-3x1.webp"
## Frames: 0 closed, 1 torn open, 2 the glint (drawn over the closed one); 2 px a unit.
const FRAMES := 3
const ART_SCALE := 0.5
## The frames' bottom margin (px) under the parcel's front edge.
const FOOT_PX := 4.0
## The glint's middle in its frame (px; scripts/art/pack-web-art.py prints it).
const GLINT_AT_PX := Vector2(78.0, 44.0)
## The glint grows from this size to the full one and back as it fades in and out.
const GLINT_MIN_SCALE := 0.6
## The parcel's footprint (solid) and hurtbox, from the root.
const SOLID := Rect2(-30.0, -22.0, 60.0, 20.0)
const HURT := Rect2(-38.0, -46.0, 76.0, 48.0)
const CUT_TAGS: Array[String] = ["weapon", "spear"]
const RULE := {"priority": 0, "damageMultiplier": 0}
const TAGS: Array[String] = ["barrier", "web"]
const FLAG_PREFIX := "silk-parcel."
const MAIN_GROUP := &"world_main"
const FREED_TEXT := "Freed from the silk!"
const FREED_RISE := 50.0
const FREED_MS := 1800.0
const COIN_TEXT_RISE := 24.0
## The parcel's middle, from the root (where things spill from).
const MIDDLE := Vector2(0.0, -16.0)
## A dungeon item it holds drops here (from the root: in front of the parcel), the next one this
## far to the right.
const KEY_DROP := Vector2(0.0, 30.0)
const KEY_STEP := 30.0
const LINE_RISE := 10.0
const SHIVER_PX := 1.5
const SHIVER_RATE := 46.0
const SHIVER_MS := 220.0

## The parcel was freed. Payload: {"flagId", "coins", "contents"}.
signal freed(payload: Dictionary)
## A hit was refused (the clink). Payload: {"crosses": bool}.
signal refused(payload: Dictionary)

## Coins paid when it is freed.
@export var coins: int = 0
## What spills out: {item_id: count}, as a chest's contents.
@export var contents: Dictionary = {}
## Said when a hit cannot free it (no Silk skin): it needs something, never naming the skin.
@export var refusal_text: String = "Wrapped tight in silk. You need something to free it."
## The story flag set when it is freed (empty: `silk-parcel.<world scene>:<node path>`).
@export var flag_id: String = ""
## Editor only: show the torn look.
@export var preview_open: bool = false:
	set(value):
		preview_open = value
		queue_redraw()

var _open: bool = false
var _body: StaticBody2D
var _area: Area2D
var _next_glint_ms: float = 0.0
var _glint_from_ms: float = -1.0
var _shiver_until_ms: float = 0.0
## Freed earlier with a dungeon item in it: it is dropped again once the world is up.
var _redrop_pending := false
static var _texture: Texture2D


func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		set_process(false)
		return
	var run := Services.run()
	_open = run != null and run.has_flag(save_key())
	if _open:
		# A dungeon item freed but not picked up yet lies there again (DungeonKeyPickup.drop skips
		# one already taken), once the world is up.
		_redrop_pending = not _dungeon_items().is_empty()
		set_process(_redrop_pending)
		return
	_body = StaticBody2D.new()
	_body.name = "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.add_child(_rect_shape(SOLID))
	add_child(_body)
	_area = Area2D.new()
	_area.name = "DamageArea"
	_area.collision_layer = 8
	_area.collision_mask = 0
	_area.monitoring = false
	_area.add_child(_rect_shape(HURT))
	add_child(_area)
	var router := Services.router()
	if router != null:
		router.register_area(_area, self, RULE, TAGS)
	_plan_glint(float(Time.get_ticks_msec()))


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_unregister()


## True once it is freed (now or earlier in the run).
func is_open() -> bool:
	return _open


## The story flag it sets when freed.
func save_key() -> String:
	if not flag_id.is_empty():
		return flag_id
	var scene_root := owner
	if scene_root != null and not scene_root.scene_file_path.is_empty():
		return FLAG_PREFIX + "%s:%s" % [scene_root.scene_file_path.get_file().get_basename(), str(scene_root.get_path_to(self))]
	return FLAG_PREFIX + str(get_path())


## The positive counts of `contents` ({item_id: count}).
func spill() -> Dictionary:
	var result := {}
	for item_id: Variant in contents:
		var count := int(contents[item_id])
		if count > 0:
			result[str(item_id)] = count
	return result


# --- the damage contract -----------------------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _open}


func can_receive_damage(input: Dictionary) -> Dictionary:
	if _open:
		return {"accepted": false, "reason": "dead"}
	var request: Dictionary = input.get("request", {})
	var crosses := _player_crosses_webs()
	if crosses and _is_cut_hit(request):
		return {"accepted": true}
	_shiver_until_ms = float(Time.get_ticks_msec()) + SHIVER_MS
	refused.emit({"crosses": crosses})
	if crosses:
		return {"accepted": false, "reason": BlastBarrier.REASON_IMMUNE}
	return BlastBarrier.refuse(global_position - Vector2(0.0, LINE_RISE), refusal_text)


func commit_damage(_commit: Dictionary) -> void:
	if not _open:
		free_parcel()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


## Tears it open for good and spills what it holds (the shape's cut; scripts may call it).
func free_parcel() -> void:
	if _open:
		return
	_open = true
	var run := Services.run()
	if run != null:
		run.set_flag(save_key())
	_unregister()
	if _body != null:
		_body.queue_free()
		_body = null
	if _area != null:
		_area.queue_free()
		_area = null
	_glint_from_ms = -1.0
	queue_redraw()
	var world := Services.world()
	SkinState.show(world.player if world != null else null, SkinState.SILK)
	var at := global_position + MIDDLE
	var feel := Services.feel()
	if coins > 0 and run != null:
		run.add_coins(coins)
		if feel != null:
			feel.floating_text(at - Vector2(0.0, COIN_TEXT_RISE), "+%dc" % coins, &"yellow", false)
	var items := spill()
	var loot := {}
	for item_id: String in items:
		if DungeonState.item_of(item_id).is_empty():
			loot[item_id] = items[item_id]
	if not loot.is_empty():
		_drop(loot, at)
	_drop_dungeon_items()
	if feel != null:
		feel.audio_cue(SpiderWebPort.TORN_CUE)
		feel.particles(SpiderWebPort.TORN_PARTICLES, at)
		feel.floating_text(at - Vector2(0.0, FREED_RISE), FREED_TEXT, &"cyan", true, FREED_MS)
	freed.emit({"flagId": save_key(), "coins": coins, "contents": items})


## The dungeon items it holds ("dungeon-small-key", ...: DungeonState.item_of), {item: count}.
func _dungeon_items() -> Dictionary:
	var out := {}
	for item_id: String in spill():
		var item := DungeonState.item_of(item_id)
		if not item.is_empty():
			out[item] = int(out.get(item, 0)) + int(spill()[item_id])
	return out


## A key wrapped in silk (the Weaver Hollow's C4): each dungeon item drops on the floor in front of
## the parcel as the kit's floor key (`object.dungeon-key`, DungeonKeyPickup), recorded by the
## parcel's flag, so it is taken once and lies there again until it is.
func _drop_dungeon_items() -> void:
	var index := 0
	for item: String in _dungeon_items():
		for n in int(_dungeon_items()[item]):
			var at := global_position + KEY_DROP + Vector2(KEY_STEP * index, 0.0)
			DungeonKeyPickup.drop(item, at, "%s:%s-%d" % [save_key(), item, n])
			index += 1


## The items as loot piles around `at` (main's EnemyLoot), else straight into the bag.
func _drop(items: Dictionary, at: Vector2) -> void:
	var run := Services.run()
	var world := Services.world()
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	var loot: Node = main.get(&"loot") as Node if main != null else null
	if loot != null and loot.has_method(&"drop_loot") and world != null:
		var list: Array = []
		for item_id: String in items:
			list.append({"item_id": item_id, "count": int(items[item_id])})
		loot.call(&"drop_loot", world.map_id(), at, list)
		return
	if run != null:
		for item_id: String in items:
			run.add_item(item_id, int(items[item_id]))


static func _is_cut_hit(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	if not (tags is Array):
		return false
	for tag: Variant in tags:
		if str(tag) in CUT_TAGS:
			return true
	return false


static func _player_crosses_webs() -> bool:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player) or world.player.is_dead():
		return false
	return world.player.crosses_webs()


func _unregister() -> void:
	var router := Services.router()
	if router != null and _area != null and is_instance_valid(_area):
		router.unregister_area(_area)


static func _rect_shape(rect: Rect2) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	return shape


# --- the look: the glint now and then ------------------------------------------------------------------

func _plan_glint(now: float) -> void:
	var constants := Services.constants()
	var every: Variant = constants.value("webs.glintEveryMs", [2600, 5200]) if constants != null else [2600, 5200]
	var low := 2600.0
	var high := 5200.0
	if every is Array and (every as Array).size() >= 2:
		low = float((every as Array)[0])
		high = float((every as Array)[1])
	_next_glint_ms = now + randf_range(low, maxf(low, high))


func _process(_delta: float) -> void:
	if _open:
		var world := Services.world()
		if _redrop_pending and world != null and world.entities_root() != null and world.player != null:
			_redrop_pending = false
			_drop_dungeon_items()
		if not _redrop_pending:
			set_process(false)
		return
	var now := float(Time.get_ticks_msec())
	if _glint_from_ms < 0.0 and now >= _next_glint_ms:
		_glint_from_ms = now
	if _glint_from_ms >= 0.0 or now < _shiver_until_ms:
		queue_redraw()
	if _glint_from_ms >= 0.0 and now - _glint_from_ms >= _glint_ms():
		_glint_from_ms = -1.0
		_plan_glint(now)
		queue_redraw()


func _glint_ms() -> float:
	var constants := Services.constants()
	return constants.number("webs.glintMs") if constants != null else 520.0


func _draw() -> void:
	if _texture == null and ResourceLoader.exists(ART):
		_texture = load(ART) as Texture2D
	if _texture == null:
		return
	var frame := Vector2(_texture.get_width() / float(FRAMES), _texture.get_height())
	var drawn := frame * ART_SCALE
	var now := float(Time.get_ticks_msec())
	var shake := 0.0
	if not Engine.is_editor_hint() and now < _shiver_until_ms:
		shake = sin(now * SHIVER_RATE / 1000.0) * SHIVER_PX * (_shiver_until_ms - now) / SHIVER_MS
	var origin := Vector2(-drawn.x / 2.0 + shake, FOOT_PX * ART_SCALE - drawn.y)
	var torn := _open or (Engine.is_editor_hint() and preview_open)
	draw_texture_rect_region(_texture, Rect2(origin, drawn), Rect2(Vector2(frame.x if torn else 0.0, 0.0), frame))
	if torn or _glint_from_ms < 0.0 or Engine.is_editor_hint():
		return
	var t := clampf((now - _glint_from_ms) / maxf(1.0, _glint_ms()), 0.0, 1.0)
	var strength := sin(t * PI)
	var size := GLINT_MIN_SCALE + (1.0 - GLINT_MIN_SCALE) * strength
	var centre := origin + GLINT_AT_PX * ART_SCALE
	draw_set_transform(centre, 0.0, Vector2.ONE * size)
	draw_texture_rect_region(_texture, Rect2(-GLINT_AT_PX * ART_SCALE, drawn),
		Rect2(Vector2(frame.x * 2.0, 0.0), frame), Color(1.0, 1.0, 1.0, strength))
	draw_set_transform(Vector2.ZERO)

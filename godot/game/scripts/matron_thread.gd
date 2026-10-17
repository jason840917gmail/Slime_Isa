@tool
extends Node2D
class_name MatronThreadScript
## Scene script of `object.matron-thread` (game/scenes/objects/matron-thread.tscn; roadmap 8.7,
## question 106; built 2026-10-17): the Orb-Weaver Matron's thread, a spool caught in a strand of
## her web at the top of the Weaver Hollow, the silk Burr needs for the Bow. The Silk skin's first
## lock (the Weaver Hollow design, "Her thread").
##
## - **Caught:** the spool hangs `hang_px` over the floor point (the root) on a strand that rises
##   `strand_top_px` into her web. Without the Silk skin (`player.crosses_webs()`; until roadmap 7.8
##   its stand-in, the story flag `skin.silk` that Pearl 2 sets) every hit clinks with
##   `refusal_text`, which says something is needed and never names the skin. While `boss_id` is
##   not beaten every hit clinks quietly.
## - **Cut:** with the skin, a weapon's hit (request tags in CUT_TAGS: the Spear, the old weapons)
##   cuts the strand: the web tear cue, a sparkle, and the spool drops to the floor (`drop_ms`).
## - **Taken:** the slime's centre within `take_radius` of the dropped spool puts `item_id` (a story
##   item, items.json) in the bag with its ceremony card (`AbilityCeremony.request_item`); the story
##   flag `flag_id` keeps it taken for good (saved). A full bag leaves it on the floor with a line.
##   The cut alone is not saved: an untaken spool hangs again on the next visit.
##
## Place the root where the spool should land (on the floor, at the foot of her web); `hang_px` and
## `strand_top_px` lift the spool and the strand. `preview_dropped` shows it on the floor.
##
## Owner: boss port (the Matron).

const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const SpiderWebPort := preload("res://game/enemy/spider_web_port.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const GroundShadowLook := preload("res://game/enemy/ground_shadow.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const STATE_CAUGHT := "caught"
const STATE_FALLING := "falling"
const STATE_DROPPED := "dropped"
const STATE_TAKEN := "taken"
const ART := "res://asset/MAPS/props/128x128-matron-spool.webp"
## 2 art px a unit would be 0.5; the spool is drawn a little smaller.
const ART_SCALE := 0.42
## The packed picture's bottom margin (px, scripts/art/pack-matron-art.py).
const FOOT_PX := 4.0
const CUT_TAGS: Array[String] = ["weapon", "spear"]
## A cut is an accepted hit of 1 (`mitigate_damage`), so the sender plays a hit, not a clink.
const RULE := {"priority": 0, "damageMultiplier": 1}
const TAGS: Array[String] = ["barrier", "web"]
const STRAND_COLOR := Color(0.95, 0.94, 0.9, 0.85)
## The cut leaves this much frayed strand hanging from the web.
const FRAYED_PX := 26.0
const CUT_TEXT := "The strand parts!"
const CUT_RISE := 40.0
const TAKE_RISE := 50.0
const TEXT_MS := 1800.0
const FULL_BAG_TEXT := "Your bag is full."
const FULL_BAG_EVERY_MS := 2000.0
const CUE_TAKE := &"SecretFound"
const CUE_LAND := &"DropLand"
const SHIVER_PX := 1.5
const SHIVER_RATE := 46.0
const SHIVER_MS := 220.0

## The spool's strand was cut. Payload {"itemId"}.
signal cut(payload: Dictionary)
## The spool was taken into the bag. Payload {"itemId", "flagId"}.
signal taken(payload: Dictionary)
## A hit was refused (the clink). Payload {"crosses": bool}.
signal refused(payload: Dictionary)

## The story item the spool is (items.json).
@export var item_id: String = "matron-thread"
## Story flag set when it is taken (read at load: gone for good).
@export var flag_id: String = "matron-thread.taken"
## Hits clink quietly until this boss is beaten ("" = never).
@export var boss_id: String = "orb-weaver-matron"
## The spool's bottom over the floor point while caught, and the strand's top (her web).
@export var hang_px: float = 90.0:
	set(value):
		hang_px = value
		_apply()
@export var strand_top_px: float = 200.0:
	set(value):
		strand_top_px = value
		queue_redraw()
@export var take_radius: float = 34.0
## Its fall to the floor once cut.
@export var drop_ms: float = 320.0
## Said when a hit cannot cut it (no Silk skin): never naming the skin.
@export var refusal_text: String = "Sticky silk holds it fast. You need a way with webs."
## Editor only: show it dropped on the floor.
@export var preview_dropped: bool = false:
	set(value):
		preview_dropped = value
		_apply()

var _state: String = STATE_CAUGHT
var _cut_at: float = 0.0
var _spool: Sprite2D
var _shadow: GroundShadowLook
var _area: Area2D
var _shiver_until_ms: float = 0.0
var _next_full_line_ms: float = 0.0


func _ready() -> void:
	_spool = SheetSprite.new()
	_spool.name = "Spool"
	_spool.centered = false
	_spool.offset = Vector2(-64.0, -128.0 + FOOT_PX)
	_spool.scale = Vector2.ONE * ART_SCALE
	_spool.sheet_path = ART
	_shadow = GroundShadowLook.new()
	_shadow.name = "Shadow"
	add_child(_shadow, false, Node.INTERNAL_MODE_FRONT)
	add_child(_spool, false, Node.INTERNAL_MODE_FRONT)
	if Engine.is_editor_hint():
		_apply()
		return
	var run := Services.run()
	if run != null and not flag_id.is_empty() and run.has_flag(flag_id):
		_state = STATE_TAKEN
		visible = false
		set_physics_process(false)
		return
	_area = Area2D.new()
	_area.name = "DamageArea"
	_area.collision_layer = 8
	_area.collision_mask = 0
	_area.monitoring = false
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	var hurt := _hurt_rect()
	box.size = hurt.size
	shape.shape = box
	shape.position = hurt.get_center()
	_area.add_child(shape)
	add_child(_area)
	var router := Services.router()
	if router != null:
		router.register_area(_area, self, RULE, TAGS)
	_apply()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_unregister()


## "caught", "falling", "dropped" or "taken".
func get_state() -> String:
	return _state


func is_taken() -> bool:
	return _state == STATE_TAKEN


## The spool's hurtbox while caught (round it and the strand's foot), from the root.
func _hurt_rect() -> Rect2:
	return Rect2(-30.0, -hang_px - 84.0, 60.0, 88.0)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var now := Services.now_ms()
	if _state == STATE_FALLING:
		if now - _cut_at >= maxf(1.0, drop_ms):
			_state = STATE_DROPPED
			var feel := Services.feel()
			if feel != null:
				feel.audio_cue(CUE_LAND)
		_apply()
	elif _state == STATE_DROPPED:
		var world := Services.world()
		var player: Node = world.player if world != null else null
		if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
			return
		if (player.call(&"get_centre") as Vector2).distance_to(global_position) <= take_radius:
			take()
	if now < _shiver_until_ms + 1.0:
		_apply()


# --- the damage contract -----------------------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _state != STATE_CAUGHT}


func can_receive_damage(input: Dictionary) -> Dictionary:
	if _state != STATE_CAUGHT:
		return {"accepted": false, "reason": "dead"}
	var request: Dictionary = input.get("request", {})
	var crosses := _player_crosses_webs()
	if crosses and _boss_beaten() and _is_cut_hit(request):
		return {"accepted": true}
	_shiver_until_ms = Services.now_ms() + SHIVER_MS
	refused.emit({"crosses": crosses})
	if crosses or not _boss_beaten():
		return {"accepted": false, "reason": BlastBarrier.REASON_IMMUNE}
	return BlastBarrier.refuse(global_position - Vector2(0.0, hang_px + 30.0), refusal_text)


func mitigate_damage(_input: Dictionary) -> float:
	return 1.0


func commit_damage(_commit: Dictionary) -> void:
	cut_strand()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


## The strand parts and the spool falls (the Spear's cut; scripts may call it).
func cut_strand() -> void:
	if _state != STATE_CAUGHT:
		return
	_state = STATE_FALLING
	_cut_at = Services.now_ms()
	_unregister()
	if _area != null:
		_area.queue_free()
		_area = null
	var at := global_position - Vector2(0.0, hang_px + 20.0)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(SpiderWebPort.TORN_CUE)
		feel.particles(SpiderWebPort.TORN_PARTICLES, at)
		feel.floating_text(at - Vector2(0.0, CUT_RISE), CUT_TEXT, &"cyan", true, TEXT_MS)
	cut.emit({"itemId": item_id})
	_apply()


## The slime takes the dropped spool: into the bag (with its ceremony), the flag, gone.
func take() -> bool:
	if _state != STATE_DROPPED:
		return false
	var run := Services.run()
	if run == null:
		return false
	var feel := Services.feel()
	if run.add_item(item_id, 1) <= 0:
		var now := float(Time.get_ticks_msec())
		if feel != null and now >= _next_full_line_ms:
			_next_full_line_ms = now + FULL_BAG_EVERY_MS
			feel.floating_text(global_position - Vector2(0.0, TAKE_RISE), FULL_BAG_TEXT, &"orange", false)
		return false
	_state = STATE_TAKEN
	if not flag_id.is_empty():
		run.set_flag(flag_id)
	visible = false
	set_physics_process(false)
	if feel != null:
		feel.audio_cue(CUE_TAKE)
		feel.particles(SpiderWebPort.TORN_PARTICLES, global_position)
		feel.floating_text(global_position - Vector2(0.0, TAKE_RISE), ItemCatalog.item_name(item_id), &"yellow", true, TEXT_MS)
	if is_inside_tree() and AbilityCeremony.enabled(get_tree()):
		AbilityCeremony.request_item(get_tree(), item_id)
	taken.emit({"itemId": item_id, "flagId": flag_id})
	return true


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


func _boss_beaten() -> bool:
	if boss_id.is_empty():
		return true
	var run := Services.run()
	return run != null and boss_id in (run.world.get("defeated_boss_ids", []) as Array)


func _unregister() -> void:
	var router := Services.router()
	if router != null and _area != null and is_instance_valid(_area):
		router.unregister_area(_area)


# --- the look ----------------------------------------------------------------------------------------

## How high the spool's bottom is now: caught, falling (an ease-in drop) or on the floor.
func _lift() -> float:
	if Engine.is_editor_hint():
		return 0.0 if preview_dropped else hang_px
	match _state:
		STATE_CAUGHT:
			return hang_px
		STATE_FALLING:
			var t := clampf((Services.now_ms() - _cut_at) / maxf(1.0, drop_ms), 0.0, 1.0)
			return hang_px * (1.0 - t * t)
	return 0.0


func _apply() -> void:
	if _spool == null:
		return
	var shake := 0.0
	if not Engine.is_editor_hint():
		var now := Services.now_ms()
		if now < _shiver_until_ms:
			shake = sin(now * SHIVER_RATE / 1000.0) * SHIVER_PX * (_shiver_until_ms - now) / SHIVER_MS
	var lift := _lift()
	_spool.position = Vector2(shake, -lift)
	_shadow.size = Vector2(16.0, 5.0) * (1.0 - 0.4 * clampf(lift / maxf(1.0, hang_px), 0.0, 1.0))
	_shadow.strength = 1.0 - 0.6 * clampf(lift / maxf(1.0, hang_px), 0.0, 1.0)
	queue_redraw()


## The strand: from the spool's top up into her web while it is caught; a frayed end once cut.
func _draw() -> void:
	var top := -strand_top_px
	var caught := _state == STATE_CAUGHT and not (Engine.is_editor_hint() and preview_dropped)
	if caught:
		var spool_top := -_lift() - (128.0 - FOOT_PX) * ART_SCALE + 6.0
		draw_line(Vector2(0.0, spool_top), Vector2(0.0, top), STRAND_COLOR, 2.0, true)
	elif _state != STATE_TAKEN:
		draw_line(Vector2(0.0, top + FRAYED_PX), Vector2(0.0, top), STRAND_COLOR, 2.0, true)

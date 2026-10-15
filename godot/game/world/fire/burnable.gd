extends Node
## Something dry that only fire takes (bomb-lantern-and-secrets design section 2 "Burnables"; the
## pattern of game/scripts/tom_web.gd; docs/godot/DARKNESS.md): a deadthorn hedge on an old road,
## later hay heaps, old banners, rotten planks and dry root plugs.
##
## - **A fire target** (group `fire_targets`, fire_targets.gd): a flame (or a blast) sets it on fire
##   (`receive_fire`: true, the flame stops there).
## - **It burns** for `abilities.lantern.burnable.burnMs` (600 ms, gameplay time): flames run along
##   it, it is a light source, halfway it shows its burnt look and sets fire to every burnable it
##   touches (its fire box grown by `spreadPx`), and at the end it stops colliding.
## - **It stays burnt**: the story flag `burnt.<persistence key or path>` (RunState), so it shows
##   burnt and open on the way back.
## - **Weapons refuse it**: every other hit clinks (`immune`) with the line "Too dry and hard. Fire
##   would take it." (at most every HINT_EVERY_MS).
##
## Node: under the burnable's root (a StaticBody2D whose shapes block the way), with its look
## (`visual`, a two-frame Sprite2D: whole | burnt) and its hurtbox (`damage_area`).
##
## Owner: world (fire and darkness).

const Services := preload("res://game/shared/services.gd")
const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

const GROUP := &"burnables"
const FLAG_PREFIX := "burnt."
const PERSISTENCE_KEY_META := &"persistence_key"
const INSTANCE_ID_META := &"instance_id"
const RULE := {"priority": 0, "damageMultiplier": 1}
const REFUSAL := "Too dry and hard. Fire would take it."
const HINT_EVERY_MS := 2500.0
const TEXT_MS := 2400.0
const CUE_IGNITE := &"GulpSpit"
const FRAME_WHOLE := 0
const FRAME_BURNT := 1
## The fire's look: flames along the hedge (the Lantern's flame art pointing up), their glow, and
## the light while it burns.
const FLAME_SHEET := preload("res://asset/abilities/lantern/flame-4x1.webp")
const FLAME_FRAMES := 4
const FLAME_FRAME_MS := 60.0
const FLAMES := 6
const FLAME_SCALE := 0.62
const SCORCH := Color(0.45, 0.22, 0.12)
const LIGHT_PX := 170.0
const SMOKE_PUFFS := 4
const EMBERS := 14
## The share of the burn at which it shows burnt and spreads.
const TURN_SHARE := 0.55

## The look: frame 0 whole, frame 1 burnt.
@export var visual: Sprite2D
## The hurtbox weapons hit (they are refused).
@export var damage_area: Area2D
## The body whose shapes block the way until it has burnt (default: the parent).
@export var blocker: CollisionObject2D
## The fire box above its feet (width x height, px): what a flame must touch and what spreads.
@export var fire_size: Vector2 = Vector2(150, 70)
## The text rises this far over its feet.
@export var text_rise: float = 90.0

var _registered: Area2D
var _burning_from_ms: float = -1.0
var _burnt: bool = false
var _spread: bool = false
var _turned: bool = false
var _flames: Array[Sprite2D] = []
var _next_hint_ms: float = 0.0
var _seed: float = 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(FireTargets.FIRE_GROUP)
	add_to_group(FireTargets.LIGHT_GROUP)


func _ready() -> void:
	_seed = randf() * 100.0
	if blocker == null:
		blocker = get_parent() as CollisionObject2D
	var run := Services.run()
	if run != null and run.has_flag(burnt_flag()):
		_show_burnt()
		return
	var router := Services.router()
	if damage_area != null and router != null:
		router.register_area(damage_area, self, RULE, [])
		_registered = damage_area


func _exit_tree() -> void:
	_unregister()


func is_burnt() -> bool:
	return _burnt


func is_burning() -> bool:
	return _burning_from_ms >= 0.0 and not _burnt


## Fire target: it catches fire (once).
func receive_fire(_hit: Dictionary) -> bool:
	if _burnt or is_burning():
		return false
	ignite()
	return true


## The fire box: `fire_size` centred over its feet.
func fire_rect() -> Rect2:
	var root := get_parent() as Node2D
	var feet := root.global_position if root != null else Vector2.ZERO
	return Rect2(feet + Vector2(-fire_size.x * 0.5, -fire_size.y), fire_size)


## Sets it on fire.
func ignite() -> void:
	if _burnt or is_burning():
		return
	_burning_from_ms = Services.now_ms()
	_make_flames()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_IGNITE)


## Light source while it burns.
func light_circle() -> Vector3:
	if not is_burning():
		return Vector3.ZERO
	var rect := fire_rect()
	var at := rect.get_center()
	return Vector3(at.x, at.y, FireTargets.flicker(LIGHT_PX, _seed))


## `burnt.<key>`: the placement's persistence key, else its instance id, else its path.
func burnt_flag() -> String:
	var node: Node = self
	while node != null:
		var key: Variant = node.get_meta(PERSISTENCE_KEY_META, "")
		if key is String and not (key as String).is_empty():
			return FLAG_PREFIX + key
		var instance_id: Variant = node.get_meta(INSTANCE_ID_META, "")
		if instance_id is String and not (instance_id as String).is_empty():
			return FLAG_PREFIX + instance_id
		node = node.get_parent()
	return FLAG_PREFIX + str(get_path())


# --- the router (weapons are refused) -----------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 0.0 if _burnt else 1.0, "max_hp": 1.0, "dead": _burnt}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	if _burnt:
		return {"accepted": false, "reason": "dead"}
	_hint()
	return {"accepted": false, "reason": "immune"}


func commit_damage(_commit: Dictionary) -> void:
	pass


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


# --- burning ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not is_burning():
		return
	var burn_ms := maxf(1.0, FireTargets.lantern_number("burnable.burnMs", 600.0))
	var t := clampf((Services.now_ms() - _burning_from_ms) / burn_ms, 0.0, 1.0)
	if not _turned and t >= TURN_SHARE:
		_turned = true
		if visual != null:
			visual.frame = FRAME_BURNT
	if not _spread and t >= TURN_SHARE * 0.6:
		_spread = true
		_spread_fire()
	if visual != null:
		visual.modulate = Color.WHITE.lerp(SCORCH, minf(1.0, t / TURN_SHARE)) if not _turned \
			else SCORCH.lerp(Color.WHITE, clampf((t - TURN_SHARE) / (1.0 - TURN_SHARE), 0.0, 1.0))
	_place_flames(t)
	if t >= 1.0:
		_finish()


func _spread_fire() -> void:
	var reach := fire_rect().grow(FireTargets.lantern_number("burnable.spreadPx", 24.0))
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node == self or not node.has_method(&"fire_rect"):
			continue
		if reach.intersects(node.call(&"fire_rect") as Rect2):
			node.call(&"ignite")


func _finish() -> void:
	_burning_from_ms = -1.0
	var run := Services.run()
	if run != null:
		run.set_flag(burnt_flag())
	var rect := fire_rect()
	for i in SMOKE_PUFFS:
		FireFx.smoke(rect.position + Vector2(rect.size.x * (float(i) + 0.5) / SMOKE_PUFFS, rect.size.y * 0.6))
	FireFx.embers(rect.get_center(), EMBERS)
	_show_burnt()


func _show_burnt() -> void:
	_burnt = true
	_unregister()
	for flame in _flames:
		if is_instance_valid(flame):
			flame.queue_free()
	_flames.clear()
	if visual != null:
		visual.frame = FRAME_BURNT
		visual.modulate = Color.WHITE
	if blocker != null:
		for child: Node in blocker.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				child.set_deferred(&"disabled", true)
	remove_from_group(FireTargets.FIRE_GROUP)


func _make_flames() -> void:
	var root := get_parent() as Node2D
	if root == null:
		return
	for i in FLAMES:
		var flame := Sprite2D.new()
		flame.texture = FLAME_SHEET
		flame.hframes = FLAME_FRAMES
		flame.rotation = PI / 2.0
		flame.z_index = 1
		flame.offset = Vector2(-30.0, 0.0)
		root.add_child(flame)
		_flames.append(flame)
	_place_flames(0.0)


## The flames start at the middle and run out to both ends, tall at the middle of the burn.
func _place_flames(t: float) -> void:
	var now := float(Time.get_ticks_msec())
	for i in _flames.size():
		var flame := _flames[i]
		var side := (float(i) + 0.5) / float(_flames.size()) - 0.5
		var reach := clampf(t * 2.2, 0.0, 1.0)
		var shown := absf(side) * 2.0 <= reach + 0.15
		flame.visible = shown
		var life := sin(clampf(t, 0.0, 1.0) * PI)
		var wobble := 1.0 + 0.12 * sin(now / 90.0 + float(i) * 1.7)
		flame.scale = Vector2.ONE * FLAME_SCALE * maxf(0.25, life) * wobble
		flame.position = Vector2(side * fire_size.x * 0.9, -fire_size.y * 0.35 + absf(side) * 10.0)
		flame.frame = (int(now / FLAME_FRAME_MS) + i) % FLAME_FRAMES


func _unregister() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func _hint() -> void:
	var now := float(Time.get_ticks_msec())
	if now < _next_hint_ms:
		return
	_next_hint_ms = now + HINT_EVERY_MS
	var feel := Services.feel()
	var root := get_parent() as Node2D
	if feel != null and root != null:
		feel.floating_text(root.global_position - Vector2(0.0, text_rise), REFUSAL, &"white", false, TEXT_MS)

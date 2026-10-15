extends Node2D
## Scene script of `object.goo-bomb` (game/scenes/objects/goo-bomb.tscn; bomb-lantern-and-secrets
## design section 1; BODY_SHAPES.md "Goo Bomb"; numbers in game-constants.json `abilities.gooBomb`).
## A jelly bomb: a ball of the slime's green goo with a glowing core and a small leaf fuse
## (asset/abilities/goo-bomb/bomb.webp, 2 px per unit, drawn at ART_SCALE).
##
## - **Spat out** (`spit_from`, GooBombSequence): it pops from the slime's mouth and hops `hopPx`
##   along the aim in `hopMs` with an arc of `hopArcPx`, stopping short of what blocks the slime
##   (walls, the cliffs of its level, deep water: a ray on the slime's mask).
## - **The fuse** (`fuseMs`, 3000, from the moment it leaves the mouth; the gameplay clock, so
##   hit-stop and menus hold it): it pulses from `pulseStartHz` to `pulseEndHz` (2 to 8 Hz, faster
##   the nearer the end), its core glows brighter, the leaf fuse sparks more, and it flashes white in
##   the last `flashMs` (500). Then it blows (GooBlast.detonate). `chain(delay_ms)` (a blast nearby)
##   and `receive_fire(hit)` (group `fire_targets`: the Lantern's flame) set it off sooner.
## - **The mouth:** a light liftable (group `suckable`: `can_take`, `origin`, `suck_info`, `take`;
##   held kind "goo-bomb" with "bomb" = this node's instance id). Q sucks it in and a Q tap throws it
##   (game/player/gulp/). The fuse keeps running in the mouth, where the held look pulses with it; if
##   it blows there the mouth empties and the slime is hurt. A throw carries it (`ride`) and lands it
##   where the throw ends, at a wall or at the first hurtbox (`land`: no break on impact); a hit on
##   the slime drops it whole beside it (`land`); death throws it away (`discard`). Landing on deep
##   water it sinks with a fizzle (no blast).
## - **Light:** group `light_sources`, `light_circle()`: about `lightRadiusPx` (40), pulsing.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")

const GROUP := &"goo_bombs"
const SUCKABLE_GROUP := &"suckable"
const FIRE_GROUP := &"fire_targets"
const LIGHT_GROUP := &"light_sources"
## The held kind (game/player/gulp/: the mouth, the held look, the throw).
const KIND := "goo-bomb"
const HELD_KEY := "bomb"
const TEXTURE_PATH := "res://asset/abilities/goo-bomb/bomb.webp"
## The art (96 x 112, bottom-aligned) at this scale: about 43 x 50 units.
const ART_SCALE := 0.45
const ART_SIZE := Vector2(96.0, 112.0)
## The leaf fuse's tip and the core's middle on the art, from its bottom middle (art px).
const FUSE_TIP_PX := Vector2(24.0, -108.0)
const CORE_PX := Vector2(-3.0, -44.0)
const CORE_COLOR := Color("#e6ff7a")
const SPARK_COLOR := Color("#ffd75a")
const SPARK_HOT := Color("#fff8d0")
const SHADOW := Color(0.0, 0.0, 0.0, 0.3)
const SHADOW_HALF := Vector2(17.0, 6.0)
## The fuse's look: the pulse's size and squash, the glow's alpha from start to end, the flash's
## blink rate and brightness.
const PULSE_GROW := 0.07
const GLOW_ALPHA := Vector2(0.25, 0.95)
const GLOW_SIZE := Vector2(0.55, 0.85)
const FLASH_HZ := 12.0
const FLASH_BRIGHT := 1.9
const SPARKS := Vector2(2.0, 7.0)
## The spit leaves the mouth this high over the feet (Mouth.MOUTH_RISE).
const MOUTH_RISE := 26.0
## The hop stops this far before what blocks it.
const WALL_MARGIN := 14.0
## Physics layers the hop ignores (bodies, not walls).
const PASS_LAYERS: Array[String] = ["player", "enemy", "npc"]
const TILE_ID_DATA_LAYER := "tile_id"
const DEEP_TILE_ID := "deep-water"
const CUE_SINK := &"GooBombSink"
const SINK_FALLBACK_CUE := &"BreakSoft"
const SINK_TEXT := "Fsss..."
## The light follows the bomb's core (this far over its ground point).
const LIGHT_RISE := 22.0

enum State { HOP, REST, CARRIED, RIDING, DONE }

## How close a flame must come to set it off (the Lantern's fire-target contract).
var fire_radius: float = 18.0

static var _texture: Texture2D
static var _glow: Texture2D
static var _additive: CanvasItemMaterial

var _state: State = State.REST
var _player: Node
var _fuse_ms: float = 3000.0
var _fuse_end_ms: float = 0.0
var _chain_at_ms: float = -1.0
var _hop_from := Vector2.ZERO
var _hop_to := Vector2.ZERO
var _hop_started_ms: float = 0.0
var _hop_ms: float = 260.0
var _hop_arc: float = 18.0
var _height: float = 0.0
var _phase: float = 0.0
var _pulse: float = 0.0
var _progress: float = 0.0
var _last_ms: float = -1.0
var _rider: Node2D
var _sparks: Array[Vector2] = []
@onready var _visual: Sprite2D = $Visual
@onready var _glow_sprite: Sprite2D = $Glow


static func setting(key: String) -> float:
	var constants := Services.constants()
	return constants.number(Definitions.GOO_BOMB_CONSTANTS + "." + key) if constants != null else 0.0


static func bomb_texture() -> Texture2D:
	if _texture == null and ResourceLoader.exists(TEXTURE_PATH):
		_texture = load(TEXTURE_PATH) as Texture2D
	return _texture


## A soft round glow (white, fading out), 128 px.
static func glow_texture() -> Texture2D:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.55))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 128
		texture.height = 128
		_glow = texture
	return _glow


static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


## The bomb a held state names ({"kind": "goo-bomb", "bomb": id}), or null.
static func from_held(held: Dictionary) -> Node:
	if str(held.get("kind", "")) != KIND:
		return null
	var id := int(held.get(HELD_KEY, 0))
	if id == 0 or not is_instance_id_valid(id):
		return null
	var node := instance_from_id(id) as Node
	return node if node != null and node.has_method(&"land") else null


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(SUCKABLE_GROUP)
	add_to_group(FIRE_GROUP)
	add_to_group(LIGHT_GROUP)


func _ready() -> void:
	if _visual != null and _visual.texture == null:
		_visual.texture = bomb_texture()
	if _glow_sprite != null:
		_glow_sprite.texture = glow_texture()
		_glow_sprite.material = additive_material()
	if _fuse_end_ms <= 0.0:
		_fuse_ms = setting("fuseMs")
		_fuse_end_ms = Services.now_ms() + _fuse_ms
	_look()


## Out of the slime's mouth: from its feet `feet` along `direction` (unit), the fuse lit now.
func spit_from(player: Node, feet: Vector2, direction: Vector2) -> void:
	_player = player
	var unit := direction.normalized() if direction != Vector2.ZERO else Vector2.DOWN
	_fuse_ms = setting("fuseMs")
	_fuse_end_ms = Services.now_ms() + _fuse_ms
	_hop_ms = maxf(1.0, setting("hopMs"))
	_hop_arc = setting("hopArcPx")
	_hop_from = feet + unit * 6.0
	var reach := _hop_reach(player, feet, unit, setting("hopPx"))
	_hop_to = feet + unit * maxf(6.0, reach)
	_hop_started_ms = Services.now_ms()
	_state = State.HOP
	global_position = _hop_from
	_height = MOUTH_RISE
	_look()


func ground_point() -> Vector2:
	if _state == State.CARRIED and _player != null and is_instance_valid(_player):
		var body := _player.get(&"body") as Node2D
		if body != null:
			return body.global_position
	if _state == State.RIDING and _rider != null and is_instance_valid(_rider):
		return _rider.global_position
	return global_position


## A blast nearby: it goes off `delay_ms` from now (or sooner if already due).
func chain(delay_ms: float) -> void:
	if _state == State.DONE:
		return
	var at := Services.now_ms() + maxf(0.0, delay_ms)
	if _chain_at_ms < 0.0 or at < _chain_at_ms:
		_chain_at_ms = at


## The Lantern's flame (group `fire_targets`): it blows at once. True (the flame is used up).
func receive_fire(_hit: Dictionary) -> bool:
	if _state == State.DONE:
		return false
	explode()
	return true


func light_circle() -> Vector3:
	if _state == State.DONE:
		return Vector3(global_position.x, global_position.y, 0.0)
	var at := ground_point() - Vector2(0.0, _height + LIGHT_RISE)
	var radius := setting("lightRadiusPx") * (0.8 + 0.25 * _pulse + 0.3 * _progress)
	return Vector3(at.x, at.y, radius)


# --- the mouth -----------------------------------------------------------------------------------

func can_take() -> bool:
	return _state == State.REST and is_inside_tree() and not is_queued_for_deletion()


func origin() -> Vector2:
	return global_position


func suck_info() -> Dictionary:
	return {"kind": KIND, "essence": "", "variant": 0, HELD_KEY: get_instance_id()}


## Sucked in: it rides inside the slime (hidden here; the mouth shows its look), its fuse running.
func take() -> void:
	var world := Services.world()
	_player = world.player if world != null else _player
	_state = State.CARRIED
	visible = false


## Thrown: it flies with the throw (`rider`, the ThrownObject) until `land`.
func ride(rider: Node2D) -> void:
	_state = State.RIDING
	_rider = rider
	visible = false


## Back on the ground at `at` (a throw's end, a drop): it rests there, ticking (or sinks in deep
## water).
func land(at: Vector2) -> void:
	if _state == State.DONE:
		return
	_rider = null
	_state = State.REST
	_height = 0.0
	global_position = at
	visible = true
	if _deep_at(at):
		_sink()
		return
	_look()


## Gone without a blast (the slime died holding it).
func discard() -> void:
	_state = State.DONE
	queue_free()


# --- the fuse ------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _state == State.DONE:
		return
	var now := Services.now_ms()
	if (_chain_at_ms >= 0.0 and now >= _chain_at_ms) or now >= _fuse_end_ms:
		explode()
		return
	match _state:
		State.HOP:
			var t := clampf((now - _hop_started_ms) / _hop_ms, 0.0, 1.0)
			global_position = _hop_from.lerp(_hop_to, t)
			_height = MOUTH_RISE * (1.0 - t) * (1.0 - t) + 4.0 * _hop_arc * t * (1.0 - t)
			if t >= 1.0:
				land(_hop_to)
				if _state == State.DONE:
					return
		State.CARRIED:
			global_position = ground_point()
		State.RIDING:
			if _rider == null or not is_instance_valid(_rider):
				land(global_position)
			else:
				global_position = _rider.global_position
	var step := 0.0 if _last_ms < 0.0 else maxf(0.0, now - _last_ms)
	_last_ms = now
	_progress = clampf(1.0 - (_fuse_end_ms - now) / maxf(1.0, _fuse_ms), 0.0, 1.0)
	var hz := lerpf(setting("pulseStartHz"), setting("pulseEndHz"), _progress * _progress)
	_phase = fmod(_phase + step / 1000.0 * hz, 1.0)
	_pulse = 0.5 + 0.5 * sin(_phase * TAU)
	_look()


## The blast now, where the bomb is (at the slime's feet when it is in the mouth).
func explode() -> void:
	if _state == State.DONE:
		return
	var in_mouth := _state == State.CARRIED
	var at := ground_point()
	if _state == State.RIDING and _rider != null and is_instance_valid(_rider):
		_rider.queue_free()
	_state = State.DONE
	if in_mouth and _player != null and is_instance_valid(_player):
		var mouth: Variant = _player.call(&"get_mouth")
		if mouth is Object:
			var held: Dictionary = (mouth as Object).get(&"held")
			if from_held(held) == self:
				(mouth as Object).call(&"clear_held")
			elif bool((mouth as Object).call(&"is_pulling")):
				# It blew while still flying in: the pull and the suck end.
				(mouth as Object).call(&"clear")
	GooBlast.detonate(at, in_mouth, self)
	queue_free()


# --- the look ------------------------------------------------------------------------------------

func _look() -> void:
	var remaining := _fuse_end_ms - Services.now_ms()
	var flashing := remaining <= setting("flashMs")
	var blink := flashing and fmod(Services.now_ms() / 1000.0 * FLASH_HZ, 1.0) < 0.5
	var bright := FLASH_BRIGHT if blink else 1.0 + 0.25 * _progress * _pulse
	var grow := 1.0 + PULSE_GROW * _pulse * (0.6 + 0.8 * _progress)
	if _state == State.CARRIED:
		_pulse_held(grow, bright)
		return
	if _visual != null:
		_visual.position = Vector2(0.0, -_height)
		_visual.scale = Vector2(ART_SCALE * grow, ART_SCALE * (2.0 - grow))
		_visual.modulate = Color(bright, bright, bright, 1.0)
	if _glow_sprite != null:
		_glow_sprite.position = Vector2(0.0, -_height) + CORE_PX * ART_SCALE
		_glow_sprite.scale = Vector2.ONE * lerpf(GLOW_SIZE.x, GLOW_SIZE.y, _progress) * (0.85 + 0.3 * _pulse)
		_glow_sprite.modulate = Color(CORE_COLOR, lerpf(GLOW_ALPHA.x, GLOW_ALPHA.y, _progress) * (0.55 + 0.45 * _pulse) \
			* (1.4 if blink else 1.0))
	_sparks.clear()
	var count := int(round(lerpf(SPARKS.x, SPARKS.y, _progress)))
	for i in count:
		_sparks.append(Vector2.from_angle(randf() * TAU) * randf_range(1.0, 4.0 + 5.0 * _progress))
	queue_redraw()


## In the mouth: the slime's held look (Mouth's "HeldInside") pulses and flashes with the fuse.
func _pulse_held(grow: float, bright: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var body := _player.get(&"body") as Node2D
	var inside := body.get_node_or_null(^"HeldInside") as Node2D if body != null else null
	if inside == null:
		return
	if not inside.has_meta(&"goo_bomb_rest_scale"):
		inside.set_meta(&"goo_bomb_rest_scale", inside.scale)
	inside.scale = (inside.get_meta(&"goo_bomb_rest_scale") as Vector2) * grow
	inside.modulate = Color(bright, bright, bright, inside.modulate.a)


func _draw() -> void:
	if _state == State.DONE or _state == State.CARRIED or _state == State.RIDING:
		return
	var shrink := clampf(1.0 - _height / 60.0, 0.5, 1.0)
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * i / 16.0
		points.append(Vector2(cos(angle) * SHADOW_HALF.x, sin(angle) * SHADOW_HALF.y) * shrink)
	draw_colored_polygon(points, SHADOW)
	var tip := Vector2(0.0, -_height) + FUSE_TIP_PX * ART_SCALE * Vector2(1.0, 1.0)
	for spark in _sparks:
		draw_line(tip, tip + spark, Color(SPARK_COLOR, 0.9), 1.4)
	draw_circle(tip, 1.6 + 1.2 * _pulse, SPARK_HOT)


# --- helpers -------------------------------------------------------------------------------------

## How far a hop from `feet` along `unit` gets (at most `distance`) before what blocks the slime.
static func _hop_reach(player: Node, feet: Vector2, unit: Vector2, distance: float) -> float:
	var body := player.get(&"body") as CharacterBody2D if player != null else null
	if body == null or not body.is_inside_tree() or distance <= 0.0:
		return distance
	var mask := body.collision_mask
	for layer_name: String in PASS_LAYERS:
		mask &= ~_layer_bit(layer_name)
	var space := body.get_world_2d().direct_space_state
	var exclude: Array[RID] = player.call(&"body_rids")
	var query := PhysicsRayQueryParameters2D.create(feet, feet + unit * (distance + WALL_MARGIN), mask, exclude)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return distance
	return clampf(feet.distance_to(hit["position"]) - WALL_MARGIN, 0.0, distance)


static func _layer_bit(layer_name: String) -> int:
	for i in range(1, 33):
		if str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % i, "")) == layer_name:
			return 1 << (i - 1)
	return 0


static func _deep_at(point: Vector2) -> bool:
	var world := Services.world()
	var ground: TileMapLayer = world.ground_layer if world != null else null
	if ground == null or not is_instance_valid(ground):
		return false
	var data := ground.get_cell_tile_data(ground.local_to_map(ground.to_local(point)))
	return data != null and str(data.get_custom_data(TILE_ID_DATA_LAYER)) == DEEP_TILE_ID


## Deep water: it sinks with a splash and a fizzle, no blast.
func _sink() -> void:
	_state = State.DONE
	var feel := Services.feel()
	if feel != null:
		feel.particles(&"slime-splash", global_position)
		var root: Node = feel.global_audio()
		feel.audio_cue(CUE_SINK if root != null and root.find_child(String(CUE_SINK), true, false) != null else SINK_FALLBACK_CUE)
		feel.floating_text(global_position - Vector2(0.0, 30.0), SINK_TEXT, &"white", false)
	queue_free()

extends Node2D
## The Goo Bomb's blast (bomb-lantern-and-secrets design section 1 "The blast"; BODY_SHAPES.md "Goo
## Bomb"; numbers in game-constants.json `abilities.gooBomb`). `detonate` runs it at a bomb's ground
## point and leaves this node in the world for the look and the light:
##
## - **Enemies:** every hurtbox (not the slime's, not a resource, not a blast target's) in the ground
##   ellipse `ellipse` (176 x 120, wider than tall, as the Slam's) around the bomb, on the height level
##   of the ground under it, gets one router hit through AbilityWorld.strike_targets with the rework
##   `hit` (HitReaction.build_hit of `hit.class`, "slam": the Slam's inner hit, 40, launch 380 with a
##   16 px hop), pushed away from the bomb; the reactions decide the rest (the training dummies fly).
## - **The slime:** standing inside the ellipse (its feet), or with the bomb in its mouth (always),
##   it takes `selfDamage` (in the mouth `mouthDamage`) and a knock of `selfKnockback` away from the
##   bomb: an old-style request (the player has no rework reaction) from this node, so the slime's own
##   rules (i-frames, the Roll's and the Slam's untouchable windows, defense) apply.
## - **Blast targets:** every node in group `blast_targets` whose `blast_point()` (else its
##   global_position) lies in the ellipse gets `receive_blast(hit) -> bool` (the hit with
##   "position" set to the bomb's ground point): cracked walls and rubble heaps break.
## - **Chains:** every other bomb (group `goo_bombs`) in the ellipse goes off `chainDelayMs` later.
## - **Feel:** GameFeel.play_hit once (the per-swing hit-stop `feel.hitStopMs`, trauma `feel.trauma`,
##   the targets' material cue), each target's number, sparks and debris; the painted goo burst
##   (blast-6x1.webp, 6 frames), a flash, the Slam's shockwave ring over the ellipse, pebbles and dust
##   in the ground's colour, goo-splat blobs, and a goo splat on the ground that fades. Cue
##   GooBombBlast (its placeholder SlamImpact until baked).
## - **Light:** while it lasts the node is in group `light_sources`: `light_circle()` is a flash of
##   `blastLightRadiusPx` (220) fading over `blastLightMs` (250).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Self := preload("res://game/player/abilities/goo_blast.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")

const BLAST_TARGETS_GROUP := &"blast_targets"
const BOMBS_GROUP := &"goo_bombs"
const LIGHT_GROUP := &"light_sources"
const WEAPON_ID := "goo-bomb"
const TAGS: Array[String] = ["blast"]
const CUE_BLAST := &"GooBombBlast"
const PLACEHOLDER_CUES := {CUE_BLAST: &"SlamImpact"}
## The old Phaser centre is this far above the feet: the ellipse is centred there for hurtboxes, as
## the Slam's (hurtboxes sit around a body's centre).
const CENTRE_RISE := 27.56
## The painted burst: 6 frames of 320 px, drawn at BURST_SCALE, its middle BURST_RISE over the
## ground, FRAME_MS a frame.
const BURST_PATH := "res://asset/abilities/goo-bomb/blast-6x1.webp"
const BURST_FRAMES := 6
const BURST_SCALE := 0.66
const BURST_RISE := 30.0
const FRAME_MS := 70.0
## The splat on the ground: a goo puddle of the ellipse's SPLAT_SHARE, fading over SPLAT_MS.
const SPLAT_SHARE := 0.62
const SPLAT_MS := 3200.0
const SPLAT_COLOR := Color("#5fae2e")
const SPLAT_DARK := Color("#2d5a17")
const GOO_TINT := Color("#a6f05a")
const FLASH_TINT := Color("#f6ffc8")
const PEBBLES := 14
const PUFFS := 10
const GOO_BLOBS := 5
const TARGET_SPARKS := 5
const SPARK_PRESET := &"hit-spark"
const GOO_SPLAT_PRESET := &"goo-splat-sheet"
const WOBBLE_RADIUS := 220.0

var _age_ms: float = 0.0
var _half: Vector2 = Vector2(88.0, 60.0)
var _burst: Sprite2D
var _splat: Node2D
var _light_radius: float = 0.0
var _light_ms: float = 0.0
var _source_area: Area2D
var _splat_points := PackedVector2Array()


static func setting(key: String) -> float:
	var constants := Services.constants()
	return constants.number(Definitions.GOO_BOMB_CONSTANTS + "." + key) if constants != null else 0.0


static func section(key: String) -> Dictionary:
	var constants := Services.constants()
	return constants.dictionary(Definitions.GOO_BOMB_CONSTANTS + "." + key) if constants != null else {}


## The ellipse's half axes (`ellipse` width x height / 2).
static func half_size() -> Vector2:
	var ellipse := section("ellipse")
	return Vector2(float(ellipse.get("width", 176.0)), float(ellipse.get("height", 120.0))) * 0.5


## True when `point` lies in the ground ellipse of half axes `half` around `at`.
static func in_ellipse(point: Vector2, at: Vector2, half: Vector2) -> bool:
	if half.x <= 0.0 or half.y <= 0.0:
		return false
	var d := point - at
	return (d.x * d.x) / (half.x * half.x) + (d.y * d.y) / (half.y * half.y) <= 1.0


static func cue_or_placeholder(cue: StringName) -> StringName:
	var feel := Services.feel()
	var root: Node = feel.global_audio() if feel != null else null
	if root != null and root.find_child(String(cue), true, false) != null:
		return cue
	return PLACEHOLDER_CUES.get(cue, cue)


## The blast at the ground point `at`; `in_mouth` when it went off in the slime's mouth; `bomb` the
## bomb that blew (left out of the chain). Returns the blast node (null outside a world).
static func detonate(at: Vector2, in_mouth: bool, bomb: Node = null) -> Self:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return null
	var blast := Self.new()
	blast.name = "GooBlast"
	blast.z_index = AbilityFx.OVER_Z - 1
	parent.add_child(blast)
	blast.global_position = at
	blast._go(in_mouth, bomb)
	return blast


func light_circle() -> Vector3:
	if _light_ms <= 0.0 or _age_ms >= _light_ms:
		return Vector3(global_position.x, global_position.y, 0.0)
	var t := _age_ms / _light_ms
	return Vector3(global_position.x, global_position.y - BURST_RISE, _light_radius * (1.0 - t * t))


func _go(in_mouth: bool, bomb: Node) -> void:
	_half = half_size()
	_light_radius = setting("blastLightRadiusPx")
	_light_ms = setting("blastLightMs")
	add_to_group(LIGHT_GROUP)
	_make_source_area()
	var at := global_position
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var hit := _hit()
	var landed: Array[Dictionary] = []
	if player != null and is_instance_valid(player):
		landed = _strike_enemies(player, at, hit)
		_strike_slime(player, at, in_mouth)
	_strike_blast_targets(at, hit)
	_chain(at, bomb)
	_play_feel(at, hit, landed)
	_make_look(at)


func _physics_process(delta: float) -> void:
	_age_ms += delta * 1000.0
	if _burst != null:
		var frame := int(_age_ms / FRAME_MS)
		if frame >= BURST_FRAMES:
			_burst.queue_free()
			_burst = null
		else:
			_burst.frame = frame
	if _splat != null:
		_splat.modulate.a = clampf(1.0 - (_age_ms - SPLAT_MS * 0.5) / (SPLAT_MS * 0.5), 0.0, 1.0)
	if _age_ms >= _light_ms and is_in_group(LIGHT_GROUP):
		remove_from_group(LIGHT_GROUP)
	if _age_ms >= SPLAT_MS and _burst == null:
		queue_free()


# --- what it hits --------------------------------------------------------------------------------

func _hit() -> Dictionary:
	var numbers := section("hit")
	return HitReaction.build_hit(str(numbers.get("class", "slam")), {
		"step": 0,
		"last": true,
		"shape": "",
		"tags": TAGS.duplicate(),
		"hold_ms": 0.0,
		"launch_speed": float(numbers.get("launchSpeed", 0.0)),
		"hop_px": float(numbers.get("hopPx", 0.0)),
		"knock": Vector2.ZERO,
	})


## The enemies (and dummies) in the ellipse on the level of the ground under the bomb; returns the
## accepted outcomes ({"receiver", "area", "position", "result"}).
func _strike_enemies(player: Node, at: Vector2, hit: Dictionary) -> Array[Dictionary]:
	var landed: Array[Dictionary] = []
	var centre := at - Vector2(0.0, CENTRE_RISE)
	var router := Services.router()
	var targets: Array[Area2D] = []
	for area in AbilityWorld.hurtboxes_in_ellipse(player, centre, _half, _level(at)):
		var receiver: Object = router.receiver_for_area(area) if router != null else null
		if receiver is Node and _is_blast_target(receiver as Node):
			continue
		targets.append(area)
	if targets.is_empty():
		return landed
	var numbers := section("hit")
	var on_outcome := func(outcome: Dictionary) -> void:
		var result: Variant = outcome.get("result")
		if result is Dictionary and str((result as Dictionary).get("status", "")) == "accepted":
			landed.append(outcome)
	AbilityWorld.strike_targets(player, centre, targets, float(numbers.get("damage", 0.0)),
		float(numbers.get("launchSpeed", 0.0)), TAGS.duplicate(), WEAPON_ID, hit, on_outcome)
	return landed


## A node (or its parent) that takes blasts itself (a cracked wall's or a rubble heap's refusing
## hurtbox): the blast reaches it through `receive_blast`, never as damage.
static func _is_blast_target(node: Node) -> bool:
	return node.is_in_group(BLAST_TARGETS_GROUP) or (node.get_parent() != null and node.get_parent().is_in_group(BLAST_TARGETS_GROUP))


## The slime's own share: inside the ellipse, or the bomb in its mouth.
func _strike_slime(player: Node, at: Vector2, in_mouth: bool) -> void:
	var body := player.get(&"body") as Node2D
	if body == null:
		return
	var feet := body.global_position
	if not in_mouth and not in_ellipse(feet, at, _half):
		return
	var router := Services.router()
	var target := player.call(&"get_damage_area") as Area2D if player.has_method(&"get_damage_area") else null
	if router == null or target == null or _source_area == null:
		return
	var knock := feet - at
	if knock.length() < 1.0:
		var facing: Vector2 = player.call(&"get_facing")
		knock = -facing if facing != Vector2.ZERO else Vector2.DOWN
	var activation := router.begin_activation(self, [_source_area])
	router.route({
		"activation_id": activation,
		"source": self,
		"attack_area": _source_area,
		"target_area": target,
		"weapon_id": WEAPON_ID,
		"weapon_tags": TAGS.duplicate(),
		"damage_types": ["physical"],
		"base_damage": setting("mouthDamage" if in_mouth else "selfDamage"),
		"effects": [{"effect_id": "knockback", "potency": setting("selfKnockback")}],
		"impact": {"position": at, "knock": knock.normalized()},
	})
	router.end_activation(activation)


func _strike_blast_targets(at: Vector2, hit: Dictionary) -> void:
	var tree := get_tree()
	var sent := hit.duplicate(true)
	sent["position"] = at
	sent["half_size"] = _half
	for node: Node in tree.get_nodes_in_group(BLAST_TARGETS_GROUP):
		if not is_instance_valid(node) or not node.has_method(&"receive_blast"):
			continue
		var point: Vector2
		if node.has_method(&"blast_point"):
			point = node.call(&"blast_point")
		elif node is Node2D:
			point = (node as Node2D).global_position
		else:
			continue
		if in_ellipse(point, at, _half):
			node.call(&"receive_blast", sent.duplicate(true))


func _chain(at: Vector2, bomb: Node) -> void:
	var delay := setting("chainDelayMs")
	for other: Node in get_tree().get_nodes_in_group(BOMBS_GROUP):
		if other == bomb or not is_instance_valid(other) or not other.has_method(&"chain"):
			continue
		var point: Vector2 = other.call(&"ground_point")
		if in_ellipse(point, at, _half):
			other.call(&"chain", delay)


# --- the look and the feel -----------------------------------------------------------------------

func _play_feel(at: Vector2, hit: Dictionary, landed: Array[Dictionary]) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var numbers := section("feel")
	var reactions: Array[Dictionary] = []
	var killed := false
	for outcome: Dictionary in landed:
		var result: Dictionary = outcome["result"]
		var reaction: Variant = result.get("reaction")
		if reaction is Dictionary:
			reactions.append(reaction)
		killed = killed or bool(result.get("defeated", false))
	var swing := {"hitStopMs": float(numbers.get("hitStopMs", 0.0)), "trauma": float(numbers.get("trauma", 0.0))}
	var spec := HitJuice.swing_spec(swing, hit, reactions, 0, maxi(1, landed.size()), killed)
	spec["debris_preset"] = &""
	spec["number"] = 0
	feel.play_hit(spec, at - Vector2(0.0, BURST_RISE), Vector2.ZERO)
	for outcome: Dictionary in landed:
		_play_number(feel, outcome, at)
	feel.audio_cue(cue_or_placeholder(CUE_BLAST))


## One struck target's number, its material's sparks and its debris, flying away from the bomb.
func _play_number(feel: Node, outcome: Dictionary, at: Vector2) -> void:
	var result: Dictionary = outcome["result"]
	var damage := int(result.get("actual_damage", 0))
	if damage <= 0:
		return
	var hit := _hit()
	var spec := HitJuice.number_spec(damage, hit)
	var reaction: Variant = result.get("reaction")
	if reaction is Dictionary:
		var r: Dictionary = reaction
		var rf: Variant = r.get("feel", {})
		var feel_dict: Dictionary = rf if rf is Dictionary else {}
		var look := HitJuice.material_spec(str(feel_dict.get("material", r.get("material", ""))), true)
		look.erase("material_cue")
		spec.merge(look, true)
	spec.merge({"hit_stop_ms": 0.0, "trauma": 0.0, "kick_px": 0.0, "sparks": TARGET_SPARKS,
		"spark_preset": SPARK_PRESET, "sound_cue": &""}, true)
	var point: Vector2 = outcome.get("position", at)
	feel.call(&"play_hit", spec, point, (point - at).normalized())


func _make_look(at: Vector2) -> void:
	var feel := Services.feel()
	var tint := AbilityFx.ground_tint(at)
	AbilityFx.flash(at - Vector2(0.0, BURST_RISE), FLASH_TINT)
	AbilityFx.shockwave(at, _half * 2.0, GOO_TINT, 0.5)
	AbilityFx.debris(at, tint, PEBBLES, PUFFS, _half.y / _half.x)
	AbilityFx.wobble_liftables(at, WOBBLE_RADIUS)
	if feel != null:
		for i in GOO_BLOBS:
			var angle := TAU * float(i) / float(GOO_BLOBS) + randf() * 0.6
			var offset := Vector2(cos(angle) * _half.x, sin(angle) * _half.y) * randf_range(0.35, 0.75)
			feel.burst(GOO_SPLAT_PRESET, at + offset - Vector2(0.0, 6.0), offset.normalized(), Color.WHITE, 0.8)
	# The splat on the ground (under the bodies), then the burst over everything.
	_splat = Node2D.new()
	_splat.name = "Splat"
	_splat.z_as_relative = false
	_splat.z_index = AbilityFx.GROUND_Z
	_splat.draw.connect(_draw_splat)
	add_child(_splat)
	_splat_points = _blob_points(_half * SPLAT_SHARE)
	_splat.queue_redraw()
	if ResourceLoader.exists(BURST_PATH):
		_burst = Sprite2D.new()
		_burst.name = "Burst"
		_burst.texture = load(BURST_PATH) as Texture2D
		_burst.hframes = BURST_FRAMES
		_burst.scale = Vector2.ONE * BURST_SCALE
		_burst.position = Vector2(0.0, -BURST_RISE)
		add_child(_burst)


func _draw_splat() -> void:
	if _splat_points.size() < 3:
		return
	var dark := PackedVector2Array()
	for p in _splat_points:
		dark.append(p * 1.08 + Vector2(0.0, 2.0))
	_splat.draw_colored_polygon(dark, Color(SPLAT_DARK, 0.55))
	_splat.draw_colored_polygon(_splat_points, Color(SPLAT_COLOR, 0.6))
	var shine := PackedVector2Array()
	for p in _splat_points:
		shine.append(p * 0.45 + Vector2(-_half.x * 0.12, -_half.y * 0.12))
	_splat.draw_colored_polygon(shine, Color(GOO_TINT, 0.35))


## A lumpy goo puddle of half axes `half`.
static func _blob_points(half: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := 22
	var seed_phase := randf() * TAU
	for i in count:
		var angle := TAU * float(i) / float(count)
		var lump := 1.0 + 0.14 * sin(angle * 3.0 + seed_phase) + 0.08 * sin(angle * 7.0 - seed_phase * 2.0)
		points.append(Vector2(cos(angle) * half.x, sin(angle) * half.y) * lump)
	return points


## The level of the ground under the bomb (AbilityWorld.ANY_LEVEL without elevation).
static func _level(at: Vector2) -> int:
	var world := Services.world()
	if world == null or world.elevation == null:
		return AbilityWorld.ANY_LEVEL
	return world.elevation.level_at(at, 0)


## The attack area the slime's damage request comes from (no shape, no layers: a token for the
## router's activation).
func _make_source_area() -> void:
	_source_area = Area2D.new()
	_source_area.name = "BlastSource"
	_source_area.collision_layer = 0
	_source_area.collision_mask = 0
	_source_area.monitoring = false
	_source_area.monitorable = false
	add_child(_source_area)

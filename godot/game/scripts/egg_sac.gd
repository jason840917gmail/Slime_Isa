extends "res://game/enemy/patterned_enemy.gd"
class_name EggSacScript
## Scene script `game.egg-sac` (the bestiary's row 20, the Broodling's nest; docs/godot/BESTIARY.md
## "Broodling"): three silk egg pods glued to the ground, each with a curled spiderling inside. It
## never moves (rooted: knockbacks never slide it) and never bites; it pours Broodlings out.
##
## - **Quiet:** while the slime is out of its arena (its pen) it rests.
## - **Swell** (the tell, `swellMs`): `firstHatchMs` after the slime came in, then every
##   `hatchEveryMs`, while fewer than `maxBrood` Broodlings of its arena are alive: its top pod
##   swells and splits, a leg poking out.
## - **Hatch:** `hatchCount` Broodlings (`character.broodling`; never more than `maxBrood` alive)
##   pop out `hatchPx` in front of it toward the slime, `hatchSpreadRad` apart, with its arena; then
##   it is quiet again.
## - **Hits:** the Spear tears it slowly (its health); a Goo Bomb's blast (tag `blast`) bursts it at
##   once: the swarm stops. Burst, it lies torn open (`corpseMs`); the Broodlings already out stay
##   until they are popped.
##
## Owner: enemy builder.

const PHASE_QUIET := "quiet"
const PHASE_SWELL := "swell"
const FRAME_SAC := 0
const FRAME_HATCHING := 1
const FRAME_BURST := 2
const BLAST_TAG := "blast"
const BROOD_TYPE := "broodling"
const SCENE_PREFIX := "character."
## Every Broodling alive (the cap counts those of the same arena).
const BROOD_GROUP := &"broodlings"
const CUE_SWELL := &"GroundCreak"
const CUE_HATCH := &"DropPop"
const CUE_BURST := &"BreakSoft"
const GOO := &"slime-splash"
## Presentation: the quiet pulse and the swell's squash.
const PULSE := 0.025
const PULSE_MS := 380.0
const SWELL_SQUASH := Vector2(1.08, 1.1)

var _next_hatch_at: float = -1.0


func _ready() -> void:
	super()
	_transition(PHASE_QUIET, Services.now_ms())
	set_frame(FRAME_SAC)
	var world := Services.world()
	if world != null:
		world.packed_scene(SCENE_PREFIX + BROOD_TYPE)


func _step_pattern(now: float, _delta: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_QUIET:
			var pulse := sin(now / PULSE_MS) * PULSE
			set_look(0.0, Vector2(1.0 + pulse, 1.0 - pulse))
			if not engaged:
				_next_hatch_at = -1.0
				return
			if _next_hatch_at < 0.0:
				_next_hatch_at = now + pattern("firstHatchMs", 600.0)
			if now >= _next_hatch_at and brood_alive() < int(pattern("maxBrood", 5.0)):
				_transition(PHASE_SWELL, now)
				set_frame(FRAME_HATCHING)
				_cue(CUE_SWELL)
		PHASE_SWELL:
			var t := clampf(elapsed / maxf(1.0, pattern("swellMs", 500.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE.lerp(SWELL_SQUASH, sin(t * PI * 0.5)))
			if t >= 1.0:
				var count := mini(int(pattern("hatchCount", 2.0)), int(pattern("maxBrood", 5.0)) - brood_alive())
				for i in maxi(1, count):
					_hatch(target, (float(i) - float(count - 1) * 0.5) * pattern("hatchSpreadRad", 0.7))
				_transition(PHASE_QUIET, now)
				set_frame(FRAME_SAC)
				_next_hatch_at = now + pattern("hatchEveryMs", 1800.0)


## The live Broodlings of its arena (any sac's: a pen counts as one nest).
func brood_alive() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group(BROOD_GROUP):
		var brood := node as EnemyScript
		if brood == null or brood.is_defeated() or brood.is_queued_for_deletion():
			continue
		if _arena.is_empty() or brood.get_arena() == _arena:
			count += 1
	return count


## One Broodling out of the top pod, `hatchPx` toward the slime (turned `turn` radians), with this
## sac's arena.
func _hatch(target: Dictionary, turn: float = 0.0) -> void:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	var root := world.instantiate_scene(SCENE_PREFIX + BROOD_TYPE) as Node2D if world != null else null
	if root == null or parent == null:
		if root != null:
			root.free()
		return
	var brood: EnemyScript = null
	for child: Node in root.get_children():
		if child is EnemyScript:
			brood = child as EnemyScript
			break
	if brood == null:
		root.free()
		return
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre + Vector2.DOWN)
	var toward := ((slime - centre).normalized() if slime != centre else Vector2.DOWN).rotated(turn)
	var at := centre + toward * pattern("hatchPx", 30.0)
	if brood.has_method(&"set_hatched_from"):
		brood.call(&"set_hatched_from", centre)
	var parent_item := parent as CanvasItem
	var global_target := FeetAnchor.global_for_phaser_position(root, at)
	root.position = parent_item.get_global_transform().affine_inverse() * global_target \
		if parent_item != null and parent_item.is_inside_tree() else global_target
	parent.add_child(root)
	root.reset_physics_interpolation()
	var no_zones: Array[Dictionary] = []
	brood.configure_navigation({}, no_zones)
	brood.configure_arena(_arena.duplicate(true))
	_cue(CUE_HATCH)
	_puff(GOO, feet() + toward * 10.0)


func _shields(_request: Dictionary) -> bool:
	return false


## A Goo Bomb's blast bursts it at once.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, BLAST_TAG)


## Rooted to the ground: a stun never slides it.
func _slides_when_stunned() -> bool:
	return false


func _defeat() -> void:
	if is_defeated():
		return
	_cue(CUE_BURST)
	_puff(GOO, feet())
	super()

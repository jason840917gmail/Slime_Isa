extends "res://game/scripts/enemy.gd"
class_name MatronScript
## Scene script `game.matron` (Phaser `features/scripts/MatronScript.ts`): the Orb-Weaver Matron,
## the gloop-forest boss. Implements docs/godot/specs/matron.md section 3.
##
## Extends the base enemy as MatronScript extends EnemyScript: every step runs the whole base step
## first (the slime-spider AI, the web spit through the common ranged attack, the arena leash),
## then the phase machine below in `_after_enemy_step`, then the body moves once. Between volleys
## she fights like an orb weaver; every `volley_cadence_ms` she stops, marks `volley_points`
## circles (one on the slime) for `volley_telegraph_ms`, then the webs land: a slime inside a
## circle is hit and each circle becomes a web patch (`effect.<patch_effect_id>`, web_patch.gd).
## She rests `volley_rest_ms` afterwards. Every transition emits `phase_changed({phase, time})`
## (VolleySfx on `volley-telegraph`, SpitSfx on `volley-rest`).
##
## **The cocoon** (the Weaver Hollow's fight, 2026-10-17; matron spec section 8; roadmap 8.7,
## question 133), on while `cocoon_enabled` (today's Crown's camp, `weaver-hollow-matron-old.tscn`,
## turns it on through its `boss_overrides`; since the switch-over of 2026-11-25 the rebuilt Hollow
## fights the rework, matron_ram.gd; the open-world nest keeps the fight above):
## - **Cocooned:** she hangs in a web cocoon from her thread over its shadow (her feet). She never
##   walks; she still spits and volleys from inside. Every hit clinks with `clink_text`
##   (BlastBarrier.refuse). The cocoon breathes (the Cocoon Mimic's tell; `breath_ms`).
## - **Torn:** a Goo Bomb blast whose ellipse holds the shadow (`blast_point`, `receive_blast`; group
##   `blast_targets`) tears it: she drops to the floor dazed, solid and open for `open_ms`, and
##   every weapon hurts her, but no more than down to her round's floor (`round_floor`).
## - **Respin:** after `open_ms`, or as soon as the round's floor is reached, she climbs her thread
##   and spins a new cocoon in `respin_ms` (threads whirl: the tell). The cocoon closes into the
##   round her health is in.
## - **Rounds:** 1 above `round_two_below_hp`, 2 above `round_three_below_hp`, 3 below. Each hangs
##   the cocoon `round_hang_px[round - 1]` over its shadow. Round 2 webs a ring of `ring_patches`
##   floor webs `ring_radius` round the shadow (again every `ring_reweb_ms` while she is cocooned);
##   round 3 drops `egg_sac_scene` at each of `egg_sac_offsets` once (their Broodlings swarm and
##   drop energy shards, as kills do). No blast, no damage: she cannot be beaten without the Goo
##   Bomb.
## - **The Silk skin's exam** (the Pearl inside the dungeon, owner 2026-10-17;
##   docs/design/2026-10-17-pearl-mid-dungeon.md "The Matron's exam"): when the slime has the Silk
##   skin (SkinState; it always has in the Hollow, whose Pearl comes first) and `silk_exam` is on,
##   round 2 spins a **cage of web walls** (`object.web-wall`, not remembered) on a square
##   `ring_radius` round her shadow in place of the ring, its cut walls spun again every
##   `ring_reweb_ms` (never one the slime stands in): a thrown bomb stops in its silk (a throw ends
##   at the first hurtbox) and blows out of reach of her shadow ("A thrown bomb sticks in the
##   silk."), so the slime cuts a gap with the Spear or wades a wall at half speed, then casts
##   inside. Round 3 **webs the floor** round her shadow (`object.floor-web` cells out to
##   `floor_web_radius_px`), which the Silk slime walks and Rolls through. Both go with her (her
##   fall, a reset). Without the skin the built rounds above play.
## - **Beaten:** the cocoon unravels and she shrinks into an ordinary big orb-weaver (the
##   orb-weaver's own sheet) that scuttles off up through her web; her egg sacs and their brood
##   burst. The rewards are the camp scene's (Pearl 2, the full heart, her thread).
## The look is `cocoon_look` (game/bosses/matron_cocoon_look.gd), set from `_present` each step.
##
## Node: `EnemyScript` under the Matron's CharacterBody2D (feet origin, `depth_anchor (0, 30)`).
## All points are old Phaser positions (`get_centre()` = feet - (0, 30)). Spawned by the
## `gloop-matron-nest` boss camp (boss_camp.gd), which hands it its arena.
##
## Owner: boss port.

const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const CocoonLook := preload("res://game/bosses/matron_cocoon_look.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const PHASE_FIGHT := "fight"
const PHASE_VOLLEY_TELEGRAPH := "volley-telegraph"
const PHASE_VOLLEY_REST := "volley-rest"
const PHASE_DEAD := "dead"
## MatronScript.ts:78: the volley plays the side attack clip.
const CLIP_VOLLEY := "attack-side"
## MatronScript.ts:69: each volley turns its marks by 0.9 rad.
const VOLLEY_TURN_STEP := 0.9
## MatronScript.ts:53, 101: lower bounds of the telegraph time and the mark radius.
const MIN_VOLLEY_TELEGRAPH_MS := 500.0
const MIN_VOLLEY_RADIUS := 8.0
## MatronScript.ts:96: the landing's camera shake.
const VOLLEY_SHAKE_MS := 80.0
const VOLLEY_SHAKE_INTENSITY := 0.002
## Bosses are hit as enemies and bosses (UniversalSceneWorldController.ts:2199-2201).
const BOSS_RECEIVER_TAGS: Array[String] = ["enemy", "boss"]

## The cocoon's states (`get_shell`).
const SHELL_COCOONED := "cocooned"
const SHELL_TORN := "torn"
const SHELL_RESPIN := "respin"
## goo_blast.gd BLAST_TARGETS_GROUP: blasts reach her through `receive_blast`, never as damage.
const BLAST_GROUP := &"blast_targets"
const ENEMY_TYPE_GROUP_BROOD := &"broodlings"
## Presentation (the tear's line and burst, her fall, her climb, the brood's end).
const TEAR_TEXT := "The cocoon tears open!"
const TEAR_TEXT_RISE := 50.0
const TEAR_TEXT_MS := 1400.0
const TATTERS := &"dodge-dust"
const CUE_TEAR := &"WebTear"
const CUE_LAND := &"DropLand"
const CUE_RESPIN := &"MimicWrap"
const CUE_SACS := &"DropPop"
const LAND_SHAKE_MS := 120.0
const LAND_SHAKE_INTENSITY := 0.003
## While dazed she shivers this far sideways, this fast.
const DAZED_SHIVER_PX := 1.5
const DAZED_SHIVER_MS := 60.0
## Her climb takes this share of the respin; the new silk closes over the rest.
const CLIMB_SHARE := 0.6
## Her own poses in the cocoon fight (scripts/art/pack-matron-art.py; 384 px cells, standing on y 380):
## dazed twice (legs twitching), flinching from a hit, climbing her thread from behind. The pose
## sprite replaces the old orb-weaver sheet's Visual (the open-world nest keeps that one).
const POSE_SHEET := "res://asset/MAPS/enemies/384x384-tile_4x1-matron.webp"
const POSE_FRAMES := 4
const POSE_DAZED_A := 0
const POSE_DAZED_B := 1
const POSE_FLINCH := 2
const POSE_CLIMB := 3
## The pose's feet sit this far below the cell's bottom line (art px), so her claws reach the floor.
const POSE_OFFSET := Vector2(-192.0, -360.0)
const DAZED_TWITCH_MS := 320.0
const FLINCH_MS := 260.0
## Her retreat: the ordinary orb-weaver's sheet (13 poses, frame 8 from behind) and its placement
## (orb-weaver.tscn's Visual), grown from about her size down to `retreat_scale`.
const RETREAT_SHEET := "res://asset/MAPS/enemies/256x256-tile_13x1-orb-weaver.webp"
const RETREAT_FRAMES := 13
const RETREAT_FRAME_AWAY := 8
const RETREAT_OFFSET := Vector2(-128.0, -147.0)
const RETREAT_RISE := Vector2(0.0, -15.0)
const RETREAT_START_SCALE := 0.85
const RETREAT_SHRINK_S := 0.45
const RETREAT_SCUTTLE_S := 1.25
const RETREAT_STRIDE_S := 0.12
const UNRAVEL_S := 0.7
## Enough to burst any egg sac or Broodling (take_reaction_damage clamps to their health).
const BURST_DAMAGE := 1000000.0
## The Silk skin's exam: the cage's and the webbed floor's pieces (scene ids), the Goo Bombs' group
## (goo_bomb.gd), how near a wall's passage a resting bomb counts as stuck in it, the new silk's
## fade-in, and the floor webs' cell.
const CAGE_WALL_SCENE := "object.web-wall"
const FLOOR_WEB_SCENE := "object.floor-web"
const BOMBS_GROUP := &"goo_bombs"
const STUCK_REACH_PX := 30.0
const SPIN_IN_S := 0.35
const FLOOR_CELL := 64.0
const FLOOR_WEB_VARIANTS := 6

## JSON `firstVolleyDelayMs` (3500): from the spawn to the first volley.
@export var first_volley_delay_ms: float = 3500.0
## JSON `volleyCadenceMs` (6500): from the end of a rest to the next volley.
@export var volley_cadence_ms: float = 6500.0
## JSON `volleyTelegraphMs` (900, at least 500).
@export var volley_telegraph_ms: float = 900.0
## JSON `volleyRestMs` (1300).
@export var volley_rest_ms: float = 1300.0
## JSON `volleyPoints` (4): marks per volley, the first on the slime.
@export var volley_points: float = 4.0
## JSON `volleySpread` (170): distance of the other marks from the slime.
@export var volley_spread: float = 170.0
## JSON `volleyRadius` (56, at least 8).
@export var volley_radius: float = 56.0
## JSON `volleyDamage` (40 since 2026-11-24; 20 in Phaser).
@export var volley_damage: float = 40.0
## JSON `volleyKnockbackStrength` (120).
@export var volley_knockback_strength: float = 120.0
## JSON `patchEffectId` ("matron-web-patch"; "" = no patches).
@export var patch_effect_id: String = ""

@export_group("Cocoon (Weaver Hollow)")
## She fights from inside her cocoon (class notes). Off in the scene: the Weaver Hollow's camp turns
## it on (`boss_overrides`), the open-world nest keeps the old fight.
@export var cocoon_enabled: bool = false
## The cocoon's look (game/bosses/matron_cocoon_look.gd), a child of the body at the feet.
@export var cocoon_look: Node2D
## Torn: how long she lies open on the floor, and how long her fall to it takes (part of it).
@export var open_ms: float = 4000.0
@export var drop_ms: float = 260.0
## Her climb up the thread and the new cocoon.
@export var respin_ms: float = 1500.0
## Round 2 below this health, round 3 below the next (of 300: about 100 a round).
@export var round_two_below_hp: float = 200.0
@export var round_three_below_hp: float = 100.0
## The cocoon's bottom over its shadow in rounds 1, 2 and 3 (low, then higher).
@export var round_hang_px: PackedFloat32Array = PackedFloat32Array([60.0, 130.0, 130.0])
## Round 2's ring of floor webs (`patch_effect_id`) round her shadow.
@export var ring_patches: int = 8
@export var ring_radius: float = 130.0
@export var ring_reweb_ms: float = 5000.0
## Round 3's egg sacs, dropped once by her shadow (offsets from it, old Phaser centres).
@export var egg_sac_scene: String = "character.egg-sac"
@export var egg_sac_offsets: PackedVector2Array = PackedVector2Array([Vector2(-72.0, 36.0), Vector2(72.0, 36.0)])
## One breath of the cocoon (the tell), swell and sink.
@export var breath_ms: float = 2600.0
## Said (at most every 1.5 s, BlastBarrier) when a hit clinks off the cocoon.
@export var clink_text: String = "Woven too thick. It would take a blast."
## The Silk skin's exam (class notes): round 2's cage and round 3's webbed floor, when the slime has
## the Silk skin. Off: the built rounds always.
@export var silk_exam: bool = true
## The cage's web walls: `cage_walls_per_side` on each side of the square, `cage_thickness_px`
## deep, the front and back ones drawn `cage_height_px` tall (0: the web wall's own height).
@export var cage_walls_per_side: int = 2
@export var cage_thickness_px: float = 24.0
@export var cage_height_px: float = 100.0
## Said (BlastBarrier: at most every 1.5 s) when a bomb comes to rest in the cage's silk.
@export var cage_text: String = "A thrown bomb sticks in the silk."
## Round 3's webbed floor: the cells whose middles lie within this of her shadow, about this share
## of them (picked by the cell), inside her arena.
@export var floor_web_radius_px: float = 352.0
@export_range(0.0, 1.0) var floor_web_share: float = 0.8
## Her poses' size in the world (0.5: 2 art px a unit).
@export var pose_scale: float = 0.5
## Beaten: she scuttles this far up through her web, shrunk to this scale (the orb-weaver's 0.46 is
## an ordinary one).
@export var retreat_px: float = 260.0
@export var retreat_scale: float = 0.62
@export_group("")

## Payload {"phase": String, "time": float (Services.now_ms())}.
signal phase_changed(payload: Dictionary)
## The cocoon changed (cocoon fight only). Payload {"shell": String, "round": int, "time": float}.
signal shell_changed(payload: Dictionary)

var _phase: String = PHASE_FIGHT
var _phase_started_at: float = 0.0
var _next_volley_at: float = 0.0
## The marks of the current (or last) volley, old Phaser positions.
var _volley: Array[Vector2] = []
var _volley_sequence: int = 0
## The cocoon: its state, since when, the round (0 until the cocoon fight starts on the first step),
## the next re-web of round 2's ring, the egg sacs she dropped.
var _shell: String = SHELL_COCOONED
var _shell_started_at: float = 0.0
var _round: int = 0
var _next_reweb_at: float = INF
var _egg_sacs: Array[Node] = []
var _sacs_dropped: bool = false
var _landed: bool = false
var _body_layer: int = -1
var _visual_rest: Vector2 = Vector2.ZERO
## Her pose sprite in the cocoon fight (null outside it), and until when a hit makes her flinch.
var _pose: Sprite2D
var _flinch_until: float = 0.0
## The Silk skin's exam: the cage's holder and its walls by slot (a slot's wall may be gone or
## cut), the bombs already told they stuck, the webbed floor's holder.
var _cage: Node2D
var _cage_walls: Array = []
var _stuck_bombs: Dictionary = {}
var _floor_webs: Node2D


## Base `_ready`, then the first volley at now + first_volley_delay_ms (MatronScript.ts:32-35);
## warms the patch effect scene. The cocoon starts on the first step (its switch may come from the
## camp's overrides right after the spawn).
func _ready() -> void:
	super()
	_next_volley_at = Services.now_ms() + maxf(1.0, first_volley_delay_ms)
	if visual != null:
		_visual_rest = visual.position
	if cocoon_look != null:
		cocoon_look.set(&"state", CocoonLook.STATE_OFF)
	var world := Services.world()
	if world != null and not patch_effect_id.is_empty():
		world.packed_scene("effect." + patch_effect_id)


## Clears the telegraph, then the base exit (MatronScript.ts:125-128). Her cage and her webbed
## floor go with her (a reset frees her).
func _exit_tree() -> void:
	AttackTelegraph.clear_for(self)
	_clear_cage()
	_clear_floor_webs()
	super()


## "fight", "volley-telegraph", "volley-rest" or "dead".
func get_phase() -> String:
	return _phase


## Gameplay time the current phase started.
func get_phase_started_at() -> float:
	return _phase_started_at


## Gameplay time of the next volley (checked only while fighting).
func get_next_volley_at() -> float:
	return _next_volley_at


## The marks of the current (or last) volley.
func get_volley() -> Array[Vector2]:
	return _volley.duplicate()


## Volleys begun so far.
func get_volley_sequence() -> int:
	return _volley_sequence


## Matron spec 3.2 (MatronScript.ts:37-60), after the base step and before the body moves. In the
## cocoon fight the cocoon steps first; she volleys only from inside it, and never walks.
func _after_enemy_step(_delta: float) -> void:
	if is_defeated() or _phase == PHASE_DEAD or body == null:
		return
	var now := Services.now_ms()
	if _cocoon_on():
		_step_cocoon(now)
		if _shell != SHELL_COCOONED:
			return
		body.velocity = Vector2.ZERO
	if _phase == PHASE_FIGHT:
		# Never mid-spit; while walking back into her arena she waits.
		if is_returning_to_arena() or now < _next_volley_at or is_attacking():
			return
		var target := _primary_target()
		if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
			return
		begin_volley(now, target["centre"])
		return
	body.velocity = Vector2.ZERO
	if _phase == PHASE_VOLLEY_TELEGRAPH:
		if now - _phase_started_at >= maxf(MIN_VOLLEY_TELEGRAPH_MS, volley_telegraph_ms):
			_land_volley(now)
		return
	if _phase == PHASE_VOLLEY_REST and now - _phase_started_at >= maxf(1.0, volley_rest_ms):
		_next_volley_at = now + maxf(1.0, volley_cadence_ms)
		_transition_to(PHASE_FIGHT, now)


## `beginVolley` (MatronScript.ts:63-81): the marks, one on `at` (the slime's centre) and the rest
## `volley_spread` around it at evenly spaced angles turned by 0.9 rad per volley, clamped into the
## arena; the telegraph (circles plus a shadow at `at`); the side attack clip; phase
## volley-telegraph. False unless fighting (and, in the cocoon fight, cocooned).
func begin_volley(now: float, at: Vector2) -> bool:
	if is_defeated() or _phase != PHASE_FIGHT or (_cocoon_on() and _shell != SHELL_COCOONED):
		return false
	cancel_attack()
	var count := maxi(1, roundi(volley_points))
	var spread := maxf(0.0, volley_spread)
	var arena := get_arena()
	var turn := fmod(float(_volley_sequence) * VOLLEY_TURN_STEP, TAU)
	var points: Array[Vector2] = [at]
	for index in range(1, count):
		var angle := turn + (float(index - 1) / float(maxi(1, count - 1))) * TAU
		points.append(at + Vector2(cos(angle), sin(angle)) * spread)
	_volley.clear()
	for point: Vector2 in points:
		_volley.append(BossArena.clamp_point(arena, point) if not arena.is_empty() else point)
	_volley_sequence += 1
	AttackTelegraph.show_for(self, volley_shapes(), at)
	_play_animation(CLIP_VOLLEY, true)
	_transition_to(PHASE_VOLLEY_TELEGRAPH, now)
	return true


## The volley's marks as AreaShapes entries: circles of max(8, volley_radius) (MatronScript.ts:100-109).
func volley_shapes() -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var circle := CircleShape2D.new()
	circle.radius = maxf(MIN_VOLLEY_RADIUS, volley_radius)
	for point: Vector2 in _volley:
		shapes.append({"shape": circle, "transform": Transform2D(0.0, point)})
	return shapes


# --- the cocoon (the Weaver Hollow's fight) -----------------------------------------------------

## "cocooned", "torn" or "respin" (always "cocooned" outside the cocoon fight).
func get_shell() -> String:
	return _shell


## Gameplay time the cocoon's state began.
func get_shell_started_at() -> float:
	return _shell_started_at


## 1, 2 or 3 in the cocoon fight (0 before its first step and outside it).
func get_round() -> int:
	return _round


## True while she lies torn out of her cocoon (weapons hurt her).
func is_open() -> bool:
	return _cocoon_on() and _shell == SHELL_TORN


## The health her round cannot take her below: round 1 `round_two_below_hp`, round 2
## `round_three_below_hp`, round 3 none (0).
func round_floor() -> float:
	match _round:
		1:
			return maxf(0.0, round_two_below_hp)
		2:
			return maxf(0.0, round_three_below_hp)
	return 0.0


## Round 2's cage walls standing now (WebWallScript nodes, intact or cut); empty without the cage.
func get_cage_walls() -> Array[Node]:
	var out: Array[Node] = []
	for wall: Variant in _cage_walls:
		if wall != null and is_instance_valid(wall):
			out.append(wall as Node)
	return out


## Round 3's floor webs (FloorWebScript nodes); empty before it or without the Silk skin.
func get_floor_webs() -> Array[Node]:
	var out: Array[Node] = []
	if _floor_webs != null and is_instance_valid(_floor_webs):
		out.assign(_floor_webs.get_children())
	return out


## True when this fight is the Silk skin's exam: on, and the slime has the skin.
func silk_exam_on() -> bool:
	var world := Services.world()
	return silk_exam and SkinState.is_on(world.player if world != null else null, SkinState.SILK)


## The egg sacs she dropped in round 3 (live or burst).
func get_egg_sacs() -> Array[Node]:
	var live: Array[Node] = []
	for sac: Node in _egg_sacs:
		if is_instance_valid(sac):
			live.append(sac)
	return live


## The cocoon's shadow (her feet): a blast whose ellipse holds it tears the cocoon.
func blast_point() -> Vector2:
	return body.global_position if body != null else Vector2.INF


## A Goo Bomb's blast (game/player/abilities/goo_blast.gd) held her shadow: the cocoon tears, whole
## or half spun. False when there was nothing to tear.
func receive_blast(_hit: Dictionary) -> bool:
	if not _cocoon_on() or _shell == SHELL_TORN:
		return false
	_tear(Services.now_ms())
	return true


func _cocoon_on() -> bool:
	return cocoon_enabled and not is_defeated()


## The round her health is in now.
func _round_for_hp() -> int:
	if _hp > round_two_below_hp:
		return 1
	if _hp > round_three_below_hp:
		return 2
	return 3


func _hang_px() -> float:
	if round_hang_px.is_empty():
		return 0.0
	return round_hang_px[clampi(_round - 1, 0, round_hang_px.size() - 1)]


## The first cocoon step: a blast target from now on, cocooned in the round her health is in.
func _start_cocoon(now: float) -> void:
	add_to_group(BLAST_GROUP)
	if body != null and _body_layer < 0:
		_body_layer = body.collision_layer
	_make_pose()
	_set_shell(SHELL_COCOONED, now, false)
	_enter_round(_round_for_hp(), now)
	_set_solid(false)
	_present(now)


## The cocoon's own step: the open window and the respin end, round 2's re-webbing, the look.
func _step_cocoon(now: float) -> void:
	var elapsed := now - _shell_started_at
	match _shell:
		SHELL_COCOONED:
			if _round == 2 and now >= _next_reweb_at:
				_web_ring(now)
		SHELL_TORN:
			if elapsed >= maxf(1.0, open_ms):
				_begin_respin(now)
		SHELL_RESPIN:
			if elapsed >= maxf(1.0, respin_ms):
				_close_cocoon(now)
	if not _cage_walls.is_empty():
		_tell_stuck_bombs()
	_present(now)


## The blast tore it: a volley in hand is dropped, she falls to the floor, solid and open.
func _tear(now: float) -> void:
	cancel_attack()
	AttackTelegraph.clear_for(self)
	if _phase != PHASE_FIGHT:
		_transition_to(PHASE_FIGHT, now)
	_landed = false
	_set_shell(SHELL_TORN, now)
	_set_solid(true)
	var feel := Services.feel()
	if feel != null:
		var middle := _cocoon_middle()
		feel.particles(TATTERS, middle)
		feel.audio_cue(CUE_TEAR)
		feel.floating_text(middle - Vector2(0.0, TEAR_TEXT_RISE), TEAR_TEXT, &"yellow", true, TEAR_TEXT_MS)


## She climbs her thread and spins (the window is over, or her round's share of health is gone).
func _begin_respin(now: float) -> void:
	_set_shell(SHELL_RESPIN, now)
	_set_solid(false)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_RESPIN)


## The new cocoon is closed: the round her health is in, and the first volley a while later.
func _close_cocoon(now: float) -> void:
	_set_shell(SHELL_COCOONED, now, false)
	_enter_round(_round_for_hp(), now)
	_next_volley_at = now + maxf(1.0, first_volley_delay_ms)


## Round 2 webs its ring or spins its cage (and keeps it webbed); round 3 drops the egg sacs, once,
## and with the Silk skin webs the floor (the cage goes).
func _enter_round(round_number: int, now: float) -> void:
	_round = round_number
	if _round == 2:
		_web_ring(now)
	else:
		_next_reweb_at = INF
		_clear_cage(true)
	if _round >= 3 and not _sacs_dropped:
		_drop_egg_sacs()
	if _round >= 3 and silk_exam_on() and get_floor_webs().is_empty():
		_web_floor()
	shell_changed.emit({"shell": _shell, "round": _round, "time": now})


## `ring_patches` floor webs on a circle of `ring_radius` round her shadow, clamped into the arena;
## with the Silk skin the cage instead (`_spin_cage`).
func _web_ring(now: float) -> void:
	_next_reweb_at = now + maxf(1.0, ring_reweb_ms)
	if body == null:
		return
	if silk_exam_on():
		_spin_cage()
		return
	if patch_effect_id.is_empty():
		return
	var count := maxi(0, ring_patches)
	var shadow := body.global_position
	for index in count:
		var angle := TAU * float(index) / float(maxi(1, count))
		var point := shadow + Vector2(cos(angle), sin(angle)) * maxf(0.0, ring_radius)
		_spawn_effect_at(patch_effect_id, BossArena.clamp_point(_arena, point) if not _arena.is_empty() else point)


## The cage's walls round her shadow: [{"at" (global), "orientation", "span"}]: the back and front
## rows "across" (the web faces the camera), the sides "side", `cage_walls_per_side` each, meeting
## at the corners (the rows reach over the sides' ends), on a square of half side `ring_radius`.
func cage_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if body == null:
		return out
	var shadow := body.global_position
	var r := maxf(0.0, ring_radius)
	var n := maxi(1, cage_walls_per_side)
	var half_t := maxf(4.0, cage_thickness_px) / 2.0
	var across_span := 2.0 * (r + half_t) / float(n)
	var side_span := 2.0 * maxf(8.0, r - half_t) / float(n)
	for i in n:
		var x := -(r + half_t) + across_span * (float(i) + 0.5)
		out.append({"at": shadow + Vector2(x, -r), "orientation": "across", "span": across_span})
		out.append({"at": shadow + Vector2(x, r), "orientation": "across", "span": across_span})
		var y := -maxf(8.0, r - half_t) + side_span * (float(i) + 0.5)
		out.append({"at": shadow + Vector2(-r, y), "orientation": "side", "span": side_span})
		out.append({"at": shadow + Vector2(r, y), "orientation": "side", "span": side_span})
	return out


## A slot's solid band, global.
func _slot_rect(slot: Dictionary) -> Rect2:
	var span := float(slot["span"])
	var thickness := maxf(4.0, cage_thickness_px)
	var size := Vector2(span, thickness) if str(slot["orientation"]) == "across" else Vector2(thickness, span)
	return Rect2((slot["at"] as Vector2) - size / 2.0, size)


## Round 2 with the Silk skin: every slot of the cage whose wall is gone or cut gets a new one
## (faded in, the respin cue), except where the slime's feet are (it stays as it was, out or in).
func _spin_cage() -> void:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null:
		return
	if _cage == null or not is_instance_valid(_cage):
		_cage = Node2D.new()
		_cage.name = "MatronCage"
		_cage.y_sort_enabled = true
		parent.add_child(_cage)
		_cage_walls.clear()
	var slots := cage_slots()
	_cage_walls.resize(slots.size())
	var feet: Vector2 = world.player_body.global_position if world.player_body != null else Vector2.INF
	var spun := false
	for index in slots.size():
		var wall: Variant = _cage_walls[index]
		var standing := wall != null and is_instance_valid(wall)
		if standing and not bool((wall as Node).call(&"is_cut")):
			continue
		if feet.is_finite() and _slot_rect(slots[index]).grow(STUCK_REACH_PX).has_point(feet):
			continue
		if standing:
			(wall as Node).queue_free()
		_cage_walls[index] = _spawn_cage_wall(slots[index])
		spun = true
	if spun:
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_RESPIN)


func _spawn_cage_wall(slot: Dictionary) -> Node2D:
	var world := Services.world()
	var wall := world.instantiate_scene(CAGE_WALL_SCENE) as Node2D if world != null else null
	if wall == null:
		return null
	var across := str(slot["orientation"]) == "across"
	wall.set(&"orientation", slot["orientation"])
	wall.set(&"span", float(slot["span"]))
	wall.set(&"thickness", maxf(4.0, cage_thickness_px))
	if across and cage_height_px > 0.0:
		wall.set(&"height", cage_height_px)
	wall.set(&"remembered", false)
	wall.position = _cage.to_local(slot["at"] as Vector2)
	wall.modulate.a = 0.0
	_cage.add_child(wall)
	wall.create_tween().tween_property(wall, "modulate:a", 1.0, SPIN_IN_S)
	return wall


## A Goo Bomb come to rest against the cage from outside (a throw ends at its silk, a spit hop stops
## short of it): its line, once a bomb.
func _tell_stuck_bombs() -> void:
	if not is_inside_tree() or body == null:
		return
	var inner := maxf(0.0, ring_radius - maxf(4.0, cage_thickness_px) / 2.0)
	for node: Node in get_tree().get_nodes_in_group(BOMBS_GROUP):
		var bomb := node as Node2D
		if bomb == null or not bomb.visible or _stuck_bombs.has(bomb.get_instance_id()):
			continue
		var at: Vector2 = bomb.call(&"ground_point") if bomb.has_method(&"ground_point") else bomb.global_position
		var from_shadow := at - body.global_position
		if absf(from_shadow.x) < inner and absf(from_shadow.y) < inner:
			continue
		for wall: Node in get_cage_walls():
			if bool(wall.call(&"is_cut")):
				continue
			if (wall.call(&"solid_rect") as Rect2).grow(STUCK_REACH_PX).has_point((wall as Node2D).to_local(at)):
				_stuck_bombs[bomb.get_instance_id()] = true
				BlastBarrier.refuse(at, cage_text)
				break


## The cage goes (round 3, her fall, a reset); `tatters` shows the silk falling apart.
func _clear_cage(tatters: bool = false) -> void:
	if _cage != null and is_instance_valid(_cage):
		var feel := Services.feel() if tatters else null
		if feel != null:
			for wall: Node in get_cage_walls():
				if not bool(wall.call(&"is_cut")):
					feel.particles(TATTERS, (wall as Node2D).global_position)
		_cage.queue_free()
	_cage = null
	_cage_walls.clear()
	_stuck_bombs.clear()


## Round 3 with the Silk skin: floor webs (`object.floor-web`, one a cell, its web picked by the
## cell) on about `floor_web_share` of the cells within `floor_web_radius_px` of her shadow and
## inside her arena, faded in.
func _web_floor() -> void:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null or body == null:
		return
	_clear_floor_webs()
	_floor_webs = Node2D.new()
	_floor_webs.name = "MatronFloorWebs"
	parent.add_child(_floor_webs)
	var shadow := body.global_position
	var reach := maxf(0.0, floor_web_radius_px)
	var first := ((shadow - Vector2(reach, reach)) / FLOOR_CELL).floor()
	var last := ((shadow + Vector2(reach, reach)) / FLOOR_CELL).floor()
	for cy in range(int(first.y), int(last.y) + 1):
		for cx in range(int(first.x), int(last.x) + 1):
			var middle := (Vector2(cx, cy) + Vector2(0.5, 0.5)) * FLOOR_CELL
			if middle.distance_to(shadow) > reach:
				continue
			if not _arena.is_empty() and not BossArena.contains(_arena, middle):
				continue
			var roll := absi(hash(Vector2i(cx, cy)))
			if float(roll % 1000) / 1000.0 >= floor_web_share:
				continue
			var web := world.instantiate_scene(FLOOR_WEB_SCENE) as Node2D
			if web == null:
				return
			web.set(&"size", Vector2(FLOOR_CELL, FLOOR_CELL))
			web.set(&"variant", roll % FLOOR_WEB_VARIANTS)
			web.set(&"turn", (roll / FLOOR_WEB_VARIANTS) % 4)
			web.position = _floor_webs.to_local(middle)
			web.modulate.a = 0.0
			_floor_webs.add_child(web)
			web.create_tween().tween_property(web, "modulate:a", 1.0, SPIN_IN_S)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_RESPIN)


func _clear_floor_webs() -> void:
	if _floor_webs != null and is_instance_valid(_floor_webs):
		_floor_webs.queue_free()
	_floor_webs = null


## Her fall: the webbed floor stops holding at once and fades away.
func _fade_floor_webs() -> void:
	if _floor_webs == null or not is_instance_valid(_floor_webs):
		return
	var holder := _floor_webs
	_floor_webs = null
	for web: Node in holder.get_children():
		web.remove_from_group(FloorWebs.GROUP)
	var tween := holder.create_tween()
	tween.tween_property(holder, "modulate:a", 0.0, UNRAVEL_S)
	tween.tween_callback(holder.queue_free)


## Round 3: an egg sac at each offset from her shadow, with her arena (their Broodlings get it too).
func _drop_egg_sacs() -> void:
	_sacs_dropped = true
	var world := Services.world()
	if world == null or body == null or egg_sac_scene.is_empty():
		return
	var no_zones: Array[Dictionary] = []
	for offset: Vector2 in egg_sac_offsets:
		var root := world.spawn_at_phaser_position(egg_sac_scene, body.global_position + offset)
		if root == null:
			continue
		var sac := _enemy_script_of(root)
		if sac == null:
			continue
		sac.configure_navigation({}, no_zones)
		sac.configure_arena(_arena.duplicate(true))
		_egg_sacs.append(sac)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SACS)


## The cocoon's state from `now`; `announce` emits `shell_changed` (a new cocoon announces itself
## with its round, `_enter_round`).
func _set_shell(shell: String, now: float, announce: bool = true) -> void:
	_shell = shell
	_shell_started_at = now
	if announce:
		shell_changed.emit({"shell": shell, "round": _round, "time": now})


## Solid on the floor (the slime bumps her); not while she hangs (it walks under the cocoon).
func _set_solid(on: bool) -> void:
	if body == null or _body_layer < 0:
		return
	body.set_deferred(&"collision_layer", _body_layer if on else 0)


func _cocoon_middle() -> Vector2:
	if cocoon_look != null and body != null:
		return body.global_position + (cocoon_look as CocoonLook).cocoon_middle()
	return get_centre()


## The look, every step: the cocoon's state, its hang and breath; her own sprite hidden inside it,
## falling to the floor and shivering when torn, climbing and fading as it is spun again.
func _present(now: float) -> void:
	var look := cocoon_look as CocoonLook
	var hang := _hang_px()
	var elapsed := now - _shell_started_at
	if look != null:
		look.hang_px = hang
	var climb_height := hang + (look.art_bottom_px * look.art_scale * 0.5 if look != null else 0.0)
	match _shell:
		SHELL_COCOONED:
			if look != null:
				look.state = CocoonLook.STATE_COCOONED
				look.breath = (sin(now / maxf(1.0, breath_ms) * TAU) + 1.0) * 0.5
			if visual != null:
				visual.visible = false
				visual.position = _visual_rest
				visual.modulate.a = 1.0
		SHELL_TORN:
			if look != null:
				look.state = CocoonLook.STATE_TORN
			var t := clampf(elapsed / maxf(1.0, drop_ms), 0.0, 1.0)
			if t >= 1.0 and not _landed:
				_landed = true
				_shake_camera(LAND_SHAKE_MS, LAND_SHAKE_INTENSITY)
				var feel := Services.feel()
				if feel != null:
					feel.audio_cue(CUE_LAND)
			if visual != null:
				visual.visible = true
				visual.modulate.a = 1.0
				var shiver := sin(now / DAZED_SHIVER_MS) * DAZED_SHIVER_PX if t >= 1.0 else 0.0
				visual.position = _visual_rest + Vector2(shiver, -(1.0 - t) * (1.0 - t) * climb_height)
			if _pose != null:
				var twitch := int((now - _shell_started_at) / DAZED_TWITCH_MS) % 2 == 1 and t >= 1.0
				_pose.frame = POSE_FLINCH if now < _flinch_until else (POSE_DAZED_B if twitch else POSE_DAZED_A)
		SHELL_RESPIN:
			var progress := clampf(elapsed / maxf(1.0, respin_ms), 0.0, 1.0)
			if look != null:
				look.state = CocoonLook.STATE_RESPIN
				look.progress = progress
			var up := clampf(progress / CLIMB_SHARE, 0.0, 1.0)
			if visual != null:
				visual.visible = up < 1.0
				visual.position = _visual_rest - Vector2(0.0, up * climb_height)
				visual.modulate.a = 1.0 - up
			if _pose != null:
				_pose.frame = POSE_CLIMB


# --- damage receiver (MatronScript.ts:112-123) ------------------------------------------------

## The cocoon refuses every hit with a clink and its line until a blast tears it open.
func can_receive_damage(input: Dictionary) -> Dictionary:
	if _cocoon_on() and _shell != SHELL_TORN:
		return BlastBarrier.refuse(_cocoon_middle(), clink_text)
	return super(input)


## Open, a hit takes her no lower than her round's floor.
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	if _cocoon_on():
		damage = minf(damage, maxf(0.0, _hp - round_floor()))
	return damage


## Damage outside a routed hit (a rework wall splat, a bowled enemy) follows the cocoon's rules too:
## none while cocooned, no lower than her round's floor while open.
func take_reaction_damage(amount: float) -> int:
	if not _cocoon_on():
		return super(amount)
	if _shell != SHELL_TORN:
		return 0
	var dealt := super(minf(amount, maxf(0.0, _hp - round_floor())))
	if not is_defeated() and _shell == SHELL_TORN and _hp <= round_floor():
		_begin_respin(Services.now_ms())
	return dealt


## The hit, then: her round's share gone, she climbs at once.
func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if int((commit.get("result", {}) as Dictionary).get("actual_damage", 0)) > 0:
		_flinch_until = Services.now_ms() + FLINCH_MS
	if _cocoon_on() and _shell == SHELL_TORN and _hp <= round_floor():
		_begin_respin(Services.now_ms())


## A boss keeps her pattern: hits flash and show their damage but never cancel a volley, stagger
## or shove her.
func _react_to_damage(commit: Dictionary, _is_dead: bool) -> void:
	_show_hit_feedback(commit)


## Clears the telegraph, runs the base defeat, phase dead. In the cocoon fight her brood bursts,
## the cocoon unravels and she scuttles off as an ordinary orb-weaver.
func _defeat() -> void:
	if is_defeated():
		return
	var cocoon_fight := _cocoon_on()
	AttackTelegraph.clear_for(self)
	super()
	_transition_to(PHASE_DEAD, Services.now_ms())
	if cocoon_fight:
		remove_from_group(BLAST_GROUP)
		_burst_brood()
		_clear_cage(true)
		_fade_floor_webs()
		_retreat()


## Her egg sacs and their Broodlings burst with her.
func _burst_brood() -> void:
	for sac: Node in get_egg_sacs():
		if not bool(sac.call(&"is_defeated")):
			sac.call(&"take_reaction_damage", BURST_DAMAGE)
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(ENEMY_TYPE_GROUP_BROOD):
		var brood := node as EnemyScript
		if brood != null and not brood.is_defeated() and not brood.is_queued_for_deletion() \
				and brood.get_arena() == _arena:
			brood.take_reaction_damage(BURST_DAMAGE)


## She shrinks into an ordinary big orb-weaver and scuttles off up through her web (presentation;
## the body has no collision now and frees itself after `_dispose_delay_ms`).
func _retreat() -> void:
	if body == null:
		return
	var feel := Services.feel()
	if feel != null:
		feel.particles(TATTERS, get_centre())
	if visual != null:
		visual.visible = false
	var look := cocoon_look as CocoonLook
	if look != null:
		look.state = CocoonLook.STATE_GONE
		look.progress = 0.0
		var unravel := look.create_tween()
		unravel.tween_property(look, "progress", 1.0, UNRAVEL_S)
	var scuttler := SheetSprite.new()
	scuttler.name = "Retreat"
	scuttler.centered = false
	scuttler.hframes = RETREAT_FRAMES
	scuttler.offset = RETREAT_OFFSET
	scuttler.position = RETREAT_RISE
	scuttler.scale = Vector2.ONE * RETREAT_START_SCALE
	scuttler.sheet_path = RETREAT_SHEET
	scuttler.frame = RETREAT_FRAME_AWAY
	body.add_child(scuttler)
	var tween := scuttler.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(scuttler, "scale", Vector2.ONE * retreat_scale, RETREAT_SHRINK_S)
	tween.tween_property(body, "position", body.position + Vector2(0.0, -retreat_px), RETREAT_SCUTTLE_S)
	tween.parallel().tween_method(func(t: float) -> void:
		scuttler.flip_h = int(t / RETREAT_STRIDE_S) % 2 == 1, 0.0, RETREAT_SCUTTLE_S, RETREAT_SCUTTLE_S)


## Her own pose sprite takes the place of the old Visual for the cocoon fight (the hit flash and the
## reactions' hit motion follow `visual`).
func _make_pose() -> void:
	if body == null or _pose != null:
		return
	if visual != null:
		visual.visible = false
	_pose = SheetSprite.new()
	_pose.name = "MatronPose"
	_pose.centered = false
	_pose.hframes = POSE_FRAMES
	_pose.offset = POSE_OFFSET
	_pose.scale = Vector2.ONE * pose_scale
	_pose.sheet_path = POSE_SHEET
	_pose.frame = POSE_DAZED_A
	_pose.visible = false
	body.add_child(_pose)
	visual = _pose
	_visual_rest = Vector2.ZERO
	HitFlash.install(_pose)


static func _enemy_script_of(root: Node) -> EnemyScript:
	for child: Node in root.get_children():
		if child is EnemyScript:
			return child as EnemyScript
	return null


# --- base hooks -------------------------------------------------------------------------------

## In the cocoon fight, torn or climbing back: no AI, no spit, no leash; she holds still. The cocoon
## fight starts on the first step.
func _step_enemy(delta: float) -> bool:
	if cocoon_enabled and _round == 0 and not is_defeated():
		_start_cocoon(Services.now_ms())
	if not _cocoon_on() or _runs_ai():
		return super(delta)
	_update_hit_flash(Services.now_ms())
	body.velocity = Vector2.ZERO
	return true


## In the cocoon fight, whether the base step (the slime-spider AI, the spit, the leash) runs: from
## inside the cocoon. The ram fight (game/bosses/matron_ram.gd) also lets it run while she hangs free.
func _runs_ai() -> bool:
	return _shell == SHELL_COCOONED


## The common attack (the web spit) runs only while fighting (MatronScript.ts:116), and in the
## cocoon fight only from inside the cocoon.
func _can_run_common_attack() -> bool:
	return _phase == PHASE_FIGHT and (not _cocoon_on() or _runs_ai())


func _receiver_tags() -> Array[String]:
	return BOSS_RECEIVER_TAGS


## Bosses are not ordinary enemies, so their damage number rises from their position
## (UniversalSceneWorldController.ts:2039-2045).
func _damage_number_top() -> float:
	return get_centre().y


## Godot deviation (matron spec 4, as for Fatty; owner decision 2026-10-05): the dead body stays
## 2 s (its `die-<facing>` clip, then the last frame) and fades out at the end; Phaser removes it
## the step it dies.
func _dispose_delay_ms() -> float:
	return maxf(BOSS_CORPSE_MS, _clip_length_ms("die-" + _facing))


func _corpse_fade_ms() -> float:
	return BOSS_CORPSE_FADE_MS


# --- phases -------------------------------------------------------------------------------------

## `landVolley` (MatronScript.ts:83-98): clear the telegraph; a slime whose hurtbox overlaps a mark
## takes the volley hit (no impact effect); a web patch on every mark; a small camera shake; rest.
func _land_volley(now: float) -> void:
	AttackTelegraph.clear_for(self)
	var shapes := volley_shapes()
	var target := _primary_target()
	if not target.is_empty() and bool(target.get("active", false)) and _target_overlaps(shapes, target):
		_route_immediate_attack(target, volley_damage, volley_knockback_strength, -1.0, false)
	for point: Vector2 in _volley:
		_spawn_effect_at(patch_effect_id, point)
	_shake_camera(VOLLEY_SHAKE_MS, VOLLEY_SHAKE_INTENSITY)
	_transition_to(PHASE_VOLLEY_REST, now)


func _transition_to(phase: String, now: float) -> void:
	_phase = phase
	_phase_started_at = now
	phase_changed.emit({"phase": phase, "time": now})

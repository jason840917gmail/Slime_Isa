extends MatronScript
## Scene script of `character.orb-weaver-matron-rework`: the Orb-Weaver Matron's **ram fight**, step 2
## of the dungeons 2 and 3 rework (docs/design/2026-11-23-dungeons-2-3-rework.md "The Orb-Weaver
## Matron"; docs/godot/specs/matron.md section 9). It extends the cocoon fight (matron.gd, sections 8):
## the cocoon, its tear, the open window, the respin, the rounds' floors, the egg sacs and the Silk
## skin's webbed floor are that fight's; this script adds the rams and her new frames. Her lab
## (`world.matron-lab`) and the rebuilt Weaver Hollow's Crown (`weaver-hollow-c2-crown`, through
## `encounter.weaver-hollow-matron`, since 2026-11-25) place her, five rams in each.
##
## The rams are demolition tools both sides use (owner, 2026-11-24): the slime trips them at her, and
## she trips them at the slime (**her ram call**: the slime in a ready ram's lane, she spits a glob of
## web at that ram's knock target: game/bosses/web_glob.gd). She calls one from the floor too, after a
## dive, even down the lane she lies in: a slime that stands in her lane and steps out of it in time
## makes her log hit her (owner, the same day: "the player can trick her to make her hit herself").
## **Every cocoon she spins hangs over one
## ram's lane**, picked at random and never the one she just hung over (`get_rams`, `_pick_home`), so
## the slime must find which target lets that ram go. Far from a new cocoon's lane she first climbs
## and crawls along her web to its middle (`relocate_speed`), then spins: a cocoon always closes over
## its lane.
##
## - **Round 1** (above `round_two_below_hp`): her breathing cocoon hangs low; a Goo Bomb's blast on
##   its shadow tears it and she lies dazed `open_ms`. Its lane's ram knocks it down whole too (as in
##   round 3), and a blast tears it there.
## - **Round 2** (above `round_three_below_hp`): no cocoon. She hangs high on her thread
##   (`ram_hang_px[1]`), out of reach (hits clink with `high_text`), crawls along her web over the slime
##   and spits; every `dive_every_ms` she lets go and **dives** where her shadow lies (`dive_ms`: her
##   shadow grows as she falls; `dive_damage` to a slime within `dive_radius_px`), lies on the floor
##   `landed_ms` (4 s: time to trip a ram at her), calling a ram at the slime from there once
##   (`ground_call_after_ms`), and climbs back up (`climb_ms`). She **rings every knock target** in her arena with
##   web walls (`object.web-wall`, a square of half side `target_ring_radius`, spun again every
##   `ring_reweb_ms` when cut), which stop a throw: the slime wades in (the Silk skin) or cuts a window
##   (the Spear) and throws at the target. **A ram that catches her** in the dive's lower part
##   (`dive_catch_from`) or landed (`on_mechanism_hit`) flings her along its lane to the wall
##   (`fling_speed`, at most `fling_max_ms`): she crashes (`ram_blow_damage`) **on her back** and is
##   open for `open_ms`
##   (the cocoon fight's window: the Spear, and a thrown thing for `thrown_damage_share` of a Spear
##   hit), then climbs back up, or at the round's floor spins a new cocoon, high.
## - **Round 3**: the new cocoon hangs high (`ram_hang_px[2]`) over a ram's lane, out of a blast's
##   reach (`high_cocoon_text`); the floor webbed (the Silk skin) and two egg sacs, as built. **Its
##   lane's ram knocks it down whole** (`knock_down_px` along the lane): it lies on the floor straining
##   for `downed_ms`, and a blast on it tears it: she spills out dazed, open as in round 1. Otherwise
##   she cuts herself free and spins again, over another lane.
##
## A thrown thing hurts her for half a Spear hit whenever she is open (`thrown_damage_share` of
## `shapes.spear.baseDamage`), as Fatty's eye. Her look in this fight is `MatronRamLook`
## (game/bosses/matron_ram_look.gd: her packed frames, res://asset/MAPS/enemies/bosses/matron/) beside
## the cocoon's own (matron_cocoon_look.gd, for the hanging cocoon). Sounds: `MatronHiss` (a dive),
## `MatronShriek` (caught by a ram, the cocoon torn), `MatronImpact` (a dive lands, she crashes, the
## cocoon hits the floor): Sound Picker round 16, silent until staged.
##
## Owner: boss port (the Matron).

const RamLook := preload("res://game/bosses/matron_ram_look.gd")
const KnockTargetScript := preload("res://game/dungeon/knock_target.gd")
const WebGlob := preload("res://game/bosses/web_glob.gd")
## The mechanisms a knock target lets go (mechanism_strike.gd GROUP_MECHANISMS).
const MECHANISMS_GROUP := &"knock_mechanisms"

## Her shell states besides the cocoon fight's (`get_shell`).
const SHELL_HANGING := "hanging"
const SHELL_DIVING := "diving"
const SHELL_LANDED := "landed"
const SHELL_FLUNG := "flung"
const SHELL_CLIMBING := "climbing"
## Up on her web, crawling to a new cocoon's lane before she spins it.
const SHELL_RELOCATING := "relocating"
## Within this of the lane's middle she spins where she is.
const RELOCATE_ARRIVE_PX := 6.0
const SHELL_DOWNED := "downed"
## What she lies out of while "torn" (open): the hanging cocoon (round 1), the cocoon knocked down
## (round 3), or nothing: on her back after a ram (round 2).
const OPEN_COCOON := "cocoon"
const OPEN_GROUND := "ground"
const OPEN_BACK := "back"
const RAM_KIND := &"ram"
const THROWN_TAG := "thrown"
const SPEAR_BASE_DAMAGE_KEY := "shapes.spear.baseDamage"
const CUE_HISS := &"MatronHiss"
const CUE_SHRIEK := &"MatronShriek"
const CUE_IMPACT := &"MatronImpact"
const DUST := &"dodge-dust"
const RINGS_NAME := "MatronTargetRings"
const WAYS := {"north": Vector2.UP, "south": Vector2.DOWN, "east": Vector2.RIGHT, "west": Vector2.LEFT}
## Presentation: the spit's frames (wind-up and charge share the wind-up, the spit shows this long),
## how long the crash's frame shows before she kicks on her back, the fling's arc, the respin's climb
## share, a fallen cocoon's straining beat, the dive's frames by its progress.
const SPIT_SHOW_MS := 160.0
const CRASH_FRAME_MS := 280.0
const FLING_ARC_PX := 36.0
const RESPIN_CLIMB_SHARE := 0.4
const STRAIN_MS := 420.0
const DIVE_FRAME_AT: Array[float] = [0.3, 0.6]
## Her hanging pose shows the ram call's spit this long.
const RAM_CALL_SPIT_MS := 380.0
## A husk left on the floor fades out over this.
const HUSK_FADE_S := 0.9
## The fling ends when a step moved less than this share of its speed (a wall stopped her).
const FLING_STOP_SHARE := 0.35
const FLING_MIN_MS := 60.0
const CRASH_SHAKE_MS := 200.0
const CRASH_SHAKE_INTENSITY := 0.006
## Her mouth sits this far above her hanging pose's bottom (the spit leaves from it).
const MOUTH_ABOVE_BOTTOM_PX := 40.0
## Her missed webs' balls: the pot scene (any liftable kind), its kind node, what it leaves when sucked
## up (nothing: the room's pots hold the energy), how close to the slime one may land (none closer:
## it would land on the slime), its pop as it lands and its unravel when too many lie about.
const LIFTABLE_SCENE := "res://game/scenes/objects/liftable.tscn"
const LIFTABLE_SCRIPT_NODE := "LiftableScript"
const WEB_BALL_UNDER := "none"
const WEB_BALL_CLEAR_PX := 48.0
const WEB_BALL_POP_S := 0.18
const WEB_BALL_POP_FROM := 0.4
const WEB_BALL_UNRAVEL_S := 0.6

@export_group("Ram fight (rework)")
## The bottom of her (or her cocoon) over the shadow in rounds 1 to 3: low, then out of reach.
@export var ram_hang_px: PackedFloat32Array = PackedFloat32Array([60.0, 200.0, 170.0])
## A cocoon hanging higher than this is out of a blast's reach (round 3 until a ram knocks it down).
@export var blast_reach_px: float = 100.0
## Round 2: her crawl along the web over the slime, her first dive and the next ones.
@export var reposition_speed: float = 150.0
@export var first_dive_ms: float = 1800.0
@export var dive_every_ms: float = 3600.0
## The dive: its length (her shadow grows as she falls: the tell), from what share of it a ram's log
## catches her, its blow on a slime within its radius, and how long she lies after it (owner,
## 2026-11-24: "she stay for 4 seconds so you have time to trigger the" ram).
@export var dive_ms: float = 900.0
@export_range(0.0, 1.0) var dive_catch_from: float = 0.3
@export var dive_damage: float = 40.0
@export var dive_knockback: float = 260.0
@export var dive_radius_px: float = 64.0
@export var landed_ms: float = 4000.0
## Her ram call from the floor after a dive: once per landing, `ground_call_after_ms` after she lands,
## whenever the slime stands in a ready ram's lane, her own lane too, whatever her ram call's pace
## (`ram_call_every_ms`). She lies on at least `ground_call_stay_ms` after the glob lands (the ram's
## shudder, swing and hold: `dungeon.ram` windupMs + swingMs + holdMs, 920), so a log she trips down
## her own lane always reaches her: she flings herself.
@export var ground_call_after_ms: float = 600.0
@export var ground_call_stay_ms: float = 1000.0
## Her climb back up to hang.
@export var climb_ms: float = 1100.0
## Her crawl along her web to a new cocoon's lane (she spins it only once she is over its middle).
@export var relocate_speed: float = 320.0
## Caught by a ram: flung along its lane this fast, at most this long (a wall stops her first).
@export var fling_speed: float = 1100.0
@export var fling_max_ms: float = 650.0
## A thrown thing on her while she is open: this share of the Spear's base hit.
@export var thrown_damage_share: float = 0.5
## Round 2's web walls round every knock target in her arena (half the square's side).
@export var target_ring_radius: float = 70.0
## A ram that catches her dive hurts her this much when she hits the wall (no lower than her round's
## floor): the rams are tools that hurt her as they hurt the slime (owner, 2026-11-24).
@export var ram_blow_damage: float = 20.0
## Her ram call: while she can attack (in her cocoon or hanging free) and the slime stands in a ready
## ram's lane (within `lane_margin_px` of it), she spits a glob of web at that ram's knock target
## (`ram_call_flight_ms` in the air), so the log swings at the slime; at most every
## `ram_call_every_ms`, the first `ram_call_first_ms` after her fight starts. Never the ram whose lane
## her own cocoon hangs over.
@export var ram_call_first_ms: float = 3500.0
@export var ram_call_every_ms: float = 4500.0
@export var ram_call_flight_ms: float = 450.0
@export var lane_margin_px: float = 8.0
## Her spit and her webs at her size (owner, 2026-11-24: "make matron's projectiles and webs bigger
## to match her size"): her spit's projectile (its picture and its hitbox) and her volley's web
## patches (their picture and their slowing circle) grown by these; her ram call's glob by `glob_scale`.
@export var spit_scale: float = 2.0
@export var patch_scale: float = 1.6
@export var glob_scale: float = 2.0
## Round 3: a ram knocks her high cocoon down: its fall, how far it is knocked along the lane, how
## long it lies before she cuts herself free.
@export var downed_fall_ms: float = 260.0
@export var knock_down_px: float = 70.0
@export var downed_ms: float = 9000.0
## Said (at most every 1.5 s) when a hit clinks off her high up, and when a blast misses her high cocoon.
@export var high_text: String = "Out of reach up there."
@export var high_cocoon_text: String = "Too high for a blast. Knock it down first."
## Said (as `high_text`, at most every 1.5 s) when a hit glances off her lying after a dive.
@export var landed_text: String = "Her shell turns it. A ram would crack her."
## Her missed webs are ammo (owner, 2026-11-24: "the webs that she miss should be throwables in case
## we ran out of pot", as Fatty's mud balls): a volley's mark that missed the slime and a spit that
## missed it leave a web ball (the liftable `web_ball_kind`: the Gulp sucks it in and throws it like a
## pot) where they landed; at most `max_web_balls` lie at once (the oldest unravels).
@export var web_ball_kind: String = "web-ball"
@export var max_web_balls: int = 6
## Her volley (the web marks that rain onto the floor) in round 3 too; off (owner, 2026-11-24: "in
## phase 3 mattron not longer use if frist grounf web attack , is too many attacks"): in round 3 she
## keeps to her spit, her ram call and her brood.
@export var volley_in_round_three: bool = false
@export_group("")

var _open_kind: String = OPEN_COCOON
var _next_dive_at: float = INF
var _fling_dir: Vector2 = Vector2.RIGHT
var _fling_last: Vector2 = Vector2.ZERO
var _crash_at: float = -INF
var _home: Vector2 = Vector2.INF
var _downed_landed: bool = false
var _look: RamLook
var _rings: Node2D
## The ring walls by slot (a slot's wall may be gone or cut), and their slots.
var _ring_walls: Array = []
var _ring_slots: Array[Dictionary] = []
var _next_ring_spin: float = INF
## The ram whose lane her cocoon hangs over now (picked at random for each cocoon).
var _lane_ram: Node
var _next_ram_call_at: float = INF
## Until when her pose (hanging, or on the floor) shows the ram call's spit.
var _ram_call_until: float = -INF
## This landing's ram call from the floor was made, and she lies at least until then for its log.
var _ground_called: bool = false
var _stay_down_until: float = -INF
var _rng := RandomNumberGenerator.new()
## The relocation's start height (0 from the floor), and whether the respin after it starts up there
## (its climb share skipped).
var _relocate_from_px: float = 0.0
var _spin_from_hang: bool = false
## Her body's mask on the floor (the scene's: world, player, water), put aside while she is up.
var _floor_mask: int = -1
## The web balls her missed webs left, oldest first (gone ones are dropped as they are found).
var _web_balls: Array[Node2D] = []


func _exit_tree() -> void:
	_clear_rings()
	super()


## The ram fight's states, and the cocoon fight's.
func get_shell() -> String:
	return _shell


## What she lies out of while open: "cocoon", "ground" or "back".
func get_open_kind() -> String:
	return _open_kind


## Gameplay time of her next dive (round 2, hanging).
func get_next_dive_at() -> float:
	return _next_dive_at


## Her spot: the middle of the lane picked for her cocoon (`_pick_home`; each cocoon's, round 3's too).
func get_home() -> Vector2:
	return _home


## Round 2's ring walls standing now (intact or cut).
func get_ring_walls() -> Array[Node]:
	var out: Array[Node] = []
	for wall: Variant in _ring_walls:
		if wall != null and is_instance_valid(wall):
			out.append(wall as Node)
	return out


## True while a ram's log would catch her (the dive's lower part, or landed).
func is_catchable() -> bool:
	if _shell == SHELL_LANDED:
		return true
	return _shell == SHELL_DIVING and _dive_progress(Services.now_ms()) >= dive_catch_from


# --- the step ------------------------------------------------------------------------------------

func _start_cocoon(now: float) -> void:
	_rng.randomize()
	super(now)
	_pick_home()
	if body != null and _home.is_finite():
		body.global_position = _home
		body.reset_physics_interpolation()
	_next_ram_call_at = now + maxf(0.0, ram_call_first_ms)
	_present(now)


## The rams in her arena (the mechanisms with a lane).
func get_rams() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not is_inside_tree():
		return out
	for node: Node in get_tree().get_nodes_in_group(MECHANISMS_GROUP):
		if not node.has_method(&"lane_rect") or not node is Node2D:
			continue
		var lane: Rect2 = node.call(&"lane_rect")
		if not _arena.is_empty() and not BossArena.contains(_arena, lane.get_center()):
			continue
		out.append(node as Node2D)
	return out


## The ram whose lane her cocoon hangs over now (null without rams).
func get_lane_ram() -> Node:
	return _lane_ram


## Her next cocoon's spot: the middle of a ram's lane picked at random, not the one she hangs over
## now (her camp's spot when the room has no rams).
func _pick_home() -> void:
	var rams := get_rams()
	if rams.size() > 1 and _lane_ram != null:
		rams.erase(_lane_ram)
	if rams.is_empty():
		if not _home.is_finite() and body != null:
			_home = body.global_position
		return
	_lane_ram = rams[_rng.randi_range(0, rams.size() - 1)]
	_home = (_lane_ram.call(&"lane_rect") as Rect2).get_center()


func _runs_ai() -> bool:
	return _shell == SHELL_COCOONED or _shell == SHELL_HANGING


func _hang_px() -> float:
	if ram_hang_px.is_empty():
		return 0.0
	return ram_hang_px[clampi(_round - 1, 0, ram_hang_px.size() - 1)]


## The hang of the round her health is in (a respin closes into it).
func _next_hang_px() -> float:
	if ram_hang_px.is_empty():
		return 0.0
	return ram_hang_px[clampi(_round_for_hp() - 1, 0, ram_hang_px.size() - 1)]


func _after_enemy_step(delta: float) -> void:
	super(delta)
	if is_defeated() or _phase == PHASE_DEAD or body == null or not _cocoon_on():
		return
	var now := Services.now_ms()
	match _shell:
		SHELL_HANGING:
			_step_hanging(now)
		SHELL_DIVING:
			body.velocity = Vector2.ZERO
			if _dive_progress(now) >= 1.0:
				_land(now)
		SHELL_LANDED:
			body.velocity = Vector2.ZERO
			if now - _shell_started_at >= maxf(1.0, landed_ms) and now >= _stay_down_until:
				_begin_climb(now)
		SHELL_FLUNG:
			_step_flung(now, delta)
		SHELL_CLIMBING:
			body.velocity = Vector2.ZERO
			if now - _shell_started_at >= maxf(1.0, climb_ms):
				_set_shell(SHELL_HANGING, now)
				# a dive already due (round 2's first, set when the round began) keeps its time; after
				# a dive (which clears it) the next comes `dive_every_ms` on
				if not is_finite(_next_dive_at):
					_next_dive_at = now + maxf(1.0, dive_every_ms)
		SHELL_RELOCATING:
			_step_relocating(now, delta)
		SHELL_DOWNED:
			_step_downed(now)
		SHELL_RESPIN:
			# she spins over her lane's middle (the relocation brought her there; a last few units are
			# closed here)
			body.velocity = Vector2.ZERO
			if _home.is_finite() and body.global_position.distance_to(_home) > 4.0:
				var to_home := _home - body.global_position
				body.velocity = to_home.normalized() * minf(reposition_speed * 2.0, to_home.length() / maxf(delta, 0.001))
		SHELL_TORN:
			body.velocity = Vector2.ZERO
	if _round == 2 and now >= _next_ring_spin:
		_spin_rings(now)
	_step_ram_call(now)
	_present(now)


## Her volley only in round 1 (and in round 3 with `volley_in_round_three`): in round 3 the next one is
## put off a cadence each time it comes due.
func begin_volley(now: float, at: Vector2) -> bool:
	if _cocoon_on() and _round >= 3 and not volley_in_round_three:
		_next_volley_at = now + maxf(1.0, volley_cadence_ms)
		return false
	return super(now, at)


## Her ram call: the slime in a ready ram's lane (not the lane her cocoon hangs over), its target
## armed: a glob of web at the target. On the floor after a dive: once, `ground_call_after_ms` in,
## any lane the slime stands in (hers too), and she stays down until its log has swung.
func _step_ram_call(now: float) -> void:
	var landed := _shell == SHELL_LANDED
	if landed:
		if _ground_called or now - _shell_started_at < maxf(0.0, ground_call_after_ms):
			return
	elif now < _next_ram_call_at or is_attacking() or (_shell != SHELL_COCOONED and _shell != SHELL_HANGING):
		return
	var world := Services.world()
	if world == null or world.player_body == null:
		return
	var feet := world.player_body.global_position
	for ram: Node2D in get_rams():
		if _shell == SHELL_COCOONED and ram == _lane_ram:
			continue
		if not bool(ram.call(&"is_ready")):
			continue
		if not (ram.call(&"lane_rect") as Rect2).grow(maxf(0.0, lane_margin_px)).has_point(feet):
			continue
		var target: Variant = ram.call(&"get_knock_target") if ram.has_method(&"get_knock_target") else null
		if not target is Node2D or not is_instance_valid(target) or not bool((target as Node).call(&"is_armed")):
			continue
		_launch_glob(target as Node2D, now)
		if landed:
			_ground_called = true
			_stay_down_until = now + maxf(1.0, ram_call_flight_ms) + maxf(0.0, ground_call_stay_ms)
		return


func _launch_glob(target: Node2D, now: float) -> void:
	_next_ram_call_at = now + maxf(1.0, ram_call_every_ms)
	_ram_call_until = now + RAM_CALL_SPIT_MS
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null:
		return
	var glob := WebGlob.new()
	glob.name = "MatronWebGlob"
	glob.from = get_centre() if _shell == SHELL_HANGING else _cocoon_middle()
	glob.target = target
	glob.flight_ms = maxf(1.0, ram_call_flight_ms)
	glob.size = maxf(0.1, glob_scale)
	parent.add_child(glob)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HISS)


## Hanging high: she crawls along her web over the slime (holding still while she spits) and dives
## when it is time.
func _step_hanging(now: float) -> void:
	body.velocity = Vector2.ZERO
	var world := Services.world()
	var feet: Vector2 = world.player_body.global_position if world != null and world.player_body != null else Vector2.INF
	if not is_attacking() and feet.is_finite():
		var to := feet - body.global_position
		if not _arena.is_empty():
			to = BossArena.clamp_point(_arena, feet) - body.global_position
		if to.length() > 6.0:
			body.velocity = to.normalized() * maxf(0.0, reposition_speed)
	if now < _next_dive_at or is_attacking():
		return
	var target := _primary_target()
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return
	_begin_dive(now)


func _begin_dive(now: float) -> void:
	cancel_attack()
	body.velocity = Vector2.ZERO
	# the next dive is set when she is back up (her climb's end)
	_next_dive_at = INF
	_set_shell(SHELL_DIVING, now)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HISS)


func _dive_progress(now: float) -> float:
	return clampf((now - _shell_started_at) / maxf(1.0, dive_ms), 0.0, 1.0)


## The dive lands: a slime under her takes its blow; dust, a thud, a small shake.
func _land(now: float) -> void:
	_set_shell(SHELL_LANDED, now)
	_ground_called = false
	_stay_down_until = -INF
	var circle := CircleShape2D.new()
	circle.radius = maxf(8.0, dive_radius_px)
	var shapes: Array[Dictionary] = [{"shape": circle, "transform": Transform2D(0.0, body.global_position)}]
	var target := _primary_target()
	if not target.is_empty() and bool(target.get("active", false)) and _target_overlaps(shapes, target):
		_route_immediate_attack(target, dive_damage, dive_knockback, -1.0, false)
	_shake_camera(LAND_SHAKE_MS, LAND_SHAKE_INTENSITY)
	var feel := Services.feel()
	if feel != null:
		feel.particles(DUST, body.global_position)
		feel.audio_cue(CUE_IMPACT)


## Every shell change: her body collides with the floor's things (walls, a target's post, the slime)
## only while she is down on it: landed from a dive, flung, open (on her back, dazed) or her cocoon
## knocked down. Up on her web (hanging, climbing, crawling, spinning, in her cocoon, diving) her
## body collides with nothing, as the Colossus's in the air, so nothing on the floor holds a spider
## drawn up there; where she goes then is always inside her arena (the slime's spot clamped into
## it, a lane's middle).
func _set_shell(shell: String, now: float, announce: bool = true) -> void:
	super(shell, now, announce)
	if body == null:
		return
	if _floor_mask < 0:
		_floor_mask = body.collision_mask
	var down := shell == SHELL_LANDED or shell == SHELL_FLUNG or shell == SHELL_TORN or shell == SHELL_DOWNED
	body.collision_mask = _floor_mask if down else 0


func _begin_climb(now: float) -> void:
	_set_shell(SHELL_CLIMBING, now)
	_set_solid(false)


## To a new cocoon's lane before she spins it: she climbs to its hang (`climb_ms`, or less when she
## is already up), then crawls along her web to the lane's middle at `relocate_speed`, then spins
## there (the cocoon fight's respin, its climb share skipped). So a cocoon always closes over its
## lane, wherever she lay.
func _begin_relocate(now: float) -> void:
	_relocate_from_px = _hang_px() if _shell == SHELL_HANGING or _shell == SHELL_CLIMBING else 0.0
	_set_shell(SHELL_RELOCATING, now)
	_set_solid(false)


func _relocate_climb_ms() -> float:
	var hang := _next_hang_px()
	if hang <= 0.0:
		return 0.0
	return maxf(0.0, climb_ms) * clampf((hang - _relocate_from_px) / hang, 0.0, 1.0)


func _step_relocating(now: float, delta: float) -> void:
	body.velocity = Vector2.ZERO
	if now - _shell_started_at < _relocate_climb_ms() or not _home.is_finite():
		return
	var to_home := _home - body.global_position
	if to_home.length() <= RELOCATE_ARRIVE_PX:
		_spin_from_hang = true
		super._begin_respin(now)
		return
	body.velocity = to_home.normalized() * minf(maxf(1.0, relocate_speed), to_home.length() / maxf(delta, 0.001))


## Flung along a ram's lane: she flies until a wall stops her (or the arena's edge, or the time).
func _step_flung(now: float, delta: float) -> void:
	var elapsed := now - _shell_started_at
	var moved := body.global_position.distance_to(_fling_last)
	_fling_last = body.global_position
	var step := _fling_dir * maxf(0.0, fling_speed) * delta
	var stopped := elapsed >= FLING_MIN_MS and moved < maxf(0.0, fling_speed) * delta * FLING_STOP_SHARE
	var leaving := not _arena.is_empty() and not BossArena.contains(_arena, body.global_position + step)
	if stopped or leaving or elapsed >= maxf(1.0, fling_max_ms):
		_crash(now)
		return
	body.velocity = _fling_dir * maxf(0.0, fling_speed)


## She hits the wall: on her back, open (the cocoon fight's window from now).
func _crash(now: float) -> void:
	body.velocity = Vector2.ZERO
	_open_kind = OPEN_BACK
	_crash_at = now
	_landed = true
	_set_shell(SHELL_TORN, now)
	_set_solid(true)
	_shake_camera(CRASH_SHAKE_MS, CRASH_SHAKE_INTENSITY)
	var feel := Services.feel()
	if feel != null:
		feel.particles(DUST, body.global_position)
		feel.audio_cue(CUE_IMPACT)
	# the ram's blow tells as she hits the wall (no lower than her round's floor; at it, her round
	# is over and she climbs at once)
	if ram_blow_damage > 0.0:
		var dealt := take_reaction_damage(ram_blow_damage)
		if feel != null and dealt > 0:
			feel.play_hit({"hit_stop_ms": 90.0, "trauma": 0.5, "kick_px": 0.0, "sparks": 12, "number": dealt,
				"number_big": true}, get_centre(), _fling_dir)


## A cocoon knocked down: its fall along the lane, then it lies straining until she cuts free.
func _step_downed(now: float) -> void:
	var elapsed := now - _shell_started_at
	var fall := maxf(1.0, downed_fall_ms)
	body.velocity = Vector2.ZERO
	if elapsed < fall:
		body.velocity = _fling_dir * maxf(0.0, knock_down_px) / (fall / 1000.0)
		return
	if not _downed_landed:
		_downed_landed = true
		_set_solid(true)
		_shake_camera(LAND_SHAKE_MS, LAND_SHAKE_INTENSITY)
		var feel := Services.feel()
		if feel != null:
			feel.particles(DUST, body.global_position)
			feel.audio_cue(CUE_IMPACT)
	if elapsed >= maxf(fall, downed_ms):
		_open_kind = OPEN_GROUND
		_begin_respin(now)


# --- the rams -----------------------------------------------------------------------------------

## A dungeon mechanism's moving part reached her (game/dungeon/mechanism_strike.gd): a ram's log
## flings her from a dive, knocks round 3's cocoon down, or rocks round 1's. Hanging high, on her
## back, or climbing, the log swings under her.
func on_mechanism_hit(kind: StringName, source: Node) -> void:
	if kind != RAM_KIND or is_defeated() or body == null or not _cocoon_on():
		return
	var now := Services.now_ms()
	var along := _way_of(source)
	if _shell == SHELL_LANDED or (_shell == SHELL_DIVING and _dive_progress(now) >= dive_catch_from):
		_fling(along, now)
	elif _shell == SHELL_COCOONED:
		_knock_down(along, now)


func _fling(along: Vector2, now: float) -> void:
	cancel_attack()
	AttackTelegraph.clear_for(self)
	_fling_dir = along
	_fling_last = body.global_position
	_set_shell(SHELL_FLUNG, now)
	_set_solid(false)
	var feel := Services.feel()
	if feel != null:
		feel.particles(TATTERS, get_centre())
		feel.audio_cue(CUE_SHRIEK)
	_shake_camera(LAND_SHAKE_MS, LAND_SHAKE_INTENSITY)


func _knock_down(along: Vector2, now: float) -> void:
	cancel_attack()
	AttackTelegraph.clear_for(self)
	if _phase != PHASE_FIGHT:
		_transition_to(PHASE_FIGHT, now)
	_fling_dir = along
	_downed_landed = false
	_set_shell(SHELL_DOWNED, now)
	var feel := Services.feel()
	if feel != null:
		feel.particles(TATTERS, _cocoon_middle())
		feel.audio_cue(CUE_SHRIEK)


## The way a ram's log swings (its `toward`), right when it has none.
static func _way_of(source: Node) -> Vector2:
	if source != null and &"toward" in source:
		return WAYS.get(str(source.get(&"toward")), Vector2.RIGHT)
	return Vector2.RIGHT


# --- the cocoon fight's turns, the ram fight's way ------------------------------------------------

## Round 1's window ended, or a round's floor was reached: to the next part of the fight.
func _begin_respin(now: float) -> void:
	var next_round := _round_for_hp()
	if _round == 1 and next_round >= 2:
		# round 2 has no cocoon: she climbs up to hang free and rings the targets
		_begin_climb(now)
		_enter_round(2, now)
		_next_dive_at = now + climb_ms + maxf(1.0, first_dive_ms)
		return
	if _round == 2 and next_round == 2:
		_begin_climb(now)
		return
	# a new cocoon: over another ram's lane, picked at random; the torn husk on the floor stays where it
	# lies and fades. Far from that lane's middle she climbs and crawls there first (`_begin_relocate`),
	# then spins: the cocoon always closes over its lane.
	if _open_kind == OPEN_GROUND and (_shell == SHELL_TORN or _shell == SHELL_DOWNED):
		_leave_husk(2 if _shell == SHELL_TORN else 0)
	_pick_home()
	if body != null and _home.is_finite() and body.global_position.distance_to(_home) > RELOCATE_ARRIVE_PX:
		_begin_relocate(now)
		return
	_spin_from_hang = false
	super(now)


func _enter_round(round_number: int, now: float) -> void:
	super(round_number, now)
	if _round >= 3:
		_clear_rings(true)


## Round 2 rings the knock targets (its ring of floor webs and its cage are the built fight's).
func _web_ring(now: float) -> void:
	_next_reweb_at = INF
	_spin_rings(now)


## A blast: round 1's low cocoon tears as built; round 3's high one is out of reach until a ram
## knocks it down, then the blast tears it there; free, she takes no blast.
func receive_blast(hit: Dictionary) -> bool:
	if not _cocoon_on():
		return false
	match _shell:
		SHELL_DOWNED:
			_open_kind = OPEN_GROUND
			_tear(Services.now_ms())
			_shout_tear()
			return true
		SHELL_COCOONED, SHELL_RESPIN:
			var hang := _hang_px() if _shell == SHELL_COCOONED else _next_hang_px()
			if hang > blast_reach_px:
				BlastBarrier.refuse(_cocoon_middle(), high_cocoon_text)
				return false
			_open_kind = OPEN_COCOON
			var torn := super(hit)
			if torn:
				_shout_tear()
			return torn
	return false


func _shout_tear() -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SHRIEK)


func _cocoon_middle() -> Vector2:
	if body == null:
		return get_centre()
	if _shell == SHELL_DOWNED or (_shell == SHELL_TORN and _open_kind != OPEN_COCOON):
		return body.global_position - Vector2(0.0, 40.0)
	if _shell in [SHELL_HANGING, SHELL_CLIMBING, SHELL_RELOCATING, SHELL_DIVING, SHELL_LANDED, SHELL_FLUNG] and _look != null:
		return body.global_position + _look.pose_middle()
	return super()


## While she hangs high her spit leaves her mouth, up there.
func get_centre() -> Vector2:
	if body != null and _cocoon_on() and _shell == SHELL_HANGING:
		return body.global_position - Vector2(0.0, _hang_px() + MOUTH_ABOVE_BOTTOM_PX)
	return super()


# --- damage ---------------------------------------------------------------------------------------

## Open (out of a cocoon or on her back) every weapon reaches her; hanging high or climbing a hit
## clinks with `high_text`; lying after a dive it clinks with `landed_text` (she lies there 4 s: the
## line says what would reach her); diving or flung it glances off unsaid; a cocoon clinks as built.
func can_receive_damage(input: Dictionary) -> Dictionary:
	if _cocoon_on():
		match _shell:
			SHELL_HANGING, SHELL_CLIMBING, SHELL_RELOCATING:
				return BlastBarrier.refuse(_cocoon_middle(), high_text)
			SHELL_LANDED:
				return BlastBarrier.refuse(_cocoon_middle(), landed_text)
			SHELL_DIVING, SHELL_FLUNG:
				return {"accepted": false, "reason": "immune"}
	return super(input)


## Round 3 is her last hit (owner, 2026-11-24: "phase 3 is only when she have a hit left"; the ram
## fight's scene starts it at `round_three_below_hp` 25): open in it, the first hit that lands takes
## all she has left. Else a thrown thing while she is open: `thrown_damage_share` of a Spear hit, no
## lower than her round's floor; else as the cocoon fight.
func mitigate_damage(input: Dictionary) -> float:
	if _cocoon_on() and _round >= 3 and _shell == SHELL_TORN:
		return maxf(0.0, _hp)
	var request: Dictionary = input.get("request", {})
	var tags: Variant = request.get("weapon_tags", [])
	if _cocoon_on() and tags is Array and (tags as Array).has(THROWN_TAG):
		var constants := Services.constants()
		var spear := float(constants.value(SPEAR_BASE_DAMAGE_KEY, 12.0)) if constants != null else 12.0
		return minf(spear * maxf(0.0, thrown_damage_share), maxf(0.0, _hp - round_floor()))
	return super(input)


func _defeat() -> void:
	if is_defeated():
		return
	var on_floor := _shell == SHELL_TORN and _open_kind != OPEN_COCOON
	super()
	_clear_rings(true)
	if _look != null:
		_look.hide_pose()
		if not on_floor:
			_look.hide_all()
	if on_floor and cocoon_look != null:
		# no cocoon hangs over her to unravel: it lies torn on the floor (it fades with her body)
		(cocoon_look as CocoonLook).state = CocoonLook.STATE_OFF


# --- round 2's rings ------------------------------------------------------------------------------

## The ring's slots round every knock target in her arena: four web walls on a square of half side
## `target_ring_radius` round the target's foot (the front and back ones across, the sides side).
func target_ring_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_inside_tree():
		return out
	var r := maxf(16.0, target_ring_radius)
	var half_t := maxf(4.0, cage_thickness_px) / 2.0
	for node: Node in get_tree().get_nodes_in_group(BLAST_GROUP):
		if not node is KnockTargetScript or not (node as Node2D).is_inside_tree():
			continue
		var at := (node as Node2D).global_position
		if not _arena.is_empty() and not BossArena.contains(_arena, at):
			continue
		var across_span := 2.0 * (r + half_t)
		var side_span := 2.0 * maxf(8.0, r - half_t)
		out.append({"at": at + Vector2(0.0, -r), "orientation": "across", "span": across_span})
		out.append({"at": at + Vector2(0.0, r), "orientation": "across", "span": across_span})
		out.append({"at": at + Vector2(-r, 0.0), "orientation": "side", "span": side_span})
		out.append({"at": at + Vector2(r, 0.0), "orientation": "side", "span": side_span})
	return out


## Every slot whose wall is gone or cut gets a new one (faded in), but where the slime's feet are.
func _spin_rings(now: float) -> void:
	_next_ring_spin = now + maxf(1.0, ring_reweb_ms)
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null:
		return
	if _rings == null or not is_instance_valid(_rings):
		_rings = Node2D.new()
		_rings.name = RINGS_NAME
		_rings.y_sort_enabled = true
		parent.add_child(_rings)
		_ring_walls.clear()
		_ring_slots = target_ring_slots()
	_ring_walls.resize(_ring_slots.size())
	var feet: Vector2 = world.player_body.global_position if world.player_body != null else Vector2.INF
	var spun := false
	for index in _ring_slots.size():
		var wall: Variant = _ring_walls[index]
		var standing := wall != null and is_instance_valid(wall)
		if standing and not bool((wall as Node).call(&"is_cut")):
			continue
		if feet.is_finite() and _slot_rect(_ring_slots[index]).grow(STUCK_REACH_PX).has_point(feet):
			continue
		if standing:
			(wall as Node).queue_free()
		_ring_walls[index] = _spawn_ring_wall(_ring_slots[index])
		spun = true
	if spun:
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_RESPIN)


func _spawn_ring_wall(slot: Dictionary) -> Node2D:
	var world := Services.world()
	var wall := world.instantiate_scene(CAGE_WALL_SCENE) as Node2D if world != null else null
	if wall == null:
		return null
	wall.set(&"orientation", slot["orientation"])
	wall.set(&"span", float(slot["span"]))
	wall.set(&"thickness", maxf(4.0, cage_thickness_px))
	if str(slot["orientation"]) == "across" and cage_height_px > 0.0:
		wall.set(&"height", cage_height_px)
	wall.set(&"remembered", false)
	wall.position = _rings.to_local(slot["at"] as Vector2)
	wall.modulate.a = 0.0
	_rings.add_child(wall)
	wall.create_tween().tween_property(wall, "modulate:a", 1.0, SPIN_IN_S)
	return wall


func _clear_rings(tatters: bool = false) -> void:
	_next_ring_spin = INF
	if _rings != null and is_instance_valid(_rings):
		var feel := Services.feel() if tatters else null
		if feel != null:
			for wall: Node in get_ring_walls():
				if not bool(wall.call(&"is_cut")):
					feel.particles(TATTERS, (wall as Node2D).global_position)
		_rings.queue_free()
	_rings = null
	_ring_walls.clear()
	_ring_slots.clear()


# --- the look -------------------------------------------------------------------------------------

## Her look in the ram fight takes the place of the old Visual and of the cocoon fight's pose sheet.
func _make_pose() -> void:
	if body == null or _look != null:
		return
	if visual != null:
		visual.visible = false
	_look = RamLook.new()
	_look.name = "MatronRamLook"
	body.add_child(_look)
	_pose = _look.pose_sprite()
	visual = _pose
	_visual_rest = Vector2.ZERO
	HitFlash.install(_pose)


func _present(now: float) -> void:
	var cocoon := cocoon_look as CocoonLook
	if _look == null or cocoon == null:
		return
	var elapsed := now - _shell_started_at
	var hang := _hang_px()
	cocoon.hang_px = hang
	cocoon.state = CocoonLook.STATE_OFF
	_look.hide_prop()
	match _shell:
		SHELL_COCOONED:
			cocoon.state = CocoonLook.STATE_COCOONED
			cocoon.breath = (sin(now / maxf(1.0, breath_ms) * TAU) + 1.0) * 0.5
			_look.hide_all()
		SHELL_TORN:
			_present_open(now, elapsed, hang, cocoon)
		SHELL_RESPIN:
			_present_respin(elapsed, cocoon)
		SHELL_HANGING:
			if now < _ram_call_until:
				_look.show_pose("spit", _ram_call_frame(now), hang, false, true)
			elif is_attacking():
				_look.show_pose("spit", _spit_frame(now), hang, false, true)
			else:
				_look.show_pose("hang", _look.pose_sprite().play_index("hang", now), hang, false, true)
			_look.set_shadow(hang)
		SHELL_DIVING:
			var p := _dive_progress(now)
			var bottom := hang * (1.0 - p * p)
			var frame := 0 if p < DIVE_FRAME_AT[0] else (1 if p < DIVE_FRAME_AT[1] else 2)
			_look.show_pose("dive", frame, bottom)
			_look.set_shadow(bottom)
		SHELL_LANDED:
			if now < _ram_call_until:
				_look.show_pose("spit", _ram_call_frame(now), 0.0)
			else:
				_look.show_pose("dive", 3, 0.0)
			_look.set_shadow(0.0)
		SHELL_FLUNG:
			var frame := 0 if elapsed < 90.0 else (1 if elapsed < 260.0 else 2)
			var arc := FLING_ARC_PX * sin(clampf(elapsed / maxf(1.0, fling_max_ms), 0.0, 1.0) * PI)
			_look.show_pose("rammed", frame, arc, _fling_dir.x < 0.0)
			_look.set_shadow(arc)
		SHELL_CLIMBING:
			var up := hang * clampf(elapsed / maxf(1.0, climb_ms), 0.0, 1.0)
			_look.show_pose("climb", _look.pose_sprite().play_index("climb", elapsed), up, false, true)
			_look.set_shadow(up)
		SHELL_RELOCATING:
			# up her thread to the new cocoon's hang, then along her web to its lane (hanging, crawling)
			var target_hang := _next_hang_px()
			var climb := _relocate_climb_ms()
			if elapsed < climb:
				var up := lerpf(_relocate_from_px, target_hang, clampf(elapsed / maxf(1.0, climb), 0.0, 1.0))
				_look.show_pose("climb", _look.pose_sprite().play_index("climb", elapsed), up, false, true)
				_look.set_shadow(up)
			else:
				_look.show_pose("hang", _look.pose_sprite().play_index("hang", now), target_hang, false, true)
				_look.set_shadow(target_hang)
		SHELL_DOWNED:
			_look.hide_pose()
			var t := clampf(elapsed / maxf(1.0, downed_fall_ms), 0.0, 1.0)
			var bottom := hang * (1.0 - t * t)
			var straining := t >= 1.0 and int((elapsed - downed_fall_ms) / STRAIN_MS) % 2 == 1
			_look.show_prop("cocoon", 1 if straining else 0, bottom)
			_look.set_shadow(bottom)


## The ram call's spit frame (1 to 3) while it shows.
func _ram_call_frame(now: float) -> int:
	var p := 1.0 - (_ram_call_until - now) / RAM_CALL_SPIT_MS
	return 1 if p < 0.4 else (2 if p < 0.7 else 3)


## Open: dazed under the torn cocoon (round 1: the husk hangs; round 3: it lies on the floor), or on
## her back after a ram (round 2).
func _present_open(now: float, elapsed: float, hang: float, cocoon: CocoonLook) -> void:
	if _open_kind == OPEN_BACK:
		var since := now - _crash_at
		if since < CRASH_FRAME_MS:
			_look.show_pose("rammed", 3, 0.0, _fling_dir.x < 0.0)
		else:
			_look.show_pose("on-back", _look.pose_sprite().play_index("on-back", since - CRASH_FRAME_MS), 0.0)
		_look.set_shadow(0.0)
		return
	var from := hang if _open_kind == OPEN_COCOON else 30.0
	if _open_kind == OPEN_COCOON:
		cocoon.state = CocoonLook.STATE_TORN
	else:
		_look.show_prop("cocoon", 2, 0.0)
	var t := clampf(elapsed / maxf(1.0, drop_ms), 0.0, 1.0)
	if t >= 1.0 and not _landed:
		_landed = true
		_shake_camera(LAND_SHAKE_MS, LAND_SHAKE_INTENSITY)
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_LAND)
	var bottom := from * (1.0 - t) * (1.0 - t)
	var frame := 0
	if t >= 1.0:
		var twitch := int(elapsed / DAZED_TWITCH_MS) % 2 == 1
		frame = 3 if now < _flinch_until else (2 if twitch else 1)
	_look.show_pose("dazed", frame, bottom)
	_look.set_shadow(bottom, _open_kind != OPEN_COCOON)


## The respin: she climbs to the hang (from the floor or her back), then spins herself in; the old
## husk fades (on the floor) or hangs until she reaches it (round 1).
func _present_respin(elapsed: float, cocoon: CocoonLook) -> void:
	var p := clampf(elapsed / maxf(1.0, respin_ms), 0.0, 1.0)
	var hang := _next_hang_px()
	cocoon.hang_px = hang
	if _spin_from_hang:
		# she crawled here hanging: the whole respin is the spin
		_look.show_pose("spin", clampi(int(p * 4.0), 0, 3), hang, false, true)
		_look.set_shadow(hang)
		return
	if p < RESPIN_CLIMB_SHARE:
		var up := hang * p / RESPIN_CLIMB_SHARE
		_look.show_pose("climb", _look.pose_sprite().play_index("climb", elapsed), up, false, true)
		_look.set_shadow(up)
		return
	var spin := clampi(int((p - RESPIN_CLIMB_SHARE) / (1.0 - RESPIN_CLIMB_SHARE) * 4.0), 0, 3)
	_look.show_pose("spin", spin, hang, false, true)
	_look.set_shadow(hang)


## Her web spit (the base's projectile), grown to her size: `spit_scale` on its picture and hitbox.
func _fire_projectile(origin: Vector2, config: Dictionary) -> void:
	var root := EnemyProjectiles.fire({
		"source": self,
		"position": origin,
		"direction": _attack_direction,
		"speed": _attribute("projectileSpeed", DEFAULT_PROJECTILE_SPEED),
		"damage": float(config["damage"]),
		"knockback_strength": _attribute("knockbackStrength"),
		"projectile_id": str(config["projectile_id"]),
		"asset_id": str(config["asset_id"]),
		"stick_ms": float(config["stick_ms"]),
	})
	if root == null:
		return
	root.scale *= maxf(0.1, spit_scale)
	# a spit that misses the slime leaves a web ball where it ends (a wall, the end of its flight)
	var shot := EnemyProjectiles.find_projectile_script(root)
	if shot != null:
		shot.expired.connect(_on_spit_expired.bind(shot, root), CONNECT_ONE_SHOT)


func _on_spit_expired(_payload: Dictionary, shot: ProjectileScript, root: Node2D) -> void:
	if shot == null or not is_instance_valid(shot) or shot.did_hit_target() or not is_instance_valid(root):
		return
	_drop_web_ball(root.global_position)


## The base's volley landing (the hit, a web patch on every mark), and a web ball on every mark that
## missed the slime.
func _land_volley(now: float) -> void:
	var missed: Array[Vector2] = []
	var target := _primary_target()
	var hits := not target.is_empty() and bool(target.get("active", false))
	for shape: Dictionary in volley_shapes():
		var one: Array[Dictionary] = [shape]
		if not hits or not _target_overlaps(one, target):
			missed.append((shape["transform"] as Transform2D).origin)
	super(now)
	for point: Vector2 in missed:
		_drop_web_ball(point)


## A web ball (a liftable of `web_ball_kind`) at `at`, kept inside her arena and never on the slime;
## past `max_web_balls` the oldest unravels.
func _drop_web_ball(at: Vector2) -> void:
	if web_ball_kind.is_empty() or max_web_balls <= 0 or is_defeated():
		return
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	var packed := load(LIFTABLE_SCENE) as PackedScene
	if parent == null or packed == null:
		return
	var point := BossArena.clamp_point(_arena, at) if not _arena.is_empty() else at
	var target := _primary_target()
	if not target.is_empty() and point.distance_to(target.get("centre", Vector2.INF)) < WEB_BALL_CLEAR_PX:
		return
	var ball := packed.instantiate() as Node2D
	ball.set(&"kind", web_ball_kind)
	ball.set(&"under", WEB_BALL_UNDER)
	ball.name = "WebBall"
	parent.add_child(ball)
	ball.global_position = point
	ball.reset_physics_interpolation()
	var visual := ball.get_node_or_null(^"Visual") as Node2D
	if visual != null:
		var full := visual.scale
		visual.scale = full * WEB_BALL_POP_FROM
		visual.create_tween().tween_property(visual, "scale", full, WEB_BALL_POP_S) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_prune_web_balls()
	_web_balls.append(ball)
	while _web_balls.size() > max_web_balls:
		_unravel(_web_balls.pop_front())


## Drops the web balls that are gone (sucked up, thrown, unravelled). A ball the Gulp took is a
## freed object in the list, so each entry is checked as a Variant before it is typed: a typed
## lambda in `filter` fails on a freed object and `filter` then returns an untyped empty Array.
func _prune_web_balls() -> void:
	var kept: Array[Node2D] = []
	for i in _web_balls.size():
		var entry: Variant = _web_balls[i]
		if is_instance_valid(entry) and not (entry as Node2D).is_queued_for_deletion():
			kept.append(entry as Node2D)
	_web_balls = kept


## A web ball too many: it can no longer be sucked up, flattens and fades away.
func _unravel(ball: Node2D) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var script_node := ball.get_node_or_null(LIFTABLE_SCRIPT_NODE)
	if script_node != null:
		for group: StringName in script_node.get_groups():
			script_node.remove_from_group(group)
	var body := ball as CollisionObject2D
	if body != null:
		body.set_deferred(&"collision_layer", 0)
	for child: Node in ball.get_children():
		if child is Area2D:
			(child as Area2D).set_deferred(&"monitorable", false)
			(child as Area2D).set_deferred(&"monitoring", false)
	var tween := ball.create_tween().set_parallel(true)
	tween.tween_property(ball, "scale", Vector2(1.3, 0.2), WEB_BALL_UNRAVEL_S)
	tween.tween_property(ball, "modulate:a", 0.0, WEB_BALL_UNRAVEL_S)
	tween.chain().tween_callback(ball.queue_free)


## The web balls lying now (the films and tests read them).
func get_web_balls() -> Array[Node2D]:
	_prune_web_balls()
	return _web_balls.duplicate()


## Her volley's web patches grown to her size: `patch_scale` on their picture and slowing circle.
func _spawn_effect_at(effect_id: String, point: Vector2) -> void:
	if effect_id.is_empty():
		return
	var world := Services.world()
	if world == null:
		return
	var root := world.spawn_at_phaser_position("effect." + effect_id, point)
	if root == null or effect_id != patch_effect_id:
		return
	var grow := maxf(0.1, patch_scale)
	root.scale *= grow
	for child: Node in root.get_children():
		if &"radius" in child:
			child.set(&"radius", float(child.get(&"radius")) * grow)


## The cocoon left on the floor (`frame`: knocked down whole, or torn) as its own picture where it
## lies, fading out while she climbs away to spin a new one.
func _leave_husk(frame: int) -> void:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null or body == null or _look == null:
		return
	var husk := RamLook.new()
	husk.name = "MatronHusk"
	husk.position = parent.to_local(body.global_position)
	parent.add_child(husk)
	husk.show_prop("cocoon", frame, 0.0)
	var tween := husk.create_tween()
	tween.tween_property(husk, "modulate:a", 0.0, HUSK_FADE_S)
	tween.tween_callback(husk.queue_free)


## The spit's frame from the common attack's timing: the wind-up, the charge, the spit, the recovery.
func _spit_frame(now: float) -> int:
	if now < _attack_impact_at:
		var windup := maxf(1.0, _attribute("attackWindupMs"))
		return 0 if (_attack_impact_at - now) > windup * 0.5 else 1
	return 2 if now - _attack_impact_at < SPIT_SHOW_MS else 3

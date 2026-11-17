extends RefCounted
## What the ground does to an enemy a blow moves (owner, 2026-11-16: "if enemies are pushed against
## an edge that has no fence and they can fall, they should fall; if it is an endless hole they
## should die, disappearing as they fall, becoming smaller until gone, similar to Zelda; in deep
## water they should drown if they are not aquatic creatures; and in danger zones they should
## receive the damage as the player does until they get out or die"). Static; EnemyReactions calls
## it for a body a blow moves (a throw's knock, a launch, a bowl, a kill's sliding corpse:
## `after_move` while `ReactionState.blown_until_ms` runs) and gulpable_enemy.gd for a thrown enemy
## that comes down (`landing`). Never for an enemy that walks by itself: its own AI is not looked at
## here, so nothing walks off a ledge, into a hole or into deep water because of this. Behind
## `combat.rules.hazards.enabled`; with it off a blown body splats on every rim and bank as before.
##
## Everything is the slime's own logic, asked for the enemy's body:
## - **A ledge** (`at_obstacle`): the mover's collider stopped it faster than `minSpeed` into a rim
##   the slime could drop from: `Elevation.drop_target` (which is `ledge_below`: a rim that drops,
##   no fence, no wall, no stairs, room below). It goes over (`_fall`): enemy.gd flies its body to the
##   landing over the slime's drop time (`elevation.dropBaseMs` + `dropMsPerLevel` per level), its
##   art in the slime's drop arc (EnemyHitMotion.DROP); it lands knocked down `fall.stunMs` with a dust
##   puff, takes `fall.damagePerLevel` per level fallen (a death there is a send-off's pop), and
##   lives on that level from then on: the elevation tracks its body there (so a throw from that level
##   reaches it), and its territory, its arena and a patterned enemy's home are let go or moved to
##   where it landed (enemy.gd `settle_at`), so it fights there and never walks at the cliff to get
##   back. A fenced rim, a wall and a rim with no room below still stop it with the splat.
## - **An endless hole**: the landing of that drop lies in a void Hazard (hazard.gd `covers`: the
##   dungeons' void, the sky floor's SkyFall), or a blown body slides into one on its own level, or
##   a thrown enemy comes down over one. It dies at once, where it stood (`_die_into`: counted as
##   killed in every way: `defeated`, the rewards and `enemy.died` at the rim it went over, where the
##   slime can reach them), then its corpse glides out over the hole, spins and shrinks to nothing
##   over the slime's `dungeon.void.fallMs` with the slime's `FallDown` cue (EnemyHitMotion.HOLE_FALL;
##   no corpse, no pop), and the kill cue plays as it is gone (`fate_done`).
## - **Deep water**: the ground past the collider, the drop's landing or a thrown enemy's landing is
##   a deep-water tile with no bridge over it (the slime's own test), or a water Hazard. A creature
##   that is not `aquatic` drowns: dead at the bank as above, a splash (the dungeon's WaterSplash
##   rings and cue), and its corpse glides in, sinks and fades over `dungeon.water.fallMs`
##   (EnemyHitMotion.DROWN). An aquatic one is stopped by the bank as before. Shallow water is ground.
## - **A danger zone** (spikes, lava): a blown body that comes to lie in one (or falls into a sunken
##   one, or is thrown into one) takes the hazard's own damage (`Hazard.hit_damage`) every
##   `character.player.hitInvulnerabilityMs`, the slime's rhythm, from the moment it is in it until it
##   is out or dead (`step`, from enemy.gd every step; a death is a send-off's pop). Stunned, it
##   stays; on its legs again it walks out the shortest way at `zone.walkOutSpeed` (`walk_out`, read
##   by enemy.gd and patterned_enemy.gd before their AI), unless it lies in a sunken pit (the only
##   way out is the stairs: it stays). Once out it is left alone: an enemy that wanders into a zone
##   by itself is never hurt by this.
## - **Who is spared** (the type's `reactions` in enemy-types.json): `flies` (holes, water, ledges
##   and zones do nothing: it is stopped by what stops it, as before), `aquatic` (deep water), and
##   `hazardProof` (a list of what never hurts it: "fall", "void", "water", "spikes", "lava"). A
##   boss is never touched.
##
## Owner: reactions.

const Services := preload("res://game/shared/services.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const ReactionState := preload("res://game/combat/reactions/reaction_state.gd")
const EnemyHitMotion := preload("res://game/feel/enemy_hit_motion.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const Hazard := preload("res://game/dungeon/hazard.gd")
const HazardDeck := preload("res://game/dungeon/hazard_deck.gd")
const WaterSplash := preload("res://game/dungeon/water_splash.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const JumpSequence := preload("res://game/player/abilities/jump_sequence.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")

const ROOT := "combat.rules.hazards"
## The fates (enemy.gd `begin_fate`) and what `hazardProof` can name.
const FATE_HOLE := "hole"
const FATE_WATER := "water"
const KIND_FALL := "fall"
const KIND_VOID := "void"
const KIND_WATER := "water"
const KIND_SPIKES := "spikes"
const KIND_LAVA := "lava"
## The slime's own cues and looks (hazard_watch.gd).
const CUE_FALL := &"FallDown"
const CUE_SPLASH := &"WaterSplash"
const DUST := &"dodge-dust"
## The ground's deep-water tile (player_swimming.gd).
const TILE_ID_DATA_LAYER := "tile_id"
const DEEP_TILE_ID := "deep-water"
## How far past its feet a stopped body looks for deep water (px, two probes).
const WATER_PROBES: Array[float] = [18.0, 30.0]
## One level of height (units).
const LEVEL_UNITS := 64.0
const WEIGHT_BOSS := "boss"
## A push with more of it down the screen than this goes over a south face.
const SOUTH_FACE := 0.5

static var _reactions_script: GDScript


## True while the hazards act (`combat.rules.hazards.enabled`).
static func is_on() -> bool:
	var constants := Services.constants()
	return constants != null and bool(constants.value(ROOT + ".enabled", false))


## A blown body of `enemy` was stopped this step (`info`: the mover's collision, not an enemy's or the
## slime's body). True when a fate took it: it fell, or it died into a hole or into deep water. The
## caller splats it otherwise.
static func at_obstacle(enemy: Node, body: CharacterBody2D, state: ReactionState, info: Dictionary, now: float) -> bool:
	if not is_on() or body == null or _spared(enemy):
		return false
	var normal: Vector2 = info.get("normal", Vector2.ZERO)
	var before: Vector2 = info.get("velocity", Vector2.ZERO)
	if normal == Vector2.ZERO or -before.dot(normal) < _number("minSpeed"):
		return false
	var way := -normal
	var feet := body.global_position
	var world := Services.world()
	var elevation: Elevation = world.elevation if world != null else null
	var profile := ReactionProfile.for_enemy(enemy)
	# Deep water past the bank it was stopped at.
	if not _proof(profile, KIND_WATER):
		for reach: float in WATER_PROBES:
			if deep_at(feet + way * reach):
				_die_into(enemy, state, FATE_WATER, feet + way * _number("water.overPx"), true, now)
				return true
	if elevation == null or not is_instance_valid(elevation) or not elevation.bodies.has(body):
		return false
	var level := elevation.level_of(body)
	var target := elevation.drop_target(feet, level, way)
	if target.is_empty():
		return false
	var landing: Vector2 = target["feet"]
	var to := int(target["level"])
	var under := hazard_at(landing - Vector2(0.0, Elevation.BODY_HALF.y), to)
	if under != null and under.kind == KIND_VOID:
		if _proof(profile, KIND_VOID):
			return false
		# Off a south face it falls down the face to where a drop lands; off any other rim it shrinks
		# away just past the rim (the hole lies there on screen, not a cliff's height further down).
		_die_into(enemy, state, FATE_HOLE, landing if way.y > SOUTH_FACE else feet + way * _number("hole.overPx"), true, now)
		return true
	if (under != null and under.kind == KIND_WATER) or deep_at(landing):
		if _proof(profile, KIND_WATER):
			return false
		_die_into(enemy, state, FATE_WATER, landing, true, now)
		return true
	if _defeated(enemy) or _proof(profile, KIND_FALL):
		# A sliding corpse stops at a plain rim (its send-off pops it there).
		return false
	_fall(enemy, body, state, landing, level, to, now)
	return true


## A blown body of `enemy` moved this step: a void or a water Hazard on its own level under it takes
## it (true), a spikes or lava one starts to hurt it (`step`).
static func over(enemy: Node, body: CharacterBody2D, state: ReactionState, now: float) -> bool:
	if not is_on() or body == null or _spared(enemy):
		return false
	var hazard := hazard_at(_middle(body), _level_of(body))
	if hazard == null:
		return false
	var profile := ReactionProfile.for_enemy(enemy)
	if _proof(profile, hazard.kind):
		return false
	if hazard.kind == KIND_VOID:
		_die_into(enemy, state, FATE_HOLE, body.global_position, false, now)
		return true
	if hazard.kind == KIND_WATER:
		_die_into(enemy, state, FATE_WATER, body.global_position, false, now)
		return true
	if not _defeated(enemy):
		_enter_zone(state, hazard, now)
	return false


## Every physics step of `enemy` (enemy.gd): the danger zone a blow put it in hurts it on the
## slime's rhythm until it is out of it.
static func step(enemy: Node) -> void:
	if enemy == null or not enemy.has_meta(&"reaction_state"):
		return
	var state := enemy.get_meta(&"reaction_state") as ReactionState
	if state == null or state.zone_hazard == 0:
		return
	var hazard := _zone_of(enemy, state)
	if hazard == null:
		state.zone_hazard = 0
		return
	var now := Services.now_ms()
	if now < state.zone_next_ms:
		return
	state.zone_next_ms = now + _player_rhythm_ms()
	_hurt(enemy, state, hazard.hit_damage(), now)


## The way out of the danger zone `enemy` lies in, for an enemy on its legs (a unit vector; ZERO
## when it is in none, or in a sunken pit it cannot walk out of): its AI is skipped and it walks
## that way at `walk_out_speed()` (enemy.gd, patterned_enemy.gd).
static func walk_out(enemy: Node) -> Vector2:
	if enemy == null or not enemy.has_meta(&"reaction_state"):
		return Vector2.ZERO
	var state := enemy.get_meta(&"reaction_state") as ReactionState
	if state == null or state.zone_hazard == 0:
		return Vector2.ZERO
	var hazard := _zone_of(enemy, state)
	var body := _body_of(enemy)
	if hazard == null or body == null or _level_of(body) < hazard.rim():
		return Vector2.ZERO
	var rect := hazard.rect()
	var at := _middle(body)
	var ways := {Vector2.LEFT: at.x - rect.position.x, Vector2.RIGHT: rect.end.x - at.x,
		Vector2.UP: at.y - rect.position.y, Vector2.DOWN: rect.end.y - at.y}
	var best := Vector2.ZERO
	var nearest := INF
	for way: Vector2 in ways:
		if float(ways[way]) < nearest:
			nearest = float(ways[way])
			best = way
	return best


static func walk_out_speed() -> float:
	return _number("zone.walkOutSpeed")


## A thrown enemy comes down with its ground point at `at` (gulpable_enemy.gd, before it looks for a
## spot to stand on): "hole" over an endless hole, "water" over deep water, "" over ground. The
## thrown thing flew at height level `level`.
static func landing_fate(enemy: Node, at: Vector2, level: int) -> String:
	if not is_on() or _spared(enemy):
		return ""
	var profile := ReactionProfile.for_enemy(enemy)
	var world := Services.world()
	var elevation: Elevation = world.elevation if world != null else null
	var ground := level
	if elevation != null and is_instance_valid(elevation):
		ground = mini(level, elevation.level_at(at)) if level != AbilityWorld.ANY_LEVEL else elevation.level_at(at)
	var hazard := hazard_at(at, ground)
	if hazard != null and hazard.kind == KIND_VOID and not _proof(profile, KIND_VOID):
		return FATE_HOLE
	if ((hazard != null and hazard.kind == KIND_WATER) or deep_at(at)) and not _proof(profile, KIND_WATER):
		return FATE_WATER
	return ""


## A thrown enemy met `fate` (`landing_fate`) at `at`: it stands (put there by the caller) on the
## nearest ground the slime reaches, dies there (its rewards fall there) and its corpse falls or
## sinks at `at`.
static func landing_death(enemy: Node, fate: String, at: Vector2) -> void:
	_die_into(enemy, _state_of(enemy), fate, at, false, Services.now_ms())


## A thrown enemy stands on `spot` after its landing: a spikes or lava Hazard there starts to hurt it.
static func landed_at(enemy: Node) -> void:
	if not is_on() or _spared(enemy) or _defeated(enemy):
		return
	var body := _body_of(enemy)
	if body == null:
		return
	var hazard := hazard_at(_middle(body), _level_of(body))
	if hazard != null and hazard.is_pit() and not _proof(ReactionProfile.for_enemy(enemy), hazard.kind):
		_enter_zone(_state_of(enemy), hazard, Services.now_ms())


## The fall of `enemy` ended (enemy.gd, as its body stands on the landing): dust, the fall's damage
## per level, the knockdown it lies in, its new home, and the zone it may have fallen into.
static func landed(enemy: Node, levels: int) -> void:
	var body := _body_of(enemy)
	var feel := Services.feel()
	if body != null and feel != null:
		feel.burst(DUST, body.global_position)
	if _defeated(enemy) or body == null:
		return
	var state := _state_of(enemy)
	var now := Services.now_ms()
	if enemy.has_method(&"settle_at"):
		enemy.call(&"settle_at", enemy.call(&"get_centre"))
	_hurt(enemy, state, _number("fall.damagePerLevel") * float(maxi(1, levels)), now)
	if _defeated(enemy):
		return
	# What it landed in: a hole or deep water after all (the slime, too, lands in the sky and is caught
	# there), or a sunken danger zone.
	var hazard := hazard_at(_middle(body), _level_of(body))
	var profile := ReactionProfile.for_enemy(enemy)
	if hazard == null or _proof(profile, hazard.kind):
		return
	if hazard.is_pit():
		_enter_zone(state, hazard, now)
	else:
		_die_into(enemy, state, FATE_WATER if hazard.kind == KIND_WATER else FATE_HOLE, body.global_position, false, now)


## The fate of `enemy`'s corpse is over (enemy.gd, as the corpse goes): the kill cue, at the pop
## streak's pitch.
static func fate_done(enemy: Node) -> void:
	var feel := Services.feel()
	var constants := Services.constants()
	if feel == null or constants == null:
		return
	var cue := str(constants.value("combat.rules.killSendoff.cue", ""))
	if cue.is_empty():
		return
	var pitch := _state_of(enemy).sendoff_pitch if enemy != null and enemy.has_meta(&"reaction_state") else 1.0
	feel.audio_cue(StringName(cue), {"pitch": pitch})


## The Hazard a body with its middle at `point`, walking on `level`, is in (hazard.gd `covers`; one
## per floor level: a body above a hazard's rim is over it, not in it), unless a deck holds it up
## there (hazard_deck.gd, as HazardWatch asks for the slime). Null when none.
static func hazard_at(point: Vector2, level: int) -> Hazard:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found: Hazard = null
	for node: Node in tree.get_nodes_in_group(Hazard.GROUP):
		var hazard := node as Hazard
		if hazard == null or not hazard.is_inside_tree() or not hazard.covers(point) or level > hazard.rim():
			continue
		found = hazard
		break
	if found == null:
		return null
	if level == found.rim():
		for deck: Node in tree.get_nodes_in_group(HazardDeck.GROUP):
			if bool(deck.call(&"holds")) and bool(deck.call(&"holds_at", point)) and int(deck.call(&"deck_level")) <= level:
				return null
	return found


## True when the ground at `point` is deep water with no bridge deck over it (the slime's own test:
## player_swimming.gd `_deep_at`).
static func deep_at(point: Vector2) -> bool:
	var world := Services.world()
	var ground: TileMapLayer = world.ground_layer if world != null else null
	if ground == null or not is_instance_valid(ground):
		return false
	var cell := ground.local_to_map(ground.to_local(point))
	if world.is_bridged(cell.x, cell.y):
		return false
	var data := ground.get_cell_tile_data(cell)
	return data != null and str(data.get_custom_data(TILE_ID_DATA_LAYER)) == DEEP_TILE_ID


# --- the fates --------------------------------------------------------------------------------------

## Over the ledge, alive: the body flies to `landing` on level `to` over the slime's drop time, its
## art in the drop's arc, stunned until it has lain there `fall.stunMs`.
static func _fall(enemy: Node, body: CharacterBody2D, state: ReactionState, landing: Vector2, from: int, to: int, now: float) -> void:
	if not enemy.has_method(&"begin_fall"):
		return
	var levels := maxi(1, from - to)
	var ms := Elevation.setting("dropBaseMs") + Elevation.setting("dropMsPerLevel") * float(levels)
	var down := _number("fall.stunMs")
	state.verb = HitReaction.VERB_KNOCKDOWN
	state.stun_until_ms = maxf(state.stun_until_ms, now + ms + down)
	state.damage_taken = 1.0
	state.launch_until_ms = now
	state.blown_until_ms = now
	state.slide_decay_until_ms = 0.0
	state.wake_until_ms = now
	# It lies helpless where it landed (a throw's blow sent it over).
	state.throw_helpless = true
	state.helpless_from_ms = now + ms
	if enemy.has_method(&"cancel_attack"):
		enemy.call(&"cancel_attack")
	if enemy.has_method(&"set_hit_stun_until"):
		enemy.call(&"set_hit_stun_until", maxf(float(enemy.call(&"get_hit_stun_until")), now + ms + down))
	var away := landing - body.global_position
	var motion := _motion_of(enemy)
	if motion != null:
		motion.hide_stars()
		motion.play(EnemyHitMotion.DROP, away, {
			"ms": ms, "lift": JumpSequence.lift(JumpSequence.DROP_ARC, float(levels) * LEVEL_UNITS),
			"then": EnemyHitMotion.FALL, "then_params": {"ms": down, "down": true},
		})
	enemy.call(&"begin_fall", landing, to, ms)


## Into an endless hole or deep water: `enemy` dies where it stands (its rewards fall there, every
## listener hears its death), no death puff, and its corpse meets `fate` over `over` (it glides
## there when `glides`, else it is put there): enemy.gd `begin_fate`. A corpse that slid in only
## meets the fate.
static func _die_into(enemy: Node, state: ReactionState, fate: String, over: Vector2, glides: bool, now: float) -> void:
	if not enemy.has_method(&"begin_fate"):
		return
	var feel := Services.feel()
	var body := _body_of(enemy)
	var away := over - body.global_position if body != null else Vector2.ZERO
	if not _defeated(enemy):
		state.sendoff = true
		state.sendoff_pitch = float(_reactions().call(&"kill_pitch", now))
		state.zone_hazard = 0
		if enemy.has_method(&"cancel_attack"):
			enemy.call(&"cancel_attack")
		if enemy.has_method(&"take_reaction_damage"):
			enemy.call(&"take_reaction_damage", _health(enemy))
		if not _defeated(enemy):
			state.sendoff = false
			return
	state.launch_until_ms = now
	state.blown_until_ms = now
	var motion := _motion_of(enemy)
	if motion != null:
		motion.hide_stars()
	# It goes as it was struck (its hurt pose, blinking), not as a corpse lying down.
	if enemy.has_method(&"play_hurt"):
		enemy.call(&"play_hurt", "knockback")
	_reactions().call(&"flash_fate", enemy)
	var water := fate == FATE_WATER
	var ms := DungeonState.number("water.fallMs", EnemyHitMotion.DROWN_MS) if water else DungeonState.number("void.fallMs", EnemyHitMotion.HOLE_MS)
	if water:
		WaterSplash.spawn(over, DungeonState.number("plank.ringRadiusPx", 46.0), DungeonState.number("water.splashRingMs", 900.0),
			int(DungeonState.number("plank.rings", 3.0)))
		if motion != null:
			motion.play(EnemyHitMotion.DROWN, away, {"ms": ms, "sink_px": DungeonState.number("water.sinkPx", EnemyHitMotion.DROWN_SINK_PX)})
	elif motion != null:
		motion.play(EnemyHitMotion.HOLE_FALL, away, {"ms": ms})
	if feel != null:
		feel.audio_cue(CUE_SPLASH if water else CUE_FALL)
	enemy.call(&"begin_fate", fate, over, ms, glides)


## A spikes or lava Hazard starts to hurt the enemy now (its first hit at once).
static func _enter_zone(state: ReactionState, hazard: Hazard, now: float) -> void:
	if hazard == null or not hazard.is_pit() or state.zone_hazard == hazard.get_instance_id():
		return
	state.zone_hazard = hazard.get_instance_id()
	state.zone_next_ms = now


## The zone `state` remembers while the enemy's body is still in it; null once it is out (or gone).
static func _zone_of(enemy: Node, state: ReactionState) -> Hazard:
	if not is_on() or _defeated(enemy) or not is_instance_id_valid(state.zone_hazard):
		return null
	var hazard := instance_from_id(state.zone_hazard) as Hazard
	var body := _body_of(enemy)
	if hazard == null or body == null or (enemy.has_method(&"is_carried") and bool(enemy.call(&"is_carried"))):
		return null
	return hazard if hazard_at(_middle(body), _level_of(body)) == hazard else null


## Hazard damage on `enemy` (a fall's, a zone's): its number, and a death by it is a send-off's pop
## where it lies.
static func _hurt(enemy: Node, state: ReactionState, amount: float, now: float) -> void:
	var dealt := int(_reactions().call(&"hurt_by_ground", enemy, state, roundi(amount), now))
	var feel := Services.feel()
	if dealt > 0 and feel != null and feel.has_method(&"play_hit"):
		feel.play_hit({"hit_stop_ms": 0.0, "number": dealt, "number_big": false}, enemy.call(&"get_centre"), Vector2.ZERO)


# --- helpers ----------------------------------------------------------------------------------------

## A boss and a creature that flies are never touched.
static func _spared(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.get(&"reaction_preset") is String:
		return true
	var profile := ReactionProfile.for_enemy(enemy)
	return str(profile.get("weight", "")) == WEIGHT_BOSS or bool(profile.get("flies", false)) \
		or (enemy.has_method(&"can_send_off") and not bool(enemy.call(&"can_send_off")))


## True when `kind` never hurts this type: its `hazardProof` list, and `aquatic` for water.
static func _proof(profile: Dictionary, kind: String) -> bool:
	if kind == KIND_WATER and bool(profile.get("aquatic", false)):
		return true
	var list: Variant = profile.get("hazardProof", [])
	return list is Array and (list as Array).has(kind)


static func _player_rhythm_ms() -> float:
	var constants := Services.constants()
	return maxf(1.0, constants.number("character.player.hitInvulnerabilityMs")) if constants != null else 500.0


## The middle of the body's footprint (where HazardWatch reads the slime): a little over its feet.
static func _middle(body: Node2D) -> Vector2:
	return body.global_position - Vector2(0.0, Elevation.BODY_HALF.y)


static func _level_of(body: Node2D) -> int:
	var world := Services.world()
	var elevation: Elevation = world.elevation if world != null else null
	if elevation == null or not is_instance_valid(elevation):
		return 0
	return elevation.level_of(body) if elevation.bodies.has(body) else elevation.level_at(body.global_position)


static func _health(enemy: Node) -> float:
	var found: Variant = enemy.call(&"get_damage_state") if enemy.has_method(&"get_damage_state") else null
	return float((found as Dictionary).get("hp", 0.0)) if found is Dictionary else 0.0


static func _defeated(enemy: Node) -> bool:
	return enemy.has_method(&"is_defeated") and bool(enemy.call(&"is_defeated"))


static func _body_of(enemy: Node) -> CharacterBody2D:
	if enemy == null or not enemy.has_method(&"get_body"):
		return null
	var body: Variant = enemy.call(&"get_body")
	return body as CharacterBody2D if is_instance_valid(body) and body is CharacterBody2D else null


static func _state_of(enemy: Node) -> ReactionState:
	return _reactions().call(&"state_of", enemy) as ReactionState


static func _motion_of(enemy: Node) -> EnemyHitMotion:
	return _reactions().call(&"motion_of", enemy) as EnemyHitMotion


## EnemyReactions (loaded here, not preloaded: it preloads this file).
static func _reactions() -> GDScript:
	if _reactions_script == null:
		_reactions_script = load("res://game/combat/reactions/enemy_reactions.gd") as GDScript
	return _reactions_script


static func _number(key: String) -> float:
	var constants := Services.constants()
	return constants.number("%s.%s" % [ROOT, key]) if constants != null else 0.0

extends Node
class_name PlayerCombat
## The player's weapon controller (Phaser `features/combat/CombatController.ts`, player-weapon
## part, + `UniversalSceneWorldController.mountWeapon`). Combat spec 3, 4.2, 9.
## Also the "combat port" the WeaponScript calls (Phaser `PLAYER_WEAPON_COMBAT_SERVICE`).
##
## Created by main.gd as a child Node "PlayerCombat" of the player root:
##   combat = PlayerCombat.new(); player_root.add_child(combat); combat.setup(player_script);
##   player_script.set_combat(combat); combat.equip("basic-sword")
## Pausable (`_physics_process` updates the combo window).
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const Directions := preload("res://game/shared/directions.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const WeaponScript := preload("res://game/scripts/weapon.gd")
const CombatScaling := preload("res://game/combat/combat_scaling.gd")
const ComboCounter := preload("res://game/combat/combo_counter.gd")
const EffectSpawner := preload("res://game/combat/effect_spawner.gd")

## weapon.json `directionalAttacks.*.characterActionId` for the basic sword (not in the scene
## JSON; combat spec 1): the player clip played for every swing direction.
const DEFAULT_CHARACTER_ACTION := "attack-1"
## Particle offset above the struck centre (CombatController.ts:201-235).
const HIT_SPARK_RISE_PX := 12.0


## Game-constants paths (`systems/PlayerStats.ts getStats`).
const STAT_ATTACK := "character.player.stats.attack"
const STAT_CRIT_CHANCE := "character.player.stats.critChance"
const STAT_CRIT_MULTIPLIER := "character.player.stats.critMultiplier"
const INITIAL_ATTRIBUTES := "character.player.initialAttributes"
## CombatController.ts:157: attack stat 10 is neutral (`baseDamage * attack / 10`).
const ATTACK_STAT_BASELINE := 10.0
const IDLE_CLIP := "idle"
const RESOURCE_TAG := "resource"
const CRIT_AUDIO_CUE := &"Crit"
## A weapon without an impact effect (gauntlet, axes, pickaxes) still thuds on a hit; a hit the
## target refuses (Fatty in the air, an immune target) clinks.
const DULL_HIT_CUE := &"HitDull"
const BLOCKED_HIT_CUE := &"HitBlocked"
const BLOCKED_REASONS: Array[String] = ["source-blocked", "state-blocked", "immune"]

var _player: PlayerScript
var _weapon: WeaponScript
var _weapon_root: Node2D
var _combo: ComboCounter = ComboCounter.new()
var _attacking: bool = false
var _critical_attack: bool = false


## Remembers the player script.
func setup(player: PlayerScript) -> void:
	_player = player


## Combat spec 3 (mountWeapon): instance `weapon.<weapon_id>` via WorldService, find its
## WeaponScript (child "WeaponScript"), check `weapon_id`, add the weapon root as the LAST child
## of the player root at local `FeetAnchor.local_phaser_origin(player_root)` (= (0, -27.56)),
## `weapon.bind_combat(self)`, free any previous weapon. Returns false on failure.
## Refused while a swing is in flight (CombatController.equipWeapon).
func equip(weapon_id: String) -> bool:
	if _attacking:
		return false
	var player_root := _player_root()
	if player_root == null:
		push_error("PlayerCombat.equip: setup(player) must run first")
		return false
	var world := Services.world()
	if world == null:
		return false
	var instance := world.instantiate_scene("weapon.%s" % weapon_id)
	if instance == null:
		return false
	var root := instance as Node2D
	var weapon := _find_weapon_script(instance)
	if root == null or weapon == null or weapon.weapon_id != weapon_id:
		push_error("PlayerCombat.equip: weapon.%s has no matching WeaponScript" % weapon_id)
		instance.free()
		return false
	var previous_root := _weapon_root
	var previous := _weapon
	if previous != null and is_instance_valid(previous):
		previous.cancel_attack()
	weapon.bind_combat(self)
	_weapon = weapon
	_weapon_root = root
	root.position = FeetAnchor.local_phaser_origin(player_root)
	player_root.add_child(root)
	root.reset_physics_interpolation()
	if previous_root != null and is_instance_valid(previous_root):
		previous_root.queue_free()
	return true


## Cancels any swing and frees the mounted weapon.
func unequip() -> void:
	if _weapon != null and is_instance_valid(_weapon):
		_weapon.cancel_attack()
	if _weapon_root != null and is_instance_valid(_weapon_root):
		_weapon_root.queue_free()
	_weapon = null
	_weapon_root = null
	_attacking = false
	_critical_attack = false


## The mounted WeaponScript or null.
func get_weapon() -> WeaponScript:
	return _weapon if _weapon != null and is_instance_valid(_weapon) else null


## True between on_attack_started and on_attack_finished.
func is_attacking() -> bool:
	return _attacking


## True when a swing toward `direction` ("right" | "left" | "up" | "down") would reach the hurtbox
## `area` from where the slime stands now (WeaponScript.reaches). A click order walks until it does.
func reaches(direction: String, area: Area2D) -> bool:
	var weapon := get_weapon()
	return weapon != null and weapon.reaches(direction, area)


## `CombatController.tryAttack` (combat spec 4.2): gates (weapon, not attacking, player not
## action-locked / dead, tree not paused, weapon.can_begin_attack()); direction =
## Directions.cardinal_name(player facing); payload {"damage": int, "knockback_strength": float,
## "cooldown_ms": float, "weapon_tags": Array[String], "damage_types": ["physical"]} with
## damage = round(scaled(base_damage * attack / 10, scaling.damage)), crit roll
## (critChance/critMultiplier), knockback = scaled(knock_strength, scaling.knockback),
## cooldown = scaled(cooldown_ms, scaling.cooldown, 1); `weapon.try_begin_attack(dir, payload)`;
## on accept and crit: `Services.feel().play(&"critical-hit")`, remember the crit. The player
## script calls this AFTER facing the pointer.
func try_attack() -> bool:
	var weapon := get_weapon()
	if weapon == null or _attacking or not _can_attack():
		return false
	if not weapon.can_begin_attack():
		return false
	var constants := Services.constants()
	if constants == null:
		return false
	var direction := Directions.cardinal_name(_player.get_facing())
	var attributes := constants.dictionary(INITIAL_ATTRIBUTES)
	var attack := constants.number(STAT_ATTACK)
	var scaled_damage := roundi(CombatScaling.scaled(
		weapon.base_damage * (attack / ATTACK_STAT_BASELINE), _coefs(weapon, "damage"), attributes))
	var critical := randf() < constants.number(STAT_CRIT_CHANCE)
	var damage := roundi(scaled_damage * constants.number(STAT_CRIT_MULTIPLIER)) if critical else scaled_damage
	var weapon_tags: Array[String] = ["spear" if weapon.weapon_id.contains("spear") else "weapon"]
	for tag: Variant in weapon.harvest_capabilities:
		weapon_tags.append("harvest:%s:%s" % [str(tag), _js_number(weapon.harvest_capabilities[tag])])
	var payload := {
		"damage": damage,
		"knockback_strength": CombatScaling.scaled(weapon.knock_strength, _coefs(weapon, "knockback"), attributes),
		"cooldown_ms": CombatScaling.scaled(weapon.cooldown_ms, _coefs(weapon, "cooldown"), attributes, 1.0),
		"weapon_tags": weapon_tags,
		"damage_types": ["physical"],
	}
	var attacked := weapon.try_begin_attack(direction, payload)
	if attacked and critical:
		var feel := Services.feel()
		if feel != null:
			feel.play(&"critical-hit")
	if attacked:
		_critical_attack = critical
	return attacked


## Combo window update (`ComboCounter.update(now)`).
func _physics_process(_delta: float) -> void:
	_combo.update(Services.now_ms())


# --- combat port called by WeaponScript ---------------------------------------------------------

## `onAttackStarted` (CombatController.ts:254-260): attacking, player action-locked, player
## velocity 0, player plays DEFAULT_CHARACTER_ACTION (subject to the knockback priority gate).
func on_attack_started(weapon_id: String, _direction: String) -> void:
	var weapon := get_weapon()
	if weapon == null or weapon.weapon_id != weapon_id:
		return
	_attacking = true
	if _player_valid():
		_player.set_action_locked(true)
		_player.stop_movement()
		_player.play_animation(DEFAULT_CHARACTER_ACTION)


## `onAttackFinished` (CombatController.ts:262-267): not attacking, player unlocked, player
## plays "idle" (dropped while knockback has priority).
func on_attack_finished(weapon_id: String, _direction: String) -> void:
	var weapon := get_weapon()
	if weapon == null or weapon.weapon_id != weapon_id:
		return
	_attacking = false
	if _player_valid():
		_player.set_action_locked(false)
		_player.play_animation(IDLE_CLIP)


## `transformManagedWeaponDamage` (combat spec 6.3): `max(0, round(damage *
## modifier(target tags) * combo.register_hit(now).multiplier))`; damage_modifiers: first target
## tag with an entry wins, else 1. A combo finisher plays `Services.feel().play(&"combo-finisher")`.
## Called once per routed target, before routing.
func transform_damage(damage: float, target: Dictionary) -> int:
	var modifier := _damage_modifier(target.get("tags", []))
	var combo := _combo.register_hit(Services.now_ms())
	if bool(combo["finisher"]):
		var feel := Services.feel()
		if feel != null:
			feel.play(&"combo-finisher")
	return maxi(0, roundi(damage * modifier * float(combo["multiplier"])))


## `onManagedWeaponOutcome` (combat spec 9): rejected -> the HitBlocked clink for a refused hit
## (BLOCKED_REASONS; Phaser was silent); actual > 0 -> crit sting once
## (audio cue "Crit"), `feel().play(&"hit")`, particles "hit-spark" at target centre - (0, 12),
## impact effect `on_hit_effect_id` via EffectSpawner in front of the target (none: the HitDull cue).
## `target` = {"area": Area2D, "receiver": Object, "position": Vector2 (target centre =
## area.global_position), "attack_direction": String, "tags": Array[String]}.
func on_outcome(outcome: Dictionary, target: Dictionary) -> void:
	var tags: Array = target.get("tags", [])
	if outcome.get("status", "") != "accepted":
		var feel_rejected := Services.feel()
		if feel_rejected != null and not tags.has(RESOURCE_TAG) and BLOCKED_REASONS.has(str(outcome.get("reason", ""))):
			feel_rejected.audio_cue(BLOCKED_HIT_CUE)
		return
	if tags.has(RESOURCE_TAG):
		return
	var actual := int(outcome.get("actual_damage", 0))
	var feel := Services.feel()
	if _critical_attack and actual > 0:
		# One crit sting per swing, however many creatures it hits.
		_critical_attack = false
		if feel != null:
			feel.audio_cue(CRIT_AUDIO_CUE, {})
	if actual <= 0:
		return
	var centre: Vector2 = target.get("position", Vector2.ZERO)
	if feel != null:
		feel.play(&"hit")
		feel.particles(&"hit-spark", centre - Vector2(0.0, HIT_SPARK_RISE_PX))
	var weapon := get_weapon()
	if weapon == null or weapon.on_hit_effect_id.is_empty():
		if feel != null:
			feel.audio_cue(DULL_HIT_CUE)
		return
	var direction := str(target.get("attack_direction", Directions.RIGHT))
	var effect := EffectSpawner.spawn_in_front(weapon.on_hit_effect_id, direction, centre, _target_feet(target, centre))
	if effect == null:
		push_warning("PlayerCombat: effect.%s could not be spawned" % weapon.on_hit_effect_id)


## The player's receiver object (the PlayerScript), so the weapon never hits its wielder.
func wielder_receiver() -> Object:
	return _player


# --- private -----------------------------------------------------------------------------------

## `canAttack()` = not action-locked, not paused, not dead (WorldScene.ts:2243).
func _can_attack() -> bool:
	if not _player_valid() or not is_inside_tree():
		return false
	return not _player.is_action_locked() and not get_tree().paused and not _player.is_dead()


func _player_valid() -> bool:
	return _player != null and is_instance_valid(_player)


## The player CharacterBody2D root (the PlayerScript's `body`, else its parent).
func _player_root() -> Node2D:
	if not _player_valid():
		return null
	if _player.body != null and is_instance_valid(_player.body):
		return _player.body
	return _player.get_parent() as Node2D


func _find_weapon_script(root: Node) -> WeaponScript:
	var direct := root.get_node_or_null(^"WeaponScript")
	if direct is WeaponScript:
		return direct as WeaponScript
	for node in root.find_children("*", "Node", true, false):
		if node is WeaponScript:
			return node as WeaponScript
	return null


## `weapon.scaling[kind]` as a coefficient Dictionary ({} when absent).
static func _coefs(weapon: WeaponScript, kind: String) -> Dictionary:
	var value: Variant = weapon.scaling.get(kind, {})
	return value if value is Dictionary else {}


## `resolveDamageModifier` (combat/DamageModifiers.ts): first target tag (in the target's order)
## with an entry in `damage_modifiers` wins, else 1.
func _damage_modifier(target_tags: Variant) -> float:
	var weapon := get_weapon()
	if weapon == null or weapon.damage_modifiers.is_empty() or not (target_tags is Array):
		return 1.0
	for tag: Variant in target_tags:
		for entry: Variant in weapon.damage_modifiers:
			if entry is Dictionary and str((entry as Dictionary).get("targetTag", "")) == str(tag):
				return float((entry as Dictionary).get("modifier", 1.0))
	return 1.0


## Feet of the struck target for the impact-effect holder (combat spec F8): the receiver's
## `body` root when it has one, else the hurtbox centre.
static func _target_feet(target: Dictionary, centre: Vector2) -> Vector2:
	var receiver: Variant = target.get("receiver", null)
	if receiver is Object and is_instance_valid(receiver):
		var body: Variant = (receiver as Object).get("body")
		if body is Node2D and is_instance_valid(body):
			return (body as Node2D).global_position
	return centre


## JS template-literal number formatting for harvest tags (1.0 -> "1").
static func _js_number(value: Variant) -> String:
	if value is float and is_finite(value) and float(value) == floorf(value):
		return str(int(value))
	return str(value)

extends Node
class_name TrainingDummyScript
## Scene script `game.training-dummy` (Phaser `features/scripts/TrainingDummyScript.ts`;
## abilities spec 13.6). A straw dummy for trying attacks: every hit shows its damage (orange, big,
## 96 px above the root) and wobbles the sprite away from the blow, fading out in about 0.9 s. It
## never breaks and never fights back; the attacker's usual hit feedback applies.
## Body-shapes rework (docs/godot/BODY_SHAPES.md; combat-feel plan section 5, "Training dummy:
## switchable preset"): a dummy answers rework hits (requests with a top-level `hit`) through
## EnemyReactions with the profile of its `reaction_preset` (the shapes testbed's: light, medium,
## heavy, boss; ReactionProfile.for_preset) under its own `reaction_overrides`, and so shows what each
## weight does to every hit: the hold count and break-free, the wake guard, armor and poise breaks,
## with the hit motion (nudge, squash, tumble, wobble, daze stars, the break-free outline) in place
## of its own wobble. It never attacks, never falls and never drops an energy shard. A scene dummy
## (a StaticBody2D root, `body` null) has no body or stun, so nothing moves it. The shapes testbed's
## dummies have a CharacterBody2D root (`body`): in the rework mode they take the stun and the push of
## each reaction (knockback, launch, the break-free move), slide with `EnemyReactions.slide_decay`
## through ArcadeMover, splat on walls and bowl other bodies (`EnemyReactions.after_move`), and once
## the stun is over walk back to where they stood at `return_speed`. Their number and their hit sound
## are the attacker's feel (`GameFeel.play_hit`, which follows the Damage numbers setting); the dummy's
## own number and DummyHit cue are for old hits only. Old hits are unchanged.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")

const RULE := {"priority": 0, "damageMultiplier": 1}
const TEXT_RISE := 96.0
const CUE_HIT := &"DummyHit"
## Wobble: 0.22 rad decaying by e^(-4.5 t), cos(6 pi t); stops under 0.004 rad.
const WOBBLE_AMPLITUDE := 0.22
const WOBBLE_DECAY := 4.5
const WOBBLE_RATE := 9.0 * TAU / 3.0
const WOBBLE_END := 0.004

## JSON `damageArea`: the hurtbox Area2D.
@export var damage_area: Area2D
## JSON `visual`: the dummy Sprite2D (optional).
@export var visual: Sprite2D
## Rework: the weight whose default reactions this dummy shows (`combat.weights`: light, medium,
## heavy, boss); "" = it answers rework hits with no reaction profile of its own (medium's).
@export var reaction_preset: String = ""
## Rework: reaction profile keys this dummy changes on top of its preset's (for tuning: e.g.
## {"holdCap": 3} or {"poise": 6}; ReactionProfile.for_enemy).
@export var reaction_overrides: Dictionary = {}
## Rework: the CharacterBody2D root the reactions move (the shapes testbed's dummies); null = the
## scene's static dummy, which nothing moves.
@export var body: CharacterBody2D
## Rework: how fast a moved dummy walks back to where it stood once its stun is over (px/s).
@export var return_speed: float = 0.0

## A hit landed. Payload: {"damage": float}.
signal hit(payload: Dictionary)

var hits: int = 0
var _wobble_age: float = -1.0
var _side: float = 1.0
var _registered: Area2D
## Rework (a dummy with a body): its reaction stun's end (simulation ms) and the spot it walks back
## to (its first position; INF until the first physics step).
var _hit_stun_until: float = 0.0
var _post: Vector2 = Vector2.INF


func _ready() -> void:
	var router := Services.router()
	if damage_area != null and router != null:
		router.register_area(damage_area, self, RULE, [])
		_registered = damage_area


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func get_damage_state() -> Dictionary:
	return {"hp": 9999.0, "max_hp": 9999.0, "dead": false}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	return {"accepted": true}


func commit_damage(commit: Dictionary) -> void:
	var result: Dictionary = commit.get("result", {})
	var actual := float(result.get("actual_damage", 0.0))
	hits += 1
	var request: Dictionary = commit.get("request", {})
	var rework := ReworkMode.is_rework_request(request)
	# A rework hit's motion is the reaction's (EnemyHitMotion), not the dummy's own wobble.
	if rework and _wobble_age >= 0.0 and visual != null:
		visual.rotation = 0.0
	_wobble_age = -1.0 if rework else 0.0
	var impact: Dictionary = request.get("impact", {})
	var knock: Vector2 = impact.get("knock", Vector2.RIGHT)
	_side = -1.0 if knock.x < 0.0 else 1.0
	var root := get_parent() as Node2D
	var feel := Services.feel()
	# A rework hit's sound is the attacker's swing feel (one per swing), not the dummy's own.
	if feel != null and not rework:
		feel.audio_cue(CUE_HIT)
	if feel != null and root != null and not rework:
		feel.floating_text(root.global_position - Vector2(0.0, TEXT_RISE), str(roundi(actual)), &"orange", true)
	hit.emit({"damage": actual})
	if rework:
		EnemyReactions.react(self, commit, false)


## Rework (EnemyReactions): the dummy's sprite.
func get_visual() -> Sprite2D:
	return visual


## Rework (EnemyReactions): where hits land on the dummy: its hurtbox shape's centre (the
## DamageShape sits 46 px above the root, at the straw body; else the hurtbox, else its root).
func get_centre() -> Vector2:
	if damage_area != null and damage_area.is_inside_tree():
		for child: Node in damage_area.get_children():
			var shape := child as CollisionShape2D
			if shape != null and not shape.disabled:
				return shape.global_position
		return damage_area.global_position
	var root := get_parent() as Node2D
	return root.global_position if root != null else Vector2.ZERO


## Rework (EnemyReactions): a dummy never falls.
func is_defeated() -> bool:
	return false


## Rework (EnemyReactions): the body the reactions move (null for the scene's static dummy).
func get_body() -> CharacterBody2D:
	return body if body != null and is_instance_valid(body) else null


## Rework (EnemyReactions): the reaction stun (a moved dummy slides while it lasts).
func set_hit_stun_until(until_ms: float) -> void:
	_hit_stun_until = until_ms


func get_hit_stun_until() -> float:
	return _hit_stun_until


## Rework, a dummy with a body only: while stunned it slides (the reaction's velocity decaying by
## `EnemyReactions.slide_decay` per 60 Hz step), else it walks back to its post at `return_speed`;
## ArcadeMover moves it, then the wall splat and bowling (`EnemyReactions.after_move`).
func _physics_process(delta: float) -> void:
	if body == null or not is_instance_valid(body) or not ReworkMode.is_on():
		return
	if _post == Vector2.INF:
		_post = body.global_position
	if Services.now_ms() < _hit_stun_until:
		body.velocity *= pow(EnemyReactions.slide_decay(), delta * 60.0)
	else:
		body.velocity = ((_post - body.global_position) / maxf(delta, 0.0001)).limit_length(return_speed)
	ArcadeMover.move(body, delta)
	EnemyReactions.after_move(self, delta)


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


func _process(delta: float) -> void:
	if _wobble_age < 0.0 or visual == null:
		return
	_wobble_age += delta
	var amplitude := WOBBLE_AMPLITUDE * exp(-WOBBLE_DECAY * _wobble_age)
	var lean := 0.0 if amplitude < WOBBLE_END else _side * amplitude * cos(_wobble_age * WOBBLE_RATE)
	visual.rotation = lean
	if lean == 0.0:
		_wobble_age = -1.0

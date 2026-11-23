extends RefCounted
class_name CampTerritory
## Camp territory layer for enemies spawned from an enemy-spawn area or placed with a wander area
## (game/enemy/placed_enemy.gd: the wander area is the home) (Phaser
## `enemies/ai/Territory.ts:42-169`). Enemy spec 4.3. Pure logic; all points are old Phaser
## centres (FeetAnchor). Two things are not Phaser's (owner, 2026-11-21; enemy spec 4.3 "Getting
## home"): an enemy walking home turns round on sight too (`reengage_margin`), and one that cannot
## get home settles where it stands (`settle`).
##
## Owner: enemy builder.

const Perimeter := preload("res://game/shared/perimeter.gd")

## Territory.ts literals.
const MIN_LEASH := 520.0
const SEARCH_MS := 3000.0
const LOSE_SIGHT_MULTIPLIER := 1.5
const RETURN_SPEED_MULTIPLIER := 1.3
const REGEN_PER_SECOND_RATIO := 0.35
const ARRIVED_DISTANCE := 18.0

const MODE_HOME := "home"
const MODE_ENGAGED := "engaged"
const MODE_SEARCHING := "searching"
const MODE_RETURNING := "returning"

var mode: String = MODE_HOME
## Last seen player centre (Vector2) or null.
var last_seen: Variant = null
var search_until: float = 0.0
## Stay perimeter (Perimeter dictionary).
var home: Dictionary = {}
var aggro: float = 0.0
var attack_reach: float = 0.0
## `attributes.leashRange` when set, else max(MIN_LEASH, aggro * 2) (worm: 520).
var leash: float = MIN_LEASH
## How far inside its leash the slime must be for an enemy walking home to turn round on sight alone
## (game-constants.json `combat.wayAround.reengageMarginPx`, set by enemy.gd; the margin keeps it
## from flickering between the chase and the walk home at the leash's edge).
var reengage_margin: float = 0.0


## Stores the stay perimeter, aggro (targeting_radius), attack reach (attack_range) and the leash
## (`leash_range` < 0 means absent).
func setup(home_perimeter: Dictionary, aggro_range: float, attack_range: float, leash_range: float = -1.0) -> void:
	home = home_perimeter
	aggro = aggro_range
	attack_reach = attack_range
	# territoryRulesFor: `leashRange ?? max(520, aggro * 2)`.
	leash = leash_range if leash_range >= 0.0 else maxf(MIN_LEASH, aggro_range * 2.0)
	mode = MODE_HOME
	last_seen = null
	search_until = 0.0


## One decision (enemy spec 4.3 table, first match per mode). Inputs: `now_ms`, enemy centre,
## `has_player`, player centre, `sees_player` (sight check), `distance` (centre to centre),
## `hurt` (hit since the last step). Returns:
## {"mode": String, "move_to": Vector2 or null, "hold": bool, "may_engage": bool,
##  "regenerate": bool, "restore_health": bool}.
func step(now_ms: float, enemy_centre: Vector2, has_player: bool, player_centre: Vector2,
		sees_player: bool, distance: float, hurt: bool) -> Dictionary:
	var from_home := Perimeter.distance_outside(home, enemy_centre)
	var player_distance := distance if has_player else INF
	var reachable := has_player and _within_leash(from_home, player_distance)
	var in_sight := has_player and sees_player and player_distance <= aggro

	match mode:
		MODE_HOME:
			if (in_sight or hurt) and reachable:
				return _engage(has_player, player_centre)
			# Knocked or wandered out of its area: walk back in.
			if from_home > ARRIVED_DISTANCE:
				return _go_home()
			return _decision(MODE_HOME)
		MODE_ENGAGED:
			if not has_player or not reachable:
				return _go_home()
			var lost := not sees_player or player_distance > aggro * LOSE_SIGHT_MULTIPLIER
			if lost and not hurt:
				return _search(now_ms, enemy_centre)
			return _engage(has_player, player_centre)
		MODE_SEARCHING:
			if (in_sight or hurt) and reachable:
				return _engage(has_player, player_centre)
			if now_ms >= search_until:
				return _go_home()
			return _search(now_ms, enemy_centre)
		MODE_RETURNING:
			# A hit from within its leash turns it around, and so does the slime in plain sight well
			# inside its leash (owner, 2026-11-21: an enemy on its way home must never be left unable
			# to notice and attack; Phaser's turned round on a hit only, so one held up on the way
			# looked dead).
			if reachable and (hurt or (in_sight and _within_leash(from_home + reengage_margin, player_distance))):
				return _engage(has_player, player_centre)
			if from_home <= 0.0:
				mode = MODE_HOME
				last_seen = null
				var arrived := _decision(MODE_HOME)
				arrived["regenerate"] = true
				arrived["restore_health"] = true
				return arrived
			return _go_home()
	push_error("CampTerritory: unknown mode '%s'" % mode)
	mode = MODE_HOME
	return _decision(MODE_HOME)


## It cannot get home (enemy.gd: WayAround gave the walk up): it lives where it stands from now on.
## Its home becomes a circle of `radius` around `centre` (its old centre now) and it is at home.
func settle(centre: Vector2, radius: float) -> void:
	home = {"shape": Perimeter.SHAPE_CIRCLE, "x": centre.x, "y": centre.y, "radius": maxf(1.0, radius)}
	mode = MODE_HOME
	last_seen = null


## Walking speed while returning/searching: movement_speed * RETURN_SPEED_MULTIPLIER.
static func return_speed(movement_speed: float) -> float:
	return movement_speed * RETURN_SPEED_MULTIPLIER


func _within_leash(from_home: float, distance_to_player: float) -> bool:
	return from_home + maxf(0.0, distance_to_player - attack_reach) <= leash


func _engage(has_player: bool, player_centre: Vector2) -> Dictionary:
	mode = MODE_ENGAGED
	if has_player:
		last_seen = player_centre
	var decision := _decision(MODE_ENGAGED)
	decision["may_engage"] = true
	return decision


func _go_home() -> Dictionary:
	mode = MODE_RETURNING
	var decision := _decision(MODE_RETURNING)
	decision["move_to"] = Perimeter.centre(home)
	decision["regenerate"] = true
	return decision


func _search(now_ms: float, enemy_centre: Vector2) -> Dictionary:
	if mode != MODE_SEARCHING:
		search_until = now_ms + SEARCH_MS
	mode = MODE_SEARCHING
	var decision := _decision(MODE_SEARCHING)
	if last_seen is Vector2:
		var spot: Vector2 = last_seen
		if spot.distance_to(enemy_centre) > ARRIVED_DISTANCE and Perimeter.distance_outside(home, spot) <= leash:
			decision["move_to"] = spot
			return decision
	decision["hold"] = true
	return decision


static func _decision(decision_mode: String) -> Dictionary:
	return {"mode": decision_mode, "move_to": null, "hold": false, "may_engage": false,
		"regenerate": false, "restore_health": false}

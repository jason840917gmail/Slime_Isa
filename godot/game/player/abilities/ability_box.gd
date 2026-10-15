extends RefCounted
## The Ability Box (body-shapes plan section 6 "The box"; BODY_SHAPES.md "Ability Box and HUD"):
## Zelda's item screen. Squash Slam and every later gadget sit in sockets in a fixed order
## (`abilityBox.sockets` in game-constants.json); the box shows only the learned ones; the chosen one
## is used with `ability_use` (F; S in keys-only). It lives in the bag window's top band (B; a click
## on the HUD's Ability slot opens it too), beside the Shapes row; no key of its own.
##
## - **The choice** is saved with the run: `RunState.player.loadout.ability_id` (the plan's
##   `loadout`, section 10 "Saves"; other loadout keys are left alone). Without a run it lives for
##   the session. A choice that is no longer learned falls back to the first learned socket.
## - **A newly learned box ability is chosen by itself** (`on_learned`; the HUD's ability bar calls it
##   on `RunState.ability_learned`, which quiet grants such as the rework's playground kit skip).
## - **Use** (`use`, an `ability_use` press; player.gd, rework mode only): the chosen ability through
##   `PlayerScript.use_ability`, with its usual refusals (`PlayerAbilities.try_begin`: "Not learned
##   yet", "Low energy", the AbilityDenied cue). With an empty box the press is refused the same way
##   ("Not learned yet").
## - **Numbers** the box shows (the card, the HUD chip, the cooldown sweep) are the ones the ability
##   spends: `AbilityDefinitions.energy_cost` and `cooldown_ms`.
## - **Keys**: in the rework mode a box ability has no key of its own (its old number key is gone,
##   game/shapes/rework_input.gd); texts that name its key ask `key_action(id)`, which is
##   `ability_use` for a socket in the mode (and `eat` for Swallow, a Q hold there) and the
##   ability's own action otherwise.
##
## Owner: Ability Box and HUD.

const Services := preload("res://game/shared/services.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")

## The input action that uses the chosen box ability (F; S in keys-only).
const USE_ACTION := &"ability_use"
## The action that swallows in the rework mode (Q held with an essence in the mouth).
const SWALLOW_ACTION := &"eat"
const SOCKETS_PATH := "abilityBox.sockets"
## Where the choice is kept in `RunState.player`: {"loadout": {"ability_id": String}}.
const LOADOUT_KEY := "loadout"
const ABILITY_KEY := "ability_id"
## PlayerAbilities' refusal reason for an ability that is not learned ("Not learned yet").
const REFUSAL_EMPTY := "locked"

## The choice while there is no run (an editor scene played alone).
static var _session_choice: StringName = &""
## How many box abilities `use` has started this session (the control hints learn from it).
static var _use_count: int = 0


## Every socket id in box order (learned or not).
static func socket_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var constants := Services.constants()
	var raw: Variant = constants.value(SOCKETS_PATH, []) if constants != null else []
	if raw is Array:
		for id: Variant in raw:
			ids.append(StringName(str(id)))
	return ids


## The box abilities `player` has learned (RunState's when `player` is null), in box order; only
## the ones AbilityDefinitions knows (a socket without an ability yet stays hidden).
static func box_ids(player: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in socket_ids():
		if AbilityDefinitions.has(id) and _is_learned(player, id):
			ids.append(id)
	return ids


## The chosen box ability: the one chosen if still learned, else the first learned, else &"".
static func selected(player: Node) -> StringName:
	var ids := box_ids(player)
	var chosen := _stored()
	if ids.has(chosen):
		return chosen
	return ids[0] if not ids.is_empty() else &""


## Chooses `id` (a learned box ability only) and saves the choice with the run. False when refused.
static func select(player: Node, id: StringName) -> bool:
	if not box_ids(player).has(id):
		return false
	_store(id)
	return true


## A box ability was just learned (not quietly): it becomes the choice. False for anything else.
static func on_learned(player: Node, id: StringName) -> bool:
	if not socket_ids().has(id):
		return false
	return select(player, id)


## Uses the chosen ability (an `ability_use` press). True when it started; a refusal plays the
## ability's usual feedback.
static func use(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var id := selected(player)
	if id.is_empty():
		_refuse_empty(player)
		return false
	var started := bool(player.call(&"use_ability", id))
	if started:
		_use_count += 1
	return started


## How many box abilities `use` has started this session (it only grows).
static func use_count() -> int:
	return _use_count


## The action whose key a text should name for ability `id`: while the rework mode is on,
## `ability_use` for a box socket and `eat` for Swallow (a Q hold, body-shapes plan section 5); else
## the ability's own action (AbilityDefinitions.action).
static func key_action(id: StringName) -> StringName:
	if ReworkMode.is_on() and socket_ids().has(id):
		return USE_ACTION
	if ReworkMode.is_on() and id == AbilityDefinitions.SWALLOW:
		return SWALLOW_ACTION
	return AbilityDefinitions.action(id)


## The energy `id` spends (what the box card and the HUD chip show).
static func energy_cost(id: StringName) -> float:
	return AbilityDefinitions.energy_cost(id)


## The cooldown of `id` in ms, from the press.
static func cooldown_ms(id: StringName) -> float:
	return AbilityDefinitions.cooldown_ms(id, Services.constants())


static func _is_learned(player: Node, id: StringName) -> bool:
	if player != null and is_instance_valid(player) and player.has_method(&"is_learned"):
		return bool(player.call(&"is_learned", id))
	var run := Services.run()
	return run != null and run.has_learned_ability(String(id))


## The saved choice (&"" when none).
static func _stored() -> StringName:
	var run := Services.run()
	if run == null:
		return _session_choice
	var loadout: Variant = run.player.get(LOADOUT_KEY)
	if loadout is Dictionary:
		return StringName(str((loadout as Dictionary).get(ABILITY_KEY, "")))
	return &""


static func _store(id: StringName) -> void:
	var run := Services.run()
	if run == null:
		_session_choice = id
		return
	if not run.player.get(LOADOUT_KEY) is Dictionary:
		run.player[LOADOUT_KEY] = {}
	var loadout: Dictionary = run.player[LOADOUT_KEY]
	if str(loadout.get(ABILITY_KEY, "")) == String(id):
		return
	loadout[ABILITY_KEY] = String(id)
	run.schedule_autosave()


## An `ability_use` press with an empty box: the abilities' usual refusal ("Not learned yet").
static func _refuse_empty(player: Node) -> void:
	var abilities: Variant = player.call(&"get_abilities") if player.has_method(&"get_abilities") else null
	if abilities is Object and (abilities as Object).has_method(&"notify_rejected"):
		(abilities as Object).call(&"notify_rejected", &"", REFUSAL_EMPTY)

extends RefCounted
## The first weapon daze of a run (one combat, 2026-11-25; the plan's piece 3: a combo sets up the
## throw; docs/godot/THROW_COMBAT.md "Enemies as ammo"): the Gulp's hint, the hint line over the slime
## ("Dazed! Press Q to suck it up, then Q to throw it", the Gulp's key read from the bindings) and a
## pointer that flashes the dazed enemy (game/feel/hint_cue.gd, docs/GAME_GUIDELINES.md "Hints"), riding
## on its body. Once a run (story flag `hint.weapon-daze`, saved with the run). EnemyReactions calls
## `on_daze` when a weapon's daze begins.
##
## Owner: throw combat.

const Services := preload("res://game/shared/services.gd")
const HintCue := preload("res://game/feel/hint_cue.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const FLAG := "hint.weapon-daze"
const TEXT := "Dazed! %s to suck it up, then %s to throw it"
## The line's lift over the slime, how long it and the pointer last, the pointer's flashes and how high
## its arrow stands over the enemy's middle (presentation).
const LIFT_PX := 96.0
const HINT_MS := 6000.0
const FLASHES := 3
const ARROW_RISE_PX := 56.0
const CUE_NAME := "WeaponDazeHint"


## A weapon's daze began on `enemy`: the hint, the first time in the run. True when it showed.
static func on_daze(enemy: Node) -> bool:
	var run := Services.run()
	if run == null or enemy == null or not is_instance_valid(enemy) or run.has_flag(FLAG):
		return false
	run.set_flag(FLAG)
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var feel := Services.feel()
	if feel != null and player != null:
		var eat := ControlLabels.control_label(&"eat")
		feel.hint_text(player, LIFT_PX, TEXT % [ControlLabels.control_verb(&"eat"), eat], &"orange", HINT_MS)
	var body: Variant = enemy.call(&"get_body") if enemy.has_method(&"get_body") else enemy
	if not body is Node2D:
		return true
	var cue := HintCue.new()
	cue.name = CUE_NAME
	cue.set(&"flashes", FLASHES)
	cue.set(&"life_ms", HINT_MS)
	cue.set(&"arrow_rise", ARROW_RISE_PX)
	(body as Node2D).add_child(cue)
	var centre: Variant = enemy.call(&"get_centre") if enemy.has_method(&"get_centre") else null
	cue.global_position = centre if centre is Vector2 else (body as Node2D).global_position
	return true

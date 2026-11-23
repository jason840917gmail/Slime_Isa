extends "res://game/scripts/silk_parcel.gd"
## A forest critter wrapped in silk (Gloop Forest's River Roads, 2026-11-21;
## docs/design/2026-11-21-gloop-river-roads.md "Critters in silk"; the ideas board's Okami animals
## and lost Cuccos): a silk parcel (silk_parcel.gd: the Silk skin and a Spear hit free it, without
## the skin a hit clinks; its story flag `flag_id` keeps it torn open) with a small animal inside.
## It wriggles now and then (the parcel's shiver, every `wriggle_every_ms`), so it reads as alive
## from the first visit, before the Silk skin.
##
## Freed, the animal (`critter`: one of the town animals' scenes, game/scenes/objects/animals/) pops
## out and scampers off along `run_toward` (home, toward Mossy's camp), fading as it goes. Only its
## picture runs (its Visual, Shadow and clips on a plain node, real time: presentation, no body
## moves); at the camp a FreedCritter (freed_critter.gd) with the same flag shows it, wandering,
## from then on. Sunny gives a prize once all five are home (npc-definitions.json, her talks).
##
## Owner: webs (the Gloop Forest).

const RUN_PX := 300.0
const RUN_MS := 1500.0
const FADE_MS := 500.0
## The pop out of the torn silk: up and back down.
const POP_PX := 22.0
const POP_MS := 280.0
## A bird flies off: it rises this far as it goes.
const FLY_RISE_PX := 90.0
const FREED_LINE := "It scampers off home!"
const FREED_LINE_RISE := 76.0

## The animal inside (a town animal's scene).
@export var critter: PackedScene
## The way it runs once freed (home: toward the camp).
@export var run_toward: Vector2 = Vector2.LEFT
## It wriggles every so often (ms, real time: a random wait between the two).
@export var wriggle_every_ms: Vector2 = Vector2(1800.0, 4200.0)

var _next_wriggle_ms := 0.0


func _ready() -> void:
	super()
	if Engine.is_editor_hint() or _open:
		return
	_plan_wriggle(float(Time.get_ticks_msec()))
	set_process(true)


func _process(delta: float) -> void:
	super(delta)
	if _open or Engine.is_editor_hint():
		return
	var now := float(Time.get_ticks_msec())
	if now >= _next_wriggle_ms:
		# Two shivers' worth: a wriggle, not a clink.
		_shiver_until_ms = now + SHIVER_MS * 2.0
		_plan_wriggle(now)
		queue_redraw()


func _plan_wriggle(now: float) -> void:
	_next_wriggle_ms = now + randf_range(wriggle_every_ms.x, maxf(wriggle_every_ms.x, wriggle_every_ms.y))


func free_parcel() -> void:
	if _open:
		return
	super()
	_release_critter()


## The animal's picture pops out of the silk and runs off along `run_toward`, fading.
func _release_critter() -> void:
	if critter == null or get_parent() == null:
		return
	var animal := critter.instantiate()
	var runner := Node2D.new()
	runner.name = "FreedCritter"
	runner.y_sort_enabled = true
	for part_name: String in ["Shadow", "Visual", "Animation"]:
		var part := animal.get_node_or_null(part_name)
		if part != null:
			part.owner = null
			animal.remove_child(part)
			runner.add_child(part)
	animal.free()
	runner.position = position + KEY_DROP * 0.5
	get_parent().add_child(runner)
	var visual := runner.get_node_or_null(^"Visual") as Node2D
	var player := runner.get_node_or_null(^"Animation") as AnimationPlayer
	var way := run_toward.normalized() if run_toward.length() > 0.01 else Vector2.LEFT
	var side := "right" if way.x >= 0.0 else "left"
	var flies := player != null and player.has_animation("fly-" + side)
	if player != null:
		var clip := ("fly-" if flies else "walk-") + side
		if player.has_animation(clip):
			player.play(clip)
	var tween := runner.create_tween()
	if visual != null:
		var rest := visual.position
		tween.tween_property(visual, "position", rest - Vector2(0.0, POP_PX), POP_MS * 0.5 / 1000.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "position", rest, POP_MS * 0.5 / 1000.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if flies:
			tween.tween_property(visual, "position", rest - Vector2(0.0, FLY_RISE_PX), RUN_MS / 1000.0)
	var run := tween.parallel() if flies else tween
	run.tween_property(runner, "position", runner.position + way * RUN_PX, RUN_MS / 1000.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(runner, "modulate:a", 0.0, FADE_MS / 1000.0) \
		.set_delay((RUN_MS - FADE_MS) / 1000.0)
	tween.tween_callback(runner.queue_free)
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, FREED_LINE_RISE), FREED_LINE, &"yellow", false)

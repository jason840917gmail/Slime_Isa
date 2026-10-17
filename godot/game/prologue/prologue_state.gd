extends RefCounted
## The prologue's place in the run (roadmap 5.18 to 5.24; docs/design/2026-10-16-prologue.md;
## docs/godot/PROLOGUE.md): a few minutes from the slime's birth at the Wellspring to its first shape,
## the Spear, and out through the barred gate into Slimeshire, where Elder Plop meets it.
##
## Its state is the run's story flags (RunState `story.world_flags`), so it needs no record of its own:
## - `prologue.started`: a new game began it (the title's New Game, the `prologue` launch option);
## - one flag per beat as it is played: `prologue.born` (the birth scene is over: the HUD shows),
##   `prologue.path-cleared`, `prologue.fight-seen`, `prologue.rescued`, `prologue.spear`,
##   `prologue.gate-open`;
## - `prologue.done`: Plop met the slime at the town's edge; the main game goes on.
## The prologue **runs** from `prologue.started` until `prologue.done`. A run that never started it (a
## save made before the prologue was built, a launch option, the test runner's runs) never runs it,
## and its places stand as they are after it: the path open, the gate open, no actors.
##
## While it runs nothing is saved (question 113): RunState refuses every save and the autosave
## (`RunState.can_save`, `saving_blocked_reason`), so quitting, closing the window or a crash leaves
## no save of it, and the next start plays it again from the birth (question 118's proposal). The
## title's New Game removes the old autosave the player agreed to replace, so Continue cannot bring
## back the run before it.
##
## Owner: prologue.

## Story flags (`RunState.set_flag` / `has_flag`).
const STARTED := "prologue.started"
const BORN := "prologue.born"
const PATH_CLEARED := "prologue.path-cleared"
const FIGHT_SEEN := "prologue.fight-seen"
const RESCUED := "prologue.rescued"
const SPEAR := "prologue.spear"
const GATE_OPEN := "prologue.gate-open"
const DONE := "prologue.done"
## Every beat flag in play order (the tests walk them).
const BEATS: Array[String] = [BORN, PATH_CLEARED, FIGHT_SEEN, RESCUED, SPEAR, GATE_OPEN, DONE]

## Where a new game starts: the Wellspring's chunk and the birth spot's marker in it.
const START_MAP_ID := "west-village-b4"
const BIRTH_MARKER := "prologue-birth"
## Where the slime comes out into Slimeshire (level-1-c4's west edge) and Plop meets it.
const TOWN_MAP_ID := "level-1-c4"
## The reason RunState gives for refusing a save.
const NO_SAVE_REASON := "prologue"
## The slime is born with nothing, not even a bag (roadmap 5.7): no bag slots until Plop gives his.
const BAG_SLOTS_AT_BIRTH := 0


## True while the run plays the prologue (started, not done).
static func is_running(run: Object) -> bool:
	return run != null and bool(run.call(&"has_flag", STARTED)) and not bool(run.call(&"has_flag", DONE))


## True when the run has played beat `flag` (one of BEATS).
static func has_beat(run: Object, flag: String) -> bool:
	return run != null and bool(run.call(&"has_flag", flag))


## Marks beat `flag` played. False when it already was.
static func mark(run: Object, flag: String) -> bool:
	return run != null and bool(run.call(&"set_flag", flag))


## Starts the prologue on `run`, a fresh run (`RunState.new_run` just ran): the flag, no bag yet, and
## the first world build goes to the birth spot. The old autosave goes when `drop_autosave` (the title,
## where the player agreed to replace it).
static func begin(run: Object, drop_autosave: bool = false) -> void:
	if run == null:
		return
	run.call(&"set_flag", STARTED)
	var inventory: Dictionary = run.get(&"inventory")
	inventory["max_slots"] = BAG_SLOTS_AT_BIRTH
	# The newborn has been nowhere yet (a new run counts level-1 as discovered): Slimeshire's quests,
	# which wait for level-1, begin when it comes out of the forest there.
	var world: Dictionary = run.get(&"world")
	world["discovered_areas"] = []
	if drop_autosave and bool(run.call(&"has_save", 0)):
		run.call(&"delete_slot", 0)
	run.call(&"request_navigation", "area", START_MAP_ID, "", "", false, BIRTH_MARKER)


## Ends the prologue (Plop met the slime): saving works again.
static func finish(run: Object) -> void:
	if run != null:
		run.call(&"set_flag", DONE)

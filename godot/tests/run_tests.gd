extends SceneTree
## Headless integration tests for the Godot port (Phase 0 trial: level-1, player slime, worm
## swordsman, basic sword).
##
## Run from the repository root:
##   "<Godot 4.7.2 console exe>" --headless --path godot -s res://tests/run_tests.gd
##   pnpm test:godot          (scripts/godot/run-tests.mjs; finds Godot through $GODOT)
## Options after `--`: `--filter=<text>` runs only tests whose "<file>::<test>" contains the text;
## `--strict` also fails the run on known failures.
##
## Discovery: every res://tests/test_*.gd; each `func test_*(t)` in it (alphabetical) is one test.
## A test file is a RefCounted script; a fresh instance runs each test. Every test gets a fresh
## res://game/main.tscn (SimClock reset, WorldService cleared, tree unpaused) and a TestContext
## (res://tests/lib/test_context.gd) with the game handles, waits, input and soft assertions.
##
## A test fails when one of its checks failed, it timed out, or the engine logged an error (push_error,
## SCRIPT ERROR, ...) while it ran. Warnings are printed but do not fail.
##
## Known failures (game bugs the suite has found and that are not fixed yet): a test file may
## declare `const KNOWN_FAILURES := {"test_name": "why"}`. Such a test still runs; when it fails it
## prints KNOWN FAIL and does not fail the run (unless --strict); when it passes it prints
## UNEXPECTED PASS and fails the run so the entry gets removed.
##
## Exit code: 0 when every test passed (or failed only as a known failure), else 1.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const TESTS_DIR := "res://tests/"
const MAIN_SCENE := "res://game/main.tscn"
## Saves made by tests go here (one folder per runner process, so two runs at once do not empty each
## other's saves); removed when the run ends.
const TEST_SAVE_ROOT := "user://test-saves-%d"
## Real-time limit for one test, setup and teardown excluded.
const TEST_TIMEOUT_MS := 120000
## The game's frame rate (vsync on a 60 Hz display). Headless runs otherwise render as fast as
## they can, which changes real-time presentation such as the camera damping (its floored
## sub-pixel catch-up stalls further from the deadzone edge at high frame rates).
const MAX_FPS := 60
## Physics ticks the fresh main runs before the test starts.
const SETUP_STEPS := 2


## Records engine errors and warnings (the engine may log from any thread).
class ErrorCollector extends Logger:
	var _mutex := Mutex.new()
	var _entries: Array[Dictionary] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var where := "%s:%d (%s)" % [file, line, function]
		for backtrace in script_backtraces:
			if backtrace.get_frame_count() > 0:
				where = "%s:%d" % [backtrace.get_frame_file(0), backtrace.get_frame_line(0)]
				break
		var kind := "ERROR"
		match error_type:
			ERROR_TYPE_WARNING:
				kind = "WARNING"
			ERROR_TYPE_SCRIPT:
				kind = "SCRIPT ERROR"
			ERROR_TYPE_SHADER:
				kind = "SHADER ERROR"
		_mutex.lock()
		_entries.append({
			"warning": error_type == ERROR_TYPE_WARNING,
			"text": "%s: %s at %s" % [kind, rationale if not rationale.is_empty() else code, where],
		})
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[Dictionary]:
		_mutex.lock()
		var taken := _entries.duplicate()
		_entries.clear()
		_mutex.unlock()
		return taken


var _collector := ErrorCollector.new()
var _filter := ""
var _strict := false
var _counts := {"passed": 0, "failed": 0, "known": 0, "unexpected_pass": 0}
var _save_root := TEST_SAVE_ROOT % OS.get_process_id()


func _initialize() -> void:
	OS.add_logger(_collector)
	Engine.max_fps = MAX_FPS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.substr("--filter=".length())
		elif arg == "--strict":
			_strict = true
	_run()


func _run() -> void:
	var cases := _discover()
	print("run_tests: %d test(s) in %s%s" % [cases.size(), TESTS_DIR,
		(" matching '%s'" % _filter) if not _filter.is_empty() else ""])
	# Errors logged while the engine started (autoloads) belong to no test; show them.
	_print_entries(_collector.take(), "startup")
	for test_case: Dictionary in cases:
		await _run_case(test_case)
	print("")
	print("run_tests: %d passed, %d failed, %d known failure(s), %d unexpected pass(es)" % [
		_counts["passed"], _counts["failed"], _counts["known"], _counts["unexpected_pass"]])
	var failed: bool = _counts["failed"] > 0 or _counts["unexpected_pass"] > 0 \
		or (_strict and _counts["known"] > 0)
	_clear_test_saves()
	DirAccess.remove_absolute(_save_root)
	OS.remove_logger(_collector)
	quit(1 if failed else 0)


## [{file, script, method, known_reason}] for every test_*.gd file and test_* method, sorted.
func _discover() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var files := Array(DirAccess.get_files_at(TESTS_DIR))
	files.sort()
	for file: String in files:
		if not file.begins_with("test_") or not file.ends_with(".gd"):
			continue
		var script := load(TESTS_DIR + file) as GDScript
		if script == null or not script.can_instantiate():
			cases.append({"file": file, "script": null, "method": "<load>", "known_reason": ""})
			continue
		var known: Dictionary = script.get_script_constant_map().get("KNOWN_FAILURES", {})
		# A test file may name the world its tests start in (`const MAP_ID := "playground"`).
		var map_id := str(script.get_script_constant_map().get("MAP_ID", ""))
		var methods: Array[String] = []
		for method: Dictionary in script.get_script_method_list():
			var method_name := String(method["name"])
			if method_name.begins_with("test_") and not methods.has(method_name):
				methods.append(method_name)
		methods.sort()
		for method_name in methods:
			var label := "%s::%s" % [file, method_name]
			if not _filter.is_empty() and not label.contains(_filter):
				continue
			cases.append({"file": file, "script": script, "method": method_name,
				"known_reason": str(known.get(method_name, "")), "map_id": map_id})
	return cases


func _run_case(test_case: Dictionary) -> void:
	var label := "%s::%s" % [test_case["file"], test_case["method"]]
	var context := TestContext.new(self, label)
	var started := Time.get_ticks_msec()
	if test_case["script"] == null:
		context.fail("could not load %s%s" % [TESTS_DIR, test_case["file"]])
	else:
		await _setup(context, str(test_case.get("map_id", "")))
		if context.failures.is_empty():
			await _run_body(test_case, context)
		await _teardown(context)
	var warnings := PackedStringArray()
	for entry in _collector.take():
		if entry["warning"]:
			warnings.append(entry["text"])
		else:
			context.fail(entry["text"])
	_report(label, test_case["known_reason"], context, warnings, Time.get_ticks_msec() - started)


## Fresh world: wait out any hit-stop, clear the world service, start a new run (RunState), reset
## the clock, unpause, then instance main.tscn (in the test file's `MAP_ID` world when it names one,
## else level-1) and let it run SETUP_STEPS physics ticks.
func _setup(context: TestContext, map_id: String = "") -> void:
	await _settle()
	var world := Services.world()
	if world != null:
		world.clear()
	var run := Services.run()
	if run != null:
		# Saves made by tests go to a scratch folder, never over the player's own, and every test
		# starts without any (main turns the autosave on once a world is built).
		run.save_root = _save_root
		run.autosave_enabled = false
		_clear_test_saves()
		run.new_run()
		# Tests start armed with the sword (most fight at once); a game's new run starts
		# empty-handed (test_inventory.gd::test_new_run_starts_empty_handed clears this).
		run.start_weapon_id = "basic-sword"
	var clock := Services.clock()
	if clock != null:
		clock.reset()
	paused = false
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		context.fail("could not load %s" % MAIN_SCENE)
		return
	context.main = packed.instantiate()
	if not map_id.is_empty():
		context.main.set(&"map_id", map_id)
	# Playground tests start like a new run: no abilities learned, nothing to gulp (main grants the
	# playground every ability otherwise; its weapons still come).
	context.main.set(&"playground_abilities", false)
	root.add_child(context.main)
	if context.player() == null:
		context.fail("main.tscn did not register a player")
		return
	await context.steps(SETUP_STEPS)


func _run_body(test_case: Dictionary, context: TestContext) -> void:
	var instance: Object = (test_case["script"] as GDScript).new()
	var state := {"done": false}
	var body := func() -> void:
		await Callable(instance, test_case["method"]).call(context)
		state["done"] = true
	body.call()
	var started := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - started > TEST_TIMEOUT_MS:
			context.aborted = true
			context.fail("timed out after %d ms (real time)" % TEST_TIMEOUT_MS)
			return
		await process_frame


func _clear_test_saves() -> void:
	var dir := DirAccess.open(_save_root)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)


## Releases held input, frees main and the world, and leaves the tree unpaused.
func _teardown(context: TestContext) -> void:
	context.release_all()
	context.disconnect_all()
	await _settle()
	if context.main != null and is_instance_valid(context.main):
		context.main.queue_free()
	await process_frame
	await process_frame
	var world := Services.world()
	if world != null:
		world.clear()
	paused = false


## Waits (real time, at most 1 s) until no hit-stop is running, so a deferred hit-stop pause cannot
## land in the next test.
func _settle() -> void:
	var feel := Services.feel()
	var started := Time.get_ticks_msec()
	while feel != null and feel.is_frozen() and Time.get_ticks_msec() - started < 1000:
		await process_frame
	await process_frame
	await process_frame


func _report(label: String, known_reason: String, context: TestContext, warnings: PackedStringArray,
		elapsed_ms: int) -> void:
	var passed := context.failures.is_empty()
	var status := "PASS"
	if passed and not known_reason.is_empty():
		status = "UNEXPECTED PASS"
		_counts["unexpected_pass"] += 1
	elif passed:
		_counts["passed"] += 1
	elif not known_reason.is_empty():
		status = "KNOWN FAIL"
		_counts["known"] += 1
	else:
		status = "FAIL"
		_counts["failed"] += 1
	print("%-15s %s (%.1f s)" % [status, label, elapsed_ms / 1000.0])
	if status == "KNOWN FAIL":
		print("      known game bug: %s" % known_reason)
	elif status == "UNEXPECTED PASS":
		print("      listed in KNOWN_FAILURES (%s) but passed: remove the entry" % known_reason)
	for line in _unique(context.failures):
		print("      - %s" % line)
	for line in _unique(warnings):
		print("      (warning) %s" % line)
	for line in context.notes:
		print("      . %s" % line)


func _print_entries(entries: Array[Dictionary], where: String) -> void:
	for entry in entries:
		print("run_tests: %s during %s" % [entry["text"], where])


static func _unique(lines: PackedStringArray, limit: int = 12) -> PackedStringArray:
	var seen := {}
	var result := PackedStringArray()
	for line in lines:
		if seen.has(line):
			continue
		seen[line] = true
		if result.size() < limit:
			result.append(line)
	if seen.size() > limit:
		result.append("... %d more distinct" % (seen.size() - limit))
	return result

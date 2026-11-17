extends SceneTree
## Films one Gulp throw in the playground, frame by frame, to judge its feel
## (docs/godot/THROW_COMBAT.md "Filming a throw"): the slime stands beside a liftable with an enemy
## in front of it, sucks the thing in, throws it, and every frame from the throw's key press on is
## saved. The enemy stands at its post and leaves the slime alone (a dot arena, as the pen's enemies
## do while the slime is outside it).
## Run windowed (it renders) with a fixed frame time, from the repo:
##     "<Godot 4.7.2 console exe>" --path godot --fixed-fps 60 -s res://tools/film_throw.gd -- \
##         --out=<dir> [--enemy=<type id>] [--kind=<liftable kind>] [--gap=<px>] [--frames=<n>]
##         [--throws=<n>] [--dir=right|left|up|down] [--gulp=<1..3>] [--set=<constant path>=<number>]
##         [--second=<type id>@<px behind the enemy>[,<px aside>]] [--wall=<px behind the enemy>]
##         [--ammo=<gulp frame>[,<throw frame>]] [--ammo-gap=<px>] [--ammo-wait=<frames>]
##         [--stage=<x>,<y> (the slime's feet)] [--map=<world id>] [--ammo-dir=<dir>]
##         [--attacker=<type id>@<dx>,<dy>] [--attacker-at=<frame>]
##         [--side=<px>: the enemy stands that far beside the throw's line, so the throw misses it]
##         [--catch-at=<frames after the throw's press>: a second Gulp press then (the mouth catch of
##         a rebound)] [--uses=<n>: the thing has that many hits left] [--back-wall=<px behind the
##         slime>: a wall there, staged once the thing is in the mouth] [--empty-suck] [--drop-at=
##         <frames after the throw's press>: the mouth drops what it holds, as on a hit]
## Writes <dir>/f<nnn>.png (the game's own view, one per frame) and <dir>/film.json (what was filmed,
## the frame of each throw, the enemy's health after each).
## `scripts/godot/throw-film-sheet.py <dir>` lays the frames out as a strip and a GIF.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const MAIN_SCENE := "res://game/main.tscn"
const MAP_ID := "playground"
const ENEMY_SCENE_PREFIX := "character."
const WINDOW := Vector2i(1024, 768)
## Where the stage stands from the playground's spawn point (open ground, clear of the pen).
const STAGE_OFFSET := Vector2(60.0, -40.0)
## The liftable lies this far behind the slime (away from the enemy), within the suck's near reach.
const LIFTABLE_BEHIND_PX := 34.0
## The film ends itself after this long in real time, whatever happened (a script error would
## otherwise leave the window open for ever).
const WATCHDOG_S := 240.0
## The staged wall (--wall): its size for a throw to the right or left (turned for up and down).
const WALL_SIZE := Vector2(40.0, 200.0)
## The staged attacker's arena (--attacker): it fights the slime anywhere within this of its post.
const ATTACKER_ARENA_PX := 600.0
const WALL_COLOR := Color(0.42, 0.44, 0.5)

var _main: Node
var _out := "user://throw-film"
var _enemy_type := "slime-spider"
var _kind := "clay-pot"
var _gap := 190.0
var _frames := 70
var _throws := 1
var _dir := Vector2.RIGHT
var _gulp := 0
var _sets: Dictionary = {}
var _index := 0
var _log: Dictionary = {}
## The real time of each saved frame (ms since the first): a hit-stop runs on real time, so its
## length in film frames is its real length only where these step by about 17.
var _real_ms: Array[int] = []
## Whether the tree was paused (a hit-stop) at each saved frame: 1 or 0 (film.json "paused").
var _paused: Array[int] = []
## Whether the slime was action-locked (the throw's `spit` clip) at each saved frame: 1 or 0
## (film.json "locked").
var _locked: Array[int] = []
var _first_real_ms := -1
## The reactions' stages: a second enemy behind the first (--second=<type>@<px>[,<px aside>]), a
## wall behind it (--wall=<px>), and where every staged enemy was at each saved frame (film.json
## "track": per frame, per enemy, [x, y, health] or null once it is gone).
var _second_type := ""
var _second_gap := 70.0
var _second_side := 0.0
var _wall_gap := 0.0
## The first enemy stands this far to the side of the throw's line (--side=<px>): a throw that
## misses it (and breaks on the ground, or on the --wall, which stays on the line).
var _side := 0.0
## The rebound prototype's stages: a second Gulp press this many frames after the throw's (--catch-at,
## 0 = none), the hits the thing has left (--uses, 0 = all of its material's), and a wall this far
## behind the slime (--back-wall, 0 = none).
var _catch_at := 0
var _uses := 0
var _back_wall := 0.0
## --empty-suck: before the throws, one Gulp press with nothing in reach; film.json "empty_suck"
## says for how many physics steps the mouth rooted the slime and how many more until a new suck
## could start (the cooldown).
var _empty_suck := false
## --drop-at=<frames after the throw's press>: the mouth drops what it holds then, as a hit on the
## slime makes it (Mouth.drop): a held pot bursts, a carried enemy comes out.
var _drop_at := 0
var _tracked: Array = []
var _track: Array = []
## The enemy-ammo prototype's stages (--ammo=<gulp frame>[,<throw frame>], --ammo-gap=<px>,
## --ammo-wait=<frames>): `_ammo_wait` frames before the gulp frame (counted from the throw's press)
## the slime is set `_ammo_gap` px before the first enemy (so the hint on a helpless enemy shows);
## at the gulp frame it taps the Gulp key (it gulps the enemy when it lies helpless); at the throw
## frame it taps again.
var _ammo_at := 0
var _ammo_throw_at := 0
var _ammo_gap := 60.0
var _ammo_wait := 0
## --ammo-dir=right|left|up|down: the way the slime steps up to the enemy and throws it (default the
## first throw's). --attacker=<type id>@<dx>,<dy> and --attacker-at=<frame>: at that frame (after the
## throw's press) an enemy that fights the slime is put that far from the slime's feet (a hit while
## it carries one).
var _ammo_dir := Vector2.ZERO
var _attacker_type := ""
var _attacker_offset := Vector2.ZERO
var _attacker_at := 0
## The size of the "enemy" group at each saved frame (film.json "enemy_group").
var _group_sizes: Array[int] = []
## The ground's fates' stages (--stage=<x>,<y>: where the slime's feet stand, in place of the open
## grass by the spawn point; --map=<world id>: another world than the playground).
var _stage_at := Vector2.INF
var _map := MAP_ID


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--enemy="):
			_enemy_type = arg.trim_prefix("--enemy=")
		elif arg.begins_with("--kind="):
			_kind = arg.trim_prefix("--kind=")
		elif arg.begins_with("--gap="):
			_gap = float(arg.trim_prefix("--gap="))
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--throws="):
			_throws = int(arg.trim_prefix("--throws="))
		elif arg.begins_with("--gulp="):
			_gulp = int(arg.trim_prefix("--gulp="))
		elif arg.begins_with("--dir="):
			_dir = {"right": Vector2.RIGHT, "left": Vector2.LEFT, "up": Vector2.UP, "down": Vector2.DOWN}.get(
				arg.trim_prefix("--dir="), Vector2.RIGHT)
		elif arg.begins_with("--set="):
			var pair := arg.trim_prefix("--set=").split("=")
			if pair.size() == 2:
				_sets[pair[0]] = float(pair[1])
		elif arg.begins_with("--second="):
			# A second enemy behind the first: <type>@<px behind it>[,<px to its side>].
			var parts := arg.trim_prefix("--second=").split("@")
			_second_type = parts[0]
			if parts.size() > 1:
				var place := parts[1].split(",")
				_second_gap = float(place[0])
				_second_side = float(place[1]) if place.size() > 1 else 0.0
		elif arg.begins_with("--side="):
			_side = float(arg.trim_prefix("--side="))
		elif arg.begins_with("--catch-at="):
			_catch_at = int(arg.trim_prefix("--catch-at="))
		elif arg.begins_with("--uses="):
			_uses = int(arg.trim_prefix("--uses="))
		elif arg.begins_with("--drop-at="):
			_drop_at = int(arg.trim_prefix("--drop-at="))
		elif arg == "--empty-suck":
			_empty_suck = true
		elif arg.begins_with("--back-wall="):
			_back_wall = float(arg.trim_prefix("--back-wall="))
		elif arg.begins_with("--ammo="):
			var frames := arg.trim_prefix("--ammo=").split(",")
			_ammo_at = int(frames[0])
			_ammo_throw_at = int(frames[1]) if frames.size() > 1 else 0
		elif arg.begins_with("--ammo-gap="):
			_ammo_gap = float(arg.trim_prefix("--ammo-gap="))
		elif arg.begins_with("--ammo-dir="):
			_ammo_dir = {"right": Vector2.RIGHT, "left": Vector2.LEFT, "up": Vector2.UP, "down": Vector2.DOWN}.get(
				arg.trim_prefix("--ammo-dir="), Vector2.ZERO)
		elif arg.begins_with("--attacker="):
			var parts := arg.trim_prefix("--attacker=").split("@")
			_attacker_type = parts[0]
			if parts.size() > 1:
				var place := parts[1].split(",")
				_attacker_offset = Vector2(float(place[0]), float(place[1]) if place.size() > 1 else 0.0)
		elif arg.begins_with("--attacker-at="):
			_attacker_at = int(arg.trim_prefix("--attacker-at="))
		elif arg.begins_with("--ammo-wait="):
			_ammo_wait = int(arg.trim_prefix("--ammo-wait="))
		elif arg.begins_with("--stage="):
			var place := arg.trim_prefix("--stage=").split(",")
			if place.size() == 2:
				_stage_at = Vector2(float(place[0]), float(place[1]))
		elif arg.begins_with("--map="):
			_map = arg.trim_prefix("--map=")
		elif arg.begins_with("--wall="):
			# A wall this far behind the first enemy (px from its middle to the wall's face).
			_wall_gap = float(arg.trim_prefix("--wall="))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		push_error("film_throw: gave up after %d s" % int(WATCHDOG_S))
		quit(1))
	DisplayServer.window_set_size(WINDOW)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", _map)
	_main.set(&"ability_ceremonies", false)
	root.add_child(_main)
	for i in 90:
		await process_frame
	var world := Services.world()
	var constants := Services.constants()
	# The hit-stop counts the film's frames, not the wall clock: a film runs many times slower than
	# real time, and a 90 ms freeze would be over before its first frame was saved (GameFeel).
	if Services.feel() != null:
		Services.feel().frame_clock_ms = 1000.0 / 60.0
	for path: String in _sets:
		_set_constant(constants, path, _sets[path])
	if _gulp > 0:
		ThrowMode.set_dev_level(_gulp)
	var stage := world.player_spawn_point() + STAGE_OFFSET
	var player: Node = world.player
	var body := world.player_body
	if _stage_at.is_finite():
		# The slime's feet on that spot (teleport takes its middle).
		stage = _stage_at + ((player.call(&"get_centre") as Vector2) - body.global_position)
	player.call(&"teleport", stage)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	# Put there without walking: the slime stands on the level of the ground there (a staged ledge).
	if _stage_at.is_finite() and world.elevation != null:
		world.elevation.track(body)
	player.call(&"face", _dir)
	# A Variant: the enemy is freed 0.8 s after it dies.
	var enemy: Variant = _spawn_enemy(stage + _dir * _gap + _dir.orthogonal() * _side)
	_tracked.append(enemy)
	_stage_extras(stage + _dir * _gap, enemy)
	for i in 40:
		await physics_frame
	var empty_suck := {}
	if _empty_suck:
		empty_suck = await _time_empty_suck(player)
	var throws: Array = []
	for n in _throws:
		var mouth: RefCounted = player.call(&"get_mouth")
		# A mouth that already holds something (the last throw's rebound, caught: --catch-at) throws
		# that; else a new thing is laid behind the slime and sucked in.
		var full := bool(mouth.call(&"is_holding"))
		var liftable: Node2D = null
		if not full:
			liftable = ThrowAmmo.spawn_liftable(_kind, body.global_position - _dir * LIFTABLE_BEHIND_PX,
				{"uses": _uses} if _uses > 0 else {})
		for i in 20:
			await physics_frame
		player.call(&"face", _dir)
		if not full:
			# The suck: a tap of the Gulp key; the thing is in the mouth when the burst ends.
			_push(&"eat", true)
			await physics_frame
			await physics_frame
			_push(&"eat", false)
		# How many physics steps after the suck's press the thing was in the mouth, and whether the
		# mouth still rooted the slime on that step (film.json "catch_steps", "rooted_at_catch").
		var catch_steps := -1
		var rooted_at_catch := false
		for i in (0 if full else 90):
			await physics_frame
			if bool(mouth.call(&"is_holding")) and not bool(mouth.call(&"is_sucking")):
				catch_steps = i + 3
				rooted_at_catch = bool((player.call(&"get_mouth_hold") as RefCounted).call(&"roots_player"))
				break
		if not bool(mouth.call(&"is_holding")):
			push_warning("film_throw: nothing was caught (%s, valid %s)" % [_kind, is_instance_valid(liftable)])
		if _back_wall > 0.0 and n == 0:
			_add_wall(body.global_position - _dir * (_back_wall + WALL_SIZE.x * 0.5), body.collision_mask)
		for i in 24:
			await physics_frame
		player.call(&"face", _dir)
		# The throw: frames from two before the key press.
		await _frame()
		await _frame()
		var first := _index
		_push(&"eat", true)
		await _frame()
		await _frame()
		_push(&"eat", false)
		for i in _frames:
			# The mouth catch: a second press `_catch_at` frames after the throw's (two are filmed already).
			if _catch_at > 0 and i + 2 == _catch_at:
				_push(&"eat", true)
			if _catch_at > 0 and i + 2 == _catch_at + 2:
				_push(&"eat", false)
			if _drop_at > 0 and i + 2 == _drop_at:
				mouth.call(&"drop")
			# The enemy-ammo stages: step up to the first enemy and gulp it; later throw it.
			if _ammo_at > 0 and i + 2 == _ammo_at - _ammo_wait and is_instance_valid(enemy):
				player.call(&"teleport", ((enemy as Node).call(&"get_centre") as Vector2) - _ammo_way() * _ammo_gap)
				body.velocity = Vector2.ZERO
				body.reset_physics_interpolation()
				if _stage_at.is_finite() and world.elevation != null:
					world.elevation.track(body)
				player.call(&"face", _ammo_way())
			if _ammo_at > 0 and i + 2 == _ammo_at:
				player.call(&"face", _ammo_way())
				_push(&"eat", true)
			if _ammo_throw_at > 0 and i + 2 == _ammo_throw_at:
				player.call(&"face", _ammo_way())
				_push(&"eat", true)
			if not _attacker_type.is_empty() and i + 2 == _attacker_at:
				_tracked.append(_spawn_attacker(body.global_position + _attacker_offset))
			if (_ammo_at > 0 and i + 2 == _ammo_at + 2) or (_ammo_throw_at > 0 and i + 2 == _ammo_throw_at + 2):
				_push(&"eat", false)
			await _frame()
		throws.append({"first_frame": first, "enemy_health": _health(enemy), "enemy_alive": _alive(enemy),
			"catch_steps": catch_steps, "rooted_at_catch": rooted_at_catch, "held_after": (mouth.get(&"held") as Dictionary).duplicate()})
	_log = {"enemy": _enemy_type, "kind": _kind, "gap": _gap, "frames": _index, "throws": throws, "sets": _sets,
		"window": [WINDOW.x, WINDOW.y], "real_ms": _real_ms, "paused": _paused, "locked": _locked}
	_log["track"] = _track
	_log["enemy_group"] = _group_sizes
	if _empty_suck:
		_log["empty_suck"] = empty_suck
	var file := FileAccess.open(_out.path_join("film.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_log, "\t"))
	file.close()
	print("film_throw: ", JSON.stringify(_log))
	quit()


## The enemy of `_enemy_type` at `centre`, standing there (a dot arena) with its type's health.
func _spawn_enemy(centre: Vector2) -> Node:
	var world := Services.world()
	var parent: Node = world.entities_root()
	var enemy_root := world.instantiate_scene(ENEMY_SCENE_PREFIX + _enemy_type) as Node2D
	if enemy_root == null:
		push_warning("film_throw: no scene for '%s'" % _enemy_type)
		return null
	var enemy: Node = null
	for child: Node in enemy_root.get_children():
		if child.has_method(&"configure_navigation"):
			enemy = child
			break
	var target: Vector2 = FeetAnchor.global_for_phaser_position(enemy_root, centre)
	# The type's health, as the pen's enemies have (shapes_testbed.gd `pen_type_health`): the scene's
	# own is often lower.
	var types: Variant = Services.constants().data_file("enemy-types.json")
	var row: Variant = ((types as Dictionary).get("types", {}) as Dictionary).get(_enemy_type, {}) if types is Dictionary else {}
	if enemy != null and row is Dictionary and enemy.get(&"max_health") != null:
		enemy.set(&"max_health", maxf(float(enemy.get(&"max_health")), float((row as Dictionary).get("maxHp", 0.0))))
	var parent_item := parent as CanvasItem
	enemy_root.position = parent_item.get_global_transform().affine_inverse() * target if parent_item != null else target
	parent.add_child(enemy_root)
	enemy_root.reset_physics_interpolation()
	if enemy != null:
		var no_zones: Array[Dictionary] = []
		enemy.call(&"configure_navigation", {}, no_zones)
		if enemy.has_method(&"configure_arena"):
			enemy.call(&"configure_arena", {"shape": "circle", "x": centre.x, "y": centre.y, "radius": 1.0})
	return enemy


## The film's own numbers: `path` in game-constants.json reads `number` for this run.
func _set_constant(constants: Node, path: String, number: float) -> void:
	var current: Variant = constants.get(&"_constants")
	var segments := path.split(".")
	for i in segments.size() - 1:
		if not current is Dictionary or not (current as Dictionary).has(segments[i]):
			push_warning("film_throw: no constant '%s'" % path)
			return
		current = (current as Dictionary)[segments[i]]
	if current is Dictionary:
		(current as Dictionary)[segments[segments.size() - 1]] = number


func _health(enemy: Variant) -> float:
	if not is_instance_valid(enemy):
		return 0.0
	var value: Variant = (enemy as Node).get(&"_hp")
	return float(value) if value is float or value is int else -1.0


func _alive(enemy: Variant) -> bool:
	if not is_instance_valid(enemy):
		return false
	var node := enemy as Node
	return not (node.has_method(&"is_defeated") and bool(node.call(&"is_defeated")))


## One game frame, saved.
func _frame() -> void:
	await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("f%03d.png" % _index)))
	if _first_real_ms < 0:
		_first_real_ms = Time.get_ticks_msec()
	_real_ms.append(Time.get_ticks_msec() - _first_real_ms)
	_paused.append(1 if paused else 0)
	var slime: Node = Services.world().player if Services.world() != null else null
	_locked.append(1 if slime != null and bool(slime.call(&"is_action_locked")) else 0)
	_track.append(_places())
	_group_sizes.append(get_nodes_in_group(&"enemy").size())
	_index += 1


## The reactions' stages (--second, --wall): a second enemy `_second_gap` behind the first one
## (`_second_side` to its side), a wall `_wall_gap` behind it. The wall is a static body on every
## layer the enemy's body collides with, drawn as a grey block.
func _stage_extras(centre: Vector2, enemy: Variant) -> void:
	if not _second_type.is_empty():
		var first_type := _enemy_type
		_enemy_type = _second_type
		_tracked.append(_spawn_enemy(centre + _dir * _second_gap + _dir.orthogonal() * _second_side))
		_enemy_type = first_type
	if _wall_gap > 0.0 and is_instance_valid(enemy):
		var enemy_body := (enemy as Node).call(&"get_body") as CharacterBody2D
		_add_wall(centre + _dir * (_wall_gap + WALL_SIZE.x * 0.5), enemy_body.collision_mask if enemy_body != null else 1)


## A Gulp press with nothing in reach: {"rooted_steps": physics steps the mouth rooted the slime,
## "cooldown_steps": steps after that until a second press started a suck}.
func _time_empty_suck(player: Node) -> Dictionary:
	var hold: RefCounted = player.call(&"get_mouth_hold")
	var mouth: RefCounted = player.call(&"get_mouth")
	_push(&"eat", true)
	await physics_frame
	await physics_frame
	_push(&"eat", false)
	var rooted := 0
	for i in 120:
		await physics_frame
		if not bool(hold.call(&"roots_player")):
			break
		rooted += 1
	# A new press every step until one starts a suck: the cooldown's length.
	var cooldown := 0
	for i in 60:
		_push(&"eat", true)
		await physics_frame
		_push(&"eat", false)
		await physics_frame
		if bool(mouth.call(&"is_sucking")):
			break
		cooldown += 2
	for i in 60:
		await physics_frame
	return {"rooted_steps": rooted + 2, "cooldown_steps": cooldown}


## A staged wall (a grey block, a static body on `layers`) with its middle at `at`, across the throw.
func _add_wall(at: Vector2, layers: int) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = layers
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = WALL_SIZE if _dir.x != 0.0 else Vector2(WALL_SIZE.y, WALL_SIZE.x)
	shape.shape = box
	wall.add_child(shape)
	var look := ColorRect.new()
	look.color = WALL_COLOR
	look.size = box.size
	look.position = -box.size * 0.5
	wall.add_child(look)
	Services.world().entities_root().add_child(wall)
	wall.global_position = at


## Where each staged enemy's middle is now ([x, y], its health, 1 while the slime carries it as
## ammo; null once it is gone).
func _places() -> Array:
	var out: Array = []
	for entry: Variant in _tracked:
		if not is_instance_valid(entry) or not (entry as Node).has_method(&"get_centre"):
			out.append(null)
			continue
		var at: Vector2 = (entry as Node).call(&"get_centre")
		var carried := (entry as Node).has_method(&"is_carried") and bool((entry as Node).call(&"is_carried"))
		var entry_body := (entry as Node).call(&"get_body") as Node2D if (entry as Node).has_method(&"get_body") else null
		var seen := entry_body != null and is_instance_valid(entry_body) and entry_body.visible
		out.append([snappedf(at.x, 0.1), snappedf(at.y, 0.1), _health(entry), 1 if carried else 0,
			1 if (entry as Node).is_in_group(&"enemy") else 0, 1 if seen else 0])
	return out


## The way the enemy-ammo stages step up and throw (--ammo-dir, else the first throw's).
func _ammo_way() -> Vector2:
	return _ammo_dir if _ammo_dir != Vector2.ZERO else _dir


## An enemy of `_attacker_type` at `feet` that fights the slime (an arena round it that holds the
## slime, instead of the staged enemies' dot).
func _spawn_attacker(feet: Vector2) -> Node:
	var first_type := _enemy_type
	_enemy_type = _attacker_type
	var attacker := _spawn_enemy(feet)
	_enemy_type = first_type
	if attacker != null and attacker.has_method(&"configure_arena"):
		attacker.call(&"configure_arena", {"shape": "circle", "x": feet.x, "y": feet.y, "radius": ATTACKER_ARENA_PX})
	return attacker


## The key as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

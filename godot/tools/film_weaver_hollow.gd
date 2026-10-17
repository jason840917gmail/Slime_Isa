extends SceneTree
## Films the Weaver Hollow's main path in the running game (docs/godot/DUNGEONS.md "The Weaver
## Hollow"): from the entrance to the Pearl, one shot per step, each the game's own view with the HUD.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/film_weaver_hollow.gd -- --out=<dir> [--only=<shot prefix>]
## Writes <dir>/<nn>-<shot>.png and <dir>/shots.json (each shot's caption), which
## scripts/maps/weaver-hollow-contact-sheet.py lays out as a contact sheet.
##
## A shot is staged, not played: the slime is put where the step happens, the step's locks are
## opened by their flags when the shot shows what comes after them, and what the step does (a blast,
## a held key) is played for a moment before the frame is taken.

const Services := preload("res://game/shared/services.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DUNGEON_ID := "weaver-hollow"
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://weaver-hollow-film"
const CELL := 64.0
const WORLD := "weaver-hollow-%s"

## [name, floor (or a whole world id), the slime's feet (cells), facing, actions, caption]. Actions: "flag:<id>" (set before
## the world is entered), "keys:<n>" (small keys held), "item:<big-key|map>" (a dungeon item held),
## "trigger:<node path>" (sets a kit piece off once the world is entered: a bridge, a shutter, a door),
## "blast:<x>,<y>" (cells), "hold:<action>:<ms>", "wait:<ms>".
const SHOTS := [
	["forecourt", "gloop-forest-f4", Vector2(15, 11.5), Vector2.UP, ["wait:400"], "The forecourt: the Watch Oak's bricked root gate"],
	["forecourt-blown", "gloop-forest-f4", Vector2(15, 11.5), Vector2.UP, ["blast:15,10.4", "wait:900"], "A bomb blows the gate: the way into the Trunk"],
	["entrance", "trunk", Vector2(24, 39.5), Vector2.UP, [], "T1 Root Door: in through the cracked root gate"],
	["webs", "trunk", Vector2(24, 36.5), Vector2.UP, ["hold:move_up:900"], "T1: a floor web slows the walk"],
	["hub", "trunk", Vector2(32, 7.7), Vector2.UP, [], "T2 the Hollow Heart: the Crown Door on its gallery"],
	["larder", "trunk", Vector2(8, 19.5), Vector2.UP, ["wait:600"], "T3 the Larder: two cracks, two orb-weavers"],
	["larder-blown", "trunk", Vector2(8, 19.5), Vector2.UP, ["blast:8,17.5", "wait:900"], "T3: a bomb blows the north crack"],
	["map-nook", "trunk", Vector2(2.5, 12.2), Vector2.UP, ["flag:weaver-hollow.larder-crack-nook"], "T3a the map nook, behind the second crack"],
	["well-room", "trunk", Vector2(10, 10.5), Vector2.LEFT, ["flag:weaver-hollow.larder-crack-well"], "T4 the Well Room: the first cracked floor"],
	["root-fall", "roots", Vector2(3.5, 4), Vector2.DOWN, ["wait:1800"], "R1 Root Fall: the first egg sac, seen from the ledge"],
	["bone-cellar", "roots", Vector2(22, 9), Vector2.RIGHT, ["wait:1200"], "R2 the Bone Cellar: cast behind a pillar; key 1 sealed"],
	["cellar-key", "roots", Vector2(38.5, 6.4), Vector2.UP, ["flag:weaver-hollow.cellar-crack-key", "wait:600"], "R2: the blown pocket, small key 1"],
	["drop-gate", "roots", Vector2(51.6, 9.6), Vector2.RIGHT, ["keys:1", "wait:400"], "R3 the Drop Gate: roll the web-free lane"],
	["hatch", "trunk", Vector2(43.5, 22), Vector2.RIGHT, ["flag:weaver-hollow.hatch-open", "keys:1"], "T2: up through the hatch; key 1 opens the east door"],
	["bough-stair", "boughs", Vector2(4, 22), Vector2.RIGHT, ["wait:800"], "B1 the Bough Stair: a Silk Lurker's shadow"],
	["drawbridge", "boughs", Vector2(27, 22), Vector2.RIGHT, ["wait:400"], "B2 the Drawbridge: the bridge up, its cracked post"],
	["drawbridge-down", "boughs", Vector2(27, 22), Vector2.RIGHT, ["blast:34.6,20.8", "wait:1400"], "B2: a bomb over the void breaks the post"],
	["mimic", "boughs", Vector2(42, 37), Vector2.UP, ["wait:600"], "B3 the Mimic's Pantry: a cocoon that breathes"],
	["nursery", "boughs", Vector2(55.5, 25), Vector2.UP, ["wait:1500"], "B4 the Nursery: the ambush shuts its doors"],
	["double-door", "boughs", Vector2(40, 19.5), Vector2.UP, ["keys:2", "wait:300"], "B2: keys 2 and 3 open the Warden's double door"],
	["warden", "boughs", Vector2(40, 11.5), Vector2.UP, ["trigger:Objects/den-double-door", "wait:1200"], "B5 the Warden's Den: the Brood Warden"],
	["hoard", "boughs", Vector2(27.5, 9), Vector2.UP, ["trigger:Objects/hoard-shutter"], "The Hoard: the big chest, the big key"],
	["gallery", "trunk", Vector2(34, 4.6), Vector2.UP, ["item:big-key"], "T2's gallery: the calm room before the Crown Door"],
	["crown-stair", "crown", Vector2(8, 24), Vector2.UP, [], "C1 the Crown Stair: the climb"],
	["matron", "crown", Vector2(8, 11.5), Vector2.UP, ["wait:2500"], "C2 the Crown: the Matron in her cocoon"],
	["outer-bough", "crown", Vector2(22, 8), Vector2.RIGHT, [], "C3 the Outer Bough: the way out with the Silk skin"],
	["s1", "gloop-forest-f4", Vector2(19.4, 13.2), Vector2.RIGHT, ["wait:400"], "The drop lands by the gate: S1's web wall"],
	# Checks (only with --only=check): walks over the lowered drawbridges, the slime's end printed.
	["check-b2-bridge", "boughs", Vector2(28.5, 22), Vector2.RIGHT, ["trigger:Objects/b2-drawbridge", "hold:move_right:2600"], "B2: over the lowered bridge"],
	["check-b6-bridge", "boughs", Vector2(52, 10.4), Vector2.UP, ["trigger:Objects/b6-drawbridge", "hold:move_up:1800"], "B6: up the lowered bridge to the far shore"],
	["check-larder-door", "trunk", Vector2(12.5, 22), Vector2.RIGHT, ["hold:move_right:2200"], "T3: east through the doorway into the hub"],
	["check-gallery-stair", "trunk", Vector2(44.5, 4.4), Vector2.DOWN, ["trigger:Objects/gallery-stair-block", "hold:move_down:2000"], "T2: down the gallery's open stair"],
]

var _main: Node


func _initialize() -> void:
	var out := DEFAULT_OUT
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_size(Vector2i(1024, 1024))
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", WORLD % "trunk")
	_main.set(&"playground_abilities", false)
	root.add_child(_main)
	for i in 60:
		await process_frame
	var captions := []
	var index := 0
	for shot: Array in SHOTS:
		index += 1
		var shot_name: String = shot[0]
		if only != "" and not shot_name.begins_with(only):
			continue
		if shot_name.begins_with("check-") and not only.begins_with("check"):
			continue
		var world_id := str(shot[1]) if str(shot[1]).contains("-") else WORLD % str(shot[1])
		var actions: Array = shot[4]
		var run := Services.run()
		var travel := Services.world().map_id() != world_id
		for action: String in actions:
			if action.begins_with("flag:") and not run.has_flag(action.trim_prefix("flag:")):
				run.set_flag(action.trim_prefix("flag:"))
				travel = true
			elif action.begins_with("keys:"):
				var keys := int(action.trim_prefix("keys:"))
				var held := DungeonState.small_keys(run, DUNGEON_ID)
				if keys > held:
					DungeonState.add_small_key(run, DUNGEON_ID, keys - held)
			elif action.begins_with("item:"):
				DungeonState.give_item(run, DUNGEON_ID, action.trim_prefix("item:"))
		if travel:
			_main.call(&"travel_to", world_id)
			var waited := 0
			while (Services.world().map_id() != world_id or Services.world().player_body == null) and waited < 600:
				await process_frame
				waited += 1
			for i in 50:
				await physics_frame
		var player: Node = Services.world().player
		var body := Services.world().player_body
		body.global_position = (shot[2] as Vector2) * CELL
		body.velocity = Vector2.ZERO
		body.reset_physics_interpolation()
		if Services.world().elevation != null:
			Services.world().elevation.call(&"track", body)
		player.call(&"face", shot[3])
		for i in 20:
			await physics_frame
		for action: String in actions:
			if action.begins_with("trigger:"):
				var piece := Services.world().world_root.get_node_or_null(action.trim_prefix("trigger:"))
				if piece != null and piece.has_method(&"trigger"):
					piece.call(&"trigger")
				elif piece != null and piece.has_method(&"open_for_good"):
					piece.call(&"open_for_good")
				await _wait_ms(900.0)
			elif action.begins_with("blast:"):
				var xy := action.trim_prefix("blast:").split(",")
				GooBlast.detonate(Vector2(float(xy[0]), float(xy[1])) * CELL, false)
			elif action.begins_with("hold:"):
				var parts := action.split(":")
				_push(StringName(parts[1]), true)
				await _wait_ms(float(parts[2]))
				_push(StringName(parts[1]), false)
			elif action.begins_with("wait:"):
				await _wait_ms(float(action.trim_prefix("wait:")))
		for i in 6:
			await RenderingServer.frame_post_draw
		print("end %s at %s cells" % [shot_name, (Services.world().player_body.global_position / CELL).snapped(Vector2(0.1, 0.1))])
		var file := "%02d-%s.png" % [index, shot_name]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join(file)))
		captions.append({"file": file, "caption": shot[5]})
		print("shot ", file)
	var json := FileAccess.open(ProjectSettings.globalize_path(out.path_join("shots.json")), FileAccess.WRITE)
	json.store_string(JSON.stringify(captions, "\t"))
	json.close()
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


## Waits `ms` of game time (at most three times as long in real time: a ceremony pauses the clock).
func _wait_ms(ms: float) -> void:
	var started := Services.now_ms()
	var real_start := Time.get_ticks_msec()
	while Services.now_ms() - started < ms and Time.get_ticks_msec() - real_start < ms * 3.0 + 2000.0:
		await physics_frame


## The key as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)

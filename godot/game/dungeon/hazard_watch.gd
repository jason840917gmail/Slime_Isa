extends Node
class_name HazardWatch
## Watches the slime over a world's hazards (docs/godot/DUNGEONS.md "The void, slabs and spikes"):
## made by the first Hazard or HazardDeck of a world (`ensure`), a child of the world's root.
##
## Every physics step, with the slime on the ground (not in the air, not on stairs, not dead):
## - every deck its body stands on is touched (a falling slab starts to give);
## - the middle of its body (its collision rect's centre: the middle of its footprint) in a hazard
##   (hazard.gd) and not held up by a deck there, or on a lower level than the hazard's rim (the
##   owner, 2026-10-19: by its feet, the front of its body walking south, a walker reached the next
##   slab of a bridge just before the one behind fell, and crossed): **void**: it falls (it spins and shrinks over `dungeon.void.fallMs`, the
##   `FallDown` cue), then it is put back on the rim it fell from (the hazard's nearest return
##   point to its last safe ground, else that ground itself) and loses `dungeon.void.damage` health;
##   **spikes** / **lava**: it is hurt each time its invulnerability ends; a slab gone from under it
##   over a sunken pit first drops it in (to the pit's floor, `dungeon.spikes.fallMs`; with no floor
##   of the pit within reach, only wall faces under it, it is put back on the rim as from the void);
##   **water** (deep water under a plank bridge, falling_plank.gd): it sinks with a splash
##   (`dungeon.water.fallMs`, the `WaterSplash` cue, water_splash.gd's rings) and is put back as from
##   the void, losing `dungeon.water.damage`; a form that swims never falls in;
## - elsewhere, on solid ground (its body clear of the cells every hazard covers, or the middle of its
##   body on a safe deck, and its body clear of every slab), that spot is its last safe ground.
## Hazard damage goes through DamageRouter (true damage, no knockback; weapon id `hazard-<kind>`,
## tags `hazard` and the kind), so the slime's invulnerability, its Roll's i-frames and its fainting
## work as for any hit. A fall that faints it ends with the slime waking at the dungeon's entrance.
##
## The decks' passages over elevation holes (Elevation.open_passage) are opened here too, merged
## into as few rectangles as their cells allow, once the world is registered, and only while each deck
## holds (`_sync_passages`): a slab that falls (a plank that sinks) closes its cells again
## (Elevation.close_passage), so the floor's rim beside the gap holds the slime and a push drops it
## (the ledge drop) as at any rim; it opens them again once it is back. A deck closes only once the
## slime's body on its level is clear of it (and of a tile round it): the rim coming back never shuts
## the slime inside it. Falling with the deck is the hazard's, as before.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const Door := preload("res://game/scripts/door.gd")
const Hazard := preload("res://game/dungeon/hazard.gd")
const WaterSplash := preload("res://game/dungeon/water_splash.gd")
const HazardDeck := preload("res://game/dungeon/hazard_deck.gd")

const GROUP := &"hazard_watch"
const NODE_NAME := "HazardWatch"
const CUE_FALL := &"FallDown"
const CUE_SPLASH := &"WaterSplash"
const WATER_KIND := "water"
## The sinking slime shrinks to this and fades.
const WATER_SCALE := 0.8
const FALL_TURNS := 1.5
const FALL_SINK_PX := 10.0
## A pit drop looks for floor this far down (then up) from where the slime stood, in steps.
const PIT_SEARCH_PX := 192.0
const PIT_SEARCH_STEP := 8.0
const WEAPON_PREFIX := "hazard-"

## The slime fell into the void or into deep water. Payload: {"kind", "x", "y"} (where it fell).
signal fell(payload: Dictionary)
## The slime was put back after a fall. Payload: {"x", "y"} (its centre).
signal returned(payload: Dictionary)
## A hazard hit the slime. Payload: {"kind", "damage"}.
signal hurt(payload: Dictionary)

static var _watches: Dictionary = {}

var _world_root: Node
var _safe_centre := Vector2.INF
var _falling := false
var _fall_kind := ""
var _fall_hazard: Hazard
var _fall_ends_ms := 0.0
var _fall_from := Vector2.ZERO
## The decks whose passages it opens (`queue_passages`): instance id -> {"deck": Node, "open": bool
## (its cells are in the passages)}.
var _decks: Dictionary = {}
## The passages it opened, per level: level -> Array[Rect2] (world).
var _opened: Dictionary = {}
var _source_area: Area2D
## The fall's look (on the player's art): stopped as the slime lands, so a tween that runs on in real
## time never hides the slime put back on the rim.
var _fall_tween: Tween


## The watch of `from`'s world, made (and added to its world's root) when there is none yet.
static func ensure(from: Node) -> HazardWatch:
	var root := _world_root_of(from)
	if root == null:
		return null
	var key := root.get_instance_id()
	var found: Variant = _watches.get(key)
	if is_instance_valid(found) and found is HazardWatch:
		return found as HazardWatch
	var watch: HazardWatch = (load("res://game/dungeon/hazard_watch.gd") as GDScript).new()
	watch.name = NODE_NAME
	watch.set(&"_world_root", root)
	_watches[key] = watch
	root.add_child.call_deferred(watch)
	return watch


## Queues the passages of `deck` over elevation holes (opened once the world is registered).
static func open_passages_for(deck: Node) -> void:
	var watch := ensure(deck)
	if watch != null:
		watch.queue_passages(deck)


## The watch's world: the scene root holding the `world-definition` node above `from`.
static func _world_root_of(from: Node) -> Node:
	var at := from
	while at != null:
		if at.get_node_or_null(^"world-definition") != null:
			return at
		at = at.get_parent()
	return from.get_parent() if from != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_source_area = Area2D.new()
	_source_area.name = "HazardSource"
	_source_area.monitoring = false
	_source_area.monitorable = false
	_source_area.collision_layer = 0
	_source_area.collision_mask = 0
	add_child(_source_area)
	_sync_passages.call_deferred()


func _exit_tree() -> void:
	if _world_root != null and _watches.get(_world_root.get_instance_id()) == self:
		_watches.erase(_world_root.get_instance_id())


## True while the slime falls.
func is_falling() -> bool:
	return _falling


## The last safe ground (the slime's centre there), INF when none yet.
func safe_centre() -> Vector2:
	return _safe_centre


## Adds `deck` to the decks whose passages it opens (while they hold).
func queue_passages(deck: Node) -> void:
	if not deck.has_method(&"deck_rects"):
		return
	if not _decks.has(deck.get_instance_id()):
		_decks[deck.get_instance_id()] = {"deck": deck, "open": false}
	if is_inside_tree():
		_sync_passages.call_deferred()


## Opens the passages of the decks that hold and closes those of the decks that no longer do (each
## physics step): the cells of the holding decks of each level, merged (`merged_rects`), are the
## passages of that level; only the rectangles that changed are opened or closed.
func _sync_passages() -> void:
	var world := Services.world()
	if _decks.is_empty() or world == null or world.elevation == null or not is_instance_valid(world.elevation) \
			or not _mine(world.elevation):
		return
	var changed := false
	for id: int in _decks.keys():
		var entry: Dictionary = _decks[id]
		var deck: Node = entry["deck"]
		if not is_instance_valid(deck) or not deck.is_inside_tree():
			_decks.erase(id)
			changed = changed or bool(entry["open"])
			continue
		var holds := bool(deck.call(&"holds"))
		if holds == bool(entry["open"]) or (not holds and _in_the_way(world, deck)):
			continue
		entry["open"] = holds
		changed = true
	if changed:
		_apply_passages(world)


## True while the slime's body, on `deck`'s level, overlaps the deck or a tile round it: closing the
## deck's cells now would put the floor's rim back across it.
func _in_the_way(world: Node, deck: Node) -> bool:
	var body: CharacterBody2D = world.player_body
	if body == null or not is_instance_valid(body) or world.elevation.level_of(body) != int(deck.call(&"deck_level")):
		return false
	var body_rect := Door._body_rect(body)
	var margin := float(world.elevation.cell) * 0.25
	for rect: Rect2 in deck.call(&"deck_rects"):
		if rect.grow(margin).intersects(body_rect):
			return true
	return false


## Opens the passages of the open decks' cells and closes the ones no deck covers any more.
func _apply_passages(world: Node) -> void:
	var elevation: Node = world.elevation
	var cell := float(elevation.cell)
	var by_level: Dictionary = {}
	for entry: Dictionary in _decks.values():
		if not bool(entry["open"]):
			continue
		var deck: Node = entry["deck"]
		var cells: Dictionary = by_level.get_or_add(int(deck.call(&"deck_level")), {})
		for rect: Rect2 in deck.call(&"deck_rects"):
			for y in range(floori(rect.position.y / cell), ceili(rect.end.y / cell)):
				for x in range(floori(rect.position.x / cell), ceili(rect.end.x / cell)):
					cells[Vector2i(x, y)] = true
	var wanted: Dictionary = {}
	for level: int in by_level:
		var rects: Array[Rect2] = []
		for rect: Rect2i in merged_rects(by_level[level]):
			rects.append(Rect2(Vector2(rect.position) * cell, Vector2(rect.size) * cell))
		wanted[level] = rects
	for level: int in _opened:
		for rect: Rect2 in _opened[level]:
			if not (wanted.get(level, []) as Array).has(rect):
				elevation.close_passage(rect, level)
	for level: int in wanted:
		for rect: Rect2 in wanted[level]:
			if not (_opened.get(level, []) as Array).has(rect):
				elevation.open_passage(rect, level)
	_opened = wanted


## The cells (a set of Vector2i) as few rectangles: runs along each row, stacked where the rows
## below have the same run.
static func merged_rects(cells: Dictionary) -> Array[Rect2i]:
	var rows: Array = []
	for c: Vector2i in cells:
		if not rows.has(c.y):
			rows.append(c.y)
	rows.sort()
	var out: Array[Rect2i] = []
	var open: Dictionary = {}
	for y: int in rows:
		var xs: Array = []
		for c: Vector2i in cells:
			if c.y == y:
				xs.append(c.x)
		xs.sort()
		var row_runs: Array[Vector2i] = []
		var start: int = xs[0]
		var last: int = xs[0]
		for i in range(1, xs.size()):
			if int(xs[i]) == last + 1:
				last = xs[i]
				continue
			row_runs.append(Vector2i(start, last))
			start = xs[i]
			last = xs[i]
		row_runs.append(Vector2i(start, last))
		var next_open: Dictionary = {}
		for run: Vector2i in row_runs:
			if open.has(run) and (open[run] as Rect2i).end.y == y:
				var grown: Rect2i = open[run]
				grown.size.y += 1
				next_open[run] = grown
			else:
				next_open[run] = Rect2i(run.x, y, run.y - run.x + 1, 1)
		for run: Vector2i in open:
			if not next_open.has(run) or (next_open[run] as Rect2i).position != (open[run] as Rect2i).position:
				out.append(open[run])
		open = next_open
	for run: Vector2i in open:
		out.append(open[run])
	return out


func _physics_process(_delta: float) -> void:
	_sync_passages()
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player) or world.player_body == null:
		return
	var player: Node = world.player
	var body := world.player_body
	if _falling:
		if Services.now_ms() >= _fall_ends_ms:
			_land(player, body)
		return
	if bool(player.call(&"is_dead")) or bool(player.call(&"is_airborne")) or bool(player.call(&"is_on_stairs")):
		return
	var level := world.elevation.level_of(body) if world.elevation != null and is_instance_valid(world.elevation) else 0
	var body_rect := Door._body_rect(body)
	# where it stands over a hazard: the middle of its footprint, not its feet (the footprint's front
	# edge), so it is the same walking either way across a bridge
	var middle := body_rect.get_center()
	var held_by: Node = null
	# Whether the body is on a deck that is not safe ground (a slab, standing or fallen).
	var on_loose := false
	for deck: Node in get_tree().get_nodes_in_group(HazardDeck.GROUP):
		if not _mine(deck):
			continue
		var touching := false
		for rect: Rect2 in deck.call(&"deck_rects"):
			if rect.intersects(body_rect):
				touching = true
				break
		if touching and not bool(deck.call(&"is_safe_ground")):
			on_loose = true
		if not bool(deck.call(&"holds")):
			continue
		# a deck is touched from its own level only (a slime in the pit under a bridge never cracks it)
		if touching and int(deck.call(&"deck_level")) == level:
			deck.call(&"touch")
		if held_by == null and bool(deck.call(&"holds_at", middle)) and int(deck.call(&"deck_level")) <= level:
			held_by = deck
	var in_any := false
	var body_over := false
	for node: Node in get_tree().get_nodes_in_group(Hazard.GROUP):
		var hazard := node as Hazard
		if hazard == null or not _mine(hazard):
			continue
		# over the cells it covers (not merely its rectangle: R7's spikes cover the whole room)
		if not body_over and hazard.rect().intersects(body_rect):
			for corner: Vector2 in [body_rect.position, Vector2(body_rect.end.x, body_rect.position.y), body_rect.end,
					Vector2(body_rect.position.x, body_rect.end.y), body_rect.get_center()]:
				if hazard.covers(corner):
					body_over = true
					break
		# a hazard catches only on the sunken cells painted under it (the paint is the pit; its
		# rectangle may be bigger)
		if not hazard.covers(middle):
			continue
		# A form that swims (the Frog) swims in deep water: it never falls in.
		if hazard.kind == WATER_KIND and _swims(player):
			continue
		in_any = true
		# one hazard per floor level: a body above its rim (a bridge over it, a higher floor inside its
		# rectangle) is never in it
		if level > hazard.rim():
			continue
		var dropped_in := level < hazard.rim()
		if not dropped_in and held_by != null:
			continue
		_hit(hazard, player, body, level, dropped_in)
		return
	# Safe ground, where a fall puts the slime back: its whole body clear of every slab, and either
	# the middle of its body on a safe deck or its body clear of every hazard's cells (so it is never put back half on
	# the bridge it fell from, touching a slab that would give again).
	if on_loose:
		return
	if held_by != null:
		if bool(held_by.call(&"is_safe_ground")):
			_safe_centre = player.call(&"get_centre")
	elif not in_any and not body_over:
		_safe_centre = player.call(&"get_centre")


func _mine(node: Node) -> bool:
	return _world_root != null and is_instance_valid(_world_root) and _world_root.is_ancestor_of(node)


func _hit(hazard: Hazard, player: Node, body: CharacterBody2D, level: int, dropped_in: bool) -> void:
	if hazard.kind == "void":
		_start_fall(hazard, player, "void", DungeonState.number("void.fallMs", 600.0))
		return
	if hazard.kind == WATER_KIND:
		_start_fall(hazard, player, WATER_KIND, DungeonState.number("water.fallMs", 650.0))
		return
	var world := Services.world()
	if not dropped_in and world.elevation != null and is_instance_valid(world.elevation) and hazard.rim() > hazard.floor_level():
		# A slab gone from under it over a sunken pit: it drops in first.
		_start_fall(hazard, player, "pit", DungeonState.number(hazard.kind + ".fallMs", 320.0))
		return
	_damage(hazard, player, body)


func _start_fall(hazard: Hazard, player: Node, kind: String, ms: float) -> void:
	_falling = true
	_fall_kind = kind
	_fall_hazard = hazard
	_fall_ends_ms = Services.now_ms() + ms
	_fall_from = player.call(&"get_centre")
	player.call(&"stop_movement")
	player.call(&"suppress_movement", ms + 80.0)
	var feel := Services.feel()
	var water := kind == WATER_KIND
	if feel != null:
		feel.audio_cue(CUE_SPLASH if water else CUE_FALL)
	if kind == "void" or water:
		fell.emit({"kind": hazard.kind, "x": _fall_from.x, "y": _fall_from.y})
	if water:
		_sink(player, ms)
		return
	var tween: Tween = player.call(&"effect_tween")
	_fall_tween = tween
	if tween == null:
		return
	var seconds := maxf(ms, 1.0) / 1000.0
	var void_fall := kind == "void"
	tween.set_parallel(true)
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(player):
			return
		player.call(&"set_effect_offset", Vector2(0.0, FALL_SINK_PX * t))
		var size := lerpf(1.0, 0.0 if void_fall else 0.7, t)
		player.call(&"set_effect_scale", Vector2(size, size))
		if void_fall:
			player.call(&"set_effect_alpha", lerpf(1.0, 0.0, t * t)), 0.0, 1.0, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var visual: Node2D = player.call(&"get_visual")
	if void_fall and visual != null:
		tween.tween_property(visual, "rotation", TAU * FALL_TURNS, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Into deep water: a splash at its feet, and it sinks (down, a little smaller, fading out).
func _sink(player: Node, ms: float) -> void:
	var world := Services.world()
	var feet: Vector2 = world.player_body.global_position if world != null and world.player_body != null else _fall_from
	WaterSplash.spawn(feet, DungeonState.number("plank.ringRadiusPx", 46.0), DungeonState.number("water.splashRingMs", 900.0),
		int(DungeonState.number("plank.rings", 3.0)))
	var tween: Tween = player.call(&"effect_tween")
	_fall_tween = tween
	if tween == null:
		return
	var sink_px := DungeonState.number("water.sinkPx", 14.0)
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(player):
			return
		player.call(&"set_effect_offset", Vector2(0.0, sink_px * t))
		var size := lerpf(1.0, WATER_SCALE, t)
		player.call(&"set_effect_scale", Vector2(size, size))
		player.call(&"set_effect_alpha", lerpf(1.0, 0.0, t)), 0.0, 1.0, maxf(ms, 1.0) / 1000.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## True when the slime's current form swims (it is let into deep water).
func _swims(player: Node) -> bool:
	if not player.has_method(&"current_form"):
		return false
	var form: Variant = player.call(&"current_form")
	return form is Dictionary and bool((form as Dictionary).get("swims", false))


func _land(player: Node, body: CharacterBody2D) -> void:
	_falling = false
	if _fall_tween != null and _fall_tween.is_valid():
		_fall_tween.kill()
	_fall_tween = null
	player.call(&"reset_effects")
	var visual: Node2D = player.call(&"get_visual")
	if visual != null:
		visual.rotation = 0.0
	var world := Services.world()
	var elevation: Node = world.elevation if world.elevation != null and is_instance_valid(world.elevation) else null
	var hazard := _fall_hazard
	if _fall_kind == "pit":
		if elevation != null and hazard != null and is_instance_valid(hazard):
			var floor_level := hazard.floor_level()
			var spot := _floor_near(elevation, body.global_position, floor_level)
			if spot.is_finite():
				elevation.call(&"track", body, floor_level)
				body.global_position = spot
				body.reset_physics_interpolation()
				return
			# no floor of the pit within reach (only wall faces under where it fell, as under a bridge
			# between two raised floors' faces): put back on the rim it fell from, as from the void
		else:
			return
	var back := return_point(hazard)
	player.call(&"teleport", back)
	if elevation != null:
		elevation.call(&"track", body)
	returned.emit({"x": back.x, "y": back.y})
	if hazard != null and is_instance_valid(hazard):
		_damage(hazard, player, body)


## Where a fall from `hazard` puts the slime back: its `fixed_return` spot when it has one; else its
## return point nearest the last safe ground (or
## the spot it fell from), else that ground, else the spot it fell from.
func return_point(hazard: Hazard) -> Vector2:
	if hazard != null and is_instance_valid(hazard) and not hazard.fixed_return.is_empty():
		var fixed := hazard.get_node_or_null(hazard.fixed_return) as Node2D
		if fixed != null:
			return fixed.global_position
	var near := _safe_centre if _safe_centre.is_finite() else _fall_from
	var spots: Array[Vector2] = hazard.return_spots() if hazard != null and is_instance_valid(hazard) else []
	if not spots.is_empty():
		var best := spots[0]
		for spot: Vector2 in spots:
			if spot.distance_squared_to(near) < best.distance_squared_to(near):
				best = spot
		return best
	return near


func _floor_near(elevation: Node, feet: Vector2, floor_level: int) -> Vector2:
	var step := 0.0
	while step <= PIT_SEARCH_PX:
		for sign_y: float in [1.0, -1.0]:
			var point := feet + Vector2(0.0, step * sign_y)
			# the whole body on that floor (never on the wall face over it)
			if bool(elevation.call(&"body_fits", point, floor_level)):
				return point
		step += PIT_SEARCH_STEP
	return Vector2.INF


func _damage(hazard: Hazard, player: Node, _body: CharacterBody2D) -> void:
	var router := Services.router()
	var target: Area2D = player.call(&"get_damage_area")
	if router == null or target == null or _source_area == null:
		return
	var amount := hazard.hit_damage()
	var centre: Vector2 = player.call(&"get_centre")
	var activation := router.begin_activation(self, [_source_area])
	var result := router.route({
		"activation_id": activation,
		"source": self,
		"attack_area": _source_area,
		"target_area": target,
		"weapon_id": WEAPON_PREFIX + hazard.kind,
		"weapon_tags": ["hazard", hazard.kind],
		"damage_types": ["physical"],
		"base_damage": amount,
		"true_damage": true,
		"effects": [],
		"impact": {"position": centre, "knock": Vector2.ZERO},
	})
	router.end_activation(activation)
	if str(result.get("status", "")) == "accepted":
		hurt.emit({"kind": hazard.kind, "damage": float(result.get("actual_damage", amount))})

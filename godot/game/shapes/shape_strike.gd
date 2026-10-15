extends RefCounted
## Delivers the shapes' hits (body-shapes plan section 3 "Reach / area" and "Walls"; combat-feel plan
## sections 3 "What every hit carries", 4 and 6; BODY_SHAPES.md "The hit" and "Juice").
##
## - The areas, rotated to the aim and placed at the slime's centre (`area_shapes`): the Spear's line
##   (`minReach`..`reach` x `width`, `sidePx` beside the aim line for the second jab; on the Spear's
##   strike frames, game/shapes/shape_strikes.gd, from the full-lean frame's socket, where the drawn
##   spear leaves the body, to `reach` along the aim, where its tip is at full reach), shortened by a
##   wall ray (`wall_reach`: cast from the feet, where walls and prop footprints lie; it ignores
##   water, enemies, NPCs and any body with a hurtbox, such as a training dummy, a tree or a rock, so
##   the line reaches the body it stabs);
##   the Axe's arc (`arcDeg`, `radius`), swept so far (`progress`), as wedges of at most 60 deg (its
##   chop's whole sector at once; the Spin's full circle swept round from the aim); the
##   Hammer's circle `offset` px ahead (`radius`), with its ring (`ringHit`, the Quake's `cracks`)
##   around the head's impact.
## - The hurtboxes in an area (`targets_in`: registered receivers, the slime's own excluded, one entry
##   per receiver).
## - One request per target (`deliver`): `request_for` with the hit at the top level and the
##   `impact` effect (HitReaction.attach), the old fields (`weapon_id` = the shape id, `weapon_tags`
##   = the hit's tags plus the shape's harvest tags, ShapeDefs.request_tags), routed through
##   DamageRouter with an activation of the slime's ShapeHitbox (`hitbox_of`).
## - The swing's feel (`feel_swing`), read from each `result.reaction`: GameFeel.play_hit once per
##   swing (HitJuice.swing_spec: the hit-stop with its extra-target share, the trauma and kick of a
##   finisher), sparks and a number per target; a clink (the wrong tool, a shut weak point) plays its
##   high tick, its short freeze and its few white sparks (HitJuice.clink_spec), and the caller
##   recoils the slime and ends the chain.
##
## The shape controller calls the pieces step by step (one activation per step, each receiver once per
## step); `strike` is the one-shot form (the whole area at once). Only the shapes module calls it.
##
## Owner: shapes.

const Services := preload("res://game/shared/services.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapeStrikes := preload("res://game/shapes/shape_strikes.gd")
const PlayerScript := preload("res://game/scripts/player.gd")

const DAMAGE_TYPES: Array[String] = ["physical"]

## The slime's activation token (an Area2D without shapes under its body, as the Slam's SlamArea):
## DamageRouter wants an attack area per activation; the shapes query the space themselves.
const HITBOX_NAME := "ShapeHitbox"
const HITBOX_META := &"shape_hitbox"
## Physics layer names (project.godot `layer_names/2d_physics`).
const LAYER_HURTBOX := "hurtbox"
const LAYER_ENEMY := "enemy"
const LAYER_NPC := "npc"
const LAYER_WATER := "water"
const LAYER_PLAYER := "player"
## Results per query shape.
const MAX_RESULTS := 32
## The wall ray looks past at most this many bodies with a hurtbox before it gives up (no wall).
const WALL_RAY_TRIES := 4
## An arc is queried as wedges of at most this many degrees (each a convex polygon), with this many
## points on each wedge's rim.
const WEDGE_MAX_DEG := 60.0
const WEDGE_RIM_POINTS := 6
## The least share of an arc's sweep a query covers (its first active frame is never empty).
const MIN_SWEEP_SHARE := 0.05
## Router reasons (damage_resolver.gd) and the target tag of resources.
const REASON_IMMUNE := "immune"
const REASON_SOURCE_BLOCKED := "source-blocked"
const REASON_STATE_BLOCKED := "state-blocked"
const RESOURCE_TAG := "resource"
const STATUS_ACCEPTED := "accepted"
## Cues (audio.global): the dry clink, a plain hit until the juice module gives each shape its own,
## and the crit sting (played on a real hit, once per swing).
const CUE_CLINK := &"HitBlocked"
const CUE_HIT := &"HitDull"
const CUE_CRIT := &"Crit"


## The `hit` of chain step `step` (its numbers, as in `shapes.<name>.chain`) of shape `shape_id`:
## `step_number` 1-3 (0 for a charge), `last` true on the chain's last step or a charge's last tick,
## `hold_ms` from the hold formula (combat-feel plan section 4), `knock` the push's unit direction.
## A step's own `tier` / `poise` override the class's.
static func make_hit(shape_id: StringName, step: Dictionary, step_number: int, last: bool, hold_ms: float,
		knock: Vector2) -> Dictionary:
	var fields := {
		"step": step_number,
		"last": last,
		"shape": ShapeDefs.short_name(shape_id),
		"tags": ShapeDefs.tags(shape_id),
		"hold_ms": hold_ms,
		"launch_speed": float(step.get("launchSpeed", 0.0)),
		"hop_px": float(step.get("hopPx", 0.0)),
		"knock": knock.normalized() if knock != Vector2.ZERO else Vector2.ZERO,
	}
	for key: String in ["tier", "poise"]:
		if step.has(key):
			fields[key] = int(step[key])
	return HitReaction.build_hit(str(step.get("class", "tap")), fields)


## The DamageRouter request for one target of a shape hit (`source` the PlayerScript).
static func request_for(source: Object, shape_id: StringName, hit: Dictionary, attack_area: Area2D,
		target_area: Area2D, activation_id: int, damage: float, impact_position: Vector2) -> Dictionary:
	var request := {
		"activation_id": activation_id,
		"source": source,
		"attack_area": attack_area,
		"target_area": target_area,
		"weapon_id": String(shape_id),
		"weapon_tags": (hit.get("tags", []) as Array).duplicate(),
		"damage_types": DAMAGE_TYPES.duplicate(),
		"base_damage": maxf(0.0, damage),
		"effects": [],
		"impact": {"position": impact_position, "knock": hit.get("knock", Vector2.ZERO)},
	}
	return HitReaction.attach(request, hit)


# --- the slime's token and the walls ---------------------------------------------------------------

## The slime's ShapeHitbox (made, under its body, on first use; no shapes, no layers: DamageRouter
## only needs an attack area for its activations). Null without a body.
static func hitbox_of(player: Node) -> Area2D:
	var slime := player as PlayerScript
	if slime == null or slime.body == null or not is_instance_valid(slime.body):
		return null
	var body := slime.body
	if body.has_meta(HITBOX_META):
		var known: Variant = body.get_meta(HITBOX_META)
		if known is Area2D and is_instance_valid(known):
			return known
	var area := Area2D.new()
	area.name = HITBOX_NAME
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	body.set_meta(HITBOX_META, area)
	body.add_child.call_deferred(area)
	return area


## The bit of the physics layer project.godot names `layer_name`; 0 when none is.
static func layer_bit(layer_name: String) -> int:
	for i in range(1, 33):
		if str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % i, "")) == layer_name:
			return 1 << (i - 1)
	return 0


## How far the Spear's line reaches along `aim` before a wall (body-shapes plan section 3 "Walls"): a
## ray against what blocks the slime's body (its mask: the world and its own height level's cliffs),
## without enemies, NPCs and water, cast from the slime's feet moved by `shift` (the hit centre,
## `hit_offset`; walls, cliff outlines and prop footprints lie on the ground plane) and passing through
## any body that owns a registered hurtbox (a training dummy, a tree, a rock: the line must reach the
## body it stabs); `reach` when nothing is in the way. The line itself runs from `_origin` (the centre)
## moved the same way, parallel to the ray, so the distance along the aim is the same.
static func wall_reach(player: Node, _origin: Vector2, aim: Vector2, reach: float, shift: Vector2 = Vector2.ZERO) -> float:
	var slime := player as PlayerScript
	if slime == null or slime.body == null or not slime.body.is_inside_tree() or aim == Vector2.ZERO or reach <= 0.0:
		return reach
	var mask := slime.body.collision_mask & ~(layer_bit(LAYER_ENEMY) | layer_bit(LAYER_NPC)
		| layer_bit(LAYER_WATER) | layer_bit(LAYER_PLAYER))
	if mask == 0:
		return reach
	var space := slime.body.get_world_2d().direct_space_state
	var from := slime.body.global_position + shift
	var to := from + aim.normalized() * reach
	var exclude := slime.body_rids()
	var query := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for _try in WALL_RAY_TRIES:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return reach
		if _owns_hurtbox(hit.get("collider")):
			exclude.append(hit.get("rid"))
			# The getter hands out a copy: set the list again.
			query.exclude = exclude
			continue
		return minf(reach, from.distance_to(hit.get("position", to)))
	return reach


## True when `node` (a body the wall ray met) has an Area2D child registered with DamageRouter (it
## can be hit, so it is a target, not a wall).
static func _owns_hurtbox(node: Variant) -> bool:
	var router := Services.router()
	if router == null or not (node is Node) or not is_instance_valid(node):
		return false
	for child: Node in (node as Node).get_children():
		if child is Area2D and router.receiver_for_area(child as Area2D) != null:
			return true
	return false


# --- areas -----------------------------------------------------------------------------------------

## Where a step's hit is measured from, px from the slime's centre: its `ShapeStrikes.HIT_CENTER_KEY` (a chain
## step's strike file's `hit_center`), else the centre itself.
static func hit_offset(data: Dictionary) -> Vector2:
	var offset: Variant = data.get(ShapeStrikes.HIT_CENTER_KEY)
	return offset if offset is Vector2 else Vector2.ZERO


## Where an impact lands: `offset` px ahead of the hit centre (`origin` moved by `hit_offset`) along `aim` (the
## Hammer's head); the hit centre for a step without an offset.
static func impact_centre(data: Dictionary, origin: Vector2, aim: Vector2) -> Vector2:
	return origin + hit_offset(data) + aim * ShapeDefs.num(data, "offset")


## The query shapes of `data`'s area from `origin` toward `aim` (unit): [{"shape": Shape2D,
## "transform": Transform2D}]. `reach` is the line's reach (wall-shortened; ignored for other kinds),
## `progress` how much of an arc is swept (0..1, from its start side; a chop's whole sector at once;
## a full circle from the aim round), `sweep_sign` +1 for a sweep that runs clockwise on screen, -1
## the other way (it also picks the side of a line's `sidePx`). A line whose `data` carries
## `ShapeStrikes.LINE_FROM_KEY` (the shape controller adds it while the Spear's strike frames show)
## starts there instead, px from `origin` (the full-lean frame's socket), and runs along the aim to
## `reach` measured along it (where the drawn spear's tip is at full reach), with no `sidePx`: the art
## decides where the spear leaves the body. Its near end comes back along the aim to `minReach` (it
## keeps the socket's offset across the aim), so a target pressed against the slime's front is hit.
## Every kind is measured from the hit centre: `origin` moved by `hit_offset(data)`.
static func area_shapes(data: Dictionary, origin: Vector2, aim: Vector2, reach: float, sweep_sign: float,
		progress: float = 1.0) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	if aim == Vector2.ZERO:
		return shapes
	var unit := aim.normalized()
	var centre := origin
	origin += hit_offset(data)
	match ShapeDefs.area_kind(data):
		ShapeDefs.AREA_LINE:
			var width := ShapeDefs.num(data, "width")
			var line_from: Variant = data.get(ShapeStrikes.LINE_FROM_KEY)
			if line_from is Vector2:
				var start: Vector2 = line_from
				start -= unit * maxf(0.0, start.dot(unit) - ShapeDefs.num(data, "minReach"))
				var length := reach - start.dot(unit)
				if length <= 0.0 or width <= 0.0:
					return shapes
				var spear := RectangleShape2D.new()
				spear.size = Vector2(length, width)
				shapes.append({"shape": spear, "transform": Transform2D(unit.angle(), origin + start + unit * length * 0.5)})
				return shapes
			var near := ShapeDefs.num(data, "minReach")
			if reach <= near or width <= 0.0:
				return shapes
			var rect := RectangleShape2D.new()
			rect.size = Vector2(reach - near, width)
			# Beside the aim line (the second jab), across it on the sweep sign's side, as ShapeVisuals draws it.
			var beside := Vector2(-unit.y, unit.x) * ShapeDefs.side_px(data) * sweep_sign
			shapes.append({"shape": rect, "transform": Transform2D(unit.angle(), origin + beside + unit * (near + reach) * 0.5)})
		ShapeDefs.AREA_ARC:
			var radius := ShapeDefs.num(data, "radius")
			var arc := deg_to_rad(ShapeDefs.num(data, "arcDeg"))
			if radius <= 0.0 or arc <= 0.0:
				return shapes
			if arc >= TAU:
				if progress >= 1.0:
					shapes.append(_circle(origin, radius))
					return shapes
				# The Spin: round from the aim, as far as the head has turned (as ShapeVisuals draws it).
				var turned := TAU * clampf(progress, MIN_SWEEP_SHARE, 1.0)
				var begin := unit.angle()
				var end := begin + sweep_sign * turned
				shapes.append_array(_wedges(origin, radius, minf(begin, end), maxf(begin, end)))
				return shapes
			# A chop lands on its whole sector at once; a sweep covers what it has swept.
			var share := 1.0 if ShapeDefs.is_chop(data) else clampf(progress, MIN_SWEEP_SHARE, 1.0)
			var start := unit.angle() - sweep_sign * arc * 0.5
			var finish := start + sweep_sign * arc * share
			shapes.append_array(_wedges(origin, radius, minf(start, finish), maxf(start, finish)))
		ShapeDefs.AREA_CIRCLE:
			var radius := ShapeDefs.num(data, "radius")
			if radius > 0.0:
				shapes.append(_circle(impact_centre(data, centre, unit), radius))
	return shapes


## The query shape of a ring hit (`ring`: {radius, ...}) around `centre`.
static func ring_shapes(ring: Dictionary, centre: Vector2) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var radius := ShapeDefs.num(ring, "radius")
	if radius > 0.0:
		shapes.append(_circle(centre, radius))
	return shapes


## Every monitorable hurtbox that meets one of `shapes`, the slime's own excluded.
static func areas_in(player: Node, shapes: Array[Dictionary]) -> Array[Area2D]:
	var areas: Array[Area2D] = []
	var slime := player as PlayerScript
	if slime == null or slime.body == null or not slime.body.is_inside_tree() or shapes.is_empty():
		return areas
	var mask := layer_bit(LAYER_HURTBOX)
	if mask == 0:
		return areas
	var space := slime.body.get_world_2d().direct_space_state
	var exclude: Array[RID] = []
	var own := slime.get_damage_area()
	if own != null and is_instance_valid(own):
		exclude.append(own.get_rid())
	var seen: Dictionary = {}
	for entry: Dictionary in shapes:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = entry["shape"]
		query.transform = entry["transform"]
		query.collision_mask = mask
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.exclude = exclude
		for found: Dictionary in space.intersect_shape(query, MAX_RESULTS):
			var area := found.get("collider") as Area2D
			if area == null or not area.monitorable or seen.has(area.get_instance_id()):
				continue
			seen[area.get_instance_id()] = true
			areas.append(area)
	return areas


## Where a hit on hurtbox `area` lands: its first enabled shape's centre (the dummy's DamageShape
## sits 46 px above its root, Fatty's Eye shape 33 px off its area), else the area's origin.
static func hurtbox_point(area: Area2D) -> Vector2:
	if area == null or not is_instance_valid(area):
		return Vector2.ZERO
	for child: Node in area.get_children():
		var shape := child as CollisionShape2D
		if shape != null and not shape.disabled:
			return shape.global_position
	return area.global_position


## The targets in `shapes`: one {"area", "receiver", "tags", "position"} per registered receiver (its
## first hurtbox found), never the slime itself. `position` is the hurtbox's centre (`hurtbox_point`:
## the hit, its knock, sparks, debris and number land there, as the old weapon's).
static func targets_in(player: Node, shapes: Array[Dictionary]) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var router := Services.router()
	if router == null:
		return targets
	var receivers: Dictionary = {}
	for area: Area2D in areas_in(player, shapes):
		var receiver := router.receiver_for_area(area)
		if receiver == null or receiver == player or receivers.has(receiver.get_instance_id()):
			continue
		receivers[receiver.get_instance_id()] = true
		targets.append({"area": area, "receiver": receiver, "tags": router.tags_for_area(area),
			"position": hurtbox_point(area)})
	return targets


## The push of a hit on a target at `to` (combat-feel plan section 3 "knock"): "aim" along the aim;
## "sweep" along the arc's tangent at the target, the way the sweep runs; "radial" away from `from`
## (the slime, or the Hammer's impact), the aim when the target sits on it.
static func knock_for(mode: String, aim: Vector2, from: Vector2, to: Vector2, sweep_sign: float) -> Vector2:
	var unit := aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	match mode:
		ShapeDefs.KNOCK_SWEEP:
			var out := to - from
			if out == Vector2.ZERO:
				return unit
			return out.normalized().rotated(sweep_sign * PI * 0.5)
		ShapeDefs.KNOCK_RADIAL:
			var away := to - from
			return away.normalized() if away.length_squared() > 1.0 else unit
	return unit


## The damage of a hit of `scale` (a step's or a ring's `damageScale`) on a target with
## `target_tags`, with the swing's crit factor.
static func damage_for(shape_id: StringName, scale: float, crit_factor: float, target_tags: Array) -> float:
	return ShapeDefs.damage(shape_id, scale) * crit_factor * ShapeDefs.target_modifier(shape_id, target_tags)


## Routes `hit` to `target` (from `targets_in`) in `activation_id` with `damage`. The request's
## `weapon_tags` are the shape's tags plus its harvest tags (the Stone form's iron on the Hammer).
## Returns the outcome {"receiver", "area", "position", "result", "hit", "tags"}.
static func deliver(player: Node, shape_id: StringName, hit: Dictionary, activation_id: int, target: Dictionary,
		damage: float) -> Dictionary:
	var area: Area2D = target.get("area")
	var position: Vector2 = target.get("position", Vector2.ZERO)
	var outcome := {"receiver": target.get("receiver"), "area": area, "position": position, "result": {},
		"hit": hit, "tags": target.get("tags", [])}
	var router := Services.router()
	var hitbox := hitbox_of(player)
	if router == null or hitbox == null or area == null or not is_instance_valid(area):
		return outcome
	var request := request_for(player, shape_id, hit, hitbox, area, activation_id, damage, position)
	var slime := player as PlayerScript
	var form: StringName = slime.current_form_id() if slime != null else &""
	request["weapon_tags"] = ShapeDefs.request_tags(shape_id, form)
	outcome["result"] = router.route(request)
	return outcome


# --- feel ------------------------------------------------------------------------------------------

## True when an outcome is a clink (combat-feel plan sections 3 and 7 rule 9): the receiver refused
## the hit as the wrong tool or a shut weak point (`immune`, `source-blocked`; a resource's harvest
## gate answers `state-blocked`), or its reaction answered `clink`.
static func is_clink(result: Dictionary, resource: bool) -> bool:
	var reaction: Variant = result.get("reaction")
	if reaction is Dictionary and str((reaction as Dictionary).get("verb", "")) == HitReaction.VERB_CLINK:
		return true
	if str(result.get("status", "")) == STATUS_ACCEPTED:
		return false
	var reason := str(result.get("reason", ""))
	if reason == REASON_IMMUNE or reason == REASON_SOURCE_BLOCKED:
		return true
	return resource and reason == REASON_STATE_BLOCKED


## The feel of one batch of `outcomes` of a swing of `data` (its step, charge or tick numbers),
## combat-feel plan section 6: on the swing's first batch with hits (`first`), GameFeel.play_hit with
## the whole spec (the hit-stop once per swing, +`hitStop.extraTargetMs` per extra target, the kill
## bonus, the trauma and kick of a finisher) at the first target; every other target its sparks and
## its number only. A crit makes the numbers big and plays the crit sting once. Resources show their
## own hit. A batch of only clinks plays the clink (HitJuice.clink_spec): its high tick (resources
## play their own), the short freeze, a few white sparks at the tip. Beside the contract's keys the
## spec carries the step's flourishes, "impact_ring" and "thump" (bools), for the juice module.
## Returns {"hits": int (creatures hit), "landed": int (every accepted hit, resources too), "clink":
## bool, "clink_point": Vector2, "killed": bool, "recoil_px": float (the largest slime recoil the
## reactions asked for)}.
static func feel_swing(data: Dictionary, outcomes: Array[Dictionary], first: bool, crit: bool,
		aim: Vector2) -> Dictionary:
	var summary := {"hits": 0, "landed": 0, "clink": false, "clink_point": Vector2.ZERO, "killed": false,
		"recoil_px": 0.0}
	var hits: Array[Dictionary] = []
	var reactions: Array[Dictionary] = []
	var clink_resource := true
	var blocked := false
	var max_damage := 0
	for outcome: Dictionary in outcomes:
		var result: Dictionary = outcome.get("result", {})
		var tags: Array = outcome.get("tags", [])
		var resource := tags.has(RESOURCE_TAG)
		if is_clink(result, resource):
			if not summary["clink"]:
				summary["clink_point"] = outcome.get("position", Vector2.ZERO)
			summary["clink"] = true
			clink_resource = clink_resource and resource
			continue
		if str(result.get("status", "")) != STATUS_ACCEPTED:
			blocked = blocked or (not resource and str(result.get("reason", "")) == REASON_STATE_BLOCKED)
			continue
		summary["landed"] = int(summary["landed"]) + 1
		if resource:
			continue
		hits.append(outcome)
		var reaction: Variant = result.get("reaction")
		if reaction is Dictionary:
			reactions.append(reaction)
			var slime := str((reaction as Dictionary).get("slime", HitReaction.SLIME_NONE))
			if slime != HitReaction.SLIME_NONE and slime != HitReaction.SLIME_PASS:
				summary["recoil_px"] = maxf(float(summary["recoil_px"]), float((reaction as Dictionary).get("recoil_px", 0.0)))
		summary["killed"] = bool(summary["killed"]) or bool(result.get("defeated", false))
		max_damage = maxi(max_damage, int(result.get("actual_damage", 0)))
	summary["hits"] = hits.size()
	var feel := Services.feel()
	if feel == null:
		return summary
	if not hits.is_empty():
		var hit: Dictionary = hits[0].get("hit", {})
		var spec := HitJuice.swing_spec(data, hit, reactions, max_damage, hits.size(), bool(summary["killed"]))
		if str(spec.get("sound_cue", "")).is_empty():
			spec["sound_cue"] = CUE_HIT
		# The step's extra flourishes, for the juice module (the finisher's impact ring and thump).
		spec["impact_ring"] = bool(data.get("impactRing", false))
		spec["thump"] = bool(data.get("thump", false))
		var minor := spec.duplicate()
		for key: String in ["hit_stop_ms", "trauma", "kick_px"]:
			minor[key] = 0.0
		# The swing's sounds play once: the other targets keep their sparks, ring, debris and number.
		minor["sound_cue"] = &""
		minor["material_cue"] = &""
		minor["thump_cue"] = &""
		minor["thump"] = false
		for i in hits.size():
			var outcome := hits[i]
			var one: Dictionary = spec.duplicate() if i == 0 and first else minor.duplicate()
			var result: Dictionary = outcome.get("result", {})
			one.merge(HitJuice.number_spec(int(result.get("actual_damage", 0)), outcome.get("hit", hit)), true)
			if crit:
				one["number_big"] = true
			var knock: Variant = (outcome.get("hit", {}) as Dictionary).get("knock", aim)
			feel.play_hit(one, outcome.get("position", Vector2.ZERO), knock if knock is Vector2 else aim)
		if crit and first:
			feel.audio_cue(CUE_CRIT)
	elif bool(summary["clink"]):
		# HitJuice's clink: the short freeze, a few white sparks and the dry high tick (resources play
		# their own sound).
		var clink := HitJuice.clink_spec()
		if clink_resource:
			clink["sound_cue"] = &""
		feel.play_hit(clink, summary["clink_point"], aim)
	elif blocked:
		# Refused for now (Fatty in the air, a dodging target): the old dry tick, no recoil.
		feel.audio_cue(CUE_CLINK)
	return summary


# --- private ---------------------------------------------------------------------------------------

static func _circle(centre: Vector2, radius: float) -> Dictionary:
	var circle := CircleShape2D.new()
	circle.radius = radius
	return {"shape": circle, "transform": Transform2D(0.0, centre)}


## Convex pie wedges (at most WEDGE_MAX_DEG each) between the angles `from` and `to` (radians,
## from < to) of the circle of `radius` around `centre`.
static func _wedges(centre: Vector2, radius: float, from: float, to: float) -> Array[Dictionary]:
	var wedges: Array[Dictionary] = []
	var span := to - from
	if span <= 0.0:
		return wedges
	var count := maxi(1, ceili(rad_to_deg(span) / WEDGE_MAX_DEG))
	var each := span / float(count)
	for i in count:
		var points := PackedVector2Array([Vector2.ZERO])
		var start := from + each * float(i)
		for j in WEDGE_RIM_POINTS + 1:
			points.append(Vector2.from_angle(start + each * float(j) / float(WEDGE_RIM_POINTS)) * radius)
		var polygon := ConvexPolygonShape2D.new()
		polygon.points = points
		wedges.append({"shape": polygon, "transform": Transform2D(0.0, centre)})
	return wedges

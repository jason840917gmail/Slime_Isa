extends RefCounted
## The body shapes' ids and data (body-shapes plan section 3; combat-feel plan section 4;
## BODY_SHAPES.md "Files and owners"). A shape is a learned ability id (`shape-spear`, `shape-axe`,
## `shape-hammer`, through `RunState.learn_ability`), and its numbers are the `shapes.<name>` block of
## game-constants.json: `id`, `title`, `tags`, `baseDamage`, `aim` ("exact" | "snap8" | "snap4"), `lineCheck`,
## `targetModifiers`, `harvest` (and the Hammer's `harvestStoneForm`), `chain` (steps: id, class,
## windupMs, activeMs, recoveryMs, cancelAtMs, damageScale, launchSpeed, hopPx, stepPx (with
## its `stepFromMs` / `stepToMs` window), the area keys (a line's `sidePx`, an arc's `chop`),
## knockMode, walkCancel, hitStopMs, trauma, kickPx, pitch, sparks, the last step's `anticipation`,
## ...) and `charge` (ringMs, energy, class, its hit numbers; `ticks` for a charge that hits in
## ticks (none since the Spin hits once, owner 2026-10-12), the Quake's `cracks`).
## Damage of a step = baseDamage x (character.player.stats.attack / 10) x damageScale.
##
## Typed reads of the step and charge numbers the shape controller, ShapeStrike and ShapeVisuals
## share: the area kind of a step, its contact frames, the hold formula (combat-feel plan section 4),
## the aim rule (Spear exact, Axe and Hammer snapped to 8 ways), the target modifiers and the harvest
## tags a shape adds to its requests. Plain data: nothing here moves or hits anything.
##
## Owner: shapes.

const Services := preload("res://game/shared/services.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")

const SPEAR := &"shape-spear"
const AXE := &"shape-axe"
const HAMMER := &"shape-hammer"
## Every shape, in switch order (E wraps through the learned ones in this order).
const IDS: Array[StringName] = [SPEAR, AXE, HAMMER]
## Shape id -> its key in `shapes`, which is also the hit's `shape` and `combat.chain.restMs` key.
const NAMES := {SPEAR: "spear", AXE: "axe", HAMMER: "hammer"}
## `combat.chain` (link window, hold formula, charge start, rest, clink, hit-stop rules).
const CHAIN_PATH := "combat.chain"
## The attack stat that scales every shape's damage (attack 10 is neutral, as PlayerCombat).
const STAT_ATTACK := "character.player.stats.attack"
const ATTACK_STAT_BASELINE := 10.0
## The crit roll, once per swing (combat-feel plan section 4).
const STAT_CRIT_CHANCE := "character.player.stats.critChance"
const STAT_CRIT_MULTIPLIER := "character.player.stats.critMultiplier"

## `shapes.<name>.aim`: the Spear aims at the exact angle (inside its 45 deg sector by definition);
## the Axe and the Hammer snap to the nearest of 8 directions.
const AIM_EXACT := "exact"
const AIM_SNAP8 := "snap8"
## Attacks in four directions only (owner, 2026-10-12: the diagonals looked off on every weapon).
const AIM_SNAP4 := "snap4"
## How much more vertical than horizontal a direction must be to snap up or down (an exact diagonal,
## whose parts differ only by float rounding, goes to the side; ShapePoses.DIAGONAL_EPSILON).
const DIAGONAL_EPSILON := 0.001
## The area kinds of a step or a charge (`area_kind`): a line from the slime (`minReach`, `reach`,
## `width`), an arc around it (`arcDeg`, `radius`) or a circle ahead of it (`radius`, `offset`). The chain
## steps' reach (a line's `reach`, an arc's `radius`, a circle's `offset`) is in their strike files
## (StrikeLibrary.chain_hit), not in game-constants.json.
const AREA_LINE := "line"
const AREA_ARC := "arc"
const AREA_CIRCLE := "circle"
const AREA_NONE := ""
## `knockMode`: along the aim, along the sweep (the arc's tangent), or away from the strike's centre.
const KNOCK_AIM := "aim"
const KNOCK_SWEEP := "sweep"
const KNOCK_RADIAL := "radial"
## `sweep` of an arc step: "cw" (screen clockwise: the angle grows) or "ccw".
const SWEEP_CCW := "ccw"
## The prefix of the harvest tags a shape adds to its requests' `weapon_tags`
## (`harvest:<target>:<tier>`, read by resource_node.gd), from `shapes.<name>.harvest` /
## `.harvestStoneForm` (Axe wood 1, Hammer stone 1, and iron 2 in the Stone form).
const HARVEST_PREFIX := "harvest"


static func is_shape(id: StringName) -> bool:
	return NAMES.has(id)


## "spear" | "axe" | "hammer"; "" for anything else.
static func short_name(id: StringName) -> String:
	return str(NAMES.get(id, ""))


## The shape id of a short name ("axe" -> &"shape-axe"); &"" when unknown.
static func id_for(short: String) -> StringName:
	for id: StringName in NAMES:
		if NAMES[id] == short:
			return id
	return &""


## The shape's `shapes.<name>` block ({} when unknown). Shared with GameConstants: never change it.
static func definition(id: StringName) -> Dictionary:
	var constants := Services.constants()
	if constants == null or not is_shape(id):
		return {}
	var block: Variant = constants.value("shapes.%s" % short_name(id), {})
	return block if block is Dictionary else {}


static func title(id: StringName) -> String:
	return str(definition(id).get("title", String(id)))


## The shape's tags as the hit and the request's `weapon_tags` carry them.
static func tags(id: StringName) -> Array[String]:
	var list: Array[String] = []
	var raw: Variant = definition(id).get("tags", [])
	if raw is Array:
		for tag: Variant in raw:
			list.append(str(tag))
	return list


static func base_damage(id: StringName) -> float:
	return float(definition(id).get("baseDamage", 0.0))


## The chain's steps, in order ([] when unknown).
static func chain(id: StringName) -> Array:
	var raw: Variant = definition(id).get("chain", [])
	return raw if raw is Array else []


## Step `index` (0-based) of the chain; {} when out of range.
static func step(id: StringName, index: int) -> Dictionary:
	var steps := chain(id)
	if index < 0 or index >= steps.size() or not steps[index] is Dictionary:
		return {}
	return steps[index]


static func step_count(id: StringName) -> int:
	return chain(id).size()


## The hold-to-charge attack ({} when none).
static func charge(id: StringName) -> Dictionary:
	var raw: Variant = definition(id).get("charge", {})
	return raw if raw is Dictionary else {}


## The Spin's ticks (`charge.ticks`: atMs, damageScale, last, launchSpeed, hitStopMs); [] for a charge
## that hits once.
static func charge_ticks(charge_data: Dictionary) -> Array:
	var raw: Variant = charge_data.get("ticks", [])
	return raw if raw is Array else []


## The rest after the chain's last step (`combat.chain.restMs.<name>`).
static func rest_ms(id: StringName) -> float:
	var constants := Services.constants()
	if constants == null:
		return 0.0
	return float(constants.value("%s.restMs.%s" % [CHAIN_PATH, short_name(id)], 0.0))


## A `combat.chain` number (e.g. "linkMs", "holdCapMs", "clink.recoilPx").
static func chain_number(key: String) -> float:
	var constants := Services.constants()
	return constants.number("%s.%s" % [CHAIN_PATH, key]) if constants != null else 0.0


## A step's damage before crits and target modifiers: baseDamage x attack / 10 x `scale`.
static func damage(id: StringName, scale: float) -> float:
	var constants := Services.constants()
	var attack := constants.number(STAT_ATTACK) if constants != null else ATTACK_STAT_BASELINE
	return base_damage(id) * (attack / ATTACK_STAT_BASELINE) * scale


# --- typed step numbers ----------------------------------------------------------------------------

## A number of a step, a charge or a tick (`fallback` when absent or not a number).
static func num(data: Dictionary, key: String, fallback: float = 0.0) -> float:
	var raw: Variant = data.get(key, fallback)
	return float(raw) if (raw is float or raw is int) else fallback


## A step's whole length: wind-up + active + recovery.
static func length_ms(data: Dictionary) -> float:
	return num(data, "windupMs") + num(data, "activeMs") + num(data, "recoveryMs")


## The step's cancel point (`cancelAtMs`; the chain's last step: its whole length, then the rest).
static func cancel_ms(data: Dictionary) -> float:
	return num(data, "cancelAtMs", length_ms(data))


## True when the slime may walk out of the step from its cancel point (steps 1-2).
static func walk_cancel(data: Dictionary) -> bool:
	return bool(data.get("walkCancel", false))


## When the slime's forward step (`stepPx`) starts, ms after the step starts (`stepFromMs`, default
## 0: the Hammer steps into its swing, a finisher after its pull-back).
static func step_from_ms(data: Dictionary) -> float:
	return num(data, "stepFromMs")


## When the slime's forward step ends (`stepToMs`, default the end of the active window).
static func step_to_ms(data: Dictionary) -> float:
	return num(data, "stepToMs", num(data, "windupMs") + num(data, "activeMs"))


## The anticipation of a chain's last step (owner, 2026-10-12: the loading before the strike):
## `pullMs` (the pull-back, from the step's start), `pullPx`, `pushPx`, `squashAlong`,
## `squashAcross`, `jumpPx` (the art's hop that lands on the contact frame: the War Axe's chop); read by
## ShapeVisuals.art_pose. {} for a step without one.
static func anticipation(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("anticipation", {})
	return raw if raw is Dictionary else {}


## How far a line runs beside the aim (`sidePx`, px across it: the Spear's second jab comes from one
## side of the aim line), on the side the strike's sweep sign picks, so left-facing strikes mirror.
static func side_px(data: Dictionary) -> float:
	return num(data, "sidePx")


## The sweep sign of `data` aimed along `direction`: +1 for a "cw" sweep (the angle grows on screen),
## -1 for "ccw", mirrored for a left-facing strike (so the Axe's first swing always comes down in
## front and a line's `sidePx` lies on the same side of the slime). The shape controller and the strike
## rig's editor overlay use it.
static func sweep_sign(data: Dictionary, direction: Vector2) -> float:
	var sweep := -1.0 if str(data.get("sweep", "")) == SWEEP_CCW else 1.0
	return -sweep if direction.x < -0.01 else sweep


## True for an arc step that chops (`chop`: the War Axe's overhead finisher): its whole sector hits
## from its first active frame instead of being swept from one side.
static func is_chop(data: Dictionary) -> bool:
	return bool(data.get("chop", false))


## "line" | "arc" | "circle" | "" (combat-feel plan section 4 "Reach" / "Area" columns). A line is told by its
## `minReach` too, since a chain step's `reach` comes from its strike file.
static func area_kind(data: Dictionary) -> String:
	if data.has("reach") or data.has("minReach"):
		return AREA_LINE
	if data.has("arcDeg"):
		return AREA_ARC
	if data.has("radius"):
		return AREA_CIRCLE
	return AREA_NONE


## True for a step that hits on its impact frame only (the Hammer's circle ahead and the Quake):
## its contact is the first active frame, not the whole active window.
static func impact_only(data: Dictionary) -> bool:
	return area_kind(data) == AREA_CIRCLE


## The first contact frame after the step starts (its wind-up).
static func contact_start_ms(data: Dictionary) -> float:
	return num(data, "windupMs")


## The last contact frame: the end of the active window, or the impact frame itself.
static func contact_end_ms(data: Dictionary) -> float:
	if impact_only(data):
		return contact_start_ms(data)
	return contact_start_ms(data) + num(data, "activeMs")


## The ring hit of an impact (the BOOM's `ringHit`, the Quake's `cracks`): {class, radius,
## damageScale, bounceMs}; {} when the step has none.
static func ring_of(data: Dictionary) -> Dictionary:
	for key: String in ["ringHit", "cracks"]:
		var raw: Variant = data.get(key)
		if raw is Dictionary:
			return raw
	return {}


## The hold formula (combat-feel plan section 4) for step `index` of shape `id` hitting at
## `contact_ms` after the step started: (cancel point - contact) + link window + the next step's last
## contact frame + `holdMarginMs`, capped at `holdCapMs`. So a press at the very end of the link
## window still lands while the enemy is held; since a tap fires on its release (owner,
## 2026-10-12), the margin also covers the tap's own press (a tap released within `holdMarginMs` of
## its press). The chain's last step (a hold only when the enemy's profile turns its launch into
## one) holds until the first step of a new chain lands after the rest.
static func hold_ms(id: StringName, index: int, contact_ms: float) -> float:
	var steps := chain(id)
	if index < 0 or index >= steps.size() or not steps[index] is Dictionary:
		return 0.0
	var current: Dictionary = steps[index]
	var link := chain_number("linkMs")
	var margin := chain_number("holdMarginMs")
	var cap := chain_number("holdCapMs")
	var hold := 0.0
	if index < steps.size() - 1 and steps[index + 1] is Dictionary:
		hold = (cancel_ms(current) - contact_ms) + link + contact_end_ms(steps[index + 1]) + margin
	elif steps[0] is Dictionary:
		hold = (length_ms(current) - contact_ms) + rest_ms(id) + link + contact_end_ms(steps[0]) + margin
	return clampf(hold, 0.0, cap)


## A charge's hold at `contact_ms` (a launch unless the profile turns it into a hold): the rest of the
## charge plus the margin, capped.
static func charge_hold_ms(charge_data: Dictionary, contact_ms: float) -> float:
	var hold := (length_ms(charge_data) - contact_ms) + chain_number("holdMarginMs")
	return clampf(hold, 0.0, chain_number("holdCapMs"))


## The hold of the Spin's tick `index`: `charge.holdMs` when the data has it (the plan's 300 ms),
## else until the last tick lands plus the margin; capped.
static func tick_hold_ms(charge_data: Dictionary, index: int) -> float:
	var cap := chain_number("holdCapMs")
	if charge_data.has("holdMs"):
		return clampf(num(charge_data, "holdMs"), 0.0, cap)
	var ticks := charge_ticks(charge_data)
	if index < 0 or index >= ticks.size() or not ticks[index] is Dictionary or not ticks[ticks.size() - 1] is Dictionary:
		return 0.0
	var last_at := num(ticks[ticks.size() - 1], "atMs")
	var hold := (last_at - num(ticks[index], "atMs")) + chain_number("holdMarginMs")
	return clampf(hold, 0.0, cap)


# --- aim, targets, harvest -------------------------------------------------------------------------

## "exact" | "snap8" | "snap4" (snap8 when absent).
static func aim_mode(id: StringName) -> String:
	return str(definition(id).get("aim", AIM_SNAP8))


## True when the shape's line stops at walls (the Spear; the check ignores water).
static func line_check(id: StringName) -> bool:
	return bool(definition(id).get("lineCheck", false))


## `direction` snapped to the nearest of 8 directions (unit); ZERO stays ZERO.
static func snap8(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return Vector2.ZERO
	var eighth := TAU / 8.0
	return Vector2.from_angle(roundf(direction.angle() / eighth) * eighth)


## `direction` snapped to the nearest of right, down, left and up (unit); ZERO stays ZERO. An exact
## diagonal (an 8-way key press) goes to the side, as the strike art shows a diagonal side on
## (ShapePoses.direction_of).
static func snap4(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return Vector2.ZERO
	if absf(direction.y) > absf(direction.x) + DIAGONAL_EPSILON:
		return Vector2.DOWN if direction.y > 0.0 else Vector2.UP
	return Vector2.RIGHT if direction.x >= 0.0 else Vector2.LEFT


## The hit's aim for `direction` (unit or not) by the shape's `aim` mode: the exact direction, the
## 8-way snap, or the 4-way snap (every shape in game-constants.json since 2026-10-12).
static func aim_for(id: StringName, direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return Vector2.ZERO
	match aim_mode(id):
		AIM_EXACT:
			return direction.normalized()
		AIM_SNAP4:
			return snap4(direction)
	return snap8(direction)


## The damage factor of the shape on a target with `target_tags` (body-shapes plan section 3
## "Per-target modifiers"): the first target tag, in the target's order, with an entry in
## `targetModifiers` wins; 1 without one.
static func target_modifier(id: StringName, target_tags: Array) -> float:
	var raw: Variant = definition(id).get("targetModifiers", {})
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return 1.0
	var modifiers: Dictionary = raw
	for tag: Variant in target_tags:
		if modifiers.has(str(tag)):
			return num(modifiers, str(tag), 1.0)
	return 1.0


## The `harvest:<target>:<tier>` tags the shape adds to its requests: `harvest`, plus
## `harvestStoneForm` while the slime is in the Stone form (`form_id` GulpForms.HEAVY).
static func harvest_tags(id: StringName, form_id: StringName) -> Array[String]:
	var list: Array[String] = []
	var block := definition(id)
	var keys: Array[String] = ["harvest"]
	if form_id == GulpForms.HEAVY:
		keys.append("harvestStoneForm")
	for key: String in keys:
		var raw: Variant = block.get(key, {})
		if not (raw is Dictionary):
			continue
		var table: Dictionary = raw
		for target: Variant in table:
			var tier := num(table, str(target))
			if tier > 0.0:
				list.append("%s:%s:%d" % [HARVEST_PREFIX, str(target), roundi(tier)])
	return list


## The request's `weapon_tags`: the shape's tags, then its harvest tags (unique: the resolver
## refuses a request with a tag twice).
static func request_tags(id: StringName, form_id: StringName) -> Array[String]:
	var list := tags(id)
	for tag: String in harvest_tags(id, form_id):
		if not list.has(tag):
			list.append(tag)
	return list


static func crit_chance() -> float:
	var constants := Services.constants()
	return constants.number(STAT_CRIT_CHANCE) if constants != null else 0.0


static func crit_multiplier() -> float:
	var constants := Services.constants()
	return constants.number(STAT_CRIT_MULTIPLIER) if constants != null else 1.0

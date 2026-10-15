extends RefCounted
## The body shapes and the Ability Box as the HUD and the bag window show them (body-shapes plan
## sections 6 and 8; BODY_SHAPES.md "Ability Box and HUD"), rework mode only:
## - **who**: the world's player, its ShapeController, the learned shapes (RunState, ShapeDefs.IDS
##   order) and the current one (the controller's; the first learned without one);
## - **icons**: each shape has its own (`SHAPE_ICONS`, res://asset/UI/shapes/<shape>-icon.webp:
##   its jelly weapon turned to point up and to the right, 128 x 128, packed by
##   scripts/characters/pack-slime-shape-poses.py); the HUD's Shape slot and its carousel and the
##   bag's Shapes row show it; box abilities use the HUD console's ability icons
##   (`AbilityDefinitions.icon`);
## - **cards**: what the bag window's details panel shows for a clicked shape or box ability
##   (`shape_card`, `ability_card`): {"name", "status", "status_color", "details"}: a status line,
##   one line of what it does, its energy cost, its cooldown and its keys, read from the InputMap.
##   Numbers come from game-constants.json (`shapes.<name>.charge`) and AbilityBox (what the
##   ability spends).
##
## Owner: Ability Box and HUD.

const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const InventoryModel := preload("res://game/ui/screens/inventory_model.gd")

## Shape id -> its icon.
const SHAPE_ICONS := {
	ShapeDefs.SPEAR: "res://asset/UI/shapes/spear-icon.webp",
	ShapeDefs.AXE: "res://asset/UI/shapes/axe-icon.webp",
	ShapeDefs.HAMMER: "res://asset/UI/shapes/hammer-icon.webp",
}
## One line per shape (plan section 3, "The table").
const SHAPE_LINES := {
	ShapeDefs.SPEAR: "Long reach, precise and fast: it pierces everything on its line and stops at walls.",
	ShapeDefs.AXE: "A wide arc for crowds: it cuts webs, tethers, bushes and trees.",
	ShapeDefs.HAMMER: "A slow, heavy area hit: it crushes stone, iron and armour.",
}
## The chain and the charge in words (plan section 3; combat-feel plan section 4).
const SHAPE_CHAINS := {
	ShapeDefs.SPEAR: "jab, jab, lunging jab",
	ShapeDefs.AXE: "sweep, backswing, chop",
	ShapeDefs.HAMMER: "thud, BOOM",
}
const CHARGE_NAMES := {
	ShapeDefs.SPEAR: "Lunge",
	ShapeDefs.AXE: "Spin",
	ShapeDefs.HAMMER: "Quake smash",
}
const CURRENT_COLOR := UiTokens.WARNING
const OTHER_COLOR := InventoryModel.MUTED_COLOR


## The world's player, or null.
static func world_player() -> Node:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	return player if player != null and is_instance_valid(player) else null


## `player`'s ShapeController (rework mode), or null.
static func shapes_of(player: Node) -> Node:
	if player == null or not is_instance_valid(player) or not player.has_method(&"get_shapes"):
		return null
	var shapes: Variant = player.call(&"get_shapes")
	return shapes if shapes is Node and is_instance_valid(shapes) else null


## The learned shapes, in switch order (ShapeDefs.IDS), from RunState.
static func learned_shapes() -> Array[StringName]:
	var learned: Array[StringName] = []
	var run := Services.run()
	if run == null:
		return learned
	for id: StringName in ShapeDefs.IDS:
		if run.has_learned_ability(String(id)):
			learned.append(id)
	return learned


## The current shape: the controller's, else the first learned, else &"".
static func current_shape(player: Node) -> StringName:
	var shapes := shapes_of(player)
	if shapes != null and shapes.has_method(&"current_shape_id"):
		return StringName(shapes.call(&"current_shape_id"))
	var learned := learned_shapes()
	return learned[0] if not learned.is_empty() else &""


## Makes `id` the current shape (the bag's Shapes row). False when refused.
static func set_shape(player: Node, id: StringName) -> bool:
	var shapes := shapes_of(player)
	return shapes != null and shapes.has_method(&"set_current") and bool(shapes.call(&"set_current", id))


## The shape's icon (loaded on demand; the ResourceLoader caches it), or null.
static func shape_icon(id: StringName) -> Texture2D:
	var path := str(SHAPE_ICONS.get(id, ""))
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null


## The box ability's icon (the HUD console's), or null.
static func ability_icon(id: StringName) -> Texture2D:
	return AbilityDefinitions.icon(id) if not id.is_empty() else null


## The energy the shape's charge costs (0 without a charge).
static func charge_energy(id: StringName) -> int:
	return roundi(float(ShapeDefs.charge(id).get("energy", 0.0)))


## The bag card of shape `id` ({} for an unknown id).
static func shape_card(id: StringName, current: bool) -> Dictionary:
	if not ShapeDefs.is_shape(id):
		return {}
	var attack := ControlLabels.control_label(&"attack")
	var lines := PackedStringArray([str(SHAPE_LINES.get(id, "")), ""])
	lines.append("Attack (%s): tap for %s" % [_key_or_none(attack), str(SHAPE_CHAINS.get(id, ""))])
	var charge := ShapeDefs.charge(id)
	if not charge.is_empty():
		lines.append("Hold to charge: %s · %d energy · ring %s" % [str(CHARGE_NAMES.get(id, "Charge")),
			charge_energy(id), _seconds(float(charge.get("ringMs", 0.0)))])
	lines.append("Cooldown: none")
	lines.append("Next shape: %s" % _key_or_none(ControlLabels.control_labels(&"weapon_next")))
	return {
		"name": ShapeDefs.title(id),
		"status": "Your shape now" if current else "Click to take this shape",
		"status_color": CURRENT_COLOR if current else OTHER_COLOR,
		"details": "\n".join(lines),
	}


## The bag card of box ability `id` ({} for an unknown id).
static func ability_card(id: StringName, chosen: bool) -> Dictionary:
	if not AbilityDefinitions.has(id):
		return {}
	var key := _key_or_none(ControlLabels.control_label(AbilityBox.USE_ACTION))
	var lines := PackedStringArray([AbilityDefinitions.ceremony_line(id), ""])
	var cost := roundi(AbilityBox.energy_cost(id))
	lines.append("Energy: %s" % (str(cost) if cost > 0 else "none"))
	var cooldown := AbilityBox.cooldown_ms(id)
	lines.append("Cooldown: %s" % (_seconds(cooldown) if cooldown > 0.0 else "none"))
	lines.append("Use: %s" % key)
	return {
		"name": AbilityDefinitions.title(id),
		"status": ("Chosen: press %s to use it" % key) if chosen else ("Click to put it on %s" % key),
		"status_color": CURRENT_COLOR if chosen else OTHER_COLOR,
		"details": "\n".join(lines),
	}


## "2.5 s", "2 s".
static func _seconds(ms: float) -> String:
	var seconds := ms / 1000.0
	return ("%d s" % int(seconds)) if is_equal_approx(seconds, roundf(seconds)) else ("%.1f s" % seconds)


static func _key_or_none(label: String) -> String:
	return label if not label.is_empty() else "no key"

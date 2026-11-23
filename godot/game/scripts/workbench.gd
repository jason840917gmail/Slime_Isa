extends Node
class_name WorkbenchScript
## Scene script `game.workbench` (Phaser `features/scripts/WorkbenchScript.ts`; interaction spec
## 3.6, 6.4). A crafting station: the interaction controller offers it (priority 88); using it
## opens the crafting window for `site()` (crafting port). Every campfire carries one
## (`recipe_context` "campfire", prompt "Cook": the Release 1 craft panel, crafting spec 12).
##
## Owner: interaction.

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const GROUP := &"crafting_station"
const STATIONS: PackedStringArray = ["workbench", "workshop", "forge", "kitchen", "campfire"]

## JSON `prompt`.
@export var prompt: String = "Use workbench"
## JSON `recipeContext`: the crafting station kind.
@export var recipe_context: String = "workbench"
## JSON `tier` (integer >= 1).
@export var tier: int = 1
## JSON `interactRadius`: how far the slime's centre may be from the station to be offered it; with
## `reach_from_walls` from the walls of its building, else from `origin()`.
@export var interact_radius: float = 90.0
## Measure the reach from the walls of the building the station is part of (the collision boxes of
## its body: the lit Forge), not from the middle of its base.
@export var reach_from_walls: bool = false
## JSON `badgeRise`.
@export var badge_rise: float = 80.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if prompt.is_empty():
		prompt = "Use workbench"
	if not recipe_context in STATIONS:
		recipe_context = "workbench"
	tier = maxi(1, tier)
	if not (is_finite(interact_radius) and interact_radius > 0.0):
		interact_radius = 90.0
	if not is_finite(badge_rise):
		badge_rise = 80.0


## Old Phaser position of the station (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## {"station", "tier"} (WorkbenchScript `site`).
func site() -> Dictionary:
	return {"station": recipe_context, "tier": tier}

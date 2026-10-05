extends Node
class_name WorkbenchScript
## Scene script `game.workbench` (Phaser `features/scripts/WorkbenchScript.ts`; interaction spec
## 3.6, 6.4). A crafting station: the interaction controller offers it (priority 88); using it
## opens the crafting window for `site()` (crafting port).
##
## Owner: interaction.

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const GROUP := &"crafting_station"
const STATIONS: PackedStringArray = ["workbench", "workshop", "forge", "kitchen"]

## JSON `prompt`.
@export var prompt: String = "Use workbench"
## JSON `recipeContext`: the crafting station kind.
@export var recipe_context: String = "workbench"
## JSON `tier` (integer >= 1).
@export var tier: int = 1
## JSON `interactRadius`.
@export var interact_radius: float = 90.0
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

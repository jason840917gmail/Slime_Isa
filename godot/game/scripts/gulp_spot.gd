extends Node
class_name GulpSpotScript
## Scene script `game.gulp-spot` (Phaser `features/scripts/GulpSpotScript.ts`; abilities spec
## 13.1). A pile the slime eats from with a tap of Q (or a right click), any number of times, to
## take the Gulp form of its material. The player's Gulp controller finds spots in this group.
##
## Owner: abilities.

const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const GROUP := &"gulp-spot"

## JSON `materialItemId` ("stone" -> Heavy, "silk-clump" -> Sticky, "frog" -> Frog).
@export var material_item_id: String = ""
## The name in the "Gulp the ..." prompt when the material is not an item (the frog); empty: the
## item's name.
@export var display_name: String = ""
## JSON `radius`: reach from the slime's centre.
@export var radius: float = 96.0
## JSON `badgeRise`: where the "[Q] Gulp" hint floats.
@export var badge_rise: float = 80.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if not (is_finite(radius) and radius > 0.0):
		radius = 96.0
	if not is_finite(badge_rise):
		badge_rise = 80.0


## The name the prompt uses: `display_name`, else the material item's name.
func prompt_name() -> String:
	return display_name if not display_name.is_empty() else ItemCatalog.item_name(material_item_id)


## The spot's root (the bottom-centre of its art).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return parent.global_position if parent != null else Vector2.ZERO

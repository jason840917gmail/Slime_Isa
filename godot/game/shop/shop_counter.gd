extends Node2D
## A shop's counter (docs/godot/specs/crafting.md 12.3; Dollop's in `west-village-shop.tscn`): the
## interact key at the counter opens the shop window (game/ui/screens/shop_window.gd, group
## `shop_window`) for `shop_id`. It joins the interaction's `usable` group (prompt "Shop") and is
## offered only while the shop is open (ShopCatalog.is_open: Dollop's once Market Hill is awake, so
## not while she sleeps). Put it in front of the counter, a little aside from the keeper, so that
## standing by the keeper still offers her talk (a usable outranks a talk).
##
## Owner: shop.

const ShopCatalog := preload("res://game/shop/shop_catalog.gd")

const USABLE_GROUP := &"usable"
const WINDOW_GROUP := &"shop_window"
const WINDOWS_GROUP := &"game_windows"

## The shop's id in game-constants.json `shop`.
@export var shop_id: String = "dollop"
## The prompt the interaction shows.
@export var prompt: String = "Shop"
## How near the slime's centre must be (world units).
@export var interact_radius: float = 72.0
## Where the key badge floats over it.
@export var badge_rise: float = 96.0


func _enter_tree() -> void:
	add_to_group(USABLE_GROUP)


## The point the interaction measures from.
func origin() -> Vector2:
	return global_position


func can_use() -> bool:
	return ShopCatalog.is_open(shop_id)


## Opens the shop window; false while another game window is open or without one.
func use() -> bool:
	if not can_use():
		return false
	var windows := get_tree().get_first_node_in_group(WINDOWS_GROUP)
	if windows != null and bool(windows.call(&"is_any_open")):
		return false
	var window := get_tree().get_first_node_in_group(WINDOW_GROUP)
	return window != null and bool(window.call(&"open_shop", shop_id))

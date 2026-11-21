extends RefCounted
## Glimmerhill's shop (docs/godot/specs/crafting.md 12.3; owner, 2026-11-19, question 161: "the shop
## sells potions, ingredients and one slot"): the table `shop.<shop id>` in game-constants.json and
## the purchase rules. Static helpers; the coins and the bag live in RunState.
##
## A shop: {"name", "keeper", "openFlag" (open only once it is set; Dollop's is Market Hill's wake
## flag), "greeting" (the keeper's line over the stock), "stock": [{"itemId", "price" (coins),
## "count" (how many one purchase gives, 1 when absent), "once" (sold one time only),
## "soldFlag" (the story flag that marks a `once` entry sold; `shop.<shop id>.<item id>.sold` when
## absent)}]}. An entry whose item is unknown is left out.
##
## A purchase is all or nothing: the shop must be open, a `once` entry not sold yet, the coins enough
## (`RunState.spend_coins`) and the bag able to take the whole count (`RunState.transact_items` with
## `preview` first, so nothing is spent on a full bag). A bought `once` entry sets its sold flag. The
## Coin cue plays on a purchase, CraftFail on a refusal.
##
## Owner: shop.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const TABLE_PATH := "shop"
const SOLD_SUFFIX := ".sold"

const READY := "ready"
const CLOSED := "closed"
const UNKNOWN := "unknown"
const SOLD_OUT := "sold-out"
const NO_COINS := "no-coins"
const BAG_FULL := "bag-full"

const CUE_BUY := &"Coin"
const CUE_REFUSED := &"CraftFail"


## The shop `shop_id` ({} when the table has none).
static func shop(shop_id: String) -> Dictionary:
	var constants := Services.constants()
	var table: Variant = constants.value(TABLE_PATH, {}) if constants != null else {}
	var found: Variant = (table as Dictionary).get(shop_id, {}) if table is Dictionary else {}
	return found if found is Dictionary else {}


static func shop_name(shop_id: String) -> String:
	return str(shop(shop_id).get("name", shop_id))


static func greeting(shop_id: String) -> String:
	return str(shop(shop_id).get("greeting", ""))


## True once the shop's `openFlag` is set (a shop without one is always open; an unknown one never).
static func is_open(shop_id: String) -> bool:
	var entry := shop(shop_id)
	if entry.is_empty():
		return false
	var flag := str(entry.get("openFlag", ""))
	if flag.is_empty():
		return true
	var run := Services.run()
	return run != null and run.has_flag(flag)


## The stock, in the table's order: the entries whose item is known.
static func stock(shop_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = shop(shop_id).get("stock", [])
	if not raw is Array:
		return out
	for entry: Variant in raw:
		if entry is Dictionary and not ItemCatalog.definition(str((entry as Dictionary).get("itemId", ""))).is_empty():
			out.append(entry as Dictionary)
	return out


## The stock entry of `item_id` ({} when the shop does not sell it).
static func entry_of(shop_id: String, item_id: String) -> Dictionary:
	for entry: Dictionary in stock(shop_id):
		if str(entry.get("itemId", "")) == item_id:
			return entry
	return {}


static func price(entry: Dictionary) -> int:
	return maxi(0, int(entry.get("price", 0)))


## How many one purchase gives (at least 1).
static func count(entry: Dictionary) -> int:
	return maxi(1, int(entry.get("count", 1)))


static func sold_flag(shop_id: String, entry: Dictionary) -> String:
	var flag := str(entry.get("soldFlag", ""))
	return flag if not flag.is_empty() else "%s.%s.%s%s" % [TABLE_PATH, shop_id, str(entry.get("itemId", "")), SOLD_SUFFIX]


## True for a `once` entry already bought.
static func is_sold_out(shop_id: String, entry: Dictionary) -> bool:
	if not bool(entry.get("once", false)):
		return false
	var run := Services.run()
	return run != null and run.has_flag(sold_flag(shop_id, entry))


## Why `item_id` cannot be bought now (CLOSED, UNKNOWN, SOLD_OUT, NO_COINS, BAG_FULL), else READY.
static func status(shop_id: String, item_id: String) -> String:
	var run := Services.run()
	if run == null or not is_open(shop_id):
		return CLOSED
	var entry := entry_of(shop_id, item_id)
	if entry.is_empty():
		return UNKNOWN
	if is_sold_out(shop_id, entry):
		return SOLD_OUT
	if run.coins() < price(entry):
		return NO_COINS
	if not run.transact_items([], [{"item_id": item_id, "count": count(entry)}], true):
		return BAG_FULL
	return READY


## Buys `item_id`: {"ok": bool, "reason": status (READY when bought), "item_id", "price", "count"}.
## Nothing changes when it is refused.
static func buy(shop_id: String, item_id: String) -> Dictionary:
	var entry := entry_of(shop_id, item_id)
	var result := {"ok": false, "reason": status(shop_id, item_id), "item_id": item_id,
		"price": price(entry), "count": count(entry)}
	var run := Services.run()
	if str(result["reason"]) != READY or not run.spend_coins(price(entry)):
		if str(result["reason"]) == READY:
			result["reason"] = NO_COINS
		_cue(CUE_REFUSED)
		return result
	run.transact_items([], [{"item_id": item_id, "count": count(entry)}])
	if bool(entry.get("once", false)):
		run.set_flag(sold_flag(shop_id, entry))
	result["ok"] = true
	_cue(CUE_BUY)
	return result


static func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)

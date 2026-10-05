extends RefCounted
## The weapon belt's rules (Phaser `systems/WeaponLoadout.ts`, `core/GameState.ts:154-175`) on
## the run's equipment (RunState `weapon_slots` / `equipped_weapon_id`). Crafting spec 8.1-8.3.
##
## The belt holds references, not items: every weapon lives in the bag as a 1-stack item and a
## belt slot only names one. A weapon is owned while the bag holds it. `reconcile()` (every world
## build) drops unowned and duplicate belt entries, puts an owned weapon in hand onto the belt and
## empties a hand whose weapon is gone. The dev arsenal's belt reshuffle (K13) is not ported
## (owner decision C5); `ARSENAL` stays for the `arsenal` launch option.
##
## Owner: crafting / inventory.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

## `WEAPON_HOTBAR_SLOT_COUNT` (RunState.WEAPON_SLOT_COUNT).
const SLOT_COUNT := 4
## `WeaponLoadout.ts:6`: the development arsenal (launch option `arsenal`).
const ARSENAL: PackedStringArray = ["goo-gauntlet", "basic-sword", "basic-spear", "slam-hammer", "wooden-axe", "pickaxe"]

const REASON_EMPTY := "empty"
const REASON_NOT_OWNED := "not-owned"
const REASON_UNKNOWN := "unknown"
const REASON_BUSY := "busy"


## `ownsWeapon`: a known weapon the bag holds.
static func owns_weapon(weapon_id: Variant) -> bool:
	if not weapon_id is String or (weapon_id as String).is_empty() or not ItemCatalog.is_weapon(weapon_id):
		return false
	var run := Services.run()
	return run != null and run.item_count(weapon_id) > 0


## `weaponAt`: the belt slot's weapon when owned; "" when empty, unowned or out of range.
static func weapon_at(index: int) -> String:
	if index < 0 or index >= SLOT_COUNT:
		return ""
	var entry: Variant = Services.run().weapon_slots()[index]
	return str(entry) if owns_weapon(entry) else ""


## Every owned weapon, in weapon definition order (the bag's harvest advice).
static func owned_weapons() -> Array[String]:
	var out: Array[String] = []
	var run := Services.run()
	for slot: Dictionary in run.slots():
		var weapon_id := ItemCatalog.weapon_id_of(str(slot.get("item_id", "")))
		if not weapon_id.is_empty() and not weapon_id in out:
			out.append(weapon_id)
	return out


## Owned weapons on the belt, slot order.
static func belt_weapons() -> Array[String]:
	var out: Array[String] = []
	for index in SLOT_COUNT:
		var weapon_id := weapon_at(index)
		if not weapon_id.is_empty():
			out.append(weapon_id)
	return out


## `reconcile` without the arsenal steps (crafting spec 8.2, owner decision C5).
static func reconcile() -> void:
	var run := Services.run()
	var slots: Array = []
	for entry: Variant in run.weapon_slots():
		if owns_weapon(entry) and not entry in slots:
			slots.append(entry)
		else:
			slots.append(null)
	var equipped: Variant = run.equipped_weapon_id()
	if owns_weapon(equipped) and not equipped in slots:
		var empty := slots.find(null)
		if empty >= 0:
			slots[empty] = equipped
	run.set_weapon_slots(slots)
	if equipped != null and not owns_weapon(equipped):
		var first: Variant = null
		for entry: Variant in slots:
			if entry != null:
				first = entry
				break
		run.set_equipped_weapon(first)


## Puts each weapon of `weapon_ids` the bag lacks into it (`grantDevelopmentArsenal` without its
## reconcile), then onto an empty belt slot while there is one. Returns the ids added.
static func grant(weapon_ids: Array) -> Array[String]:
	var run := Services.run()
	var added: Array[String] = []
	for value: Variant in weapon_ids:
		var weapon_id := str(value)
		if not ItemCatalog.is_weapon(weapon_id) or owns_weapon(weapon_id):
			continue
		if run.add_item(weapon_id, 1) > 0:
			added.append(weapon_id)
	for weapon_id in added:
		ensure_assigned(weapon_id)
	return added


## `assignWeapon(slotIndex, weaponId)` (WeaponLoadout.ts:102-123): {"ok", "equip_assigned_weapon"}.
## Moving a belt weapon swaps it with the target slot's; a bag weapon replaces the target (which
## stays in the bag), and is to be put in hand when the replaced entry was the hand (also when both
## are empty).
static func assign_weapon(index: int, weapon_id: String) -> Dictionary:
	if index < 0 or index >= SLOT_COUNT or not owns_weapon(weapon_id):
		return {"ok": false, "equip_assigned_weapon": false}
	var run := Services.run()
	var slots := run.weapon_slots()
	var previous_target: Variant = slots[index]
	var previous_index := slots.find(weapon_id)
	if previous_index == index:
		return {"ok": true, "equip_assigned_weapon": false}
	if previous_index >= 0:
		slots[previous_index] = previous_target
	slots[index] = weapon_id
	run.set_weapon_slots(slots)
	return {"ok": true, "equip_assigned_weapon": previous_index < 0 and previous_target == run.equipped_weapon_id()}


## `ensureAssigned`: the weapon's belt slot, else the first empty one it is put on; -1 when it is
## not owned or the belt is full.
static func ensure_assigned(weapon_id: String) -> int:
	if not owns_weapon(weapon_id):
		return -1
	var slots := Services.run().weapon_slots()
	var current := slots.find(weapon_id)
	if current >= 0:
		return current
	var empty := slots.find(null)
	if empty < 0:
		return -1
	return empty if bool(assign_weapon(empty, weapon_id)["ok"]) else -1


## `cycleSlot(step)` (WeaponLoadout.ts:130-141): the next (+1, wheel down) or previous (-1) belt
## slot holding an owned weapon after the hand's, wrapping; -1 when no other weapon is on the belt.
static func cycle_slot(step: int) -> int:
	var run := Services.run()
	var equipped: Variant = run.equipped_weapon_id()
	var current := run.weapon_slots().find(equipped) if equipped != null else -1
	var start := current if current >= 0 else (SLOT_COUNT - 1 if step > 0 else 0)
	for offset in range(1, SLOT_COUNT + 1):
		var index := (start + step * offset + SLOT_COUNT * offset) % SLOT_COUNT
		if index == current:
			return -1
		if not weapon_at(index).is_empty():
			return index
	return -1


## `equipSlot(slotIndex, apply)` (WeaponLoadout.ts:152-165): {"ok": true, "weapon_id",
## "changed"} or {"ok": false, "reason": "empty" | "not-owned" | "unknown" | "busy"}. `apply`
## (weapon id -> bool) mounts the weapon; false means a swing is in flight.
static func equip_slot(index: int, apply: Callable) -> Dictionary:
	var run := Services.run()
	var weapon_id: Variant = null
	if index >= 0 and index < SLOT_COUNT:
		weapon_id = run.weapon_slots()[index]
	if weapon_id == null:
		return {"ok": false, "reason": REASON_EMPTY}
	if not owns_weapon(weapon_id):
		return {"ok": false, "reason": REASON_NOT_OWNED}
	var world := Services.world()
	if world == null or world.scene_path("weapon." + str(weapon_id)).is_empty():
		return {"ok": false, "reason": REASON_UNKNOWN}
	if weapon_id == run.equipped_weapon_id():
		return {"ok": true, "weapon_id": weapon_id, "changed": false}
	if not bool(apply.call(weapon_id)):
		return {"ok": false, "reason": REASON_BUSY}
	run.set_equipped_weapon(weapon_id)
	return {"ok": true, "weapon_id": weapon_id, "changed": true}

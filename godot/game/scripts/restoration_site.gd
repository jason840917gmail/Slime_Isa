extends Node
class_name RestorationSiteScript
## Scene script `game.restoration-site` (Phaser `features/scripts/RestorationSiteScript.ts` +
## `WorldScene.restoreSite`; abilities spec 13.8). A ruined building the player restores at the
## interaction prompt by paying its `cost` from the bag: the story flag is set (the story variant
## on it swaps in the restored building, whose station then works), with a shake, dust and the
## restored message. Missing materials are listed ("Missing: 12 Stone, 3 Wood"). A site with a
## `quest_id` needs that quest active; quests are not ported yet, so such a site shows its locked
## message unless `RunState`'s debug override says the quest is active.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const GROUP := &"restoration_site"
const LABEL_RISE := 36.0
const LOCKED_MS := 2400.0
const MISSING_MS := 2400.0
const RESTORED_MS := 2600.0
const DUST_RISE := 70.0
const CUE_RESTORED := &"BuildingRestored"
const CUE_REFUSED := &"CraftFail"

## JSON `prompt`.
@export var prompt: String = "Restore"
## JSON `flagId`: set when restored.
@export var flag_id: String = ""
## JSON `objectId` (reported to quests later).
@export var object_id: String = ""
## JSON `questId`: the quest that must be active ("" = none).
@export var quest_id: String = ""
## JSON `cost`: {item_id: count}.
@export var cost: Dictionary = {}
## JSON `lockedMessage`.
@export var locked_message: String = "It is in ruins."
## JSON `restoredMessage`.
@export var restored_message: String = "Restored!"
## JSON `interactRadius`.
@export var interact_radius: float = 150.0
## JSON `badgeRise`.
@export var badge_rise: float = 200.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if prompt.is_empty():
		prompt = "Restore"
	if not (is_finite(interact_radius) and interact_radius > 0.0):
		interact_radius = 150.0
	if not (is_finite(badge_rise) and badge_rise > 0.0):
		badge_rise = 200.0


## Old Phaser position of the site (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## The cost as [[item_id, count], ...] in authored order, positive whole counts only.
func cost_entries() -> Array:
	var entries: Array = []
	for key: Variant in cost:
		var count: Variant = cost[key]
		if (count is int or count is float) and float(count) > 0.0 and float(count) == roundf(float(count)):
			entries.append([str(key), int(count)])
	return entries


## `WorldScene.restoreSite`: false when nothing happens (already restored, no flag); true when a
## message was shown (refused or restored).
func restore() -> bool:
	var run := Services.run()
	if run == null or flag_id.is_empty() or run.has_flag(flag_id):
		return false
	var at := origin()
	var label_at := at - Vector2(0.0, LABEL_RISE)
	var feel := Services.feel()
	if not quest_id.is_empty() and not run.is_quest_active(quest_id):
		if feel != null:
			feel.floating_text(label_at, locked_message, &"white", true, LOCKED_MS)
		return true
	var missing: Array[String] = []
	for entry: Array in cost_entries():
		var short := int(entry[1]) - run.item_count(entry[0])
		if short > 0:
			missing.append("%d %s" % [short, ItemCatalog.item_name(entry[0])])
	if not missing.is_empty():
		if feel != null:
			feel.audio_cue(CUE_REFUSED)
			feel.floating_text(label_at, "Missing: " + ", ".join(missing), &"red", true, MISSING_MS)
		return true
	for entry: Array in cost_entries():
		run.remove_item(entry[0], int(entry[1]))
	run.set_flag(flag_id)
	if feel != null:
		feel.audio_cue(CUE_RESTORED)
		feel.play(&"building-restored")
		feel.particles(&"dust-puff", at - Vector2(0.0, DUST_RISE))
		feel.floating_text(label_at, restored_message, &"green", true, RESTORED_MS)
	return true

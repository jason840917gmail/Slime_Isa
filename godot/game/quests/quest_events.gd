extends RefCounted
## The quest events world scripts and features send (Phaser `gameEvents` + `QuestEventBridge`):
## `QuestEvents.emit(event, payload)` hands the event to the quest service (main's child "Quests",
## group "quests") and does nothing when there is none (the title screen, a test without main).
## Payload keys are Phaser's camelCase (ARCHITECTURE §5). Quests spec §3 and §10.4.
##
## Owner: quests.

const SERVICE_GROUP := &"quests"

## {mapId, instanceId, objectId, itemId, quantity, recovered?}
const COLLECTIBLE_COLLECTED := &"collectible.collected"
## {enemyId, areaId, kind, tags?} (ordinary enemies only, never bosses)
const ENEMY_DIED := &"enemy.died"
## {npcId}
const NPC_TALKED := &"npc.talked"
## {recipeId, itemId, quantity}
const CRAFT_COMPLETED := &"craft.completed"
## {bossId, factId?}
const BOSS_DEFEATED := &"boss.defeated"
## {objectId, instanceId, areaId}
const OBJECT_ACTIVATED := &"object.activated"
## {areaId}
const AREA_ENTER := &"area.enter"
## {controlId}: "menu:inventory", "menu:crafting", "menu:journal", "menu:map", "sprint",
## "weapon-switch", "pause"
const CONTROL_USED := &"control.used"
## {mapId, placementId, itemId, sceneId, x, y}
const FURNITURE_PLACED := &"furniture.placed"
const ESCORT_COMPLETED := &"escort.completed"
const SURVIVAL_COMPLETED := &"survival.completed"


static func emit(event: StringName, payload: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var service: Node = tree.get_first_node_in_group(SERVICE_GROUP) if tree != null else null
	if service != null and service.has_method(&"handle_event"):
		service.call(&"handle_event", event, payload)

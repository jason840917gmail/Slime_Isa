import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import { RECIPE_CATALOG } from '../../content/recipes/RecipeCatalog';
import type { CraftingStation } from '../../content/recipes/types';
import type { QuestObjectiveDefinition, QuestView } from '../../content/quests/types';

export interface WaypointPoint {
  readonly x: number;
  readonly y: number;
}

/** Where the tracked quest wants the player to go next, and what to do there. */
export interface QuestWaypointTarget extends WaypointPoint {
  readonly label: string;
}

/** What the current map can locate; anything it cannot find simply shows no arrow. */
export interface QuestWaypointWorld {
  npcPosition(npcId: string): WaypointPoint | undefined;
  bossCampPosition(bossId: string): WaypointPoint | undefined;
  /** The nearest enemy spawn area holding any of these enemy kinds. */
  spawnAreaFor(enemyKinds: readonly string[], from: WaypointPoint): WaypointPoint | undefined;
  /** The exit or door that leads into an area. */
  exitToArea(areaId: string, from: WaypointPoint): WaypointPoint | undefined;
  /** The nearest pile, bush, tree or rock that yields one of these items. */
  nearestSource(itemIds: readonly string[], from: WaypointPoint): WaypointPoint | undefined;
  /** The nearest crafting station of a kind (a placed workbench, the Workshop). */
  nearestStation(station: CraftingStation, from: WaypointPoint): WaypointPoint | undefined;
  /** The nearest ruined building (restoration site) with one of these quest object ids. */
  restorationSite(objectIds: readonly string[], from: WaypointPoint): WaypointPoint | undefined;
}

function npcName(npcId: string): string {
  return getNpcDefinition(npcId)?.displayName ?? npcId;
}

function nearestNpc(npcIds: readonly string[], world: QuestWaypointWorld, from: WaypointPoint): { npcId: string; point: WaypointPoint } | undefined {
  let best: { npcId: string; point: WaypointPoint } | undefined;
  for (const npcId of npcIds) {
    const point = world.npcPosition(npcId);
    if (!point) continue;
    if (!best || Math.hypot(point.x - from.x, point.y - from.y) < Math.hypot(best.point.x - from.x, best.point.y - from.y)) best = { npcId, point };
  }
  return best;
}

function objectiveTarget(objective: QuestObjectiveDefinition, world: QuestWaypointWorld, from: WaypointPoint): QuestWaypointTarget | undefined {
  switch (objective.kind) {
    case 'talk-to-npc': {
      const npc = nearestNpc(objective.npcIds, world, from);
      return npc ? { ...npc.point, label: `Talk to ${npcName(npc.npcId)}` } : undefined;
    }
    case 'kill': {
      const point = objective.enemyKinds?.length ? world.spawnAreaFor(objective.enemyKinds, from) : undefined;
      return point ? { ...point, label: objective.label } : undefined;
    }
    case 'defeat-boss': {
      const point = objective.bossIds.map((bossId) => world.bossCampPosition(bossId)).find((entry) => entry !== undefined);
      return point ? { ...point, label: objective.label } : undefined;
    }
    case 'discover-area': {
      const point = objective.areaIds.map((areaId) => world.exitToArea(areaId, from)).find((entry) => entry !== undefined);
      return point ? { ...point, label: objective.label } : undefined;
    }
    case 'collect': {
      const point = world.nearestSource(objective.itemIds, from);
      return point ? { ...point, label: objective.label } : undefined;
    }
    case 'craft-item': {
      // Station recipes point at the nearest station; portable ones are crafted anywhere (C).
      const station = RECIPE_CATALOG.find((recipe) => objective.itemIds.includes(recipe.output.itemId))?.station;
      if (!station || station === 'portable') return undefined;
      const point = world.nearestStation(station, from);
      return point ? { ...point, label: objective.label } : undefined;
    }
    case 'activate-object': {
      const point = objective.objectIds?.length ? world.restorationSite(objective.objectIds, from) : undefined;
      return point ? { ...point, label: objective.label } : undefined;
    }
    default:
      return undefined;
  }
}

/**
 * Resolves the next place for a quest, like the waypoint arrow in WoW: the quest
 * giver for an offer, the turn-in NPC once the work is done, otherwise the first
 * unfinished objective of the active step. Undefined when there is nowhere to go
 * on this map (crafting anywhere, placing furniture, another map).
 */
export function resolveQuestWaypoint(quest: QuestView, world: QuestWaypointWorld, from: WaypointPoint): QuestWaypointTarget | undefined {
  const definition = quest.definition;
  if (quest.status === 'available') {
    if (definition.acquisition.kind !== 'npc') return undefined;
    const npc = nearestNpc(definition.acquisition.npcIds, world, from);
    return npc ? { ...npc.point, label: `Talk to ${npcName(npc.npcId)}` } : undefined;
  }
  if (quest.status !== 'active') return undefined;
  if (quest.readyToTurnIn) {
    if (definition.completion.kind !== 'npc-turn-in') return undefined;
    const npc = nearestNpc(definition.completion.npcIds, world, from);
    return npc ? { ...npc.point, label: `Return to ${npcName(npc.npcId)}` } : undefined;
  }
  const stage = definition.stages.find((candidate) => candidate.id === quest.activeStageId);
  for (const objective of stage?.objectives ?? []) {
    if ((quest.progress[objective.id] ?? 0) >= objective.target) continue;
    const target = objectiveTarget(objective, world, from);
    if (target) return target;
  }
  return undefined;
}

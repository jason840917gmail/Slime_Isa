import type { CollisionShapeDocument } from '../../shared/collisionShapes';
import { npcAnchorDomain, npcAnchorInsideDomain } from '../npcs/npcWanderGeometry';
import type { MapFile } from './mapFormat';

export interface MapObjectReference {
  readonly kind: 'object' | 'npc';
  readonly placementVisualId?: string;
  readonly npcDefinitionId?: string;
  readonly body?: CollisionShapeDocument;
  readonly chest?: boolean;
}

export interface MapNpcReference {
  readonly characterId: string;
}

export interface MapReferenceResolver {
  isWorldTileId(tileId: string): boolean;
  getObjectReference(objectId: string): MapObjectReference | undefined;
  getNpcReference(definitionId: string): MapNpcReference | undefined;
  getNpcBody(characterId: string): CollisionShapeDocument | undefined;
  isEnemyId(enemyId: string): boolean;
  isBossId(bossId: string): boolean;
  isItemId(itemId: string): boolean;
  hasMap(mapId: string): boolean;
}

export function validateMapReferences(map: MapFile, resolver: MapReferenceResolver): string[] {
  const issues: string[] = [];
  for (const [layerIndex, layer] of map.layers.entries()) {
    for (const [token, tileId] of Object.entries(layer.legend)) if (!resolver.isWorldTileId(tileId)) issues.push(`layers[${layerIndex}].legend['${token}']: unknown tile '${tileId}'`);
  }
  const objects = new Map<string, MapFile['objects'][number]>();
  for (const [index, object] of map.objects.entries()) {
    objects.set(object.instanceId, object);
    const reference = resolver.getObjectReference(object.objectId);
    if (!reference) { issues.push(`objects[${index}].objectId: unknown object '${object.objectId}'`); continue; }
    if (reference.kind === 'npc') {
      if (object.visualId !== reference.placementVisualId) issues.push(`objects[${index}].visualId: must match NPC placement visual '${reference.placementVisualId}'`);
      if (!reference.npcDefinitionId || !resolver.getNpcReference(reference.npcDefinitionId)) issues.push(`objects[${index}].objectId: NPC definition is unavailable`);
    } else if (reference.placementVisualId !== undefined && object.visualId !== reference.placementVisualId) {
      issues.push(`objects[${index}].visualId: unknown visual '${object.visualId}' for '${object.objectId}'`);
    }
  }
  for (const [index, enemy] of (map.spawns?.enemies ?? []).entries()) if (!resolver.isEnemyId(enemy.type)) issues.push(`spawns.enemies[${index}].type: unknown enemy '${enemy.type}'`);
  for (const [areaIndex, area] of (map.enemySpawnAreas ?? []).entries()) for (const [enemyIndex, enemy] of area.enemies.entries()) if (!resolver.isEnemyId(enemy.type)) issues.push(`enemySpawnAreas[${areaIndex}].enemies[${enemyIndex}].type: unknown enemy '${enemy.type}'`);
  for (const [index, exit] of (map.exits ?? []).entries()) if (!resolver.hasMap(exit.to)) issues.push(`exits[${index}].to: unknown authored map '${exit.to}'`);
  const gateIds = new Set<string>();
  for (const [index, exit] of (map.exits ?? []).entries()) {
    if (!exit.gate) continue;
    if (gateIds.has(exit.gate.id)) issues.push(`exits[${index}].gate.id: duplicate '${exit.gate.id}'`);
    else gateIds.add(exit.gate.id);
    if (!resolver.isItemId(exit.gate.requiredItemId)) issues.push(`exits[${index}].gate.requiredItemId: unknown item '${exit.gate.requiredItemId}'`);
  }
  for (const [index, camp] of (map.bossCamps ?? []).entries()) {
    if (!resolver.isBossId(camp.bossId)) issues.push(`bossCamps[${index}].bossId: unknown boss '${camp.bossId}'`);
    if (camp.guardedChestInstanceId === undefined) continue;
    const chest = objects.get(camp.guardedChestInstanceId);
    const reference = chest ? resolver.getObjectReference(chest.objectId) : undefined;
    if (!chest) issues.push(`bossCamps[${index}].guardedChestInstanceId: unknown object instance '${camp.guardedChestInstanceId}'`);
    else if (!reference?.chest) issues.push(`bossCamps[${index}].guardedChestInstanceId: must reference a chest object`);
  }
  for (const [index, area] of (map.npcWanderAreas ?? []).entries()) {
    const owner = objects.get(area.npcInstanceId);
    const reference = owner ? resolver.getObjectReference(owner.objectId) : undefined;
    if (!owner) { issues.push(`npcWanderAreas[${index}].npcInstanceId: unknown object instance '${area.npcInstanceId}'`); continue; }
    if (!reference || reference.kind !== 'npc' || !reference.npcDefinitionId) { issues.push(`npcWanderAreas[${index}].npcInstanceId: must reference an NPC object`); continue; }
    const npc = resolver.getNpcReference(reference.npcDefinitionId);
    const body = npc ? resolver.getNpcBody(npc.characterId) : undefined;
    const domain = body ? npcAnchorDomain(area.perimeter, body) : undefined;
    if (!domain) issues.push(`npcWanderAreas[${index}].perimeter: too small for NPC body and margin`);
    else if (!npcAnchorInsideDomain({ x: owner.x, y: owner.y }, domain)) issues.push(`npcWanderAreas[${index}].perimeter: NPC anchor is outside the valid wander domain`);
  }
  return issues;
}

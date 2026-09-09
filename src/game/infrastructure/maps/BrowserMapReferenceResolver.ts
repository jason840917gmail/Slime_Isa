import { getCharacterPackage } from '../../content/characters/CharacterCatalog';
import { getObjectArchetype, isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import { isWorldTileId } from '../../content/terrain/TileCatalog';
import { ENEMY_CONFIGS } from '../../enemies/library/EnemyTypes';
import type { MapReferenceResolver } from '../../content/maps/validateMapReferences';

const MAP_MODULES = import.meta.glob('/src/game/content/maps/*.map.json');

export const browserMapReferenceResolver: MapReferenceResolver = {
  isWorldTileId,
  getObjectReference(objectId) {
    if (!isObjectArchetypeId(objectId)) return undefined;
    const definition = getObjectArchetype(objectId);
    if (definition.npc) return { kind: 'npc', placementVisualId: definition.npc.placementVisualId, npcDefinitionId: definition.npc.definitionId };
    return { kind: 'object' };
  },
  getNpcReference(definitionId) {
    const definition = getNpcDefinition(definitionId);
    return definition ? { characterId: definition.characterId } : undefined;
  },
  getNpcBody(characterId) {
    try { return getCharacterPackage(characterId).character.body; } catch { return undefined; }
  },
  isEnemyId(enemyId) { return enemyId in ENEMY_CONFIGS; },
  hasMap(mapId) { return Boolean(MAP_MODULES[`/src/game/content/maps/${mapId}.map.json`]); },
};

export { capabilitiesForNode, createCoreDescriptorRegistry, handlersForNode, handlersForScript, propertiesForNode, signalsForNode, validateDescriptorRegistry } from './propertyDescriptors';
export { assertValidSceneDocument, assertValidSceneResourceDocument, canonicalSceneJson, validatePropertyDocumentValue, validateSceneDocument, validateSceneResourceDocument } from './validation';
export { SceneCatalog } from './SceneCatalog';
export { authoredNodeId, instanceId, persistenceKey, resourceId, runtimeNodeId, sceneId } from './identifiers';
export { GAME_SCRIPT_DESCRIPTORS, createGameDescriptorRegistry } from '../../features/scripts/registrations';
export { parseTileMapDataResource } from './resources/TileMapDataResource';
export { parseTileSetResource } from './resources/TileSetResource';
export { CHARACTER_BODY_REQUIRED_MASK, COLLISION_LAYERS, DEFINED_COLLISION_BITS, collisionBits, collisionLayerNames, undefinedCollisionBits } from '../physics/CollisionLayers';
export { blockingPairAccepts } from '../../runtime/scene/physics/PhysicsContact';

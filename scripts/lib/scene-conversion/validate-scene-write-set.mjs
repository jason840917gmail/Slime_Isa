import { loadSceneTooling } from './load-scene-tooling.mjs';

export async function validateSceneWriteSet(outputs, { hasAsset, existingScenes = [], existingResources = [] } = {}) {
  const tooling = await loadSceneTooling();
  const registry = tooling.createGameDescriptorRegistry?.() ?? tooling.createCoreDescriptorRegistry();
  const convertedScenes = [];
  const convertedResources = [];
  for (const output of outputs) {
    if (!output.path.endsWith('.scene.json') && !output.path.endsWith('.resource.json')) continue;
    let document;
    try { document = JSON.parse(output.content); } catch (error) {
      throw new Error(`Conversion output '${output.path}' is malformed JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (`${JSON.stringify(document, null, 2)}\n` !== output.content) throw new Error(`Conversion output '${output.path}' is not canonical JSON`);
    if (output.path.endsWith('.scene.json')) convertedScenes.push(document);
    else convertedResources.push(document);
  }
  const convertedResourceIds = new Set();
  for (const resource of convertedResources) {
    if (convertedResourceIds.has(resource.resourceId)) throw new Error(`Duplicate converted resource ID '${String(resource.resourceId)}'`);
    convertedResourceIds.add(resource.resourceId);
  }
  const convertedSceneIds = new Set();
  for (const scene of convertedScenes) {
    if (convertedSceneIds.has(scene.sceneId)) throw new Error(`Duplicate converted scene ID '${String(scene.sceneId)}'`);
    convertedSceneIds.add(scene.sceneId);
  }
  const resourceById = new Map(existingResources.map((resource) => [resource.resourceId, resource]));
  for (const resource of convertedResources) resourceById.set(resource.resourceId, resource);
  const sceneById = new Map(existingScenes.map((scene) => [scene.sceneId, scene]));
  for (const scene of convertedScenes) sceneById.set(scene.sceneId, scene);
  const context = {
    registry,
    hasAsset,
    hasResource: (resourceId) => resourceById.has(resourceId),
    getResourceKind: (resourceId) => resourceById.get(resourceId)?.kind,
  };
  for (const resource of resourceById.values()) tooling.assertValidSceneResourceDocument(resource, context);
  new tooling.SceneCatalog([...sceneById.values()], context);
}

import { loadSceneTooling } from './load-scene-tooling.mjs';

export async function validateSceneWriteSet(outputs, { hasAsset } = {}) {
  const tooling = await loadSceneTooling();
  const registry = tooling.createCoreDescriptorRegistry();
  const scenes = [];
  const resources = [];
  for (const output of outputs) {
    if (!output.path.endsWith('.scene.json') && !output.path.endsWith('.resource.json')) continue;
    let document;
    try { document = JSON.parse(output.content); } catch (error) {
      throw new Error(`Conversion output '${output.path}' is malformed JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (`${JSON.stringify(document, null, 2)}\n` !== output.content) throw new Error(`Conversion output '${output.path}' is not canonical JSON`);
    if (output.path.endsWith('.scene.json')) scenes.push(document);
    else resources.push(document);
  }
  const resourceById = new Map();
  for (const resource of resources) {
    if (resourceById.has(resource.resourceId)) throw new Error(`Duplicate converted resource ID '${String(resource.resourceId)}'`);
    resourceById.set(resource.resourceId, resource);
  }
  const context = {
    registry,
    hasAsset,
    hasResource: (resourceId) => resourceById.has(resourceId),
    getResourceKind: (resourceId) => resourceById.get(resourceId)?.kind,
  };
  for (const resource of resources) tooling.assertValidSceneResourceDocument(resource, context);
  new tooling.SceneCatalog(scenes, context);
}

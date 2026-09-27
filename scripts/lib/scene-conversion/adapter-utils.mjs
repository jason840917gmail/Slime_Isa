export function canonicalJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export async function readJson(readSource, relativePath) {
  return JSON.parse(await readSource(relativePath));
}

export function convertedOutput(unit, outputPath, document, consumedFieldPaths, intentionallyRetainedFields = []) {
  return {
    unitKey: unit.key,
    path: outputPath,
    content: canonicalJson(document),
    consumedFieldPaths,
    intentionallyRetainedFields,
  };
}

export function requireSupportedUnit(unit, supportedKeys) {
  if (!supportedKeys.has(unit.key)) {
    throw new Error(`Scene conversion adapter does not support unit '${unit.key}' yet`);
  }
}

export function resourcePath(group, stableId, suffix) {
  return `resources/${group}/${stableId}.${suffix}.resource.json`;
}

export function shapeValue(body) {
  if (body.shape === 'ellipse') return { shape: 'ellipse', radiusX: body.radiusX ?? body.width / 2, radiusY: body.radiusY ?? body.height / 2 };
  return { shape: 'rectangle', width: body.width, height: body.height };
}

/** Visual sets named `effect.<group>.<name>` are mounted as the effect scene `effect.<group>-<name>`. */
export function effectIdForVisualSet(visualSetId) {
  if (!visualSetId.startsWith('effect.')) throw new Error(`Visual set '${visualSetId}' is not an effect visual set`);
  return visualSetId.slice('effect.'.length).replaceAll('.', '-');
}

/**
 * Characters sort by their feet (the old runtime sorted by the Arcade body
 * bottom). The body root gets a `depthAnchor` derived from its collision body
 * and its direct Sprite2D visuals draw relative to it, so the character's
 * visuals, anything attached to the body (weapons) and occlusion all share one
 * depth source. `depthAnchor` comes from `bodyDepthAnchor` in the shared
 * conversion sampling module.
 */
export function withCharacterDepthAnchor(scene, depthAnchor) {
  const root = scene.nodes.find((node) => node.id === scene.rootNodeId);
  if (!root) throw new Error(`Character scene '${scene.sceneId}' has no root node`);
  root.properties = { ...root.properties, depthAnchor: [...depthAnchor] };
  for (const node of scene.nodes) {
    if (node.type === 'Sprite2D' && node.parentId === root.id) node.properties = { ...node.properties, depthMode: 'relative' };
  }
  return scene;
}

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

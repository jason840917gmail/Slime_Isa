import { canonicalJson } from './adapter-utils.mjs';

/**
 * Resource kinds that follow Godot's sub-resource convention: a shape, sprite
 * sheet, animation library, or painted tile layer used by one scene lives
 * inside that scene (Godot stores TileMapLayer cells in the scene), and only a
 * resource shared by several scenes keeps its own file.
 */
export const EMBEDDABLE_RESOURCE_KINDS = new Set(['collision-shape', 'sprite-sheet', 'animation-library', 'tile-data']);

/** IDs referenced through `{ "resourceId": ... }` property values anywhere in a document. */
function referencedResourceIds(value, found = new Set()) {
  if (Array.isArray(value)) {
    for (const entry of value) referencedResourceIds(entry, found);
  } else if (value && typeof value === 'object') {
    const keys = Object.keys(value);
    if (keys.length === 1 && keys[0] === 'resourceId' && typeof value.resourceId === 'string') found.add(value.resourceId);
    else for (const entry of Object.values(value)) referencedResourceIds(entry, found);
  }
  return found;
}

/** True when a resource document mentions the ID anywhere other than its own identity. */
function resourceMentions(resource, resourceId) {
  const { resourceId: _own, ...rest } = resource;
  return JSON.stringify(rest).includes(JSON.stringify(resourceId));
}

function sortedFields(fields) {
  return [...fields].sort((left, right) => (typeof left === 'string' ? left.localeCompare(right) : left.path.localeCompare(right.path)));
}

/**
 * Moves every embeddable resource output referenced by exactly one scene
 * output (and by no other resource) into that scene's `subresources`.
 * Units whose outputs are absorbed are recorded as `contributions` on the
 * scene output so the ledger still attributes their consumed source fields.
 *
 * A partial run may convert a scene without the unit that produces one of its
 * resources. When the scene already embeds that resource on disk
 * (`existingScenes`), the existing copy is carried over instead of leaving a
 * dangling reference.
 */
export function embedOwnedResources(outputs, { existingScenes = [] } = {}) {
  const scenes = new Map();
  const resources = new Map();
  for (const output of outputs) {
    let document;
    // Malformed outputs are left untouched for the write-set validator to report.
    try { document = JSON.parse(output.content); } catch { continue; }
    if (output.path.endsWith('.scene.json')) scenes.set(output, document);
    else if (output.path.endsWith('.resource.json')) resources.set(output, document);
  }
  const sceneReferences = new Map([...scenes].map(([output, scene]) => [output, referencedResourceIds(scene)]));
  const resourceIds = new Set([...resources.values()].map((resource) => resource.resourceId));

  const absorbed = new Map();
  for (const [resourceOutput, resource] of resources) {
    if (!EMBEDDABLE_RESOURCE_KINDS.has(resource.kind)) continue;
    const owners = [...sceneReferences].filter(([, ids]) => ids.has(resource.resourceId)).map(([output]) => output);
    if (owners.length !== 1) continue;
    if ([...resources.values()].some((other) => other !== resource && resourceMentions(other, resource.resourceId))) continue;
    const owner = owners[0];
    const entries = absorbed.get(owner) ?? [];
    entries.push({ output: resourceOutput, resource });
    absorbed.set(owner, entries);
  }

  const existingById = new Map(existingScenes.map((scene) => [scene.sceneId, scene]));
  const replaced = new Map();
  for (const [sceneOutput, scene] of scenes) {
    const entries = absorbed.get(sceneOutput) ?? [];
    const local = new Set((scene.subresources ?? []).map((resource) => resource.resourceId));
    const carried = [];
    for (const resourceId of sceneReferences.get(sceneOutput)) {
      if (local.has(resourceId) || resourceIds.has(resourceId)) continue;
      const existing = existingById.get(scene.sceneId)?.subresources?.find((resource) => resource.resourceId === resourceId);
      if (existing) carried.push(structuredClone(existing));
    }
    if (entries.length === 0 && carried.length === 0) continue;
    const embedded = [...entries.map((entry) => entry.resource), ...carried].sort((left, right) => left.resourceId.localeCompare(right.resourceId));
    for (const resource of embedded) {
      if (local.has(resource.resourceId)) throw new Error(`Scene '${scene.sceneId}' already has subresource '${resource.resourceId}'`);
      local.add(resource.resourceId);
    }
    const document = { ...scene, subresources: [...(scene.subresources ?? []), ...embedded] };
    const own = entries.filter((entry) => entry.output.unitKey === sceneOutput.unitKey).map((entry) => entry.output);
    const contributions = new Map((sceneOutput.contributions ?? []).map((entry) => [entry.unitKey, entry]));
    for (const { output } of entries.filter((entry) => entry.output.unitKey !== sceneOutput.unitKey)) {
      const previous = contributions.get(output.unitKey);
      contributions.set(output.unitKey, {
        unitKey: output.unitKey,
        consumedFieldPaths: sortedFields(new Set([...(previous?.consumedFieldPaths ?? []), ...output.consumedFieldPaths])),
        intentionallyRetainedFields: sortedFields([...(previous?.intentionallyRetainedFields ?? []), ...output.intentionallyRetainedFields]),
      });
    }
    replaced.set(sceneOutput, {
      ...sceneOutput,
      content: canonicalJson(document),
      consumedFieldPaths: [...new Set([...sceneOutput.consumedFieldPaths, ...own.flatMap((output) => output.consumedFieldPaths)])],
      intentionallyRetainedFields: [...sceneOutput.intentionallyRetainedFields, ...own.flatMap((output) => output.intentionallyRetainedFields)],
      ...(contributions.size > 0 ? { contributions: [...contributions.values()].sort((left, right) => left.unitKey.localeCompare(right.unitKey)) } : {}),
    });
  }

  const removed = new Set([...absorbed.values()].flatMap((entries) => entries.map((entry) => entry.output)));
  return outputs.filter((output) => !removed.has(output)).map((output) => replaced.get(output) ?? output);
}

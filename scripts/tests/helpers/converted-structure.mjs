import assert from 'node:assert/strict';
import { isDeepStrictEqual } from 'node:util';

const nodeIdentity = (node) => ({ name: node.name, type: node.type, parentId: node.parentId, scriptId: node.scriptId });
const trackKeys = (clip) => clip.tracks.map((track) => `${track.binding} ${track.property}`).sort();

/**
 * Scene-owned documents are Scene Studio's to retune after conversion: values
 * (shape sizes, offsets, key values, text) may change and content (clips,
 * audio) may be added. What they keep is everything the runtime binds to that
 * the conversion produced: each node with its name, type, parent and script,
 * each connection, each resource with its kind, and each animation clip with
 * its track bindings.
 */
export function assertKeepsConvertedStructure(authored, converted, label) {
  assert.equal(authored.sceneId, converted.sceneId, `${label} sceneId`);
  assert.equal(authored.rootNodeId, converted.rootNodeId, `${label} root node`);
  const nodes = new Map(authored.nodes.map((node) => [node.id, node]));
  for (const node of converted.nodes) {
    assert.ok(nodes.has(node.id), `${label} keeps node '${node.id}'`);
    assert.deepEqual(nodeIdentity(nodes.get(node.id)), nodeIdentity(node), `${label} node '${node.id}'`);
  }
  for (const connection of converted.connections ?? []) {
    assert.ok((authored.connections ?? []).some((candidate) => isDeepStrictEqual(candidate, connection)), `${label} keeps connection ${JSON.stringify(connection)}`);
  }
  const resources = new Map((authored.subresources ?? []).map((resource) => [resource.resourceId, resource]));
  for (const resource of converted.subresources ?? []) {
    const kept = resources.get(resource.resourceId);
    assert.equal(kept?.kind, resource.kind, `${label} keeps ${resource.kind} '${resource.resourceId}'`);
    for (const [clipId, clip] of Object.entries(resource.animations ?? {})) {
      const keptClip = kept.animations[clipId];
      assert.ok(keptClip, `${label} keeps clip '${clipId}'`);
      const keptTracks = new Set(trackKeys(keptClip));
      for (const track of trackKeys(clip)) assert.ok(keptTracks.has(track), `${label} clip '${clipId}' keeps track '${track}'`);
    }
  }
}

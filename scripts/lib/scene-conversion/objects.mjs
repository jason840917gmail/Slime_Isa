import { convertedOutput, readJson, requireSupportedUnit } from './adapter-utils.mjs';

const SUPPORTED = new Set(['object:chest.wooden', 'object:resource.stone-node']);

function slug(value) {
  return value.replaceAll('.', '-').replace(/[^a-z0-9-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
}

function shapeValue(collider, scale) {
  if (collider.shape === 'circle') return { shape: 'circle', radius: (collider.radius ?? Math.min(collider.width, collider.height) / 2) * scale };
  if (collider.shape === 'ellipse') return { shape: 'ellipse', radiusX: (collider.radiusX ?? collider.width / 2) * scale, radiusY: (collider.radiusY ?? collider.height / 2) * scale };
  return { shape: 'rectangle', width: collider.width * scale, height: collider.height * scale };
}

function objectVisualScenes(unit, object, manifest) {
  const frames = object.variants.flatMap((variant) => variant.frames.map((frame) => ({ assetId: variant.assetId, frame })));
  return frames.map(({ assetId, frame }, index) => {
    if (!frame.collider) throw new Error(`Damageable object '${object.objectId}' visual '${frame.visualId}' requires a collider`);
    const asset = manifest.assets[assetId];
    if (!asset || asset.source.kind !== 'spritesheet') throw new Error(`Object '${object.objectId}' visual '${frame.visualId}' requires a spritesheet asset`);
    const scale = frame.scale ?? 1;
    const visualOffset = frame.visualOffset ?? { x: 0, y: 0 };
    const baseSlug = slug(object.objectId);
    const visualSlug = slug(frame.visualId);
    const sceneSuffix = index === 0 ? '' : `.${visualSlug}`;
    const fileSuffix = index === 0 ? '' : `--${visualSlug}`;
    const resourcePrefix = `${baseSlug}.${visualSlug}`;
    const origin = Array.isArray(asset.render?.origin) ? asset.render.origin : [0.5, 1];
    const node = object.resourceNode;
    const document = {
      version: 1,
      sceneId: `object.${baseSlug}${sceneSuffix}`,
      rootNodeId: 'body',
      nodes: [
        { id: 'body', name: frame.displayName ?? frame.visualId, type: 'StaticBody2D', parentId: null, order: 0, properties: { collisionLayer: 1, collisionMask: 2, position: [0, 0] } },
        { id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: `${resourcePrefix}.shape` }, position: [(frame.collider.offsetX - visualOffset.x) * scale, (frame.collider.offsetY - visualOffset.y) * scale] } },
        { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'body', order: 1, properties: { texture: { resourceId: `${resourcePrefix}.sprite` }, frame: frame.frame, origin, scale: [scale, scale], visualOffset: [visualOffset.x, visualOffset.y], depthMode: 'world-sorted', depthBand: 'world-entities' } },
        { id: 'damage-area', name: 'DamageArea', type: 'Area2D', parentId: 'body', order: 2, properties: { collisionLayer: 8, collisionMask: 16, monitoring: true, monitorable: true } },
        { id: 'damage-shape', name: 'DamageShape', type: 'CollisionShape2D', parentId: 'damage-area', order: 0, properties: { shape: { resourceId: `${resourcePrefix}.shape` }, position: [(frame.collider.offsetX - visualOffset.x) * scale, (frame.collider.offsetY - visualOffset.y) * scale] } },
        {
          id: 'script', name: 'ResourceNodeScript', type: 'ScriptNode', scriptId: 'game.resource-node', parentId: 'body', order: 3,
          properties: {
            mapId: 'map-template', instanceId: 'resource-template', objectId: object.objectId,
            damageArea: { nodeId: 'damage-area' }, maxHealth: node.health, tags: object.tags,
            drop: node.drop, hitEffectId: node.hitEffectId ?? '', onHitAnimationId: frame.onHitAnimationId ?? '',
            persistHealth: node.persistHealth ?? true, depletionMessage: node.depletionMessage ?? '',
            harvestRequirement: node.harvestRequirement ?? {}, damageRule: { priority: 0, damageMultiplier: 1 },
          },
        },
      ],
      instances: [],
      subresources: [
        { version: 1, resourceId: `${resourcePrefix}.sprite`, kind: 'sprite-sheet', assetId, frameWidth: asset.source.frame.w, frameHeight: asset.source.frame.h, frameCount: asset.source.frame.count },
        { version: 1, resourceId: `${resourcePrefix}.shape`, kind: 'collision-shape', value: shapeValue(frame.collider, scale) },
      ],
    };
    return convertedOutput(unit, `objects/${baseSlug}${fileSuffix}.scene.json`, document, [
      '$.objectId', '$.selection', '$.variants', '$.physics', '$.behavior', '$.resourceNode', '$.tags',
    ], [{ path: '$.$schema', owner: unit.oldSourcePath }]);
  });
}

export const objectSceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    const manifest = await readJson(readSource, 'asset/assets.json');
    for (const unit of units) {
      requireSupportedUnit(unit, SUPPORTED);
      const object = await readJson(readSource, unit.oldSourcePath);
      if (unit.key === 'object:resource.stone-node') {
        outputs.push(...objectVisualScenes(unit, object, manifest));
        continue;
      }
      const closed = object.variants[0].frames.find((frame) => frame.visualId === 'wooden-closed');
      const assetId = object.variants[0].assetId;
      const frame = manifest.assets[assetId].source.frame;
      const document = {
        version: 1,
        sceneId: 'object.chest-wooden',
        rootNodeId: 'body',
        nodes: [
          { id: 'body', name: 'WoodenChest', type: 'StaticBody2D', parentId: null, order: 0, properties: { collisionLayer: 1, collisionMask: 2, position: [0, 0] } },
          { id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: 'chest-wooden.body-shape' }, position: [closed.collider.offsetX, closed.collider.offsetY] } },
          { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'body', order: 1, properties: { texture: { resourceId: 'chest-wooden.sprite' }, frame: closed.frame, origin: [0.5, 0.75], scale: [closed.scale, closed.scale] } },
          { id: 'script', name: 'ChestScript', type: 'ScriptNode', scriptId: 'game.chest', parentId: 'body', order: 2, properties: { mapId: 'level-1', instanceId: 'chest-template', initialContents: {} } },
        ],
        instances: [],
        subresources: [
          { version: 1, resourceId: 'chest-wooden.sprite', kind: 'sprite-sheet', assetId, frameWidth: frame.w, frameHeight: frame.h, frameCount: frame.count },
          { version: 1, resourceId: 'chest-wooden.body-shape', kind: 'collision-shape', value: { shape: 'rectangle', width: closed.collider.width, height: closed.collider.height } },
        ],
      };
      outputs.push(convertedOutput(unit, 'objects/chest-wooden.scene.json', document, [
        '$.objectId', '$.selection', '$.variants', '$.physics', '$.behavior', '$.chest', '$.tags',
      ], [{ path: '$.$schema', owner: unit.oldSourcePath }]));
    }
    return outputs;
  },
};

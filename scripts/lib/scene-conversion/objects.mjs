import { convertedOutput, readJson, requireSupportedUnit } from './adapter-utils.mjs';

const COLLECTIBLE_KEYS = [
  'object:collectible.charcoal-pile',
  'object:collectible.crystal-shard',
  'object:collectible.energy-potion',
  'object:collectible.green-key',
  'object:collectible.hp-potion',
  'object:collectible.iron-ore-pile',
  'object:collectible.purple-berry',
  'object:collectible.silk-clump',
  'object:collectible.small-stone-pile',
  'object:collectible.small-wood-pile',
  'object:collectible.stone-pile',
  'object:collectible.wood-pile',
];
const PASSIVE_OBJECT_KEYS = [
  'object:decoration.world.floor',
  'object:decoration.world.solid',
  'object:house.world.solid',
  'object:rock.world-wall.decorative',
  'object:rock.world-wall.solid',
  'object:wall.stone.solid',
];
const SUPPORTED = new Set([
  'object:chest.wooden',
  'object:rock.amber-ore.mineable',
  'object:resource.stone-node',
  'object:tree.world.solid',
  ...COLLECTIBLE_KEYS,
  ...PASSIVE_OBJECT_KEYS,
]);

const OBJECT_ANIMATION_PATHS = {
  'object.tree.idle': 'src/game/content/animations/objects/tree/idle/animation.json',
  'object.tree.autumn.idle': 'src/game/content/animations/objects/tree/autumn/idle/animation.json',
  'object.tree.autumn.leaf-fall': 'src/game/content/animations/objects/tree/autumn/leaf-fall/animation.json',
};

function slug(value) {
  return value.replaceAll('.', '-').replace(/[^a-z0-9-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
}

function shapeValue(collider, scale) {
  if (collider.shape === 'circle') return { shape: 'circle', radius: (collider.radius ?? Math.min(collider.width, collider.height) / 2) * scale };
  if (collider.shape === 'ellipse') return { shape: 'ellipse', radiusX: (collider.radiusX ?? collider.width / 2) * scale, radiusY: (collider.radiusY ?? collider.height / 2) * scale };
  return { shape: 'rectangle', width: collider.width * scale, height: collider.height * scale };
}

function vectorProduct(first = [1, 1], second = [1, 1], scalar = 1) {
  return [first[0] * second[0] * scalar, first[1] * second[1] * scalar];
}

function vectorSum(first = [0, 0], second = [0, 0]) {
  return [first[0] + second[0], first[1] + second[1]];
}

function animationDocument(animationPackage, staticScale) {
  const animation = animationPackage.animation;
  if (animation.layers.length !== 1) throw new Error(`Object animation '${animationPackage.animationId}' must contain exactly one visual layer`);
  const layer = animation.layers[0];
  const layerTransform = layer.transform ?? {};
  const frameKeys = [];
  const offsetKeys = [];
  const scaleKeys = [];
  for (const block of layer.blocks) {
    const transform = block.transform ?? {};
    frameKeys.push({ at: block.from, value: block.sourceFrame });
    offsetKeys.push({ at: block.from, value: vectorSum(layerTransform.offset, transform.offset) });
    scaleKeys.push({ at: block.from, value: vectorProduct(layerTransform.scale, transform.scale, staticScale) });
  }
  return {
    durationSeconds: animation.durationSeconds,
    framesPerSecond: animation.framesPerSecond,
    loop: animation.loop,
    loopMode: animation.loopMode,
    tracks: [
      { binding: '../Visual', property: 'frame', keys: frameKeys },
      { binding: '../Visual', property: 'visualOffset', keys: offsetKeys },
      { binding: '../Visual', property: 'scale', keys: scaleKeys },
    ],
  };
}

async function animationLibrary(frame, staticScale, readSource) {
  const ids = [frame.idleAnimationId, frame.onHitAnimationId].filter(Boolean);
  if (ids.length === 0) return undefined;
  const animations = {};
  for (const id of ids) {
    const sourcePath = OBJECT_ANIMATION_PATHS[id];
    if (!sourcePath) throw new Error(`Object animation '${id}' has no scene conversion source`);
    const animationPackage = await readJson(readSource, sourcePath);
    animations[id] = animationDocument(animationPackage, staticScale);
  }
  return animations;
}

async function objectVisualScenes(unit, object, manifest, readSource, gameplayFieldPath = '$.resourceNode') {
  const frames = object.variants.flatMap((variant) => variant.frames.map((frame) => ({ assetId: variant.assetId, frame })));
  return Promise.all(frames.map(async ({ assetId, frame }, index) => {
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
    const animations = await animationLibrary(frame, scale, readSource);
    const animationResourceId = `${resourcePrefix}.animations`;
    const animationNode = animations ? {
      id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'body', order: 3,
      properties: { library: { resourceId: animationResourceId }, domain: 'physics', autoplay: frame.idleAnimationId },
    } : undefined;
    const document = {
      version: 1,
      sceneId: `object.${baseSlug}${sceneSuffix}`,
      rootNodeId: 'body',
      nodes: [
        { id: 'body', name: frame.displayName ?? frame.visualId, type: 'StaticBody2D', parentId: null, order: 0, properties: { collisionLayer: 1, collisionMask: 2, position: [0, 0] } },
        { id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: `${resourcePrefix}.shape` }, position: [(frame.collider.offsetX - visualOffset.x) * scale, (frame.collider.offsetY - visualOffset.y) * scale] } },
        { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'body', order: 1, properties: { texture: { resourceId: `${resourcePrefix}.sprite` }, frame: frame.frame, origin, scale: [scale, scale], visualOffset: [visualOffset.x, visualOffset.y], depthMode: 'world-sorted', depthBand: 'world-entities', ...(frame.occlusionBounds ? { occlusionBounds: frame.occlusionBounds } : {}), ...(frame.depthBounds ? { depthBounds: frame.depthBounds } : {}) } },
        { id: 'damage-area', name: 'DamageArea', type: 'Area2D', parentId: 'body', order: 2, properties: { collisionLayer: 8, collisionMask: 16, monitoring: true, monitorable: true } },
        { id: 'damage-shape', name: 'DamageShape', type: 'CollisionShape2D', parentId: 'damage-area', order: 0, properties: { shape: { resourceId: `${resourcePrefix}.shape` }, position: [(frame.collider.offsetX - visualOffset.x) * scale, (frame.collider.offsetY - visualOffset.y) * scale] } },
        ...(animationNode ? [animationNode] : []),
        {
          id: 'script', name: 'ResourceNodeScript', type: 'ScriptNode', scriptId: 'game.resource-node', parentId: 'body', order: animations ? 4 : 3,
          properties: {
            mapId: 'map-template', instanceId: 'resource-template', objectId: object.objectId,
            damageArea: { nodeId: 'damage-area' }, maxHealth: node.health, tags: object.tags,
            drop: node.drop, hitEffectId: node.hitEffectId ?? '', onHitAnimationId: frame.onHitAnimationId ?? '',
            persistHealth: node.persistHealth ?? true, depletionMessage: node.depletionMessage ?? '',
            harvestRequirement: node.harvestRequirement ?? {}, damageRule: { priority: 0, damageMultiplier: 1 },
            ...(frame.idleAnimationId ? { idleAnimationId: frame.idleAnimationId } : {}),
            ...(animations ? { animation: { nodeId: 'animation' } } : {}),
          },
        },
      ],
      instances: [],
      subresources: [
        { version: 1, resourceId: `${resourcePrefix}.sprite`, kind: 'sprite-sheet', assetId, frameWidth: asset.source.frame.w, frameHeight: asset.source.frame.h, frameCount: asset.source.frame.count },
        { version: 1, resourceId: `${resourcePrefix}.shape`, kind: 'collision-shape', value: shapeValue(frame.collider, scale) },
        ...(animations ? [{ version: 1, resourceId: animationResourceId, kind: 'animation-library', animations }] : []),
      ],
    };
    return convertedOutput(unit, `objects/${baseSlug}${fileSuffix}.scene.json`, document, [
      '$.objectId', '$.selection', '$.variants', '$.physics', '$.behavior', gameplayFieldPath, '$.tags',
    ], [{ path: '$.$schema', owner: unit.oldSourcePath }]);
  }));
}

function destructibleResourceNode(object, items) {
  const dropIds = object.destructible?.drops;
  if (!Array.isArray(dropIds) || dropIds.length === 0) {
    throw new Error(`Destructible object '${object.objectId}' requires at least one authored drop`);
  }
  const uniqueDropIds = [...new Set(dropIds)];
  if (uniqueDropIds.length !== 1) {
    throw new Error(`Destructible object '${object.objectId}' requires one repeatable item drop for resource conversion`);
  }
  const item = items[uniqueDropIds[0]];
  if (!item?.worldDrop?.objectId || !item.worldDrop.visualId) {
    throw new Error(`Destructible object '${object.objectId}' drop '${uniqueDropIds[0]}' has no world-drop presentation`);
  }
  return {
    ...object,
    resourceNode: {
      health: object.destructible.health,
      drop: {
        objectId: item.worldDrop.objectId,
        visualId: item.worldDrop.visualId,
        pieces: dropIds.length,
      },
      persistHealth: true,
      depletionMessage: 'Ore depleted',
    },
  };
}

function collectibleScene(unit, object, manifest) {
  const variant = object.variants[0];
  const frame = variant.frames[0];
  const asset = manifest.assets[variant.assetId];
  if (!asset) throw new Error(`Collectible '${object.objectId}' references missing asset '${variant.assetId}'`);
  const scale = frame.scale ?? 1;
  const visualOffset = frame.visualOffset ?? { x: 0, y: 0 };
  const origin = Array.isArray(asset.render?.origin) ? asset.render.origin : [0.5, 1];
  const objectSlug = slug(object.objectId);
  const resourcePrefix = `${objectSlug}.${slug(frame.visualId)}`;
  const sourceWidth = asset.source.kind === 'spritesheet' ? asset.source.frame.w : 16;
  const sourceHeight = asset.source.kind === 'spritesheet' ? asset.source.frame.h : 16;
  const pickupRadius = Math.max(12, Math.min(32, Math.min(sourceWidth, sourceHeight) * scale * 0.28));
  const textureResource = asset.source.kind === 'spritesheet'
    ? { version: 1, resourceId: `${resourcePrefix}.sprite`, kind: 'sprite-sheet', assetId: variant.assetId, frameWidth: sourceWidth, frameHeight: sourceHeight, frameCount: asset.source.frame.count }
    : { version: 1, resourceId: `${resourcePrefix}.sprite`, kind: 'texture', assetId: variant.assetId };
  const document = {
    version: 1,
    sceneId: `object.${objectSlug}`,
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: frame.displayName ?? frame.visualId, type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
      { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0, properties: { texture: { resourceId: `${resourcePrefix}.sprite` }, frame: frame.frame, origin, scale: [scale, scale], visualOffset: [visualOffset.x, visualOffset.y], depthMode: 'world-sorted', depthBand: 'world-entities' } },
      { id: 'pickup-area', name: 'PickupArea', type: 'Area2D', parentId: 'root', order: 1, properties: { collisionLayer: 64, collisionMask: 32, monitoring: true, monitorable: true } },
      { id: 'pickup-shape', name: 'PickupShape', type: 'CollisionShape2D', parentId: 'pickup-area', order: 0, properties: { shape: { resourceId: `${resourcePrefix}.pickup-shape` }, position: [visualOffset.x * scale, visualOffset.y * scale] } },
      {
        id: 'script', name: 'CollectibleScript', type: 'ScriptNode', scriptId: 'game.collectible', parentId: 'root', order: 2,
        properties: {
          mapId: 'map-template', instanceId: 'collectible-template', objectId: object.objectId,
          itemId: object.collectible.itemId, quantity: object.collectible.quantity,
          pickupArea: { nodeId: 'pickup-area' },
        },
      },
    ],
    instances: [],
    connections: [
      { source: { nodeId: 'pickup-area' }, signal: 'area_entered', target: { nodeId: 'script' }, handler: 'on_area_entered' },
    ],
    subresources: [
      textureResource,
      { version: 1, resourceId: `${resourcePrefix}.pickup-shape`, kind: 'collision-shape', value: { shape: 'circle', radius: pickupRadius } },
    ],
  };
  return convertedOutput(unit, `objects/${objectSlug}.scene.json`, document, [
    '$.objectId', '$.selection', '$.variants', '$.physics', '$.behavior', '$.collectible', '$.tags',
  ], [{ path: '$.$schema', owner: unit.oldSourcePath }]);
}

function passiveObjectScenes(unit, object, manifest) {
  const frames = object.variants.flatMap((variant) => variant.frames.map((frame) => ({ assetId: variant.assetId, frame })));
  return frames.map(({ assetId, frame }, index) => {
    const asset = manifest.assets[assetId];
    if (!asset || asset.source.kind !== 'spritesheet') {
      throw new Error(`Object '${object.objectId}' visual '${frame.visualId}' requires a spritesheet asset`);
    }
    const solid = object.physics?.body === 'static';
    if (solid && !frame.collider) throw new Error(`Solid object '${object.objectId}' visual '${frame.visualId}' requires a collider`);
    const scale = frame.scale ?? 1;
    const visualOffset = frame.visualOffset ?? { x: 0, y: 0 };
    const objectSlug = slug(object.objectId);
    const visualSlug = slug(frame.visualId);
    const sceneSuffix = index === 0 ? '' : `.${visualSlug}`;
    const fileSuffix = index === 0 ? '' : `--${visualSlug}`;
    const resourcePrefix = `${objectSlug}.${visualSlug}`;
    const rootId = solid ? 'body' : 'root';
    const document = {
      version: 1,
      sceneId: `object.${objectSlug}${sceneSuffix}`,
      rootNodeId: rootId,
      nodes: [
        {
          id: rootId,
          name: frame.displayName ?? frame.visualId,
          type: solid ? 'StaticBody2D' : 'Node2D',
          parentId: null,
          order: 0,
          properties: solid
            ? { collisionLayer: 1, collisionMask: 2, position: [0, 0] }
            : { position: [0, 0] },
        },
        ...(solid ? [{
          id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: rootId, order: 0,
          properties: {
            shape: { resourceId: `${resourcePrefix}.shape` },
            position: [(frame.collider.offsetX - visualOffset.x) * scale, (frame.collider.offsetY - visualOffset.y) * scale],
          },
        }] : []),
        {
          id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: rootId, order: solid ? 1 : 0,
          properties: {
            texture: { resourceId: `${resourcePrefix}.sprite` }, frame: frame.frame,
            origin: Array.isArray(asset.render?.origin) ? asset.render.origin : [0.5, 1],
            scale: [scale, scale], visualOffset: [visualOffset.x, visualOffset.y],
            depthMode: 'world-sorted', depthBand: 'world-entities',
            ...(frame.occlusionBounds ? { occlusionBounds: frame.occlusionBounds } : {}),
            ...(frame.depthBounds ? { depthBounds: frame.depthBounds } : {}),
          },
        },
      ],
      instances: [],
      subresources: [
        { version: 1, resourceId: `${resourcePrefix}.sprite`, kind: 'sprite-sheet', assetId, frameWidth: asset.source.frame.w, frameHeight: asset.source.frame.h, frameCount: asset.source.frame.count },
        ...(solid ? [{ version: 1, resourceId: `${resourcePrefix}.shape`, kind: 'collision-shape', value: shapeValue(frame.collider, scale) }] : []),
      ],
    };
    return convertedOutput(unit, `objects/${objectSlug}${fileSuffix}.scene.json`, document, [
      '$.objectId', '$.selection', '$.variants', '$.physics', '$.tags',
    ], [{ path: '$.$schema', owner: unit.oldSourcePath }]);
  });
}

export const objectSceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    const manifest = await readJson(readSource, 'asset/assets.json');
    const items = await readJson(readSource, 'src/game/content/items/items.json');
    for (const unit of units) {
      requireSupportedUnit(unit, SUPPORTED);
      const object = await readJson(readSource, unit.oldSourcePath);
      if (COLLECTIBLE_KEYS.includes(unit.key)) {
        outputs.push(collectibleScene(unit, object, manifest));
        continue;
      }
      if (PASSIVE_OBJECT_KEYS.includes(unit.key)) {
        outputs.push(...passiveObjectScenes(unit, object, manifest));
        continue;
      }
      if (unit.key === 'object:resource.stone-node' || unit.key === 'object:tree.world.solid') {
        outputs.push(...await objectVisualScenes(unit, object, manifest, readSource));
        continue;
      }
      if (unit.key === 'object:rock.amber-ore.mineable') {
        outputs.push(...await objectVisualScenes(
          unit,
          destructibleResourceNode(object, items),
          manifest,
          readSource,
          '$.destructible',
        ));
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

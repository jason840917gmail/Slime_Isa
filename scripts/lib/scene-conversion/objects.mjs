import { convertedOutput, readJson, requireSupportedUnit } from './adapter-utils.mjs';

const SUPPORTED = new Set(['object:chest.wooden']);

export const objectSceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    for (const unit of units) {
      requireSupportedUnit(unit, SUPPORTED);
      const object = await readJson(readSource, unit.oldSourcePath);
      const closed = object.variants[0].frames.find((frame) => frame.visualId === 'wooden-closed');
      const manifest = await readJson(readSource, 'asset/assets.json');
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

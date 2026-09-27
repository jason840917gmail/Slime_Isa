import { contentSha256 } from './contentHash.mjs';

import { convertedOutput, readJson } from './adapter-utils.mjs';

const DESCRIPTOR_PATH = 'scripts/migrations/ui-extraction-descriptors.json';

function sha256(value) {
  return contentSha256(value);
}

function sceneDocument(descriptor, themeResourceId) {
  const rootType = descriptor.modal ? 'ModalRoot' : 'Container';
  const rootProperties = {
    ...descriptor.layoutValues,
    theme: { resourceId: themeResourceId },
    styleClass: `game-ui game-ui--${descriptor.id}`,
    ariaLabel: descriptor.id.replaceAll('-', ' '),
    zIndex: descriptor.modal ? 90 : 20,
    ...(descriptor.modal ? { open: false, focused: false, inputPriority: 2000 } : { visible: true }),
  };
  const orderByParent = new Map();
  const controls = descriptor.controls.map((control) => {
    const parentId = control.parentId ?? 'surface';
    const order = orderByParent.get(parentId) ?? 0;
    orderByParent.set(parentId, order + 1);
    return { id: control.id, name: control.name, type: control.type, parentId, order, properties: control.properties };
  });
  const connections = [
    ...(descriptor.modal ? [{
      source: { nodeId: 'surface' }, signal: 'close_requested', target: { nodeId: 'script' }, handler: 'on_close_action',
    }] : []),
    ...descriptor.controls.flatMap((control) => [
      ...(control.signal && control.handler ? [{
        source: { nodeId: control.id }, signal: control.signal, target: { nodeId: 'script' }, handler: control.handler,
      }] : []),
      ...(control.secondarySignal && control.secondaryHandler ? [{
        source: { nodeId: control.id }, signal: control.secondarySignal, target: { nodeId: 'script' }, handler: control.secondaryHandler,
      }] : []),
    ]),
  ];
  return {
    version: 1,
    sceneId: descriptor.sceneId,
    rootNodeId: 'surface',
    nodes: [
      { id: 'surface', name: descriptor.id, type: rootType, parentId: null, order: 0, properties: rootProperties },
      ...controls,
      {
        id: 'script', name: 'UiSurfaceScript', type: 'ScriptNode', scriptId: 'game.ui-surface', parentId: 'surface', order: orderByParent.get('surface') ?? 0,
        properties: { surfaceId: descriptor.id, modal: descriptor.modal, bindings: descriptor.bindings, actions: descriptor.actions },
      },
    ],
    instances: [],
    ...(connections.length > 0 ? { connections } : {}),
    subresources: descriptor.resources ?? [],
  };
}

export const uiSceneAdapter = {
  family: 'ui',
  async convert({ units, readSource }) {
    const extraction = await readJson(readSource, DESCRIPTOR_PATH);
    if (extraction.version !== 1 || !Array.isArray(extraction.surfaces)) throw new Error('UI extraction descriptors require version 1 and a surfaces array');
    const byId = new Map(extraction.surfaces.map((descriptor) => [descriptor.id, descriptor]));
    if (byId.size !== extraction.surfaces.length) throw new Error('UI extraction descriptors contain duplicate surface IDs');
    return Promise.all(units.map(async (unit) => {
      const descriptor = byId.get(unit.stableId);
      if (!descriptor) throw new Error(`UI conversion has no extraction descriptor for '${unit.key}'`);
      if (descriptor.sourcePath !== unit.oldSourcePath) throw new Error(`UI descriptor '${descriptor.id}' source path differs from the conversion ledger`);
      const destinationSceneId = unit.destinationId.replace('scene://', '').replace('/', '.');
      if (descriptor.sceneId !== destinationSceneId) throw new Error(`UI descriptor '${descriptor.id}' destination differs from the conversion ledger`);
      const source = await readSource(descriptor.sourcePath);
      const sourceHash = sha256(source);
      if (sourceHash !== descriptor.sourceHash) throw new Error(`UI descriptor source hash changed for '${unit.key}'`);
      if (unit.sourceHash !== sourceHash) throw new Error(`UI conversion ledger source hash changed for '${unit.key}'`);
      return convertedOutput(
        unit,
        `ui/${descriptor.id}.scene.json`,
        sceneDocument(descriptor, extraction.themeResourceId),
        ['$.sourceHash', '$.layoutValues', '$.themeValues', '$.bindings', '$.actions', '$.controls', ...(descriptor.resources ? ['$.resources'] : [])],
        [{ path: '$.sourcePath', owner: descriptor.sourcePath }],
      );
    }));
  },
};

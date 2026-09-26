import '../../../../src/game/editor/scene-studio/scene-studio.css';

import { createCoreDescriptorRegistry } from '../../../../src/game/content/scenes/propertyDescriptors';
import { authoredNodeId, sceneId } from '../../../../src/game/content/scenes/identifiers';
import type { SceneDocument } from '../../../../src/game/content/scenes/types';
import type { TileDataResourceDocument, TileSetResourceDocument } from '../../../../src/game/content/scenes/resources/types';
import { ScenePreview } from '../../../../src/game/editor/scene-studio/ScenePreview';
import { SceneStudioController } from '../../../../src/game/editor/scene-studio/SceneStudio';
import { SceneStudioRepository } from '../../../../src/game/infrastructure/scenes/editor/SceneStudioRepository';

const app = document.querySelector<HTMLDivElement>('#app');
if (!app) throw new Error('Scene Studio fixture mount is missing');

let documentValue: SceneDocument = {
  version: 1,
  sceneId: sceneId('browser.studio'),
  rootNodeId: authoredNodeId('root'),
  nodes: [
    { id: authoredNodeId('root'), name: 'BrowserScene', type: 'Node2D', parentId: null, order: 0, properties: {} },
    { id: authoredNodeId('child'), name: 'Scout', type: 'Node2D', parentId: authoredNodeId('root'), order: 0, properties: { position: [16, 24] } },
    { id: authoredNodeId('script'), name: 'Behavior', type: 'ScriptNode', scriptId: 'fixture.actor', parentId: authoredNodeId('root'), order: 1, properties: { health: 5 } },
    { id: authoredNodeId('layer-ground'), name: 'Ground', type: 'TileMapLayer2D', parentId: authoredNodeId('root'), order: 2, properties: { position: [0, 0], tileData: { resourceId: 'tiles.browser.ground.data' }, tileSize: 64, seed: 1, depth: 0, collisionLayer: 1, collisionMask: 2, collisionEnabled: true, editorLocked: false } },
  ],
  instances: [],
};
let tileDataValue: TileDataResourceDocument = {
  version: 1,
  resourceId: 'tiles.browser.ground.data' as TileDataResourceDocument['resourceId'],
  kind: 'tile-data',
  tileSet: 'tiles.browser.ground.set' as TileDataResourceDocument['tileSet'],
  columns: 4,
  rows: 3,
  cells: [{ x: 0, y: 0, tileId: 'grass' }],
};
let tileSetValue: TileSetResourceDocument = {
  version: 1,
  resourceId: 'tiles.browser.ground.set' as TileSetResourceDocument['resourceId'],
  kind: 'tile-set',
  tiles: {
    grass: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order', physics: null, allowsDecorations: true, tags: ['ground'] },
    wall: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order', physics: { body: 'static' }, allowsDecorations: false, tags: ['solid'] },
  },
};
let hash = 'a'.repeat(64);
let conflict = false;
let savedCount = 0;
let lastWriteIds: string[] = [];
let openedSource: string | undefined;
app.addEventListener('scene-studio-open-source', (event) => { openedSource = (event as CustomEvent<{ path: string }>).detail.path; });

const response = (value: unknown, status = 200): Response => new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
const request: typeof fetch = async (_input, init) => {
  if (init?.method === 'POST') {
    if (conflict) return response({ error: 'newer disk version' }, 409);
    const payload = JSON.parse(String(init.body)) as { writes: Array<{ kind: 'scene' | 'resource'; id: string; relativePath: string; document: SceneDocument | TileDataResourceDocument | TileSetResourceDocument }> };
    lastWriteIds = payload.writes.map((write) => write.id);
    for (const write of payload.writes) {
      if (write.kind === 'scene') documentValue = structuredClone(write.document as SceneDocument);
      else if (write.id === tileDataValue.resourceId) tileDataValue = structuredClone(write.document as TileDataResourceDocument);
      else if (write.id === tileSetValue.resourceId) tileSetValue = structuredClone(write.document as TileSetResourceDocument);
    }
    hash = 'b'.repeat(64);
    savedCount += 1;
    return response({ writes: payload.writes.map((write) => ({ kind: write.kind, id: write.id, relativePath: write.relativePath, hash })) });
  }
  const url = String(_input);
  if (url.includes('action=list')) return response({ items: [
    { kind: 'scene', id: documentValue.sceneId, relativePath: 'browser.scene.json' },
    { kind: 'resource', id: tileDataValue.resourceId, relativePath: 'authored/resources/tiles/browser.ground.tile-data.resource.json' },
    { kind: 'resource', id: tileSetValue.resourceId, relativePath: 'authored/resources/tiles/browser.ground.tile-set.resource.json' },
  ] });
  if (url.includes(encodeURIComponent(String(tileDataValue.resourceId)))) return response({ item: { kind: 'resource', id: tileDataValue.resourceId, relativePath: 'authored/resources/tiles/browser.ground.tile-data.resource.json', document: tileDataValue, hash, repairMode: false, issues: [] } });
  if (url.includes(encodeURIComponent(String(tileSetValue.resourceId)))) return response({ item: { kind: 'resource', id: tileSetValue.resourceId, relativePath: 'authored/resources/tiles/browser.ground.tile-set.resource.json', document: tileSetValue, hash, repairMode: false, issues: [] } });
  return response({ item: { kind: 'scene', id: documentValue.sceneId, relativePath: 'browser.scene.json', document: documentValue, hash, repairMode: false, issues: [] } });
};
const registry = createCoreDescriptorRegistry([{ scriptId: 'fixture.actor', displayName: 'Actor behavior', sourcePath: 'fixtures/Actor.ts', capabilities: ['actor'], properties: [{ key: 'health', label: 'Health', group: 'Actor', value: { kind: 'number', integer: true, min: 1 }, defaultValue: 5, serialized: true, inspector: 'number', overridable: true }] }]);
const controller = new SceneStudioController(app, new SceneStudioRepository('/fixture-content', request), registry);
await controller.start();

declare global {
  interface Window {
    sceneStudioFixture: {
      ready(): boolean;
      setConflict(value: boolean): void;
      snapshot(): { savedCount: number; nodeCount: number; tileCells: number; tileSetTiles: number; lastWriteIds: readonly string[]; openedSource?: string };
      previewIsolation(): { scripts: number; persistence: boolean; disposed: boolean };
      destroy(): void;
    };
  }
}

window.sceneStudioFixture = {
  ready: () => Boolean(document.querySelector('[data-scene-studio] [data-scene-tree-key]')),
  setConflict(value) { conflict = value; },
  snapshot: () => ({ savedCount, nodeCount: documentValue.nodes.length, tileCells: tileDataValue.cells.length, tileSetTiles: Object.keys(tileSetValue.tiles).length, lastWriteIds, ...(openedSource ? { openedSource } : {}) }),
  previewIsolation() {
    let scripts = -1;
    let persistence = true;
    let disposed = false;
    const preview = new ScenePreview({ create(document, capabilities) { scripts = document.nodes.filter((node) => node.type === 'ScriptNode').length; persistence = capabilities.has('persistence'); return { dispose() { disposed = true; } }; } });
    preview.open(documentValue);
    preview.close();
    return { scripts, persistence, disposed };
  },
  destroy() { controller.destroy(); },
};

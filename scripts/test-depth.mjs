import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

async function loadTypeScriptModule(relativePath) {
  const source = await fs.readFile(relativePath, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ESNext,
    },
    fileName: relativePath,
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
}

const depth = await loadTypeScriptModule('src/game/presentation/WorldDepth.ts');
const occlusion = await loadTypeScriptModule('src/game/presentation/WorldOcclusion.ts');

test('depth bands do not overlap the complete supported Y-sorted range', () => {
  const first = depth.resolveWorldDepth(0).depth;
  const last = depth.resolveWorldDepth(depth.MAX_SORT_ANCHOR_Y).depth;
  assert.ok(first > depth.DEPTH_BANDS['ground-decals']);
  assert.ok(last < depth.DEPTH_BANDS['overhead-artwork']);
  assert.ok(depth.DEPTH_BANDS['overhead-artwork'] > last);
});

test('anchor resolvers use body geometry and preserve authored object anchors', () => {
  assert.equal(depth.resolveBodyBottom({ y: 30, height: 22 }), 52);
  assert.equal(depth.resolveBodyCenterY({ y: 30, height: 22 }), 41);
  assert.equal(depth.resolveObjectGroundAnchorY(1234), 1234);
  assert.equal(depth.resolveWorldDepth(-10).groundAnchorY, 0);
  assert.equal(depth.resolveWorldDepth(Infinity).groundAnchorY, 0);
  assert.equal(depth.resolveWorldDepth(depth.MAX_SORT_ANCHOR_Y + 50).groundAnchorY, depth.MAX_SORT_ANCHOR_Y);
});

test('stable ties and attachment slots are deterministic and local', () => {
  const first = depth.resolveWorldDepth(200, { stableId: 'tree-a' });
  const second = depth.resolveWorldDepth(200, { stableId: 'tree-a' });
  const attached = depth.resolveWorldDepth(200, { stableId: 'tree-a', attachmentSlot: 7 });
  assert.deepEqual(first, second);
  assert.equal(attached.depth - first.depth, 7);
  assert.equal(depth.resolveWorldDepth(200, { stableId: 'tree-a', attachmentSlot: -100 }).attachmentSlot, -7);
  assert.equal(depth.resolveWorldDepth(200, { stableId: 'tree-a', attachmentSlot: 100 }).attachmentSlot, 7);
  assert.ok(depth.resolveWorldDepth(200.06, { stableId: 'tree-a' }).depth > first.depth);
});

test('source-space occlusion bounds transform across origin, scale, and flips', () => {
  const frame = { width: 128, height: 170 };
  const bounds = { width: 96, height: 112, offsetX: 16, offsetY: 8 };
  const origins = [[0, 0], [0.5, 1], [1, 0.5]];
  for (const [originX, originY] of origins) {
    for (const flipX of [false, true]) {
      for (const flipY of [false, true]) {
        const rectangle = occlusion.resolveWorldOcclusionRectangle({
          x: 400,
          y: 300,
          originX,
          originY,
          scaleX: 2,
          scaleY: -1.5,
          flipX,
          flipY,
        }, frame, bounds);
        const frameTopLeft = occlusion.resolveRenderedFrameTopLeft({
          x: 400,
          y: 300,
          originX,
          originY,
          scaleX: 2,
          scaleY: -1.5,
          flipX,
          flipY,
        }, frame);
        assert.equal(rectangle.width, 192);
        assert.equal(rectangle.height, 168);
        const sourceX = flipX ? frame.width - bounds.offsetX - bounds.width : bounds.offsetX;
        const sourceY = flipY ? frame.height - bounds.offsetY - bounds.height : bounds.offsetY;
        assert.equal(rectangle.x, frameTopLeft.x + sourceX * 2);
        assert.equal(rectangle.y, frameTopLeft.y + sourceY * 1.5);
      }
    }
  }
});

test('source alpha masks keep only opaque pixels and compact vertical runs', () => {
  const mask = occlusion.buildSourceAlphaMask(
    { width: 6, height: 4 },
    (x, y) => (x >= 1 && x <= 3 && y <= 2) || (x === 5 && y === 3) ? 255 : 0,
  );
  assert.equal(mask.opaqueArea, 10);
  assert.deepEqual(mask.runs, [
    { x: 1, y: 0, width: 3, height: 3 },
    { x: 5, y: 3, width: 1, height: 1 },
  ]);
  assert.deepEqual(
    occlusion.resolveWorldAlphaMaskRuns(
      { x: 100, y: 80, originX: 0, originY: 0, scaleX: 2, scaleY: 2, flipX: false, flipY: false },
      { width: 6, height: 4 },
      mask,
    ),
    [
      { x: 102, y: 80, width: 6, height: 6 },
      { x: 110, y: 86, width: 2, height: 2 },
    ],
  );
});

test('occlusion overlap uses strict rectangle intersection and query margins expand symmetrically', () => {
  const a = { x: 10, y: 10, width: 20, height: 20 };
  assert.equal(occlusion.rectanglesIntersect(a, { x: 30, y: 10, width: 5, height: 5 }), false);
  assert.equal(occlusion.rectanglesIntersect(a, { x: 29.9, y: 10, width: 5, height: 5 }), true);
  assert.deepEqual(occlusion.expandRectangle(a, 32), { x: -22, y: -22, width: 84, height: 84 });
});

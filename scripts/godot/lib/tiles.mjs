/**
 * Ground tiles: the shared `terrain.tiles` TileSet and each world's
 * TileMapLayer (`tile_map_data` + generated collision bodies).
 *
 * Frame selection is exactly Phaser's (TileMapLayer2DNode.resolveVisual):
 * the asset is `assetIds[tileHash(x, y, seed) % n]`; `sheet-wrap` shows frame
 * (x mod cols, y mod rows); `seeded-hash` shows the whole image at frame 0.
 * The 128-px interior floors on the 64-px grid are overdrawn by the next
 * cells in Phaser, so every cell shows the top-left 64-px quadrant: their
 * atlas sources use a 64-px region and atlas coords (0, 0).
 *
 * Collision is not per cell: Phaser merges same-tile solid cells into
 * rectangles (rows first, then equal runs stacked) and insets only the outer
 * edges (default 6/6/8/8). The converter emits one StaticBody2D per merged
 * rectangle under a `TileCollision` child and leaves TileSet physics empty.
 *
 * `tile_map_data` layout (checked against a scene saved by Godot 4.7.2):
 * uint16 format (0), then 12 bytes per cell, little-endian:
 * int16 x, int16 y, uint16 source, uint16 atlas x, uint16 atlas y, uint16 alternative.
 */
import { gd, writeTres } from './tscn.mjs';

export const TILESET_RES_PATH = 'res://generated/resources/terrain_tileset.tres';
const DEFAULT_INSET = { left: 6, right: 6, top: 8, bottom: 8 };

/** Phaser's tile hash (32-bit wrapping multiply, unsigned result). */
export function tileHash(x, y, seed) {
  return (Math.imul(x + seed * 17, 374761393) ^ Math.imul(y - seed * 31, 668265263)) >>> 0;
}

/**
 * Deterministic greedy rectangle cover of a cell set (port of Phaser's
 * mergeCellRectangles): horizontal runs per row, then runs with the same
 * span on consecutive rows stack into one rectangle.
 */
export function mergeCellRectangles(cells) {
  const byRow = new Map();
  for (const { x, y } of cells) {
    if (!byRow.has(y)) byRow.set(y, []);
    byRow.get(y).push(x);
  }
  let open = new Map();
  const done = [];
  for (const y of [...byRow.keys()].sort((a, b) => a - b)) {
    const runs = [];
    for (const x of byRow.get(y).sort((a, b) => a - b)) {
      const last = runs.at(-1);
      if (last && last.x + last.width === x) last.width += 1;
      else if (!last || last.x + last.width - 1 !== x) runs.push({ x, width: 1 });
    }
    const next = new Map();
    for (const run of runs) {
      const key = `${run.x}:${run.width}`;
      const rect = open.get(key);
      if (rect && rect.y + rect.height === y) {
        rect.height += 1;
        open.delete(key);
        next.set(key, rect);
      } else {
        next.set(key, { x: run.x, y, width: run.width, height: 1 });
      }
    }
    done.push(...open.values());
    open = next;
  }
  done.push(...open.values());
  return done.sort((a, b) => a.y - b.y || a.x - b.x);
}

/**
 * The TileSet: one atlas source per (tile id, asset), in tile declaration
 * order, with a `tile_id` custom data layer on every tile.
 * Returns { text, sources: Map tileId → [{ sourceId, assetId, cols, rows, wrap }] }.
 */
export function buildTileSet(tileSetResource, assets, report) {
  const sources = new Map();
  const props = [
    ['tile_size', gd.vec2i(64, 64)],
    ['custom_data_layer_0/name', 'tile_id'],
    ['custom_data_layer_0/type', 4],
  ];
  let nextSource = 0;
  for (const [tileId, tile] of Object.entries(tileSetResource.tiles)) {
    const list = [];
    for (const assetId of tile.assetIds) {
      const grid = assets.grid(assetId);
      const wrap = tile.selection === 'sheet-wrap';
      if (!wrap && tile.selection !== 'seeded-hash') {
        report.warnGlobal('tile-selection-unsupported', `tile '${tileId}' uses selection '${tile.selection}'; frame 0 is used`);
      }
      if (wrap && (grid.frameW !== 64 || grid.frameH !== 64)) {
        report.warnGlobal('tile-frame-size', `tile '${tileId}' sheet frames are ${grid.frameW}×${grid.frameH}, not 64×64`);
      }
      const cols = wrap ? grid.cols : 1;
      const rows = wrap ? grid.rows : 1;
      const sourceProps = [
        ['texture', assets.texture(assetId)],
        ['texture_region_size', gd.vec2i(wrap ? grid.frameW : 64, wrap ? grid.frameH : 64)],
        ['resource_name', `${tileId}:${assetId}`],
      ];
      for (let y = 0; y < rows; y += 1) {
        for (let x = 0; x < cols; x += 1) {
          sourceProps.push([`${x}:${y}/0`, 0]);
          sourceProps.push([`${x}:${y}/0/custom_data_0`, tileId]);
        }
      }
      const sourceId = nextSource;
      nextSource += 1;
      props.push([`sources/${sourceId}`, gd.sub('TileSetAtlasSource', `${tileId}:${assetId}`, sourceProps)]);
      list.push({ sourceId, assetId, cols, rows, wrap });
    }
    sources.set(tileId, list);
  }
  return { text: writeTres('TileSet', props), sources };
}

function encodeCells(cells) {
  const bytes = Buffer.alloc(2 + cells.length * 12);
  bytes.writeUInt16LE(0, 0);
  cells.forEach((cell, index) => {
    const offset = 2 + index * 12;
    bytes.writeInt16LE(cell.x, offset);
    bytes.writeInt16LE(cell.y, offset + 2);
    bytes.writeUInt16LE(cell.source, offset + 4);
    bytes.writeUInt16LE(cell.atlasX, offset + 6);
    bytes.writeUInt16LE(cell.atlasY, offset + 8);
    bytes.writeUInt16LE(0, offset + 10);
  });
  return [...bytes];
}

/**
 * TileMapLayer2D → TileMapLayer properties plus the `TileCollision` child.
 * Returns { props, children }.
 */
export function convertTileLayer(ctx) {
  const p = ctx.props;
  const project = ctx.project;
  const data = p.tileData?.resourceId ? ctx.resource(p.tileData.resourceId, 'tile-data') : null;
  const props = [['z_index', -2]];
  ctx.node2d(props, {});
  if (!data) {
    ctx.warn('tile-data-missing', `${ctx.label}: no tile-data resource`);
    return { props, children: [] };
  }
  if (data.tileSet !== 'terrain.tiles') ctx.warn('tile-set-unknown', `${ctx.label}: tile set '${data.tileSet}' is not terrain.tiles`);
  const tileSize = p.tileSize ?? 64;
  if (tileSize !== 64) ctx.warn('tile-size', `${ctx.label}: tileSize ${tileSize} differs from the 64-px TileSet`);
  const seed = p.seed ?? 0;
  const tiles = project.tileSetResource.tiles;
  const cells = [];
  const solidCells = new Map();
  for (const cell of data.cells) {
    const tile = tiles[cell.tileId];
    const sources = project.tileSources.get(cell.tileId);
    if (!tile || !sources) {
      ctx.warn('tile-unknown', `${ctx.label}: unknown tile id '${cell.tileId}'`);
      continue;
    }
    const source = sources[tileHash(cell.x, cell.y, seed) % sources.length];
    const atlasX = source.wrap ? ((cell.x % source.cols) + source.cols) % source.cols : 0;
    const atlasY = source.wrap ? ((cell.y % source.rows) + source.rows) % source.rows : 0;
    cells.push({ x: cell.x, y: cell.y, source: source.sourceId, atlasX, atlasY });
    if (tile.physics) {
      if (!solidCells.has(cell.tileId)) solidCells.set(cell.tileId, []);
      solidCells.get(cell.tileId).push(cell);
    }
  }
  props.push(['tile_map_data', gd.packedByte(encodeCells(cells))]);
  props.push(['tile_set', gd.ext('TileSet', TILESET_RES_PATH)]);
  props.push(['metadata/tile_seed', seed]);
  props.push(['metadata/source_cell_count', data.cells.length]);
  props.push(['metadata/columns', data.columns]);
  props.push(['metadata/rows', data.rows]);
  for (const key of ['editorLocked', 'collisionMask', 'depth', 'collisionEnabled']) if (p[key] !== undefined) ctx.report.dropped('TileMapLayer2D', key);
  if (p.collisionEnabled === false) return { props, children: [] };
  return { props, children: [collisionChild(ctx, tiles, solidCells, tileSize)] };
}

/** One StaticBody2D per merged rectangle, with the tile's inset on outer edges. */
function collisionChild(ctx, tiles, solidCells, tileSize) {
  const layerBits = ctx.project.collisionLayerBits;
  const bodies = [];
  for (const [tileId, cells] of solidCells) {
    const physics = tiles[tileId].physics;
    const inset = { ...DEFAULT_INSET, ...physics.inset };
    const layer = physics.layer === undefined ? (ctx.props.collisionLayer ?? 1) : layerBits.get(physics.layer);
    if (layer === undefined) ctx.warn('tile-collision-layer', `${ctx.label}: tile '${tileId}' names unknown layer '${physics.layer}'`);
    for (const rect of mergeCellRectangles(cells)) {
      const x = rect.x * tileSize + inset.left;
      const y = rect.y * tileSize + inset.top;
      const width = rect.width * tileSize - inset.left - inset.right;
      const height = rect.height * tileSize - inset.top - inset.bottom;
      const shape = gd.sub('RectangleShape2D', `tile-rect:${width}x${height}`, [['size', gd.vec2(width, height)]]);
      bodies.push({
        name: `${tileId}_${rect.x}_${rect.y}`,
        type: 'StaticBody2D',
        props: [['position', gd.vec2(x + width / 2, y + height / 2)], ['collision_layer', layer ?? 1], ['collision_mask', 0]],
        children: [{ name: 'Shape', type: 'CollisionShape2D', props: [['shape', shape]], children: [] }],
      });
    }
  }
  return { name: 'TileCollision', type: 'Node2D', props: [], children: bodies };
}

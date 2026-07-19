#!/usr/bin/env node
/**
 * assets:check — validates asset/assets.json against disk truth.
 *
 * Checks (every error names the asset ID and field):
 *   1. Manifest parses and matches the v1 structural contract.
 *   2. runtime.textureKey values are unique.
 *   3. Bundles reference existing asset IDs.
 *   4. source paths exist under asset/ with exact casing (no '..' escapes).
 *   5. source.expect dimensions match the real PNG header; spritesheet
 *      frames divide the image evenly; grid cut-lines are ascending and
 *      in bounds.
 *   6. derived sources reference an existing image/spritesheet asset and a
 *      crop cell inside its grid.
 *   7. Orphan detection: every .png under asset/ is either mapped or
 *      covered by an ignore pattern.
 *
 * No third-party dependencies; run via `pnpm assets:check`.
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const assetRoot = join(repoRoot, 'asset');
const manifestPath = join(assetRoot, 'assets.json');

const SOURCE_KINDS = new Set(['image', 'spritesheet', 'atlas', 'audio', 'tilemap', 'derived', 'procedural']);
const PATH_KINDS = new Set(['image', 'spritesheet', 'atlas', 'audio', 'tilemap']);
const STATUSES = new Set(['draft', 'ready', 'deprecated']);
const ASSET_ID_PATTERN = /^[a-z0-9]+(\.[a-z0-9-]+)+$/;

const errors = [];

function fail(id, field, message) {
  errors.push(`[${id}] ${field}: ${message}`);
}

/** Reads PNG width/height from the IHDR header (bytes 16..24). */
function readPngSize(filePath) {
  const buffer = readFileSync(filePath);
  const PNG_SIGNATURE = '89504e470d0a1a0a';

  if (buffer.length < 24 || buffer.subarray(0, 8).toString('hex') !== PNG_SIGNATURE) {
    return null;
  }

  return { w: buffer.readUInt32BE(16), h: buffer.readUInt32BE(20) };
}

/** Case-exact existence check, segment by segment (Windows FS is case-insensitive). */
function findCaseMismatch(relativePath) {
  const segments = relativePath.split('/');
  let current = assetRoot;

  for (const segment of segments) {
    let entries;
    try {
      entries = readdirSync(current);
    } catch {
      return `directory not found: ${relative(assetRoot, current) || '.'}`;
    }

    if (!entries.includes(segment)) {
      const ciMatch = entries.find((entry) => entry.toLowerCase() === segment.toLowerCase());
      return ciMatch
        ? `case mismatch: expected '${segment}', on disk '${ciMatch}'`
        : `not found: '${segment}' in ${relative(assetRoot, current) || '.'}`;
    }

    current = join(current, segment);
  }

  return null;
}

/** Minimal glob matcher supporting **, * and ? against forward-slash paths. */
function globToRegExp(glob) {
  let pattern = '';
  let i = 0;

  while (i < glob.length) {
    const char = glob[i];

    if (char === '*') {
      if (glob[i + 1] === '*') {
        pattern += '.*';
        i += 2;
        if (glob[i] === '/') i += 1;
      } else {
        pattern += '[^/]*';
        i += 1;
      }
    } else if (char === '?') {
      pattern += '[^/]';
      i += 1;
    } else {
      pattern += char.replace(/[.+^${}()|[\]\\]/g, '\\$&');
      i += 1;
    }
  }

  return new RegExp(`^${pattern}$`);
}

function listPngFiles(dir) {
  const results = [];

  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...listPngFiles(fullPath));
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.png')) {
      results.push(fullPath);
    }
  }

  return results;
}

function toManifestPath(absolutePath) {
  return relative(assetRoot, absolutePath).split(sep).join('/');
}

// ── 1. Parse ────────────────────────────────────────────────────────────────

let manifest;
try {
  manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
} catch (error) {
  console.error(`assets:check failed — cannot parse ${manifestPath}: ${error.message}`);
  process.exit(1);
}

if (manifest.version !== 1) {
  fail('manifest', 'version', `expected 1, got ${JSON.stringify(manifest.version)}`);
}

const assets = manifest.assets ?? {};
const bundles = manifest.bundles ?? {};
const ignorePatterns = Array.isArray(manifest.ignore) ? manifest.ignore : [];
const ignoreRegExps = ignorePatterns.map(globToRegExp);
const assetIds = new Set(Object.keys(assets));

// ── 2-3. Structure, unique keys, bundle references ──────────────────────────

const seenTextureKeys = new Map();

for (const [id, asset] of Object.entries(assets)) {
  if (!ASSET_ID_PATTERN.test(id)) {
    fail(id, 'id', `must be dotted lowercase (e.g. ground.meadow.grass-a)`);
  }

  if (!asset || typeof asset !== 'object') {
    fail(id, 'asset', 'entry must be an object');
    continue;
  }

  const source = asset.source;
  if (!source || !SOURCE_KINDS.has(source.kind)) {
    fail(id, 'source.kind', `expected one of ${[...SOURCE_KINDS].join(', ')}`);
    continue;
  }

  if (!STATUSES.has(asset.status)) {
    fail(id, 'status', `expected one of ${[...STATUSES].join(', ')}`);
  }

  const textureKey = asset.runtime?.textureKey;
  if (typeof textureKey !== 'string' || textureKey.length === 0) {
    fail(id, 'runtime.textureKey', 'required non-empty string');
  } else if (seenTextureKeys.has(textureKey)) {
    fail(id, 'runtime.textureKey', `duplicate of ${seenTextureKeys.get(textureKey)}`);
  } else {
    seenTextureKeys.set(textureKey, id);
  }

  if (source.kind === 'spritesheet') {
    const frame = source.frame;
    if (!frame || !Number.isInteger(frame.w) || !Number.isInteger(frame.h) || frame.w < 1 || frame.h < 1) {
      fail(id, 'source.frame', 'spritesheet requires integer frame { w, h }');
    }
  }

  if (asset.frames !== undefined) {
    if (source.kind !== 'spritesheet') {
      fail(id, 'frames', 'per-frame metadata is only valid for spritesheets');
    } else if (!asset.frames || typeof asset.frames !== 'object' || Array.isArray(asset.frames)) {
      fail(id, 'frames', 'must be an object keyed by zero-based frame index');
    } else {
      if (!Number.isInteger(source.frame.cols) || !Number.isInteger(source.frame.rows)) {
        fail(id, 'source.frame', 'cols and rows are required when per-frame metadata is declared');
      }
      const declaredFrameCount = source.frame.cols * source.frame.rows;
      const seenFrameNames = new Set();

      for (const [frameIndexText, frameMetadata] of Object.entries(asset.frames)) {
        const frameIndex = Number(frameIndexText);
        const field = `frames.${frameIndexText}`;

        if (!/^(0|[1-9][0-9]*)$/.test(frameIndexText) || !Number.isInteger(frameIndex)) {
          fail(id, field, 'key must be a zero-based integer frame index');
          continue;
        }
        if (frameIndex >= declaredFrameCount) {
          fail(id, field, `frame index outside declared sheet range 0..${declaredFrameCount - 1}`);
        }
        if (!frameMetadata || typeof frameMetadata !== 'object') {
          fail(id, field, 'metadata must be an object');
          continue;
        }

        const frameName = frameMetadata.name;
        if (typeof frameName !== 'string' || !/^[a-z0-9]+([.-][a-z0-9]+)*$/.test(frameName)) {
          fail(id, `${field}.name`, 'must be a lowercase kebab/dotted name');
        } else if (seenFrameNames.has(frameName)) {
          fail(id, `${field}.name`, `duplicate frame name '${frameName}'`);
        } else {
          seenFrameNames.add(frameName);
        }

      }
    }
  }

  if (source.kind === 'derived') {
    if (typeof source.from !== 'string' || !assetIds.has(source.from)) {
      fail(id, 'source.from', `unknown asset ID '${source.from}'`);
    } else {
      const parent = assets[source.from].source;
      const crop = source.crop ?? {};

      if (parent.kind === 'image' && parent.grid) {
        const maxCol = parent.grid.columnLines.length - 2;
        const maxRow = parent.grid.rowLines.length - 2;
        if (crop.column > maxCol || crop.row > maxRow) {
          fail(id, 'source.crop', `cell (${crop.column}, ${crop.row}) outside grid ${maxCol + 1}x${maxRow + 1}`);
        }
      } else if (parent.kind !== 'spritesheet') {
        fail(id, 'source.from', `'${source.from}' must be an image with grid or a spritesheet`);
      }
    }

    if (!source.out || !Number.isInteger(source.out.w) || !Number.isInteger(source.out.h)) {
      fail(id, 'source.out', 'derived requires integer out { w, h }');
    }
  }

  if (source.kind === 'procedural' && (typeof source.generator !== 'string' || source.generator.length === 0)) {
    fail(id, 'source.generator', 'required non-empty string (TS registry ID)');
  }
}

for (const [bundleName, ids] of Object.entries(bundles)) {
  if (!Array.isArray(ids)) {
    fail(bundleName, 'bundles', 'bundle must be an array of asset IDs');
    continue;
  }

  for (const id of ids) {
    if (!assetIds.has(id)) {
      fail(bundleName, 'bundles', `references unknown asset ID '${id}'`);
    }
  }
}

// ── 4-5. Paths, casing, dimensions, frame math ──────────────────────────────

for (const [id, asset] of Object.entries(assets)) {
  const source = asset.source;
  if (!source || !PATH_KINDS.has(source.kind)) continue;

  const path = source.path;
  if (typeof path !== 'string' || path.length === 0) {
    fail(id, 'source.path', 'required non-empty string');
    continue;
  }

  if (path.includes('\\') || path.startsWith('/') || path.split('/').includes('..')) {
    fail(id, 'source.path', `must be forward-slash, relative to asset/, no '..': '${path}'`);
    continue;
  }

  const mismatch = findCaseMismatch(path);
  if (mismatch) {
    fail(id, 'source.path', mismatch);
    continue;
  }

  if (!path.toLowerCase().endsWith('.png')) continue;

  const size = readPngSize(join(assetRoot, path));
  if (!size) {
    fail(id, 'source.path', `'${path}' is not a readable PNG`);
    continue;
  }

  if (source.expect && (source.expect.w !== size.w || source.expect.h !== size.h)) {
    fail(id, 'source.expect', `expected ${source.expect.w}x${source.expect.h}, file is ${size.w}x${size.h}`);
  }

  if (source.kind === 'spritesheet' && source.frame) {
    const { w, h, cols, rows } = source.frame;
    if (Number.isInteger(w) && Number.isInteger(h)) {
      if (size.w % w !== 0 || size.h % h !== 0) {
        fail(id, 'source.frame', `${size.w}x${size.h} does not divide evenly by ${w}x${h}`);
      }
      if (Number.isInteger(cols) && size.w / w !== cols) {
        fail(id, 'source.frame.cols', `declared ${cols}, file implies ${size.w / w}`);
      }
      if (Number.isInteger(rows) && size.h / h !== rows) {
        fail(id, 'source.frame.rows', `declared ${rows}, file implies ${size.h / h}`);
      }
    }
  }

  if (source.kind === 'image' && source.grid) {
    const { columnLines, rowLines } = source.grid;
    const checkLines = (lines, max, field) => {
      for (let i = 0; i < lines.length; i += 1) {
        if (lines[i] < 0 || lines[i] > max) {
          fail(id, field, `line ${lines[i]} out of bounds 0..${max}`);
        }
        if (i > 0 && lines[i] <= lines[i - 1]) {
          fail(id, field, `lines must be strictly ascending (${lines[i - 1]} then ${lines[i]})`);
        }
      }
    };
    checkLines(columnLines, size.w, 'source.grid.columnLines');
    checkLines(rowLines, size.h, 'source.grid.rowLines');
  }
}

// ── 6. Orphan detection ─────────────────────────────────────────────────────

const mappedPaths = new Set(
  Object.values(assets)
    .map((asset) => asset.source)
    .filter((source) => source && PATH_KINDS.has(source.kind) && typeof source.path === 'string')
    .map((source) => source.path),
);

for (const absolutePath of listPngFiles(assetRoot)) {
  const relativePath = toManifestPath(absolutePath);
  if (relativePath === 'assets.schema.json' || relativePath === 'assets.json') continue;
  if (mappedPaths.has(relativePath)) continue;
  if (ignoreRegExps.some((pattern) => pattern.test(relativePath))) continue;

  fail(relativePath, 'orphan', 'PNG on disk is neither mapped in assets nor covered by ignore');
}

// ── Report ──────────────────────────────────────────────────────────────────

if (errors.length > 0) {
  console.error(`assets:check failed with ${errors.length} error(s):`);
  for (const error of errors) {
    console.error(`  ✗ ${error}`);
  }
  process.exit(1);
}

console.log(
  `assets:check OK — ${assetIds.size} asset(s), ${Object.keys(bundles).length} bundle(s), ` +
    `${ignorePatterns.length} ignore pattern(s), no orphans.`,
);

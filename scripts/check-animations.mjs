import { promises as fs } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const repoRoot = process.cwd();
const animationRoot = path.join(repoRoot, 'src', 'game', 'content', 'animations');
const assetManifestPath = path.join(repoRoot, 'asset', 'assets.json');
const animationIdPattern = /^[a-z0-9]+(?:[.-][a-z0-9]+(?:-[a-z0-9]+)*)+$/;
const packageFolderPattern = /^[a-z0-9][a-z0-9-]*$/;

function fail(message) {
  throw new Error(message);
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

async function findPackages(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true }).catch((error) => {
    if (error.code === 'ENOENT') return [];
    throw error;
  });
  const files = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await findPackages(candidate));
    } else if (entry.isFile() && entry.name === 'animation.json') {
      files.push(candidate);
    }
  }
  return files.sort();
}

function assetFrameCount(assetId, assets, packagePath) {
  const asset = assets[assetId];
  if (!isRecord(asset) || !isRecord(asset.source)) fail(`${packagePath}: unknown asset '${assetId}'`);
  if (asset.source.kind !== 'spritesheet') fail(`${packagePath}: asset '${assetId}' must be a spritesheet`);
  const frame = asset.source.frame;
  if (!isRecord(frame)) fail(`${packagePath}: asset '${assetId}' is missing spritesheet frame metadata`);
  const columns = frame.cols;
  const rows = frame.rows;
  if (typeof columns !== 'number' || typeof rows !== 'number' || columns < 1 || rows < 1) {
    fail(`${packagePath}: asset '${assetId}' has invalid spritesheet dimensions`);
  }
  return typeof frame.count === 'number' ? frame.count : columns * rows;
}

function validateAnimation(animation, assets, packagePath) {
  if (!isRecord(animation)) fail(`${packagePath}.animation: must be an object`);
  if (animation.version !== 2) fail(`${packagePath}.animation.version: must be 2`);
  if (typeof animation.durationSeconds !== 'number' || animation.durationSeconds <= 0) fail(`${packagePath}.animation.durationSeconds: must be greater than 0`);
  if (!Number.isInteger(animation.framesPerSecond) || animation.framesPerSecond < 1 || animation.framesPerSecond > 240) fail(`${packagePath}.animation.framesPerSecond: must be an integer between 1 and 240`);
  if (typeof animation.loop !== 'boolean') fail(`${packagePath}.animation.loop: must be boolean`);
  if (animation.loopMode !== 'wrap' && animation.loopMode !== 'hold') fail(`${packagePath}.animation.loopMode: must be wrap or hold`);
  if (!Array.isArray(animation.layers) || animation.layers.length === 0) fail(`${packagePath}.animation.layers: must contain at least one layer`);

  const layerIds = new Set();
  for (let layerIndex = 0; layerIndex < animation.layers.length; layerIndex += 1) {
    const layer = animation.layers[layerIndex];
    const layerPath = `${packagePath}.animation.layers[${layerIndex}]`;
    if (!isRecord(layer)) fail(`${layerPath}: must be an object`);
    if (typeof layer.layerId !== 'string' || layer.layerId.length === 0) fail(`${layerPath}.layerId: must be a non-empty string`);
    if (layerIds.has(layer.layerId)) fail(`${layerPath}.layerId: must be unique`);
    layerIds.add(layer.layerId);
    if (typeof layer.displayName !== 'string' || layer.displayName.length === 0) fail(`${layerPath}.displayName: must be a non-empty string`);
    if (typeof layer.depthOffset !== 'number' || !Number.isFinite(layer.depthOffset)) fail(`${layerPath}.depthOffset: must be finite`);
    if (typeof layer.assetId !== 'string') fail(`${layerPath}.assetId: must be a string`);
    const frameCount = assetFrameCount(layer.assetId, assets, `${layerPath}.assetId`);
    if (!Array.isArray(layer.blocks) || layer.blocks.length === 0) fail(`${layerPath}.blocks: must contain at least one block`);
    let previousThrough = -1;
    for (let blockIndex = 0; blockIndex < layer.blocks.length; blockIndex += 1) {
      const block = layer.blocks[blockIndex];
      const blockPath = `${layerPath}.blocks[${blockIndex}]`;
      if (!isRecord(block)) fail(`${blockPath}: must be an object`);
      if (!Number.isInteger(block.from) || !Number.isInteger(block.through) || block.from < 0 || block.through < block.from) {
        fail(`${blockPath}: from/through must be non-negative integer frame bounds`);
      }
      if (block.from <= previousThrough) fail(`${blockPath}: blocks must not overlap or be out of order`);
      if (!Number.isInteger(block.sourceFrame) || block.sourceFrame < 0 || block.sourceFrame >= frameCount) fail(`${blockPath}: source frame ${block.sourceFrame} exceeds asset frame count ${frameCount}`);
      previousThrough = block.through;
    }
  }
}

async function main() {
  const manifest = JSON.parse(await fs.readFile(assetManifestPath, 'utf8'));
  if (!isRecord(manifest) || !isRecord(manifest.assets)) fail(`${assetManifestPath}: invalid asset manifest`);
  const files = await findPackages(animationRoot);
  const ids = new Set();
  for (const file of files) {
    const relative = path.relative(animationRoot, file);
    const segments = relative.split(path.sep);
    const folderSegments = segments.slice(0, -1);
    if (folderSegments.length < 1 || folderSegments.some((segment) => !packageFolderPattern.test(segment))) {
      fail(`${relative}: every package folder must use lowercase kebab-case`);
    }
    const packageValue = JSON.parse(await fs.readFile(file, 'utf8'));
    const packagePath = path.relative(repoRoot, file).replaceAll(path.sep, '/');
    if (!isRecord(packageValue)) fail(`${packagePath}: must be an object`);
    if (typeof packageValue.animationId !== 'string' || !animationIdPattern.test(packageValue.animationId)) {
      fail(`${packagePath}.animationId: must match the lowercase stable animation ID pattern`);
    }
    if (ids.has(packageValue.animationId)) fail(`${packagePath}.animationId: duplicate animation ID '${packageValue.animationId}'`);
    ids.add(packageValue.animationId);
    const expectedSchema = path.relative(path.dirname(file), path.join(animationRoot, 'animation-package.schema.json')).replaceAll(path.sep, '/');
    if (packageValue.$schema !== expectedSchema) fail(`${packagePath}.$schema: must be ${expectedSchema}`);
    if (packageValue.version !== 1) fail(`${packagePath}.version: must be 1`);
    for (const field of ['displayName', 'description']) {
      if (typeof packageValue[field] !== 'string' || packageValue[field].trim().length === 0) fail(`${packagePath}.${field}: must be a non-empty string`);
    }
    validateAnimation(packageValue.animation, manifest.assets, packagePath);
  }
  const revision = files.length === 0 ? 'empty' : String(files.length);
  console.log(`animations:check OK — ${files.length} package(s), revision ${revision}`);
}

main().catch((error) => {
  console.error(`animations:check FAILED — ${error.message}`);
  process.exitCode = 1;
});

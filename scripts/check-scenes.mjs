#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadSceneTooling } from './lib/scene-conversion/load-scene-tooling.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const authoredRoot = path.join(root, 'src/game/content/scenes/authored');
const manifest = JSON.parse(readFileSync(path.join(root, 'asset/assets.json'), 'utf8'));

function discover(directory, suffix) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const candidate = path.join(directory, entry.name);
    return entry.isDirectory() ? discover(candidate, suffix) : entry.isFile() && entry.name.endsWith(suffix) ? [candidate] : [];
  }).sort();
}

const sceneFiles = discover(authoredRoot, '.scene.json');
const resourceFiles = discover(authoredRoot, '.resource.json');
const resources = resourceFiles.map((file) => JSON.parse(readFileSync(file, 'utf8')));
const resourceById = new Map(resources.map((resource) => [resource.resourceId, resource]));
const scenes = sceneFiles.map((file) => JSON.parse(readFileSync(file, 'utf8')));
const tooling = await loadSceneTooling();
const registry = tooling.createCoreDescriptorRegistry();
const context = {
  registry,
  hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId),
  hasResource: (resourceId) => resourceById.has(resourceId),
  getResourceKind: (resourceId) => resourceById.get(resourceId)?.kind,
};

const failures = [];
for (let index = 0; index < resources.length; index += 1) {
  const issues = tooling.validateSceneResourceDocument(resources[index], context);
  if (issues.length > 0) failures.push(...issues.map((issue) => `${resourceFiles[index]}${issue.path}: ${issue.message}`));
}
for (let index = 0; index < scenes.length; index += 1) {
  const issues = tooling.validateSceneDocument(scenes[index], context);
  if (issues.length > 0) failures.push(...issues.map((issue) => `${sceneFiles[index]}${issue.path}: ${issue.message}`));
}
try { new tooling.SceneCatalog(scenes, context); } catch (error) { failures.push(error instanceof Error ? error.message : String(error)); }
if (failures.length > 0) {
  console.error(`scenes:check failed:\n  - ${failures.join('\n  - ')}`);
  process.exitCode = 1;
} else {
  console.log(`scenes:check OK - ${scenes.length} scene(s), ${resources.length} resource(s).`);
}

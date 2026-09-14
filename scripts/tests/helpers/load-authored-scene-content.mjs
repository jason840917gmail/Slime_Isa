import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

import { REPOSITORY_ROOT } from './load-typescript.mjs';

const authoredRoot = path.join(REPOSITORY_ROOT, 'src/game/content/scenes/authored');

async function discover(directory, suffix) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) return discover(candidate, suffix);
    return entry.isFile() && entry.name.endsWith(suffix) ? [candidate] : [];
  }));
  return files.flat().sort();
}

export async function loadAuthoredSceneContent() {
  const [sceneFiles, resourceFiles] = await Promise.all([
    discover(authoredRoot, '.scene.json'),
    discover(authoredRoot, '.resource.json'),
  ]);
  const parse = async (file) => JSON.parse(await readFile(file, 'utf8'));
  return {
    scenes: await Promise.all(sceneFiles.map(parse)),
    resources: await Promise.all(resourceFiles.map(parse)),
  };
}

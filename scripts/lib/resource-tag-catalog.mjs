import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { build } from 'esbuild';

const validators = new Map();

async function gameConstantsValidator(repositoryRoot) {
  let validator = validators.get(repositoryRoot);
  if (!validator) {
    validator = build({
      absWorkingDir: repositoryRoot,
      entryPoints: ['src/game/content/GameConstantsValidation.ts'],
      bundle: true,
      format: 'esm',
      platform: 'node',
      write: false,
    }).then((result) => import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`))
      .then((module) => module.validateGameConstants);
    validators.set(repositoryRoot, validator);
  }
  return validator;
}

export async function loadValidatedResourceTags(
  repositoryRoot,
  gameConstantsPath = join(repositoryRoot, 'src', 'game', 'content', 'game-constants.json'),
) {
  let document;
  try {
    document = JSON.parse(readFileSync(gameConstantsPath, 'utf8'));
  } catch (error) {
    throw new Error(`Could not read game constants at '${gameConstantsPath}': ${error instanceof Error ? error.message : String(error)}`);
  }

  const validateGameConstants = await gameConstantsValidator(repositoryRoot);
  const issues = validateGameConstants(document);
  if (issues.length > 0) {
    throw new Error(`Invalid game constants at '${gameConstantsPath}': ${issues.map((entry) => `${entry.path}: ${entry.message}`).join('; ')}`);
  }
  return new Set(document.resources.tags);
}

import { readFile } from 'node:fs/promises';
import path from 'node:path';

import Ajv2020 from 'ajv/dist/2020.js';
import standaloneCode from 'ajv/dist/standalone/index.js';
import { compile } from 'json-schema-to-typescript';

export const GENERATED_GAME_CONSTANTS_CONTRACT_PATHS = Object.freeze({
  types: 'src/game/content/GameConstantsDocument.generated.ts',
  validator: 'src/game/content/GameConstantsSchemaValidator.generated.js',
  validatorTypes: 'src/game/content/GameConstantsSchemaValidator.generated.d.ts',
});

const GENERATED_HEADER = '// Generated from game-constants.schema.json. Run `pnpm constants:generate`; do not edit.\n';

export async function generateGameConstantsContractSources(repositoryRoot) {
  const schemaPath = path.join(repositoryRoot, 'src', 'game', 'content', 'game-constants.schema.json');
  const schema = JSON.parse(await readFile(schemaPath, 'utf8'));
  const typeSchema = structuredClone(schema);
  typeSchema.title = 'GameConstantsDocument';
  const types = await compile(typeSchema, 'GameConstantsDocument', {
    bannerComment: GENERATED_HEADER.trimEnd(),
    style: { singleQuote: true, semi: true, trailingComma: 'all' },
    unreachableDefinitions: true,
  });

  const ajv = new Ajv2020({
    allErrors: true,
    strict: true,
    code: { esm: true, source: true },
  });
  const validate = ajv.compile(schema);
  const runtimeImports = [];
  const standaloneValidator = standaloneCode(ajv, validate).replace(
    /const (func\d+) = require\("([^"]+)"\)\.default;/g,
    (_statement, binding, specifier) => {
      const moduleBinding = `${binding}Module`;
      runtimeImports.push(`import ${moduleBinding} from '${specifier}.js';`);
      runtimeImports.push(
        `const ${binding} = typeof ${moduleBinding} === 'function' ? ${moduleBinding} : ${moduleBinding}.default;`,
      );
      return '';
    },
  );
  const validator = `${GENERATED_HEADER}${runtimeImports.join('\n')}\n${standaloneValidator}\n`;
  const validatorTypes = `${GENERATED_HEADER}import type { ErrorObject } from 'ajv';
import type { GameConstants } from './GameConstantsTypes';

declare const validate: {
  (value: unknown): value is GameConstants;
  errors: ErrorObject[] | null;
};

export { validate };
export default validate;
`;

  return {
    [GENERATED_GAME_CONSTANTS_CONTRACT_PATHS.types]: types,
    [GENERATED_GAME_CONSTANTS_CONTRACT_PATHS.validator]: validator,
    [GENERATED_GAME_CONSTANTS_CONTRACT_PATHS.validatorTypes]: validatorTypes,
  };
}

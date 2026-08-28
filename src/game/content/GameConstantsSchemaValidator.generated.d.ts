// Generated from game-constants.schema.json. Run `pnpm constants:generate`; do not edit.
import type { ErrorObject } from 'ajv';
import type { GameConstants } from './GameConstantsTypes';

declare const validate: {
  (value: unknown): value is GameConstants;
  errors: ErrorObject[] | null;
};

export { validate };
export default validate;

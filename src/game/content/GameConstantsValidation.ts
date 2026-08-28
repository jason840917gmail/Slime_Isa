import type { ErrorObject } from 'ajv';

import validateStructure from './GameConstantsSchemaValidator.generated.js';
import type { GameConstants } from './GameConstantsTypes';

export interface GameConstantsIssue {
  readonly path: string;
  readonly message: string;
}

export class GameConstantsValidationError extends Error {
  constructor(public readonly issues: readonly GameConstantsIssue[]) {
    super(`Invalid gameplay configuration:\n${issues.map((entry) => `- ${entry.path}: ${entry.message}`).join('\n')}`);
    this.name = 'GameConstantsValidationError';
  }
}

function decodePointerSegment(segment: string): string {
  return segment.replaceAll('~1', '/').replaceAll('~0', '~');
}

function appendPath(path: string, segment: string): string {
  if (/^\d+$/.test(segment)) return path.length > 0 ? `${path}[${segment}]` : `[${segment}]`;
  if (/^[A-Za-z_$][A-Za-z0-9_$-]*$/.test(segment)) return path.length > 0 ? `${path}.${segment}` : segment;
  return path.length > 0 ? `${path}[${JSON.stringify(segment)}]` : `[${JSON.stringify(segment)}]`;
}

function issuePath(error: ErrorObject): string {
  let path = '';
  for (const segment of error.instancePath.split('/').slice(1).map(decodePointerSegment)) {
    path = appendPath(path, segment);
  }
  const basePath = path.length > 0 ? path : 'gameConstants';
  if (error.keyword === 'required') return appendPath(basePath, String(error.params.missingProperty));
  if (error.keyword === 'additionalProperties') return appendPath(basePath, String(error.params.additionalProperty));
  if (error.keyword === 'propertyNames') return appendPath(basePath, String(error.params.propertyName));
  return basePath;
}

function valueAtPointer(value: unknown, pointer: string): unknown {
  let current = value;
  for (const segment of pointer.split('/').slice(1).map(decodePointerSegment)) {
    if (Array.isArray(current) && /^\d+$/.test(segment)) current = current[Number(segment)];
    else if (current !== null && typeof current === 'object') current = (current as Record<string, unknown>)[segment];
    else return undefined;
  }
  return current;
}

function schemaIssue(error: ErrorObject, value: unknown): GameConstantsIssue {
  const path = issuePath(error);
  if (error.keyword === 'additionalProperties') return { path, message: 'unknown property' };
  if (error.keyword === 'required') return { path, message: 'is required' };
  if (error.keyword === 'const') return { path, message: `must be ${JSON.stringify(error.params.allowedValue)}` };
  if (error.keyword === 'uniqueItems' && error.instancePath === '/resources/tags') {
    const tags = valueAtPointer(value, error.instancePath);
    const duplicateIndex = Number(error.params.i);
    const duplicate = Array.isArray(tags) ? tags[duplicateIndex] : undefined;
    return {
      path: Number.isInteger(duplicateIndex) ? appendPath(path, String(duplicateIndex)) : path,
      message: typeof duplicate === 'string' ? `duplicate tag '${duplicate}'` : 'must not contain duplicate tags',
    };
  }
  if (error.keyword === 'pattern' && error.instancePath.startsWith('/resources/tags/')) {
    return { path, message: 'must be a lowercase kebab-case tag' };
  }
  if (error.keyword === 'pattern' && error.instancePath === '/inventory/maxStackByItem') {
    const propertyName = (error as ErrorObject & { propertyName?: string }).propertyName;
    return {
      path: propertyName === undefined ? path : appendPath(path, propertyName),
      message: 'item ID must be lowercase kebab-case',
    };
  }
  return { path, message: error.message ?? `failed ${error.keyword} validation` };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function semanticIssues(value: unknown): readonly GameConstantsIssue[] {
  const issues: GameConstantsIssue[] = [];
  if (!isRecord(value)) return issues;
  const character = isRecord(value.character) ? value.character : undefined;
  const player = character && isRecord(character.player) ? character.player : undefined;
  if (!player) return issues;

  const movementPath = 'character.player.movement';
  const movement = isRecord(player.movement) ? player.movement : undefined;
  if (movement) {
    const { baseSpeed, boostSpeed, dodgeSpeed, movementSpeedCap } = movement;
    if (isNonNegativeNumber(baseSpeed) && isNonNegativeNumber(boostSpeed) && baseSpeed > boostSpeed) {
      issues.push({ path: movementPath, message: 'baseSpeed must not exceed boostSpeed' });
    }
    if (isNonNegativeNumber(boostSpeed) && isNonNegativeNumber(movementSpeedCap) && boostSpeed > movementSpeedCap) {
      issues.push({ path: movementPath, message: 'boostSpeed must not exceed movementSpeedCap' });
    }
    if (isNonNegativeNumber(dodgeSpeed) && isNonNegativeNumber(movementSpeedCap) && dodgeSpeed > movementSpeedCap) {
      issues.push({ path: movementPath, message: 'dodgeSpeed must not exceed movementSpeedCap' });
    }
  }

  const progressionPath = 'character.player.progression';
  const progression = isRecord(player.progression) ? player.progression : undefined;
  if (!progression || !Array.isArray(progression.levels)) return issues;
  const maxLevel = progression.maxLevel;
  const hasMaxLevel = typeof maxLevel === 'number' && Number.isInteger(maxLevel) && maxLevel >= 1;
  if (hasMaxLevel && progression.levels.length !== maxLevel) {
    issues.push({
      path: `${progressionPath}.levels`,
      message: `must contain exactly ${maxLevel} entries`,
    });
  }
  progression.levels.forEach((candidate, index) => {
    if (!isRecord(candidate)) return;
    const expectedLevel = index + 1;
    const levelPath = `${progressionPath}.levels[${index}]`;
    if (typeof candidate.level === 'number' && Number.isInteger(candidate.level) && candidate.level >= 1 && candidate.level !== expectedLevel) {
      issues.push({ path: `${levelPath}.level`, message: `must be ${expectedLevel}` });
    }
    const isFinal = hasMaxLevel && expectedLevel === maxLevel;
    if (isFinal && candidate.xpToNextLevel !== null) {
      issues.push({ path: `${levelPath}.xpToNextLevel`, message: 'final level must use null' });
    } else if (hasMaxLevel && !isFinal && candidate.xpToNextLevel === null) {
      issues.push({ path: `${levelPath}.xpToNextLevel`, message: 'non-final level must use a positive integer' });
    }
    if (expectedLevel === 1 && isRecord(candidate.gains)) {
      for (const [field, gain] of Object.entries(candidate.gains)) {
        if (isNonNegativeNumber(gain) && gain !== 0) {
          issues.push({ path: `${levelPath}.gains.${field}`, message: 'level 1 gain must be zero' });
        }
      }
    }
  });
  return issues;
}

export function validateGameConstants(value: unknown): readonly GameConstantsIssue[] {
  const structuralIssues = validateStructure(value)
    ? []
    : (validateStructure.errors ?? []).map((error) => schemaIssue(error, value));
  return [...structuralIssues, ...semanticIssues(value)];
}

export function normalizeGameConstants(value: unknown): GameConstants {
  const issues = validateGameConstants(value);
  if (issues.length > 0) throw new GameConstantsValidationError(issues);
  return structuredClone(value) as GameConstants;
}

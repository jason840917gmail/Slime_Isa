export interface GameConstantsIssue {
  readonly path: string;
  readonly message: string;
}

export interface PlayerAttributeDefaults {
  readonly strength: number;
  readonly vitality: number;
  readonly agility: number;
  readonly intellect: number;
}

export interface PlayerLevelGains {
  readonly maxHp: number;
  readonly maxEnergy: number;
  readonly attack: number;
  readonly defense: number;
}

export interface PlayerLevelDefinition {
  readonly level: number;
  readonly xpToNextLevel: number | null;
  readonly gains: PlayerLevelGains;
}

export interface PlayerProgressionDefinition {
  readonly maxLevel: number;
  readonly baseMaxHp: number;
  readonly baseMaxEnergy: number;
  readonly baseAttack: number;
  readonly baseDefense: number;
  readonly levels: readonly PlayerLevelDefinition[];
}

export interface GameConstants {
  $schema?: string;
  version: 1;
  resources: {
    tags: readonly string[];
  };
  inventory: {
    initialMaxSlots: number;
    maxStackByItem: Record<string, number>;
    weaponMaxStack: number;
  };
  character: {
    player: {
      initialAttributes: PlayerAttributeDefaults;
      movement: {
        baseSpeed: number;
        boostSpeed: number;
        dodgeSpeed: number;
        dodgeInvulnerabilityMs: number;
        movementSpeedCap: number;
      };
      hitInvulnerabilityMs: number;
      progression: PlayerProgressionDefinition;
    };
  };
}

export class GameConstantsValidationError extends Error {
  constructor(public readonly issues: readonly GameConstantsIssue[]) {
    super(`Invalid gameplay configuration:\n${issues.map((entry) => `- ${entry.path}: ${entry.message}`).join('\n')}`);
    this.name = 'GameConstantsValidationError';
  }
}

const isRecord = (value: unknown): value is Record<string, unknown> => (
  value !== null && typeof value === 'object' && !Array.isArray(value)
);

function issue(issues: GameConstantsIssue[], path: string, message: string): void {
  issues.push({ path, message });
}

function keys(issues: GameConstantsIssue[], value: Record<string, unknown>, path: string, allowed: readonly string[]): void {
  const allowedKeys = new Set(allowed);
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) issue(issues, `${path}.${key}`, 'unknown property');
  }
}

function record(issues: GameConstantsIssue[], value: unknown, path: string): Record<string, unknown> | undefined {
  if (isRecord(value)) return value;
  issue(issues, path, 'must be an object');
  return undefined;
}

function finite(issues: GameConstantsIssue[], value: unknown, path: string, minimum = 0, exclusive = false): value is number {
  const valid = typeof value === 'number' && Number.isFinite(value) && (exclusive ? value > minimum : value >= minimum);
  if (!valid) issue(issues, path, exclusive ? `must be greater than ${minimum}` : `must be ${minimum} or greater`);
  return valid;
}

function integer(issues: GameConstantsIssue[], value: unknown, path: string, minimum: number): value is number {
  const valid = typeof value === 'number' && Number.isInteger(value) && value >= minimum;
  if (!valid) issue(issues, path, `must be an integer ${minimum} or greater`);
  return valid;
}

function validateAttributes(issues: GameConstantsIssue[], value: unknown): void {
  const attributes = record(issues, value, 'character.player.initialAttributes');
  if (!attributes) return;
  keys(issues, attributes, 'character.player.initialAttributes', ['strength', 'vitality', 'agility', 'intellect']);
  for (const field of ['strength', 'vitality', 'agility', 'intellect']) {
    finite(issues, attributes[field], `character.player.initialAttributes.${field}`);
  }
}

function validateInventory(issues: GameConstantsIssue[], value: unknown): void {
  const inventory = record(issues, value, 'inventory');
  if (!inventory) return;
  keys(issues, inventory, 'inventory', ['initialMaxSlots', 'maxStackByItem', 'weaponMaxStack']);
  integer(issues, inventory.initialMaxSlots, 'inventory.initialMaxSlots', 1);
  integer(issues, inventory.weaponMaxStack, 'inventory.weaponMaxStack', 1);
  const stacks = record(issues, inventory.maxStackByItem, 'inventory.maxStackByItem');
  if (!stacks) return;
  if (Object.keys(stacks).length === 0) issue(issues, 'inventory.maxStackByItem', 'must not be empty');
  for (const [itemId, stack] of Object.entries(stacks)) {
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(itemId)) issue(issues, `inventory.maxStackByItem.${itemId}`, 'item ID must be lowercase kebab-case');
    integer(issues, stack, `inventory.maxStackByItem.${itemId}`, 1);
  }
}

function validateResources(issues: GameConstantsIssue[], value: unknown): void {
  const resources = record(issues, value, 'resources');
  if (!resources) return;
  keys(issues, resources, 'resources', ['tags']);
  if (!Array.isArray(resources.tags)) {
    issue(issues, 'resources.tags', 'must be an array');
    return;
  }
  if (resources.tags.length === 0) issue(issues, 'resources.tags', 'must not be empty');
  const seen = new Set<string>();
  resources.tags.forEach((tag, index) => {
    const path = `resources.tags[${index}]`;
    if (typeof tag !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(tag)) {
      issue(issues, path, 'must be a lowercase kebab-case tag');
      return;
    }
    if (seen.has(tag)) issue(issues, path, `duplicate tag '${tag}'`);
    else seen.add(tag);
  });
}

function validateMovement(issues: GameConstantsIssue[], value: unknown): void {
  const path = 'character.player.movement';
  const movement = record(issues, value, path);
  if (!movement) return;
  keys(issues, movement, path, ['baseSpeed', 'boostSpeed', 'dodgeSpeed', 'dodgeInvulnerabilityMs', 'movementSpeedCap']);
  const { baseSpeed, boostSpeed, dodgeSpeed, movementSpeedCap } = movement;
  const hasBase = finite(issues, baseSpeed, `${path}.baseSpeed`);
  const hasBoost = finite(issues, boostSpeed, `${path}.boostSpeed`);
  const hasDodge = finite(issues, dodgeSpeed, `${path}.dodgeSpeed`);
  const hasCap = finite(issues, movementSpeedCap, `${path}.movementSpeedCap`);
  integer(issues, movement.dodgeInvulnerabilityMs, `${path}.dodgeInvulnerabilityMs`, 0);
  if (hasBase && hasBoost && baseSpeed > boostSpeed) issue(issues, path, 'baseSpeed must not exceed boostSpeed');
  if (hasBoost && hasCap && boostSpeed > movementSpeedCap) issue(issues, path, 'boostSpeed must not exceed movementSpeedCap');
  if (hasDodge && hasCap && dodgeSpeed > movementSpeedCap) issue(issues, path, 'dodgeSpeed must not exceed movementSpeedCap');
}

function validateGains(issues: GameConstantsIssue[], value: unknown, path: string, level: number): void {
  const gains = record(issues, value, path);
  if (!gains) return;
  keys(issues, gains, path, ['maxHp', 'maxEnergy', 'attack', 'defense']);
  for (const field of ['maxHp', 'maxEnergy', 'attack', 'defense']) {
    if (finite(issues, gains[field], `${path}.${field}`) && level === 1 && gains[field] !== 0) {
      issue(issues, `${path}.${field}`, 'level 1 gain must be zero');
    }
  }
}

function validateProgression(issues: GameConstantsIssue[], value: unknown): void {
  const path = 'character.player.progression';
  const progression = record(issues, value, path);
  if (!progression) return;
  keys(issues, progression, path, ['maxLevel', 'baseMaxHp', 'baseMaxEnergy', 'baseAttack', 'baseDefense', 'levels']);
  const hasMax = integer(issues, progression.maxLevel, `${path}.maxLevel`, 1);
  finite(issues, progression.baseMaxHp, `${path}.baseMaxHp`, 0, true);
  finite(issues, progression.baseMaxEnergy, `${path}.baseMaxEnergy`, 0, true);
  finite(issues, progression.baseAttack, `${path}.baseAttack`);
  finite(issues, progression.baseDefense, `${path}.baseDefense`);
  if (!Array.isArray(progression.levels)) {
    issue(issues, `${path}.levels`, 'must be an array');
    return;
  }
  if (hasMax && progression.levels.length !== progression.maxLevel) {
    issue(issues, `${path}.levels`, `must contain exactly ${progression.maxLevel} entries`);
  }
  progression.levels.forEach((candidate, index) => {
    const levelPath = `${path}.levels[${index}]`;
    const entry = record(issues, candidate, levelPath);
    if (!entry) return;
    keys(issues, entry, levelPath, ['level', 'xpToNextLevel', 'gains']);
    const expectedLevel = index + 1;
    if (integer(issues, entry.level, `${levelPath}.level`, 1) && entry.level !== expectedLevel) {
      issue(issues, `${levelPath}.level`, `must be ${expectedLevel}`);
    }
    const isFinal = hasMax && expectedLevel === progression.maxLevel;
    if (isFinal) {
      if (entry.xpToNextLevel !== null) issue(issues, `${levelPath}.xpToNextLevel`, 'final level must use null');
    } else {
      integer(issues, entry.xpToNextLevel, `${levelPath}.xpToNextLevel`, 1);
    }
    validateGains(issues, entry.gains, `${levelPath}.gains`, expectedLevel);
  });
}

export function validateGameConstants(value: unknown): readonly GameConstantsIssue[] {
  const issues: GameConstantsIssue[] = [];
  const root = record(issues, value, 'gameConstants');
  if (!root) return issues;
  keys(issues, root, 'gameConstants', ['$schema', 'version', 'resources', 'inventory', 'character']);
  if (root.$schema !== undefined && typeof root.$schema !== 'string') issue(issues, 'gameConstants.$schema', 'must be a string');
  if (root.version !== 1) issue(issues, 'gameConstants.version', 'must be 1');
  validateResources(issues, root.resources);
  validateInventory(issues, root.inventory);
  const character = record(issues, root.character, 'character');
  if (!character) return issues;
  keys(issues, character, 'character', ['player']);
  const player = record(issues, character.player, 'character.player');
  if (!player) return issues;
  keys(issues, player, 'character.player', ['initialAttributes', 'movement', 'hitInvulnerabilityMs', 'progression']);
  validateAttributes(issues, player.initialAttributes);
  validateMovement(issues, player.movement);
  integer(issues, player.hitInvulnerabilityMs, 'character.player.hitInvulnerabilityMs', 0);
  validateProgression(issues, player.progression);
  return issues;
}

export function normalizeGameConstants(value: unknown): GameConstants {
  const issues = validateGameConstants(value);
  if (issues.length > 0) throw new GameConstantsValidationError(issues);
  return structuredClone(value) as GameConstants;
}

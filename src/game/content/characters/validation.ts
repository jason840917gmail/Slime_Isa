import { ASSET_MANIFEST } from '../../infrastructure/assets/manifest';
import type { CharacterStudioAssetManifestInput } from './characterAssetCatalog';
import type {
  CharacterDocument,
  CharacterHitboxDocument,
  CharacterPackage,
  JsonValue,
  VisualSetDocument,
} from './types';
import { timelineFrameCount } from '../../shared/animation';

export interface CharacterValidationIssue {
  readonly path: string;
  readonly message: string;
}

export interface CharacterValidationOptions {
  readonly characterIds?: ReadonlySet<string>;
  readonly visualSetIds?: ReadonlySet<string>;
  readonly knownItemIds?: ReadonlySet<string>;
  readonly allowDuplicateIdentity?: boolean;
  readonly assetManifest?: CharacterStudioAssetManifestInput;
}

const ID_PATTERN = /^[a-z0-9]+(?:[.-][a-z0-9-]+)*$/;
const CHARACTER_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const isRecord = (value: unknown): value is Record<string, unknown> => (
  value !== null && typeof value === 'object' && !Array.isArray(value)
);

function issue(issues: CharacterValidationIssue[], path: string, message: string): void {
  issues.push({ path, message });
}

function checkKeys(
  issues: CharacterValidationIssue[],
  value: unknown,
  path: string,
  allowed: ReadonlySet<string>,
): void {
  if (!isRecord(value)) return;
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) issue(issues, `${path}.${key}`, 'unknown property');
  }
}

function finite(
  issues: CharacterValidationIssue[],
  value: unknown,
  path: string,
  predicate: (numberValue: number) => boolean,
  message: string,
): value is number {
  if (typeof value !== 'number' || !Number.isFinite(value) || !predicate(value)) {
    issue(issues, path, message);
    return false;
  }
  return true;
}

function integer(
  issues: CharacterValidationIssue[],
  value: unknown,
  path: string,
  predicate: (numberValue: number) => boolean,
  message: string,
): value is number {
  if (typeof value !== 'number' || !Number.isInteger(value) || !predicate(value)) {
    issue(issues, path, message);
    return false;
  }
  return true;
}

function stringValue(
  issues: CharacterValidationIssue[],
  value: unknown,
  path: string,
  predicate: (stringValue: string) => boolean,
  message: string,
): value is string {
  if (typeof value !== 'string' || !predicate(value)) {
    issue(issues, path, message);
    return false;
  }
  return true;
}

function pair(
  issues: CharacterValidationIssue[],
  value: unknown,
  path: string,
  predicate: (numberValue: number) => boolean,
  message: string,
): value is [number, number] {
  if (!Array.isArray(value) || value.length !== 2) {
    issue(issues, path, 'must contain exactly two numbers');
    return false;
  }
  value.forEach((entry, index) => finite(issues, entry, `${path}[${index}]`, predicate, message));
  return true;
}

function validateTransform(
  issues: CharacterValidationIssue[],
  value: unknown,
  path: string,
  required: boolean,
): void {
  if (!isRecord(value)) {
    issue(issues, path, 'must be an object');
    return;
  }
  checkKeys(issues, value, path, new Set(['origin', 'scale', 'sourceOffset']));
  if (required || value.origin !== undefined) {
    pair(issues, value.origin, `${path}.origin`, (entry) => entry >= 0 && entry <= 1, 'must be between 0 and 1');
  }
  if (required || value.scale !== undefined) {
    pair(issues, value.scale, `${path}.scale`, (entry) => entry > 0, 'must be greater than zero');
  }
  if (required || value.sourceOffset !== undefined) {
    pair(issues, value.sourceOffset, `${path}.sourceOffset`, () => true, 'must be finite');
  }
}

function isJsonValue(value: unknown): value is JsonValue {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return true;
  if (typeof value === 'number') return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(isJsonValue);
  if (!isRecord(value)) return false;
  return Object.values(value).every(isJsonValue);
}

function frameCountForAsset(assetId: string, manifest: CharacterStudioAssetManifestInput = ASSET_MANIFEST): number | undefined {
  const asset = manifest.assets?.[assetId];
  if (!isRecord(asset) || !isRecord(asset.source)) return undefined;
  if (!isRecord(asset.source.frame)) return 1;
  const { cols, rows, count } = asset.source.frame;
  if (typeof cols !== 'number' || typeof rows !== 'number') return undefined;
  return typeof count === 'number' && count > 0 ? count : cols * rows;
}

export function validateVisualSetDocument(
  value: unknown,
  path = 'visualSet',
  manifest: CharacterStudioAssetManifestInput = ASSET_MANIFEST,
): CharacterValidationIssue[] {
  const issues: CharacterValidationIssue[] = [];
  if (!isRecord(value)) {
    issue(issues, path, 'must be an object');
    return issues;
  }
  checkKeys(issues, value, path, new Set(['$schema', 'version', 'visualSetId', 'assetId', 'defaults', 'frameVisuals', 'clips']));
  if (value.version !== 1) issue(issues, `${path}.version`, 'must be version 1');
  stringValue(issues, value.visualSetId, `${path}.visualSetId`, (entry) => ID_PATTERN.test(entry) && entry.length >= 3 && entry.length <= 120, 'must be a lowercase dotted stable ID');
  const hasAssetId = stringValue(issues, value.assetId, `${path}.assetId`, (entry) => ID_PATTERN.test(entry), 'must be a lowercase stable asset ID');
  const assetId = hasAssetId && typeof value.assetId === 'string' ? value.assetId : undefined;
  const frameCount = assetId ? frameCountForAsset(assetId, manifest) : undefined;
  if (assetId && frameCount === undefined) issue(issues, `${path}.assetId`, `unknown manifest asset '${assetId}'`);
  validateTransform(issues, value.defaults, `${path}.defaults`, true);

  if (value.frameVisuals !== undefined && !isRecord(value.frameVisuals)) issue(issues, `${path}.frameVisuals`, 'must be an object');
  for (const [frameText, transform] of Object.entries(isRecord(value.frameVisuals) ? value.frameVisuals : {})) {
    const frame = Number(frameText);
    if (!/^(0|[1-9][0-9]*)$/.test(frameText) || !Number.isInteger(frame) || frame < 0 || (frameCount !== undefined && frame >= frameCount)) {
      issue(issues, `${path}.frameVisuals.${frameText}`, `frame must be inside 0..${(frameCount ?? 1) - 1}`);
    }
    validateTransform(issues, transform, `${path}.frameVisuals.${frameText}`, false);
  }

  if (!isRecord(value.clips) || Object.keys(value.clips).length === 0) {
    issue(issues, `${path}.clips`, 'must be a non-empty object');
  }
  for (const [clipId, clip] of Object.entries(isRecord(value.clips) ? value.clips : {})) {
    const clipPath = `${path}.clips.${clipId}`;
    if (!ID_PATTERN.test(clipId) || clipId.length > 80) issue(issues, clipPath, 'clip ID must be a lowercase stable ID');
    checkKeys(issues, clip, clipPath, new Set(['frames', 'keyframeTimes', 'durationSeconds', 'framesPerSecond', 'loop', 'loopMode', 'sourceOffset']));
    if (!isRecord(clip)) {
      issue(issues, clipPath, 'must be an object');
      continue;
    }
    if (!Array.isArray(clip.frames) || clip.frames.length === 0) issue(issues, `${clipPath}.frames`, 'must contain at least one source frame');
    for (const [index, frame] of (Array.isArray(clip.frames) ? clip.frames : []).entries()) {
      if (!Number.isInteger(frame) || frame < 0 || (frameCount !== undefined && frame >= frameCount)) {
        issue(issues, `${clipPath}.frames[${index}]`, `frame ${String(frame)} is outside 0..${(frameCount ?? 1) - 1}`);
      }
    }
    finite(issues, clip.framesPerSecond, `${clipPath}.framesPerSecond`, (entry) => entry > 0 && entry <= 240, 'must be greater than zero and no more than 240');
    if (typeof clip.loop !== 'boolean') issue(issues, `${clipPath}.loop`, 'must be boolean');
    if (clip.loopMode !== undefined && clip.loopMode !== 'wrap' && clip.loopMode !== 'ping-pong') issue(issues, `${clipPath}.loopMode`, "must be 'wrap' or 'ping-pong'");
    const hasTimes = clip.keyframeTimes !== undefined;
    const hasDuration = clip.durationSeconds !== undefined;
    if (hasTimes !== hasDuration) issue(issues, clipPath, 'keyframeTimes and durationSeconds must be authored together');
    if (hasDuration) finite(issues, clip.durationSeconds, `${clipPath}.durationSeconds`, (entry) => entry > 0, 'must be greater than zero');
    if (hasTimes) {
      if (!Array.isArray(clip.keyframeTimes)) issue(issues, `${clipPath}.keyframeTimes`, 'must be an array');
      else {
        const keyframeTimes = clip.keyframeTimes;
        if (Array.isArray(clip.frames) && keyframeTimes.length !== clip.frames.length) issue(issues, `${clipPath}.keyframeTimes`, 'must match frames length');
        const timelineFrames = typeof clip.durationSeconds === 'number' && Number.isFinite(clip.durationSeconds) && typeof clip.framesPerSecond === 'number'
          ? timelineFrameCount({ durationSeconds: clip.durationSeconds, framesPerSecond: clip.framesPerSecond })
          : 0;
        keyframeTimes.forEach((time, index) => {
          if (!Number.isInteger(time) || time < 0 || (timelineFrames > 0 && time >= timelineFrames)) issue(issues, `${clipPath}.keyframeTimes[${index}]`, 'must be an integer inside the clip timeline');
          if (index === 0 && time !== 0) issue(issues, `${clipPath}.keyframeTimes[0]`, 'must be zero');
          if (index > 0 && time <= keyframeTimes[index - 1]) issue(issues, `${clipPath}.keyframeTimes`, 'values must be strictly increasing');
        });
        if (Array.isArray(clip.frames) && timelineFrames > 0 && clip.frames.length > timelineFrames) issue(issues, clipPath, 'cannot fit all keyframes in its timeline');
      }
    }
    if (clip.sourceOffset !== undefined) pair(issues, clip.sourceOffset, `${clipPath}.sourceOffset`, () => true, 'must be finite');
  }
  return issues;
}

function validateBody(issues: CharacterValidationIssue[], body: unknown): void {
  if (!isRecord(body)) {
    issue(issues, 'character.body', 'must be an object');
    return;
  }
  checkKeys(issues, body, 'character.body', new Set(['shape', 'width', 'height', 'radius', 'radiusX', 'radiusY', 'centerOffsetX', 'centerOffsetY']));
  validateShapeFields(issues, body, 'character.body', false);
  finite(issues, body.width, 'character.body.width', (entry) => entry > 0, 'must be greater than zero');
  finite(issues, body.height, 'character.body.height', (entry) => entry > 0, 'must be greater than zero');
  finite(issues, body.centerOffsetX, 'character.body.centerOffsetX', () => true, 'must be finite');
  finite(issues, body.centerOffsetY, 'character.body.centerOffsetY', () => true, 'must be finite');
}

function validateShapeFields(
  issues: CharacterValidationIssue[],
  value: Record<string, unknown>,
  path: string,
  shapeRequired: boolean,
): void {
  const shape = value.shape;
  if (shapeRequired && shape === undefined) issue(issues, `${path}.shape`, 'is required');
  if (shape !== undefined && shape !== 'rectangle' && shape !== 'circle' && shape !== 'ellipse') {
    issue(issues, `${path}.shape`, "must be 'rectangle', 'circle', or 'ellipse'");
  }
  if (shape === 'circle') {
    finite(issues, value.radius, `${path}.radius`, (entry) => entry > 0, 'must be greater than zero for a circle');
    if (value.radiusX !== undefined || value.radiusY !== undefined) issue(issues, `${path}.radiusX`, 'radiusX/radiusY are only allowed for an ellipse');
  } else if (shape === 'ellipse') {
    finite(issues, value.radiusX, `${path}.radiusX`, (entry) => entry > 0, 'must be greater than zero for an ellipse');
    finite(issues, value.radiusY, `${path}.radiusY`, (entry) => entry > 0, 'must be greater than zero for an ellipse');
    if (value.radius !== undefined) issue(issues, `${path}.radius`, 'radius is only allowed for a circle');
  } else {
    if (value.radius !== undefined || value.radiusX !== undefined || value.radiusY !== undefined) issue(issues, `${path}.radius`, 'shape radii require circle or ellipse');
  }
}

function validateAttributes(issues: CharacterValidationIssue[], attributes: unknown): void {
  if (!isRecord(attributes)) {
    issue(issues, 'character.attributes', 'must be an object');
    return;
  }
  checkKeys(issues, attributes, 'character.attributes', new Set(['strength', 'vitality', 'agility', 'intellect']));
  for (const field of ['strength', 'vitality', 'agility', 'intellect'] as const) {
    finite(issues, attributes[field], `character.attributes.${field}`, (entry) => entry >= 0, 'must be zero or greater');
  }
}

function validateHitbox(issues: CharacterValidationIssue[], value: unknown, path: string): value is CharacterHitboxDocument {
  if (!isRecord(value)) {
    issue(issues, path, 'must be an object');
    return false;
  }
  checkKeys(issues, value, path, new Set(['shape', 'width', 'height', 'radius', 'radiusX', 'radiusY', 'offsetX', 'offsetY', 'mirrorX']));
  validateShapeFields(issues, value, path, true);
  finite(issues, value.width, `${path}.width`, (entry) => entry > 0, 'must be greater than zero');
  finite(issues, value.height, `${path}.height`, (entry) => entry > 0, 'must be greater than zero');
  finite(issues, value.offsetX, `${path}.offsetX`, () => true, 'must be finite');
  finite(issues, value.offsetY, `${path}.offsetY`, () => true, 'must be finite');
  if (typeof value.mirrorX !== 'boolean') issue(issues, `${path}.mirrorX`, 'must be boolean');
  return true;
}

function validateEnemy(issues: CharacterValidationIssue[], enemy: unknown, options: CharacterValidationOptions): void {
  if (!isRecord(enemy)) {
    issue(issues, 'character.enemy', 'must be an object');
    return;
  }
  const ai = enemy.ai;
  const drop = enemy.drop;
  checkKeys(issues, enemy, 'character.enemy', new Set(['maxHp', 'ai', 'drop', 'projectile', 'impactEffect']));
  finite(issues, enemy.maxHp, 'character.enemy.maxHp', (entry) => entry > 0, 'must be greater than zero');
  if (!isRecord(ai)) issue(issues, 'character.enemy.ai', 'must be an object');
  else {
    checkKeys(issues, ai, 'character.enemy.ai', new Set(['behavior', 'aggroRange', 'attackRange', 'leapRange', 'fleeRange', 'wanderSpeed', 'chaseSpeed', 'attackCooldownMs', 'attackWindupMs', 'attackRecoveryMs', 'contactDamage', 'knockbackStrength', 'isRanged', 'isLeaper', 'projectileSpeed', 'knockbackResist']));
    if (ai.behavior !== undefined && ai.behavior !== 'standard' && ai.behavior !== 'slime-spider') issue(issues, 'character.enemy.ai.behavior', "must be 'standard' or 'slime-spider'");
    for (const field of ['aggroRange', 'attackRange', 'wanderSpeed', 'chaseSpeed', 'contactDamage', 'knockbackStrength'] as const) finite(issues, ai[field], `character.enemy.ai.${field}`, (entry) => entry >= 0, 'must be zero or greater');
    for (const field of ['attackCooldownMs', 'attackWindupMs', 'attackRecoveryMs'] as const) integer(issues, ai[field], `character.enemy.ai.${field}`, (entry) => entry >= 0, 'must be a non-negative integer');
    for (const field of ['leapRange', 'fleeRange'] as const) if (ai[field] !== undefined) finite(issues, ai[field], `character.enemy.ai.${field}`, (entry) => entry >= 0, 'must be zero or greater');
    if (typeof ai.isRanged !== 'boolean') issue(issues, 'character.enemy.ai.isRanged', 'must be boolean');
    if (ai.isLeaper !== undefined && typeof ai.isLeaper !== 'boolean') issue(issues, 'character.enemy.ai.isLeaper', 'must be boolean');
    finite(issues, ai.knockbackResist, 'character.enemy.ai.knockbackResist', (entry) => entry >= 0 && entry <= 1, 'must be between 0 and 1');
    if (ai.isRanged === true) finite(issues, ai.projectileSpeed, 'character.enemy.ai.projectileSpeed', (entry) => entry > 0, 'is required and must be greater than zero');
    else if (ai.projectileSpeed !== undefined) issue(issues, 'character.enemy.ai.projectileSpeed', 'is only allowed for ranged enemies');
    if (ai.isLeaper === true) finite(issues, ai.leapRange, 'character.enemy.ai.leapRange', (entry) => entry >= 0, 'is required for leapers');
    else if (ai.leapRange !== undefined) issue(issues, 'character.enemy.ai.leapRange', 'is only allowed for leapers');
  }
  if (!isRecord(drop)) issue(issues, 'character.enemy.drop', 'must be an object');
  else {
    checkKeys(issues, drop, 'character.enemy.drop', new Set(['xp', 'coins', 'items']));
    integer(issues, drop.xp, 'character.enemy.drop.xp', (entry) => entry >= 0, 'must be a non-negative integer');
    integer(issues, drop.coins, 'character.enemy.drop.coins', (entry) => entry >= 0, 'must be a non-negative integer');
    if (drop.items !== undefined && !Array.isArray(drop.items)) issue(issues, 'character.enemy.drop.items', 'must be an array');
    for (const [index, item] of (Array.isArray(drop.items) ? drop.items : []).entries()) {
      const itemPath = `character.enemy.drop.items[${index}]`;
      if (!isRecord(item)) { issue(issues, itemPath, 'must be an object'); continue; }
      checkKeys(issues, item, itemPath, new Set(['itemId', 'chance', 'count']));
      stringValue(issues, item.itemId, `${itemPath}.itemId`, (entry) => options.knownItemIds?.has(entry) ?? entry.length > 0, 'must reference a known item');
      finite(issues, item.chance, `${itemPath}.chance`, (entry) => entry >= 0 && entry <= 1, 'must be between 0 and 1');
      if (item.count !== undefined) integer(issues, item.count, `${itemPath}.count`, (entry) => entry >= 1, 'must be at least 1');
    }
  }
  if (enemy.projectile !== undefined) {
    if (!isRecord(enemy.projectile)) issue(issues, 'character.enemy.projectile', 'must be an object');
    else {
      checkKeys(issues, enemy.projectile, 'character.enemy.projectile', new Set(['projectileId', 'assetId', 'damage']));
      if (enemy.projectile.projectileId === undefined && enemy.projectile.assetId === undefined) issue(issues, 'character.enemy.projectile', 'must reference a projectile ID or manifest asset');
      if (enemy.projectile.projectileId !== undefined) stringValue(issues, enemy.projectile.projectileId, 'character.enemy.projectile.projectileId', (entry) => ID_PATTERN.test(entry), 'must be a lowercase stable projectile ID');
      if (enemy.projectile.assetId !== undefined) stringValue(issues, enemy.projectile.assetId, 'character.enemy.projectile.assetId', (entry) => entry in (options.assetManifest?.assets ?? ASSET_MANIFEST.assets), 'must reference a known manifest asset');
      finite(issues, enemy.projectile.damage, 'character.enemy.projectile.damage', (entry) => entry >= 0, 'must be zero or greater');
    }
  }
  if (enemy.impactEffect !== undefined) {
    if (!isRecord(enemy.impactEffect)) issue(issues, 'character.enemy.impactEffect', 'must be an object');
    else {
      checkKeys(issues, enemy.impactEffect, 'character.enemy.impactEffect', new Set(['visualSetId', 'clipId', 'distance']));
      stringValue(issues, enemy.impactEffect.visualSetId, 'character.enemy.impactEffect.visualSetId', (entry) => entry.length > 0, 'must be a visual set ID');
      stringValue(issues, enemy.impactEffect.clipId, 'character.enemy.impactEffect.clipId', (entry) => ID_PATTERN.test(entry), 'must be a clip ID');
      finite(issues, enemy.impactEffect.distance, 'character.enemy.impactEffect.distance', (entry) => entry >= 0, 'must be zero or greater');
    }
  }
}

export function validateCharacterDocument(
  value: unknown,
  visualSet: VisualSetDocument | undefined,
  options: CharacterValidationOptions = {},
): CharacterValidationIssue[] {
  const issues: CharacterValidationIssue[] = [];
  if (!isRecord(value)) {
    issue(issues, 'character', 'must be an object');
    return issues;
  }
  checkKeys(issues, value, 'character', new Set(['$schema', 'version', 'characterId', 'displayName', 'kind', 'runtimeRole', 'visualSetId', 'attributes', 'body', 'hitboxes', 'animationTracks', 'player', 'enemy']));
  if (value.version !== 1) issue(issues, 'character.version', 'must be version 1');
  const hasCharacterId = stringValue(issues, value.characterId, 'character.characterId', (entry) => CHARACTER_ID_PATTERN.test(entry) && entry.length <= 80, 'must be a lowercase kebab-case ID');
  const characterId = hasCharacterId && typeof value.characterId === 'string' ? value.characterId : undefined;
  if (characterId && !options.allowDuplicateIdentity && options.characterIds?.has(characterId)) issue(issues, 'character.characterId', `duplicate character ID '${characterId}'`);
  stringValue(issues, value.displayName, 'character.displayName', (entry) => entry.trim().length > 0 && entry.length <= 80, 'must be a non-empty display name of at most 80 characters');
  if (value.kind !== 'player' && value.kind !== 'enemy') issue(issues, 'character.kind', "must be 'player' or 'enemy'");
  if (value.runtimeRole !== undefined && value.runtimeRole !== 'primary-player') issue(issues, 'character.runtimeRole', "must be 'primary-player'");
  if (value.runtimeRole === 'primary-player' && value.kind !== 'player') issue(issues, 'character.runtimeRole', 'is only allowed on a player');
  const hasVisualSetId = stringValue(issues, value.visualSetId, 'character.visualSetId', (entry) => ID_PATTERN.test(entry), 'must be a lowercase dotted stable ID');
  const visualSetId = hasVisualSetId && typeof value.visualSetId === 'string' ? value.visualSetId : undefined;
  if (visualSetId && visualSet?.visualSetId !== visualSetId) issue(issues, 'character.visualSetId', 'must match the package visual set ID');
  if (visualSetId && !options.allowDuplicateIdentity && options.visualSetIds?.has(visualSetId)) issue(issues, 'character.visualSetId', `duplicate visual set ID '${visualSetId}'`);
  if (value.attributes !== undefined) validateAttributes(issues, value.attributes);
  validateBody(issues, value.body);
  if (!isRecord(value.hitboxes)) issue(issues, 'character.hitboxes', 'must be an object');
  for (const [hitboxId, hitbox] of Object.entries(isRecord(value.hitboxes) ? value.hitboxes : {})) {
    if (!ID_PATTERN.test(hitboxId) || hitboxId.length > 80) issue(issues, `character.hitboxes.${hitboxId}`, 'must use a lowercase stable ID');
    validateHitbox(issues, hitbox, `character.hitboxes.${hitboxId}`);
  }
  if (!isRecord(value.animationTracks)) issue(issues, 'character.animationTracks', 'must be an object');
  const clips = visualSet?.clips ?? {};
  for (const [clipId, track] of Object.entries(isRecord(value.animationTracks) ? value.animationTracks : {})) {
    const trackPath = `character.animationTracks.${clipId}`;
    if (!clips[clipId]) issue(issues, trackPath, `unknown clip '${clipId}'`);
    if (!isRecord(track)) { issue(issues, trackPath, 'must be an object'); continue; }
    checkKeys(issues, track, trackPath, new Set(['hitboxSpans', 'events']));
    const frameLength = clips[clipId]
      ? clips[clipId].keyframeTimes !== undefined && clips[clipId].durationSeconds !== undefined
        ? timelineFrameCount(clips[clipId])
        : clips[clipId].frames.length
      : 0;
    for (const [index, span] of (Array.isArray(track.hitboxSpans) ? track.hitboxSpans : []).entries()) {
      const spanPath = `${trackPath}.hitboxSpans[${index}]`;
      if (!isRecord(span)) { issue(issues, spanPath, 'must be an object'); continue; }
      checkKeys(issues, span, spanPath, new Set(['hitboxId', 'from', 'through']));
      if (typeof span.hitboxId !== 'string' || !value.hitboxes || !isRecord(value.hitboxes) || !value.hitboxes[span.hitboxId]) issue(issues, `${spanPath}.hitboxId`, `unknown hitbox '${String(span.hitboxId)}'`);
      integer(issues, span.from, `${spanPath}.from`, (entry) => entry >= 0 && entry < frameLength, `position must be inside 0..${Math.max(0, frameLength - 1)}`);
      integer(issues, span.through, `${spanPath}.through`, (entry) => entry >= (typeof span.from === 'number' ? span.from : 0) && entry < frameLength, `position must be inside 0..${Math.max(0, frameLength - 1)}`);
    }
    if (track.events !== undefined && !Array.isArray(track.events)) issue(issues, `${trackPath}.events`, 'must be an array');
    for (const [index, event] of (Array.isArray(track.events) ? track.events : []).entries()) {
      const eventPath = `${trackPath}.events[${index}]`;
      if (!isRecord(event)) { issue(issues, eventPath, 'must be an object'); continue; }
      checkKeys(issues, event, eventPath, new Set(['at', 'eventId', 'payload']));
      integer(issues, event.at, `${eventPath}.at`, (entry) => entry >= 0 && entry < frameLength, `position must be inside 0..${Math.max(0, frameLength - 1)}`);
      if (typeof event.eventId !== 'string' || !ID_PATTERN.test(event.eventId)) issue(issues, `${eventPath}.eventId`, 'must be a lowercase stable event ID');
      if (event.payload !== undefined && !isJsonValue(event.payload)) issue(issues, `${eventPath}.payload`, 'must be JSON data');
    }
  }
  if (value.kind === 'player') {
    if (value.enemy !== undefined) issue(issues, 'character.enemy', 'is forbidden for players');
    if (!isRecord(value.player)) issue(issues, 'character.player', 'is required for players');
    else {
      checkKeys(issues, value.player, 'character.player', new Set(['name', 'movement', 'progression']));
      stringValue(issues, value.player.name, 'character.player.name', (entry) => entry.trim().length > 0 && entry.length <= 80, 'must be a non-empty name of at most 80 characters');
      if (!isRecord(value.player.movement)) issue(issues, 'character.player.movement', 'must be an object');
      else {
        for (const field of ['baseSpeed', 'boostSpeed', 'dodgeSpeed'] as const) finite(issues, value.player.movement[field], `character.player.movement.${field}`, (entry) => entry >= 0, 'must be zero or greater');
        integer(issues, value.player.movement.dodgeInvulnerabilityMs, 'character.player.movement.dodgeInvulnerabilityMs', (entry) => entry >= 0, 'must be a non-negative integer');
      }
      if (!isRecord(value.player.progression)) issue(issues, 'character.player.progression', 'must be an object');
      else {
        finite(issues, value.player.progression.baseMaxHp, 'character.player.progression.baseMaxHp', (entry) => entry > 0, 'must be greater than zero');
        finite(issues, value.player.progression.baseMaxEnergy, 'character.player.progression.baseMaxEnergy', (entry) => entry > 0, 'must be greater than zero');
        for (const field of ['hpPerLevel', 'attackPerLevel', 'defensePerLevel', 'energyPerLevel'] as const) finite(issues, value.player.progression[field], `character.player.progression.${field}`, (entry) => entry >= 0, 'must be zero or greater');
      }
    }
  } else if (value.kind === 'enemy') {
    if (value.player !== undefined) issue(issues, 'character.player', 'is forbidden for enemies');
    validateEnemy(issues, value.enemy, options);
  }
  return issues;
}

export function validateCharacterPackage(
  packageValue: unknown,
  options: CharacterValidationOptions = {},
): CharacterValidationIssue[] {
  if (!isRecord(packageValue)) return [{ path: 'package', message: 'must be an object' }];
  const visualSet = packageValue.visualSet as VisualSetDocument | undefined;
  return [
    ...validateVisualSetDocument(visualSet, 'visualSet', options.assetManifest),
    ...validateCharacterDocument(packageValue.character, visualSet, options),
  ];
}

export function normalizeCharacterPackage(packageValue: CharacterPackage): CharacterPackage {
  const character = JSON.parse(JSON.stringify(packageValue.character)) as CharacterDocument;
  const visualSet = JSON.parse(JSON.stringify(packageValue.visualSet)) as VisualSetDocument;
  for (const track of Object.values(character.animationTracks)) {
    if (track.hitboxSpans) track.hitboxSpans = [...track.hitboxSpans].sort((a, b) => a.from - b.from || a.through - b.through || a.hitboxId.localeCompare(b.hitboxId));
  }
  return { character, visualSet };
}

export function cloneCharacterPackage(packageValue: CharacterPackage): CharacterPackage {
  return JSON.parse(JSON.stringify(packageValue)) as CharacterPackage;
}

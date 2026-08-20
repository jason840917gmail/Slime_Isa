import type {
  AuthoredWeaponDefinition,
  LayeredWeaponDefinition,
  LegacyWeaponDefinition,
  WeaponAnimationDocument,
  WeaponDefinition,
  WeaponHitboxDocument,
  WeaponAttackTrackDocument,
} from './types';
import { layeredTimelineFrameCount, timelineFrameCount, validateLayeredAnimationDocument } from '../../shared/animation';

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function animationTimelineFrameCount(animation: WeaponAnimationDocument): number {
  return animation.keyframeTimes !== undefined && animation.durationSeconds !== undefined
    ? timelineFrameCount(animation)
    : Math.max(1, animation.frames.length);
}

function validateAnimation(animation: unknown, path: string, issues: string[]): void {
  if (animation === null || typeof animation !== 'object' || Array.isArray(animation)) {
    issues.push(`${path}: must be an object`);
    return;
  }
  const clip = animation as Partial<WeaponAnimationDocument>;
  if (!Array.isArray(clip.frames) || clip.frames.length === 0 || clip.frames.some((frame) => !Number.isInteger(frame) || frame < 0)) issues.push(`${path}.frames: must contain non-negative integers`);
  if (typeof clip.framesPerSecond !== 'number' || !Number.isInteger(clip.framesPerSecond) || clip.framesPerSecond < 1 || clip.framesPerSecond > 240) issues.push(`${path}.framesPerSecond: must be an integer between 1 and 240`);
  if (typeof clip.loop !== 'boolean') issues.push(`${path}.loop: must be boolean`);
  if (clip.loopMode !== undefined && clip.loopMode !== 'wrap' && clip.loopMode !== 'ping-pong') issues.push(`${path}.loopMode: must be 'wrap' or 'ping-pong'`);
  const hasTimes = clip.keyframeTimes !== undefined;
  const hasDuration = clip.durationSeconds !== undefined;
  if (hasTimes !== hasDuration) issues.push(`${path}: keyframeTimes and durationSeconds must be authored together`);
  if (hasDuration && (typeof clip.durationSeconds !== 'number' || !Number.isFinite(clip.durationSeconds) || clip.durationSeconds <= 0)) {
    issues.push(`${path}.durationSeconds: must be positive and finite`);
  }
  if (hasTimes) {
    if (!Array.isArray(clip.keyframeTimes)) issues.push(`${path}.keyframeTimes: must be an array`);
    else {
      if (Array.isArray(clip.frames) && clip.keyframeTimes.length !== clip.frames.length) issues.push(`${path}.keyframeTimes: must match frames length`);
      const timelineFrames = typeof clip.durationSeconds === 'number' && Number.isFinite(clip.durationSeconds) && typeof clip.framesPerSecond === 'number'
        ? Math.max(1, Math.round(clip.durationSeconds * clip.framesPerSecond))
        : 0;
      clip.keyframeTimes.forEach((time, index) => {
        if (!Number.isInteger(time) || time < 0 || (timelineFrames > 0 && time >= timelineFrames)) issues.push(`${path}.keyframeTimes[${index}]: must be an integer inside the clip timeline`);
        if (index === 0 && time !== 0) issues.push(`${path}.keyframeTimes[0]: must be 0`);
        if (index > 0 && time <= clip.keyframeTimes![index - 1]) issues.push(`${path}.keyframeTimes: values must be strictly increasing`);
      });
      if (Array.isArray(clip.frames) && timelineFrames > 0 && clip.frames.length > timelineFrames) issues.push(`${path}: cannot fit all keyframes in its timeline`);
    }
  }
  if (clip.frameTransforms !== undefined) {
    if (!isRecord(clip.frameTransforms)) issues.push(`${path}.frameTransforms: must be an object keyed by animation position`);
    else for (const [position, rawTransform] of Object.entries(clip.frameTransforms)) {
      const transformPath = `${path}.frameTransforms.${position}`;
      if (!/^\d+$/.test(position)) issues.push(`${transformPath}: key must be a non-negative animation position`);
      if (!isRecord(rawTransform)) {
        issues.push(`${transformPath}: must be an object`);
        continue;
      }
      for (const field of ['offset', 'scale'] as const) {
        const pair = rawTransform[field];
        if (pair !== undefined && (!Array.isArray(pair) || pair.length !== 2 || pair.some((entry) => typeof entry !== 'number' || !Number.isFinite(entry)))) {
          issues.push(`${transformPath}.${field}: must contain exactly two finite numbers`);
        } else if (field === 'scale' && pair?.some((entry) => entry <= 0)) {
          issues.push(`${transformPath}.scale: values must be greater than zero`);
        }
      }
      if (rawTransform.rotationDeg !== undefined && (typeof rawTransform.rotationDeg !== 'number' || !Number.isFinite(rawTransform.rotationDeg))) {
        issues.push(`${transformPath}.rotationDeg: must be a finite number`);
      }
       if (clip.frames && Number.isInteger(Number(position)) && Number(position) >= clip.frames.length) issues.push(`${transformPath}: must reference a position inside frames`);
    }
  }
}

function validateNumber(value: unknown, path: string, issues: string[], minimum = 0): void {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum) issues.push(`${path}: must be a finite number >= ${minimum}`);
}

function validateHitboxes(value: unknown, issues: string[], rootPath = 'weapon.hitboxes'): void {
  if (!isRecord(value)) {
    issues.push(`${rootPath}: must be an object keyed by stable hitbox IDs`);
    return;
  }
  for (const [hitboxId, rawHitbox] of Object.entries(value)) {
    const path = `${rootPath}.${hitboxId}`;
    if (!isRecord(rawHitbox)) {
      issues.push(`${path}: must be an object`);
      continue;
    }
    const hitbox = rawHitbox as Partial<WeaponHitboxDocument>;
    if (!['rectangle', 'circle', 'ellipse', 'sector'].includes(String(hitbox.shape))) issues.push(`${path}.shape: must be rectangle, circle, ellipse, or sector`);
    validateNumber(hitbox.width, `${path}.width`, issues, 0.001);
    validateNumber(hitbox.height, `${path}.height`, issues, 0.001);
    validateNumber(hitbox.offsetX, `${path}.offsetX`, issues, -Infinity);
    validateNumber(hitbox.offsetY, `${path}.offsetY`, issues, -Infinity);
    for (const field of ['radius', 'radiusX', 'radiusY', 'innerRadius', 'outerRadius', 'arcWidthRad', 'damageMultiplier', 'knockbackMultiplier'] as const) {
      if (hitbox[field] !== undefined) validateNumber(hitbox[field], `${path}.${field}`, issues, 0);
    }
    if (hitbox.shape === 'sector') {
      if (hitbox.outerRadius === undefined) issues.push(`${path}.outerRadius: is required for sector hitboxes`);
      if (hitbox.arcWidthRad === undefined) issues.push(`${path}.arcWidthRad: is required for sector hitboxes`);
      if (hitbox.arcWidthRad !== undefined && hitbox.arcWidthRad > Math.PI * 2) issues.push(`${path}.arcWidthRad: must be <= 2π`);
    }
  }
}

function validateAttackTrack(
  value: unknown,
  weapon: Partial<WeaponDefinition>,
  issues: string[],
  path = 'weapon.attackTrack',
  animation?: WeaponAnimationDocument,
  authoredHitboxes?: unknown,
): void {
  if (!isRecord(value)) {
    issues.push(`${path}: must be an object`);
    return;
  }
  const track = value as Partial<WeaponAttackTrackDocument>;
  const hitboxes = isRecord(authoredHitboxes) ? authoredHitboxes : isRecord(weapon.hitboxes) ? weapon.hitboxes : {};
  if (!Array.isArray(track.hitboxSpans)) {
    issues.push(`${path}.hitboxSpans: must be an array`);
  } else {
    const spansByHitbox = new Map<string, Array<{ from: number; through: number }>>();
    const attackFrameCount = animation ? animationTimelineFrameCount(animation) : weapon.animations?.attack ? animationTimelineFrameCount(weapon.animations.attack) : undefined;
    track.hitboxSpans.forEach((rawSpan, index) => {
      const spanPath = `${path}.hitboxSpans[${index}]`;
      if (!isRecord(rawSpan)) {
        issues.push(`${spanPath}: must be an object`);
        return;
      }
      const hitboxId = rawSpan.hitboxId;
      const from = typeof rawSpan.from === 'number' ? rawSpan.from : Number.NaN;
      const through = typeof rawSpan.through === 'number' ? rawSpan.through : Number.NaN;
      if (typeof hitboxId !== 'string' || !hitboxId) issues.push(`${spanPath}.hitboxId: must reference a named hitbox`);
      else if (!(hitboxId in hitboxes)) issues.push(`${spanPath}.hitboxId: '${hitboxId}' is not defined in weapon.hitboxes`);
      if (!Number.isInteger(from) || from < 0) issues.push(`${spanPath}.from: must be a non-negative integer`);
      if (!Number.isInteger(through) || through < 0 || (Number.isInteger(from) && through < from)) issues.push(`${spanPath}.through: must be an integer >= from`);
      if (attackFrameCount !== undefined && Number.isInteger(through) && through >= attackFrameCount) issues.push(`${spanPath}.through: must be inside the selected attack animation`);
      if (typeof hitboxId === 'string' && Number.isInteger(from) && Number.isInteger(through)) {
        const spans = spansByHitbox.get(hitboxId) ?? [];
        spans.push({ from, through });
        spansByHitbox.set(hitboxId, spans);
      }
    });
    for (const [hitboxId, spans] of spansByHitbox) {
      spans.sort((left, right) => left.from - right.from);
      for (let index = 1; index < spans.length; index += 1) {
        if (spans[index].from <= spans[index - 1].through) issues.push(`${path}.hitboxSpans: '${hitboxId}' has overlapping windows`);
      }
    }
  }
  if (track.events !== undefined) {
    if (!Array.isArray(track.events)) issues.push(`${path}.events: must be an array`);
    else track.events.forEach((event, index) => {
      const eventPath = `${path}.events[${index}]`;
      if (!isRecord(event)) { issues.push(`${eventPath}: must be an object`); return; }
      const at = typeof event.at === 'number' ? event.at : Number.NaN;
      if (!Number.isInteger(at) || at < 0) issues.push(`${eventPath}.at: must be a non-negative integer`);
      if (typeof event.eventId !== 'string' || !event.eventId.trim()) issues.push(`${eventPath}.eventId: must be a non-empty string`);
       const attackFrameCount = animation ? animationTimelineFrameCount(animation) : weapon.animations?.attack ? animationTimelineFrameCount(weapon.animations.attack) : undefined;
      if (attackFrameCount !== undefined && Number.isInteger(at) && at >= attackFrameCount) issues.push(`${eventPath}.at: must be inside the selected attack animation`);
    });
  }
}

export function validateWeaponDefinition(value: unknown): string[] {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return ['weapon: must be an object'];
  const authored = value as Partial<AuthoredWeaponDefinition>;
  if (authored.version !== 1 && authored.version !== 2) return ['weapon.version: must be 1 or 2'];
  return authored.version === 1
    ? validateLegacyWeaponDefinition(authored as LegacyWeaponDefinition)
    : validateLayeredWeaponDefinition(authored as LayeredWeaponDefinition);
}

function validateCommonWeaponFields(weapon: Partial<AuthoredWeaponDefinition>, issues: string[]): void {
  if (typeof weapon.weaponId !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(weapon.weaponId)) issues.push('weapon.weaponId: must be a lowercase kebab-case ID');
  if (typeof weapon.displayName !== 'string' || weapon.displayName.trim().length === 0 || weapon.displayName.length > 80) issues.push('weapon.displayName: must be between 1 and 80 characters');
  if (weapon.category !== 'melee' && weapon.category !== 'ranged') issues.push("weapon.category: must be 'melee' or 'ranged'");
  for (const field of ['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxOffset', 'hitboxDurationMs', 'knockStrength'] as const) {
    if (typeof weapon[field] !== 'number' || !Number.isFinite(weapon[field]) || weapon[field] < 0) issues.push(`weapon.${field}: must be zero or greater`);
  }
  if (typeof weapon.vfxColor !== 'number' || !Number.isInteger(weapon.vfxColor) || weapon.vfxColor < 0) issues.push('weapon.vfxColor: must be a non-negative integer');
  if (typeof weapon.unlockLevel !== 'number' || !Number.isInteger(weapon.unlockLevel) || weapon.unlockLevel < 1) issues.push('weapon.unlockLevel: must be a positive integer');
  if (typeof weapon.iconKey !== 'string') issues.push('weapon.iconKey: must be a string');
  if (typeof weapon.description !== 'string') issues.push('weapon.description: must be a string');
  if (weapon.damageModifiers !== undefined) {
    if (!Array.isArray(weapon.damageModifiers)) {
      issues.push('weapon.damageModifiers: must be an array');
    } else {
      const tags = new Set<string>();
      weapon.damageModifiers.forEach((entry, index) => {
        const path = `weapon.damageModifiers[${index}]`;
        if (!isRecord(entry)) {
          issues.push(`${path}: must be an object`);
          return;
        }
        if (typeof entry.targetTag !== 'string' || !entry.targetTag.trim()) {
          issues.push(`${path}.targetTag: must be a non-empty string`);
        } else if (tags.has(entry.targetTag)) {
          issues.push(`${path}.targetTag: duplicate '${entry.targetTag}'`);
        } else {
          tags.add(entry.targetTag);
        }
        if (typeof entry.modifier !== 'number' || !Number.isFinite(entry.modifier) || entry.modifier < 0) {
          issues.push(`${path}.modifier: must be a finite number >= 0`);
        }
      });
    }
  }
}

function validateLegacyWeaponDefinition(weapon: LegacyWeaponDefinition): string[] {
  const issues: string[] = [];
  validateCommonWeaponFields(weapon, issues);
  const hasActionId = typeof weapon.characterActionId === 'string' && weapon.characterActionId.trim().length > 0;
  const hasLegacyAnimation = typeof weapon.animKey === 'string' && weapon.animKey.length > 0;
  if (!hasActionId && !hasLegacyAnimation) issues.push('weapon.characterActionId: must be provided (or legacy weapon.animKey must be non-empty)');
  if (weapon.assetId !== undefined && (typeof weapon.assetId !== 'string' || weapon.assetId.length === 0)) issues.push('weapon.assetId: must be a non-empty string');
  if (weapon.animations !== undefined) {
    validateAnimation(weapon.animations.idle, 'weapon.animations.idle', issues);
    validateAnimation(weapon.animations.attack, 'weapon.animations.attack', issues);
    validateAnimation(weapon.animations.impact, 'weapon.animations.impact', issues);
  }
  if (weapon.directionalAttacks !== undefined) {
    if (!isRecord(weapon.directionalAttacks)) issues.push('weapon.directionalAttacks: must be an object');
    else for (const direction of ['right', 'left', 'up', 'down', 'side'] as const) {
      const attack = weapon.directionalAttacks[direction];
      if (attack === undefined) continue;
      const path = `weapon.directionalAttacks.${direction}`;
      if (!isRecord(attack)) {
        issues.push(`${path}: must be an object`);
        continue;
      }
      validateAnimation(attack.animation, `${path}.animation`, issues);
      if (attack.characterActionId !== undefined && (typeof attack.characterActionId !== 'string' || !attack.characterActionId.trim())) issues.push(`${path}.characterActionId: must be a non-empty string`);
      if (attack.hitboxes !== undefined) validateHitboxes(attack.hitboxes, issues, `${path}.hitboxes`);
      const inheritedHitboxes = direction === 'left' ? weapon.directionalAttacks.right?.hitboxes : undefined;
      if (attack.attackTrack !== undefined) validateAttackTrack(attack.attackTrack, weapon, issues, `${path}.attackTrack`, attack.animation as WeaponAnimationDocument, attack.hitboxes ?? inheritedHitboxes);
    }
  }
  if (weapon.hitboxes !== undefined) validateHitboxes(weapon.hitboxes, issues);
  if (weapon.attackTrack !== undefined) {
    if (!weapon.animations?.attack) issues.push('weapon.animations.attack: is required when weapon.attackTrack is authored');
    validateAttackTrack(weapon.attackTrack, weapon, issues);
  }
  if (weapon.visual !== undefined) {
    const sourceOffset = weapon.visual.sourceOffset;
    if (!Array.isArray(sourceOffset) || sourceOffset.length !== 2 || sourceOffset.some((entry) => typeof entry !== 'number' || !Number.isInteger(entry))) issues.push('weapon.visual.sourceOffset: must contain exactly two integers');
  }
  return issues;
}

function validateLayeredTrack(
  value: unknown,
  path: string,
  timelineFrames: number,
  hitboxes: Readonly<Record<string, WeaponHitboxDocument>>,
  issues: string[],
): void {
  if (!isRecord(value)) {
    issues.push(`${path}: must be an object`);
    return;
  }
  const spans = value.hitboxSpans;
  if (!Array.isArray(spans)) issues.push(`${path}.hitboxSpans: must be an array`);
  else {
    const byHitbox = new Map<string, Array<{ readonly from: number; readonly through: number }>>();
    spans.forEach((span, index) => {
      const spanPath = `${path}.hitboxSpans[${index}]`;
      if (!isRecord(span)) { issues.push(`${spanPath}: must be an object`); return; }
      const hitboxId = span.hitboxId;
      const from = typeof span.from === 'number' ? span.from : Number.NaN;
      const through = typeof span.through === 'number' ? span.through : Number.NaN;
      if (typeof hitboxId !== 'string' || !(hitboxId in hitboxes)) issues.push(`${spanPath}.hitboxId: must reference a directional hitbox`);
      if (!Number.isInteger(from) || from < 0) issues.push(`${spanPath}.from: must be a non-negative integer`);
      if (!Number.isInteger(through) || through < from || through >= timelineFrames) issues.push(`${spanPath}.through: must be inside the attack timeline and >= from`);
      if (typeof hitboxId === 'string' && Number.isInteger(from) && Number.isInteger(through)) {
        const previous = byHitbox.get(hitboxId) ?? [];
        previous.push({ from, through });
        byHitbox.set(hitboxId, previous);
      }
    });
    for (const [hitboxId, hitboxSpans] of byHitbox) {
      hitboxSpans.sort((left, right) => left.from - right.from);
      for (let index = 1; index < hitboxSpans.length; index += 1) {
        if (hitboxSpans[index].from <= hitboxSpans[index - 1].through) issues.push(`${path}.hitboxSpans: '${hitboxId}' has overlapping windows`);
      }
    }
  }
  if (value.events !== undefined) {
    if (!Array.isArray(value.events)) issues.push(`${path}.events: must be an array`);
    else value.events.forEach((event, index) => {
      const eventPath = `${path}.events[${index}]`;
      if (!isRecord(event)) { issues.push(`${eventPath}: must be an object`); return; }
      if (!Number.isInteger(event.at) || (event.at as number) < 0 || (event.at as number) >= timelineFrames) issues.push(`${eventPath}.at: must be inside the attack timeline`);
      if (typeof event.eventId !== 'string' || !event.eventId.trim()) issues.push(`${eventPath}.eventId: must be non-empty`);
      if (event.eventId === 'weapon.impact') issues.push(`${eventPath}.eventId: legacy weapon.impact events are forbidden in version 2`);
    });
  }
}

function validateLayeredWeaponDefinition(weapon: LayeredWeaponDefinition): string[] {
  const issues: string[] = [];
  validateCommonWeaponFields(weapon, issues);
  if (typeof weapon.characterActionId !== 'string' || !weapon.characterActionId.trim()) issues.push('weapon.characterActionId: must be non-empty');
  if (weapon.onHitEffectId !== undefined && !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(weapon.onHitEffectId)) issues.push('weapon.onHitEffectId: must be a lowercase kebab-case ID');
  const rawWeapon = weapon as unknown as Record<string, unknown>;
  for (const forbidden of ['animKey', 'assetId', 'visual', 'attackTrack', 'hitboxes']) {
    if (forbidden in rawWeapon) issues.push(`weapon.${forbidden}: is forbidden in version 2`);
  }
  if (!isRecord(weapon.animations) || !('idle' in weapon.animations)) issues.push('weapon.animations.idle: is required');
  else {
    issues.push(...validateLayeredAnimationDocument(weapon.animations.idle, { path: 'weapon.animations.idle', allowNoVisualLayers: true }));
    for (const forbidden of ['attack', 'impact']) {
      if (forbidden in weapon.animations) issues.push(`weapon.animations.${forbidden}: is forbidden in version 2`);
    }
  }
  if (!isRecord(weapon.directionalAttacks)) {
    issues.push('weapon.directionalAttacks: must be an object');
    return issues;
  }
  for (const direction of ['right', 'down'] as const) {
    if (!(direction in weapon.directionalAttacks)) issues.push(`weapon.directionalAttacks.${direction}: is required`);
  }
  for (const [direction, rawAttack] of Object.entries(weapon.directionalAttacks)) {
    const path = `weapon.directionalAttacks.${direction}`;
    if (!['right', 'left', 'up', 'down'].includes(direction)) { issues.push(`${path}: direction is not supported in version 2`); continue; }
    if (!isRecord(rawAttack)) { issues.push(`${path}: must be an object`); continue; }
    issues.push(...validateLayeredAnimationDocument(rawAttack.animation, { path: `${path}.animation`, allowLoop: false, allowNoVisualLayers: true }));
    if (typeof rawAttack.characterActionId !== 'string' || !rawAttack.characterActionId.trim()) issues.push(`${path}.characterActionId: must be non-empty`);
    validateHitboxes(rawAttack.hitboxes, issues, `${path}.hitboxes`);
    if (rawAttack.attackTrack !== undefined && isRecord(rawAttack.hitboxes)) {
      let timelineFrames = 0;
      try { timelineFrames = layeredTimelineFrameCount(rawAttack.animation as never); } catch { /* animation issues already reported */ }
      if (timelineFrames > 0) validateLayeredTrack(rawAttack.attackTrack, `${path}.attackTrack`, timelineFrames, rawAttack.hitboxes as Readonly<Record<string, WeaponHitboxDocument>>, issues);
    }
  }
  return issues;
}

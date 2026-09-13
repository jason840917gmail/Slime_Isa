import fattyOneEyeJson from './fatty-one-eye.json';
import { isEnemyEffectImmunity } from '../enemies/EnemyEffects';
import type { BossDefinition } from './types';
import type { BossEditorPreview } from './types';
import { ASSET_MANIFEST, getAsset, type AssetId } from '../../infrastructure/assets/manifest';

const BOSS_INPUTS: readonly unknown[] = [fattyOneEyeJson];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function positive(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function nonNegativeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function positiveInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) > 0;
}

function validatePositiveFields(record: Record<string, unknown>, fields: readonly string[], label: string): void {
  for (const field of fields) {
    if (!positive(record[field])) throw new Error(`Boss '${label}' has invalid ${field}`);
  }
}

function normalizeBoss(value: unknown): BossDefinition {
  if (!isRecord(value) || typeof value.id !== 'string' || typeof value.displayName !== 'string'
    || typeof value.characterId !== 'string' || typeof value.visualSetId !== 'string' || !positive(value.visualScale) || !positive(value.maxHp)
    || !isRecord(value.editorPreview)
    || !isRecord(value.body) || !isRecord(value.eye) || !positive(value.chaseSpeed)
    || !isRecord(value.contactHop) || !isRecord(value.leap)
    || !Array.isArray(value.allowedWeaponIds) || value.allowedWeaponIds.length === 0
    || !value.allowedWeaponIds.every((entry) => typeof entry === 'string')) {
    throw new Error('Invalid boss definition');
  }
  if (typeof value.editorPreview.assetId !== 'string'
    || !(value.editorPreview.assetId in ASSET_MANIFEST.assets)
    || !nonNegativeInteger(value.editorPreview.idleFrame)) {
    throw new Error(`Boss '${value.id}' has invalid editor preview`);
  }
  validatePositiveFields(value.body, ['width', 'height'], value.id);
  validatePositiveFields(value.eye, ['width', 'height'], value.id);
  for (const field of ['centerOffsetX', 'centerOffsetY'] as const) {
    if (typeof value.body[field] !== 'number' || !Number.isFinite(value.body[field])) throw new Error(`Boss '${value.id}' has invalid body ${field}`);
  }
  for (const field of ['offsetX', 'offsetY'] as const) {
    if (typeof value.eye[field] !== 'number' || !Number.isFinite(value.eye[field])) throw new Error(`Boss '${value.id}' has invalid eye ${field}`);
  }
  if (typeof value.contactHop.clipId !== 'string' || typeof value.contactHop.hitboxId !== 'string') {
    throw new Error(`Boss '${value.id}' has invalid contact-hop animation references`);
  }
  validatePositiveFields(value.contactHop, ['cooldownMs', 'damage', 'knockbackStrength'], value.id);
  validatePositiveFields(value.leap, ['cadenceMs', 'smallHopCount', 'smallHopDurationMs', 'betweenHopsMs', 'airTimeMs', 'landingRadius', 'landingDamage', 'landingKnockbackStrength', 'recoveryMs', 'crackFadeMs'], value.id);
  for (const field of ['cooldownMs'] as const) {
    if (!positiveInteger(value.contactHop[field])) throw new Error(`Boss '${value.id}' has invalid contactHop ${field}`);
  }
  for (const field of ['cadenceMs', 'smallHopCount', 'smallHopDurationMs', 'betweenHopsMs', 'airTimeMs', 'recoveryMs', 'crackFadeMs'] as const) {
    if (!positiveInteger(value.leap[field])) throw new Error(`Boss '${value.id}' has invalid leap ${field}`);
  }
  if (new Set(value.allowedWeaponIds).size !== value.allowedWeaponIds.length) throw new Error(`Boss '${value.id}' has duplicate allowed weapons`);
  const previewAsset = getAsset(value.editorPreview.assetId as AssetId);
  const previewSource = previewAsset.source;
  if (previewAsset.source.kind !== 'spritesheet'
    || !('frame' in previewSource)
    || !isRecord(previewSource.frame)) {
    throw new Error(`Boss '${value.id}' editor preview must use a spritesheet`);
  }
  const previewFrame = previewSource.frame as Record<string, unknown>;
  const previewFrameCount = positiveInteger(previewFrame.count)
    ? previewFrame.count
    : positiveInteger(previewFrame.cols) && positiveInteger(previewFrame.rows)
      ? previewFrame.cols * previewFrame.rows
      : 0;
  if (previewFrameCount === 0 || value.editorPreview.idleFrame >= previewFrameCount) {
    throw new Error(`Boss '${value.id}' editor preview frame is outside its spritesheet`);
  }
  const immunities = value.effectImmunities;
  if (immunities !== undefined && (!Array.isArray(immunities) || !immunities.every(isEnemyEffectImmunity)
    || new Set(immunities).size !== immunities.length)) throw new Error(`Boss '${value.id}' has invalid effect immunities`);
  return value as unknown as BossDefinition;
}

const BOSS_DEFINITIONS = Object.fromEntries(BOSS_INPUTS.map((value) => {
  const boss = normalizeBoss(value);
  return [boss.id, boss];
})) as Readonly<Record<string, BossDefinition>>;

export function getBossDefinition(id: string): BossDefinition {
  const boss = BOSS_DEFINITIONS[id];
  if (!boss) throw new Error(`Unknown boss '${id}'`);
  return boss;
}

export function isBossId(id: string): boolean {
  return id in BOSS_DEFINITIONS;
}

export function getBossIds(): readonly string[] {
  return Object.keys(BOSS_DEFINITIONS).sort();
}

export function getBossEditorPreview(id: string): BossEditorPreview {
  const boss = getBossDefinition(id);
  const assetId = boss.editorPreview.assetId as AssetId;
  const asset = getAsset(assetId);
  const origin = 'render' in asset && Array.isArray(asset.render.origin) && asset.render.origin.length === 2
    ? asset.render.origin as unknown as readonly [number, number]
    : [0.5, 0.5] as const;
  return {
    assetId,
    textureKey: asset.runtime.textureKey,
    frame: boss.editorPreview.idleFrame,
    origin,
    scale: boss.visualScale,
  };
}

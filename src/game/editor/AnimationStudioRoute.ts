import type { WeaponAttackDirection } from '../content/weapons/types';

export type AnimationStudioSelection =
  | { readonly kind: 'character'; readonly characterId: string; readonly clipId?: string }
  | { readonly kind: 'shared'; readonly animationId: string }
  | { readonly kind: 'weapon-idle'; readonly weaponId: string }
  | { readonly kind: 'weapon-attack'; readonly weaponId: string; readonly direction: WeaponAttackDirection };

const DIRECTIONS = new Set<WeaponAttackDirection>(['right', 'left', 'up', 'down']);

export function parseAnimationStudioRoute(query: URLSearchParams): AnimationStudioSelection | undefined {
  const families = [query.has('character'), query.has('animation'), query.has('weapon')].filter(Boolean).length;
  if (families !== 1) return undefined;
  if (query.has('character')) {
    const characterId = query.get('character')?.trim();
    if (!characterId || query.has('slot') || query.has('direction')) return undefined;
    const clipId = query.get('clip')?.trim() || undefined;
    return { kind: 'character', characterId, ...(clipId ? { clipId } : {}) };
  }
  if (query.has('animation')) {
    const animationId = query.get('animation')?.trim();
    if (!animationId || query.has('slot') || query.has('direction')) return undefined;
    return { kind: 'shared', animationId };
  }
  const weaponId = query.get('weapon')?.trim();
  const slot = query.get('slot');
  if (!weaponId || slot === 'idle') return weaponId && slot === 'idle' ? { kind: 'weapon-idle', weaponId } : undefined;
  if (slot !== 'attack') return undefined;
  const direction = query.get('direction');
  if (!direction || !DIRECTIONS.has(direction as WeaponAttackDirection)) return undefined;
  return { kind: 'weapon-attack', weaponId, direction: direction as WeaponAttackDirection };
}

export function writeAnimationStudioRoute(current: URLSearchParams, selection: AnimationStudioSelection | undefined): URLSearchParams {
  const next = new URLSearchParams(current);
  next.set('studio', 'animations');
  for (const key of ['character', 'clip', 'animation', 'weapon', 'slot', 'direction']) next.delete(key);
  if (!selection) return next;
  if (selection.kind === 'character') {
    next.set('character', selection.characterId);
    if (selection.clipId) next.set('clip', selection.clipId);
  } else if (selection.kind === 'shared') {
    next.set('animation', selection.animationId);
  } else {
    next.set('weapon', selection.weaponId);
    next.set('slot', selection.kind === 'weapon-idle' ? 'idle' : 'attack');
    if (selection.kind === 'weapon-attack') next.set('direction', selection.direction);
  }
  return next;
}


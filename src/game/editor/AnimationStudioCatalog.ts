import type { AnimationPackageCatalog, AnimationPackageCatalogEntry } from '../content/animations/types';
import type { CharacterPackage } from '../content/characters/types';
import type { AuthoredWeaponDefinition, LayeredWeaponDefinition, WeaponAttackDirection } from '../content/weapons/types';

export type AnimationStudioRole = 'player' | 'enemy' | 'npc' | 'shared' | 'weapon';

export type AnimationStudioEntry =
  | {
      readonly kind: 'single-sheet';
      readonly role: 'player' | 'enemy' | 'npc';
      readonly characterId: string;
      readonly displayName: string;
      readonly visualSetId: string;
      readonly clipIds: readonly string[];
    }
  | {
      readonly kind: 'shared-package';
      readonly role: 'shared';
      readonly animationId: string;
      readonly displayName: string;
      readonly packagePath: string;
      readonly revision: string;
    }
  | {
      readonly kind: 'weapon-owned';
      readonly role: 'weapon';
      readonly weaponId: string;
      readonly displayName: string;
      readonly revision: string;
      readonly slot: 'idle';
    }
  | {
      readonly kind: 'weapon-owned';
      readonly role: 'weapon';
      readonly weaponId: string;
      readonly displayName: string;
      readonly revision: string;
      readonly slot: 'attack';
      readonly direction: WeaponAttackDirection;
    };

export type AnimationStudioAlias = {
  readonly kind: 'alias';
  readonly key: string;
  readonly weaponId: string;
  readonly displayName: string;
  readonly slot: 'idle' | 'attack';
  readonly direction?: WeaponAttackDirection;
  readonly targetKey?: string;
  readonly targetAnimationId?: string;
  readonly reason: 'shared-reference' | 'inherited' | 'missing-shared-reference';
};

export interface AnimationStudioTimingLock {
  readonly animationId: string;
  readonly consumers: readonly string[];
}

export interface AnimationStudioCatalog {
  readonly entries: readonly AnimationStudioEntry[];
  readonly aliases: readonly AnimationStudioAlias[];
  readonly timingLocks: readonly AnimationStudioTimingLock[];
}

export function animationStudioEntryKey(entry: AnimationStudioEntry): string {
  if (entry.kind === 'single-sheet') return `character:${entry.characterId}`;
  if (entry.kind === 'shared-package') return `shared:${entry.animationId}`;
  if (entry.slot === 'idle') return `weapon:${entry.weaponId}:idle`;
  return `weapon:${entry.weaponId}:attack:${entry.direction}`;
}

export function animationStudioAliasKey(alias: Pick<AnimationStudioAlias, 'weaponId' | 'slot' | 'direction'>): string {
  return alias.slot === 'idle'
    ? `weapon-alias:${alias.weaponId}:idle`
    : `weapon-alias:${alias.weaponId}:attack:${alias.direction}`;
}

function sharedById(packages: readonly AnimationPackageCatalogEntry[]): Map<string, AnimationPackageCatalogEntry> {
  return new Map(packages.map((entry) => [entry.animationId, entry]));
}

function isLayeredWeapon(value: AuthoredWeaponDefinition): value is LayeredWeaponDefinition {
  return value.version === 2;
}

function addWeaponAlias(
  aliases: AnimationStudioAlias[],
  weapon: LayeredWeaponDefinition & { readonly revision: string },
  slot: 'idle' | 'attack',
  direction: WeaponAttackDirection | undefined,
  targetKey: string | undefined,
  targetAnimationId: string | undefined,
  reason: AnimationStudioAlias['reason'],
): void {
  const alias = { kind: 'alias' as const, key: animationStudioAliasKey({ weaponId: weapon.weaponId, slot, direction }), weaponId: weapon.weaponId, displayName: weapon.displayName, slot, ...(direction ? { direction } : {}), ...(targetKey ? { targetKey } : {}), ...(targetAnimationId ? { targetAnimationId } : {}), reason };
  aliases.push(alias);
}

export function buildAnimationStudioCatalog(
  characterPackages: readonly CharacterPackage[],
  animationCatalog: AnimationPackageCatalog,
  weapons: readonly (AuthoredWeaponDefinition & { readonly revision: string })[],
): AnimationStudioCatalog {
  const entries: AnimationStudioEntry[] = characterPackages.map((entry) => ({
    kind: 'single-sheet',
    role: entry.character.kind,
    characterId: entry.character.characterId,
    displayName: entry.character.displayName,
    visualSetId: entry.visualSet.visualSetId,
    clipIds: Object.keys(entry.visualSet.clips),
  }));
  const sharedEntries = animationCatalog.packages.map((entry) => ({
    kind: 'shared-package' as const,
    role: 'shared' as const,
    animationId: entry.animationId,
    displayName: entry.displayName,
    packagePath: entry.packagePath,
    revision: entry.revision,
  }));
  entries.push(...sharedEntries);
  const shared = sharedById(animationCatalog.packages);
  const aliases: AnimationStudioAlias[] = [];
  const timingConsumers = new Map<string, string[]>();
  for (const candidate of weapons) {
    if (!isLayeredWeapon(candidate)) continue;
    const weapon = candidate;
    if (weapon.animations.idleAnimationId) {
      const target = shared.get(weapon.animations.idleAnimationId);
      addWeaponAlias(aliases, weapon, 'idle', undefined, target ? `shared:${target.animationId}` : undefined, weapon.animations.idleAnimationId, target ? 'shared-reference' : 'missing-shared-reference');
    } else {
      entries.push({ kind: 'weapon-owned', role: 'weapon', weaponId: weapon.weaponId, displayName: `${weapon.displayName} · Idle`, revision: weapon.revision, slot: 'idle' });
    }
    const directions: readonly WeaponAttackDirection[] = ['right', 'left', 'up', 'down'];
    for (const direction of directions) {
      const attack = weapon.directionalAttacks[direction];
      if (attack?.animationId && attack.attackTrack && ((attack.attackTrack.events?.length ?? 0) > 0 || attack.attackTrack.hitboxSpans.length > 0)) {
        const consumers = timingConsumers.get(attack.animationId) ?? [];
        consumers.push(`${weapon.displayName} · ${direction.toUpperCase()}`);
        timingConsumers.set(attack.animationId, consumers);
      }
      if (!attack) {
        const master = direction === 'left' ? 'right' : direction === 'up' ? 'down' : undefined;
        if (master) {
          const masterAttack = weapon.directionalAttacks[master];
          const targetKey = masterAttack?.animationId ? `shared:${masterAttack.animationId}` : masterAttack?.animation ? `weapon:${weapon.weaponId}:attack:${master}` : undefined;
          addWeaponAlias(aliases, weapon, 'attack', direction, targetKey, masterAttack?.animationId, masterAttack?.animationId ? 'shared-reference' : 'inherited');
        }
        continue;
      }
      if (attack.animationId) {
        const target = shared.get(attack.animationId);
        addWeaponAlias(aliases, weapon, 'attack', direction, target ? `shared:${target.animationId}` : undefined, attack.animationId, target ? 'shared-reference' : 'missing-shared-reference');
      } else {
        entries.push({ kind: 'weapon-owned', role: 'weapon', weaponId: weapon.weaponId, displayName: `${weapon.displayName} · Attack ${direction}`, revision: weapon.revision, slot: 'attack', direction });
      }
    }
  }
  return { entries, aliases, timingLocks: [...timingConsumers.entries()].map(([animationId, consumers]) => ({ animationId, consumers })) };
}

import type { JsonValue } from '../../content/scenes/types';
import { PLAYER_ABILITY_DEFINITIONS, type PlayerAbilityId } from '../player/PlayerAbilityDefinitions';
import type { PlayerAbilityController } from '../player/PlayerAbilityController';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import { controlLabel } from '../player/ControlLabels';

/** In key order (Space, then 1–4); each slot shows its key from the binding table. */
const ABILITIES = [
  { id: 'jump', name: 'Jump', model: 'jump' },
  { id: 'dodge', name: 'Dodge', model: 'dodge' },
  { id: 'stretch-lash', name: 'Lash', model: 'lash' },
  { id: 'squash-slam', name: 'Slam', model: 'slam' },
  { id: 'teleport', name: 'Teleport', model: 'teleport' },
] as const satisfies readonly { id: PlayerAbilityId; name: string; model: string }[];

/** Read-only ability status plus typed activation for the authored action bar. */
export class AbilityBarSurfacePort implements UiSurfacePort {
  private lastSignature = '';
  private lastModel: UiPresentationModel = {};
  private stopped = false;

  constructor(
    private readonly getAbilitySystem: () => PlayerAbilityController | undefined,
    private readonly canInteract: () => boolean,
    private readonly activateAbility: (abilityId: PlayerAbilityId) => void,
  ) {}

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'ability-bar' || this.stopped) return {};
    const system = this.getAbilitySystem();
    const interactive = this.canInteract();
    const entries = ABILITIES.flatMap(({ id, name, model }) => {
      const key = controlLabel(PLAYER_ABILITY_DEFINITIONS[id].action);
      const status = system?.status(id);
      const unlocked = status?.unlocked ?? false;
      const cooldownMs = status?.cooldownRemainingMs ?? 0;
      const label = !unlocked
        ? `${status?.earnedBy ?? PLAYER_ABILITY_DEFINITIONS[id].earnedBy}\n${name}`
        : cooldownMs > 0
          ? `${(Math.ceil(cooldownMs / 100) / 10).toFixed(1)}s\n${name}`
          : status?.insufficientEnergy
            ? `Need ${PLAYER_ABILITY_DEFINITIONS[id].energyCost}E\n${name}`
            : status?.busy || status?.actionLocked
              ? `Busy\n${name}`
              : `${key}\n${name}`;
      return [[`${model}Label`, label], [`${model}Disabled`, !interactive || !status?.canActivate]] as const;
    });
    const signature = JSON.stringify(entries);
    if (signature === this.lastSignature) return this.lastModel;
    this.lastSignature = signature;
    this.lastModel = Object.fromEntries(entries);
    return this.lastModel;
  }

  invoke(surfaceId: string, actionId: string, _payload?: JsonValue): void {
    if (this.stopped || surfaceId !== 'ability-bar' || !this.canInteract()) return;
    const ability = ABILITIES.find((entry) => entry.id === actionId);
    if (!ability || !this.getAbilitySystem()?.status(ability.id).canActivate) return;
    this.activateAbility(ability.id);
    this.lastSignature = '';
  }

  destroy(): void {
    this.stopped = true;
    this.lastModel = {};
    this.lastSignature = '';
  }
}

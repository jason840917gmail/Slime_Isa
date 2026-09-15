import Phaser from 'phaser';

import { gameState } from '../core/GameState';
import { isTileCollidable, type WorldTileId } from '../content/terrain/TileCatalog';
import type { PlayerAbilityId } from '../features/player/PlayerAbilityDefinitions';
import { PlayerAbilityPresentation } from '../features/player/PlayerAbilityPresentation';
import { PlayerAbilityService } from '../features/player/PlayerAbilityService';
import type { WorldVisual } from '../presentation/WorldVisual';
import {
  LegacyPlayerAbilityPresentation,
  type LegacyPlayerAbilityPresentationContext,
} from '../infrastructure/scenes/compatibility/LegacyPlayerAbilityPresentation';
import type { WorldDimensions } from '../world/WorldDimensions';

export type AbilityId = PlayerAbilityId;

export interface AbilitySystemContext extends LegacyPlayerAbilityPresentationContext {
  dimensions: WorldDimensions;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getPlayerVisual: () => WorldVisual;
  isActionLocked: () => boolean;
  setActionLocked: (locked: boolean) => void;
  getFacing: () => Phaser.Math.Vector2;
  playAnimation: (key: string) => void;
  getTerrainGrid: () => WorldTileId[][];
  getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
}

/**
 * Compatibility facade for current callers. Decisions and presentation leases
 * are player-feature objects; Phaser rendering lives in the temporary backend.
 */
export class AbilitySystem {
  private readonly decisions: PlayerAbilityService;
  private readonly presentation: PlayerAbilityPresentation;

  constructor(private readonly context: AbilitySystemContext) {
    this.decisions = new PlayerAbilityService({
      nowMs: () => context.scene.time.now,
      state: {
        getLevel: () => gameState.level,
        getEnergy: () => gameState.energy,
        isActionLocked: context.isActionLocked,
        setActionLocked: context.setActionLocked,
        spendEnergy: (amount) => gameState.useEnergy(amount),
      },
      terrain: {
        isBlocked: (x, y) => {
          const grid = context.getTerrainGrid();
          const tileX = Math.floor(x / context.dimensions.tileSize);
          const tileY = Math.floor(y / context.dimensions.tileSize);
          if (tileY < 0 || tileY >= grid.length || tileX < 0 || tileX >= (grid[0]?.length ?? 0)) return true;
          const tileId = grid[tileY]?.[tileX];
          return tileId !== undefined && isTileCollidable(tileId);
        },
      },
    });
    this.presentation = new PlayerAbilityPresentation(new LegacyPlayerAbilityPresentation(context));
  }

  unlockLevel(ability: AbilityId): number {
    return this.decisions.unlockLevel(ability);
  }

  isUnlocked(ability: AbilityId): boolean {
    return this.decisions.isUnlocked(ability);
  }

  isBusy(): boolean {
    return this.decisions.isBusy();
  }

  tryJump(direction: Phaser.Math.Vector2): boolean {
    return this.tryAbility('jump', direction);
  }

  tryTeleport(direction: Phaser.Math.Vector2): boolean {
    return this.tryAbility('teleport', direction);
  }

  trySquashSlam(): boolean {
    return this.tryAbility('squash-slam');
  }

  tryStretchLash(): boolean {
    return this.tryAbility('stretch-lash');
  }

  update(): void {}

  destroy(): void {
    this.presentation.dispose();
    this.decisions.cancel();
  }

  private tryAbility(abilityId: AbilityId, direction?: Phaser.Math.Vector2): boolean {
    const player = this.context.getPlayer();
    const facing = this.context.getFacing();
    const decision = this.decisions.tryBegin(abilityId, {
      position: { x: player.x, y: player.y },
      direction: direction ? { x: direction.x, y: direction.y } : { x: 0, y: 0 },
      facing: { x: facing.x, y: facing.y },
    });
    if (!decision.accepted) {
      this.presentation.notifyRejected(abilityId, decision.reason, decision.unlockLevel);
      return false;
    }
    try {
      if (this.presentation.present(decision.intent, (sequenceId) => {
        if (this.decisions.complete(sequenceId)) this.context.playAnimation('slime-idle');
      })) return true;
    } catch (error) {
      this.decisions.cancel();
      throw error;
    }
    this.decisions.cancel();
    return false;
  }
}

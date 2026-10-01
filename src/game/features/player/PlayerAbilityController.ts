import Phaser from 'phaser';

import { gameState } from '../../core/GameState';
import { storyProgress } from '../progression/StoryProgress';
import { isTileCollidable, type WorldTileId } from '../../content/terrain/TileCatalog';
import { PLAYER_ABILITY_DEFINITIONS, type PlayerAbilityId } from './PlayerAbilityDefinitions';
import { PlayerAbilityPresentation } from './PlayerAbilityPresentation';
import { PlayerAbilityService } from './PlayerAbilityService';
import type { WorldVisual } from '../../presentation/WorldVisual';
import {
  LegacyPlayerAbilityPresentation,
  type LegacyPlayerAbilityPresentationContext,
} from '../../infrastructure/scenes/compatibility/LegacyPlayerAbilityPresentation';
import type { WorldDimensions } from '../../world/WorldDimensions';

export interface PlayerAbilityStatus {
  readonly unlocked: boolean;
  /** How the ability is earned while it is locked ("Quest", "Boss"). */
  readonly earnedBy: string;
  readonly cooldownRemainingMs: number;
  readonly busy: boolean;
  readonly actionLocked: boolean;
  readonly insufficientEnergy: boolean;
  readonly canActivate: boolean;
}

export interface PlayerAbilityControllerContext extends LegacyPlayerAbilityPresentationContext {
  dimensions: WorldDimensions;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getPlayerVisual: () => WorldVisual;
  isActionLocked: () => boolean;
  setActionLocked: (locked: boolean) => void;
  getFacing: () => Phaser.Math.Vector2;
  playAnimation: (key: string) => void;
  getTerrainGrid: () => WorldTileId[][];
  getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
  /** Gameplay clock for cooldowns; defaults to the Phaser scene clock. */
  nowMs?: () => number;
}

/**
 * Compatibility facade for current callers. Decisions and presentation leases
 * are player-feature objects; Phaser rendering lives in the temporary backend.
 */
export class PlayerAbilityController {
  private readonly decisions: PlayerAbilityService;
  private readonly presentation: PlayerAbilityPresentation;

  constructor(private readonly context: PlayerAbilityControllerContext) {
    this.decisions = new PlayerAbilityService({
      nowMs: () => this.now(),
      state: {
        isLearned: (abilityId) => storyProgress.knowsAbility(abilityId),
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
        isOccupied: (x, y) => {
          // The slime's own body, moved to (x, y), against every solid object.
          const player = context.getPlayer();
          const body = player.body as Phaser.Physics.Arcade.Body | null;
          if (!body) return false;
          const centerX = x + (body.center.x - player.x);
          const centerY = y + (body.center.y - player.y);
          const hits = context.scene.physics.overlapRect(centerX - body.width / 2, centerY - body.height / 2, body.width, body.height, false, true);
          return hits.some((hit) => hit.enable);
        },
      },
    });
    this.presentation = new PlayerAbilityPresentation(new LegacyPlayerAbilityPresentation(context));
  }

  private now(): number {
    return this.context.nowMs?.() ?? this.context.scene.time.now;
  }

  isUnlocked(ability: PlayerAbilityId): boolean {
    return this.decisions.isUnlocked(ability);
  }

  isBusy(): boolean {
    return this.decisions.isBusy();
  }

  status(ability: PlayerAbilityId): PlayerAbilityStatus {
    const unlocked = this.decisions.isUnlocked(ability);
    const cooldownRemainingMs = Math.max(0, this.decisions.readyAt(ability) - this.now());
    const busy = this.decisions.isBusy();
    const actionLocked = this.context.isActionLocked();
    const insufficientEnergy = gameState.energy < PLAYER_ABILITY_DEFINITIONS[ability].energyCost;
    return {
      unlocked,
      earnedBy: PLAYER_ABILITY_DEFINITIONS[ability].earnedBy,
      cooldownRemainingMs,
      busy,
      actionLocked,
      insufficientEnergy,
      canActivate: unlocked && cooldownRemainingMs === 0 && !busy && !actionLocked && !insufficientEnergy,
    };
  }

  tryJump(direction: Phaser.Math.Vector2): boolean {
    return this.tryAbility('jump', direction);
  }

  /** Lands toward `direction`, at most `reach` px away (the pointer's distance) and the ability's range. */
  tryTeleport(direction: Readonly<{ x: number; y: number }>, reach?: number): boolean {
    return this.tryAbility('teleport', direction, reach);
  }

  trySquashSlam(): boolean {
    return this.tryAbility('squash-slam');
  }

  tryStretchLash(direction?: Readonly<{ x: number; y: number }>): boolean {
    return this.tryAbility('stretch-lash', direction);
  }

  /**
   * The dodge is learned and cools down like any ability, but the roll itself
   * is body motion: `roll` performs it once the ability rules allow.
   */
  tryDodge(roll: () => boolean): boolean {
    const rejection = this.decisions.tryInstant('dodge');
    if (rejection) {
      if (rejection !== 'cooldown') this.presentation.notifyRejected('dodge', rejection);
      return false;
    }
    return roll();
  }

  update(): void {}

  destroy(): void {
    this.presentation.dispose();
    this.decisions.cancel();
  }

  private tryAbility(abilityId: PlayerAbilityId, direction?: Readonly<{ x: number; y: number }>, reach?: number): boolean {
    const player = this.context.getPlayer();
    const facing = this.context.getFacing();
    const decision = this.decisions.tryBegin(abilityId, {
      position: { x: player.x, y: player.y },
      direction: direction ? { x: direction.x, y: direction.y } : { x: 0, y: 0 },
      facing: { x: facing.x, y: facing.y },
      ...(reach === undefined ? {} : { reach }),
    });
    if (!decision.accepted) {
      this.presentation.notifyRejected(abilityId, decision.reason);
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

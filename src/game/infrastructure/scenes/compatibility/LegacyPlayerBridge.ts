import type { DamageAreaRule } from '../../../features/combat/DamageReceiver';
import type { DamageRouter } from '../../../features/combat/DamageRouter';
import type { PlayerHealthService } from '../../../features/player/PlayerHealthService';
import type { PlayerRuntimePorts } from '../../../features/player/PlayerServicePorts';
import type { EnemyTargetService, EnemyTargetSnapshot } from '../../../features/scripts/EnemyScript';

export interface LegacyPlayerSensorSnapshot {
  readonly areaNodeId: string;
  readonly bounds: Readonly<{ x: number; y: number; width: number; height: number }>;
}

export class LegacyPlayerBridge implements EnemyTargetService {
  readonly damageAreaNodeId: string;
  private registered = false;
  private disposed = false;

  constructor(
    private readonly router: DamageRouter,
    readonly health: PlayerHealthService,
    readonly player: PlayerRuntimePorts,
    areaNodeId = 'legacy.player.damage-area',
  ) {
    this.damageAreaNodeId = areaNodeId;
  }

  enter(): void {
    if (this.disposed) throw new Error('LegacyPlayerBridge has been disposed.');
    if (this.registered) return;
    const rule: DamageAreaRule = { areaNodeId: this.damageAreaNodeId, priority: 0, damageMultiplier: 1 };
    this.router.registerArea(this.health, rule);
    this.registered = true;
  }

  postPhysicsSensorSnapshot(): LegacyPlayerSensorSnapshot {
    if (!this.registered) throw new Error('LegacyPlayerBridge must enter before synchronizing its sensor proxy.');
    return Object.freeze({ areaNodeId: this.damageAreaNodeId, bounds: Object.freeze({ ...this.player.getBodyBounds() }) });
  }

  getPrimaryTarget(_sourceNodeId: string): EnemyTargetSnapshot {
    return Object.freeze({
      position: Object.freeze({ ...this.player.getPosition() }),
      damageAreaNodeId: this.damageAreaNodeId,
      active: !this.health.isDead(),
      hostile: true,
    });
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    if (this.registered) this.router.unregisterArea(this.health, this.damageAreaNodeId);
    this.registered = false;
  }
}

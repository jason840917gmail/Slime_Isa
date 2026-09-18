import type { JsonValue } from '../../content/scenes/types';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

type ModelListener = (model: UiPresentationModel) => void;

/** Read-only adapter from progression state into the authored HUD scene. */
export class HudSurfacePort implements UiSurfacePort {
  private readonly listeners = new Set<ModelListener>();
  private stopped = false;

  constructor() {
    gameEvents.on('coins.changed', this.publish, this);
    gameEvents.on('hp.changed', this.publish, this);
    gameEvents.on('xp.changed', this.publish, this);
    gameEvents.on('energy.changed', this.publish, this);
    gameEvents.on('level.up', this.publish, this);
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'hud') return {};
    const xpMax = gameState.xpToNextLevel;
    return {
      levelLabel: `Level ${gameState.level}`,
      coinsLabel: `Coins ${formatHudCount(gameState.coins)}`,
      hp: gameState.hp,
      maxHp: gameState.maxHp,
      xp: xpMax === null ? 1 : gameState.currentXp,
      xpMax: xpMax ?? 1,
      energy: gameState.energy,
      maxEnergy: gameState.maxEnergy,
    } satisfies Readonly<Record<string, JsonValue>>;
  }

  subscribe(surfaceId: string, listener: ModelListener): () => void {
    if (surfaceId !== 'hud' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(): void {
    // The HUD is intentionally read-only. Domain mutations never originate here.
  }

  destroy(): void {
    if (this.stopped) return;
    this.stopped = true;
    gameEvents.off('coins.changed', this.publish, this);
    gameEvents.off('hp.changed', this.publish, this);
    gameEvents.off('xp.changed', this.publish, this);
    gameEvents.off('energy.changed', this.publish, this);
    gameEvents.off('level.up', this.publish, this);
    this.listeners.clear();
  }

  private readonly publish = (): void => {
    const model = this.snapshot('hud');
    for (const listener of this.listeners) listener(model);
  };
}

function formatHudCount(value: number): string {
  const count = Math.max(0, Math.floor(value));
  if (count < 10_000) return count.toLocaleString('en-US');
  if (count < 1_000_000) return `${Math.min(999.9, count / 1_000).toFixed(1)}k`;
  if (count < 1_000_000_000) return `${Math.min(999.9, count / 1_000_000).toFixed(1)}m`;
  return '999m+';
}

import type Phaser from 'phaser';

import type { JsonValue } from '../../content/scenes/types';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import { projectWorldToScreen } from './projectWorldToScreen';

const BAR_WIDTH = 56;
const BAR_HEIGHT = 8;
const SHOW_MS = 1800;

/** Projects the short lived player health meter into the authored screen layer. */
export class PlayerHealthSurfacePort implements UiSurfacePort {
  private visibleUntilMs = 0;
  private lastSignature = '';
  private lastModel: UiPresentationModel = {};
  private stopped = false;

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly getPlayer: () => Phaser.Physics.Arcade.Sprite | undefined,
  ) {
    gameEvents.on('hp.changed', this.flash, this);
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'health-bar' || this.stopped) return {};
    const player = this.getPlayer();
    const camera = this.scene.cameras.main;
    const visible = Boolean(player?.active && !gameState.isDead() && this.scene.time.now < this.visibleUntilMs);
    const screen = player && visible
      ? projectWorldToScreen(camera, player.x, player.y - 48)
      : undefined;
    const left = Math.round((screen?.x ?? 0) - BAR_WIDTH / 2);
    const top = Math.round((screen?.y ?? 0) - BAR_HEIGHT / 2);
    const model = {
      hp: gameState.hp,
      maxHp: gameState.maxHp,
      tone: gameState.hp / Math.max(1, gameState.maxHp) <= 0.25 ? 'danger'
        : gameState.hp / Math.max(1, gameState.maxHp) <= 0.5 ? 'warning' : 'accent',
      visible,
      offsetMin: [left, top],
      offsetMax: [left + BAR_WIDTH, top + BAR_HEIGHT],
    } satisfies Readonly<Record<string, JsonValue>>;
    const signature = JSON.stringify(model);
    if (signature === this.lastSignature) return this.lastModel;
    this.lastSignature = signature;
    this.lastModel = model;
    return model;
  }

  invoke(): void {}

  flash(): void {
    if (!this.stopped) this.visibleUntilMs = this.scene.time.now + SHOW_MS;
  }

  destroy(): void {
    if (this.stopped) return;
    this.stopped = true;
    gameEvents.off('hp.changed', this.flash, this);
    this.lastModel = {};
  }
}

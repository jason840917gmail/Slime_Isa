import Phaser from 'phaser';

import { getObjectArchetype } from '../../content/objects/ObjectCatalog';
import type { ChestInitialContent } from '../../content/objects/ObjectInitialState';
import type { Inventory } from '../../systems/Inventory';
import type { InteractionProvider, InteractionRouter } from '../interaction/InteractionRouter';
import type { WorldProgress } from '../progression/WorldProgress';
import type { BuiltObjectRegistration } from '../world/MapBuilder';
import { ChestInventoryPanel } from '../../ui/ChestInventoryPanel';
import type { ModalStack } from '../../ui/ModalStack';
import type { FloatingTextColor } from '../../ui/FloatingText';
import type { InventoryWorldTransaction } from '../progression/InventoryWorldTransaction';

interface ChestRecord {
  readonly instanceId: string;
  readonly image: Phaser.GameObjects.Image;
}

export interface ChestControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly inventory: Inventory;
  readonly progress: WorldProgress;
  readonly transaction: InventoryWorldTransaction;
  readonly router: InteractionRouter;
  readonly modalStack: ModalStack;
  readonly getPlayer: () => Phaser.Physics.Arcade.Sprite;
  readonly isLocked: (instanceId: string) => boolean;
  readonly onPausedChange: (paused: boolean) => void;
  readonly showMessage: (x: number, y: number, message: string, color?: FloatingTextColor, important?: boolean) => void;
}

export class ChestController implements InteractionProvider {
  private readonly records = new Map<string, ChestRecord>();
  private readonly panel: ChestInventoryPanel;
  private readonly unregisterInteraction: () => void;

  constructor(private readonly ctx: ChestControllerContext) {
    this.panel = new ChestInventoryPanel({
      scene: ctx.scene,
      modalStack: ctx.modalStack,
      onPausedChange: ctx.onPausedChange,
      getContents: (instanceId) => ctx.progress.chestState(ctx.mapId, instanceId)?.remaining ?? {},
      transferStack: (instanceId, itemId) => this.transferStack(instanceId, itemId),
      onClosed: (instanceId) => this.syncFrame(instanceId),
    });
    this.unregisterInteraction = ctx.router.register('chests', this);
  }

  register(registration: BuiltObjectRegistration): void {
    if (getObjectArchetype(registration.objectId as Parameters<typeof getObjectArchetype>[0]).chest !== true) return;
    const contents = Array.isArray(registration.initialState?.contents)
      ? registration.initialState.contents as readonly ChestInitialContent[]
      : [];
    const totals: Record<string, number> = {};
    for (const entry of contents) totals[entry.itemId] = (totals[entry.itemId] ?? 0) + entry.quantity;
    this.ctx.progress.ensureChestInitialized(this.ctx.mapId, registration.instanceId, totals);
    this.records.set(registration.instanceId, { instanceId: registration.instanceId, image: registration.image });
    this.syncFrame(registration.instanceId);
  }

  getCandidate() {
    const player = this.ctx.getPlayer();
    let nearest: ChestRecord | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const record of this.records.values()) {
      const distance = Phaser.Math.Distance.Between(player.x, player.y, record.image.x, record.image.y);
      if (distance <= 112 && distance < nearestDistance) {
        nearest = record;
        nearestDistance = distance;
      }
    }
    if (!nearest) return undefined;
    const state = this.ctx.progress.chestState(this.ctx.mapId, nearest.instanceId);
    const empty = !state || Object.keys(state.remaining).length === 0;
    const locked = !empty && this.ctx.isLocked(nearest.instanceId);
    return {
      id: `chests:${nearest.instanceId}`,
      prompt: locked ? '[F] Chest locked by Fatty One Eye' : empty ? '[F] Inspect empty chest' : '[F] Open chest',
      priority: 80,
      execute: () => {
        if (locked) {
          this.ctx.showMessage(nearest!.image.x, nearest!.image.y - 48, 'Fatty One Eye is guarding this chest!', 'white', true);
          return true;
        }
        nearest!.image.setFrame(1);
        this.panel.open(nearest!.instanceId);
        return true;
      },
    };
  }

  destroy(): void {
    this.unregisterInteraction();
    this.panel.destroy();
    this.records.clear();
  }

  private transferStack(instanceId: string, itemId: string): number {
    const moved = this.ctx.transaction.transferChestStack(this.ctx.mapId, instanceId, itemId);
    if (moved <= 0) return 0;
    this.syncFrame(instanceId);
    return moved;
  }

  private syncFrame(instanceId: string): void {
    const record = this.records.get(instanceId);
    if (!record) return;
    const remaining = this.ctx.progress.chestState(this.ctx.mapId, instanceId)?.remaining ?? {};
    record.image.setFrame(Object.keys(remaining).length === 0 ? 1 : 0);
  }
}

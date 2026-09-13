import Phaser from 'phaser';

import { itemRegistry } from '../systems/Inventory';
import { addUiSkin } from '../presentation/UiSkin';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { ModalStack, type ModalHandle } from './ModalStack';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export interface ChestInventoryPanelContext {
  readonly scene: Phaser.Scene;
  readonly modalStack: ModalStack;
  readonly onPausedChange: (paused: boolean) => void;
  readonly getContents: (instanceId: string) => Readonly<Record<string, number>>;
  readonly transferStack: (instanceId: string, itemId: string) => number;
  readonly onClosed: (instanceId: string) => void;
}

/** Inventory-skinned chest surface: inspect with left click, transfer with right click. */
export class ChestInventoryPanel {
  private readonly modalHandle: ModalHandle;
  private container?: Phaser.GameObjects.Container;
  private instanceId?: string;
  private selectedItemId?: string;
  private status = 'Left-click to inspect · Right-click to take a stack';

  constructor(private readonly ctx: ChestInventoryPanelContext) {
    this.modalHandle = ctx.modalStack.register('chest-inventory', {
      isOpen: () => this.isOpen(),
      close: () => this.close(),
    });
    ctx.scene.game.canvas.addEventListener('contextmenu', this.preventContextMenu);
  }

  isOpen(): boolean {
    return Boolean(this.container);
  }

  open(instanceId: string): void {
    if (this.container) this.close();
    this.instanceId = instanceId;
    this.selectedItemId = Object.keys(this.ctx.getContents(instanceId))[0];
    this.status = 'Left-click to inspect · Right-click to take a stack';
    this.build(true);
    this.ctx.onPausedChange(true);
    this.modalHandle.open();
  }

  close(): void {
    const instanceId = this.instanceId;
    this.container?.destroy();
    this.container = undefined;
    this.instanceId = undefined;
    this.selectedItemId = undefined;
    this.modalHandle.close();
    this.ctx.onPausedChange(false);
    if (instanceId) this.ctx.onClosed(instanceId);
  }

  destroy(): void {
    if (this.container) this.close();
    this.modalHandle.unregister();
    this.ctx.scene.game.canvas.removeEventListener('contextmenu', this.preventContextMenu);
  }

  private build(animate: boolean): void {
    const instanceId = this.instanceId;
    if (!instanceId) return;
    const scene = this.ctx.scene;
    const camera = scene.cameras.main;
    const panelW = Math.max(620, Math.min(camera.width - 32, 920));
    const panelH = Math.max(410, Math.min(camera.height - 32, 620));
    const container = scene.add.container(camera.width / 2, camera.height / 2)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(92));
    this.container = container;
    if (!addUiSkin(scene, container, 'ui.backplate.inventory', { x: 0, y: 0, width: panelW, height: panelH })) {
      container.add(scene.add.rectangle(0, 0, panelW, panelH, 0x101a31, 0.98).setStrokeStyle(2, 0x527565));
    }

    const left = -panelW / 2 + 130;
    const top = -panelH / 2 + 116;
    const detailX = panelW / 2 - 300;
    container.add(scene.add.text(left, -panelH / 2 + 40, 'Chest', {
      fontFamily: FONT, fontSize: '22px', fontStyle: 'bold', color: '#ffe09a', stroke: '#17251c', strokeThickness: 4,
    }));
    container.add(scene.add.text(panelW / 2 - 120, -panelH / 2 + 44, 'Esc to close', {
      fontFamily: FONT, fontSize: '12px', color: '#9ac7ad',
    }).setOrigin(1, 0));

    const entries = Object.entries(this.ctx.getContents(instanceId)).filter(([, amount]) => amount > 0);
    entries.forEach(([itemId, amount], index) => {
      const col = index % 5;
      const row = Math.floor(index / 5);
      const x = left + col * 62;
      const y = top + row * 62;
      const selected = itemId === this.selectedItemId;
      const slot = scene.add.rectangle(x, y, 52, 52, selected ? 0x315c57 : 0x182b46, 0.96)
        .setStrokeStyle(selected ? 3 : 1, selected ? 0xffdc78 : 0x527565)
        .setInteractive({ useHandCursor: true });
      slot.on('pointerdown', (pointer: Phaser.Input.Pointer) => {
        if (pointer.rightButtonDown()) this.transfer(itemId);
        else {
          this.selectedItemId = itemId;
          this.refresh();
        }
      });
      container.add(slot);
      const item = itemRegistry.get(itemId);
      if (item) container.add(scene.add.image(x, y, item.icon, item.iconFrame).setDisplaySize(36, 36));
      container.add(scene.add.text(x + 22, y + 22, `×${amount}`, {
        fontFamily: FONT, fontSize: '11px', color: '#ffe09a', stroke: '#101a31', strokeThickness: 3,
      }).setOrigin(1, 1));
    });
    if (entries.length === 0) {
      container.add(scene.add.text(left, top, 'The chest is empty.', { fontFamily: FONT, fontSize: '16px', color: '#9ac7ad' }).setOrigin(0, 0.5));
    }

    this.renderDetails(detailX, top - 26, 210);
    container.add(scene.add.text(left, panelH / 2 - 78, this.status, {
      fontFamily: FONT, fontSize: '12px', color: '#c7e8d6', wordWrap: { width: panelW - 260 },
    }).setOrigin(0, 1));
    if (animate) scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, scale: { from: 0.97, to: 1 }, duration: 150, ease: 'Cubic.Out' });
  }

  private renderDetails(x: number, y: number, width: number): void {
    if (!this.container) return;
    const item = this.selectedItemId ? itemRegistry.get(this.selectedItemId) : undefined;
    if (!item) {
      this.container.add(this.ctx.scene.add.text(x, y, 'Select an item', { fontFamily: FONT, fontSize: '15px', color: '#9ac7ad' }));
      return;
    }
    const scene = this.ctx.scene;
    this.container.add(scene.add.image(x + 28, y + 28, item.icon, item.iconFrame).setDisplaySize(46, 46));
    this.container.add(scene.add.text(x + 58, y + 7, item.name, {
      fontFamily: FONT, fontSize: '17px', fontStyle: 'bold', color: '#f5f7ff', wordWrap: { width: width - 58 },
    }));
    this.container.add(scene.add.text(x + 58, y + 35, item.category.toUpperCase(), { fontFamily: FONT, fontSize: '10px', color: '#ffe09a' }));
    this.container.add(scene.add.text(x, y + 82, item.description, {
      fontFamily: FONT, fontSize: '12px', color: '#c7e8d6', wordWrap: { width },
    }));
    this.container.add(scene.add.text(x, y + 166, 'Right-click this slot to transfer as much of the stack as your inventory can hold.', {
      fontFamily: FONT, fontSize: '11px', color: '#8fbba3', wordWrap: { width },
    }));
  }

  private transfer(itemId: string): void {
    if (!this.instanceId) return;
    const moved = this.ctx.transferStack(this.instanceId, itemId);
    this.status = moved > 0 ? `Moved ${moved} × ${itemRegistry.get(itemId)?.name ?? itemId}` : 'No inventory space for that item.';
    if ((this.ctx.getContents(this.instanceId)[itemId] ?? 0) <= 0) {
      this.selectedItemId = Object.keys(this.ctx.getContents(this.instanceId))[0];
    }
    this.refresh();
  }

  private refresh(): void {
    if (!this.container) return;
    this.container.destroy();
    this.container = undefined;
    this.build(false);
  }

  private readonly preventContextMenu = (event: MouseEvent): void => {
    if (this.isOpen()) event.preventDefault();
  };
}

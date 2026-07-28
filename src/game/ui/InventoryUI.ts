import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { playerInventory, itemRegistry } from '../systems/Inventory';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';
const COLS = 6;
const CELL = 52;
const GAP = 6;

export interface InventoryUIContext {
  scene: Phaser.Scene;
  onPausedChange: (paused: boolean) => void;
  onUseItem: (itemId: string) => void;
}

export class InventoryUI {
  private ctx: InventoryUIContext;
  private container?: Phaser.GameObjects.Container;
  private escKey?: Phaser.Input.Keyboard.Key;
  private selectedItemId?: string;
  private clickRegions: Array<{ x: number; y: number; width: number; height: number; onClick: () => void }> = [];

  constructor(ctx: InventoryUIContext) {
    this.ctx = ctx;
    gameEvents.on('inventory.changed', this.refresh, this);

    const kb = ctx.scene.input.keyboard;
    if (kb) {
      this.escKey = kb.addKey(Phaser.Input.Keyboard.KeyCodes.ESC);
      this.escKey.on('down', () => {
        if (this.container) this.close();
      });
    }
    ctx.scene.input.on('pointerdown', this.handlePointerDown, this);
  }

  isOpen(): boolean {
    return !!this.container;
  }

  toggle(): void {
    if (this.container) this.close();
    else this.open();
  }

  private open(): void {
    this.ensureSelectedItem();
    this.build(true);
    this.ctx.onPausedChange(true);
  }

  private refresh = (): void => {
    if (!this.container) return;
    this.ensureSelectedItem();
    this.container.destroy();
    this.container = undefined;
    this.build(false);
  };

  private build(animate: boolean): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const panelW = 700;
    const panelH = 360;
    const container = scene.add.container(cam.width / 2, cam.height / 2).setScrollFactor(0).setDepth(resolveScreenUiDepth(90));
    this.container = container;
    this.clickRegions = [];

    container.add(scene.add.rectangle(0, 0, cam.width, cam.height, 0x000000, 0.5).setOrigin(0.5));

    const bg = scene.add.graphics();
    bg.fillStyle(0x101a31, 0.97);
    bg.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 12);
    bg.lineStyle(2, 0x3b5c78, 0.8);
    bg.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 12);
    container.add(bg);

    container.add(scene.add.text(-panelW / 2 + 18, -panelH / 2 + 18, 'Inventory', {
      fontFamily: FONT,
      fontSize: '18px',
      color: '#d7f6e9',
    }).setOrigin(0, 0));

    container.add(scene.add.text(panelW / 2 - 18, -panelH / 2 + 20, 'Tab / Esc to close', {
      fontFamily: FONT,
      fontSize: '11px',
      color: '#88c899',
    }).setOrigin(1, 0));

    this.renderSlots(-panelW / 2 + 24, -panelH / 2 + 58);
    this.renderDetails(95, -panelH / 2 + 58, 235, panelH - 86);

    if (animate) {
      scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, duration: 140 });
    }
  }

  private renderSlots(startX: number, startY: number): void {
    const scene = this.ctx.scene;
    if (!this.container) return;

    const slots = playerInventory.getSlots();

    for (let i = 0; i < playerInventory.maxSlots(); i += 1) {
      const col = i % COLS;
      const row = Math.floor(i / COLS);
      const x = startX + col * (CELL + GAP) + CELL / 2;
      const y = startY + row * (CELL + GAP) + CELL / 2;
      const slot = slots[i];
      const selected = !!slot && slot.itemId === this.selectedItemId;

      const slotBg = scene.add
        .rectangle(x, y, CELL, CELL, selected ? 0x244e56 : 0x182b46, 0.95)
        .setStrokeStyle(selected ? 3 : 1, selected ? 0xffdf8a : 0x3b5c78, selected ? 1 : 0.7);
      this.container.add(slotBg);

      if (!slot) continue;

      const def = itemRegistry.get(slot.itemId);
      if (!def) continue;

      this.container.add(scene.add.image(x, y, def.icon).setDisplaySize(34, 34));

      if (slot.count > 1) {
        this.container.add(scene.add.text(x + CELL / 2 - 4, y + CELL / 2 - 4, `${slot.count}`, {
          fontFamily: FONT,
          fontSize: '11px',
          color: '#ffd277',
          stroke: '#0b1020',
          strokeThickness: 3,
        }).setOrigin(1, 1));
      }

      this.addClickRegion(x - CELL / 2, y - CELL / 2, CELL, CELL, () => {
        this.selectedItemId = slot.itemId;
        this.refresh();
      });
    }
  }

  private renderDetails(x: number, y: number, width: number, height: number): void {
    const scene = this.ctx.scene;
    if (!this.container) return;

    const detailBg = scene.add.graphics();
    detailBg.fillStyle(0x172543, 0.96);
    detailBg.fillRoundedRect(x, y, width, height, 10);
    detailBg.lineStyle(1.5, 0x3b5c78, 0.8);
    detailBg.strokeRoundedRect(x, y, width, height, 10);
    this.container.add(detailBg);

    if (!this.selectedItemId) {
      this.container.add(scene.add.text(x + width / 2, y + height / 2, 'Select an item', {
        fontFamily: FONT,
        fontSize: '14px',
        color: '#88c899',
      }).setOrigin(0.5));
      return;
    }

    const def = itemRegistry.get(this.selectedItemId);
    const count = playerInventory.count(this.selectedItemId);
    if (!def || count <= 0) return;

    this.container.add(scene.add.image(x + 30, y + 32, def.icon).setDisplaySize(38, 38));
    this.container.add(scene.add.text(x + 58, y + 16, def.name, {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#f5f7ff',
      stroke: '#0b1020',
      strokeThickness: 3,
    }).setOrigin(0, 0));
    this.container.add(scene.add.text(x + 58, y + 42, `${def.category}  Â·  x${count}`, {
      fontFamily: FONT,
      fontSize: '11px',
      color: '#ffd277',
    }).setOrigin(0, 0));
    this.container.add(scene.add.text(x + 16, y + 82, def.description, {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#d7f6e9',
      wordWrap: { width: width - 32 },
    }).setOrigin(0, 0));

    if (def.use) {
      const effects = [
        def.use.healHp ? `Heal HP +${def.use.healHp}` : '',
        def.use.healEnergy ? `Energy +${def.use.healEnergy}` : '',
        def.use.cureStatus?.length ? `Cures ${def.use.cureStatus.join(', ')}` : '',
      ].filter(Boolean).join('  Â·  ');
      this.container.add(scene.add.text(x + 16, y + 148, effects, {
        fontFamily: FONT,
        fontSize: '11px',
        color: '#86f0c3',
        wordWrap: { width: width - 32 },
      }).setOrigin(0, 0));
    }

    if (def.use) {
      this.addButton(x + 16, y + height - 52, 92, 34, 'Use', 0x86f0c3, () => {
        if (!this.selectedItemId) return;
        this.ctx.onUseItem(this.selectedItemId);
      });
    } else {
      this.addButton(x + 16, y + height - 52, 92, 34, 'No Use', 0x253552, undefined);
    }

    this.addButton(x + 124, y + height - 52, 92, 34, 'Delete 1', 0xff8f7a, () => {
      if (!this.selectedItemId) return;
      playerInventory.remove(this.selectedItemId, 1);
      if (playerInventory.count(this.selectedItemId) <= 0) this.selectedItemId = undefined;
    });
  }

  private addButton(x: number, y: number, width: number, height: number, label: string, color: number, onClick?: () => void): void {
    const scene = this.ctx.scene;
    if (!this.container) return;

    const enabled = !!onClick;
    const bg = scene.add
      .rectangle(x + width / 2, y + height / 2, width, height, color, enabled ? 1 : 0.55)
      .setStrokeStyle(1.5, enabled ? 0xe7fff5 : 0x4a6075, enabled ? 0.9 : 0.45);
    this.container.add(bg);

    this.container.add(scene.add.text(x + width / 2, y + height / 2, label, {
      fontFamily: FONT,
      fontSize: '12px',
      color: enabled ? '#101a31' : '#809080',
    }).setOrigin(0.5));

    if (!enabled) return;
    this.addClickRegion(x, y, width, height, onClick);
  }

  private addClickRegion(x: number, y: number, width: number, height: number, onClick: () => void): void {
    this.clickRegions.push({ x, y, width, height, onClick });
  }

  private handlePointerDown = (pointer: Phaser.Input.Pointer): void => {
    if (!this.container) return;
    const localX = pointer.x - this.container.x;
    const localY = pointer.y - this.container.y;

    for (let i = this.clickRegions.length - 1; i >= 0; i -= 1) {
      const r = this.clickRegions[i];
      if (localX >= r.x && localX <= r.x + r.width && localY >= r.y && localY <= r.y + r.height) {
        r.onClick();
        return;
      }
    }
  };

  private ensureSelectedItem(): void {
    if (this.selectedItemId && playerInventory.count(this.selectedItemId) > 0) return;
    this.selectedItemId = playerInventory.getSlots()[0]?.itemId;
  }

  private close(): void {
    if (!this.container) return;
    this.container.destroy();
    this.container = undefined;
    this.ctx.onPausedChange(false);
  }

  destroy(): void {
    gameEvents.off('inventory.changed', this.refresh, this);
    this.escKey?.off('down');
    this.ctx.scene.input.off('pointerdown', this.handlePointerDown, this);
    this.container?.destroy();
  }
}

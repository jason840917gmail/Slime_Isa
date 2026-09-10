import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { playerInventory, itemRegistry } from '../systems/Inventory';
import { playerWeaponLoadout } from '../systems/WeaponLoadout';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { addUiSkin } from '../presentation/UiSkin';
import { createWeaponThumbnail } from './WeaponThumbnail';
import { ModalStack, type ModalHandle } from './ModalStack';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';
const COLS = 6;
const CELL = 52;
const GAP = 6;
const PANEL_INSET = 16;
const MIN_CELL = 36;
const PANEL_BORDER_PADDING = {
  top: 150,
  right:140,
  bottom: 150,
  left: 170,
} as const;
const DETAIL_REGION_WIDTH_RATIO = 0.25;

export interface InventoryUIContext {
  scene: Phaser.Scene;
  modalStack: ModalStack;
  onPausedChange: (paused: boolean) => void;
  onUseItem: (itemId: string) => void;
  onEquipWeapon: (weaponId: string) => void;
  onAssignWeapon: (weaponId: string, slotIndex: number) => void;
  canDropItem: (itemId: string) => boolean;
  onDropItem: (slotIndex: number, quantity: number) => boolean;
}

export class InventoryUI {
  private ctx: InventoryUIContext;
  private readonly modalHandle: ModalHandle;
  private container?: Phaser.GameObjects.Container;
  private selectedItemId?: string;
  private selectedSlotIndex?: number;
  private removeQuantity = 1;
  private clickRegions: Array<{ x: number; y: number; width: number; height: number; onClick: () => void }> = [];

  constructor(ctx: InventoryUIContext) {
    this.ctx = ctx;
    this.modalHandle = ctx.modalStack.register('inventory', {
      isOpen: () => this.isOpen(),
      close: () => this.close(),
    });
    gameEvents.on('inventory.changed', this.refresh, this);
    gameEvents.on('weapon.loadout.changed', this.refresh, this);
    gameEvents.on('weapon.equipped', this.refresh, this);

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
    this.modalHandle.open();
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
    const slotCount = playerInventory.maxSlots();
    const rowCount = Math.max(1, Math.ceil(slotCount / COLS));
    const panelW = Math.max(320, cam.width - PANEL_INSET * 2);
    const panelH = Math.max(360, cam.height - PANEL_INSET * 2);
    const contentTop = -panelH / 2 + PANEL_BORDER_PADDING.top;
    const contentHeight = Math.max(1, panelH - PANEL_BORDER_PADDING.top - PANEL_BORDER_PADDING.bottom);
    const contentRight = panelW / 2 - PANEL_BORDER_PADDING.right;
    const availableGridHeight = contentHeight;
    const cell = Math.min(
      CELL,
      Math.max(MIN_CELL, Math.floor((availableGridHeight - (rowCount - 1) * GAP) / rowCount)),
    );
    const slotsX = -panelW / 2 + PANEL_BORDER_PADDING.left;
    const detailWidth = Math.max(235, panelW * DETAIL_REGION_WIDTH_RATIO);
    const detailX = contentRight - detailWidth;
    const detailHeight = contentHeight;
    const container = scene.add.container(cam.width / 2, cam.height / 2).setScrollFactor(0).setDepth(resolveScreenUiDepth(90));
    this.container = container;
    this.clickRegions = [];

    //container.add(scene.add.rectangle(0, 0, cam.width, cam.height, 0x000000, 0.5).setOrigin(0.5));

    const skin = addUiSkin(scene, container, 'ui.backplate.inventory', {
      x: 0,
      y: 0,
      width: panelW,
      height: panelH,
    });
    if (!skin) {
      const bg = scene.add.graphics();
      bg.fillStyle(0x101a31, 0.97);
      bg.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 12);
      bg.lineStyle(2, 0x3b5c78, 0.8);
      bg.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 12);
      container.add(bg);
    }

    container.add(scene.add.text(slotsX, -panelH / 2 + 18, 'Inventory', {
      fontFamily: FONT,
      fontSize: '18px',
      color: '#d7f6e9',
    }).setOrigin(0, 0));

    container.add(scene.add.text(contentRight, -panelH / 2 + 20, 'Tab / Esc to close', {
      fontFamily: FONT,
      fontSize: '11px',
      color: '#88c899',
    }).setOrigin(1, 0));

    this.renderSlots(slotsX, contentTop, cell);
    this.renderDetails(detailX, contentTop, detailWidth, detailHeight);

    if (animate) {
      scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, duration: 140 });
    }
  }

  private renderSlots(startX: number, startY: number, cell: number): void {
    const scene = this.ctx.scene;
    if (!this.container) return;

    const slots = playerInventory.getSlots();
    const iconSize = Math.min(34, cell - 12);

    for (let i = 0; i < playerInventory.maxSlots(); i += 1) {
      const col = i % COLS;
      const row = Math.floor(i / COLS);
      const x = startX + col * (cell + GAP) + cell / 2;
      const y = startY + row * (cell + GAP) + cell / 2;
      const slot = slots[i];
      const selected = !!slot && i === this.selectedSlotIndex;

      const slotBg = scene.add
        .rectangle(x, y, cell, cell, selected ? 0x244e56 : 0x182b46, 0.95)
        .setStrokeStyle(selected ? 3 : 1, selected ? 0xffdf8a : 0x3b5c78, selected ? 1 : 0.7);
      this.container.add(slotBg);

      if (!slot) continue;

      const def = itemRegistry.get(slot.itemId);
      if (!def) continue;

      const thumbnail = def.equipment
        ? createWeaponThumbnail(scene, def.equipment.weaponId, { x, y, size: iconSize })
        : undefined;
      if (thumbnail) this.container.add(thumbnail);
      else if (!def.equipment) this.container.add(scene.add.image(x, y, def.icon, def.iconFrame).setDisplaySize(iconSize, iconSize));

      if (slot.count > 1) {
        this.container.add(scene.add.text(x + cell / 2 - 4, y + cell / 2 - 4, `${slot.count}`, {
          fontFamily: FONT,
          fontSize: '11px',
          color: '#ffd277',
          stroke: '#0b1020',
          strokeThickness: 3,
        }).setOrigin(1, 1));
      }

      this.addClickRegion(x - cell / 2, y - cell / 2, cell, cell, () => {
        this.selectedItemId = slot.itemId;
        this.selectedSlotIndex = i;
        this.removeQuantity = 1;
        this.refresh();
      });
    }
  }

  private renderDetails(x: number, y: number, width: number, height: number): void {
    const scene = this.ctx.scene;
    if (!this.container) return;


    if (!this.selectedItemId) {
      this.container.add(scene.add.text(x + width / 2, y + height / 2, 'Select an item', {
        fontFamily: FONT,
        fontSize: '14px',
        color: '#88c899',
      }).setOrigin(0.5));
      return;
    }

    const selectedSlot = this.selectedSlotIndex === undefined
      ? undefined
      : playerInventory.getSlots()[this.selectedSlotIndex];
    const def = itemRegistry.get(this.selectedItemId);
    const count = selectedSlot?.itemId === this.selectedItemId ? selectedSlot.count : 0;
    if (!def || count <= 0) return;
    this.removeQuantity = Phaser.Math.Clamp(this.removeQuantity, 1, count);

    const thumbnail = def.equipment
      ? createWeaponThumbnail(scene, def.equipment.weaponId, { x: x + 30, y: y + 32, size: 38 })
      : undefined;
    if (thumbnail) this.container.add(thumbnail);
    else if (!def.equipment) this.container.add(scene.add.image(x + 30, y + 32, def.icon, def.iconFrame).setDisplaySize(38, 38));
    this.container.add(scene.add.text(x + 58, y + 16, def.name, {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#f5f7ff',
      stroke: '#0b1020',
      strokeThickness: 3,
    }).setOrigin(0, 0));
    this.container.add(scene.add.text(x + 58, y + 42, `${def.category}  ·  x${count}`, {
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

    if (def.equipment) {
      const weaponId = def.equipment.weaponId;
      const assignedIndex = playerWeaponLoadout.slots().indexOf(weaponId);
      const equipped = playerWeaponLoadout.equippedWeaponId() === weaponId;
      this.container.add(scene.add.text(x + 16, y + 134, equipped ? 'EQUIPPED' : assignedIndex >= 0 ? `HOTBAR SLOT ${assignedIndex + 1}` : 'NOT ON HOTBAR', {
        fontFamily: FONT,
        fontSize: '10px',
        fontStyle: 'bold',
        color: equipped ? '#ffdf8a' : '#86f0c3',
      }).setOrigin(0, 0));
      this.container.add(scene.add.text(x + 16, y + 154, 'Assign number key', {
        fontFamily: FONT,
        fontSize: '10px',
        color: '#88aeb5',
      }).setOrigin(0, 0));
      for (let slotIndex = 0; slotIndex < 5; slotIndex += 1) {
        this.addButton(
          x + 16 + slotIndex * 40,
          y + 174,
          34,
          30,
          `${slotIndex + 1}`,
          assignedIndex === slotIndex ? 0xffd277 : 0x2b6070,
          () => this.ctx.onAssignWeapon(weaponId, slotIndex),
        );
      }
    } else if (def.use) {
      const effects = [
        def.use.healHp ? `Heal HP +${def.use.healHp}` : '',
        def.use.healEnergy ? `Energy +${def.use.healEnergy}` : '',
        def.use.cureStatus?.length ? `Cures ${def.use.cureStatus.join(', ')}` : '',
      ].filter(Boolean).join('  ·  ');
      this.container.add(scene.add.text(x + 16, y + 148, effects, {
        fontFamily: FONT,
        fontSize: '11px',
        color: '#86f0c3',
        wordWrap: { width: width - 32 },
      }).setOrigin(0, 0));
    }

    if (def.equipment) {
      this.addButton(x + 16, y + height - 52, 112, 34, 'Equip Now', 0xffd277, () => {
        this.ctx.onEquipWeapon(def.equipment!.weaponId);
      });
      this.container.add(scene.add.text(x + 140, y + height - 35, 'Equipment is kept', {
        fontFamily: FONT,
        fontSize: '9px',
        color: '#6f8794',
      }).setOrigin(0, 0.5));
    } else {
      const quantityY = y + height - 132;
      this.addButton(x + 16, quantityY, 36, 30, '-10', 0x2b6070, () => this.adjustRemoveQuantity(-10, count));
      this.addButton(x + 56, quantityY, 30, 30, '-1', 0x2b6070, () => this.adjustRemoveQuantity(-1, count));
      this.container.add(scene.add.text(x + 112, quantityY + 15, `${this.removeQuantity}`, {
        fontFamily: FONT,
        fontSize: '13px',
        color: '#ffd277',
      }).setOrigin(0.5));
      this.addButton(x + 138, quantityY, 30, 30, '+1', 0x2b6070, () => this.adjustRemoveQuantity(1, count));
      this.addButton(x + 172, quantityY, 46, 30, '+10', 0x2b6070, () => this.adjustRemoveQuantity(10, count));

      const dropY = y + height - 94;
      const actionY = y + height - 52;
      const canDrop = this.ctx.canDropItem(def.id);
      this.addButton(x + 16, dropY, 120, 34, `Drop ${this.removeQuantity}`, 0x86f0c3, canDrop
        ? () => this.dropSelected(false)
        : undefined);
      this.addButton(x + 140, dropY, 78, 34, 'Drop All', 0x63d8aa, canDrop
        ? () => this.dropSelected(true)
        : undefined);
      if (def.use) {
        this.addButton(x + 16, actionY, 58, 34, 'Use', 0x86f0c3, () => {
          if (this.selectedItemId) this.ctx.onUseItem(this.selectedItemId);
        });
        this.addButton(x + 78, actionY, 88, 34, `Remove ${this.removeQuantity}`, 0xff8f7a, () => this.removeSelected(false));
        this.addButton(x + 170, actionY, 48, 34, 'All', 0xff6f88, () => this.removeSelected(true));
      } else {
        this.addButton(x + 16, actionY, 120, 34, `Remove ${this.removeQuantity}`, 0xff8f7a, () => this.removeSelected(false));
        this.addButton(x + 140, actionY, 78, 34, 'Remove All', 0xff6f88, () => this.removeSelected(true));
      }
    }
  }

  private adjustRemoveQuantity(delta: number, available: number): void {
    this.removeQuantity = Phaser.Math.Clamp(this.removeQuantity + delta, 1, available);
    this.refresh();
  }

  private removeSelected(removeAll: boolean): void {
    if (this.selectedItemId === undefined || this.selectedSlotIndex === undefined) return;
    const slotIndex = this.selectedSlotIndex;
    const selectedSlot = playerInventory.getSlots()[slotIndex];
    if (!selectedSlot || selectedSlot.itemId !== this.selectedItemId) return;
    const available = selectedSlot.count;
    const quantity = removeAll ? available : Phaser.Math.Clamp(this.removeQuantity, 1, available);
    if (quantity >= available) {
      this.selectedItemId = undefined;
      this.selectedSlotIndex = undefined;
      this.removeQuantity = 1;
    } else {
      this.removeQuantity = Math.min(this.removeQuantity, available - quantity);
    }
    playerInventory.removeFromSlot(slotIndex, quantity);
  }

  private dropSelected(dropAll: boolean): void {
    if (this.selectedItemId === undefined || this.selectedSlotIndex === undefined) return;
    const selectedSlot = playerInventory.getSlots()[this.selectedSlotIndex];
    if (!selectedSlot || selectedSlot.itemId !== this.selectedItemId) return;
    const quantity = dropAll
      ? selectedSlot.count
      : Phaser.Math.Clamp(this.removeQuantity, 1, selectedSlot.count);
    this.ctx.onDropItem(this.selectedSlotIndex, quantity);
    this.close();
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
    const slots = playerInventory.getSlots();
    const selectedSlot = this.selectedSlotIndex === undefined ? undefined : slots[this.selectedSlotIndex];
    if (selectedSlot && selectedSlot.itemId === this.selectedItemId) return;
    this.selectedSlotIndex = slots.length > 0 ? 0 : undefined;
    this.selectedItemId = slots[0]?.itemId;
    this.removeQuantity = 1;
  }

  public close(): void {
    if (!this.container) {
      this.modalHandle.close();
      return;
    }
    this.modalHandle.close();
    this.container.destroy();
    this.container = undefined;
    this.ctx.onPausedChange(false);
  }

  destroy(): void {
    gameEvents.off('inventory.changed', this.refresh, this);
    gameEvents.off('weapon.loadout.changed', this.refresh, this);
    gameEvents.off('weapon.equipped', this.refresh, this);
    this.modalHandle.unregister();
    this.ctx.scene.input.off('pointerdown', this.handlePointerDown, this);
    const wasOpen = !!this.container;
    this.container?.destroy();
    this.container = undefined;
    if (wasOpen) this.ctx.onPausedChange(false);
  }
}

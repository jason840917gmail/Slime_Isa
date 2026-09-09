import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { WEAPON_HOTBAR_SLOT_COUNT } from '../core/types';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { playerWeaponLoadout } from '../systems/WeaponLoadout';
import { createWeaponThumbnail } from './WeaponThumbnail';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';
const HOTBAR_MARGIN = 12;
const MIN_CELL = 40;
const MAX_CELL = 56;
const MIN_GAP = 4;
const MAX_GAP = 8;
const THUMBNAIL_SIZE = 30;

interface HotbarMetrics {
  readonly cell: number;
  readonly gap: number;
  readonly totalWidth: number;
}

export interface WeaponHotbarContext {
  readonly scene: Phaser.Scene;
  readonly onEquipSlot: (slotIndex: number) => void;
}

/** Six-slot field-tool belt. Inventory ownership is the authority for availability. */
export class WeaponHotbar {
  private root?: Phaser.GameObjects.Container;

  constructor(private readonly ctx: WeaponHotbarContext) {
    gameEvents.on('inventory.changed', this.refresh, this);
    gameEvents.on('weapon.loadout.changed', this.refresh, this);
    gameEvents.on('weapon.equipped', this.refresh, this);
    ctx.scene.scale.on('resize', this.refresh, this);
    ctx.scene.events.once(Phaser.Scenes.Events.CREATE, this.refresh, this);
    this.refresh();
  }

  destroy(): void {
    gameEvents.off('inventory.changed', this.refresh, this);
    gameEvents.off('weapon.loadout.changed', this.refresh, this);
    gameEvents.off('weapon.equipped', this.refresh, this);
    this.ctx.scene.scale.off('resize', this.refresh, this);
    this.ctx.scene.events.off(Phaser.Scenes.Events.CREATE, this.refresh, this);
    this.root?.destroy(true);
    this.root = undefined;
  }

  private refresh = (): void => {
    if (!this.ctx.scene.sys.isActive()) return;
    this.root?.destroy(true);
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const { cell, gap, totalWidth } = getHotbarMetrics(cam.width);
    const startX = cam.width / 2 - totalWidth / 2;
    const centerY = cam.height - 144;
    const root = scene.add.container(0, 0).setScrollFactor(0).setDepth(resolveScreenUiDepth(54));
    this.root = root;

    for (let index = 0; index < WEAPON_HOTBAR_SLOT_COUNT; index += 1) {
      const weaponId = playerWeaponLoadout.slots()[index];
      const owned = !!weaponId && playerWeaponLoadout.ownsWeapon(weaponId);
      const active = owned && weaponId === playerWeaponLoadout.equippedWeaponId();
      const x = startX + index * (cell + gap) + cell / 2;
      const slot = scene.add.container(x, centerY);
      root.add(slot);

      const frame = scene.add.graphics();
      frame.lineStyle(active ? 2.5 : 1, active ? 0xffd277 : owned ? 0x9be8b8 : 0xe2e9d7, active ? 1 : 0.7);
      frame.strokeRoundedRect(-cell / 2 + 0.75, -cell / 2 + 0.75, cell - 1.5, cell - 1.5, 8);
      if (active) {
        frame.lineStyle(1, 0xf5fff9, 0.72);
        frame.strokeRoundedRect(-cell / 2 + 4, -cell / 2 + 4, cell - 8, cell - 8, 5);
        frame.fillStyle(0xffd277, 1);
        frame.fillTriangle(-5, cell / 2 + 1, 5, cell / 2 + 1, 0, cell / 2 + 7);
      }
      slot.add(frame);

      slot.add(scene.add.text(-cell / 2 + 8, -cell / 2 + 8, `${index + 1}`, {
        fontFamily: FONT,
        fontSize: '9px',
        fontStyle: 'bold',
        color: active ? '#ffe8ae' : '#e7f2d7',
      }).setOrigin(0.5).setShadow(0, 1, '#081022', 2, true, true));

      const thumbnail = owned && weaponId
        ? createWeaponThumbnail(scene, weaponId, { x: 0, y: 2, size: Math.min(THUMBNAIL_SIZE, cell - 14) })
        : undefined;
      if (thumbnail) {
        slot.add(thumbnail);
      } else {
        const placeholder = scene.add.graphics();
        if (weaponId) {
          placeholder.lineStyle(1.5, 0xff8f7a, 0.9);
          placeholder.lineBetween(-5, -5, 5, 5);
          placeholder.lineBetween(5, -5, -5, 5);
        } else {
          placeholder.fillStyle(0xc1d4c0, 0.75);
          placeholder.fillCircle(0, 2, 2);
        }
        slot.add(placeholder);
      }

      const hitArea = scene.add.rectangle(0, 0, cell, cell, 0xffffff, 0.001).setInteractive({ useHandCursor: owned });
      hitArea.on('pointerdown', (
        _pointer: Phaser.Input.Pointer,
        _localX: number,
        _localY: number,
        event: Phaser.Types.Input.EventData,
      ) => {
        event.stopPropagation();
        this.ctx.onEquipSlot(index);
      });
      hitArea.on('pointerover', () => slot.setScale(1.06));
      hitArea.on('pointerout', () => slot.setScale(1));
      slot.add(hitArea);
    }
  };
}

function getHotbarMetrics(viewWidth: number): HotbarMetrics {
  const safeWidth = Math.max(0, viewWidth - HOTBAR_MARGIN * 2);
  const gap = Phaser.Math.Clamp(
    Math.floor((safeWidth - WEAPON_HOTBAR_SLOT_COUNT * MIN_CELL) / (WEAPON_HOTBAR_SLOT_COUNT - 1)),
    MIN_GAP,
    MAX_GAP,
  );
  const cell = Phaser.Math.Clamp(
    Math.floor((safeWidth - (WEAPON_HOTBAR_SLOT_COUNT - 1) * gap) / WEAPON_HOTBAR_SLOT_COUNT),
    MIN_CELL,
    MAX_CELL,
  );
  return {
    cell,
    gap,
    totalWidth: WEAPON_HOTBAR_SLOT_COUNT * cell + (WEAPON_HOTBAR_SLOT_COUNT - 1) * gap,
  };
}

import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { WEAPON_HOTBAR_SLOT_COUNT } from '../core/types';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { playerWeaponLoadout } from '../systems/WeaponLoadout';
import { weaponItemFor } from '../systems/Inventory';
import { createWeaponThumbnail } from './WeaponThumbnail';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';
const CELL = 56;
const GAP = 8;
const THUMBNAIL_SIZE = 30;

export interface WeaponHotbarContext {
  readonly scene: Phaser.Scene;
  readonly onEquipSlot: (slotIndex: number) => void;
}

/** Five-slot field-tool belt. Inventory ownership is the authority for availability. */
export class WeaponHotbar {
  private root?: Phaser.GameObjects.Container;

  constructor(private readonly ctx: WeaponHotbarContext) {
    gameEvents.on('inventory.changed', this.refresh, this);
    gameEvents.on('weapon.loadout.changed', this.refresh, this);
    gameEvents.on('weapon.equipped', this.refresh, this);
    ctx.scene.scale.on('resize', this.refresh, this);
    this.refresh();
  }

  destroy(): void {
    gameEvents.off('inventory.changed', this.refresh, this);
    gameEvents.off('weapon.loadout.changed', this.refresh, this);
    gameEvents.off('weapon.equipped', this.refresh, this);
    this.ctx.scene.scale.off('resize', this.refresh, this);
    this.root?.destroy(true);
    this.root = undefined;
  }

  private refresh = (): void => {
    if (!this.ctx.scene.sys.isActive()) return;
    this.root?.destroy(true);
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const totalWidth = WEAPON_HOTBAR_SLOT_COUNT * CELL + (WEAPON_HOTBAR_SLOT_COUNT - 1) * GAP;
    const startX = cam.width / 2 - totalWidth / 2;
    const centerY = cam.height - 144;
    const root = scene.add.container(0, 0).setScrollFactor(0).setDepth(resolveScreenUiDepth(54));
    this.root = root;

    const equippedItem = weaponItemFor(playerWeaponLoadout.equippedWeaponId());
    root.add(scene.add.text(cam.width / 2, centerY - 42, `FIELD TOOLS  ·  ${equippedItem?.name ?? 'NO WEAPON'}`, {
      fontFamily: FONT,
      fontSize: '10px',
      fontStyle: 'bold',
      color: '#c8ead9',
      stroke: '#081022',
      strokeThickness: 4,
      letterSpacing: 1.5,
    }).setOrigin(0.5));

    for (let index = 0; index < WEAPON_HOTBAR_SLOT_COUNT; index += 1) {
      const weaponId = playerWeaponLoadout.slots()[index];
      const owned = !!weaponId && playerWeaponLoadout.ownsWeapon(weaponId);
      const active = owned && weaponId === playerWeaponLoadout.equippedWeaponId();
      const item = weaponId ? weaponItemFor(weaponId) : undefined;
      const x = startX + index * (CELL + GAP) + CELL / 2;
      const slot = scene.add.container(x, centerY);
      root.add(slot);

      const shadow = scene.add.graphics();
      shadow.fillStyle(0x050a12, 0.72);
      shadow.fillRoundedRect(-CELL / 2 + 2, -CELL / 2 + 4, CELL, CELL, 9);
      slot.add(shadow);

      const frame = scene.add.graphics();
      frame.fillStyle(active ? 0x253e3d : 0x101a2b, active ? 0.98 : 0.94);
      frame.fillRoundedRect(-CELL / 2, -CELL / 2, CELL, CELL, 8);
      frame.lineStyle(active ? 3 : 1.5, active ? 0xffd277 : owned ? 0x67d8c6 : 0x35465d, active ? 1 : 0.82);
      frame.strokeRoundedRect(-CELL / 2, -CELL / 2, CELL, CELL, 8);
      if (active) {
        frame.lineStyle(1, 0xf5fff9, 0.7);
        frame.strokeRoundedRect(-CELL / 2 + 4, -CELL / 2 + 4, CELL - 8, CELL - 8, 5);
        frame.fillStyle(0xffd277, 1);
        frame.fillTriangle(-6, CELL / 2 + 2, 6, CELL / 2 + 2, 0, CELL / 2 + 9);
      }
      slot.add(frame);

      const keyPlate = scene.add.graphics();
      keyPlate.fillStyle(active ? 0xffd277 : 0x22324a, 1);
      keyPlate.fillRoundedRect(-CELL / 2 + 4, -CELL / 2 + 4, 16, 15, 4);
      slot.add(keyPlate);
      slot.add(scene.add.text(-CELL / 2 + 12, -CELL / 2 + 11, `${index + 1}`, {
        fontFamily: FONT,
        fontSize: '10px',
        fontStyle: 'bold',
        color: active ? '#17202a' : '#d9eef0',
      }).setOrigin(0.5));

      const thumbnail = owned && weaponId
        ? createWeaponThumbnail(scene, weaponId, { x: 3, y: -3, size: THUMBNAIL_SIZE })
        : undefined;
      if (thumbnail) {
        slot.add(thumbnail);
      } else if (owned && item && scene.textures.exists(item.icon)) {
        slot.add(scene.add.image(3, -3, item.icon).setDisplaySize(THUMBNAIL_SIZE, THUMBNAIL_SIZE));
      } else {
        slot.add(scene.add.text(3, -3, weaponId ? '×' : '·', {
          fontFamily: FONT,
          fontSize: weaponId ? '22px' : '28px',
          color: weaponId ? '#ff8f7a' : '#52657a',
        }).setOrigin(0.5));
      }

      const shortName = item?.name.split(/\s+/)[0]?.toUpperCase() ?? (weaponId ? 'LOCKED' : 'EMPTY');
      slot.add(scene.add.text(0, CELL / 2 - 7, shortName.slice(0, 9), {
        fontFamily: FONT,
        fontSize: '8px',
        fontStyle: 'bold',
        color: active ? '#ffdf8a' : owned ? '#a9d8cf' : '#59697a',
      }).setOrigin(0.5, 1));

      const hitArea = scene.add.rectangle(0, 0, CELL, CELL, 0xffffff, 0.001).setInteractive({ useHandCursor: owned });
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

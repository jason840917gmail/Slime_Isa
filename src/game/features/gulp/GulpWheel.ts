import type Phaser from 'phaser';

import { GULP_FORM_ICON_TEXTURE } from '../../content/gulp/gulpForms';
import { UI_THEME } from '../../presentation/theme';
import { itemRegistry } from '../../systems/Inventory';
import type { GulpPoint, GulpWheelEntry } from './GulpController';
import { gulpWheelSlotAngle } from './GulpWheelLayout';

/** Above every world object and the Gulp HUD texts. */
const WHEEL_DEPTH = 9_000_000_002;
const RING_RADIUS = 72;
const SLOT_RADIUS = 25;
const ICON_SIZE = 46;
/** The wheel is centred on the slime's body. */
const BODY_RISE = 0;
const RING_TEXTURE = 'gulp-wheel-ring';

/** Draws the ring backdrop once (a canvas even-odd fill has no seams). */
function ringTexture(scene: Phaser.Scene): string {
  if (scene.textures.exists(RING_TEXTURE)) return RING_TEXTURE;
  const outer = RING_RADIUS + SLOT_RADIUS + 8;
  const inner = RING_RADIUS - SLOT_RADIUS - 8;
  const size = outer * 2 + 4;
  const canvas = scene.textures.createCanvas(RING_TEXTURE, size, size);
  const context = canvas?.getContext();
  if (!canvas || !context) return RING_TEXTURE;
  const center = size / 2;
  context.beginPath();
  context.arc(center, center, outer, 0, Math.PI * 2);
  context.arc(center, center, inner, 0, Math.PI * 2, true);
  context.fillStyle = 'rgba(11, 20, 38, 0.58)';
  context.fill('evenodd');
  context.lineWidth = 2;
  context.strokeStyle = 'rgba(255, 232, 154, 0.6)';
  for (const radius of [outer, inner]) {
    context.beginPath();
    context.arc(center, center, radius, 0, Math.PI * 2);
    context.stroke();
  }
  canvas.refresh();
  return RING_TEXTURE;
}

interface WheelSlot {
  readonly disc: Phaser.GameObjects.Arc;
  readonly icon?: Phaser.GameObjects.Image;
  readonly count: Phaser.GameObjects.Text;
}

/**
 * The hold-W quick wheel (roadmap 7.2): the carried Gulp materials in a ring
 * around the slime, the chosen one lit, its form named in the middle. It draws
 * in the world, so nothing pauses while it is open.
 */
export class GulpWheel {
  private readonly container: Phaser.GameObjects.Container;
  private readonly title: Phaser.GameObjects.Text;
  private slots: WheelSlot[] = [];
  private entries: readonly GulpWheelEntry[] = [];

  constructor(private readonly scene: Phaser.Scene) {
    // A ring, not a disc: the slime stays visible in the middle.
    const backdrop = scene.add.image(0, 0, ringTexture(scene));
    this.title = scene.add.text(0, RING_RADIUS + SLOT_RADIUS + 18, '', {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '13px',
      color: '#ffe89a',
      stroke: UI_THEME.colors.shadow,
      strokeThickness: 4,
      align: 'center',
    }).setOrigin(0.5, 0.5);
    this.container = scene.add.container(0, 0, [backdrop, this.title]).setDepth(WHEEL_DEPTH).setVisible(false);
  }

  get isOpen(): boolean {
    return this.container.visible;
  }

  open(entries: readonly GulpWheelEntry[]): void {
    this.clearSlots();
    this.entries = entries;
    this.slots = entries.map((entry, index) => {
      const radians = (gulpWheelSlotAngle(index, entries.length) * Math.PI) / 180;
      const x = Math.cos(radians) * RING_RADIUS;
      const y = Math.sin(radians) * RING_RADIUS;
      const disc = this.scene.add.circle(x, y, SLOT_RADIUS, 0x1b2a45, 0.95).setStrokeStyle(2, 0x6d7fa6, 1);
      // The form's badge shows what eating it does; the material icon is the fallback.
      const item = itemRegistry.get(entry.itemId);
      const icon = this.scene.textures.exists(GULP_FORM_ICON_TEXTURE)
        ? this.scene.add.image(x, y, GULP_FORM_ICON_TEXTURE, entry.form.iconFrame)
        : item && this.scene.textures.exists(item.icon)
          ? this.scene.add.image(x, y - 2, item.icon, item.iconFrame ?? 0)
          : undefined;
      if (icon) icon.setScale(ICON_SIZE / Math.max(icon.width, icon.height, 1));
      const count = this.scene.add.text(x + 14, y + 12, `${entry.count}`, {
        fontFamily: UI_THEME.fontFamily,
        fontSize: '12px',
        color: UI_THEME.colors.text,
        stroke: UI_THEME.colors.shadow,
        strokeThickness: 3,
      }).setOrigin(0.5, 0.5);
      this.container.add([disc, ...(icon ? [icon] : []), count]);
      return { disc, icon, count };
    });
    this.container.setVisible(true);
  }

  /** Follows the slime and lights the chosen slot. */
  update(player: GulpPoint, selected: number | undefined): void {
    if (!this.isOpen) return;
    this.container.setPosition(player.x, player.y - BODY_RISE);
    this.slots.forEach((slot, index) => {
      const chosen = index === selected;
      slot.disc.setFillStyle(chosen ? 0x3a5a2c : 0x1b2a45, 0.95).setStrokeStyle(chosen ? 3 : 2, chosen ? 0xffe89a : 0x6d7fa6, 1);
      slot.disc.setScale(chosen ? 1.15 : 1);
      slot.icon?.setAlpha(chosen ? 1 : 0.75);
    });
    const entry = selected === undefined ? undefined : this.entries[selected];
    this.title.setText(entry ? entry.form.name.toUpperCase() : 'GULP');
  }

  close(): void {
    this.container.setVisible(false);
    this.clearSlots();
    this.entries = [];
  }

  destroy(): void {
    this.clearSlots();
    this.container.destroy();
  }

  private clearSlots(): void {
    for (const slot of this.slots) {
      slot.disc.destroy();
      slot.icon?.destroy();
      slot.count.destroy();
    }
    this.slots = [];
  }
}

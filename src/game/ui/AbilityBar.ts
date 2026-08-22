import Phaser from 'phaser';
import type { AbilitySystem, AbilityId } from '../systems/AbilitySystem';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';

/**
 * Bottom-center ability bar. Shows the two level-gated abilities (jump,
 * teleport) with their unlock level while locked, and a radial/linear
 * cooldown overlay once unlocked. Communicates "abilities are earned by
 * leveling" without text.
 */
const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export interface AbilityBarContext {
  scene: Phaser.Scene;
  getAbilitySystem: () => AbilitySystem | undefined;
}

interface Slot {
  id: AbilityId;
  key: string;
  bg: Phaser.GameObjects.Graphics;
  icon: Phaser.GameObjects.Text;
  label: Phaser.GameObjects.Text;
  cooldown: Phaser.GameObjects.Graphics;
  locked: Phaser.GameObjects.Text;
}

const DEFS: { id: AbilityId; key: string; glyph: string; hotkey: string }[] = [
  { id: 'jump', key: 'Space', glyph: 'â¤´', hotkey: 'Space' },
  { id: 'squash-slam', key: 'T', glyph: 'â—‰', hotkey: 'T' },
  { id: 'stretch-lash', key: 'R', glyph: 'âŸ¶', hotkey: 'R' },
  { id: 'teleport', key: 'Y', glyph: 'âœ¦', hotkey: 'Y' },
];

export class AbilityBar {
  private ctx: AbilityBarContext;
  private slots: Slot[] = [];

  constructor(ctx: AbilityBarContext) {
    this.ctx = ctx;
    const scene = ctx.scene;

    const cell = 52;
    const gap = 10;
    const totalW = DEFS.length * cell + (DEFS.length - 1) * gap;
    const startX = scene.cameras.main.width / 2 - totalW / 2;
    const y = scene.cameras.main.height - 70;

    DEFS.forEach((def, i) => {
      const x = startX + i * (cell + gap);
      const cx = x + cell / 2;
      const cy = y + cell / 2;

      const bg = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(50));
      this.drawBg(bg, cx, cy, cell);

      const icon = scene.add
        .text(cx, cy - 6, def.glyph, { fontFamily: FONT, fontSize: '22px', color: '#f5f7ff' })
        .setOrigin(0.5)
        .setScrollFactor(0)
        .setDepth(resolveScreenUiDepth(51));

      const label = scene.add
        .text(cx, cy + 16, def.hotkey, { fontFamily: FONT, fontSize: '10px', color: '#88c899' })
        .setOrigin(0.5)
        .setScrollFactor(0)
        .setDepth(resolveScreenUiDepth(51));

      const cooldown = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(52));

      const locked = scene.add
        .text(cx, cy, '', { fontFamily: FONT, fontSize: '11px', color: '#ffd277', stroke: '#0b1020', strokeThickness: 3 })
        .setOrigin(0.5)
        .setScrollFactor(0)
        .setDepth(resolveScreenUiDepth(53));

      this.slots.push({ id: def.id, key: def.key, bg, icon, label, cooldown, locked });
    });

    scene.scale.on('resize', this.handleResize, this);
  }

  update(): void {
    const sys = this.ctx.getAbilitySystem();
    if (!sys) return;

    for (const slot of this.slots) {
      const unlocked = sys.isUnlocked(slot.id);
      const unlockLevel = sys.unlockLevel(slot.id);

      if (!unlocked) {
        slot.icon.setAlpha(0.35);
        slot.locked.setText(`Lv ${unlockLevel}`).setVisible(true);
        slot.cooldown.clear();
        continue;
      }

      slot.locked.setVisible(false);
      slot.icon.setAlpha(1);

      // Cooldown sweep â€” we don't expose remaining ms directly; approximate
      // by re-drawing each frame. Read via a small reflection: the system
      // exposes isBusy + we can ask via a method. For now, no overlay when
      // not busy (ready). A fuller cooldown ring is added in Phase 2.
      slot.cooldown.clear();
      if (sys.isBusy()) {
        const cx = slot.icon.x;
        const cy = slot.icon.y;
        slot.cooldown.fillStyle(0x0b1020, 0.5);
        slot.cooldown.fillRoundedRect(cx - 22, cy - 22, 44, 44, 6);
      }
    }
  }

  private drawBg(g: Phaser.GameObjects.Graphics, cx: number, cy: number, cell: number): void {
    g.fillStyle(0x0b1020, 0.85);
    g.fillRoundedRect(cx - cell / 2, cy - cell / 2, cell, cell, 8);
    g.lineStyle(2, 0x3b5c78, 0.8);
    g.strokeRoundedRect(cx - cell / 2, cy - cell / 2, cell, cell, 8);
  }

  private handleResize(size: Phaser.Structs.Size): void {
    const w = size.width;
    const h = size.height;
    const cell = 52;
    const gap = 10;
    const totalW = DEFS.length * cell + (DEFS.length - 1) * gap;
    const startX = w / 2 - totalW / 2;
    const y = h - 70;
    this.slots.forEach((slot, i) => {
      const x = startX + i * (cell + gap);
      const cx = x + cell / 2;
      const cy = y + cell / 2;
      slot.bg.clear();
      this.drawBg(slot.bg, cx, cy, cell);
      slot.icon.setPosition(cx, cy - 6);
      slot.label.setPosition(cx, cy + 16);
      slot.locked.setPosition(cx, cy);
      slot.cooldown.clear();
    });
  }

  destroy(): void {
    this.ctx.scene.scale.off('resize', this.handleResize, this);
    for (const s of this.slots) {
      s.bg.destroy();
      s.icon.destroy();
      s.label.destroy();
      s.cooldown.destroy();
      s.locked.destroy();
    }
  }
}

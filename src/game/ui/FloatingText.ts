import Phaser from 'phaser';

/**
 * Pooled floating combat text. Rises + fades, crits bigger/yellow.
 *
 * Use `FloatingText.spawn(scene, x, y, text, color, big)` from anywhere.
 */

const FONT = 'Aptos, Segoe UI Variable, sans-serif';
const POOL_SIZE = 24;

type Color = 'white' | 'yellow' | 'orange' | 'green' | 'red' | 'cyan';

const COLORS: Record<Color, string> = {
  white: '#ffffff',
  yellow: '#ffe680',
  orange: '#ff9a3c',
  green: '#7be08a',
  red: '#ff5a5a',
  cyan: '#6be0ff',
};

interface PooledText {
  text: Phaser.GameObjects.Text;
  busy: boolean;
}

class FloatingTextPool {
  private pools = new Map<Phaser.Scene, PooledText[]>();

  spawn(scene: Phaser.Scene, x: number, y: number, content: string, color: Color = 'white', big = false): void {
    const pool = this.getPool(scene);
    const slot = pool.find((p) => !p.busy);

    if (slot) {
      this.activate(slot, x, y, content, color, big);
      return;
    }

    if (pool.length < POOL_SIZE) {
      const newText = scene.add
        .text(x, y, content, {
          fontFamily: FONT,
          fontSize: big ? '22px' : '15px',
          color: COLORS[color],
          stroke: '#0a1f15',
          strokeThickness: 4,
        })
        .setOrigin(0.5)
        .setDepth(150)
        .setScale(0.1)
        .setAlpha(0);

      const entry: PooledText = { text: newText, busy: false };
      pool.push(entry);
      this.activate(entry, x, y, content, color, big);
    }
  }

  private getPool(scene: Phaser.Scene): PooledText[] {
    let pool = this.pools.get(scene);
    if (!pool) {
      pool = [];
      this.pools.set(scene, pool);
    }
    return pool;
  }

  private activate(slot: PooledText, x: number, y: number, content: string, color: Color, big: boolean): void {
    slot.busy = true;
    const t = slot.text;
    t.setText(content)
      .setFontSize(big ? '22px' : '15px')
      .setColor(COLORS[color])
      .setPosition(x, y)
      .setAlpha(1)
      .setScale(big ? 1.1 : 0.9)
      .setVisible(true);

    const scene = t.scene;
    scene.tweens.add({
      targets: t,
      y: y - (big ? 48 : 34),
      alpha: 0,
      scale: big ? 1.3 : 1,
      duration: big ? 900 : 700,
      ease: 'Quad.Out',
      onComplete: () => {
        slot.busy = false;
        t.setVisible(false);
      },
    });
  }

  clearScene(scene: Phaser.Scene): void {
    const pool = this.pools.get(scene);
    if (pool) {
      for (const p of pool) p.text.destroy();
      this.pools.delete(scene);
    }
  }
}

export const floatingText = new FloatingTextPool();

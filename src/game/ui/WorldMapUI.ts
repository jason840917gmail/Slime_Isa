import Phaser from 'phaser';
import { AREAS, type AreaId } from '../world/Area';
import { BIOMES } from '../world/Biome';
import { worldProgress } from '../features/progression/WorldProgress';
import { UI_THEME } from '../presentation/theme';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';

const FONT = UI_THEME.fontFamily;

export interface WorldMapUIContext {
  scene: Phaser.Scene;
  getCurrentArea: () => AreaId;
  onPausedChange: (paused: boolean) => void;
}

export class WorldMapUI {
  private ctx: WorldMapUIContext;
  private container?: Phaser.GameObjects.Container;
  private escKey?: Phaser.Input.Keyboard.Key;

  constructor(ctx: WorldMapUIContext) {
    this.ctx = ctx;
    const kb = ctx.scene.input.keyboard;
    if (kb) {
      this.escKey = kb.addKey(Phaser.Input.Keyboard.KeyCodes.ESC);
      this.escKey.on('down', () => {
        if (this.container) this.close();
      });
    }
  }

  isOpen(): boolean {
    return !!this.container;
  }

  discover(areaId: AreaId): void {
    worldProgress.discoverArea(areaId);
  }

  toggle(): void {
    if (this.container) this.close();
    else this.open();
  }

  private open(): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const currentArea = this.ctx.getCurrentArea();
    worldProgress.discoverArea(currentArea);
    const discovered = worldProgress.discovered();

    const container = scene.add.container(cam.width / 2, cam.height / 2).setScrollFactor(0).setDepth(resolveScreenUiDepth(110));
    this.container = container;
    container.add(scene.add.rectangle(0, 0, cam.width, cam.height, 0x080f20, 0.72).setOrigin(0.5));

    const panelW = 560;
    const panelH = 330;
    const bg = scene.add.graphics();
    bg.fillStyle(0x101a31, 0.98);
    bg.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    bg.lineStyle(2, 0x73e2b1, 0.85);
    bg.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    container.add(bg);

    container.add(scene.add.text(0, -panelH / 2 + 28, 'World Map', {
      fontFamily: FONT,
      fontSize: '24px',
      color: '#e7fff5',
      stroke: '#0b1020',
      strokeThickness: 5,
    }).setOrigin(0.5));

    container.add(scene.add.text(panelW / 2 - 18, -panelH / 2 + 20, 'M / Esc to close', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#88c899',
    }).setOrigin(1, 0));

    this.drawConnections(container, discovered);
    this.drawAreas(container, discovered, currentArea);

    container.add(scene.add.text(0, panelH / 2 - 28, 'Discovered areas stay marked as you travel.', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#88c899',
    }).setOrigin(0.5));

    this.ctx.onPausedChange(true);
    scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, scale: { from: 0.96, to: 1 }, duration: 140 });
  }

  private drawConnections(container: Phaser.GameObjects.Container, discovered: ReadonlySet<AreaId>): void {
    const scene = this.ctx.scene;
    const g = scene.add.graphics();
    container.add(g);

    for (const area of Object.values(AREAS)) {
      if (!discovered.has(area.id)) continue;
      const from = this.mapPoint(area.id);
      for (const targetId of Object.values(area.neighbors)) {
        if (!targetId || !discovered.has(targetId)) continue;
        const to = this.mapPoint(targetId);
        g.lineStyle(4, 0x3b5c78, 0.95);
        g.lineBetween(from.x, from.y, to.x, to.y);
        g.lineStyle(1.5, 0x86f0c3, 0.55);
        g.lineBetween(from.x, from.y, to.x, to.y);
      }
    }
  }

  private drawAreas(container: Phaser.GameObjects.Container, discovered: ReadonlySet<AreaId>, currentArea: AreaId): void {
    const scene = this.ctx.scene;

    for (const area of Object.values(AREAS)) {
      const p = this.mapPoint(area.id);
      const isDiscovered = discovered.has(area.id);
      const isCurrent = area.id === currentArea;
      const biome = BIOMES[area.biome];
      const node = scene.add.graphics();

      node.fillStyle(isDiscovered ? biome.ambientTint : 0x203028, isDiscovered ? 1 : 0.8);
      node.fillCircle(p.x, p.y, isCurrent ? 26 : 22);
      node.lineStyle(isCurrent ? 4 : 2, isCurrent ? 0xffdf8a : 0x73e2b1, isDiscovered ? 1 : 0.35);
      node.strokeCircle(p.x, p.y, isCurrent ? 26 : 22);
      container.add(node);

      container.add(scene.add.text(p.x, p.y - 4, isDiscovered ? 'â—' : '?', {
        fontFamily: FONT,
        fontSize: isCurrent ? '18px' : '16px',
        color: isCurrent ? '#ffdf8a' : '#e7fff5',
      }).setOrigin(0.5));

      container.add(scene.add.text(p.x, p.y + 34, isDiscovered ? area.name : 'Unknown', {
        fontFamily: FONT,
        fontSize: '12px',
        color: isDiscovered ? '#e7fff5' : '#668070',
        align: 'center',
        wordWrap: { width: 120 },
      }).setOrigin(0.5, 0));
    }
  }

  private mapPoint(areaId: AreaId): Phaser.Math.Vector2 {
    const area = AREAS[areaId];
    return new Phaser.Math.Vector2(-180 + area.mapX * 180, -30 + area.mapY * 120);
  }

  private close(): void {
    if (!this.container) return;
    this.container.destroy();
    this.container = undefined;
    this.ctx.onPausedChange(false);
  }

  destroy(): void {
    this.escKey?.off('down');
    this.container?.destroy();
  }
}

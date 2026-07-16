import Phaser from 'phaser';
import { AREAS, type AreaId } from '../world/Area';
import { BIOMES } from '../world/Biome';

const FONT = 'Aptos, Segoe UI Variable, sans-serif';
const DISCOVERED_KEY = 'slime-isa:discovered-areas';

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
    const discovered = this.loadDiscovered();
    discovered.add(areaId);
    this.saveDiscovered(discovered);
  }

  toggle(): void {
    if (this.container) this.close();
    else this.open();
  }

  private open(): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const currentArea = this.ctx.getCurrentArea();
    const discovered = this.loadDiscovered();
    discovered.add(currentArea);
    this.saveDiscovered(discovered);

    const container = scene.add.container(cam.width / 2, cam.height / 2).setScrollFactor(0).setDepth(310);
    this.container = container;
    container.add(scene.add.rectangle(0, 0, cam.width, cam.height, 0x020906, 0.72).setOrigin(0.5));

    const panelW = 560;
    const panelH = 330;
    const bg = scene.add.graphics();
    bg.fillStyle(0x071612, 0.98);
    bg.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    bg.lineStyle(2, 0x44cc88, 0.85);
    bg.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    container.add(bg);

    container.add(scene.add.text(0, -panelH / 2 + 28, 'World Map', {
      fontFamily: FONT,
      fontSize: '24px',
      color: '#dffff0',
      stroke: '#0a1f15',
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

  private drawConnections(container: Phaser.GameObjects.Container, discovered: Set<AreaId>): void {
    const scene = this.ctx.scene;
    const g = scene.add.graphics();
    container.add(g);

    for (const area of Object.values(AREAS)) {
      if (!discovered.has(area.id)) continue;
      const from = this.mapPoint(area.id);
      for (const targetId of Object.values(area.neighbors)) {
        if (!targetId || !discovered.has(targetId)) continue;
        const to = this.mapPoint(targetId);
        g.lineStyle(4, 0x335c45, 0.95);
        g.lineBetween(from.x, from.y, to.x, to.y);
        g.lineStyle(1.5, 0x88ffaa, 0.55);
        g.lineBetween(from.x, from.y, to.x, to.y);
      }
    }
  }

  private drawAreas(container: Phaser.GameObjects.Container, discovered: Set<AreaId>, currentArea: AreaId): void {
    const scene = this.ctx.scene;

    for (const area of Object.values(AREAS)) {
      const p = this.mapPoint(area.id);
      const isDiscovered = discovered.has(area.id);
      const isCurrent = area.id === currentArea;
      const biome = BIOMES[area.biome];
      const node = scene.add.graphics();

      node.fillStyle(isDiscovered ? biome.ambientTint : 0x203028, isDiscovered ? 1 : 0.8);
      node.fillCircle(p.x, p.y, isCurrent ? 26 : 22);
      node.lineStyle(isCurrent ? 4 : 2, isCurrent ? 0xffe680 : 0x44cc88, isDiscovered ? 1 : 0.35);
      node.strokeCircle(p.x, p.y, isCurrent ? 26 : 22);
      container.add(node);

      container.add(scene.add.text(p.x, p.y - 4, isDiscovered ? '●' : '?', {
        fontFamily: FONT,
        fontSize: isCurrent ? '18px' : '16px',
        color: isCurrent ? '#ffe680' : '#dffff0',
      }).setOrigin(0.5));

      container.add(scene.add.text(p.x, p.y + 34, isDiscovered ? area.name : 'Unknown', {
        fontFamily: FONT,
        fontSize: '12px',
        color: isDiscovered ? '#dffff0' : '#668070',
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

  private loadDiscovered(): Set<AreaId> {
    try {
      const raw = localStorage.getItem(DISCOVERED_KEY);
      const parsed = raw ? JSON.parse(raw) as AreaId[] : [];
      return new Set(parsed.filter((id): id is AreaId => id in AREAS));
    } catch {
      return new Set<AreaId>();
    }
  }

  private saveDiscovered(discovered: Set<AreaId>): void {
    try {
      localStorage.setItem(DISCOVERED_KEY, JSON.stringify([...discovered]));
    } catch {
      // ignore storage failures; map still works for current open.
    }
  }

  destroy(): void {
    this.escKey?.off('down');
    this.container?.destroy();
  }
}

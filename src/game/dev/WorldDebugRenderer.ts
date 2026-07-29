import Phaser from 'phaser';
import { hitboxPool, type HitboxConfig } from '../combat/Hitbox';
import { devToolsState } from '../devTools';
import type { House } from '../House';
import type { WorldDimensions } from '../world/WorldDimensions';
import { resolveExplicitDepth } from '../presentation/WorldDepth';

type DebugGroup = Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup;

export interface WorldDebugContext {
  scene: Phaser.Scene;
  dimensions: WorldDimensions;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getFriends: () => Phaser.Physics.Arcade.Group | undefined;
  getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
  getCollisionTiles: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getPurpleFoods: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getGrapeChips: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getDungeonSwitches: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getDungeonChests: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getHouses: () => Array<{ house: House }>;
  getTransitionZones: () => Phaser.GameObjects.Zone[];
}

export class WorldDebugRenderer {
  private graphics?: Phaser.GameObjects.Graphics;

  constructor(private readonly ctx: WorldDebugContext) {}

  update(): void {
    if (!import.meta.env.DEV) return;
    const g = this.graphics ?? this.ctx.scene.add.graphics()
      .setDepth(resolveExplicitDepth('editor-template-overlay', 10))
      .setScrollFactor(1);
    this.graphics = g;
    g.clear();
    if (!devToolsState.enabled) {
      g.setVisible(false);
      return;
    }

    g.setVisible(true);
    if (devToolsState.worldBounds) this.drawWorld(g);
    if (devToolsState.visualBounds) this.drawVisualBounds(g);
    if (devToolsState.hitBoxes) this.drawHitBoxes(g);
    if (devToolsState.interactionZones) this.drawInteractionZones(g);
    if (devToolsState.attackBoxes) this.drawAttackBoxes(g);
  }

  destroy(): void {
    this.graphics?.destroy();
    this.graphics = undefined;
  }

  private drawWorld(g: Phaser.GameObjects.Graphics): void {
    this.strokeRect(
      g,
      0,
      0,
      this.ctx.dimensions.width,
      this.ctx.dimensions.height,
      0xffe66d,
      0.95,
      3,
    );
    const view = this.ctx.scene.cameras.main.worldView;
    this.strokeRect(g, view.x, view.y, view.width, view.height, 0xffe66d, 0.6, 2);
  }

  private drawVisualBounds(g: Phaser.GameObjects.Graphics): void {
    this.drawObjectBounds(g, this.ctx.getPlayer(), 0x72d8ff, 0.95);
    this.forChildren(this.ctx.getFriends(), (child) => this.drawObjectBounds(g, child, 0x72d8ff, 0.75));
    this.forChildren(this.ctx.getCombatTargets(), (child) => this.drawObjectBounds(g, child, 0x72d8ff, 0.85));
    this.forChildren(this.ctx.getPurpleFoods(), (child) => this.drawObjectBounds(g, child, 0x72d8ff, 0.55));
    this.forChildren(this.ctx.getGrapeChips(), (child) => this.drawObjectBounds(g, child, 0x72d8ff, 0.55));
    for (const entry of this.ctx.getHouses()) this.drawObjectBounds(g, entry.house.sprite, 0x72d8ff, 0.65);
  }

  private drawHitBoxes(g: Phaser.GameObjects.Graphics): void {
    this.drawBody(g, this.ctx.getPlayer().body, 0xff4d6d, 0.95);
    this.forChildren(this.ctx.getFriends(), (child) => this.drawBody(g, this.bodyOf(child), 0xff4d6d, 0.7));
    this.forChildren(this.ctx.getCombatTargets(), (child) => this.drawBody(g, this.bodyOf(child), 0xff4d6d, 0.9));
    this.forChildren(this.ctx.getCollisionTiles(), (child) => this.drawBody(g, this.bodyOf(child), 0xff4d6d, 0.35));
  }

  private drawInteractionZones(g: Phaser.GameObjects.Graphics): void {
    for (const entry of this.ctx.getHouses()) this.drawBody(g, this.bodyOf(entry.house.doorZone), 0x73e2b1, 0.9);
    for (const zone of this.ctx.getTransitionZones()) this.drawBody(g, this.bodyOf(zone), 0x73e2b1, 0.85);
    this.forChildren(this.ctx.getPurpleFoods(), (child) => this.drawBody(g, this.bodyOf(child), 0x73e2b1, 0.75));
    this.forChildren(this.ctx.getGrapeChips(), (child) => this.drawBody(g, this.bodyOf(child), 0x73e2b1, 0.75));
    this.forChildren(this.ctx.getDungeonSwitches(), (child) => this.drawBody(g, this.bodyOf(child), 0x73e2b1, 0.85));
    this.forChildren(this.ctx.getDungeonChests(), (child) => this.drawBody(g, this.bodyOf(child), 0x73e2b1, 0.85));
  }

  private drawAttackBoxes(g: Phaser.GameObjects.Graphics): void {
    for (const config of hitboxPool.getActiveConfigs(this.ctx.scene)) this.drawAttackShape(g, config);
  }

  private drawAttackShape(g: Phaser.GameObjects.Graphics, config: HitboxConfig): void {
    if (config.shape === 'sector') {
      const originX = config.originX ?? config.x;
      const originY = config.originY ?? config.y;
      const angle = config.angle ?? 0;
      const halfArc = (config.arcWidth ?? Math.PI / 2) / 2;
      const inner = config.innerRadius ?? 0;
      const outer = config.outerRadius ?? Math.max(config.width, config.height) / 2;
      g.fillStyle(0xa78bfa, 0.12).lineStyle(3, 0xa78bfa, 0.95).beginPath();
      g.arc(originX, originY, outer, angle - halfArc, angle + halfArc, false);
      if (inner > 0) g.arc(originX, originY, inner, angle + halfArc, angle - halfArc, true);
      else g.lineTo(originX, originY);
      g.closePath().fillPath().strokePath();
      this.strokeRect(g, config.x - config.width / 2, config.y - config.height / 2, config.width, config.height, 0xa78bfa, 0.42, 1);
      return;
    }
    this.fillRect(g, config.x - config.width / 2, config.y - config.height / 2, config.width, config.height, 0xa78bfa, 0.12);
    this.strokeRect(g, config.x - config.width / 2, config.y - config.height / 2, config.width, config.height, 0xa78bfa, 0.95, 3);
  }

  private drawObjectBounds(g: Phaser.GameObjects.Graphics, object: Phaser.GameObjects.GameObject | null | undefined, color: number, alpha: number): void {
    const target = object as (Phaser.GameObjects.GameObject & { getBounds?: () => Phaser.Geom.Rectangle; active?: boolean }) | null | undefined;
    if (!target || target.active === false || !target.getBounds) return;
    const bounds = target.getBounds();
    this.strokeRect(g, bounds.x, bounds.y, bounds.width, bounds.height, color, alpha, 2);
  }

  private drawBody(g: Phaser.GameObjects.Graphics, body: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null | undefined, color: number, alpha: number): void {
    if (!body) return;
    if ('isCircle' in body && body.isCircle) {
      const radius = Math.min(body.width, body.height) / 2;
      const centerX = body.x + body.width / 2;
      const centerY = body.y + body.height / 2;
      g.fillStyle(color, 0.06).fillCircle(centerX, centerY, radius);
      g.lineStyle(2, color, alpha).strokeCircle(centerX, centerY, radius);
      return;
    }
    this.fillRect(g, body.x, body.y, body.width, body.height, color, 0.06);
    this.strokeRect(g, body.x, body.y, body.width, body.height, color, alpha, 2);
  }

  private forChildren(group: DebugGroup | null | undefined, callback: (child: Phaser.GameObjects.GameObject) => void): void {
    if (!group) return;
    for (const child of group.getChildren()) callback(child);
  }

  private bodyOf(object: Phaser.GameObjects.GameObject | null | undefined): Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null {
    return (object as Phaser.GameObjects.GameObject & {
      body?: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody;
    } | null | undefined)?.body ?? null;
  }

  private fillRect(g: Phaser.GameObjects.Graphics, x: number, y: number, width: number, height: number, color: number, alpha: number): void {
    g.fillStyle(color, alpha).fillRect(x, y, width, height);
  }

  private strokeRect(g: Phaser.GameObjects.Graphics, x: number, y: number, width: number, height: number, color: number, alpha: number, lineWidth: number): void {
    g.lineStyle(lineWidth, color, alpha).strokeRect(x, y, width, height);
  }
}

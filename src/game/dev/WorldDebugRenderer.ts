import Phaser from 'phaser';
import { hitboxPool, type HitboxConfig } from '../combat/Hitbox';
import { devToolsState } from '../devTools';
import type { MapEnemyAreaPerimeter, MapEnemySpawnArea } from '../content/maps/mapFormat';
import type { House } from '../House';
import type { WorldDimensions } from '../world/WorldDimensions';
import {
  resolveBodyBottom,
  resolveExplicitDepth,
} from '../presentation/WorldDepth';
import {
  resolveWorldOcclusionRectangle,
  type SourceFrameDimensions,
  type SourceOcclusionBounds,
} from '../presentation/WorldOcclusion';

type DebugGroup = Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup;

export interface WorldDebugContext {
  scene: Phaser.Scene;
  dimensions: WorldDimensions;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getFriends: () => Phaser.Physics.Arcade.Group | undefined;
  getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
  getCollisionTiles: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getCollectibleTargets: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getDungeonSwitches: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getDungeonChests: () => Phaser.Physics.Arcade.StaticGroup | undefined;
  getHouses: () => Array<{ house: House }>;
  getTransitionZones: () => Phaser.GameObjects.Zone[];
  getEnemySpawnAreas: () => readonly MapEnemySpawnArea[];
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
    if (devToolsState.occlusionBounds) this.drawOcclusionBounds(g);
    if (devToolsState.depthBounds) this.drawDepthBounds(g);
    if (devToolsState.depthAnchors) this.drawDepthAnchors(g);
    if (devToolsState.interactionZones) this.drawInteractionZones(g);
    if (devToolsState.attackBoxes) this.drawActiveAttackHitboxes(g);
    if (devToolsState.enemyBoundaries) this.drawEnemyBoundaries(g);
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
    this.forChildren(this.ctx.getCollectibleTargets(), (child) => this.drawObjectBounds(g, child, 0x72d8ff, 0.55));
    this.forWorldObjects((object) => this.drawObjectBounds(g, object, 0x72d8ff, 0.75));
    for (const entry of this.ctx.getHouses()) this.drawObjectBounds(g, entry.house.sprite, 0x72d8ff, 0.65);
  }

  private drawHitBoxes(g: Phaser.GameObjects.Graphics): void {
    this.drawBody(g, this.ctx.getPlayer().body, 0xff4d6d, 0.95);
    this.forChildren(this.ctx.getFriends(), (child) => this.drawBody(g, this.bodyOf(child), 0xff4d6d, 0.7));
    this.forChildren(this.ctx.getCombatTargets(), (child) => {
      if (!child.active) return;
      this.drawBody(g, this.bodyOf(child), 0xff4d6d, 0.9);
    });
    this.forChildren(this.ctx.getCollisionTiles(), (child) => this.drawBody(g, this.bodyOf(child), 0xff4d6d, 0.35));
  }

  private drawOcclusionBounds(g: Phaser.GameObjects.Graphics): void {
    this.forWorldObjects((object) => {
      const sourceFrame = object.getData('sourceFrame') as SourceFrameDimensions | undefined;
      const bounds = object.getData('occlusionBounds') as SourceOcclusionBounds | undefined;
      if (!sourceFrame || !bounds) return;
      const rectangle = resolveWorldOcclusionRectangle({
        x: object.x,
        y: object.y,
        originX: object.originX,
        originY: object.originY,
        scaleX: object.scaleX,
        scaleY: object.scaleY,
        flipX: object.flipX,
        flipY: object.flipY,
      }, sourceFrame, bounds);
      this.fillRect(g, rectangle.x, rectangle.y, rectangle.width, rectangle.height, 0x38bdf8, 0.08);
      this.strokeRect(g, rectangle.x, rectangle.y, rectangle.width, rectangle.height, 0x38bdf8, 0.95, 2);
    });
  }

  private drawDepthBounds(g: Phaser.GameObjects.Graphics): void {
    this.forWorldObjects((object) => {
      const sourceFrame = object.getData('sourceFrame') as SourceFrameDimensions | undefined;
      const bounds = object.getData('depthBounds') as SourceOcclusionBounds | undefined;
      if (!sourceFrame || !bounds) return;
      const visualOffset = object.getData('visualOffset') as { x: number; y: number } | undefined;
      const rectangle = resolveWorldOcclusionRectangle({
        x: object.x - (visualOffset?.x ?? 0) * Math.abs(object.scaleX),
        y: object.y - (visualOffset?.y ?? 0) * Math.abs(object.scaleY),
        originX: object.originX,
        originY: object.originY,
        scaleX: object.scaleX,
        scaleY: object.scaleY,
        flipX: object.flipX,
        flipY: object.flipY,
      }, sourceFrame, bounds);
      this.fillRect(g, rectangle.x, rectangle.y, rectangle.width, rectangle.height, 0xff9f43, 0.1);
      this.strokeRect(g, rectangle.x, rectangle.y, rectangle.width, rectangle.height, 0xff9f43, 0.95, 2);
      g.lineStyle(3, 0xff9f43, 1).lineBetween(
        rectangle.x,
        rectangle.y + rectangle.height,
        rectangle.x + rectangle.width,
        rectangle.y + rectangle.height,
      );
    });
  }

  private drawDepthAnchors(g: Phaser.GameObjects.Graphics): void {
    this.drawActorDepthAnchor(g, this.ctx.getPlayer(), 0x73d7ff, 0.95);
    this.forChildren(this.ctx.getFriends(), (child) => this.drawActorDepthAnchor(g, child, 0x73d7ff, 0.7));
    this.forChildren(this.ctx.getCombatTargets(), (child) => this.drawActorDepthAnchor(g, child, 0xa78bfa, 0.85));
    this.forWorldObjects((object) => {
      const x = object.getData('objectAnchorX') as number | undefined;
      const y = object.getData('depthAnchorY') as number | undefined;
      if (typeof x !== 'number' || typeof y !== 'number') return;
      this.drawDepthAnchor(g, x, y, 0xffd166, 0.95);
    });
    for (const entry of this.ctx.getHouses()) {
      this.drawDepthAnchor(g, entry.house.sprite.x, entry.house.getGroundAnchorY(), 0xffd166, 0.75);
    }
  }

  private drawInteractionZones(g: Phaser.GameObjects.Graphics): void {
    for (const entry of this.ctx.getHouses()) this.drawBody(g, this.bodyOf(entry.house.doorZone), 0x73e2b1, 0.9);
    for (const zone of this.ctx.getTransitionZones()) this.drawBody(g, this.bodyOf(zone), 0x73e2b1, 0.85);
    this.forChildren(this.ctx.getCollectibleTargets(), (child) => this.drawBody(g, this.bodyOf(child), 0x73e2b1, 0.75));
    this.forChildren(this.ctx.getDungeonSwitches(), (child) => this.drawBody(g, this.bodyOf(child), 0x73e2b1, 0.85));
    this.forChildren(this.ctx.getDungeonChests(), (child) => this.drawBody(g, this.bodyOf(child), 0x73e2b1, 0.85));
  }

  private drawActiveAttackHitboxes(g: Phaser.GameObjects.Graphics): void {
    for (const config of hitboxPool.getActiveConfigs(this.ctx.scene)) this.drawAttackShape(g, config);
  }

  private drawEnemyBoundaries(g: Phaser.GameObjects.Graphics): void {
    for (const area of this.ctx.getEnemySpawnAreas()) {
      this.drawEnemyPerimeter(g, area.pursuePerimeter, 0x5ee7ff, 0.06, 3);
      this.drawEnemyPerimeter(g, area.stayPerimeter, 0xffc65c, 0.08, 3);
    }
  }

  private drawEnemyPerimeter(
    g: Phaser.GameObjects.Graphics,
    perimeter: MapEnemyAreaPerimeter,
    color: number,
    fillAlpha: number,
    lineWidth: number,
  ): void {
    g.fillStyle(color, fillAlpha).lineStyle(lineWidth, color, 0.95);
    if (perimeter.shape === 'circle') {
      g.fillCircle(perimeter.x, perimeter.y, perimeter.radius);
      g.strokeCircle(perimeter.x, perimeter.y, perimeter.radius);
    } else {
      g.fillRect(perimeter.x, perimeter.y, perimeter.w, perimeter.h);
      g.strokeRect(perimeter.x, perimeter.y, perimeter.w, perimeter.h);
    }
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
      return;
    }
    if (config.shape === 'circle' || config.shape === 'ellipse') {
      const radiusX = config.radiusX ?? config.width / 2;
      const radiusY = config.radiusY ?? config.height / 2;
      g.fillStyle(0xa78bfa, 0.12).fillEllipse(config.x, config.y, radiusX * 2, radiusY * 2);
      g.lineStyle(3, 0xa78bfa, 0.95).strokeEllipse(config.x, config.y, radiusX * 2, radiusY * 2);
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

  private drawActorDepthAnchor(
    g: Phaser.GameObjects.Graphics,
    object: Phaser.GameObjects.GameObject | null | undefined,
    color: number,
    alpha: number,
  ): void {
    const body = this.bodyOf(object);
    if (!body) return;
    this.drawDepthAnchor(g, body.x + body.width / 2, resolveBodyBottom(body), color, alpha);
  }

  private drawDepthAnchor(g: Phaser.GameObjects.Graphics, x: number, y: number, color: number, alpha: number): void {
    this.fillRect(g, x - 5, y - 5, 10, 10, color, 0.16);
    this.strokeRect(g, x - 5, y - 5, 10, 10, color, alpha, 2);
    g.lineStyle(2, color, alpha).lineBetween(x - 14, y, x + 14, y);
  }

  private drawBody(g: Phaser.GameObjects.Graphics, body: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null | undefined, color: number, alpha: number): void {
    if (!body || !body.enable) return;
    if ('isCircle' in body && body.isCircle) {
      const radius = body.halfWidth;
      const centerX = body.center.x;
      const centerY = body.center.y;
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

  private forWorldObjects(callback: (object: Phaser.GameObjects.Image) => void): void {
    for (const child of this.ctx.scene.children.list) {
      const object = child as Phaser.GameObjects.Image;
      if (typeof object.getData('objectId') !== 'string') continue;
      callback(object);
    }
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

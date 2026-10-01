import Phaser from 'phaser';
import { hitboxPool, type HitboxConfig } from '../combat/Hitbox';
import { devToolsState } from '../devTools';
import type { MapEnemyAreaPerimeter, MapEnemySpawnArea } from '../content/maps/mapFormat';
import type { WorldDimensions } from '../world/WorldDimensions';
import {
  resolveBodyBottom,
  resolveExplicitDepth,
} from '../presentation/WorldDepth';
import type { SpriteBoundsGeometry } from '../infrastructure/phaser-nodes/Sprite2DNode';
import type { EnemyDebugAttackArea } from '../features/scripts/EnemyScript';
import { traceSensorShape } from '../features/effects/AttackTelegraphs';
import type { WeaponDebugSwing } from '../features/scripts/WeaponScript';
import type { DebugHurtbox } from '../features/world/UniversalSceneWorldController';

/** A finished swing stays on screen this long, so a 150 ms hit window can be seen. */
const SWING_LINGER_MS = 450;
const SWING_COLOR: Readonly<Record<WeaponDebugSwing['outcome'], number>> = { open: 0xffe14d, hit: 0x4dff88, refused: 0xff4d4d };
const HURTBOX_COLOR: Readonly<Record<DebugHurtbox['kind'], number>> = { player: 0x00e5ff, enemy: 0xff5fa2, boss: 0xff3df5 };

type DebugGroup = Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup;

/** A mounted world sprite (Sprite2DNode) as the overlay reads it. */
export interface DebugWorldVisual {
  readonly phaserObjectActive: boolean;
  readonly presentationObject: Phaser.GameObjects.Sprite;
  /** Sorts by its own ground point (objects), not a character body's depth anchor. */
  readonly selfSorted: boolean;
  boundsGeometry(): SpriteBoundsGeometry | undefined;
}

export interface WorldDebugContext {
  scene: Phaser.Scene;
  dimensions: WorldDimensions;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
  getTransitionZones: () => Phaser.GameObjects.Zone[];
  getEnemySpawnAreas: () => readonly MapEnemySpawnArea[];
  /** Live boss camp perimeters, resolved from the mounted encounter scenes. */
  getBossBattleAreas: () => readonly { readonly activation?: MapEnemyAreaPerimeter; readonly arena?: MapEnemyAreaPerimeter }[];
  /** Every mounted world sprite; object overlays (visual, occlusion, depth) are drawn from these. */
  getWorldVisuals: () => readonly DebugWorldVisual[];
  /** Authored enemy attack areas (contact, landing) with live target overlap. */
  getEnemyAttackAreas: () => readonly EnemyDebugAttackArea[];
  /** The slime's weapon swing while its hitboxes are open. */
  getWeaponSwing: () => WeaponDebugSwing | undefined;
  /** Where the slime, enemies and bosses take damage. */
  getHurtboxes: () => readonly DebugHurtbox[];
}

export class WorldDebugRenderer {
  private graphics?: Phaser.GameObjects.Graphics;
  private readonly labels: Phaser.GameObjects.Text[] = [];
  private usedLabels = 0;
  private lastSwing?: { readonly swing: WeaponDebugSwing; readonly until: number };

  constructor(private readonly ctx: WorldDebugContext) {}

  update(): void {
    if (!import.meta.env.DEV) return;
    const g = this.graphics ?? this.ctx.scene.add.graphics()
      .setDepth(resolveExplicitDepth('editor-template-overlay', 10))
      .setScrollFactor(1);
    this.graphics = g;
    g.clear();
    this.usedLabels = 0;
    if (!devToolsState.enabled) {
      g.setVisible(false);
      this.hideUnusedLabels();
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
    if (devToolsState.hurtboxes) this.drawHurtboxes(g);
    if (devToolsState.enemyBoundaries) this.drawEnemyBoundaries(g);
    if (devToolsState.bossBattleAreas) this.drawBossBattleAreas(g);
    if (devToolsState.enemyAttackAreas) this.drawEnemyAttackAreas(g);
    this.hideUnusedLabels();
  }

  destroy(): void {
    this.graphics?.destroy();
    this.graphics = undefined;
    for (const label of this.labels) label.destroy();
    this.labels.length = 0;
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
    this.forChildren(this.ctx.getCombatTargets(), (child) => this.drawObjectBounds(g, child, 0x72d8ff, 0.85));
    this.forWorldObjects((visual) => { if (visual.selfSorted) this.drawObjectBounds(g, visual.presentationObject, 0x72d8ff, 0.75); });
  }

  /** Every enabled Arcade body: scene-tree bodies are registered with the world, not with a scene group. */
  private drawHitBoxes(g: Phaser.GameObjects.Graphics): void {
    const world = this.ctx.scene.physics.world;
    for (const body of world.staticBodies.entries) this.drawBody(g, body, 0xff4d6d, 0.7);
    for (const body of world.bodies.entries) this.drawBody(g, body, 0xff4d6d, 0.95);
  }

  private drawOcclusionBounds(g: Phaser.GameObjects.Graphics): void {
    this.forWorldObjects((visual) => {
      const rectangle = visual.boundsGeometry()?.occlusion;
      if (!rectangle) return;
      this.fillRect(g, rectangle.x, rectangle.y, rectangle.width, rectangle.height, 0x38bdf8, 0.08);
      this.strokeRect(g, rectangle.x, rectangle.y, rectangle.width, rectangle.height, 0x38bdf8, 0.95, 2);
    });
  }

  private drawDepthBounds(g: Phaser.GameObjects.Graphics): void {
    this.forWorldObjects((visual) => {
      const rectangle = visual.boundsGeometry()?.depth;
      if (!rectangle) return;
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
    this.forChildren(this.ctx.getCombatTargets(), (child) => this.drawActorDepthAnchor(g, child, 0xa78bfa, 0.85));
    this.forWorldObjects((visual) => {
      if (!visual.selfSorted) return;
      const anchor = visual.boundsGeometry()?.anchor;
      if (anchor) this.drawDepthAnchor(g, anchor.x, anchor.y, 0xffd166, 0.95);
    });
  }

  private drawInteractionZones(g: Phaser.GameObjects.Graphics): void {
    for (const zone of this.ctx.getTransitionZones()) this.drawBody(g, this.bodyOf(zone), 0x73e2b1, 0.85);
  }

  /**
   * The slime's weapon swing (its authored hitbox shapes while a hit window is
   * open, lingering briefly): yellow while open, green once it hit something,
   * red when every touch was refused (wrong weapon, a guarding boss). Also the
   * legacy pool (Squash Slam on training dummies).
   */
  private drawActiveAttackHitboxes(g: Phaser.GameObjects.Graphics): void {
    for (const config of hitboxPool.getActiveConfigs(this.ctx.scene)) this.drawAttackShape(g, config);
    const now = this.ctx.scene.time.now;
    const swing = this.ctx.getWeaponSwing();
    if (swing) this.lastSwing = { swing, until: now + SWING_LINGER_MS };
    if (!this.lastSwing || now > this.lastSwing.until) return;
    const fade = swing ? 1 : Math.max(0.25, (this.lastSwing.until - now) / SWING_LINGER_MS);
    const color = SWING_COLOR[this.lastSwing.swing.outcome];
    g.fillStyle(color, 0.22 * fade).lineStyle(3, color, 0.95 * fade);
    for (const shape of this.lastSwing.swing.shapes) traceSensorShape(g, shape);
  }

  /** Where things take damage: the slime in cyan, enemies in pink, bosses in magenta with the weapons they accept. */
  private drawHurtboxes(g: Phaser.GameObjects.Graphics): void {
    for (const hurtbox of this.ctx.getHurtboxes()) {
      const color = HURTBOX_COLOR[hurtbox.kind];
      const boss = hurtbox.kind === 'boss';
      g.fillStyle(color, boss ? 0.3 : 0.16).lineStyle(boss ? 3 : 2, color, 1);
      for (const shape of hurtbox.shapes) traceSensorShape(g, shape);
      const first = hurtbox.shapes[0];
      if (!boss || !first) continue;
      const top = first.shape === 'rectangle' ? { x: first.x + first.width / 2, y: first.y }
        : first.shape === 'circle' ? { x: first.centerX, y: first.centerY - first.radius }
          : 'centerX' in first ? { x: first.centerX, y: first.centerY - ('radiusY' in first ? first.radiusY : 0) } : undefined;
      if (top) this.label(top.x, top.y - 6, hurtbox.accepts ? `HURTBOX · ${hurtbox.accepts}` : 'HURTBOX', color);
    }
  }

  private label(x: number, y: number, text: string, color: number): void {
    let label = this.labels[this.usedLabels];
    if (!label) {
      label = this.ctx.scene.add.text(0, 0, '', { fontFamily: 'monospace', fontSize: '11px', fontStyle: 'bold', backgroundColor: '#081022cc', padding: { x: 3, y: 1 } })
        .setOrigin(0.5, 1)
        .setDepth(resolveExplicitDepth('editor-template-overlay', 11));
      this.labels.push(label);
    }
    this.usedLabels += 1;
    label.setText(text).setColor(`#${color.toString(16).padStart(6, '0')}`).setPosition(x, y).setVisible(true);
  }

  private hideUnusedLabels(): void {
    for (let index = this.usedLabels; index < this.labels.length; index += 1) this.labels[index]!.setVisible(false);
  }

  private drawEnemyBoundaries(g: Phaser.GameObjects.Graphics): void {
    for (const area of this.ctx.getEnemySpawnAreas()) {
      this.drawEnemyPerimeter(g, area.pursuePerimeter, 0x5ee7ff, 0.06, 3);
      this.drawEnemyPerimeter(g, area.stayPerimeter, 0xffc65c, 0.08, 3);
    }
  }

  private drawBossBattleAreas(g: Phaser.GameObjects.Graphics): void {
    for (const camp of this.ctx.getBossBattleAreas()) {
      if (camp.activation) this.drawEnemyPerimeter(g, camp.activation, 0x40e0d0, 0.045, 3);
      if (camp.arena) this.drawEnemyPerimeter(g, camp.arena, 0xffb84d, 0.07, 3);
    }
  }

  /** Landing zones in blue, other attack areas in amber; any area the player overlaps turns red. */
  private drawEnemyAttackAreas(g: Phaser.GameObjects.Graphics): void {
    for (const area of this.ctx.getEnemyAttackAreas()) {
      const color = area.overlapsTarget ? 0xff3b3b : area.reference === 'landingZone' ? 0x4da3ff : 0xffb020;
      g.fillStyle(color, area.overlapsTarget ? 0.18 : 0.07).lineStyle(2, color, 0.95);
      for (const shape of area.shapes) traceSensorShape(g, shape);
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

  private forWorldObjects(callback: (visual: DebugWorldVisual) => void): void {
    for (const visual of this.ctx.getWorldVisuals()) {
      if (visual.phaserObjectActive && visual.presentationObject.visible) callback(visual);
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

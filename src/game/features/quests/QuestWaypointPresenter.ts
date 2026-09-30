import type Phaser from 'phaser';

import { UI_THEME } from '../../presentation/theme';
import type { QuestWaypointTarget, WaypointPoint } from './QuestWaypoint';

/** Draw above every world object, like the Gulp hints. */
const WAYPOINT_DEPTH = 9_000_000_001;
const ARROW_RADIUS = 72;
const GOLD = 0xffd277;
const INK = 0x081022;
/** World pixels per displayed metre (one ground tile). */
const PIXELS_PER_METRE = 64;
/** The marker replaces the arrow once the target is this far inside the view. */
const VIEW_INSET = 48;

/**
 * The quest waypoint: a gold arrow circling the slime toward the next quest
 * place, with the distance, and a bobbing marker over the place itself once it
 * is on screen. Placeholder art until the waypoint arrow asset lands.
 */
export class QuestWaypointPresenter {
  private readonly arrow: Phaser.GameObjects.Graphics;
  private readonly marker: Phaser.GameObjects.Graphics;
  private readonly distance: Phaser.GameObjects.Text;
  private readonly label: Phaser.GameObjects.Text;
  private elapsed = 0;

  constructor(private readonly scene: Phaser.Scene) {
    const style = {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '12px',
      color: '#ffe8a8',
      stroke: UI_THEME.colors.shadow,
      strokeThickness: 4,
    };
    this.arrow = scene.add.graphics().setDepth(WAYPOINT_DEPTH).setVisible(false);
    this.marker = scene.add.graphics().setDepth(WAYPOINT_DEPTH).setVisible(false);
    this.distance = scene.add.text(0, 0, '', style).setOrigin(0.5, 0.5).setDepth(WAYPOINT_DEPTH).setVisible(false);
    this.label = scene.add.text(0, 0, '', { ...style, fontSize: '13px' }).setOrigin(0.5, 1).setDepth(WAYPOINT_DEPTH).setVisible(false);
    this.drawArrow();
    this.drawMarker();
  }

  update(deltaMs: number, player: WaypointPoint | undefined, target: QuestWaypointTarget | undefined): void {
    this.elapsed += deltaMs;
    if (!player || !target) { this.hide(); return; }
    const camera = this.scene.cameras.main;
    const view = camera.worldView;
    const onScreen = target.x > view.x + VIEW_INSET && target.x < view.right - VIEW_INSET
      && target.y > view.y + VIEW_INSET && target.y < view.bottom - VIEW_INSET;
    const pulse = 0.5 + 0.5 * Math.sin(this.elapsed / 220);
    const bob = Math.sin(this.elapsed / 260) * 5;
    this.marker.setVisible(true).setPosition(target.x, target.y - 58 + bob).setAlpha(0.8 + 0.2 * pulse);
    this.label.setVisible(onScreen).setText(target.label).setPosition(target.x, target.y - 86 + bob);
    const dx = target.x - player.x;
    const dy = target.y - player.y;
    const metres = Math.round(Math.hypot(dx, dy) / PIXELS_PER_METRE);
    const showArrow = !onScreen && metres > 1;
    if (!showArrow) {
      this.arrow.setVisible(false);
      this.distance.setVisible(false);
      return;
    }
    const angle = Math.atan2(dy, dx);
    const radius = ARROW_RADIUS + pulse * 6;
    this.arrow.setVisible(true).setPosition(player.x + Math.cos(angle) * radius, player.y - 16 + Math.sin(angle) * radius).setRotation(angle);
    this.distance.setVisible(true).setText(`${metres} m`)
      .setPosition(player.x + Math.cos(angle) * (radius + 30), player.y - 16 + Math.sin(angle) * (radius + 30));
  }

  hide(): void {
    this.arrow.setVisible(false);
    this.marker.setVisible(false);
    this.distance.setVisible(false);
    this.label.setVisible(false);
  }

  destroy(): void {
    this.arrow.destroy();
    this.marker.destroy();
    this.distance.destroy();
    this.label.destroy();
  }

  /** A chevron pointing along +x, drawn around its tip's base. */
  private drawArrow(): void {
    const g = this.arrow;
    g.fillStyle(INK, 0.85);
    g.fillTriangle(20, 0, -12, -15, -12, 15);
    g.fillStyle(GOLD, 1);
    g.fillTriangle(16, 0, -9, -11, -9, 11);
    g.fillStyle(INK, 0.9);
    g.fillTriangle(-1, 0, -10, -6, -10, 6);
  }

  /** A downward pin: a ring with a point below, over the target. */
  private drawMarker(): void {
    const g = this.marker;
    g.fillStyle(INK, 0.85);
    g.fillCircle(0, 0, 13);
    g.fillTriangle(-9, 7, 9, 7, 0, 24);
    g.fillStyle(GOLD, 1);
    g.fillCircle(0, 0, 10);
    g.fillTriangle(-6, 6, 6, 6, 0, 20);
    g.fillStyle(INK, 1);
    g.fillCircle(0, 0, 4);
  }
}

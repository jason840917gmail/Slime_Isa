import type Phaser from 'phaser';

import { GULP_FORM_ICON_TEXTURE, type GulpFormDefinition } from '../../content/gulp/gulpForms';
import { UI_THEME } from '../../presentation/theme';
import type { GulpPoint, GulpSpot } from './GulpController';

/** Draw above every world object: the texts float over the player and spots. */
const HUD_DEPTH = 9_000_000_000;

const BADGE_SIZE = 36;

/**
 * Gulp presentation: the form's badge and time left float over the slime
 * ("[badge] 0:42"), and a "[W] Gulp" hint floats over the Gulp spot in reach.
 */
export class GulpHud {
  private readonly timer: Phaser.GameObjects.Text;
  private readonly badge: Phaser.GameObjects.Image;
  private readonly hint: Phaser.GameObjects.Text;

  constructor(scene: Phaser.Scene) {
    const style = {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '14px',
      color: UI_THEME.colors.text,
      stroke: UI_THEME.colors.shadow,
      strokeThickness: 4,
    };
    this.timer = scene.add.text(0, 0, '', style).setOrigin(0, 1).setDepth(HUD_DEPTH).setVisible(false);
    this.badge = scene.add.image(0, 0, GULP_FORM_ICON_TEXTURE, 0).setOrigin(1, 1).setDepth(HUD_DEPTH).setVisible(false);
    this.badge.setScale(BADGE_SIZE / Math.max(this.badge.width, 1));
    this.hint = scene.add.text(0, 0, '[W] Gulp', { ...style, color: '#ffe89a' }).setOrigin(0.5, 1).setDepth(HUD_DEPTH).setVisible(false);
  }

  update(player: GulpPoint, form: GulpFormDefinition | undefined, remainingMs: number, spot: GulpSpot | undefined): void {
    if (form) {
      const seconds = Math.ceil(remainingMs / 1000);
      const time = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
      const hasBadge = this.badge.scene.textures.exists(GULP_FORM_ICON_TEXTURE);
      // Without its badge art the timer still names the form.
      this.timer.setText(hasBadge ? time : `${form.name.toUpperCase()} ${time}`);
      const width = this.timer.width + (hasBadge ? BADGE_SIZE + 4 : 0);
      const left = player.x - width / 2;
      if (hasBadge) this.badge.setFrame(form.iconFrame).setPosition(left + BADGE_SIZE, player.y - 70).setVisible(true);
      this.timer.setPosition(left + (hasBadge ? BADGE_SIZE + 4 : 0), player.y - 76).setVisible(true);
    } else {
      this.timer.setVisible(false);
      this.badge.setVisible(false);
    }
    if (spot) this.hint.setPosition(spot.x, spot.y - (spot.badgeRise ?? 80)).setVisible(true);
    else this.hint.setVisible(false);
  }

  destroy(): void {
    this.timer.destroy();
    this.badge.destroy();
    this.hint.destroy();
  }
}

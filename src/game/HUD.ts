import Phaser from 'phaser';
import { gameEvents } from './core/EventBus';
import { gameState } from './core/GameState';
import { UI_THEME } from './presentation/theme';
import { resolveScreenUiDepth } from './presentation/WorldDepth';

/**
 * Heads-up display. Event-driven: subscribes to GameState changes via
 * EventBus. Now includes HP bar, XP bar, level, and energy readouts.
 *
 * Layout (screen-space, top-left):
 *   Level + coins + friends (text)
 *   HP bar (redâ†’green) under the text
 *   XP bar (cyan) under HP
 *   Energy bar (yellow) under XP
 */
export class HUD {
  private coinsText: Phaser.GameObjects.Text;
  private friendCountText: Phaser.GameObjects.Text;
  private levelText: Phaser.GameObjects.Text;
  private hpBar: Phaser.GameObjects.Graphics;
  private xpBar: Phaser.GameObjects.Graphics;
  private energyBar: Phaser.GameObjects.Graphics;
  private hpLabel: Phaser.GameObjects.Text;
  private xpLabel: Phaser.GameObjects.Text;
  private energyLabel: Phaser.GameObjects.Text;

  private readonly barX = 24;
  private readonly barW = 220;
  private readonly barH = 12;
  private readonly barGap = 18;

  constructor(scene: Phaser.Scene) {
    const font = UI_THEME.fontFamily;

    let y = 24;
    this.levelText = scene.add
      .text(this.barX, y, `Level ${gameState.level}`, {
        fontFamily: font,
        fontSize: '16px',
        color: '#a3f0c0',
        stroke: '#081022',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(0)) as Phaser.GameObjects.Text;

    y += 22;
    this.coinsText = scene.add
      .text(this.barX, y, `Coins: ${gameState.coins}`, {
        fontFamily: font,
        fontSize: '16px',
        color: '#ffd277',
        stroke: '#081022',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(0)) as Phaser.GameObjects.Text;

    y += 22;
    this.friendCountText = scene.add
      .text(this.barX, y, `Friends: ${gameState.totalFriends}`, {
        fontFamily: font,
        fontSize: '16px',
        color: '#ffd277',
        stroke: '#081022',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(0)) as Phaser.GameObjects.Text;

    y += 26;
    this.hpBar = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(1));
    this.hpLabel = scene.add
      .text(this.barX, y, '', { fontFamily: font, fontSize: '11px', color: '#f5f7ff', stroke: '#0b1020', strokeThickness: 3 })
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(2)) as Phaser.GameObjects.Text;
    this.hpLabel.setPosition(this.barX + this.barW + 8, y);
    y += this.barH + this.barGap;

    this.xpBar = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(3));
    this.xpLabel = scene.add
      .text(this.barX, y, '', { fontFamily: font, fontSize: '11px', color: '#cfe6ff', stroke: '#0b1020', strokeThickness: 3 })
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(4)) as Phaser.GameObjects.Text;
    this.xpLabel.setPosition(this.barX + this.barW + 8, y);
    y += this.barH + this.barGap;

    this.energyBar = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(5));
    this.energyLabel = scene.add
      .text(this.barX, y, '', { fontFamily: font, fontSize: '11px', color: '#ffdf8a', stroke: '#0b1020', strokeThickness: 3 })
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(6)) as Phaser.GameObjects.Text;
    this.energyLabel.setPosition(this.barX + this.barW + 8, y);

    gameEvents.on('coins.changed', this.onCoinsChanged, this);
    gameEvents.on('friend.count', this.onFriendCountChanged, this);
    gameEvents.on('hp.changed', this.onHpChanged, this);
    gameEvents.on('xp.changed', this.onXpChanged, this);
    gameEvents.on('energy.changed', this.onEnergyChanged, this);
    gameEvents.on('level.up', this.onLevelUp, this);

    this.drawHp(gameState.hp, gameState.maxHp);
    this.drawXp(0, 0, gameState.level);
    this.drawEnergy(gameState.energy, gameState.maxEnergy);
  }

  updateCoins(coins: number): void {
    this.coinsText.setText(`Coins: ${coins}`);
  }

  updateFriendCount(count: number): void {
    this.friendCountText.setText(`Friends: ${count}`);
  }

  updateLevel(level: number): void {
    this.levelText.setText(`Level ${level}`);
  }

  flashCoins(scene: Phaser.Scene): void {
    scene.tweens.add({ targets: this.coinsText, scale: 1.08, duration: 120, yoyo: true });
  }

  private drawHp(hp: number, maxHp: number): void {
    const g = this.hpBar;
    const { barX, barW, barH } = this;
    const y = this.hpBarY();
    g.clear();
    g.fillStyle(0x0b1020, 0.9);
    g.fillRoundedRect(barX, y, barW, barH, 4);
    g.lineStyle(1.5, 0x3b5c78, 0.9);
    g.strokeRoundedRect(barX, y, barW, barH, 4);

    const pct = maxHp > 0 ? Phaser.Math.Clamp(hp / maxHp, 0, 1) : 0;
    const fill = pct <= 0.25 ? 0xff6f88 : pct <= 0.5 ? 0xffad66 : 0x7be08a;
    g.fillStyle(fill, 1);
    g.fillRoundedRect(barX + 1, y + 1, Math.max(0, (barW - 2) * pct), barH - 2, 3);

    this.hpLabel.setText(`${Math.ceil(hp)} / ${maxHp}`);
  }

  private drawXp(into: number, need: number, level: number): void {
    const g = this.xpBar;
    const { barX, barW, barH } = this;
    const y = this.xpBarY();
    g.clear();
    g.fillStyle(0x0b1020, 0.9);
    g.fillRoundedRect(barX, y, barW, barH, 4);
    g.lineStyle(1.5, 0x3b5c78, 0.9);
    g.strokeRoundedRect(barX, y, barW, barH, 4);

    const pct = need > 0 ? Phaser.Math.Clamp(into / need, 0, 1) : 0;
    g.fillStyle(0x72d8ff, 1);
    g.fillRoundedRect(barX + 1, y + 1, Math.max(0, (barW - 2) * pct), barH - 2, 3);

    this.xpLabel.setText(need > 0 ? `${Math.floor(into)} / ${need}` : `MAX`);
    this.updateLevel(level);
  }

  private drawEnergy(energy: number, maxEnergy: number): void {
    const g = this.energyBar;
    const { barX, barW, barH } = this;
    const y = this.energyBarY();
    g.clear();
    g.fillStyle(0x0b1020, 0.9);
    g.fillRoundedRect(barX, y, barW, barH, 4);
    g.lineStyle(1.5, 0x3b5c78, 0.9);
    g.strokeRoundedRect(barX, y, barW, barH, 4);

    const pct = maxEnergy > 0 ? Phaser.Math.Clamp(energy / maxEnergy, 0, 1) : 0;
    g.fillStyle(0xffdf8a, 1);
    g.fillRoundedRect(barX + 1, y + 1, Math.max(0, (barW - 2) * pct), barH - 2, 3);

    this.energyLabel.setText(`${Math.ceil(energy)} / ${maxEnergy}`);
  }

  private hpBarY(): number {
    return 24 + 22 + 22 + 26;
  }
  private xpBarY(): number {
    return this.hpBarY() + this.barH + this.barGap;
  }
  private energyBarY(): number {
    return this.xpBarY() + this.barH + this.barGap;
  }

  private onCoinsChanged = (payload: { coins: number }): void => this.updateCoins(payload.coins);
  private onFriendCountChanged = (payload: { count: number }): void => this.updateFriendCount(payload.count);
  private onHpChanged = (payload: { hp: number; maxHp: number }): void => this.drawHp(payload.hp, payload.maxHp);
  private onXpChanged = (payload: { xpIntoLevel: number; xpForNext: number; level: number }): void => {
    this.drawXp(payload.xpIntoLevel, payload.xpForNext, payload.level);
  };
  private onEnergyChanged = (payload: { energy: number; maxEnergy: number }): void => {
    this.drawEnergy(payload.energy, payload.maxEnergy);
  };
  private onLevelUp = (payload: { level: number }): void => this.updateLevel(payload.level);

  destroy(): void {
    gameEvents.off('coins.changed', this.onCoinsChanged, this);
    gameEvents.off('friend.count', this.onFriendCountChanged, this);
    gameEvents.off('hp.changed', this.onHpChanged, this);
    gameEvents.off('xp.changed', this.onXpChanged, this);
    gameEvents.off('energy.changed', this.onEnergyChanged, this);
    gameEvents.off('level.up', this.onLevelUp, this);
    this.coinsText.destroy();
    this.friendCountText.destroy();
    this.levelText.destroy();
    this.hpBar.destroy();
    this.xpBar.destroy();
    this.energyBar.destroy();
    this.hpLabel.destroy();
    this.xpLabel.destroy();
    this.energyLabel.destroy();
  }
}

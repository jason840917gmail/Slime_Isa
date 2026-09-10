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
 *   Level + coins (text)
 *   HP bar (red-to-green) under the text
 *   XP bar (cyan) under HP
 *   Energy bar (yellow) under XP
 */
export class HUD {
  private readonly scene: Phaser.Scene;
  private coinsText: Phaser.GameObjects.Text;
  private levelText: Phaser.GameObjects.Text;
  private hpBar: Phaser.GameObjects.Graphics;
  private xpBar: Phaser.GameObjects.Graphics;
  private energyBar: Phaser.GameObjects.Graphics;
  private hpLabel: Phaser.GameObjects.Text;
  private xpLabel: Phaser.GameObjects.Text;
  private energyLabel: Phaser.GameObjects.Text;
  private xpIntoLevel = gameState.currentXp;
  private xpForNext: number | null = gameState.xpToNextLevel;
  private currentLevel = gameState.level;

  private barX = 24;
  private barW = 220;
  private statsW = 220;
  private readonly barH = 8;
  private readonly barGap = 11;

  private static readonly HUD_MARGIN = 16;
  private static readonly STATS_MIN_WIDTH = 180;
  private static readonly STATS_MAX_WIDTH = 260;
  private static readonly METER_LABEL_GAP = 8;
  private static readonly METER_LABEL_WIDTH = 62;
  private static readonly LEVEL_Y = 18;
  private static readonly METER_TOP_Y = 42;

  constructor(scene: Phaser.Scene) {
    this.scene = scene;
    const font = UI_THEME.fontFamily;

    this.levelText = scene.add
      .text(this.barX, HUD.LEVEL_Y, `Level ${gameState.level}`, {
        fontFamily: font,
        fontSize: '14px',
        fontStyle: 'bold',
        color: '#a3f0c0',
      })
      .setOrigin(0, 0)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(0))
      .setShadow(0, 2, UI_THEME.colors.shadow, 2, true, true) as Phaser.GameObjects.Text;

    this.coinsText = scene.add
      .text(0, HUD.LEVEL_Y, `Coins ${formatHudCount(gameState.coins)}`, {
        fontFamily: font,
        fontSize: '12px',
        fontStyle: 'bold',
        color: '#ffd277',
      })
      .setOrigin(1, 0)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(0))
      .setShadow(0, 2, UI_THEME.colors.shadow, 2, true, true) as Phaser.GameObjects.Text;

    this.hpBar = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(1));
    this.hpLabel = scene.add
      .text(0, 0, '', { fontFamily: font, fontSize: '10px', color: '#f5f7ff' })
      .setOrigin(0, 0.5)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(2))
      .setShadow(0, 1, UI_THEME.colors.shadow, 2, true, true) as Phaser.GameObjects.Text;

    this.xpBar = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(3));
    this.xpLabel = scene.add
      .text(0, 0, '', { fontFamily: font, fontSize: '10px', color: '#cfe6ff' })
      .setOrigin(0, 0.5)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(4))
      .setShadow(0, 1, UI_THEME.colors.shadow, 2, true, true) as Phaser.GameObjects.Text;

    this.energyBar = scene.add.graphics().setScrollFactor(0).setDepth(resolveScreenUiDepth(5));
    this.energyLabel = scene.add
      .text(0, 0, '', { fontFamily: font, fontSize: '10px', color: '#ffdf8a' })
      .setOrigin(0, 0.5)
      .setScrollFactor(0)
      .setDepth(resolveScreenUiDepth(6))
      .setShadow(0, 1, UI_THEME.colors.shadow, 2, true, true) as Phaser.GameObjects.Text;

    gameEvents.on('coins.changed', this.onCoinsChanged, this);
    gameEvents.on('hp.changed', this.onHpChanged, this);
    gameEvents.on('xp.changed', this.onXpChanged, this);
    gameEvents.on('energy.changed', this.onEnergyChanged, this);
    gameEvents.on('level.up', this.onLevelUp, this);

    this.drawHp(gameState.hp, gameState.maxHp);
    this.drawXp(this.xpIntoLevel, this.xpForNext, this.currentLevel);
    this.drawEnergy(gameState.energy, gameState.maxEnergy);
    this.resize(scene.scale.width || scene.cameras.main.width);
    scene.scale.on('resize', this.handleResize, this);
  }

  resize(viewWidth: number): void {
    this.barX = Phaser.Math.Clamp(viewWidth * 0.03, HUD.HUD_MARGIN, 24);
    this.statsW = Phaser.Math.Clamp(viewWidth * 0.28, HUD.STATS_MIN_WIDTH, HUD.STATS_MAX_WIDTH);
    const maxBarWidth = viewWidth - this.barX - HUD.HUD_MARGIN
      - HUD.METER_LABEL_GAP - HUD.METER_LABEL_WIDTH;
    this.barW = Phaser.Math.Clamp(
      Math.min(viewWidth * 0.22, Math.max(132, maxBarWidth)),
      132,
      220,
    );

    this.levelText.setPosition(this.barX, HUD.LEVEL_Y);
    this.coinsText.setPosition(this.barX + this.statsW, HUD.LEVEL_Y);
    this.hpLabel.setPosition(this.barX + this.barW + HUD.METER_LABEL_GAP, this.hpBarY());
    this.xpLabel.setPosition(this.barX + this.barW + HUD.METER_LABEL_GAP, this.xpBarY());
    this.energyLabel.setPosition(this.barX + this.barW + HUD.METER_LABEL_GAP, this.energyBarY());

    this.drawHp(gameState.hp, gameState.maxHp);
    this.drawXp(this.xpIntoLevel, this.xpForNext, this.currentLevel);
    this.drawEnergy(gameState.energy, gameState.maxEnergy);
  }

  updateCoins(coins: number): void {
    this.coinsText.setText(`Coins ${formatHudCount(coins)}`);
  }

  updateLevel(level: number): void {
    this.currentLevel = level;
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
    this.drawTrack(g, y);

    const pct = maxHp > 0 ? Phaser.Math.Clamp(hp / maxHp, 0, 1) : 0;
    const fill = pct <= 0.25 ? 0xff6f88 : pct <= 0.5 ? 0xffad66 : 0x7be08a;
    g.fillStyle(fill, 1);
    g.fillRoundedRect(barX + 1, y + 1, Math.max(0, (barW - 2) * pct), barH - 2, 3);

    this.hpLabel.setText(`${Math.ceil(hp)} / ${maxHp}`);
  }

  private drawXp(into: number, need: number | null, level: number): void {
    this.xpIntoLevel = into;
    this.xpForNext = need;
    const g = this.xpBar;
    const { barX, barW, barH } = this;
    const y = this.xpBarY();
    g.clear();
    this.drawTrack(g, y);

    const pct = need !== null && need > 0 ? Phaser.Math.Clamp(into / need, 0, 1) : 0;
    g.fillStyle(0x72d8ff, 1);
    g.fillRoundedRect(barX + 1, y + 1, Math.max(0, (barW - 2) * pct), barH - 2, 3);

    this.xpLabel.setText(need !== null ? `${Math.floor(into)} / ${need}` : 'MAX');
    this.updateLevel(level);
  }

  private drawEnergy(energy: number, maxEnergy: number): void {
    const g = this.energyBar;
    const { barX, barW, barH } = this;
    const y = this.energyBarY();
    g.clear();
    this.drawTrack(g, y);

    const pct = maxEnergy > 0 ? Phaser.Math.Clamp(energy / maxEnergy, 0, 1) : 0;
    g.fillStyle(0xffdf8a, 1);
    g.fillRoundedRect(barX + 1, y + 1, Math.max(0, (barW - 2) * pct), barH - 2, 3);

    this.energyLabel.setText(`${Math.ceil(energy)} / ${maxEnergy}`);
  }

  private hpBarY(): number {
    return HUD.METER_TOP_Y;
  }
  private xpBarY(): number {
    return this.hpBarY() + this.barH + this.barGap;
  }
  private energyBarY(): number {
    return this.xpBarY() + this.barH + this.barGap;
  }

  private drawTrack(g: Phaser.GameObjects.Graphics, y: number): void {
    g.lineStyle(1, 0xe4f1d8, 0.72);
    g.strokeRoundedRect(this.barX + 0.5, y + 0.5, this.barW - 1, this.barH - 1, 4);
  }

  private handleResize = (size: Phaser.Structs.Size): void => {
    this.resize(size.width);
  };

  private onCoinsChanged = (payload: { coins: number }): void => this.updateCoins(payload.coins);
  private onHpChanged = (payload: { hp: number; maxHp: number }): void => this.drawHp(payload.hp, payload.maxHp);
  private onXpChanged = (payload: { currentXp: number; xpToNextLevel: number | null; level: number }): void => {
    this.drawXp(payload.currentXp, payload.xpToNextLevel, payload.level);
  };
  private onEnergyChanged = (payload: { energy: number; maxEnergy: number }): void => {
    this.drawEnergy(payload.energy, payload.maxEnergy);
  };
  private onLevelUp = (payload: { level: number }): void => this.updateLevel(payload.level);

  destroy(): void {
    this.scene.scale.off('resize', this.handleResize, this);
    gameEvents.off('coins.changed', this.onCoinsChanged, this);
    gameEvents.off('hp.changed', this.onHpChanged, this);
    gameEvents.off('xp.changed', this.onXpChanged, this);
    gameEvents.off('energy.changed', this.onEnergyChanged, this);
    gameEvents.off('level.up', this.onLevelUp, this);
    this.coinsText.destroy();
    this.levelText.destroy();
    this.hpBar.destroy();
    this.xpBar.destroy();
    this.energyBar.destroy();
    this.hpLabel.destroy();
    this.xpLabel.destroy();
    this.energyLabel.destroy();
  }
}

function formatHudCount(value: number): string {
  const count = Math.max(0, Math.floor(value));
  if (count < 10_000) return count.toLocaleString('en-US');
  if (count < 1_000_000) return `${Math.min(999.9, count / 1_000).toFixed(1)}k`;
  if (count < 1_000_000_000) return `${Math.min(999.9, count / 1_000_000).toFixed(1)}m`;
  return '999m+';
}

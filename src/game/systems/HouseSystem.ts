import Phaser from 'phaser';
import { House } from '../House';
import { gameState } from '../core/GameState';
import { gameEvents } from '../core/EventBus';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';

/**
 * Extracted from WorldScene (AGENTS.md flagged HouseUI + EnterPrompt + Sleep as
 * the next extraction target). Owns all house interaction: enter/leave UI,
 * "Press F to enter" prompt, proximity detection, and the sleep-at-bed flow.
 *
 * Behavior is preserved exactly from the original WorldScene implementation;
 * only the coin mutation now flows through GameState + EventBus.
 */

export interface HouseSystemContext {
  scene: Phaser.Scene;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getHouses: () => Array<{ owner: 'player' | 'friend'; house: House }>;
  isActionLocked: () => boolean;
  setActionLocked: (locked: boolean) => void;
  playIdle: () => void;
  defaultZoom: number;
  houseZoom: number;
}

const ENTER_PROMPT_THRESHOLD = 96;
const FONT = 'Aptos, Segoe UI Variable, sans-serif';

export class HouseSystem {
  private ctx: HouseSystemContext;
  private insideHouse = false;
  private currentHouse: House | null = null;
  private houseUI?: Phaser.GameObjects.Container;
  private nearHouse: House | null = null;
  private enterPrompt?: Phaser.GameObjects.Text | null;

  constructor(ctx: HouseSystemContext) {
    this.ctx = ctx;
  }

  update(): void {
    this.updateHousePrompt();

    if (this.enterPrompt) {
      const player = this.ctx.getPlayer();
      this.enterPrompt.setPosition(player.x, player.y - 40);
    }
  }

  getNearHouse(): House | null {
    return this.nearHouse;
  }

  isInside(): boolean {
    return this.insideHouse;
  }

  getCurrentHouse(): House | null {
    return this.currentHouse;
  }

  /** Sets the near-house hint from an external overlap (door zone physics). */
  notifyNear(house: House): void {
    this.nearHouse = house;
    this.showEnterPrompt();
  }

  /**
   * Handles the interact (F) key. Returns true if a house/sleep action was
   * performed, false if the caller should fall through to the shop.
   */
  handleInteract(): boolean {
    if (this.insideHouse) {
      if (this.houseUI) {
        this.closeHouse();
      } else if (this.currentHouse) {
        this.showHouseUI(this.currentHouse);
      }
      return true;
    }

    if (this.tryEnterHouseNearby()) return true;
    if (this.trySleepNearby()) return true;

    return false;
  }

  private updateHousePrompt(): void {
    const player = this.ctx.getPlayer();
    const houses = this.ctx.getHouses();
    if (!player || houses.length === 0) return;

    let best: { house: House; d: number } | null = null;

    for (const e of houses) {
      const door = e.house.getDoorPosition();
      const d = Phaser.Math.Distance.Between(player.x, player.y, door.x, door.y);
      if (!best || d < best.d) {
        best = { house: e.house, d };
      }
    }

    if (best && best.d <= ENTER_PROMPT_THRESHOLD) {
      if (this.nearHouse !== best.house) {
        this.nearHouse = best.house;
        this.showEnterPrompt();
      }
    } else if (this.nearHouse) {
      this.nearHouse = null;
      this.hideEnterPrompt();
    }
  }

  private tryEnterHouseNearby(): boolean {
    const player = this.ctx.getPlayer();
    if (!player) return false;

    if (this.nearHouse) {
      this.openHouseInterior(this.nearHouse);
      return true;
    }

    const houses = this.ctx.getHouses();
    const entry = houses.find((h) => {
      const door = h.house.getDoorPosition();
      return Phaser.Math.Distance.Between(player.x, player.y, door.x, door.y) < 80;
    });

    if (entry) {
      this.openHouseInterior(entry.house);
      return true;
    }

    return false;
  }

  private openHouseInterior(house: House): void {
    if (!house || this.insideHouse) return;

    this.insideHouse = true;
    this.currentHouse = house;

    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    cam.stopFollow();
    cam.pan(house.sprite.x, house.sprite.y, 350, 'Power2');
    cam.zoomTo(this.ctx.houseZoom, 350);

    const door = house.getDoorPosition();
    this.ctx.getPlayer().setPosition(door.x, door.y + 12);

    this.showHouseUI(house);
  }

  private showHouseUI(_house: House): void {
    if (this.houseUI) return;

    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const cx = cam.width / 2;
    const cy = cam.height / 2;

    const container = scene.add.container(cx, cy).setScrollFactor(0).setDepth(resolveScreenUiDepth(60));

    const bg = scene.add.graphics();
    bg.fillStyle(0x071612, 0.96);
    bg.fillRoundedRect(-140, -80, 280, 160, 12);
    bg.lineStyle(2, 0x335c45, 0.6);
    bg.strokeRoundedRect(-140, -80, 280, 160, 12);
    container.add(bg);

    container.add(
      scene.add
        .text(0, -52, 'House', {
          fontFamily: FONT,
          fontSize: '18px',
          color: '#ccebd0',
        })
        .setOrigin(0.5),
    );

    const sleepBtn = scene.add
      .text(0, -8, 'Sleep', {
        fontFamily: FONT,
        fontSize: '16px',
        color: '#ffffff',
      })
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => {
        if (this.currentHouse) this.sleepAtBed(this.currentHouse);
      });

    container.add(sleepBtn);

    const leaveBtn = scene.add
      .text(0, 44, 'Leave', {
        fontFamily: FONT,
        fontSize: '14px',
        color: '#ffd86b',
      })
      .setOrigin(0.5)
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => this.closeHouse());

    container.add(leaveBtn);

    this.houseUI = container;
  }

  private closeHouse(): void {
    if (!this.insideHouse) return;

    if (this.houseUI) {
      this.houseUI.destroy();
      this.houseUI = undefined;
    }

    this.insideHouse = false;
    this.currentHouse = null;

    const scene = this.ctx.scene;
    const player = this.ctx.getPlayer();
    const cam = scene.cameras.main;
    cam.pan(player.x, player.y, 350, 'Power2');
    cam.zoomTo(this.ctx.defaultZoom, 350);
    cam.startFollow(player, true, 0.08, 0.08);

    gameEvents.emit('house.leave', {});
  }

  private showEnterPrompt(): void {
    if (this.enterPrompt) return;
    const player = this.ctx.getPlayer();
    if (!player) return;

    const scene = this.ctx.scene;
    const t = scene.add
      .text(player.x, player.y - 40, 'Press F to enter', {
        fontFamily: FONT,
        fontSize: '14px',
        color: '#ffffff',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setOrigin(0.5)
      .setDepth(resolveScreenUiDepth(61))
      .setScrollFactor(0);

    this.enterPrompt = t;
  }

  private hideEnterPrompt(): void {
    if (!this.enterPrompt) return;
    this.enterPrompt.destroy();
    this.enterPrompt = undefined;
  }

  private trySleepNearby(): boolean {
    const player = this.ctx.getPlayer();
    const houses = this.ctx.getHouses();

    for (const entry of houses) {
      const bedPos = entry.house.getBedPosition();
      if (!bedPos) continue;

      if (Phaser.Math.Distance.Between(player.x, player.y, bedPos.x, bedPos.y) < 80) {
        this.sleepAtBed(entry.house);
        return true;
      }
    }

    return false;
  }

  private sleepAtBed(house: House): void {
    const bedPos = house.getBedPosition();
    if (!bedPos || this.ctx.isActionLocked()) return;

    const scene = this.ctx.scene;
    const player = this.ctx.getPlayer();

    this.ctx.setActionLocked(true);
    player.setVelocity(0, 0);
    player.setPosition(bedPos.x, bedPos.y - 6);
    player.rotation = 0;
    this.ctx.playIdle();

    const zzz = scene.add
      .text(player.x, player.y - 26, 'Zzz...', {
        fontFamily: FONT,
        fontSize: '18px',
        color: '#dfefff',
      })
      .setDepth(resolveScreenUiDepth(61))
      .setOrigin(0.5)
      .setScrollFactor(0);

    const follow = scene.time.addEvent({
      delay: 50,
      loop: true,
      callback: () => {
        if (zzz && player) zzz.setPosition(player.x, player.y - 26);
      },
    });

    const sleepTime = 3000;
    const coinsGained = 20;
    scene.time.delayedCall(
      sleepTime,
      () => {
        follow.remove(false);
        zzz.destroy();
        this.ctx.setActionLocked(false);
        gameState.addCoins(coinsGained);
        gameEvents.emit('house.sleep', { coinsGained });
        scene.tweens.add({ targets: player, scale: 1.04, duration: 140, yoyo: true });
      },
      [],
      this,
    );
  }

  destroy(): void {
    if (this.houseUI) {
      this.houseUI.destroy();
      this.houseUI = undefined;
    }
    this.hideEnterPrompt();
  }
}

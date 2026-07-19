import Phaser from 'phaser';
import { gameState } from '../../core/GameState';
import { playerInventory } from '../../systems/Inventory';
import { floatingText } from '../../ui/FloatingText';
import type { AreaId } from '../../world/Area';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { worldProgress } from '../progression/WorldProgress';
import { UI_THEME } from '../../presentation/theme';

const TRIAL_ID = 'crystal-caverns-switch-trial';

export interface CrystalTrialContext {
  scene: Phaser.Scene;
  areaId: AreaId;
  dimensions: WorldDimensions;
  switches: Phaser.Physics.Arcade.StaticGroup;
  chests: Phaser.Physics.Arcade.StaticGroup;
  findSpawnPoint: (anchor: Phaser.Math.Vector2) => Phaser.Math.Vector2;
  onReward: () => void;
}

export class CrystalTrialController {
  private switchStates: boolean[] = [];
  private chestOpened = false;
  private hintReadyAt = 0;

  constructor(private readonly ctx: CrystalTrialContext) {}

  create(): void {
    if (this.ctx.areaId !== 'crystal-caverns') return;

    const completed = worldProgress.isDungeonCompleted(TRIAL_ID);
    this.chestOpened = completed;
    this.switchStates = [completed, completed];

    const { scene } = this.ctx;
    const center = this.ctx.findSpawnPoint(new Phaser.Math.Vector2(
      this.ctx.dimensions.width * 0.58,
      this.ctx.dimensions.height * 0.48,
    ));
    const chestPos = this.ctx.findSpawnPoint(new Phaser.Math.Vector2(center.x, center.y - 130));
    const switchPositions = [
      this.ctx.findSpawnPoint(new Phaser.Math.Vector2(center.x - 170, center.y + 95)),
      this.ctx.findSpawnPoint(new Phaser.Math.Vector2(center.x + 170, center.y + 95)),
    ];

    const ring = scene.add.graphics().setDepth(1.5);
    ring.lineStyle(3, 0x9cf0ff, 0.38);
    ring.strokeEllipse(center.x, center.y + 12, 520, 330);
    ring.lineStyle(1, 0x496d89, 0.5);
    ring.strokeEllipse(center.x, center.y + 12, 410, 250);

    scene.add.text(center.x, center.y - 205, completed ? 'Crystal Trial Cleared' : 'Crystal Trial: wake both switches', {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '18px',
      color: '#d8fbff',
      stroke: '#102033',
      strokeThickness: 4,
    }).setOrigin(0.5).setDepth(6);

    switchPositions.forEach((position, index) => {
      const switchSprite = this.ctx.switches.create(
        position.x,
        position.y,
        completed ? 'crystal-switch-on' : 'crystal-switch-off',
      ) as Phaser.Physics.Arcade.Image;
      switchSprite.setDepth(4).setData('switchIndex', index).refreshBody();
    });

    const chest = this.ctx.chests.create(
      chestPos.x,
      chestPos.y,
      completed ? 'crystal-chest-open' : 'crystal-chest-closed',
    ) as Phaser.Physics.Arcade.Image;
    chest.setDepth(4).refreshBody();
  }

  activateSwitch(switchObject: Phaser.GameObjects.GameObject): void {
    if (this.ctx.areaId !== 'crystal-caverns' || this.chestOpened) return;
    const switchSprite = switchObject as Phaser.Physics.Arcade.Image;
    const index = switchSprite.getData('switchIndex') as number | undefined;
    if (index === undefined || this.switchStates[index]) return;

    this.switchStates[index] = true;
    switchSprite.setTexture('crystal-switch-on').setTint(0xc9fbff);
    this.ctx.scene.tweens.add({
      targets: switchSprite,
      scale: 1.18,
      duration: 120,
      yoyo: true,
      onComplete: () => switchSprite.clearTint(),
    });
    floatingText.spawn(this.ctx.scene, switchSprite.x, switchSprite.y - 30, 'switch lit', 'cyan');

    if (this.switchStates.every(Boolean)) {
      const chest = this.ctx.chests.getChildren()[0] as Phaser.Physics.Arcade.Image | undefined;
      if (chest) {
        this.ctx.scene.tweens.add({ targets: chest, scale: 1.12, duration: 160, yoyo: true, repeat: 2 });
        floatingText.spawn(this.ctx.scene, chest.x, chest.y - 42, 'CHEST UNSEALED', 'yellow', true);
      }
    }
  }

  tryOpenChest(chestObject: Phaser.GameObjects.GameObject): void {
    if (this.ctx.areaId !== 'crystal-caverns' || this.chestOpened) return;
    const chest = chestObject as Phaser.Physics.Arcade.Image;

    if (!this.switchStates.every(Boolean)) {
      if (this.ctx.scene.time.now >= this.hintReadyAt) {
        this.hintReadyAt = this.ctx.scene.time.now + 1400;
        floatingText.spawn(this.ctx.scene, chest.x, chest.y - 42, 'Find both switches', 'cyan');
      }
      return;
    }

    this.chestOpened = true;
    worldProgress.completeDungeon(TRIAL_ID);
    chest.setTexture('crystal-chest-open');
    this.ctx.scene.cameras.main.shake(220, 0.006);
    gameState.addCoins(90);
    gameState.addXp(120);
    playerInventory.add('shard', 4);
    playerInventory.add('hp-potion', 1);
    this.ctx.onReward();
    floatingText.spawn(this.ctx.scene, chest.x, chest.y - 62, 'Crystal Cache Opened!', 'yellow', true);
    floatingText.spawn(this.ctx.scene, chest.x, chest.y - 38, '+90c  +120 XP  +4 shards  +tonic', 'green', true);
  }
}

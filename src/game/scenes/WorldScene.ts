import Phaser from 'phaser';
import { SLIME_ANIMS } from '../slimeAnimations';

const TILE_SIZE = 64;
const WORLD_TILES_X = 54;
const WORLD_TILES_Y = 54;
const WORLD_WIDTH = WORLD_TILES_X * TILE_SIZE;
const WORLD_HEIGHT = WORLD_TILES_Y * TILE_SIZE;
const WALK_SPEED = 230;
const BOOST_SPEED = 360;

type Controls = Phaser.Types.Input.Keyboard.CursorKeys & {
  upAlt: Phaser.Input.Keyboard.Key;
  downAlt: Phaser.Input.Keyboard.Key;
  leftAlt: Phaser.Input.Keyboard.Key;
  rightAlt: Phaser.Input.Keyboard.Key;
  boost: Phaser.Input.Keyboard.Key;
  trick: Phaser.Input.Keyboard.Key;
};

export class WorldScene extends Phaser.Scene {
  private player!: Phaser.Physics.Arcade.Sprite;
  private controls!: Controls;
  private currentAnimation = 'slime-idle';
  private trickLocked = false;

  constructor() {
    super('world');
  }

  create(): void {
    this.buildWorld();
    this.createSlimeAnimations();
    this.createPlayer();
    this.createCamera();
    this.createControls();
    this.createOverlay();
  }

  update(): void {
    const direction = new Phaser.Math.Vector2(0, 0);

    if (this.controls.left.isDown || this.controls.leftAlt.isDown) {
      direction.x -= 1;
    }
    if (this.controls.right.isDown || this.controls.rightAlt.isDown) {
      direction.x += 1;
    }
    if (this.controls.up.isDown || this.controls.upAlt.isDown) {
      direction.y -= 1;
    }
    if (this.controls.down.isDown || this.controls.downAlt.isDown) {
      direction.y += 1;
    }

    const wantsBoost = this.controls.boost.isDown;
    const speed = wantsBoost ? BOOST_SPEED : WALK_SPEED;

    if (direction.lengthSq() > 0) {
      direction.normalize().scale(speed);
    }

    this.player.setVelocity(direction.x, direction.y);
    this.player.rotation = 0;

    if (Phaser.Input.Keyboard.JustDown(this.controls.trick) && !this.trickLocked) {
      this.playTrickAnimation();
      return;
    }

    if (this.trickLocked) {
      return;
    }

    if (direction.lengthSq() === 0) {
      this.player.setFlipX(false);
      this.playAnimation('slime-idle');
      return;
    }

    // Horizontal motion → flip sprite instead of separate left animation.
    if (Math.abs(direction.x) >= Math.abs(direction.y)) {
      this.player.setFlipX(direction.x > 0);
    } else {
      this.player.setFlipX(false);
    }

    if (wantsBoost) {
      this.playAnimation('slime-roll');
    } else if (Math.abs(direction.y) > Math.abs(direction.x)) {
      this.playAnimation(direction.y < 0 ? 'slime-stretch' : 'slime-hop');
    } else {
      this.playAnimation('slime-walk');
    }
  }

  private buildWorld(): void {
    for (let tileY = 0; tileY < WORLD_TILES_Y; tileY += 1) {
      for (let tileX = 0; tileX < WORLD_TILES_X; tileX += 1) {
        const worldX = tileX * TILE_SIZE;
        const worldY = tileY * TILE_SIZE;
        const noise = this.sample(tileX, tileY);
        const texture = noise > 0.73 ? 'water' : noise > 0.38 ? 'grass-b' : 'grass-a';

        this.add.image(worldX, worldY, texture).setOrigin(0);

        if (texture !== 'water' && noise > 0.62 && this.sample(tileX + 11, tileY - 7) > 0.5) {
          this.add
            .image(worldX + 42, worldY + 24, 'flower')
            .setDepth(2)
            .setScale(Phaser.Math.FloatBetween(0.9, 1.2));
        }

        if (texture !== 'water' && noise < 0.18 && this.sample(tileX - 5, tileY + 9) > 0.62) {
          this.add
            .image(worldX + 28, worldY + 34, 'stone')
            .setDepth(2)
            .setRotation(Phaser.Math.FloatBetween(-0.3, 0.3));
        }
      }
    }

    this.physics.world.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
  }

  private createSlimeAnimations(): void {
    for (const clip of SLIME_ANIMS) {
      this.makeAnimation(clip.key, clip.frames, clip.frameRate, clip.repeat);
    }
  }

  private createPlayer(): void {
    this.player = this.physics.add.sprite(WORLD_WIDTH / 2, WORLD_HEIGHT / 2, 'slime', 0);
    this.player.setScale(0.28);
    this.player.setCollideWorldBounds(true);
    this.player.setDepth(10);
    this.player.setSize(108, 80);
    this.player.setOffset(74, 140);
    this.playAnimation('slime-idle');
  }

  private createCamera(): void {
    this.cameras.main.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
    this.cameras.main.startFollow(this.player, true, 0.08, 0.08);
    this.cameras.main.setZoom(1.7);
    this.cameras.main.setRoundPixels(true);
  }

  private createControls(): void {
    const cursorKeys = this.input.keyboard?.createCursorKeys();
    const extraKeys = this.input.keyboard?.addKeys({
      upAlt: Phaser.Input.Keyboard.KeyCodes.W,
      downAlt: Phaser.Input.Keyboard.KeyCodes.S,
      leftAlt: Phaser.Input.Keyboard.KeyCodes.A,
      rightAlt: Phaser.Input.Keyboard.KeyCodes.D,
      boost: Phaser.Input.Keyboard.KeyCodes.SHIFT,
      trick: Phaser.Input.Keyboard.KeyCodes.SPACE,
    }) as Omit<Controls, keyof Phaser.Types.Input.Keyboard.CursorKeys> | undefined;

    if (!cursorKeys || !extraKeys) {
      throw new Error('Keyboard input is not available.');
    }

    this.controls = {
      ...cursorKeys,
      ...extraKeys,
    };
  }

  private createOverlay(): void {
    this.add
      .text(24, 24, 'Explore the meadow', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '24px',
        color: '#f2ffef',
        stroke: '#163033',
        strokeThickness: 5,
      })
      .setScrollFactor(0)
      .setDepth(50);

    this.add
      .text(24, 56, 'Shift = boost   Space = slime trick', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '16px',
        color: '#ccebd0',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50);
  }

  private playAnimation(key: string): void {
    if (this.currentAnimation === key) {
      return;
    }

    this.currentAnimation = key;
    this.player.play(key, true);
  }

  private playTrickAnimation(): void {
    this.trickLocked = true;
    this.currentAnimation = 'slime-trick';
    this.player.setVelocity(0, 0);
    this.player.play('slime-trick');
    this.player.once(Phaser.Animations.Events.ANIMATION_COMPLETE_KEY + 'slime-trick', () => {
      this.trickLocked = false;
      this.currentAnimation = '';
      this.player.play('slime-idle', true);
    });
  }

  private makeAnimation(key: string, frames: number[], frameRate: number, repeat = -1): void {
    if (this.anims.exists(key)) {
      return;
    }

    this.anims.create({
      key,
      frames: frames.map((frame) => ({ key: 'slime', frame })),
      frameRate,
      repeat,
    });
  }

  private sample(tileX: number, tileY: number): number {
    const value = Math.sin(tileX * 12.9898 + tileY * 78.233) * 43758.5453;
    const fraction = value - Math.floor(value);
    const wave = (Math.sin(tileX * 0.25) + Math.cos(tileY * 0.32) + 2) / 4;

    return Phaser.Math.Clamp(fraction * 0.45 + wave * 0.55, 0, 1);
  }
}
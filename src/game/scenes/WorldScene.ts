import Phaser from 'phaser';
import { SLIME_ANIM_MAP, SLIME_ANIMS } from '../slimeAnimations';
import {
  getTileBodyBounds,
  isTileCollidable,
  resolveWorldTile,
  WORLD_TILE_RULES,
  type WorldTileId,
} from '../worldTiles';

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
  jump: Phaser.Input.Keyboard.Key;
  trick: Phaser.Input.Keyboard.Key;
  stretch: Phaser.Input.Keyboard.Key;
  squash: Phaser.Input.Keyboard.Key;
  teleport: Phaser.Input.Keyboard.Key;
};

export class WorldScene extends Phaser.Scene {
  private player!: Phaser.Physics.Arcade.Sprite;
  private collisionTiles!: Phaser.Physics.Arcade.StaticGroup;
  private controls!: Controls;
  private currentAnimation = 'slime-idle';
  private actionLocked = false;
  private terrainGrid: WorldTileId[][] = [];

  constructor() {
    super('world');
  }

  create(): void {
    this.createCollisionLayer();
    this.buildWorld();
    this.createSlimeAnimations();
    this.createPlayer();
    this.createPhysics();
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

    if (this.actionLocked) {
      this.player.setVelocity(0, 0);
      this.player.rotation = 0;
      return;
    }

    if (this.handleActionInput(direction)) {
      return;
    }

    const wantsBoost = this.controls.boost.isDown;
    const speed = wantsBoost ? BOOST_SPEED : WALK_SPEED;

    if (direction.lengthSq() > 0) {
      direction.normalize().scale(speed);
    }

    this.player.setVelocity(direction.x, direction.y);
    this.player.rotation = 0;

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
    this.terrainGrid = [];

    for (let tileY = 0; tileY < WORLD_TILES_Y; tileY += 1) {
      const row: WorldTileId[] = [];

      for (let tileX = 0; tileX < WORLD_TILES_X; tileX += 1) {
        const worldX = tileX * TILE_SIZE;
        const worldY = tileY * TILE_SIZE;
        const noise = this.sample(tileX, tileY);
        const tileId = resolveWorldTile(tileX, tileY, this.sample.bind(this));
        const tileRule = WORLD_TILE_RULES[tileId];

        row.push(tileId);
        this.createWorldTile(tileId, worldX, worldY);

        if (tileRule.allowsDecorations && noise > 0.62 && this.sample(tileX + 11, tileY - 7) > 0.5) {
          this.add
            .image(worldX + 42, worldY + 24, 'flower')
            .setDepth(2)
            .setScale(Phaser.Math.FloatBetween(0.9, 1.2));
        }

        if (tileRule.allowsDecorations && noise < 0.18 && this.sample(tileX - 5, tileY + 9) > 0.62) {
          this.add
            .image(worldX + 28, worldY + 34, 'stone')
            .setDepth(2)
            .setRotation(Phaser.Math.FloatBetween(-0.3, 0.3));
        }
      }

      this.terrainGrid.push(row);
    }

    this.physics.world.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
  }

  private createCollisionLayer(): void {
    this.collisionTiles = this.physics.add.staticGroup();
  }

  private createSlimeAnimations(): void {
    for (const clip of SLIME_ANIMS) {
      this.makeAnimation(clip.key, clip.frames, clip.frameRate, clip.repeat);
    }
  }

  private createPlayer(): void {
    const spawnPoint = this.findSpawnPoint();

    this.player = this.physics.add.sprite(spawnPoint.x, spawnPoint.y, 'slime', 0);
    this.player.setScale(0.28);
    this.player.setCollideWorldBounds(true);
    this.player.setDepth(10);
    this.player.setSize(108, 80);
    this.player.setOffset(74, 140);
    this.playAnimation('slime-idle');
  }

  private createPhysics(): void {
    this.physics.add.collider(this.player, this.collisionTiles);
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
      upAlt: Phaser.Input.Keyboard.KeyCodes.I,
      downAlt: Phaser.Input.Keyboard.KeyCodes.K,
      leftAlt: Phaser.Input.Keyboard.KeyCodes.J,
      rightAlt: Phaser.Input.Keyboard.KeyCodes.L,
      boost: Phaser.Input.Keyboard.KeyCodes.Q,
      jump: Phaser.Input.Keyboard.KeyCodes.SPACE,
      trick: Phaser.Input.Keyboard.KeyCodes.E,
      stretch: Phaser.Input.Keyboard.KeyCodes.R,
      squash: Phaser.Input.Keyboard.KeyCodes.T,
      teleport: Phaser.Input.Keyboard.KeyCodes.Y,
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
      .text(24, 56, 'Arrows / IJKL move   Space jump   Q roll/boost', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '16px',
        color: '#ccebd0',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50);

    this.add
      .text(24, 82, 'E trick   R stretch   T squash   Y teleport', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '16px',
        color: '#ccebd0',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50);

    this.add
      .text(24, 108, 'Rock tiles are solid obstacles', {
        fontFamily: 'Aptos, Segoe UI Variable, sans-serif',
        fontSize: '16px',
        color: '#ccebd0',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50);
  }

  private createWorldTile(tileId: WorldTileId, worldX: number, worldY: number): void {
    const rule = WORLD_TILE_RULES[tileId];
    const bodyBounds = getTileBodyBounds(tileId, TILE_SIZE);

    if (!bodyBounds) {
      this.add.image(worldX, worldY, rule.texture).setOrigin(0);
      return;
    }

    const tile = this.collisionTiles.create(worldX + TILE_SIZE / 2, worldY + TILE_SIZE / 2, rule.texture) as Phaser.Physics.Arcade.Image;
    const body = tile.body as Phaser.Physics.Arcade.StaticBody;

    tile.setDepth(1);
    body.setSize(bodyBounds.width, bodyBounds.height);
    body.setOffset(bodyBounds.offsetX, bodyBounds.offsetY);
    tile.refreshBody();
  }

  private findSpawnPoint(): Phaser.Math.Vector2 {
    const startX = Math.floor(WORLD_TILES_X / 2);
    const startY = Math.floor(WORLD_TILES_Y / 2);
    const maxRadius = Math.max(WORLD_TILES_X, WORLD_TILES_Y);

    for (let radius = 0; radius < maxRadius; radius += 1) {
      for (let tileY = startY - radius; tileY <= startY + radius; tileY += 1) {
        for (let tileX = startX - radius; tileX <= startX + radius; tileX += 1) {
          if (!this.isWithinWorld(tileX, tileY) || this.isSolidTile(tileX, tileY)) {
            continue;
          }

          return new Phaser.Math.Vector2(
            tileX * TILE_SIZE + TILE_SIZE / 2,
            tileY * TILE_SIZE + TILE_SIZE / 2,
          );
        }
      }
    }

    return new Phaser.Math.Vector2(WORLD_WIDTH / 2, WORLD_HEIGHT / 2);
  }

  private isWithinWorld(tileX: number, tileY: number): boolean {
    return tileX >= 0 && tileX < WORLD_TILES_X && tileY >= 0 && tileY < WORLD_TILES_Y;
  }

  private isSolidTile(tileX: number, tileY: number): boolean {
    const tileId = this.terrainGrid[tileY]?.[tileX];

    return tileId ? isTileCollidable(tileId) : false;
  }

  private playAnimation(key: string): void {
    if (this.currentAnimation === key) {
      return;
    }

    this.currentAnimation = key;
    this.player.play(key, true);
  }

  private handleActionInput(direction: Phaser.Math.Vector2): boolean {
    if (Phaser.Input.Keyboard.JustDown(this.controls.jump)) {
      this.playActionAnimation('slime-hop');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.boost) && direction.lengthSq() === 0) {
      this.playActionAnimation('slime-roll');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.trick)) {
      this.playActionAnimation('slime-trick');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.stretch)) {
      this.playActionAnimation('slime-stretch');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.squash)) {
      this.playActionAnimation('slime-squash');
      return true;
    }

    if (Phaser.Input.Keyboard.JustDown(this.controls.teleport)) {
      this.playActionAnimation('slime-teleport');
      return true;
    }

    return false;
  }

  private playActionAnimation(key: string): void {
    const clip = SLIME_ANIM_MAP[key];

    if (!clip) {
      return;
    }

    this.actionLocked = true;
    this.currentAnimation = key;
    this.player.setVelocity(0, 0);
    this.player.rotation = 0;
    this.player.play(key, true);

    const unlock = () => {
      this.actionLocked = false;
      this.currentAnimation = '';
      this.player.play('slime-idle', true);
    };

    if (clip.repeat === 0) {
      this.player.once(Phaser.Animations.Events.ANIMATION_COMPLETE_KEY + key, unlock);
      return;
    }

    const durationMs = Math.max(1, Math.round((clip.frames.length / clip.frameRate) * 1000));
    this.time.delayedCall(durationMs, unlock);
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
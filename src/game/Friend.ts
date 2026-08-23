import Phaser from 'phaser';
import { House } from './House';
import { resolvePhysicsPresentationPosition } from './presentation/PhysicsPresentation';
import { resolveBodyBottom, resolveWorldDepth } from './presentation/WorldDepth';

let friendIdCounter = 0;

export class Friend extends Phaser.Physics.Arcade.Sprite {
  readonly friendId = ++friendIdCounter;
  public home?: House;
  public hp = 40;
  public maxHp = 40;
  private wanderTarget: Phaser.Math.Vector2 | null = null;
  private nextWanderAt = 0;
  private speed = 48;

  private faceVariants = ['friend-face-0', 'friend-face-1', 'friend-face-2', 'friend-face-3'];
  private nextFaceChangeAt = 0;

  private colorVariants = [0xffc86b, 0x8cd1ff, 0xffb6b6, 0x9aff9a, 0xd8a8ff];
  private nextColorChangeAt = 0;

  private earVariants = ['friend-ear-cat', 'friend-ear-bunny', 'friend-ear-dog', 'friend-ear-fox'];
  private readonly visualImage: Phaser.GameObjects.Image;
  private earsImage?: Phaser.GameObjects.Image;
  private readonly presentationPosition = new Phaser.Math.Vector2();
  private nextEarChangeAt = 0;

  constructor(scene: Phaser.Scene, x: number, y: number) {
    super(scene, x, y, 'friend');
    scene.add.existing(this);
    scene.physics.add.existing(this);
    this.setVisible(false);
    this.visualImage = scene.add.image(x, y, 'friend');

    const body = this.body as Phaser.Physics.Arcade.Body;
    body.setCollideWorldBounds(true);
    body.setSize(28, 28);

    this.syncPresentation();
    this.setScale(1);

    this.pickNewTarget();
    this.applyRandomFace();
    this.applyRandomColor();
    this.applyRandomEars();

    this.nextFaceChangeAt = this.scene.time.now + Phaser.Math.Between(800, 3200);
    this.nextColorChangeAt = this.scene.time.now + Phaser.Math.Between(4000, 10000);
    this.nextEarChangeAt = this.scene.time.now + Phaser.Math.Between(5000, 15000);
  }

  private pickNewTarget(): void {
    const range = 120;
    const angle = Phaser.Math.FloatBetween(0, Math.PI * 2);
    const radius = Phaser.Math.Between(24, range);
    this.wanderTarget = new Phaser.Math.Vector2(this.x + Math.cos(angle) * radius, this.y + Math.sin(angle) * radius);
    this.nextWanderAt = this.scene.time.now + Phaser.Math.Between(1200, 4200);
  }

  preUpdate(time: number, delta: number): void {
    super.preUpdate(time, delta);
    if (time >= this.nextFaceChangeAt) {
      this.applyRandomFace();
      this.nextFaceChangeAt = time + Phaser.Math.Between(800, 4200);
    }

    if (time >= this.nextColorChangeAt) {
      this.applyRandomColor();
      this.nextColorChangeAt = time + Phaser.Math.Between(4000, 10000);
    }

    if (time >= this.nextEarChangeAt) {
      this.applyRandomEars();
      this.nextEarChangeAt = time + Phaser.Math.Between(5000, 15000);
    }

    if (!this.wanderTarget || time >= this.nextWanderAt) {
      this.pickNewTarget();
    }

    if (!this.wanderTarget) {
      return;
    }

    const dx = this.wanderTarget.x - this.x;
    const dy = this.wanderTarget.y - this.y;
    const dist2 = dx * dx + dy * dy;

    if (dist2 < 10 * 10) {
      (this.body as Phaser.Physics.Arcade.Body).setVelocity(0, 0);
      return;
    }

    const vec = new Phaser.Math.Vector2(dx, dy).normalize().scale(this.speed);
    (this.body as Phaser.Physics.Arcade.Body).setVelocity(vec.x, vec.y);
  }

  updatePresentation(): void {
    this.syncPresentation();
  }

  private applyRandomEars(): void {
    const key = this.earVariants[Phaser.Math.Between(0, this.earVariants.length - 1)];

    if (this.earsImage) {
      this.earsImage.setTexture(key);
    } else {
      this.earsImage = this.scene.add.image(this.x, this.y - 8, key).setOrigin(0.5, 0.5).setDepth(resolveWorldDepth(resolveBodyBottom(this.body as Phaser.Physics.Arcade.Body), {
        stableId: `friend:${this.friendId}`,
        attachmentSlot: 1,
      }).depth);
    }

    // match current tint
    this.earsImage.setTint(this.visualImage.tintTopLeft);
  }

  private applyRandomFace(): void {
    const key = this.faceVariants[Phaser.Math.Between(0, this.faceVariants.length - 1)];
    this.visualImage.setTexture(key);
  }

  private applyRandomColor(): void {
    const color = this.colorVariants[Phaser.Math.Between(0, this.colorVariants.length - 1)];
    this.visualImage.setTint(color);
    if (this.earsImage) {
      this.earsImage.setTint(color);
    }
  }

  destroy(fromScene?: boolean): void {
    this.visualImage.destroy();
    if (this.earsImage) {
      this.earsImage.destroy();
      this.earsImage = undefined;
    }

    super.destroy(fromScene);
  }

  private syncPresentation(): void {
    if (!this.body || !this.visualImage.active) return;
    const body = this.body as Phaser.Physics.Arcade.Body;
    const position = resolvePhysicsPresentationPosition(
      this.scene,
      this,
      this.presentationPosition,
    );
    const depth = resolveWorldDepth(resolveBodyBottom(body), {
      stableId: `friend:${this.friendId}`,
    }).depth;
    this.setDepth(depth);
    this.visualImage.setPosition(position.x, position.y).setDepth(depth);
    if (this.earsImage) {
      this.earsImage
        .setPosition(position.x, position.y - Math.max(8, this.visualImage.displayHeight * 0.28))
        .setTint(this.visualImage.tintTopLeft)
        .setDepth(resolveWorldDepth(resolveBodyBottom(body), {
          stableId: `friend:${this.friendId}`,
          attachmentSlot: 1,
        }).depth);
    }
  }
}

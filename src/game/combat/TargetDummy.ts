import Phaser from 'phaser';
import { floatingText } from '../ui/FloatingText';
import { resolveBodyBottom, resolveWorldDepth } from '../presentation/WorldDepth';
import { acceptedDamage, rejectedDamage, type DamageApplicationRequest, type DamageApplicationResult } from './DamageableTarget';

/**
 * Target dummy for combat practice. Has HP, takes damage, shows a
 * world-space health bar, gets knocked back, and respawns after a short
 * delay. Does not fight back â€” pure damage sponge for M2 playtesting.
 *
 * In Phase 3 this is replaced by the real Enemy class with AI.
 */
export class TargetDummy extends Phaser.Physics.Arcade.Sprite {
  public maxHp: number;
  public hp: number;
  private healthBar: Phaser.GameObjects.Graphics;
  private hitFlashUntil = 0;
  private dead = false;
  private respawnAt = 0;
  private spawnX: number;
  private spawnY: number;

  constructor(scene: Phaser.Scene, x: number, y: number) {
    super(scene, x, y, 'target-dummy');
    scene.add.existing(this);
    scene.physics.add.existing(this);

    this.spawnX = x;
    this.spawnY = y;
    this.maxHp = 100;
    this.hp = 100;
    this.setScale(1.6);
    this.setCollideWorldBounds(true);

    const body = this.body as Phaser.Physics.Arcade.Body;
    body.setSize(24, 32);
    body.setOffset(4, 0);
    body.setBounce(0.3);

    this.syncDepth();
    this.healthBar = scene.add.graphics().setDepth(this.healthBarDepth());
    this.drawHealthBar();
  }

  applyDamage(request: DamageApplicationRequest): DamageApplicationResult {
    const { amount, knockX, knockY, knockStrength } = request;
    if (this.dead) return rejectedDamage('dead');
    if (!Number.isFinite(amount) || amount < 0) return rejectedDamage('invalid');
    const hpBefore = this.hp;

    this.hp = Math.max(0, this.hp - amount);
    this.hitFlashUntil = this.scene.time.now + 120;
    this.setTintFill(0xff6f88);

    floatingText.spawn(this.scene, this.x, this.y - 24, `-${amount}`, amount > 15 ? 'yellow' : 'white', amount > 15);

    if (knockStrength > 0) {
      this.setVelocity(knockX * knockStrength, knockY * knockStrength);
    }

    this.drawHealthBar();

    if (this.hp <= 0) {
      this.die();
    }
    return acceptedDamage(hpBefore, this.hp);
  }

  takeDamage(amount: number, knockX: number, knockY: number, knockStrength: number): DamageApplicationResult {
    return this.applyDamage({ amount, knockX, knockY, knockStrength });
  }

  private die(): void {
    this.dead = true;
    this.setActive(false);
    this.setVisible(false);
    this.setVelocity(0, 0);
    this.healthBar.clear();
    floatingText.spawn(this.scene, this.spawnX, this.spawnY - 30, 'KO!', 'green', true);
    this.respawnAt = this.scene.time.now + 3000;
  }

  private respawn(): void {
    this.dead = false;
    this.hp = this.maxHp;
    this.setActive(true);
    this.setVisible(true);
    this.clearTint();
    this.setPosition(this.spawnX, this.spawnY);
    this.setVelocity(0, 0);
    this.drawHealthBar();
    floatingText.spawn(this.scene, this.spawnX, this.spawnY - 30, 'Respawned', 'cyan');
  }

  preUpdate(time: number, delta: number): void {
    super.preUpdate(time, delta);
    this.syncDepth();
    this.healthBar.setDepth(this.healthBarDepth());

    if (this.hitFlashUntil > 0 && time > this.hitFlashUntil) {
      this.clearTint();
      this.hitFlashUntil = 0;
    }

    if (this.dead && time >= this.respawnAt) {
      this.respawn();
    }

    // Drag knockback.
    const body = this.body as Phaser.Physics.Arcade.Body;
    if (body.velocity.lengthSq() > 10) {
      body.velocity.scale(0.92);
    } else {
      body.setVelocity(0, 0);
    }

    this.drawHealthBar();
  }

  private syncDepth(): void {
    const body = this.body as Phaser.Physics.Arcade.Body;
    this.setDepth(resolveWorldDepth(resolveBodyBottom(body), {
      stableId: `target-dummy:${this.spawnX}:${this.spawnY}`,
    }).depth);
  }

  private healthBarDepth(): number {
    return resolveWorldDepth(resolveBodyBottom(this.body as Phaser.Physics.Arcade.Body), {
      stableId: `target-dummy:${this.spawnX}:${this.spawnY}`,
      attachmentSlot: 7,
    }).depth;
  }

  private drawHealthBar(): void {
    if (this.dead) {
      this.healthBar.clear();
      return;
    }
    const g = this.healthBar;
    g.clear();
    const x = this.x - 22;
    const y = this.y - 36;
    const w = 44;
    const h = 5;

    g.fillStyle(0x0b1020, 0.85);
    g.fillRoundedRect(x, y, w, h, 3);

    const pct = this.maxHp > 0 ? Phaser.Math.Clamp(this.hp / this.maxHp, 0, 1) : 0;
    const fill = pct <= 0.25 ? 0xff6f88 : pct <= 0.5 ? 0xffad66 : 0x7be08a;
    g.fillStyle(fill, 1);
    g.fillRoundedRect(x + 1, y + 1, Math.max(0, (w - 2) * pct), h - 2, 2);
  }

  destroy(fromScene?: boolean): void {
    this.healthBar.destroy();
    super.destroy(fromScene);
  }
}

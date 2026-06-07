import Phaser from 'phaser';

export class House {
  public sprite: Phaser.Physics.Arcade.Image;
  public doorZone: Phaser.GameObjects.Zone;
  public bed?: Phaser.Physics.Arcade.Image;
  public bedZone?: Phaser.GameObjects.Zone;

  /**
   * @param textureKey texture for the house (defaults to 'house')
   * @param bedKey optional texture for a bed to place near/inside the house
   */
  constructor(scene: Phaser.Scene, x: number, y: number, textureKey = 'house', bedKey?: string) {
    // center-based static image
    this.sprite = scene.physics.add.staticImage(x, y, textureKey);
    this.sprite.setOrigin(0.5, 0.5);
    this.sprite.setDepth(2);

    // door area near bottom center of the house
    const doorOffsetY = Math.round((this.sprite.displayHeight ?? 64) / 2) - 10;
    this.doorZone = scene.add.zone(x, y + doorOffsetY, 28, 18);
    scene.physics.add.existing(this.doorZone, true);

    if (bedKey) {
      // Place the bed slightly inside / in front of the house toward the bottom-left
      const bedOffsetX = Math.round((this.sprite.displayWidth ?? 64) * -0.18);
      const bedOffsetY = Math.round((this.sprite.displayHeight ?? 64) * 0.2);
      const bx = x + bedOffsetX;
      const by = y + bedOffsetY;

      this.bed = scene.physics.add.staticImage(bx, by, bedKey);
      this.bed.setOrigin(0.5, 0.5);
      this.bed.setDepth(2);

      const bw = Math.max(16, (this.bed.width ?? 24));
      const bh = Math.max(8, (this.bed.height ?? 12));
      this.bedZone = scene.add.zone(bx, by, bw, bh);
      scene.physics.add.existing(this.bedZone, true);
    }
  }

  getDoorPosition(): Phaser.Math.Vector2 {
    return new Phaser.Math.Vector2(this.doorZone.x, this.doorZone.y);
  }

  getBedPosition(): Phaser.Math.Vector2 | null {
    if (!this.bedZone) return null;
    return new Phaser.Math.Vector2(this.bedZone.x, this.bedZone.y);
  }

  destroy(): void {
    this.sprite.destroy();
    this.doorZone.destroy();
    if (this.bed) this.bed.destroy();
    if (this.bedZone) this.bedZone.destroy();
  }
}

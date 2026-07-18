import Phaser from 'phaser';
import { PLAYER_CONFIG } from '../../content/player';
import { UI_THEME } from '../../presentation/theme';

export interface PlayerEntity {
  sprite: Phaser.Physics.Arcade.Sprite;
  nameTag: Phaser.GameObjects.Text;
}

export function createPlayerEntity(
  scene: Phaser.Scene,
  spawnPoint: Phaser.Math.Vector2,
  playIdle: () => void,
): PlayerEntity {
  const sprite = scene.physics.add.sprite(spawnPoint.x, spawnPoint.y, PLAYER_CONFIG.textureKey, 0);
  sprite.setScale(PLAYER_CONFIG.scale);
  sprite.setCollideWorldBounds(true);
  sprite.setDepth(PLAYER_CONFIG.depth);
  sprite.setSize(PLAYER_CONFIG.body.width, PLAYER_CONFIG.body.height);
  sprite.setOffset(PLAYER_CONFIG.body.offsetX, PLAYER_CONFIG.body.offsetY);
  playIdle();

  const nameTag = scene.add.text(sprite.x, sprite.y - 56, PLAYER_CONFIG.name, {
    fontFamily: UI_THEME.fontFamily,
    fontSize: '14px',
    color: UI_THEME.colors.text,
    stroke: UI_THEME.colors.shadow,
    strokeThickness: 4,
  }).setOrigin(0.5).setDepth(PLAYER_CONFIG.depth + 1);

  return { sprite, nameTag };
}

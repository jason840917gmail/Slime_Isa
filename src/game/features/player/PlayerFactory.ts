import Phaser from 'phaser';
import { PLAYER_CONFIG } from '../../content/player';
import { UI_THEME } from '../../presentation/theme';
import { AnimatedVisual } from '../visuals/AnimatedVisual';
import { resolveBodyBottom, resolveWorldDepth } from '../../presentation/WorldDepth';

export interface PlayerEntity {
  sprite: Phaser.Physics.Arcade.Sprite;
  visual: AnimatedVisual;
  nameTag: Phaser.GameObjects.Text;
}

export function createPlayerEntity(
  scene: Phaser.Scene,
  spawnPoint: Phaser.Math.Vector2,
): PlayerEntity {
  const sprite = scene.physics.add.sprite(spawnPoint.x, spawnPoint.y, '__WHITE');
  sprite.setVisible(false);
  sprite.setCollideWorldBounds(true);
  const body = sprite.body as Phaser.Physics.Arcade.Body;
  body.setSize(PLAYER_CONFIG.body.width, PLAYER_CONFIG.body.height, false);
  body.setOffset(
    sprite.displayOriginX - PLAYER_CONFIG.body.width / 2 + PLAYER_CONFIG.body.centerOffsetX,
    sprite.displayOriginY - PLAYER_CONFIG.body.height / 2 + PLAYER_CONFIG.body.centerOffsetY,
  );

  const playerDepth = resolveWorldDepth(resolveBodyBottom(body), { stableId: 'player' }).depth;
  sprite.setDepth(playerDepth);

  const visual = new AnimatedVisual(scene, sprite, 'character.player.slime', {
    depth: playerDepth,
    getDepth: () => sprite.depth,
    initialFrame: 0,
  });
  visual.play('slime-idle');

  const nameTag = scene.add.text(sprite.x, sprite.y - 56, PLAYER_CONFIG.name, {
    fontFamily: UI_THEME.fontFamily,
    fontSize: '14px',
    color: UI_THEME.colors.text,
    stroke: UI_THEME.colors.shadow,
    strokeThickness: 4,
  }).setOrigin(0.5).setDepth(resolveWorldDepth(resolveBodyBottom(body), {
    stableId: 'player',
    attachmentSlot: 7,
  }).depth);

  return { sprite, visual, nameTag };
}

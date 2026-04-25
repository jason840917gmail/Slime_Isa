import Phaser from 'phaser';

import { BootScene } from './scenes/BootScene';
import { WorldScene } from './scenes/WorldScene';

export function createGame(container: HTMLDivElement): Phaser.Game {
  container.innerHTML = `
    <section class="game-shell">
      <header class="hud">
        <div>
          <h1>Slime Wanderer</h1>
          <p>WASD or arrow keys to move, hold Shift to boost, press Space for a slime trick.</p>
        </div>
      </header>
      <div class="canvas-frame" id="game-root"></div>
    </section>
  `;

  const gameRoot = container.querySelector<HTMLDivElement>('#game-root');

  if (!gameRoot) {
    throw new Error('Missing game mount node.');
  }

  return new Phaser.Game({
    type: Phaser.AUTO,
    parent: gameRoot,
    backgroundColor: '#112028',
    scale: {
      mode: Phaser.Scale.FIT,
      autoCenter: Phaser.Scale.CENTER_BOTH,
      width: 1280,
      height: 720,
    },
    pixelArt: true,
    roundPixels: true,
    physics: {
      default: 'arcade',
      arcade: {
        gravity: { y: 0, x: 0 },
        debug: false,
      },
    },
    scene: [BootScene, WorldScene],
  });
}
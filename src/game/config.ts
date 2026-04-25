import Phaser from 'phaser';

import { BootScene } from './scenes/BootScene';
import { WorldScene } from './scenes/WorldScene';

export function createGame(container: HTMLDivElement): Phaser.Game {
  container.innerHTML = `
    <section class="game-shell">
      <div class="canvas-frame">
        <div id="game-root"></div>
        <details class="keymap-panel" open>
          <summary>⌨ Controls</summary>
          <table>
            <tr><td class="k">Arrows / IJKL</td><td>Move</td></tr>
            <tr><td class="k">Space</td><td>Jump</td></tr>
            <tr><td class="k">Q</td><td>Roll / boost</td></tr>
            <tr><td class="k">E</td><td>Trick</td></tr>
            <tr><td class="k">R / T / Y</td><td>Stretch / squash / teleport</td></tr>
          </table>
        </details>
      </div>
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
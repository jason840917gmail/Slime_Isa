import Phaser from 'phaser';

import { BootScene } from './scenes/BootScene';
import { WorldScene } from './scenes/WorldScene';
import { bindDevToolsPanel, createDevToolsPanel } from './devTools';

export function createGame(container: HTMLDivElement): Phaser.Game {
  const devPanel = import.meta.env.DEV ? createDevToolsPanel() : '';

  container.innerHTML = `
    <section class="game-shell${import.meta.env.DEV ? ' is-dev-mode' : ''}">
      <div class="canvas-frame">
        <div id="game-root"></div>
        <details class="keymap-panel" open>
          <summary>⌨ Controls</summary>
          <table>
            <tr><td class="k">Arrows / IJKL</td><td>Move</td></tr>
            <tr><td class="k">E / Click</td><td>Attack</td></tr>
            <tr><td class="k">Q</td><td>Roll / dodge (i-frames)</td></tr>
            <tr><td class="k">Space</td><td>Jump <span class="lock">Lv 2</span></td></tr>
            <tr><td class="k">T</td><td>Squash Slam <span class="lock">Lv 3</span></td></tr>
            <tr><td class="k">R</td><td>Stretch Lash <span class="lock">Lv 4</span></td></tr>
            <tr><td class="k">Y</td><td>Teleport <span class="lock">Lv 5</span></td></tr>
            <tr><td class="k">F</td><td>Interact / Shop</td></tr>
            <tr><td class="k">Tab</td><td>Inventory</td></tr>
            <tr><td class="k">M</td><td>World Map</td></tr>
            <tr><td class="k">U</td><td>Quest Journal</td></tr>
            <tr><td class="k">C</td><td>Crafting</td></tr>
            <tr><td class="k">/</td><td>Chat</td></tr>
            <tr><td class="k">1–8</td><td>Debug cheats</td></tr>
          </table>
        </details>
      </div>
      ${devPanel}
    </section>
  `;

  if (import.meta.env.DEV) {
    bindDevToolsPanel(container);
  }

  const gameRoot = container.querySelector<HTMLDivElement>('#game-root');

  if (!gameRoot) {
    throw new Error('Missing game mount node.');
  }

    return new Phaser.Game({
    type: Phaser.AUTO,
    parent: gameRoot,
    backgroundColor: '#112028',
    scale: {
      mode: Phaser.Scale.EXPAND,
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

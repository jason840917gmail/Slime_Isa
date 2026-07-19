import Phaser from 'phaser';

import { BootScene } from './scenes/BootScene';
import { WorldScene } from './scenes/WorldScene';
import { MapLoadScene } from './scenes/MapLoadScene';
import { bindDevToolsPanel, createDevToolsPanel } from './devTools';

export async function createGame(container: HTMLDivElement): Promise<Phaser.Game> {
  const editorMapId = import.meta.env.DEV
    ? new URLSearchParams(window.location.search).get('editor')
    : null;
  const isEditor = editorMapId !== null;
  const editorScenes = isEditor
    ? await Promise.all([
        import('./editor/MapEditorLoadScene').then((module) => module.MapEditorLoadScene),
        import('./editor/MapEditorScene').then((module) => module.MapEditorScene),
      ])
    : [];
  const devPanel = import.meta.env.DEV && !isEditor ? createDevToolsPanel() : '';
  if (isEditor) document.title = `Field Cartographer — ${editorMapId}`;

  container.innerHTML = `
    <section class="game-shell${import.meta.env.DEV && !isEditor ? ' is-dev-mode' : ''}${isEditor ? ' is-map-editor' : ''}">
      <div class="canvas-frame">
        <div id="game-root"></div>
        ${isEditor ? '' : `<details class="keymap-panel" open>
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
        </details>`}
      </div>
      ${isEditor ? '<aside class="map-editor-panel" data-map-editor-panel></aside>' : ''}
      ${devPanel}
    </section>
  `;

  if (import.meta.env.DEV && !isEditor) {
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
    scene: [BootScene, MapLoadScene, WorldScene, ...editorScenes],
  });
}

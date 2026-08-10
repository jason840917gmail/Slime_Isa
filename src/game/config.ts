import Phaser from 'phaser';

import { BootScene } from './scenes/BootScene';
import { WorldScene } from './scenes/WorldScene';
import { MapLoadScene } from './scenes/MapLoadScene';
import { bindDevToolsPanel, createDevToolsPanel } from './devTools';

export async function createGame(container: HTMLDivElement): Promise<Phaser.Game | undefined> {
  const editorMapId = import.meta.env.DEV
    ? new URLSearchParams(window.location.search).get('editor')
    : null;
  const characterStudio = import.meta.env.DEV
    ? new URLSearchParams(window.location.search).get('studio') === 'characters'
    : false;
  const projectileStudio = import.meta.env.DEV
    ? new URLSearchParams(window.location.search).get('studio') === 'projectiles'
    : false;
  const weaponStudio = import.meta.env.DEV
    ? new URLSearchParams(window.location.search).get('studio') === 'weapons'
    : false;
  if (characterStudio) {
    document.title = 'Character Studio — Field Cartographer';
    const { mountCharacterStudio } = await import('./editor/CharacterStudio');
    mountCharacterStudio(container);
    return undefined;
  }
  if (projectileStudio) {
    document.title = 'Projectile Studio — Field Cartographer';
    const { mountProjectileStudio } = await import('./editor/ProjectileStudio');
    mountProjectileStudio(container);
    return undefined;
  }
  if (weaponStudio) {
    document.title = 'Weapon Studio — Field Cartographer';
    const { mountWeaponStudio } = await import('./editor/WeaponStudio');
    mountWeaponStudio(container);
    return undefined;
  }
  const isEditor = editorMapId !== null;
  const editorScenes = isEditor
    ? await Promise.all([
        import('./editor/MapEditorLoadScene').then((module) => module.MapEditorLoadScene),
        import('./editor/MapEditorScene').then((module) => module.MapEditorScene),
      ])
    : [];
  const devPanel = import.meta.env.DEV && !isEditor ? createDevToolsPanel() : '';
  if (isEditor) document.title = `Field Cartographer â€” ${editorMapId}`;

  container.innerHTML = `
    <section class="game-shell${import.meta.env.DEV && !isEditor ? ' is-dev-mode' : ''}${isEditor ? ' is-map-editor' : ''}">
      <div class="canvas-frame">
        <div id="game-root"></div>
        ${isEditor ? '' : `<details class="keymap-panel" open>
          <summary>âŒ¨ Controls</summary>
          <table>
            <tr><td class="k">Arrows / IJKL</td><td>Move</td></tr>
            <tr><td class="k">E / Click</td><td>Attack</td></tr>
            <tr><td class="k">Q</td><td>Roll / dodge (i-frames)</td></tr>
            <tr><td class="k">Space</td><td>Jump <span class="lock">Lv 2</span></td></tr>
            <tr><td class="k">T</td><td>Squash Slam <span class="lock">Lv 3</span></td></tr>
            <tr><td class="k">R</td><td>Stretch Lash <span class="lock">Lv 4</span></td></tr>
            <tr><td class="k">Y</td><td>Teleport <span class="lock">Lv 5</span></td></tr>
            <tr><td class="k">F</td><td>Interact / Shop</td></tr>
            <tr><td class="k">1–5</td><td>Equip inventory weapon</td></tr>
            <tr><td class="k">Tab</td><td>Inventory</td></tr>
            <tr><td class="k">M</td><td>World Map</td></tr>
            <tr><td class="k">U</td><td>Quest Journal</td></tr>
            <tr><td class="k">C</td><td>Crafting</td></tr>
            <tr><td class="k">/</td><td>Chat</td></tr>
            <tr><td class="k">Shift + 1–8</td><td>Debug cheats</td></tr>
          </table>
        </details>`}
      </div>
      ${isEditor ? `
        <aside class="map-editor-panel" data-map-editor-panel></aside>
        <aside class="map-editor-inspector" data-map-editor-inspector></aside>
      ` : ''}
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
    backgroundColor: '#0b1020',
    scale: {
      mode: Phaser.Scale.EXPAND,
      width: 1280,
      height: 720,
    },
    // Keep authored edges crisp while allowing modernized pixel-stylized
    // source art to use richer shading than strict native-resolution sprites.
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

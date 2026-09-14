import Phaser from 'phaser';

import { BootScene } from './scenes/BootScene';
import { WorldScene } from './scenes/WorldScene';
import { MapLoadScene } from './scenes/MapLoadScene';
import { bindDevToolsPanel, createDevToolsPanel } from './devTools';
import { prepareRunStartup } from './features/persistence/StartupPersistence';
import { ModalStack } from './ui/ModalStack';

export async function createGame(container: HTMLDivElement): Promise<Phaser.Game | undefined> {
  const studioQuery = import.meta.env.DEV ? new URLSearchParams(window.location.search) : undefined;
  const studioMode = studioQuery?.get('studio');
  const editorMapId = import.meta.env.DEV
    ? studioQuery?.get('editor') ?? null
    : null;
  const characterStudio = import.meta.env.DEV
    ? studioMode === 'characters'
    : false;
  const projectileStudio = import.meta.env.DEV
    ? studioMode === 'projectiles'
    : false;
  const animationStudio = import.meta.env.DEV
    ? studioMode === 'animations' || (studioMode === 'weapons' && studioQuery?.has('animation') === true)
    : false;
  const weaponStudio = import.meta.env.DEV
    ? studioMode === 'weapons' && !animationStudio
    : false;
  const sceneStudio = import.meta.env.DEV
    ? studioMode === 'scenes'
    : false;
  if (sceneStudio) {
    document.title = 'Scene Studio — Field Cartographer';
    const { mountSceneStudio } = await import('./editor/scene-studio/SceneStudio');
    mountSceneStudio(container);
    return undefined;
  }
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
  if (animationStudio) {
    if (studioMode === 'weapons' && studioQuery) {
      studioQuery.set('studio', 'animations');
      window.history.replaceState(null, '', `?${studioQuery.toString()}`);
    }
    document.title = 'Animation Studio — Field Cartographer';
    const { mountAnimationStudio } = await import('./editor/AnimationStudio');
    mountAnimationStudio(container);
    return undefined;
  }
  if (weaponStudio) {
    document.title = 'Weapon Studio — Field Cartographer';
    const { mountWeaponStudio } = await import('./editor/WeaponStudio');
    mountWeaponStudio(container);
    return undefined;
  }
  const isEditor = editorMapId !== null;
  const modalStack = isEditor ? undefined : new ModalStack();
  const editorScenes = isEditor
    ? await Promise.all([
        import('./editor/MapEditorLoadScene').then((module) => module.MapEditorLoadScene),
        import('./editor/MapEditorScene').then((module) => module.MapEditorScene),
      ])
    : [];
  const devPanel = import.meta.env.DEV && !isEditor ? createDevToolsPanel() : '';
  if (isEditor) document.title = `Field Cartographer - ${editorMapId}`;

  if (!isEditor) await prepareRunStartup(container);

  container.innerHTML = `
    <section class="game-shell${import.meta.env.DEV && !isEditor ? ' is-dev-mode' : ''}${isEditor ? ' is-map-editor' : ''}">
      <div class="canvas-frame">
        <div id="game-root"></div>
        ${isEditor ? '' : `<details class="keymap-panel" open>
          <summary>Controls</summary>
          <table>
            <tr><td class="k">Arrows / IJKL</td><td>Move</td></tr>
            <tr><td class="k">Mouse Wheel</td><td>Zoom camera</td></tr>
            <tr><td class="k">E / Click</td><td>Attack</td></tr>
            <tr><td class="k">Q</td><td>Roll / dodge (i-frames)</td></tr>
            <tr><td class="k">Space</td><td>Jump <span class="lock">Lv 2</span></td></tr>
            <tr><td class="k">T</td><td>Squash Slam <span class="lock">Lv 3</span></td></tr>
            <tr><td class="k">R</td><td>Stretch Lash <span class="lock">Lv 4</span></td></tr>
            <tr><td class="k">Y</td><td>Teleport <span class="lock">Lv 5</span></td></tr>
            <tr><td class="k">F</td><td>Interact</td></tr>
            <tr><td class="k">1–5</td><td>Equip inventory weapon</td></tr>
            <tr><td class="k">Tab</td><td>Inventory</td></tr>
            <tr><td class="k">M</td><td>World Map</td></tr>
            <tr><td class="k">U</td><td>Quest Journal</td></tr>
            <tr><td class="k">C</td><td>Crafting</td></tr>
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
    bindDevToolsPanel(container, modalStack!);
  }

  const gameRoot = container.querySelector<HTMLDivElement>('#game-root');

  if (!gameRoot) {
    throw new Error('Missing game mount node.');
  }

  const game = new Phaser.Game({
    type: Phaser.AUTO,
    parent: gameRoot,
    backgroundColor: '#0b1020',
    scale: {
      mode: Phaser.Scale.RESIZE,
      width: 1280,
      height: 720,
      autoRound: false,
    },
    // Keep authored edges crisp while allowing modernized pixel-stylized
    // source art to use richer shading than strict native-resolution sprites.
    pixelArt: false,
    roundPixels: true,
    physics: {
      default: 'arcade',
      arcade: {
        gravity: { y: 0, x: 0 },
        debug: false,
        fps: 60,
        // WorldScene remains on Phaser's legacy automatic fixed step until its
        // authored-scene cutover. Managed SceneTree hosts disable that scene's
        // automatic update and become its single manual Arcade step owner.
        fixedStep: true,
      },
    },
    callbacks: {
      preBoot: (bootingGame) => {
        if (modalStack) bootingGame.registry.set('modalStack', modalStack);
      },
    },
    scene: [BootScene, MapLoadScene, WorldScene, ...editorScenes],
  });
  if (modalStack) game.events.once(Phaser.Core.Events.DESTROY, () => modalStack.destroy());
  return game;
}

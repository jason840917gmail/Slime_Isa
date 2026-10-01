import Phaser from 'phaser';

import { BootScene } from './scenes/BootScene';
import { WorldScene } from './scenes/WorldScene';
import { MapLoadScene } from './scenes/MapLoadScene';
import { bindDevToolsPanel, createDevToolsPanel } from './devTools';
import { prepareRunStartup } from './features/persistence/StartupPersistence';
import { ModalStack } from './ui/ModalStack';
import { createGameDescriptorRegistry } from './features/scripts/registrations';
import { ASSET_MANIFEST } from './infrastructure/assets/manifest';
import { PREPARED_SCENE_CONTENT_KEY, PreparedSceneContent } from './infrastructure/scenes/PreparedSceneContent';
import { sceneDocuments, sceneResourceDocuments } from 'virtual-scene-content';
import { sceneId } from './content/scenes/identifiers';
import { itemRegistry } from './systems/Inventory';
import { redirectLegacyStudioRoute } from './editor/scene-studio/SceneStudioRoute';
import { hideBootLoader, removeBootLoader, showBootLoader } from './presentation/BootLoader';
import { GAME_SHELL_SCENE_IDS } from './features/shell/GameShell';
import { controlRows } from './features/shell/ControlsSurfacePort';
import { loadKeyboardLayoutLabels } from './features/player/ControlLabels';

export async function createGame(container: HTMLDivElement): Promise<Phaser.Game | undefined> {
  const legacyStudioRoute = import.meta.env.DEV
    ? redirectLegacyStudioRoute(window.location.search)
    : undefined;
  if (legacyStudioRoute !== undefined) {
    window.history.replaceState(null, '', legacyStudioRoute);
  }
  const sceneStudio = import.meta.env.DEV
    && new URLSearchParams(window.location.search).get('studio') === 'scenes';
  if (sceneStudio) {
    removeBootLoader();
    document.title = 'Scene Studio — Field Cartographer';
    const { mountSceneStudio } = await import('./editor/scene-studio/SceneStudio');
    mountSceneStudio(container);
    return undefined;
  }
  const modalStack = new ModalStack();
  // Key labels follow the player's keyboard layout where the browser reports it (AZERTY shows Z Q S D).
  await loadKeyboardLayoutLabels();
  const devPanel = import.meta.env.DEV ? createDevToolsPanel() : '';

  // A startup prompt (dev `?map=` recovery choice) needs the screen; the loader returns for scene preparation.
  hideBootLoader();
  await prepareRunStartup(container);
  showBootLoader();

  const preparedSceneContent = await PreparedSceneContent.prepare({
        scenes: sceneDocuments,
        resources: sceneResourceDocuments,
        registry: createGameDescriptorRegistry(),
        sceneIds: [
          // Every character and encounter: enemies and bosses are mounted on demand
          // by spawn areas and boss camps, so new ones need no registration here.
          ...sceneDocuments
            .filter((document) => document.sceneId.startsWith('character.') || document.sceneId.startsWith('encounter.'))
            .map((document) => sceneId(document.sceneId)),
          sceneId('object.resource-stone-node'),
          sceneId('object.resource-stone-node.big-stone-mine'),
          sceneId('object.rock-amber-ore-mineable'),
          sceneId('object.resource-iron-node'),
          ...sceneDocuments
            .filter((document) => document.sceneId.startsWith('object.tree-world-solid'))
            .map((document) => sceneId(document.sceneId)),
          ...sceneDocuments
            .filter((document) => document.sceneId.startsWith('object.collectible-'))
            .map((document) => sceneId(document.sceneId)),
          ...sceneDocuments
            .filter((document) => (
              document.sceneId.startsWith('object.decoration-world-')
              || document.sceneId.startsWith('object.house-world-solid')
              || document.sceneId.startsWith('object.rock-world-wall-')
              || document.sceneId.startsWith('object.wall-stone-solid')
            ))
            .map((document) => sceneId(document.sceneId)),
          // Furniture the player can place from the inventory is mounted at runtime.
          ...itemRegistry.all().flatMap((item) => item.placeable?.sceneIds ?? []).map((id) => sceneId(id)),
          sceneId('projectile.worm-arrow'),
          sceneId('projectile.spider-web'),
          sceneId('effect.spider-web-cover'),
          sceneId('effect.basic-spear-impact'),
          sceneId('effect.basic-sword-impact'),
          sceneId('effect.slam-hammer-impact'),
          sceneId('effect.stone-impact'),
          sceneId('effect.wood-impact'),
          sceneId('effect.enemy-worm-brawler-hit'),
          sceneId('effect.boss-ground-crack'),
          sceneId('effect.matron-web-patch'),
          sceneId('weapon.basic-spear'),
          sceneId('weapon.basic-sword'),
          sceneId('weapon.goo-gauntlet'),
          sceneId('weapon.pickaxe'),
          sceneId('weapon.slam-hammer'),
          sceneId('weapon.stone-axe'),
          sceneId('weapon.stone-pickaxe'),
          sceneId('weapon.reinforced-pickaxe'),
          sceneId('weapon.iron-spear'),
          sceneId('weapon.iron-axe'),
          sceneId('weapon.stone-spear'),
          sceneId('weapon.wooden-axe'),
          sceneId('weapon.wooden-spear'),
          sceneId('audio.global'),
          sceneId('ui.hud'),
          sceneId('ui.weapon-hotbar'),
          sceneId('ui.ability-bar'),
          sceneId('ui.health-bar'),
          sceneId('ui.boss-health-bar'),
          sceneId('ui.area-title-card'),
          sceneId('ui.floating-text'),
          sceneId('ui.inventory-ui'),
          sceneId('ui.chest-inventory-panel'),
          sceneId('ui.crafting-ui'),
          sceneId('ui.quest-journal'),
          sceneId('ui.quest-offer-modal'),
          sceneId('ui.npc-dialogue'),
          sceneId('ui.quest-tracker'),
          sceneId('ui.world-map-ui'),
          ...GAME_SHELL_SCENE_IDS.map((id) => sceneId(id)),
          sceneId('ui.control-hint'),
          sceneId('ui.menu-tabs'),
          sceneId('ui.minimap'),
        ],
        hasAsset: (assetId) => Object.hasOwn(ASSET_MANIFEST.assets, assetId),
      });

  container.innerHTML = `
    <section class="game-shell${import.meta.env.DEV ? ' is-dev-mode' : ''}">
      <div class="canvas-frame">
        <div id="game-root"></div>
        <div class="scene-ui-root" data-scene-ui-root aria-label="Game interface"></div>
${import.meta.env.DEV ? `
        <details class="keymap-panel">
          <summary>Controls</summary>
          <table>
            ${controlRows().map(([key, action]) => `<tr><td class="k">${key}</td><td>${action}</td></tr>`).join('\n            ')}
            <tr><td class="k">Dev panel</td><td>Cheats and the attack-direction test</td></tr>
          </table>
        </details>
        ` : ''}
      </div>
      ${devPanel}
    </section>
  `;

  if (import.meta.env.DEV) {
    bindDevToolsPanel(container, modalStack);
  }

  const gameRoot = container.querySelector<HTMLDivElement>('#game-root');
  const sceneUiRoot = container.querySelector<HTMLDivElement>('[data-scene-ui-root]');

  if (!gameRoot) {
    throw new Error('Missing game mount node.');
  }
  if (!sceneUiRoot) {
    throw new Error('Missing universal UI mount node.');
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
        // Managed SceneTree hosts disable the world's automatic update and
        // own its single manual Arcade step.
        fixedStep: true,
      },
    },
    callbacks: {
      preBoot: (bootingGame) => {
        bootingGame.registry.set('modalStack', modalStack);
        bootingGame.registry.set(PREPARED_SCENE_CONTENT_KEY, preparedSceneContent);
        bootingGame.registry.set('universal-ui-root', sceneUiRoot);
      },
    },
    scene: [BootScene, MapLoadScene, WorldScene],
  });
  // Development only: lets automated playtests inspect the running game.
  if (import.meta.env.DEV) Object.assign(window, { __slimeGame: game });
  game.events.once(Phaser.Core.Events.DESTROY, () => modalStack.destroy());
  game.events.once(Phaser.Core.Events.DESTROY, () => preparedSceneContent.dispose());
  return game;
}

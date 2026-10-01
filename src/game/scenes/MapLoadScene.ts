import Phaser from 'phaser';

import { peekRunNavigation, resolveAreaRequest } from '../features/world-navigation/AreaNavigation';
import { PREPARED_SCENE_CONTENT_KEY, PreparedSceneContent } from '../infrastructure/scenes/PreparedSceneContent';
import { WorldSceneLoader } from '../infrastructure/scenes/WorldSceneLoader';
import { assertAssetsLoaded, queueAssets } from '../infrastructure/assets/AssetLoader';
import { createLoadingBar } from '../infrastructure/assets/LoadingBar';
import { worldImageAssetIds } from '../infrastructure/assets/WorldAssetSets';

/**
 * Resolves lazy authored content, then loads the images only this world needs
 * (`worldAssetSets.generated.json`), both behind a loading bar, before
 * WorldScene creates physics or entities.
 */
export class MapLoadScene extends Phaser.Scene {
  private loadController?: AbortController;

  constructor() {
    super('map-load');
  }

  create(): void {
    const request = resolveAreaRequest({});
    const pending = peekRunNavigation();
    const devMapOverride = import.meta.env.DEV
      ? new URLSearchParams(window.location.search).get('map')
      : null;
    // Explicit load/reset/area handoffs own precedence over development
    // query overrides. The query remains useful only when no run request is
    // waiting to be consumed.
    const mapId = pending?.mapId ?? devMapOverride ?? request.area.mapId;
    const content = this.game.registry.get(PREPARED_SCENE_CONTENT_KEY);
    if (!(content instanceof PreparedSceneContent)) {
      throw new Error('MapLoadScene requires prepared universal scene content.');
    }
    this.loadController?.abort();
    const controller = new AbortController();
    this.loadController = controller;
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => controller.abort());
    const bar = createLoadingBar(this, 'Loading…');

    void new WorldSceneLoader(content).load(mapId, controller.signal)
      .then((loadedWorld) => {
        if (controller.signal.aborted) return;
        const start = () => {
          if (controller.signal.aborted) return;
          bar.destroy();
          this.scene.start('world', {
            // A development `?map=` preview plays as that map's own area.
            areaId: pending?.mapId ?? (devMapOverride && !pending ? mapId : request.area.id),
            entryEdge: pending?.entryEdge ?? request.entryEdge,
            entryDoor: pending?.entryDoor ?? request.entryDoor,
            loadedWorld,
          });
        };
        const worldImages = worldImageAssetIds(mapId);
        if (queueAssets(this, worldImages) === 0) {
          start();
          return;
        }
        this.load.on(Phaser.Loader.Events.PROGRESS, (value: number) => bar.setProgress(value));
        this.load.once(Phaser.Loader.Events.COMPLETE, () => {
          if (controller.signal.aborted) return;
          assertAssetsLoaded(this, worldImages, `World '${mapId}' images`);
          start();
        });
        this.load.start();
      })
      .catch((error: unknown) => {
        if (controller.signal.aborted || (error instanceof Error && error.name === 'AbortError')) return;
        const message = error instanceof Error ? error.message : String(error);
        console.error(error);
        bar.destroy();
        this.add.text(this.cameras.main.centerX, this.cameras.main.centerY, `Map failed to load\n\n${message}`, {
          fontFamily: 'Arial', fontSize: '20px', color: '#ff8f8f', align: 'center',
        }).setOrigin(0.5);
      });
  }
}

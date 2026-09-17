import Phaser from 'phaser';

import { peekRunNavigation, resolveAreaRequest } from '../features/world-navigation/AreaNavigation';
import { mapRepository } from '../infrastructure/maps/MapRepository';
import { PREPARED_SCENE_CONTENT_KEY, PreparedSceneContent } from '../infrastructure/scenes/PreparedSceneContent';
import { WorldSceneLoader } from '../infrastructure/scenes/WorldSceneLoader';

/** Resolves lazy authored content before WorldScene creates physics or entities. */
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
    const status = this.add.text(
      this.cameras.main.centerX,
      this.cameras.main.centerY,
      'Loading map...',
      { fontFamily: 'Arial', fontSize: '20px', color: '#d8fbff' },
    ).setOrigin(0.5);

    void new WorldSceneLoader(mapRepository, content).load(mapId, controller.signal)
      .then((loadedWorld) => {
        if (controller.signal.aborted) return;
        status.destroy();
        this.scene.start('world', {
          areaId: pending?.mapId ?? request.area.id,
          entryEdge: pending?.entryEdge ?? request.entryEdge,
          loadedWorld,
        });
      })
      .catch((error: unknown) => {
        if (controller.signal.aborted || (error instanceof Error && error.name === 'AbortError')) return;
        const message = error instanceof Error ? error.message : String(error);
        console.error(error);
        status.setText(`Map failed to load\n\n${message}`).setColor('#ff8f8f');
      });
  }
}

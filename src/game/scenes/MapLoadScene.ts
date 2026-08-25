import Phaser from 'phaser';

import { peekRunNavigation, resolveAreaRequest } from '../features/world-navigation/AreaNavigation';
import { mapRepository } from '../infrastructure/maps/MapRepository';

/** Resolves lazy authored content before WorldScene creates physics or entities. */
export class MapLoadScene extends Phaser.Scene {
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
    const status = this.add.text(
      this.cameras.main.centerX,
      this.cameras.main.centerY,
      'Loading map...',
      { fontFamily: 'Arial', fontSize: '20px', color: '#d8fbff' },
    ).setOrigin(0.5);

    void mapRepository.load(mapId)
      .then((loadedMap) => {
        if (!loadedMap) {
          throw new Error(`Required authored map '${mapId}' was not found in src/game/content/maps`);
        }
        status.destroy();
        this.scene.start('world', {
          areaId: pending?.mapId ?? request.area.id,
          entryEdge: pending?.entryEdge ?? request.entryEdge,
          loadedMap,
        });
      })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : String(error);
        console.error(error);
        status.setText(`Map failed to load\n\n${message}`).setColor('#ff8f8f');
      });
  }
}

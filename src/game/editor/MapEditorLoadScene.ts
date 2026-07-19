import Phaser from 'phaser';

import { mapRepository } from '../infrastructure/maps/MapRepository';

export class MapEditorLoadScene extends Phaser.Scene {
  constructor() {
    super('map-editor-load');
  }

  create(): void {
    const mapId = new URLSearchParams(window.location.search).get('editor') ?? 'icege';
    const status = this.add.text(
      this.cameras.main.centerX,
      this.cameras.main.centerY,
      'Opening authored map...',
      { fontFamily: 'Trebuchet MS', fontSize: '20px', color: '#f2d58a' },
    ).setOrigin(0.5);

    void mapRepository.load(mapId)
      .then((loadedMap) => {
        if (!loadedMap) throw new Error(`Map '${mapId}' was not found`);
        status.destroy();
        this.scene.start('map-editor', { loadedMap });
      })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : String(error);
        console.error(error);
        status.setText(`Map editor could not open '${mapId}'\n\n${message}`).setColor('#ff8f78');
      });
  }
}

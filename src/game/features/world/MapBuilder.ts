import Phaser from 'phaser';

import type {
  MapExit,
  MapEnemySafeZone,
  MapFile,
  MapPoint,
  MapSpawns,
} from '../../content/maps/mapFormat';
import {
  isObjectArchetypeId,
} from '../../content/objects/ObjectCatalog';
import { isWorldTileId, type WorldTileId } from '../../content/terrain/TileCatalog';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { ObjectFactory } from '../objects/ObjectFactory';
import {
  TerrainTransitionLayer,
  TerrainTransitionRenderer,
} from './TerrainTransitionRenderer';
import { TileFactory } from './TileFactory';

export interface BuiltMap {
  readonly terrainGrid: WorldTileId[][];
  readonly playerSpawn: MapPoint;
  readonly entries: MapFile['player']['entries'];
  readonly exits: readonly MapExit[];
  readonly enemySafeZones: readonly MapEnemySafeZone[];
  readonly spawns?: MapSpawns;
}

interface MapBuilderContext {
  readonly scene: Phaser.Scene;
  readonly map: MapFile;
  readonly dimensions: WorldDimensions;
  readonly collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  readonly seed: number;
  readonly behaviorGroups?: Readonly<Record<string, Phaser.Physics.Arcade.StaticGroup>>;
}

/** Builds validated authored-map data through the same tile/object factories as runtime content. */
export class MapBuilder {
  private readonly tileFactory: TileFactory;
  private readonly objectFactory: ObjectFactory;
  private transitionLayer?: TerrainTransitionLayer;

  constructor(private readonly ctx: MapBuilderContext) {
    this.tileFactory = new TileFactory({
      scene: ctx.scene,
      collisionTiles: ctx.collisionTiles,
      dimensions: ctx.dimensions,
      seed: ctx.seed,
    });
    this.objectFactory = new ObjectFactory({
      scene: ctx.scene,
      staticGroup: ctx.collisionTiles,
      behaviorGroups: ctx.behaviorGroups,
    });
    ctx.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.transitionLayer?.destroy());
  }

  build(): BuiltMap {
    const terrainGrid: WorldTileId[][] = [];

    for (const layer of this.ctx.map.layers) {
      layer.rows.forEach((row, tileY) => {
        const targetRow = terrainGrid[tileY] ?? [];
        for (let tileX = 0; tileX < row.length; tileX += 1) {
          const tileId = layer.legend[row[tileX]];
          if (!isWorldTileId(tileId)) {
            throw new Error(`Map '${this.ctx.map.mapId}' reached MapBuilder with invalid tile '${tileId}'`);
          }
          this.tileFactory.create(tileId, tileX, tileY);
          targetRow[tileX] = tileId;
        }
        terrainGrid[tileY] = targetRow;
      });
    }

    this.transitionLayer?.destroy();
    this.transitionLayer = new TerrainTransitionRenderer({
      scene: this.ctx.scene,
      tileFactory: this.tileFactory,
      dimensions: this.ctx.dimensions,
      seed: this.ctx.seed,
    }).render(terrainGrid);

    for (const object of this.ctx.map.objects) {
      if (!isObjectArchetypeId(object.objectId)) {
        throw new Error(`Map '${this.ctx.map.mapId}' reached MapBuilder with invalid object '${object.objectId}'`);
      }
      this.objectFactory.create(object.objectId, {
        x: object.x,
        y: object.y,
        visualId: object.visualId,
        initialState: object.initialState,
      });
    }

    this.ctx.scene.physics.world.setBounds(
      0,
      0,
      this.ctx.dimensions.width,
      this.ctx.dimensions.height,
    );

    return {
      terrainGrid,
      playerSpawn: this.ctx.map.player.spawn,
      entries: this.ctx.map.player.entries,
      exits: this.ctx.map.exits ?? [],
      enemySafeZones: this.ctx.map.enemySafeZones ?? this.ctx.map.spawns?.safeZones ?? [],
      spawns: this.ctx.map.spawns,
    };
  }
}

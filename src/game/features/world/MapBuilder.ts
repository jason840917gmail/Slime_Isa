import Phaser from 'phaser';

import type {
  MapExit,
  MapEnemySpawnArea,
  MapEnemySafeZone,
  MapFile,
  MapPoint,
  MapSpawns,
  MapNpcWanderArea,
} from '../../content/maps/mapFormat';
import {
  getObjectArchetype,
  isObjectArchetypeId,
  type ObjectArchetypeId,
} from '../../content/objects/ObjectCatalog';
import { isWorldTileId, type WorldTileId } from '../../content/terrain/TileCatalog';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { ObjectFactory, type CreateObjectOptions, type ObjectOccluderRegistration } from '../objects/ObjectFactory';
import {
  TerrainTransitionLayer,
  TerrainTransitionRenderer,
} from './TerrainTransitionRenderer';
import { TileFactory } from './TileFactory';
import { getCharacterPackage } from '../../content/characters/CharacterCatalog';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import { NpcActor } from '../npcs/NpcActor';
import type { CharacterTrackEvent } from '../characters/CharacterAnimationTrackRunner';

export interface BuiltMap {
  readonly terrainGrid: WorldTileId[][];
  readonly playerSpawn: MapPoint;
  readonly entries: MapFile['player']['entries'];
  readonly exits: readonly MapExit[];
  readonly enemySafeZones: readonly MapEnemySafeZone[];
  readonly enemySpawnAreas: readonly MapEnemySpawnArea[];
  readonly npcWanderAreas: readonly MapNpcWanderArea[];
  readonly npcActors: readonly NpcActor[];
  readonly spawns?: MapSpawns;
}

export interface BuiltObjectRegistration {
  readonly image: Phaser.GameObjects.Image;
  readonly objectId: string;
  readonly instanceId: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
  readonly npcDefinitionId?: string;
}

export interface BuiltNpcRegistration {
  readonly actor: NpcActor;
  readonly objectId: string;
  readonly instanceId: string;
  readonly npcDefinitionId: string;
  readonly x: number;
  readonly y: number;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

interface MapBuilderContext {
  readonly scene: Phaser.Scene;
  readonly map: MapFile;
  readonly dimensions: WorldDimensions;
  readonly collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  readonly seed: number;
  readonly behaviorGroups?: Readonly<Record<string, Phaser.Physics.Arcade.StaticGroup>>;
  readonly onObjectCreated?: (registration: BuiltObjectRegistration) => void;
  readonly onNpcCreated?: (registration: BuiltNpcRegistration) => void;
  readonly onNpcPresentationEvent?: (event: CharacterTrackEvent, instanceId: string) => void;
  readonly onTerrainBuilt?: (terrainGrid: WorldTileId[][]) => void;
  readonly registerOccluder?: (registration: ObjectOccluderRegistration) => { dispose(): void };
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
      registerOccluder: ctx.registerOccluder,
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
    this.ctx.onTerrainBuilt?.(terrainGrid);

    const npcActors: NpcActor[] = [];
    for (const object of this.ctx.map.objects) {
      if (!isObjectArchetypeId(object.objectId)) {
        throw new Error(`Map '${this.ctx.map.mapId}' reached MapBuilder with invalid object '${object.objectId}'`);
      }
      const definition = getObjectArchetype(object.objectId);
      if (definition.npc) {
        const npcDefinition = getNpcDefinition(definition.npc.definitionId);
        if (!npcDefinition) throw new Error(`Object '${object.objectId}' references unknown NPC '${definition.npc.definitionId}'`);
        const packageValue = getCharacterPackage(npcDefinition.characterId);
        const area = this.ctx.map.npcWanderAreas?.find((candidate) => candidate.npcInstanceId === object.instanceId);
        let actor: NpcActor | undefined;
        actor = new NpcActor(this.ctx.scene, { packageValue, definitionId: definition.npc.definitionId, instanceId: object.instanceId, x: object.x, y: object.y, area, getDepth: () => actor?.anchor.y ?? object.y, onPresentationEvent: this.ctx.onNpcPresentationEvent });
        if (!actor) throw new Error(`Failed to create NPC actor for '${object.instanceId}'`);
        npcActors.push(actor);
        this.ctx.scene.physics.add.collider(actor.anchor, this.ctx.collisionTiles);
        this.ctx.onNpcCreated?.({ actor, objectId: object.objectId, instanceId: object.instanceId, npcDefinitionId: definition.npc.definitionId, x: object.x, y: object.y, initialState: object.initialState });
        if (!this.ctx.onNpcCreated) this.ctx.onObjectCreated?.({ image: actor.image, objectId: object.objectId, instanceId: object.instanceId, initialState: object.initialState, npcDefinitionId: definition.npc.definitionId });
        continue;
      }
      const image = this.objectFactory.create(object.objectId, {
        x: object.x,
        y: object.y,
        visualId: object.visualId,
        sortId: object.instanceId,
        initialState: object.initialState,
      });
      this.ctx.onObjectCreated?.({
        image,
        objectId: object.objectId,
        instanceId: object.instanceId,
        initialState: object.initialState,
        npcDefinitionId: getObjectArchetype(object.objectId).npc?.definitionId,
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
      enemySpawnAreas: this.ctx.map.enemySpawnAreas ?? [],
      npcWanderAreas: this.ctx.map.npcWanderAreas ?? [],
      npcActors,
      spawns: this.ctx.map.spawns,
    };
  }

  createDynamicObject(
    objectId: ObjectArchetypeId,
    options: CreateObjectOptions,
  ): Phaser.GameObjects.Image {
    return this.objectFactory.create(objectId, options);
  }
}

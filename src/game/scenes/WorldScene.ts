import Phaser from 'phaser';
import {
  isWorldTileId,
  isTileCollidable,
  type WorldTileId,
} from '../content/terrain/TileCatalog';
import { gameState } from '../core/GameState';
import { gameEvents } from '../core/EventBus';
import { saveSystem } from '../core/SaveSystem';
import {
  PlayerHealthController,
  type AcceptedDamageResult,
  type DamageRequest,
} from '../features/player/PlayerHealthController';
import { StatusEffectManager } from '../systems/StatusEffects';
import { getStats } from '../systems/PlayerStats';
import { PlayerAbilityController } from '../features/player/PlayerAbilityController';
import type { PlayerAbilityId } from '../features/player/PlayerAbilityDefinitions';
import { playerInventory, itemRegistry, weaponItemFor } from '../systems/Inventory';
import { playerWeaponLoadout } from '../systems/WeaponLoadout';
import { floatingText } from '../ui/FloatingText';
import { hitboxPool } from '../combat/Hitbox';
import { AREAS, type AreaDef, type AreaId, type Direction } from '../world/Area';
import { BIOMES } from '../world/Biome';
import { questTracker } from '../quests/QuestTracker';
import { ModalStack } from '../ui/ModalStack';
import { DisposableBag } from '../shared/lifecycle/Disposable';
import { PlayerController } from '../features/player/PlayerController';
import type { PlayerActorPort } from '../features/player/PlayerServicePorts';
import type { WorldVisual } from '../presentation/WorldVisual';
import { UI_THEME } from '../presentation/theme';
import {
  clearOneShotNavigationParams,
  navigateToArea as navigateToAreaUrl,
  resolveAreaRequest,
  restoreAreaTransition,
} from '../features/world-navigation/AreaNavigation';
import { WorldDebugRenderer } from '../dev/WorldDebugRenderer';
import { RenderingDiagnostics } from '../dev/RenderingDiagnostics';
import { CombatController } from '../features/combat/CombatController';
import { ResourceNodeController } from '../features/resources/ResourceNodeController';
import { worldProgress } from '../features/progression/WorldProgress';
import { CollectibleController } from '../features/collectibles/CollectibleController';
import { CollectibleEventChannel } from '../features/collectibles/CollectibleEventChannel';
import { CollectibleReactionController } from '../features/collectibles/CollectibleReactionController';
import type { WorldDropRequest } from '../features/collectibles/WorldDropRequest';
import { InventoryDropController } from '../features/collectibles/InventoryDropController';
import type { InventoryDropCellInspection } from '../features/collectibles/InventoryDropPlacement';
import { OcclusionController } from '../features/occlusion/OcclusionController';
import { DepthDiagnostics } from '../features/occlusion/DepthDiagnostics';
import { TileFactory } from '../features/world/TileFactory';
import { TerrainTransitionLayer, TerrainTransitionRenderer } from '../features/world/TerrainTransitionRenderer';
import { resolveBodyBottom, resolveWorldDepth } from '../presentation/WorldDepth';
import { ResponsiveCameraController } from '../presentation/ResponsiveCameraController';
import type { WorldDimensions } from '../world/WorldDimensions';
import { updateDevToolsCameraZoom } from '../devTools';
import type { GameLocationData, FacingDirection } from '../infrastructure/persistence/SaveSchema';
import { InteractionRouter } from '../features/interaction/InteractionRouter';
import { QuestNpcController } from '../features/interaction/QuestNpcController';
import { QuestNotificationPresenter } from '../features/quests/QuestNotificationPresenter';
import { playerInventoryWorldTransaction } from '../features/progression/InventoryWorldTransaction';
import { PREPARED_SCENE_CONTENT_KEY, PreparedSceneContent } from '../infrastructure/scenes/PreparedSceneContent';
import type { LoadedWorldScene } from '../infrastructure/scenes/WorldSceneLoader';
import { UniversalSceneWorldController } from '../features/world/UniversalSceneWorldController';
import type { MapBossCamp, MapEnemySafeZone, MapEnemySpawnArea, MapFile, MapPoint, MapSpawns } from '../content/maps/mapFormat';
import type { WorldExitRequest, WorldExitResult } from '../features/scripts/WorldExitScript';

const COLLECTIBLE_EVENTS = new CollectibleEventChannel(gameEvents);

interface WorldSceneData {
  areaId?: AreaId;
  entryEdge?: Direction;
  loadedWorld?: LoadedWorldScene;
}

interface AuthoredWorldMetadata {
  readonly terrainGrid: WorldTileId[][];
  readonly playerSpawn: MapPoint;
  readonly entries: MapFile['player']['entries'];
  readonly enemySafeZones: readonly MapEnemySafeZone[];
  readonly enemySpawnAreas: readonly MapEnemySpawnArea[];
  readonly bossCamps: readonly MapBossCamp[];
  readonly spawns?: MapSpawns;
}

export class WorldScene extends Phaser.Scene {
  private static sessionStarted = false;
  private player!: Phaser.Physics.Arcade.Sprite;
  private playerVisual?: WorldVisual;
  private collisionTiles!: Phaser.Physics.Arcade.StaticGroup;
  private currentAnimation = 'slime-idle';
  private actionLocked = false;
  private paused = false;
  private pauseSources = new Set<string>();
  private terrainGrid: WorldTileId[][] = [];
  private resourceNodes?: ResourceNodeController;
  private collectibles?: CollectibleController;
  private pendingWorldDrops: WorldDropRequest[] = [];
  private inventoryDrops?: InventoryDropController;
  private playerController!: PlayerController;
  private healthSystem?: PlayerHealthController;
  private statusEffects?: StatusEffectManager;
  private modalStack?: ModalStack;
  private interactionRouter?: InteractionRouter;
  private questNpcController?: QuestNpcController;
  private universalWorld?: UniversalSceneWorldController;
  private questNotifications?: QuestNotificationPresenter;
  private abilitySystem?: PlayerAbilityController;
  private iFrameFlashActive = false;
  private playerKnockbackUntil = 0;
  private actionAnimationUntil?: number;
  private combatController?: CombatController;
  private currentArea: AreaDef = AREAS.icege;
  private worldDimensions!: WorldDimensions;
  private loadedMap!: LoadedWorldScene['loadedMap'];
  private loadedWorld?: LoadedWorldScene;
  private builtMap?: AuthoredWorldMetadata;
  private terrainTransitionLayer?: TerrainTransitionLayer;
  private entryEdge?: Direction;
  private transitioning = false;
  private nextGateMessageAt = 0;
  private levelUpNoticeHandler?: (payload: { level: number }) => void;
  private questCompleteHandler?: (payload: { questId: string; title: string; rewards: { coins?: number; xp?: number } }) => void;
  private restoredFromAreaTransition = false;
  private pendingRestoreLocation?: GameLocationData;
  private debugRenderer?: WorldDebugRenderer;
  private occlusionController?: OcclusionController;
  private depthDiagnostics?: DepthDiagnostics;
  private cameraController?: ResponsiveCameraController;
  private renderingDiagnostics?: RenderingDiagnostics;
  private uiCamera?: Phaser.Cameras.Scene2D.Camera;
  private cameraLayerAssignments = new WeakMap<Phaser.GameObjects.GameObject, 'world' | 'ui'>();
  private disposables = new DisposableBag();

  constructor() {
    super('world');
  }

  init(data: WorldSceneData = {}): void {
    const request = resolveAreaRequest(data);
    if (!data.loadedWorld) {
      throw new Error(`WorldScene requires an authored map for area '${request.area.id}'`);
    }
    this.currentArea = request.area;
    this.loadedWorld = data.loadedWorld;
    this.loadedMap = this.loadedWorld.loadedMap;
    this.worldDimensions = this.loadedMap.dimensions;
    this.builtMap = undefined;
    this.entryEdge = request.entryEdge;
    this.transitioning = false;
    this.nextGateMessageAt = 0;
  }

  create(): void {
    this.resetSceneStateForAreaLoad();
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, this.resetSceneStateForAreaLoad, this);
    this.game.events.once(Phaser.Core.Events.DESTROY, this.resetSceneStateForAreaLoad, this);
    this.disposables.add(() => this.game.events.off(Phaser.Core.Events.DESTROY, this.resetSceneStateForAreaLoad, this));
    this.pendingRestoreLocation = undefined;
    this.restoredFromAreaTransition = this.restoreAreaTransitionHandoff();
    // Install the complete run before authored objects are registered. Resource
    // nodes consult WorldProgress during registration, so loading afterwards
    // would build the first scene from stale map state.
    if (!WorldScene.sessionStarted && !this.restoredFromAreaTransition) {
      if (!saveSystem.hasInstalledRun()) saveSystem.startNewRun();
      WorldScene.sessionStarted = true;
    }
    saveSystem.startAutoSave();
    playerWeaponLoadout.reconcile();

    // Phase 1: World entities (no cross-system side effects)
    this.createCollisionLayer();
    this.occlusionController = new OcclusionController(this);
    const modalStack = this.game.registry.get('modalStack');
    if (!(modalStack instanceof ModalStack)) {
      throw new Error('WorldScene requires a shared ModalStack.');
    }
    this.modalStack = modalStack;
    this.interactionRouter = new InteractionRouter(this);
    this.questNpcController = new QuestNpcController({
      scene: this,
      getPlayer: () => this.player,
      router: this.interactionRouter,
      getOfferSurface: () => this.universalWorld?.questOfferSurface,
      showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
    });
    this.buildWorld();
    this.questNpcController.finalize();
    this.statusEffects = new StatusEffectManager();
    this.healthSystem = new PlayerHealthController({
      getPlayerPosition: () => ({ x: this.player.x, y: this.player.y }),
      applyKnockback: (direction, strength, durationMs) => {
        this.playerKnockbackUntil = Math.max(
          this.playerKnockbackUntil,
          this.simulationNow() + durationMs,
        );
        this.playerController.applyKnockback(new Phaser.Math.Vector2(direction.x, direction.y), strength, durationMs);
        this.playAnimation('slime-knockback', true);
      },
      onHit: (result) => this.onPlayerHit(result),
      onDeath: () => this.onPlayerDeath(),
    });
    this.createPlayer();
    this.disposables.add(saveSystem.setLocationProvider(() => this.capturePlayerLocation()));
    this.depthDiagnostics = new DepthDiagnostics({
      scene: this,
      getPlayer: () => this.player,
      getOcclusionController: () => this.occlusionController,
    });
    this.createPhysics();
    this.createCamera();
    this.createRenderingDiagnostics();
    this.createDebugRenderer();

    // Phase 2: UI systems
    this.createCollectibleReactions();

    // Phase 1 systems: health presentation, abilities, level-up modal, inventory UI
    this.abilitySystem = new PlayerAbilityController({
      scene: this,
      dimensions: this.worldDimensions,
      getPlayer: () => this.player,
      getPlayerVisual: () => this.playerVisual!,
      stopPlayerMotion: () => this.stopPlayerMotion(),
      teleportPlayer: (position) => this.teleportPlayer(position),
      isActionLocked: () => this.actionLocked,
      setActionLocked: (locked) => { this.actionLocked = locked; },
      getFacing: () => this.playerController.facing,
      playAnimation: (key) => this.playAnimation(key),
      getTerrainGrid: () => this.terrainGrid,
      getCombatTargets: () => this.combatController?.targets ?? null,
      nowMs: () => this.simulationNow(),
    });
    this.universalWorld?.worldMapSurface.discover(this.currentArea.id);
    this.questNotifications = new QuestNotificationPresenter({
      getPosition: () => ({ x: this.player.x, y: this.player.y }),
      show: (x, y, message, color, important) => floatingText.spawn(this, x, y, message, color, important),
    });
    questTracker.start();
    // Phase 2: combat system
    this.createCombatSystem();

    this.bindHotkeys();
    this.bindDebugCheats();

    const persistenceModalHandler = (payload: { open: boolean }) => {
      this.setSimulationPaused('persistence', payload.open);
    };
    gameEvents.on('persistence.modal', persistenceModalHandler);
    this.disposables.add(() => gameEvents.off('persistence.modal', persistenceModalHandler));

    // Notify when an ability unlocks via level-up.
    this.levelUpNoticeHandler = (p) => {
      if (p.level === 2) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'JUMP UNLOCKED!', 'green', true);
      } else if (p.level === 3) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'SQUASH SLAM!', 'green', true);
      } else if (p.level === 4) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'STRETCH LASH!', 'orange', true);
      } else if (p.level === 5) {
        floatingText.spawn(this, this.player.x, this.player.y - 50, 'TELEPORT UNLOCKED!', 'cyan', true);
      }
    };
    gameEvents.on('level.up', this.levelUpNoticeHandler);
    this.disposables.add(() => {
      if (this.levelUpNoticeHandler) gameEvents.off('level.up', this.levelUpNoticeHandler);
    });

    this.questCompleteHandler = (p) => {
      const reward = [`+${p.rewards.coins ?? 0}c`, `+${p.rewards.xp ?? 0} XP`].join('  ');
      floatingText.spawn(this, this.player.x, this.player.y - 70, `QUEST COMPLETE: ${p.title}`, 'yellow', true);
      floatingText.spawn(this, this.player.x, this.player.y - 48, reward, 'green', true);
    };
    gameEvents.on('quest.completed', this.questCompleteHandler);
    this.disposables.add(() => {
      if (this.questCompleteHandler) gameEvents.off('quest.completed', this.questCompleteHandler);
    });

    // Phase 3: One-time cross-system sync
    this.scale.on('resize', this.handleResize, this);
    this.disposables.add(() => this.scale.off('resize', this.handleResize, this));
    gameEvents.emit('area.enter', { areaId: this.currentArea.id });
    saveSystem.writeRecovery(this.capturePlayerLocation());
    clearOneShotNavigationParams();
    this.universalWorld?.showAreaTitle(this.currentArea.name, BIOMES[this.currentArea.biome].titleColor);
    this.syncCameraLayers();
  }

  private resetSceneStateForAreaLoad(): void {
    // Release NPC interaction sessions before destroying their actors. Modal
    // close callbacks can then return every movement lock while the actor
    // lifecycle is still alive; actor teardown follows as the final NPC step.
    this.questNpcController?.destroy();
    this.questNpcController = undefined;
    this.builtMap = undefined;
    this.terrainTransitionLayer?.destroy();
    this.terrainTransitionLayer = undefined;
    this.disposables.dispose();
    this.disposables = new DisposableBag();
    this.abilitySystem?.destroy();
    this.statusEffects?.destroy();
    this.debugRenderer?.destroy();
    this.renderingDiagnostics?.destroy();
    this.renderingDiagnostics = undefined;
    this.cameraController = undefined;
    this.questNotifications?.destroy();
    this.questNotifications = undefined;
    this.interactionRouter?.destroy();
    this.interactionRouter = undefined;
    this.combatController?.destroy();
    this.universalWorld?.destroy();
    this.universalWorld = undefined;
    floatingText.clearScene(this);
    this.resourceNodes?.destroy();
    this.resourceNodes = undefined;
    this.inventoryDrops = undefined;
    this.pendingWorldDrops = [];
    this.collectibles?.destroy();
    this.collectibles = undefined;
    this.occlusionController?.destroy();
    this.occlusionController = undefined;
    this.depthDiagnostics?.destroy();
    this.depthDiagnostics = undefined;
    this.healthSystem?.destroy();
    this.playerVisual = undefined;
    if (this.levelUpNoticeHandler) {
      gameEvents.off('level.up', this.levelUpNoticeHandler);
      this.levelUpNoticeHandler = undefined;
    }
    if (this.questCompleteHandler) {
      gameEvents.off('quest.completed', this.questCompleteHandler);
      this.questCompleteHandler = undefined;
    }
    hitboxPool.clearScene(this);

    this.combatController = undefined;
    this.pauseSources.clear();
    this.paused = false;
    this.actionLocked = false;
    this.actionAnimationUntil = undefined;
    // Gameplay deadlines are simulation times of the area runtime being replaced.
    this.playerKnockbackUntil = 0;
  }

  private restoreAreaTransitionHandoff(): boolean {
    const restored = restoreAreaTransition();
    if (restored.restored && restored.data) {
      saveSystem.install(restored.data);
      if (restored.kind === 'reset') saveSystem.completeResetHandoff();
      this.pendingRestoreLocation = restored.data.location;
      WorldScene.sessionStarted = true;
    }
    return restored.restored;
  }

  private setSimulationPaused(source: string, paused: boolean): void {
    if (paused) {
      this.pauseSources.add(source);
    } else {
      this.pauseSources.delete(source);
    }

    const shouldPause = this.pauseSources.size > 0;
    if (this.paused === shouldPause) {
      if (shouldPause) this.stopMovingBodies();
      return;
    }

    this.paused = shouldPause;
    this.universalWorld?.setPaused(shouldPause);
    if (shouldPause) {
      this.stopMovingBodies();
      this.physics.world.pause();
    } else {
      this.physics.world.resume();
    }
  }

  private stopMovingBodies(): void {
    const stop = (child: Phaser.GameObjects.GameObject): void => {
      const body = (child as Phaser.GameObjects.GameObject & {
        body?: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody;
      }).body;

      if (body instanceof Phaser.Physics.Arcade.Body) {
        body.setVelocity(0, 0);
      }
    };

    this.stopPlayerMotion();
    this.combatController?.targets.children.each((child) => {
      stop(child);
      return true;
    });
  }

  update(_time: number, delta: number): void {
    if (this.universalWorld) {
      this.universalWorld.advanceFrame(delta / 1000);
      return;
    }
    this.updatePresentation(delta);
    if (!this.paused) this.updateGameplay(delta);
  }

  private updatePresentation(_delta: number): void {
    this.syncCameraLayers();

    if (this.paused) {
      this.stopPlayerMotion();
      this.debugRenderer?.update();
    }
  }

  private updateGameplay(delta: number): void {
    this.universalWorld?.minimapSurface.update(this.cameras.main, this.player);

    const now = this.simulationNow();
    this.finishExpiredActionAnimation(now);
    this.interactionRouter?.update();
    this.statusEffects?.update(now, delta);
    this.abilitySystem?.update();
    this.combatController?.update(now, delta);
    this.occlusionController?.update();
    this.depthDiagnostics?.update();
    // Passive energy regen (scaled by Quick Recovery perk).
    if (!this.healthSystem?.isDead()) {
      const stats = getStats();
      const regen = (stats.energyRegenPerSec * delta) / 1000;
      if (regen > 0) gameState.regenEnergy(regen);
    }

    // Respawn override: if dead, skip input but still tick systems above.
    if (this.healthSystem?.isDead()) {
      this.stopPlayerMotion();
      this.player.rotation = 0;
      this.debugRenderer?.update();
      return;
    }

    const direction = this.playerController.readDirection();

    if (this.playerController.isMovementSuppressed()) {
      this.playerController.move(direction);
      this.debugRenderer?.update();
      return;
    }

    if (this.actionLocked) {
      this.stopPlayerMotion();
      this.player.rotation = 0;
      this.debugRenderer?.update();
      return;
    }

    if (this.handleActionInput(direction)) {
      this.debugRenderer?.update();
      return;
    }

    this.playerController.move(direction);
    this.debugRenderer?.update();
  }

  private createDebugRenderer(): void {
    this.debugRenderer = new WorldDebugRenderer({
      scene: this,
      dimensions: this.worldDimensions,
      getPlayer: () => this.player,
      getCombatTargets: () => this.combatController?.targets ?? null,
      getCollisionTiles: () => this.collisionTiles,
      getTransitionZones: () => [],
      getEnemySpawnAreas: () => this.builtMap?.enemySpawnAreas ?? [],
      getBossCamps: () => this.builtMap?.bossCamps ?? [],
      getWorldVisuals: () => this.universalWorld?.worldVisuals ?? [],
    });
  }

  private createRenderingDiagnostics(): void {
    this.renderingDiagnostics = new RenderingDiagnostics(
      this,
      () => this.cameras.main,
      () => {
        const bounds = this.playerVisual?.getBounds();
        return bounds ? { width: bounds.width, height: bounds.height } : undefined;
      },
      () => this.cameraController?.presentationState,
    );
  }

  private transitionTo(areaId: AreaId, entryEdge: Direction): void {
    this.transitioning = true;
    this.stopPlayerMotion();
    this.navigateToArea(areaId, entryEdge, false);
  }

  private requestAuthoredExit(request: WorldExitRequest): WorldExitResult {
    if (request.mapId !== this.loadedMap.map.mapId) return { status: 'ignored' };
    if (this.transitioning) return { status: 'ignored' };
    if (!request.targetAreaId || !isDirection(request.entry)) {
      return { status: 'blocked', message: 'Navigation unavailable' };
    }

    const gate = request.gate;
    if (isJsonObject(gate) && Object.keys(gate).length > 0) {
      const gateId = gate.id;
      const requiredItemId = gate.requiredItemId;
      const consumeOnUnlock = gate.consumeOnUnlock;
      const lockedMessage = gate.lockedMessage;
      if (
        typeof gateId !== 'string'
        || typeof requiredItemId !== 'string'
        || typeof consumeOnUnlock !== 'boolean'
        || typeof lockedMessage !== 'string'
      ) {
        return { status: 'blocked', message: 'Navigation unavailable' };
      }
      if (!worldProgress.isGateUnlocked(request.mapId, gateId)) {
        if (playerInventory.count(requiredItemId) < 1) {
          if (this.time.now >= this.nextGateMessageAt) {
            this.nextGateMessageAt = this.time.now + 900;
            floatingText.spawn(this, this.player.x, this.player.y - 42, lockedMessage, 'white', true);
          }
          return { status: 'blocked', message: lockedMessage };
        }
        const unlock = playerInventoryWorldTransaction.unlockGate({
          mapId: request.mapId,
          gateId,
          requiredItemId,
          consumeOnUnlock,
        });
        if (unlock !== 'unlocked' && unlock !== 'already-unlocked') {
          return { status: 'blocked', message: lockedMessage };
        }
        floatingText.spawn(this, this.player.x, this.player.y - 42, 'The Verdant Gate unlocks!', 'green', true);
      }
    } else if (gate !== null && (!isJsonObject(gate) || Object.keys(gate).length > 0)) {
      return { status: 'blocked', message: 'Navigation unavailable' };
    }

    this.transitionTo(request.targetAreaId, request.entry);
    return { status: 'queued' };
  }

  private navigateToArea(areaId: AreaId, entryEdge?: Direction, respawnHome = false): void {
    navigateToAreaUrl(
      areaId,
      entryEdge,
      respawnHome,
      saveSystem.captureCurrentState(this.capturePlayerLocation()),
    );
  }

  private buildWorld(): void {
    const map = this.loadedMap.map;
    const terrainGrid = this.buildTerrainGrid(map);
    this.terrainGrid = terrainGrid;
    this.builtMap = {
      terrainGrid,
      playerSpawn: map.player.spawn,
      entries: map.player.entries,
      enemySafeZones: map.enemySafeZones ?? map.spawns?.safeZones ?? [],
      enemySpawnAreas: map.enemySpawnAreas ?? [],
      bossCamps: map.bossCamps ?? [],
      ...(map.spawns ? { spawns: map.spawns } : {}),
    };
    this.physics.world.setBounds(0, 0, this.worldDimensions.width, this.worldDimensions.height);

    const transitionTileFactory = new TileFactory({
      scene: this,
      collisionTiles: this.collisionTiles,
      dimensions: this.worldDimensions,
      seed: this.currentArea.seed,
      physicsEnabled: false,
    });
    this.terrainTransitionLayer?.destroy();
    this.terrainTransitionLayer = new TerrainTransitionRenderer({
      scene: this,
      tileFactory: transitionTileFactory,
      dimensions: this.worldDimensions,
      seed: this.currentArea.seed,
    }).render(terrainGrid);

    this.collectibles = new CollectibleController({
      scene: this,
      mapId: this.loadedMap.map.mapId,
      transaction: playerInventoryWorldTransaction,
      progress: worldProgress,
      publisher: COLLECTIBLE_EVENTS,
      showMessage: (x, y, message, color, important) => floatingText.spawn(this, x, y, message, color, important),
      onStateChanged: (change) => {
        this.resourceNodes?.onCollectibleStateChanged(change);
        this.inventoryDrops?.onCollectibleStateChanged(change);
      },
    });
    this.resourceNodes = new ResourceNodeController({
      scene: this,
      mapId: this.loadedMap.map.mapId,
      dimensions: this.worldDimensions,
      getCollectibleQuantity: (objectId) => {
        if (!this.universalWorld) throw new Error(`Collectible scene '${objectId}' is unavailable before world mount`);
        return this.universalWorld.collectibleQuantity(objectId);
      },
      spawnWorldDrop: (request) => this.spawnWorldDrop(request),
      isCellBlocked: (cellX, cellY, sourceInstanceId) => this.isResourceDropCellBlocked(cellX, cellY, sourceInstanceId),
    });
    this.inventoryDrops = new InventoryDropController({
      mapId: this.loadedMap.map.mapId,
      dimensions: this.worldDimensions,
      inventory: playerInventory,
      getPlayerAnchor: () => ({ x: this.player.x, y: this.player.y }),
      getFacing: () => this.facingDirection(),
      inspectCell: (itemId, cellX, cellY) => this.inspectInventoryDropCell(itemId, cellX, cellY),
      spawnWorldDrop: (request) => this.spawnWorldDrop(request),
      showMessage: (message) => floatingText.spawn(this, this.player.x, this.player.y - 42, message, 'white', true, 1800),
      progress: worldProgress,
    });
  }

  private spawnWorldDrop(request: WorldDropRequest): void {
    if (this.universalWorld) this.universalWorld.spawnWorldDrop(request);
    else this.pendingWorldDrops.push(request);
  }

  private buildTerrainGrid(map: MapFile): WorldTileId[][] {
    const terrainGrid: WorldTileId[][] = [];
    for (const layer of map.layers) {
      layer.rows.forEach((row, tileY) => {
        const targetRow = terrainGrid[tileY] ?? [];
        for (let tileX = 0; tileX < row.length; tileX += 1) {
          const tileId = layer.legend[row[tileX]];
          if (!isWorldTileId(tileId)) {
            throw new Error(`Map '${map.mapId}' reached WorldScene with invalid tile '${tileId}'`);
          }
          targetRow[tileX] = tileId;
        }
        terrainGrid[tileY] = targetRow;
      });
    }
    return terrainGrid;
  }

  private createCollectibleReactions(): void {
    this.disposables.addDisposable(new CollectibleReactionController({
      events: COLLECTIBLE_EVENTS,
      awardCoins: (amount) => gameState.addCoins(amount),
      playEatAnimation: () => this.playActionAnimation('slime-eat'),
      flashCoins: () => this.universalWorld?.flashHudCoins(),
    }));
  }

  private createCollisionLayer(): void {
    this.collisionTiles = this.physics.add.staticGroup();
  }

  private createPlayer(): void {
    const restoredLocation = this.pendingRestoreLocation?.mapId === this.loadedMap.map.mapId
      ? this.pendingRestoreLocation
      : saveSystem.currentLocation().mapId === this.loadedMap.map.mapId
        ? saveSystem.currentLocation()
        : undefined;
    const spawnPoint = restoredLocation && this.isValidSavedPosition(restoredLocation)
      ? new Phaser.Math.Vector2(restoredLocation.x, restoredLocation.y)
      : this.findSpawnPoint(this.getEntryAnchor());
    this.createUniversalSceneWorld(spawnPoint);
    this.player = this.universalWorld!.playerPhysicsSprite;
    this.playerVisual = this.universalWorld!.playerPresentation;
    const nameTag = this.add.text(this.player.x, this.player.y - 56, this.universalWorld!.managedPlayer.playerName, {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '14px',
      color: UI_THEME.colors.text,
      stroke: UI_THEME.colors.shadow,
      strokeThickness: 4,
    }).setOrigin(0.5).setDepth(resolveWorldDepth(resolveBodyBottom(this.player.body as Phaser.Physics.Arcade.Body), {
      stableId: 'player',
      attachmentSlot: 7,
    }).depth);
    this.playerController = new PlayerController({
      scene: this,
      player: this.player,
      visual: this.playerVisual,
      nameTag,
      getMotion: () => this.playerMotion(),
      getInput: () => this.playerMotion(),
      getStatusEffects: () => this.statusEffects,
      playAnimation: (key) => this.playAnimation(key),
    });
    if (restoredLocation) this.applyFacing(restoredLocation.facing);
  }

  private createPhysics(): void {
    this.physics.add.collider(this.player, this.collisionTiles);
  }

  private createCamera(): void {
    this.physics.world.resume();
    this.cameras.main.resetFX();
    this.cameras.main.setBounds(0, 0, this.worldDimensions.width, this.worldDimensions.height);
    this.cameraController = new ResponsiveCameraController(this, this.cameras.main);
    this.cameraController.resetZoom();
    this.cameraController.startFollow(this.player, true);

    this.events.on(Phaser.Scenes.Events.POST_UPDATE, this.handlePresentationPostUpdate, this);
    this.disposables.add(() => {
      this.events.off(Phaser.Scenes.Events.POST_UPDATE, this.handlePresentationPostUpdate, this);
    });

    const uiCamera = this.cameras.add(
      0,
      0,
      this.scale.width,
      this.scale.height,
      false,
      'screen-ui',
    );
    uiCamera.setScroll(0, 0);
    uiCamera.setZoom(1);
    uiCamera.setRoundPixels(true);
    this.uiCamera = uiCamera;
    this.disposables.add(() => {
      this.cameras.remove(uiCamera, true);
      if (this.uiCamera === uiCamera) this.uiCamera = undefined;
    });

    this.input.on('wheel', this.handleCameraWheel, this);
    this.disposables.add(() => this.input.off('wheel', this.handleCameraWheel, this));
  }

  private capturePlayerLocation(): GameLocationData {
    return {
      areaId: this.currentArea.id,
      mapId: this.loadedMap.map.mapId,
      x: this.player?.x ?? this.loadedMap.map.player.spawn.x,
      y: this.player?.y ?? this.loadedMap.map.player.spawn.y,
      facing: this.facingDirection(),
    };
  }

  private facingDirection(): FacingDirection {
    const facing = this.playerController?.facing;
    if (!facing) return 'down';
    if (Math.abs(facing.x) > Math.abs(facing.y)) return facing.x < 0 ? 'left' : 'right';
    return facing.y < 0 ? 'up' : 'down';
  }

  private applyFacing(facing: FacingDirection): void {
    const vector = {
      up: { x: 0, y: -1 },
      down: { x: 0, y: 1 },
      left: { x: -1, y: 0 },
      right: { x: 1, y: 0 },
    }[facing];
    this.playerController.facing.set(vector.x, vector.y);
  }

  private isValidSavedPosition(location: GameLocationData): boolean {
    if (!Number.isFinite(location.x) || !Number.isFinite(location.y)) return false;
    if (location.x < 0 || location.y < 0 || location.x > this.worldDimensions.width || location.y > this.worldDimensions.height) return false;
    const tileX = Math.floor(location.x / this.worldDimensions.tileSize);
    const tileY = Math.floor(location.y / this.worldDimensions.tileSize);
    return this.isWithinWorld(tileX, tileY) && !this.isSolidTile(tileX, tileY);
  }

  private syncCameraLayers(): void {
    const uiCamera = this.uiCamera;
    if (!uiCamera) return;

    for (const child of this.children.list) {
      const scrollable = child as Phaser.GameObjects.GameObject & {
        scrollFactorX?: number;
        scrollFactorY?: number;
      };
      const layer: 'world' | 'ui' = scrollable.scrollFactorX === 0 && scrollable.scrollFactorY === 0
        ? 'ui'
        : 'world';

      if (this.cameraLayerAssignments.get(child) === layer) continue;

      if (layer === 'ui') {
        this.cameras.main.ignore(child);
      } else {
        uiCamera.ignore(child);
      }
      this.cameraLayerAssignments.set(child, layer);
    }
  }

  private handleCameraWheel(
    _pointer: Phaser.Input.Pointer,
    _objects: unknown[],
    _deltaX: number,
    deltaY: number,
  ): void {
    if (this.universalWorld?.craftingSurface.isOpen()) return;
    this.cameraController?.stepZoom(deltaY);
  }

  private playerMotion(): PlayerActorPort {
    if (!this.universalWorld) throw new Error('The authored player runtime is not initialized.');
    return this.universalWorld.managedPlayer;
  }

  private stopPlayerMotion(): void {
    this.universalWorld?.managedPlayer.stopMovement();
    if (this.player?.body) this.player.setVelocity(0, 0);
  }

  private teleportPlayer(position: Readonly<{ x: number; y: number }>): void {
    this.universalWorld?.managedPlayer.teleport(position);
    this.player.setPosition(position.x, position.y);
    (this.player.body as Phaser.Physics.Arcade.Body | null)?.reset(position.x, position.y);
  }

  private handlePresentationPostUpdate(_time: number, delta: number): void {
    this.playerController?.updateVisuals();
    this.cameraController?.update(delta);
    updateDevToolsCameraZoom(this.cameraController?.zoom ?? this.cameras.main.zoom);
    this.renderingDiagnostics?.update(this.time.now);
  }

  private getEntryAnchor(): Phaser.Math.Vector2 | undefined {
    const authoredPoint = this.entryEdge
      ? this.builtMap?.entries[this.entryEdge]
      : this.builtMap?.playerSpawn;
    return authoredPoint
      ? new Phaser.Math.Vector2(authoredPoint.x, authoredPoint.y)
      : undefined;
  }

  private findSpawnPoint(anchor?: Phaser.Math.Vector2): Phaser.Math.Vector2 {
    const { columns, rows, tileSize, width, height } = this.worldDimensions;
    const startX = Math.floor((anchor?.x ?? width / 2) / tileSize);
    const startY = Math.floor((anchor?.y ?? height / 2) / tileSize);
    const maxRadius = Math.max(columns, rows);

    for (let radius = 0; radius < maxRadius; radius += 1) {
      for (let tileY = startY - radius; tileY <= startY + radius; tileY += 1) {
        for (let tileX = startX - radius; tileX <= startX + radius; tileX += 1) {
          if (!this.isWithinWorld(tileX, tileY) || this.isSolidTile(tileX, tileY)) {
            continue;
          }

          return new Phaser.Math.Vector2(
            tileX * tileSize + tileSize / 2,
            tileY * tileSize + tileSize / 2,
          );
        }
      }
    }

    return new Phaser.Math.Vector2(width / 2, height / 2);
  }

  private isWithinWorld(tileX: number, tileY: number): boolean {
    return tileX >= 0
      && tileX < this.worldDimensions.columns
      && tileY >= 0
      && tileY < this.worldDimensions.rows;
  }

  private isSolidTile(tileX: number, tileY: number): boolean {
    const tileId = this.terrainGrid[tileY]?.[tileX];
    return tileId ? isTileCollidable(tileId) : false;
  }

  private isResourceDropCellBlocked(cellX: number, cellY: number, sourceInstanceId: string): boolean {
    if (!this.isWithinWorld(cellX, cellY) || this.isSolidTile(cellX, cellY)) return true;
    return this.universalWorld?.isAuthoredCellOccupied(
      cellX,
      cellY,
      sourceInstanceId,
      this.worldDimensions.tileSize,
    ) ?? false;
  }

  private inspectInventoryDropCell(_itemId: string, cellX: number, cellY: number): InventoryDropCellInspection {
    if (this.isResourceDropCellBlocked(cellX, cellY, '__inventory-drop__')) return { kind: 'blocked' };
    return this.universalWorld?.isManagedCollectibleCellOccupied(cellX, cellY, this.worldDimensions.tileSize)
      ? { kind: 'blocked' }
      : { kind: 'open' };
  }

  private playAnimation(key: string, forceRestart = false): void {
    if (this.healthSystem?.isDead() && key !== 'slime-die') return;
    const knockbackHasPriority = this.simulationNow() < this.playerKnockbackUntil;
    const isForcedKnockback = forceRestart && key === 'slime-knockback';
    if (knockbackHasPriority && key !== 'slime-die' && !isForcedKnockback) return;

    if (this.currentAnimation === key && !forceRestart) {
      return;
    }

    this.currentAnimation = key;
    const animationId = key.startsWith('slime-') ? key.slice('slime-'.length) : key;
    this.universalWorld?.managedPlayer.playAnimation(animationId, forceRestart);
  }

  private activateAbilityFromUi(abilityId: PlayerAbilityId): void {
    if (this.paused || this.healthSystem?.isDead() || !this.abilitySystem) return;
    const direction = this.playerController.readDirection();
    switch (abilityId) {
      case 'jump': this.abilitySystem.tryJump(direction); break;
      case 'squash-slam': this.abilitySystem.trySquashSlam(); break;
      case 'stretch-lash': this.abilitySystem.tryStretchLash(); break;
      case 'teleport': this.abilitySystem.tryTeleport(direction); break;
    }
  }

  private handleActionInput(direction: Phaser.Math.Vector2): boolean {
    const input = this.playerMotion();
    if (input.consumeActionPress('interact')) {
      // The router owns the visible shared prompt, so its candidate must own
      // the key press whenever one is displayed.
      if (this.interactionRouter?.hasCandidate()) {
        this.interactionRouter.handleInteract();
      }
      return true;
    }

    if (input.consumeActionPress('jump')) {
      this.abilitySystem?.tryJump(direction);
      return true;
    }

    if (input.consumeActionPress('dodge')) {
      this.playerController.tryDodge(direction);
      return true;
    }

    if (input.consumeActionPress('attack')) {
      this.combatController?.tryAttack();
      return true;
    }

    if (input.consumeActionPress('stretch-lash')) {
      this.abilitySystem?.tryStretchLash();
      return true;
    }

    if (input.consumeActionPress('squash-slam')) {
      this.abilitySystem?.trySquashSlam();
      return true;
    }

    if (input.consumeActionPress('teleport')) {
      this.abilitySystem?.tryTeleport(direction);
      return true;
    }

    if (input.consumeActionPress('eat')) {
      this.playActionAnimation('slime-eat');
      return true;
    }

    return false;
  }

  private playActionAnimation(key: string): void {
    if (this.healthSystem?.isDead() || this.simulationNow() < this.playerKnockbackUntil) return;
    const animationId = key.startsWith('slime-') ? key.slice('slime-'.length) : key;
    const durationMs = this.universalWorld?.playerAnimationDurationMs(animationId);
    if (durationMs === undefined) return;

    this.actionLocked = true;
    this.currentAnimation = key;
    this.stopPlayerMotion();
    this.player.rotation = 0;
    this.universalWorld?.managedPlayer.playAnimation(animationId);
    // Unlocked from updateGameplay on the simulation clock, so modal pauses
    // hold the lock instead of letting it expire underneath them.
    this.actionAnimationUntil = this.simulationNow() + durationMs;
  }

  private finishExpiredActionAnimation(now: number): void {
    if (this.actionAnimationUntil === undefined || now < this.actionAnimationUntil) return;
    this.actionAnimationUntil = undefined;
    this.actionLocked = false;
    this.playAnimation('slime-idle');
  }

  /** Gameplay time in ms; stands still while the simulation is paused. */
  private simulationNow(): number {
    return this.universalWorld?.simulationTime ?? 0;
  }

  private handleResize(gameSize: Phaser.Structs.Size): void {
    this.cameras.main.setViewport(0, 0, gameSize.width, gameSize.height);
    this.uiCamera?.setViewport(0, 0, gameSize.width, gameSize.height);
  }

  // â”€â”€ Phase 1: health / damage / death / XP / items â”€â”€

  private onPlayerHit(result: AcceptedDamageResult): void {
    this.universalWorld?.flashPlayerHealthBar();
    floatingText.spawn(
      this,
      this.player.x,
      this.player.y - 30,
      `-${result.actualHpLost}`,
      'red',
      true,
    );
    // Red flash tween on the sprite.
    if (!this.iFrameFlashActive) {
      this.iFrameFlashActive = true;
      this.playerVisual?.setTintFill(0xff6f88);
      this.time.delayedCall(120, () => {
        this.playerVisual?.clearTint();
        this.iFrameFlashActive = false;
      });
    }
  }

  private onPlayerDeath(): void {
    this.playerKnockbackUntil = 0;
    this.universalWorld?.resetActiveFights();
    this.playAnimation('slime-die', true);
    this.stopPlayerMotion();
    this.player.rotation = 0;
    this.cameras.main.shake(400, 0.012);
    floatingText.spawn(this, this.player.x, this.player.y - 40, 'DEFEATED', 'red', true);

    // Respawn at last bed after a short delay.
    this.time.delayedCall(1400, () => this.respawnPlayer());
  }

  private respawnPlayer(): void {
    if (!this.healthSystem) return;

    if (this.currentArea.id !== 'level-1') {
      gameState.revive();
      this.statusEffects?.clear();
      this.navigateToArea('level-1', undefined, true);
      return;
    }

    const pos = this.findSpawnPoint(this.getEntryAnchor());

    this.healthSystem.respawn();
    this.statusEffects?.clear();
    this.teleportPlayer(pos);
    this.playerKnockbackUntil = 0;
    this.playAnimation('slime-idle', true);
    this.playerVisual?.clearTint();
    this.playerVisual?.setAlpha(1);

    this.cameras.main.pan(pos.x, pos.y, 350, 'Power2');
    this.cameraController?.resetZoom();
    this.cameraController?.startFollow(this.player);

    floatingText.spawn(this, pos.x, pos.y - 40, 'Respawned', 'green', true);
  }

  private useItem(itemId: string): void {
    const def = itemRegistry.get(itemId);
    if (!def?.use) return;
    if (playerInventory.count(itemId) <= 0) return;

    if (def.use.healHp) {
      const healed = this.healthSystem?.heal(def.use.healHp) ?? 0;
      if (healed > 0) {
        floatingText.spawn(this, this.player.x, this.player.y - 30, `+${healed}`, 'green', true);
      }
    }
    if (def.use.healEnergy) {
      gameState.regenEnergy(def.use.healEnergy);
    }
    if (def.use.cureStatus) {
      for (const s of def.use.cureStatus) this.statusEffects?.remove(s);
    }

    playerInventory.remove(itemId, 1);
  }

  private spawnItemDropIcon(x: number, y: number, itemId: string, count: number, index: number, total: number): void {
    const item = itemRegistry.get(itemId);
    const texture = item?.icon;
    const label = item?.name ?? itemId;
    const offsetX = (index - (total - 1) / 2) * 30;

    if (texture && this.textures.exists(texture)) {
      const icon = this.add.image(x, y, texture)
        .setDepth(resolveWorldDepth(y, { band: 'reveal-effects', stableId: `item-drop:${itemId}:${index}` }).depth)
        .setScale(1.35)
        .setAlpha(0);
      this.tweens.add({
        targets: icon,
        x: x + offsetX,
        y: y - 34,
        alpha: { from: 0, to: 1 },
        scale: { from: 0.8, to: 1.55 },
        duration: 180,
        ease: 'Back.Out',
        onComplete: () => {
          this.tweens.add({
            targets: icon,
            y: y - 54,
            alpha: 0,
            duration: 650,
            ease: 'Sine.In',
            onComplete: () => icon.destroy(),
          });
        },
      });
    }

    floatingText.spawn(this, x + offsetX, y - 64, `+${count} ${label}`, 'green');
  }

  private bindHotkeys(): void {
    const kb = this.input.keyboard;
    if (!kb) return;

    // Tab = toggle inventory. Bind via keydown-TAB so we can preventDefault
    // before the browser moves focus.
    kb.on('keydown-TAB', (event: KeyboardEvent) => {
      event.preventDefault();
      if (this.universalWorld?.levelUpSurface.isOpen() || this.actionLocked) return;
      this.universalWorld?.inventorySurface.toggle();
    });

    const weaponKeys = ['keydown-ONE', 'keydown-TWO', 'keydown-THREE', 'keydown-FOUR', 'keydown-FIVE', 'keydown-SIX'] as const;
    weaponKeys.forEach((eventName, slotIndex) => {
      const equipHandler = (event: KeyboardEvent) => {
        if (event.shiftKey || event.repeat || this.paused || this.healthSystem?.isDead()) return;
        this.equipWeaponSlot(slotIndex);
      };
      kb.on(eventName, equipHandler);
      this.disposables.add(() => kb.off(eventName, equipHandler));
    });

    kb.on('keydown-U', () => {
      if (this.universalWorld?.levelUpSurface.isOpen() || this.universalWorld?.inventorySurface.isOpen() || this.universalWorld?.worldMapSurface.isOpen() || this.universalWorld?.craftingSurface.isOpen()) return;
      this.universalWorld?.questJournalSurface.toggle();
    });

    kb.on('keydown-C', () => {
      if (this.universalWorld?.levelUpSurface.isOpen() || this.universalWorld?.inventorySurface.isOpen() || this.universalWorld?.worldMapSurface.isOpen() || this.universalWorld?.questJournalSurface.isOpen()) return;
      this.universalWorld?.craftingSurface.toggle();
    });

    // Left-click triggers an attack in the player's current facing direction.
    this.input.on('pointerdown', (pointer: Phaser.Input.Pointer) => {
      if (pointer.leftButtonDown()) {
        this.combatController?.tryAttack();
      }
    });
  }

  private equipWeaponSlot(slotIndex: number): void {
    const result = playerWeaponLoadout.equipSlot(slotIndex, (weaponId) => this.combatController?.equipWeapon(weaponId) ?? false);
    if (result.ok) {
      if (result.changed) {
        const item = weaponItemFor(result.weaponId);
        floatingText.spawn(this, this.player.x, this.player.y - 48, `${item?.name ?? result.weaponId} equipped`, 'yellow', true);
      }
      return;
    }
    const message = result.reason === 'empty'
      ? `Slot ${slotIndex + 1} is empty`
      : result.reason === 'not-owned'
        ? 'Weapon not in inventory'
        : result.reason === 'busy'
          ? 'Finish the attack first'
          : 'Weapon is unavailable';
    floatingText.spawn(this, this.player.x, this.player.y - 42, message, 'white');
  }

  private equipWeaponFromInventory(weaponId: string): void {
    const slotIndex = playerWeaponLoadout.ensureAssigned(weaponId);
    if (slotIndex === null) {
      floatingText.spawn(this, this.player.x, this.player.y - 42, 'Hotbar is full — choose a slot', 'white');
      return;
    }
    this.equipWeaponSlot(slotIndex);
  }

  private assignWeaponSlot(weaponId: string, slotIndex: number): void {
    const assignment = playerWeaponLoadout.assignWeapon(slotIndex, weaponId);
    if (!assignment.ok) {
      floatingText.spawn(this, this.player.x, this.player.y - 42, 'Weapon not in inventory', 'white');
      return;
    }
    if (assignment.equipAssignedWeapon) this.equipWeaponSlot(slotIndex);
  }

  // â”€â”€ Phase 2: combat â”€â”€

  private createCombatSystem(): void {
    this.combatController = new CombatController({
      scene: this,
      player: this.player,
      collisionTiles: this.collisionTiles,
      dimensions: this.worldDimensions,
      spawns: this.builtMap?.spawns,
      enemySpawnAreas: this.builtMap?.enemySpawnAreas ?? [],
      enemySafeZones: this.builtMap?.enemySafeZones ?? [],
      areaId: this.currentArea.id,
      getFacing: () => this.playerController.facing,
      findSpawnPoint: (anchor) => this.findSpawnPoint(anchor),
      playCharacterAction: (actionId) => this.playAnimation(`slime-${actionId}`),
      setActionLocked: (locked) => { this.actionLocked = locked; },
      canAttack: () => !this.actionLocked && !this.paused && !this.healthSystem?.isDead(),
      nowMs: () => this.simulationNow(),
      healPlayer: (amount) => this.healthSystem?.heal(amount) ?? 0,
      spawnItemDropIcon: (x, y, itemId, count, index, total) => {
        this.spawnItemDropIcon(x, y, itemId, count, index, total);
      },
      createManagedEnemy: (request) => this.universalWorld?.createManagedEnemy(request),
      spawnManagedEffect: (request) => this.universalWorld?.spawnEffect(request) ?? false,
      mountManagedWeapon: (weaponId) => this.universalWorld?.mountWeapon(weaponId) ?? false,
      canManagedWeaponAttack: () => this.universalWorld?.canWeaponAttack() ?? false,
      playManagedWeaponAttack: (direction, damage) => this.universalWorld?.playWeaponAttack(direction, damage) ?? false,
      clearManagedWeapon: () => this.universalWorld?.clearWeapon(),
    });
  }

  private createUniversalSceneWorld(playerSpawn: Readonly<{ x: number; y: number }>): void {
    const content = this.game.registry.get(PREPARED_SCENE_CONTENT_KEY);
    const uiRoot = this.game.registry.get('universal-ui-root');
    if (!(content instanceof PreparedSceneContent) || !this.loadedWorld || !this.healthSystem) {
      throw new Error('WorldScene requires prepared universal scene content and initialized compatibility services.');
    }
    if (!(uiRoot instanceof HTMLElement)) {
      throw new Error('WorldScene requires the universal UI mount node.');
    }
    if (content.get(this.loadedWorld.sceneId) !== this.loadedWorld.packedScene) {
      throw new Error(`WorldScene received stale prepared content for '${this.loadedWorld.sceneId}'.`);
    }
    this.universalWorld = new UniversalSceneWorldController({
      scene: this,
      content,
      map: this.loadedMap.map,
      worldSceneId: this.loadedWorld.sceneId,
      playerSpawn,
      health: this.healthSystem,
      progress: worldProgress,
      transaction: playerInventoryWorldTransaction,
      interactions: this.interactionRouter!,
      modalStack: this.modalStack!,
      setChestPaused: (paused) => this.setSimulationPaused('managed-chest', paused),
      setInventoryPaused: (paused) => this.setSimulationPaused('inventory', paused),
      setCraftingPaused: (paused) => this.setSimulationPaused('crafting', paused),
      setJournalPaused: (paused) => this.setSimulationPaused('journal', paused),
      setQuestOfferPaused: (paused) => this.setSimulationPaused('quest-npc', paused),
      setWorldMapPaused: (paused) => this.setSimulationPaused('worldmap', paused),
      setLevelUpPaused: (paused) => this.setSimulationPaused('levelup', paused),
      getCurrentAreaId: () => this.currentArea.id,
      worldDimensions: this.worldDimensions,
      onCrafted: ({ recipe }) => {
        const craftedWeaponId = itemRegistry.get(recipe.output.itemId)?.equipment?.weaponId;
        if (craftedWeaponId) {
          const slotIndex = playerWeaponLoadout.ensureAssigned(craftedWeaponId);
          if (slotIndex !== null && playerWeaponLoadout.equippedWeaponId() === null) {
            this.equipWeaponSlot(slotIndex);
          }
        }
        floatingText.spawn(this, this.player.x, this.player.y - 44, `Crafted: ${recipe.name}`, 'green', true);
      },
      onUseInventoryItem: (itemId) => this.useItem(itemId),
      onEquipInventoryWeapon: (weaponId) => this.equipWeaponFromInventory(weaponId),
      onAssignInventoryWeapon: (weaponId, slotIndex) => this.assignWeaponSlot(weaponId, slotIndex),
      canDropInventoryItem: (itemId) => this.inventoryDrops?.canDrop(itemId) ?? false,
      onDropInventoryItem: (slotIndex, quantity) => this.inventoryDrops?.dropFromSlot(slotIndex, quantity) ?? false,
      showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
      updateGameplay: (deltaMs) => this.updateGameplay(deltaMs),
      updatePresentation: (deltaMs) => this.updatePresentation(deltaMs),
      transformManagedWeaponDamage: (damage, target) => this.combatController?.transformManagedWeaponDamage(damage, target) ?? damage,
      onManagedWeaponOutcome: (outcome, target) => this.combatController?.onManagedWeaponOutcome(outcome, target),
      onManagedWeaponAttackStarted: (weaponId, direction) => this.combatController?.onManagedWeaponAttackStarted(weaponId, direction),
      onManagedWeaponAttackFinished: (weaponId) => this.combatController?.onManagedWeaponAttackFinished(weaponId),
      onManagedEnemyDefeated: (enemy) => this.combatController?.onManagedEnemyDefeated(enemy),
      getEnemySafeZones: () => this.builtMap?.enemySafeZones ?? [],
      registerNpc: (registration) => this.questNpcController?.register(registration),
      registerManagedResource: (registration) => this.resourceNodes?.registerManagedResource(registration),
      spawnManagedResourceDrops: (request) => this.resourceNodes?.spawnManagedResourceDrops(request),
      collectibles: this.collectibles!,
      registerOccluder: (registration) => this.occlusionController!.registerOccluder(registration),
      registerOcclusionActor: (registration) => this.occlusionController!.registerActor(registration),
      requestExit: (request) => this.requestAuthoredExit(request),
      onEquipWeaponSlot: (slotIndex) => this.equipWeaponSlot(slotIndex),
      getAbilitySystem: () => this.abilitySystem,
      canUseAbilities: () => !this.paused && !this.healthSystem?.isDead(),
      onActivateAbility: (abilityId) => this.activateAbilityFromUi(abilityId),
      getPlayer: () => this.player,
      uiRoot,
    });
    for (const request of this.pendingWorldDrops) this.universalWorld.spawnWorldDrop(request);
    this.pendingWorldDrops = [];
    this.inventoryDrops?.restore();
  }

  private bindDebugCheats(): void {
    const kb = this.input.keyboard;
    if (!kb) return;

    const guard = () => !this.paused && !this.healthSystem?.isDead();

    // Shift+[1] = debug damage, Shift+[2] = XP, Shift+[3] = heal,
    // Shift+[4] = coins, Shift+[5] = potion, Shift+[6/7] = status, Shift+[8] = dummy.
    kb.on('keydown-ONE', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      if (this.playerController.isDodging()) {
        floatingText.spawn(this, this.player.x, this.player.y - 30, 'DODGED!', 'cyan', true);
        return;
      }
      const req: DamageRequest = { amount: 20, source: 'debug', knockStrength: 180 };
      const dx = this.player.x;
      req.knockX = dx > this.worldDimensions.width / 2 ? -1 : 1;
      req.knockY = 0;
      this.healthSystem?.applyDamage(req, this.simulationNow());
    });

    kb.on('keydown-TWO', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      gameState.addXp(25);
      floatingText.spawn(this, this.player.x, this.player.y - 30, '+25 XP', 'cyan');
    });

    kb.on('keydown-THREE', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      this.healthSystem?.heal(gameState.maxHp);
      floatingText.spawn(this, this.player.x, this.player.y - 30, 'FULL HEAL', 'green', true);
    });

    kb.on('keydown-FOUR', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      gameState.addCoins(100);
    });

    kb.on('keydown-FIVE', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      playerInventory.add('hp-potion', 1);
      floatingText.spawn(this, this.player.x, this.player.y - 30, '+potion', 'green');
    });

    kb.on('keydown-SIX', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      this.statusEffects?.apply('burn');
      floatingText.spawn(this, this.player.x, this.player.y - 30, 'BURN!', 'orange');
    });

    kb.on('keydown-SEVEN', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      this.statusEffects?.apply('slow');
      floatingText.spawn(this, this.player.x, this.player.y - 30, 'SLOWED', 'cyan');
    });

    kb.on('keydown-EIGHT', (event: KeyboardEvent) => {
      if (!event.shiftKey) return;
      if (!guard()) return;
      this.combatController?.spawnDummy(this.player.x + Phaser.Math.Between(60, 140), this.player.y + Phaser.Math.Between(-60, 60));
      floatingText.spawn(this, this.player.x, this.player.y - 30, '+dummy', 'white');
    });
  }

}

function isDirection(value: string): value is Direction {
  return value === 'north' || value === 'east' || value === 'south' || value === 'west';
}

function isJsonObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

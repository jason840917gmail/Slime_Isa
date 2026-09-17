import Phaser from 'phaser';
import {
  isTileCollidable,
  type WorldTileId,
} from '../content/terrain/TileCatalog';
import { Minimap } from '../Minimap';
import { HUD } from '../HUD';
import { gameState } from '../core/GameState';
import { gameEvents } from '../core/EventBus';
import { saveSystem } from '../core/SaveSystem';
import {
  LegacyPlayerHealthAdapter,
  type AcceptedDamageResult,
  type DamageRequest,
} from '../infrastructure/scenes/compatibility/LegacyPlayerHealthAdapter';
import { StatusEffectManager } from '../systems/StatusEffects';
import { getStats } from '../systems/PlayerStats';
import { PlayerAbilityController } from '../features/player/PlayerAbilityController';
import { playerInventory, itemRegistry, weaponItemFor } from '../systems/Inventory';
import { playerWeaponLoadout } from '../systems/WeaponLoadout';
import { floatingText } from '../ui/FloatingText';
import { HealthBar } from '../ui/HealthBar';
import { LevelUpModal } from '../ui/LevelUpModal';
import { InventoryUI } from '../ui/InventoryUI';
import { WeaponHotbar } from '../ui/WeaponHotbar';
import { hitboxPool } from '../combat/Hitbox';
import { AREAS, type AreaDef, type AreaId, type Direction } from '../world/Area';
import { BIOMES } from '../world/Biome';
import { showAreaTitleCard } from '../ui/AreaTitleCard';
import { WorldMapUI } from '../ui/WorldMapUI';
import { questTracker } from '../quests/QuestTracker';
import { QuestJournal } from '../ui/QuestJournal';
import { CraftingUI } from '../ui/CraftingUI';
import { craftingService } from '../crafting/Crafting';
import { reopenPendingLevelUpWhenIdle } from '../ui/LevelUpReopenPolicy';
import { ModalStack } from '../ui/ModalStack';
import { DisposableBag } from '../shared/lifecycle/Disposable';
import { PlayerController } from '../features/player/PlayerController';
import type { PlayerActorPort } from '../features/player/PlayerServicePorts';
import { findVisualClipByRuntimeKey, getVisualClip } from '../content/visuals/VisualCatalog';
import { animationCycleDurationMs } from '../shared/animationLoop';
import type { WorldVisual } from '../presentation/WorldVisual';
import { UI_THEME } from '../presentation/theme';
import { registerAllVisualSetAnimations } from '../features/visuals/AnimationRegistrar';
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
import { WorldDropSpawner } from '../features/collectibles/WorldDropSpawner';
import { InventoryDropController } from '../features/collectibles/InventoryDropController';
import type { InventoryDropCellInspection } from '../features/collectibles/InventoryDropPlacement';
import { OcclusionController } from '../features/occlusion/OcclusionController';
import { DepthDiagnostics } from '../features/occlusion/DepthDiagnostics';
import { MapBuilder, type BuiltMap } from '../features/world/MapBuilder';
import {
  setObjectAnchor,
  setObjectDepthMode,
} from '../features/objects/ObjectFactory';
import { resolveBodyBottom, resolveWorldDepth } from '../presentation/WorldDepth';
import { ResponsiveCameraController } from '../presentation/ResponsiveCameraController';
import type { LoadedMap } from '../infrastructure/maps/MapRepository';
import type { WorldDimensions } from '../world/WorldDimensions';
import { updateDevToolsCameraZoom } from '../devTools';
import type { GameLocationData, FacingDirection } from '../infrastructure/persistence/SaveSchema';
import { GAME_CONSTANTS } from '../Constant';
import { InteractionRouter } from '../features/interaction/InteractionRouter';
import { QuestNpcController } from '../features/interaction/QuestNpcController';
import { QuestNotificationPresenter } from '../features/quests/QuestNotificationPresenter';
import { NpcRuntimeController } from '../features/npcs/NpcRuntimeController';
import { ChestController } from '../features/chests/ChestController';
import { BossCampController } from '../features/bosses/BossCampController';
import { playerInventoryWorldTransaction } from '../features/progression/InventoryWorldTransaction';
import { getObjectArchetype, isObjectArchetypeId } from '../content/objects/ObjectCatalog';
import { PREPARED_SCENE_CONTENT_KEY, PreparedSceneContent } from '../infrastructure/scenes/PreparedSceneContent';
import type { LoadedWorldScene } from '../infrastructure/scenes/WorldSceneLoader';
import { LegacyMapPlacementBridge } from '../infrastructure/scenes/compatibility/LegacyMapPlacementBridge';
import { UniversalSceneWorldController } from '../features/world/UniversalSceneWorldController';

const EDGE_TRANSITION_GRACE_MS = GAME_CONSTANTS.worldNavigation.edgeTransitionGraceMs;
const COLLECTIBLE_EVENTS = new CollectibleEventChannel(gameEvents);

interface WorldSceneData {
  areaId?: AreaId;
  entryEdge?: Direction;
  loadedWorld?: LoadedWorldScene;
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
  private minimap!: Minimap;
  private hud!: HUD;
  private collectibleTargets!: Phaser.Physics.Arcade.StaticGroup;
  private resourceTargets!: Phaser.GameObjects.Group;
  private resourceNodes?: ResourceNodeController;
  private collectibles?: CollectibleController;
  private worldDrops?: WorldDropSpawner;
  private inventoryDrops?: InventoryDropController;
  private playerController!: PlayerController;
  private healthSystem?: LegacyPlayerHealthAdapter;
  private statusEffects?: StatusEffectManager;
  private healthBar?: HealthBar;
  private levelUpModal?: LevelUpModal;
  private modalStack?: ModalStack;
  private inventoryUI?: InventoryUI;
  private worldMapUI?: WorldMapUI;
  private questJournal?: QuestJournal;
  private craftingUI?: CraftingUI;
  private interactionRouter?: InteractionRouter;
  private questNpcController?: QuestNpcController;
  private npcRuntimeController?: NpcRuntimeController;
  private chestController?: ChestController;
  private bossCampController?: BossCampController;
  private universalWorld?: UniversalSceneWorldController;
  private scenePlacementBridge?: LegacyMapPlacementBridge;
  private questNotifications?: QuestNotificationPresenter;
  private abilitySystem?: PlayerAbilityController;
  private weaponHotbar?: WeaponHotbar;
  private iFrameFlashActive = false;
  private playerKnockbackUntil = 0;
  private combatController?: CombatController;
  private currentArea: AreaDef = AREAS.icege;
  private worldDimensions!: WorldDimensions;
  private loadedMap!: LoadedMap;
  private loadedWorld?: LoadedWorldScene;
  private builtMap?: BuiltMap;
  private entryEdge?: Direction;
  private transitioning = false;
  private transitionReadyAt = 0;
  private nextGateMessageAt = 0;
  private transitionZones: Phaser.GameObjects.Zone[] = [];
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
    this.transitionReadyAt = this.time.now + EDGE_TRANSITION_GRACE_MS;
    this.nextGateMessageAt = 0;
  }

  create(): void {
    this.resetSceneStateForAreaLoad();
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
    registerAllVisualSetAnimations(this);
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
      modalStack,
      onPausedChange: (paused) => { this.setSimulationPaused('quest-npc', paused); },
      showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
    });
    this.npcRuntimeController = new NpcRuntimeController();
    this.buildWorld();
    this.questNpcController.finalize();
    this.statusEffects = new StatusEffectManager();
    this.healthSystem = new LegacyPlayerHealthAdapter({
      scene: this,
      getPlayer: () => this.player,
      getStatus: () => this.statusEffects!,
      applyKnockback: (direction, strength, durationMs) => {
        this.playerKnockbackUntil = Math.max(
          this.playerKnockbackUntil,
          this.time.now + durationMs,
        );
        this.playerController.applyKnockback(direction, strength, durationMs);
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
    this.createMinimap();
    this.createHUD();
    this.createCollectibleReactions();

    // Phase 1 systems: health presentation, abilities, level-up modal, inventory UI
    this.healthBar = new HealthBar(this, this.player);
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
    });
    this.levelUpModal = new LevelUpModal({
      scene: this,
      modalStack,
      onPausedChange: (p) => { this.setSimulationPaused('levelup', p); },
    });
    this.inventoryUI = new InventoryUI({
      scene: this,
      modalStack,
      onPausedChange: (p) => { this.setSimulationPaused('inventory', p); },
      onUseItem: (itemId) => this.useItem(itemId),
      onEquipWeapon: (weaponId) => this.equipWeaponFromInventory(weaponId),
      onAssignWeapon: (weaponId, slotIndex) => this.assignWeaponSlot(weaponId, slotIndex),
      canDropItem: (itemId) => this.inventoryDrops?.canDrop(itemId) ?? false,
      onDropItem: (slotIndex, quantity) => this.inventoryDrops?.dropFromSlot(slotIndex, quantity) ?? false,
    });
    this.worldMapUI = new WorldMapUI({
      scene: this,
      modalStack,
      getCurrentArea: () => this.currentArea.id,
      onPausedChange: (p) => { this.setSimulationPaused('worldmap', p); },
    });
    this.worldMapUI.discover(this.currentArea.id);
    this.questJournal = new QuestJournal({
      scene: this,
      modalStack,
      onPausedChange: (p) => { this.setSimulationPaused('journal', p); },
    });
    this.questNotifications = new QuestNotificationPresenter({
      getPosition: () => ({ x: this.player.x, y: this.player.y }),
      show: (x, y, message, color, important) => floatingText.spawn(this, x, y, message, color, important),
    });
    questTracker.start();
    this.craftingUI = new CraftingUI({
      scene: this,
      modalStack,
      craftingService,
      onPausedChange: (p) => { this.setSimulationPaused('crafting', p); },
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
    });
    // Phase 2: combat system
    this.createCombatSystem();
    this.weaponHotbar = new WeaponHotbar({
      scene: this,
      onEquipSlot: (slotIndex) => this.equipWeaponSlot(slotIndex),
    });

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
    showAreaTitleCard(this, this.currentArea.name, BIOMES[this.currentArea.biome].titleColor);
    this.syncCameraLayers();
  }

  private resetSceneStateForAreaLoad(): void {
    // Release NPC interaction sessions before destroying their actors. Modal
    // close callbacks can then return every movement lock while the actor
    // lifecycle is still alive; actor teardown follows as the final NPC step.
    this.questNpcController?.destroy();
    this.questNpcController = undefined;
    this.npcRuntimeController?.destroy();
    this.npcRuntimeController = undefined;
    this.chestController?.destroy();
    this.chestController = undefined;
    this.builtMap = undefined;
    this.disposables.dispose();
    this.disposables = new DisposableBag();
    this.hud?.destroy();
    this.minimap?.destroy();
    this.abilitySystem?.destroy();
    this.weaponHotbar?.destroy();
    this.statusEffects?.destroy();
    this.debugRenderer?.destroy();
    this.renderingDiagnostics?.destroy();
    this.renderingDiagnostics = undefined;
    this.cameraController = undefined;
    this.levelUpModal?.destroy();
    this.inventoryUI?.destroy();
    this.worldMapUI?.destroy();
    this.questJournal?.destroy();
    this.questNotifications?.destroy();
    this.questNotifications = undefined;
    this.craftingUI?.destroy();
    this.interactionRouter?.destroy();
    this.interactionRouter = undefined;
    this.combatController?.destroy();
    this.universalWorld?.destroy();
    this.universalWorld = undefined;
    this.bossCampController?.destroy();
    this.bossCampController = undefined;
    this.resourceNodes?.destroy();
    this.resourceNodes = undefined;
    this.inventoryDrops = undefined;
    this.worldDrops?.destroy();
    this.worldDrops = undefined;
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

    this.transitionZones.forEach((zone) => zone.destroy());
    this.transitionZones = [];
    this.combatController = undefined;
    this.weaponHotbar = undefined;
    this.worldMapUI = undefined;
    this.questJournal = undefined;
    this.craftingUI = undefined;
    this.pauseSources.clear();
    this.scenePlacementBridge = undefined;
    this.paused = false;
    this.actionLocked = false;
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
    this.npcRuntimeController?.setSimulationPaused(shouldPause);
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
    this.bossCampController?.targets.children.each((child) => {
      stop(child);
      return true;
    });
    this.npcRuntimeController?.stopMoving();
  }

  update(_time: number, delta: number): void {
    if (this.universalWorld) {
      this.universalWorld.advanceFrame(delta / 1000);
      return;
    }
    this.updateLegacyRender(delta);
    if (!this.paused) this.updateLegacyFixed(delta);
  }

  private updateLegacyRender(_delta: number): void {
    this.syncCameraLayers();

    if (this.paused) {
      this.stopPlayerMotion();
      this.debugRenderer?.update();
    }
  }

  private updateLegacyFixed(delta: number): void {
    this.npcRuntimeController?.update(delta);

    this.minimap.update(this.cameras.main, this.player);

    this.interactionRouter?.update();
    this.statusEffects?.update(this.time.now, delta);
    this.healthSystem?.update(this.time.now);
    this.healthBar?.update();
    this.abilitySystem?.update();
    this.combatController?.update(this.time.now, delta);
    this.bossCampController?.update(this.time.now, delta);
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
      getCollectibleTargets: () => this.collectibleTargets,
      getTransitionZones: () => this.transitionZones,
      getEnemySpawnAreas: () => this.builtMap?.enemySpawnAreas ?? [],
      getBossCamps: () => this.builtMap?.bossCamps ?? [],
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

  private navigateToArea(areaId: AreaId, entryEdge?: Direction, respawnHome = false): void {
    navigateToAreaUrl(
      areaId,
      entryEdge,
      respawnHome,
      saveSystem.captureCurrentState(this.capturePlayerLocation()),
    );
  }

  private buildWorld(): void {
    this.scenePlacementBridge = new LegacyMapPlacementBridge(
      this.loadedMap.map.mapId,
      this.loadedMap.map.objects,
      this.loadedMap.map.bossCamps ?? [],
    );
    this.scenePlacementBridge.scenePlacements();
    let mapBuilder: MapBuilder;
    mapBuilder = new MapBuilder({
      scene: this,
      map: this.loadedMap.map,
      dimensions: this.worldDimensions,
      collisionTiles: this.collisionTiles,
      seed: this.currentArea.seed,
      behaviorGroups: {
        'collectible.walk-over': this.collectibleTargets,
      },
      onTerrainBuilt: (terrainGrid) => { this.terrainGrid = terrainGrid; },
      shouldBuildObject: (instance) => !this.scenePlacementBridge?.shouldSuppressLegacyObject(instance),
      onObjectCreated: (registration) => {
        this.resourceNodes?.register(registration);
        this.collectibles?.register(registration);
        this.chestController?.register(registration);
      },
      onNpcCreated: (registration) => {
        this.npcRuntimeController?.register(registration);
        this.questNpcController?.register(registration);
      },
      registerOccluder: (registration) => this.occlusionController!.registerOccluder(registration),
    });
    this.collectibles = new CollectibleController({
      scene: this,
      mapId: this.loadedMap.map.mapId,
      group: this.collectibleTargets,
      inventory: playerInventory,
      transaction: playerInventoryWorldTransaction,
      progress: worldProgress,
      publisher: COLLECTIBLE_EVENTS,
      showMessage: (x, y, message, color, important) => floatingText.spawn(this, x, y, message, color, important),
      onStateChanged: (change) => {
        this.resourceNodes?.onCollectibleStateChanged(change);
        this.inventoryDrops?.onCollectibleStateChanged(change);
      },
    });
    this.worldDrops = new WorldDropSpawner({
      scene: this,
      createObject: (objectId, options) => mapBuilder.createDynamicObject(objectId, options),
      setObjectAnchor,
      setObjectDepthMode,
      registerCollectible: (registration) => this.collectibles?.register(registration),
    });
    this.resourceNodes = new ResourceNodeController({
      scene: this,
      mapId: this.loadedMap.map.mapId,
      dimensions: this.worldDimensions,
      collisionGroup: this.collisionTiles,
      targetGroup: this.resourceTargets,
      spawnWorldDrop: (request) => this.worldDrops!.spawn(request),
      isCellBlocked: (cellX, cellY, sourceInstanceId) => this.isResourceDropCellBlocked(cellX, cellY, sourceInstanceId),
    });
    this.inventoryDrops = new InventoryDropController({
      mapId: this.loadedMap.map.mapId,
      dimensions: this.worldDimensions,
      inventory: playerInventory,
      getPlayerAnchor: () => ({ x: this.player.x, y: this.player.y }),
      getFacing: () => this.facingDirection(),
      inspectCell: (itemId, cellX, cellY) => this.inspectInventoryDropCell(itemId, cellX, cellY),
      spawnWorldDrop: (request) => this.worldDrops!.spawn(request),
      showMessage: (message) => floatingText.spawn(this, this.player.x, this.player.y - 42, message, 'white', true, 1800),
      progress: worldProgress,
    });
    const hasLegacyChest = this.loadedMap.map.objects.some((instance) => (
      isObjectArchetypeId(instance.objectId)
      && getObjectArchetype(instance.objectId).chest === true
      && !this.scenePlacementBridge?.shouldSuppressLegacyObject(instance)
    ));
    if (hasLegacyChest) {
      this.chestController = new ChestController({
        scene: this,
        mapId: this.loadedMap.map.mapId,
        inventory: playerInventory,
        progress: worldProgress,
        transaction: playerInventoryWorldTransaction,
        router: this.interactionRouter!,
        modalStack: this.modalStack!,
        getPlayer: () => this.player,
        isLocked: (instanceId) => this.bossCampController?.isChestLocked(instanceId) ?? false,
        onPausedChange: (paused) => this.setSimulationPaused('chest', paused),
        showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
      });
    }
    this.builtMap = mapBuilder.build();
    this.terrainGrid = this.builtMap.terrainGrid;
    this.inventoryDrops.restore();
  }

  private createCollectibleReactions(): void {
    this.disposables.addDisposable(new CollectibleReactionController({
      events: COLLECTIBLE_EVENTS,
      awardCoins: (amount) => gameState.addCoins(amount),
      playEatAnimation: () => this.playActionAnimation('slime-eat'),
      flashCoins: () => this.hud.flashCoins(this),
    }));
  }

  private createCollisionLayer(): void {
    this.collisionTiles = this.physics.add.staticGroup();
    this.collectibleTargets = this.physics.add.staticGroup();
    this.resourceTargets = this.add.group();
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
    this.occlusionController?.registerActor({
      id: 'player',
      owner: this.player,
      visual: this.playerVisual,
      getGroundAnchorY: () => resolveBodyBottom(this.player.body as Phaser.Physics.Arcade.Body),
      getDepth: () => this.player.depth,
      isEligible: () => this.player.active,
      silhouetteColor: 0x73d7ff,
    });
  }

  private createPhysics(): void {
    this.physics.add.collider(this.player, this.collisionTiles);
    if (this.collectibleTargets) {
      this.physics.add.overlap(this.player, this.collectibleTargets, (_player, collectible) => {
        this.collectibles?.collect(collectible as Phaser.GameObjects.GameObject);
      });
    }
    this.createAreaTransitionZones();
  }

  private createAreaTransitionZones(): void {
    for (const exit of this.builtMap?.exits ?? []) {
      const zone = this.add.zone(
        exit.zone.x + exit.zone.w / 2,
        exit.zone.y + exit.zone.h / 2,
        exit.zone.w,
        exit.zone.h,
      );
      this.physics.add.existing(zone, true);
      this.transitionZones.push(zone);
      this.physics.add.overlap(this.player, zone, () => {
        if (this.transitioning || this.time.now < this.transitionReadyAt) return;
        if (exit.gate && !worldProgress.isGateUnlocked(this.loadedMap.map.mapId, exit.gate.id)) {
          if (playerInventory.count(exit.gate.requiredItemId) < 1) {
            if (this.time.now >= this.nextGateMessageAt) {
              this.nextGateMessageAt = this.time.now + 900;
              floatingText.spawn(this, this.player.x, this.player.y - 42, exit.gate.lockedMessage, 'white', true);
            }
            return;
          }
          const unlock = playerInventoryWorldTransaction.unlockGate({
            mapId: this.loadedMap.map.mapId,
            gateId: exit.gate.id,
            requiredItemId: exit.gate.requiredItemId,
            consumeOnUnlock: exit.gate.consumeOnUnlock,
          });
          if (unlock !== 'unlocked' && unlock !== 'already-unlocked') return;
          floatingText.spawn(this, this.player.x, this.player.y - 42, 'The Verdant Gate unlocks!', 'green', true);
        }
        this.transitionTo(exit.to as AreaId, exit.entry as Direction);
      });
    }
  }

  private createMinimap(): void {
    this.minimap = new Minimap(this, this.worldDimensions);
  }

  private createHUD(): void {
    this.hud = new HUD(this);
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
    if (this.craftingUI?.isOpen()) return;
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
    return this.loadedMap.map.objects.some((object) => {
      if (object.instanceId === sourceInstanceId) return false;
      const objectCellX = Math.floor(object.x / this.worldDimensions.tileSize);
      const objectCellY = Math.floor((object.y - 1) / this.worldDimensions.tileSize);
      return objectCellX === cellX && objectCellY === cellY;
    });
  }

  private inspectInventoryDropCell(itemId: string, cellX: number, cellY: number): InventoryDropCellInspection {
    if (this.isResourceDropCellBlocked(cellX, cellY, '__inventory-drop__')) return { kind: 'blocked' };
    const settled = this.collectibles?.inspectCell(itemId, cellX, cellY, this.worldDimensions.tileSize);
    if (settled && settled.kind !== 'open') return settled;
    const hasUnregisteredDrop = this.collectibleTargets.getChildren().some((child) => {
      const image = child as Phaser.GameObjects.Image;
      if (!image.active || image.getData('collectibleInstanceId')) return false;
      const anchorX = image.getData('objectAnchorX');
      const anchorY = image.getData('objectAnchorY');
      if (!Number.isFinite(anchorX) || !Number.isFinite(anchorY)) return false;
      return Math.floor(anchorX / this.worldDimensions.tileSize) === cellX
        && Math.floor(anchorY / this.worldDimensions.tileSize) - 1 === cellY;
    });
    return hasUnregisteredDrop ? { kind: 'blocked' } : { kind: 'open' };
  }

  private playAnimation(key: string, forceRestart = false): void {
    if (this.healthSystem?.isDead() && key !== 'slime-die') return;
    const knockbackHasPriority = this.time.now < this.playerKnockbackUntil;
    const isForcedKnockback = forceRestart && key === 'slime-knockback';
    if (knockbackHasPriority && key !== 'slime-die' && !isForcedKnockback) return;

    if (this.currentAnimation === key && !forceRestart) {
      return;
    }

    this.currentAnimation = key;
    const animationId = key.startsWith('slime-') ? key.slice('slime-'.length) : key;
    this.universalWorld?.managedPlayer.playAnimation(animationId, forceRestart);
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
    if (this.healthSystem?.isDead() || this.time.now < this.playerKnockbackUntil) return;
    const clip = key.startsWith('slime-')
      ? getVisualClip('character.player.slime', key.slice('slime-'.length))
      : findVisualClipByRuntimeKey('character.player.slime', key);
    if (!clip) return;

    this.actionLocked = true;
    this.currentAnimation = key;
    this.stopPlayerMotion();
    this.player.rotation = 0;
    const animationId = key.startsWith('slime-') ? key.slice('slime-'.length) : key;
    this.universalWorld?.managedPlayer.playAnimation(animationId);

    const unlock = () => {
      this.actionLocked = false;
      this.playAnimation('slime-idle');
    };

    if (!clip.loop) {
      this.time.delayedCall(Math.max(1, Math.round(animationCycleDurationMs(clip))), unlock);
      return;
    }

    const durationMs = Math.max(1, Math.round(animationCycleDurationMs(clip)));
    this.time.delayedCall(durationMs, unlock);
  }

  private handleResize(gameSize: Phaser.Structs.Size): void {
    this.cameras.main.setViewport(0, 0, gameSize.width, gameSize.height);
    this.uiCamera?.setViewport(0, 0, gameSize.width, gameSize.height);
    this.hud?.resize(gameSize.width);

  }

  // â”€â”€ Phase 1: health / damage / death / XP / items â”€â”€

  private onPlayerHit(result: AcceptedDamageResult): void {
    this.healthBar?.flash();
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
    this.bossCampController?.resetActiveFights();
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
      if (this.levelUpModal?.isOpen() || this.actionLocked) return;
      this.inventoryUI?.toggle();
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

    kb.on('keydown-M', () => {
      if (this.levelUpModal?.isOpen() || this.inventoryUI?.isOpen() || this.questJournal?.isOpen() || this.craftingUI?.isOpen()) return;
      this.worldMapUI?.toggle();
    });

    kb.on('keydown-U', () => {
      if (this.levelUpModal?.isOpen() || this.inventoryUI?.isOpen() || this.worldMapUI?.isOpen() || this.craftingUI?.isOpen()) return;
      this.questJournal?.toggle();
    });

    kb.on('keydown-C', () => {
      if (this.levelUpModal?.isOpen() || this.inventoryUI?.isOpen() || this.worldMapUI?.isOpen() || this.questJournal?.isOpen()) return;
      this.craftingUI?.toggle();
    });

    const reopenLevelUp = (): void => {
      if (!this.modalStack || !this.levelUpModal) return;
      reopenPendingLevelUpWhenIdle(this.modalStack, this.levelUpModal);
    };
    kb.on('keydown-P', reopenLevelUp);
    this.disposables.add(() => kb.off('keydown-P', reopenLevelUp));

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
    const legacyBossCamps = (this.builtMap?.bossCamps ?? [])
      .filter((camp) => !this.scenePlacementBridge?.shouldSuppressLegacyBossCamp(camp));
    this.bossCampController = new BossCampController({
      scene: this,
      mapId: this.loadedMap.map.mapId,
      camps: legacyBossCamps,
      player: this.player,
      collisionTiles: this.collisionTiles,
      progress: worldProgress,
      isPlayerDodging: () => this.playerController.isDodging(),
      applyPlayerDamage: (amount, source, impactX, impactY, knockbackStrength) => {
        this.healthSystem?.applyDamage({ amount, source, knockX: impactX, knockY: impactY, knockStrength: knockbackStrength }, this.time.now);
      },
      showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
    });
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
      isDodging: () => this.playerController.isDodging(),
      applyPlayerDamage: (amount, source, impactX, impactY, knockbackStrength) => {
        this.healthSystem?.applyDamage({
          amount,
          source,
          knockX: impactX,
          knockY: impactY,
          knockStrength: knockbackStrength,
        }, this.time.now);
      },
      healPlayer: (amount) => this.healthSystem?.heal(amount) ?? 0,
      spawnItemDropIcon: (x, y, itemId, count, index, total) => {
        this.spawnItemDropIcon(x, y, itemId, count, index, total);
      },
      registerRevealActor: (enemy, visual) => this.occlusionController?.registerActor({
        id: `enemy:${enemy.enemyId}`,
        owner: enemy,
        visual,
        getGroundAnchorY: () => resolveBodyBottom(enemy.body as Phaser.Physics.Arcade.Body),
        getDepth: () => enemy.depth,
        isEligible: () => enemy.isRevealEligible(),
        silhouetteColor: 0xff936d,
      }),
      getResourceTargets: () => this.resourceTargets,
      resourceNodes: this.resourceNodes,
      getBossTargets: () => this.bossCampController?.targets ?? null,
      isBossTarget: (target) => this.bossCampController?.isBossTarget(target) ?? false,
      applyBossHit: (request) => this.bossCampController?.applyWeaponHit(request) ?? {
        status: 'rejected', actualDamage: 0, defeated: false, reason: 'invalid',
      },
      createManagedEnemy: (request) => this.universalWorld?.createManagedEnemy(request),
      spawnManagedEffect: (request) => this.universalWorld?.spawnEffect(request) ?? false,
      mountManagedWeapon: (weaponId) => this.universalWorld?.mountWeapon(weaponId) ?? false,
      canManagedWeaponAttack: (timeMs) => this.universalWorld?.canWeaponAttack(timeMs) ?? false,
      playManagedWeaponAttack: (direction, timeMs, damage) => this.universalWorld?.playWeaponAttack(direction, timeMs, damage) ?? false,
      spawnManagedEnemyProjectile: (request) => this.universalWorld?.spawnEnemyProjectile(request) ?? false,
      clearManagedWeapon: () => this.universalWorld?.clearWeapon(),
    });
  }

  private createUniversalSceneWorld(playerSpawn: Readonly<{ x: number; y: number }>): void {
    const content = this.game.registry.get(PREPARED_SCENE_CONTENT_KEY);
    if (!(content instanceof PreparedSceneContent) || !this.loadedWorld || !this.scenePlacementBridge || !this.healthSystem) {
      throw new Error('WorldScene requires prepared universal scene content and initialized compatibility services.');
    }
    if (content.get(this.loadedWorld.sceneId) !== this.loadedWorld.packedScene) {
      throw new Error(`WorldScene received stale prepared content for '${this.loadedWorld.sceneId}'.`);
    }
    this.universalWorld = new UniversalSceneWorldController({
      scene: this,
      content,
      map: this.loadedMap.map,
      placementBridge: this.scenePlacementBridge,
      playerSpawn,
      collisionTiles: this.collisionTiles,
      health: this.healthSystem,
      progress: worldProgress,
      transaction: playerInventoryWorldTransaction,
      interactions: this.interactionRouter!,
      modalStack: this.modalStack!,
      setChestPaused: (paused) => this.setSimulationPaused('managed-chest', paused),
      showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
      updateLegacyFixed: (deltaMs) => this.updateLegacyFixed(deltaMs),
      updateLegacyRender: (deltaMs) => this.updateLegacyRender(deltaMs),
      transformManagedWeaponDamage: (damage, target) => this.combatController?.transformManagedWeaponDamage(damage, target) ?? damage,
      onManagedWeaponOutcome: (outcome, target) => this.combatController?.onManagedWeaponOutcome(outcome, target),
      onManagedWeaponAttackStarted: (weaponId, direction) => this.combatController?.onManagedWeaponAttackStarted(weaponId, direction),
      onManagedWeaponAttackFinished: (weaponId) => this.combatController?.onManagedWeaponAttackFinished(weaponId),
      activateLegacyWeaponHitbox: (request) => this.combatController?.activateLegacyWeaponHitbox(request) ?? (() => undefined),
      onManagedEnemyDefeated: (enemy) => this.combatController?.onManagedEnemyDefeated(enemy),
      getEnemySafeZones: () => [
        ...(this.builtMap?.enemySafeZones ?? []),
        ...(this.loadedMap.map.spawns?.safeZones ?? []),
      ],
      registerNpc: (registration) => this.questNpcController?.register(registration),
      registerManagedResource: (registration) => this.resourceNodes?.registerManagedResource(registration),
      spawnManagedResourceDrops: (request) => this.resourceNodes?.spawnManagedResourceDrops(request),
      collectibles: this.collectibles!,
      registerOccluder: (registration) => this.occlusionController!.registerOccluder(registration),
    });
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
      this.healthSystem?.applyDamage(req, this.time.now);
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

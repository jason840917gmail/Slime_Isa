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
import { StatusEffectManager, statusSpeedMultiplier } from '../systems/StatusEffects';
import { getStats } from '../systems/PlayerStats';
import { PlayerAbilityController } from '../features/player/PlayerAbilityController';
import {
  isPassiveAbilityId,
  isPlayerAbilityId,
  PASSIVE_ABILITY_DEFINITIONS,
  PLAYER_ABILITY_DEFINITIONS,
  type PlayerAbilityId,
} from '../features/player/PlayerAbilityDefinitions';
import { playerInventory, itemRegistry, weaponItemFor } from '../systems/Inventory';
import { playerWeaponLoadout } from '../systems/WeaponLoadout';
import { floatingText } from '../ui/FloatingText';
import { hitboxPool } from '../combat/Hitbox';
import { AREAS, STARTING_AREA_ID, getAreaDefinition, type AreaDef, type AreaId, type Direction } from '../world/Area';
import { sceneId } from '../content/scenes/identifiers';
import { placedBedId, planRespawn, worldHasBed } from '../features/rest/RespawnDestination';
import { GulpController } from '../features/gulp/GulpController';
import { GulpHud } from '../features/gulp/GulpHud';
import { GulpWheel } from '../features/gulp/GulpWheel';
import { gameFeel } from '../features/feel/sharedFeel';
import { FEEL_PRESETS, type FeelEvent } from '../features/feel/GameFeel';
import { SquashStretch, type SquashEvent } from '../features/feel/SquashStretch';
import { particleFx, type ParticleEvent } from '../features/feel/ParticlePresets';
import { SlimeTrail } from '../features/feel/SlimeTrail';
import { GULP_WHEEL_HOLD_MS, pickGulpWheelSlot } from '../features/gulp/GulpWheelLayout';
import type { GulpWheelEntry } from '../features/gulp/GulpController';
import { resolveQuestWaypoint, type QuestWaypointTarget, type QuestWaypointWorld } from '../features/quests/QuestWaypoint';
import { QuestWaypointPresenter } from '../features/quests/QuestWaypointPresenter';
import { GAME_CONSTANTS } from '../Constant';
import { GAME_SHELL_SCENE_IDS, GameShell } from '../features/shell/GameShell';
import { CONTROL_HINT_SURFACE_ID, ControlHintsController, type ControlHintId } from '../features/hints/ControlHints';
import type { TutorialControlId } from '../content/quests/types';
import { harvestToolAdvice } from '../features/combat/HarvestAdvice';
import type { ResourceHarvestBlocked } from '../features/scripts/ResourceNodeScript';
import { getWeaponDefinition } from '../content/weapons/WeaponCatalog';
import { gameSettings } from '../features/settings/GameSettingsService';
import { getCharacterPackages } from '../content/characters/CharacterCatalog';
import { BIOMES } from '../world/Biome';
import { questTracker } from '../quests/QuestTracker';
import { bindQuestStory, questService } from '../quests/QuestService';
import { storyProgress } from '../features/progression/StoryProgress';
import { RECIPE_CATALOG } from '../content/recipes/RecipeCatalog';
import { ModalStack } from '../ui/ModalStack';
import { DisposableBag } from '../shared/lifecycle/Disposable';
import { PlayerController } from '../features/player/PlayerController';
import { controlLabel } from '../features/player/ControlLabels';
import { isControlCode, type ShellInputAction } from '../features/player/PlayerInputActions';
import { aimToward, snapToCardinal, type PointerAim } from '../features/player/PointerAim';
import { MENU_TABS_SURFACE_ID, MenuTabsSurfacePort } from '../features/ui/MenuTabsSurfacePort';
import type { PlayerActorPort } from '../features/player/PlayerServicePorts';
import type { WorldVisual } from '../presentation/WorldVisual';
import { UI_THEME } from '../presentation/theme';
import {
  clearOneShotNavigationParams,
  navigateToArea as navigateToAreaUrl,
  resolveAreaRequest,
  restoreAreaTransition,
  returnToTitle,
  type AreaEntry,
} from '../features/world-navigation/AreaNavigation';
import { WorldDebugRenderer } from '../dev/WorldDebugRenderer';
import { RenderingDiagnostics } from '../dev/RenderingDiagnostics';
import { CombatController } from '../features/combat/CombatController';
import { ResourceNodeController } from '../features/resources/ResourceNodeController';
import { worldProgress } from '../features/progression/WorldProgress';
import { SleepController, type SleepRequest } from '../features/rest/SleepController';
import { FurniturePlacementController, type FootprintRect, type PlacementRequest } from '../features/building/FurniturePlacementController';
import type { CraftingSite } from '../content/recipes/types';
import type { ModalHandle } from '../ui/ModalStack';
import type { RespawnPointData } from '../infrastructure/persistence/SaveSchema';
import { CollectibleController } from '../features/collectibles/CollectibleController';
import { CollectibleEventChannel } from '../features/collectibles/CollectibleEventChannel';
import { CollectibleReactionController } from '../features/collectibles/CollectibleReactionController';
import type { WorldDropRequest } from '../features/collectibles/WorldDropRequest';
import { InventoryDropController } from '../features/collectibles/InventoryDropController';
import type { InventoryDropCellInspection } from '../features/collectibles/InventoryDropPlacement';
import { OcclusionController } from '../features/occlusion/OcclusionController';
import { DepthDiagnostics } from '../features/occlusion/DepthDiagnostics';
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
import { UniversalSceneWorldController, type RestorationRequest } from '../features/world/UniversalSceneWorldController';
import type { MapEnemySafeZone, MapEnemySpawnArea, MapFile, MapPoint, MapSpawns } from '../content/maps/mapFormat';
import type { WorldExitRequest, WorldExitResult } from '../features/scripts/WorldExitScript';
import { questRewardLines } from '../features/quests/QuestRewardText';

const COLLECTIBLE_EVENTS = new CollectibleEventChannel(gameEvents);

interface WorldSceneData extends AreaEntry {
  areaId?: AreaId;
  loadedWorld?: LoadedWorldScene;
}

interface AuthoredWorldMetadata {
  readonly terrainGrid: WorldTileId[][];
  readonly playerSpawn: MapPoint;
  readonly entries: MapFile['player']['entries'];
  readonly doors: NonNullable<MapFile['player']['doors']>;
  readonly enemySafeZones: readonly MapEnemySafeZone[];
  readonly enemySpawnAreas: readonly MapEnemySpawnArea[];
  readonly spawns?: MapSpawns;
}

/** The picture and music fade out this long before a map change. */
const AREA_LEAVE_FADE_MS = 320;
const AREA_ARRIVE_FADE_MS = 400;
/** The dodge hint appears when an enemy is this close. */
/** How far short of a heavy Stretch Lash catch the slime lands. */
const LASH_STANDOFF_PX = 30;
const HINT_DODGE_ENEMY_RANGE_PX = 360;
/** The crafting hint appears once the first workbench is affordable. */
const HINT_CRAFTING_WOOD = 40;
/** Enemy loot owns no authored cell: every authored object blocks where it lands. */
const LOOT_SOURCE_ID = '__enemy-loot__';
/** Story flag set once the player has seen what the menu tabs are. */
const MENU_TABS_COACH_FLAG = 'hint.menu-tabs';
/** Menu windows (modal ids) that tutorial quests ask the player to open. */
const MENU_CONTROL_IDS: Readonly<Record<string, TutorialControlId>> = {
  inventory: 'menu:inventory',
  crafting: 'menu:crafting',
  'quest-journal': 'menu:journal',
  'world-map': 'menu:map',
  'pause-menu': 'pause',
};
/** The slime's middle sits this far above its origin; the pointer aims from there. */
const SLIME_CENTER_RISE_PX = 28;
/** Holding interact this long on a placed bed or bench picks it up instead of using it. */
const INTERACT_HOLD_MS = 450;
/** Banner color for a story-taught ability (a fresh-goo green, distinct from area names). */
const ABILITY_LEARNED_COLOR = '#9ff0c8';
/** Banner color for a collected Goo Heart. */
const GOO_HEART_COLOR = '#ff9fb4';

/** The run-wide story flag that remembers a collected Goo Heart. */
function gooHeartFlag(heartId: string): string {
  return `goo-heart.${heartId}`;
}
/** Title backdrop: drift ±TITLE_PAN_RANGE_PX around the start, one sweep per period. */
const TITLE_PAN_PERIOD_MS = 60_000;
const TITLE_PAN_RANGE_PX = 360;
const TITLE_PAN_OFFSET = { x: 160, y: 120 } as const;
/** Shown on the title screen; bump with package.json when a release is tagged. */
const GAME_VERSION = '0.1.0';

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
  private sleepController?: SleepController;
  private furniturePlacement?: FurniturePlacementController;
  private gulp?: GulpController;
  private gulpHud?: GulpHud;
  private gulpWheel?: GulpWheel;
  private squash?: SquashStretch;
  /** A hit-stop is holding physics, tweens and animation still. */
  private hitStopHeld = false;
  private slimeTrail?: SlimeTrail;
  /** The Heavy slime's last jump landing (cracked ground breaks under it). */
  private heavyLanding?: { readonly x: number; readonly y: number; readonly id: number };
  private nextCreakHintAt = 0;
  private nextTrailSlowAt = 0;
  /** Move-start squash: whether the slime moved last frame, and since when it has stood still. */
  private wasMoving = false;
  private stillSince = 0;
  /** W is down: a tap eats on release; held past GULP_WHEEL_HOLD_MS it opens the quick wheel. */
  private eatHold?: {
    readonly since: number;
    lastSeen: number;
    open: boolean;
    /** Held with nothing to choose: releasing does nothing. */
    empty: boolean;
    entries: readonly GulpWheelEntry[];
    selected?: number;
    pointerStart?: Readonly<{ x: number; y: number }>;
  };
  /** Interact pressed on a target with a second action: a release uses it, a hold picks it up. */
  private interactHold?: { readonly since: number };
  /** False until the pointer first moves over the game, so aiming falls back to the facing. */
  private pointerSeen = false;
  /** One menu: the tab strip over the bag, crafting, journal and map windows. */
  private readonly menuTabs = new MenuTabsSurfacePort(() => ({
    inventory: this.universalWorld?.inventorySurface,
    crafting: this.universalWorld?.craftingSurface,
    journal: this.universalWorld?.questJournalSurface,
    map: this.universalWorld?.worldMapSurface,
  }), {
    isLearned: () => storyProgress.hasFlag(MENU_TABS_COACH_FLAG),
    learn: () => storyProgress.setFlags([MENU_TABS_COACH_FLAG]),
    now: () => performance.now(),
  });
  /** True while sprint is held with the slime moving (a new sprint is reported once). */
  private sprinting = false;
  private waypointPresenter?: QuestWaypointPresenter;
  private waypointTarget?: QuestWaypointTarget;
  private nextWaypointResolveAt = 0;
  private nextWebMessageAt = 0;
  private shell?: GameShell;
  private hints?: ControlHintsController;
  /** The first world of a page load shows the title screen over a paused, empty Slimeshire. */
  private titleMode = false;
  /** Shown on the title screen once, e.g. why a save failed to load. */
  private titleNotice?: string;
  private titleCameraMs = 0;
  private playerNameTag?: Phaser.GameObjects.Text;
  /** Source ID of the last hit the player took, to name what defeated them. */
  private lastDamageSource?: string;
  private placementModal?: ModalHandle;
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
  private entryEdge?: Direction;
  private entryDoor?: string;
  private transitioning = false;
  private nextGateMessageAt = 0;
  private abilityLearnedHandler?: (payload: { abilityId: string }) => void;
  private questCompleteHandler?: (payload: { questId: string; title: string; rewards: { coins?: number } }) => void;
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
    this.entryDoor = request.entryDoor;
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
    const devMapPreview = import.meta.env.DEV && new URLSearchParams(window.location.search).has('map');
    this.titleMode = !WorldScene.sessionStarted && !this.restoredFromAreaTransition && !devMapPreview;
    // Install the complete run before authored objects are registered. Resource
    // nodes consult WorldProgress during registration, so loading afterwards
    // would build the first scene from stale map state. Behind the title screen
    // this is a throwaway run that is never saved.
    if (!WorldScene.sessionStarted && !this.restoredFromAreaTransition) {
      if (!saveSystem.hasInstalledRun()) saveSystem.startNewRun();
      WorldScene.sessionStarted = true;
    }
    if (!this.titleMode) saveSystem.startAutoSave();
    playerWeaponLoadout.reconcile();

    // Phase 1: World entities (no cross-system side effects)
    this.createCollisionLayer();
    this.occlusionController = new OcclusionController(this);
    const modalStack = this.game.registry.get('modalStack');
    if (!(modalStack instanceof ModalStack)) {
      throw new Error('WorldScene requires a shared ModalStack.');
    }
    this.modalStack = modalStack;
    this.shell = this.createGameShell(modalStack);
    this.hints = this.createControlHints();
    this.interactionRouter = new InteractionRouter(this);
    this.questNpcController = new QuestNpcController({
      scene: this,
      getPlayer: () => this.player,
      router: this.interactionRouter,
      getOfferSurface: () => this.universalWorld?.questOfferSurface,
      getDialogueSurface: () => this.universalWorld?.npcDialogueSurface,
      setMarker: (instanceId, marker) => this.universalWorld?.setNpcQuestMarker(instanceId, marker),
      showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
    });
    this.buildWorld();
    this.questNpcController.finalize();
    this.statusEffects = new StatusEffectManager();
    this.healthSystem = new PlayerHealthController({
      getPlayerPosition: () => ({ x: this.player.x, y: this.player.y }),
      applyKnockback: (direction, strength, durationMs) => {
        // A Heavy slime cannot be pushed around.
        if (this.gulp?.activeForm?.knockbackImmune) return;
        this.playerKnockbackUntil = Math.max(
          this.playerKnockbackUntil,
          this.simulationNow() + durationMs,
        );
        this.playerController.applyKnockback(new Phaser.Math.Vector2(direction.x, direction.y), strength, durationMs);
        this.playAnimation('slime-knockback', true);
      },
      applyWeb: (durationMs) => this.applyWeb(durationMs),
      onHit: (result) => this.onPlayerHit(result),
      onDeath: () => this.onPlayerDeath(),
    });
    this.createPlayer();
    this.sleepController = this.createSleepController();
    this.furniturePlacement = this.createFurniturePlacement();
    this.createGulp();
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
      abilityWorld: {
        lashProbe: (from, to, halfWidth) => this.universalWorld?.lashProbe(from, to, halfWidth) ?? { kind: 'none', at: to },
        lashLanding: (from, caught) => this.lashLanding(from, caught),
        lashRing: (from, caught, halfWidth) => this.universalWorld?.lashRing(from, caught, halfWidth) ?? 0,
        lashPull: (pickupId, to) => this.universalWorld?.lashPull(pickupId, to) ?? false,
        strikeArea: (request) => this.universalWorld?.strikeArea(request) ?? { hits: [] },
      },
      nowMs: () => this.simulationNow(),
    });
    this.universalWorld?.worldMapSurface.discover(this.currentArea.id);
    this.questNotifications = new QuestNotificationPresenter({
      getPosition: () => ({ x: this.player.x, y: this.player.y }),
      show: (x, y, message, color, important) => floatingText.spawn(this, x, y, message, color, important),
      showBanner: (title) => this.universalWorld?.showAreaTitle(title, '#ffd277'),
    });
    bindQuestStory({
      hasDiscoveredArea: (areaId) => worldProgress.discovered().has(areaId),
      hasWorldFlag: (flagId) => storyProgress.hasFlag(flagId),
      hasTalkedToNpc: (npcId) => storyProgress.hasTalkedTo(npcId),
      learnRecipes: (recipeIds) => storyProgress.learnRecipes(recipeIds),
      learnAbilities: (abilityIds) => storyProgress.learnAbilities(abilityIds),
      setFlags: (flagIds) => storyProgress.setFlags(flagIds),
    });
    questTracker.start();
    // Phase 2: combat system
    this.createCombatSystem();

    this.bindHotkeys();
    this.bindDevCheats();

    const persistenceModalHandler = (payload: { open: boolean }) => {
      this.setSimulationPaused('persistence', payload.open);
    };
    gameEvents.on('persistence.modal', persistenceModalHandler);
    this.disposables.add(() => gameEvents.off('persistence.modal', persistenceModalHandler));

    // Game feel (9.1): shakes and hit-stops go through one service that honours the shake and motion settings.
    this.disposables.add(gameFeel.bind({ now: () => this.time.now, shake: (ms, intensity) => this.cameras.main.shake(ms, intensity) }));
    this.disposables.add(() => this.holdForHitStop(false));
    // Pooled particle presets (9.3): one emitter each, reused for every burst.
    this.disposables.add(particleFx.bind(this));
    // The goo trail (9.4): pooled fading marks that slow enemies standing on fresh goo.
    const trail = new SlimeTrail(this);
    this.slimeTrail = trail;
    this.disposables.add(() => {
      trail.destroy();
      if (this.slimeTrail === trail) this.slimeTrail = undefined;
    });
    const onCollected = () => { if (this.player) particleFx.play('loot-sparkle', this.player.x, this.player.y - 24); };
    gameEvents.on('collectible.collected', onCollected);
    this.disposables.add(() => gameEvents.off('collectible.collected', onCollected));
    // Squash and stretch (9.2) on the slime's effect channel.
    const squash = new SquashStretch({
      scene: this,
      effects: () => this.playerVisual?.effects,
      reduceMotion: () => gameSettings.settings.reduceMotion,
      busy: () => this.abilitySystem?.isBusy() ?? false,
    });
    this.squash = squash;
    const onAction = ({ anim }: { anim: string }) => {
      if (anim !== 'jump-land') return;
      squash.play('land', true);
      if (this.gulp?.activeForm?.pressesPlates && this.player) {
        this.heavyLanding = { x: this.player.x, y: this.player.y, id: (this.heavyLanding?.id ?? 0) + 1 };
      }
    };
    const onGulp = ({ reason }: { reason: string }) => { if (reason === 'started' || reason === 'refreshed') squash.play('gulp'); };
    gameEvents.on('player.action', onAction);
    gameEvents.on('gulp.changed', onGulp);
    this.disposables.add(() => {
      gameEvents.off('player.action', onAction);
      gameEvents.off('gulp.changed', onGulp);
      squash.destroy();
      if (this.squash === squash) this.squash = undefined;
    });

    // Dev tools: the playground panel plays one game-feel effect on the slime.
    if (import.meta.env.DEV) {
      const onDevFeel = ({ effect }: { effect: string }) => {
        const [kind, id] = effect.split(':');
        const player = this.player;
        if (!player || !id) return;
        if (kind === 'particle') particleFx.play(id as ParticleEvent, player.x, player.y - 20);
        else if (kind === 'feel') {
          // A real hit-stop lasts a few frames; the panel holds it five times longer so it can be seen.
          gameFeel.play(id as FeelEvent);
          gameFeel.hitStop(FEEL_PRESETS[id as FeelEvent].hitStopMs * 5);
        }
        else if (kind === 'squash') squash.play(id as SquashEvent, true);
      };
      gameEvents.on('dev.feel', onDevFeel);
      this.disposables.add(() => gameEvents.off('dev.feel', onDevFeel));
    }

    // A story-taught ability is announced with the area-title banner and its key
    // (the quest's reward lines already float above the player).
    this.abilityLearnedHandler = ({ abilityId }) => {
      if (isPassiveAbilityId(abilityId)) {
        this.universalWorld?.showAreaTitle(PASSIVE_ABILITY_DEFINITIONS[abilityId].learnedText, ABILITY_LEARNED_COLOR);
        return;
      }
      if (!isPlayerAbilityId(abilityId)) return;
      const { title, action } = PLAYER_ABILITY_DEFINITIONS[abilityId];
      this.universalWorld?.showAreaTitle(`${title} learned: press ${controlLabel(action)}`, ABILITY_LEARNED_COLOR);
    };
    gameEvents.on('ability.learned', this.abilityLearnedHandler);
    this.disposables.add(() => {
      if (this.abilityLearnedHandler) gameEvents.off('ability.learned', this.abilityLearnedHandler);
    });

    this.questCompleteHandler = (p) => {
      floatingText.spawn(this, this.player.x, this.player.y - 70, `QUEST COMPLETE: ${p.title}`, 'yellow', true, 2400);
      questRewardLines(p.rewards).forEach((line, index) => {
        floatingText.spawn(this, this.player.x, this.player.y - 46 + index * 20, `+ ${line}`, 'green', true, 2400);
      });
    };
    gameEvents.on('quest.completed', this.questCompleteHandler);
    this.disposables.add(() => {
      if (this.questCompleteHandler) gameEvents.off('quest.completed', this.questCompleteHandler);
    });

    // Phase 3: One-time cross-system sync
    this.scale.on('resize', this.handleResize, this);
    this.disposables.add(() => this.scale.off('resize', this.handleResize, this));
    clearOneShotNavigationParams();
    if (this.titleMode) {
      this.enterTitleMode();
    } else {
      gameEvents.emit('area.enter', { areaId: this.currentArea.id });
      saveSystem.writeRecovery(this.capturePlayerLocation());
      this.universalWorld?.showAreaTitle(this.currentArea.name, BIOMES[this.currentArea.biome].titleColor);
    }
    this.syncCameraLayers();
  }

  private createGameShell(modalStack: ModalStack): GameShell {
    const outcome = (result: { readonly ok: boolean; readonly message?: string }) => (
      result.ok ? { ok: true as const } : { ok: false as const, message: result.message ?? 'That did not work.' }
    );
    const shell = new GameShell({
      modalStack,
      setPaused: (source, paused) => this.setSimulationPaused(source, paused),
      version: GAME_VERSION,
      settings: gameSettings,
      saves: {
        list: () => saveSystem.listNamedSaves(),
        unreadable: () => saveSystem.unreadableNamedSaves(),
        create: (name) => outcome(saveSystem.createNamedSave(name, this.capturePlayerLocation())),
        overwrite: (saveId) => outcome(saveSystem.overwriteNamedSave(saveId, this.capturePlayerLocation())),
        load: async (saveId) => outcome(await saveSystem.loadNamedSave(saveId)),
        autosave: () => saveSystem.autosaveSummary(),
        loadAutosave: () => outcome(saveSystem.loadAutosave()),
      },
      placeName: (mapId) => getAreaDefinition(mapId).name,
      hasStoryFlag: (flagId) => storyProgress.hasFlag(flagId),
      pause: {
        canOpen: () => !this.titleMode && !this.transitioning && !(this.healthSystem?.isDead() ?? false)
          && !(this.furniturePlacement?.active ?? false),
        openJournal: () => this.universalWorld?.questJournalSurface.open(),
        openInventory: () => this.universalWorld?.inventorySurface.open(),
        openMap: () => this.universalWorld?.worldMapSurface.open(),
        quitToTitle: () => this.quitToTitle(),
      },
      title: {
        canContinue: () => saveSystem.canContinue(),
        hasAutosave: () => saveSystem.hasSave(),
        newGame: () => { saveSystem.resetRun(); },
        continueGame: () => { void saveSystem.continueLatest(); },
      },
      wake: () => this.respawnPlayer(),
    });
    const onStoryChanged = (): void => shell.endCard.checkFlags();
    const onPlayerDamage = ({ source }: { source?: string }): void => { this.lastDamageSource = source; };
    gameEvents.on('story.changed', onStoryChanged);
    gameEvents.on('player.damage', onPlayerDamage);
    this.disposables.add(() => {
      gameEvents.off('story.changed', onStoryChanged);
      gameEvents.off('player.damage', onPlayerDamage);
      shell.destroy();
      if (this.shell === shell) this.shell = undefined;
    });
    return shell;
  }

  /** First-time control hints; what the player has learned is saved with the run as story flags. */
  private createControlHints(): ControlHintsController {
    const flag = (id: ControlHintId): string => `hint.${id}`;
    const hints = new ControlHintsController({
      isLearned: (id) => storyProgress.hasFlag(flag(id)),
      learn: (id) => storyProgress.setFlags([flag(id)]),
      isRelevant: (id) => {
        switch (id) {
          case 'move': return true;
          case 'interact': return this.interactionRouter?.hasCandidate() ?? false;
          case 'attack': return gameState.equippedWeaponId !== null;
          case 'dodge': return storyProgress.knowsAbility('dodge')
            && (this.universalWorld?.nearestEnemyDistance(this.player) ?? Number.POSITIVE_INFINITY) < HINT_DODGE_ENEMY_RANGE_PX;
          case 'inventory': return playerInventory.serialize().slots.some((slot) => slot !== null);
          case 'crafting': return playerInventory.count('wood') >= HINT_CRAFTING_WOOD;
          case 'weapon-switch': return playerWeaponLoadout.slots().filter((weaponId) => weaponId && playerWeaponLoadout.ownsWeapon(weaponId)).length >= 2;
          case 'sprint': return storyProgress.hasFlag('hint.move');
          case 'map':
          case 'pause': return storyProgress.hasFlag('hint.inventory');
          default: return false;
        }
      },
    });
    // Menus pause the game while open, so learn them (and report them to tutorial quests) as they open.
    const stopObserving = this.modalStack?.observe(({ id, open }) => {
      if (!open) return;
      if (id === 'inventory') hints.learn('inventory');
      if (id === 'crafting') hints.learn('crafting');
      if (id === 'world-map') hints.learn('map');
      if (id === 'pause-menu') hints.learn('pause');
      const controlId = MENU_CONTROL_IDS[id];
      if (controlId) gameEvents.emit('control.used', { controlId });
    });
    this.disposables.add(() => {
      stopObserving?.();
      if (this.hints === hints) this.hints = undefined;
    });
    return hints;
  }

  /** Shows the useful hint, and learns controls the player just used without a key press path. */
  private updateControlHints(direction: Phaser.Math.Vector2): void {
    const hints = this.hints;
    if (!hints) return;
    if (this.titleMode || this.paused || (this.healthSystem?.isDead() ?? false) || (this.sleepController?.sleeping ?? false)) {
      hints.hide();
      return;
    }
    if (direction.lengthSq() > 0) hints.learn('move');
    const sprinting = direction.lengthSq() > 0 && this.playerMotion().isActionPressed('sprint');
    if (sprinting && !this.sprinting) {
      hints.learn('sprint');
      gameEvents.emit('control.used', { controlId: 'sprint' });
    }
    this.sprinting = sprinting;
    hints.update();
  }

  /** Behind the title screen: no player, no HUD, a slow pan over Slimeshire. */
  private enterTitleMode(): void {
    this.playerVisual?.setAlpha(0);
    this.playerNameTag?.setVisible(false);
    this.cameras.main.stopFollow();
    const uiRoot = this.game.registry.get('universal-ui-root');
    if (uiRoot instanceof HTMLElement) {
      uiRoot.classList.add('is-title-screen');
      this.disposables.add(() => uiRoot.classList.remove('is-title-screen'));
    }
    this.shell?.title.open();
    if (this.titleNotice) this.shell?.title.showNotice(this.titleNotice);
    this.titleNotice = undefined;
  }

  /** Saves the run, fades out, and reloads to the title screen. */
  private quitToTitle(): void {
    if (this.transitioning) return;
    this.transitioning = true;
    saveSystem.writeRecovery(this.capturePlayerLocation());
    this.leaveAreaThen(() => returnToTitle());
  }

  private resetSceneStateForAreaLoad(): void {
    // Release NPC interaction sessions before destroying their actors. Modal
    // close callbacks can then return every movement lock while the actor
    // lifecycle is still alive; actor teardown follows as the final NPC step.
    this.questNpcController?.destroy();
    this.questNpcController = undefined;
    this.builtMap = undefined;
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
    this.sleepController?.destroy();
    this.sleepController = undefined;
    this.furniturePlacement?.destroy();
    this.furniturePlacement = undefined;
    this.placementModal?.unregister();
    this.placementModal = undefined;
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
    if (this.abilityLearnedHandler) {
      gameEvents.off('ability.learned', this.abilityLearnedHandler);
      this.abilityLearnedHandler = undefined;
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
      try {
        saveSystem.install(restored.data);
      } catch (error) {
        // A save that cannot be installed lands on the title with the reason, never a blank screen.
        console.error('The saved run could not be installed.', error);
        this.titleNotice = `That save could not be loaded. ${error instanceof Error ? error.message.split('\n')[0] : ''}`.trim();
        return false;
      }
      if (restored.kind === 'reset') saveSystem.completeResetHandoff();
      this.pendingRestoreLocation = restored.data.location;
      WorldScene.sessionStarted = true;
    }
    return restored.restored;
  }

  /**
   * Hit-stop (9.1) freezes more than the scene runtime: Arcade physics (so a
   * sliding slime or a knocked-back enemy stops too), tweens and sprite
   * animation hold still until it ends.
   */
  private holdForHitStop(frozen: boolean): void {
    if (frozen === this.hitStopHeld) return;
    this.hitStopHeld = frozen;
    if (frozen) {
      this.physics.world.pause();
      this.tweens.timeScale = 0;
      this.anims.pauseAll();
      return;
    }
    // A modal pause (inventory, dialogue) that began during the stop keeps physics paused.
    if (!this.paused) this.physics.world.resume();
    this.tweens.timeScale = 1;
    this.anims.resumeAll();
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
    if (shouldPause) this.hints?.hide();
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
      // Hit-stop: the whole world holds still for a moment while rendering, the shake and particles carry on.
      const frozen = gameFeel.frozen;
      this.holdForHitStop(frozen);
      this.universalWorld.advanceFrame(frozen ? 0 : delta / 1000);
      return;
    }
    this.updatePresentation(delta);
    if (!this.paused) this.updateGameplay(delta);
  }

  private updatePresentation(_delta: number): void {
    this.syncCameraLayers();

    if (this.paused) {
      this.closeEatHold();
      this.stopPlayerMotion();
      this.debugRenderer?.update();
    }
  }

  private updateGameplay(delta: number): void {
    this.updateQuestWaypoint(delta);
    this.universalWorld?.minimapSurface.update(this.cameras.main, this.player, this.waypointTarget);

    const now = this.simulationNow();
    this.finishExpiredActionAnimation(now);
    this.interactionRouter?.setSuppressed((this.sleepController?.sleeping ?? false) || (this.furniturePlacement?.active ?? false));
    // Right click acts on what the pointer is on; with nothing pointed at, the nearest target.
    this.interactionRouter?.update(this.pointerSeen ? this.pointerWorldPosition() : undefined);
    this.furniturePlacement?.update();
    this.statusEffects?.update(now, delta);
    this.updateSlimeTrail(now);
    this.gulp?.update();
    this.gulpHud?.update(this.player, this.gulp?.activeForm, this.gulp?.remainingMs() ?? 0, this.gulp?.nearestSpot());
    this.abilitySystem?.update();
    this.combatController?.update(now, delta);
    this.occlusionController?.update();
    this.depthDiagnostics?.update();
    // Passive energy regen.
    if (!this.healthSystem?.isDead()) {
      const stats = getStats();
      const regen = (stats.energyRegenPerSec * delta) / 1000;
      if (regen > 0) gameState.regenEnergy(regen);
    }

    // Respawn override: if dead, skip input but still tick systems above.
    if (this.healthSystem?.isDead()) {
      this.closeEatHold();
      this.stopPlayerMotion();
      this.player.rotation = 0;
      this.debugRenderer?.update();
      return;
    }

    if (this.sleepController?.sleeping) {
      this.closeEatHold();
      this.sleepController.update(delta);
      this.debugRenderer?.update();
      return;
    }

    const direction = this.playerController.readDirection();
    this.updateControlHints(direction);

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

    if (this.updateEatHold(direction)) {
      // The quick wheel owns the arrow keys while it is open: the slime stands still.
      this.stopPlayerMotion();
      this.debugRenderer?.update();
      return;
    }

    if (this.handleActionInput()) {
      this.debugRenderer?.update();
      return;
    }

    this.squashOnMoveStart(direction);
    this.playerController.move(direction);
    this.debugRenderer?.update();
  }

  /**
   * Once the Goo Trail is learned, drops goo marks while the slime is on the
   * ground; enemies on fresh goo move at the `slow` status's speed.
   */
  private updateSlimeTrail(now: number): void {
    const trail = this.slimeTrail;
    const body = this.player?.body as Phaser.Physics.Arcade.Body | undefined;
    if (!trail || !body) return;
    const grounded = storyProgress.knowsAbility('goo-trail') && !this.healthSystem?.isDead()
      && !this.sleepController?.sleeping && !this.transitioning && !(this.abilitySystem?.isBusy() ?? false);
    trail.update(now, grounded ? { x: this.player.x, y: resolveBodyBottom(body) - 3 } : undefined);
    if (now < this.nextTrailSlowAt) return;
    this.nextTrailSlowAt = now + 100;
    this.universalWorld?.slowEnemiesNear(trail.model.freshPoints(now), 26, statusSpeedMultiplier('slow'), 400);
  }

  /** A little lean into a walk that starts from standing still (not on every key tap). */
  private squashOnMoveStart(direction: Phaser.Math.Vector2): void {
    const moving = direction.lengthSq() > 0;
    const now = this.time.now;
    if (moving && !this.wasMoving && now - this.stillSince >= 150) this.squash?.play('move-start');
    if (!moving && this.wasMoving) this.stillSince = now;
    this.wasMoving = moving;
  }

  /**
   * W (roadmap 7.2): a tap eats when released (a Gulp spot, else the last-used
   * material, else burps a form); holding opens the quick wheel of carried Gulp
   * materials, the arrow keys or the mouse choose, and releasing eats the choice.
   * True while the wheel is open.
   */
  private updateEatHold(direction: Phaser.Math.Vector2): boolean {
    const hold = this.eatHold;
    const gulp = this.gulp;
    if (!hold || !gulp) return false;
    const now = this.time.now;
    // Frames were skipped (a menu, a knockback): drop the press rather than eat late.
    if (now - hold.lastSeen > 600) {
      this.closeEatHold();
      return false;
    }
    hold.lastSeen = now;
    if (!this.playerMotion().isActionPressed('eat')) {
      if (hold.open) {
        const entry = hold.selected === undefined ? undefined : hold.entries[hold.selected];
        if (entry && gulp.eatMaterial(entry.itemId) !== 'nothing') this.playActionAnimation('slime-eat');
      } else if (!hold.empty && gulp.eat() !== 'nothing') {
        this.playActionAnimation('slime-eat');
      }
      this.closeEatHold();
      return false;
    }
    if (!hold.open && !hold.empty && now - hold.since >= GULP_WHEEL_HOLD_MS) {
      const entries = gulp.wheelEntries();
      if (entries.length === 0) {
        hold.empty = true;
        floatingText.spawn(this, this.player.x, this.player.y - 56, 'No Gulp materials carried', 'white', false);
      } else {
        const preferred = gulp.preferredMaterial;
        hold.open = true;
        hold.entries = entries;
        hold.selected = Math.max(0, entries.findIndex((entry) => entry.itemId === preferred));
        hold.pointerStart = this.pointerWorldPosition();
        this.gulpWheel?.open(entries);
      }
    }
    if (!hold.open) return false;
    let pick = pickGulpWheelSlot(direction, hold.entries.length);
    const pointer = this.pointerWorldPosition();
    if (pick === undefined && hold.pointerStart && Math.hypot(pointer.x - hold.pointerStart.x, pointer.y - hold.pointerStart.y) > 10) {
      pick = pickGulpWheelSlot({ x: pointer.x - this.player.x, y: pointer.y - (this.player.y - 28) }, hold.entries.length);
    }
    if (pick !== undefined) hold.selected = pick;
    this.gulpWheel?.update({ x: this.player.x, y: this.player.y }, hold.selected);
    return true;
  }

  private closeEatHold(): void {
    if (!this.eatHold) return;
    this.eatHold = undefined;
    this.gulpWheel?.close();
  }

  private pointerWorldPosition(): { x: number; y: number } {
    const pointer = this.input.activePointer;
    const point = this.cameras.main.getWorldPoint(pointer.x, pointer.y);
    return { x: point.x, y: point.y };
  }

  private createDebugRenderer(): void {
    this.debugRenderer = new WorldDebugRenderer({
      scene: this,
      dimensions: this.worldDimensions,
      getPlayer: () => this.player,
      getCombatTargets: () => this.combatController?.targets ?? null,
      getTransitionZones: () => [],
      getEnemySpawnAreas: () => this.builtMap?.enemySpawnAreas ?? [],
      getBossBattleAreas: () => this.universalWorld?.bossBattleAreas ?? [],
      getWorldVisuals: () => this.universalWorld?.worldVisuals ?? [],
      getEnemyAttackAreas: () => this.universalWorld?.enemyAttackAreas ?? [],
      getWeaponSwing: () => this.universalWorld?.weaponDebugSwing,
      getHurtboxes: () => this.universalWorld?.hurtboxes ?? [],
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

  private transitionTo(areaId: AreaId, entry: AreaEntry): void {
    this.transitioning = true;
    this.stopPlayerMotion();
    this.leaveAreaThen(() => this.navigateToArea(areaId, entry, false));
  }

  /** Fades the picture and the music out, then travels (a map change reloads the page). */
  private leaveAreaThen(travel: () => void): void {
    this.universalWorld?.fadeOutMusic(AREA_LEAVE_FADE_MS);
    this.cameras.main.fadeOut(AREA_LEAVE_FADE_MS, 11, 16, 32);
    this.time.delayedCall(AREA_LEAVE_FADE_MS, travel);
  }

  private requestAuthoredExit(request: WorldExitRequest): WorldExitResult {
    if (request.mapId !== this.loadedMap.map.mapId) return { status: 'ignored' };
    if (this.transitioning) return { status: 'ignored' };
    const entry: AreaEntry | undefined = request.targetDoorId
      ? { entryDoor: request.targetDoorId }
      : isDirection(request.entry) ? { entryEdge: request.entry } : undefined;
    if (!request.targetAreaId || !entry) {
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

    this.transitionTo(request.targetAreaId, entry);
    return { status: 'queued' };
  }

  /** Reloads into the bed's area with the player standing at the bed. */
  private navigateToRespawnPoint(point: RespawnPointData): void {
    navigateToAreaUrl(
      point.areaId,
      {},
      true,
      saveSystem.captureCurrentState({
        ...this.capturePlayerLocation(),
        areaId: point.areaId,
        mapId: point.mapId,
        x: point.x,
        y: point.y,
      }),
    );
  }

  private createGulp(): void {
    this.gulp = new GulpController({
      now: () => this.simulationNow(),
      formDurationMs: GAME_CONSTANTS.gulp.formDurationMs,
      playerPosition: () => ({ x: this.player.x, y: this.player.y }),
      spots: () => this.universalWorld?.gulpSpots() ?? [],
      inventoryCount: (itemId) => playerInventory.count(itemId),
      consume: (itemId) => playerInventory.transact([{ itemId, count: 1 }], []),
      onFormChanged: (form, reason) => {
        this.restorePlayerTint();
        gameEvents.emit('gulp.changed', { formId: form?.id ?? null, reason });
        const message = form
          ? (reason === 'refreshed' ? `${form.name} refreshed` : `${form.name.toUpperCase()}!`)
          : reason === 'burp' ? 'Burp!' : reason === 'expired' ? 'The form wore off' : undefined;
        if (message) floatingText.spawn(this, this.player.x, this.player.y - 56, message, form ? 'cyan' : 'white', true);
      },
      showMessage: (text) => floatingText.spawn(this, this.player.x, this.player.y - 56, text, 'white', false),
    });
    const waypoint = new QuestWaypointPresenter(this);
    this.waypointPresenter = waypoint;
    this.disposables.add(() => {
      waypoint.destroy();
      if (this.waypointPresenter === waypoint) this.waypointPresenter = undefined;
    });
    // A Gulp spot is also an interactable: right-clicking it eats, the same as a tap of the mouth key.
    // No badge: the spot's own "[Q] Gulp" hint already floats over it.
    const unregisterSpots = this.interactionRouter?.register('gulp-spots', {
      getCandidate: () => {
        const gulp = this.gulp;
        const spot = gulp?.nearestSpot();
        if (!gulp || !spot) return undefined;
        const material = itemRegistry.get(spot.materialItemId)?.name ?? spot.materialItemId;
        return {
          id: `gulp-spots:${Math.round(spot.x)}:${Math.round(spot.y)}`,
          prompt: `Gulp the ${material}`,
          priority: 60,
          origin: () => spot,
          execute: () => {
            if (gulp.eat() !== 'nothing') this.playActionAnimation('slime-eat');
            return true;
          },
        };
      },
    });
    if (unregisterSpots) this.disposables.add(unregisterSpots);
    const hud = new GulpHud(this);
    this.gulpHud = hud;
    const wheel = new GulpWheel(this);
    this.gulpWheel = wheel;
    this.disposables.add(() => {
      hud.destroy();
      wheel.destroy();
      if (this.gulpHud === hud) this.gulpHud = undefined;
      if (this.gulpWheel === wheel) this.gulpWheel = undefined;
      this.eatHold = undefined;
      this.gulp = undefined;
    });
  }

  /**
   * The quest waypoint (clicking the quest tracker): where the tracked quest's
   * next step happens on this map, re-resolved a few times a second.
   */
  private updateQuestWaypoint(delta: number): void {
    const tracker = this.universalWorld?.questTrackerSurface;
    if (!tracker?.showingWay || !this.player || this.titleMode) {
      this.waypointTarget = undefined;
      this.waypointPresenter?.hide();
      return;
    }
    const now = this.time.now;
    if (now >= this.nextWaypointResolveAt) {
      this.nextWaypointResolveAt = now + 250;
      const quest = tracker.waypointQuest();
      const from = { x: this.player.x, y: this.player.y };
      this.waypointTarget = quest ? resolveQuestWaypoint(quest, this.questWaypointWorld(), from) : undefined;
      tracker.setWaypointFound(this.waypointTarget !== undefined);
    }
    this.waypointPresenter?.update(delta, { x: this.player.x, y: this.player.y }, this.waypointTarget);
  }

  private questWaypointWorld(): QuestWaypointWorld {
    const world = this.universalWorld;
    return {
      npcPosition: (npcId) => this.questNpcController?.npcPosition(npcId),
      bossCampPosition: (bossId) => world?.bossCampPosition(bossId),
      spawnAreaFor: (kinds, from) => {
        let best: { x: number; y: number } | undefined;
        for (const area of this.builtMap?.enemySpawnAreas ?? []) {
          if (!area.enemies.some((entry) => kinds.includes(entry.type))) continue;
          const stay = area.stayPerimeter;
          if (!stay || stay.shape !== 'rectangle') continue;
          const center = { x: stay.x + stay.w / 2, y: stay.y + stay.h / 2 };
          if (!best || Math.hypot(center.x - from.x, center.y - from.y) < Math.hypot(best.x - from.x, best.y - from.y)) best = center;
        }
        return best;
      },
      exitToArea: (areaId, from) => world?.exitToArea(areaId, from),
      nearestSource: (itemIds, from) => world?.nearestSource(itemIds, from),
      nearestStation: (station, from) => world?.nearestStation(station, from),
      restorationSite: (objectIds, from) => world?.restorationSite(objectIds, from),
    };
  }

  /** Clears a flash and puts back the Gulp form's look, if any. */
  /** A Gulp form draws the slime from its skin (a stone or silk slime); the tint is only a fallback. */
  private restorePlayerTint(): void {
    const form = this.gulp?.activeForm;
    const skinned = !!form && this.textures.exists(form.skinTextureKey);
    this.playerVisual?.setSkin(skinned ? form.skinTextureKey : undefined);
    if (form && !skinned) this.playerVisual?.setTint(form.tint);
    else this.playerVisual?.clearTint();
  }

  private createFurniturePlacement(): FurniturePlacementController {
    const controller = new FurniturePlacementController({
      scene: this,
      describe: (sceneIdValue) => this.universalWorld?.describePlaceable(sceneIdValue),
      playerPosition: () => ({ x: this.player.x, y: this.player.y }),
      isAreaFree: (rect) => this.isFootprintFree(rect),
      place: (request) => this.placeFurniture(request),
      onActiveChange: (active) => {
        if (active) this.placementModal?.open();
        else this.placementModal?.close();
      },
      showHint: (message) => floatingText.spawn(this, this.player.x, this.player.y - 56, message, 'white', false),
    });
    this.placementModal = this.modalStack?.register('furniture-placement', {
      isOpen: () => controller.active,
      close: () => controller.cancel(),
    });
    return controller;
  }

  private startFurniturePlacement(itemId: string): void {
    const sceneIds = itemRegistry.get(itemId)?.placeable?.sceneIds ?? [];
    if (!this.furniturePlacement || this.paused || this.transitioning || this.healthSystem?.isDead() || playerInventory.count(itemId) < 1) return;
    this.furniturePlacement.start(itemId, sceneIds);
  }

  /** Only blocking geometry counts: static bodies (walls, furniture, solid tiles) and the player. */
  private isFootprintFree(rect: FootprintRect): boolean {
    const { width, height } = this.worldDimensions;
    if (rect.x < 0 || rect.y < 0 || rect.x + rect.width > width || rect.y + rect.height > height) return false;
    if (this.physics.overlapRect(rect.x, rect.y, rect.width, rect.height, false, true).length > 0) return false;
    const player = this.player.body as Phaser.Physics.Arcade.Body | null;
    return !player || !Phaser.Geom.Rectangle.Overlaps(
      new Phaser.Geom.Rectangle(rect.x, rect.y, rect.width, rect.height),
      new Phaser.Geom.Rectangle(player.x, player.y, player.width, player.height),
    );
  }

  private placeFurniture(request: PlacementRequest): boolean {
    const mapId = this.loadedMap.map.mapId;
    const name = itemRegistry.get(request.itemId)?.name ?? request.itemId;
    if (!playerInventory.transact([{ itemId: request.itemId, count: 1 }], [])) return false;
    const record = worldProgress.placeFurniture(mapId, request);
    if (!this.universalWorld?.mountPlacedFurniture(record)) {
      worldProgress.removePlacedFurniture(mapId, record.id);
      playerInventory.transact([], [{ itemId: request.itemId, count: 1 }]);
      floatingText.spawn(this, request.x, request.y - 48, `${name} could not be placed`, 'white', true);
      return false;
    }
    gameEvents.emit('furniture.placed', {
      mapId, placementId: record.id, itemId: record.itemId, sceneId: record.sceneId, x: record.x, y: record.y,
    });
    floatingText.spawn(this, request.x, request.y - 48, `Placed ${name}`, 'green', false);
    return true;
  }

  private pickUpFurniture(placementId: string): boolean {
    const mapId = this.loadedMap.map.mapId;
    const record = worldProgress.placedFurniture(mapId).find((placed) => placed.id === placementId);
    if (!record || this.paused || this.furniturePlacement?.active) return false;
    const name = itemRegistry.get(record.itemId)?.name ?? record.itemId;
    if (!playerInventory.previewTransact([], [{ itemId: record.itemId, count: 1 }])) {
      floatingText.spawn(this, record.x, record.y - 56, 'Inventory full', 'white', true);
      return false;
    }
    worldProgress.removePlacedFurniture(mapId, placementId);
    this.universalWorld?.unmountPlacedFurniture(placementId);
    playerInventory.transact([], [{ itemId: record.itemId, count: 1 }]);
    // A bed that is picked up can no longer be woken up in.
    const respawn = worldProgress.respawnPoint;
    if (respawn && respawn.mapId === mapId && (respawn.bedId !== undefined
      ? respawn.bedId === placedBedId(placementId)
      : Phaser.Math.Distance.Between(respawn.x, respawn.y, record.x, record.y) < 128)) {
      worldProgress.clearRespawnPoint();
    }
    gameEvents.emit('furniture.picked-up', { mapId, placementId, itemId: record.itemId });
    floatingText.spawn(this, record.x, record.y - 56, `Picked up ${name}`, 'cyan', false);
    return true;
  }

  private openCraftingStation(site: CraftingSite): boolean {
    const world = this.universalWorld;
    if (!world || this.paused || world.craftingSurface.isOpen() || world.inventorySurface.isOpen()) return false;
    world.craftingSurface.open(site);
    gameEvents.emit('workbench.opened', { mapId: this.loadedMap.map.mapId, context: site.station });
    return true;
  }

  private requestSleep(request: SleepRequest): boolean {
    if (!this.sleepController || this.paused || this.transitioning || this.actionLocked || this.healthSystem?.isDead()) return false;
    return this.sleepController.sleep(request);
  }

  private createSleepController(): SleepController {
    const wakeActions = ['interact', 'pickup', 'attack', 'jump', 'dodge', 'stretch-lash', 'squash-slam', 'teleport', 'eat'];
    return new SleepController({
      scene: this,
      now: () => this.simulationNow(),
      teleportPlayer: (point) => this.teleportPlayer(point),
      setPlayerArtOffset: (offset) => {
        const visual = this.universalWorld?.playerPresentation;
        if (!visual) return;
        const scale = visual.get_global_transform().scale;
        visual.visualOffset = { x: offset.x / (scale.x || 1), y: offset.y / (scale.y || 1) };
      },
      setActionLocked: (locked) => { this.actionLocked = locked; },
      stopPlayerMotion: () => this.stopPlayerMotion(),
      playAnimation: (animationId, forceRestart) => this.playAnimation(`slime-${animationId}`, forceRestart),
      animationDurationMs: (animationId) => this.universalWorld?.playerAnimationDurationMs(animationId),
      heal: (amount) => this.healthSystem?.heal(amount, 'rest') ?? 0,
      isAtFullHealth: () => gameState.hp >= gameState.maxHp,
      consumeWakeInput: () => {
        const input = this.universalWorld?.managedPlayer;
        if (!input) return false;
        const moving = this.playerController.readDirection().lengthSq() > 0;
        // Consume every pending press so a stale key cannot wake the next nap.
        const pressed = wakeActions.filter((action) => input.consumeActionPress(action)).length > 0;
        return moving || pressed;
      },
      onFellAsleep: (request) => {
        worldProgress.setRespawnPoint({
          areaId: this.currentArea.id,
          mapId: this.loadedMap.map.mapId,
          x: Math.round(request.wakePoint.x),
          y: Math.round(request.wakePoint.y),
          bedId: request.bedId,
        });
        floatingText.spawn(this, request.sleepPoint.x, request.sleepPoint.y - 48, 'Respawn point set', 'cyan', false);
      },
      onSleepStateChanged: (asleep) => gameEvents.emit('player.sleep', { asleep }),
      onRested: () => gameEvents.emit('player.rested', {}),
      showMessage: (point, message, color) => floatingText.spawn(this, point.x, point.y, message, color, false),
    });
  }

  private navigateToArea(areaId: AreaId, entry: AreaEntry = {}, respawnHome = false): void {
    navigateToAreaUrl(
      areaId,
      entry,
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
      doors: map.player.doors ?? {},
      enemySafeZones: map.enemySafeZones ?? map.spawns?.safeZones ?? [],
      enemySpawnAreas: map.enemySpawnAreas ?? [],
      ...(map.spawns ? { spawns: map.spawns } : {}),
    };
    this.physics.world.setBounds(0, 0, this.worldDimensions.width, this.worldDimensions.height);

    // Blended terrain borders and wall props are drawn by the world's TileMapLayer2D node.

    this.collectibles = new CollectibleController({
      scene: this,
      mapId: this.loadedMap.map.mapId,
      transaction: playerInventoryWorldTransaction,
      progress: worldProgress,
      publisher: COLLECTIBLE_EVENTS,
      showMessage: (x, y, message, color, important) => floatingText.spawn(this, x, y, message, color, important),
      itemName: (itemId) => itemRegistry.get(itemId)?.name ?? itemId,
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
      isLootPointBlocked: (x, y) => {
        const { tileSize } = this.worldDimensions;
        return this.isResourceDropCellBlocked(Math.floor(x / tileSize), Math.floor((y - 1) / tileSize), LOOT_SOURCE_ID);
      },
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
    const nameTag = this.playerNameTag = this.add.text(this.player.x, this.player.y - 56, this.universalWorld!.managedPlayer.playerName, {
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
      getFormSpeedMultiplier: () => this.gulp?.activeForm?.speedMultiplier ?? 1,
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
    // Arriving mirrors leaving (leaveAreaThen): the picture fades in while the music rises.
    this.cameras.main.fadeIn(AREA_ARRIVE_FADE_MS, 11, 16, 32);
    this.cameras.main.setBounds(0, 0, this.worldDimensions.width, this.worldDimensions.height);
    this.cameraController = new ResponsiveCameraController(this, this.cameras.main);
    if (this.loadedMap.cameraMode === 'fixed') {
      const { width, height } = this.worldDimensions;
      this.cameraController.holdFixed({ centerX: width / 2, centerY: height / 2, width, height });
    } else {
      this.cameraController.resetZoom();
      this.cameraController.startFollow(this.player, true);
    }

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
    this.universalWorld?.updateMusic(delta);
    this.playerController?.updateVisuals();
    if (this.titleMode) this.panTitleCamera(delta);
    else this.cameraController?.update(delta);
    updateDevToolsCameraZoom(this.cameraController?.zoom ?? this.cameras.main.zoom);
    this.renderingDiagnostics?.update(this.time.now);
  }

  /** A slow side-to-side drift over the start area while the title screen shows. */
  private panTitleCamera(deltaMs: number): void {
    this.titleCameraMs += deltaMs;
    const spawn = this.builtMap?.playerSpawn ?? { x: this.worldDimensions.width / 2, y: this.worldDimensions.height / 2 };
    const drift = Math.sin(this.titleCameraMs / TITLE_PAN_PERIOD_MS * Math.PI * 2) * TITLE_PAN_RANGE_PX;
    this.cameras.main.centerOn(spawn.x + TITLE_PAN_OFFSET.x + drift, spawn.y + TITLE_PAN_OFFSET.y);
  }

  private getEntryAnchor(): Phaser.Math.Vector2 | undefined {
    const authoredPoint = (this.entryDoor ? this.builtMap?.doors[this.entryDoor] : undefined)
      ?? (this.entryEdge ? this.builtMap?.entries[this.entryEdge] : undefined)
      ?? this.builtMap?.playerSpawn;
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

  /**
   * Where a heavy Stretch Lash catch pulls the slime: `LASH_STANDOFF_PX` short
   * of the catch, stepping back towards the throw until the tile is walkable
   * (so a catch at the water's edge never drops the slime in the water).
   */
  private lashLanding(from: Readonly<{ x: number; y: number }>, caught: Readonly<{ x: number; y: number }>): Readonly<{ x: number; y: number }> {
    const length = Math.hypot(caught.x - from.x, caught.y - from.y);
    if (length <= LASH_STANDOFF_PX) return from;
    const dirX = (caught.x - from.x) / length;
    const dirY = (caught.y - from.y) / length;
    const tile = this.worldDimensions.tileSize;
    for (let distance = length - LASH_STANDOFF_PX; distance > 0; distance -= 8) {
      const x = from.x + dirX * distance;
      const y = from.y + dirY * distance;
      const tileX = Math.floor(x / tile);
      const tileY = Math.floor(y / tile);
      if (this.isWithinWorld(tileX, tileY) && !this.isSolidTile(tileX, tileY)) return { x, y };
    }
    return from;
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
    if (this.playerController.isMovementSuppressed()) return;
    this.useAbility(abilityId, this.statusEffects?.isRooted() ?? false);
  }

  /**
   * An ability from its key or its ability-bar button. Jump follows the
   * movement keys; Dodge, Stretch Lash and Teleport aim at the pointer (the
   * facing when it sits on the slime). Stuck in a web, nothing that moves the
   * slime works.
   */
  private useAbility(abilityId: PlayerAbilityId, stuck: boolean): void {
    const abilities = this.abilitySystem;
    if (!abilities) return;
    const aim = this.pointerAim();
    const toward = aim ?? this.playerController.facing;
    switch (abilityId) {
      case 'jump':
        if (!stuck) abilities.tryJump(this.playerController.readDirection());
        break;
      case 'dodge':
        if (!stuck && abilities.tryDodge(() => this.playerController.tryDodge(snapToCardinal(toward)))) this.hints?.learn('dodge');
        break;
      case 'stretch-lash': abilities.tryStretchLash(toward); break;
      case 'squash-slam': abilities.trySquashSlam(); break;
      case 'teleport':
        if (!stuck) abilities.tryTeleport(toward, aim?.distance);
        break;
    }
  }

  /** Where the pointer is from the slime's middle, or undefined when it sits on the slime or never reached the game. */
  private pointerAim(): PointerAim | undefined {
    if (!this.player || !this.pointerSeen) return undefined;
    return aimToward({ x: this.player.x, y: this.player.y - SLIME_CENTER_RISE_PX }, this.pointerWorldPosition());
  }

  /**
   * A swing of the equipped weapon. With `attackAim` on `pointer` the slime
   * first turns toward the pointer (snapped to 4 directions); on `facing` it
   * swings the way it last moved.
   */
  private attack(): boolean {
    if (gameSettings.settings.attackAim === 'pointer') {
      const aim = this.pointerAim();
      if (aim) this.playerController.face(snapToCardinal(aim));
    }
    // The weapon in hand always swings, even at a tree or rock (owner, 2026-10-01:
    // swapping to a tool on its own lost fights against enemies hiding behind one).
    return this.combatController?.tryAttack() ?? false;
  }

  /** Web hit: the player is stuck in place and wrapped in web until it wears off. */
  private applyWeb(durationMs: number): void {
    const alreadyStuck = this.statusEffects?.isRooted() ?? false;
    this.statusEffects?.apply('sticky', durationMs);
    if (alreadyStuck) return;
    this.universalWorld?.spawnEffect({
      effectId: 'spider-web-cover',
      direction: 'right',
      x: this.player.x,
      y: this.player.y,
      followPositionOf: this.player,
      followDepthOffset: 1,
    });
  }

  private handleActionInput(): boolean {
    const input = this.playerMotion();
    if (this.furniturePlacement?.active) {
      // Placing furniture: the player may walk; the attack button places, the
      // wheel switches the variant, interact cancels, and nothing else acts.
      const placement = this.furniturePlacement;
      if (input.consumeActionPress('attack')) placement.handlePointerDown();
      if (input.consumeActionPress('weapon-next')) placement.cycleVariant(1);
      if (input.consumeActionPress('weapon-previous')) placement.cycleVariant(-1);
      if (input.consumeActionPress('interact')) placement.cancel();
      for (const action of ['jump', 'dodge', 'stretch-lash', 'squash-slam', 'teleport', 'eat']) {
        input.consumeActionPress(action);
      }
      return false;
    }
    // Switching weapons never stops the slime walking.
    for (const [action, step] of [['weapon-next', 1], ['weapon-previous', -1]] as const) {
      if (!input.consumeActionPress(action)) continue;
      const slotIndex = playerWeaponLoadout.cycleSlot(step);
      if (slotIndex !== null) this.switchWeaponSlot(slotIndex);
    }
    if (this.updateInteractHold()) return true;
    if (input.consumeActionPress('interact')) {
      // The router owns the visible shared prompt, so its candidate must own
      // the press whenever one is displayed. A target with a second action
      // (pick up a placed bed or bench) waits for the release: holding picks it up.
      const router = this.interactionRouter;
      if (router?.hasCandidate()) {
        this.hints?.learn('interact');
        if (router.hasSecondary()) this.interactHold = { since: this.simulationNow() };
        else router.handleInteract();
      }
      return true;
    }

    // Stuck in a web: attacks still work, but nothing that moves the player.
    const stuck = this.statusEffects?.isRooted() ?? false;
    for (const abilityId of ['jump', 'dodge', 'stretch-lash', 'squash-slam', 'teleport'] as const) {
      if (!input.consumeActionPress(PLAYER_ABILITY_DEFINITIONS[abilityId].action)) continue;
      this.useAbility(abilityId, stuck);
      return true;
    }

    if (input.consumeActionPress('attack')) {
      if (this.attack()) this.hints?.learn('attack');
      return true;
    }

    if (input.consumeActionPress('eat')) {
      // Q is the mouth: what it does is decided on release or after a hold (updateEatHold).
      const now = this.time.now;
      this.eatHold = { since: now, lastSeen: now, open: false, empty: false, entries: [] };
      return true;
    }

    return false;
  }

  /**
   * Interact on a target with a second action: a short press does the main
   * action on release; holding past `INTERACT_HOLD_MS` does the second one.
   * True while the button is still held.
   */
  private updateInteractHold(): boolean {
    const hold = this.interactHold;
    if (!hold) return false;
    const router = this.interactionRouter;
    if (!router?.hasSecondary()) {
      this.interactHold = undefined;
      return false;
    }
    if (this.simulationNow() - hold.since >= INTERACT_HOLD_MS) {
      this.interactHold = undefined;
      router.handleSecondary();
      return true;
    }
    if (this.playerMotion().isActionPressed('interact')) return true;
    this.interactHold = undefined;
    router.handleInteract();
    return true;
  }

  private playActionAnimation(key: string): void {
    if (this.healthSystem?.isDead() || this.simulationNow() < this.playerKnockbackUntil) return;
    const animationId = key.startsWith('slime-') ? key.slice('slime-'.length) : key;
    const durationMs = this.universalWorld?.playerAnimationDurationMs(animationId);
    if (durationMs === undefined) return;
    gameEvents.emit('player.action', { anim: animationId });

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
    this.cameraController?.refitFixed();
  }

  // â”€â”€ Phase 1: health / damage / death / XP / items â”€â”€

  private onPlayerHit(result: AcceptedDamageResult): void {
    this.sleepController?.wake('damage');
    // Hits only: burn and poison ticks bypass this, so they never stutter the game.
    if (result.actualHpLost > 0) {
      gameFeel.play('player-hurt');
      this.squash?.play('hit');
      particleFx.play('slime-splash', this.player.x, this.player.y);
    }
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
        this.restorePlayerTint();
        this.iFrameFlashActive = false;
      });
    }
  }

  private onPlayerDeath(): void {
    this.sleepController?.wake('death');
    this.gulp?.clear();
    this.playerKnockbackUntil = 0;
    this.universalWorld?.resetActiveFights();
    this.playAnimation('slime-die', true);
    this.stopPlayerMotion();
    this.player.rotation = 0;
    gameFeel.play('player-defeated');
    floatingText.spawn(this, this.player.x, this.player.y - 40, 'DEFEATED', 'red', true);

    // After the defeat animation, the game-over screen offers waking or loading.
    this.time.delayedCall(1400, () => {
      if (!this.shell) { this.respawnPlayer(); return; }
      this.shell.showDefeat({
        cause: this.describeDefeat(this.lastDamageSource),
        playTimeMs: saveSystem.playTimeMs(),
        hasBed: worldProgress.respawnPoint !== undefined,
      });
    });
  }

  private respawnPlayer(): void {
    if (!this.healthSystem) return;

    // Home is the last bed slept in; without one (or if its world lost it), the start area's spawn.
    const plan = planRespawn(worldProgress.respawnPoint, (mapId, bedId) => this.bedExists(mapId, bedId));
    if (plan.kind === 'start' && plan.staleBed) worldProgress.clearRespawnPoint();
    const bed = plan.kind === 'bed' ? plan.point : undefined;
    if (bed && bed.mapId !== this.loadedMap.map.mapId) {
      gameState.revive();
      this.statusEffects?.clear();
      this.leaveAreaThen(() => this.navigateToRespawnPoint(bed));
      return;
    }
    if (!bed && this.currentArea.id !== STARTING_AREA_ID) {
      gameState.revive();
      this.statusEffects?.clear();
      this.leaveAreaThen(() => this.navigateToArea(STARTING_AREA_ID, {}, true));
      return;
    }

    const spawn = this.builtMap?.playerSpawn;
    const pos = this.findSpawnPoint(bed
      ? new Phaser.Math.Vector2(bed.x, bed.y)
      : spawn ? new Phaser.Math.Vector2(spawn.x, spawn.y) : this.getEntryAnchor());

    this.healthSystem.respawn();
    this.statusEffects?.clear();
    this.teleportPlayer(pos);
    this.playerKnockbackUntil = 0;
    this.playAnimation('slime-idle', true);
    this.playerVisual?.clearTint();
    this.playerVisual?.setAlpha(1);

    if (this.loadedMap.cameraMode === 'fixed') this.cameraController?.resetZoom();
    else {
      this.cameras.main.pan(pos.x, pos.y, 350, 'Power2');
      this.cameraController?.resetZoom();
      this.cameraController?.startFollow(this.player);
    }

    floatingText.spawn(this, pos.x, pos.y - 40, 'Respawned', 'green', true);
  }

  private bedExists(mapId: string, bedId: string | undefined): boolean {
    const content = this.game.registry.get(PREPARED_SCENE_CONTENT_KEY);
    if (!(content instanceof PreparedSceneContent)) return false;
    return worldHasBed({
      scene: (id) => content.catalog.get(sceneId(id)),
      placedFurniture: (id) => worldProgress.placedFurniture(id),
    }, mapId, bedId);
  }

  /** Names what defeated the player from the damage source ID ("Worm Brawler"). */
  private describeDefeat(source: string | undefined): string | undefined {
    if (!source) return undefined;
    const match = getCharacterPackages()
      .map((pack) => pack.character)
      .filter((character) => source.includes(character.characterId))
      .sort((left, right) => right.characterId.length - left.characterId.length)[0];
    const name = match?.displayName;
    return name ? name.charAt(0).toUpperCase() + name.slice(1) : undefined;
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

  /**
   * Controls that also work over an open window: the menu key and zoom. The
   * player's own actions (moving, both mouse buttons, the wheel, abilities)
   * arrive through the input router and the binding table instead.
   */
  private bindHotkeys(): void {
    const kb = this.input.keyboard;
    if (kb) {
      const onKeyDown = (event: KeyboardEvent): void => {
        if (event.repeat || this.titleMode) return;
        const zoom = (['zoom-in', 'zoom-out'] as const satisfies readonly ShellInputAction[])
          .find((action) => isControlCode(action, event.code));
        if (zoom) this.cameraController?.stepZoom(zoom === 'zoom-in' ? -1 : 1);
      };
      kb.on('keydown', onKeyDown);
      this.disposables.add(() => kb.off('keydown', onKeyDown));
    }
    // The menu key must also close a window that holds keyboard focus (windows stop
    // keys from bubbling), so it listens in the capture phase, like Esc and M.
    const onMenuKey = (event: KeyboardEvent): void => {
      if (!isControlCode('menu', event.code) || event.repeat || this.titleMode || event.ctrlKey || event.altKey || event.metaKey) return;
      if (event.target instanceof HTMLElement && event.target.closest('input, textarea, select, [contenteditable]')) return;
      if (this.toggleMenu()) {
        event.preventDefault();
        event.stopPropagation();
      }
    };
    document.addEventListener('keydown', onMenuKey, { capture: true });
    this.disposables.add(() => document.removeEventListener('keydown', onMenuKey, { capture: true }));

    // Right click is the interact button: the browser's menu never opens over the game.
    this.input.mouse?.disableContextMenu();
    const onPointer = (): void => { this.pointerSeen = true; };
    this.input.on('pointermove', onPointer);
    this.input.on('pointerdown', onPointer);
    this.disposables.add(() => {
      this.input.off('pointermove', onPointer);
      this.input.off('pointerdown', onPointer);
    });
  }

  /** The menu key: closes the open menu tab (bag, crafting, journal or map), else opens the bag. True when it did either. */
  private toggleMenu(): boolean {
    const world = this.universalWorld;
    if (!world || this.shell?.isAnyOpen()) return false;
    const open = this.menuTabs.current();
    if (open) {
      const windows = { inventory: world.inventorySurface, crafting: world.craftingSurface, journal: world.questJournalSurface, map: world.worldMapSurface };
      windows[open].close();
      return true;
    }
    if (this.actionLocked || this.paused || this.furniturePlacement?.active) return false;
    world.inventorySurface.open();
    return true;
  }

  /** Weak ground broke under the Heavy form. */
  private onGroundCracked(at: Readonly<{ x: number; y: number }>): void {
    gameFeel.play('ground-crack');
    gameEvents.emit('ground.cracked', { x: at.x, y: at.y });
    floatingText.spawn(this, at.x, at.y - 60, 'The ground gives way!', 'yellow', true, 1800);
  }

  /**
   * F at a ruined building (roadmap 6.3): on its quest and carrying the materials,
   * the player pays them, the story flag swaps the ruin for the restored building,
   * and quests hear `object.activated`. Otherwise it says why, in red when short.
   */
  private restoreSite(request: RestorationRequest): boolean {
    if (this.paused || this.transitioning || !request.flagId || storyProgress.hasFlag(request.flagId)) return false;
    // In front of the building, where the player stands (above the roof is off screen).
    const labelY = request.at.y - 36;
    if (request.questId && questService.get(request.questId)?.status !== 'active') {
      floatingText.spawn(this, request.at.x, labelY, request.lockedMessage, 'white', true, 2400);
      gameEvents.emit('building.restore-refused', { objectId: request.objectId, reason: 'locked' });
      return true;
    }
    const missing = request.cost
      .map((cost) => ({ ...cost, short: cost.count - playerInventory.count(cost.itemId) }))
      .filter((cost) => cost.short > 0)
      .map((cost) => `${cost.short} ${itemRegistry.get(cost.itemId)?.name ?? cost.itemId}`);
    if (missing.length > 0) {
      floatingText.spawn(this, request.at.x, labelY, `Missing: ${missing.join(', ')}`, 'red', true, 2400);
      gameEvents.emit('building.restore-refused', { objectId: request.objectId, reason: 'missing-materials' });
      return true;
    }
    for (const cost of request.cost) playerInventory.remove(cost.itemId, cost.count);
    storyProgress.setFlags([request.flagId]);
    gameEvents.emit('object.activated', { objectId: request.objectId, instanceId: request.instanceId, areaId: this.currentArea.id });
    gameEvents.emit('building.restored', { objectId: request.objectId, instanceId: request.instanceId, x: request.at.x, y: request.at.y });
    gameFeel.play('building-restored');
    const dust = this.add.particles(request.at.x, request.at.y - 70, 'dust-puff', {
      lifespan: { min: 700, max: 1200 },
      speed: { min: 30, max: 130 },
      angle: { min: 180, max: 360 },
      scale: { start: 2.2, end: 0.6 },
      alpha: { start: 0.95, end: 0 },
      emitZone: { type: 'random', source: new Phaser.Geom.Rectangle(-140, -90, 280, 120), quantity: 1 },
      emitting: false,
    }).setDepth(resolveWorldDepth(request.at.y + 60, { stableId: 'restoration-dust', attachmentSlot: 4 }).depth);
    dust.emitParticle(60);
    this.time.delayedCall(1300, () => dust.destroy());
    floatingText.spawn(this, request.at.x, labelY, request.restoredMessage, 'green', true, 2600);
    return true;
  }

  /** A web caught the slime: stuck for a moment and set back on the side it came from. */
  private catchInWeb(zone: Readonly<{ x: number; y: number; halfWidth: number; halfHeight: number }>): void {
    const fromAbove = this.player.y < zone.y;
    this.teleportPlayer({ x: this.player.x, y: fromAbove ? zone.y - zone.halfHeight - 26 : zone.y + zone.halfHeight + 30 });
    this.applyWeb(900);
    const now = this.time.now;
    if (now >= this.nextWebMessageAt) {
      this.nextWebMessageAt = now + 2500;
      floatingText.spawn(this, this.player.x, this.player.y - 56, 'Caught in the web! (something sticky could cross)', 'white', true, 2200);
    }
  }

  /** A Goo Heart raises max HP for the rest of the run; its story flag keeps it collected. */
  private collectGooHeart(heartId: string, at: Readonly<{ x: number; y: number }>): void {
    const flag = gooHeartFlag(heartId);
    if (storyProgress.hasFlag(flag)) return;
    storyProgress.setFlags([flag]);
    gameState.addGooHeart();
    const bonus = GAME_CONSTANTS.character.player.gooHeart.maxHpBonus;
    gameEvents.emit('goo-heart.collected', { heartId, maxHp: gameState.maxHp });
    this.universalWorld?.showAreaTitle(`Goo Heart! Max HP ${gameState.maxHp}`, GOO_HEART_COLOR);
    floatingText.spawn(this, at.x, at.y - 40, `+${bonus} max HP`, 'green', true, 2000);
  }

  /** The player switched weapons on the belt (wheel or a click): teaches the switch hint and tutorial. */
  private switchWeaponSlot(slotIndex: number): void {
    if (!this.equipWeaponSlot(slotIndex)) return;
    this.hints?.learn('weapon-switch');
    gameEvents.emit('control.used', { controlId: 'weapon-switch' });
  }

  /** Puts a belt slot's weapon in hand; true when the weapon in hand changed. */
  private equipWeaponSlot(slotIndex: number): boolean {
    const result = playerWeaponLoadout.equipSlot(slotIndex, (weaponId) => this.combatController?.equipWeapon(weaponId) ?? false);
    if (result.ok) {
      if (result.changed) {
        const item = weaponItemFor(result.weaponId);
        floatingText.spawn(this, this.player.x, this.player.y - 48, `${item?.name ?? result.weaponId} equipped`, 'yellow', true);
      }
      return result.changed;
    }
    const message = result.reason === 'empty'
      ? `Slot ${slotIndex + 1} is empty`
      : result.reason === 'not-owned'
        ? 'Weapon not in inventory'
        : result.reason === 'busy'
          ? 'Finish the attack first'
          : 'Weapon is unavailable';
    floatingText.spawn(this, this.player.x, this.player.y - 42, message, 'white');
    return false;
  }

  /**
   * A tree or rock the weapon in hand cannot harvest names its tool, and says
   * how to get it in hand when the player owns one (tools never swap by themselves).
   */
  private harvestBlockedMessage(request: ResourceHarvestBlocked): string {
    const belt = playerWeaponLoadout.slots().filter((weaponId): weaponId is string => !!weaponId && playerWeaponLoadout.ownsWeapon(weaponId));
    const bag = itemRegistry.all()
      .filter((item) => item.equipment && playerInventory.count(item.id) > 0)
      .map((item) => item.equipment!.weaponId);
    const advice = harvestToolAdvice(request, belt, bag, (weaponId) => {
      try {
        return getWeaponDefinition(weaponId).harvestCapabilities;
      } catch {
        return undefined;
      }
    });
    if (advice === 'belt') return `${request.message}: switch with the ${controlLabel('weapon-next').toLowerCase()}`;
    if (advice === 'bag') return `${request.message}: put yours on the belt (${controlLabel('menu')})`;
    return request.message;
  }

  /** Holds a weapon from the bag; with a full belt it takes the slot of the weapon in hand. */
  private equipWeaponFromInventory(weaponId: string): void {
    const slotIndex = playerWeaponLoadout.ensureAssigned(weaponId);
    if (slotIndex !== null) {
      this.equipWeaponSlot(slotIndex);
      return;
    }
    const inHand = playerWeaponLoadout.equippedWeaponId();
    const handSlot = inHand ? playerWeaponLoadout.slots().indexOf(inHand) : -1;
    this.assignWeaponSlot(weaponId, Math.max(0, handSlot));
    if (playerWeaponLoadout.equippedWeaponId() !== weaponId) this.equipWeaponSlot(Math.max(0, handSlot));
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
      dropEnemyLoot: (request) => this.inventoryDrops?.dropLoot(request),
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
      setNpcDialoguePaused: (paused) => this.setSimulationPaused('npc-dialogue', paused),
      setWorldMapPaused: (paused) => this.setSimulationPaused('worldmap', paused),
      shellSurfaces: [
        ...(this.shell?.surfaces ?? []),
        ...(this.hints ? [[CONTROL_HINT_SURFACE_ID, this.hints] as const] : []),
        [MENU_TABS_SURFACE_ID, this.menuTabs] as const,
      ],
      shellSceneIds: [...GAME_SHELL_SCENE_IDS, 'ui.control-hint', 'ui.menu-tabs'],
      setStoryFlags: (flagIds) => storyProgress.setFlags(flagIds),
      getCurrentAreaId: () => this.currentArea.id,
      worldDimensions: this.worldDimensions,
      onCrafted: ({ recipe }) => {
        if (itemRegistry.get(recipe.output.itemId)?.placeable) {
          // Straight from the bench to the ground: close crafting and start placing (Esc keeps it in the bag).
          this.universalWorld?.craftingSurface.close();
          this.startFurniturePlacement(recipe.output.itemId);
          floatingText.spawn(this, this.player.x, this.player.y - 44, `Crafted: ${recipe.name}`, 'green', true);
          return;
        }
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
      onPlaceInventoryItem: (itemId) => this.startFurniturePlacement(itemId),
      onEquipInventoryWeapon: (weaponId) => this.equipWeaponFromInventory(weaponId),
      onAssignInventoryWeapon: (weaponId, slotIndex) => this.assignWeaponSlot(weaponId, slotIndex),
      canDropInventoryItem: (itemId) => this.inventoryDrops?.canDrop(itemId) ?? false,
      onDropInventoryItem: (slotIndex, quantity) => this.inventoryDrops?.dropFromSlot(slotIndex, quantity) ?? false,
      showMessage: (x, y, message, color = 'white', important = false) => floatingText.spawn(this, x, y, message, color, important),
      harvestBlockedMessage: (request) => this.harvestBlockedMessage(request),
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
      requestSleep: (request) => this.requestSleep(request),
      plateWeights: () => (this.gulp?.activeForm?.pressesPlates && this.player ? [{ x: this.player.x, y: this.player.y }] : []),
      hasStoryFlag: (flagId) => storyProgress.hasFlag(flagId),
      groundCrack: {
        groundCracked: (at) => this.onGroundCracked(at),
        lastHeavyLanding: () => this.heavyLanding,
        groundCreaks: (at) => {
          const now = this.time.now;
          if (now < this.nextCreakHintAt) return;
          this.nextCreakHintAt = now + 4000;
          floatingText.spawn(this, at.x, at.y - 50, 'It creaks under you... jump on it! (Space)', 'yellow', true, 2200);
        },
      },
      spiderWebs: {
        playerPosition: () => (this.player && !this.healthSystem?.isDead() && !this.transitioning ? { x: this.player.x, y: this.player.y } : undefined),
        playerCrossesWebs: () => this.gulp?.activeForm?.crossesWebs ?? false,
        catchPlayer: (zone) => this.catchInWeb(zone),
        webTorn: (zone) => {
          gameEvents.emit('web.torn', { x: zone.x, y: zone.y });
          particleFx.play('loot-sparkle', zone.x, zone.y);
          floatingText.spawn(this, zone.x, zone.y - 40, 'The web tears open!', 'cyan', true, 1800);
        },
      },
      gooHearts: {
        isCollected: (heartId) => storyProgress.hasFlag(gooHeartFlag(heartId)),
        collect: (heartId, at) => this.collectGooHeart(heartId, at),
        playerPosition: () => (this.player && !this.healthSystem?.isDead() ? { x: this.player.x, y: this.player.y } : undefined),
      },
      trainingDummies: {
        showHit: (at, damage) => floatingText.spawn(this, at.x, at.y - 96, `${damage}`, 'orange', true),
      },
      lashBells: {
        rung: (at) => {
          gameEvents.emit('lash-bell.rung', { x: at.x, y: at.y });
          particleFx.play('loot-sparkle', at.x, at.y - 70);
        },
      },
      abilityLessons: {
        playerPosition: () => (this.player && !this.healthSystem?.isDead() ? { x: this.player.x, y: this.player.y } : undefined),
        knows: (abilityId) => storyProgress.knowsAbility(abilityId),
        learn: (abilityIds) => storyProgress.learnAbilities(abilityIds),
      },
      restoreSite: (request) => this.restoreSite(request),
      openCraftingStation: (context) => this.openCraftingStation(context),
      pickUpFurniture: (placementId) => this.pickUpFurniture(placementId),
      onEquipWeaponSlot: (slotIndex) => this.switchWeaponSlot(slotIndex),
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

  /** Cheat buttons on the development panel; they exist only in `pnpm dev`, never in a release build. */
  private bindDevCheats(): void {
    if (!import.meta.env.DEV) return;
    const onCheat = ({ cheat }: { cheat: string }): void => {
      if (this.paused || this.healthSystem?.isDead() || !this.player) return;
      const { x, y } = this.player;
      switch (cheat) {
        case 'damage': {
          if (this.playerController.isDodging()) {
            floatingText.spawn(this, x, y - 30, 'DODGED!', 'cyan', true);
            return;
          }
          const request: DamageRequest = { amount: 20, source: 'debug', knockStrength: 180, knockX: x > this.worldDimensions.width / 2 ? -1 : 1, knockY: 0 };
          this.healthSystem?.applyDamage(request, this.simulationNow());
          return;
        }
        case 'heal':
          this.healthSystem?.heal(gameState.maxHp);
          floatingText.spawn(this, x, y - 30, 'FULL HEAL', 'green', true);
          return;
        case 'coins':
          gameState.addCoins(100);
          return;
        case 'potion':
          playerInventory.add('hp-potion', 1);
          floatingText.spawn(this, x, y - 30, '+potion', 'green');
          return;
        case 'burn':
          this.statusEffects?.apply('burn');
          floatingText.spawn(this, x, y - 30, 'BURN!', 'orange');
          return;
        case 'slow':
          this.statusEffects?.apply('slow');
          floatingText.spawn(this, x, y - 30, 'SLOWED', 'cyan');
          return;
        case 'dummy':
          this.combatController?.spawnDummy(x + Phaser.Math.Between(60, 140), y + Phaser.Math.Between(-60, 60));
          floatingText.spawn(this, x, y - 30, '+dummy', 'white');
          return;
        case 'recipes':
          storyProgress.learnRecipes(RECIPE_CATALOG.map((recipe) => recipe.id));
          floatingText.spawn(this, x, y - 30, 'ALL RECIPES', 'green', true);
          return;
      }
    };
    gameEvents.on('dev.cheat', onCheat);
    this.disposables.add(() => gameEvents.off('dev.cheat', onCheat));
  }

}

function isDirection(value: string): value is Direction {
  return value === 'north' || value === 'east' || value === 'south' || value === 'west';
}

function isJsonObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

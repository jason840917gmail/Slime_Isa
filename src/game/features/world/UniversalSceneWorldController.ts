import Phaser from 'phaser';

import type { MapEnemyAreaPerimeter, MapEnemySafeZone, MapFile } from '../../content/maps/mapFormat';
import { getCharacterPackage } from '../../content/characters/CharacterCatalog';
import { resourceId, sceneId, type SceneId } from '../../content/scenes/identifiers';
import { ASSET_MANIFEST, type AssetId } from '../../infrastructure/assets/manifest';
import { createGlobalAudioCuePort } from '../../infrastructure/audio/GlobalAudioCuePort';
import { GlobalAudioServices } from '../../infrastructure/audio/GlobalAudioServices';
import { DEFAULT_AUDIO_SETTINGS, loadAudioSettings, saveAudioSettings } from '../../infrastructure/persistence/AudioSettingsStore';
import { AudioSettingsSurfacePort } from '../ui/AudioSettingsSurfacePort';
import { gameEvents } from '../../core/EventBus';
import { AudioEventBridge } from '../audio/AudioEventBridge';
import { CharacterBody2DNode } from '../../infrastructure/phaser-nodes/CharacterBody2DNode';
import { Area2DNode } from '../../infrastructure/phaser-nodes/Area2DNode';
import { Sprite2DNode } from '../../infrastructure/phaser-nodes/Sprite2DNode';
import { PhaserUniversalSceneRuntime, type MountedScene } from '../../infrastructure/scenes/PhaserUniversalSceneRuntime';
import type { PreparedSceneContent } from '../../infrastructure/scenes/PreparedSceneContent';
import type { Node } from '../../runtime/scene/Node';
import { InputRouter } from '../../runtime/scene/input/InputRouter';
import type { InputEventSink } from '../../runtime/scene/input/InputRouter';
import { Node2D } from '../../runtime/scene/Node2D';
import { AttackActivation } from '../combat/AttackActivation';
import type { RoutedDamageOutcome } from '../combat/DamageRouter';
import { DamageRouter } from '../combat/DamageRouter';
import type { InteractionProvider, InteractionRouter } from '../interaction/InteractionRouter';
import type { NpcActorHandle, QuestNpcRegistration } from '../interaction/QuestNpcController';
import { createNpcWanderState, stepNpcWander } from '../npcs/NpcWanderPolicy';
import { NpcNameTags, type NpcQuestMarker } from '../npcs/NpcNameTags';
import { AttackTelegraphs } from '../effects/AttackTelegraphs';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import type { InventoryWorldTransaction } from '../progression/InventoryWorldTransaction';
import type { WorldProgress } from '../progression/WorldProgress';
import type { EnemyPopulationMember, EnemySpawnRequest } from '../../enemies/AuthoredEnemyPopulationController';
import type { ManagedEnemyDefeat } from '../combat/CombatController';
import {
  BOSS_CAMP_PROGRESS_SERVICE,
  BOSS_SCENE_SPAWNER_SERVICE,
  BOSS_UI_SERVICE,
  BossCampScript,
  type BossSceneSpawnRequest,
} from '../scripts/BossCampScript';
import {
  CHEST_GUARD_SERVICE,
  CHEST_VIEW_SERVICE,
  CHEST_WORLD_SERVICE,
  ChestScript,
} from '../scripts/ChestScript';
import {
  ATTACK_ACTIVATION_SERVICE,
  DAMAGE_ROUTER_SERVICE,
  ENEMY_TARGET_SERVICE,
  EnemyScript,
  type EnemyDamageNumberRequest,
  type EnemyDebugAttackArea,
  type EnemyTelegraphRequest,
  type EnemyNavigationSnapshot,
  type EnemyProjectileRequest,
} from '../scripts/EnemyScript';
import { createGameDescriptorRegistry, createGameScriptRegistry } from '../scripts/registrations';
import {
  NPC_RUNTIME_SERVICE,
  NpcScript,
  type NpcRuntimeRequest,
  type NpcWanderAgent,
} from '../scripts/NpcScript';
import { PLAYER_HEALTH_SERVICE, PlayerScript } from '../scripts/PlayerScript';
import { ProjectileScript } from '../scripts/ProjectileScript';
import { EffectScript } from '../scripts/EffectScript';
import {
  RESOURCE_NODE_SERVICE,
  ResourceNodeScript,
  type ResourceDropRequest,
  type ResourceHarvestBlocked,
  type ResourceHitFeedbackRequest,
} from '../scripts/ResourceNodeScript';
import {
  WORLD_OBJECT_STATE_SERVICE,
  type WorldObjectStatePort,
} from '../scripts/DestructibleScript';
import type { ManagedResourceRegistration } from '../resources/ResourceNodeController';
import type { ObjectOccluderRegistration } from '../objects/ObjectRegistration';
import type { OcclusionActorRegistration } from '../occlusion/OcclusionController';
import type { WorldDropRequest } from '../collectibles/WorldDropRequest';
import {
  resolveWorldDropTrajectory,
  WORLD_DROP_FLIGHT_MS,
  WORLD_DROP_REBOUND_HEIGHT,
  WORLD_DROP_REBOUND_MS,
  WORLD_DROP_SETTLE_MS,
  WORLD_DROP_STAGGER_MS,
} from '../collectibles/WorldDropMotion';
import {
  COLLECTIBLE_WORLD_SERVICE,
  CollectibleScript,
  type CollectiblePickupRequest,
  type CollectiblePickupResult,
  type CollectibleWorldPort,
} from '../scripts/CollectibleScript';
import {
  PLAYER_WEAPON_COMBAT_SERVICE,
  WeaponScript,
  type ManagedWeaponTarget,
  type WeaponAttackDirection,
  type WeaponDamagePayload,
} from '../scripts/WeaponScript';
import type { WorldEffectSpawnRequest } from '../effects/WorldEffectSpawn';
import { WorldEffectPositionAttachment } from '../effects/WorldEffectPositionAttachment';
import { resolvePhysicsPresentationPosition, type PhysicsPresentationTarget } from '../../presentation/PhysicsPresentation';
import { PLAYER_INPUT_ACTIONS } from '../player/PlayerInputActions';
import type { PlayerHealthController } from '../player/PlayerHealthController';
import type { ModalStack } from '../../ui/ModalStack';
import { HtmlControlPresentationAdapter } from '../../infrastructure/phaser-nodes/ui/HtmlControlPresentationAdapter';
import { HudSurfacePort } from '../ui/HudSurfacePort';
import { WeaponHotbarSurfacePort } from '../ui/WeaponHotbarSurfacePort';
import { AbilityBarSurfacePort } from '../ui/AbilityBarSurfacePort';
import { PlayerHealthSurfacePort } from '../ui/PlayerHealthSurfacePort';
import { BossHealthSurfacePort } from '../ui/BossHealthSurfacePort';
import { AreaTitleSurfacePort } from '../ui/AreaTitleSurfacePort';
import { FloatingTextSurfacePort } from '../ui/FloatingTextSurfacePort';
import { InventorySurfacePort } from '../ui/InventorySurfacePort';
import { ChestInventorySurfacePort } from '../ui/ChestInventorySurfacePort';
import { CraftingSurfacePort } from '../ui/CraftingSurfacePort';
import { QuestJournalSurfacePort } from '../ui/QuestJournalSurfacePort';
import { QuestOfferSurfacePort } from '../ui/QuestOfferSurfacePort';
import { NpcDialogueSurfacePort } from '../ui/NpcDialogueSurfacePort';
import { QuestTrackerSurfacePort } from '../ui/QuestTrackerSurfacePort';
import { WorldMapSurfacePort } from '../ui/WorldMapSurfacePort';
import { LevelUpSurfacePort } from '../ui/LevelUpSurfacePort';
import { MinimapSurfacePort } from '../ui/MinimapSurfacePort';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { craftingService } from '../../crafting/Crafting';
import type { CraftSuccess } from '../../crafting/CraftingService';
import { floatingText } from '../../ui/FloatingText';
import type { PlayerAbilityController } from '../player/PlayerAbilityController';
import type { PlayerAbilityId } from '../player/PlayerAbilityDefinitions';
import { UI_SURFACE_SERVICE, type UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import {
  WORLD_EXIT_SERVICE,
  type WorldExitPort,
  type WorldExitRequest,
  type WorldExitResult,
} from '../scripts/WorldExitScript';
import { BedScript } from '../scripts/BedScript';
import { WorkbenchScript } from '../scripts/WorkbenchScript';
import type { CraftingContext } from '../../content/recipes/types';
import type { PlacedFurnitureData } from '../../infrastructure/persistence/SaveSchema';
import type { PlaceableVisual } from '../building/FurniturePlacementController';
import { DoorScript } from '../scripts/DoorScript';
import type { SleepRequest } from '../rest/SleepController';

export interface UniversalSceneWorldControllerOptions {
  readonly scene: Phaser.Scene;
  readonly content: PreparedSceneContent;
  readonly map: MapFile;
  readonly worldSceneId: SceneId;
  readonly playerSpawn: Readonly<{ x: number; y: number }>;
  readonly health: PlayerHealthController;
  readonly progress: WorldProgress;
  readonly transaction: InventoryWorldTransaction;
  readonly interactions: InteractionRouter;
  readonly modalStack: ModalStack;
  readonly setChestPaused: (paused: boolean) => void;
  readonly setInventoryPaused: (paused: boolean) => void;
  readonly setCraftingPaused: (paused: boolean) => void;
  readonly setJournalPaused: (paused: boolean) => void;
  readonly setQuestOfferPaused: (paused: boolean) => void;
  readonly setNpcDialoguePaused: (paused: boolean) => void;
  readonly setWorldMapPaused: (paused: boolean) => void;
  readonly setLevelUpPaused: (paused: boolean) => void;
  readonly setAudioSettingsPaused: (paused: boolean) => void;
  readonly getCurrentAreaId: () => string;
  readonly worldDimensions: WorldDimensions;
  readonly onCrafted: (result: CraftSuccess) => void;
  readonly onUseInventoryItem: (itemId: string) => void;
  readonly onPlaceInventoryItem: (itemId: string) => void;
  readonly onEquipInventoryWeapon: (weaponId: string) => void;
  readonly onAssignInventoryWeapon: (weaponId: string, slotIndex: number) => void;
  readonly canDropInventoryItem: (itemId: string) => boolean;
  readonly onDropInventoryItem: (slotIndex: number, quantity: number) => boolean;
  readonly showMessage: (x: number, y: number, message: string, color?: 'white' | 'yellow' | 'green' | 'cyan' | 'orange' | 'red', important?: boolean) => void;
  readonly updateGameplay: (deltaMs: number) => void;
  readonly updatePresentation: (deltaMs: number) => void;
  readonly transformManagedWeaponDamage: (damage: number, target: ManagedWeaponTarget) => number;
  readonly onManagedWeaponOutcome: (outcome: RoutedDamageOutcome, target: ManagedWeaponTarget | undefined) => void;
  readonly onManagedWeaponAttackStarted: (weaponId: string, direction: WeaponAttackDirection) => void;
  readonly onManagedWeaponAttackFinished: (weaponId: string, direction: WeaponAttackDirection) => void;
  readonly onManagedEnemyDefeated: (enemy: ManagedEnemyDefeat) => void;
  readonly getEnemySafeZones: () => readonly MapEnemySafeZone[];
  readonly registerNpc?: (registration: QuestNpcRegistration) => void;
  readonly registerManagedResource: (registration: ManagedResourceRegistration) => void;
  readonly spawnManagedResourceDrops: (request: ResourceDropRequest) => void;
  readonly collectibles: CollectibleWorldPort;
  readonly registerOccluder?: (registration: ObjectOccluderRegistration) => { dispose(): void };
  /** Registers a character visual that should reveal a silhouette when occluded. */
  readonly registerOcclusionActor?: (registration: OcclusionActorRegistration) => { dispose(): void };
  readonly requestExit: (request: WorldExitRequest) => WorldExitResult;
  /** Lies the player down in a bed; returns false when sleeping is not possible now. */
  readonly requestSleep: (request: SleepRequest) => boolean;
  /** Opens the crafting surface for a station's recipe context. */
  readonly openCraftingStation: (context: CraftingContext) => boolean;
  /** Returns placed furniture to the inventory; false when it cannot be picked up now. */
  readonly pickUpFurniture: (placementId: string) => boolean;
  readonly onEquipWeaponSlot: (slotIndex: number) => void;
  readonly getAbilitySystem: () => PlayerAbilityController | undefined;
  readonly canUseAbilities: () => boolean;
  readonly onActivateAbility: (abilityId: PlayerAbilityId) => void;
  readonly getPlayer: () => Phaser.Physics.Arcade.Sprite | undefined;
  readonly uiRoot: HTMLElement;
}

export interface BossBattleAreas {
  readonly activation?: MapEnemyAreaPerimeter;
  readonly arena?: MapEnemyAreaPerimeter;
}

interface ManagedCamp {
  readonly script: BossCampScript;
  readonly owner: Node2D;
}

interface ManagedBoss {
  readonly campId: string;
  readonly bossId: string;
  readonly script: EnemyScript;
  readonly mount: MountedScene;
  defeatedNotified: boolean;
}

interface ManagedOrdinaryEnemy {
  readonly enemyId: number;
  readonly request: EnemySpawnRequest;
  readonly script: EnemyScript;
  readonly mount: MountedScene;
  defeatNotified: boolean;
  disposeAtMs?: number;
}

interface ManagedProjectile {
  readonly mount: MountedScene;
  readonly script: ProjectileScript;
}

interface ManagedEffect {
  readonly mount: MountedScene;
  readonly script: EffectScript;
  readonly attachment?: WorldEffectPositionAttachment;
}

interface ManagedWeapon {
  readonly mount: MountedScene;
  readonly script: WeaponScript;
}

interface ManagedResource {
  readonly owner: Node;
  readonly script: ResourceNodeScript;
}

interface ManagedCollectible {
  readonly owner: Node;
  readonly script: CollectibleScript;
}

const PLAYER_SILHOUETTE_COLOR = 0x73d7ff;
const HOSTILE_SILHOUETTE_COLOR = 0xff936d;

/** Enemy spawn-area types resolve to their character scene by convention: `character.<type>`. */
function enemySceneId(enemyType: string): string {
  return `character.${enemyType}`;
}

/** The boss scene's authored display name, or a readable fallback from its id. */
function bossDisplayName(script: EnemyScript, fallbackId: string): string {
  if (script.displayName) return script.displayName;
  return fallbackId.split(/[-_.]/).filter(Boolean).map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
}

/** Key-badge height above a chest's body origin. */
const CHEST_BADGE_RISE_PX = 56;

function isPassiveObjectScene(sceneIdValue: string): boolean {
  return sceneIdValue.startsWith('object.decoration-world-')
    || sceneIdValue.startsWith('object.house-world-solid')
    || sceneIdValue.startsWith('object.rock-world-wall-')
    || sceneIdValue.startsWith('object.wall-stone-solid')
    || sceneIdValue.startsWith('object.interior-');
}

export class UniversalSceneWorldController implements InteractionProvider {
  readonly runtime: PhaserUniversalSceneRuntime;
  readonly audioComposition: MountedScene;
  readonly audioServices: GlobalAudioServices;
  private readonly audioEvents: AudioEventBridge;
  private readonly activations = new AttackActivation();
  private readonly damageRouter = new DamageRouter(this.activations, () => this.simulationTimeMs);
  readonly chestUi: ChestInventorySurfacePort;
  private readonly bossHealthSurface: BossHealthSurfacePort;
  private readonly areaTitleSurface: AreaTitleSurfacePort;
  private readonly floatingTextSurface: FloatingTextSurfacePort;
  private readonly unregisterFloatingText: () => void;
  private readonly inputRouter: InputRouter;
  private readonly uiPresentation: HtmlControlPresentationAdapter;
  private readonly hudSurface: HudSurfacePort;
  private readonly weaponHotbarSurface: WeaponHotbarSurfacePort;
  private readonly abilityBarSurface: AbilityBarSurfacePort;
  private readonly playerHealthSurface: PlayerHealthSurfacePort;
  readonly inventorySurface: InventorySurfacePort;
  readonly craftingSurface: CraftingSurfacePort;
  readonly questJournalSurface: QuestJournalSurfacePort;
  readonly questOfferSurface: QuestOfferSurfacePort;
  readonly npcDialogueSurface: NpcDialogueSurfacePort;
  private readonly questTrackerSurface: QuestTrackerSurfacePort;
  readonly worldMapSurface: WorldMapSurfacePort;
  readonly levelUpSurface: LevelUpSurfacePort;
  readonly audioSettingsSurface: AudioSettingsSurfacePort;
  readonly minimapSurface: MinimapSurfacePort;
  private readonly camps = new Map<string, ManagedCamp>();
  private readonly bosses = new Map<string, ManagedBoss>();
  private readonly ordinaryEnemies = new Map<number, ManagedOrdinaryEnemy>();
  private readonly projectiles = new Map<number, ManagedProjectile>();
  private readonly effects = new Map<number, ManagedEffect>();
  private readonly resources = new Map<string, ManagedResource>();
  private readonly collectibles = new Map<string, ManagedCollectible>();
  private nextDropSequence = 0;
  private readonly passiveObjects = new Set<Node>();
  private readonly authoredRoots = new Set<Node2D>();
  private weapon?: ManagedWeapon;
  private readonly npcs = new Map<string, NpcScript>();
  private readonly npcNameTags: NpcNameTags;
  private readonly attackTelegraphs: AttackTelegraphs;
  private playerScript?: PlayerScript;
  private playerBody?: CharacterBody2DNode;
  private playerVisual?: Sprite2DNode;
  private playerPickupArea?: Area2DNode;
  private readonly chests = new Map<string, ChestScript>();
  private readonly doors = new Set<DoorScript>();
  private readonly beds = new Set<BedScript>();
  private readonly workbenches = new Set<WorkbenchScript>();
  /** Player-placed furniture mounted at runtime, keyed by placement id. */
  private readonly placedFurniture = new Map<string, { readonly record: PlacedFurnitureData; readonly mount: MountedScene; readonly scripts: readonly Node[] }>();
  /** Which placement an interactable script belongs to (absent for authored objects). */
  private readonly scriptPlacement = new Map<Node, string>();
  private readonly unregisterInteraction: () => void;
  private readonly unregisterDoorInteraction: () => void;
  private readonly unregisterBedInteraction: () => void;
  private readonly unregisterWorkbenchInteraction: () => void;
  private readonly unregisterFurnitureInteraction: () => void;
  private nextBossSequence = 1;
  private nextEnemySequence = 1;
  private nextProjectileSequence = 1;
  private nextEffectSequence = 1;
  private nextWeaponSequence = 1;
  private managedProjectileSpawnCountValue = 0;
  private simulationTimeMs = 0;
  private disposed = false;

  constructor(private readonly options: UniversalSceneWorldControllerOptions) {
    let inputSink: InputEventSink | undefined;
    this.audioServices = new GlobalAudioServices(options.scene.sound);
    this.npcNameTags = new NpcNameTags(options.scene);
    this.attackTelegraphs = new AttackTelegraphs(options.scene);
    this.hudSurface = new HudSurfacePort();
    this.weaponHotbarSurface = new WeaponHotbarSurfacePort(options.onEquipWeaponSlot);
    this.abilityBarSurface = new AbilityBarSurfacePort(options.getAbilitySystem, options.canUseAbilities, options.onActivateAbility);
    this.playerHealthSurface = new PlayerHealthSurfacePort(options.scene, options.getPlayer);
    this.chestUi = new ChestInventorySurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot, onPausedChange: options.setChestPaused,
      getContents: (instanceId) => this.chests.get(instanceId)?.remaining ?? {},
    });
    this.questJournalSurface = new QuestJournalSurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot, onPausedChange: options.setJournalPaused,
    });
    this.questOfferSurface = new QuestOfferSurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot, onPausedChange: options.setQuestOfferPaused,
    });
    this.questTrackerSurface = new QuestTrackerSurfacePort();
    this.npcDialogueSurface = new NpcDialogueSurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot, onPausedChange: options.setNpcDialoguePaused,
    });
    this.worldMapSurface = new WorldMapSurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot,
      getCurrentArea: options.getCurrentAreaId, onPausedChange: options.setWorldMapPaused,
    });
    this.audioSettingsSurface = new AudioSettingsSurfacePort({
      modalStack: options.modalStack, mixer: this.audioServices, load: loadAudioSettings, save: saveAudioSettings,
      defaults: DEFAULT_AUDIO_SETTINGS, onPausedChange: options.setAudioSettingsPaused,
    });
    this.levelUpSurface = new LevelUpSurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot, onPausedChange: options.setLevelUpPaused,
    });
    this.minimapSurface = new MinimapSurfacePort({ uiRoot: options.uiRoot, dimensions: options.worldDimensions });
    this.craftingSurface = new CraftingSurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot, service: craftingService,
      onPausedChange: options.setCraftingPaused, onCrafted: options.onCrafted,
    });
    this.inventorySurface = new InventorySurfacePort({
      modalStack: options.modalStack, uiRoot: options.uiRoot, onPausedChange: options.setInventoryPaused,
      onUseItem: options.onUseInventoryItem, onPlaceItem: options.onPlaceInventoryItem, onEquipWeapon: options.onEquipInventoryWeapon,
      onAssignWeapon: options.onAssignInventoryWeapon, canDropItem: options.canDropInventoryItem,
      onDropItem: options.onDropInventoryItem,
    });
    this.areaTitleSurface = new AreaTitleSurfacePort(options.scene);
    this.floatingTextSurface = new FloatingTextSurfacePort(options.scene, (surfaceId) => {
      this.runtime.mountScene(sceneId('ui.floating-text'), {
        runtimeNamespace: `ui-${surfaceId.replace(':', '-')}`,
        propertyOverrides: [{ nodeId: 'script', property: 'surfaceId', value: surfaceId }],
      });
    });
    this.bossHealthSurface = new BossHealthSurfacePort((campId, bossId) => {
      const boss = this.bosses.get(campId);
      if (!boss) return undefined;
      return {
        name: bossDisplayName(boss.script, bossId),
        hp: () => boss.script.hp,
        maxHp: () => boss.script.maxHealth,
      };
    });
    const ports = new Map<string, UiSurfacePort>([
      ['hud', this.hudSurface],
      ['weapon-hotbar', this.weaponHotbarSurface],
      ['ability-bar', this.abilityBarSurface],
      ['health-bar', this.playerHealthSurface],
      ['inventory-ui', this.inventorySurface],
      ['chest-inventory-panel', this.chestUi],
      ['crafting-ui', this.craftingSurface],
      ['quest-journal', this.questJournalSurface],
      ['quest-offer-modal', this.questOfferSurface],
      ['npc-dialogue', this.npcDialogueSurface],
      ['quest-tracker', this.questTrackerSurface],
      ['world-map-ui', this.worldMapSurface],
      ['level-up-modal', this.levelUpSurface],
      ['audio-settings', this.audioSettingsSurface],
      ['minimap', this.minimapSurface],
      ['boss-health-bar', this.bossHealthSurface],
      ['area-title-card', this.areaTitleSurface],
    ]);
    const portFor = (surfaceId: string): UiSurfacePort | undefined =>
      ports.get(surfaceId) ?? (surfaceId.startsWith('floating-text:') ? this.floatingTextSurface : undefined);
    const uiSurfaces: UiSurfacePort = {
      snapshot: (surfaceId) => portFor(surfaceId)?.snapshot(surfaceId) ?? {},
      subscribe: (surfaceId, listener) => portFor(surfaceId)?.subscribe?.(surfaceId, listener),
      invoke: (surfaceId, actionId, payload) => { portFor(surfaceId)?.invoke(surfaceId, actionId, payload); },
    };
    this.inputRouter = new InputRouter({
      sink: { enqueueInput: (event) => inputSink?.enqueueInput(event) },
      actions: PLAYER_INPUT_ACTIONS,
      isPaused: () => this.runtime.tree.paused,
    });
    this.uiPresentation = new HtmlControlPresentationAdapter({
      root: options.uiRoot,
      viewport: () => ({ width: options.uiRoot.clientWidth, height: options.uiRoot.clientHeight }),
      resolveAssetUrl: createUiAssetUrlResolver(options.scene),
    });
    const bossStatus = this.bossHealthSurface;
    const scripts = createGameScriptRegistry({
      [DAMAGE_ROUTER_SERVICE]: this.damageRouter,
      [ATTACK_ACTIVATION_SERVICE]: this.activations,
      [PLAYER_WEAPON_COMBAT_SERVICE]: {
        onAttackStarted: options.onManagedWeaponAttackStarted,
        onAttackFinished: options.onManagedWeaponAttackFinished,
        transformDamage: (damage: number, target: ManagedWeaponTarget) => options.transformManagedWeaponDamage(damage, {
          ...target,
          targetTags: this.managedTargetTags(target.receiverNodeId),
        }),
        onOutcome: (outcome: RoutedDamageOutcome, target: ManagedWeaponTarget) => options.onManagedWeaponOutcome(outcome, {
          ...target,
          targetTags: this.managedTargetTags(target.receiverNodeId),
        }),
        wielderReceiverNodeId: () => this.playerScript?.runtimeNodeId,
      },
      [PLAYER_HEALTH_SERVICE]: options.health,
      [ENEMY_TARGET_SERVICE]: {
        getPrimaryTarget: () => this.primaryEnemyTarget(),
        getNavigation: (sourceNodeId: string) => this.enemyNavigation(sourceNodeId),
        fireProjectile: (request: EnemyProjectileRequest) => this.spawnEnemyProjectile(request),
        spawnImpactEffect: (request: { readonly effectId: string; readonly x: number; readonly y: number }) => {
          this.spawnEffect({ effectId: request.effectId, direction: 'right', x: request.x, y: request.y });
        },
        showDamageNumber: (request: EnemyDamageNumberRequest) => this.showEnemyDamageNumber(request),
        showTelegraph: (request: EnemyTelegraphRequest) => this.attackTelegraphs.show(request),
        clearTelegraph: (sourceNodeId: string) => this.attackTelegraphs.clear(sourceNodeId),
        shakeCamera: (request: { readonly durationMs: number; readonly intensity: number }) => options.scene.cameras.main.shake(request.durationMs, request.intensity),
      },
      [NPC_RUNTIME_SERVICE]: {
        acquire: (request: NpcRuntimeRequest) => this.acquireNpcAgent(request),
      },
      [BOSS_CAMP_PROGRESS_SERVICE]: {
        getRespawnReadyAt: (mapId: string, campId: string) => options.progress.bossCampRespawnReadyAt(mapId, campId),
        setRespawnReadyAt: (mapId: string, campId: string, epochMs: number | undefined) => options.progress.setBossCampRespawnReadyAt(mapId, campId, epochMs),
        markBossDefeated: (bossId: string) => {
          options.progress.defeatBoss(bossId);
          gameEvents.emit('boss.defeated', { bossId });
        },
      },
      [BOSS_SCENE_SPAWNER_SERVICE]: {
        spawnBoss: (request: BossSceneSpawnRequest) => this.spawnBoss(request),
        removeBoss: (campId: string) => this.removeBoss(campId),
      },
      [BOSS_UI_SERVICE]: bossStatus,
      [CHEST_WORLD_SERVICE]: {
        ensureInitialized: (mapId: string, instanceId: string, contents: Readonly<Record<string, number>>) => { options.progress.ensureChestInitialized(mapId, instanceId, contents); },
        getRemaining: (mapId: string, instanceId: string) => options.progress.chestState(mapId, instanceId)?.remaining ?? {},
        transferStack: (mapId: string, instanceId: string, itemId: string) => options.transaction.transferChestStack(mapId, instanceId, itemId),
      },
      [CHEST_GUARD_SERVICE]: { isLocked: (instanceId: string) => this.isChestLocked(instanceId) },
      [CHEST_VIEW_SERVICE]: this.chestUi,
      [WORLD_OBJECT_STATE_SERVICE]: {
        load: (mapId: string, instanceId: string) => {
          const state = options.progress.resourceState(mapId, instanceId);
          return state ? { health: state.value, destroyed: state.stage !== 'node' } : undefined;
        },
        saveHealth: (mapId: string, instanceId: string, health: number) => {
          options.progress.setResourceState(mapId, instanceId, { stage: 'node', value: health });
        },
        markDestroyed: (mapId: string, instanceId: string) => {
          options.progress.setResourceState(mapId, instanceId, { stage: 'depleted', value: 0 });
        },
      } satisfies WorldObjectStatePort,
      [RESOURCE_NODE_SERVICE]: {
        publishHit: (request: ResourceHitFeedbackRequest) => this.publishResourceHit(request),
        publishHarvestBlocked: (request: ResourceHarvestBlocked) => {
          options.showMessage(request.x, request.y - 58, request.message, 'cyan', true);
        },
        spawnDrops: (request: ResourceDropRequest) => options.spawnManagedResourceDrops(request),
      },
      [COLLECTIBLE_WORLD_SERVICE]: {
        ensureInitialized: (mapId: string, instanceId: string, quantity: number) => options.collectibles.ensureInitialized(mapId, instanceId, quantity),
        remaining: (mapId: string, instanceId: string) => options.collectibles.remaining(mapId, instanceId),
        pickup: (request: CollectiblePickupRequest) => this.pickupCollectible(request),
      } satisfies CollectibleWorldPort,
      [WORLD_EXIT_SERVICE]: {
        requestExit: (request: WorldExitRequest) => {
          if (!this.playerBody || request.actorNodeId !== this.playerBody.runtimeId) {
            return { status: 'ignored' };
          }
          return options.requestExit(request);
        },
      } satisfies WorldExitPort,
      [UI_SURFACE_SERVICE]: uiSurfaces,
    });
    let mountedRuntime: PhaserUniversalSceneRuntime | undefined;
    let audioEvents: AudioEventBridge | undefined;
    try {
      mountedRuntime = this.runtime = new PhaserUniversalSceneRuntime({
        scene: options.scene,
        content: options.content,
        descriptors: createGameDescriptorRegistry(),
        scripts,
        nodeServices: {
          inputRouter: this.inputRouter,
          controlPresentation: this.uiPresentation,
          audioPreferences: this.audioServices,
          audioUnlock: this.audioServices,
        },
        resolveAssetKey: (assetId) => ASSET_MANIFEST.assets[assetId as AssetId].runtime.textureKey,
        diagnosticSink: (diagnostic) => {
          console.error(`[UniversalScene:${diagnostic.phase}] ${diagnostic.message}`, diagnostic.error ?? '');
        },
        lifecycle: {
          beforeFixedStep: (deltaSeconds) => {
            this.simulationTimeMs += deltaSeconds * 1000;
            options.updateGameplay(deltaSeconds * 1000);
            this.evaluateCamps();
          },
          afterFixedStep: () => {
            this.finishDefeatedBosses();
            this.finishDefeatedOrdinaryEnemies();
            this.finishExpiredProjectiles();
            this.finishExpiredEffects();
            this.finishDestroyedResources();
            this.finishDepletedCollectibles();
          },
          beforePresentation: (deltaSeconds) => {
            options.updatePresentation(deltaSeconds * 1000);
            for (const effect of this.effects.values()) effect.attachment?.update();
          },
          afterPresentation: () => this.npcNameTags.update(),
        },
      });
      inputSink = this.runtime;
      this.audioComposition = this.runtime.mountScene(sceneId('audio.global'), { runtimeNamespace: 'audio-global' });
      audioEvents = this.audioEvents = new AudioEventBridge(createGlobalAudioCuePort(this.audioComposition.root), gameEvents, options.modalStack);
      this.runtime.mountScene(sceneId('ui.hud'), { runtimeNamespace: 'ui-hud' });
      this.runtime.mountScene(sceneId('ui.weapon-hotbar'), { runtimeNamespace: 'ui-weapon-hotbar' });
      this.runtime.mountScene(sceneId('ui.ability-bar'), { runtimeNamespace: 'ui-ability-bar' });
      this.runtime.mountScene(sceneId('ui.health-bar'), { runtimeNamespace: 'ui-health-bar' });
      this.runtime.mountScene(sceneId('ui.boss-health-bar'), { runtimeNamespace: 'ui-boss-health-bar' });
      this.runtime.mountScene(sceneId('ui.area-title-card'), { runtimeNamespace: 'ui-area-title-card' });
      this.runtime.mountScene(sceneId('ui.inventory-ui'), { runtimeNamespace: 'ui-inventory-ui' });
      this.runtime.mountScene(sceneId('ui.chest-inventory-panel'), { runtimeNamespace: 'ui-chest-inventory-panel' });
      this.runtime.mountScene(sceneId('ui.crafting-ui'), { runtimeNamespace: 'ui-crafting-ui' });
      this.runtime.mountScene(sceneId('ui.quest-journal'), { runtimeNamespace: 'ui-quest-journal' });
      this.runtime.mountScene(sceneId('ui.quest-offer-modal'), { runtimeNamespace: 'ui-quest-offer-modal' });
      this.runtime.mountScene(sceneId('ui.npc-dialogue'), { runtimeNamespace: 'ui-npc-dialogue' });
      this.runtime.mountScene(sceneId('ui.quest-tracker'), { runtimeNamespace: 'ui-quest-tracker' });
      this.runtime.mountScene(sceneId('ui.world-map-ui'), { runtimeNamespace: 'ui-world-map-ui' });
      this.runtime.mountScene(sceneId('ui.level-up-modal'), { runtimeNamespace: 'ui-level-up-modal' });
      this.runtime.mountScene(sceneId('ui.audio-settings'), { runtimeNamespace: 'ui-audio-settings' });
      this.runtime.mountScene(sceneId('ui.minimap'), { runtimeNamespace: 'ui-minimap' });
    } catch (error) {
      mountedRuntime?.shutdown();
      audioEvents?.dispose();
      this.audioServices.destroy();
      this.inputRouter.destroy();
      this.hudSurface.destroy();
      this.weaponHotbarSurface.destroy();
      this.abilityBarSurface.destroy();
      this.playerHealthSurface.destroy();
      this.bossHealthSurface.destroy();
      this.areaTitleSurface.destroy();
      this.floatingTextSurface.destroy();
      this.inventorySurface.destroy();
      this.chestUi.destroy();
      this.craftingSurface.destroy();
      this.questJournalSurface.destroy();
      this.questOfferSurface.destroy();
      this.npcDialogueSurface.destroy();
      this.questTrackerSurface.destroy();
      this.worldMapSurface.destroy();
      this.levelUpSurface.destroy();
      this.audioSettingsSurface.destroy();
      this.minimapSurface.destroy();
      throw error;
    }

    this.mountPlayer();
    this.mountAuthoredWorld();
    this.unregisterInteraction = options.interactions.register('managed-chests', this);
    this.unregisterDoorInteraction = options.interactions.register('world-doors', { getCandidate: () => this.doorCandidate() });
    this.unregisterBedInteraction = options.interactions.register('world-beds', { getCandidate: () => this.bedCandidate() });
    this.unregisterWorkbenchInteraction = options.interactions.register('world-workbenches', { getCandidate: () => this.workbenchCandidate() });
    this.unregisterFurnitureInteraction = options.interactions.register('placed-furniture', { getCandidate: () => this.furnitureCandidate() });
    this.unregisterFloatingText = floatingText.registerPresentation(options.scene, this.floatingTextSurface);
  }

  advanceFrame(deltaSeconds: number): number { return this.runtime.advanceFrame(deltaSeconds); }
  /** Gameplay clock: advances only with fixed simulation steps, so it stands still while paused. */
  get simulationTime(): number { return this.simulationTimeMs; }
  flashPlayerHealthBar(): void { this.playerHealthSurface.flash(); }
  showAreaTitle(title: string, color: string): void { this.areaTitleSurface.show(title, color); }
  setNpcQuestMarker(instanceId: string, marker: NpcQuestMarker | undefined): void { this.npcNameTags.setMarker(instanceId, marker); }
  setPaused(paused: boolean): void {
    if (paused) this.playerScript?.clearInput();
    this.runtime.setPaused(paused);
  }
  get managedOrdinaryEnemyCount(): number { return this.ordinaryEnemies.size; }
  get managedBossCount(): number { return this.bosses.size; }
  get managedCampCount(): number { return this.camps.size; }
  get managedChestCount(): number { return this.chests.size; }
  get managedNpcCount(): number { return this.npcs.size; }
  get managedPlayerCount(): number { return this.playerScript ? 1 : 0; }
  get managedProjectileCount(): number { return this.projectiles.size; }
  get managedProjectileSpawnCount(): number { return this.managedProjectileSpawnCountValue; }
  get managedEffectCount(): number { return this.effects.size; }
  get managedResourceCount(): number { return this.resources.size; }
  get managedCollectibleCount(): number { return this.collectibles.size; }
  get managedPassiveObjectCount(): number { return this.passiveObjects.size; }
  get managedWeaponId(): string | null { return this.weapon?.script.weaponId ?? null; }
  get managedWeaponAttacking(): boolean { return this.weapon?.script.attacking ?? false; }
  get managedPlayer(): PlayerScript {
    if (!this.playerScript) throw new Error('The authored player scene is not mounted.');
    return this.playerScript;
  }
  playerAnimationDurationMs(animationId: string): number | undefined {
    const library = this.options.content.resourceForScene(sceneId('character.player-slime'), resourceId('character.player.slime.animations'));
    if (library?.kind !== 'animation-library') return undefined;
    const clip = library.animations[animationId];
    if (!clip || typeof clip !== 'object' || Array.isArray(clip)) return undefined;
    const duration = (clip as Readonly<Record<string, unknown>>).durationSeconds;
    return typeof duration === 'number' && Number.isFinite(duration) && duration > 0
      ? Math.max(1, Math.round(duration * 1000))
      : undefined;
  }
  get playerPhysicsSprite(): Phaser.Physics.Arcade.Sprite {
    if (!this.playerBody) throw new Error('The authored player body is not mounted.');
    return this.playerBody.physicsSprite;
  }
  /** Every rendered sprite in the runtime tree, for the dev overlay. */
  get worldVisuals(): readonly Sprite2DNode[] {
    return descendants(this.runtime.root, Sprite2DNode).filter((visual) => visual.phaserObjectActive);
  }

  get playerPresentation(): Sprite2DNode {
    if (!this.playerVisual) throw new Error('The authored player visual is not mounted.');
    return this.playerVisual;
  }
  /** World-space activation and arena perimeters of every mounted boss camp. */
  get bossBattleAreas(): readonly BossBattleAreas[] {
    return [...this.camps.values()].map(({ script }) => ({
      activation: script.activationPerimeter,
      arena: script.arenaPerimeter,
    }));
  }

  /** Authored attack areas of every live enemy, for the dev overlay. */
  get enemyAttackAreas(): readonly EnemyDebugAttackArea[] {
    return descendants(this.runtime.root, EnemyScript).flatMap((script) => script.debugAttackAreas());
  }

  get managedLiveCampCount(): number { return [...this.camps.values()].filter((camp) => camp.script.hasLiveBoss).length; }

  flashHudCoins(): void {
    const coins = this.options.uiRoot.querySelector<HTMLElement>('.game-ui--hud [aria-label="Coins"]');
    coins?.animate(
      [{ transform: 'scale(1)' }, { transform: 'scale(1.08)' }, { transform: 'scale(1)' }],
      { duration: 240, easing: 'ease-out' },
    );
  }

  getCandidate() {
    let nearest: { readonly script: ChestScript; readonly position: Readonly<{ x: number; y: number }> } | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const script of this.chests.values()) {
      this.syncChestFrame(script);
      const parent = script.get_parent() as Node2D | undefined;
      if (!parent) continue;
      const position = parent.get_global_transform().position;
      const player = this.managedPlayer.getPosition();
      const distance = Phaser.Math.Distance.Between(player.x, player.y, position.x, position.y);
      if (distance <= 112 && distance < nearestDistance) { nearest = { script, position }; nearestDistance = distance; }
    }
    if (!nearest) return undefined;
    const locked = !nearest.script.empty && this.isChestLocked(nearest.script.instanceId);
    return {
      id: `managed-chests:${nearest.script.instanceId}`,
      prompt: locked ? '[F] Chest locked by Fatty One Eye' : nearest.script.empty ? '[F] Inspect empty chest' : '[F] Open chest',
      priority: 80,
      anchor: () => ({ x: nearest!.position.x, y: nearest!.position.y - CHEST_BADGE_RISE_PX }),
      execute: () => {
        const result = nearest!.script.requestOpen();
        if (result === 'guarded') this.options.showMessage(nearest!.position.x, nearest!.position.y - 48, 'Fatty One Eye is guarding this chest!', 'white', true);
        return true;
      },
    };
  }

  private doorCandidate() {
    if (!this.playerBody) return undefined;
    const player = this.managedPlayer.getPosition();
    let nearest: DoorScript | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const door of this.doors) {
      const parent = door.get_parent() as Node2D | undefined;
      if (!parent) continue;
      const position = parent.get_global_transform().position;
      const distance = Phaser.Math.Distance.Between(player.x, player.y, position.x, position.y);
      if (distance <= door.interactRadius && distance < nearestDistance) { nearest = door; nearestDistance = distance; }
    }
    if (!nearest) return undefined;
    const door = nearest;
    const actorNodeId = this.playerBody.runtimeId;
    return {
      id: `world-doors:${door.doorId}`,
      prompt: `[F] ${door.prompt}`,
      priority: 90,
      anchor: () => {
        const position = (door.get_parent() as Node2D).get_global_transform().position;
        return { x: position.x, y: position.y - door.badgeRise };
      },
      execute: () => {
        const result = this.options.requestExit({
          mapId: door.mapId,
          exitId: door.doorId,
          targetAreaId: door.targetAreaId,
          entry: door.entry,
          actorNodeId,
          gate: {},
        });
        return result.status === 'queued';
      },
    };
  }

  /** G on placed furniture puts it back in the inventory. */
  private pickUpAction(script: Node) {
    const placementId = this.scriptPlacement.get(script);
    if (!placementId) return undefined;
    return { prompt: '[G] Pick up', execute: () => this.options.pickUpFurniture(placementId) };
  }

  private workbenchCandidate() {
    if (!this.playerBody) return undefined;
    const player = this.managedPlayer.getPosition();
    let nearest: { readonly bench: WorkbenchScript; readonly origin: Readonly<{ x: number; y: number }> } | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const bench of this.workbenches) {
      const parent = bench.get_parent() as Node2D | undefined;
      if (!parent) continue;
      const origin = parent.get_global_transform().position;
      const distance = Phaser.Math.Distance.Between(player.x, player.y, origin.x, origin.y);
      if (distance <= bench.interactRadius && distance < nearestDistance) { nearest = { bench, origin }; nearestDistance = distance; }
    }
    if (!nearest) return undefined;
    const { bench, origin } = nearest;
    const secondary = this.pickUpAction(bench);
    return {
      id: `world-workbenches:${bench.runtimeId}`,
      prompt: `[F] ${bench.prompt}`,
      priority: 88,
      anchor: () => ({ x: origin.x, y: origin.y - bench.badgeRise }),
      ...(secondary ? { secondary } : {}),
      execute: () => this.options.openCraftingStation(bench.recipeContext),
    };
  }

  /** Placed furniture without its own interaction can still be picked up (G or F). */
  private furnitureCandidate() {
    if (!this.playerBody) return undefined;
    const player = this.managedPlayer.getPosition();
    let nearest: { readonly placementId: string; readonly x: number; readonly y: number } | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const [placementId, placed] of this.placedFurniture) {
      if (placed.scripts.length > 0) continue;
      const distance = Phaser.Math.Distance.Between(player.x, player.y, placed.record.x, placed.record.y);
      if (distance <= 90 && distance < nearestDistance) { nearest = { placementId, x: placed.record.x, y: placed.record.y }; nearestDistance = distance; }
    }
    if (!nearest) return undefined;
    const { placementId, x, y } = nearest;
    const execute = () => this.options.pickUpFurniture(placementId);
    return {
      id: `placed-furniture:${placementId}`,
      prompt: '[F] Pick up',
      priority: 40,
      anchor: () => ({ x, y: y - 72 }),
      execute,
    };
  }

  private bedCandidate() {
    if (!this.playerBody) return undefined;
    const player = this.managedPlayer.getPosition();
    let nearest: { readonly bed: BedScript; readonly origin: Readonly<{ x: number; y: number }> } | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const bed of this.beds) {
      const parent = bed.get_parent() as Node2D | undefined;
      if (!parent) continue;
      const origin = parent.get_global_transform().position;
      const distance = Phaser.Math.Distance.Between(player.x, player.y, origin.x, origin.y);
      if (distance <= bed.interactRadius && distance < nearestDistance) { nearest = { bed, origin }; nearestDistance = distance; }
    }
    if (!nearest) return undefined;
    const { bed, origin } = nearest;
    return {
      id: `world-beds:${bed.runtimeId}`,
      prompt: `[F] ${bed.prompt}`,
      priority: 85,
      anchor: () => ({ x: origin.x, y: origin.y - bed.badgeRise }),
      ...(this.pickUpAction(bed) ? { secondary: this.pickUpAction(bed)! } : {}),
      execute: () => this.options.requestSleep({
        sleepPoint: { x: origin.x + bed.sleepPoint.x, y: origin.y + bed.sleepPoint.y },
        wakePoint: { x: origin.x + bed.wakePoint.x, y: origin.y + bed.wakePoint.y },
      }),
    };
  }

  isChestLocked(instanceId: string): boolean {
    return [...this.camps.values()].some((camp) => camp.script.isChestGuarded(instanceId));
  }

  resetActiveFights(): void {
    for (const camp of this.camps.values()) camp.script.resetActiveFight();
  }

  createManagedEnemy(request: EnemySpawnRequest): EnemyPopulationMember | null | undefined {
    const authoredSceneId = enemySceneId(request.config.id);
    if (!this.options.content.catalog.has(sceneId(authoredSceneId))) return undefined;
    const enemyId = this.nextEnemySequence++;
    const mount = this.runtime.mountScene(sceneId(authoredSceneId), {
      runtimeNamespace: `managed-enemy-${enemyId}`,
      position: { x: request.x, y: request.y },
    });
    const script = descendants(mount.root, EnemyScript)[0];
    if (!script) {
      mount.dispose();
      return null;
    }
    const record: ManagedOrdinaryEnemy = { enemyId, request, script, mount, defeatNotified: false };
    this.ordinaryEnemies.set(enemyId, record);
    this.registerCharacterOcclusion(mount.root, HOSTILE_SILHOUETTE_COLOR, () => !script.defeated);
    const controller = this;
    return {
      config: request.config,
      get active() { return !mount.disposed; },
      get dead() { return script.defeated; },
      get x() { return script.worldPosition.x; },
      get y() { return script.worldPosition.y; },
      destroy() { controller.removeOrdinaryEnemy(enemyId); },
    };
  }

  spawnWorldDrop(request: WorldDropRequest): void {
    const points = request.mode === 'launch' ? [request.source, request.destination] : [request.destination];
    if (points.some((point) => !Number.isFinite(point.x) || !Number.isFinite(point.y))) {
      throw new Error('World drop requires finite coordinates');
    }
    if (request.mode === 'launch' && (!Number.isSafeInteger(request.launchIndex) || request.launchIndex < 0)) {
      throw new Error('World drop launch order must be a zero-based non-negative integer');
    }
    const objectId = request.drop.objectId;
    const initial = request.drop.initialState ?? {};
    const remaining = initial.remaining;
    if (remaining !== undefined && (!Number.isSafeInteger(remaining) || (remaining as number) <= 0)) {
      throw new Error(`World drop '${request.drop.instanceId}' requires a positive remaining quantity`);
    }
    if (this.collectibles.has(request.drop.instanceId)) {
      throw new Error(`Collectible '${request.drop.instanceId}' is already mounted`);
    }
    const position = request.mode === 'launch' ? request.source : request.destination;
    const mount = this.runtime.mountScene(sceneId(`object.${objectId.replaceAll('.', '-')}`), {
      runtimeNamespace: `managed-drop-${++this.nextDropSequence}`,
      position,
      propertyOverrides: [
        { nodeId: 'script', property: 'mapId', value: this.options.map.mapId },
        { nodeId: 'script', property: 'instanceId', value: request.drop.instanceId },
        ...(remaining === undefined ? [] : [{ nodeId: 'script', property: 'quantity', value: remaining as number }]),
        ...(typeof initial.sourceResourceInstanceId === 'string'
          ? [{ nodeId: 'script', property: 'sourceResourceInstanceId', value: initial.sourceResourceInstanceId }]
          : []),
        ...(typeof initial.sourceInventoryDropId === 'string'
          ? [{ nodeId: 'script', property: 'sourceInventoryDropId', value: initial.sourceInventoryDropId }]
          : []),
      ],
    });
    const script = descendants(mount.root, CollectibleScript)[0];
    const area = descendants(mount.root, Area2DNode).find((node) => node.name === 'PickupArea');
    if (!script || !area || script.objectId !== objectId) {
      mount.dispose();
      throw new Error(`Collectible scene for '${objectId}' is incomplete`);
    }
    this.collectibles.set(request.drop.instanceId, { owner: mount.mount, script });
    if (request.mode === 'launch') {
      area.monitorable = false;
      this.animateWorldDrop(mount, area, request);
    }
  }

  collectibleQuantity(objectId: string): number {
    const document = this.options.content.catalog.get(sceneId(`object.${objectId.replaceAll('.', '-')}`));
    const script = document?.nodes.find((node) => node.scriptId === 'game.collectible');
    const quantity = script?.properties.quantity;
    if (!Number.isSafeInteger(quantity) || (quantity as number) <= 0) {
      throw new Error(`Collectible scene for '${objectId}' requires a positive authored quantity`);
    }
    return quantity as number;
  }

  private animateWorldDrop(mount: MountedScene, area: Area2DNode, request: Extract<WorldDropRequest, { mode: 'launch' }>): void {
    const visual = descendants(mount.root, Sprite2DNode)[0];
    const tweens = new Set<Phaser.Tweens.Tween>();
    mount.mount.lifetimeDisposables.add(() => { for (const tween of tweens) tween.remove(); tweens.clear(); });
    const active = () => !mount.disposed;
    const finish = () => {
      if (!active()) return;
      mount.mount.position = request.destination;
      if (visual) { visual.effects.scaleX = 1; visual.effects.scaleY = 1; }
      area.monitorable = true;
    };
    const add = (state: { progress: number }, duration: number, delay: number, ease: string, update: () => void, complete: () => void) => {
      try {
        let tween: Phaser.Tweens.Tween | undefined;
        tween = this.options.scene.tweens.add({
          targets: state, progress: 1, duration, delay, ease,
          onUpdate: () => { if (active()) update(); },
          onComplete: () => { if (tween) tweens.delete(tween); if (active()) complete(); },
        });
        if (active()) tweens.add(tween);
        else tween.remove();
      } catch { finish(); }
    };
    const flight = { progress: 0 };
    add(flight, WORLD_DROP_FLIGHT_MS, request.launchIndex * WORLD_DROP_STAGGER_MS, 'Linear', () => {
      mount.mount.position = resolveWorldDropTrajectory(request.source, request.destination, flight.progress);
    }, () => {
      mount.mount.position = request.destination;
      if (visual) { visual.effects.scaleX = 1.12; visual.effects.scaleY = 0.82; }
      const rebound = { progress: 0 };
      add(rebound, WORLD_DROP_REBOUND_MS, 0, 'Sine.Out', () => {
        mount.mount.position = { x: request.destination.x, y: request.destination.y - WORLD_DROP_REBOUND_HEIGHT * rebound.progress };
        if (visual) {
          visual.effects.scaleX = 1.12 - 0.16 * rebound.progress;
          visual.effects.scaleY = 0.82 + 0.22 * rebound.progress;
        }
      }, () => {
        const settle = { progress: 0 };
        add(settle, WORLD_DROP_SETTLE_MS, 0, 'Sine.In', () => {
          mount.mount.position = { x: request.destination.x, y: request.destination.y - WORLD_DROP_REBOUND_HEIGHT * (1 - settle.progress) };
          if (visual) {
            visual.effects.scaleX = 0.96 + 0.04 * settle.progress;
            visual.effects.scaleY = 1.04 - 0.04 * settle.progress;
          }
        }, finish);
      });
    });
  }

  isAuthoredCellOccupied(cellX: number, cellY: number, sourceInstanceId: string, tileSize: number): boolean {
    for (const root of this.authoredRoots) {
      if (!root.is_inside_tree() || root.is_freed()) continue;
      const instanceId = root.authoredInstanceProvenance?.authoredInstanceId;
      if (!instanceId || instanceId === sourceInstanceId) continue;
      const position = root.get_global_transform().position;
      if (Math.floor(position.x / tileSize) === cellX && Math.floor((position.y - 1) / tileSize) === cellY) return true;
    }
    return false;
  }

  isManagedCollectibleCellOccupied(cellX: number, cellY: number, tileSize: number): boolean {
    for (const collectible of this.collectibles.values()) {
      if (!(collectible.owner instanceof Node2D)
        || !collectible.owner.is_inside_tree()
        || collectible.owner.is_freed()
        || collectible.script.remaining <= 0) continue;
      const position = collectible.owner.get_global_transform().position;
      if (Math.floor(position.x / tileSize) === cellX && Math.floor((position.y - 1) / tileSize) === cellY) return true;
    }
    return false;
  }

  spawnEffect(request: WorldEffectSpawnRequest): boolean {
    const sequence = this.nextEffectSequence++;
    const mount = this.runtime.mountScene(sceneId(`effect.${request.effectId}`), {
      runtimeNamespace: `managed-effect-${sequence}`,
      position: { x: request.x, y: request.y },
    });
    const script = descendants(mount.root, EffectScript)[0];
    if (!script) {
      mount.dispose();
      throw new Error(`Effect scene '${request.effectId}' requires EffectScript.`);
    }
    // The effect root is the depth source of its relative-depth layers; an
    // explicit request depth replaces its world-sorted base depth.
    const depthSource = mount.root instanceof Node2D ? mount.root : mount.mount;
    if (request.depth !== undefined) depthSource.depthOverride = request.depth;
    const attachment = request.followPositionOf
      ? new WorldEffectPositionAttachment(
          {
            setPosition: (x, y) => { mount.mount.position = { x, y }; },
            setDepth: (depth) => { if (request.depth !== undefined) depthSource.depthOverride = depth; },
          },
          request.followPositionOf,
          Phaser.GameObjects.Events.DESTROY,
          request.x,
          request.y,
          request.depth ?? Number.NaN,
          request.followDepthOffset ?? 0,
          (target) => resolvePhysicsPresentationPosition(
            this.options.scene,
            target as unknown as PhysicsPresentationTarget,
          ),
        )
      : undefined;
    this.effects.set(sequence, { mount, script, ...(attachment ? { attachment } : {}) });
    script.play(request.direction);
    return true;
  }

  mountWeapon(weaponId: string): boolean {
    const playerBody = this.playerBody;
    if (!playerBody) return false;
    let mount: MountedScene;
    try {
      mount = this.runtime.mountScene(sceneId(`weapon.${weaponId}`), {
        runtimeNamespace: `managed-player-weapon-${this.nextWeaponSequence++}`,
      });
    } catch {
      return false;
    }
    const script = descendants(mount.root, WeaponScript)[0];
    if (!script || script.weaponId !== weaponId) {
      mount.dispose();
      return false;
    }
    mount.mount.reparent(playerBody);
    this.runtime.tree.flushMutations();
    mount.mount.position = { x: 0, y: 0 };
    const previous = this.weapon;
    this.weapon = { mount, script };
    previous?.mount.dispose();
    return true;
  }

  playWeaponAttack(direction: WeaponAttackDirection, damage: WeaponDamagePayload): boolean {
    return this.weapon?.script.tryBeginAttack(direction, damage) ?? false;
  }

  canWeaponAttack(): boolean {
    return this.weapon?.script.canBeginAttack() ?? false;
  }

  clearWeapon(): void {
    this.weapon?.mount.dispose();
    this.weapon = undefined;
  }

  destroy(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unregisterInteraction();
    this.unregisterDoorInteraction();
    this.unregisterBedInteraction();
    this.unregisterWorkbenchInteraction();
    this.unregisterFurnitureInteraction();
    this.unregisterFloatingText();
    this.inputRouter.destroy();
    this.runtime.shutdown();
    this.npcNameTags.destroy();
    this.attackTelegraphs.destroy();
    this.audioEvents.dispose();
    this.audioServices.destroy();
    this.hudSurface.destroy();
    this.weaponHotbarSurface.destroy();
    this.abilityBarSurface.destroy();
    this.playerHealthSurface.destroy();
    this.bossHealthSurface.destroy();
    this.areaTitleSurface.destroy();
    this.floatingTextSurface.destroy();
    this.inventorySurface.destroy();
    this.chestUi.destroy();
    this.craftingSurface.destroy();
    this.questJournalSurface.destroy();
    this.questOfferSurface.destroy();
    this.npcDialogueSurface.destroy();
    this.questTrackerSurface.destroy();
    this.worldMapSurface.destroy();
    this.levelUpSurface.destroy();
    this.audioSettingsSurface.destroy();
    this.minimapSurface.destroy();
    this.camps.clear();
    this.bosses.clear();
    this.ordinaryEnemies.clear();
    this.projectiles.clear();
    for (const effect of this.effects.values()) effect.attachment?.dispose();
    this.effects.clear();
    this.resources.clear();
    this.collectibles.clear();
    this.passiveObjects.clear();
    this.authoredRoots.clear();
    this.weapon = undefined;
    this.npcs.clear();
    this.playerScript = undefined;
    this.playerBody = undefined;
    this.playerVisual = undefined;
    this.playerPickupArea = undefined;
    this.chests.clear();
    this.doors.clear();
    this.beds.clear();
    this.workbenches.clear();
    this.placedFurniture.clear();
    this.scriptPlacement.clear();
  }

  private mountAuthoredWorld(): void {
    const mount = this.runtime.mountScene(this.options.worldSceneId, {
      runtimeNamespace: `managed-world-${this.options.map.mapId}`,
    });
    for (const visual of descendants(mount.root, Sprite2DNode)) {
      if (!visual.occlusionBounds || !this.options.registerOccluder) continue;
      const registration = this.options.registerOccluder({
        id: visual.runtimeId,
        owner: visual.presentationObject,
        sourceFrame: visual.getRenderState().sourceFrame,
        bounds: visual.occlusionBounds,
        getDepth: () => visual.presentationObject.depth,
      });
      visual.lifetimeDisposables.add(() => registration.dispose());
    }

    for (const script of descendants(mount.root, ResourceNodeScript)) {
      const owner = authoredInstanceOwner(script);
      const drop = script.dropDefinition;
      if (!drop) throw new Error(`Resource '${script.instanceId}' requires an authored drop definition.`);
      this.options.registerManagedResource({
        instanceId: script.instanceId,
        dropObjectId: drop.objectId,
        dropVisualId: drop.visualId,
      });
      if (script.destroyed) owner.queue_free();
      else this.resources.set(script.instanceId, { owner, script });
    }
    for (const script of descendants(mount.root, CollectibleScript)) {
      const owner = authoredInstanceOwner(script);
      if (script.remaining <= 0) owner.queue_free();
      else this.collectibles.set(script.instanceId, { owner, script });
    }
    for (const script of descendants(mount.root, NpcScript)) this.registerNpcPlacement(script);
    for (const script of descendants(mount.root, ChestScript)) this.chests.set(script.instanceId, script);
    this.registerInteractables(mount.root);
    for (const script of descendants(mount.root, BossCampScript)) {
      const owner = authoredInstanceOwner(script);
      if (owner instanceof Node2D) this.camps.set(script.campId, { script, owner });
    }
    for (const node of directAuthoredInstanceRoots(mount.root)) {
      if (node instanceof Node2D) this.authoredRoots.add(node);
      if (isPassiveObjectScene(node.authoredInstanceProvenance?.sourceSceneId ?? '')) this.passiveObjects.add(node);
    }
    for (const record of this.options.progress.placedFurniture(this.options.map.mapId)) this.mountPlacedFurniture(record);
    this.runtime.tree.flushMutations();
  }

  /** Doors, beds, and stations inside a mounted subtree become interaction candidates. */
  private registerInteractables(root: Node, placementId?: string): Node[] {
    const scripts: Node[] = [
      ...descendants(root, DoorScript),
      ...descendants(root, BedScript),
      ...descendants(root, WorkbenchScript),
    ];
    for (const script of scripts) {
      if (script instanceof DoorScript) this.doors.add(script);
      else if (script instanceof BedScript) this.beds.add(script);
      else if (script instanceof WorkbenchScript) this.workbenches.add(script);
      if (placementId) this.scriptPlacement.set(script, placementId);
    }
    return scripts;
  }

  /** Mounts one player-placed furniture record; false if its scene is unavailable. */
  mountPlacedFurniture(record: PlacedFurnitureData): boolean {
    if (this.placedFurniture.has(record.id)) return true;
    let mount: MountedScene;
    try {
      mount = this.runtime.mountScene(sceneId(record.sceneId), {
        runtimeNamespace: `placed-furniture-${record.id}`,
        position: { x: record.x, y: record.y },
      });
    } catch (error) {
      console.error(`Placed furniture '${record.id}' (${record.sceneId}) could not be mounted`, error);
      return false;
    }
    const scripts = this.registerInteractables(mount.root, record.id);
    this.placedFurniture.set(record.id, { record, mount, scripts });
    this.runtime.tree.flushMutations();
    return true;
  }

  unmountPlacedFurniture(placementId: string): void {
    const placed = this.placedFurniture.get(placementId);
    if (!placed) return;
    for (const script of placed.scripts) {
      this.doors.delete(script as DoorScript);
      this.beds.delete(script as BedScript);
      this.workbenches.delete(script as WorkbenchScript);
      this.scriptPlacement.delete(script);
    }
    this.placedFurniture.delete(placementId);
    placed.mount.dispose();
    this.runtime.tree.flushMutations();
  }

  /** Texture, scale, origin, and blocking footprint of an object scene, for placement previews. */
  describePlaceable(sceneIdValue: string): PlaceableVisual | undefined {
    const document = this.options.content.catalog.get(sceneId(sceneIdValue));
    if (!document) return undefined;
    const visual = document.nodes.find((node) => node.type === 'Sprite2D');
    const texture = visual?.properties.texture as { resourceId?: string } | undefined;
    const sheet = document.subresources?.find((resource) => resource.resourceId === texture?.resourceId) as { assetId?: string } | undefined;
    const asset = sheet?.assetId ? ASSET_MANIFEST.assets[sheet.assetId as AssetId] : undefined;
    if (!visual || !asset) return undefined;
    const pair = (value: unknown, fallback: readonly [number, number]): readonly [number, number] => (
      Array.isArray(value) && value.length === 2 && value.every((part) => typeof part === 'number')
        ? [value[0] as number, value[1] as number] : fallback
    );
    const shapeNode = document.nodes.find((node) => node.type === 'CollisionShape2D');
    const shapeRef = shapeNode?.properties.shape as { resourceId?: string } | undefined;
    const shape = document.subresources?.find((resource) => resource.resourceId === shapeRef?.resourceId) as
      { value?: { shape?: string; width?: number; height?: number } } | undefined;
    const shapePosition = pair(shapeNode?.properties.position, [0, 0]);
    const width = shape?.value?.width;
    const height = shape?.value?.height;
    const [scaleX, scaleY] = pair(visual.properties.scale, [1, 1]);
    const [originX, originY] = pair(visual.properties.origin, [0.5, 1]);
    return {
      textureKey: asset.runtime.textureKey,
      frame: typeof visual.properties.frame === 'number' ? visual.properties.frame : 0,
      scaleX,
      scaleY,
      originX,
      originY,
      rotation: typeof visual.properties.rotation === 'number' ? visual.properties.rotation : 0,
      footprint: typeof width === 'number' && typeof height === 'number'
        ? { x: shapePosition[0], y: shapePosition[1], width, height }
        : undefined,
    };
  }

  private mountPlayer(): void {
    const mount = this.runtime.mountScene(sceneId('character.player-slime'), {
      runtimeNamespace: 'managed-player',
      position: this.options.playerSpawn,
    });
    const script = descendants(mount.root, PlayerScript)[0];
    const body = descendants(mount.root, CharacterBody2DNode)[0];
    const visual = descendants(mount.root, Sprite2DNode)[0];
    const pickupArea = descendants(mount.root, Area2DNode).find((area) => area.name === 'PickupArea');
    if (!script || !body || !visual || !pickupArea) {
      mount.dispose();
      throw new Error("Player scene 'character.player-slime' requires PlayerScript, CharacterBody2D, Sprite2D, and PickupArea.");
    }
    this.playerScript = script;
    this.playerBody = body;
    this.playerVisual = visual;
    this.playerPickupArea = pickupArea;
    this.registerCharacterOcclusion(mount.root, PLAYER_SILHOUETTE_COLOR, () => !script.getDamageState().dead);
  }

  /**
   * Every character body with an authored depth anchor sorts by its feet; its
   * direct Sprite2D children are the character's visuals and are registered
   * for occlusion silhouettes using the same depth they render with.
   */
  private registerCharacterOcclusion(root: Node, silhouetteColor: number, isAlive: () => boolean): void {
    const register = this.options.registerOcclusionActor;
    if (!register) return;
    for (const body of descendants(root, CharacterBody2DNode)) {
      if (!body.depthAnchor) continue;
      for (const visual of body.get_children()) {
        if (!(visual instanceof Sprite2DNode) || !visual.phaserObjectActive) continue;
        const registration = register({
          id: visual.runtimeId,
          owner: visual.presentationObject,
          visual,
          getGroundAnchorY: () => visual.depthSortY,
          getDepth: () => visual.renderDepth,
          isEligible: () => visual.is_inside_tree() && visual.visible && isAlive(),
          silhouetteColor,
        });
        visual.lifetimeDisposables.add(() => registration.dispose());
      }
    }
  }

  private primaryEnemyTarget() {
    const script = this.playerScript;
    if (!script) return undefined;
    return {
      position: script.getPosition(),
      damageAreaNodeId: script.damageAreaNodeId,
      damageShapes: script.damageShapes,
      active: !script.getDamageState().dead,
      hostile: true,
    };
  }

  private acquireNpcAgent(request: NpcRuntimeRequest): NpcWanderAgent | undefined {
    const packageValue = getCharacterPackage(request.characterId);
    const area = this.options.map.npcWanderAreas?.find((candidate) => request.sourceNodeId.includes(`/${candidate.npcInstanceId}/`));
    if (!area) return undefined;
    const randomPause = (): number => request.pauseMinMs + Math.random() * Math.max(0, request.pauseMaxMs - request.pauseMinMs);
    return {
      initialState: createNpcWanderState(randomPause()),
      step: (state, input) => {
        const result = stepNpcWander(state, {
          position: input.position,
          deltaMs: input.deltaMs,
          speed: input.speed,
          body: packageValue.character.body,
          perimeter: area.perimeter,
        });
        if (result.animation !== 'idle' || result.state.phase !== 'pause' || result.state.pauseRemainingMs !== 0) return result;
        return { ...result, state: createNpcWanderState(randomPause(), result.state.facing) };
      },
      dispose() {},
    };
  }

  private registerNpcPlacement(script: NpcScript): void {
    const owner = authoredInstanceOwner(script);
    const instanceId = owner.authoredInstanceProvenance?.authoredInstanceId;
    if (!instanceId || !script.npcDefinitionId) throw new Error(`NPC '${script.runtimeId}' requires an authored scene identity.`);
    const actor: NpcActorHandle = {
      instanceId,
      npcId: script.npcDefinitionId,
      isActive: () => script.isActive(),
      getPosition: () => script.getPosition(),
      acquireInteractionLock: () => script.acquireInteractionLock(),
    };
    this.npcs.set(instanceId, script);
    const visual = script.getReference<Node>('visual')?.configuredTarget;
    if (visual instanceof Sprite2DNode) {
      this.npcNameTags.add(instanceId, {
        label: getNpcDefinition(script.npcDefinitionId)?.displayName ?? script.npcDefinitionId,
        isActive: () => script.isActive(),
        sprite: () => visual.presentationObject,
      });
    }
    this.options.registerNpc?.({
      actor,
      instanceId,
      npcDefinitionId: script.npcDefinitionId,
    });
  }

  private evaluateCamps(): void {
    const epochNow = Date.now();
    for (const camp of this.camps.values()) {
      const player = this.managedPlayer.getPosition();
      const inside = camp.script.containsActivationPoint(player.x, player.y);
      camp.script.evaluateActivation(inside, epochNow);
    }
  }

  private spawnBoss(request: BossSceneSpawnRequest): void {
    this.removeBoss(request.campId);
    const camp = this.camps.get(request.campId);
    if (!camp) throw new Error(`Managed boss camp '${request.campId}' is not mounted.`);
    const origin = camp.owner.get_global_transform().position;
    const mount = this.runtime.mountScene(sceneId(request.sceneId), {
      runtimeNamespace: `managed-boss-${this.nextBossSequence++}`,
      persistenceKey: `${request.campId}.boss`,
      position: { x: origin.x + request.spawn.x, y: origin.y + request.spawn.y },
    });
    const script = descendants(mount.root, EnemyScript)[0];
    if (!script) { mount.dispose(); throw new Error(`Boss scene '${request.sceneId}' has no enemy receiver script.`); }
    this.registerCharacterOcclusion(mount.root, HOSTILE_SILHOUETTE_COLOR, () => !script.defeated);
    this.bosses.set(request.campId, { campId: request.campId, bossId: request.bossId, script, mount, defeatedNotified: false });
  }

  private removeBoss(campId: string): void {
    const boss = this.bosses.get(campId);
    if (!boss) return;
    boss.mount.dispose();
    this.bosses.delete(campId);
  }

  private finishDefeatedBosses(): void {
    for (const [campId, boss] of [...this.bosses]) {
      if (!boss.script.defeated || boss.defeatedNotified) continue;
      boss.defeatedNotified = true;
      this.camps.get(campId)?.script.onBossDefeated(Date.now());
      this.options.showMessage(
        boss.script.worldPosition.x,
        boss.script.worldPosition.y - 84,
        `${bossDisplayName(boss.script, boss.bossId)} defeated!`,
        'yellow',
        true,
      );
      boss.mount.dispose();
      this.bosses.delete(campId);
    }
  }

  private showEnemyDamageNumber(request: EnemyDamageNumberRequest): void {
    const enemy = [...this.ordinaryEnemies.values()].find((entry) => entry.script.runtimeId === request.sourceNodeId);
    const visual = enemy ? descendants(enemy.mount.root, Sprite2DNode)[0] : undefined;
    const top = visual?.phaserObjectActive ? visual.getBounds().top : request.y;
    const important = request.amount > 15;
    this.options.showMessage(request.x, top - 8, `-${request.amount}`, important ? 'yellow' : 'white', important);
  }

  private finishDefeatedOrdinaryEnemies(): void {
    for (const [enemyId, enemy] of [...this.ordinaryEnemies]) {
      if (!enemy.script.defeated) continue;
      if (!enemy.defeatNotified) {
        enemy.defeatNotified = true;
        enemy.disposeAtMs = enemy.script.simulationTime + 800;
        this.options.onManagedEnemyDefeated({
          enemyId,
          config: enemy.request.config,
          x: enemy.script.worldPosition.x,
          y: enemy.script.worldPosition.y,
        });
      }
      if (enemy.disposeAtMs !== undefined && enemy.script.simulationTime >= enemy.disposeAtMs) {
        this.removeOrdinaryEnemy(enemyId);
      }
    }
  }

  private removeOrdinaryEnemy(enemyId: number): void {
    const enemy = this.ordinaryEnemies.get(enemyId);
    if (!enemy) return;
    enemy.mount.dispose();
    this.ordinaryEnemies.delete(enemyId);
  }

  private enemyNavigation(sourceNodeId: string): EnemyNavigationSnapshot | undefined {
    const boss = [...this.bosses.values()].find((candidate) => candidate.script.runtimeId === sourceNodeId);
    if (boss) {
      const arena = this.camps.get(boss.campId)?.script.arenaPerimeter;
      return arena ? { arena } : undefined;
    }
    const enemy = [...this.ordinaryEnemies.values()].find((candidate) => candidate.script.runtimeId === sourceNodeId);
    if (!enemy) return undefined;
    return {
      safeZones: this.options.getEnemySafeZones(),
      ...(enemy.request.area ? { spawnArea: enemy.request.area } : {}),
    };
  }

  spawnEnemyProjectile(request: EnemyProjectileRequest): boolean {
    if (!request.projectileId) {
      throw new Error(`Enemy '${request.sourceNodeId}' projectile must reference an authored projectile scene.`);
    }
    const sequence = this.nextProjectileSequence++;
    const mount = this.runtime.mountScene(sceneId(`projectile.${request.projectileId}`), {
      runtimeNamespace: `managed-projectile-${sequence}`,
      position: request.position,
    });
    const script = descendants(mount.root, ProjectileScript)[0];
    if (!script) {
      mount.dispose();
      throw new Error(`Projectile scene '${request.projectileId}' requires ProjectileScript.`);
    }
    this.projectiles.set(sequence, { mount, script });
    script.launch(request.direction, request.speed, {
      sourceNodeId: request.sourceNodeId,
      damage: request.damage,
      knockbackStrength: request.knockbackStrength,
      weaponId: request.projectileId,
      weaponTags: ['enemy', 'projectile'],
      damageTypes: ['physical'],
      targetAreaNodeIds: [this.managedPlayer.damageAreaNodeId],
      ...(request.stickMs ? { effects: [{ effectId: 'web', potency: request.stickMs }] } : {}),
    });
    this.managedProjectileSpawnCountValue += 1;
    return true;
  }

  private finishExpiredProjectiles(): void {
    for (const [sequence, projectile] of [...this.projectiles]) {
      if (projectile.script.launched && !projectile.mount.root.is_freed()) continue;
      projectile.mount.dispose();
      this.projectiles.delete(sequence);
    }
  }

  private finishExpiredEffects(): void {
    for (const [sequence, effect] of [...this.effects]) {
      if (effect.script.playing && !effect.mount.root.is_freed()) continue;
      effect.attachment?.dispose();
      effect.mount.dispose();
      this.effects.delete(sequence);
    }
  }

  private publishResourceHit(request: ResourceHitFeedbackRequest): void {
    const resource = this.resources.get(request.instanceId);
    const visual = resource ? descendants(resource.owner, Sprite2DNode)[0] : undefined;
    visual?.setTintFill(0xffd277);
    if (visual && resource) {
      this.options.scene.time.delayedCall(110, () => {
        if (!resource.owner.is_freed()) visual.clearTint();
      });
    }
    this.options.showMessage(request.x, request.y - 54, `-${Math.round(request.actualDamage)}`, 'white');
    if (request.effectId) {
      this.spawnEffect({
        effectId: request.effectId,
        direction: 'right',
        x: request.x,
        y: request.y,
      });
    }
  }

  private finishDestroyedResources(): void {
    for (const [instanceId, resource] of [...this.resources]) {
      if (!resource.script.destroyed) continue;
      resource.owner.queue_free();
      this.resources.delete(instanceId);
    }
    this.runtime.tree.flushMutations();
  }

  private pickupCollectible(request: CollectiblePickupRequest): CollectiblePickupResult {
    if (!this.playerPickupArea || request.collectorAreaNodeId !== this.playerPickupArea.runtimeId) {
      return {
        status: 'rejected',
        moved: 0,
        remaining: this.options.collectibles.remaining(request.mapId, request.instanceId),
        reason: 'invalid-collector',
      };
    }
    return this.options.collectibles.pickup(request);
  }

  private finishDepletedCollectibles(): void {
    for (const [instanceId, collectible] of [...this.collectibles]) {
      if (collectible.script.remaining > 0) continue;
      collectible.owner.queue_free();
      this.collectibles.delete(instanceId);
    }
    this.runtime.tree.flushMutations();
  }

  private managedTargetTags(receiverNodeId: string): readonly string[] {
    for (const resource of this.resources.values()) {
      if (resource.script.runtimeNodeId === receiverNodeId) return resource.script.tags;
    }
    for (const boss of this.bosses.values()) {
      if (boss.script.runtimeNodeId === receiverNodeId) return ['enemy', 'boss'];
    }
    for (const enemy of this.ordinaryEnemies.values()) {
      if (enemy.script.runtimeNodeId === receiverNodeId) return ['enemy'];
    }
    return [];
  }

  private syncChestFrame(script: ChestScript): void {
    const visual = descendants(script.get_parent() ?? script, Sprite2DNode)[0];
    if (visual) visual.frame = script.empty ? 1 : 0;
  }
}

function descendants<T extends Node>(root: Node, type: abstract new (...args: any[]) => T): T[] {
  const matches: T[] = [];
  const visit = (node: Node): void => {
    if (node instanceof type) matches.push(node);
    for (const child of node.get_children()) visit(child);
  };
  visit(root);
  return matches;
}

function authoredInstanceOwner(node: Node): Node {
  let current: Node | undefined = node;
  while (current) {
    if (current.authoredInstanceProvenance) return current;
    current = current.get_parent();
  }
  throw new Error(`Node '${node.runtimeId}' is not owned by an authored scene instance.`);
}

function directAuthoredInstanceRoots(root: Node): Node[] {
  const output: Node[] = [];
  const visit = (node: Node): void => {
    if (node.authoredInstanceProvenance?.containingInstancePath.length === 0) output.push(node);
    for (const child of node.get_children()) visit(child);
  };
  visit(root);
  return output;
}

export function createUiAssetUrlResolver(scene: Phaser.Scene): (key: string, frame: number) => string | undefined {
  const urls = new Map<string, string>();
  return (key, frame) => {
    const cacheKey = `${key}:${frame}`;
    const cached = urls.get(cacheKey);
    if (cached) return cached;
    if (!scene.textures.exists(key)) return undefined;
    const texture = scene.textures.get(key);
    const frameName = String(frame);
    const selected = texture.has(frameName)
      ? texture.get(frameName)
      : frame === 0 && texture.firstFrame === '__BASE' ? texture.get('__BASE') : undefined;
    if (!selected || selected.source.image instanceof Uint8Array) return undefined;
    const canvas = document.createElement('canvas');
    canvas.width = selected.cutWidth;
    canvas.height = selected.cutHeight;
    const context = canvas.getContext('2d');
    if (!context) return undefined;
    context.drawImage(
      selected.source.image,
      selected.cutX, selected.cutY, selected.cutWidth, selected.cutHeight,
      0, 0, selected.cutWidth, selected.cutHeight,
    );
    const url = canvas.toDataURL('image/png');
    urls.set(cacheKey, url);
    return url;
  };
}

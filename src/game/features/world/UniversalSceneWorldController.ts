import Phaser from 'phaser';

import type { MapEnemySafeZone, MapFile } from '../../content/maps/mapFormat';
import { getCharacterPackage } from '../../content/characters/CharacterCatalog';
import { sceneId, type SceneId } from '../../content/scenes/identifiers';
import { getBossDefinition } from '../../content/bosses/BossCatalog';
import { ASSET_MANIFEST, type AssetId } from '../../infrastructure/assets/manifest';
import { CharacterBody2DNode } from '../../infrastructure/phaser-nodes/CharacterBody2DNode';
import { Area2DNode } from '../../infrastructure/phaser-nodes/Area2DNode';
import { Sprite2DNode } from '../../infrastructure/phaser-nodes/Sprite2DNode';
import { PhaserUniversalSceneRuntime, type MountedScene } from '../../infrastructure/scenes/PhaserUniversalSceneRuntime';
import type { PreparedSceneContent } from '../../infrastructure/scenes/PreparedSceneContent';
import { LegacyBossUiBridge, type LegacyBossBarHandle } from '../../infrastructure/scenes/compatibility/LegacyBossUiBridge';
import { LegacyChestUiBridge } from '../../infrastructure/scenes/compatibility/LegacyChestUiBridge';
import { LegacyWorldAdapter } from '../../infrastructure/scenes/compatibility/LegacyWorldAdapter';
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
import type { ObjectOccluderRegistration } from '../objects/ObjectFactory';
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
  type LegacyWeaponHitboxRequest,
  type WeaponAttackDirection,
  type WeaponDamagePayload,
} from '../scripts/WeaponScript';
import type { WorldEffectSpawnRequest } from '../effects/WorldEffectSpawn';
import { WorldEffectPositionAttachment } from '../effects/WorldEffectPositionAttachment';
import { resolvePhysicsPresentationPosition, type PhysicsPresentationTarget } from '../../presentation/PhysicsPresentation';
import { PLAYER_INPUT_ACTIONS } from '../player/PlayerInputActions';
import type { LegacyPlayerHealthAdapter } from '../../infrastructure/scenes/compatibility/LegacyPlayerHealthAdapter';
import type { ModalStack } from '../../ui/ModalStack';
import { ChestInventoryPanel } from '../../ui/ChestInventoryPanel';
import { BossHealthBar } from '../../ui/BossHealthBar';
import { HtmlControlPresentationAdapter } from '../../infrastructure/phaser-nodes/ui/HtmlControlPresentationAdapter';
import { HudSurfacePort } from '../ui/HudSurfacePort';
import { UI_SURFACE_SERVICE } from '../scripts/ui/UiSurfaceScript';
import {
  WORLD_EXIT_SERVICE,
  type WorldExitPort,
  type WorldExitRequest,
  type WorldExitResult,
} from '../scripts/WorldExitScript';

export interface UniversalSceneWorldControllerOptions {
  readonly scene: Phaser.Scene;
  readonly content: PreparedSceneContent;
  readonly map: MapFile;
  readonly worldSceneId: SceneId;
  readonly playerSpawn: Readonly<{ x: number; y: number }>;
  readonly health: LegacyPlayerHealthAdapter;
  readonly progress: WorldProgress;
  readonly transaction: InventoryWorldTransaction;
  readonly interactions: InteractionRouter;
  readonly modalStack: ModalStack;
  readonly setChestPaused: (paused: boolean) => void;
  readonly showMessage: (x: number, y: number, message: string, color?: 'white' | 'yellow' | 'green' | 'cyan' | 'orange' | 'red', important?: boolean) => void;
  readonly updateLegacyFixed: (deltaMs: number) => void;
  readonly updateLegacyRender: (deltaMs: number) => void;
  readonly transformManagedWeaponDamage: (damage: number, target: ManagedWeaponTarget) => number;
  readonly onManagedWeaponOutcome: (outcome: RoutedDamageOutcome, target: ManagedWeaponTarget | undefined) => void;
  readonly onManagedWeaponAttackStarted: (weaponId: string, direction: WeaponAttackDirection) => void;
  readonly onManagedWeaponAttackFinished: (weaponId: string, direction: WeaponAttackDirection) => void;
  readonly activateLegacyWeaponHitbox: (request: LegacyWeaponHitboxRequest) => () => void;
  readonly onManagedEnemyDefeated: (enemy: ManagedEnemyDefeat) => void;
  readonly getEnemySafeZones: () => readonly MapEnemySafeZone[];
  readonly registerNpc?: (registration: QuestNpcRegistration) => void;
  readonly registerManagedResource: (registration: ManagedResourceRegistration) => void;
  readonly spawnManagedResourceDrops: (request: ResourceDropRequest) => void;
  readonly collectibles: CollectibleWorldPort;
  readonly registerOccluder?: (registration: ObjectOccluderRegistration) => { dispose(): void };
  readonly requestExit: (request: WorldExitRequest) => WorldExitResult;
  readonly uiRoot: HTMLElement;
}

interface ManagedCamp {
  readonly script: BossCampScript;
  readonly owner: Node2D;
}

interface ManagedBoss {
  readonly campId: string;
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

const MANAGED_ENEMY_SCENES = {
  'worm-archer': 'character.worm-archer',
  'worm-brawler': 'character.worm-brawler',
  'worm-swordsman': 'character.worm-swordsman',
  'slime-spider': 'character.slime-spider',
} as const;

function isPassiveObjectScene(sceneIdValue: string): boolean {
  return sceneIdValue.startsWith('object.decoration-world-')
    || sceneIdValue.startsWith('object.house-world-solid')
    || sceneIdValue.startsWith('object.rock-world-wall-')
    || sceneIdValue.startsWith('object.wall-stone-solid');
}

class ManagedBossBar implements LegacyBossBarHandle {
  readonly bar: BossHealthBar;
  private destroyed = false;

  constructor(scene: Phaser.Scene, script: EnemyScript, name: string, private readonly onDestroy: (bar: ManagedBossBar) => void) {
    const target = {
      get active() { return !script.defeated; },
      get dead() { return script.defeated; },
      get hp() { return script.hp; },
      get maxHp() { return script.maxHealth; },
    };
    this.bar = new BossHealthBar(scene, target, name);
  }

  update(): void { if (!this.destroyed) this.bar.update(); }
  defeat(): void { if (!this.destroyed) this.bar.defeat(); this.destroyed = true; this.onDestroy(this); }
  destroy(): void { if (!this.destroyed) this.bar.destroy(); this.destroyed = true; this.onDestroy(this); }
}

export class UniversalSceneWorldController implements InteractionProvider {
  readonly runtime: PhaserUniversalSceneRuntime;
  private readonly activations = new AttackActivation();
  private readonly damageRouter = new DamageRouter(this.activations, () => this.simulationTimeMs);
  private readonly chestUi?: LegacyChestUiBridge;
  private readonly bossUi: LegacyBossUiBridge;
  private readonly inputRouter: InputRouter;
  private readonly uiPresentation: HtmlControlPresentationAdapter;
  private readonly hudSurface: HudSurfacePort;
  private readonly camps = new Map<string, ManagedCamp>();
  private readonly bosses = new Map<string, ManagedBoss>();
  private readonly ordinaryEnemies = new Map<number, ManagedOrdinaryEnemy>();
  private readonly projectiles = new Map<number, ManagedProjectile>();
  private readonly effects = new Map<number, ManagedEffect>();
  private readonly resources = new Map<string, ManagedResource>();
  private readonly collectibles = new Map<string, ManagedCollectible>();
  private readonly passiveObjects = new Set<Node>();
  private readonly authoredRoots = new Set<Node2D>();
  private weapon?: ManagedWeapon;
  private readonly npcs = new Map<string, NpcScript>();
  private playerScript?: PlayerScript;
  private playerBody?: CharacterBody2DNode;
  private playerVisual?: Sprite2DNode;
  private playerPickupArea?: Area2DNode;
  private readonly chests = new Map<string, ChestScript>();
  private readonly bossBars = new Set<ManagedBossBar>();
  private readonly unregisterInteraction: () => void;
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
    this.hudSurface = new HudSurfacePort();
    this.inputRouter = new InputRouter({
      sink: { enqueueInput: (event) => inputSink?.enqueueInput(event) },
      actions: PLAYER_INPUT_ACTIONS,
      isPaused: () => this.runtime.tree.paused,
    });
    this.uiPresentation = new HtmlControlPresentationAdapter({
      root: options.uiRoot,
      viewport: () => ({ width: options.uiRoot.clientWidth, height: options.uiRoot.clientHeight }),
    });
    const chestView = {
      open: (model: Parameters<LegacyChestUiBridge['open']>[0]) => this.chestUi?.open(model),
      close: (instanceId: string) => this.chestUi?.close(instanceId),
    };
    const bossStatus = {
      showBoss: (campId: string, bossId: string) => this.bossUi.showBoss(campId, bossId),
      hideBoss: (campId: string, defeated: boolean) => this.bossUi.hideBoss(campId, defeated),
    };
    const scripts = createGameScriptRegistry({
      [DAMAGE_ROUTER_SERVICE]: this.damageRouter,
      [ATTACK_ACTIVATION_SERVICE]: this.activations,
      [PLAYER_WEAPON_COMBAT_SERVICE]: {
        onAttackStarted: options.onManagedWeaponAttackStarted,
        onAttackFinished: options.onManagedWeaponAttackFinished,
        activateLegacyHitbox: options.activateLegacyWeaponHitbox,
        transformDamage: (damage: number, target: ManagedWeaponTarget) => options.transformManagedWeaponDamage(damage, {
          ...target,
          targetTags: this.managedTargetTags(target.receiverNodeId),
        }),
        onOutcome: (outcome: RoutedDamageOutcome, target: ManagedWeaponTarget) => options.onManagedWeaponOutcome(outcome, {
          ...target,
          targetTags: this.managedTargetTags(target.receiverNodeId),
        }),
      },
      [PLAYER_HEALTH_SERVICE]: options.health.managedReceiver,
      [ENEMY_TARGET_SERVICE]: {
        getPrimaryTarget: () => this.primaryEnemyTarget(),
        getNavigation: (sourceNodeId: string) => this.enemyNavigation(sourceNodeId),
        fireProjectile: (request: EnemyProjectileRequest) => this.spawnEnemyProjectile(request),
      },
      [NPC_RUNTIME_SERVICE]: {
        acquire: (request: NpcRuntimeRequest) => this.acquireNpcAgent(request),
      },
      [BOSS_CAMP_PROGRESS_SERVICE]: {
        getRespawnReadyAt: (mapId: string, campId: string) => options.progress.bossCampRespawnReadyAt(mapId, campId),
        setRespawnReadyAt: (mapId: string, campId: string, epochMs: number | undefined) => options.progress.setBossCampRespawnReadyAt(mapId, campId, epochMs),
        markBossDefeated: (bossId: string) => options.progress.defeatBoss(bossId),
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
      [CHEST_VIEW_SERVICE]: chestView,
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
      [UI_SURFACE_SERVICE]: this.hudSurface,
    });
    try {
      this.runtime = new PhaserUniversalSceneRuntime({
        scene: options.scene,
        content: options.content,
        descriptors: createGameDescriptorRegistry(),
        scripts,
        nodeServices: {
          inputRouter: this.inputRouter,
          controlPresentation: this.uiPresentation,
        },
        resolveAssetKey: (assetId) => ASSET_MANIFEST.assets[assetId as AssetId].runtime.textureKey,
        diagnosticSink: (diagnostic) => {
          console.error(`[UniversalScene:${diagnostic.phase}] ${diagnostic.message}`, diagnostic.error ?? '');
        },
        legacy: new LegacyWorldAdapter({
          prePhysics: (deltaSeconds) => {
            this.simulationTimeMs += deltaSeconds * 1000;
            options.updateLegacyFixed(deltaSeconds * 1000);
            this.evaluateCamps();
          },
          postPhysics: () => {
            this.finishDefeatedBosses();
            this.finishDefeatedOrdinaryEnemies();
            this.finishExpiredProjectiles();
            this.finishExpiredEffects();
            this.finishDestroyedResources();
            this.finishDepletedCollectibles();
          },
          render: (deltaSeconds) => {
            options.updateLegacyRender(deltaSeconds * 1000);
            for (const effect of this.effects.values()) effect.attachment?.update();
            for (const bar of this.bossBars) bar.update();
          },
        }),
      });
      inputSink = this.runtime;
      this.runtime.mountScene(sceneId('ui.hud'), { runtimeNamespace: 'ui-hud' });
    } catch (error) {
      this.inputRouter.destroy();
      this.hudSurface.destroy();
      throw error;
    }

    let panelBridge: LegacyChestUiBridge | undefined;
    const panel = new ChestInventoryPanel({
      scene: options.scene,
      modalStack: options.modalStack,
      onPausedChange: options.setChestPaused,
      getContents: (instanceId) => panelBridge?.getContents(instanceId) ?? {},
      transferStack: (instanceId, itemId) => panelBridge?.transferStack(instanceId, itemId) ?? 0,
      onClosed: (instanceId) => this.chests.get(instanceId)?.close(),
    });
    this.chestUi = panelBridge = new LegacyChestUiBridge(panel);
    this.bossUi = new LegacyBossUiBridge((campId, bossId) => this.createBossBar(campId, bossId));
    this.mountPlayer();
    this.mountAuthoredWorld();
    this.unregisterInteraction = options.interactions.register('managed-chests', this);
  }

  advanceFrame(deltaSeconds: number): number { return this.runtime.advanceFrame(deltaSeconds); }
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
  get playerPhysicsSprite(): Phaser.Physics.Arcade.Sprite {
    if (!this.playerBody) throw new Error('The authored player body is not mounted.');
    return this.playerBody.physicsSprite;
  }
  get playerPresentation(): Sprite2DNode {
    if (!this.playerVisual) throw new Error('The authored player visual is not mounted.');
    return this.playerVisual;
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
      execute: () => {
        const result = nearest!.script.requestOpen();
        if (result === 'guarded') this.options.showMessage(nearest!.position.x, nearest!.position.y - 48, 'Fatty One Eye is guarding this chest!', 'white', true);
        return true;
      },
    };
  }

  isChestLocked(instanceId: string): boolean {
    return [...this.camps.values()].some((camp) => camp.script.isChestGuarded(instanceId));
  }

  resetActiveFights(): void {
    for (const camp of this.camps.values()) camp.script.resetActiveFight();
  }

  createManagedEnemy(request: EnemySpawnRequest): EnemyPopulationMember | null | undefined {
    const authoredSceneId = MANAGED_ENEMY_SCENES[request.config.id as keyof typeof MANAGED_ENEMY_SCENES];
    if (!authoredSceneId) return undefined;
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
    const attachment = request.followPositionOf
      ? new WorldEffectPositionAttachment(
          {
            setPosition: (x, y) => { mount.mount.position = { x, y }; },
            setDepth: () => undefined,
          },
          request.followPositionOf,
          Phaser.GameObjects.Events.DESTROY,
          request.x,
          request.y,
          request.depth,
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

  playWeaponAttack(direction: WeaponAttackDirection, timeMs: number, damage: WeaponDamagePayload): boolean {
    return this.weapon?.script.tryBeginAttack(direction, timeMs, damage) ?? false;
  }

  canWeaponAttack(timeMs: number): boolean {
    return this.weapon?.script.canBeginAttack(timeMs) ?? false;
  }

  clearWeapon(): void {
    this.weapon?.mount.dispose();
    this.weapon = undefined;
  }

  destroy(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unregisterInteraction();
    this.inputRouter.destroy();
    this.runtime.shutdown();
    this.hudSurface.destroy();
    this.chestUi?.dispose();
    this.bossUi.dispose();
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
    this.bossBars.clear();
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
    for (const script of descendants(mount.root, BossCampScript)) {
      const owner = authoredInstanceOwner(script);
      if (owner instanceof Node2D) this.camps.set(script.campId, { script, owner });
    }
    for (const node of directAuthoredInstanceRoots(mount.root)) {
      if (node instanceof Node2D) this.authoredRoots.add(node);
      if (isPassiveObjectScene(node.authoredInstanceProvenance?.sourceSceneId ?? '')) this.passiveObjects.add(node);
    }
    this.runtime.tree.flushMutations();
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
  }

  private primaryEnemyTarget() {
    const script = this.playerScript;
    if (!script) return undefined;
    return {
      position: script.getPosition(),
      damageAreaNodeId: script.damageAreaNodeId,
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
    this.bosses.set(request.campId, { campId: request.campId, script, mount, defeatedNotified: false });
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
        'Fatty One Eye defeated!',
        'yellow',
        true,
      );
      boss.mount.dispose();
      this.bosses.delete(campId);
    }
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
        depth: 0,
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

  private createBossBar(campId: string, bossId: string): LegacyBossBarHandle {
    const boss = this.bosses.get(campId);
    if (!boss) return { destroy() {} };
    const bar = new ManagedBossBar(this.options.scene, boss.script, getBossDefinition(bossId).displayName, (entry) => this.bossBars.delete(entry));
    this.bossBars.add(bar);
    return bar;
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

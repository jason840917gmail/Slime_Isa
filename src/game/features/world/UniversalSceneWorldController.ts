import Phaser from 'phaser';

import type { SupplementalWeaponHitboxPort } from '../../combat/Weapon';
import type { MapBossCamp, MapEnemySafeZone, MapFile } from '../../content/maps/mapFormat';
import { getCharacterPackage } from '../../content/characters/CharacterCatalog';
import { sceneId } from '../../content/scenes/identifiers';
import { getBossDefinition } from '../../content/bosses/BossCatalog';
import { ASSET_MANIFEST, type AssetId } from '../../infrastructure/assets/manifest';
import { PhysicsBody2DNode } from '../../infrastructure/phaser-nodes/PhysicsBody2DNode';
import { CharacterBody2DNode } from '../../infrastructure/phaser-nodes/CharacterBody2DNode';
import { Sprite2DNode } from '../../infrastructure/phaser-nodes/Sprite2DNode';
import { PhaserUniversalSceneRuntime, type MountedScene } from '../../infrastructure/scenes/PhaserUniversalSceneRuntime';
import type { PreparedSceneContent } from '../../infrastructure/scenes/PreparedSceneContent';
import { LegacyBossUiBridge, type LegacyBossBarHandle } from '../../infrastructure/scenes/compatibility/LegacyBossUiBridge';
import { LegacyChestUiBridge } from '../../infrastructure/scenes/compatibility/LegacyChestUiBridge';
import { LegacyCombatBridge } from '../../infrastructure/scenes/compatibility/LegacyCombatBridge';
import {
  LegacyMapPlacementBridge,
  type SceneEnabledPlacement,
} from '../../infrastructure/scenes/compatibility/LegacyMapPlacementBridge';
import { LegacyWeaponTargetBridge, type LegacyWeaponManagedTarget } from '../../infrastructure/scenes/compatibility/LegacyWeaponTargetBridge';
import { LegacyWorldAdapter } from '../../infrastructure/scenes/compatibility/LegacyWorldAdapter';
import type { Node } from '../../runtime/scene/Node';
import { InputRouter } from '../../runtime/scene/input/InputRouter';
import type { Node2D } from '../../runtime/scene/Node2D';
import { AttackActivation } from '../combat/AttackActivation';
import type { RoutedDamageOutcome } from '../combat/DamageRouter';
import { DamageRouter } from '../combat/DamageRouter';
import type { InteractionProvider, InteractionRouter } from '../interaction/InteractionRouter';
import type { NpcActorHandle, QuestNpcRegistration } from '../interaction/QuestNpcController';
import { createNpcWanderState, stepNpcWander } from '../npcs/NpcWanderPolicy';
import type { InventoryWorldTransaction } from '../progression/InventoryWorldTransaction';
import type { WorldProgress } from '../progression/WorldProgress';
import type { EnemyPopulationMember, EnemySpawnRequest } from '../../enemies/EnemySpawner';
import { projectilePool } from '../../enemies/Projectile';
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
import { PLAYER_INPUT_ACTIONS } from '../player/PlayerInputActions';
import type { HealthSystem } from '../../systems/HealthSystem';
import type { ModalStack } from '../../ui/ModalStack';
import { ChestInventoryPanel } from '../../ui/ChestInventoryPanel';
import { BossHealthBar } from '../../ui/BossHealthBar';
import { bossPerimeterContains } from '../bosses/BossCampBehavior';

export interface UniversalSceneWorldControllerOptions {
  readonly scene: Phaser.Scene;
  readonly content: PreparedSceneContent;
  readonly map: MapFile;
  readonly placementBridge: LegacyMapPlacementBridge;
  readonly playerSpawn: Readonly<{ x: number; y: number }>;
  readonly collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  readonly health: HealthSystem;
  readonly progress: WorldProgress;
  readonly transaction: InventoryWorldTransaction;
  readonly interactions: InteractionRouter;
  readonly modalStack: ModalStack;
  readonly setChestPaused: (paused: boolean) => void;
  readonly showMessage: (x: number, y: number, message: string, color?: 'white' | 'yellow' | 'green' | 'cyan' | 'orange' | 'red', important?: boolean) => void;
  readonly updateLegacyFixed: (deltaMs: number) => void;
  readonly updateLegacyRender: (deltaMs: number) => void;
  readonly transformManagedWeaponDamage: (damage: number, target: LegacyWeaponManagedTarget) => number;
  readonly onManagedWeaponOutcome: (outcome: RoutedDamageOutcome, target: LegacyWeaponManagedTarget | undefined) => void;
  readonly onManagedEnemyDefeated: (enemy: ManagedEnemyDefeat) => void;
  readonly getEnemySafeZones: () => readonly MapEnemySafeZone[];
  readonly registerNpc?: (registration: QuestNpcRegistration) => void;
}

interface ManagedCamp {
  readonly definition: MapBossCamp;
  readonly script: BossCampScript;
  readonly mount: MountedScene;
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

const MANAGED_ENEMY_SCENES = {
  'worm-archer': 'character.worm-archer',
  'worm-brawler': 'character.worm-brawler',
  'worm-swordsman': 'character.worm-swordsman',
  'slime-spider': 'character.slime-spider',
} as const;

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
  readonly supplementalWeaponHitboxes: SupplementalWeaponHitboxPort;
  readonly runtime: PhaserUniversalSceneRuntime;
  private readonly activations = new AttackActivation();
  private readonly damageRouter = new DamageRouter(this.activations, () => this.simulationTimeMs);
  private readonly combatBridge: LegacyCombatBridge;
  private readonly weaponBridge: LegacyWeaponTargetBridge;
  private readonly chestUi?: LegacyChestUiBridge;
  private readonly bossUi: LegacyBossUiBridge;
  private readonly inputRouter: InputRouter;
  private readonly camps = new Map<string, ManagedCamp>();
  private readonly bosses = new Map<string, ManagedBoss>();
  private readonly ordinaryEnemies = new Map<number, ManagedOrdinaryEnemy>();
  private readonly npcs = new Map<string, NpcScript>();
  private playerScript?: PlayerScript;
  private playerBody?: CharacterBody2DNode;
  private playerVisual?: Sprite2DNode;
  private readonly chests = new Map<string, ChestScript>();
  private readonly bossBars = new Set<ManagedBossBar>();
  private readonly unregisterInteraction: () => void;
  private nextBossSequence = 1;
  private nextEnemySequence = 1;
  private simulationTimeMs = 0;
  private mountingPlacement?: SceneEnabledPlacement;
  private disposed = false;

  constructor(private readonly options: UniversalSceneWorldControllerOptions) {
    this.combatBridge = new LegacyCombatBridge(this.activations, this.damageRouter);
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
      [PLAYER_HEALTH_SERVICE]: options.health.managedReceiver,
      [ENEMY_TARGET_SERVICE]: {
        getPrimaryTarget: () => this.primaryEnemyTarget(),
        getNavigation: (sourceNodeId: string) => this.enemyNavigation(sourceNodeId),
        fireProjectile: (request: EnemyProjectileRequest) => this.fireEnemyProjectile(request),
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
    });
    this.runtime = new PhaserUniversalSceneRuntime({
      scene: options.scene,
      content: options.content,
      descriptors: createGameDescriptorRegistry(),
      scripts,
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
        },
        render: (deltaSeconds) => {
          options.updateLegacyRender(deltaSeconds * 1000);
          for (const bar of this.bossBars) bar.update();
        },
      }),
    });

    if (options.placementBridge.scenePlacements().length > 0) {
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
    }
    this.bossUi = new LegacyBossUiBridge((campId, bossId) => this.createBossBar(campId, bossId));
    this.weaponBridge = new LegacyWeaponTargetBridge({
      context: this.runtime.context,
      combat: this.combatBridge,
      router: this.damageRouter,
      weaponTags: (weaponId) => [weaponId.includes('spear') ? 'spear' : 'weapon'],
      transformDamage: options.transformManagedWeaponDamage,
      onOutcome: options.onManagedWeaponOutcome,
    });
    this.supplementalWeaponHitboxes = this.weaponBridge;
    this.inputRouter = new InputRouter({
      sink: this.runtime,
      actions: PLAYER_INPUT_ACTIONS,
      isPaused: () => this.runtime.tree.paused,
    });
    this.mountPlayer();
    this.mountAuthoredPlacements();
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
    this.registerLegacyColliders(mount);
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

  destroy(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unregisterInteraction();
    this.inputRouter.destroy();
    this.weaponBridge.dispose();
    this.combatBridge.dispose();
    this.runtime.shutdown();
    this.chestUi?.dispose();
    this.bossUi.dispose();
    this.camps.clear();
    this.bosses.clear();
    this.ordinaryEnemies.clear();
    this.npcs.clear();
    this.playerScript = undefined;
    this.playerBody = undefined;
    this.playerVisual = undefined;
    this.chests.clear();
    this.bossBars.clear();
  }

  private mountAuthoredPlacements(): void {
    for (const placement of this.options.placementBridge.scenePlacements()) {
      this.mountingPlacement = placement;
      let mount: MountedScene;
      try {
        mount = this.runtime.mountScene(sceneId(placement.sceneId), {
          runtimeNamespace: `managed-${placement.placementId}`,
          persistenceKey: placement.persistenceKey,
          position: { x: placement.x, y: placement.y },
        });
      } finally {
        this.mountingPlacement = undefined;
      }
      const npcScript = descendants(mount.root, NpcScript)[0];
      this.registerLegacyColliders(mount, !npcScript);
      if (npcScript) this.registerNpcPlacement(placement, npcScript);
      for (const script of descendants(mount.root, ChestScript)) this.chests.set(script.instanceId, script);
      const campScript = descendants(mount.root, BossCampScript)[0];
      const definition = this.options.map.bossCamps?.find((camp) => camp.id === campScript?.campId);
      if (campScript && definition) this.camps.set(campScript.campId, { definition, script: campScript, mount });
    }
  }

  private mountPlayer(): void {
    const mount = this.runtime.mountScene(sceneId('character.player-slime'), {
      runtimeNamespace: 'managed-player',
      position: this.options.playerSpawn,
    });
    const script = descendants(mount.root, PlayerScript)[0];
    const body = descendants(mount.root, CharacterBody2DNode)[0];
    const visual = descendants(mount.root, Sprite2DNode)[0];
    if (!script || !body || !visual) {
      mount.dispose();
      throw new Error("Player scene 'character.player-slime' requires PlayerScript, CharacterBody2D, and Sprite2D.");
    }
    this.playerScript = script;
    this.playerBody = body;
    this.playerVisual = visual;
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
    const placement = this.mountingPlacement;
    if (!placement?.npcDefinitionId) throw new Error(`NPC '${request.sourceNodeId}' has no authored map placement context.`);
    const packageValue = getCharacterPackage(request.characterId);
    const area = this.options.map.npcWanderAreas?.find((candidate) => candidate.npcInstanceId === placement.placementId);
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

  private registerNpcPlacement(
    placement: SceneEnabledPlacement,
    script: NpcScript,
  ): void {
    if (!placement.npcDefinitionId) {
      throw new Error(`NPC scene '${placement.sceneId}' requires an NPC definition identity.`);
    }
    const actor: NpcActorHandle = {
      instanceId: placement.placementId,
      npcId: placement.npcDefinitionId,
      isActive: () => script.isActive(),
      getPosition: () => script.getPosition(),
      acquireInteractionLock: () => script.acquireInteractionLock(),
    };
    this.npcs.set(placement.placementId, script);
    this.options.registerNpc?.({
      actor,
      instanceId: placement.placementId,
      npcDefinitionId: placement.npcDefinitionId,
    });
  }

  private evaluateCamps(): void {
    const epochNow = Date.now();
    for (const camp of this.camps.values()) {
      const player = this.managedPlayer.getPosition();
      const inside = bossPerimeterContains(camp.definition.activationPerimeter, player.x, player.y);
      camp.script.evaluateActivation(inside, epochNow);
    }
  }

  private spawnBoss(request: BossSceneSpawnRequest): void {
    this.removeBoss(request.campId);
    const camp = this.camps.get(request.campId);
    if (!camp) throw new Error(`Managed boss camp '${request.campId}' is not mounted.`);
    const origin = camp.mount.mount.get_global_transform().position;
    const mount = this.runtime.mountScene(sceneId(request.sceneId), {
      runtimeNamespace: `managed-boss-${this.nextBossSequence++}`,
      persistenceKey: `${request.campId}.boss`,
      position: { x: origin.x + request.spawn.x, y: origin.y + request.spawn.y },
    });
    const script = descendants(mount.root, EnemyScript)[0];
    if (!script) { mount.dispose(); throw new Error(`Boss scene '${request.sceneId}' has no enemy receiver script.`); }
    this.bosses.set(request.campId, { campId: request.campId, script, mount, defeatedNotified: false });
    this.registerLegacyColliders(mount);
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

  private fireEnemyProjectile(request: EnemyProjectileRequest): void {
    if (request.projectileId) {
      projectilePool.fireDefinition(
        this.options.scene,
        request.position.x,
        request.position.y,
        request.direction.x,
        request.direction.y,
        request.projectileId,
        'enemy',
        request.damage,
        request.knockbackStrength,
        request.speed,
      );
      return;
    }
    if (!request.assetId) throw new Error(`Managed enemy '${request.sourceNodeId}' projectile has no asset identity.`);
    const asset = ASSET_MANIFEST.assets[request.assetId as AssetId];
    if (!asset) throw new Error(`Managed enemy '${request.sourceNodeId}' projectile references unknown asset '${request.assetId}'.`);
    projectilePool.fire(
      this.options.scene,
      request.position.x,
      request.position.y,
      request.direction.x,
      request.direction.y,
      request.speed,
      asset.runtime.textureKey,
      'enemy',
      request.damage,
      request.knockbackStrength,
    );
  }

  private createBossBar(campId: string, bossId: string): LegacyBossBarHandle {
    const boss = this.bosses.get(campId);
    if (!boss) return { destroy() {} };
    const bar = new ManagedBossBar(this.options.scene, boss.script, getBossDefinition(bossId).displayName, (entry) => this.bossBars.delete(entry));
    this.bossBars.add(bar);
    return bar;
  }

  private registerLegacyColliders(mount: MountedScene, collideDynamicWithPlayer = true): void {
    const colliders: Phaser.Physics.Arcade.Collider[] = [];
    for (const body of descendants(mount.root, PhysicsBody2DNode)) {
      if (body.isStaticBody) colliders.push(this.options.scene.physics.add.collider(this.playerPhysicsSprite, body.physicsObject));
      else {
        colliders.push(this.options.scene.physics.add.collider(body.physicsObject, this.options.collisionTiles));
        if (collideDynamicWithPlayer) colliders.push(this.options.scene.physics.add.collider(this.playerPhysicsSprite, body.physicsObject));
      }
    }
    mount.mount.lifetimeDisposables.add(() => { for (const collider of colliders) collider.destroy(); });
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
